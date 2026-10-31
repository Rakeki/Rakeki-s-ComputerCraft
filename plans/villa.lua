-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Villa: a modern house of two white boxes with flat roofs and walls of
-- glass. The upper box sits across the lower one and runs out over a
-- wooden terrace on two slim columns. Downstairs an open living room with
-- a kitchen, a dining table and a sofa; a stair to a bedroom and study
-- upstairs; lights set in the ceilings. Outside: a pool (30 water buckets)
-- with a quartz deck, loungers and a fire pit under the overhang,
-- planters, and a hedge round the back of the plot. y 0 is the ground; x
-- runs east, z south; the pool is on the south side, the door on the north.
local A = { x0 = 2, x1 = 13, z0 = 2, z1 = 11 } -- the lower box
local B = { x0 = 6, x1 = 20, z0 = 0, z1 = 9 } -- the upper box
local UP = 5 -- the upper floor's level
local TOP = 10 -- the upper roof's level

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
local function fill(x0, y0, z0, x1, y1, z1, block)
  for y = y0, y1 do for z = z0, z1 do for x = x0, x1 do set(x, y, z, block) end end end
end
-- a box: floor and ceiling slabs, walls round the edge with the given block for each wall cell
local function box(b, y0, y1, wall)
  fill(b.x0, y0, b.z0, b.x1, y0, b.z1, "smooth_quartz")
  fill(b.x0, y1, b.z0, b.x1, y1, b.z1, "white_concrete")
  for y = y0 + 1, y1 - 1 do
    for z = b.z0, b.z1 do
      for x = b.x0, b.x1 do
        if x == b.x0 or x == b.x1 or z == b.z0 or z == b.z1 then set(x, y, z, wall(x, y, z)) else set(x, y, z, nil) end
      end
    end
  end
  -- lights set in the ceiling
  for z = b.z0 + 2, b.z1 - 2, 3 do for x = b.x0 + 2, b.x1 - 2, 4 do set(x, y1, z, "sea_lantern") end end
end

---------------------------------------------------------------- the plot

fill(-1, 0, -3, 22, 0, 17, "moss_block")
for z = -3, 1 do set(9, 0, z, "smooth_stone"); set(10, 0, z, "smooth_stone") end
-- the terrace under the overhang and the pool deck
fill(14, 0, 0, 21, 0, 11, "spruce_planks")
fill(2, 0, 12, 18, 0, 16, "smooth_quartz")
for z = 13, 15 do for x = 4, 13 do set(x, 0, z, "water"); set(x, -1, z, "light_blue_terracotta") end end
-- the hedge round the back and sides
for z = -3, 17 do
  for x = -1, 22 do
    local edge = x == -1 or x == 22 or z == -3
    if edge and not (z == -3 and (x == 9 or x == 10)) then set(x, 1, z, "azalea_leaves"); set(x, 2, z, "azalea_leaves") end
  end
end

---------------------------------------------------------------- the lower box

box(A, 0, UP, function(x, y, z)
  if (x == A.x0 or x == A.x1) and (z == A.z0 or z == A.z1) then return "gray_concrete" end
  if z == A.z1 then return "glass" end -- the garden side is all glass
  if x == A.x1 and z > A.z0 + 1 then return "glass" end
  if z == A.z0 and x <= 5 then return "dark_oak_planks" end -- a wooden panel by the door
  if y == 2 or y == 3 then return (x + z) % 4 == 0 and "white_concrete" or "glass" end
  return "white_concrete"
end)
set(9, 1, A.z0, "dark_oak_door[facing=north]"); set(9, 2, A.z0, nil)
set(10, 1, A.z0, "white_concrete"); set(10, 2, A.z0, "white_concrete")
set(9, 1, A.z1, "dark_oak_door[facing=south]"); set(9, 2, A.z1, nil) -- out to the pool
-- kitchen along the back wall, a dining table, a sofa facing the garden
for x = 3, 7 do set(x, 1, 10, "smooth_quartz") end
set(3, 1, 10, "smoker"); set(5, 1, 10, "cauldron"); set(7, 1, 10, "barrel")
for x = 4, 6 do set(x, 1, 7, "dark_oak_fence"); set(x, 2, 7, "smooth_quartz_slab") end
set(3, 1, 7, "dark_oak_stairs[facing=west]"); set(7, 1, 7, "dark_oak_stairs[facing=east]")
for z = 5, 8 do set(8, 1, z, "light_gray_wool") end
for x = 9, 10 do for z = 5, 8 do set(x, 1, z, "white_carpet") end end
set(10, 1, 6, "dark_oak_slab")
-- the stair up along the east wall, under the upper box
for i = 0, UP - 1 do set(12, 1 + i, 3 + i, "smooth_quartz_stairs[facing=south]") end

