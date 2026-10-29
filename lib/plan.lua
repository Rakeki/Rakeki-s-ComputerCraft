-- Building plans: load one from /plans (a .json or .lua file) and place it in
-- the world. The blueprint projector shows them, build-control and the
-- projector hand them to builder turtles (lib/crew.lua).
--
--   local plan = require("lib.plan")
--   local p, err = plan.load("skystation")   -- /plans/skystation.json or .lua, or a file path
--   local at = plan.corner(p, 0, 100, 150, -40) -- north-west bottom corner, facing north
--   local mats, blocks = plan.world(p, at)    -- block names; { x, y, z, m } in world coordinates
--
-- A plan file (JSON, or Lua returning the same table):
--   { "name": "Gatehouse", "clear": true,
--     "legend": { "C": "minecraft:cobblestone", "G": ["minecraft:glass", "#99ddff"] },
--     "layers": [ ["CCC", "C.C", "CCC"], ["CGC", "G.G", "CGC"] ] }
-- layers: bottom layer first; each a list of rows seen from above, the first
-- row the north side, each row west to east; "." and " " are air. Or
-- "blocks": [ [x, y, z, "minecraft:stone"], ... ] in place of legend and
-- layers. "clear": false says it's built in the air, so builders don't dig
-- out its box first. A colour (a number, or "#rrggbb") is only for the
-- projection. A block may carry a state, as setblock takes it:
-- "minecraft:spruce_stairs[facing=east]". Builder turtles face that way to
-- place it (stairs climb towards it), and turning the plan turns it.
local plan = {}

local FACINGS = { "north", "east", "south", "west" }

-- A block name without its [state].
function plan.base(block) return (block:gsub("%[.*$", "")) end

-- The facing in a block's state (0 north .. 3 west, as nav headings), or nil.
function plan.facing(block)
  local f = block:match("[%[,]facing=(%a+)")
  for i, name in ipairs(FACINGS) do
    if name == f then return i - 1 end
  end
end

-- The block with its facing turned turn quarter turns clockwise.
local function turned(block, turn)
  local f = plan.facing(block)
  if not f or (turn or 0) % 4 == 0 then return block end
  return (block:gsub("([%[,]facing=)%a+", "%1" .. FACINGS[(f + turn) % 4 + 1]))
end

plan.DIR = "/plans"

---------------------------------------------------------------- loading

local function colour(c)
  if type(c) == "string" then return tonumber(c:gsub("^#", ""), 16) end
  return c
end

