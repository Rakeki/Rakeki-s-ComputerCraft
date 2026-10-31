-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Bunker: a first base for the small 23x15x7 hole 'excavate bunker' digs.
-- A stone corridor runs east-west through the middle with eight rooms off
-- it behind spruce doors. North side: storage, a kitchen, a bedroom (bed
-- spots marked with carpet) and an enchanting room with its shelves. South
-- side: a farm of sugar cane along a water channel, a smithy, a brewing
-- room and an unlit portal frame. Lights are set in the ceiling. The
-- corridor's west end is open on the rock: dig your way in from there.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 23, 15, 7
local TOP = H - 2
local HOME = { x = 11, z = 7 }
local bunker = { name = "Bunker", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local HALL = { 6, 8 } -- the corridor's z range; walls on 5 and 9
local ROOMS_X = { { 1, 5 }, { 7, 10 }, { 12, 15 }, { 17, 21 } } -- partitions on 6, 11 and 16
local CEILING = TOP -- rooms are 4 high under it
local LIGHT = "minecraft:shroomlight"

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function stone(x, y, z)
  local n = noise(x, y, z)
  return n < 0.12 and "minecraft:cracked_stone_bricks" or n < 0.25 and "minecraft:andesite" or "minecraft:stone_bricks"
end

---------------------------------------------------------------- shell, walls, floors and ceiling

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      if x == 0 or z == 0 or x == W - 1 or z == L - 1 then
        set(x, y, z, stone(x, y, z))
      elseif y == 0 then
        local hall = z >= HALL[1] and z <= HALL[2]
        set(x, y, z, hall and (z == 7 and "minecraft:polished_andesite" or "minecraft:stone_bricks") or "minecraft:spruce_planks")
      elseif y == CEILING then
        set(x, y, z, "minecraft:spruce_planks")
      elseif z == HALL[1] - 1 or z == HALL[2] + 1 or x == 6 or x == 11 or x == 16 then
        local post = x == 6 or x == 11 or x == 16
        set(x, y, z, post and "minecraft:stripped_spruce_log" or "minecraft:spruce_planks")
      end
    end
  end
end
-- the corridor runs out through the west wall
for y = 1, 3 do for z = HALL[1], HALL[2] do set(0, y, z, nil) end end
for z = HALL[1], HALL[2] do set(0, 4, z, "minecraft:chiseled_stone_bricks") end
-- a light in each room's ceiling and along the corridor
for _, r in ipairs(ROOMS_X) do
  local mx = math.floor((r[1] + r[2]) / 2)
  set(mx, CEILING, 3, LIGHT)
  set(mx, CEILING, 11, LIGHT)
end
for _, x in ipairs({ 3, 8, 14, 19 }) do set(x, CEILING, 7, LIGHT) end

-- a door from the corridor into each room, in the middle of its wall
local function door(x, z, facing)
  set(x, 1, z, "minecraft:spruce_door[facing=" .. facing .. "]")
  set(x, 2, z, nil)
end
for _, r in ipairs(ROOMS_X) do
  local mx = math.floor((r[1] + r[2]) / 2)
  door(mx, HALL[1] - 1, "north")
  door(mx, HALL[2] + 1, "south")
end

---------------------------------------------------------------- north rooms (z 1-4)

-- storage
for x = 1, 5 do
  set(x, 1, 1, "minecraft:chest[facing=south]")
  set(x, 2, 1, "minecraft:barrel")
end
for z = 2, 3 do set(1, 1, z, "minecraft:barrel"); set(1, 2, z, "minecraft:barrel") end
set(5, 1, 3, "minecraft:barrel")
set(5, 2, 3, "minecraft:lantern")

-- kitchen
local KITCHEN = { "minecraft:smoker[facing=south]", "minecraft:furnace[facing=south]", "minecraft:crafting_table", "minecraft:barrel" }
for i, block in ipairs(KITCHEN) do set(6 + i, 1, 1, block) end
set(10, 2, 1, "minecraft:candle")
set(7, 1, 3, "minecraft:stripped_spruce_wood")
set(7, 2, 3, "minecraft:lantern")

-- bedroom
for _, x in ipairs({ 12, 15 }) do
  set(x, 1, 1, "minecraft:red_carpet")
  set(x, 1, 2, "minecraft:red_carpet")
end
set(13, 1, 1, "minecraft:chest[facing=south]")
set(14, 1, 1, "minecraft:barrel")
set(14, 2, 1, "minecraft:lantern")
for x = 13, 14 do set(x, 1, 3, "minecraft:white_carpet") end

-- enchanting: the table two from its shelves
for x = 17, 21 do
  set(x, 1, 1, "minecraft:bookshelf")
  set(x, 2, 1, "minecraft:bookshelf")
end
for z = 2, 3 do
  for _, x in ipairs({ 17, 21 }) do
    set(x, 1, z, "minecraft:bookshelf")
    set(x, 2, z, "minecraft:bookshelf")
  end
end
set(19, 1, 3, "minecraft:enchanting_table")
set(17, 3, 1, "minecraft:candle")
set(21, 3, 1, "minecraft:candle")

---------------------------------------------------------------- south rooms (z 10-13)

-- farm: moss, a water channel, sugar cane either side
for z = 10, 13 do
  for x = 1, 5 do
    if z == 12 then set(x, 0, z, "minecraft:water")
    else
      set(x, 0, z, "minecraft:moss_block")
      if z == 11 or z == 13 then set(x, 1, z, x == 3 and z == 11 and nil or "minecraft:sugar_cane") end
    end
  end
end
set(5, 1, 10, "minecraft:composter")

-- smithy
local SMITHY = { "minecraft:blast_furnace[facing=north]", "minecraft:smithing_table", "minecraft:anvil[facing=east]", "minecraft:grindstone[facing=north]" }
for i, block in ipairs(SMITHY) do set(6 + i, 1, 13, block) end
set(7, 1, 11, "minecraft:barrel")
set(7, 2, 11, "minecraft:lantern")

-- brewing
set(12, 1, 13, "minecraft:barrel")
set(13, 1, 13, "minecraft:brewing_stand")
set(14, 1, 13, "minecraft:cauldron")
set(15, 1, 13, "minecraft:barrel")
set(15, 2, 13, "minecraft:candle")
set(12, 2, 13, "minecraft:lantern")

-- portal: 4 wide and 5 high, its foot in the floor; light it yourself
for x = 17, 20 do
  for y = 0, 4 do
    local frame = x == 17 or x == 20 or y == 0 or y == 4
    set(x, y, 13, frame and ((x == 17 or x == 20) and (y == 0 or y == 4) and "minecraft:crying_obsidian" or "minecraft:obsidian") or nil)
  end
end
set(21, 1, 11, "minecraft:soul_lantern")

---------------------------------------------------------------- out

-- the builder's home column, and the floor under its two chests, stay empty
for y = 0, TOP do set(HOME.x, y, HOME.z, nil) end
set(HOME.x, 0, HOME.z - 1, nil)
set(HOME.x + 1, 0, HOME.z, nil)

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = grid[x .. "," .. y .. "," .. z]
      if block then bunker.blocks[#bunker.blocks + 1] = { x, y, z, block } end
    end
  end
end
return bunker
