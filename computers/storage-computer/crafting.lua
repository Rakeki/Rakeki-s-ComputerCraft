-- Crafting plans for the storage system: which recipe makes an item, and
-- the list of crafts needed to make some of it from what's in storage,
-- ingredients first (logs into planks into sticks into fences).
--
--   crafting.load(builtIn)          the recipes from recipes.lua, plus learnt ones
--   crafting.loadPack(pack)         add a modpack's recipes (pack_recipes.lua, from tools/recipes.mjs)
--   crafting.learn(recipe)          add a recipe taught with 'crafter learn', and save it
--   crafting.canMake(name)          is there a recipe for it?
--   crafting.reachable(avail)       every item that could possibly be made from avail
--   crafting.plan(name, n, avail, reach)       crafts that make n, or nil; avail: item -> count usable
--   crafting.craftable(name, avail, max, reach) how many could be made from avail
--   crafting.names()                every item it has a recipe for
--
-- reach (from crafting.reachable) is optional: with thousands of modded
-- recipes, plans only try making ingredients that can be made at all,
-- which keeps them quick. Work it out once and pass it to many plans.
local crafting = {}

local LEARNT_FILE = "/.storage_recipes"
local MAX_DEPTH = 6 -- how many crafts deep a plan may go
local MAX_CRAFTABLE = 4096 -- craftable() never counts higher than this

local learnt = {} -- recipes as taught, saved in LEARNT_FILE
local byMake = {} -- item -> recipes that make it, learnt ones first
local tags = {} -- tag -> { [item] = true }, from a modpack's recipes ("#minecraft:planks")
local makeableCache = {} -- recipe key -> items with a recipe that fit it

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
  if not next(grid) then return nil, "the recipe is empty" end
  return { make = r.make, count = r.count or 1, grid = grid }
end

local function add(raw, first)
  local r, err = normalize(raw)
  if not r then return nil, err end
  local list = byMake[r.make] or {}
  byMake[r.make] = list
  if first then table.insert(list, 1, r) else list[#list + 1] = r end
  makeableCache = {}
  return r
end

function crafting.load(builtIn)
  byMake = {}
  for _, raw in ipairs(builtIn or {}) do add(raw) end
  learnt = {}
  if fs.exists(LEARNT_FILE) then
    local f = fs.open(LEARNT_FILE, "r")
    learnt = textutils.unserialize(f.readAll()) or {}
    f.close()
  end
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
  local f = fs.open(LEARNT_FILE, "w")
  f.write(textutils.serialize(learnt))
  f.close()
  local list = byMake[raw.make] or {}
  for i = #list, 1, -1 do
    if list[i].learnt then table.remove(list, i) end
  end
  byMake[raw.make] = list
  r.learnt = true
  table.insert(list, 1, r)
  makeableCache = {}
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

-- How many different items it knows how to make.
function crafting.count()
  local n = 0
  for _, list in pairs(byMake) do
    if #list > 0 then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------- matching

local function glob(pattern, name)
  if pattern:sub(1, 1) == "#" then
    local set = tags[pattern:sub(2)]
    return set ~= nil and set[name] == true
  end
  if not pattern:find("*", 1, true) then return pattern == name end
  local lua = "^" .. pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
  return name:find(lua) ~= nil
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
  if type(key) == "string" and key:sub(1, 1) ~= "#" and not key:find("*", 1, true) then
    if byMake[key] then list[1] = key end -- a plain name: no need to look through every recipe
  else
    for make in pairs(byMake) do
      if crafting.matches(key, make) then list[#list + 1] = make end
    end
    table.sort(list)
  end
  makeableCache[key] = list
  return list
end

---------------------------------------------------------------- planning

local function copyInto(dst, src)
  for k in pairs(dst) do dst[k] = nil end
  for k, v in pairs(src) do dst[k] = v end
end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local planItem -- defined below; the two call each other

-- CC stops a program that runs too long without yielding, and a big plan
-- (or many of them, for counts) can. Yield now and then.
local calls = 0
local function breathe()
  calls = calls + 1
  if calls % 200 == 0 and os and os.queueEvent then
    os.queueEvent("crafting_yield")
    os.pullEvent("crafting_yield")
  end
end

-- One recipe, made count times over (rounded up to whole crafts).
local function planRecipe(r, count, avail, jobs, depth, visiting, reach)
  local steps = math.ceil(count / r.count)
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
    for item, n in pairs(avail) do
      if n > bestN and crafting.matches(key, item) then best, bestN = item, n end
    end
    if bestN < need then
      local made = false
      for _, item in ipairs(best and { best } or makeable(key)) do
        if planItem(item, need - math.max(0, avail[item] or 0), avail, jobs, depth + 1, visiting, reach) then
          best, made = item, true
          break
        end
      end
      if not made then return false end
    end
    avail[best] = avail[best] - need
    choice[key] = best
  end
  local grid = {}
  for k = 1, 9 do
    if r.grid[k] then grid[k] = choice[r.grid[k]] end
  end
  jobs[#jobs + 1] = { name = r.make, recipe = r, steps = steps, grid = grid }
  avail[r.make] = (avail[r.make] or 0) + steps * r.count
  return true
end

-- Add to jobs the crafts that make count of name, using up avail. On failure
-- avail and jobs are left as they were.
planItem = function(name, count, avail, jobs, depth, visiting, reach)
  if count <= 0 then return true end
  breathe()
  if depth > MAX_DEPTH or visiting[name] then return false end
  if reach and not reach[name] then return false end -- can't be made from what's there at all
  for _, r in ipairs(byMake[name] or {}) do
    local saved, savedJobs = copy(avail), #jobs
    visiting[name] = true
    local ok = planRecipe(r, count, avail, jobs, depth, visiting, reach)
    visiting[name] = nil
    if ok then return true end
    copyInto(avail, saved)
    for i = #jobs, savedJobs + 1, -1 do jobs[i] = nil end
  end
  return false
end

-- The crafts (in order) that make count of name from avail, or nil.
function crafting.plan(name, count, avail, reach)
  local jobs = {}
  if not planItem(name, count, copy(avail), jobs, 0, {}, reach) then return nil end
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

-- Everything that could possibly be made from avail, ignoring amounts:
-- what's there, plus anything with a recipe whose every ingredient is
-- (over and over, so planks count once logs do, then sticks).
function crafting.reachable(avail)
  local have = {}
  for item, n in pairs(avail) do
    if n > 0 then have[item] = true end
  end
  local function ok(key)
    if type(key) == "table" then
      for _, k in ipairs(key) do
        if ok(k) then return true end
      end
      return false
    end
    if key:sub(1, 1) == "#" then
      for item in pairs(tags[key:sub(2)] or {}) do
        if have[item] then return true end
      end
      return false
    end
    if key:find("*", 1, true) then
      for item in pairs(have) do
        if glob(key, item) then return true end
      end
      return false
    end
    return have[key] == true
  end
  local changed = true
  while changed do
    changed = false
    for make, list in pairs(byMake) do
      if not have[make] then
        for _, r in ipairs(list) do
          local all = true
          for _, key in pairs(r.grid) do
            breathe()
            if not ok(key) then
              all = false
              break
            end
          end
          if all then
            have[make], changed = true, true
            break
          end
        end
      end
    end
  end
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
  makeableCache = {}
  return added
end

return crafting
