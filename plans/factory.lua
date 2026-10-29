-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Turtle Works: a brick factory hall, 57 wide and 45 deep inside its walls,
-- built for a ComputerCraft base. Every machine spot sits on a port (a full
-- wired modem set in the floor) over a cable trench under the floor, so the
-- whole hall is one wired network back to the control room:
--   north wall: 12 turtle docks (a turtle-sized hole, the turtle's home
--     block, a supply barrel behind it and a spoil barrel to its left),
--     the main doors, and the storage system's input and fuel barrels
--   middle:     four storage racks of barrels, 3 high, round a column of
--     full modems each; the main cable runs under a glass strip down the
--     middle aisle
--   west:       two lines of furnaces under a brick hood, chimneys outside
--   east:       four crafting cells (a barrel and a turtle spot each), a bay
--     of spare ports for machines, and a gallery round the walls
--   south:      a glass control room up on a mezzanine, with ports for its
--     computers and a monitor wall
--   roof:       sawtooth, glazed to the north, with two sky docks: holes for
--     turtles that cruise high to drop straight down to a landing pad
-- Coordinates: x west to east, z north to south (the apron and docks face
-- north), y = 0 is the cable trench under the floor (y = 1). Put the corner
-- one block below the ground so the floor is level with it.
local factory = { name = "Turtle Works", blocks = {} }

local X1 = 56 -- the east wall (the west wall is x = 0)
local Z0, Z1 = 4, 48 -- the north and south walls; the apron is z 0..3
local TOP = 13 -- the top of the walls
local BAND = 9 -- depth of each tooth of the sawtooth roof
local DOCKS = { 3, 5, 11, 13, 19, 21, 35, 37, 43, 45, 51, 53 } -- x of each turtle dock
local RACKS = { 17, 23, 33, 39 } -- x of each storage rack's modem column
local RACK_Z0, RACK_Z1 = 12, 25
local FURNACES = { 4, 8 } -- x of each furnace line
local CELLS = { 14, 19, 24, 29 } -- z of each crafting cell
local SKY_DOCKS = { { 14, 34 }, { 42, 34 } }
local BEAMS = { 13, 22, 31, 40 } -- z of the roof trusses (the glazing above them)

local M = {
  trench = "minecraft:cobblestone",
  footing = "minecraft:stone_bricks",
  floor = "minecraft:polished_andesite",
  grid = "minecraft:smooth_stone",
  light = "minecraft:sea_lantern",
  base = "minecraft:stone_bricks",
  wall = "minecraft:bricks",
  frame = "minecraft:polished_deepslate",
  roof = "minecraft:deepslate_tiles",
  glass = "minecraft:glass",
  pane = "minecraft:glass_pane",
  bars = "minecraft:iron_bars",
  apron = "minecraft:gray_concrete",
  hazard = { "minecraft:yellow_concrete", "minecraft:black_concrete" },
  home = "minecraft:lime_concrete", -- a turtle's home block
  input = "minecraft:blue_concrete",
  fuel = "minecraft:orange_concrete",
  delivery = "minecraft:cyan_concrete",
  catwalk = "minecraft:waxed_cut_copper",
  slab = "minecraft:smooth_stone_slab",
  cable = "computercraft:cable",
  port = "computercraft:wired_modem_full",
  computer = "computercraft:computer_advanced",
  drive = "computercraft:disk_drive",
  barrel = "minecraft:barrel",
  furnace = "minecraft:furnace",
}

-- Everything goes into a grid first, so later parts can replace or cut out
-- what earlier ones put there (doors through walls, ports in the floor).
local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block and { x, y, z, block } or false end
local function box(x0, y0, z0, x1, y1, z1, block)
  for y = y0, y1 do
    for z = z0, z1 do
      for x = x0, x1 do set(x, y, z, block) end
    end
  end
end
local function hazard(x, y, z) set(x, y, z, M.hazard[(x + y + z) % 2 + 1]) end

-- The roof's height at z: each tooth is highest at its north edge (where
-- its glazing is) and steps down to the south.
local function roofAt(z) return TOP + 5 - math.floor(((z - Z0) % BAND) / 2) end

---------------------------------------------------------------- ground

