-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Tavern: a two-storey timber-framed inn. Stone ground floor with a bar of
-- barrels, tables and stools and a brick fireplace; a stair up to an upper
-- floor of white plaster between dark posts that juts out over the street
-- on both long sides, with three guest rooms (bed spots marked with
-- carpet: turtles can't place beds). A steep dark oak roof with dormers,
-- a chimney, lamp posts and a bench by the door. y 0 is the ground; x
-- runs east, z south, the front door faces north.
local W, L = 16, 10 -- ground floor walls on x 0..W, z 0..L
local UP = 5 -- the upper floor's level
local EAVES = 10 -- the roof's lowest course

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
local function fill(x0, y0, z0, x1, y1, z1, block)
  for y = y0, y1 do for z = z0, z1 do for x = x0, x1 do set(x, y, z, block) end end end
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function stone(x, y, z)
  local n = noise(x, y, z)
  return n < 0.2 and "cobblestone" or n < 0.3 and "mossy_stone_bricks" or "stone_bricks"
end

---------------------------------------------------------------- ground floor

fill(0, 0, 0, W, 0, L, "cobblestone")
fill(1, 0, 1, W - 1, 0, L - 1, "spruce_planks")
for y = 1, UP - 1 do
  for z = 0, L do
    for x = 0, W do
      if x == 0 or x == W or z == 0 or z == L then
        local corner = (x == 0 or x == W) and (z == 0 or z == L)
        set(x, y, z, corner and "dark_oak_log" or stone(x, y, z))
      end
    end
  end
end
-- windows each side of the door, and along the back and ends
for _, x in ipairs({ 2, 3, 5, 11, 13, 14 }) do set(x, 2, 0, "glass_pane"); set(x, 3, 0, "glass_pane") end
for _, x in ipairs({ 3, 4, 12, 13 }) do set(x, 2, L, "glass_pane") end
for _, z in ipairs({ 3, 7 }) do set(0, 2, z, "glass_pane"); set(W, 2, z, "glass_pane") end
-- double doors under a little porch roof
set(8, 1, 0, "spruce_door[facing=north]"); set(8, 2, 0, nil)
set(9, 1, 0, "spruce_door[facing=north]"); set(9, 2, 0, nil)
for x = 7, 10 do set(x, 4, -1, "dark_oak_slab") end
set(7, 1, -1, "dark_oak_fence"); set(7, 2, -1, "dark_oak_fence"); set(7, 3, -1, "dark_oak_fence")
set(10, 1, -1, "dark_oak_fence"); set(10, 2, -1, "dark_oak_fence"); set(10, 3, -1, "dark_oak_fence")

-- the bar along the east end, barrels behind it
for z = 2, 7 do set(12, 1, z, "spruce_slab") end
set(12, 1, 2, "barrel"); set(12, 2, 2, "lantern")
for z = 2, 8 do set(15, 1, z, "barrel"); if z % 2 == 0 then set(15, 2, z, "barrel") end end
set(14, 1, 8, "smoker"); set(13, 1, 8, "crafting_table")
for z = 3, 6 do set(11, 1, z, "spruce_stairs[facing=west]") end
-- tables (a fence under a pressure plate) with stools round them
for _, t in ipairs({ { 3, 3 }, { 3, 7 }, { 7, 4 } }) do
  set(t[1], 1, t[2], "dark_oak_fence"); set(t[1], 2, t[2], "oak_pressure_plate")
  set(t[1] - 1, 1, t[2], "spruce_stairs[facing=west]"); set(t[1] + 1, 1, t[2], "spruce_stairs[facing=east]")
end
-- the fireplace in the west wall (its chimney goes up after the roof)
set(0, 1, 5, "campfire"); set(0, 2, 5, "bricks"); set(0, 3, 5, "bricks"); set(0, 1, 4, "bricks"); set(0, 1, 6, "bricks")
set(1, 1, 1, "lantern"); set(1, 1, L - 1, "lantern")

---------------------------------------------------------------- upper floor

-- it juts a block out over the street front and back
local Z0, Z1 = -1, L + 1
fill(0, UP, Z0, W, UP, Z1, "spruce_planks")
for x = 0, W do set(x, UP, Z0, "dark_oak_planks"); set(x, UP, Z1, "dark_oak_planks") end
for y = UP + 1, EAVES - 1 do
  for z = Z0, Z1 do
    for x = 0, W do
      if x == 0 or x == W or z == Z0 or z == Z1 then
        local post = (z == Z0 or z == Z1) and x % 4 == 0 or (x == 0 or x == W) and (z == Z0 or z == Z1 or z == 5)
        local beam = y == EAVES - 1
        set(x, y, z, (post or beam) and "dark_oak_log" or "white_terracotta")
      end
    end
  end
end
-- diagonal braces in the end walls
set(0, UP + 1, Z0 + 1, "dark_oak_planks"); set(0, UP + 2, Z0 + 2, "dark_oak_planks")
set(W, UP + 1, Z0 + 1, "dark_oak_planks"); set(W, UP + 2, Z0 + 2, "dark_oak_planks")
for _, x in ipairs({ 2, 6, 10, 14 }) do
  set(x, UP + 2, Z0, "glass_pane"); set(x, UP + 2, Z1, "glass_pane")
end
-- the stair up: along the back wall, west to east, through a hole in the floor
for i = 0, UP - 1 do set(5 + i, 1 + i, L - 1, "spruce_stairs[facing=east]") end
for x = 6, 8 do set(x, UP, L - 1, nil) end -- headroom over the top steps
-- three guest rooms off a landing at the back
for y = UP + 1, EAVES - 1 do
  for _, x in ipairs({ 5, 11 }) do for z = Z0 + 1, 6 do set(x, y, z, "spruce_planks") end end
  for x = 1, W - 1 do set(x, y, 6, "spruce_planks") end
end
for _, x in ipairs({ 3, 8, 14 }) do set(x, UP + 1, 6, "spruce_door[facing=south]"); set(x, UP + 2, 6, nil) end
for _, room in ipairs({ { 1, 4 }, { 6, 10 }, { 12, 15 } }) do
  set(room[1], UP + 1, 0, "red_carpet"); set(room[1], UP + 1, 1, "red_carpet")
  set(room[1] + 1, UP + 1, 0, "chest"); set(room[2], UP + 1, 0, "lantern")
end
set(13, UP + 1, 9, "barrel"); set(2, UP + 1, 9, "lantern")

---------------------------------------------------------------- roof

local i = 0
while Z0 - 1 + i < Z1 + 1 - i do
  for x = -1, W + 1 do
    set(x, EAVES + i, Z0 - 1 + i, "dark_oak_stairs[facing=south]")
    set(x, EAVES + i, Z1 + 1 - i, "dark_oak_stairs[facing=north]")
  end
  for z = Z0 + i, Z1 - i do set(0, EAVES + i, z, "white_terracotta"); set(W, EAVES + i, z, "white_terracotta") end
  i = i + 1
end
for x = -1, W + 1 do set(x, EAVES + i, Z0 - 1 + i, "dark_oak_slab") end
-- two dormers on the front slope
for _, dx in ipairs({ 4, 12 }) do
  for y = EAVES, EAVES + 2 do
    set(dx - 1, y, Z0, "dark_oak_log"); set(dx + 1, y, Z0, "dark_oak_log")
    set(dx, y, Z0, y == EAVES + 2 and "dark_oak_planks" or "glass_pane")
  end
  for z = Z0, Z0 + 2 do set(dx, EAVES + 3, z, "dark_oak_slab"); set(dx - 1, EAVES + 3, z, "dark_oak_stairs[facing=east]"); set(dx + 1, EAVES + 3, z, "dark_oak_stairs[facing=west]") end
  for z = Z0 + 1, Z0 + 2 do for y = EAVES, EAVES + 2 do set(dx, y, z, nil) end end
end

-- the chimney, outside the west wall and up through the eaves
for y = 1, 18 do for z = 4, 6 do set(-1, y, z, "bricks") end end
set(-1, 18, 5, "campfire")

---------------------------------------------------------------- street

for _, x in ipairs({ 3, 14 }) do
  set(x, 1, -3, "dark_oak_fence"); set(x, 2, -3, "dark_oak_fence"); set(x, 3, -3, "lantern")
end
for x = 11, 13 do set(x, 1, -2, "spruce_stairs[facing=south]") end
set(5, 1, -2, "barrel"); set(5, 2, -2, "barrel"); set(4, 1, -2, "barrel")

local tavern = { name = "Tavern", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  tavern.blocks[#tavern.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return tavern
