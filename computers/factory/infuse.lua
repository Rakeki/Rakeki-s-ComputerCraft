-- The factory's infuser (factory.lua loads it). Runs Mekanism Metallurgic
-- Infusers (and Infusing Factories) on request: nothing is infused until
-- someone asks. Requests come from its page (tap +1, +8 or +64 by what you
-- want, on the terminal or the monitor's Infuse page), from 'factory infuse',
-- or from the storage computer: it's told what can be infused here, so a
-- crafting plan that needs steel dust or an alloy has this make it first.
--
-- CC can't put items into a Mekanism machine, so each infuser has two
-- feeders (lib/mekfeed.lua): one for what's infused (a hopper on top, or a
-- barrel a pipe empties into its top) and one for the infusion items
-- (coal, redstone, diamond dust, ...: a hopper into any side, or a barrel a
-- pipe empties into a side). Its sides are set to match (top Input, bottom
-- Output, the rest Extra, Auto-eject on) when its security is Public. What
-- it makes comes out of its bottom into its output chest, where it's
-- counted towards the requests and then goes into storage.
--
-- An infuser holds one infusion type at a time: before it switches (carbon
-- to redstone, say) what's left of the old one is dumped, which needs
-- Public security too. Only what each request needs is sent, so little is
-- lost. The items requests are waiting on are left alone by the smelter
-- (rank 0 in the chain), so it doesn't smelt the iron or tin dust away.
local screen = require("lib.screen") -- flicker-free drawing
local mekfeed = require("lib.mekfeed") -- Mekanism machines fed through a hopper or barrel
local files = require("lib.files") -- crash-safe save files

local M = {}

local REQUEST_DIR = "/.factory_infuse" -- a file per request, so a request typed in another tab is never lost
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local GIVE_UP = 600 -- seconds a storage computer's request may wait with nothing to load before it's handed back
local MAKES_EVERY = 60 -- seconds between telling the craft overseer what can be infused here
local EXTRA_STUCK = 60 -- seconds infusion items may sit in their feeder over an empty slot before they're put back
local EXTRA_FILL = 64 -- most infusion items kept waiting in a feeder
local QUEUE_SHOWN = 3 -- requests listed under the recipes
local BUTTONS = { 1, 8, 64 } -- the request buttons by each recipe

