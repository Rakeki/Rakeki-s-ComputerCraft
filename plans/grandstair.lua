-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Grand Stair: an entrance hall for the 31x46x22 hole 'excavate grandstair'
-- digs. You come in high up, through an arch in the north wall, onto a
-- landing; a stone staircase 11 wide runs down from it in two flights, with
-- a half landing between, to the hall floor, which ends at an aquarium
-- window in the south wall: a tank of water, coral and sea lanterns behind
-- glass. Tall stone brick pillars with chiselled capitals line both sides
-- and carry balconies along the walls, level with the landing, with a
-- stone railing and lanterns; dark oak beams cross under a timber ceiling
-- set with glowstone. Under the landing, a vaulted storeroom.
--
-- Mirror-symmetric east-west: the west half is drawn and mirrored (facings
-- too). Coordinates are the hole's: x and z from its north-west corner, y 0
-- its floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 31, 46, 22
local TOP = H - 2
local HOME = { x = 15, z = 30 }
local grand = { name = "Grand Stair", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local N = W - 1 -- the east side (x mirrors to N - x)
local C = 15 -- the middle (x)
local UPPER = 12 -- the landing's and balconies' floor (you stand on it at 13)
local LANDING_Z = 8 -- the landing runs from the north wall to here
local STAIR_X = 10 -- the stair runs x 10-20
local HALF = 6 -- the half landing's layer
local PILLAR_X = 6 -- pillars stand on x 6 (and 24), the balconies' edge
local PILLARS_Z = { 4, 9, 15, 21, 27, 33, 39 }
local TANK_Z = 42 -- the aquarium's glass; water behind it up to the south wall
local TANK_X = 10 -- the tank runs x 10-20
local TANK_TOP = 6 -- its water's top layer

local STONE = "minecraft:stone_bricks"
local CHISELED = "minecraft:chiseled_stone_bricks"
local POLISHED = "minecraft:polished_andesite"
local OAK = "minecraft:dark_oak_planks"
local BEAM = "minecraft:stripped_dark_oak_wood"
local GLOW = "minecraft:glowstone"

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
local function get(x, y, z) return grid[x .. "," .. y .. "," .. z] end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
-- a block on the west side and its mirror on the east, facings flipped
local FLIP = { east = "west", west = "east" }
local function sym(x, y, z, block)
  set(x, y, z, block)
  set(N - x, y, z, block and (block:gsub("facing=(%a+)", function(f) return "facing=" .. (FLIP[f] or f) end)))
end
local function stone(x, y, z)
  local n = noise(x, y, z)
  return n < 0.1 and "minecraft:cracked_stone_bricks" or n < 0.18 and "minecraft:mossy_stone_bricks" or STONE
end
local isPillarZ = {}
for _, z in ipairs(PILLARS_Z) do isPillarZ[z] = true end

---------------------------------------------------------------- shell, floors and ceiling

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      if x == 0 or z == 0 or x == N or z == L - 1 then
        set(x, y, z, (y == 0 or y == UPPER) and POLISHED or (y == UPPER + 1 or y == 1) and CHISELED or stone(x, y, z))
      end
    end
  end
end
for z = 1, L - 2 do
  for x = 1, C do
    -- the hall floor: polished andesite, a stone brick border and runner
    local edge = x == 1 or z == 1 or x == STAIR_X or x == PILLAR_X
    sym(x, 0, z, (edge or x == C) and STONE or POLISHED)
    -- the ceiling, glowstone down the middle and over the balconies
    local lit = (x == C or x == 3) and (z % 6 == 0) and z > 2
    sym(x, TOP, z, lit and GLOW or OAK)
    -- the landing and the balconies
    if z <= LANDING_Z or x <= PILLAR_X then
      local glow = x == 3 and z % 6 == 0 and z > LANDING_Z
      sym(x, UPPER, z, glow and GLOW or (x == PILLAR_X or z == LANDING_Z) and STONE or OAK)
    end
  end
end

---------------------------------------------------------------- pillars, beams, railing

for _, z in ipairs(PILLARS_Z) do
  for y = 1, TOP - 1 do
    local block = STONE
    if y == 1 or y == UPPER - 1 or y == TOP - 1 then block = CHISELED end
    if y == UPPER then block = POLISHED end
    sym(PILLAR_X, y, z, block)
  end
  -- corbels either side under the balcony edge and the beams
  for _, dz in ipairs({ -1, 1 }) do
    if z + dz > LANDING_Z then
      sym(PILLAR_X, UPPER - 2, z + dz, STONE)
      sym(PILLAR_X, TOP - 2, z + dz, BEAM)
    end
  end
  -- a dark oak beam across under the ceiling
  for x = PILLAR_X + 1, C do sym(x, TOP - 1, z, BEAM) end
end
-- the beam along each balcony's edge under its floor
for z = LANDING_Z + 1, TANK_Z - 1 do
  if not isPillarZ[z] then sym(PILLAR_X, UPPER - 1, z, STONE) end
end
-- the railing: along the balconies and the landing's edge, open onto the stair
local function rail(x, z)
  if get(x, UPPER + 1, z) == nil then
    sym(x, UPPER + 1, z, "minecraft:stone_brick_wall")
    if (x == PILLAR_X and z % 6 == 0) or (z == LANDING_Z and (x == PILLAR_X + 1 or x == STAIR_X - 1)) then
      sym(x, UPPER + 2, z, "minecraft:lantern")
    end
  end
end
for z = LANDING_Z, TANK_Z - 1 do rail(PILLAR_X, z) end
for x = PILLAR_X, STAIR_X - 1 do rail(x, LANDING_Z) end
-- a wall across the balconies' south ends
for x = 1, PILLAR_X do sym(x, UPPER + 1, TANK_Z - 1, "minecraft:stone_brick_wall") end

---------------------------------------------------------------- the stair

-- From the landing down to the hall: five steps, a half landing three
-- deep, five steps; solid under them, polished sides.
local steps = {} -- z -> the step's layer, or the half landing's
for i = 1, 5 do steps[LANDING_Z + i] = UPPER - i end -- 11 .. 7
for i = 1, 3 do steps[LANDING_Z + 5 + i] = HALF end
for i = 1, 5 do steps[LANDING_Z + 8 + i] = HALF - i end -- 5 .. 1
for z, top in pairs(steps) do
  local flat = top == HALF
  for x = STAIR_X, C do
    local block = flat and POLISHED or "minecraft:stone_brick_stairs[facing=north]"
    if x == STAIR_X then block = flat and CHISELED or "minecraft:polished_andesite_stairs[facing=north]" end
    sym(x, top, z, block)
    for y = 1, top - 1 do sym(x, y, z, x == STAIR_X and POLISHED or "minecraft:cobblestone") end
  end
end
-- lantern posts at the half landing's corners and the foot of the stair
for _, z in ipairs({ LANDING_Z + 6, LANDING_Z + 8 }) do
  sym(STAIR_X, HALF + 1, z, "minecraft:stone_brick_wall")
  sym(STAIR_X, HALF + 2, z, "minecraft:lantern")
end
local FOOT = LANDING_Z + 14
sym(STAIR_X - 1, 1, FOOT, "minecraft:stone_brick_wall")
sym(STAIR_X - 1, 2, FOOT, "minecraft:stone_brick_wall")
sym(STAIR_X - 1, 3, FOOT, "minecraft:lantern")

---------------------------------------------------------------- the storeroom under the landing

for x = 1, STAIR_X - 2 do
  for y = 1, 3 do sym(x, y, 1, (y == 2 and x % 3 == 0) and "minecraft:chest[facing=south]" or "minecraft:barrel") end
end
for z = 2, LANDING_Z - 1 do
  for y = 1, 2 do sym(1, y, z, "minecraft:barrel") end
end
sym(3, 4, 1, "minecraft:lantern")
sym(PILLAR_X, 1, 1, nil)
-- a vault over it: arches from the pillars to the stair
for x = PILLAR_X + 1, STAIR_X - 1 do sym(x, UPPER - 1, 4, STONE) end
for z = 1, LANDING_Z do sym(STAIR_X - 1, UPPER - 1, z, STONE) end
sym(STAIR_X - 1, UPPER - 2, 4, STONE)
for x = 1, PILLAR_X - 1 do sym(x, UPPER - 1, 4, STONE) end
-- the stair's back wall, under the landing's middle
for x = STAIR_X, C do
  for y = 1, UPPER - 1 do sym(x, y, LANDING_Z, y <= 3 and (x == C and nil or POLISHED) or STONE) end
end
sym(C, 3, LANDING_Z, CHISELED)

---------------------------------------------------------------- the aquarium

-- glass from the floor up, a frame round it, the tank behind: water, coral
-- on a sand floor, sea lanterns in the corners
for y = 1, TANK_TOP + 1 do
  for x = TANK_X - 1, C do
    local frame = x == TANK_X - 1 or y == TANK_TOP + 1
    sym(x, y, TANK_Z, frame and CHISELED or "minecraft:glass")
    for z = TANK_Z + 1, L - 2 do
      if frame then sym(x, y, z, "minecraft:dark_prismarine")
      else sym(x, y, z, "minecraft:water") end
    end
  end
end
for z = TANK_Z + 1, L - 2 do
  for x = TANK_X, C do
    local corner = x == TANK_X and z == L - 2
    sym(x, 0, z, corner and "minecraft:sea_lantern" or "minecraft:sand")
  end
end
local CORAL = { "minecraft:tube_coral_block", "minecraft:brain_coral_block", "minecraft:fire_coral_block",
  "minecraft:horn_coral_block", "minecraft:bubble_coral_block" }
-- coral on the tank floor: x, y, z and which coral
for _, c in ipairs({ { 11, 1, 44, 1 }, { 11, 2, 44, 2 }, { 12, 1, 44, 3 }, { 13, 1, 43, 4 }, { 14, 1, 44, 5 } }) do
  sym(c[1], c[2], c[3], CORAL[c[4]])
end
set(C, 1, L - 2, "minecraft:sea_lantern")
-- the arch beside the window, and benches facing it
for x = PILLAR_X + 1, TANK_X - 2 do
  for y = 1, TANK_TOP + 1 do sym(x, y, TANK_Z, y == TANK_TOP + 1 and CHISELED or STONE) end
end
for x = C - 3, C do sym(x, 1, TANK_Z - 5, "minecraft:dark_oak_stairs[facing=north]") end

---------------------------------------------------------------- the way in

-- an arch in the north wall at the landing, opening on the rock: dig your
-- way in from the surface there
for x = C - 1, C + 1 do
  for y = UPPER + 1, UPPER + 3 do set(x, y, 0, nil) end
  set(x, UPPER + 4, 0, CHISELED)
end
sym(C - 2, UPPER + 1, 1, "minecraft:stone_brick_wall")
sym(C - 2, UPPER + 2, 1, "minecraft:lantern")

---------------------------------------------------------------- out

-- the builder's home column, and the floor under its two chests, stay empty
for y = 0, TOP do set(HOME.x, y, HOME.z, nil) end
set(HOME.x, 0, HOME.z - 1, nil)
set(HOME.x + 1, 0, HOME.z, nil)

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = grid[x .. "," .. y .. "," .. z]
      if block then grand.blocks[#grand.blocks + 1] = { x, y, z, block } end
    end
  end
end
return grand
