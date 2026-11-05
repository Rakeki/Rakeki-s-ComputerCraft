-- The factory's smelter (factory.lua loads it). Keeps every furnace, blast
-- furnace and smoker this computer owns busy: ores and raw metals in
-- storage go into the furnaces and blast furnaces, raw food into the smokers
-- and furnaces, fuel comes from the storage computer's fuel chest, and
-- what's smelted goes back into storage through its input chest. On order
-- it also burns spare logs into charcoal, which ends up in the fuel chest,
-- smelts cobblestone into stone and sand into glass. Ores an enricher (here
-- or on another factory computer) takes are left to it, and their dust
-- smelted instead.
--
-- Mekanism Energized Smelters and Smelting Factories work too, fed through a
-- hopper or barrel like the enricher's chambers (lib/mekfeed.lua), and get
-- first pick of what there is to smelt. They need no fuel, eject what they
-- make into the chest under them (an output chest emptied into storage, or a
-- storage input chest). With an output chest they work on orders too, ahead
-- of the furnaces: what's emptied from it is counted.
--
-- Create fans (bulk blasting through lava, bulk smoking through fire)
-- aren't peripherals: a fan line is a feeder chest a funnel empties onto a
-- belt past the fan, and the chest at the belt's end (lib/mekfeed.lua
-- lines). They're loaded with the Mekanism smelters, blasting fans with
-- ores and dust, smoking fans with food, and shown red when their feeder
-- stops going down. They take no part in orders.
local screen = require("lib.screen") -- flicker-free drawing
local files = require("lib.files") -- crash-safe save files
local mekfeed = require("lib.mekfeed") -- Mekanism machines fed through a hopper or barrel

local M = {}

local LOAD_MIN = 8 -- fewest items put in an empty furnace at once (what one coal smelts)
local STUCK_AFTER = 120 -- seconds a fuelled furnace may sit on an item without smelting it before it's taken back out
-- Items one of each fuel smelts, for counting what's in a fuel slot.
local FUEL_SMELTS = { ["minecraft:charcoal"] = 8, ["minecraft:coal"] = 8, ["minecraft:coal_block"] = 80 }
-- Fuel loaded from the work chest, in the order the storage computer gives it.
local FUEL_ORDER = { "minecraft:charcoal", "minecraft:coal", "minecraft:coal_block" }

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

-- A furnace's name on screen: "Furnace 3", "Blast furnace 0" ("Blast 0" short, for a tile).
local function furnaceTitle(fu, short)
  local t = nice(fu.name)
  if short then t = t:gsub("^blast furnace", "blast") end
  return (t:gsub("^%l", string.upper))
end

-- Logs and wood (bark on all sides) of every tree burn into charcoal;
-- nether stems don't, and aren't called logs.
local function isWood(name) return (name:find("_log$") or name:find("_wood$")) ~= nil end

local function kindOf(f) return f.blast and "blast:" or f.smoker and "smoker:" or "furnace:" end

