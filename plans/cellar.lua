-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Cellar: one cosy room for the 17x17x7 hole 'excavate cellar' digs. Stone
-- brick walls and a checked floor; dark oak log pillars round the walls
-- carry a beam, with corbels beside each pillar, so every wall is three
-- alcoves. The middle ones hold the storage barrels, a library with an
-- enchanting table, a work counter with a brewing stand, and an unlit
-- portal frame. The corner ones hang with azalea leaves over a lantern.
-- In the middle, a pool lit by sea lanterns, with a stair rim to sit on
-- and lanterns on fence posts at its corners.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 17, 17, 7
local TOP = H - 2
local HOME = { x = 8, z = 3 }
local cellar = { name = "Cellar", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end

-- A cell against one wall: a counts along it, depth out from the lining.
-- Walls: n, s, w, e; inward is the facing that looks into the room.
local SIDES = {
  n = { inward = "south", at = function(a, d) return a, 1 + d end },
  s = { inward = "north", at = function(a, d) return a, L - 2 - d end },
  w = { inward = "east", at = function(a, d) return 1 + d, a end },
  e = { inward = "west", at = function(a, d) return W - 2 - d, a end },
}
local function wall(side, a, d, y, block)
  local x, z = SIDES[side].at(a, d)
  set(x, y, z, block)
end

---------------------------------------------------------------- shell

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      if x == 0 or z == 0 or x == W - 1 or z == L - 1 then
        local n = noise(x, y, z)
        set(x, y, z, n < 0.12 and "minecraft:cracked_stone_bricks" or n < 0.22 and "minecraft:mossy_stone_bricks"
          or "minecraft:stone_bricks")
      elseif y == 0 then
        -- 2x2 checks
        set(x, y, z, (math.floor(x / 2) + math.floor(z / 2)) % 2 == 0 and "minecraft:polished_andesite"
          or "minecraft:stone_bricks")
      end
    end
  end
end

---------------------------------------------------------------- pillars and beams

local PILLARS = { 1, 5, 11, 15 } -- along each wall; alcoves 2-4, 6-10, 12-14
local isPillar = {}
for _, a in ipairs(PILLARS) do isPillar[a] = true end
for side in pairs(SIDES) do
  for a = 1, 15 do
    if isPillar[a] then
      for y = 1, TOP do wall(side, a, 0, y, "minecraft:dark_oak_log") end
    else
      wall(side, a, 0, TOP, "minecraft:stripped_dark_oak_wood")
      if isPillar[a - 1] or isPillar[a + 1] then wall(side, a, 0, TOP - 1, "minecraft:spruce_planks") end
    end
  end
end

---------------------------------------------------------------- corner alcoves: hanging leaves

for side in pairs(SIDES) do
  for _, first in ipairs({ 2, 12 }) do
    for a = first, first + 2 do
      local x, z = SIDES[side].at(a, 0)
      if a == first + 1 then wall(side, a, 0, TOP - 1, "minecraft:azalea_leaves") end
      for y = TOP - 2, 2, -1 do
        if noise(x, y, z) < (y - 1) * 0.2 then
          wall(side, a, 0, y, noise(z, y, x) < 0.3 and "minecraft:flowering_azalea_leaves" or "minecraft:azalea_leaves")
        end
      end
    end
    wall(side, first + 1, 0, 1, "minecraft:lantern")
    wall(side, first, 1, 1, "minecraft:moss_carpet")
  end
end

---------------------------------------------------------------- middle alcoves

-- north: storage barrels, a lantern on top
for a = 6, 10 do
  for y = 1, 3 do wall("n", a, 0, y, "minecraft:barrel") end
end
wall("n", 8, 0, 4, "minecraft:lantern")

-- south: library, candles on the shelves, the enchanting table in front
for a = 6, 10 do
  for y = 1, 3 do wall("s", a, 0, y, "minecraft:bookshelf") end
end
wall("s", 7, 0, 4, "minecraft:candle")
wall("s", 9, 0, 4, "minecraft:candle")
wall("s", 8, 2, 1, "minecraft:enchanting_table")

-- east: work counter, brewing stand and lantern on it
local COUNTER = { "minecraft:barrel", "minecraft:crafting_table", "minecraft:smithing_table",
  "minecraft:cartography_table", "minecraft:barrel" }
for i, block in ipairs(COUNTER) do wall("e", 5 + i, 0, 1, block) end
wall("e", 6, 0, 2, "minecraft:lantern")
wall("e", 8, 0, 2, "minecraft:brewing_stand")
wall("e", 10, 0, 2, "minecraft:candle")

-- west: a portal frame (5 wide, 5 high); light it yourself
for a = 6, 10 do
  for y = 1, TOP do
    if a == 6 or a == 10 or y == 1 or y == TOP then
      wall("w", a, 0, y, "minecraft:obsidian")
    else
      wall("w", a, 0, y, nil)
    end
  end
end

---------------------------------------------------------------- pool

-- water 5x5 in the floor, sea lanterns at its corners; a rim of stairs
-- leaning in, fence posts with lanterns on the rim's corners
local P0, P1 = 6, 10
for z = P0, P1 do
  for x = P0, P1 do
    local corner = (x == P0 or x == P1) and (z == P0 or z == P1)
    set(x, 0, z, corner and "minecraft:sea_lantern" or "minecraft:water")
  end
end
for i = P0, P1 do
  set(i, 1, P0 - 1, "minecraft:spruce_stairs[facing=south]")
  set(i, 1, P1 + 1, "minecraft:spruce_stairs[facing=north]")
  set(P0 - 1, 1, i, "minecraft:spruce_stairs[facing=east]")
  set(P1 + 1, 1, i, "minecraft:spruce_stairs[facing=west]")
end
for _, x in ipairs({ P0 - 1, P1 + 1 }) do
  for _, z in ipairs({ P0 - 1, P1 + 1 }) do
    set(x, 1, z, "minecraft:dark_oak_fence")
    set(x, 2, z, "minecraft:lantern")
  end
end

---------------------------------------------------------------- out

-- the builder's home column, and the floor under its two chests, stay empty
for y = 0, TOP do set(HOME.x, y, HOME.z, nil) end
set(HOME.x, 0, HOME.z - 1, nil)
set(HOME.x + 1, 0, HOME.z, nil)

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = grid[x .. "," .. y .. "," .. z]
      if block then cellar.blocks[#cellar.blocks + 1] = { x, y, z, block } end
    end
  end
end
return cellar
