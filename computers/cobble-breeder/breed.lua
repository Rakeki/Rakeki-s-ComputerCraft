-- Cobblemon breeder: breeds better and better Pokemon from a Cobbreeding
-- pasture, from a command computer (creative / op). Every egg the pasture
-- lays (a hopper under it fills the egg chest) is read before it hatches.
-- An egg whose IVs beat the breeder it would replace goes to the Cobblemon
-- Incubator (through the hopper that feeds it), and the monitor tells you
-- which breeder to recall and to put the new one in once it hatches. Other
-- eggs go to the reject chest (or are deleted, or hatched anyway: setup).
-- The monitor shows every breeder's six IVs and how close you are to a
-- 6x31 Pokemon.
--
--   breed                     run it on the monitor (startup.lua runs it once set up)
--   breed setup               find the pasture and chests around this computer, pick each
--   breed scan                read the Pokemon sent out next to this computer (the monitor's Scan button)
--   breed ivs <n> <hp> <atk> <def> <spa> <spd> <spe>   type breeder n's IVs by hand
--   breed monitor [name|none] pick the monitor
--   breed forget              forget the egg history and the best egg (keeps the breeders)
--
-- Needs Cobbreeding's egg encryption off (eggEncryptionEnabled false in
-- config/cobbreeding/main.json, then /cobbreeding reload): encrypted eggs
-- can't be read by anything. A Pokemon in a pasture has no data the game
-- shows, so breeders are learned once (Scan, or typed) and swaps are
-- followed from then on. Scoring is in config.lua.
local screen = require("lib.screen") -- flicker-free drawing
local files = require("lib.files") -- crash-safe save files
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local config = fs.exists("config.lua") and require("config") or {}

local ROUND_EVERY = 5 -- seconds between looks at the pasture and the egg chest
local SETUP_FILE = "/.breed_setup" -- where the pasture and chests are
local STATE_FILE = "/.breed_state" -- breeders, swaps waiting, egg history
local MANUAL_FILE = "/.breed_manual" -- Pokemon scanned or typed in another tab, picked up next round
local SEARCH_RADIUS = 8 -- 'breed setup' looks this far from the computer
local HISTORY = 30 -- eggs remembered for the list
local KEEP_SCANNED = 12 -- Pokemon remembered from scans that aren't breeders (yet)
local MAX_IV, PERFECT = 31, 186
local SCORE = config.score or "total" -- "total": sum of IVs; "perfect": count of 31s first
local MIN_GAIN = config.minGain or 1 -- an egg must beat a breeder's total by this much
local KEEP_SHINY = config.keepShiny ~= false -- hatch shiny eggs even when they're not better
local NATURE = config.nature -- e.g. "adamant": only eggs with this nature can take a breeder's place
local SCAN_RANGE = config.scanRange or 8 -- Scan reads Pokemon this close to the computer
local MONITOR_SCALE = config.monitorScale or 0.5

local STATS = { { "hp", "HP" }, { "atk", "Atk" }, { "def", "Def" }, { "spa", "SpA" }, { "spd", "SpD" }, { "spe", "Spe" } }
-- every name a stat goes by: egg properties (hp_iv, special_attack_iv),
-- Cobblemon's save data (cobblemon:special_attack) and showdown ids (spa)
local STAT_KEYS = {
  hp = "hp", atk = "atk", attack = "atk", def = "def", defence = "def", defense = "def",
  spa = "spa", special_attack = "spa", spd = "spd", special_defence = "spd", special_defense = "spd",
  spe = "spe", speed = "spe",
}

local args = { ... }
local setup = files.read(SETUP_FILE)
local state -- loaded below: see loadState
local ui = { zones = {}, msg = nil, msgColour = "white" }
local problem -- why it can't go on right now: { word, text, colour }
local wantScan = false

---------------------------------------------------------------- reading Cobblemon data

