-- The factory's custom machines (factory.lua loads it): any machine at all,
-- run from the recipes the player gives it. Every machine on the cable with
-- slots that no other part runs (not a chest, barrel, furnace, brewing stand,
-- AE2 machine...) is found by itself: a press, a mixer, a modded furnace.
-- Give one a recipe, what goes in for one go (2 iron ingots and a coal) and
-- what comes out (1 steel ingot, maybe a byproduct too), and its inputs go
-- straight into it from storage and what it makes is taken out of it into
-- storage. Recipes are set on the setup screen (shown by putting one go's
-- inputs, then outputs, in any empty chest) or typed with 'factory custom recipe'.
--
-- A machine CC can't see at all (Create's, or one with no item port on the
-- cable) is added by hand instead, as two chests: a feeder a hopper or pipe
-- empties into it, and the output chest it puts what it makes into.
--
-- A recipe runs on request (its page's +1, +8 or +64, 'factory custom', or
-- the craft overseer, which is told what the custom machines make), or
-- keeps an amount in storage for good: with 'keep 64' it makes more whenever
-- storage holds fewer than 64 of what it makes, for as long as it's set.
-- What comes out is counted towards the requests (the first thing a recipe
-- makes), then goes into storage.
--
-- The items a request waits on are left alone by the smelter (rank 0 in the
-- chain), so it doesn't smelt them away first.
local screen = require("lib.screen") -- flicker-free drawing
local mekfeed = require("lib.mekfeed") -- the hidden machines' feeders and output chests
local files = require("lib.files") -- crash-safe save files

local M = {}

local REQUEST_DIR = "/.factory_custom" -- a file per request, so a request typed in another tab is never lost
local RECIPE_FILE = "/.factory_custom_recipes" -- found machine name -> its recipes ({ ins, outs, keep } each)
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local FILL = 64 -- input items kept waiting in a machine or its feeder (config.fill), never less than one go
local GIVE_UP = 600 -- seconds a craft overseer's request may go with nothing loaded or made before it's handed back
local SHORT_AFTER = 60 -- seconds with everything sent, none of it waiting and nothing made, before more is sent
local STUCK_AFTER = 60 -- seconds a found machine may hold inputs with nothing used or made before it shows red
local ORDER_EVERY = 30 -- seconds between asking the craft overseer to make a request's missing inputs
local MAKES_EVERY = 60 -- seconds between telling the craft overseer what the custom machines make
local KEEP_SETTLE = 15 -- seconds after something came out before a kept item is topped up (it may not be counted in storage yet)
local LEARN_FOR = 30 -- seconds a chest is left alone after the learn page last looked at it
local WATCH_EVERY = 0.2 -- seconds between looks at a machine being watched for its recipe (in the running factory)
local QUEUE_SHOWN = 3 -- requests listed under the recipes
local BUTTONS = { 1, 8, 64 } -- the request buttons by each recipe
local KEEP_CHOICES = { 1, 16, 32, 64, 128, 256, 512, 1024, 4096 } -- the setup screen's keep amounts
-- Peripheral types (any part of the name) that are never a custom machine:
-- storage and its chests, and the machines other parts run.
local NOT_MACHINES = { "chest", "barrel", "shulker", "crate", "drawer", "vault", "hopper", "dropper", "dispenser",
  "ender", "furnace", "smoker", "brewing_stand", "ae2:", "pot", "computer", "turtle", "interface", "bridge",
  "drive", "storage", "tank", "crafter" }
-- Machine types (any part of the name) never listed as a machine CC sees but can't fill: the
-- Mekanism machines other parts run, and things that read an input but make no items.
local NOT_SEEN = { "enrichmentChamber", "energizedSmelter", "metallurgicInfuser", "EnrichingFactory",
  "SmeltingFactory", "InfusingFactory", "Generator", "generator",
  "Cable", "Tube", "Pipe", "Conductor", "Cube", "Matrix", "Reactor", "Turbine", "Boiler", "Tank" }
local LEARN_TYPES = { "chest", "barrel" } -- chests a recipe can be shown in

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function escape(name) return "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "$" end

local function capital(text) return (text:gsub("^%l", string.upper)) end

-- A typed item: "iron_ingot" is minecraft:iron_ingot.
local function itemId(text)
  text = text:lower()
  return text:find(":", 1, true) and text or ("minecraft:" .. text)
end

