-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Wizard tower: a round tower of dark deepslate brick on a rocky mound
-- studded with amethyst, purple windows winding up it, a balcony halfway,
-- and a wider top room jutting out over a sloped collar. On top a tall
-- purple witch's hat that bends over at the tip. Inside, a spiral stair
-- climbs round a column of bookshelves past a library floor to the study:
-- an enchanting table, brewing stand, cauldron, lectern and more shelves.
-- y 0 is the ground; x and z are from the tower's middle.
local TOP_FLOOR = 20 -- the study's floor
local MID_FLOOR = 10

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function dist(x, z) return math.sqrt(x * x + z * z) end
local function brick(x, y, z)
  local n = noise(x, y, z)
  return n < 0.15 and "cracked_deepslate_bricks" or n < 0.22 and "deepslate_tiles" or "deepslate_bricks"
end
-- the cardinal direction pointing from the middle out through x, z
local function outward(x, z)
  if math.abs(x) >= math.abs(z) then return x > 0 and "east" or "west" end
  return z > 0 and "south" or "north"
end

---------------------------------------------------------------- the mound

for z = -8, 8 do
  for x = -8, 8 do
    local d = dist(x, z) + noise(x, 0, z) * 1.5
    local top = d < 5.5 and 1 or d < 8 and 0 or -1
    for y = 0, top do
      local n = noise(x, y, z)
      set(x, y, z, n < 0.12 and "amethyst_block" or n < 0.22 and "calcite" or n < 0.32 and "smooth_basalt" or n < 0.5 and "cobbled_deepslate" or "stone")
    end
    if top >= 0 and d > 5 and noise(z, 2, x) < 0.06 then set(x, top + 1, z, "amethyst_cluster") end
  end
end

---------------------------------------------------------------- the tower

for y = 1, TOP_FLOOR - 1 do
  for z = -5, 5 do
    for x = -5, 5 do
      local d = dist(x, z)
      if d <= 4.5 and d > 3.3 then set(x, y, z, brick(x, y, z))
      elseif d <= 3.3 then
        -- the library floor leaves the stairwell open; the ground floor doesn't
        local floor = y == 1 or (y == MID_FLOOR and math.max(math.abs(x), math.abs(z)) >= 2)
        set(x, y, z, floor and "dark_oak_planks" or nil)
      end
    end
  end
end
-- windows winding round the tower
for y = 3, TOP_FLOOR - 2, 3 do
  local a = y * 0.75
  local x, z = math.floor(4 * math.cos(a) + 0.5), math.floor(4 * math.sin(a) + 0.5)
  if not (x == 0 and z < 0 and y < 5) then set(x, y, z, "purple_stained_glass_pane"); set(x, y + 1, z, "purple_stained_glass_pane") end
end
-- the door
set(0, 2, -4, "dark_oak_door[facing=north]"); set(0, 3, -4, nil)
set(0, 2, -5, nil); set(0, 3, -5, nil); set(0, 1, -5, "deepslate_brick_stairs[facing=south]")
set(0, 1, -4, "polished_deepslate")

-- the balcony on the east side, off the library floor
for z = -1, 1 do
  for x = 5, 6 do set(x, MID_FLOOR, z, "polished_deepslate") end
  set(7, MID_FLOOR + 1, z, "dark_oak_fence")
end
set(5, MID_FLOOR + 1, -2, "dark_oak_fence"); set(6, MID_FLOOR + 1, -2, "dark_oak_fence")
set(5, MID_FLOOR + 1, 2, "dark_oak_fence"); set(6, MID_FLOOR + 1, 2, "dark_oak_fence")
set(4, MID_FLOOR + 1, 0, nil); set(4, MID_FLOOR + 2, 0, nil)
set(6, MID_FLOOR + 1, 1, "cauldron"); set(7, MID_FLOOR + 2, -1, "lantern")

---------------------------------------------------------------- the study, jutting out on a collar

-- a sloped collar of stairs climbing outwards
for z = -6, 6 do
  for x = -6, 6 do
    local d = dist(x, z)
    if d <= 5.6 and d > 4.5 then set(x, TOP_FLOOR - 1, z, "deepslate_brick_stairs[facing=" .. outward(x, z) .. "]") end
  end