-- SNBT, as /data get prints it, into Lua tables: compounds become tables
-- with string keys, lists and typed arrays ([I; 1, 2]) become arrays,
-- numbers lose their suffix (1b, 0.5f).
local function parseSnbt(s)
  local pos = 1
  local function ws() pos = s:find("%S", pos) or #s + 1 end
  local function char() return s:sub(pos, pos) end
  local function str()
    local quote, out = char(), {}
    pos = pos + 1
    while pos <= #s do
      local c = char()
      if c == "\\" then
        out[#out + 1] = s:sub(pos + 1, pos + 1)
        pos = pos + 2
      elseif c == quote then
        pos = pos + 1
        return table.concat(out)
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    error("unfinished string", 0)
  end
  local function bare()
    local word = s:match("^[%w_%-%.%+]+", pos) -- no ':': it ends a key, and namespaced keys are quoted
    if not word then error(("unexpected %q at %d"):format(char(), pos), 0) end
    pos = pos + #word
    return word
  end
  local function scalar(word)
    local n = word:match("^([%-+]?%d*%.?%d+[eE]?[%-+]?%d*)[bBsSlLfFdD]?$")
    if n and tonumber(n) then return tonumber(n) end
    if word == "true" or word == "false" then return word == "true" end
    return word
  end
  local value
  local function items(close, fn)
    ws()
    if char() == close then pos = pos + 1 return end
    while true do
      fn()
      ws()
      local c = char()
      pos = pos + 1
      if c == close then return end
      if c ~= "," then error(("expected , or %s at %d"):format(close, pos - 1), 0) end
    end
  end
  value = function()
    ws()
    local c = char()
    if c == "{" then
      pos = pos + 1
      local t = {}
      items("}", function()
        ws()
        local key = (char() == '"' or char() == "'") and str() or bare()
        ws()
        if char() ~= ":" then error(("expected : at %d"):format(pos), 0) end
        pos = pos + 1
        t[key] = value()
      end)
      return t
    elseif c == "[" then
      pos = pos + 1
      if s:match("^[BIL];", pos) then pos = pos + 2 end
      local t = {}
      items("]", function() t[#t + 1] = value() end)
      return t
    elseif c == '"' or c == "'" then
      return str()
    end
    return scalar(bare())
  end
  return value()
end

-- "cobblemon:special_attack" -> "special_attack"
local function plain(id) return id and (tostring(id):gsub("^.*:", "")) or nil end

-- "mr_mime" -> "Mr Mime"
local function nice(id)
  if not id then return "?" end
  return (plain(id):gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end))
end

local function genderOf(text)
  text = tostring(text or ""):lower()
  if text == "male" then return "M" elseif text == "female" then return "F" end
  return text == "genderless" and "-" or nil
end

-- A UUID int array (from getBlockInfo or /data get) as text, the same both ways.
local function uuidKey(arr)
  local parts = {}
  for i = 1, 4 do parts[i] = ("%d"):format(arr[i] or 0) end
  return table.concat(parts, ",")
end

-- The Pokemon in an egg, from Cobbreeding's pokemon_properties: Cobblemon's
-- property string, "bulbasaur gender=FEMALE nature=cobblemon:bold hp_iv=31 ..."
local function parseProps(text)
  local mon = { ivs = {} }
  for word in tostring(text):gmatch("%S+") do
    local k, v = word:match("^([^=]+)=(.*)$")
    if not k then
      mon.species = mon.species or plain(word)
    else
      k = k:lower()
      local stat = k:match("^(.-)_iv$")
      if stat and STAT_KEYS[stat] then mon.ivs[STAT_KEYS[stat]] = tonumber(v)
      elseif k == "gender" then mon.gender = genderOf(v)
      elseif k == "nature" then mon.nature = plain(v)
      elseif k == "ability" then mon.ability = plain(v)
      elseif k == "shiny" then mon.shiny = v:lower() == "true"
      end
    end
  end
  return mon
end

-- A Pokemon from its save data (the Pokemon compound of /data get entity).
local function monFromSave(t)
  local mon = {
    species = plain(t.Species), gender = genderOf(t.Gender), nature = plain(t.Nature),
    shiny = t.Shiny == 1 or t.Shiny == true, ivs = {},
  }
  local ability = t.Ability
  mon.ability = plain(type(ability) == "table" and ability.AbilityName or ability)
  -- Base only: hyper training doesn't pass to eggs
  local base = type(t.IVs) == "table" and (t.IVs.Base or t.IVs) or {}
  for k, v in pairs(base) do
    local stat = STAT_KEYS[plain(k):lower()]
    if stat and type(v) == "number" then mon.ivs[stat] = v end
  end
  return mon
end

---------------------------------------------------------------- judging

local function total(mon)
  local t = 0
  for _, s in ipairs(STATS) do t = t + (mon.ivs[s[1]] or 0) end
  return t
end

local function perfects(mon)
  local n = 0
  for _, s in ipairs(STATS) do
    if mon.ivs[s[1]] == MAX_IV then n = n + 1 end
  end
  return n
end

local function isDitto(mon) return mon.species == "ditto" end

-- Does a beat b? By MIN_GAIN in total, or (scoring "perfect") by more 31s.
local function better(a, b)
  if SCORE == "perfect" then
    local pa, pb = perfects(a), perfects(b)
    if pa ~= pb then return pa > pb end
  end
  return total(a) >= total(b) + MIN_GAIN
end

local function weaker(a, b)
  if SCORE == "perfect" and perfects(a) ~= perfects(b) then return perfects(a) < perfects(b) end
  return total(a) < total(b)
end

-- What a breeder will be once its swap is made: the kept egg waiting to
-- take its place, else what it is now.
local function projected(uuid) return state.swaps[uuid] or state.mons[uuid] end

-- The breeder an egg would take the place of: the weakest that isn't a
-- Ditto. Without a Ditto in the pasture the pair needs a male and a female,
-- so only one of the egg's gender will do.
local function targetFor(egg)
  local ditto = false
  for _, u in ipairs(state.breeders) do
    local m = state.mons[u]
    if m and isDitto(m) then ditto = true end
  end
  local pick
  for _, u in ipairs(state.breeders) do
    local m = projected(u)
    local genderOk = ditto or not egg.gender or egg.gender == "-" or not m.gender or m.gender == egg.gender
    if not isDitto(m) and genderOk and (not pick or weaker(m, projected(pick))) then pick = u end
  end
  return pick
end

local function unknownBreeders()
  local n = 0
  for _, u in ipairs(state.breeders) do
    if not projected(u) then n = n + 1 end
  end
  return n
end

-- "Bulbasaur F 31/31/28/31/30/31 (182)"
local function describe(mon)
  local ivs = {}
  for i, s in ipairs(STATS) do ivs[i] = tostring(mon.ivs[s[1]] or "?") end
  return ("%s%s %s (%d)"):format(nice(mon.species), mon.gender and mon.gender ~= "-" and (" " .. mon.gender) or "",
    table.concat(ivs, "/"), total(mon))
end

---------------------------------------------------------------- state

local function loadState()
  state = files.read(STATE_FILE) or {}
  state.breeders = state.breeders or {} -- pasture order: uuid keys
  state.mons = state.mons or {} -- uuid key -> what's known of it
  state.swaps = state.swaps or {} -- breeder uuid -> the kept egg that should replace it
  state.eggs = state.eggs or {} -- newest first: { mon, verdict }
  state.counts = state.counts or { judged = 0, kept = 0, rejected = 0 }
end

local dirty = false
local function saveState()
  if dirty then files.write(STATE_FILE, state) end
  dirty = false
end

local function stamp() return textutils.formatTime(os.time(), true) end

local function say(text, colour)
  ui.msg, ui.msgColour = text, colour or "white"
end

local function log(text)
  print(("%s  %s"):format(stamp(), text))
  if report then report.log(text) end
end

local function copyMon(mon)
  local c = {}
  for k, v in pairs(mon) do c[k] = v end
  c.ivs = {}
  for k, v in pairs(mon.ivs) do c.ivs[k] = v end
  return c
end

-- Forget Pokemon that aren't breeders and aren't among the last few scanned.
local function prune()
  local keep, extra = {}, {}
  for _, u in ipairs(state.breeders) do keep[u] = true end
  for u, m in pairs(state.mons) do
    if not keep[u] then extra[#extra + 1] = { u, m.at or 0 } end
  end
  table.sort(extra, function(a, b) return a[2] > b[2] end)
  for i, e in ipairs(extra) do
    if i > KEEP_SCANNED then state.mons[e[1]] = nil end
  end
end

-- Pokemon scanned or typed in another tab ('breed scan', 'breed ivs').
local function takeManual()
  local list = files.read(MANUAL_FILE)
  if not list then return end
  files.delete(MANUAL_FILE)
  for _, e in ipairs(list) do
    state.mons[e.uuid] = e.mon
    dirty = true
  end
end

---------------------------------------------------------------- the world

local function exec(command)
  local ok, out = commands.exec(command)
  return ok, out and out[1]
end

local function blockAt(pos)
  return commands.getBlockInfo(pos.x, pos.y, pos.z)
end

-- How many slots a container has (getBlockInfo doesn't say).
local function slotsOf(name)
  if name:find("hopper") then return 5 end
  if name:find("dispenser") or name:find("dropper") then return 9 end
  return 27
end

local function freeSlot(pos)
  local info = blockAt(pos)
  if not info or not info.nbt then return nil end
  local used = {}
  for _, item in ipairs(info.nbt.Items or {}) do used[item.Slot] = true end
  for i = 0, slotsOf(info.name) - 1 do
    if not used[i] then return i end
  end
end

local function clearSlot(pos, slot)
  return exec(("item replace block %d %d %d container.%d with minecraft:air"):format(pos.x, pos.y, pos.z, slot))
end

-- Copy the egg into a free slot of to, then empty its old slot, so an egg
-- is never lost if the copy fails. false, "full" when there's no room.
local function moveEgg(from, slot, to)
  local free = freeSlot(to)
  if not free then return false, "full" end
  local ok, why = exec(("item replace block %d %d %d container.%d from block %d %d %d container.%d"):format(
    to.x, to.y, to.z, free, from.x, from.y, from.z, slot))
  if not ok then return false, why end
  return clearSlot(from, slot)
end

-- The uuid key of every Pokemon in the pasture, or nil and why not.
local function pastured()
  local info = blockAt(setup.pasture)
  if not info or not info.name:find("pasture") then return nil, "The pasture isn't there any more. Run 'breed setup'." end
  local list = {}
  for _, t in ipairs(info.nbt and info.nbt.TetherPokemon or {}) do
    if t.UUID then list[#list + 1] = uuidKey(t.UUID) end
  end
  return list
end

-- The eggs in the egg chest: { slot, mon } each, or { slot, encrypted }.
local function eggsWaiting()
  local info = blockAt(setup.eggs)
  if not info or not info.nbt then return nil end
  local eggs = {}
  for _, item in ipairs(info.nbt.Items or {}) do
    local c = item.components or {}
    local props = c["cobbreeding:pokemon_properties"]
    if props then
      eggs[#eggs + 1] = { slot = item.Slot, mon = parseProps(props) }
    elseif c["cobbreeding:egg_info"] then
      eggs[#eggs + 1] = { slot = item.Slot, encrypted = true }
    end
  end
  return eggs
end

-- Every Pokemon out within SCAN_RANGE of this computer, with its uuid key,
-- nearest first. Pastured ones have no data to read, so they're never in
-- it. Wild ones are kept too: there's no reliable owner in the data (older
-- catches have no original trainer), and only a Pokemon whose uuid turns up
-- in the pasture is ever used. Also returns what was skipped, as text for
-- the screen: data it couldn't read (logged in full to /errors.log).
local function scanNearby()
  local x, y, z = commands.getBlockPosition()
  local _, out = commands.exec(("execute as @e[type=cobblemon:pokemon,x=%d,y=%d,z=%d,distance=..%d,sort=nearest] run data get entity @s Pokemon")
    :format(x, y, z, SCAN_RANGE))
  local found, unread = {}, 0
  for _, line in ipairs(out or {}) do
    local data = line:match("has the following entity data: (.*)$")
    local ok, t = false, "no data in the answer"
    if data then ok, t = pcall(parseSnbt, data) end
    if ok and type(t) == "table" and type(t.UUID) == "table" then
      local mon = monFromSave(t)
      mon.from, mon.at = "scan", os.epoch("utc")
      found[#found + 1] = { uuid = uuidKey(t.UUID), mon = mon }
    elseif not line:find("[Ff]ound no elements") then -- a pastured one: nothing to read, as expected
      unread = unread + 1
      if errlog then errlog.warn("Scan couldn't read a Pokemon: " .. tostring(t), { line = line:sub(1, 600) }) end
    end
  end
  return found, unread > 0 and ("couldn't read %d (see /errors.log)"):format(unread) or ""
end

---------------------------------------------------------------- a round

-- Follow the pasture: a new Pokemon that arrives once a breeder with a swap
-- waiting has left is taken to be the kept egg, so you never scan a swap.
local function followPasture(now)
  local here = {}
  for _, u in ipairs(now) do here[u] = true end
  for _, u in ipairs(now) do
    if not state.mons[u] then
      for target, egg in pairs(state.swaps) do
        if not here[target] then
          local mon = copyMon(egg)
          mon.from, mon.assumed, mon.at = "egg", true, os.epoch("utc")
          state.mons[u] = mon
          state.swaps[target] = nil
          log("Swap made: the new one is " .. describe(mon))
          say("Swap made. Scan the new one to be sure, if you like.", "lime")
          break
        end
      end
    end
  end
  -- a breeder left and a known Pokemon took its place: that swap was skipped
  local unknown = false
  for _, u in ipairs(now) do
    if not state.mons[u] then unknown = true end
  end
  for target, egg in pairs(state.swaps) do
    if not here[target] and not unknown and #now >= (egg.size or 0) then state.swaps[target] = nil end
  end
  if table.concat(now, "|") ~= table.concat(state.breeders, "|") then
    state.breeders = now
    prune()
    dirty = true
  end
end

local function remember(mon, verdict)
  table.insert(state.eggs, 1, { mon = mon, verdict = verdict })
  while #state.eggs > HISTORY do table.remove(state.eggs) end
  state.counts.judged = state.counts.judged + 1
  if verdict == "keep" then state.counts.kept = state.counts.kept + 1
  elseif verdict == "rej" then state.counts.rejected = state.counts.rejected + 1 end
  -- a copy: textutils.serialize refuses a table that's in the state twice
  if not state.best or better(mon, state.best) then state.best = copyMon(mon) end
  dirty = true
end

-- Decide one egg and move it. false when it has to wait (a full chest).
local function judge(egg)
  local mon = egg.mon
  local target = targetFor(mon)
  local natureOk = not NATURE or mon.nature == NATURE
  local to, verdict
  if target and natureOk and better(mon, projected(target)) then
    to, verdict = setup.feed, "keep"
  elseif KEEP_SHINY and mon.shiny then
    to, verdict = setup.feed, "shiny"
  elseif setup.rejects == "hatch" then
    to, verdict = setup.feed, "hatch"
  else
    to, verdict = setup.rejects ~= "delete" and setup.rejects or nil, "rej"
  end

  local ok, why
  if to then ok, why = moveEgg(setup.eggs, egg.slot, to) else ok, why = clearSlot(setup.eggs, egg.slot) end
  if not ok then
    local where = to == setup.feed and "The incubator's hopper" or "The reject chest"
    problem = why == "full" and { "FULL", where .. " is full. Waiting...", "orange" }
      or { "STUCK", "Can't move an egg: " .. tostring(why), "red" }
    return false
  end

  if verdict == "keep" then
    local old = projected(target)
    local kept = copyMon(mon)
    kept.size = #state.breeders
    state.swaps[target] = kept
    log(("Kept %s: it beats %s"):format(describe(mon), describe(old)))
  end
  remember(mon, verdict)
  return true
end

local function round()
  problem = nil
  if not setup then
    problem = { "SET UP", "Type 'breed setup' on this computer first.", "red" }
    return
  end
  takeManual()
  if wantScan then
    wantScan = false
    local found, skipped = scanNearby()
    local names = {}
    for _, f in ipairs(found) do
      state.mons[f.uuid] = f.mon
      names[#names + 1] = describe(f.mon)
    end
    dirty = true
    local extra = skipped ~= "" and (" (" .. skipped .. ")") or ""
    if #found == 0 then
      say(("Nothing to scan: send your Pokemon out within %d blocks of the computer.%s"):format(SCAN_RANGE, extra), "orange")
    else
      say("Scanned " .. table.concat(names, ", ") .. extra, "lime")
    end
    log("Scan: " .. (#found > 0 and table.concat(names, ", ") or "nothing") .. extra)
  end

  local now, why = pastured()
  if not now then
    problem = { "NO PASTURE", why, "red" }
    return
  end
  followPasture(now)
  prune()
  saveState()

  if #now == 0 then
    problem = { "EMPTY", "Put your breeders in the pasture.", "orange" }
    return
  end
  if unknownBreeders() > 0 then
    problem = { "SCAN", "I don't know every breeder's IVs yet: eggs wait in the chest.", "orange" }
    return
  end
  if state.paused then return end

  local eggs = eggsWaiting()
  if not eggs then
    problem = { "NO CHEST", "The egg chest isn't there any more. Run 'breed setup'.", "red" }
    return
  end
  for _, egg in ipairs(eggs) do
    if egg.encrypted then
      problem = { "ENCRYPTED", "Eggs are encrypted: set eggEncryptionEnabled false in config/cobbreeding/main.json, then /cobbreeding reload.", "red" }
    elseif not judge(egg) then
      break
    end
  end
  saveState()
end

---------------------------------------------------------------- drawing

local display -- lib/screen.lua on the monitor, or this computer's screen
local win -- the window the frame being drawn goes into
local fit = screen.fit

local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end

local function button(x, y, label, fg, bg, action)
  local text = " " .. label .. " "
  put(x, y, text, fg, bg)
  ui.zones[#ui.zones + 1] = { x1 = x, x2 = x + #text - 1, y = y, action = action }
  return x + #text + 1
end

local function bar(x, y, w, frac, colour)
  if w < 1 then return end
  local filled = math.floor(math.max(0, math.min(1, frac or 0)) * w + 0.5)
  put(x, y, (" "):rep(filled), "white", colour)
  put(x + filled, y, (" "):rep(w - filled), "white", "gray")
end

local function ivColour(v)
  if not v then return "lightGray" end
  return v >= MAX_IV and "lime" or v >= 25 and "yellow" or v >= 15 and "orange" or "red"
end

local function pctOf(mon) return math.floor(total(mon) / PERFECT * 100 + 0.5) end

-- The headline: the best breeder that isn't a Ditto (a perfect Ditto is
-- where you start, not where you're going).
local function bestBreeder()
  local best, anyBest
  for _, u in ipairs(state.breeders) do
    local m = state.mons[u]
    if m then
      if not isDitto(m) and (not best or weaker(best, m)) then best = m end
      if not anyBest or weaker(anyBest, m) then anyBest = m end
    end
  end
  return best or anyBest
end

local function status()
  if problem then return problem[1], problem[3] end
  if state.paused then return "PAUSED", "gray" end
  if next(state.swaps) then return "SWAP", "orange" end
  return "BREEDING", "green"
end

local function drawCard(x, y, w, n, uuid)
  local mon = state.mons[uuid]
  local swap = state.swaps[uuid]
  local head = swap and "orange" or "gray"
  if not mon then
    put(x, y, fit((" %d  unknown"):format(n), w), "white", "red")
    local lines = screen.wrap(("Recall it, send it out next to the computer, tap Scan, put it back. Or type: breed ivs %d hp atk def spa spd spe"):format(n), w - 1, 7)
    for i, line in ipairs(lines) do put(x + 1, y + i, fit(line, w - 1), "lightGray") end
    return
  end
  local name = (" %d %s %s"):format(n, nice(mon.species), mon.gender == "-" and "" or mon.gender or "")
  local right = nice(mon.nature) .. " "
  put(x, y, fit(name, w), "white", head)
  if #name + #right + 1 <= w then put(x + w - #right, y, right, "white", head) end
  for i, s in ipairs(STATS) do
    local v = mon.ivs[s[1]]
    put(x, y + i, fit(s[2], 4), "lightGray")
    bar(x + 4, y + i, w - 7, (v or 0) / MAX_IV, ivColour(v))
    put(x + w - 2, y + i, ("%2s"):format(v or "?"), ivColour(v))
  end
  local foot = ("%d/%d  %d%%"):format(total(mon), PERFECT, pctOf(mon))
  if mon.assumed then foot = foot .. "  (from egg)" end
  put(x, y + 7, fit(foot, w), mon.assumed and "lightGray" or "white")
end

local function draw()
  local word, colour = status()
  local key = textutils.serialize({ word, problem and problem[2], state.breeders, state.mons, state.swaps,
    state.eggs[1], state.counts, state.paused, ui.msg }, { compact = true })
  if display:same(key) then return end

  ui.zones = {}
  local w, h
  win, w, h = display:frame()
  put(1, 1, (" "):rep(w), "white", colour)
  put(2, 1, "Breeder", "white", colour)
  put(w - #word, 1, word, "white", colour)

  -- how close to a 6x31 Pokemon
  local best = bestBreeder()
  local y = 3
  if best then
    local label = ("%3d%%"):format(pctOf(best))
    put(2, y, "To 6x31", "lightGray")
    bar(10, y, w - 16, total(best) / PERFECT, pctOf(best) >= 100 and "lime" or "lightBlue")
    put(w - #label, y, label, "white")
    -- the best of each stat across the breeders: what the eggs can inherit
    local x, covered = 2, 0
    for _, s in ipairs(STATS) do
      local top
      for _, u in ipairs(state.breeders) do
        local m = state.mons[u]
        local v = m and m.ivs[s[1]]
        if v and (not top or v > top) then top = v end
      end
      covered = covered + (top or 0)
      local text = ("%s %s "):format(s[2], top or "?")
      if x + #text <= w then put(x, y + 1, text, ivColour(top)) end
      x = x + #text + 1
    end
    local pair = ("pair %d%%"):format(math.floor(covered / PERFECT * 100 + 0.5))
    if x + #pair <= w + 1 then put(w - #pair, y + 1, pair, "lightGray") end
    y = y + 3
  end

  -- breeder cards, side by side as far as they fit
  local cardW = 24
  local cols = math.max(1, math.min(#state.breeders, math.floor((w - 1) / (cardW + 1))))
  cardW = math.floor((w - 1) / cols) - 1
  local bottom = h - 6 -- swap, eggs and buttons below
  for i, u in ipairs(state.breeders) do
    local row, col = math.floor((i - 1) / cols), (i - 1) % cols
    local cy = y + row * 9
    if cy + 7 > bottom then break end
    drawCard(2 + col * (cardW + 1), cy, cardW, i, u)
  end
  if #state.breeders > 0 then
    y = math.min(bottom, y + math.ceil(#state.breeders / cols) * 9)
  end

  -- what to do: the swaps waiting, or the problem
  local notes = {}
  for i, u in ipairs(state.breeders) do
    local egg = state.swaps[u]
    if egg then
      local old = state.mons[u]
      notes[#notes + 1] = { ("Swap breeder %d (%d) for the new %s once it hatches."):format(
        i, old and total(old) or 0, describe(egg)), "black", "orange" }
    end
  end
  for target, egg in pairs(state.swaps) do
    local inPasture = false
    for _, u in ipairs(state.breeders) do
      if u == target then inPasture = true end
    end
    if not inPasture then
      notes[#notes + 1] = { "Now put the new " .. describe(egg) .. " in the pasture.", "black", "orange" }
    end
  end
  if problem then notes[#notes + 1] = { problem[2], "white", problem[3] } end
  for _, n in ipairs(notes) do
    for _, line in ipairs(screen.wrap(n[1], w - 2, 3)) do
      if y > h - 3 then break end
      put(1, y, fit(" " .. line, w), n[2], n[3])
      y = y + 1
    end
  end

  -- the last eggs
  y = y + 1
  if y <= h - 2 then
    local c = state.counts
    local head = ("Eggs  %d judged  %d kept  %d rejected"):format(c.judged, c.kept, c.rejected)
    if state.best then head = head .. "  best " .. total(state.best) end
    put(2, y, fit(head, w - 2), "lightGray")
    y = y + 1
  end
  local verdicts = { keep = { "KEEP", "lime" }, shiny = { "SHINY", "yellow" }, hatch = { "hatch", "lightGray" }, rej = { "rej", "gray" } }
  for _, e in ipairs(state.eggs) do
    if y > h - 2 then break end
    local m = e.mon
    put(2, y, fit(("%s %s"):format(nice(m.species), m.gender or ""), 13), m.shiny and "yellow" or "white")
    local x = 16
    for _, s in ipairs(STATS) do
      local v = m.ivs[s[1]]
      if x + 2 <= w then put(x, y, ("%2s"):format(v or "?"), ivColour(v)) end
      x = x + 3
    end
    local v = verdicts[e.verdict] or { e.verdict, "white" }
    local tail = ("%3d %s"):format(total(m), v[1])
    if x + #tail <= w then put(x, y, tail, v[2]) end
    y = y + 1
  end

  -- buttons and the last message
  local x = button(2, h, "Scan", "white", "blue", function()
    wantScan = true
    say("Scanning...", "lightGray")
    os.queueEvent("breed_now")
  end)
  x = button(x, h, state.paused and "Resume" or "Pause", "white", state.paused and "green" or "gray", function()
    state.paused = not state.paused
    dirty = true
    saveState()
    say(state.paused and "Paused: eggs stay in the chest." or "Running again.", "white")
    os.queueEvent("breed_now")
  end)
  if ui.msg then put(x, h, fit(ui.msg, w - x + 1), ui.msgColour) end
  display:show()
end

---------------------------------------------------------------- loops

local function reportState()
  if not report then return end
  local word = status()
  local st = "running"
  if problem then st = (problem[3] == "red") and "alert" or "waiting"
  elseif state.paused then st = "paused"
  elseif next(state.swaps) then st = "waiting" end
  local best = bestBreeder()
  report.set(st, problem and problem[2] or ("%s, best breeder %s%%"):format(word:lower(), best and pctOf(best) or "?"))
end

-- One bad round is logged and the next one runs.
local function roundLoop()
  while true do
    local ok, err = (errlog and errlog.pcall or pcall)(round)
    if not ok then say("Round failed: " .. tostring(err), "red") end
    draw()
    reportState()
    local timer = os.startTimer(ROUND_EVERY)
    while true do
      local ev, id = os.pullEvent()
      if (ev == "timer" and id == timer) or ev == "breed_now" then break end
    end
  end
end

-- With the breeder on a monitor, this computer's screen says so (and logs eggs kept).
local function announce()
  if not display.name then return end
  term.clear()
  term.setCursorPos(1, 1)
  print("Breeder running on the monitor.")
  print("Kept eggs and swaps are listed here. Hold Ctrl+T to stop.")
end

local function touchLoop()
  while true do
    local ev = { os.pullEvent() }
    local event = ev[1]
    local x, y, drag = display:clicked(ev)
    if x and not drag then
      for _, z in ipairs(ui.zones) do
        if y == z.y and x >= z.x1 and x <= z.x2 then
          z.action()
          draw()
          break
        end
      end
    elseif event == "peripheral" or event == "peripheral_detach" or event == "breed_monitor" then
      -- also fired by turtles driving past: only redraws if the monitor moved
      if display:refresh() then
        announce()
        draw()
      end
    elseif event == "monitor_resize" or event == "term_resize" then
      draw()
    end
  end
end

local function run()
  loadState()
  display = screen.find({ setting = "breed.monitor", scales = { MONITOR_SCALE }, fallback = term.current() })
  announce()
  require("lib.label").set("Breeder")
  if report then report.init("cobblemon breeder") end
  if errlog then errlog.init("breed", function() return { breeders = #state.breeders } end) end
  local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, roundLoop, touchLoop,
    report and report.loop or function() sleep(math.huge) end)
  if not ok then
    if report then pcall(report.set, "error", tostring(err)) end
    error(err, 0)
  end
end

---------------------------------------------------------------- setup

-- Every pasture and container within SEARCH_RADIUS of the computer. One row
-- along x per getBlockInfos call, so the order its blocks come in is plain.
local function search()
  local cx, cy, cz = commands.getBlockPosition()
  local r = SEARCH_RADIUS
  local found = {}
  local _, line = term.getCursorPos()
  for y = cy - r, cy + r do
    term.setCursorPos(1, line)
    term.clearLine()
    write(("Looking around me... %d%%"):format(math.floor((y - cy + r) / (2 * r) * 100)))
    local rows = {}
    for z = cz - r, cz + r do
      rows[#rows + 1] = function()
        local infos = commands.getBlockInfos(cx - r, y, z, cx + r, y, z)
        for i, info in ipairs(infos) do
          local n = info.name
          local pasture = n:find("pasture") and info.nbt and info.nbt.TetherPokemon
          local container = info.nbt and (info.nbt.Items or n:find("chest") or n:find("barrel") or n:find("hopper"))
          if pasture or (container and not n:find("pasture")) then
            found[#found + 1] = { x = cx - r + i - 1, y = y, z = z, name = n, nbt = info.nbt, pasture = pasture and true }
          end
        end
      end
    end
    parallel.waitForAll(table.unpack(rows))
  end
  print()
  local function dist(b) return math.abs(b.x - cx) + math.abs(b.y - cy) + math.abs(b.z - cz) end
  table.sort(found, function(a, b) return dist(a) < dist(b) end)
  return found
end

local function eggCount(b)
  local n = 0
  for _, item in ipairs(b.nbt.Items or {}) do
    if tostring(item.id):find("^cobbreeding:") then n = n + 1 end
  end
  return n
end

-- A pick from the list: its number, or typed coordinates "x y z".
-- extra: words allowed instead ({ delete = true }). nil when left blank.
local function pick(list, question, extra)
  while true do
    print(question)
    write("> ")
    local answer = read()
    if answer == "" then return nil end
    if extra and extra[answer:lower()] then return answer:lower() end
    local n = tonumber(answer)
    if n and list[n] then return { x = list[n].x, y = list[n].y, z = list[n].z } end
    local x, y, z = answer:match("^(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)$")
    if x then return { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
    print("Type a number from the list, or x y z.")
  end
end

local function runSetup()
  print("Breeder setup. I'll look for the pasture and the chests around me.")
  local found = search()
  local pastures, boxes = {}, {}
  for _, b in ipairs(found) do
    if b.pasture then pastures[#pastures + 1] = b else boxes[#boxes + 1] = b end
  end
  local s = {}

  if #pastures == 0 then
    print(("I can't see a pasture within %d blocks. Put the computer closer, or type its x y z."):format(SEARCH_RADIUS))
  end
  for i, b in ipairs(pastures) do
    print(("  %d. pasture at %d %d %d, %d Pokemon"):format(i, b.x, b.y, b.z, #b.nbt.TetherPokemon))
  end
  if #pastures == 1 then
    s.pasture = { x = pastures[1].x, y = pastures[1].y, z = pastures[1].z }
    print("Using that pasture.")
  else
    s.pasture = pick(pastures, "Which pasture?")
    if not s.pasture then return print("Setup stopped: nothing saved.") end
  end

  print()
  for i, b in ipairs(boxes) do
    local eggs = eggCount(b)
    print(("  %d. %s at %d %d %d%s"):format(i, nice(b.name), b.x, b.y, b.z, eggs > 0 and (", " .. eggs .. " eggs") or ""))
  end
  s.eggs = pick(boxes, "Which chest does the hopper under the pasture fill? (the egg chest)")
  if not s.eggs then return print("Setup stopped: nothing saved.") end
  s.feed = pick(boxes, "Which hopper feeds the incubator?")
  if not s.feed then return print("Setup stopped: nothing saved.") end
  s.rejects = pick(boxes, "Where do eggs that aren't better go? A chest's number, 'delete', or 'hatch' (hatch them all anyway):",
    { delete = true, hatch = true }) or "delete"

  files.write(SETUP_FILE, s)
  setup = s
  print("Saved. Turn the incubator's own pasture pull off, or keep it away from the pasture: every egg goes through me.")
  print("Next: send each breeder out next to me, tap Scan (or 'breed scan'), and put it in the pasture.")
  write("Start the breeder now? (y/n) ")
  local answer = read()
  if answer and answer:lower():sub(1, 1) == "y" then run() end
end

---------------------------------------------------------------- commands

local function addManual(entries)
  local list = files.read(MANUAL_FILE) or {}
  for _, e in ipairs(entries) do list[#list + 1] = e end
  files.write(MANUAL_FILE, list)
  os.queueEvent("breed_now") -- a running copy in another tab picks it up now
end

local function scanCommand()
  local found, skipped = scanNearby()
  if skipped ~= "" then print("Scan: " .. skipped) end
  if #found == 0 then
    return print(("None of your Pokemon are out within %d blocks of me. Send your breeder out next to the computer."):format(SCAN_RANGE))
  end
  for _, f in ipairs(found) do print("Scanned " .. describe(f.mon)) end
  addManual(found)
  print("Now put it in the pasture: I'll know it there.")
end

local function ivsCommand()
  local n = tonumber(args[2])
  local values = {}
  for i = 1, 6 do values[i] = tonumber(args[i + 2]) end
  loadState()
  local uuid = n and state.breeders[n]
  if not uuid or #values < 6 then
    print("Usage: breed ivs <n> <hp> <atk> <def> <spa> <spd> <spe>")
    print(("n is the breeder's number on the monitor (1 to %d)."):format(#state.breeders))
    return
  end
  local mon = state.mons[uuid] and copyMon(state.mons[uuid]) or { ivs = {} }
  for i, s in ipairs(STATS) do mon.ivs[s[1]] = math.max(0, math.min(MAX_IV, values[i])) end
  mon.from, mon.assumed, mon.at = "typed", nil, os.epoch("utc")
  addManual({ { uuid = uuid, mon = mon } })
  print(("Breeder %d: %s"):format(n, describe(mon)))
end

if not commands then
  print("This needs a command computer (creative, or /give @p computercraft:computer_command as an op).")
  return
end

local cmd = args[1]
if cmd == "setup" then
  runSetup()
elseif cmd == "scan" then
  scanCommand()
elseif cmd == "ivs" then
  ivsCommand()
elseif cmd == "monitor" then
  if screen.choose("breed.monitor", args[2]) then os.queueEvent("breed_monitor") end
elseif cmd == "forget" then
  loadState()
  state.eggs, state.best, state.counts = {}, nil, { judged = 0, kept = 0, rejected = 0 }
  files.write(STATE_FILE, state)
  print("Egg history forgotten. Restart the breeder if it's running.")
elseif cmd == nil then
  if not setup then
    print("Not set up yet: type 'breed setup'.")
    return
  end
  run()
else
  print("Usage: breed [setup | scan | ivs <n> <6 IVs> | monitor [name|none] | forget]")
end
