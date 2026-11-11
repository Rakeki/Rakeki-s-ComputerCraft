-- Crafting plans for the craft overseer (the storage system's recipe
-- server): which recipe makes an item, and the list of crafts needed to
-- make some of it from what's in storage,
-- ingredients first (logs into planks into sticks into fences).
--
--   crafting.load(builtIn)          the recipes from recipes.lua, plus learnt ones
--   crafting.loadPack(pack)         add a modpack's recipes (pack_recipes.lua, from tools/recipes.mjs)
--   crafting.learn(recipe)          add a recipe taught with 'crafter learn', and save it
--   crafting.canMake(name)          is there a recipe for it?
--   crafting.reachable(avail)       every item that could possibly be made from avail
--   crafting.plan(name, n, avail, reach)       crafts that make n, or nil; avail: item -> count usable
--   crafting.craftable(name, avail, max, reach) how many could be made from avail
--   crafting.missing(name, avail, reach)        the ingredient there's none of (and no way to make), or nil
--   crafting.names()                every item it has a recipe for
--   crafting.using(pattern)         every recipe with an ingredient matching a Lua pattern (essence)
--   crafting.setMachine(via, list)  recipes a machine runs instead of a crafting turtle (the factory's
--                                   infuser: via = "infuse"), replacing that machine's earlier ones
--
-- A machine's recipe looks like any other (a grid of what goes in for one
-- go), so plans use it like one; its jobs carry recipe.via, and the overseer
-- hands them to the machine instead of a crafting turtle.
-- A machine that keeps its own ingredients (the factory's essence farm,
-- via = "essence") sends recipes with nothing in the grid and max = how
-- many goes it has the makings for: plans take nothing from storage for
-- them and never ask for more goes than that.
-- reach (from crafting.reachable) is optional: with thousands of modded
-- recipes, plans only try making ingredients that can be made at all,
-- which keeps them quick. Work it out once and pass it to many plans.
local files = require("lib.files") -- crash-safe save files
local crafting = {}

local LEARNT_FILE = "/.overseer_recipes"
local MAX_DEPTH = 6 -- how many crafts deep a plan may go
local MAX_CRAFTABLE = 4096 -- craftable() never counts higher than this
local YIELD_AFTER = 0.05 -- seconds of planning before letting the screens and requests have a turn

