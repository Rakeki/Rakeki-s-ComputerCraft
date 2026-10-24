-- Crafting plans for the storage system: which recipe makes an item, and
-- the list of crafts needed to make some of it from what's in storage,
-- ingredients first (logs into planks into sticks into fences).
--
--   crafting.load(builtIn)          the recipes from recipes.lua, plus learnt ones
--   crafting.learn(recipe)          add a recipe taught with 'crafter learn', and save it
--   crafting.canMake(name)          is there a recipe for it?
--   crafting.plan(name, n, avail)   crafts that make n, or nil; avail: item -> count usable
--   crafting.craftable(name, avail) how many could be made from avail
local crafting = {}

local LEARNT_FILE = "/.storage_recipes"
local MAX_DEPTH = 6 -- how many crafts deep a plan may go
local MAX_CRAFTABLE = 4096 -- craftable() never counts higher than this

local learnt = {} -- recipes as taught, saved in LEARNT_FILE
local byMake = {} -- item -> recipes that make it, learnt ones first

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
  return r
end

function crafting.canMake(name) return byMake[name] ~= nil and #byMake[name] > 0 end

---------------------------------------------------------------- matching

local function glob(pattern, name)
  if not pattern:find("*", 1, true) then return pattern == name end
  local lua = "^" .. pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
  return name:find(lua) ~= nil
end

-- Does item name fit a recipe key (a name, a name with *, or a list of them)?
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
local function makeable(key)
  local list = {}
  for make in pairs(byMake) do
    if crafting.matches(key, make) then list[#list + 1] = make end
  end
  table.sort(list)
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

-- One recipe, made count times over (rounded up to whole crafts).
local function planRecipe(r, count, avail, jobs, depth, visiting)
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
        if planItem(item, need - math.max(0, avail[item] or 0), avail, jobs, depth + 1, visiting) then
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
planItem = function(name, count, avail, jobs, depth, visiting)
  if count <= 0 then return true end
  if depth > MAX_DEPTH or visiting[name] then return false end
  for _, r in ipairs(byMake[name] or {}) do
    local saved, savedJobs = copy(avail), #jobs
    visiting[name] = true
    local ok = planRecipe(r, count, avail, jobs, depth, visiting)
    visiting[name] = nil
    if ok then return true end
    copyInto(avail, saved)
    for i = #jobs, savedJobs + 1, -1 do jobs[i] = nil end
  end
  return false
end

-- The crafts (in order) that make count of name from avail, or nil.
function crafting.plan(name, count, avail)
  local jobs = {}
  if not planItem(name, count, copy(avail), jobs, 0, {}) then return nil end
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

-- How many of name could be crafted from avail (on top of what's stored).
function crafting.craftable(name, avail)
  if not crafting.canMake(name) then return 0 end
  local function can(n) return crafting.plan(name, n, avail) ~= nil end
  if not can(1) then return 0 end
  local lo, hi = 1, 2
  while hi <= MAX_CRAFTABLE and can(hi) do lo, hi = hi, hi * 2 end
  if hi > MAX_CRAFTABLE then return lo end
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if can(mid) then lo = mid else hi = mid end
  end
  return lo
end

return crafting
