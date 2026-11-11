-- The factory's smelter (factory.lua loads it). Keeps every furnace, blast
-- furnace and smoker this computer owns busy: ores and raw metals in
-- storage go into the furnaces and blast furnaces, raw food into the smokers
-- and furnaces, fuel comes from the storage computer's fuel chest, and
-- what's smelted goes back into storage through its input chest. Ores an
-- enricher (here or on another factory computer) takes are left to it, and
-- their dust smelted instead.
--
-- Everything else is smelted on request (RECIPES below, plus config's):
-- stone from cobblestone, glass from sand, charcoal from logs (it ends up in
-- the fuel chest), bricks, smooth stone, ingots, cooked food... Requests come
-- from the Smelter page (C, S, G), 'factory smelt', or the craft overseer:
-- it's told what can be smelted here (makes, via = "smelt"), so a crafting
-- plan or a craft terminal order that needs stone has cobblestone smelted
-- first, and anything that asks the storage system for stone (a builder
-- turtle's deliver) gets it made. Each request is a file in REQUEST_DIR, so
-- it carries on after a reboot, and the overseer hears when it's done.
--
-- Mekanism Energized Smelters and Smelting Factories work too, fed through a
-- hopper or barrel like the enricher's chambers (lib/mekfeed.lua), and get
-- first pick of what there is to smelt. They need no fuel, eject what they
-- make into the chest under them (an output chest emptied into storage, or a
-- storage input chest). With an output chest they work on requests too,
-- ahead of the furnaces: what's emptied from it is counted.
--
-- Create fans (bulk blasting through lava, bulk smoking through fire)
-- aren't peripherals: a fan line is a feeder chest a funnel empties onto a
-- belt past the fan, and the chest at the belt's end (lib/mekfeed.lua
-- lines). They're loaded with the Mekanism smelters, blasting fans with
-- ores and dust, smoking fans with food, and shown red when their feeder
-- stops going down. They take no part in requests.
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
local REQUEST_DIR = "/.factory_smelt" -- a file per request, so one made in another tab or by the overseer is never lost
-- Orders saved before requests: kind -> file. Turned into requests on start.
local OLD_ORDERS = { charcoal = "/.smelter_job", stone = "/.smelter_stone", glass = "/.smelter_glass" }
local GIVE_UP = 600 -- seconds a craft overseer's request may wait with nothing to smelt before it's handed back
local MAKES_EVERY = 60 -- seconds between telling the craft overseer what can be smelted here
local ORDER_LINES = 3 -- requests listed on the Smelter page

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function contains(list, name)
  for _, x in ipairs(list) do
    if x == name then return true end
  end
  return false
end

-- A furnace's name on screen: "Furnace 3", "Blast furnace 0" ("Blast 0" short, for a tile).
local function furnaceTitle(fu, short)
  local t = nice(fu.name)
  if short then t = t:gsub("^blast furnace", "blast") end
  return (t:gsub("^%l", string.upper))
end

-- Logs and wood (bark on all sides) of every tree burn into charcoal;
-- nether stems don't, and aren't called logs.
local function isWood(name) return (name:find("_log$") or name:find("_wood$")) ~= nil end

-- Vanilla's logs, for the craft overseer (here any log or wood burns: isWood).
local LOGS = {}
for _, wood in ipairs({ "oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "pale_oak" }) do
  for _, form in ipairs({ "%s_log", "%s_wood", "stripped_%s_log", "stripped_%s_wood" }) do
    LOGS[#LOGS + 1] = "minecraft:" .. form:format(wood)
  end
end

-- What can be requested: make (one) from one of from. kind: where it can
-- smelt besides plain furnaces and Mekanism smelters ("ore": blast furnaces
-- too, "food": smokers too). what: how the screen speaks of from. Items a
-- world doesn't have (a mod's) are never stored, so never planned with.
local RECIPES = {
  { title = "Stone", make = "minecraft:stone", from = { "minecraft:cobblestone" } },
  { title = "Glass", make = "minecraft:glass", from = { "minecraft:sand", "minecraft:red_sand" }, what = "sand" },
  { title = "Charcoal", make = "minecraft:charcoal", from = LOGS, isInput = isWood, what = "logs" },
  { title = "Smooth stone", make = "minecraft:smooth_stone", from = { "minecraft:stone" } },
  { title = "Deepslate", make = "minecraft:deepslate", from = { "minecraft:cobbled_deepslate" } },
  { title = "Brick", make = "minecraft:brick", from = { "minecraft:clay_ball" } },
  { title = "Terracotta", make = "minecraft:terracotta", from = { "minecraft:clay" } },
  { title = "Nether brick", make = "minecraft:nether_brick", from = { "minecraft:netherrack" } },
  { title = "Cracked stone bricks", make = "minecraft:cracked_stone_bricks", from = { "minecraft:stone_bricks" } },
  { title = "Cracked deepslate bricks", make = "minecraft:cracked_deepslate_bricks", from = { "minecraft:deepslate_bricks" } },
  { title = "Cracked deepslate tiles", make = "minecraft:cracked_deepslate_tiles", from = { "minecraft:deepslate_tiles" } },
  { title = "Cracked nether bricks", make = "minecraft:cracked_nether_bricks", from = { "minecraft:nether_bricks" } },
  { title = "Cracked blackstone bricks", make = "minecraft:cracked_polished_blackstone_bricks",
    from = { "minecraft:polished_blackstone_bricks" } },
  { title = "Smooth sandstone", make = "minecraft:smooth_sandstone", from = { "minecraft:sandstone" } },
  { title = "Smooth red sandstone", make = "minecraft:smooth_red_sandstone", from = { "minecraft:red_sandstone" } },
  { title = "Smooth quartz", make = "minecraft:smooth_quartz", from = { "minecraft:quartz_block" } },
  { title = "Smooth basalt", make = "minecraft:smooth_basalt", from = { "minecraft:basalt" } },
  { title = "Green dye", make = "minecraft:green_dye", from = { "minecraft:cactus" } },
  { title = "Lime dye", make = "minecraft:lime_dye", from = { "minecraft:sea_pickle" } },
  { title = "Sponge", make = "minecraft:sponge", from = { "minecraft:wet_sponge" } },
  { title = "Popped chorus fruit", make = "minecraft:popped_chorus_fruit", from = { "minecraft:chorus_fruit" } },
  { title = "Iron ingot", make = "minecraft:iron_ingot", kind = "ore", from = { "minecraft:raw_iron", "mekanism:dust_iron",
    "minecraft:iron_ore", "minecraft:deepslate_iron_ore" } },
  { title = "Gold ingot", make = "minecraft:gold_ingot", kind = "ore", from = { "minecraft:raw_gold", "mekanism:dust_gold",
    "minecraft:gold_ore", "minecraft:deepslate_gold_ore", "minecraft:nether_gold_ore" } },
  { title = "Copper ingot", make = "minecraft:copper_ingot", kind = "ore", from = { "minecraft:raw_copper",
    "mekanism:dust_copper", "minecraft:copper_ore", "minecraft:deepslate_copper_ore" } },
  { title = "Netherite scrap", make = "minecraft:netherite_scrap", kind = "ore", from = { "minecraft:ancient_debris" } },
  { title = "Osmium ingot", make = "mekanism:ingot_osmium", kind = "ore", from = { "mekanism:raw_osmium",
    "mekanism:dust_osmium", "mekanism:osmium_ore", "mekanism:deepslate_osmium_ore" } },
  { title = "Tin ingot", make = "mekanism:ingot_tin", kind = "ore", from = { "mekanism:raw_tin", "mekanism:dust_tin",
    "mekanism:tin_ore", "mekanism:deepslate_tin_ore" } },
  { title = "Lead ingot", make = "mekanism:ingot_lead", kind = "ore", from = { "mekanism:raw_lead", "mekanism:dust_lead",
    "mekanism:lead_ore", "mekanism:deepslate_lead_ore" } },
  { title = "Uranium ingot", make = "mekanism:ingot_uranium", kind = "ore", from = { "mekanism:raw_uranium",
    "mekanism:dust_uranium", "mekanism:uranium_ore", "mekanism:deepslate_uranium_ore" } },
  { title = "Steak", make = "minecraft:cooked_beef", kind = "food", from = { "minecraft:beef" } },
  { title = "Cooked porkchop", make = "minecraft:cooked_porkchop", kind = "food", from = { "minecraft:porkchop" } },
  { title = "Cooked chicken", make = "minecraft:cooked_chicken", kind = "food", from = { "minecraft:chicken" } },
  { title = "Cooked mutton", make = "minecraft:cooked_mutton", kind = "food", from = { "minecraft:mutton" } },
  { title = "Cooked rabbit", make = "minecraft:cooked_rabbit", kind = "food", from = { "minecraft:rabbit" } },
  { title = "Cooked cod", make = "minecraft:cooked_cod", kind = "food", from = { "minecraft:cod" } },
  { title = "Cooked salmon", make = "minecraft:cooked_salmon", kind = "food", from = { "minecraft:salmon" } },
  { title = "Baked potato", make = "minecraft:baked_potato", kind = "food", from = { "minecraft:potato" } },
  { title = "Dried kelp", make = "minecraft:dried_kelp", kind = "food", from = { "minecraft:kelp" } },
}

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
  local HIDE = config.hide or {} -- recipes (by what they make) not to offer
  local OFFER = config.offer ~= false -- tell the craft overseer what can be smelted here

  -- the recipes: the ones above, then config's own (one for the same item
  -- takes its place), less the hidden ones
  local recipes, byKey = {}, {}
  for _, list in ipairs({ RECIPES, config.recipes or {} }) do
    for _, r in ipairs(list) do
      if type(r) == "table" and type(r.make) == "string" and type(r.from) == "table" and #r.from > 0 then
        r.key = r.make
        r.title = r.title or (nice(r.make):gsub("^%l", string.upper))
        r.what = r.what or nice(r.from[1])
        local old = byKey[r.key]
        if old then
          for i, x in ipairs(recipes) do
            if x == old then recipes[i] = r end
          end
        else
          recipes[#recipes + 1] = r
        end
        byKey[r.key] = r
      end
    end
  end
  for i = #recipes, 1, -1 do
    if contains(HIDE, recipes[i].make) then
      byKey[recipes[i].key] = nil
      table.remove(recipes, i)
    end
  end

  local self = { id = "smelt", title = "Smelter", short = "Smelt", rank = 2, every = 10,
    what = "Ores, dust, food -> ingots, cooked food" }
  local furnaces = {} -- what the screen shows: { name, blast, input, fuel, output } per furnace
  local meks = {} -- the Mekanism smelters and fans (lib/mekfeed.lua), for the screen too
  local stock -- the storage computer's last answer to 'stock'
  local requests = {} -- every request, oldest first (REQUEST_DIR): { key, count, loaded, made, at, item, job, recipe, file }
  local progress = {} -- request at -> when it last had something loaded or made (os.clock)
  local makesKey, makesAt, makesNote, offered = nil, -math.huge, nil, false
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

  ---------------------------------------------------------------- requests

  -- Is name something rc smelts from?
  local function inputOf(rc, name)
    if rc.isInput then return rc.isInput(name) end
    return contains(rc.from, name)
  end

  local function loadRequests()
    local list = {}
    if fs.isDir(REQUEST_DIR) then
      for _, file in ipairs(fs.list(REQUEST_DIR)) do
        local q = files.read(REQUEST_DIR .. "/" .. file)
        if type(q) == "table" and type(q.count) == "number" and type(q.key) == "string" then
          q.file = REQUEST_DIR .. "/" .. file
          q.made, q.loaded = q.made or 0, q.loaded or 0
          q.recipe = byKey[q.key]
          list[#list + 1] = q
        end
      end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    return list
  end

  local function plain(q)
    return { key = q.key, count = q.count, loaded = q.loaded, made = q.made, at = q.at, item = q.item, job = q.job,
      done = q.done, ok = q.ok, why = q.why }
  end

  -- Only while its file is there: a request cancelled in another tab stays cancelled.
  local function saveRequest(q)
    if fs.exists(q.file) then files.write(q.file, plain(q)) end
  end

  -- item: the input to use (or part of its name: "spruce" logs), nil for any.
  -- job: the craft overseer's job id, for one of its plans.
  local function newRequest(key, count, job, item, made, loaded)
    if not fs.isDir(REQUEST_DIR) then fs.makeDir(REQUEST_DIR) end
    local at = os.epoch("utc")
    local file = ("%s/%.0f"):format(REQUEST_DIR, at)
    while fs.exists(file) do
      at = at + 1
      file = ("%s/%.0f"):format(REQUEST_DIR, at)
    end
    files.write(file, { key = key, count = count, made = made or 0, loaded = loaded or 0, at = at, job = job, item = item })
    f.wake()
    return file
  end

  -- Ask for count more of what a recipe makes: added to a request of yours
  -- for it (from the same input) that's still going, else a new one. The
  -- request's count.
  local function request(rc, count, item)
    for _, q in ipairs(loadRequests()) do
      if q.key == rc.key and not q.job and not q.done and q.item == item then
        q.count = q.count + count
        saveRequest(q)
        f.wake()
        return q.count
      end
    end
    newRequest(rc.key, count, nil, item)
    return count
  end

  -- A request from the craft overseer is finished (or given up on): tell
  -- it. True once it has heard (one of yours needs no telling).
  local function tellOverseer(q)
    if not q.job then return true end
    return f.craft({ type = "jobdone", job = q.job, ok = q.ok, why = q.why }, 5) ~= nil
  end

  local function cancelRequest(q, why)
    if fs.exists(q.file) then files.delete(q.file) end
    if q.job then
      q.ok, q.why = false, why or "cancelled at the factory"
      tellOverseer(q)
    end
  end

  -- Orders saved before requests carry on as requests.
  for kind, file in pairs(OLD_ORDERS) do
    local t = files.read(file)
    if type(t) == "table" and type(t.count) == "number" then
      newRequest("minecraft:" .. kind, t.count, nil, t.item or t.wood, t.made, t.loaded)
    end
    if fs.exists(file) then files.delete(file) end
  end

  -- The input a request smelts this round: the one it names (or whose name
  -- has it in, for "spruce" logs), else whichever there's most of, so it
  -- carries on with another when one runs out.
  local function pick(q, counts)
    local rc = q.recipe
    local exact = q.item and inputOf(rc, q.item)
    local best, most = nil, 0
    local function try(name, n)
      local fits = not q.item or (exact and name == q.item) or (not exact and name:find(q.item, 1, true))
      if fits and n > most and inputOf(rc, name) and not noSmelt["furnace:" .. name] then best, most = name, n end
    end
    if rc.isInput then
      for name, n in pairs(counts) do try(name, n) end
    else
      for _, name in ipairs(rc.from) do try(name, counts[name] or 0) end
    end
    return best
  end

  -- Count what came out of the furnaces and output chests towards the
  -- requests, oldest first (what was smelted anyway counts too).
  local function credit(byName)
    if not byName then return end
    for _, q in ipairs(requests) do
      if not q.done and q.recipe then
        local n = math.min(byName[q.key] or 0, q.count - q.made)
        if n > 0 then
          q.made = q.made + n
          byName[q.key] = byName[q.key] - n
          progress[q.at] = os.clock()
        end
      end
    end
  end

  -- How the screen and messages speak of what a request smelts.
  local function fromText(q)
    if q.item then return nice(q.item) end
    return q.recipe and q.recipe.what or "it"
  end

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
  -- requests, since what comes out of that chest is counted. Not one that
  -- ejects straight into storage, nor a Create fan (blasting is ores only).
  local function forOrders(m) return not m.line and m.entry.output ~= nil end

  -- A recipe's input or what it makes is still in a Mekanism smelter: its
  -- feeder, its slots, or its output chest (stuck there, not counted yet).
  local function mekBusyWith(m, rc)
    if not forOrders(m) then return false end
    for _, s in pairs(m.feedList) do
      if inputOf(rc, s.name) then return true end
    end
    for i = 1, m.slots do
      local a, b = m.inputs[i], m.outputs[i]
      if (a and inputOf(rc, a.name)) or (b and b.name == rc.make) then return true end
    end
    for _, s in pairs(m.outList) do
      if s.name == rc.make then return true end
    end
    return false
  end

  -- Something's still smelting for a request.
  local function burningFor(q)
    for _, fu in ipairs(furnaces) do
      if fu.input and inputOf(q.recipe, fu.input.name) then return true end
    end
    for _, m in ipairs(meks) do
      if mekBusyWith(m, q.recipe) then return true end
    end
    return false
  end

  -- Which kinds of recipe the furnaces here can smelt: plain (everything:
  -- plain furnaces, Mekanism smelters with an output chest), ore (blast
  -- furnaces), food (smokers).
  local function machineKinds()
    local can = {}
    for _, fu in ipairs(furnaces) do
      if fu.blast then can.ore = true elseif fu.smoker then can.food = true else can.plain = true end
    end
    for _, m in ipairs(meks) do
      if forOrders(m) then can.plain = true end
    end
    return can
  end

  local function canSmelt(rc, can) return can.plain or (rc.kind ~= nil and can[rc.kind]) end

  ---------------------------------------------------------------- the craft overseer

  -- The recipes as the craft overseer plans them: one of the input in, one
  -- out. Only what the furnaces here can smelt.
  local function asCrafts()
    local out, can = {}, machineKinds()
    for _, rc in ipairs(recipes) do
      if canSmelt(rc, can) then
        out[#out + 1] = { make = rc.make, count = 1, rows = { "A" }, keys = { A = #rc.from == 1 and rc.from[1] or rc.from } }
      end
    end
    return out
  end

  -- Tell the craft overseer what can be smelted here when it changes and
  -- every so often, as it forgets in time. A factory computer with no
  -- furnaces says nothing, unless it offered some before.
  local function offer()
    if not OFFER then return end
    local crafts = asCrafts()
    if #crafts == 0 and not offered then return end
    local key = tostring(#crafts)
    for _, c in ipairs(crafts) do key = key .. "," .. c.make end
    if (key == makesKey or makesKey == "retry") and os.clock() - makesAt < MAKES_EVERY then return end
    local reply = f.craft({ type = "makes", via = "smelt", recipes = crafts }, 5)
    makesAt = os.clock()
    if reply and reply.ok then
      makesKey, makesNote, offered = key, nil, #crafts > 0
    else
      -- tried again in a minute; no overseer at all is nothing to warn about
      -- (the smelter works without one), an old one is
      makesKey = "retry"
      makesNote = reply and (reply.error or "the craft overseer doesn't take smelting orders: update it") or nil
    end
  end

  -- From the craft overseer (factory protocol): 'smelt' (make this for one
  -- of my crafting plans) and 'cancel'. The reply, or nil if it isn't one.
  function self.request(_, msg)
    if msg.type == "smelt" then
      if not self.active() then return { ok = false, why = "no furnaces here" } end
      local rc = byKey[msg.make]
      local item
      for _, x in pairs(type(msg.grid) == "table" and msg.grid or {}) do
        if type(x) == "string" then item = item or x end
      end
      local count = math.floor(tonumber(msg.count) or 0)
      if not rc or count < 1 or (item and not inputOf(rc, item)) then
        return { ok = false, why = "this factory has no smelting recipe for it" }
      end
      newRequest(rc.key, count, msg.job, item)
      return { ok = true }
    elseif msg.type == "cancel" then
      for _, q in ipairs(loadRequests()) do
        if q.job and q.job == msg.job then files.delete(q.file) end
      end
      f.wake()
      return { ok = true }
    end
    return nil
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
    requests = loadRequests()
    collected, outStuck, outWhy, made = false, false, nil, nil
    if remote then
      local _
      _, outStuck, outWhy, made = self.set:collect(meks, remoteInput)
      credit(made)
      collected = true
    end
  end

  -- r: the factory's round: stock (the storage computer's answer to
  -- 'stock'), useWork, input, unsure (feeders the storage computer hasn't
  -- taken yet), feedProblem.
  function self.round(r)
    offer()
    if #furnaces == 0 and #meks == 0 then
      say("No furnaces yet: join them to the cable with wired modems, or add a Mekanism smelter or Create fan.", "orange")
      status("waiting", "no furnaces")
      return
    end
    stock = r.stock
    local work = f.work
    local useWork = r.useWork
    local counts, input = stock.counts, r.input

    -- what's smelted goes back through the input chest (charcoal is put in
    -- the fuel chest from there)
    local blocked, problem = false, nil
    for _, fu in ipairs(furnaces) do
      if fu.output then
        local ok, moved = pcall(peripheral.call, fu.name, "pushItems", input, 3)
        if not ok then problem, moved = tostring(moved), 0 end
        if moved > 0 then credit({ [fu.output.name] = moved }) end
        fu.output.count = fu.output.count - moved
        if fu.output.count > 0 then blocked = true else fu.output = nil end
      end
    end
    -- and the Mekanism smelters' and fans' output chests, before the
    -- requests are checked below (what they made counts too)
    if not collected then
      local _
      _, outStuck, outWhy, made = self.set:collect(meks, input)
      credit(made)
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

    -- each request: done once it's made. Once nothing's smelting for it
    -- (every input was read before its output was emptied, so everything
    -- made from finished inputs has been counted): all of it loaded but not
    -- all made (put back, or taken) loads the rest again; nothing left to
    -- smelt it from ends one of yours there, and one from the craft overseer
    -- waits for more (GIVE_UP) before it's handed back
    local function finish(q, ok, why)
      q.done, q.ok, q.why = true, ok, why
      local what = q.recipe and q.recipe.title:lower() or nice(q.key)
      if q.job then
        if not ok then tell(("Gave up smelting %s for the craft overseer: %s."):format(what, why), "orange") end
      elseif ok then
        local where = q.key == "minecraft:charcoal" and stock.fuelChest and "the fuel chest" or "storage"
        tell(("Made %d %s. It's in %s."):format(q.made, what, where), "lime")
      else
        tell(("Ran out of %s: made %d of %d %s."):format(fromText(q), q.made, q.count, what), "orange")
      end
      f.log(("smelted %d %s%s"):format(q.made, what, q.job and " for the craft overseer" or ""))
    end
    local orderItems = {} -- the item each request smelts this round, oldest request first
    local byItem = {} -- item -> the requests it's loaded for, oldest first
    for _, q in ipairs(requests) do
      q.state = nil
      if not q.done and not q.recipe then
        finish(q, false, "this factory has no smelting recipe for it any more")
      elseif not q.done then
        progress[q.at] = progress[q.at] or now
        local item = pick(q, counts)
        if q.made >= q.count then
          finish(q, true)
        elseif not burningFor(q) then
          if q.loaded >= q.count then q.loaded = q.made end
          if not item and not q.job then
            finish(q, false)
          elseif not item and now - progress[q.at] > GIVE_UP then
            finish(q, false, ("no %s to smelt it from"):format(fromText(q)))
          elseif not item then
            q.state = "waiting for " .. fromText(q)
          end
        end
        if not q.done and item and q.loaded < q.count then
          if not byItem[item] then
            orderItems[#orderItems + 1] = item
            byItem[item] = {}
          end
          table.insert(byItem[item], q)
        end
      end
    end
    -- finished ones go (a craft overseer's once it has heard)
    local open = {}
    for _, q in ipairs(requests) do
      if q.done then
        saveRequest(q)
        if tellOverseer(q) and fs.exists(q.file) then files.delete(q.file) end
      elseif fs.exists(q.file) then
        open[#open + 1] = q
      end
    end
    requests = open
    -- loads for a request's item count towards its requests, oldest first
    -- (n < 0: taken back off, newest first)
    local function addLoaded(name, n)
      local list = byItem[name]
      if not list or n == 0 then return end
      if n > 0 then
        for _, q in ipairs(list) do
          local k = math.min(n, q.count - q.loaded)
          if k > 0 then
            q.loaded, n = q.loaded + k, n - k
            progress[q.at] = now
          end
        end
      else
        for i = #list, 1, -1 do
          local q = list[i]
          local k = math.min(-n, q.loaded)
          q.loaded, n = q.loaded - k, n + k
        end
      end
    end

    -- what to load: every ore and raw food in storage (less what config.lua
    -- keeps, like potatoes for planting, and what an enricher takes), and
    -- what the requests still need
    local want, kinds = {}, {}
    for name, n in pairs(counts) do
      local kind = n > 0 and not f.leave(self.rank, name) and smeltKind(name)
      if kind then
        kinds[name] = kind
        if n > (KEEP[name] or 0) then want[name] = n - (KEEP[name] or 0) end
      end
    end
    for item, list in pairs(byItem) do
      local need = 0
      for _, q in ipairs(list) do need = need + q.count - q.loaded end
      want[item] = math.max(want[item] or 0, math.min(counts[item] or 0, need))
      kinds[item] = kinds[item] or list[1].recipe.kind
    end
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
        addLoaded(name, got)
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
          addLoaded(pick, n)
        elseif n > 0 then
          local reply = f.ask({ type = "send", to = m.entry.feeder, items = { [pick] = n } })
          local got = reply and reply.sent and reply.sent[pick] or 0
          if reply and reply.error then problem = reply.error end
          mekfeed.added(m, pick, got)
          want[pick] = want[pick] - got
          addLoaded(pick, got)
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
          addLoaded(p.name, -short)
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
        addLoaded(p.name, got - p.n)
        if got > 0 then loaded, into = loaded + got, into + 1 end
      end
      work:empty(input)
    end

    for _, q in ipairs(requests) do saveRequest(q) end

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
      problem = problem .. ". Not on the storage cable? Setup, Items come and go"
    end
    -- stone, glass and the like only smelt in plain furnaces and Mekanism
    -- smelters with an output chest (blast furnaces, smokers and fans never
    -- take them): a request none of the furnaces here can take
    local can, stuckOn = machineKinds(), nil
    for _, q in ipairs(requests) do
      if not stuckOn and q.recipe and not canSmelt(q.recipe, can) then stuckOn = q end
    end
    if problem then
      say("Couldn't move items: " .. problem, "red")
    elseif news and os.clock() < news[3] then
      say(news[1], news[2])
    elseif blocked then
      say(work.remote and "The ender chest is full: smelted items are waiting in the furnaces."
        or "The storage input chest is full: smelted items are waiting in the furnaces.", "orange")
    elseif stuckOn then
      say(("%s needs a plain furnace or a Mekanism smelter with an output chest: add one."):format(stuckOn.recipe.title),
        "orange")
    elseif work.problem then
      say(("Not using the work chest: %s."):format(work.problem), "orange")
    elseif unfuelled then
      -- the storage computer's reason, when it gave one
      say(type(unfuelled) == "string" and ("No fuel came: %s."):format(unfuelled)
        or "Out of fuel: put coal or charcoal in the fuel chest.", "orange")
    elseif loaded > 0 then
      say(("Loaded %d items into %d furnaces."):format(loaded, into))
    elseif makesNote and busy == 0 then
      say(makesNote, "orange")
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
    for i, q in ipairs(requests) do
      if i > ORDER_LINES then
        lines[#lines] = ("...and %d more requests"):format(#requests - ORDER_LINES + 1)
        break
      end
      lines[#lines + 1] = ("%s: %d of %d from %s%s%s"):format(q.recipe and q.recipe.title or nice(q.key), q.made, q.count,
        fromText(q), q.job and " (overseer)" or "", q.state and (", " .. q.state) or "")
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
    if #lines == 0 then put(1, base, fit(" No requests.", w), "gray") end
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

  ---------------------------------------------------------------- requests from the keyboard

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

  -- Ask for count of a recipe's item, and say so.
  local function ask(rc, n, item)
    local total = request(rc, n, item)
    requests = loadRequests()
    if total > n then
      say(("Asked for %d more %s: %d in all."):format(n, rc.title:lower(), total), "lightBlue")
    else
      say(("Making %d %s from %s."):format(n, rc.title:lower(), item and nice(item) or rc.what), "lightBlue")
    end
  end

  -- Ask which logs to burn and how much charcoal to make, from what the
  -- storage computer last said it holds.
  local function charcoalPrompt()
    local rc = byKey["minecraft:charcoal"]
    if not rc then return end
    local _, h = term.getSize()
    promptScreen()
    local woods = {}
    for name, n in pairs(stock and stock.counts or {}) do
      if inputOf(rc, name) and n > 0 then woods[#woods + 1] = { name = name, n = n } end
    end
    table.sort(woods, function(a, b) return a.n > b.n end)
    if #woods == 0 then
      print(stock and "There are no logs in storage to make charcoal from." or "The storage computer hasn't answered yet.")
      anyKey()
      return
    end
    print("Make charcoal from which logs?")
    for i = 1, math.min(#woods, h - 4) do
      print(("%2d  %-26s %d"):format(i, nice(woods[i].name), woods[i].n))
    end
    write(("Which? [1 = %s] "):format(nice(woods[1].name)))
    local text = read()
    local pick = woods[text == "" and 1 or tonumber(text)]
    if not pick then return end
    write(("How much charcoal? (up to %d, Enter to cancel) "):format(pick.n))
    local n = tonumber(read())
    if not n or n < 1 then return end
    ask(rc, math.floor(n), pick.name)
  end

  -- Ask how much of a recipe's item (stone, glass) to make from what's in
  -- storage. item: what it's made from, nil for any of its inputs.
  local function amountPrompt(key, item)
    local rc = byKey[key]
    if not rc then return end
    promptScreen()
    local have = 0
    for name, n in pairs(stock and stock.counts or {}) do
      if inputOf(rc, name) and (not item or name == item) then have = have + n end
    end
    if have == 0 then
      print(stock and ("There's no %s in storage to make %s from."):format(rc.what, rc.title:lower())
        or "The storage computer hasn't answered yet.")
      anyKey()
      return
    end
    write(("How much %s? (up to %d, Enter to cancel) "):format(rc.title:lower(), have))
    local n = tonumber(read())
    if not n or n < 1 then return end
    ask(rc, math.floor(n), item)
  end

  local function cancelled(q)
    return ("%s request cancelled. What's already in furnaces still smelts."):format(q.recipe and q.recipe.title or nice(q.key))
  end

  -- Cancel the one request there is, or ask which when there are more.
  local function cancelPrompt()
    local list = loadRequests()
    if #list == 0 then return end
    local q = list[1]
    if #list > 1 then
      promptScreen()
      print("Cancel which request?")
      for i = 1, math.min(#list, 9) do
        local x = list[i]
        print(("  %d  %s (%d of %d made)%s"):format(i, x.recipe and x.recipe.title or nice(x.key), x.made, x.count,
          x.job and " for the craft overseer" or ""))
      end
      print("  any other key: none")
      local _, c = os.pullEvent("char")
      q = list[tonumber(c) or 0]
      if not q then return end
    end
    cancelRequest(q)
    requests = loadRequests()
    say(cancelled(q))
  end

  -- An event while its page is showing: true if it took over the terminal
  -- (a prompt), so the page is drawn again in full.
  function self.event(ev)
    -- char, not key: read() in the prompt would otherwise get the "c" too
    local a = ev[1] == "char" and ev[2]:lower()
    if a == "c" then charcoalPrompt()
    elseif a == "s" then amountPrompt("minecraft:stone", "minecraft:cobblestone")
    elseif a == "g" then amountPrompt("minecraft:glass", nil)
    elseif a == "x" then cancelPrompt()
    else return false end
    return true
  end

  ---------------------------------------------------------------- commands

  -- A recipe by number (as 'factory smelt' lists them) or by part of its name.
  local function find(text)
    local n = tonumber(text)
    if n then return recipes[n] end
    text = text:lower()
    for _, rc in ipairs(recipes) do
      if rc.title:lower() == text or rc.make == text then return rc end
    end
    for _, rc in ipairs(recipes) do
      if rc.title:lower():find(text, 1, true) or rc.make:find(text, 1, true) then return rc end
    end
    return nil
  end

  local function asked(rc, n, item)
    local total = request(rc, n, item)
    print(("%s request saved: %d from %s%s."):format(rc.title, n, item and nice(item) or rc.what,
      total > n and (" (%d in all)"):format(total) or ""))
  end

  -- The recipes, with how many of each could be made from what's stored.
  local function listRecipes()
    local reply = f.ask({ type = "stock" })
    local counts = reply and type(reply.counts) == "table" and reply.counts or nil
    local lines = {}
    for i, rc in ipairs(recipes) do
      local have = 0
      for name, n in pairs(counts or {}) do
        if inputOf(rc, name) then have = have + n end
      end
      lines[#lines + 1] = ("%2d  %-24s from %s%s"):format(i, rc.title, rc.what, counts and (", %d stored"):format(have) or "")
    end
    if not counts then lines[#lines + 1] = "(The storage computer didn't answer, so no counts.)" end
    for i, q in ipairs(loadRequests()) do
      lines[#lines + 1] = ("Request %d: %s %d/%d%s"):format(i, q.recipe and q.recipe.title or q.key, q.made, q.count,
        q.job and " (for the craft overseer)" or "")
    end
    lines[#lines + 1] = "Usage: factory smelt <number or name> <count>, factory cancel [n or name]"
    textutils.pagedPrint(table.concat(lines, "\n"))
  end

  -- 'factory smelt|charcoal|stone|glass|cancel ...': true if args was one.
  function self.command(args)
    local verb = args[1]
    local n = tonumber(args[2] or "")
    if verb == "smelt" then
      local count = tonumber(args[#args] or "")
      if #args < 3 or not count or count < 1 then
        listRecipes()
        return true
      end
      local rc = find(table.concat(args, " ", 2, #args - 1))
      if not rc then
        print("No smelting recipe called that: 'factory smelt' lists them.")
        return true
      end
      asked(rc, math.floor(count))
    elseif verb == "charcoal" then
      if not n or n < 1 or not byKey["minecraft:charcoal"] then
        print("Usage: factory charcoal <how many> [wood, e.g. spruce]")
        return true
      end
      local wood = #args >= 3 and table.concat(args, "_", 3):lower() or nil
      asked(byKey["minecraft:charcoal"], math.floor(n), wood)
    elseif verb == "stone" then
      if not n or n < 1 or not byKey["minecraft:stone"] then
        print("Usage: factory stone <how many>")
        return true
      end
      asked(byKey["minecraft:stone"], math.floor(n))
    elseif verb == "glass" then
      if not n or n < 1 or (args[3] and args[3] ~= "red") or not byKey["minecraft:glass"] then
        print("Usage: factory glass <how many> [red]")
        return true
      end
      asked(byKey["minecraft:glass"], math.floor(n), args[3] == "red" and "minecraft:red_sand" or nil)
    elseif verb == "cancel" then
      -- by number (as 'factory smelt' lists them), by name, or all
      local text = #args >= 2 and table.concat(args, " ", 2):lower() or nil
      local gone = 0
      for i, q in ipairs(loadRequests()) do
        local title = q.recipe and q.recipe.title:lower() or q.key
        if not text or (n and n == i) or (not n and (title:find(text, 1, true) or q.key:find(text, 1, true))) then
          cancelRequest(q)
          print(cancelled(q))
          gone = gone + 1
        end
      end
      if gone == 0 then print("No smelting request like that: 'factory smelt' lists them.") end
      f.wake()
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