end
for y = TOP_FLOOR, TOP_FLOOR + 5 do
  for z = -6, 6 do
    for x = -6, 6 do
      local d = dist(x, z)
      if d <= 5.6 and d > 4.4 then set(x, y, z, y == TOP_FLOOR + 5 and "dark_oak_planks" or brick(x, y, z))
      elseif d <= 4.4 then
        local floor = y == TOP_FLOOR and math.max(math.abs(x), math.abs(z)) >= 2
        set(x, y, z, floor and "dark_oak_planks" or nil)
      end
    end
  end
end
for _, c in ipairs({ { 5, 0 }, { -5, 0 }, { 0, 5 }, { 0, -5 } }) do
  set(c[1], TOP_FLOOR + 2, c[2], "purple_stained_glass_pane"); set(c[1], TOP_FLOOR + 3, c[2], "purple_stained_glass_pane")
end

-- the spiral stair round a column of bookshelves, all the way up
local RING = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
local GOING = { "east", "east", "south", "south", "west", "west", "north", "north" }
for y = 1, TOP_FLOOR do set(0, y, 0, "bookshelf") end
for i = 0, TOP_FLOOR - 2 do
  local c = RING[i % 8 + 1]
  set(c[1], 2 + i, c[2], "spruce_stairs[facing=" .. GOING[i % 8 + 1] .. "]")
end
-- a rail round the stairwell in the study, with a gap where the stair comes up
local last = TOP_FLOOR - 2
for k, c in ipairs({ { -2, -2 }, { -1, -2 }, { 0, -2 }, { 1, -2 }, { 2, -2 }, { 2, -1 }, { 2, 0 }, { 2, 1 }, { 2, 2 }, { 1, 2 }, { 0, 2 }, { -1, 2 }, { -2, 2 }, { -2, 1 }, { -2, 0 }, { -2, -1 } }) do
  local near = RING[last % 8 + 1]
  if math.abs(c[1] - near[1]) + math.abs(c[2] - near[2]) > 2 then set(c[1], TOP_FLOOR + 1, c[2], "dark_oak_fence") end
end

-- the library floor and the study
for _, c in ipairs({ { -3, -1 }, { -3, 0 }, { -3, 1 }, { 3, -1 }, { 3, 1 }, { -1, 3 }, { 0, 3 }, { 1, 3 } }) do
  set(c[1], MID_FLOOR + 1, c[2], "bookshelf"); set(c[1], MID_FLOOR + 2, c[2], "bookshelf")
end
set(-2, MID_FLOOR + 1, 2, "lectern"); set(2, MID_FLOOR + 1, -2, "lantern")
set(0, TOP_FLOOR + 1, 3, "enchanting_table")
for _, c in ipairs({ { -2, 3 }, { 2, 3 }, { -3, 2 }, { 3, 2 }, { -3, -2 }, { 3, -2 } }) do
  set(c[1], TOP_FLOOR + 1, c[2], "bookshelf"); set(c[1], TOP_FLOOR + 2, c[2], "bookshelf")
end
set(-3, TOP_FLOOR + 1, 0, "brewing_stand"); set(-3, TOP_FLOOR + 1, -1, "cauldron"); set(3, TOP_FLOOR + 1, 0, "lectern")
set(0, TOP_FLOOR + 1, -3, "chest"); set(-2, TOP_FLOOR + 1, -3, "lantern"); set(2, TOP_FLOOR + 1, -3, "lantern")
set(1, 2, -2, "lantern"); set(-2, 2, 1, "lantern")

---------------------------------------------------------------- the hat

-- a wide brim, then rings shrinking towards a tip that bends over to the east
local HAT = TOP_FLOOR + 6
local LAYERS = 16
for k = 0, LAYERS do
  local r = 6.6 - 6.4 * (k / LAYERS) ^ 0.85
  local off = 3.2 * (k / LAYERS) ^ 3
  for z = -7, 7 do
    for x = -7, 11 do
      local d = dist(x - off, z)
      if d <= r and (d > r - 1.4 or k == 0 or k == LAYERS) then
        set(x, HAT + k, z, (k == 1 or k == 2) and "black_concrete" or "purple_concrete")
      end
    end
  end
end
-- the tip: a block on each of the last layers, wherever the bend has got to
for k = LAYERS - 2, LAYERS do set(math.floor(3.2 * (k / LAYERS) ^ 3 + 0.5), HAT + k, 0, "purple_concrete") end
set(3, HAT + LAYERS + 1, 0, "end_rod")

local tower = { name = "Wizard tower", blocks = {} }
for key, block in pairs(grid) do
  local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
  tower.blocks[#tower.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return tower