-- A plan table (layers + legend, or a block list) as one shape: blocks
-- { x, y, z, m } from 0 with m indexing mats ({ block, char, color, total }),
-- sorted bottom up, and per layer.
function plan.fromTable(raw, id)
  if type(raw) ~= "table" then error("the plan must be a table", 0) end
  local mats, byKey, blocks, usedChars = {}, {}, {}, {}

  local function material(key, def, char)
    if byKey[key] then return byKey[key] end
    local block, color
    if type(def) == "string" then
      block = def
    elseif type(def) == "table" then
      block, color = def.block or def[1], def.color or def[2]
    end
    if type(block) ~= "string" then error(("the legend entry for '%s' needs a block name"):format(key), 0) end
    mats[#mats + 1] = { block = block, char = char, color = colour(color), total = 0 }
    byKey[key] = #mats
    if char then usedChars[char] = true end
    return #mats
  end

  local function add(x, y, z, m) blocks[#blocks + 1] = { x = x, y = y, z = z, m = m } end

  if raw.layers then
    local legend = raw.legend or {}
    for y, layer in ipairs(raw.layers) do
      if type(layer) ~= "table" then error(("layer %d should be a list of rows"):format(y), 0) end
      for z, row in ipairs(layer) do
        for x = 1, #row do
          local ch = row:sub(x, x)
          if ch ~= "." and ch ~= " " then
            if legend[ch] == nil then
              error(("layer %d row %d: '%s' isn't in the legend"):format(y, z, ch), 0)
            end
            add(x - 1, y - 1, z - 1, material(ch, legend[ch], ch))
          end
        end
      end
    end
  elseif raw.blocks then
    for i, b in ipairs(raw.blocks) do
      local x, y, z, block = b.x or b[1], b.y or b[2], b.z or b[3], b.block or b[4]
      if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(block) ~= "string" then
        error(("block %d should look like { x, y, z, \"minecraft:stone\" }"):format(i), 0)
      end
      add(math.floor(x), math.floor(y), math.floor(z), material(block, block))
    end
  else
    error("the plan needs either layers or blocks", 0)
  end
  if #blocks == 0 then error("the plan has no blocks", 0) end

  -- a map letter for materials from a block list: initial, then lower case, then anything free
  for _, m in ipairs(mats) do
    if not m.char then
      local initial = m.block:gsub("^.-:", ""):sub(1, 1)
      for _, ch in ipairs({ initial:upper(), initial:lower(), "#", "%", "&", "@", "$", "+", "=" }) do
        if not usedChars[ch] then m.char = ch break end
      end
      m.char = m.char or "?"
      usedChars[m.char] = true
    end
  end

  -- layers can be written in any order, and block lists can start anywhere
  local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
  for _, b in ipairs(blocks) do
    x0, y0, z0 = math.min(x0, b.x), math.min(y0, b.y), math.min(z0, b.z)
    x1, y1, z1 = math.max(x1, b.x), math.max(y1, b.y), math.max(z1, b.z)
  end
  local seen, unique = {}, {}
  for _, b in ipairs(blocks) do
    b.x, b.y, b.z = b.x - x0, b.y - y0, b.z - z0
    local k = b.x .. "," .. b.y .. "," .. b.z
    if seen[k] then unique[seen[k]].m = b.m else unique[#unique + 1] = b; seen[k] = #unique end
  end
  blocks = unique
  for _, b in ipairs(blocks) do mats[b.m].total = mats[b.m].total + 1 end
  table.sort(blocks, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.z ~= b.z then return a.z < b.z end
    return a.x < b.x
  end)

  local p = {
    id = id, name = raw.name or id, mats = mats, blocks = blocks, layers = {},
    w = x1 - x0 + 1, h = y1 - y0 + 1, l = z1 - z0 + 1,
    clear = raw.clear ~= false, -- false: built in the air, so builders don't dig out its box first
  }
  for y = 1, p.h do p.layers[y] = {} end
  for _, b in ipairs(blocks) do table.insert(p.layers[b.y + 1], b) end
  -- turning spins the plan about this block
  p.cx, p.cz = math.floor((p.w - 1) / 2), math.floor((p.l - 1) / 2)
  return p
end

-- The file a plan id stands for: a path (anything with a "/" or ending in
-- .json or .lua), or else /plans/<id>.json or .lua only, so a stray file
-- named like a plan in the current folder is never picked up instead.
function plan.path(id)
  if id:find("/", 1, true) or id:match("%.json$") or id:match("%.lua$") then
    if fs.exists(id) and not fs.isDir(id) then return id end
    return nil
  end
  for _, ext in ipairs({ ".json", ".lua" }) do
    local path = fs.combine(plan.DIR, id .. ext)
    if fs.exists(path) then return path end
  end
end

-- Copy a plan's file to `to` plus its extension, so a building keeps the
-- plan it was started with even if /plans/<id> is updated or removed while
-- it's going up. The new path, or nil and why.
function plan.copy(id, to)
  local from = plan.path(id)
  if not from then return nil, ("No plan called '%s' in %s."):format(id, plan.DIR) end
  local path = to .. (from:match("%.json$") and ".json" or ".lua")
  if from == path then return path end
  for _, old in ipairs({ to .. ".json", to .. ".lua" }) do
    if fs.exists(old) then fs.delete(old) end
  end
  fs.copy(from, path)
  return path
end

-- Every plan in /plans, by name.
function plan.ids()
  local ids, seen = {}, {}
  if not fs.isDir(plan.DIR) then return ids end
  local names = fs.list(plan.DIR)
  table.sort(names)
  for _, f in ipairs(names) do
    local id = f:match("^(.+)%.json$") or f:match("^(.+)%.lua$")
    if id and not seen[id] then ids[#ids + 1], seen[id] = id, true end
  end
  return ids
end

-- Load a plan: the plan, or nil and what's wrong with it.
function plan.load(id)
  local path = plan.path(id)
  if not path then return nil, ("No plan called '%s' in %s."):format(id, plan.DIR) end
  local raw
  if path:sub(-5) == ".json" then
    local f = fs.open(path, "r")
    local text = f.readAll()
    f.close()
    raw = textutils.unserializeJSON(text)
    if raw == nil then return nil, ("%s isn't valid JSON"):format(path) end
  else
    local fn, err = loadfile(path, nil, setmetatable({}, { __index = _G }))
    if not fn then return nil, err end
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    raw = result
  end
  local short = fs.getName(path):gsub("%.%w+$", "")
  local ok, p = pcall(plan.fromTable, raw, short)
  if not ok then return nil, ("%s: %s"):format(short, p) end
  return p
end

---------------------------------------------------------------- placing

-- Where a plan goes, at = { x, y, z, turn }: (x, z) is where the plan's
-- middle block (cx, cz) lands, y is its bottom layer, and turn is quarter
-- turns clockwise seen from above (0 = its first row faces north).

-- Plan block (x, z) as an offset from at, turned.
function plan.offset(p, turn, x, z)
  local dx, dz = x - p.cx, z - p.cz
  for _ = 1, (turn or 0) % 4 do dx, dz = -dz, dx end
  return dx, dz
end

-- World block range the building covers on the ground: x0, z0, x1, z1.
function plan.footprint(p, at)
  local ax, az = plan.offset(p, at.turn, 0, 0)
  local bx, bz = plan.offset(p, at.turn, p.w - 1, p.l - 1)
  return at.x + math.min(ax, bx), at.z + math.min(az, bz), at.x + math.max(ax, bx), at.z + math.max(az, bz)
end

-- The building's box in world coordinates.
function plan.area(p, at)
  local x0, z0, x1, z1 = plan.footprint(p, at)
  return { x0 = x0, z0 = z0, x1 = x1, z1 = z1, y0 = at.y, y1 = at.y + p.h - 1 }
end

-- The at that puts the building's north-west bottom corner (smallest x and
-- z) on x, y, z, turned turn quarter turns.
function plan.corner(p, turn, x, y, z)
  local at = { x = 0, y = y, z = 0, turn = turn or 0 }
  local x0, z0 = plan.footprint(p, at)
  at.x, at.z = x - x0, z - z0
  return at
end

-- Every block in world coordinates: the block names (mats[m], facings
-- turned with the plan), and { x, y, z, m } per block, as builder turtles
-- take them.
function plan.world(p, at)
  local mats, blocks = {}, {}
  for i, m in ipairs(p.mats) do mats[i] = turned(m.block, at.turn) end
  for i, b in ipairs(p.blocks) do
    local dx, dz = plan.offset(p, at.turn, b.x, b.z)
    blocks[i] = { at.x + dx, at.y + b.y, at.z + dz, b.m }
  end
  return mats, blocks
end

return plan
