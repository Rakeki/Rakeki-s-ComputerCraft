-- Smelter for the storage system. Keeps every furnace, blast furnace and
-- smoker on the storage computer's wired network busy: ores and raw metals
-- in storage go into the furnaces and blast furnaces, raw food into the
-- smokers and furnaces, fuel comes from the storage computer's fuel chest,
-- and what's smelted goes back into storage through its input chest. On
-- order it also burns spare logs into charcoal, which ends up in the fuel
-- chest, smelts cobblestone into stone and sand into glass. With an enricher
-- (computers/enricher-computer) running, it leaves the ores that go into the
-- enrichment chambers alone and smelts their dust instead.
--
--   smelter                        start (startup.lua runs this)
--   smelter charcoal <n> [wood]    make n charcoal from logs, e.g. 'smelter charcoal 256 spruce'
--                                  (no wood: the kind there's most of)
--   smelter stone <n>              make n stone from cobblestone
--   smelter glass <n> [red]        make n glass from sand (red: from red sand only;
--                                  otherwise whichever sand there's most of)
--   smelter cancel [charcoal|stone|glass]  stop an order (no name: all of them)
--   smelter add [machine feeder]   add a Mekanism Energized Smelter (or Smelting Factory) and what feeds
--                                  it: the hopper on top, or a barrel a pipe pulls from (asks for what's not given)
--   smelter remove <n>             forget Mekanism smelter n (no number: list them)
--   smelter chest [name|none]      use an empty chest on the network as the work chest
--                                  (no name: pick from a list; none: stop using one)
--   smelter chest remote           far from the storage system: one ender chest both ways (or a return one too)
--
-- With a work chest, the storage computer fills it once a round with
-- everything the furnaces need, and the smelter loads them from it
-- (lib/workchest.lua); without one, it asks for each furnace's load in turn.
-- Far away (an ender modem, and an EnderStorage-style ender chest pair),
-- the work chest is an ender chest, and smelted items go home through it
-- too (the storage computer takes back what it didn't send), or through a
-- second pair whose twin is a storage input chest.
--
-- Mekanism Energized Smelters and Smelting Factories work too, fed through a
-- hopper or barrel like the enricher's chambers (lib/mekfeed.lua), and get
-- first pick of what there is to smelt. They need no fuel, eject what they
-- make into a storage input chest under them, and take no part in orders
-- (what they make isn't counted).
--
-- Needs a wired modem on the storage computer's network, furnaces joined to
-- that network by wired modems too, and the storage computer
-- (computers/storage-computer) running. It asks the storage computer for
-- everything over rednet on the cable, so it needs no wireless modem. Which
-- items get smelted and cooked is set in config.lua.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local mekfeed = require("lib.mekfeed") -- Mekanism machines fed through a hopper or barrel
local workchest = require("lib.workchest") -- the chest the storage computer fills in one go
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local config = fs.exists("config.lua") and require("config") or {}

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local ENRICHER_PROTOCOL = "enricher" -- the enricher says which ores it takes on this
local ENRICHER_WAIT = 3 -- seconds to wait for the enricher to answer
local ENRICHER_RETRY = 60 -- seconds before looking for an enricher again after there was none
local EVERY = 10 -- seconds between rounds of emptying and filling the furnaces
local REPLY_WAIT = 5 -- seconds to wait for the storage computer to answer
local LOAD_MIN = 8 -- fewest items put in an empty furnace at once (what one coal smelts)
local STUCK_AFTER = 120 -- seconds a fuelled furnace may sit on an item without smelting it before it's taken back out
-- Items one of each fuel smelts, for counting what's in a fuel slot.
local FUEL_SMELTS = { ["minecraft:charcoal"] = 8, ["minecraft:coal"] = 8, ["minecraft:coal_block"] = 80 }
-- Fuel loaded from the work chest, in the order the storage computer gives it.
local FUEL_ORDER = { "minecraft:charcoal", "minecraft:coal", "minecraft:coal_block" }

-- Used if config.lua is missing; see config.lua for what they mean.
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

local furnaces = {} -- what the screen shows: { name, blast, input, fuel, output } per furnace
local meks = {} -- the Mekanism smelters (lib/mekfeed.lua), for the screen too
local stock -- the storage computer's last answer to 'stock'
local jobs = {} -- kind -> the order: { at, item, count, loaded, made }
local message = { "Looking for the storage computer...", "lightGray" }
local stuckSince = {} -- furnace name -> { name, count, since }: an input that hasn't gone down since
local news -- { text, colour, untilTime }: a finished order or a put-back item, shown for a minute
local noSmelt = {} -- "furnace:<item>" / "blast:<item>" found not to smelt there (until restart)

---------------------------------------------------------------- helpers

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("smelter_changed")
end

local function tell(text, colour)
  news = { text, colour, os.clock() + 60 }
  say(text, colour)
end

local function status(state, detail)
  if report then report.set(state, detail) end
end

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

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
-- kept in its own file across reboots; the charcoal one keeps its old name.
-- key: the screen's key for it; input/verb: how the cancel message says it;
-- mixed: may change input from round to round (otherwise it sticks to the
-- first one it picks).
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
  os.queueEvent("smelter_order")
end

local function cancelOrder(kind) files.delete(orderKind[kind].file) end

-- A round only saves or ends the order it started with: one placed
-- meanwhile (from the keyboard, or 'smelter charcoal' in another tab) wins.
local function sameOrder(o, t)
  local cur = readOrder(o)
  return cur ~= nil and cur.at == t.at
end

---------------------------------------------------------------- talking to storage

-- over the cable (or wireless, if that's all there is)
local storage = net.peer(STORAGE_PROTOCOL, { open = "any", wait = REPLY_WAIT })

-- Ask the storage computer something and wait for its answer: nil and why
-- if there's none.
local function ask(msg, wait)
  local reply, why = storage:ask(msg, wait)
  if reply then return reply end
  return nil, why == "no answer" and "the storage computer didn't answer" or "no storage computer answered"
end

local work = workchest.new("smelter", ask)
local smelters = mekfeed.new({ name = "smelter", single = "energizedSmelter", factory = "SmeltingFactory",
  what = "energized smelter", title = "Smelter", names = config.names, setSides = config.setSides ~= false,
  ask = ask, tell = tell })

local enricher = net.peer(ENRICHER_PROTOCOL, { open = "any", wait = ENRICHER_WAIT, retry = ENRICHER_RETRY })

-- The ores the enricher is putting into its chambers (patterns on item
-- ids), or none when there's no enricher or none of its chambers is ready.
local function enricherTakes()
  local reply = enricher:ask({ type = "takes" })
  return reply and type(reply.takes) == "table" and reply.takes or {}
end

local function leftFor(name, patterns)
  for _, p in ipairs(patterns) do
    if type(p) == "string" and name:find(p) then return true end
  end
  return false
end

---------------------------------------------------------------- a round

local function round()
  -- the furnaces first, so the screen shows them even while the storage
  -- computer isn't answering
  local list = findFurnaces()
  meks = smelters:read()
  if #list == 0 and #meks == 0 then
    furnaces = list
    say("No furnaces on the network: join them to it with wired modems, or 'smelter add' a Mekanism smelter.", "orange")
    status("waiting", "no furnaces")
    return
  end
  -- each call takes a tick, so read every furnace at once
  local reads = {}
  for _, f in ipairs(list) do
    reads[#reads + 1] = function()
      local ok, slots = pcall(peripheral.call, f.name, "list")
      slots = ok and slots or {}
      f.input, f.fuel, f.output = slots[1], slots[2], slots[3]
    end
  end
  parallel.waitForAll(table.unpack(reads))
  furnaces = list
  jobs = readOrders()

  local reply, err = ask({ type = "stock" })
  if not reply or type(reply.counts) ~= "table" then
    -- an older storage program neither listens on the cable nor knows "stock"
    say("Storage not answering: 'install update' on it.", "orange")
    status("waiting", ("storage computer: %s"):format(err or "too old to answer"))
    return
  end
  stock = reply
  -- far away, everything goes home through the ender chest (or the return one)
  local useWork = work:check(stock) or work.remote
  local counts, input = reply.counts, work:input(reply.input)
  local orders = jobs

  -- what's smelted goes back through the input chest (charcoal is put in
  -- the fuel chest from there)
  local blocked, problem = false, nil
  for _, f in ipairs(furnaces) do
    if f.output then
      local ok, moved = pcall(peripheral.call, f.name, "pushItems", input, 3)
      if not ok then problem, moved = tostring(moved), 0 end
      for _, o in ipairs(ORDERS) do
        local t = orders[o.kind]
        if t and f.output.name == o.made then t.made = t.made + moved end
      end
      f.output.count = f.output.count - moved
      if f.output.count > 0 then blocked = true else f.output = nil end
    end
  end

  -- a fuelled furnace with room for its output whose input hasn't gone down
  -- from what it was left with last round isn't lit: that item doesn't
  -- smelt in it
  local now = os.clock()
  for _, f in ipairs(furnaces) do
    local s = stuckSince[f.name]
    if f.input and f.fuel and not f.output then
      if s and s.count and s.name == f.input.name and f.input.count >= s.count then
        if now - s.since > STUCK_AFTER then
          pcall(peripheral.call, f.name, "pushItems", input, 1)
          noSmelt[kindOf(f) .. f.input.name] = true
          tell(("%s doesn't smelt in %s: put it back."):format(nice(f.input.name), nice(f.name)), "orange")
          f.input, stuckSince[f.name] = nil, nil
        end
      else
        stuckSince[f.name] = { name = f.input.name, since = now } -- count: what it's left with, below
      end
    else
      stuckSince[f.name] = nil
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
      for _, f in ipairs(furnaces) do
        if f.input and o.isInput(f.input.name) then burning = true end
      end
      if t.made >= t.count or (not burning and (t.loaded >= t.count or not item)) then
        if t.made >= t.count then
          local where = o.kind == "charcoal" and stock.fuelChest and "the fuel chest" or "storage"
          tell(("Made %d %s. It's in %s."):format(t.made, o.kind, where), "lime")
        else
          tell(("Ran out of %s: made %d of %d %s."):format(t.item and nice(t.item) or o.from,
            t.made, t.count, o.kind), "orange")
        end
        if report then report.log(("made %d %s"):format(t.made, o.kind)) end
        if sameOrder(o, t) then cancelOrder(o.kind) end
        orders[o.kind] = nil
      elseif item then
        orderItems[#orderItems + 1] = item
        byItem[item] = t
      end
    end
  end

  -- what to load: every ore and raw food in storage (less what config.lua
  -- keeps, like potatoes for planting), and what the orders still need
  local want, kinds = {}, {}
  local enriched = enricherTakes()
  for name, n in pairs(counts) do
    local kind = n > 0 and not leftFor(name, enriched) and smeltKind(name)
    if kind then
      kinds[name] = kind
      if n > (KEEP[name] or 0) then want[name] = n - (KEEP[name] or 0) end
    end
  end
  for item, t in pairs(byItem) do want[item] = math.min(counts[item], t.count - t.loaded) end
  -- blast furnaces only smelt ores, smokers only cook food, furnaces do both
  local function canTake(f, name)
    if (want[name] or 0) <= 0 or noSmelt[kindOf(f) .. name] then return false end
    if f.blast then return kinds[name] == "ore" end
    if f.smoker then return kinds[name] == "food" end
    return true
  end
  local loaded, into = 0, 0
  -- with a work chest, each load is only noted down and taken as done, so
  -- the furnaces are shared out as usual; it's all fetched at once after
  -- the fuel, and what didn't come is taken back off then (far away
  -- nothing can come any other way, so a work chest not in use loads nothing)
  local plan = useWork and {} or nil
  local function load(f, name, n)
    local got
    if plan then
      plan[#plan + 1] = { f = f, name = name, n = n }
      got = n
    else
      local r = ask({ type = "send", to = f.name, slot = 1, items = { [name] = n } })
      got = r and r.sent and r.sent[name] or 0
      if r and r.error then problem = r.error end
    end
    if got > 0 then
      want[name] = want[name] - got
      if f.input then f.input.count = f.input.count + got else f.input = { name = name, count = got } end
      if byItem[name] then byItem[name].loaded = byItem[name].loaded + got end
      loaded, into = loaded + got, into + 1
    end
  end
  local haveFuel = (stock.fuel or 0) > 0

  -- Mekanism smelters first (faster, no fuel), through their feeders; never
  -- for orders, since what they make goes into storage uncounted
  local unsure, feedProblem = smelters:register(work.remote)
  problem = problem or feedProblem
  smelters:unstick(meks, input, function(m, item)
    noSmelt["mek:" .. item.name] = true
    tell(("%s didn't go into %s: put it back. Is its hopper on top, or a pipe pulling from its barrel?")
      :format(nice(item.name), m.title), "orange")
  end)
  local mekPlan = {}
  for _, m in ipairs(meks) do
    if mekfeed.ready(m) and not unsure[m.entry.feeder] then
      local pick = mekfeed.current(m)
      if not pick then
        local most = 0
        for name, n in pairs(want) do
          if not byItem[name] and n > most and not noSmelt["mek:" .. name] then pick, most = name, n end
        end
      end
      local n = pick and math.min(mekfeed.space(m, pick), want[pick] or 0, 64) or 0
      if n > 0 and plan then
        mekPlan[#mekPlan + 1] = { m = m, name = pick, n = n }
        want[pick] = want[pick] - n
      elseif n > 0 then
        local r = ask({ type = "send", to = m.entry.feeder, items = { [pick] = n } })
        local got = r and r.sent and r.sent[pick] or 0
        if r and r.error then problem = r.error end
        mekfeed.added(m, pick, got)
        want[pick] = want[pick] - got
        if got > 0 then loaded, into = loaded + got, into + 1 end
      end
    end
  end

  -- top up what's already smelting
  for _, f in ipairs(furnaces) do
    if f.input and f.input.count < 64 and canTake(f, f.input.name) then
      load(f, f.input.name, math.min(64 - f.input.count, want[f.input.name]))
    end
  end
  -- then fill empty ones: blast furnaces and smokers first (twice as fast,
  -- but only ores or only food), and plain furnaces put the orders ahead of
  -- the rest, charcoal before stone before glass
  local empty = {}
  for _, f in ipairs(furnaces) do
    if not f.input and (f.fuel or haveFuel) then empty[#empty + 1] = f end
  end
  local function fast(f) return f.blast or f.smoker end
  table.sort(empty, function(a, b) return fast(a) and not fast(b) end)
  for _, f in ipairs(empty) do
    local pick
    for _, item in ipairs(orderItems) do
      if not pick and canTake(f, item) then pick = item end
    end
    if not pick then
      local most = 0
      for name, n in pairs(want) do
        if not byItem[name] and n > most and canTake(f, name) then pick, most = name, n end
      end
    end
    if pick then
      -- share it out between the furnaces still free that can take it
      local free = 0
      for _, g in ipairs(empty) do
        if not g.input and canTake(g, pick) then free = free + 1 end
      end
      load(f, pick, math.min(64, want[pick], math.max(LOAD_MIN, math.ceil(want[pick] / free))))
    end
  end

  -- fuel: enough for everything waiting in each furnace
  local unfuelled = false
  local function fuelShort(f)
    local have = f.fuel and f.fuel.count * (FUEL_SMELTS[f.fuel.name] or 8) or 0
    if f.input and have < f.input.count and not (f.fuel and f.fuel.count >= 64) then return f.input.count - have end
    return 0
  end
  local fuelWanted = 0
  for _, f in ipairs(furnaces) do
    local short = fuelShort(f)
    if short > 0 and plan then
      fuelWanted = fuelWanted + short
    elseif short > 0 then
      local r = ask({ type = "send", to = f.name, slot = 2, fuel = short, item = f.fuel and f.fuel.name })
      if r then stock.fuel = r.fuel or stock.fuel end
      for name, n in pairs(r and r.sent or {}) do
        f.fuel = { name = name, count = (f.fuel and f.fuel.count or 0) + n }
      end
      if not f.fuel then unfuelled = true end
    end
  end

  -- the work chest: one fill for every load and all the fuel, then each
  -- furnace is loaded from it, and what's left goes back to storage
  if plan then
    local items = {}
    for _, p in ipairs(plan) do items[p.name] = (items[p.name] or 0) + p.n end
    for _, p in ipairs(mekPlan) do items[p.name] = (items[p.name] or 0) + p.n end
    local r, why = work:fill(items, fuelWanted)
    if r then
      stock.fuel = r.fuel or stock.fuel
      if r.error and not r.nochest then problem = r.error end
    elseif next(items) or fuelWanted > 0 then
      problem = why
    end
    for _, p in ipairs(plan) do
      local moved = work:move(p.name, p.f.name, 1, p.n)
      local short = p.n - moved
      if short > 0 then
        local f = p.f
        f.input.count = f.input.count - short
        if f.input.count <= 0 then f.input = nil end
        if moved == 0 then into = into - 1 end
        want[p.name] = want[p.name] + short
        if byItem[p.name] then byItem[p.name].loaded = byItem[p.name].loaded - short end
        loaded = loaded - short
      end
    end
    for _, f in ipairs(furnaces) do
      local short = fuelShort(f)
      if short > 0 then
        -- a fuel slot holds one kind: more of what's in it, else the first there is
        for _, fuel in ipairs(FUEL_ORDER) do
          if short > 0 and (not f.fuel or f.fuel.name == fuel) then
            local n = math.min(64 - (f.fuel and f.fuel.count or 0), math.ceil(short / FUEL_SMELTS[fuel]))
            local moved = work:move(fuel, f.name, 2, n)
            if moved > 0 then
              f.fuel = { name = fuel, count = (f.fuel and f.fuel.count or 0) + moved }
              short = 0
            end
          end
        end
        if not f.fuel then unfuelled = true end
      end
    end
    for _, p in ipairs(mekPlan) do
      local got = work:move(p.name, p.m.entry.feeder, nil, p.n)
      mekfeed.added(p.m, p.name, got)
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
  for _, f in ipairs(furnaces) do
    if f.input then
      busy = busy + 1
      local s = stuckSince[f.name]
      if s and s.name == f.input.name then s.count = f.input.count end
    end
  end
  for _, m in ipairs(meks) do
    if (m.usage or 0) > 0 then busy = busy + 1 end
  end
  if problem then
    say("Couldn't move items: " .. problem, "red")
  elseif news and os.clock() < news[3] then
    say(news[1], news[2])
  elseif blocked then
    say("The storage input chest is full: smelted items are waiting in the furnaces.", "orange")
  elseif work.problem then
    say(("Not using the work chest: %s."):format(work.problem), "orange")
  elseif unfuelled then
    say("Out of fuel: put coal or charcoal in the fuel chest.", "orange")
  elseif loaded > 0 then
    say(("Loaded %d items into %d furnaces."):format(loaded, into))
  elseif busy == 0 then
    say("Nothing to smelt.")
  else
    say(("Smelting in %d furnaces."):format(busy))
  end
  status(busy > 0 and "running" or "idle", ("%d of %d furnaces smelting"):format(busy, #furnaces + #meks))
end

---------------------------------------------------------------- screen

-- Drawn through lib/screen.lua (a hidden window shown in one go), so it
-- doesn't flash.
local display = screen.new(term.current())
local win
local fitText = screen.fit

local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end

local function draw()
  local w, h
  win, w, h = display:frame()
  put(1, 1, (" "):rep(w), "white", "gray")
  put(2, 1, "Smelter", "yellow", "gray")
  local stat = stock and ("fuel for %d items"):format(stock.fuel or 0) or "no storage yet"
  put(w - #stat, 1, stat, "lightGray", "gray")
  local fuelX = w - 12
  put(2, 3, "Furnace", "yellow")
  put(20, 3, "Smelting", "yellow")
  put(fuelX, 3, "Fuel", "yellow")
  local lines = {}
  for _, o in ipairs(ORDERS) do
    local t = jobs[o.kind]
    if t then
      lines[#lines + 1] = ("%s%s: %d of %d made from %s"):format(o.kind:sub(1, 1):upper(), o.kind:sub(2), t.made,
        t.count, t.item and nice(t.item) or o.from)
    end
  end
  -- each row: name, its colour, what it's smelting, that colour, fuel (power for a Mekanism smelter)
  local list = {}
  for _, f in ipairs(furnaces) do
    list[#list + 1] = { nice(f.name), f.blast and "orange" or f.smoker and "pink" or "white",
      f.input and ("%d %s"):format(f.input.count, nice(f.input.name)) or "idle", f.input and "white" or "gray",
      f.fuel and ("%d %s"):format(f.fuel.count, nice(f.fuel.name)) or "-" }
  end
  for _, m in ipairs(meks) do
    local queued, item = mekfeed.inputOf(m) + m.feedTotal, mekfeed.current(m)
    local doing, colour = item and ("%d %s"):format(queued, nice(item)) or "idle", item and "white" or "gray"
    if not m.present then
      doing, colour = "not on network", "red"
    elseif not m.feedOk then
      doing, colour = "no feeder", "red"
    elseif (m.energy or 0) <= 0 then
      doing, colour = "no power", "red"
    elseif mekfeed.full(m) then
      doing, colour = "output full: chest under it?", "red"
    end
    list[#list + 1] = { m.title, "lightBlue", doing, colour,
      m.present and ("%d%% power"):format(math.floor((m.energy or 0) * 100 + 0.5)) or "-" }
  end
  local rows = h - 6 - math.max(#lines, 1)
  for i = 1, math.min(rows, #list) do
    local row, y = list[i], 3 + i
    put(2, y, fitText(row[1], 17), row[2])
    put(20, y, fitText(row[3], fuelX - 21), row[4])
    put(fuelX, y, fitText(row[5], 12), "lightGray")
  end
  if #list > rows then put(2, 4 + rows, ("...and %d more"):format(#list - rows), "gray") end
  if #list == 0 then put(2, 4, "No furnaces yet.", "gray") end
  if #lines == 0 then put(1, h - 2, fitText(" No orders.", w), "gray") end
  for i, line in ipairs(lines) do
    put(1, h - 2 - #lines + i, fitText(" " .. line, w), "lightBlue")
  end
  put(1, h - 1, fitText(message[1], w), message[2])
  put(1, h, fitText("C: charcoal  S: stone  G: glass  X: cancel an order", w), "gray")
  display:show()
end

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

local function uiLoop()
  while true do
    draw()
    local event, a = os.pullEvent()
    -- char, not key: read() in the prompt would otherwise get the "c" too
    a = event == "char" and a:lower()
    if a == "c" then
      charcoalPrompt()
    elseif a == "s" then
      amountPrompt("stone", "minecraft:cobblestone")
    elseif a == "g" then
      amountPrompt("glass", nil)
    elseif a == "x" then
      cancelPrompt()
    end
  end
end

local function workLoop()
  while true do
    round()
    os.queueEvent("smelter_changed")
    -- a new order starts straight away
    local timer = os.startTimer(EVERY)
    repeat
      local event, value = os.pullEvent()
    until (event == "timer" and value == timer) or event == "smelter_order" or event == "smelter_added"
  end
end

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "charcoal" then
  local n = tonumber(args[2])
  if not n or n < 1 then
    print("Usage: smelter charcoal <how many> [wood, e.g. spruce]")
    return
  end
  local wood = #args >= 3 and table.concat(args, "_", 3):lower() or nil
  newOrder("charcoal", wood, math.floor(n))
  print(("Charcoal order saved: %d from %s."):format(math.floor(n), wood and nice(wood) or "whichever logs there are most of"))
  print("The smelter starts on it within 10 seconds, or when it's next started.")
  return
elseif args[1] == "stone" then
  local n = tonumber(args[2])
  if not n or n < 1 then
    print("Usage: smelter stone <how many>")
    return
  end
  newOrder("stone", "minecraft:cobblestone", math.floor(n))
  print(("Stone order saved: %d from cobblestone."):format(math.floor(n)))
  print("The smelter starts on it within 10 seconds, or when it's next started.")
  return
elseif args[1] == "glass" then
  local n = tonumber(args[2])
  if not n or n < 1 or (args[3] and args[3] ~= "red") then
    print("Usage: smelter glass <how many> [red]")
    return
  end
  local sand = args[3] == "red" and "minecraft:red_sand" or nil
  newOrder("glass", sand, math.floor(n))
  print(("Glass order saved: %d from %s."):format(math.floor(n), sand and "red sand" or "whichever sand there's most of"))
  print("The smelter starts on it within 10 seconds, or when it's next started.")
  return
elseif args[1] == "cancel" then
  if args[2] and not orderKind[args[2]] then
    print("Usage: smelter cancel [charcoal|stone|glass]")
    return
  end
  for _, o in ipairs(ORDERS) do
    if not args[2] or args[2] == o.kind then
      cancelOrder(o.kind)
      print(cancelled(o.kind))
    end
  end
  return
elseif smelters:command(args) then
  return
elseif args[1] == "chest" then
  if not net.open("any") then
    print("I need a wired modem on the storage computer's network first (far away: an ender modem too).")
    return
  end
  work:command(args[2])
  return
end

if not net.open("any") then
  print("I need a wired modem on the storage computer's network (far away: on my own, plus an ender modem).")
  print("Put one on me, join it to the network with cable and right-click it so it turns red.")
  return
end

jobs = readOrders()
term.clear()
if report then report.init("smelter") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, workLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