---------------------------------------------------------------- the upper box

box(B, UP, TOP, function(x, y, z)
  if (x == B.x0 or x == B.x1) and (z == B.z0 or z == B.z1) then return "gray_concrete" end
  if x == B.x1 or (z == B.z1 and x > A.x1) then return "glass" end -- full glass over the terrace
  if y == UP + 2 or y == UP + 3 then return "glass" end -- a long window band
  return "white_concrete"
end)
-- the stair arrives inside: its last step in the floor, room to climb over the two below
set(12, UP, 7, "smooth_quartz_stairs[facing=south]"); set(12, UP, 5, nil); set(12, UP, 6, nil)
set(8, UP + 1, B.z1, "dark_oak_door[facing=south]"); set(8, UP + 2, B.z1, nil) -- out onto the roof garden
-- the upper box's floor reaches past the lower one: it's the terrace's roof
for _, c in ipairs({ { B.x1, B.z0 }, { B.x1, B.z1 } }) do for y = 1, UP - 1 do set(c[1], y, c[2], "gray_concrete") end end
-- bedroom at the east end, study at the west
for x = 15, 16 do for z = 2, 4 do set(x, UP + 1, z, "light_blue_carpet") end end
set(17, UP + 1, 2, "chest"); set(14, UP + 1, 2, "lantern")
for z = 5, 8 do set(15, UP + 1, z, "white_carpet") end
for y = UP + 1, TOP - 1 do set(13, y, 1, "white_concrete"); set(13, y, 2, "white_concrete"); set(13, y, 4, "white_concrete") end
set(8, UP + 1, 1, "bookshelf"); set(9, UP + 1, 1, "bookshelf"); set(10, UP + 1, 1, "bookshelf")
set(9, UP + 1, 5, "lectern"); set(10, UP + 1, 5, "smooth_quartz_stairs[facing=east]")
-- a balcony rail along the glass over the terrace, a parapet round the roof
for x = B.x0, B.x1 do set(x, TOP + 1, B.z0, "white_concrete"); set(x, TOP + 1, B.z1, "white_concrete") end
for z = B.z0, B.z1 do set(B.x0, TOP + 1, z, "white_concrete"); set(B.x1, TOP + 1, z, "white_concrete") end
-- the lower box's roof is a garden terrace: planters on it
for x = A.x0, A.x1 do
  for z = A.z0, A.z1 do
    if z > B.z1 then
      if x == A.x0 or x == A.x1 or z == A.z1 then set(x, UP + 1, z, "glass_pane") end
    end
  end
end
set(3, UP + 1, 10, "moss_block"); set(3, UP + 2, 10, "azalea"); set(12, UP + 1, 10, "moss_block"); set(12, UP + 2, 10, "flowering_azalea")

---------------------------------------------------------------- terrace and pool

-- loungers by the pool, a fire pit and seats under the overhang
for _, x in ipairs({ 5, 8, 11 }) do set(x, 1, 16, "quartz_stairs[facing=south]") end
for z = 4, 6 do for x = 16, 18 do set(x, 0, z, "polished_blackstone") end end
set(17, 1, 5, "campfire")
for _, c in ipairs({ { 15, 5, "west" }, { 19, 5, "east" }, { 17, 3, "north" }, { 17, 7, "south" } }) do set(c[1], 1, c[2], "spruce_stairs[facing=" .. c[3] .. "]") end
-- planters along the terrace edge, lamps by the pool
for _, z in ipairs({ 1, 10 }) do set(21, 1, z, "moss_block"); set(21, 2, z, "fern") end
for _, x in ipairs({ 2, 15, 18 }) do set(x, 1, 12, "end_rod") end

local villa = { name = "Villa", blocks = {} }
for key, block in pairs(grid) do
  local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
  villa.blocks[#villa.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return villa