local learnt = {} -- recipes as taught, saved in LEARNT_FILE
local byMake = {} -- item -> recipes that make it, learnt ones first
local tags = {} -- tag -> { [item] = true }, from a modpack's recipes ("#minecraft:planks")
local makeableCache = {} -- recipe key -> items with a recipe that fit it
local fitsCache = {} -- recipe key -> item names that fit it, or false for a key with * in it
local recolourCache = setmetatable({}, { __mode = "k" }) -- recipe -> the group it recolours (see planRecipe), or false
local version = 0 -- goes up whenever the recipes change (reachable's cache)

---------------------------------------------------------------- recipes

-- { make, count, rows, keys } -> { make, count, grid = { [1..9] = key } },
-- cells numbered left to right, top to bottom.
local function normalize(r)
  if type(r) ~= "table" or type(r.make) ~= "string" or type(r.rows) ~= "table" or type(r.keys) ~= "table" then
    return nil, "a recipe needs make, rows and keys"
  end
  local grid = {}
  for row = 1, 3 do
    local line = r.rows[row] or ""
    for col = 1, 3 do
      local ch = line:sub(col, col)
      if ch ~= "" and ch ~= " " and ch ~= "." then
        if not r.keys[ch] then return nil, ("'%s' isn't in the keys"):format(ch) end
        grid[(row - 1) * 3 + col] = r.keys[ch]
      end
    end
  end
  -- a machine with its own ingredients (max goes) needs nothing from storage
  if not next(grid) and not (r.via and r.max) then return nil, "the recipe is empty" end
  return { make = r.make, count = r.count or 1, grid = grid }
end

local function add(raw, first)
  local r, err = normalize(raw)
  if not r then return nil, err end
  r.via = type(raw.via) == "string" and raw.via or nil
  r.max = r.via and tonumber(raw.max) or nil
  local list = byMake[r.make] or {}
  byMake[r.make] = list
  if first then table.insert(list, 1, r) else list[#list + 1] = r end
  makeableCache, version = {}, version + 1
  return r
end

-- The recipes a machine (via) can run, in place of the ones it sent last
-- time; tried after the crafting recipes for the same item. How many it took.
local machines = {} -- via -> { sig = its recipes without max, list = { [i] = the recipe added for raw i } }

-- A machine's recipes as text, leaving out max (how many goes it has the
-- makings for), which the essence farm changes whenever its essence does.
local function machineSig(list)
  local parts = {}
  for i, raw in ipairs(list) do
    if type(raw) == "table" then
      local copy = {}
      for k, v in pairs(raw) do
        if k ~= "max" and k ~= "via" then copy[k] = v end
      end
      parts[i] = textutils and textutils.serialize(copy) or tostring(i)
    else
      parts[i] = "?"
    end
  end
  return table.concat(parts, "\n")
end

function crafting.setMachine(via, list)
  list = type(list) == "table" and list or {}
  -- the same recipes, only how many goes changed: no new plans' worth of
  -- work (the recipe list, what's reachable and the lookups stay as they are)
  local sig = textutils and machineSig(list)
  local known = machines[via]
  if sig and known and known.sig == sig then
    local added = 0
    for i, raw in ipairs(list) do
      local r = known.list[i]
      if r then
        r.max = tonumber(raw.max)
        added = added + 1
      end
    end
    return added
  end
  for make, recipes in pairs(byMake) do
    for i = #recipes, 1, -1 do
      if recipes[i].via == via then table.remove(recipes, i) end
    end
    if #recipes == 0 then byMake[make] = nil end
  end
  local added, made = 0, {}
  for i, raw in ipairs(list) do
    if type(raw) == "table" then
      raw.via = via
      local r = add(raw)
      if r then
        added = added + 1
        made[i] = r
      end
    end
  end
  machines[via] = sig and { sig = sig, list = made } or nil
  makeableCache, version = {}, version + 1
  return added
end

function crafting.load(builtIn)
  byMake, makeableCache, version = {}, {}, version + 1
  machines = {}
  for _, raw in ipairs(builtIn or {}) do add(raw) end
  learnt = files.read(LEARNT_FILE) or {}
  for _, raw in ipairs(learnt) do add(raw, true) end
end

-- A recipe taught in-game. It replaces an earlier learnt one for the same item.
function crafting.learn(raw)
  local r, err = normalize(raw)
  if not r then return nil, err end
  for i = #learnt, 1, -1 do
    if learnt[i].make == raw.make then table.remove(learnt, i) end
  end
  learnt[#learnt + 1] = { make = raw.make, count = raw.count, rows = raw.rows, keys = raw.keys }
  files.write(LEARNT_FILE, learnt)
  local list = byMake[raw.make] or {}
  for i = #list, 1, -1 do
    if list[i].learnt then table.remove(list, i) end
  end
  byMake[raw.make] = list
  r.learnt = true
  table.insert(list, 1, r)
  makeableCache, version = {}, version + 1
  return r
end

function crafting.canMake(name) return byMake[name] ~= nil and #byMake[name] > 0 end

function crafting.names()
  local list = {}
  for make, recipes in pairs(byMake) do
    if #recipes > 0 then list[#list + 1] = make end
  end
  table.sort(list)
  return list
end

-- Goes up whenever the recipes change, so a list made from names() can be kept until then.
function crafting.version() return version end

-- How many different items it knows how to make.
function crafting.count()
  local n = 0
  for _, list in pairs(byMake) do
    if #list > 0 then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------- matching

local globCache = {} -- "create:*_sheet" -> the Lua pattern it becomes

local function glob(pattern, name)
  if pattern:sub(1, 1) == "#" then
    local set = tags[pattern:sub(2)]
    return set ~= nil and set[name] == true
  end
  if not pattern:find("*", 1, true) then return pattern == name end
  local lua = globCache[pattern]
  if not lua then
    lua = "^" .. pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
    globCache[pattern] = lua
  end
  return name:find(lua) ~= nil
end

-- The item names that fit key, or nil when it has a * in it (then every
-- item has to be tried). Plans look these up in the stock instead of going
-- through all of it for each ingredient: with a modpack's 1000s of stored
-- items that was most of the planning time.
local function fits(key)
  local hit = fitsCache[key]
  if hit ~= nil then return hit or nil end
  local list, seen, wild = {}, {}, false
  local function addKey(k)
    if k:sub(1, 1) == "#" then
      for item in pairs(tags[k:sub(2)] or {}) do
        if not seen[item] then seen[item], list[#list + 1] = true, item end
      end
    elseif k:find("*", 1, true) then
      wild = true
    elseif not seen[k] then
      seen[k], list[#list + 1] = true, k
    end
  end
  for _, k in ipairs(type(key) == "table" and key or { key }) do addKey(k) end
  table.sort(list) -- the same pick every time when two fit equally well
  fitsCache[key] = not wild and list or false
  return fitsCache[key] or nil
end

-- Does item name fit a recipe key (a name, a name with *, a #tag, or a list of them)?
function crafting.matches(key, name)
  if type(key) == "table" then
    for _, k in ipairs(key) do
      if glob(k, name) then return true end
    end
    return false
  end
  return glob(key, name)
end

-- Items that fit key and have a recipe, to try making when none are stored.
-- Keys are strings or recipe-owned tables, so they work as cache keys.
local function makeable(key)
  local hit = makeableCache[key]
  if hit then return hit end
  local list = {}
  local names = fits(key)
  if names then
    -- names and #tags: only those items need looking up, not every recipe
    -- (that took most of a second per tag with a modpack, after every change)
    for _, item in ipairs(names) do
      if byMake[item] and #byMake[item] > 0 then list[#list + 1] = item end
    end
  else
    for make in pairs(byMake) do
      if crafting.matches(key, make) then list[#list + 1] = make end
    end
    table.sort(list)
  end
  makeableCache[key] = list
  return list
end

-- A key as plain item names, for a program on the other end of rednet:
-- a #tag becomes the list of its items. Names with * stay as they are.
local function expandKey(key)
  if type(key) == "string" and key:sub(1, 1) ~= "#" then return key end
  local list = {}
  for _, k in ipairs(type(key) == "table" and key or { key }) do
    if k:sub(1, 1) == "#" then
      for item in pairs(tags[k:sub(2)] or {}) do list[#list + 1] = item end
    else
      list[#list + 1] = k
    end
  end
  table.sort(list)
  return list
end

---------------------------------------------------------------- planning

-- A plan works on the caller's stock (p.avail) and notes every change it
-- makes (p.keys / p.olds), so a recipe that's tried and dropped is undone
-- by putting back just what it changed. Copying the whole stock for each
-- recipe tried cost as much as the stock is long: 1000s of items in a
-- modpack, for every step of every plan.
local function put(p, k, v)
  local n = p.n + 1
  p.n, p.keys[n], p.olds[n] = n, k, p.avail[k]
  p.avail[k] = v
end

local function undo(p, mark)
  local avail, keys, olds = p.avail, p.keys, p.olds
  for i = p.n, mark + 1, -1 do
    avail[keys[i]] = olds[i]
    keys[i], olds[i] = nil, nil
  end
  p.n = mark
end

local planItem -- defined below; the two call each other

-- CC stops a program that runs too long without yielding, and a big plan
-- (or many of them, for counts) can. Yield now and then: by time, not by
-- count, since one step can be heavy (a big tag searched), and the
-- overseer's requests and screen wait for every yield (the craft
-- terminal's counts).
-- Each yield waits for its own ticket: with one shared event, every plan
-- waiting on a yield (the craft list's counts, a canmake, the queue's
-- missing check) woke on each one and planned another YIELD_AFTER, so the
-- screen waited several rounds of all of them for each tap and redraw.
local calls, yieldedAt, tickets = 0, os.clock(), 0
local function breathe()
  calls = calls + 1
  if calls % 10 == 0 and (calls % 1000 == 0 or os.clock() - yieldedAt >= YIELD_AFTER) and os.queueEvent then
    tickets = tickets + 1
    local mine = tickets
    os.queueEvent("crafting_yield", mine)
    repeat
      local _, ticket = os.pullEvent("crafting_yield")
    until ticket == mine
    yieldedAt = os.clock()
  end
end

-- One recipe, made count times over (rounded up to whole crafts).
-- Where a machine's goes left are kept in avail while planning, so a plan
-- that's tried and dropped gives them back like any item. No item is called
-- this (it starts with a 0 byte), and isItem keeps it out of the matching.
local function goesKey(r) return "\0goes\0" .. r.via .. "\0" .. r.make .. "\0" end
local function isItem(name) return name:byte(1) ~= 0 end

-- A recipe that makes one of a group from any of the group (black wool
-- from any wool and a black dye; modpacks have dozens: placards, seats,
-- concrete): the group's names joined, or false. Cached per recipe.
local function recolours(r)
  local hit = recolourCache[r]
  if hit ~= nil then return hit end
  hit = false
  for _, key in pairs(r.grid) do
    local names = fits(key)
    if names and #names > 1 then
      for _, item in ipairs(names) do
        if item == r.make then hit = table.concat(names, ",") break end
      end
    end
    if hit then break end
  end
  recolourCache[r] = hit
  return hit
end

local planRecipeIn -- planRecipe's work, below

-- Never recolour inside a recolouring of the same group: if any of the
-- group will do, one made by recolouring could have been the one recoloured.
-- Without this a plan short of something went black placard <- orange <-
-- red <- ... six deep through all 16 colours: millions of tries, minutes
-- for one item. A plain recipe for one of them is still tried (black wool
-- from white wool, made from string).
local function planRecipe(r, count, p, depth)
  local group = recolours(r)
  if not group then return planRecipeIn(r, count, p, depth) end
  if p.recolouring[group] then return false end
  p.recolouring[group] = true
  local ok = planRecipeIn(r, count, p, depth)
  p.recolouring[group] = nil
  return ok
end

planRecipeIn = function(r, count, p, depth)
  local avail = p.avail
  local steps = math.ceil(count / r.count)
  -- a machine with its own ingredients: only as many goes as it has the makings for
  local goes = r.max and goesKey(r)
  if goes then
    local left = avail[goes] or r.max
    if steps > left then return false end
    put(p, goes, left - steps)
  end
  -- cells with the same key use the same item
  local per, order = {}, {}
  for k = 1, 9 do
    local key = r.grid[k]
    if key then
      if not per[key] then
        per[key] = 0
        order[#order + 1] = key
      end
      per[key] = per[key] + 1
    end
  end
  local choice = {}
  for _, key in ipairs(order) do
    local need = per[key] * steps
    local best, bestN = nil, 0 -- the fitting item there's most of
    local names = fits(key)
    if names then
      for _, item in ipairs(names) do
        local n = avail[item] or 0
        if n > bestN then best, bestN = item, n end
      end
    else -- a name with * in it: try everything
      for item, n in pairs(avail) do
        if n > bestN and isItem(item) and crafting.matches(key, item) then best, bestN = item, n end
      end
    end
    if bestN < need then
      -- make the rest: of the item there's most of first, then any other
      -- that fits (2 spruce planks stored but only oak logs: oak planks)
      local tries = best and { best } or {}
      for _, item in ipairs(makeable(key)) do
        if item ~= best then tries[#tries + 1] = item end
      end
      local made = false
      for _, item in ipairs(tries) do
        if planItem(item, need - math.max(0, avail[item] or 0), p, depth + 1) then
          best, made = item, true
          break
        end
      end
      if not made then return false end
    end
    put(p, best, avail[best] - need)
    choice[key] = best
  end
  local grid = {}
  for k = 1, 9 do
    if r.grid[k] then grid[k] = choice[r.grid[k]] end
  end
  p.jobs[#p.jobs + 1] = { name = r.make, recipe = r, steps = steps, grid = grid }
  put(p, r.make, (avail[r.make] or 0) + steps * r.count)
  return true
end

-- Add to jobs the crafts that make count of name, using up avail. On failure
-- avail and jobs are left as they were.
planItem = function(name, count, p, depth)
  if count <= 0 then return true end
  breathe()
  local visiting, jobs = p.visiting, p.jobs
  if depth > MAX_DEPTH or visiting[name] then return false end
  if p.reach and not p.reach[name] then return false end -- can't be made from what's there at all
  for _, r in ipairs(byMake[name] or {}) do
    local mark, savedJobs = p.n, #jobs
    visiting[name] = true
    local ok = planRecipe(r, count, p, depth)
    visiting[name] = nil
    if ok then return true end
    undo(p, mark)
    for i = #jobs, savedJobs + 1, -1 do jobs[i] = nil end
  end
  return false
end

-- The crafts (in order) that make count of name from avail, or nil.
-- avail is left as it was (every change is undone at the end).
function crafting.plan(name, count, avail, reach)
  local p = { avail = avail, jobs = {}, visiting = {}, reach = reach, n = 0, keys = {}, olds = {}, recolouring = {} }
  local ok = planItem(name, count, p, 0)
  undo(p, 0)
  if not ok then return nil end
  local jobs = p.jobs
  -- the same craft twice in a row becomes one
  local merged = {}
  for _, j in ipairs(jobs) do
    local last = merged[#merged]
    local same = last and last.name == j.name and last.recipe == j.recipe
    for k = 1, 9 do
      if same and last.grid[k] ~= j.grid[k] then same = false end
    end
    if same then last.steps = last.steps + j.steps else merged[#merged + 1] = j end
  end
  return merged
end

-- How many of name could be crafted from avail (on top of what's stored),
-- counting no higher than max (or MAX_CRAFTABLE).
function crafting.craftable(name, avail, max, reach)
  if not crafting.canMake(name) then return 0 end
  if reach and not reach[name] then return 0 end
  max = math.max(1, math.min(max or MAX_CRAFTABLE, MAX_CRAFTABLE))
  local function can(n) return crafting.plan(name, n, avail, reach) ~= nil end
  if not can(1) then return 0 end
  if can(max) then return max end
  local lo, hi = 1, 2
  while hi < max and can(hi) do lo, hi = hi, hi * 2 end
  hi = math.min(hi, max)
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if can(mid) then lo = mid else hi = mid end
  end
  return lo
end

-- Why name can't be made at all from avail: the ingredient, as deep down
-- as it goes, that there's none of and no way to make (an item name, a
-- "#tag", or a list of names), or nil when it's only amounts that are short.
-- Follows each item's first recipe, so it's a hint, not the only answer.
function crafting.missing(name, avail, reach, depth)
  depth = depth or 0
  local r = (byMake[name] or {})[1]
  if not r or depth > MAX_DEPTH then return nil end
  for k = 1, 9 do
    local key = r.grid[k]
    if key then
      local have, names = false, fits(key)
      if names then
        for _, item in ipairs(names) do
          if (avail[item] or 0) > 0 then have = true break end
        end
      else
        for item, n in pairs(avail) do
          if n > 0 and isItem(item) and crafting.matches(key, item) then have = true break end
        end
      end
      if not have then
        local options = makeable(key)
        local reachable = false
        for _, item in ipairs(options) do
          if not reach or reach[item] then reachable = true break end
        end
        if not reachable then return (options[1] and crafting.missing(options[1], avail, reach, depth + 1)) or key end
      end
    end
  end
  return nil
end

-- Everything that could possibly be made from avail, ignoring amounts:
-- what's there, plus anything with a recipe whose every ingredient is
-- (over and over, so planks count once logs do, then sticks).
-- It only changes when a new kind of item is stored or the last of one goes
-- (or the recipes change), so the last answer is kept and given again until
-- then. Don't change the table it returns.
-- Worked out in one pass over a worklist: each item that turns up ticks off
-- the recipe keys it fits, and a recipe with every key ticked off adds what
-- it makes. Going over every recipe again and again until nothing changed
-- cost a pass per crafting step (planks, then sticks, then ...) over a
-- modpack's thousands of recipes, after every order.
-- The index (which keys each item fits, which recipes wait on each key) only
-- changes with the recipes, so it's built once per version.
local reachIndex = { version = -1 }
local function buildReachIndex()
  local itemKeys = {} -- item -> keys it fits
  local wild = {} -- keys with a * in them (or lists holding one): every new item is checked against these
  local waiters = {} -- key -> recipes (indexes into need/makes) that use it
  local need, makes = {}, {} -- recipe i: how many different keys it uses, what it makes
  local indexed = {} -- key -> true once its items are in itemKeys
  local function index(key)
    if indexed[key] then return end
    indexed[key] = true
    local isWild = false
    local function addName(k)
      if k:sub(1, 1) == "#" then
        for item in pairs(tags[k:sub(2)] or {}) do
          local list = itemKeys[item] or {}
          itemKeys[item] = list
          list[#list + 1] = key
        end
      elseif k:find("*", 1, true) then
        isWild = true
      else
        local list = itemKeys[k] or {}
        itemKeys[k] = list
        list[#list + 1] = key
      end
    end
    for _, k in ipairs(type(key) == "table" and key or { key }) do addName(k) end
    if isWild then wild[#wild + 1] = key end
  end
  for make, list in pairs(byMake) do
    for _, r in ipairs(list) do
      breathe()
      local i = #makes + 1
      makes[i] = make
      local seen, n = {}, 0
      for _, key in pairs(r.grid) do
        if not seen[key] then
          seen[key], n = true, n + 1
          index(key)
          local w = waiters[key] or {}
          waiters[key] = w
          w[#w + 1] = i
        end
      end
      need[i] = n
    end
  end
  reachIndex = { version = version, itemKeys = itemKeys, wild = wild, waiters = waiters, need = need, makes = makes }
end

local reachLast = { version = -1, base = {}, size = 0 }
function crafting.reachable(avail)
  local base, size = {}, 0
  for item, n in pairs(avail) do
    if n > 0 and isItem(item) then base[item], size = true, size + 1 end
  end
  if reachLast.version == version and reachLast.size == size then
    local same = true
    for item in pairs(base) do
      if not reachLast.base[item] then same = false break end
    end
    if same then return reachLast.have end
  end
  if reachIndex.version ~= version then buildReachIndex() end
  local idx = reachIndex
  local left = {} -- recipe i -> keys still to find (need[i] until touched)
  local done = {} -- keys something there fits
  local have, todo = {}, {}
  local function found(item)
    if not have[item] then
      have[item] = true
      todo[#todo + 1] = item
    end
  end
  local function tick(key)
    if done[key] then return end
    done[key] = true
    for _, i in ipairs(idx.waiters[key] or {}) do
      local n = (left[i] or idx.need[i]) - 1
      left[i] = n
      if n == 0 then found(idx.makes[i]) end
    end
  end
  for item in pairs(base) do found(item) end
  -- recipes with nothing in them (a machine with its own ingredients)
  for i, n in ipairs(idx.need) do
    if n == 0 then found(idx.makes[i]) end
  end
  local at = 1
  while at <= #todo do
    breathe()
    local item = todo[at]
    at = at + 1
    for _, key in ipairs(idx.itemKeys[item] or {}) do tick(key) end
    for _, key in ipairs(idx.wild) do
      if not done[key] and crafting.matches(key, item) then tick(key) end
    end
  end
  reachLast = { version = version, base = base, size = size, have = have }
  return have
end

-- A modpack's recipes, as written by tools/recipes.mjs: item names by number,
-- tags as lists of item numbers, and recipes as { make, count, rows, keys }
-- with rows joined by "/". Returns how many recipes it added.
function crafting.loadPack(pack)
  local names = pack.names or {}
  for tag, list in pairs(pack.tags or {}) do
    local set = {}
    for _, n in ipairs(list) do
      if names[n] then set[names[n]] = true end
    end
    tags[tag] = set
  end
  local function key(k)
    if type(k) == "number" then return names[k] end
    if type(k) == "table" then
      local out = {}
      for i, x in ipairs(k) do out[i] = key(x) end
      return out
    end
    return k -- a "#tag"
  end
  local added = 0
  for _, r in ipairs(pack.recipes or {}) do
    breathe()
    local keys = {}
    for ch, k in pairs(r[4] or {}) do keys[ch] = key(k) end
    local rows = {}
    for row in (tostring(r[3]) .. "/"):gmatch("([^/]*)/") do rows[#rows + 1] = row end
    if names[r[1]] and add({ make = names[r[1]], count = r[2], rows = rows, keys = keys }) then added = added + 1 end
  end
  makeableCache, fitsCache, version = {}, {}, version + 1
  recolourCache = setmetatable({}, { __mode = "k" })
  return added
end

-- Every recipe with an ingredient whose name (or one of whose choices)
-- matches pattern: { make, count, grid = { [cell] = item or list } }.
-- The essence computer asks for "_essence$".
function crafting.using(pattern)
  local out = {}
  local function hits(k)
    for _, name in ipairs(type(k) == "table" and k or { k }) do
      if name:find(pattern) then return true end
    end
    return false
  end
  for make, list in pairs(byMake) do
    for _, r in ipairs(list) do
      breathe()
      local machine = r.via ~= nil -- a machine's: not one to craft from essence
      local found = false
      for _, k in pairs(machine and {} or r.grid) do
        if hits(expandKey(k)) then found = true break end
      end
      if found then
        local grid = {}
        for cell, k in pairs(r.grid) do grid[cell] = expandKey(k) end
        out[#out + 1] = { make = make, count = r.count, grid = grid }
      end
    end
  end
  return out
end

return crafting