-- A list of { name, count } from name -> count, by name.
local function listOf(map)
  local out = {}
  for name, n in pairs(map) do
    if n > 0 then out[#out + 1] = { name = name, count = n } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function sideText(list)
  local parts = {}
  for _, it in ipairs(list) do parts[#parts + 1] = ("%d %s"):format(it.count, nice(it.name)) end
  return table.concat(parts, " + ")
end

-- A saved recipe ({ ins, outs, keep }) made ready to use: the inputs by
-- name, the outputs as given (the first is what it's for), a key the same
-- recipe on two machines shares. nil if it's broken.
local function compile(raw)
  if type(raw) ~= "table" or type(raw.ins) ~= "table" or type(raw.outs) ~= "table" then return nil end
  local outs, merged = {}, {}
  for _, it in ipairs(raw.ins) do
    if type(it) == "table" and type(it.name) == "string" and tonumber(it.count) then
      merged[it.name] = (merged[it.name] or 0) + math.max(1, math.floor(tonumber(it.count)))
    end
  end
  local ins = listOf(merged)
  for _, it in ipairs(raw.outs) do
    if type(it) == "table" and type(it.name) == "string" and tonumber(it.count) then
      outs[#outs + 1] = { name = it.name, count = math.max(1, math.floor(tonumber(it.count))) }
    end
  end
  if #ins == 0 or #outs == 0 then return nil end
  local perGo, most = 0, 0
  for _, it in ipairs(ins) do
    perGo = perGo + it.count
    most = math.max(most, it.count)
  end
  local key = {}
  for _, it in ipairs(ins) do key[#key + 1] = it.count .. "*" .. it.name end
  key[#key + 1] = ">"
  for _, it in ipairs(outs) do key[#key + 1] = it.count .. "*" .. it.name end
  return { ins = ins, outs = outs, make = outs[1].name, count = outs[1].count, perGo = perGo, most = most,
    key = table.concat(key, " "), keep = tonumber(raw.keep) and math.floor(tonumber(raw.keep)) or nil,
    title = capital(nice(outs[1].name)) }
end

-- 'in... = out...' typed: each side "[count] item", e.g. "2 iron_ingot coal =
-- steel_ingot". ins, outs (lists of { name, count }), or nil and why.
local function parse(words)
  local sides, side = { {}, {} }, 1
  local count
  for _, w in ipairs(words) do
    if w == "=" or w == "->" or w == ">" then
      if count then return nil, nil, "a count with no item after it" end
      side = side + 1
      if side > 2 then return nil, nil, "only one '=' between what goes in and what comes out" end
    elseif tonumber(w) and not count then
      count = math.floor(tonumber(w))
      if count < 1 then return nil, nil, "counts start at 1" end
    else
      local n, name = w:match("^(%d+)[x%*](.+)$") -- 2xcoal, 2*coal
      if n then count, w = tonumber(n), name end
      local map = sides[side]
      local id = itemId(w)
      map[id] = (map[id] or 0) + (count or 1)
      count = nil
    end
  end
  if count then return nil, nil, "a count with no item after it" end
  if side < 2 then return nil, nil, "put '=' between what goes in and what comes out" end
  if not next(sides[1]) then return nil, nil, "nothing goes in" end
  if not next(sides[2]) then return nil, nil, "nothing comes out" end
  return listOf(sides[1]), listOf(sides[2])
end

-- A peripheral that can be a custom machine: it has slots, and its type is
-- nothing another part (or storage) has.
local function machineType(name, ignore)
  local types = { peripheral.getType(name) }
  local inventory = false
  for _, t in ipairs(types) do
    if t == "inventory" then inventory = true end
  end
  local t = types[1]
  if not inventory or type(t) ~= "string" then return false end
  for _, list in ipairs({ NOT_MACHINES, ignore }) do
    for _, word in ipairs(list) do
      if t:find(word, 1, true) then return false end
    end
  end
  return true
end

-- A machine CC can see but not fill: no slots of its own to CC (a Mekanism
-- machine's own computer methods hide them), but it reads its input
-- (getInput, getInputItem...). It's run like a hidden machine, through a
-- feeder and an output chest, and listed so the player can set those up.
local function seenType(name, ignore)
  local types = { peripheral.getType(name) }
  local t = types[1]
  if type(t) ~= "string" then return false end
  for _, other in ipairs(types) do
    if other == "inventory" then return false end
  end
  for _, list in ipairs({ NOT_MACHINES, NOT_SEEN, ignore }) do
    for _, word in ipairs(list) do
      if t:find(word, 1, true) then return false end
    end
  end
  local ok, methods = pcall(peripheral.getMethods, name)
  for _, m in ipairs(ok and type(methods) == "table" and methods or {}) do
    if m:find("^getInput") then return true end
  end
  return false
end

-- "pressurizedReactionChamber_0" or "thermal:machine_press_0" as words.
local function machineTitle(name)
  local words = name:gsub("^[%w_]+:", ""):gsub("(%l)(%u)", "%1 %2"):gsub("_", " "):lower()
  return (words:gsub("^%l", string.upper))
end

-- Peripherals on the wired network (not touching this computer: the
-- storage computer can't reach those) that pass test(name).
local function onNetwork(test)
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    if not sides[name] and test(name) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- f: the factory (factory.lua): ask, craft, work, config, wake, changed, event, taken, mine.
function M.new(f)
  local config = f.config("custom")
  local KEEP = config.keep or {} -- item -> how many of an input to leave in storage
  local OFFER = config.offer ~= false -- tell the craft overseer what the custom machines make
  local ORDER = config.order ~= false -- have the craft overseer make a request's inputs when there are too few
  local FILL_TO = tonumber(config.fill) or FILL
  local IGNORE = config.ignore or {} -- more peripheral types (part of the name) never taken for a machine
  local NAMES = config.names or {} -- machine (or feeder) name -> what the screen calls it

  local self = { id = "custom", title = "Custom", short = "Custom", rank = 0, every = 5,
    what = "Your recipes -> anything, kept in stock" }
  local units = {} -- every machine run here this round: found ones (mine, with recipes) and hidden ones
  local recipes, byKey = {}, {} -- every recipe on a machine here, once each (by key), with keep = the most any asks
  local requests = {} -- every request, oldest first (REQUEST_DIR)
  local counts = {} -- the storage computer's counts, for the screen
  local progress = {} -- request at -> when it last had something loaded or made (os.clock)
  local lastOut = {} -- item -> when some last came out (os.clock)
  local watch = {} -- found machine -> { total, since }: when its inputs last went down
  local news -- { text, colour, untilTime }
  local outStuck, outWhy, collected
  local makesKey, makesAt, makesNote = nil, -math.huge, nil
  local learning = {} -- chest -> until when (os.clock) the learn page has it: not emptied, not filled
  local watches = {} -- watch page -> { names, prev, used, rose, untilTime }: a machine watched for its recipe
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

  local function isLearning(name)
    return name ~= nil and learning[name] ~= nil and os.clock() < learning[name]
  end

  -- What's in a chest or machine, by name.
  local function contents(name)
    local ok, list = pcall(peripheral.call, name, "list")
    local map = {}
    for _, it in pairs(ok and type(list) == "table" and list or {}) do map[it.name] = (map[it.name] or 0) + it.count end
    return listOf(map), ok and type(list) == "table"
  end

  ---------------------------------------------------------------- machines and their recipes

  -- The hidden machines: lib/mekfeed.lua lines of kind "custom" (a feeder
  -- and an output chest). Their recipes are saved with the line.

  local function readRecipeFile()
    local t = files.read(RECIPE_FILE)
    return type(t) == "table" and t or {}
  end

  -- Every machine on the cable this could run: not another computer's.
  local function candidates()
    return onNetwork(function(name)
      if not machineType(name, IGNORE) then return false end
      return not (f.used and f.used(name)) and not (f.taken(name) and not f.mine(name))
    end)
  end

  -- Machines CC sees but can't fill, not set up yet (one with a feeder is a hidden
  -- machine's, so f.used), nor another computer's.
  local function seenMachines()
    return onNetwork(function(name)
      if not seenType(name, IGNORE) then return false end
      for _, e in ipairs(self.set:entries()) do
        if e.machine == name then return false end
      end
      return not (f.used and f.used(name)) and not f.taken(name)
    end)
  end

  local function titleOf(name)
    return NAMES[name] or machineTitle(name)
  end

  -- A machine's saved recipes, by its key: "m:<machine>" for a found one,
  -- "l:<feeder>" for a hidden one.
  local function recipesAt(key)
    local kind, name = key:sub(1, 1), key:sub(3)
    if kind == "m" then
      local t = readRecipeFile()[name]
      return type(t) == "table" and t or {}
    end
    for _, e in ipairs(self.set:entries()) do
      if e.feeder == name then return type(e.recipes) == "table" and e.recipes or {} end
    end
    return {}
  end

  local function saveRecipesAt(key, list)
    local kind, name = key:sub(1, 1), key:sub(3)
    if kind == "m" then
      local t = readRecipeFile()
      t[name] = #list > 0 and list or nil
      files.write(RECIPE_FILE, t)
      os.queueEvent(f.event) -- the running factory, if this is another tab
      return
    end
    local entries = self.set:entries()
    for _, e in ipairs(entries) do
      if e.feeder == name then e.recipes = list end
    end
    self.set:save(entries)
  end

  -- The found machines that have recipes and are this computer's (or no
  -- one's yet: factory.lua claims them).
  local function foundWithRecipes()
    local t = readRecipeFile()
    local out = {}
    for _, name in ipairs(candidates()) do
      if type(t[name]) == "table" and #t[name] > 0 then out[#out + 1] = name end
    end
    return out
  end

  -- The recipes on every machine, once each: the same recipe on two machines
  -- is one, run on both, keeping the larger amount either asks for.
  local function refreshRecipes()
    recipes, byKey = {}, {}
    for _, u in ipairs(units) do
      u.keys = {}
      for _, raw in ipairs(u.raw) do
        local rc = compile(raw)
        if rc then
          u.keys[rc.key] = true
          local known = byKey[rc.key]
          if known then
            if rc.keep and (known.keep or 0) < rc.keep then known.keep = rc.keep end
          else
            recipes[#recipes + 1] = rc
            byKey[rc.key] = rc
          end
        end
      end
      -- what a found machine makes and takes, so its outputs can be taken out of it
      u.inputs, u.outputs = {}, {}
      for _, raw in ipairs(u.raw) do
        local rc = compile(raw)
        for _, it in ipairs(rc and rc.ins or {}) do u.inputs[it.name] = true end
        for _, it in ipairs(rc and rc.outs or {}) do u.outputs[it.name] = true end
      end
    end
    table.sort(recipes, function(a, b)
      if a.title ~= b.title then return a.title < b.title end
      return a.key < b.key
    end)
  end

  -- The machines this round: found ones that are mine, then hidden ones.
  -- Without reading them (commands and the overseer's jobs use this too).
  local function listUnits()
    local out = {}
    local t = readRecipeFile()
    for _, name in ipairs(foundWithRecipes()) do
      if f.mine(name) then
        out[#out + 1] = { key = "m:" .. name, name = name, found = true, title = titleOf(name), feed = name,
          out = name, raw = t[name] }
      end
    end
    local entries = self.set:entries()
    local titles = self.set:titles(entries)
    for i, e in ipairs(entries) do
      out[#out + 1] = { key = "l:" .. e.feeder, name = e.feeder, found = false,
        title = e.machine and titleOf(e.machine) or titles[i], feed = e.feeder,
        out = e.output, raw = type(e.recipes) == "table" and e.recipes or {} }
    end
    return out
  end

  local function refreshUnits()
    units = listUnits()
    refreshRecipes()
  end

  local function hasRecipe(u, rc) return u.keys and u.keys[rc.key] == true end

  local function anyUnit(rc)
    for _, u in ipairs(units) do
      if hasRecipe(u, rc) then return true end
    end
    return false
  end

  -- Read every found machine at once (a call each takes a tick), and the
  -- hidden ones' feeders and output chests (lib/mekfeed.lua).
  local function readUnits()
    local lines = self.set:read()
    local byFeeder = {}
    for _, m in ipairs(lines) do byFeeder[m.entry.feeder] = m end
    local jobs = {}
    for _, u in ipairs(units) do
      if u.found then
        jobs[#jobs + 1] = function()
          local ok, list = pcall(peripheral.call, u.name, "list")
          u.present = ok and type(list) == "table"
          u.list = u.present and list or {}
          u.have = {}
          for _, it in pairs(u.list) do u.have[it.name] = (u.have[it.name] or 0) + it.count end
        end
      else
        u.m = byFeeder[u.feed]
      end
    end
    if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
  end

  -- What's waiting to go into a machine: in it (a found one, its inputs
  -- only) or in its feeder (a hidden one), by name.
  local function waiting(u)
    if u.found then
      local out = {}
      for name, n in pairs(u.have or {}) do
        if u.inputs[name] then out[name] = n end
      end
      return out
    end
    return u.m and u.m.feed or {}
  end

  local function total(map)
    local n = 0
    for _, v in pairs(map) do n = n + v end
    return n
  end

  -- Ready to take a recipe's inputs: there, working, and not holding another
  -- of its recipes' inputs (the machine would get them mixed up).
  local function canTake(u, rc, unsure)
    if isLearning(u.feed) or isLearning(u.out) then return false end
    if u.found then
      if not u.present then return false end
    else
      local m = u.m
      if not m or not mekfeed.ready(m) or not m.outOk or unsure[m.entry.feeder] then return false end
    end
    local mine = {}
    for _, it in ipairs(rc.ins) do mine[it.name] = true end
    for name, n in pairs(waiting(u)) do
      if n > 0 and not mine[name] then return false end
    end
    return true
  end

  -- How many goes a machine has room for: up to the fill (never less than
  -- one go) of inputs waiting, and, for a feeder, its free slots.
  local function room(u, rc)
    local fill = math.max(FILL_TO, rc.perGo)
    local n = math.floor(math.max(0, fill - total(waiting(u))) / rc.perGo)
    if not u.found and u.m then
      n = math.min(n, math.floor(math.max(0, u.m.feedSize * mekfeed.STACK - u.m.feedTotal) / rc.perGo))
    end
    return n
  end

  local function added(u, name, n)
    if u.found then
      u.have[name] = (u.have[name] or 0) + n
      if watch[u.name] then watch[u.name].total = watch[u.name].total + n end
    elseif u.m then
      mekfeed.added(u.m, name, n)
    end
  end

  -- Take what a found machine made out of it, into input: only what one of
  -- its recipes makes and none takes, so its inputs stay in. The hidden
  -- machines' output chests are emptied whole. Item -> how many moved, and
  -- whether some didn't fit, and why a move failed.
  local function collect(input)
    local byName, stuck, why = {}, false, nil
    if not input then return byName, false, nil end
    local hidden = {}
    for _, u in ipairs(units) do
      if u.found and u.present and not isLearning(u.name) then
        for slot, it in pairs(u.list) do
          if u.outputs[it.name] and not u.inputs[it.name] then
            local ok, n = pcall(peripheral.call, u.name, "pushItems", input, slot)
            if not ok then why = ("can't move what %s made into %s: %s"):format(u.title, input, tostring(n)) end
            n = ok and n or 0
            byName[it.name] = (byName[it.name] or 0) + n
            u.have[it.name] = math.max(0, (u.have[it.name] or 0) - n)
            if n > 0 then u.made = true end
            if n < it.count then stuck = true end
          end
        end
      elseif not u.found and u.m and not isLearning(u.out) then
        hidden[#hidden + 1] = u.m
      end
    end
    local _, lineStuck, lineWhy, lineNames = self.set:collect(hidden, input)
    for name, n in pairs(lineNames) do byName[name] = (byName[name] or 0) + n end
    return byName, stuck or lineStuck, why or lineWhy
  end

  -- A found machine holding inputs that hasn't used any or made anything
  -- for STUCK_AFTER isn't working (no power, wrong recipe, output full).
  local function stalled(u, now)
    local n = total(waiting(u))
    local t = watch[u.name]
    if not t or n < t.total or u.made or n == 0 then t = { since = now } end
    t.total = n
    watch[u.name] = t
    u.made = nil
    return n > 0 and now - t.since > STUCK_AFTER
  end

  ---------------------------------------------------------------- the setup screen

  local function keepText(keep) return keep and ("keep %d"):format(keep) or "on request" end

  -- A recipe's keep amount: off (on request only) or one of KEEP_CHOICES.
  local function keepPage(ui, key, j)
    return {
      title = "Keep in stock",
      hint = "It makes more whenever storage has fewer than this of what it makes. Off: only on request.",
      rows = function()
        local list = recipesAt(key)
        local raw = list[j]
        if not raw then return { { label = "Removed.", dim = true } } end
        local function pick(n)
          return function()
            list[j].keep = n
            saveRecipesAt(key, list)
            ui:back()
            ui:say(n and ("Keeps %d %s in storage."):format(n, nice(list[j].outs[1].name)) or "Only on request now.", "lime")
            f.wake()
          end
        end
        local out = { { label = "Off", value = "only on request", colour = raw.keep and "lightGray" or "lime", act = pick(nil) } }
        for _, n in ipairs(KEEP_CHOICES) do
          out[#out + 1] = { label = tostring(n), value = raw.keep == n and "now" or "",
            colour = raw.keep == n and "lime" or "white", act = pick(n) }
        end
        out[#out + 1] = { label = "Another amount", value = "factory custom keep", colour = "gray" }
        return out
      end,
    }
  end

  -- Learning a recipe from a chest: one go's inputs, then its outputs, put
  -- in it and read from there (the factory leaves that chest alone
  -- meanwhile). j: the recipe to learn again, nil for a new one.
  local function learnPage(ui, key, j, chest)
    local stage, ins = "in", nil
    local page
    page = {
      title = function() return stage == "in" and "What goes IN" or "What comes OUT" end,
      hint = ("Put ONE go's inputs in %s, then tap Use these."):format(chest),
      tick = function() learning[chest] = os.clock() + LEARN_FOR end,
      rows = function()
        learning[chest] = os.clock() + LEARN_FOR
        local list, ok = contents(chest)
        if not ok then return { { label = chest .. " isn't on the network.", colour = "red" } } end
        local out = {}
        if stage == "out" then
          out[#out + 1] = { label = "In:", value = sideText(ins), colour = "lightGray", dim = true }
        end
        for _, it in ipairs(list) do
          out[#out + 1] = { label = capital(nice(it.name)), value = ("x%d"):format(it.count), colour = "white" }
        end
        if #list == 0 then out[#out + 1] = { label = ("(%s is empty)"):format(chest), colour = "gray", dim = true } end
        return out
      end,
      buttons = function()
        return {
          { " Use these ", "black", "lime", function()
            local list = contents(chest)
            if #list == 0 then ui:say("The chest is empty: put the items in it first.", "orange") return end
            if stage == "in" then
              ins, stage = list, "out"
              page.hint = ("Take the inputs out of %s, put ONE go's outputs in (what it's for in the first slot), tap Use these."):format(chest)
              ui:say("Inputs read.", "lime")
              return
            end
            -- what it's for: the item in the lowest slot
            local okL, raw = pcall(peripheral.call, chest, "list")
            local first, low = nil, math.huge
            for slot, it in pairs(okL and type(raw) == "table" and raw or {}) do
              if slot < low then first, low = it.name, slot end
            end
            table.sort(list, function(a, b)
              if (a.name == first) ~= (b.name == first) then return a.name == first end
              return a.name < b.name
            end)
            local recs = recipesAt(key)
            local new = { ins = ins, outs = list, keep = j and recs[j] and recs[j].keep or nil }
            if j and recs[j] then recs[j] = new else recs[#recs + 1] = new end
            saveRecipesAt(key, recs)
            learning[chest] = nil
            ui:back()
            ui:say(("%s = %s. Take the items back out of %s."):format(sideText(ins), sideText(list), chest), "lime")
            f.wake()
          end },
          { " Cancel ", "white", "gray", function()
            learning[chest] = nil
            ui:back()
          end },
        }
      end,
    }
    return page
  end

  -- Where to show a recipe: a hidden machine's own output chest, else any
  -- empty chest or barrel, picked by putting the first input in it.
  local function learn(ui, key, j, output)
    if output then return ui:open(learnPage(ui, key, j, output)) end
    ui:pickByDrop({ title = "Show it the recipe",
      hint = "Put ONE go's inputs in any empty chest or barrel on the cable.",
      names = onNetwork(function(n)
        local t = peripheral.getType(n) or ""
        for _, w in ipairs(LEARN_TYPES) do
          if t:find(w, 1, true) and not t:find("ender", 1, true) then return true end
        end
        return false
      end),
      drop = "Put the inputs in an empty chest now.",
      pick = function(chest)
        ui:back()
        ui:open(learnPage(ui, key, j, chest))
      end })
  end

  -- Learning a recipe by watching: what a machine (a found one itself; a
  -- hidden one's feeder and output chest together) uses up and makes while
  -- the page is open. Whatever goes down was used (an input), whatever only
  -- goes up was made (an output); the factory leaves the machine alone
  -- meanwhile, so it's all the player's and the machine's doing. Sampled
  -- every WATCH_EVERY by self.loop in the running factory, and every second
  -- by the page (the only sampling when the factory isn't running).
  local function watchNames(key, output)
    local kind, name = key:sub(1, 1), key:sub(3)
    if kind == "m" then return { name } end
    return output and { name, output } or { name }
  end

  local function readAll(names)
    local map, ok = {}, true
    for _, n in ipairs(names) do
      local okL, list = pcall(peripheral.call, n, "list")
      if not okL or type(list) ~= "table" then ok = false end
      for _, it in pairs(okL and type(list) == "table" and list or {}) do map[it.name] = (map[it.name] or 0) + it.count end
    end
    return map, ok
  end

  local function sample(w)
    local now, ok = readAll(w.names)
    w.ok = ok
    if not ok then return end
    if not w.prev then
      w.prev = now
      return
    end
    local seen = {}
    for name in pairs(now) do seen[name] = true end
    for name in pairs(w.prev) do seen[name] = true end
    for name in pairs(seen) do
      local d = (now[name] or 0) - (w.prev[name] or 0)
      if d < 0 then w.used[name] = (w.used[name] or 0) - d
      elseif d > 0 then w.rose[name] = (w.rose[name] or 0) + d end
    end
    w.prev = now
  end

  local function gcd(a, b)
    while b > 0 do a, b = b, a % b end
    return a
  end

  -- What a watch saw: inputs (used up), outputs (only went up: the most made
  -- first, what it's for), and how many goes that looks like (the counts'
  -- common factor), so one go is the counts divided by it.
  local function seen(w)
    local ins, outs = {}, {}
    for name, n in pairs(w.used) do ins[name] = n end
    for name, n in pairs(w.rose) do
      if not w.used[name] then outs[name] = n end
    end
    local inList, outList = listOf(ins), listOf(outs)
    table.sort(outList, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return a.name < b.name
    end)
    local goes = 0
    for _, list in ipairs({ inList, outList }) do
      for _, it in ipairs(list) do goes = gcd(it.count, goes) end
    end
    return inList, outList, math.max(1, goes)
  end

  local function divided(list, by)
    local out = {}
    for _, it in ipairs(list) do out[#out + 1] = { name = it.name, count = math.floor(it.count / by) } end
    return out
  end

  function self.loop()
    while true do
      local any = false
      for id, w in pairs(watches) do
        if os.clock() > w.untilTime then
          watches[id] = nil
        else
          any = true
          sample(w)
        end
      end
      sleep(any and WATCH_EVERY or 1)
    end
  end

  local function watchPage(ui, key, j, output)
    local names = watchNames(key, output)
    local id = {}
    local w = { names = names, used = {}, rose = {}, untilTime = os.clock() + LEARN_FOR }
    watches[id] = w
    local function hold()
      w.untilTime = os.clock() + LEARN_FOR
      for _, n in ipairs(names) do learning[n] = os.clock() + LEARN_FOR end
    end
    local function stop()
      watches[id] = nil
      for _, n in ipairs(names) do learning[n] = nil end
    end
    local function save(ins, outs)
      local recs = recipesAt(key)
      local new = { ins = ins, outs = outs, keep = j and recs[j] and recs[j].keep or nil }
      if j and recs[j] then recs[j] = new else recs[#recs + 1] = new end
      saveRecipesAt(key, recs)
      stop()
      ui:back()
      ui:say(("%s = %s."):format(sideText(ins), sideText(outs)), "lime")
      f.wake()
    end
    hold()
    sample(w)
    return {
      title = "Watching it work",
      hint = ("Put a stack or two of what goes in into %s. Once some has come out, tap Use this."):format(
        output and names[1] .. " (its feeder)" or "the machine"),
      tick = function()
        hold()
        sample(w)
      end,
      rows = function()
        hold()
        if w.ok == false then return { { label = "Can't read " .. table.concat(names, " or ") .. ".", colour = "red" } } end
        local ins, outs, goes = seen(w)
        local out = { { label = "Used up", value = #ins > 0 and sideText(ins) or "nothing yet", colour = "white", dim = false },
          { label = "Made", value = #outs > 0 and sideText(outs) or "nothing yet", colour = "white", dim = false } }
        if #ins > 0 and #outs > 0 then
          out[#out + 1] = { label = "One go", value = ("%s = %s"):format(sideText(divided(ins, goes)), sideText(divided(outs, goes))),
            colour = "lime", dim = false }
          out[#out + 1] = { label = goes > 1 and ("(it looks like %d goes so far)"):format(goes) or "(the first thing made is what it's for)",
            colour = "gray", dim = true }
        end
        return out
      end,
      buttons = function()
        return {
          { " Use this ", "black", "lime", function()
            local ins, outs, goes = seen(w)
            if #ins == 0 or #outs == 0 then
              ui:say("Nothing used up and made yet: put its inputs in and wait for something to come out.", "orange")
              return
            end
            save(divided(ins, goes), divided(outs, goes))
          end },
          { " Start over ", "black", "lightGray", function()
            w.used, w.rose, w.prev = {}, {}, nil
            sample(w)
            ui:say("Watching again from now.", "lightGray")
          end },
          { " Cancel ", "white", "gray", function()
            stop()
            ui:back()
          end },
        }
      end,
    }
  end

  local function recipePage(ui, key, j, output)
    return {
      title = "Recipe",
      rows = function()
        local list = recipesAt(key)
        local rc = list[j] and compile(list[j])
        if not rc then return { { label = "Removed.", dim = true } } end
        return {
          { label = "In", value = sideText(rc.ins), colour = "lightGray", dim = false },
          { label = "Out", value = sideText(rc.outs), colour = "lightGray", dim = false },
          { label = "Keep in stock", value = rc.keep and tostring(rc.keep) or "off: only on request",
            colour = rc.keep and "lime" or "gray", act = function() ui:open(keepPage(ui, key, j)) end },
          { label = "Watch it again", colour = "white", act = function() ui:open(watchPage(ui, key, j, output)) end },
          { label = "Show it in a chest", colour = "white", act = function() learn(ui, key, j, output) end },
          { label = "Remove it", colour = "red", act = function()
            table.remove(list, j)
            saveRecipesAt(key, list)
            ui:back()
            ui:say("Recipe removed.", "lime")
            f.wake()
          end },
        }
      end,
    }
  end

  -- A machine's recipes as setup rows, then + Add a recipe.
  local function recipeRows(ui, key, output)
    local rows = {}
    for j, raw in ipairs(recipesAt(key)) do
      local rc = compile(raw)
      rows[#rows + 1] = { label = rc and sideText(rc.outs) or "(broken recipe)",
        value = rc and (("from %s, %s"):format(sideText(rc.ins), keepText(rc.keep))) or "",
        colour = rc and "white" or "red", act = function() ui:open(recipePage(ui, key, j, output)) end }
    end
    rows[#rows + 1] = { label = "+ Add a recipe", value = "watch it make one", colour = "lime",
      act = function() ui:open(watchPage(ui, key, nil, output)) end }
    rows[#rows + 1] = { label = "+ Add a recipe", value = output and "shown in its output chest" or "shown in a chest",
      colour = "lightGray", act = function() learn(ui, key, nil, output) end }
    return rows
  end

  -- The rows on a hidden machine's setup page (lib/mekfeed.lua's lineRows).
  local function lineRows(ui, _, entry)
    return recipeRows(ui, "l:" .. entry.feeder, entry.output)
  end

  self.set = mekfeed.new({ name = "custom", cmd = "factory", event = f.event, what = "machine CC can't see",
    title = "Machine", names = NAMES, ask = f.ask, tell = tell, far = function() return f.work.remote end,
    taken = f.taken, lines = { "custom" }, pageTitle = "Custom machines", lineRows = lineRows, lineFill = FILL_TO })

  -- For factory.lua's one 'feeders' request: the found machines are fed
  -- straight from storage, so the storage computer has to know them.
  self.feedSet = { entries = function()
    local out = {}
    for _, name in ipairs(foundWithRecipes()) do
      if f.mine(name) then out[#out + 1] = { feeder = name } end
    end
    return out
  end }

  -- The setup screen's Machines rows: every machine found on the cable (tap
  -- it for its recipes), then the hidden ones.
  function self.setupParts(ui)
    local parts = self.set:setupParts(ui)
    local function machinePage(name)
      local key = "m:" .. name
      return {
        title = function() return titleOf(name) end,
        hint = ("%s: what goes in for one go, and what comes out."):format(name),
        rows = function()
          local rows = { { label = "Machine", value = (peripheral.getType(name) or "missing"), colour = "lightGray", dim = false } }
          if f.taken(name) and not f.mine(name) then
            rows[#rows + 1] = { label = "Another factory computer runs it.", colour = "orange", dim = true }
          end
          for _, row in ipairs(recipeRows(ui, key, nil)) do rows[#rows + 1] = row end
          return rows
        end,
      }
    end
    return {
      entries = function()
        local out = {}
        local t = readRecipeFile()
        for _, name in ipairs(candidates()) do
          local n = type(t[name]) == "table" and #t[name] or 0
          out[#out + 1] = { label = titleOf(name), value = n > 0 and ("%d recipe%s"):format(n, n == 1 and "" or "s")
            or ("%s: no recipe"):format(name), colour = n > 0 and "lightGray" or "gray",
            act = function() ui:open(machinePage(name)) end }
        end
        -- machines CC sees but can't fill: tap one to give it a feeder and an output chest
        for _, name in ipairs(seenMachines()) do
          out[#out + 1] = { label = titleOf(name), value = "needs a feeder and output chest", colour = "orange",
            act = function() parts.add("custom", name) end }
        end
        for _, row in ipairs(parts.entries()) do out[#out + 1] = row end
        return out
      end,
      adds = parts.adds,
    }
  end

  -- Found machines with recipes, for factory.lua to claim (so two factory
  -- computers never run one); one with no recipe is nobody's.
  function self.found()
    local out = {}
    for _, name in ipairs(foundWithRecipes()) do out[#out + 1] = { name = name, kind = "custom" } end
    return out
  end
  function self.uses() return self.set:uses() end
  function self.active()
    for _, name in ipairs(foundWithRecipes()) do
      if f.mine(name) then return true end
    end
    return #self.set:entries() > 0
  end

  ---------------------------------------------------------------- requests

  local function loadRequests()
    local list = {}
    if fs.isDir(REQUEST_DIR) then
      for _, file in ipairs(fs.list(REQUEST_DIR)) do
        local r = files.read(REQUEST_DIR .. "/" .. file)
        if type(r) == "table" and type(r.count) == "number" then
          r.file = REQUEST_DIR .. "/" .. file
          r.made, r.sent = r.made or 0, r.sent or 0
          r.recipe = byKey[r.key]
          list[#list + 1] = r
        end
      end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    return list
  end

  local function plain(r)
    return { key = r.key, count = r.count, made = r.made, sent = r.sent, at = r.at, job = r.job, keep = r.keep,
      done = r.done, ok = r.ok, why = r.why }
  end

  -- Only while its file is there: a request cancelled in another tab stays cancelled.
  local function saveRequest(r)
    if fs.exists(r.file) then files.write(r.file, plain(r)) end
  end

  local function newRequest(key, count, job, keep)
    if not fs.isDir(REQUEST_DIR) then fs.makeDir(REQUEST_DIR) end
    local at = os.epoch("utc")
    local file = ("%s/%.0f"):format(REQUEST_DIR, at)
    while fs.exists(file) do
      at = at + 1
      file = ("%s/%.0f"):format(REQUEST_DIR, at)
    end
    local r = { key = key, count = count, made = 0, sent = 0, at = at, job = job, keep = keep }
    files.write(file, r)
    r.file, r.recipe = file, byKey[key]
    return r
  end

  -- Whole goes: a recipe that makes 4 makes 4 at a time.
  local function whole(rc, count) return math.ceil(count / rc.count) * rc.count end

  -- Ask for count more of what a recipe makes: added to a request of yours
  -- for it that's still waiting, else a new one.
  local function request(rc, count)
    count = whole(rc, count)
    for _, q in ipairs(loadRequests()) do
      if q.key == rc.key and not q.job and not q.keep and not q.done then
        q.count = q.count + count
        saveRequest(q)
        f.wake()
        return
      end
    end
    newRequest(rc.key, count)
    f.wake()
  end

  -- How many a request still has to make, and how many goes to send.
  local function left(q) return math.max(0, q.count - q.made) end
  local function toSend(q) return math.max(0, math.ceil(q.count / q.recipe.count) - q.sent) end

  -- How many goes what's stored would do.
  local function goesFrom(rc, avail)
    local n = math.huge
    for _, it in ipairs(rc.ins) do
      n = math.min(n, math.floor(math.max(0, (avail[it.name] or 0) - (KEEP[it.name] or 0)) / it.count))
    end
    return n
  end

  -- Count what came out towards the requests, oldest first (each by the
  -- first thing its recipe makes).
  local function credit(byName)
    local now = os.clock()
    for name, n in pairs(byName) do
      if n > 0 then lastOut[name] = now end
    end
    for _, q in ipairs(requests) do
      if not q.done and q.recipe then
        local n = math.min(byName[q.recipe.make] or 0, left(q))
        if n > 0 then
          q.made = q.made + n
          byName[q.recipe.make] = byName[q.recipe.make] - n
          progress[q.at] = now
          saveRequest(q)
        end
      end
    end
  end

  -- A recipe kept in stock that's under its amount gets a request (one per
  -- recipe, topped up), counting what's stored and what open requests will
  -- still make. Not just after something came out: storage may not have
  -- counted it yet. A request for a recipe no longer kept ends.
  local function keepUp(now)
    local open = {}
    for _, q in ipairs(requests) do
      if q.recipe and not q.done then open[q.key] = (open[q.key] or 0) + left(q) end
    end
    for _, q in ipairs(requests) do
      if q.keep and not q.done and (not q.recipe or not q.recipe.keep) then
        q.done, q.ok = true, true
        q.count = q.made
      end
    end
    for _, rc in ipairs(recipes) do
      if rc.keep and rc.keep > 0 and now - (lastOut[rc.make] or -math.huge) >= KEEP_SETTLE and anyUnit(rc) then
        local short = rc.keep - (counts[rc.make] or 0) - (open[rc.key] or 0)
        if short > 0 then
          local mine
          for _, q in ipairs(requests) do
            if q.keep and q.key == rc.key and not q.done then mine = q end
          end
          if mine then
            mine.count = mine.count + whole(rc, short)
            mine.dirty = true
          else
            requests[#requests + 1] = newRequest(rc.key, whole(rc, short), nil, true)
          end
        end
      end
    end
  end

  -- A request asked for here or kept in stock (not the overseer's own: its
  -- plan already makes their inputs first) whose inputs are short has the
  -- craft overseer make the rest. 'prepare' tops up to a total, stored and
  -- being made included, so asking again never orders twice.
  local orderAt, orderNote = {}, {} -- input -> when last asked (os.clock), what the overseer said
  local function orderInputs(avail)
    local need = {}
    for _, q in ipairs(requests) do
      local rc = q.recipe
      if ORDER and rc and not q.job and not q.done and anyUnit(rc) then
        for _, it in ipairs(rc.ins) do need[it.name] = (need[it.name] or 0) + toSend(q) * it.count end
      end
    end
    local now = os.clock()
    for item, n in pairs(need) do
      local have = math.max(0, (avail[item] or 0) - (KEEP[item] or 0))
      if n <= have then
        orderNote[item] = nil
      elseif now - (orderAt[item] or -math.huge) >= ORDER_EVERY then
        orderAt[item] = now
        local reply = f.craft({ type = "prepare", items = { [item] = (avail[item] or 0) + n - have } }, 5)
        local making = reply and type(reply.crafting) == "table" and tonumber(reply.crafting[item]) or 0
        local why = reply and type(reply.cantCraft) == "table" and reply.cantCraft[item]
        orderNote[item] = not reply and "no craft overseer answered"
          or why and ("can't be made: " .. tostring(why))
          or reply.craftProblem and making > 0 and ("making it: " .. tostring(reply.craftProblem))
          or making > 0 and ("making %d first"):format(making)
          or nil
      end
    end
    for item in pairs(orderNote) do
      if not need[item] then orderNote[item], orderAt[item] = nil, nil end
    end
  end

  ---------------------------------------------------------------- the craft overseer

  -- A recipe as the craft overseer plans it: its inputs laid out in a grid
  -- (a cell each, so only recipes of at most 9 inputs), count of what it's for.
  local function asCraft(rc)
    if rc.perGo > 9 then return nil end
    local cells, keys, letter = {}, {}, 65
    for _, it in ipairs(rc.ins) do
      local ch = string.char(letter)
      letter = letter + 1
      keys[ch] = it.name
      for _ = 1, it.count do cells[#cells + 1] = ch end
    end
    local text = table.concat(cells)
    local rows = {}
    for r = 1, 3 do
      local row = text:sub(r * 3 - 2, r * 3)
      if row ~= "" then rows[#rows + 1] = row end
    end
    return { make = rc.make, count = rc.count, rows = rows, keys = keys }
  end

  local function offer()
    if not OFFER then return end
    local crafts, keys = {}, {}
    for _, rc in ipairs(recipes) do
      local c = anyUnit(rc) and asCraft(rc)
      if c then
        crafts[#crafts + 1] = c
        keys[#keys + 1] = rc.key
      end
    end
    local key = table.concat(keys, "|")
    if key == makesKey and os.clock() - makesAt < MAKES_EVERY then return end
    local reply = f.craft({ type = "makes", via = "custom", recipes = crafts }, 5)
    makesAt = os.clock()
    if reply and reply.ok then
      makesKey, makesNote = key, nil
    else
      makesKey = nil
      makesNote = #crafts > 0 and (reply and reply.error
        or "the craft overseer doesn't take custom machine orders: is it running, and updated?") or nil
    end
  end

  -- A craft overseer's request is finished (or given up on): tell it. True once it has heard.
  local function report(q)
    if not q.job then return true end
    local reply = f.craft({ type = "jobdone", job = q.job, ok = q.ok, why = q.why }, 5)
    return reply ~= nil
  end

  -- The recipe a craft overseer's job is for: what it makes, and its grid's items.
  local function recipeFor(make, grid)
    local have, kinds = {}, 0
    for _, item in pairs(type(grid) == "table" and grid or {}) do
      if not have[item] then kinds = kinds + 1 end
      have[item] = (have[item] or 0) + 1
    end
    for _, rc in ipairs(recipes) do
      if rc.make == make and #rc.ins == kinds then
        local same = true
        for _, it in ipairs(rc.ins) do
          if have[it.name] ~= it.count then same = false end
        end
        if same then return rc end
      end
    end
    return nil
  end

  -- From the craft overseer (factory protocol): 'custom' (make this for one
  -- of its plans) and 'cancel'. The reply, or nil if it isn't one.
  function self.request(from, msg)
    if msg.type == "custom" then
      refreshUnits()
      local rc = recipeFor(tostring(msg.make), msg.grid)
      local count = math.floor(tonumber(msg.count) or 0)
      if not rc or count < 1 then return { ok = false, why = "no custom machine here has that recipe" } end
      newRequest(rc.key, count, msg.job)
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

  -- What the smelter leaves alone: the inputs of every request still waiting.
  local taking = {}
  function self.takes() return taking end

  function self.summary()
    local waitingN, kept = 0, 0
    for _, q in ipairs(requests) do
      if not q.done then waitingN = waitingN + 1 end
    end
    for _, rc in ipairs(recipes) do
      if rc.keep then kept = kept + 1 end
    end
    return ("%d machine%s%s%s"):format(#units, #units == 1 and "" or "s", kept > 0 and (", %d kept"):format(kept) or "",
      waitingN > 0 and (", %d requests"):format(waitingN) or "")
  end

  ---------------------------------------------------------------- a round

  function self.read(remote, remoteInput)
    refreshUnits()
    readUnits()
    requests = loadRequests()
    local seen, list = {}, {}
    for _, q in ipairs(requests) do
      if q.recipe and not q.done then
        for _, it in ipairs(q.recipe.ins) do
          if not seen[it.name] then
            seen[it.name] = true
            list[#list + 1] = escape(it.name)
          end
        end
      end
    end
    taking = list
    outStuck, outWhy, collected = false, nil, false
    if remote then
      local byName
      byName, outStuck, outWhy = collect(remoteInput)
      credit(byName)
      collected = true
    end
  end

  function self.round(r)
    local work = f.work
    counts = r.stock.counts
    local problem = r.feedProblem
    offer()
    if #units == 0 then
      say("Nothing set up yet: on the setup screen, Machines, tap a machine and give it a recipe.", "orange")
      status("waiting", "nothing set up")
      return
    end
    if #recipes == 0 then
      say("No recipes yet: on the setup screen, Machines, tap a machine, then + Add a recipe.", "orange")
      status("waiting", "no recipes")
    end
    local input = r.input
    local avail = {}
    for name, n in pairs(counts) do avail[name] = n end

    if not collected then
      local byName
      byName, outStuck, outWhy = collect(input)
      credit(byName)
    end

    -- finished requests: done, or a craft overseer's that waited too long
    local now = os.clock()
    keepUp(now)
    for _, q in ipairs(requests) do
      progress[q.at] = progress[q.at] or now
      if not q.recipe and not q.done then
        q.done, q.ok, q.why = true, false, "no custom machine here has its recipe any more"
      elseif not q.done and left(q) == 0 then
        q.done, q.ok = true, true
        if not q.job and not q.keep then tell(("Made %d %s."):format(q.made, q.recipe.title), "lime") end
      elseif q.job and not q.done and now - progress[q.at] > GIVE_UP then
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

    -- the inputs, oldest request first, a whole number of goes into each
    -- machine with the recipe and room; with a work chest each load is noted
    -- down and fetched for all at once below
    local plan = r.useWork and {} or nil
    local sent = 0
    for _, q in ipairs(requests) do
      q.state = nil
      local rc = q.recipe
      -- everything sent, none of it waiting, nothing made for a while: the
      -- machine gave fewer than the recipe says, so send the rest
      if toSend(q) == 0 and left(q) > 0 and now - progress[q.at] > SHORT_AFTER then
        local inside = 0
        for _, u in ipairs(units) do
          local w = waiting(u)
          for _, it in ipairs(rc.ins) do inside = inside + (w[it.name] or 0) end
        end
        if inside == 0 then
          q.sent = math.max(0, q.sent - math.ceil(left(q) / rc.count))
          q.dirty, progress[q.at] = true, now
        end
      end
      local machines = 0
      for _, u in ipairs(units) do
        if hasRecipe(u, rc) then
          machines = machines + 1
          local want = toSend(q)
          if want > 0 and canTake(u, rc, r.unsure) and not (u.found and r.unsure[u.name]) then
            local goes = math.min(want, goesFrom(rc, avail), room(u, rc), math.floor(SEND_MAX / rc.most))
            if goes > 0 then
              local items = {}
              for _, it in ipairs(rc.ins) do items[it.name] = it.count * goes end
              local got
              if plan then
                plan[#plan + 1] = { u = u, q = q, rc = rc, items = items, goes = goes }
                got = items
              else
                local reply = f.ask({ type = "send", to = u.feed, items = items })
                got = reply and type(reply.sent) == "table" and reply.sent or {}
                if reply and reply.error then problem = reply.error end
                if not reply then problem = "the storage computer didn't answer while loading " .. u.title end
              end
              local done = goes
              for _, it in ipairs(rc.ins) do
                local n = tonumber(got[it.name]) or 0
                added(u, it.name, n)
                avail[it.name] = (avail[it.name] or 0) - n
                sent = sent + n
                done = math.min(done, math.floor(n / it.count))
              end
              q.sent = q.sent + done
              if done > 0 then progress[q.at], q.dirty = now, true end
            end
          end
        end
      end
      if machines == 0 then
        q.state = "no machine has this recipe"
      elseif toSend(q) > 0 and goesFrom(rc, avail) == 0 then
        local short, names = {}, {}
        for _, it in ipairs(rc.ins) do
          if math.max(0, (avail[it.name] or 0) - (KEEP[it.name] or 0)) < it.count then
            short[#short + 1] = it.name
            names[#names + 1] = nice(it.name)
          end
        end
        q.state = "waiting for " .. table.concat(names, ", ")
        q.short = short
      end
    end
    -- what's short is made first, and the request says so
    orderInputs(avail)
    for _, q in ipairs(requests) do
      for _, name in ipairs(q.short or {}) do
        if orderNote[name] then
          q.state = q.state .. ": " .. orderNote[name]
          break
        end
      end
      q.short = nil
    end
    if plan then
      local items = {}
      for _, p in ipairs(plan) do
        for name, n in pairs(p.items) do items[name] = (items[name] or 0) + n end
      end
      local reply, why = work:fill(items, 0)
      if reply and reply.error and not reply.nochest then problem = reply.error end
      if not reply and next(items) then problem = why end
      for _, p in ipairs(plan) do
        local done = p.goes
        for name, n in pairs(p.items) do
          local got = work:move(name, p.u.feed, nil, n)
          if got < n then
            added(p.u, name, got - n)
            sent = sent - (n - got)
          end
          for _, it in ipairs(p.rc.ins) do
            if it.name == name then done = math.min(done, math.floor(got / it.count)) end
          end
        end
        p.q.sent = p.q.sent - (p.goes - done)
      end
      work:empty(input)
    end
    for _, q in ipairs(requests) do
      if q.dirty then saveRequest(q) end
      q.dirty = nil
    end

    -- how each machine and request is doing
    local working, broken = 0, 0
    for _, u in ipairs(units) do
      local colour, text
      if isLearning(u.feed) or isLearning(u.out) then
        colour, text = "yellow", "learning a recipe"
      elseif u.found then
        local w = waiting(u)
        local name = next(w)
        if not u.present then colour, text = "red", "not on network"
        elseif r.unsure[u.name] then colour, text = "red", "not taken as a feeder"
        elseif stalled(u, now) then colour, text = "red", "not working"
        elseif name then colour, text = total(w) >= mekfeed.STACK and "orange" or "yellow", "making from " .. nice(name)
        else colour, text = "lime", "idle" end
      elseif u.m then
        local item = mekfeed.current(u.m)
        colour, text = mekfeed.status(u.m, item and ("making from " .. nice(item)))
      else
        colour, text = "red", "no feeder"
      end
      u.state, u.tile = text, colour
      u.colour = ({ red = "red", orange = "lime", yellow = "lime", lime = "gray" })[colour] or "gray"
      if colour == "red" then broken = broken + 1
      elseif colour == "orange" or colour == "yellow" then working = working + 1 end
    end
    for _, q in ipairs(requests) do
      if not q.state then q.state = toSend(q) > 0 and "queued" or "in the machine" end
    end

    if outWhy then problem = problem or outWhy
    elseif outStuck then
      problem = problem or ("the %s is full: what's made is waiting in the machines"):format(work.remote and "ender chest" or "storage input chest")
    end
    if news and os.clock() < news[3] then
      self.message = { news[1], news[2] }
    elseif problem then
      say("Couldn't move items: " .. problem, "red")
    elseif work.problem then
      say(("Not using the work chest: %s."):format(work.problem), "orange")
    elseif broken > 0 then
      local u
      for _, x in ipairs(units) do
        if x.tile == "red" then u = u or x end
      end
      local why = {
        ["no feeder"] = "its feeder isn't on the network",
        ["no output chest"] = "its output chest isn't on the network",
        ["not moving"] = "nothing goes out of its feeder: is the machine running, and does a hopper or pipe take from the feeder?",
        ["not working"] = "its inputs sit in it and nothing comes out: has it power, and is the recipe right?",
        ["not on network"] = "it isn't on the network any more: is its modem on?",
        ["not taken as a feeder"] = "the storage computer won't fill it: 'install update' the storage computer",
      }
      say(("%s: %s"):format(u.title, why[u.state] or u.state), "red")
    elseif #recipes == 0 then
      return
    elseif makesNote and #requests == 0 then
      say(makesNote, "orange")
    elseif #requests == 0 then
      say("Tap +1, +8 or +64 by what you want made. Everything kept is stocked.")
    elseif sent > 0 then
      say(("Sent %d items to the machine%s."):format(sent, #units == 1 and "" or "s"))
    else
      say(("%s: %s."):format(requests[1].recipe.title, requests[1].state))
    end
    status(broken > 0 and "alert" or working > 0 and "running" or "idle",
      ("%d of %d machines working, %d requests"):format(working, #units, #requests))
  end

  ---------------------------------------------------------------- screen

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

  -- Every recipe with how many are stored (and kept) and the request
  -- buttons, then the requests (tap x to cancel one).
  local function drawRequests(win, w, h, target, footer)
    zones[target] = {}
    local fit = screen.fit
    local btnW = 0
    for _, n in ipairs(BUTTONS) do btnW = btnW + #(" +" .. n .. " ") + 1 end
    local bx = w - btnW + 1
    local haveR = bx - 2
    screen.put(win, 2, 3, "Make", "yellow")
    screen.put(win, haveR - 3, 3, "Have", "yellow")
    screen.put(win, bx, 3, "Request", "yellow")
    local queueRows = math.min(QUEUE_SHOWN, #requests)
    local rows = h - 4 - #footer - (queueRows > 0 and queueRows + 1 or 0)
    local keyed = target == "terminal"
    if keyed then
      picked = math.max(1, math.min(picked, #recipes))
      if picked <= scroll then scroll = picked - 1 end
      if picked > scroll + rows then scroll = picked - rows end
    end
    scroll = math.max(0, math.min(scroll, #recipes - rows))
    for i = 1, rows do
      local rc, y = recipes[scroll + i], 3 + i
      if rc then
        local bg = keyed and scroll + i == picked and "gray" or "black"
        local nameW = haveR - 8
        local can = goesFrom(rc, counts) > 0
        screen.put(win, 1, y, (" "):rep(haveR + 1), "white", bg)
        local title = rc.title .. (rc.count > 1 and (" x" .. rc.count) or "")
        screen.put(win, 2, y, fit(title, nameW), can and "white" or "lightGray", bg)
        local note = rc.keep and (" keep " .. rc.keep) or (" from " .. sideText(rc.ins))
        if #title + 2 < nameW then
          screen.put(win, 2 + #title, y, fit(note, nameW - #title), rc.keep and "lime" or (bg == "gray" and "lightGray" or "gray"), bg)
        end
        local n = counts[rc.make] or 0
        local have = n > 9999 and "9999+" or tostring(n)
        screen.put(win, haveR - #have + 1, y, have, rc.keep and n < rc.keep and "orange" or "white", bg)
        local x = bx
        for _, k in ipairs(BUTTONS) do
          x = button(win, target, x, y, (" +%d "):format(k), { add = rc, n = k }, "black", can and "lightGray" or "gray")
        end
      end
    end
    if #recipes == 0 then
      screen.put(win, 2, 4, fit("No recipes yet: give a machine one on the setup screen.", w - 2), "gray")
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
        local text = ("%s %d/%d%s: %s"):format(q.recipe and q.recipe.title or "?", q.made, q.count,
          q.job and " (overseer)" or q.keep and " (kept)" or "", q.state or "queued")
        screen.put(win, 2, y + i, fit(text, w - 6), "white")
        button(win, target, w - 3, y + i, " x ", { cancel = q.file }, "white", "red")
      end
    end
    for i, line in ipairs(footer) do screen.put(win, 1, h - #footer + i, fit(line[1], w), line[2]) end
  end

  function self.key()
    local key = { self.message[1], self.message[2], scroll, picked, #recipes }
    for _, rc in ipairs(recipes) do key[#key + 1] = rc.key .. "=" .. (counts[rc.make] or 0) .. "/" .. (rc.keep or "") .. "/" .. goesFrom(rc, counts) end
    for _, q in ipairs(requests) do key[#key + 1] = table.concat({ q.key, q.made, q.count, q.state or "" }, "/") end
    for _, u in ipairs(units) do key[#key + 1] = table.concat({ u.title, u.state or "" }, "/") end
    return table.concat(key, "|")
  end

  function self.draw(win, w, h)
    local busy = 0
    for _, u in ipairs(units) do
      if u.colour == "lime" then busy = busy + 1 end
    end
    screen.put(win, 2, 2, screen.fit(("%d machine%s, %d working, %d recipes"):format(#units, #units == 1 and "" or "s",
      busy, #recipes), w - 2), "lightGray")
    local footer = {}
    for _, line in ipairs(screen.wrap(self.message[1], w, (self.message[2] == "red" or self.message[2] == "orange") and 4 or 2)) do footer[#footer + 1] = { line, self.message[2] } end
    footer[#footer + 1] = { w >= 50 and "Arrows pick. Enter +1, 8 +8, 6 +64. X cancels last" or "Enter +1, 8 +8, 6 +64, X cancels",
      "gray" }
    drawRequests(win, w, h, "terminal", footer)
  end

  -- The monitor's Custom page: the same, to tap.
  self.monitorPage = { title = "Custom",
    key = function() return self.key() end,
    draw = function(win, w, h) drawRequests(win, w, h, "monitor", {}) end,
  }

  function self.tiles()
    local tiles = {}
    for _, u in ipairs(units) do tiles[#tiles + 1] = { u.title, u.state or "idle", u.tile or "lime" } end
    return tiles
  end

  local function cancel(file)
    local q = files.read(file)
    if fs.exists(file) then fs.delete(file) end
    if type(q) == "table" and q.job then
      q.ok, q.why = false, "cancelled at the custom machine"
      report(q)
    end
    for i = #requests, 1, -1 do
      if requests[i].file == file then table.remove(requests, i) end
    end
  end

  local function act(a)
    if a.add then
      request(a.add, a.n * a.add.count)
      tell(("Asked for %d %s."):format(a.n * a.add.count, a.add.title), "lime")
    elseif a.scroll then
      scroll = math.max(0, scroll + a.scroll)
      picked = math.max(1, math.min(#recipes, picked + a.scroll))
    elseif a.cancel then
      cancel(a.cancel)
      tell("Cancelled. What's already in a machine still gets made (a kept one is asked for again when it's short).", "lime")
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
    if e == "key" and ev[2] == keys.up then picked = math.max(1, picked - 1)
    elseif e == "key" and ev[2] == keys.down then picked = math.min(#recipes, picked + 1)
    elseif e == "key" and ev[2] == keys.pageUp then picked = math.max(1, picked - 8)
    elseif e == "key" and ev[2] == keys.pageDown then picked = math.min(#recipes, picked + 8)
    elseif e == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) and recipes[picked] then
      act({ add = recipes[picked], n = 1 })
    elseif e == "char" and (ev[2] == "8" or ev[2] == "6") and recipes[picked] then
      act({ add = recipes[picked], n = ev[2] == "8" and 8 or 64 })
    elseif e == "char" and ev[2]:lower() == "x" and #requests > 0 then
      act({ cancel = requests[#requests].file })
    elseif e == "mouse_scroll" then picked = math.max(1, math.min(#recipes, picked + ev[2]))
    elseif x then tap("terminal", x, y)
    end
    return false
  end

  ---------------------------------------------------------------- commands

  local function matching(text)
    text = text:lower()
    local exact, part = {}, {}
    for _, rc in ipairs(recipes) do
      local name = rc.title:lower()
      if name == text or rc.make == text or rc.make == itemId(text) then exact[#exact + 1] = rc
      elseif name:find(text, 1, true) or rc.make:find(text, 1, true) then part[#part + 1] = rc end
    end
    for _, rc in ipairs(part) do exact[#exact + 1] = rc end
    return exact
  end

  -- Every machine a recipe can go on, numbered for the commands: each found
  -- one on the cable, then the hidden ones. { key, title, where }.
  local function numbered()
    local out = {}
    for _, name in ipairs(candidates()) do
      out[#out + 1] = { key = "m:" .. name, title = titleOf(name), where = name }
    end
    local entries = self.set:entries()
    local titles = self.set:titles(entries)
    for i, e in ipairs(entries) do
      out[#out + 1] = { key = "l:" .. e.feeder, title = e.machine and titleOf(e.machine) or titles[i],
        where = ("fed by %s, out to %s"):format(e.feeder, e.output or "?") }
    end
    return out
  end

  local function printMachines(list)
    for i, m in ipairs(list) do
      local recs = recipesAt(m.key)
      do
        print(("%d  %s: %s"):format(i, m.title, m.where))
        for j, raw in ipairs(recs) do
          local rc = compile(raw)
          print(("   %d. %s"):format(j, rc and ("%s = %s, %s"):format(sideText(rc.ins), sideText(rc.outs), keepText(rc.keep)) or "broken"))
        end
      end
    end
    for _, name in ipairs(seenMachines()) do
      print(("-  %s: needs a feeder and output chest (setup screen, Machines)"):format(titleOf(name)))
    end
    if #list == 0 and #seenMachines() == 0 then print("No machine found: put a wired modem on one, join it to the cable and right-click it.") end
  end

  local function machineArg(text)
    local list = numbered()
    local n = tonumber(text or "")
    if n and list[n] then return list[n] end
    printMachines(list)
    return nil
  end

  local function usage()
    print("factory custom                              the machines, recipes and requests")
    print("factory custom <item> <count>               make count of it")
    print("factory custom recipe <machine> <in> = <out> e.g. recipe 1 2 iron_ingot coal = steel_ingot")
    print("factory custom keep <machine> <recipe> <n|off>  keep n in storage for good")
    print("factory custom forget <machine> <recipe>    remove a recipe")
    print("factory custom cancel [n]                   cancel request n (no number: all of them)")
  end

  -- 'factory custom ...'. True if args was it.
  function self.command(args)
    if args[1] ~= "custom" then return false end
    refreshUnits()
    local queued = loadRequests()
    local verb = args[2]
    if verb == "cancel" then
      local n = tonumber(args[3] or "")
      local gone = 0
      for i, q in ipairs(queued) do
        if not n or n == i then
          cancel(q.file)
          gone = gone + 1
        end
      end
      print(gone > 0 and ("Cancelled %d request(s)."):format(gone) or "Nothing to cancel.")
      f.wake()
      return true
    elseif verb == "recipe" then
      local m = machineArg(args[3])
      if not m then
        print("Usage: factory custom recipe <machine> <in> = <out>")
        return true
      end
      local words = {}
      for k = 4, #args do words[#words + 1] = args[k] end
      local ins, outs, why = parse(words)
      if not ins then
        print("Couldn't read that: " .. why .. ".")
        print("e.g. factory custom recipe 1 2 iron_ingot coal = steel_ingot (counts before items; mod:item for mods)")
        return true
      end
      local recs = recipesAt(m.key)
      recs[#recs + 1] = { ins = ins, outs = outs }
      saveRecipesAt(m.key, recs)
      print(("%s: %s = %s (recipe %d)."):format(m.title, sideText(ins), sideText(outs), #recs))
      print(("Keep some in stock: factory custom keep %s %d <n>"):format(args[3], #recs))
      f.wake()
      return true
    elseif verb == "keep" or verb == "forget" then
      local m = machineArg(args[3])
      local j = tonumber(args[4] or "")
      local recs = m and recipesAt(m.key) or {}
      if not m or not j or not recs[j] or (verb == "keep" and not args[5]) then
        for k, raw in ipairs(recs) do
          local rc = compile(raw)
          print(("  recipe %d: %s"):format(k, rc and ("%s = %s, %s"):format(sideText(rc.ins), sideText(rc.outs), keepText(rc.keep)) or "broken"))
        end
        print(verb == "keep" and "Usage: factory custom keep <machine> <recipe> <n|off>" or "Usage: factory custom forget <machine> <recipe>")
        return true
      end
      if verb == "forget" then
        table.remove(recs, j)
        print("Recipe removed.")
      else
        local n = tonumber(args[5])
        recs[j].keep = n and n > 0 and math.floor(n) or nil
        print(recs[j].keep and ("Keeps %d %s in storage from now on."):format(recs[j].keep, nice(recs[j].outs[1].name))
          or "Only on request now.")
      end
      saveRecipesAt(m.key, recs)
      f.wake()
      return true
    end
    local count = tonumber(args[#args] or "")
    if verb and count and #args >= 3 then
      local rc = matching(table.concat(args, " ", 2, #args - 1))[1]
      if not rc then
        print("No custom recipe makes that: 'factory custom' lists them.")
        return true
      end
      local wanted = whole(rc, count)
      request(rc, wanted)
      print(("Asked for %d %s. It starts on the factory's next round."):format(wanted, rc.title))
      return true
    end
    if verb then
      usage()
      return true
    end
    printMachines(numbered())
    for i, q in ipairs(queued) do
      print(("Request %d: %s %d/%d%s"):format(i, q.recipe and q.recipe.title or q.key, q.made, q.count,
        q.job and " (for the craft overseer)" or q.keep and " (kept in stock)" or ""))
    end
    usage()
    return true
  end

  return self
end

return M
