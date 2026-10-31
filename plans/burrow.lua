-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Burrow: a survival base six floors deep, for the 21x17x31 hole 'excavate
-- burrow' digs. A stair climbs the east side, a flight per floor, turning
-- back on itself each time; at the top it carries on up into the rock, so
-- you dig the rest of the way to the surface from there (or put the burrow
-- under your house). From the top down: a lounge with a sofa, a rug and a
-- fireplace; a kitchen with a cooking counter and a storeroom of chests and
-- barrels; a farm of sugar cane, pumpkins, melons and berry bushes along
-- water channels; a bedroom (bed spots marked with carpet) with a
-- fireplace, whose ceiling is the glass under the farm's channels; an
-- enchanting room with a full ring of bookshelves; and a Nether portal room
-- at the bottom with an unlit frame.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear: a shaft through every floor beside the stair, fenced on each
-- floor (put a ladder in it once the building's done). The top layer is
-- one below the ceiling: the builder stands a block above what it places.
-- Built inside the dug hole, so "clear" is false.
local W, L, H = 21, 17, 31
local TOP = H - 2
local HOME = { x = 17, z = 15 }
local burrow = { name = "Burrow", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local STOREY = 5 -- floor to floor: a floor layer and 4 to stand in
local FLOORS = 6 -- floor k's layer is k * STOREY, from the portal room (0) to the lounge (5)
local ROOM_X = 14 -- rooms run x 1-14; the stair takes x 15-19
local LANE_N = { 18, 19 } -- flights on even floors climb north here
local LANE_S = { 15, 16 } -- flights on odd floors climb south here
local DIVIDE = 17 -- the wall between the two lanes
local STEPS_Z = { 9, 10, 11, 12 } -- every flight's four steps
local LIGHT = "minecraft:pearlescent_froglight"

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function floorY(k) return k * STOREY end

---------------------------------------------------------------- shell and floors

local FLOOR_BLOCK = {
  [0] = "minecraft:polished_blackstone", "minecraft:dark_oak_planks", "minecraft:spruce_planks",
  "minecraft:moss_block", "minecraft:polished_andesite", "minecraft:oak_planks",
}
for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      if x == 0 or z == 0 or x == W - 1 or z == L - 1 then
        local n = noise(x, y, z)
        set(x, y, z, y % STOREY == 0 and "minecraft:polished_andesite" or n < 0.1 and "minecraft:cracked_stone_bricks"
          or n < 0.2 and "minecraft:mossy_stone_bricks" or "minecraft:stone_bricks")
      end
    end
  end
end
for k = 0, FLOORS - 1 do
  local y = floorY(k)
  for z = 1, L - 2 do
    for x = 1, W - 2 do
      local block = FLOOR_BLOCK[k]
      if x > ROOM_X then block = "minecraft:stone_bricks" end
      -- lights set in the floor, for the room below
      if k > 0 and k ~= 3 and (x == 4 or x == 10) and (z == 4 or z == 12) then block = LIGHT end
      set(x, y, z, block)
    end
  end
end

---------------------------------------------------------------- the stair

-- Flight k climbs from floor k to floor k + 1: four steps on STEPS_Z, a
-- hole in the floor above them, a railing round the hole. Even flights
-- climb north on LANE_N, odd ones south on LANE_S; the wall between the
-- lanes runs the full height. Flight 5 climbs from the lounge into the rock.
for y = 1, TOP do
  for _, z in ipairs(STEPS_Z) do
    if y % STOREY ~= 0 then set(DIVIDE, y, z, "minecraft:stone_bricks") end
  end
end
for k = 0, FLOORS - 1 do
  local lane, north = k % 2 == 0 and LANE_N or LANE_S, k % 2 == 0
  local y0 = floorY(k)
  for i = 1, 4 do
    local z = north and STEPS_Z[5 - i] or STEPS_Z[i]
    for _, x in ipairs(lane) do
      set(x, y0 + i, z, north and "minecraft:stone_brick_stairs[facing=north]" or "minecraft:stone_brick_stairs[facing=south]")
      for y = y0 + 1, y0 + i - 1 do set(x, y, z, "minecraft:stone_bricks") end
      if y0 + STOREY <= TOP then set(x, y0 + STOREY, z, nil) end
    end
  end
  -- the railing round the hole, on the floor above
  local ry = y0 + STOREY + 1
  if ry <= TOP then
    if north then
      for _, x in ipairs(lane) do set(x, ry, 13, "minecraft:spruce_fence") end
    else
      for _, x in ipairs(lane) do set(x, ry, 8, "minecraft:spruce_fence") end
      for _, z in ipairs(STEPS_Z) do set(ROOM_X, ry, z, "minecraft:spruce_fence") end
      set(ROOM_X, ry + 1, STEPS_Z[1], "minecraft:lantern")
    end
  end
end
-- the builder's shaft, fenced on every floor but the bottom (its chests are there)
for k = 1, FLOORS - 1 do
  local y = floorY(k) + 1
  set(HOME.x - 1, y, HOME.z, "minecraft:spruce_fence")
  set(HOME.x + 1, y, HOME.z, "minecraft:spruce_fence")
  set(HOME.x, y, HOME.z - 1, "minecraft:spruce_fence")
end
-- lanterns on the stair landings
for k = 0, FLOORS - 1 do set(W - 2, floorY(k) + 1, k % 2 == 0 and 14 or 7, "minecraft:lantern") end

---------------------------------------------------------------- the rooms

-- a ring of bookshelves two high round (cx, cz), open on the four sides
local function shelfRing(cx, y, cz)
  for dz = -2, 2 do
    for dx = -2, 2 do
      if math.max(math.abs(dx), math.abs(dz)) == 2 and dx ~= 0 and dz ~= 0 then
        set(cx + dx, y, cz + dz, "minecraft:bookshelf")
        set(cx + dx, y + 1, cz + dz, "minecraft:bookshelf")
      end
    end
  end
end
-- a fireplace in the west wall: brick cheeks and a chimney, a campfire
local function fireplace(y, z)
  for dz = -1, 1 do
    for h = 0, STOREY - 2 do
      if not (dz == 0 and h <= 1) then set(1, y + h, z + dz, "minecraft:bricks") end
    end
  end
  set(1, y, z, "minecraft:campfire")
  set(2, y, z - 1, "minecraft:bricks")
  set(2, y, z + 1, "minecraft:bricks")
  set(2, y + 1, z - 1, "minecraft:lantern")
end

-- 0: the portal room
do
  local y = floorY(0) + 1
  for z = 1, L - 2 do
    for x = 1, ROOM_X do
      if noise(x, 0, z) < 0.25 then set(x, 0, z, "minecraft:blackstone") end
    end
  end
  -- the frame stands in the floor, against the west wall: 4 wide, 5 high
  for z = 6, 9 do
    for h = 0, 4 do
      local frame = z == 6 or z == 9 or h == 0 or h == 4
      local corner = (z == 6 or z == 9) and (h == 0 or h == 4)
      set(1, h, z, frame and (corner and "minecraft:crying_obsidian" or "minecraft:obsidian") or nil)
    end
  end
  for _, z in ipairs({ 4, 11 }) do
    set(1, y, z, "minecraft:polished_blackstone_bricks")
    set(1, y + 1, z, "minecraft:soul_campfire")
  end
  for x = 2, 4 do set(x, 0, 7, "minecraft:gilded_blackstone"); set(x, 0, 8, "minecraft:gilded_blackstone") end
  for x = 1, 6 do set(x, y, 15, "minecraft:chest[facing=north]") end
  for x = 8, 11 do set(x, y, 15, "minecraft:barrel") end
  set(9, y + 1, 15, "minecraft:soul_lantern")
  set(ROOM_X, y, 2, "minecraft:soul_lantern")
  set(ROOM_X, y, 14, "minecraft:soul_lantern")
end

-- 1: the enchanting room
do
  local y = floorY(1) + 1
  shelfRing(7, y, 8)
  set(7, y, 8, "minecraft:enchanting_table")
  for dz = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dz ~= 0 then set(7 + dx, y, 8 + dz, "minecraft:purple_carpet") end
    end
  end
  for _, c in ipairs({ { 5, 6 }, { 9, 6 }, { 5, 10 }, { 9, 10 } }) do set(c[1], y + 2, c[2], "minecraft:candle") end
  set(2, y, 2, "minecraft:anvil[facing=east]")
  set(3, y, 2, "minecraft:grindstone[facing=south]")
  set(5, y, 2, "minecraft:lectern[facing=south]")
  set(9, y, 2, "minecraft:lectern[facing=south]")
  for x = 1, ROOM_X do
    for h = 0, 2 do set(x, y + h, L - 2, (h == 1 and x % 4 == 2) and "minecraft:barrel" or "minecraft:bookshelf") end
  end
  set(2, y, 13, "minecraft:lantern")
  set(12, y, 13, "minecraft:lantern")
end

-- 2: the bedroom; glass under the farm's water channels makes its ceiling
do
  local y = floorY(2) + 1
  for _, z in ipairs({ 3, 7 }) do
    for x = 4, 5 do set(x, y, z, "minecraft:red_carpet") end
    for x = 9, 10 do set(x, y, z, "minecraft:blue_carpet") end
    set(3, y, z, "minecraft:chest[facing=east]")
    set(11, y, z, "minecraft:chest[facing=west]")
  end
  set(7, y, 3, "minecraft:barrel")
  set(7, y + 1, 3, "minecraft:lantern")
  set(7, y, 7, "minecraft:barrel")
  set(7, y + 1, 7, "minecraft:candle")
  for x = 4, 10 do for z = 10, 13 do set(x, y, z, "minecraft:white_carpet") end end
  for x = 4, 10 do
    for h = 0, 1 do set(x, y + h, 1, "minecraft:bookshelf") end
  end
  for z = 13, 15 do
    for h = 0, 2 do set(ROOM_X, y + h, z, "minecraft:barrel") end
  end
  set(ROOM_X - 1, y, 15, "minecraft:lantern")
  fireplace(y, 11)
end

-- 3: the farm: water channels in the floor, glass under them
do
  local y0 = floorY(3)
  local CHANNELS = { [4] = true, [8] = true, [12] = true }
  local ROWS = { [3] = "minecraft:sugar_cane", [5] = "minecraft:sugar_cane", [7] = "minecraft:pumpkin",
    [9] = "minecraft:melon", [11] = "minecraft:sweet_berry_bush", [13] = "minecraft:sweet_berry_bush" }
  for z = 1, L - 2 do
    for x = 1, ROOM_X do
      if x == 1 or x == ROOM_X or z == 1 or z == L - 2 then
        set(x, y0, z, "minecraft:stone_bricks")
      elseif CHANNELS[z] then
        set(x, y0, z, "minecraft:water")
        set(x, y0 - 1, z, "minecraft:glass")
      elseif ROWS[z] then
        local plant = ROWS[z]
        if (z == 7 or z == 9) and (x + z) % 2 == 0 then plant = nil end -- room for pumpkins and melons to grow
        set(x, y0 + 1, z, plant)
      end
    end
  end
  set(1, y0 + 1, 2, "minecraft:composter")
  set(1, y0 + 1, 3, "minecraft:barrel")
  set(1, y0 + 1, 4, "minecraft:barrel")
  for _, z in ipairs({ 2, 14 }) do
    for _, x in ipairs({ 4, 10 }) do
      set(x, y0 + 1, z, "minecraft:spruce_fence")
      set(x, y0 + 2, z, "minecraft:lantern")
    end
  end
end

-- 4: the kitchen and storeroom
do
  local y = floorY(4) + 1
  local COUNTER = { "minecraft:smoker[facing=south]", "minecraft:furnace[facing=south]", "minecraft:furnace[facing=south]",
    "minecraft:blast_furnace[facing=south]", "minecraft:crafting_table", "minecraft:barrel", "minecraft:cauldron",
    "minecraft:barrel", "minecraft:smithing_table" }
  for i, block in ipairs(COUNTER) do set(i + 1, y, 1, block) end
  set(6, y + 1, 1, "minecraft:lantern")
  set(9, y + 1, 1, "minecraft:candle")
  -- a table and stools
  for x = 5, 8 do set(x, y, 6, "minecraft:stripped_spruce_wood") end
  for _, x in ipairs({ 5, 8 }) do set(x, y + 1, 6, "minecraft:candle") end
  for x = 5, 8 do
    set(x, y, 5, "minecraft:spruce_stairs[facing=north]")
    set(x, y, 7, "minecraft:spruce_stairs[facing=south]")
  end
  -- the storeroom: chests and barrels along the walls, a wall of them across
  for z = 3, L - 2 do
    set(1, y, z, "minecraft:chest[facing=east]")
    set(1, y + 1, z, "minecraft:chest[facing=east]")
    set(1, y + 2, z, "minecraft:barrel")
  end
  for x = 3, 12 do
    if x ~= 7 and x ~= 8 then
      for h = 0, 2 do set(x, y + h, 11, h == 0 and "minecraft:chest[facing=south]" or "minecraft:barrel") end
    end
    for h = 0, 2 do set(x, y + h, L - 2, "minecraft:barrel") end
  end
  set(6, y + 3, 11, "minecraft:lantern")
end

-- 5: the lounge
do
  local y = floorY(5) + 1
  for x = 4, 9 do
    set(x, y, 2, "minecraft:spruce_stairs[facing=north]") -- a sofa, its back to the wall
    for z = 4, 7 do set(x, y, z, (x == 4 or x == 9 or z == 4 or z == 7) and "minecraft:red_carpet" or "minecraft:white_carpet") end
  end
  set(3, y, 2, "minecraft:spruce_planks")
  set(10, y, 2, "minecraft:spruce_planks")
  set(3, y + 1, 2, "minecraft:lantern")
  set(10, y + 1, 2, "minecraft:candle")
  for z = 1, 5 do
    for h = 0, 2 do set(1, y + h, z, "minecraft:bookshelf") end
  end
  fireplace(y, 10)
  set(6, y, 12, "minecraft:cartography_table")
  set(8, y, 12, "minecraft:jukebox")
  set(12, y, 14, "minecraft:spruce_planks")
  set(12, y + 1, 14, "minecraft:lantern")
  set(ROOM_X, y, 2, "minecraft:flowering_azalea_leaves")
  set(ROOM_X - 1, y, 1, "minecraft:azalea_leaves")
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
      if block then burrow.blocks[#burrow.blocks + 1] = { x, y, z, block } end
    end
  end
end
return burrow