-- What each infusion item gives (Mekanism 10.7's chemical_conversion recipes).
local INFUSE = {
  carbon = { ["minecraft:coal"] = 10, ["mekanism:dust_coal"] = 10, ["minecraft:charcoal"] = 20,
    ["mekanism:dust_charcoal"] = 20, ["minecraft:coal_block"] = 90, ["mekanism:block_charcoal"] = 180,
    ["mekanism:enriched_carbon"] = 80 },
  redstone = { ["minecraft:redstone"] = 10, ["minecraft:redstone_block"] = 90, ["mekanism:enriched_redstone"] = 80 },
  diamond = { ["mekanism:dust_diamond"] = 10, ["mekanism:enriched_diamond"] = 80 },
  refined_obsidian = { ["mekanism:dust_refined_obsidian"] = 10, ["mekanism:enriched_refined_obsidian"] = 80 },
  tin = { ["mekanism:dust_tin"] = 10, ["mekanism:enriched_tin"] = 80 },
  gold = { ["mekanism:dust_gold"] = 10, ["mekanism:enriched_gold"] = 80 },
  bio = { ["mekanism:bio_fuel"] = 5, ["mekanism:block_bio_fuel"] = 45 },
  fungi = { ["minecraft:brown_mushroom"] = 10, ["minecraft:red_mushroom"] = 10, ["minecraft:crimson_fungus"] = 10,
    ["minecraft:warped_fungus"] = 10 },
}
-- How each type is spoken of on the screen.
local INFUSE_WORDS = { carbon = "coal or charcoal", redstone = "redstone", diamond = "diamond dust",
  refined_obsidian = "refined obsidian dust", tin = "tin dust", gold = "gold dust", bio = "bio fuel", fungi = "mushrooms" }

-- Mekanism 10.7's metallurgic infusing recipes: make (count of it) from per
-- of one of from, with amount of an infusion type.
local RECIPES = {
  { title = "Steel dust", make = "mekanism:dust_steel", from = { "mekanism:enriched_iron" }, infuse = "carbon", amount = 10 },
  { title = "Enriched iron", make = "mekanism:enriched_iron", from = { "minecraft:iron_ingot", "mekanism:dust_iron" },
    infuse = "carbon", amount = 10 },
  { title = "Infused alloy", make = "mekanism:alloy_infused", from = { "minecraft:copper_ingot" }, infuse = "redstone", amount = 10 },
  { title = "Reinforced alloy", make = "mekanism:alloy_reinforced", from = { "mekanism:alloy_infused" },
    infuse = "diamond", amount = 20 },
  { title = "Atomic alloy", make = "mekanism:alloy_atomic", from = { "mekanism:alloy_reinforced" },
    infuse = "refined_obsidian", amount = 40 },
  { title = "Basic circuit", make = "mekanism:basic_control_circuit", from = { "mekanism:ingot_osmium" },
    infuse = "redstone", amount = 20 },
  { title = "Bronze ingot", make = "mekanism:ingot_bronze", count = 4, from = { "minecraft:copper_ingot" }, per = 3,
    infuse = "tin", amount = 10 },
  { title = "Bronze dust", make = "mekanism:dust_bronze", count = 4, from = { "mekanism:dust_copper" }, per = 3,
    infuse = "tin", amount = 10 },
  { title = "Gilded blackstone", make = "minecraft:gilded_blackstone", from = { "minecraft:blackstone" },
    infuse = "gold", amount = 100 },
  { title = "Slime ball", make = "minecraft:slime_ball", from = { "minecraft:clay_ball" }, infuse = "bio", amount = 10 },
  { title = "Slime balls", make = "minecraft:slime_ball", count = 4, from = { "minecraft:clay" }, infuse = "bio", amount = 40 },
  { title = "Podzol", make = "minecraft:podzol", from = { "minecraft:dirt" }, infuse = "bio", amount = 10 },
  { title = "Mycelium", make = "minecraft:mycelium", from = { "minecraft:dirt" }, infuse = "fungi", amount = 10 },
  { title = "Dirt", make = "minecraft:dirt", from = { "minecraft:sand", "minecraft:red_sand" }, infuse = "bio", amount = 10 },
  { title = "Crimson nylium", make = "minecraft:crimson_nylium", from = { "minecraft:netherrack" }, infuse = "fungi", amount = 10 },
  { title = "Warped nylium", make = "minecraft:warped_nylium", from = { "minecraft:crimson_nylium" }, infuse = "fungi", amount = 10 },
  { title = "Mossy cobblestone", make = "minecraft:mossy_cobblestone", from = { "minecraft:cobblestone" }, infuse = "bio", amount = 10 },
  { title = "Mossy cobble slab", make = "minecraft:mossy_cobblestone_slab", from = { "minecraft:cobblestone_slab" },
    infuse = "bio", amount = 10 },
  { title = "Mossy cobble stairs", make = "minecraft:mossy_cobblestone_stairs", from = { "minecraft:cobblestone_stairs" },
    infuse = "bio", amount = 10 },
  { title = "Mossy cobble wall", make = "minecraft:mossy_cobblestone_wall", from = { "minecraft:cobblestone_wall" },
    infuse = "bio", amount = 10 },
  { title = "Mossy stone bricks", make = "minecraft:mossy_stone_bricks", from = { "minecraft:stone_bricks" },
    infuse = "bio", amount = 10 },
  { title = "Mossy brick slab", make = "minecraft:mossy_stone_brick_slab", from = { "minecraft:stone_brick_slab" },
    infuse = "bio", amount = 10 },
  { title = "Mossy brick stairs", make = "minecraft:mossy_stone_brick_stairs", from = { "minecraft:stone_brick_stairs" },
    infuse = "bio", amount = 10 },
  { title = "Mossy brick wall", make = "minecraft:mossy_stone_brick_wall", from = { "minecraft:stone_brick_wall" },
    infuse = "bio", amount = 10 },
}

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function escape(name) return "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "$" end

local function contains(list, name)
  for _, x in ipairs(list) do
    if x == name then return true end
  end
  return false
end

-- f: the factory (factory.lua): ask, work, config, wake, changed, event, taken.
function M.new(f)
  local config = f.config("infuser")
  local KEEP = config.keep or {} -- item -> how many to leave in storage
  local HIDE = config.hide or {} -- items not to offer, e.g. { "minecraft:podzol" }
  local OFFER = config.offer ~= false -- tell the storage computer what can be infused here

  -- the recipes: the ones above, then config's own, less the hidden ones
  local recipes = {}
  for _, list in ipairs({ RECIPES, config.recipes or {} }) do
    for _, r in ipairs(list) do
      if type(r) == "table" and type(r.make) == "string" and type(r.from) == "table" and INFUSE[r.infuse]
        and not contains(HIDE, r.make) then
        r.count, r.per, r.amount = r.count or 1, r.per or 1, r.amount or 10
        r.title = r.title or nice(r.make)
        r.key = r.make .. "<" .. r.from[1]
        recipes[#recipes + 1] = r
      end
    end
  end
  local byKey = {}
  for _, r in ipairs(recipes) do byKey[r.key] = r end
  -- the infusion type an item gives, and how much
  local infuseOf = {}
  for kind, items in pairs(INFUSE) do
    for item, n in pairs(items) do infuseOf[item] = { kind = kind, amount = n } end
  end

  local self = { id = "infuse", title = "Infuser", short = "Infuse", rank = 0, every = 5, what = "Requests -> steel, alloys, circuits" }
  local machines = {}
  local requests = {} -- every request, oldest first (REQUEST_DIR)
  local counts = {} -- the storage computer's counts, for the screen
  local assigned = {} -- machine peripheral -> the request id it's working on
  local extraStuck = {} -- infusion feeder -> { name, count, since }
  local news -- { text, colour, untilTime }
  local outStuck, outWhy, collected
  local makesKey, makesAt, makesNote = nil, -math.huge, nil
  local scroll = 0 -- the first recipe shown
  local picked = 1 -- the recipe the terminal's keys ask for (a basic computer has no mouse)
  local zones = {} -- target -> { { x1, x2, y, action } }: what a tap does on the terminal or monitor
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

  -- The infusion buffer and extra slot, read with the rest of the machine.
  local function reads(m, call)
    local fac = m.factory
    return {
      function() m.buffer = call(fac and "getChemical" or "getInfuseType") end,
      function() m.bufferCap = call(fac and "getChemicalCapacity" or "getInfuseTypeCapacity") end,
      function() m.extraSlot = call(fac and "getChemicalItem" or "getInfuseTypeItem") end,
    }
  end

  self.set = mekfeed.new({ name = "infuser", cmd = "factory", event = f.event, single = "metallurgicInfuser",
    factory = "InfusingFactory", what = "infuser", title = "Infuser", names = config.names,
    setSides = config.setSides ~= false, ask = f.ask, tell = tell, far = function() return f.work.remote end,
    taken = f.taken, pageTitle = "Infusers", needOutput = true, read = reads,
    sides = { TOP = "INPUT", BOTTOM = "OUTPUT", FRONT = "EXTRA", BACK = "EXTRA", LEFT = "EXTRA", RIGHT = "EXTRA" },
    sidesText = "Top to Input, Bottom to Output, the other sides to Extra",
    extra = { title = "infusion feeder", hint = "The hopper into its side, or the barrel a pipe pulls from into its side: coal, redstone and so on go in there." } })

  function self.found() return {} end
  function self.uses() return self.set:uses() end
  function self.active() return #self.set:entries() > 0 end

  ---------------------------------------------------------------- requests

  local function loadRequests()
    local list = {}
    if fs.isDir(REQUEST_DIR) then
      for _, file in ipairs(fs.list(REQUEST_DIR)) do
        local r = files.read(REQUEST_DIR .. "/" .. file)
        if type(r) == "table" and type(r.count) == "number" then
          r.file = REQUEST_DIR .. "/" .. file
          r.made = r.made or 0
          r.recipe = byKey[r.key]
          list[#list + 1] = r
        end
      end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    return list
  end

  local function plain(r)
    return { key = r.key, count = r.count, made = r.made, at = r.at, job = r.job, done = r.done, ok = r.ok, why = r.why,
      parent = r.parent }
  end

  -- Only while its file is there: a request cancelled in another tab stays cancelled.
  local function saveRequest(r)
    if fs.exists(r.file) then files.write(r.file, plain(r)) end
  end

  local function newRequest(key, count, job, parent)
    if not fs.isDir(REQUEST_DIR) then fs.makeDir(REQUEST_DIR) end
    local at = os.epoch("utc")
    local file = ("%s/%.0f"):format(REQUEST_DIR, at)
    while fs.exists(file) do
      at = at + 1
      file = ("%s/%.0f"):format(REQUEST_DIR, at)
    end
    files.write(file, { key = key, count = count, made = 0, at = at, job = job, parent = parent })
    return file
  end

  -- Ask for count more of what recipe makes (whole goes: bronze comes in
  -- fours): added to a request of yours
  -- for it that's still waiting, else a new one.
  local function request(r, count)
    count = math.ceil(count / r.count) * r.count
    for _, q in ipairs(loadRequests()) do
      if q.key == r.key and not q.job and not q.done then
        q.count = q.count + count
        saveRequest(q)
        f.wake()
        return
      end
    end
    newRequest(r.key, count)
    f.wake()
  end

  -- How many of what a request asks for are still to be made, and in infusing ops.
  local function left(q) return math.max(0, q.count - q.made) end
  local function opsLeft(q) return math.ceil(left(q) / q.recipe.count) end

  ---------------------------------------------------------------- what's there

  -- How much of an infusion type the items in avail would give.
  local function infuseIn(avail, kind)
    local total = 0
    for item, n in pairs(INFUSE[kind]) do total = total + math.max(0, avail[item] or 0) * n end
    return total
  end

  -- How many of a recipe's crafts what's stored would do, and what's
  -- missing (nil when it's none).
  local function canMake(r, avail)
    local inputs = 0
    for _, item in ipairs(r.from) do inputs = inputs + math.max(0, (avail[item] or 0) - (KEEP[item] or 0)) end
    local ops = math.min(math.floor(inputs / r.per), math.floor(infuseIn(avail, r.infuse) / r.amount))
    local missing
    if inputs < r.per then missing = nice(r.from[1])
    elseif infuseIn(avail, r.infuse) < r.amount then missing = INFUSE_WORDS[r.infuse] end
    return ops * r.count, missing
  end

  -- The recipe here that makes one of r's inputs (enriched iron, for steel
  -- dust), if any.
  local function feeding(r)
    for _, s in ipairs(recipes) do
      if s ~= r and contains(r.from, s.make) then return s end
    end
    return nil
  end

  -- canMake, counting what could first be infused into its input here too
  -- (steel dust from iron ingots, by way of enriched iron).
  local function canChain(r, avail)
    local direct, missing = canMake(r, avail)
    local s = feeding(r)
    if not s then return direct, missing end
    local units = 0
    for _, item in ipairs(r.from) do units = units + math.max(0, (avail[item] or 0) - (KEEP[item] or 0)) end
    local subInputs = 0
    for _, item in ipairs(s.from) do subInputs = subInputs + math.max(0, (avail[item] or 0) - (KEEP[item] or 0)) end
    local function ok(k)
      local subOps = math.ceil(math.max(0, k * r.per - units) / s.count)
      if subOps * s.per > subInputs then return false end
      if s.infuse == r.infuse then return k * r.amount + subOps * s.amount <= infuseIn(avail, r.infuse) end
      return k * r.amount <= infuseIn(avail, r.infuse) and subOps * s.amount <= infuseIn(avail, s.infuse)
    end
    local lo, hi = 0, 1
    while hi <= 9999 and ok(hi) do lo, hi = hi, hi * 2 end
    hi = math.min(hi, 10000)
    while hi - lo > 1 do
      local mid = math.floor((lo + hi) / 2)
      if ok(mid) then lo = mid else hi = mid end
    end
    if lo * r.count <= direct then return direct, missing end
    return lo * r.count, nil
  end

  -- The infusion type in a machine's buffer and how much, or nil.
  local function buffer(m)
    local b = m.buffer
    if type(b) ~= "table" or type(b.name) ~= "string" or (b.amount or 0) <= 0 then return nil, 0 end
    return b.name:gsub("^[%w_]+:", ""), b.amount
  end

  local function stackOf(s)
    if type(s) == "table" and type(s.name) == "string" and (s.count or 0) > 0 and s.name ~= "minecraft:air" then return s end
  end

  -- How much of kind is waiting in the extra slot and the infusion feeder,
  -- and the first item there of another type, if any.
  local function infuseWaiting(m, kind)
    local total, other = 0, nil
    local slot = stackOf(m.extraSlot)
    local items = {}
    if slot then items[#items + 1] = { slot.name, slot.count } end
    for name, n in pairs(m.extraFeed) do items[#items + 1] = { name, n } end
    for _, it in ipairs(items) do
      local inf = infuseOf[it[1]]
      if inf and inf.kind == kind then total = total + inf.amount * it[2] else other = other or it[1] end
    end
    return total, other
  end

  -- How many of a recipe's inputs are in a machine and its feeder.
  local function inputsIn(m, r)
    local n = 0
    for _, item in ipairs(r.from) do n = n + mekfeed.inputOf(m, item) + (m.feed[item] or 0) end
    return n
  end

  -- The request a machine works on: the one it was given, else the one its
  -- input slot or feeder holds the input of.
  local function requestOf(m)
    local id = assigned[m.entry.machine]
    for _, q in ipairs(requests) do
      if q.at == id and not q.done and q.recipe then return q end
    end
    for _, q in ipairs(requests) do
      if not q.done and q.recipe and inputsIn(m, q.recipe) > 0 then return q end
    end
    return nil
  end

  -- Count what came out of the output chests towards the requests, oldest first.
  local function credit(byName)
    for _, q in ipairs(requests) do
      if not q.done and q.recipe then
        local n = math.min(byName[q.recipe.make] or 0, left(q))
        if n > 0 then
          q.made = q.made + n
          byName[q.recipe.make] = byName[q.recipe.make] - n
          q.progressAt = os.clock()
          saveRequest(q)
        end
      end
    end
  end

  ---------------------------------------------------------------- the storage computer

  -- The recipes as the craft overseer plans them: a grid of the input and
  -- enough of the cheapest infusion items for one go (only types that come
  -- in small items, and only recipes that fit nine cells).
  local function asCrafts()
    local out = {}
    for _, r in ipairs(recipes) do
      local list, least = {}, math.huge
      for item, n in pairs(INFUSE[r.infuse]) do
        if n <= 20 then
          list[#list + 1] = item
          least = math.min(least, n)
        end
      end
      table.sort(list)
      local k = math.ceil(r.amount / least)
      if #list > 0 and r.per + k <= 9 then
        local cells = ("A"):rep(r.per) .. ("B"):rep(k)
        local rows = {}
        for i = 1, #cells, 3 do rows[#rows + 1] = cells:sub(i, i + 2) end
        out[#out + 1] = { make = r.make, count = r.count, rows = rows,
          keys = { A = #r.from == 1 and r.from[1] or r.from, B = #list == 1 and list[1] or list } }
      end
    end
    return out
  end

  -- Tell the storage computer what can be infused here (none without an
  -- infuser), when it changes and every so often, as it forgets in time.
  local function offer()
    if not OFFER then return end
    local crafts = self.active() and asCrafts() or {}
    local key = tostring(#crafts)
    if key == makesKey and os.clock() - makesAt < MAKES_EVERY then return end
    local reply = f.craft({ type = "makes", via = "infuse", recipes = crafts }, 5)
    makesAt = os.clock()
    if reply and reply.ok then
      makesKey, makesNote = key, nil
    else
      makesKey = nil
      makesNote = reply and reply.error or "the craft overseer doesn't take infusing orders: is it running, and updated?"
    end
  end

  -- A storage computer's request is finished (or given up on): tell it.
  -- True once it has heard.
  local function report(q)
    if not q.job then return true end
    local reply = f.craft({ type = "jobdone", job = q.job, ok = q.ok, why = q.why }, 5)
    return reply ~= nil
  end

  -- From the storage computer (factory protocol): 'infuse' (make this for
  -- one of my crafting plans) and 'cancel'. The reply, or nil if it isn't one.
  function self.request(from, msg)
    if msg.type == "infuse" then
      if not self.active() then return { ok = false, why = "no infuser here" } end
      local r
      for _, x in ipairs(recipes) do
        if x.make == msg.make then
          for _, item in pairs(type(msg.grid) == "table" and msg.grid or {}) do
            if contains(x.from, item) then r = r or x end
          end
          r = r or (type(msg.grid) ~= "table" and x or nil)
        end
      end
      local count = math.floor(tonumber(msg.count) or 0)
      if not r or count < 1 then return { ok = false, why = "this infuser has no recipe for it" } end
      newRequest(r.key, count, msg.job)
      f.wake()
      return { ok = true }
    elseif msg.type == "cancel" then
      for _, q in ipairs(loadRequests()) do
        if q.job and q.job == msg.job then fs.delete(q.file) end
      end
      f.wake()
      return { ok = true }
    end
    return nil
  end

  -- What the smelter leaves alone: the inputs and infusion items of every
  -- request still waiting.
  local taking = {}
  function self.takes() return taking end

  function self.summary()
    local n = #self.set:entries()
    local waiting = 0
    for _, q in ipairs(requests) do
      if not q.done then waiting = waiting + 1 end
    end
    return ("%d infuser%s%s"):format(n, n == 1 and "" or "s", waiting > 0 and (", %d requests"):format(waiting) or "")
  end

  ---------------------------------------------------------------- a round

  function self.read(remote, remoteInput)
    machines = self.set:read()
    requests = loadRequests()
    local seen, list = {}, {}
    for _, q in ipairs(requests) do
      if q.recipe and not q.done then
        local items = {}
        for _, item in ipairs(q.recipe.from) do items[#items + 1] = item end
        for item in pairs(INFUSE[q.recipe.infuse]) do items[#items + 1] = item end
        for _, item in ipairs(items) do
          if not seen[item] then
            seen[item] = true
            list[#list + 1] = escape(item)
          end
        end
      end
    end
    taking = list
    outStuck, outWhy, collected = false, nil, false
    if remote then
      local _, byName
      _, outStuck, outWhy, byName = self.set:collect(machines, remoteInput)
      credit(byName)
      collected = true
    end
  end

  -- Send a feeder items: noted in plan with a work chest, else asked for
  -- now. How many it got (planned ones count as got).
  local function load(plan, m, to, name, n, extra)
    if n <= 0 then return 0 end
    if plan then
      plan[#plan + 1] = { m = m, to = to, name = name, n = n, extra = extra }
      return n
    end
    local reply = f.ask({ type = "send", to = to, items = { [name] = n } })
    local got = reply and type(reply.sent) == "table" and reply.sent[name] or 0
    if reply and reply.error then self.problem = reply.error end
    if not reply then self.problem = "the storage computer didn't answer while loading " .. m.title end
    return got
  end

  -- The infusion items to send for need more of kind: the biggest ones that
  -- don't overshoot, then one of the smallest for what's left. { item = n }.
  local function pickInfusion(kind, need, avail)
    local list = {}
    for item, n in pairs(INFUSE[kind]) do
      if (avail[item] or 0) > (KEEP[item] or 0) then list[#list + 1] = { item, n } end
    end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local out = {}
    for _, it in ipairs(list) do
      local n = math.min(math.floor(need / it[2]), avail[it[1]] - (KEEP[it[1]] or 0))
      if n > 0 then
        out[it[1]] = n
        need = need - n * it[2]
      end
    end
    if need > 0 then
      for i = #list, 1, -1 do
        local item = list[i][1]
        if avail[item] - (KEEP[item] or 0) - (out[item] or 0) > 0 then
          out[item] = (out[item] or 0) + 1
          break
        end
      end
    end
    return out
  end

  function self.round(r)
    local work = f.work
    counts = r.stock.counts
    self.problem = r.feedProblem
    offer()
    if #machines == 0 then
      say("Nothing set up yet: add an infuser on the setup screen.", "orange")
      status("waiting", "nothing set up")
      return
    end
    local input = r.input
    local avail = {}
    for name, n in pairs(counts) do avail[name] = n end

    if not collected then
      local _, byName
      _, outStuck, outWhy, byName = self.set:collect(machines, input)
      credit(byName)
    end
    self.set:unstick(machines, input, function(m, item)
      tell(("%s didn't go into %s: put it back. Is its feeder on top?"):format(nice(item.name), m.title), "orange")
    end)

    -- finished requests: done, or a storage computer's that waited too long
    local now = os.clock()
    for _, q in ipairs(requests) do
      q.progressAt = q.progressAt or now
      if not q.recipe then
        q.done, q.ok, q.why = true, false, "this infuser has no recipe for it any more"
      elseif left(q) == 0 and not q.done then
        q.done, q.ok = true, true
        if not q.job then tell(("Made %d %s."):format(q.made, q.recipe.title), "lime") end
      elseif q.job and not q.done and now - q.progressAt > GIVE_UP then
        q.done, q.ok, q.why = true, false, q.state or "nothing to make it from"
      end
      if q.done then
        saveRequest(q)
        if report(q) then fs.delete(q.file) end
      end
    end
    local open = {}
    for _, q in ipairs(requests) do
      if not q.done and fs.exists(q.file) then open[#open + 1] = q end
    end
    requests = open

    -- a request of yours whose input isn't stored but can be infused here
    -- first (enriched iron for steel dust) gets a request for that ahead of it
    for _, q in ipairs(requests) do
      local rc, s = q.recipe, feeding(q.recipe)
      local child = false
      for _, x in ipairs(requests) do
        if x.parent == q.at then child = true end
      end
      if s and not q.job and not child and canMake(rc, avail) == 0 and canMake(s, avail) > 0 then
        local stored = 0
        for _, item in ipairs(rc.from) do stored = stored + math.max(0, (avail[item] or 0) - (KEEP[item] or 0)) end
        local need = opsLeft(q) * rc.per - stored
        if need > 0 then
          local count = math.ceil(need / s.count) * s.count
          local file = newRequest(s.key, count, nil, q.at)
          local x = files.read(file)
          x.file, x.recipe = file, s
          requests[#requests + 1] = x
          tell(("%s needs %s first: asked for %d."):format(rc.title, s.title, count), "lightBlue")
        end
      end
    end

    -- what's already on its way for each request
    local busy = {} -- request id -> ops in machines and feeders
    for _, m in ipairs(machines) do
      local q = mekfeed.ready(m) and requestOf(m)
      m.request = q
      if q then busy[q.at] = (busy[q.at] or 0) + math.floor(inputsIn(m, q.recipe) / q.recipe.per) end
    end
    for _, q in ipairs(requests) do q.state = nil end

    local plan = r.useWork and {} or nil
    local sent = 0
    for _, m in ipairs(machines) do
      m.state, m.colour = nil, nil
      local q = m.request
      if mekfeed.ready(m) and not r.unsure[m.entry.feeder] and not (m.entry.extra and r.unsure[m.entry.extra]) then
        -- nothing to do: the oldest request with work left that this machine can take
        if not q then
          for _, x in ipairs(requests) do
            if not q and opsLeft(x) > (busy[x.at] or 0) then
              local ops = canMake(x.recipe, avail)
              if ops > 0 then q = x end
              if ops == 0 then x.state = x.state or ("waiting for " .. select(2, canMake(x.recipe, avail))) end
            end
          end
        end
        m.request = q
        assigned[m.entry.machine] = q and q.at or nil
        if q then
          local rc = q.recipe
          local kind, amount = buffer(m)
          local _, otherItem = infuseWaiting(m, rc.infuse)
          if otherItem then
            m.state, m.colour = ("holds %s"):format(nice(otherItem)), "orange"
            q.state = q.state or ("%s holds %s: take it out"):format(m.title, nice(otherItem))
          elseif kind and kind ~= rc.infuse then
            -- another type in the buffer: dump it once nothing's waiting to use it
            if mekfeed.inputOf(m) + m.feedTotal == 0 then
              local ok = pcall(peripheral.call, m.entry.machine, m.factory and "dumpChemical" or "dumpInfuseType")
              if ok then
                kind, amount = nil, 0
              else
                m.state, m.colour = ("holds %s"):format(kind), "orange"
                q.state = q.state or ("%s still holds %s: make it Public so it can be emptied"):format(m.title, kind)
              end
            else
              m.state, m.colour = "finishing", "lightBlue"
            end
          end
          if not m.state then
            -- the input: what's in it already, else what there's most of
            local item
            for _, x in ipairs(rc.from) do
              if mekfeed.inputOf(m, x) + (m.feed[x] or 0) > 0 then item = item or x end
            end
            if not item then
              local most = 0
              for _, x in ipairs(rc.from) do
                local n = (avail[x] or 0) - (KEEP[x] or 0)
                if n > most then item, most = x, n end
              end
            end
            local want = (opsLeft(q) - (busy[q.at] or 0)) * rc.per
            local n = item and math.min(mekfeed.space(m, item), (avail[item] or 0) - (KEEP[item] or 0), SEND_MAX, want) or 0
            if n > 0 and rc.per > 1 then n = n - (inputsIn(m, rc) + n) % rc.per end
            -- the infusion for everything it'll then hold
            local ops = math.floor((inputsIn(m, rc) + math.max(n, 0)) / rc.per)
            local have = (kind == rc.infuse and amount or 0) + infuseWaiting(m, rc.infuse)
            local need = ops * rc.amount - have
            local extras = {}
            if need > 0 then
              local room = EXTRA_FILL - m.extraTotal
              for x, k in pairs(pickInfusion(rc.infuse, need, avail)) do
                k = math.min(k, room, SEND_MAX)
                if k > 0 then
                  extras[x] = k
                  room = room - k
                end
              end
              if not next(extras) and have < rc.amount then
                q.state = q.state or ("waiting for " .. INFUSE_WORDS[rc.infuse])
              end
            end
            for x, k in pairs(extras) do
              local got = load(plan, m, m.entry.extra, x, k, true)
              avail[x] = (avail[x] or 0) - got
              m.extraFeed[x] = (m.extraFeed[x] or 0) + got
              m.extraTotal = m.extraTotal + got
              sent = sent + got
            end
            if n > 0 then
              local got = load(plan, m, m.entry.feeder, item, n)
              mekfeed.added(m, item, got)
              avail[item] = (avail[item] or 0) - got
              busy[q.at] = (busy[q.at] or 0) + math.floor(got / rc.per)
              sent = sent + got
              q.progressAt = now
            end
          end
        end
      end
    end
    if plan then
      local items = {}
      for _, p in ipairs(plan) do items[p.name] = (items[p.name] or 0) + p.n end
      local reply, why = work:fill(items, 0)
      if reply and reply.error and not reply.nochest then self.problem = reply.error end
      if not reply and next(items) then self.problem = why end
      for _, p in ipairs(plan) do
        local got = work:move(p.name, p.to, nil, p.n)
        if got < p.n then
          if p.extra then
            p.m.extraFeed[p.name] = (p.m.extraFeed[p.name] or 0) - (p.n - got)
            p.m.extraTotal = p.m.extraTotal - (p.n - got)
          else
            mekfeed.added(p.m, p.name, got - p.n)
          end
          sent = sent - (p.n - got)
        end
      end
      work:empty(input)
    end

    -- infusion items that sit in their feeder over an empty extra slot go back
    for _, m in ipairs(machines) do
      local feeder = m.entry.extra
      local s = feeder and extraStuck[feeder]
      local _, item = next(m.extraList)
      if item and m.extraOk and not stackOf(m.extraSlot) and (m.energy or 0) > 0 then
        if s and s.name == item.name and (m.extraFeed[item.name] or 0) >= s.count then
          if now - s.since > EXTRA_STUCK and input then
            for slot in pairs(m.extraList) do pcall(peripheral.call, feeder, "pushItems", input, slot) end
            extraStuck[feeder] = nil
            tell(("%s didn't go into %s: put it back. Is its infusion feeder on a side, and are its sides set (make it Public)?")
              :format(nice(item.name), m.title), "orange")
          end
        else
          extraStuck[feeder] = { name = item.name, count = m.extraFeed[item.name] or 0, since = now }
        end
      elseif feeder then
        extraStuck[feeder] = nil
      end
    end

    -- how each machine and request is doing
    local working, broken = 0, 0
    for _, m in ipairs(machines) do
      local colour, text = mekfeed.status(m, m.request and m.request.recipe.title)
      if not m.state then
        m.state = text
        m.colour = ({ red = "red", orange = "lime", yellow = "lime", lime = "gray" })[colour] or "gray"
        if colour == "yellow" and text == "starting" then m.colour = "lightBlue" end
      end
      m.tile = colour
      if colour == "red" then broken = broken + 1
      elseif colour == "orange" or colour == "yellow" then working = working + 1 end
    end
    for _, q in ipairs(requests) do
      local on = 0
      for _, m in ipairs(machines) do
        if m.request == q then on = on + 1 end
      end
      if on > 0 and not q.state then q.state = ("on %d infuser%s"):format(on, on == 1 and "" or "s") end
      q.state = q.state or "queued"
    end

    local problem = self.problem
    if outWhy then problem = problem or outWhy
    elseif outStuck then
      problem = problem or ("the %s is full: what's made is waiting in the output chests"):format(work.remote and "ender chest" or "storage input chest")
    end
    if news and os.clock() < news[3] then
      self.message = { news[1], news[2] }
    elseif problem then
      say("Couldn't move items: " .. problem, "red")
    elseif work.problem then
      say(("Not using the work chest: %s."):format(work.problem), "orange")
    elseif broken > 0 then
      local m
      for _, x in ipairs(machines) do
        if x.tile == "red" then m = m or x end
      end
      say(("%s: %s"):format(m.title, m.state), "red")
    elseif makesNote and #requests == 0 then
      say(makesNote, "orange")
    elseif #requests == 0 then
      say("Tap +1, +8 or +64 by what you want made.")
    elseif sent > 0 then
      say(("Sent %d items to the infusers."):format(sent))
    else
      say(("%s: %s."):format(requests[1].recipe.title, requests[1].state))
    end
    status(broken > 0 and "alert" or working > 0 and "running" or "idle",
      ("%d of %d infusers working, %d requests"):format(working, #machines, #requests))
  end

  ---------------------------------------------------------------- screen

  -- Tap zones: target (the terminal or the monitor) -> { x1, x2, y, action }.
  local function zone(target, x1, x2, y, action)
    zones[target] = zones[target] or {}
    local list = zones[target]
    list[#list + 1] = { x1, x2, y, action }
  end

  local function button(win, target, x, y, text, action, fg, bg)
    screen.put(win, x, y, text, fg or "black", bg or "lightGray")
    zone(target, x, x + #text - 1, y, action)
    return x + #text + 1
  end

  -- The recipes, each with what it's made from, how many can be made and
  -- the request buttons, then the requests (tap x to cancel one).
  local function drawRequests(win, w, h, target, footer)
    zones[target] = {}
    local fit = screen.fit
    local btnW = 0
    for _, n in ipairs(BUTTONS) do btnW = btnW + #(" +" .. n .. " ") + 1 end
    local bx = w - btnW + 1
    local canR = bx - 2
    screen.put(win, 2, 3, "Make", "yellow")
    screen.put(win, canR - 2, 3, "Can", "yellow")
    screen.put(win, bx, 3, "Request", "yellow")
    local queueRows = math.min(QUEUE_SHOWN, #requests)
    local rows = h - 4 - #footer - (queueRows > 0 and queueRows + 1 or 0)
    local keyed = target == "terminal"
    if keyed then
      picked = math.max(1, math.min(picked, #recipes))
      -- the picked recipe stays in view
      if picked <= scroll then scroll = picked - 1 end
      if picked > scroll + rows then scroll = picked - rows end
    end
    scroll = math.max(0, math.min(scroll, #recipes - rows))
    for i = 1, rows do
      local rc, y = recipes[scroll + i], 3 + i
      if rc then
        local n, missing = canChain(rc, counts)
        local nameW = canR - 7
        local name = rc.title
        local from = (" %s%s + %s"):format(rc.per > 1 and (rc.per .. " ") or "", nice(rc.from[1]), rc.infuse:gsub("_", " "))
        local bg = keyed and scroll + i == picked and "gray" or "black"
        screen.put(win, 1, y, (" "):rep(canR + 1), "white", bg)
        screen.put(win, 2, y, fit(name, nameW), n > 0 and "white" or "lightGray", bg)
        if #name + 2 < nameW then screen.put(win, 2 + #name, y, fit(from, nameW - #name), bg == "gray" and "lightGray" or "gray", bg) end
        local can = n > 9999 and "9999+" or tostring(n)
        screen.put(win, canR - #can + 1, y, can, n > 0 and "lime" or bg == "gray" and "lightGray" or "gray", bg)
        local x = bx
        for _, k in ipairs(BUTTONS) do
          x = button(win, target, x, y, (" +%d "):format(k), { add = rc, n = k }, "black", n > 0 and "lightGray" or "gray")
        end
        if missing and n == 0 and w >= 60 then screen.put(win, bx - 20, y, fit("needs " .. missing, 12), "orange") end
      end
    end
    if #recipes > rows then
      screen.put(win, w, 4, scroll > 0 and "^" or " ", "yellow")
      screen.put(win, w, 3 + rows, scroll + rows < #recipes and "v" or " ", "yellow")
      zone(target, w, w, 4, { scroll = -rows })
      zone(target, w, w, 3 + rows, { scroll = rows })
    end
    if queueRows > 0 then
      local y = 4 + rows
      screen.put(win, 2, y, ("Requests (%d)"):format(#requests), "yellow")
      for i = 1, queueRows do
        local q = requests[i]
        local text = ("%s %d/%d%s: %s"):format(q.recipe.title, q.made, q.count, q.job and " (storage)" or "", q.state or "queued")
        screen.put(win, 2, y + i, fit(text, w - 6), "white")
        button(win, target, w - 3, y + i, " x ", { cancel = q.file }, "white", "red")
      end
    end
    for i, line in ipairs(footer) do screen.put(win, 1, h - #footer + i, fit(line[1], w), line[2]) end
  end

  function self.key()
    local key = { self.message[1], self.message[2], scroll, picked }
    for _, rc in ipairs(recipes) do key[#key + 1] = canChain(rc, counts) end
    for _, q in ipairs(requests) do key[#key + 1] = table.concat({ q.key, q.made, q.count, q.state or "" }, "/") end
    for _, m in ipairs(machines) do key[#key + 1] = table.concat({ m.title, m.state or "" }, "/") end
    return table.concat(key, "|")
  end

  -- The terminal page, under the factory's tab bar (row 1).
  function self.draw(win, w, h)
    local busy = 0
    for _, m in ipairs(machines) do
      if m.colour == "lime" then busy = busy + 1 end
    end
    screen.put(win, 2, 2, screen.fit(("%d infuser%s, %d working"):format(#machines, #machines == 1 and "" or "s", busy), w - 2),
      "lightGray")
    -- the message takes a second line rather than being cut off
    local footer = {}
    for _, line in ipairs(screen.wrap(self.message[1], w, 2)) do footer[#footer + 1] = { line, self.message[2] } end
    footer[#footer + 1] = { w >= 50 and "Arrows pick. Enter +1, 8 +8, 6 +64. X cancels last" or "Enter +1, 8 +8, 6 +64, X cancels",
      "gray" }
    drawRequests(win, w, h, "terminal", footer)
  end

  -- The monitor's Infuse page: the same, to tap.
  self.monitorPage = { title = "Infuse",
    key = function() return self.key() end,
    draw = function(win, w, h) drawRequests(win, w, h, "monitor", {}) end,
  }

  function self.tiles()
    local tiles = {}
    for _, m in ipairs(machines) do
      local text = m.tile == "red" and m.state or m.request and m.request.recipe.title or m.state or "idle"
      tiles[#tiles + 1] = { m.title, text, m.tile or "lime" }
    end
    return tiles
  end

  local function act(a)
    if a.add then
      request(a.add, a.n * a.add.count)
      tell(("Asked for %d %s."):format(a.n * a.add.count, a.add.title), "lime")
    elseif a.scroll then
      scroll = math.max(0, scroll + a.scroll)
      picked = math.max(1, math.min(#recipes, picked + a.scroll)) -- else the terminal snaps back to it
    elseif a.cancel then
      local q = files.read(a.cancel)
      if fs.exists(a.cancel) then fs.delete(a.cancel) end
      if type(q) == "table" and q.job then
        q.ok, q.why = false, "cancelled at the infuser"
        report(q)
      end
      for i = #requests, 1, -1 do
        local x = requests[i]
        if x.file == a.cancel then table.remove(requests, i) end
        if type(q) == "table" and x.parent and x.parent == q.at then
          fs.delete(x.file)
          table.remove(requests, i)
        end
      end
      tell("Cancelled.", "lime")
      f.wake()
    end
  end

  local function tap(target, x, y)
    for _, z in ipairs(zones[target] or {}) do
      if y == z[3] and x >= z[1] and x <= z[2] then
        act(z[4])
        return true
      end
    end
    return false
  end

  -- A tap on the monitor's Infuse page.
  function self.monitorPage.touch(x, y) return tap("monitor", x, y) end

  -- Keys, scrolling and clicks while its page is showing.
  function self.event(ev, x, y)
    local e = ev[1]
    -- the arrows move the picked recipe; Enter, 8 and 6 ask for it, as +1, +8 and +64 do
    if e == "key" and ev[2] == keys.up then picked = math.max(1, picked - 1)
    elseif e == "key" and ev[2] == keys.down then picked = math.min(#recipes, picked + 1)
    elseif e == "key" and ev[2] == keys.pageUp then picked = math.max(1, picked - 8)
    elseif e == "key" and ev[2] == keys.pageDown then picked = math.min(#recipes, picked + 8)
    elseif e == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) and recipes[picked] then
      act({ add = recipes[picked], n = 1 })
    elseif e == "char" and (ev[2] == "8" or ev[2] == "6") and recipes[picked] then
      act({ add = recipes[picked], n = ev[2] == "8" and 8 or 64 })
    elseif e == "char" and ev[2]:lower() == "x" and #requests > 0 then
      -- the newest one asked for (not one a request asked for itself: that's asked for again), with what it asked for
      local last
      for _, q in ipairs(requests) do
        if not q.parent then last = q end
      end
      if last then act({ cancel = last.file }) end
    elseif e == "mouse_scroll" then picked = math.max(1, math.min(#recipes, picked + ev[2]))
    elseif x then tap("terminal", x, y)
    end
    return false
  end

  ---------------------------------------------------------------- commands

  -- A recipe by number (as listed) or by part of its name.
  local function find(text)
    local n = tonumber(text)
    if n then return recipes[n] end
    text = text:lower()
    for _, rc in ipairs(recipes) do
      if rc.title:lower():find(text, 1, true) or rc.make:find(text, 1, true) then return rc end
    end
    return nil
  end

  -- 'factory infuse [what count | cancel [n]]'. True if args was it.
  function self.command(args)
    if args[1] ~= "infuse" then return false end
    local queued = loadRequests()
    if args[2] == "cancel" then
      local n = tonumber(args[3] or "")
      local gone = {}
      for i, q in ipairs(queued) do
        if not n or n == i then
          fs.delete(q.file)
          if q.job then
            q.ok, q.why = false, "cancelled at the infuser"
            report(q)
          end
          gone[#gone + 1] = q
        end
      end
      print(#gone > 0 and ("Cancelled %d request(s)."):format(#gone) or "Nothing to cancel.")
      f.wake()
      return true
    end
    local count = tonumber(args[#args] or "")
    if args[2] and count and #args >= 3 then
      local rc = find(table.concat(args, " ", 2, #args - 1))
      if not rc then
        print("No infusing recipe called that: 'factory infuse' lists them.")
        return true
      end
      -- whole goes: 4 bronze at a time
      local wanted = math.ceil(count / rc.count) * rc.count
      request(rc, wanted)
      print(("Asked for %d %s. It starts on the factory's next round."):format(wanted, rc.title))
      return true
    end
    local reply = f.ask({ type = "stock" })
    local stock = reply and type(reply.counts) == "table" and reply.counts or nil
    for i, rc in ipairs(recipes) do
      local n, missing = 0, nil
      if stock then n, missing = canChain(rc, stock) end
      print(("%2d  %-19s %s%s + %s%s"):format(i, rc.title, rc.per > 1 and (rc.per .. " ") or "", nice(rc.from[1]),
        rc.infuse:gsub("_", " "), stock and (n > 0 and (", can make %d"):format(n) or (", needs " .. missing)) or ""))
    end
    if not stock then print("(The storage computer didn't answer, so no counts.)") end
    for i, q in ipairs(queued) do
      print(("Request %d: %s %d/%d%s"):format(i, q.recipe and q.recipe.title or q.key, q.made, q.count,
        q.job and " (for the craft overseer)" or ""))
    end
    print("Usage: factory infuse <number or name> <count>, factory infuse cancel [n]")
    return true
  end

  return self
end

return M
