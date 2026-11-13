-- The factory's brewer (factory.lua loads it). Runs brewing stands on
-- request: tap +1, +3 or +9 by a potion (on the terminal or the monitor's
-- Brew page) or type 'factory brew <potion> <count>', and it works out the
-- steps from a water bottle (nether wart for awkward, sugar for swiftness,
-- redstone for long, gunpowder for splash, dragon's breath for lingering)
-- and runs them on every stand it has, three bottles a brew.
--
-- Potions are items with extra data, which the storage computer never
-- stores or sends as plain items, so they never go into storage: they live
-- in the potion chest, one chest on the cable the player picks (it's named
-- to the storage computer like a feeder, so it isn't storage). Water bottles
-- go in it (by hand, or from the bottle filler) and every potion comes out
-- into it. Ingredients and blaze powder come from storage, straight into
-- each stand's slots ('send') or through the work chest.
--
-- CC can't read which potion a bottle holds (a long and a strong potion
-- have the same name), so each kind is learnt as it's brewed: a water bottle
-- (by its name, or from the filler) put in with sugar after nether wart is
-- swiftness from then on. Saved in /.factory_brew_names.
--
-- The bottle filler (optional): a dispenser on the cable facing a water
-- source, powered from one side of this computer or a redstone relay. The
-- storage computer puts glass bottles in it, each pulse fills one, and the
-- water bottles go into the potion chest.
--
-- Brewing stands are found by themselves, like furnaces: on the cable with
-- a wired modem each, the earliest factory computer to see one has it.
local screen = require("lib.screen") -- flicker-free drawing
local files = require("lib.files") -- crash-safe save files
local setupui = require("lib.setupui") -- lists of chests on the setup screen

local M = {}

local SETUP_FILE = "/.factory_brew_setup" -- { chest, filler, relay, side }
local NAMES_FILE = "/.factory_brew_names" -- item name#nbt -> potion key ("splash:long_swiftness"), learnt as it's brewed
local STANDS_FILE = "/.factory_brew_stands" -- stand -> { from, to, ing, n, step, req, ids, at }: what's brewing in each
local REQUEST_DIR = "/.factory_brew" -- a file per request, so a request typed in another tab is never lost
local BREW_TIME = 20 -- seconds a brew takes in vanilla
local STUCK_AFTER = 60 -- seconds past BREW_TIME a stand may sit on its ingredient (with fuel) before it's emptied
local FILLER_GLASS = 8 -- glass bottles kept in the filler while water is wanted
local PULSE_ON, PULSE_OFF = 0.2, 0.3 -- seconds the filler's redstone stays on, then off (one bottle a pulse)
local ORDER_EVERY = 30 -- seconds between asking the craft overseer to make a short ingredient
local QUEUE_SHOWN = 3 -- requests listed under the potions
local BUTTONS = { 1, 3, 9 } -- the request buttons by each potion (three bottles a brew)
local SLOT_FUEL, SLOT_INGREDIENT = 5, 4 -- a brewing stand's slots: 1-3 bottles, 4 ingredient, 5 blaze powder
local BLAZE = "minecraft:blaze_powder"
local GLASS = "minecraft:glass_bottle"

---------------------------------------------------------------- the potions

-- Bottles: the three kinds of potion item, each with any contents.
local FORMS = { { "potion", "minecraft:potion" }, { "splash", "minecraft:splash_potion" },
  { "lingering", "minecraft:lingering_potion" } }
local FORM_OF = {} -- item id -> form
for _, fm in ipairs(FORMS) do FORM_OF[fm[2]] = fm[1] end

-- Effects: id, the name after "Potion of", has a long kind (redstone), a
-- strong kind (glowstone), what turns an awkward potion into it.
local EFFECTS = {
  { "swiftness", "Swiftness", true, true, "minecraft:sugar" },
  { "slowness", "Slowness", true, true },
  { "leaping", "Leaping", true, true, "minecraft:rabbit_foot" },
  { "healing", "Healing", false, true, "minecraft:glistering_melon_slice" },
  { "harming", "Harming", false, true },
  { "poison", "Poison", true, true, "minecraft:spider_eye" },
  { "regeneration", "Regeneration", true, true, "minecraft:ghast_tear" },
  { "strength", "Strength", true, true, BLAZE },
  { "fire_resistance", "Fire Resistance", true, false, "minecraft:magma_cream" },
  { "water_breathing", "Water Breathing", true, false, "minecraft:pufferfish" },
  { "night_vision", "Night Vision", true, false, "minecraft:golden_carrot" },
  { "invisibility", "Invisibility", true, false },
  { "weakness", "Weakness", true, false },
  { "turtle_master", "the Turtle Master", true, true, "minecraft:turtle_helmet" },
  { "slow_falling", "Slow Falling", true, false, "minecraft:phantom_membrane" },
  { "wind_charged", "Wind Charging", false, false, "minecraft:breeze_rod" },
  { "weaving", "Weaving", false, false, "minecraft:cobweb" },
  { "oozing", "Oozing", false, false, "minecraft:slime_block" },
  { "infested", "Infestation", false, false, "minecraft:stone" },
}
-- Fermented spider eye: what each turns into.
local FERMENT = { water = "weakness", swiftness = "slowness", long_swiftness = "long_slowness", leaping = "slowness",
  long_leaping = "long_slowness", healing = "harming", strong_healing = "strong_harming", poison = "harming",
  long_poison = "harming", strong_poison = "strong_harming", night_vision = "invisibility",
  long_night_vision = "long_invisibility" }
-- The potions with no effect: their names.
local BASES = { { "water", "Water Bottle" }, { "awkward", "Awkward" }, { "mundane", "Mundane" }, { "thick", "Thick" } }

local contents = {} -- contents id -> { title (by form), suffix }
local contentOrder = {}
for _, b in ipairs(BASES) do
  local id, word = b[1], b[2]
  contents[id] = id == "water"
    and { potion = "Water Bottle", splash = "Splash Water Bottle", lingering = "Lingering Water Bottle", suffix = "" }
    or { potion = word .. " Potion", splash = word .. " Splash Potion", lingering = word .. " Lingering Potion", suffix = "" }
  contentOrder[#contentOrder + 1] = id
end
for _, e in ipairs(EFFECTS) do
  local function add(id, suffix)
    contents[id] = { potion = "Potion of " .. e[2], splash = "Splash Potion of " .. e[2],
      lingering = "Lingering Potion of " .. e[2], suffix = suffix }
    contentOrder[#contentOrder + 1] = id
  end
  add(e[1], "")
  if e[3] then add("long_" .. e[1], " (long)") end
  if e[4] then add("strong_" .. e[1], " II") end
end

-- Every mix, for each form: { from = key, ing = item, to = key }, keys
-- being "<form>:<contents>". Contents mixes first, then form changes, so
-- a splash potion is brewed as a potion and turned splash last.
local mixes = {}
local byFrom = {}
local function mix(from, ing, to)
  local m = { from = from, ing = ing, to = to }
  mixes[#mixes + 1] = m
  byFrom[from] = byFrom[from] or {}
  table.insert(byFrom[from], m)
end
local function contentMix(from, ing, to)
  if contents[from] and contents[to] then
    for _, fm in ipairs(FORMS) do mix(fm[1] .. ":" .. from, ing, fm[1] .. ":" .. to) end
  end
end
contentMix("water", "minecraft:nether_wart", "awkward")
contentMix("water", "minecraft:redstone", "mundane")
contentMix("water", "minecraft:glowstone_dust", "thick")
for _, e in ipairs(EFFECTS) do
  if e[5] then contentMix("awkward", e[5], e[1]) end
end
for from, to in pairs(FERMENT) do contentMix(from, "minecraft:fermented_spider_eye", to) end
for _, e in ipairs(EFFECTS) do
  if e[3] then contentMix(e[1], "minecraft:redstone", "long_" .. e[1]) end
  if e[4] then contentMix(e[1], "minecraft:glowstone_dust", "strong_" .. e[1]) end
end
for _, id in ipairs(contentOrder) do
  mix("potion:" .. id, "minecraft:gunpowder", "splash:" .. id)
  mix("splash:" .. id, "minecraft:dragon_breath", "lingering:" .. id)
end
-- pairs() gave FERMENT's in any order: keep each list the same every time
for _, list in pairs(byFrom) do
  table.sort(list, function(a, b)
    local fa, fb = a.ing == "minecraft:gunpowder" or a.ing == "minecraft:dragon_breath",
      b.ing == "minecraft:gunpowder" or b.ing == "minecraft:dragon_breath"
    if fa ~= fb then return fb end
    return a.to < b.to
  end)
end

-- The shortest way to each potion from a water bottle: key -> { mix, ... }.
local paths = { ["potion:water"] = {} }
do
  local queue, head = { "potion:water" }, 1
  while queue[head] do
    local key = queue[head]
    head = head + 1
    for _, m in ipairs(byFrom[key] or {}) do
      if not paths[m.to] then
        local p = {}
        for i, step in ipairs(paths[key]) do p[i] = step end
        p[#p + 1] = m
        paths[m.to] = p
        queue[#queue + 1] = m.to
      end
    end
  end
end

local function splitKey(key) return key:match("^(%a+):(.+)$") end

local function titleOf(key)
  local form, id = splitKey(key)
  local c = form and contents[id]
  if not c then return key end
  return c[form] .. c.suffix
end

-- Every potion that can be brewed, in the page's order: by form, then base, effect, long, strong.
local ALL = {}
for _, fm in ipairs(FORMS) do
  for _, id in ipairs(contentOrder) do
    local key = fm[1] .. ":" .. id
    if paths[key] and key ~= "potion:water" then ALL[#ALL + 1] = key end
  end
end

-- What a bottle's name says it is, when only one potion has that name
-- (water, awkward, slowness..., not swiftness: its long kind is named the same).
local byDisplay = {}
for _, fm in ipairs(FORMS) do
  for _, id in ipairs(contentOrder) do
    local shown = contents[id][fm[1]]
    byDisplay[shown] = byDisplay[shown] or {}
    table.insert(byDisplay[shown], fm[1] .. ":" .. id)
  end
end

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function escape(name) return "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "$" end

local function capital(text) return (text:gsub("^%l", string.upper)) end

local function idOf(item) return item.name .. "#" .. tostring(item.nbt or "") end

-- Brewing stands on the wired network (not ones touching this computer: the
-- storage computer can't reach those).
local function findStands()
  return setupui.onNetwork(function(t) return t:find("brewing_stand", 1, true) ~= nil end)
end

local function isChest(t)
  return (t:find("chest", 1, true) or t:find("barrel", 1, true)) ~= nil and not t:find("ender", 1, true)
end

-- f: the factory (factory.lua): ask, craft, work, config, mine, wake, changed, taken.
function M.new(f)
  local config = f.config("brewer")
  local FUEL_KEEP = config.fuel or 2 -- blaze powder kept in each stand's fuel slot (one does 20 brews)
  local WATER_KEEP = config.water or 9 -- water bottles the filler keeps in the potion chest
  local KEEP = config.keep or {} -- item -> how many to leave in storage, never brewed with
  local ORDER = config.order ~= false -- have the craft overseer make a short ingredient (blaze powder, glistering melon)

  local self = { id = "brew", title = "Brewer", short = "Brew", rank = 0, every = 5, what = "Requests -> potions" }
  local stands = {} -- this computer's stands, each { name, list, title }
  local chestList = {} -- the potion chest's list()
  local have = {} -- potion key -> bottles in the potion chest
  local unknown = {} -- name shown -> bottles in the potion chest no one knows
  local requests = {} -- every request, oldest first
  local counts = {} -- the storage computer's counts
  local jobs = files.read(STANDS_FILE) or {} -- stand -> what it's brewing
  local names = files.read(NAMES_FILE) or {} -- name#nbt -> potion key
  local looked = {} -- name#nbt -> the name the game shows (asked once each)
  local news -- { text, colour, untilTime }
  local form = "potion" -- the form the page lists
  local scroll, picked = 0, 1
  local zones = {}
  local fill = { want = 0, untilTime = 0 } -- what the filler loop is to do (set each round)
  local orderAt, orderNote = {}, {}
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

  local function readSetup()
    local s = files.read(SETUP_FILE)
    return type(s) == "table" and s or {}
  end
  local function writeSetup(s) files.write(SETUP_FILE, s) end

  local function saveJobs() files.write(STANDS_FILE, jobs) end

  local function learn(id, key)
    if names[id] ~= key then
      names[id] = key
      files.write(NAMES_FILE, names)
    end
  end

  -- What potion a bottle is: learnt, or told by its name when only one has
  -- that name. nil for an empty bottle, anything not a potion, or one not known.
  local function keyOf(item, chest, slot)
    if not FORM_OF[item.name] then return nil end
    local id = idOf(item)
    if names[id] then return names[id] end
    if looked[id] == nil and chest then
      local ok, d = pcall(peripheral.call, chest, "getItemDetail", slot)
      looked[id] = ok and type(d) == "table" and d.displayName or false
    end
    local list = looked[id] and byDisplay[looked[id]]
    if list and #list == 1 then
      learn(id, list[1])
      return list[1]
    end
    return nil
  end

  local function myStands()
    local out = {}
    for _, name in ipairs(findStands()) do
      if f.mine(name) then out[#out + 1] = name end
    end
    return out
  end

  function self.found()
    local out = {}
    for _, name in ipairs(findStands()) do out[#out + 1] = { name = name, kind = "Brewing stand" } end
    return out
  end

  -- Only added things are always this computer's: the potion chest, the
  -- filler and its relay (the stands are found, and claimed).
  function self.uses()
    local s, out = readSetup(), {}
    for _, n in ipairs({ s.chest or false, s.filler or false, s.relay or false }) do
      if n then out[#out + 1] = n end
    end
    return out
  end

  function self.active() return #myStands() > 0 end

  -- For factory.lua's one 'feeders' request: the potion chest isn't storage.
  self.feedSet = { entries = function()
    local s = readSetup()
    return s.chest and { { feeder = s.chest } } or {}
  end }

  ---------------------------------------------------------------- requests

  local function loadRequests()
    local list = {}
    if fs.isDir(REQUEST_DIR) then
      for _, file in ipairs(fs.list(REQUEST_DIR)) do
        local q = files.read(REQUEST_DIR .. "/" .. file)
        if type(q) == "table" and type(q.count) == "number" and type(q.key) == "string" then
          q.file = REQUEST_DIR .. "/" .. file
          q.made = q.made or 0
          list[#list + 1] = q
        end
      end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    return list
  end

  local function saveRequest(q)
    if fs.exists(q.file) then files.write(q.file, { key = q.key, count = q.count, made = q.made, at = q.at }) end
  end

  -- count more of a potion: added to a request for it still waiting, else a new one
  local function request(key, count)
    for _, q in ipairs(loadRequests()) do
      if q.key == key then
        q.count = q.count + count
        saveRequest(q)
        f.wake()
        return
      end
    end
    if not fs.isDir(REQUEST_DIR) then fs.makeDir(REQUEST_DIR) end
    local at = os.epoch("utc")
    local file = ("%s/%.0f"):format(REQUEST_DIR, at)
    while fs.exists(file) do
      at = at + 1
      file = ("%s/%.0f"):format(REQUEST_DIR, at)
    end
    files.write(file, { key = key, count = count, made = 0, at = at })
    f.wake()
  end

  local function left(q) return math.max(0, q.count - q.made) end

  -- Everything a request still needs from step i on, as the stands and the
  -- potion chest stand now: for each step, how many bottles still have to
  -- go through it (those past it, in the chest or a stand, count).
  -- avail: potion key -> bottles free in the chest; inStands: request file -> step -> bottles.
  local function stepNeeds(q, avail, inStands)
    local path = paths[q.key]
    local out, beyond = {}, 0
    local mine = inStands[q.file] or {}
    for i = #path, 1, -1 do
      if i < #path then beyond = beyond + (avail[path[i].to] or 0) end
      beyond = beyond + (mine[i] or 0)
      out[i] = math.max(0, left(q) - beyond)
    end
    return out
  end

  local function spare(item, used)
    return math.max(0, (counts[item] or 0) - (KEEP[item] or 0) - (used and used[item] or 0))
  end

  -- What the smelter leaves alone: every ingredient of a request still waiting, and the stands' fuel.
  local taking = {}
  function self.takes() return taking end

  function self.summary()
    local busy = 0
    for _, st in ipairs(stands) do
      if jobs[st.name] then busy = busy + 1 end
    end
    return ("%d stand%s, %d brewing%s"):format(#stands, #stands == 1 and "" or "s", busy,
      #requests > 0 and (", %d requests"):format(#requests) or "")
  end

  ---------------------------------------------------------------- reading

  function self.read()
    requests = loadRequests()
    local s = readSetup()
    local list = {}
    local reads = {}
    for i, name in ipairs(myStands()) do
      list[i] = { name = name, title = (config.names or {})[name] or ("Stand %d"):format(i), list = {} }
      reads[#reads + 1] = function()
        local ok, l = pcall(peripheral.call, name, "list")
        list[i].list = ok and type(l) == "table" and l or {}
        list[i].ok = ok
      end
    end
    reads[#reads + 1] = function()
      chestList = nil
      if s.chest and peripheral.isPresent(s.chest) then
        local ok, l = pcall(peripheral.call, s.chest, "list")
        chestList = ok and type(l) == "table" and l or nil
      end
    end
    parallel.waitForAll(table.unpack(reads))
    stands = list
    -- jobs on stands that are gone (given away, broken) are forgotten
    local here = {}
    for _, st in ipairs(stands) do here[st.name] = true end
    for name in pairs(jobs) do
      if not here[name] then jobs[name] = nil end
    end
    local seen, pats = {}, {}
    for _, q in ipairs(requests) do
      for _, m in ipairs(paths[q.key] or {}) do
        if not seen[m.ing] then
          seen[m.ing] = true
          pats[#pats + 1] = escape(m.ing)
        end
      end
    end
    if #stands > 0 and not seen[BLAZE] then pats[#pats + 1] = escape(BLAZE) end
    taking = pats
  end

  -- The bottles in the potion chest by kind, and where each kind is.
  local function sortChest(chest)
    have, unknown = {}, {}
    local where = {} -- key -> { slot, ... }
    for slot, item in pairs(chestList or {}) do
      local key = keyOf(item, chest, slot)
      if key then
        have[key] = (have[key] or 0) + item.count
        where[key] = where[key] or {}
        table.insert(where[key], slot)
      elseif FORM_OF[item.name] then
        local shown = looked[idOf(item)] or nice(item.name)
        unknown[shown] = (unknown[shown] or 0) + item.count
      end
    end
    return where
  end

  ---------------------------------------------------------------- the filler

  local function setPower(s, on)
    if s.relay then
      pcall(peripheral.call, s.relay, "setOutput", s.side, on)
    else
      pcall(redstone.setOutput, s.side, on)
    end
  end

  -- Water bottles out of the dispenser into the potion chest (all a
  -- dispenser makes is water); then pulse it once per bottle wanted, while
  -- it has glass bottles and room for what it fills (a full one drops them).
  local function fillerTurn()
    local s = readSetup()
    if not (s.filler and s.side and s.chest) or os.clock() > fill.untilTime then return false end
    if not peripheral.isPresent(s.filler) or not peripheral.isPresent(s.chest) then return false end
    local ok, list = pcall(peripheral.call, s.filler, "list")
    if not ok or type(list) ~= "table" then return false end
    local glass, used = 0, 0
    for slot, item in pairs(list) do
      used = used + 1
      if item.name == GLASS then
        glass = glass + item.count
      elseif FORM_OF[item.name] == "potion" then
        learn(idOf(item), "potion:water")
        local okP, n = pcall(peripheral.call, s.filler, "pushItems", s.chest, slot)
        if okP and n and n > 0 then
          used = used - 1
          fill.want = fill.want - n
        end
      end
    end
    local n = math.min(fill.want, glass, 9 - used)
    for _ = 1, n do
      setPower(s, true)
      sleep(PULSE_ON)
      setPower(s, false)
      sleep(PULSE_OFF)
    end
    return n > 0
  end

  function self.loop()
    while true do
      local ok, worked = pcall(fillerTurn)
      if not (ok and worked) then sleep(2) end
    end
  end

  ---------------------------------------------------------------- a round

  local function plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end
  local function potions(n, key) return ("%d x %s"):format(n, titleOf(key)) end

  function self.round(r)
    counts = r.stock.counts
    local work, input = f.work, r.input
    local s = readSetup()
    local problem = r.feedProblem
    local now = os.epoch("utc")
    if #stands == 0 then
      say("No brewing stands: put a wired modem on each, join it to the cable and right-click it.", "orange")
      status("waiting", "no brewing stands")
      return
    end
    if not s.chest then
      say("Pick the potion chest: Setup, Machines, + Set the potion chest (or 'factory add potions').", "orange")
      status("waiting", "no potion chest")
      return
    end
    if not chestList then
      say(("I can't see the potion chest %s: check its modem."):format(s.chest), "red")
      status("alert", "potion chest missing")
      return
    end
    if r.unsure[s.chest] then
      say("Waiting for the storage computer to leave the potion chest alone" .. (problem and (": " .. problem) or "..."), "orange")
      status("waiting", "potion chest not registered")
      return
    end
    local where = sortChest(s.chest)
    local avail = {}
    for k, n in pairs(have) do avail[k] = n end

    -- a bottle from the chest into a stand slot, of a kind: true if it went
    local function bottleIn(key, stand, slot)
      local list = where[key] or {}
      while #list > 0 do
        local from = table.remove(list, 1)
        local item = chestList[from]
        local ok, n = pcall(peripheral.call, s.chest, "pushItems", stand, from, 1, slot)
        if ok and n and n > 0 then
          item.count = item.count - n
          if item.count > 0 then table.insert(list, 1, from) else chestList[from] = nil end
          return idOf(item)
        end
      end
      return nil
    end
    local function out(stand, slot, to)
      local ok, n = pcall(peripheral.call, stand, "pushItems", to, slot)
      return ok and n or 0
    end

    -- finished brews out, stuck ones emptied, anything stray put away
    local chestFull = false
    local inStands = {} -- request file -> step -> bottles
    local stuck = nil
    for _, st in ipairs(stands) do
      local job, l = jobs[st.name], st.list
      local ing = l[SLOT_INGREDIENT]
      if job and ing and ing.name == job.ing then
        -- still brewing (or not taking): no fuel and none to send waits, else it's emptied
        local hasFuel = l[SLOT_FUEL] and l[SLOT_FUEL].name == BLAZE
        if hasFuel and now - (job.at or now) > (BREW_TIME + STUCK_AFTER) * 1000 then
          out(st.name, SLOT_INGREDIENT, input)
          for slot = 1, 3 do
            if l[slot] then out(st.name, slot, s.chest) end
          end
          stuck = ("%s didn't brew %s into %s: it's back in the chest"):format(st.title, titleOf(job.from), titleOf(job.to))
          jobs[st.name] = nil
          st.state, st.tile = "emptied: it didn't brew", "red"
        else
          if hasFuel then
            st.state, st.tile = ("brewing %s"):format(titleOf(job.to)), "yellow"
          else
            st.state, st.tile = "waiting for blaze powder", "orange"
          end
          inStands[job.req] = inStands[job.req] or {}
          inStands[job.req][job.step] = (inStands[job.req][job.step] or 0) + job.n
        end
      elseif job then
        -- the ingredient's gone: brewed. Each changed bottle is what the mix makes.
        local loaded = {}
        for _, id in ipairs(job.ids or {}) do loaded[id] = true end
        local made, left = 0, 0
        for slot = 1, 3 do
          local item = l[slot]
          if item then
            local id = idOf(item)
            if not loaded[id] and FORM_OF[item.name] then learn(id, job.to) end
            if names[id] == job.to then made = made + item.count end
            if out(st.name, slot, s.chest) < item.count then left = left + 1 end
          end
        end
        -- dragon's breath leaves its bottle behind
        if ing then out(st.name, SLOT_INGREDIENT, input) end
        for _, q in ipairs(requests) do
          if q.file == job.req and paths[q.key] and job.step == #paths[q.key] and made > 0 then
            q.made = q.made + made
            saveRequest(q)
          end
        end
        if left > 0 then
          -- the rest come out next round (already counted: no request to credit)
          chestFull = true
          st.state, st.tile = "the potion chest is full", "red"
          jobs[st.name] = { from = job.from, to = job.to, ing = "-", n = 0, step = job.step, req = "-", ids = {}, at = now }
        else
          jobs[st.name] = nil
        end
      else
        -- nothing of ours in it: bottles to the chest, anything else to storage
        for slot = 1, 3 do
          if l[slot] then out(st.name, slot, s.chest) end
        end
        if ing then out(st.name, SLOT_INGREDIENT, input) end
        if l[SLOT_FUEL] and l[SLOT_FUEL].name ~= BLAZE then out(st.name, SLOT_FUEL, input) end
      end
    end
    -- re-read the chest after what came in, so this round loads from it
    local function recount()
      local ok, list = pcall(peripheral.call, s.chest, "list")
      if ok and type(list) == "table" then chestList = list end
      where = sortChest(s.chest)
      avail = {}
      for k, n in pairs(have) do avail[k] = n end
    end
    recount()

    -- finished requests
    local open = {}
    for _, q in ipairs(requests) do
      if not paths[q.key] then
        fs.delete(q.file)
      elseif left(q) == 0 then
        fs.delete(q.file)
        tell(("Brewed %s. They're in the potion chest."):format(potions(q.made, q.key)), "lime")
      elseif fs.exists(q.file) then
        open[#open + 1] = q
      end
    end
    requests = open

    -- each free stand: the latest step of the oldest request it can do
    local usedIng = {}
    local loads = {} -- { to, slot, item, n, stand (an ingredient for a new brew) }
    local loading = {} -- stand -> its new job (until its ingredient is known to be there)
    local function plan()
      for _, q in ipairs(requests) do
        local path = paths[q.key]
        local needs = stepNeeds(q, avail, inStands)
        for i = #path, 1, -1 do
          local m = path[i]
          if needs[i] > 0 and (avail[m.from] or 0) > 0 and spare(m.ing, usedIng) > 0 then
            return q, i, m, math.min(3, needs[i], avail[m.from])
          end
        end
      end
    end
    local function use(item, n) usedIng[item] = (usedIng[item] or 0) + n end
    for _, st in ipairs(stands) do
      local l = st.list
      local fuel = l[SLOT_FUEL] and l[SLOT_FUEL].name == BLAZE and l[SLOT_FUEL].count or 0
      if st.ok and fuel < FUEL_KEEP and spare(BLAZE, usedIng) > 0 then
        local n = math.min(FUEL_KEEP - fuel, spare(BLAZE, usedIng))
        loads[#loads + 1] = { to = st.name, slot = SLOT_FUEL, item = BLAZE, n = n }
        use(BLAZE, n)
      end
      if st.ok and not jobs[st.name] and not chestFull then
        local q, i, m, n = plan()
        if q then
          local ids = {}
          for slot = 1, n do
            local id = bottleIn(m.from, st.name, slot)
            if id then ids[#ids + 1] = id end
          end
          if #ids > 0 then
            avail[m.from] = avail[m.from] - #ids
            use(m.ing, 1)
            inStands[q.file] = inStands[q.file] or {}
            inStands[q.file][i] = (inStands[q.file][i] or 0) + #ids
            loading[st.name] = { from = m.from, to = m.to, ing = m.ing, n = #ids, step = i, req = q.file, ids = ids, at = now }
            loads[#loads + 1] = { to = st.name, slot = SLOT_INGREDIENT, item = m.ing, n = 1, stand = st.name }
          end
        end
      end
      if not jobs[st.name] and not loading[st.name] and not st.state then
        st.state, st.tile = "idle", "lime"
      end
    end

    -- the filler keeps WATER_KEEP water bottles in the chest, or what the
    -- requests still have to start from water; it gets glass bottles to fill
    local short = {} -- item -> how many more the requests need than storage has
    local waterWanted = 0
    for _, q in ipairs(requests) do waterWanted = waterWanted + stepNeeds(q, avail, inStands)[1] end
    if s.filler then
      fill.want = math.max(0, math.max(WATER_KEEP, waterWanted) - (avail["potion:water"] or 0))
      fill.untilTime = os.clock() + 30
      local ok, list = pcall(peripheral.call, s.filler, "list")
      local glass = 0
      for _, item in pairs(ok and list or {}) do
        if item.name == GLASS then glass = glass + item.count end
      end
      if not ok then problem = problem or ("I can't see the bottle filler %s: check its modem"):format(s.filler) end
      local top = ok and math.min(FILLER_GLASS, fill.want) - glass or 0
      if top > 0 then
        local n = math.min(top, spare(GLASS, usedIng))
        if n > 0 then
          loads[#loads + 1] = { to = s.filler, item = GLASS, n = n }
          use(GLASS, n)
        end
        if n < top then short[GLASS] = top - n end
      end
    else
      fill.want = 0
    end

    -- the ingredients, fuel and glass: through the work chest in one go, else straight in
    local got = {} -- stand -> its ingredient arrived
    if r.useWork then
      local items = {}
      for _, ld in ipairs(loads) do items[ld.item] = (items[ld.item] or 0) + ld.n end
      if next(items) then
        local reply, why = work:fill(items, 0)
        if reply and reply.error and not reply.nochest then problem = problem or reply.error end
        if not reply then problem = problem or why end
        for _, ld in ipairs(loads) do
          local n = work:move(ld.item, ld.to, ld.slot, ld.n)
          if ld.stand then got[ld.stand] = n > 0 end
        end
        work:empty(input)
      end
    else
      for _, ld in ipairs(loads) do
        local reply = f.ask({ type = "send", to = ld.to, slot = ld.slot, items = { [ld.item] = ld.n } })
        local n = reply and type(reply.sent) == "table" and reply.sent[ld.item] or 0
        if reply and reply.error then
          -- an old storage computer loads furnaces and hoppers only
          problem = problem or (reply.error:find("isn't a furnace", 1, true) and not reply.error:find("brewing", 1, true)
            and "the storage computer can't load brewing stands yet: 'install update' it" or reply.error)
        end
        if not reply then problem = problem or "the storage computer didn't answer" end
        if ld.stand then got[ld.stand] = n > 0 end
      end
    end
    -- a stand whose ingredient didn't come gives its bottles back
    for _, st in ipairs(stands) do
      local job = loading[st.name]
      if job then
        if got[st.name] then
          jobs[st.name] = job
          st.state, st.tile = ("brewing %s"):format(titleOf(job.to)), "yellow"
        else
          for slot = 1, 3 do out(st.name, slot, s.chest) end
          inStands[job.req][job.step] = inStands[job.req][job.step] - job.n
          st.state, st.tile = ("no %s came"):format(nice(job.ing)), "orange"
        end
      end
    end
    saveJobs()

    -- what each request waits on, and the ingredients short
    recount()
    for _, q in ipairs(requests) do
      local path = paths[q.key]
      local needs = stepNeeds(q, avail, inStands)
      q.state = nil
      for i = #path, 1, -1 do
        local m = path[i]
        if needs[i] > 0 then
          -- a brew a step, for three bottles each
          short[m.ing] = (short[m.ing] or 0) + math.ceil(needs[i] / 3)
          if not q.state and (avail[m.from] or 0) > 0 and spare(m.ing, usedIng) == 0 then
            q.state = "waiting for " .. nice(m.ing)
          end
        end
      end
      local busy = 0
      for _, n in pairs(inStands[q.file] or {}) do busy = busy + n end
      if not q.state then
        q.state = busy > 0 and ("%d brewing"):format(busy)
          or (avail[path[1].from] or 0) == 0 and (s.filler and "waiting for water bottles from the filler"
            or "needs water bottles in the potion chest")
          or "waiting for a stand"
      end
    end
    for _, st in ipairs(stands) do
      local fuel = st.list[SLOT_FUEL]
      if not (fuel and fuel.name == BLAZE) and spare(BLAZE, usedIng) == 0 then
        short[BLAZE] = (short[BLAZE] or 0) + FUEL_KEEP
      end
    end

    -- what's short is made first, when it can be crafted ('prepare' tops up to a total)
    if ORDER then
      local t = os.clock()
      for item, n in pairs(short) do
        local free = spare(item)
        if n <= free then
          orderNote[item] = nil
        elseif t - (orderAt[item] or -math.huge) >= ORDER_EVERY then
          orderAt[item] = t
          local reply = f.craft({ type = "prepare", items = { [item] = (counts[item] or 0) + n - free } }, 5)
          local making = reply and type(reply.crafting) == "table" and tonumber(reply.crafting[item]) or 0
          local why = reply and type(reply.cantCraft) == "table" and reply.cantCraft[item]
          orderNote[item] = not reply and "no craft overseer answered" or why and "can't be crafted"
            or making > 0 and ("making %d"):format(making) or nil
        end
      end
      for item in pairs(orderNote) do
        if not short[item] then orderNote[item], orderAt[item] = nil, nil end
      end
      for _, q in ipairs(requests) do
        local item = q.state and q.state:match("^waiting for (.+)$")
        for name, note in pairs(orderNote) do
          if item == nice(name) then q.state = q.state .. ": " .. note end
        end
      end
    end

    -- how it's doing
    local working = 0
    for _, st in ipairs(stands) do
      if st.tile == "yellow" then working = working + 1 end
    end
    if stuck then tell(capital(stuck) .. ".", "orange") end
    if news and os.clock() < news[3] then
      self.message = { news[1], news[2] }
    elseif problem then
      say("Couldn't move items: " .. problem, "red")
    elseif chestFull then
      say("The potion chest is full: take some potions out.", "red")
    elseif #requests == 0 then
      say("Tap +1, +3 or +9 by a potion (F picks potions, splash or lingering).")
    else
      say(("%s: %s."):format(titleOf(requests[1].key), requests[1].state))
    end
    status(chestFull and "alert" or working > 0 and "running" or "idle",
      ("%d of %d stands brewing, %d requests"):format(working, #stands, #requests))
  end

  ---------------------------------------------------------------- screen

  local function shownList()
    local out = {}
    for _, key in ipairs(ALL) do
      if splitKey(key) == form then out[#out + 1] = key end
    end
    return out
  end

  -- Can it be brewed from what's stored now (every ingredient on its way there)?
  local function stocked(key)
    for _, m in ipairs(paths[key] or {}) do
      if spare(m.ing) == 0 and (have[m.to] or 0) == 0 then return false end
    end
    return true
  end

  local function zone(target, x1, x2, y, action)
    zones[target] = zones[target] or {}
    table.insert(zones[target], { x1, x2, y, action })
  end

  local function button(win, target, x, y, text, action, fg, bg)
    screen.put(win, x, y, text, fg or "black", bg or "lightGray")
    zone(target, x, x + #text - 1, y, action)
    return x + #text + 1
  end

  local FORM_TITLES = { potion = " Drink ", splash = " Splash ", lingering = " Lingering " }

  local function drawPage(win, w, h, target, footer)
    zones[target] = {}
    local fit = screen.fit
    local list = shownList()
    local x = 2
    for _, fm in ipairs(FORMS) do
      local on = fm[1] == form
      x = button(win, target, x, 3, FORM_TITLES[fm[1]], { form = fm[1] }, on and "black" or "white", on and "yellow" or "gray")
    end
    local btnW = 0
    for _, n in ipairs(BUTTONS) do btnW = btnW + #(" +" .. n .. " ") + 1 end
    local bx = w - btnW + 1
    local haveR = bx - 2
    screen.put(win, haveR - 3, 4, "Have", "yellow")
    screen.put(win, 2, 4, "Potion", "yellow")
    screen.put(win, bx, 4, "Request", "yellow")
    local queueRows = math.min(QUEUE_SHOWN, #requests)
    local rows = h - 5 - #footer - (queueRows > 0 and queueRows + 1 or 0)
    local keyed = target == "terminal"
    if keyed then
      picked = math.max(1, math.min(picked, #list))
      if picked <= scroll then scroll = picked - 1 end
      if picked > scroll + rows then scroll = picked - rows end
    end
    scroll = math.max(0, math.min(scroll, #list - rows))
    for i = 1, rows do
      local key, y = list[scroll + i], 4 + i
      if key then
        local bg = keyed and scroll + i == picked and "gray" or "black"
        local ok = stocked(key)
        screen.put(win, 1, y, (" "):rep(haveR + 1), "white", bg)
        screen.put(win, 2, y, fit(titleOf(key), haveR - 8), ok and "white" or "lightGray", bg)
        local n = tostring(have[key] or 0)
        screen.put(win, haveR - #n + 1, y, n, (have[key] or 0) > 0 and "lime" or "gray", bg)
        local bx2 = bx
        for _, k in ipairs(BUTTONS) do
          bx2 = button(win, target, bx2, y, (" +%d "):format(k), { add = key, n = k }, "black", ok and "lightGray" or "gray")
        end
      end
    end
    if #list > rows then
      screen.put(win, w, 5, scroll > 0 and "^" or " ", "yellow")
      screen.put(win, w, 4 + rows, scroll + rows < #list and "v" or " ", "yellow")
      zone(target, w, w, 5, { scroll = -rows })
      zone(target, w, w, 4 + rows, { scroll = rows })
    end
    if queueRows > 0 then
      local y = 5 + rows
      screen.put(win, 2, y, ("Requests (%d)"):format(#requests), "yellow")
      for i = 1, queueRows do
        local q = requests[i]
        screen.put(win, 2, y + i, fit(("%s %d/%d: %s"):format(titleOf(q.key), q.made, q.count, q.state or "queued"), w - 6), "white")
        button(win, target, w - 3, y + i, " x ", { cancel = q.file }, "white", "red")
      end
    end
    for i, line in ipairs(footer) do screen.put(win, 1, h - #footer + i, fit(line[1], w), line[2]) end
  end

  function self.key()
    local key = { self.message[1], self.message[2], scroll, picked, form }
    for k, n in pairs(have) do key[#key + 1] = k .. "=" .. n end
    for _, q in ipairs(requests) do key[#key + 1] = table.concat({ q.key, q.made, q.count, q.state or "" }, "/") end
    for _, st in ipairs(stands) do key[#key + 1] = st.title .. "/" .. (st.state or "") end
    table.sort(key, function(a, b) return tostring(a) < tostring(b) end)
    return table.concat(key, "|", 1)
  end

  function self.draw(win, w, h)
    local busy, bottles = 0, 0
    for _, st in ipairs(stands) do
      if st.tile == "yellow" then busy = busy + 1 end
    end
    for _, n in pairs(have) do bottles = bottles + n end
    local odd = 0
    for _, n in pairs(unknown) do odd = odd + n end
    screen.put(win, 2, 2, screen.fit(("%s, %d brewing; %d potions in the chest%s"):format(plural(#stands, "stand"), busy,
      bottles, odd > 0 and (", %d not known"):format(odd) or ""), w - 2), "lightGray")
    local footer = {}
    local m = self.message
    for _, line in ipairs(screen.wrap(m[1], w, (m[2] == "red" or m[2] == "orange") and 3 or 2)) do footer[#footer + 1] = { line, m[2] } end
    footer[#footer + 1] = { w >= 50 and "Arrows pick. Enter +1, 3 +3, 9 +9. F: form, X cancels last" or "Enter +1, 3, 9, F form, X cancel",
      "gray" }
    drawPage(win, w, h, "terminal", footer)
  end

  self.monitorPage = { title = "Brew",
    key = function() return self.key() end,
    draw = function(win, w, h) drawPage(win, w, h, "monitor", {}) end,
  }

  function self.tiles()
    local tiles = {}
    for _, st in ipairs(stands) do tiles[#tiles + 1] = { st.title, st.state or "idle", st.tile or "lime" } end
    return tiles
  end

  local function act(a)
    if a.add then
      request(a.add, a.n)
      tell(("Asked for %s."):format(potions(a.n, a.add)), "lime")
    elseif a.form then
      form, scroll, picked = a.form, 0, 1
    elseif a.scroll then
      scroll = math.max(0, scroll + a.scroll)
      picked = math.max(1, math.min(#shownList(), picked + a.scroll))
    elseif a.cancel then
      if fs.exists(a.cancel) then fs.delete(a.cancel) end
      tell("Cancelled. What's in the stands still brews, into the potion chest.", "lime")
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

  function self.monitorPage.touch(x, y) return tap("monitor", x, y) end

  function self.event(ev, x, y)
    local e = ev[1]
    local list = shownList()
    if e == "key" and ev[2] == keys.up then picked = math.max(1, picked - 1)
    elseif e == "key" and ev[2] == keys.down then picked = math.min(#list, picked + 1)
    elseif e == "key" and ev[2] == keys.pageUp then picked = math.max(1, picked - 8)
    elseif e == "key" and ev[2] == keys.pageDown then picked = math.min(#list, picked + 8)
    elseif e == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) and list[picked] then
      act({ add = list[picked], n = 1 })
    elseif e == "char" and (ev[2] == "3" or ev[2] == "9") and list[picked] then
      act({ add = list[picked], n = tonumber(ev[2]) })
    elseif e == "char" and ev[2]:lower() == "f" then
      local i = 1
      for j, fm in ipairs(FORMS) do
        if fm[1] == form then i = j end
      end
      act({ form = FORMS[i % #FORMS + 1][1] })
    elseif e == "char" and ev[2]:lower() == "x" and #requests > 0 then
      act({ cancel = requests[#requests].file })
    elseif e == "mouse_scroll" then picked = math.max(1, math.min(#list, picked + ev[2]))
    elseif x then tap("terminal", x, y)
    end
    return false
  end

  ---------------------------------------------------------------- adding the chest and filler

  local function chestsHere()
    return setupui.onNetwork(isChest)
  end

  local function isEmpty(name)
    local ok, list = pcall(peripheral.call, name, "list")
    return ok and type(list) == "table" and next(list) == nil
  end

  -- Can name be the potion chest? nil, or why not.
  local function chestProblem(name)
    if not peripheral.isPresent(name) then return name .. " isn't on the network" end
    local t = peripheral.getType(name) or ""
    if not isChest(t) then return name .. " isn't a chest or barrel (and never an ender chest)" end
    if f.taken(name) then return name .. " is another factory computer's" end
    -- near storage, a chest with items in it may be storage: only an empty one is taken
    if not f.work.remote and not isEmpty(name) and readSetup().chest ~= name then
      return name .. " has items in it: empty it first (it may be a storage chest)"
    end
    return nil
  end

  local function setChest(name)
    local s = readSetup()
    s.chest = name
    writeSetup(s)
    f.wake()
  end

  local function setFiller(dispenser, side, relay)
    local s = readSetup()
    s.filler, s.side, s.relay = dispenser, side, relay
    writeSetup(s)
    f.wake()
  end

  local SIDES = { "top", "bottom", "left", "right", "front", "back" }

  local function choose(question, options)
    for i, o in ipairs(options) do print(("%2d  %s"):format(i, o)) end
    write(question .. " ")
    local text = read()
    if text == "" then return nil end
    return options[tonumber(text)] or text
  end

  -- 'factory add potions [chest]' / 'factory add filler [dispenser] [side | relay side]'
  function self.addCommand(kind, a, b, c)
    if kind == "potions" then
      local name = a
      if not name then
        local free = {}
        for _, n in ipairs(chestsHere()) do
          if not chestProblem(n) then free[#free + 1] = n end
        end
        if #free == 0 then
          print("I need an empty chest or barrel on the cable for the potions: put a wired modem on it and right-click it.")
          return
        end
        print("The chest the potions go in (water bottles too):")
        name = choose("Which? (Enter to cancel)", free)
        if not name then return end
      end
      local why = chestProblem(name)
      if why then print(capital(why) .. ".") return end
      setChest(name)
      print(("Potions go in %s. Put water bottles in it, or add a bottle filler ('factory add filler')."):format(name))
      return
    end
    local dispenser = a
    if not dispenser then
      local list = setupui.onNetwork(function(t) return t:find("dispenser", 1, true) ~= nil end)
      if #list == 0 then
        print("I need a dispenser on the cable, facing a water source: put a wired modem on it and right-click it.")
        return
      end
      print("The dispenser facing water:")
      dispenser = choose("Which? (Enter to cancel)", list)
      if not dispenser then return end
    end
    if not peripheral.isPresent(dispenser) then print(dispenser .. " isn't on the network.") return end
    local side, relay = b, nil
    if b and c then relay, side = b, c end
    if not side then
      local options = {}
      for _, sd in ipairs(SIDES) do options[#options + 1] = sd end
      for _, n in ipairs(setupui.onNetwork(function(t) return t:find("redstone_relay", 1, true) ~= nil end)) do
        options[#options + 1] = n
      end
      print("What powers it: a side of this computer, or a redstone relay:")
      local pick = choose("Which? (Enter to cancel)", options)
      if not pick then return end
      local isSide = false
      for _, sd in ipairs(SIDES) do
        if sd == pick then isSide = true end
      end
      if isSide then
        side = pick
      else
        relay = pick
        side = choose("Which side of the relay faces the dispenser?", SIDES)
        if not side then return end
      end
    end
    setFiller(dispenser, side, relay)
    print(("The filler is %s, powered from %s%s. Glass bottles come from storage."):format(dispenser,
      relay and (relay .. "'s ") or "this computer's ", side))
  end

  function self.listed()
    local s, out = readSetup(), {}
    if s.chest then
      out[#out + 1] = { text = ("Potion chest: %s"):format(s.chest), remove = function()
        local t = readSetup()
        t.chest = nil
        writeSetup(t)
        return ("Forgot the potion chest %s. Take the potions out by hand."):format(s.chest)
      end }
    end
    if s.filler then
      out[#out + 1] = { text = ("Bottle filler: %s, powered from %s%s"):format(s.filler, s.relay and (s.relay .. " ") or "",
        s.side or "?"), remove = function()
        setFiller(nil, nil, nil)
        return ("Forgot the bottle filler %s. Empty it by hand."):format(s.filler)
      end }
    end
    return out
  end

  -- The setup screen's rows: the potion chest and the filler.
  function self.setupParts(ui)
    local function pickChest()
      ui:pickChest({ title = "The potion chest", hint = "Water bottles go in it, and every potion comes out into it.",
        names = chestsHere(), current = readSetup().chest,
        roleOf = function(n) return f.taken(n) and "in use" or nil end,
        pick = function(n)
          local why = chestProblem(n)
          if why then ui:say(capital(why) .. ".", "orange") return end
          ui:back()
          setChest(n)
          ui:say(("Potions go in %s. Put water bottles in it, or add a bottle filler."):format(n), "lime")
        end })
    end
    local function pickPower(done)
      ui:open({ title = "What powers the dispenser", hint = "A side of this computer, or a redstone relay on the cable.",
        rows = function()
          local out = {}
          for _, sd in ipairs(SIDES) do
            out[#out + 1] = { label = "This computer's " .. sd, act = function()
              ui:back()
              done(sd, nil)
            end }
          end
          for _, n in ipairs(setupui.onNetwork(function(t) return t:find("redstone_relay", 1, true) ~= nil end)) do
            out[#out + 1] = { label = n, value = "relay", act = function()
              ui:open({ title = "Its side facing the dispenser", rows = function()
                local rows = {}
                for _, sd in ipairs(SIDES) do
                  rows[#rows + 1] = { label = sd, act = function()
                    ui:back()
                    ui:back()
                    done(sd, n)
                  end }
                end
                return rows
              end })
            end }
          end
          return out
        end })
    end
    local function pickFiller()
      ui:open({ title = "The bottle filler", hint = "A dispenser facing a water source.",
        rows = function()
          local out = {}
          for _, n in ipairs(setupui.onNetwork(function(t) return t:find("dispenser", 1, true) ~= nil end)) do
            out[#out + 1] = { label = n, act = function()
              ui:back()
              pickPower(function(side, relay)
                setFiller(n, side, relay)
                ui:say(("Filler %s added. Glass bottles come from storage."):format(n), "lime")
              end)
            end }
          end
          if #out == 0 then
            out[1] = { label = "No dispenser here: put a wired modem on one and right-click it.", dim = true }
          end
          return out
        end })
    end
    local parts = {}
    function parts.entries()
      local s, out = readSetup(), {}
      if s.chest then
        out[#out + 1] = { label = "Potion chest", value = s.chest,
          colour = peripheral.isPresent(s.chest) and "lightGray" or "red", act = pickChest }
      end
      if s.filler then
        out[#out + 1] = { label = "Bottle filler", value = ("%s, %s%s"):format(s.filler, s.relay and (s.relay .. " ") or "",
          s.side or "?"), colour = peripheral.isPresent(s.filler) and "lightGray" or "red", act = function()
            ui:open({ title = "Bottle filler", rows = function()
              return {
                { label = "Change it", act = function()
                  ui:back()
                  pickFiller()
                end },
                { label = "Remove it", colour = "red", act = function()
                  setFiller(nil, nil, nil)
                  ui:back()
                  ui:say("No bottle filler: put water bottles in the potion chest by hand.", "lime")
                end },
              }
            end })
          end }
      end
      return out
    end
    function parts.adds()
      local s, out = readSetup(), {}
      if not s.chest then out[#out + 1] = { label = "+ Set the potion chest", colour = "lime", act = pickChest } end
      if not s.filler then out[#out + 1] = { label = "+ Add a bottle filler", colour = "lime", act = pickFiller } end
      return out
    end
    return parts
  end

  ---------------------------------------------------------------- commands

  local function matching(text)
    text = text:lower()
    local exact, some = {}, {}
    for _, key in ipairs(ALL) do
      local t = titleOf(key):lower()
      if t == text or key == text then exact[#exact + 1] = key
      elseif t:find(text, 1, true) then some[#some + 1] = key end
    end
    for _, k in ipairs(some) do exact[#exact + 1] = k end
    return exact
  end

  -- 'factory brew [potion count | find <text> | cancel [n]]'. True if args was it.
  function self.command(args)
    if args[1] ~= "brew" then return false end
    local queued = loadRequests()
    if args[2] == "cancel" then
      local n, gone = tonumber(args[3] or ""), 0
      for i, q in ipairs(queued) do
        if not n or n == i then
          fs.delete(q.file)
          gone = gone + 1
        end
      end
      print(gone > 0 and ("Cancelled %d request(s)."):format(gone) or "Nothing to cancel.")
      f.wake()
      return true
    elseif args[2] == "find" and args[3] then
      local list = matching(table.concat(args, " ", 3))
      for _, key in ipairs(list) do
        local steps = {}
        for _, m in ipairs(paths[key]) do steps[#steps + 1] = nice(m.ing) end
        print(("%s: water + %s"):format(titleOf(key), table.concat(steps, ", ")))
      end
      if #list == 0 then print("No potion called that.") end
      return true
    end
    local count = tonumber(args[#args] or "")
    if args[2] and count and #args >= 3 then
      local key = matching(table.concat(args, " ", 2, #args - 1))[1]
      if not key then
        print("No potion called that: 'factory brew find <text>' looks one up.")
        return true
      end
      request(key, math.floor(count))
      print(("Asked for %s. It starts on the factory's next round."):format(potions(math.floor(count), key)))
      return true
    end
    local s = readSetup()
    print(("Potion chest: %s. Bottle filler: %s."):format(s.chest or "none ('factory add potions')",
      s.filler or "none ('factory add filler')"))
    for i, q in ipairs(queued) do print(("Request %d: %s %d/%d"):format(i, titleOf(q.key), q.made or 0, q.count)) end
    if #queued == 0 then print("No requests.") end
    print("factory brew <potion> <count> | find <text> | cancel [n]")
    print("e.g. factory brew splash potion of healing ii 6")
    return true
  end

  return self
end

M.paths, M.titleOf, M.ALL = paths, titleOf, ALL -- for checks

return M