-- the trench layer and the footing round the hall, so clearing the box
-- leaves no holes outside the walls
box(-3, 0, 0, X1 + 1, 0, Z1 + 1, M.trench)
box(-3, 1, 0, X1 + 1, 1, Z1 + 1, M.footing)
box(0, 1, 0, X1, 1, Z0 - 1, M.apron)
for x = 0, X1 do hazard(x, 1, 0) end
box(26, 1, 0, 30, 1, Z0 - 1, M.base)

-- the floor: a grid of smooth stone every 8 blocks, lights between
for z = Z0 + 1, Z1 - 1 do
  for x = 1, X1 - 1 do
    local line = x % 8 == 0 or (z - Z0) % 8 == 0
    set(x, 1, z, line and M.grid or M.floor)
    if x % 8 == 4 and (z - Z0) % 8 == 4 then set(x, 1, z, M.light) end
  end
end

---------------------------------------------------------------- walls

local function wallBlock(y)
  if y <= 3 then return M.base end
  if y == TOP then return M.frame end
  return M.wall
end

for y = 2, TOP do
  for x = 0, X1 do
    set(x, y, Z0, wallBlock(y))
    set(x, y, Z1, wallBlock(y))
  end
  for z = Z0, Z1 do
    set(0, y, z, wallBlock(y))
    set(X1, y, z, wallBlock(y))
  end
end

-- pilasters, standing out a block: every 8 along the long walls, at each
-- truss on the side walls
local SIDE_PILLARS = { Z0, 13, 22, 31, 40, Z1 }
for y = 2, TOP do
  for x = 0, X1, 8 do
    set(x, y, Z0, M.frame)
    set(x, y, Z1, M.frame)
    if y < TOP then
      set(x, y, Z0 - 1, M.frame)
      set(x, y, Z1 + 1, M.frame)
    end
  end
  for _, z in ipairs(SIDE_PILLARS) do
    set(0, y, z, M.frame)
    set(X1, y, z, M.frame)
    if y < TOP then
      set(-1, y, z, M.frame)
      set(X1 + 1, y, z, M.frame)
    end
  end
end

-- tall windows in each bay, two panes high, a transom, two more
local function window(put)
  for _, y in ipairs({ 6, 7, 9, 10 }) do put(y, M.pane) end
  put(8, M.frame)
end
for x0 = 0, X1 - 8, 8 do
  for x = x0 + 2, x0 + 6 do
    if x0 ~= 24 then window(function(y, b) set(x, y, Z0, b) end) end -- not over the doors
    if x0 < 16 or x0 > 32 then window(function(y, b) set(x, y, Z1, b) end) end -- not behind the control room
  end
end
for i = 1, #SIDE_PILLARS - 1 do
  local z0 = SIDE_PILLARS[i]
  for z = z0 + 2, math.min(z0 + 6, SIDE_PILLARS[i + 1] - 2) do
    if z0 ~= 13 and z0 ~= 22 then window(function(y, b) set(0, y, z, b) end) end -- chimneys there
    window(function(y, b) set(X1, y, z, b) end)
  end
end

---------------------------------------------------------------- roof

for z = Z0, Z1 do
  local h = roofAt(z)
  for x = -1, X1 + 1 do
    local lamp = x % 8 == 4 and (z - Z0) % BAND == 4
    set(x, h, z, lamp and M.light or M.roof)
  end
  -- the side walls follow the teeth up
  for y = TOP + 1, h - 1 do
    set(0, y, z, M.wall)
    set(X1, y, z, M.wall)
  end
  -- glazing along the north edge of each tooth
  if (z - Z0) % BAND == 0 then
    for y = TOP + 1, h - 1 do
      for x = 1, X1 - 1 do set(x, y, z, M.glass) end
    end
  end
end

-- trusses under the glazing, on two rows of columns
for _, z in ipairs(BEAMS) do
  for x = 1, X1 - 1 do set(x, TOP, z, M.frame) end
  for y = 2, TOP - 1 do
    set(13, y, z, M.frame)
    set(43, y, z, M.frame)
  end
end

---------------------------------------------------------------- the cable network

