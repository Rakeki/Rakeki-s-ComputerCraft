-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Barn and silo: a big red barn with white trim under a dark gambrel roof
-- (steep low slopes, gentler high ones). Wide doors at both ends, a
-- hayloft door in the front gable with a hoist beam, horse stalls with
-- gates down the west side, a stair to a hayloft full of bales, and feed
-- barrels. Beside it a tall silo with a copper dome, and a fenced paddock
-- with a water trough (3 water buckets). y 0 is the ground; x runs east,
-- z south, the main doors face north.
local W, L = 12, 20 -- walls on x 0..W, z 0..L
local MID = 6
local LOFT = 7 -- the hayloft floor's level
local ROOF = "dark_oak"

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
local function fill(x0, y0, z0, x1, y1, z1, block)
  for y = y0, y1 do for z = z0, z1 do for x = x0, x1 do set(x, y, z, block) end end end
end
local function dist(x, z) return math.sqrt(x * x + z * z) end

---------------------------------------------------------------- the roof's shape

-- for each column across the barn, how high its roof is: steep (two up for
-- one across) for the first three, then one for one up to the ridge
local PROFILE = {} -- PROFILE[x] = { y of the stair, fill below it down to }
for k = -1, 1 do PROFILE[k] = { 6 + 2 * (k + 1), 6 + 2 * (k + 1) - (k >= 0 and 1 or 0) } end
for k = 2, MID - 1 do PROFILE[k] = { 11 + (k - 2), 11 + (k - 2) } end
local RIDGE = 11 + (MID - 2)
local function roofAt(x) -- the stair's height over column x, either side of the middle
  local k = x <= MID and x or W - x
  return PROFILE[k] and PROFILE[k][1] or RIDGE
end

---------------------------------------------------------------- walls and floor

for z = 0, L do
  for x = 0, W do
    set(x, 0, z, (x >= MID - 1 and x <= MID + 1) and "spruce_planks" or "coarse_dirt")
  end
end
for y = 1, 6 do
  for z = 0, L do
    for x = 0, W do
      if x == 0 or x == W or z == 0 or z == L then
        local corner = (x == 0 or x == W) and (z == 0 or z == L)
        set(x, y, z, (corner or y == 6) and "white_terracotta" or "red_terracotta")
      end
    end
  end
end
-- gable ends: red up to the roof line
for _, z in ipairs({ 0, L }) do
  for x = 1, W - 1 do
    for y = 7, roofAt(x) - 1 do set(x, y, z, "red_terracotta") end
  end
end
-- big doors at both ends, framed in white
for _, z in ipairs({ 0, L }) do
  local half = z == 0 and 2 or 1
  for y = 1, 5 do for x = MID - half, MID + half do set(x, y, z, nil) end end
  for y = 1, 6 do set(MID - half - 1, y, z, "white_terracotta"); set(MID + half + 1, y, z, "white_terracotta") end
  for x = MID - half - 1, MID + half + 1 do set(x, 6, z, "white_terracotta") end
end
-- the hayloft door and its hoist beam
for y = 9, 11 do for x = MID - 1, MID + 1 do set(x, y, 0, (y == 11 or x ~= MID) and "white_terracotta" or nil) end end
set(MID, 13, 0, "dark_oak_fence"); set(MID, 13, -1, "dark_oak_fence")
for y = 10, 12 do set(MID, y, -1, "chain") end
set(MID, 9, -1, "hay_block")
-- small windows down both sides
for z = 4, L - 4, 4 do set(0, 3, z, "glass_pane"); set(W, 3, z, "glass_pane") end

---------------------------------------------------------------- the roof

for x = -1, W + 1 do
  local k = x <= MID and x or W - x
  local p = PROFILE[k]
  for z = -1, L + 1 do
    if x == MID then set(x, RIDGE, z, ROOF .. "_slab")
    else
      set(x, p[1], z, ROOF .. "_stairs[facing=" .. (x < MID and "east" or "west") .. "]")
      for y = p[2], p[1] - 1 do set(x, y, z, ROOF .. "_planks") end
    end
  end
end

---------------------------------------------------------------- inside

-- stalls down the west side, a fence and gate across each front
for _, z0 in ipairs({ 1, 6, 11, 16 }) do
  if z0 + 4 < L then for x = 1, 3 do set(x, 1, z0 + 4, "spruce_fence") end end
  for z = z0, z0 + 3 do set(4, 1, z, z == z0 + 1 and "spruce_fence_gate[facing=east]" or "spruce_fence") end
  set(1, 1, z0 + 1, "hay_block"); set(1, 1, z0 + 2, "cauldron")
end
-- a stair up the east side to the hayloft over the back half
for i = 0, LOFT - 1 do set(W - 2, 1 + i, 4 + i, "spruce_stairs[facing=south]") end
for z = 11, L - 1 do
  for x = 2, W - 2 do set(x, LOFT, z, "spruce_planks") end
end
for _, b in ipairs({ { 3, 14 }, { 3, 15 }, { 4, 15 }, { 3, 18 }, { 4, 18 }, { 5, 18 }, { 8, 17 }, { 9, 18 }, { 8, 18 } }) do
  set(b[1], LOFT + 1, b[2], "hay_block")
end
set(3, LOFT + 2, 15, "hay_block"); set(4, LOFT + 2, 18, "hay_block")
for z = 1, 3 do set(W - 1, 1, z, "barrel") end
set(W - 1, 2, 1, "barrel"); set(W - 1, 1, L - 1, "chest"); set(W - 1, 1, L - 2, "composter")
for _, z in ipairs({ 2, L - 2 }) do set(MID - 2, 1, z, "lantern"); set(MID + 2, 1, z, "lantern") end

---------------------------------------------------------------- the silo

local SX, SZ, STOP = W + 5, 5, 18
for y = 0, STOP do
  for z = SZ - 4, SZ + 4 do
    for x = SX - 4, SX + 4 do
      local d = dist(x - SX, z - SZ)
      if d <= 3.3 and (d > 2.2 or y == 0) then
        set(x, y, z, y <= 2 and "stone_bricks" or (y % 5 == 0) and "white_concrete" or "light_gray_concrete")
      end
    end
  end
end
for k = 0, 4 do
  local r = 3.3 * math.sqrt(1 - (k / 4.6) ^ 2)
  for z = SZ - 4, SZ + 4 do
    for x = SX - 4, SX + 4 do
      local d = dist(x - SX, z - SZ)
      if d <= r and (d > r - 1.3 or k == 4) then set(x, STOP + 1 + k, z, "cut_copper") end
    end
  end
end
-- a chute from the silo into the barn's east wall
for x = W + 1, SX - 4 do set(x, 5, SZ, "spruce_slab") end

---------------------------------------------------------------- paddock

local PX0, PX1, PZ0, PZ1 = -9, -2, 2, 14
for z = PZ0, PZ1 do
  for x = PX0, PX1 do
    if x == PX0 or x == PX1 or z == PZ0 or z == PZ1 then set(x, 1, z, "spruce_fence") end
  end
end
set(PX1, 1, 8, "spruce_fence_gate[facing=east]")
-- the trough: a row of water in a plank box
for z = 5, 9 do for x = -6, -4 do set(x, 1, z, "spruce_planks") end end
for z = 6, 8 do set(-5, 1, z, "water") end
fill(-6, 0, 5, -4, 0, 9, "spruce_planks")
set(PX0, 2, PZ0, "lantern"); set(PX1, 2, PZ1, "lantern")
set(-7, 1, 12, "hay_block"); set(-8, 1, 12, "hay_block")

local barn = { name = "Barn and silo", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  barn.blocks[#barn.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return barn
