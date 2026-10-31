-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Underground atrium for the empty 60x60x30 box 'excavate atrium' digs:
-- three rooms side by side, on two floors. In the middle, a 24-wide atrium
-- open to the ceiling, with a spruce gallery round it at the second floor
-- on log pillars, arches below the gallery and below the ceiling beams,
-- shroomlights, a railing with lanterns, split stairs up to the gallery on
-- both sides, and a moss garden with a pond on the floor. Either side, a
-- 17-wide wing with a full second floor. Stone walls between them have three
-- doorways on each floor.
--
-- Everything is mirror-symmetric both ways: one quarter is drawn and
-- mirrored (stairs' facings too). Coordinates are the box's: x and z 0-59
-- from its north-west corner, y 0 its floor. The top is layer 28, one below
-- the ceiling: the builder stands a block above what it places. Nothing is
-- built above (29, 7), the builder turtle's home, or on (29, 6) and (30, 7),
-- its chests. Built inside the dug box, so "clear" is false. hole is the
-- size 'excavate atrium' digs and home that builder spot: excavate reads
-- both from here, so change them with the plan.
local atrium = { name = "Atrium", clear = false, hole = { 60, 60, 30 }, home = { x = 29, z = 7 }, blocks = {} }
local function put(x, y, z, block) atrium.blocks[#atrium.blocks + 1] = { x, y, z, block } end

local N = 59 -- far side of the box
local MID = 29 -- last block before the middle (the middle falls between 29 and 30)
local WALL = 17 -- the wall between the west wing and the atrium (and 59 - 17)
local GALLERY_W = 4 -- gallery width round the atrium
local EDGE_X = WALL + GALLERY_W -- 21: the gallery's inner edge along the walls
local EDGE_Z = GALLERY_W - 1 -- 3: its inner edge across the ends
local FLOOR2 = 14 -- the second floor's layer (you stand on it at 15)
local TOP = 28 -- the ceiling beams' layer
local STEPS = FLOOR2 + 1 -- steps up to the gallery
local DOOR_H = 4 -- doorway height
local DOORS = { 9, 10, 29 } -- doorway z's in each wall (mirrored: 49, 50, 30)

local LOG = "minecraft:stripped_spruce_log"
local PLANKS = "minecraft:spruce_planks"
local FENCE = "minecraft:spruce_fence"
local STAIRS = "minecraft:spruce_stairs"
local STONE = "minecraft:stone_bricks"
local LIGHT = "minecraft:shroomlight"
local LANTERN = "minecraft:lantern"

-- A block in the north-west quarter, and its mirrors in the other three;
-- facings flip with them.
local FLIP_X = { east = "west", west = "east" }
local FLIP_Z = { north = "south", south = "north" }
local function flip(block, map)
  return (block:gsub("facing=(%a+)", function(f) return "facing=" .. (map[f] or f) end))
end
local function sym(x, y, z, block)
  put(x, y, z, block)
  put(N - x, y, z, flip(block, FLIP_X))
  put(x, y, N - z, flip(block, FLIP_Z))
  put(N - x, y, N - z, flip(flip(block, FLIP_X), FLIP_Z))
end

---------------------------------------------------------------- walls and wings

local isDoor = {}
for _, z in ipairs(DOORS) do isDoor[z] = true end
for z = 0, MID do
  for y = 0, TOP do
    local inDoor = isDoor[z] and (y < DOOR_H or (y > FLOOR2 and y <= FLOOR2 + DOOR_H))
    if not inDoor then sym(WALL, y, z, STONE) end
  end
end

-- each wing: a full second floor, log posts down its middle under it,
-- shroomlights set in it, lanterns standing on them
local WING_MID = 8
local WING_POSTS = { [9] = true, [19] = true, [29] = true }
local WING_LIGHTS = { [4] = true, [24] = true }
for z = 0, MID do
  for x = 0, WALL - 1 do
    sym(x, FLOOR2, z, x == WING_MID and WING_LIGHTS[z] and LIGHT or PLANKS)
  end
  if WING_POSTS[z] then
    for y = 0, FLOOR2 - 1 do sym(WING_MID, y, z, LOG) end
  end
  if WING_LIGHTS[z] then sym(WING_MID, FLOOR2 + 1, z, LANTERN) end
end

---------------------------------------------------------------- atrium: pillars and gallery

-- along the gallery's inner edges, floor to ceiling beams
local PILLARS_Z = { 3, 11, 19, 27 } -- on x = 21 (mirrored: 32, 40, 48, 56)
local PILLARS_X = { 21, 29 } -- on z = 3 (mirrored: 30, 38)
local pillar = {}
local function mark(x, z)
  for _, p in ipairs({ { x, z }, { N - x, z }, { x, N - z }, { N - x, N - z } }) do
    pillar[p[1] .. "," .. p[2]] = true
  end
end
for _, z in ipairs(PILLARS_Z) do mark(EDGE_X, z) end
for _, x in ipairs(PILLARS_X) do mark(x, EDGE_Z) end
local function isPillar(x, z) return pillar[x .. "," .. z] == true end
for z = 0, MID do
  for x = WALL + 1, MID do
    if isPillar(x, z) then
      for y = 0, TOP do sym(x, y, z, LOG) end
    elseif x <= EDGE_X or z <= EDGE_Z then
      sym(x, FLOOR2, z, PLANKS)
    end
  end
end

---------------------------------------------------------------- atrium: stairs

-- Split stairs just inside the gallery on both long sides: a landing on the
-- floor in the middle (z 29-30), flights 2 wide rising to the gallery
-- towards both ends. Step k's block is at layer k - 1; the top one, level
-- with the gallery, is a plank landing.
local STAIR_X = { EDGE_X + 1, EDGE_X + 2 }
local stepAt = {} -- "x,z" -> k, for the railing
for _, x in ipairs(STAIR_X) do
  for k = 1, STEPS do
    local z = MID - k
    stepAt[x .. "," .. z] = k
    sym(x, k - 1, z, k == STEPS and PLANKS or STAIRS .. "[facing=north]")
  end
end
local function stepHeight(x, z) return stepAt[x .. "," .. z] or stepAt[(N - x) .. "," .. z]
  or stepAt[x .. "," .. (N - z)] or stepAt[(N - x) .. "," .. (N - z)] or 0 end

---------------------------------------------------------------- atrium: arches, railing, beams

-- Each inner edge of the gallery, between the pillars: a beam under the
-- gallery and one under the ceiling, a block down beside each pillar (the
-- arch), a shroomlight mid-span, and the railing on the gallery, open where
-- a flight arrives. Drawn whole, edge by edge (it's symmetric already).
local function edge(cells, inward)
  -- runs of cells between pillars, so each span gets its middle
  local runs, run = {}, nil
  for _, c in ipairs(cells) do
    if isPillar(c[1], c[2]) then run = nil
    else
      if not run then run = {}; runs[#runs + 1] = run end
      run[#run + 1] = c
    end
  end
  for _, r in ipairs(runs) do
    local m1, m2 = math.floor((#r + 1) / 2), math.floor(#r / 2) + 1
    for i, c in ipairs(r) do
      local x, z = c[1], c[2]
      local mid = i == m1 or i == m2
      local byPillar = i == 1 or i == #r
      for _, beam in ipairs({ FLOOR2 - 1, TOP }) do
        put(x, beam, z, mid and LIGHT or PLANKS)
        if byPillar then put(x, beam - 1, z, PLANKS) end
      end
      local ix, iz = inward(x, z)
      if stepHeight(ix, iz) < STEPS - 1 then
        put(x, FLOOR2 + 1, z, FENCE)
        if mid then put(x, FLOOR2 + 2, z, LANTERN) end
      end
    end
  end
end
for _, x in ipairs({ EDGE_X, N - EDGE_X }) do
  local cells = {}
  for z = EDGE_Z, N - EDGE_Z do cells[#cells + 1] = { x, z } end
  edge(cells, function(cx, cz) return cx == EDGE_X and cx + 1 or cx - 1, cz end)
end
for _, z in ipairs({ EDGE_Z, N - EDGE_Z }) do
  local cells = {}
  for x = EDGE_X, N - EDGE_X do cells[#cells + 1] = { x, z } end
  edge(cells, function(cx, cz) return cx, cz == EDGE_Z and cz + 1 or cz - 1 end)
end

-- ceiling beams across the atrium from pillar to pillar, lit in the middle
for _, z in ipairs(PILLARS_Z) do
  if z > EDGE_Z then
    for x = EDGE_X + 1, MID do sym(x, TOP, z, (x == MID) and LIGHT or PLANKS) end
  end
end

---------------------------------------------------------------- atrium: garden

-- On the floor in the middle, between the flights: moss with plants, round a
-- pond 2 wide whose edges grow sugar cane. u and v count in from the
-- garden's corner, so the planting is symmetric too.
local G_X0, G_Z0 = 26, 19 -- garden's north-west corner (to 33, 40)
local POND_Z0 = 26 -- pond: x 29-30, z 26-33
for z = G_Z0, MID do
  for x = G_X0, MID do
    local u, v = x - G_X0, z - G_Z0
    if x == MID and z >= POND_Z0 then
      sym(x, 0, z, "minecraft:water")
    else
      sym(x, 0, z, "minecraft:moss_block")
      local plant
      if (x == MID - 1 and z >= POND_Z0) or (x == MID and z == POND_Z0 - 1) then
        plant = "minecraft:sugar_cane"
      elseif u == 0 or v == 0 then
        plant = (u + v) % 2 == 0 and "minecraft:flowering_azalea" or "minecraft:azalea"
      elseif u == 1 and v % 4 == 2 then
        plant = "minecraft:bamboo"
      elseif (u + v) % 3 == 0 then
        plant = "minecraft:poppy"
      elseif (u + v) % 3 == 1 then
        plant = "minecraft:cornflower"
      end
      if plant then sym(x, 1, z, plant) end
    end
  end
end
-- lanterns on the floor at the garden's corners
sym(G_X0 - 1, 0, G_Z0 - 1, LANTERN)

return atrium
