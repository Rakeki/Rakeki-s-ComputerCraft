-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Hideout: a two-level room for the 25x17x11 hole 'excavate hideout' digs.
-- Along the north side, a stone-edged balcony on spruce posts with a dark
-- oak railing and lanterns, reached by a stair up the east wall. Under it,
-- four alcoves between the posts: a fireplace, an unlit portal frame, a
-- brewing counter with a shelf, and a moss planter hung with leaves. On the
-- balcony, a library corner with an enchanting table, barrels and another
-- planter. The south wall is a timber frame of storage barrels, a work
-- counter and hanging leaves; a pool lit by sea lanterns sits in the floor.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 25, 17, 11
local TOP = H - 2
local HOME = { x = 12, z = 8 }
local hideout = { name = "Hideout", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local BALCONY = 7 -- the balcony floor's layer (you stand on it at 8)
local EDGE = 5 -- the balcony's front edge (z); it runs back to the north wall
local POSTS = { 1, 6, 12, 18, 23 } -- along the balcony's edge and the south wall
local STAIR_X = { 22, 23 } -- the stair up the east wall, rising north

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local isPost = {}
for _, x in ipairs(POSTS) do isPost[x] = true end
local function leaves(x, y, z)
  set(x, y, z, noise(z, y, x) < 0.3 and "minecraft:flowering_azalea_leaves" or "minecraft:azalea_leaves")
end

---------------------------------------------------------------- shell

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, z)
      if x == 0 or z == 0 or x == W - 1 or z == L - 1 then
        set(x, y, z, n < 0.1 and "minecraft:cracked_stone_bricks" or n < 0.25 and "minecraft:andesite"
          or "minecraft:stone_bricks")
      elseif y == 0 then
        set(x, y, z, n < 0.15 and "minecraft:cobblestone" or n < 0.45 and "minecraft:polished_andesite"
          or n < 0.55 and "minecraft:cracked_stone_bricks" or "minecraft:stone_bricks")
      end
    end
  end
end

---------------------------------------------------------------- balcony

for x = 1, W - 2 do
  for z = 1, EDGE - 1 do set(x, BALCONY, z, "minecraft:spruce_planks") end
  set(x, BALCONY, EDGE, "minecraft:polished_andesite")
  set(x, BALCONY - 1, EDGE, "minecraft:stone_bricks")
  if isPost[x] then
    for y = 1, BALCONY - 2 do set(x, y, EDGE, "minecraft:spruce_log") end
  elseif isPost[x - 1] or isPost[x + 1] then
    set(x, BALCONY - 2, EDGE, "minecraft:spruce_planks") -- corbels: an arch between posts
  end
  -- the railing, open where the stair arrives, lanterns over the posts
  if x < STAIR_X[1] then
    set(x, BALCONY + 1, EDGE, "minecraft:dark_oak_fence")
    if isPost[x] and x > 1 then set(x, BALCONY + 2, EDGE, "minecraft:lantern") end
  end
end

-- stair up the east wall: step k's block at layer k, the top one a landing
-- level with the balcony; solid stone under the steps, a fence along the open side
for k = 1, BALCONY do
  local z = EDGE + 1 + BALCONY - k
  for _, x in ipairs(STAIR_X) do
    set(x, k, z, k == BALCONY and "minecraft:spruce_planks" or "minecraft:spruce_stairs[facing=north]")
    for y = 1, k - 1 do set(x, y, z, "minecraft:stone_bricks") end
  end
  if k < BALCONY then set(STAIR_X[1] - 1, k + 1, z, "minecraft:dark_oak_fence") end
end

---------------------------------------------------------------- alcoves under the balcony

-- fireplace (x 2-5): a stone chimney breast with cheeks, a campfire in it,
-- a lantern on the mantel
for x = 2, 5 do
  for y = 1, BALCONY - 1 do
    if not (x >= 3 and x <= 4 and y <= 2) then set(x, y, 1, "minecraft:stone_bricks") end
  end
  set(x, 3, 2, "minecraft:stone_bricks")
end
for y = 1, 2 do
  set(2, y, 2, "minecraft:stone_bricks")
  set(5, y, 2, "minecraft:stone_bricks")
end
set(3, 1, 1, "minecraft:campfire")
set(4, 1, 1, "minecraft:campfire")
set(3, 4, 2, "minecraft:lantern")
set(5, 4, 2, "minecraft:candle")

-- portal frame (x 7-11, 5 wide and 5 high); light it yourself
for x = 7, 11 do
  for y = 1, 5 do
    if x == 7 or x == 11 or y == 1 or y == 5 then set(x, y, 1, "minecraft:obsidian") end
  end
end
set(8, 1, 3, "minecraft:lantern")
set(10, 1, 3, "minecraft:lantern")