-- Every furnace, blast furnace and smoker on the wired network (not ones
-- touching this computer: the storage computer can't reach those).
local function findFurnaces()
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if not sides[name] and t and (t:find("furnace", 1, true) or t:find("smoker", 1, true)) then
      list[#list + 1] = { name = name, blast = t:find("blast", 1, true) ~= nil, smoker = t:find("smoker", 1, true) ~= nil }
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- f: the factory (factory.lua): ask, work, config, mine, leave, wake, taken, log.
function M.new(f)
  local config = f.config("smelter")
  -- Used if config.lua has none; see config.lua for what they mean.
  local SMELT = config.smelt or { ":raw_", "_ore$", ":ancient_debris$", ":crushed_raw_" }
  local SKIP = config.skip or { "_block$", "coal_ore$", "diamond_ore$", "emerald_ore$", "lapis_ore$", "redstone_ore$",
    "quartz_ore$" }
  local COOK = config.cook or { "^minecraft:beef$", "^minecraft:porkchop$", "^minecraft:chicken$", "^minecraft:mutton$",
    "^minecraft:rabbit$", "^minecraft:cod$", "^minecraft:salmon$", "^minecraft:potato$", "^minecraft:kelp$" }
  local KEEP = config.keep or { ["minecraft:potato"] = 64 }
  -- Mekanism dust (from the enrichment chambers), smelted like ores. Kept out
  -- of "smelt" so a config.lua from before the enricher still gets it.
  local DUSTS = config.dusts or { "^mekanism:dust_iron$", "^mekanism:dust_gold$", "^mekanism:dust_copper$",
    "^mekanism:dust_osmium$", "^mekanism:dust_tin$", "^mekanism:dust_lead$", "^mekanism:dust_uranium$" }

  local self = { id = "smelt", title = "Smelter", short = "Smelt", rank = 2, every = 10,
    what = "Ores, dust, food -> ingots, cooked food" }
  local furnaces = {} -- what the screen shows: { name, blast, input, fuel, output } per furnace
  local meks = {} -- the Mekanism smelters and fans (lib/mekfeed.lua), for the screen too
  local stock -- the storage computer's last answer to 'stock'
  local jobs = {} -- kind -> the order: { at, item, count, loaded, made }
  local stuckSince = {} -- furnace name -> { name, count, since }: an input that hasn't gone down since
  local news -- { text, colour, untilTime }: a finished order or a put-back item, shown for a minute
  local noSmelt = {} -- "furnace:<item>" / "blast:<item>" found not to smelt there (until restart)
  local collected, outStuck, outWhy, made -- this round's emptying of the output chests (read)
  self.message = { "Looking for the storage computer...", "lightGray" }
  self.status = { "starting", "" }

  local function say(text, colour)
    self.message = { text, colour or "lightGray" }
    f.changed()
  end

  local function tell(text, colour)
    news = { text, colour, os.clock() + 60 }
    say(text, colour)
  end

  local function status(state, detail) self.status = { state, detail } end

  -- "food" (smokers and furnaces), "ore" (blast furnaces and furnaces) or
  -- nil for an item that isn't smelted by itself.
  local function smeltKind(name)
    for _, p in ipairs(SKIP) do
      if name:find(p) then return nil end
    end
    for _, p in ipairs(COOK) do
      if name:find(p) then return "food" end
    end
    for _, p in ipairs(SMELT) do
      if name:find(p) then return "ore" end
    end
    for _, p in ipairs(DUSTS) do
      if name:find(p) then return "ore" end
    end
    return nil
  end

  self.set = mekfeed.new({ name = "smelter", cmd = "factory", event = f.event, single = "energizedSmelter",
    factory = "SmeltingFactory", what = "energized smelter", title = "Smelter", names = config.names,
    setSides = config.setSides ~= false, ask = f.ask, tell = tell, far = function() return f.work.remote end,
    taken = f.taken, lines = { "blast", "smoke" }, pageTitle = "Smelters and fans" })

  -- The furnaces this computer owns (another factory computer on the cable has the rest).
  local function myFurnaces()
    local out = {}
    for _, fu in ipairs(findFurnaces()) do
      if f.mine(fu.name) then out[#out + 1] = fu end
    end
    return out
  end

  ---------------------------------------------------------------- orders

  -- The log a charcoal order burns: the item it names, or the matching log
  -- there's most of (wood may be part of a name, like "spruce", or nil for any).
  local function pickWood(want, counts)
    if want and (counts[want] or 0) > 0 and not noSmelt["furnace:" .. want] then return want end
    local best, most = nil, 0
    for name, n in pairs(counts) do
      if isWood(name) and n > most and not noSmelt["furnace:" .. name] and (not want or name:find(want, 1, true)) then
        best, most = name, n
      end
    end
    return best
  end

  -- Both sands make glass. The sand a glass order smelts: the one it names,
  -- or whichever there's most of, round by round, so it carries on with the
  -- other when one runs out.
  local SANDS = { "minecraft:sand", "minecraft:red_sand" }
  local function isSand(name) return name == SANDS[1] or name == SANDS[2] end
  local function pickSand(want, counts)
    local best, most = nil, 0
    for _, name in ipairs(SANDS) do
      local n = counts[name] or 0
      if n > most and not noSmelt["furnace:" .. name] and (not want or want == name) then best, most = name, n end
    end
    return best
  end

  -- What can be ordered, worked on in this order by plain furnaces (blast
  -- furnaces and smokers can't burn logs, cobblestone or sand). Each order is
  -- kept in its own file across reboots (the smelter's names, so orders
  -- carry on). key: the screen's key for it; input/verb: how the cancel
  -- message says it; mixed: may change input from round to round (otherwise
  -- it sticks to the first one it picks).
  local ORDERS = {
    { kind = "charcoal", key = "c", file = "/.smelter_job", made = "minecraft:charcoal", from = "logs",
      input = "Logs", verb = "burn", isInput = isWood, pick = pickWood },
    { kind = "stone", key = "s", file = "/.smelter_stone", made = "minecraft:stone", from = "cobblestone",
      input = "Cobblestone", verb = "smelts",
      isInput = function(name) return name == "minecraft:cobblestone" end,
      pick = function(_, counts)
        local name = "minecraft:cobblestone"
        if (counts[name] or 0) > 0 and not noSmelt["furnace:" .. name] then return name end
      end },
    { kind = "glass", key = "g", file = "/.smelter_glass", made = "minecraft:glass", from = "sand",
      input = "Sand", verb = "smelts", mixed = true, isInput = isSand, pick = pickSand },
  }
  local orderKind = {}
  for _, o in ipairs(ORDERS) do orderKind[o.kind] = o end

  local function readOrder(o)
    local t = files.read(o.file)
    if type(t) ~= "table" then return nil end
    t.item = t.item or t.wood -- charcoal orders saved before stone orders existed
    return t
  end

  local function readOrders()
    local t = {}
    for _, o in ipairs(ORDERS) do t[o.kind] = readOrder(o) end
    return t
  end

  local function newOrder(kind, item, count)
    files.write(orderKind[kind].file, { at = os.epoch("utc"), item = item, count = count, loaded = 0, made = 0 })
    f.wake()
  end

  local function cancelOrder(kind) files.delete(orderKind[kind].file) end

  -- A round only saves or ends the order it started with: one placed
  -- meanwhile (from the keyboard, or 'factory charcoal' in another tab) wins.
  local function sameOrder(o, t)
    local cur = readOrder(o)
    return cur ~= nil and cur.at == t.at
  end

  jobs = readOrders()

  ---------------------------------------------------------------- what it is

  -- Furnaces it could have, for the factory's claims (it owns them unless
  -- another factory computer had them first).
  function self.found()
    local out = {}
    for _, fu in ipairs(findFurnaces()) do
      out[#out + 1] = { name = fu.name, kind = fu.blast and "Blast furnace" or fu.smoker and "Smoker" or "Furnace" }
    end
    return out
  end

  function self.uses() return self.set:uses() end

  function self.active() return #myFurnaces() > 0 or #self.set:entries() > 0 end

  -- What it smelts: nothing comes after it, so nobody needs to leave these.
  function self.takes() return {} end

  -- How many of each kind, for the chain page.
  function self.summary()
    local n, blast, smoke, mek, fans = 0, 0, 0, 0, 0
    for _, fu in ipairs(myFurnaces()) do
      if fu.blast then blast = blast + 1 elseif fu.smoker then smoke = smoke + 1 else n = n + 1 end
    end
    for _, e in ipairs(self.set:entries()) do
      if e.line then fans = fans + 1 else mek = mek + 1 end
    end
    local parts = {}
    local function add(c, what) if c > 0 then parts[#parts + 1] = ("%d %s"):format(c, what) end end
    add(n, "furnaces")
    add(blast, "blast")
    add(smoke, "smokers")
    add(mek, "Mek smelters")
    add(fans, "fans")
    return table.concat(parts, ", ")
  end

  ---------------------------------------------------------------- a round

  -- A Mekanism smelter with an output chest the smelter empties can work on
  -- orders, since what comes out of that chest is counted. Not one that
  -- ejects straight into storage, nor a Create fan (blasting is ores only).
  local function forOrders(m) return not m.line and m.entry.output ~= nil end

  -- Count what came out of the output chests towards the orders.
  local function countMade(byName)
    for _, o in ipairs(ORDERS) do
      local t = jobs[o.kind]
      if t and byName and byName[o.made] then t.made = t.made + byName[o.made] end
    end
  end

  -- An order's input or what it makes is still in a Mekanism smelter: its
  -- feeder, its slots, or its output chest (stuck there, not counted yet).
  local function mekBusyWith(m, o)
    if not forOrders(m) then return false end
    for _, s in pairs(m.feedList) do
      if o.isInput(s.name) then return true end
    end
    for i = 1, m.slots do
      local a, b = m.inputs[i], m.outputs[i]
      if (a and o.isInput(a.name)) or (b and b.name == o.made) then return true end
    end
    for _, s in pairs(m.outList) do
      if s.name == o.made then return true end
    end
    return false
  end

  -- Before the storage computer is asked: the furnaces and Mekanism
  -- smelters are read, so the screen shows them even while it isn't
  -- answering, and far away the output chests empty into the ender chest
  -- here, which needs no answer from it.
  function self.read(remote, remoteInput)
    local list = myFurnaces()
    meks = self.set:read()
    -- each call takes a tick, so read every furnace at once
    local reads = {}
    for _, fu in ipairs(list) do
      reads[#reads + 1] = function()
        local ok, slots = pcall(peripheral.call, fu.name, "list")
        slots = ok and slots or {}
        fu.input, fu.fuel, fu.output = slots[1], slots[2], slots[3]
      end
    end
    if #reads > 0 then parallel.waitForAll(table.unpack(reads)) end
    furnaces = list
    jobs = readOrders()
    collected, outStuck, outWhy, made = false, false, nil, nil
    if remote then
      local _
      _, outStuck, outWhy, made = self.set:collect(meks, remoteInput)
      countMade(made)
      collected = true
    end
  end

  -- r: the factory's round: stock (the storage computer's answer to
  -- 'stock'), useWork, input, unsure (feeders the storage computer hasn't
  -- taken yet), feedProblem.
  function self.round(r)
    if #furnaces == 0 and #meks == 0 then
      say("No furnaces yet: join them to the cable with wired modems, or add a Mekanism smelter or Create fan.", "orange")
      status("waiting", "no furnaces")
      return
    end
    stock = r.stock
    local work = f.work
    local useWork = r.useWork
    local counts, input = stock.counts, r.input
    local orders = jobs

    -- what's smelted goes back through the input chest (charcoal is put in
    -- the fuel chest from there)
    local blocked, problem = false, nil
    for _, fu in ipairs(furnaces) do
      if fu.output then
        local ok, moved = pcall(peripheral.call, fu.name, "pushItems", input, 3)
        if not ok then problem, moved = tostring(moved), 0 end
        for _, o in ipairs(ORDERS) do
          local t = orders[o.kind]
          if t and fu.output.name == o.made then t.made = t.made + moved end
        end
        fu.output.count = fu.output.count - moved
        if fu.output.count > 0 then blocked = true else fu.output = nil end
      end
    end
    -- and the Mekanism smelters' and fans' output chests, before the orders
    -- are checked below (what they made counts too)
    if not collected then
      local _
      _, outStuck, outWhy, made = self.set:collect(meks, input)
      countMade(made)
    end
    if outWhy then
      problem = problem or outWhy
    elseif outStuck then
      blocked = true
    end

    -- a fuelled furnace with room for its output whose input hasn't gone down
    -- from what it was left with last round isn't lit: that item doesn't
    -- smelt in it
    local now = os.clock()
    for _, fu in ipairs(furnaces) do
      local s = stuckSince[fu.name]
      if fu.input and fu.fuel and not fu.output then
        if s and s.count and s.name == fu.input.name and fu.input.count >= s.count then
          if now - s.since > STUCK_AFTER then
            pcall(peripheral.call, fu.name, "pushItems", input, 1)
            noSmelt[kindOf(fu) .. fu.input.name] = true
            tell(("%s doesn't smelt in %s: put it back."):format(nice(fu.input.name), nice(fu.name)), "orange")
            fu.input, stuckSince[fu.name] = nil, nil
          end
        else
          stuckSince[fu.name] = { name = fu.input.name, since = now } -- count: what it's left with, below
        end
      else
        stuckSince[fu.name] = nil
      end
    end

    -- each order: done once it's made, or once nothing's burning for it and
    -- there's nothing more to burn (every input was read before its output
    -- was emptied, so everything made from finished inputs has been counted)
    local orderItems = {} -- the item each running order burns, in ORDERS order
    local byItem = {} -- item -> the order it's loaded for
    for _, o in ipairs(ORDERS) do
      local t = orders[o.kind]
      if t then
        local item = o.pick(t.item, counts)
        if not t.item and not o.mixed then t.item = item end -- 'any logs': stick to one kind
        local burning = false
        for _, fu in ipairs(furnaces) do
          if fu.input and o.isInput(fu.input.name) then burning = true end
        end
        for _, m in ipairs(meks) do
          if mekBusyWith(m, o) then burning = true end
        end
        if t.made >= t.count or (not burning and (t.loaded >= t.count or not item)) then
          if t.made >= t.count then
            local where = o.kind == "charcoal" and stock.fuelChest and "the fuel chest" or "storage"
            tell(("Made %d %s. It's in %s."):format(t.made, o.kind, where), "lime")
          else
            tell(("Ran out of %s: made %d of %d %s."):format(t.item and nice(t.item) or o.from,
              t.made, t.count, o.kind), "orange")
          end
          f.log(("made %d %s"):format(t.made, o.kind))
          if sameOrder(o, t) then cancelOrder(o.kind) end
          orders[o.kind] = nil
        elseif item then
          orderItems[#orderItems + 1] = item
          byItem[item] = t
        end
      end
    end

    -- what to load: every ore and raw food in storage (less what config.lua
    -- keeps, like potatoes for planting, and what an enricher takes), and
    -- what the orders still need
    local want, kinds = {}, {}
    for name, n in pairs(counts) do
      local kind = n > 0 and not f.leave(self.rank, name) and smeltKind(name)
      if kind then
        kinds[name] = kind
        if n > (KEEP[name] or 0) then want[name] = n - (KEEP[name] or 0) end
      end
    end
    for item, t in pairs(byItem) do want[item] = math.min(counts[item], t.count - t.loaded) end
    -- blast furnaces only smelt ores, smokers only cook food, furnaces do both
    local function canTake(fu, name)
      if (want[name] or 0) <= 0 or noSmelt[kindOf(fu) .. name] then return false end
      if fu.blast then return kinds[name] == "ore" end
      if fu.smoker then return kinds[name] == "food" end
      return true
    end
    local loaded, into = 0, 0
    -- with a work chest, each load is only noted down and taken as done, so
    -- the furnaces are shared out as usual; it's all fetched at once after
    -- the fuel, and what didn't come is taken back off then (far away
    -- nothing can come any other way, so a work chest not in use loads nothing)
    local plan = useWork and {} or nil
    local function load(fu, name, n)
      local got
      if plan then
        plan[#plan + 1] = { f = fu, name = name, n = n }
        got = n
      else
        local reply = f.ask({ type = "send", to = fu.name, slot = 1, items = { [name] = n } })
        got = reply and reply.sent and reply.sent[name] or 0
        if reply and reply.error then problem = reply.error end
      end
      if got > 0 then
        want[name] = want[name] - got
        if fu.input then fu.input.count = fu.input.count + got else fu.input = { name = name, count = got } end
        if byItem[name] then byItem[name].loaded = byItem[name].loaded + got end
        loaded, into = loaded + got, into + 1
      end
    end
    local haveFuel = (stock.fuel or 0) > 0

    -- Mekanism smelters and Create fans first (faster, no fuel), through their
    -- feeders; a Mekanism smelter with an output chest takes the orders
    -- first (forOrders). A blasting fan only takes ores, a smoking fan only food.
    local unsure = r.unsure
    problem = problem or r.feedProblem
    self.set:unstick(meks, input, function(m, item)
      noSmelt["mek:" .. item.name] = true
      tell(("%s didn't go into %s: put it back. Is its hopper on top, or a pipe pulling from its barrel?")
        :format(nice(item.name), m.title), "orange")
    end)
    local mekPlan = {}
    local function fits(m, name)
      if m.line == "blast" then return kinds[name] == "ore" end
      if m.line == "smoke" then return kinds[name] == "food" end
      return not noSmelt["mek:" .. name]
    end
    for _, m in ipairs(meks) do
      if mekfeed.ready(m) and not unsure[m.entry.feeder] then
        local pick = mekfeed.current(m)
        if not pick and forOrders(m) then
          for _, item in ipairs(orderItems) do
            if not pick and (want[item] or 0) > 0 and fits(m, item) then pick = item end
          end
        end
        if not pick then
          local most = 0
          for name, n in pairs(want) do
            if not byItem[name] and n > most and fits(m, name) then pick, most = name, n end
          end
        end
        -- an order's item only into one whose output is counted
        if pick and byItem[pick] and not forOrders(m) then pick = nil end
        local n = pick and math.min(mekfeed.space(m, pick), want[pick] or 0, 64) or 0
        if n > 0 and plan then
          mekPlan[#mekPlan + 1] = { m = m, name = pick, n = n }
          want[pick] = want[pick] - n
          if byItem[pick] then byItem[pick].loaded = byItem[pick].loaded + n end
        elseif n > 0 then
          local reply = f.ask({ type = "send", to = m.entry.feeder, items = { [pick] = n } })
          local got = reply and reply.sent and reply.sent[pick] or 0
          if reply and reply.error then problem = reply.error end
          mekfeed.added(m, pick, got)
          want[pick] = want[pick] - got
          if byItem[pick] then byItem[pick].loaded = byItem[pick].loaded + got end
          if got > 0 then loaded, into = loaded + got, into + 1 end
        end
      end
    end

    -- top up what's already smelting
    for _, fu in ipairs(furnaces) do
      if fu.input and fu.input.count < 64 and canTake(fu, fu.input.name) then
        load(fu, fu.input.name, math.min(64 - fu.input.count, want[fu.input.name]))
      end
    end
    -- then fill empty ones: blast furnaces and smokers first (twice as fast,
    -- but only ores or only food), and plain furnaces put the orders ahead of
    -- the rest, charcoal before stone before glass
    local empty = {}
    for _, fu in ipairs(furnaces) do
      if not fu.input and (fu.fuel or haveFuel) then empty[#empty + 1] = fu end
    end
    local function fast(fu) return fu.blast or fu.smoker end
    table.sort(empty, function(a, b) return fast(a) and not fast(b) end)
    for _, fu in ipairs(empty) do
      local pick
      for _, item in ipairs(orderItems) do
        if not pick and canTake(fu, item) then pick = item end
      end
      if not pick then
        local most = 0
        for name, n in pairs(want) do
          if not byItem[name] and n > most and canTake(fu, name) then pick, most = name, n end
        end
      end
      if pick then
        -- share it out between the furnaces still free that can take it
        local free = 0
        for _, g in ipairs(empty) do
          if not g.input and canTake(g, pick) then free = free + 1 end
        end
        load(fu, pick, math.min(64, want[pick], math.max(LOAD_MIN, math.ceil(want[pick] / free))))
      end
    end

    -- fuel: enough for everything waiting in each furnace
    local unfuelled = false
    local function fuelShort(fu)
      local have = fu.fuel and fu.fuel.count * (FUEL_SMELTS[fu.fuel.name] or 8) or 0
      if fu.input and have < fu.input.count and not (fu.fuel and fu.fuel.count >= 64) then return fu.input.count - have end
      return 0
    end
    local fuelWanted = 0
    for _, fu in ipairs(furnaces) do
      local short = fuelShort(fu)
      if short > 0 and plan then
        fuelWanted = fuelWanted + short
      elseif short > 0 then
        local reply = f.ask({ type = "send", to = fu.name, slot = 2, fuel = short, item = fu.fuel and fu.fuel.name })
        if reply then stock.fuel = reply.fuel or stock.fuel end
        for name, n in pairs(reply and reply.sent or {}) do
          fu.fuel = { name = name, count = (fu.fuel and fu.fuel.count or 0) + n }
        end
        if not fu.fuel then unfuelled = reply and reply.error or true end
      end
    end

    -- the work chest: one fill for every load and all the fuel, then each
    -- furnace is loaded from it, and what's left goes back to storage
    if plan then
      local items = {}
      for _, p in ipairs(plan) do items[p.name] = (items[p.name] or 0) + p.n end
      for _, p in ipairs(mekPlan) do items[p.name] = (items[p.name] or 0) + p.n end
      local reply, why = work:fill(items, fuelWanted)
      if reply then
        stock.fuel = reply.fuel or stock.fuel
        if reply.error and not reply.nochest then problem = reply.error end
      elseif next(items) or fuelWanted > 0 then
        problem = why
      end
      for _, p in ipairs(plan) do
        local moved = work:move(p.name, p.f.name, 1, p.n)
        local short = p.n - moved
        if short > 0 then
          local fu = p.f
          fu.input.count = fu.input.count - short
          if fu.input.count <= 0 then fu.input = nil end
          if moved == 0 then into = into - 1 end
          want[p.name] = want[p.name] + short
          if byItem[p.name] then byItem[p.name].loaded = byItem[p.name].loaded - short end
          loaded = loaded - short
        end
      end
      for _, fu in ipairs(furnaces) do
        local short = fuelShort(fu)
        if short > 0 then
          -- a fuel slot holds one kind: more of what's in it, else the first there is
          for _, fuel in ipairs(FUEL_ORDER) do
            if short > 0 and (not fu.fuel or fu.fuel.name == fuel) then
              local n = math.min(64 - (fu.fuel and fu.fuel.count or 0), math.ceil(short / FUEL_SMELTS[fuel]))
              local moved = work:move(fuel, fu.name, 2, n)
              if moved > 0 then
                fu.fuel = { name = fuel, count = (fu.fuel and fu.fuel.count or 0) + moved }
                short = 0
              end
            end
          end
          if not fu.fuel then unfuelled = true end
        end
      end
      for _, p in ipairs(mekPlan) do
        local got = work:move(p.name, p.m.entry.feeder, nil, p.n)
        mekfeed.added(p.m, p.name, got)
        if byItem[p.name] then byItem[p.name].loaded = byItem[p.name].loaded - (p.n - got) end
        if got > 0 then loaded, into = loaded + got, into + 1 end
      end
      work:empty(input)
    end

    for _, o in ipairs(ORDERS) do
      local t = orders[o.kind]
      if t and sameOrder(o, t) then files.write(o.file, t) end
    end
    jobs = orders

    local busy = 0
    for _, fu in ipairs(furnaces) do
      if fu.input then
        busy = busy + 1
        local s = stuckSince[fu.name]
        if s and s.name == fu.input.name then s.count = fu.input.count end
      end
    end
    for _, m in ipairs(meks) do
      if (m.usage or 0) > 0 or (m.line and m.feedTotal > 0 and not m.stalled) then busy = busy + 1 end
    end
    -- far away without a far-away work chest, the storage computer can't see
    -- the furnaces: say what to do
    if problem and not work.chest and (problem:find("network") or problem:find("can't see") or problem:find("exist")) then
      problem = problem .. ". Far from the storage system? Setup, Work chest, Far away"
    end
    -- orders only burn in plain furnaces and Mekanism smelters with an output
    -- chest: blast furnaces, smokers and fans never take them
    local plain = false
    for _, fu in ipairs(furnaces) do
      if not fu.blast and not fu.smoker then plain = true end
    end
    for _, m in ipairs(meks) do
      if forOrders(m) then plain = true end
    end
    if problem then
      say("Couldn't move items: " .. problem, "red")
    elseif news and os.clock() < news[3] then
      say(news[1], news[2])
    elseif blocked then
      say(work.remote and "The ender chest is full: smelted items are waiting in the furnaces."
        or "The storage input chest is full: smelted items are waiting in the furnaces.", "orange")
    elseif #orderItems > 0 and not plain then
      say("Orders need a plain furnace or a Mekanism smelter with an output chest: add one.", "orange")
    elseif work.problem then
      say(("Not using the work chest: %s."):format(work.problem), "orange")
    elseif unfuelled then
      -- the storage computer's reason, when it gave one
      say(type(unfuelled) == "string" and ("No fuel came: %s."):format(unfuelled)
        or "Out of fuel: put coal or charcoal in the fuel chest.", "orange")
    elseif loaded > 0 then
      say(("Loaded %d items into %d furnaces."):format(loaded, into))
    elseif busy == 0 then
      say("Nothing to smelt.")
    else
      say(("Smelting in %d furnaces."):format(busy))
    end
    status(problem and "alert" or busy > 0 and "running" or "idle",
      ("%d of %d furnaces smelting"):format(busy, #furnaces + #meks))
  end

  ---------------------------------------------------------------- screen

  local function rows()
    local list = {}
    for _, fu in ipairs(furnaces) do
      list[#list + 1] = { furnaceTitle(fu), fu.blast and "orange" or fu.smoker and "pink" or "white",
        fu.input and ("%d %s"):format(fu.input.count, nice(fu.input.name)) or "idle", fu.input and "white" or "gray",
        fu.fuel and ("%d %s"):format(fu.fuel.count, nice(fu.fuel.name)) or "-" }
    end
    for _, m in ipairs(meks) do
      local queued, item = mekfeed.inputOf(m) + m.feedTotal, mekfeed.current(m)
      local doing, colour = item and ("%d %s"):format(queued, nice(item)) or "idle", item and "white" or "gray"
      local lineColour, lineText = mekfeed.status(m)
      if m.line then
        -- a Create fan: only its feeder can be read
        if lineColour == "red" then
          doing, colour = lineText == "not moving" and "not moving: is the fan on?" or lineText, "red"
        end
      elseif not m.present then
        doing, colour = "not on network", "red"
      elseif not m.feedOk then
        doing, colour = "no feeder", "red"
      elseif not m.outOk then
        doing, colour = "no output chest", "red"
      elseif (m.energy or 0) <= 0 then
        doing, colour = "no power", "red"
      elseif mekfeed.full(m) then
        doing, colour = "output full: chest under it?", "red"
      end
      list[#list + 1] = { m.title, m.line and "yellow" or "lightBlue", doing, colour,
        m.line and "Create" or m.present and ("%d%% power"):format(math.floor((m.energy or 0) * 100 + 0.5)) or "-" }
    end
    return list
  end

  local function orderLines()
    local lines = {}
    for _, o in ipairs(ORDERS) do
      local t = jobs[o.kind]
      if t then
        lines[#lines + 1] = ("%s%s: %d of %d made from %s"):format(o.kind:sub(1, 1):upper(), o.kind:sub(2), t.made,
          t.count, t.item and nice(t.item) or o.from)
      end
    end
    return lines
  end

  -- What the terminal page shows, to skip frames that wouldn't change.
  function self.key()
    local key = { stock and stock.fuel or "-", self.message[1], self.message[2], table.concat(orderLines(), "/") }
    for _, row in ipairs(rows()) do key[#key + 1] = table.concat(row, "/") end
    return table.concat(key, "|")
  end

  -- The terminal page, under the factory's tab bar (row 1).
  function self.draw(win, w, h)
    local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end
    local fit = screen.fit
    local lines, list = orderLines(), rows()
    local stat = stock and ("Fuel for %d items"):format(stock.fuel or 0) or "No storage yet"
    put(2, 2, fit(stat, w - 2), "lightGray")
    local fuelX = w - 12
    -- the name column as wide as the longest name (up to 17), the rest for what it's smelting
    local nameW = 7
    for _, row in ipairs(list) do nameW = math.max(nameW, #row[1]) end
    nameW = math.min(nameW, 17)
    local doX = 2 + nameW + 2
    put(2, 3, "Furnace", "yellow")
    put(doX, 3, "Smelting", "yellow")
    put(fuelX, 3, "Fuel", "yellow")
    -- the message takes a second line rather than being cut off
    local msg = screen.wrap(self.message[1], w, 2)
    local shown = h - 5 - #msg - math.max(#lines, 1)
    for i = 1, math.min(shown, #list) do
      local row, y = list[i], 3 + i
      put(2, y, fit(screen.squeeze(row[1], nameW), nameW), row[2])
      put(doX, y, fit(row[3], fuelX - doX - 1), row[4])
      put(fuelX, y, fit(row[5], 12), "lightGray")
    end
    if #list > shown then put(2, 4 + shown, ("...and %d more"):format(#list - shown), "gray") end
    if #list == 0 then put(2, 4, "No furnaces yet.", "gray") end
    local base = h - 1 - #msg -- the last order line
    if #lines == 0 then put(1, base, fit(" No orders.", w), "gray") end
    for i, line in ipairs(lines) do
      put(1, base - #lines + i, fit(" " .. line, w), "lightBlue")
    end
    for i, line in ipairs(msg) do put(1, base + i, fit(line, w), self.message[2]) end
    put(1, h, fit("C:charcoal S:stone G:glass X:cancel Tab F1:setup", w), "gray")
  end

  -- Status board colour and words for a furnace: red when items wait with
  -- no fuel or its output can't go anywhere, orange a full stack in, yellow
  -- smelting, lime idle.
  local function furnaceStatus(fu)
    if fu.output then return "red", "output full" end
    if fu.input and not fu.fuel then return "red", "no fuel" end
    if fu.input then return fu.input.count >= 64 and "orange" or "yellow", nice(fu.input.name) end
    return "lime", "idle"
  end

  -- The monitor's tiles: { title, text, colour }.
  function self.tiles()
    local tiles = {}
    for _, fu in ipairs(furnaces) do
      local colour, text = furnaceStatus(fu)
      tiles[#tiles + 1] = { furnaceTitle(fu, true), text, colour }
    end
    for _, m in ipairs(meks) do
      local item = mekfeed.current(m) or (m.inputs[1] and m.inputs[1].name)
      local colour, text = mekfeed.status(m, item and nice(item))
      tiles[#tiles + 1] = { m.title, text, colour }
    end
    return tiles
  end

  ---------------------------------------------------------------- orders from the keyboard

  local function promptScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
  end

  local function anyKey()
    print("Press any key.")
    os.pullEvent("key")
  end

  -- Ask which logs to burn and how much charcoal to make, from what the
  -- storage computer last said it holds.
  local function charcoalPrompt()
    local _, h = term.getSize()
    promptScreen()
    local woods = {}
    for name, n in pairs(stock and stock.counts or {}) do
      if isWood(name) and n > 0 then woods[#woods + 1] = { name = name, n = n } end
    end
    table.sort(woods, function(a, b) return a.n > b.n end)
    if #woods == 0 then
      print(stock and "There are no logs in storage to make charcoal from." or "The storage computer hasn't answered yet.")
      anyKey()
      return
    end
    if jobs.charcoal then print(("This replaces the order for %d charcoal."):format(jobs.charcoal.count)) end
    print("Make charcoal from which logs?")
    for i = 1, math.min(#woods, h - 5) do
      print(("%2d  %-26s %d"):format(i, nice(woods[i].name), woods[i].n))
    end
    write(("Which? [1 = %s] "):format(nice(woods[1].name)))
    local text = read()
    local pick = woods[text == "" and 1 or tonumber(text)]
    if not pick then return end
    write(("How much charcoal? (up to %d, Enter to cancel) "):format(pick.n))
    local n = tonumber(read())
    if not n or n < 1 then return end
    n = math.floor(n)
    newOrder("charcoal", pick.name, n)
    jobs = readOrders()
    say(("Making %d charcoal from %s."):format(n, nice(pick.name)), "lightBlue")
  end

  -- Ask how much stone (or glass) to make from the cobblestone (or sand) in
  -- storage. item: what it's made from, nil for any of the order's inputs.
  local function amountPrompt(kind, item)
    local o = orderKind[kind]
    promptScreen()
    local have = 0
    for name, n in pairs(stock and stock.counts or {}) do
      if o.isInput(name) and (not item or name == item) then have = have + n end
    end
    if have == 0 then
      print(stock and ("There's no %s in storage to make %s from."):format(o.from, kind) or "The storage computer hasn't answered yet.")
      anyKey()
      return
    end
    if jobs[kind] then print(("This replaces the order for %d %s."):format(jobs[kind].count, kind)) end
    write(("How much %s? (up to %d, Enter to cancel) "):format(kind, have))
    local n = tonumber(read())
    if not n or n < 1 then return end
    n = math.floor(n)
    newOrder(kind, item, n)
    jobs = readOrders()
    say(("Making %d %s from %s."):format(n, kind, o.from), "lightBlue")
  end

  local function cancelled(kind)
    local o = orderKind[kind]
    return ("%s%s order cancelled. %s already in furnaces still %s."):format(kind:sub(1, 1):upper(), kind:sub(2), o.input, o.verb)
  end

  -- Cancel the one order there is, or ask which when there are more.
  local function cancelPrompt()
    local running = {}
    for _, o in ipairs(ORDERS) do
      if jobs[o.kind] then running[#running + 1] = o end
    end
    if #running == 0 then return end
    local kind = running[1].kind
    if #running > 1 then
      promptScreen()
      print("Cancel which order?")
      for _, o in ipairs(running) do
        print(("  %s  %s (%d of %d made)"):format(o.key:upper(), o.kind, jobs[o.kind].made, jobs[o.kind].count))
      end
      print("  any other key: none")
      local _, c = os.pullEvent("char")
      kind = nil
      for _, o in ipairs(running) do
        if c:lower() == o.key then kind = o.kind end
      end
      if not kind then return end
    end
    cancelOrder(kind)
    jobs[kind] = nil
    say(cancelled(kind))
  end

  -- An event while its page is showing: true if it took over the terminal
  -- (a prompt), so the page is drawn again in full.
  function self.event(ev)
    -- char, not key: read() in the prompt would otherwise get the "c" too
    local a = ev[1] == "char" and ev[2]:lower()
    if a == "c" then charcoalPrompt()
    elseif a == "s" then amountPrompt("stone", "minecraft:cobblestone")
    elseif a == "g" then amountPrompt("glass", nil)
    elseif a == "x" then cancelPrompt()
    else return false end
    return true
  end

  ---------------------------------------------------------------- commands

  -- 'factory charcoal|stone|glass|cancel ...': true if args was one.
  function self.command(args)
    local verb = args[1]
    if verb == "charcoal" then
      local n = tonumber(args[2])
      if not n or n < 1 then
        print("Usage: factory charcoal <how many> [wood, e.g. spruce]")
        return true
      end
      local wood = #args >= 3 and table.concat(args, "_", 3):lower() or nil
      newOrder("charcoal", wood, math.floor(n))
      print(("Charcoal order saved: %d from %s."):format(math.floor(n), wood and nice(wood) or "whichever logs there are most of"))
    elseif verb == "stone" then
      local n = tonumber(args[2])
      if not n or n < 1 then
        print("Usage: factory stone <how many>")
        return true
      end
      newOrder("stone", "minecraft:cobblestone", math.floor(n))
      print(("Stone order saved: %d from cobblestone."):format(math.floor(n)))
    elseif verb == "glass" then
      local n = tonumber(args[2])
      if not n or n < 1 or (args[3] and args[3] ~= "red") then
        print("Usage: factory glass <how many> [red]")
        return true
      end
      local sand = args[3] == "red" and "minecraft:red_sand" or nil
      newOrder("glass", sand, math.floor(n))
      print(("Glass order saved: %d from %s."):format(math.floor(n), sand and "red sand" or "whichever sand there's most of"))
    elseif verb == "cancel" then
      if args[2] and not orderKind[args[2]] then
        print("Usage: factory cancel [charcoal|stone|glass]")
        return true
      end
      for _, o in ipairs(ORDERS) do
        if not args[2] or args[2] == o.kind then
          cancelOrder(o.kind)
          print(cancelled(o.kind))
        end
      end
      return true
    else
      return false
    end
    print("The factory starts on it within 10 seconds, or when it's next started.")
    return true
  end

  return self
end

return M