-- Runs of cable in the trench (y = 0); a port is a full wired modem in the
-- floor above one, and whatever stands on it joins the network. Right-click
-- a port (and each rack modem) once to connect what's next to it.
local function run(x0, z0, x1, z1)
  for z = math.min(z0, z1), math.max(z0, z1) do
    for x = math.min(x0, x1), math.max(x0, x1) do set(x, 0, z, M.cable) end
  end
end
local function port(x, z, block)
  set(x, 0, z, M.cable)
  set(x, 1, z, M.port)
  if block then set(x, 2, z, block) end
end

run(2, 6, 54, 6) -- along the docks
run(28, 6, 28, 47) -- down the middle, under the glass strip
run(RACKS[1], RACK_Z0, RACKS[#RACKS], RACK_Z0) -- across the rack ends
run(FURNACES[1], 31, 50, 31) -- across the south of the furnaces and cells
run(21, 44, 35, 44) -- under the control room
for z = Z0 + 3, Z1 - 1 do set(28, 1, z, M.glass) end

---------------------------------------------------------------- north: docks and doors

for _, d in ipairs(DOCKS) do
  set(d, 2, Z0, false) -- the hole the turtle goes in and out by
  set(d, 3, Z0, M.hazard[1])
  set(d, 4, Z0 - 1, M.light)
  for z = 0, Z0 - 1 do set(d, 1, z, M.home) end -- its lane across the apron
  set(d, 1, Z0 + 1, M.home) -- its home block, facing out
  port(d, Z0 + 2, M.barrel) -- supply barrel behind it
  run(d - 1, Z0 + 1, d - 1, Z0 + 2)
  port(d - 1, Z0 + 1, M.barrel) -- spoil barrel to its left
end
for x = 1, X1 - 1 do
  if x < 25 or x > 31 then hazard(x, 1, Z0 + 4) end
end

-- the main doors, 5 wide and 5 high, framed in stripes, a sign panel above
box(26, 2, Z0, 30, 6, Z0, false)
for y = 2, 7 do
  hazard(25, y, Z0)
  hazard(31, y, Z0)
end
for x = 25, 31 do hazard(x, 7, Z0) end
box(25, 9, Z0, 31, 11, Z0, M.hazard[2])

-- the storage system's chests by the doors, a colour on the floor in front
for x, mark in pairs({ [23] = M.delivery, [24] = M.input, [32] = M.fuel, [33] = M.input }) do
  port(x, 6, M.barrel)
  set(x, 1, 7, mark)
end

---------------------------------------------------------------- middle: storage racks

for _, s in ipairs(RACKS) do
  for z = RACK_Z0, RACK_Z1 do
    set(s, 1, z, M.cable)
    for y = 2, 4 do
      set(s, y, z, M.port)
      set(s - 1, y, z, M.barrel)
      set(s + 1, y, z, M.barrel)
    end
    for x = s - 1, s + 1 do set(x, 5, z, M.slab) end
  end
  for _, z in ipairs({ RACK_Z0 - 1, RACK_Z1 + 1 }) do
    for y = 2, 4 do set(s, y, z, M.frame) end
    set(s, 5, z, M.light)
  end
end

---------------------------------------------------------------- west: furnaces

for _, fx in ipairs(FURNACES) do
  run(fx, 14, fx, 31)
  for z = 14, 29 do port(fx, z, M.furnace) end
end
-- the hood over both lines, lit underneath, with ducts to the chimneys
box(3, 4, 13, 9, 4, 30, M.wall)
for z = 15, 29, 4 do set(6, 4, z, M.light) end
box(1, 4, 16, 2, 5, 18, M.wall)
box(1, 4, 25, 2, 5, 27, M.wall)
for _, cz in ipairs({ 17, 26 }) do
  box(-3, 2, cz - 1, -1, 21, cz + 1, M.wall)
  box(-3, 22, cz - 1, -1, 22, cz + 1, M.frame)
  set(-2, 22, cz, "minecraft:campfire") -- smoke
end
port(10, 31, M.computer) -- the smelter computer
port(11, 31, M.barrel) -- its work chest

---------------------------------------------------------------- east: crafting cells, machine bay

run(50, 14, 50, 44)
for _, cz in ipairs(CELLS) do
  port(50, cz, M.barrel) -- the crafter chest
  set(51, 1, cz, M.home) -- the crafting turtle, facing it
  set(54, 2, cz, "minecraft:crafting_table")
end
for z = 12, 32, 5 do
  for x = 47, X1 - 1 do
    for y = 2, 3 do set(x, y, z, M.bars) end
  end
end
port(46, 31, M.computer) -- the craft overseer

-- spare ports for machines, inside a striped line
for _, z in ipairs({ 36, 40, 44 }) do
  run(45, z, 54, z)
  for _, x in ipairs({ 46, 49, 52 }) do port(x, z) end
end
for x = 44, X1 - 1 do hazard(x, 1, 34) end
for z = 34, 45 do hazard(44, 1, z) end

---------------------------------------------------------------- south: control room

-- up on posts, floor at y = 7 over a layer holding its cables
box(20, 6, 39, 36, 6, 47, M.grid)
box(20, 7, 39, 36, 7, 47, M.floor)
for _, x in ipairs({ 20, 24, 32, 36 }) do
  for y = 2, 5 do set(x, y, 39, M.frame) end
end
for y = 8, 11 do
  for x = 20, 36 do set(x, y, 39, (x % 4 == 0) and M.frame or M.glass) end
  for z = 40, 47 do
    set(20, y, z, M.glass)
    set(36, y, z, M.glass)
  end
end
box(20, 12, 39, 36, 12, 47, M.grid)
for x = 24, 32, 4 do set(x, 12, 43, M.light) end
-- doors to the stairs (west) and the gallery (east)
box(20, 8, 46, 20, 9, 47, false)
box(36, 8, 46, 36, 9, 47, false)

-- its cables: up the south wall from the main run, then along under the
-- desk and the monitor wall
for y = 1, 6 do set(28, y, 47, M.cable) end
for x = 22, 34 do
  set(x, 6, 41, M.cable)
  set(x, 6, 47, M.cable)
  set(x, 7, 47, M.port) -- monitors stand on these
end
for z = 41, 47 do set(28, 6, z, M.cable) end
local DESK = { [22] = M.drive, [23] = M.computer, [26] = M.computer, [30] = M.computer, [33] = M.computer }
for x, block in pairs(DESK) do
  set(x, 7, 41, M.port)
  set(x, 8, 41, block)
end
-- the monitor wall: a black panel on the south wall behind the monitors
box(21, 8, Z1, 35, 11, Z1, M.hazard[2])

-- ports under it for power or anything else
for _, x in ipairs({ 22, 25, 31, 34 }) do port(x, 44) end

-- stairs up to it along the south wall, half a block a step
for i = 0, 11 do
  local x, full = 7 + i, math.floor((i + 1) / 2)
  for z = Z1 - 2, Z1 - 1 do
    if full >= 1 then box(x, 2, z, x, 1 + full, z, M.base) end
    if i % 2 == 0 then set(x, 2 + full, z, M.slab) end
  end
end
box(19, 2, Z1 - 2, 19, 7, Z1 - 1, M.base)

-- the gallery: along the south wall from the control room, then up the
-- east wall over the cells, railed
for x = 37, X1 - 1 do
  for z = Z1 - 2, Z1 - 1 do set(x, 7, z, M.catwalk) end
  if x <= X1 - 3 then set(x, 8, Z1 - 3, M.bars) end
end
for z = Z0 + 1, Z1 - 3 do
  for x = X1 - 2, X1 - 1 do set(x, 7, z, (z % 8 == 0) and M.light or M.catwalk) end
  set(X1 - 3, 8, z, M.bars)
end

---------------------------------------------------------------- roof: sky docks

for _, s in ipairs(SKY_DOCKS) do
  local x, z = s[1], s[2]
  for dz = -1, 1 do
    for dx = -1, 1 do
      set(x + dx, roofAt(z + dz), z + dz, M.hazard[1])
      hazard(x + dx, 1, z + dz)
    end
  end
  set(x, roofAt(z), z, false) -- the hole
  set(x, 1, z, M.home) -- the landing pad
end

---------------------------------------------------------------- out

for _, b in pairs(grid) do
  if b then factory.blocks[#factory.blocks + 1] = b end
end
grid = nil
return factory