-- brewing counter (x 13-17): barrels, the stand and a cauldron on top, a
-- plank shelf above with a lantern and candles
for x = 13, 17 do
  set(x, 1, 1, "minecraft:barrel")
  set(x, 4, 1, "minecraft:spruce_planks")
end
set(13, 2, 1, "minecraft:candle")
set(14, 2, 1, "minecraft:brewing_stand")
set(16, 2, 1, "minecraft:cauldron")
set(17, 2, 1, "minecraft:lantern")
set(13, 5, 1, "minecraft:candle")
set(15, 5, 1, "minecraft:lantern")
set(17, 5, 1, "minecraft:candle")

-- planter (x 19-21): moss, azaleas and flowers, leaves hanging above
local PLANTS = { "minecraft:flowering_azalea", "minecraft:fern", "minecraft:azalea" }
for x = 19, 21 do
  set(x, 1, 1, "minecraft:moss_block")
  set(x, 1, 2, "minecraft:moss_block")
  set(x, 2, 1, PLANTS[x - 18])
  set(x, 2, 2, x == 20 and "minecraft:poppy" or "minecraft:cornflower")
  for y = 4, BALCONY - 1 do
    if noise(x, y, 1) < (y - 3) * 0.25 then leaves(x, y, 1) end
  end
end

---------------------------------------------------------------- on the balcony

for x = 2, 9 do
  set(x, BALCONY + 1, 1, "minecraft:bookshelf")
  set(x, BALCONY + 2, 1, "minecraft:bookshelf")
end
set(5, BALCONY + 1, 3, "minecraft:enchanting_table")
set(11, BALCONY + 1, 1, "minecraft:lantern")
for x = 13, 17 do set(x, BALCONY + 1, 1, "minecraft:barrel") end
set(13, BALCONY + 2, 1, "minecraft:lantern")
set(17, BALCONY + 2, 1, "minecraft:candle")
for x = 19, 21 do set(x, BALCONY + 1, 1, "minecraft:moss_block") end
set(19, BALCONY + 2, 1, "minecraft:azalea")
set(20, BALCONY + 2, 1, "minecraft:flowering_azalea")
set(21, BALCONY + 2, 1, "minecraft:fern")

---------------------------------------------------------------- south wall

-- spruce logs full height with a beam on top, corbels beside them; between
-- them barrels, a work counter, barrels, and hanging leaves
local S = L - 2
for x = 1, W - 2 do
  if isPost[x] then
    for y = 1, TOP do set(x, y, S, "minecraft:spruce_log") end
  else
    set(x, TOP, S, "minecraft:stripped_spruce_wood")
    if isPost[x - 1] or isPost[x + 1] then set(x, TOP - 1, S, "minecraft:spruce_planks") end
  end
end
for _, x0 in ipairs({ 2, 13 }) do
  for x = x0, x0 + 4 do
    if not isPost[x] then for y = 1, 3 do set(x, y, S, "minecraft:barrel") end end
  end
  set(x0 + 2, 4, S, "minecraft:lantern")
end
local COUNTER = { "minecraft:crafting_table", "minecraft:smithing_table", "minecraft:barrel",
  "minecraft:fletching_table", "minecraft:cartography_table" }
for i, block in ipairs(COUNTER) do set(6 + i, 1, S, block) end
set(9, 2, S, "minecraft:lantern")
for x = 19, 22 do
  for y = 3, TOP - 2 do
    if noise(x, y, S) < (y - 2) * 0.15 then leaves(x, y, S) end
  end
  set(x, 1, S - 1, noise(x, 1, S) < 0.6 and "minecraft:moss_carpet" or nil)
end
set(20, 1, S, "minecraft:lantern")

-- ivy on the open stretch of the west wall
for z = EDGE + 1, S - 1 do
  for y = 2, TOP - 1 do
    if noise(1, y, z) < 0.04 * (y - 1) and noise(z, 1, y) < 0.7 then leaves(1, y, z) end
  end
end

---------------------------------------------------------------- floor pool

-- a pool in the floor, sea lanterns at its corners, lanterns beside it
for z = 10, 12 do
  for x = 10, 14 do
    local corner = (x == 10 or x == 14) and (z == 10 or z == 12)
    set(x, 0, z, corner and "minecraft:sea_lantern" or "minecraft:water")
  end
end
set(8, 1, 11, "minecraft:lantern")
set(16, 1, 11, "minecraft:lantern")

---------------------------------------------------------------- out

-- the builder's home column, and the floor under its two chests, stay empty
for y = 0, TOP do set(HOME.x, y, HOME.z, nil) end
set(HOME.x, 0, HOME.z - 1, nil)
set(HOME.x + 1, 0, HOME.z, nil)

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = grid[x .. "," .. y .. "," .. z]
      if block then hideout.blocks[#hideout.blocks + 1] = { x, y, z, block } end
    end
  end
end
return hideout
