-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Pokemon Paradise: a five-storey tower that fills exactly one chunk
-- (16x16), every floor a set of closed habitats to put Cobblemon pastures
-- in. A Create elevator in the north-west corner runs the whole height
-- (a 3x3 shaft, the pulley at the top, the cabin parked under it, an
-- elevator contact and a door on every floor; you glue the cabin and
-- power the pulley), opening onto a landing on each floor; birch doors lead
-- from the landing into each habitat, so pastured Pokemon can't wander
-- out. Chiseled stone brick tiles in the ground mark the pasture spots,
-- with room above each for the pasture block.
--
--   ground  Trainer lobby (a porch, a healing counter and a PC, seats, a
--           rug) and a Sunny Meadow with a cherry tree, flowers and a pond
--   1st     Coral Lagoon: a sandy beach round a pool with a palm island,
--           a pier and a sunshade, and a three-deep glass fish tank
--   2nd     Whispering Grove (birch and oak, moss, mushrooms, a spring)
--           and Crystal Grotto (rough rock, stalagmites, amethyst, a pool)
--   3rd     a hall to Ember Hollow (basalt, walled-in magma pits, crimson
--           roots), Frost Cavern (snow, ice spikes, a snowy spruce) and
--           Sunset Dunes (sand hills, sandstone ruins, a terracotta mesa)
--   top     Sky Garden aviary under a glass dome: a great dark oak tree,
--           two floating islands to perch on, perches and a pond
--
-- Habitats have raised ground (one block of soil on the floor), so sand
-- and gravel have something under them and ponds sit in the soil. The
-- lobby has a Cobblemon healing machine and PC: 'cobblemon=false' after
-- the plan's name leaves them out (projector paradise cobblemon=false).
-- y 0 is the ground; x runs east, z south; the porch and front doors are
-- on the south side.
local opts = ... or {}
local COBBLEMON = not (opts.cobblemon == "false" or opts.cobblemon == "no" or opts.cobblemon == "off")

local SIZE = 16 -- one chunk
local STOREY = 8 -- floor to floor; the spiral climbs one turn (8 steps) a storey
local FLOORS = 5
local ROOF = STOREY * FLOORS -- the roof layer, 40
local DOME_R, DOME_H = 6.5, 7 -- the glass dome over the top floor: radius, height
local PAD = "chiseled_stone_bricks" -- marks a pasture spot
local WALL = "white_concrete"
local BAND = "red_concrete" -- the band round the outside at each floor
local HABITAT_DOOR = "birch_door"

local grid = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function set(x, y, z, block)
  grid[key(x, y, z)] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
local function get(x, y, z) return grid[key(x, y, z)] end
local function fill(x0, y0, z0, x1, y1, z1, block)
  for y = y0, y1 do for z = z0, z1 do for x = x0, x1 do set(x, y, z, block) end end end
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126 + 7) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function pick(list, n) return list[math.floor(n * #list) + 1] end

---------------------------------------------------------------- rooms

-- Each floor's rooms: rects { x0, z0, x1, z1 } of the space inside them.
-- A habitat has raised soil; glass is its window glass (nil: no windows),
-- light the block set in its walls.
local floors = {
  [0] = {
    lobby = { rects = { { 1, 5, 8, 12 } }, glass = "glass" },
    meadow = { rects = { { 5, 1, 14, 3 }, { 10, 4, 14, 14 } }, habitat = true, glass = "glass", light = "shroomlight", soil = { "grass_block" } },
  },
  [1] = {
    landing = { rects = { { 1, 5, 3, 7 } }, glass = "glass" },
    lagoon = { rects = { { 5, 1, 14, 8 }, { 1, 9, 14, 14 } }, habitat = true, glass = "glass", light = "sea_lantern", soil = { "sand" } },
  },
  [2] = {
    landing = { rects = { { 1, 5, 3, 7 } }, glass = "glass" },
    grove = { rects = { { 5, 1, 14, 7 } }, habitat = true, glass = "glass", light = "shroomlight",
      soil = { "grass_block", "grass_block", "grass_block", "moss_block", "moss_block", "podzol", "rooted_dirt" } },
    grotto = { rects = { { 1, 9, 14, 14 } }, habitat = true, light = "glowstone",
      soil = { "stone", "stone", "andesite", "tuff", "gravel", "cobblestone", "mossy_cobblestone" } },
  },
  [3] = {
    landing = { rects = { { 1, 5, 3, 7 }, { 1, 8, 14, 8 } }, glass = "glass" },
    ember = { rects = { { 5, 1, 14, 6 } }, habitat = true, glass = "orange_stained_glass", light = "ochre_froglight",
      soil = { "blackstone", "blackstone", "basalt", "smooth_basalt", "polished_blackstone", "crimson_nylium" } },
    frost = { rects = { { 1, 10, 7, 14 } }, habitat = true, glass = "light_blue_stained_glass", light = "sea_lantern",
      soil = { "snow_block", "snow_block", "snow_block", "packed_ice", "blue_ice" } },
    dunes = { rects = { { 9, 10, 14, 14 } }, habitat = true, glass = "yellow_stained_glass", light = "glowstone", soil = { "sand" } },
  },
  [4] = {
    landing = { rects = { { 1, 5, 3, 7 } }, glass = "glass" },
    aviary = { rects = { { 5, 1, 14, 8 }, { 1, 9, 14, 14 } }, habitat = true, glass = "glass", light = "sea_lantern",
      soil = { "grass_block", "grass_block", "grass_block", "moss_block" } },
  },
}

local function inRoom(room, x, z)
  for _, r in ipairs(room.rects) do
    if x >= r[1] and x <= r[3] and z >= r[2] and z <= r[4] then return true end
  end
  return false
end
local function roomAt(f, x, z)
  for _, room in pairs(floors[f]) do if inRoom(room, x, z) then return room end end
end
local function eachCell(room, fn)
  for _, r in ipairs(room.rects) do
    for z = r[2], r[4] do for x = r[1], r[3] do fn(x, z) end end
  end
end

---------------------------------------------------------------- the outside walls

-- Windows along each side: three runs between piers.
local WINDOW = { [2] = true, [3] = true, [4] = true, [6] = true, [7] = true, [8] = true, [9] = true, [11] = true, [12] = true, [13] = true }
local function edge(v) return v == 0 or v == SIZE - 1 end
local function clampIn(v) return math.max(1, math.min(SIZE - 2, v)) end

for y = 0, ROOF do
  local f, k = math.floor(y / STOREY), y % STOREY
  for z = 0, SIZE - 1 do
    for x = 0, SIZE - 1 do
      if edge(x) or edge(z) then
        local p = edge(x) and z or x
        local block = WALL
        if edge(x) and edge(z) then block = "quartz_pillar"
        elseif y == 0 then block = "stone_bricks"
        elseif k == 0 then block = BAND
        elseif k >= 2 and k <= 5 and WINDOW[p] and f < FLOORS then
          local room = roomAt(f, clampIn(x), clampIn(z))
          if room and room.glass then block = room.glass
          elseif room then -- no windows: rough rock (the grotto)
            block = pick({ "stone", "tuff", "andesite", "cobblestone" }, noise(x, y, z))
          end
        end
        set(x, y, z, block)
      end
    end
  end
end
-- the grotto's outside walls are rock all the way up
for y = 2 * STOREY + 1, 3 * STOREY - 1 do
  for z = 9, 15 do
    for _, x in ipairs({ 0, 15 }) do set(x, y, z, pick({ "stone", "tuff", "andesite", "cobblestone", "deepslate" }, noise(x, y, z))) end
  end
  for x = 1, 14 do set(x, y, 15, pick({ "stone", "tuff", "andesite", "cobblestone", "deepslate" }, noise(x, y, 15))) end
end
-- a parapet round the roof, lanterns on the corners
for i = 0, SIZE - 1 do
  for _, c in ipairs({ { i, 0 }, { i, SIZE - 1 }, { 0, i }, { SIZE - 1, i } }) do
    set(c[1], ROOF + 1, c[2], (edge(c[1]) and edge(c[2])) and "quartz_pillar" or "smooth_quartz_slab")
  end
end
for _, c in ipairs({ { 0, 0 }, { 0, 15 }, { 15, 0 }, { 15, 15 } }) do set(c[1], ROOF + 2, c[2], "lantern") end

---------------------------------------------------------------- floors, walls and the elevator

-- A Create elevator in the north-west corner: a 3x3 shaft (x and z 1 to 3)
-- open through every floor, down to a pit under the ground floor, with
-- the elevator pulley at the top. The cabin waits under the pulley at the
-- top floor (a pulley picks up what touches it from below): its floor sits
-- in the top floor's hole, posts at the corners, a roof against the
-- pulley, a redstone contact and contraption controls. Each floor has an
-- elevator contact in the shaft's south wall, facing the cabin's contact
-- when the cabin's floor is level with that floor, and a door at (2, 4).
local PULLEY_Y = ROOF - 4 -- the pulley; the cabin's roof is just under it

local function wallX(x, z0, z1, F, block) fill(x, F + 1, z0, x, F + STOREY - 1, z1, block or WALL) end
local function wallZ(z, x0, x1, F, block) fill(x0, F + 1, z, x1, F + STOREY - 1, z, block or WALL) end
-- A door in a wall: the side it opens from stays empty (the builder stands
-- there); a habitat's side gets a stair up onto its raised ground.
local function door(x, z, F, facing, block, stepX, stepZ)
  set(x, F + 1, z, (block or HABITAT_DOOR) .. "[facing=" .. facing .. "]")
  set(x, F + 2, z, nil)
  if stepX then set(stepX, F + 1, stepZ, "birch_stairs[facing=" .. facing .. "]") end
end

for f = 0, FLOORS - 1 do
  local F = f * STOREY
  fill(1, F, 1, 14, F, 14, f == 0 and "stone_bricks" or "smooth_stone")
  -- the shaft: walls on its inner sides, a hole in the floor, the contact
  wallX(4, 0, 4, F); wallZ(4, 0, 4, F)
  fill(1, F, 1, 3, F, 3, nil)
  set(1, F + 1, 4, "create:elevator_contact[facing=north]")
  set(2, F + 1, 4, "spruce_door[facing=north]"); set(2, F + 2, 4, nil) -- opened from the landing side
  set(3, F + 4, 4, "sea_lantern") -- lights the landing side and the shaft
end
fill(1, -1, 1, 3, -1, 3, "stone_bricks") -- the pit's floor, under the cabin's lowest stop
fill(1, ROOF, 1, 3, ROOF, 3, WALL) -- the shaft's roof
set(2, PULLEY_Y, 2, "create:elevator_pulley")
-- the cabin, at the top floor
do
  local F = (FLOORS - 1) * STOREY
  fill(1, F, 1, 3, F, 3, "spruce_planks")
  fill(1, PULLEY_Y - 1, 1, 3, PULLEY_Y - 1, 3, "spruce_planks")
  set(2, PULLEY_Y - 1, 2, "sea_lantern")
  for _, c in ipairs({ { 1, 1 }, { 3, 1 }, { 1, 3 }, { 3, 3 } }) do
    for y = F + 1, PULLEY_Y - 2 do set(c[1], y, c[2], "spruce_fence") end
  end
  set(1, F + 1, 3, "create:redstone_contact[facing=south]") -- faces each floor's elevator contact
  set(3, F + 1, 2, "create:contraption_controls[facing=west]")
end

-- Raise a habitat's ground: one layer of soil over its floor.
local function soil(room, F)
  eachCell(room, function(x, z) set(x, F + 1, z, pick(room.soil, noise(x, F, z))) end)
end
-- Lights in the walls round a room, high up, every few blocks.
local function wallLights(room, F)
  local y = F + 6
  eachCell(room, function(x, z)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, nz = x + d[1], z + d[2]
      local b = get(nx, y, nz)
      if b and not inRoom(room, nx, nz) and (nx + nz) % 4 == 0 and not (edge(nx) and edge(nz))
        and not b:find("stairs", 1, true) and b ~= "minecraft:quartz_pillar" then
        set(nx, y, nz, room.light)
      end
    end
  end)
end
local pads = {} -- every pasture spot, checked at the end
local function pad(x, F, z)
  set(x, F + 1, z, PAD); set(x, F + 2, z, nil); set(x, F + 3, z, nil)
  pads[#pads + 1] = { x, F + 1, z }
end
local waters = {}
local function water(x, y, z) set(x, y, z, "water"); waters[#waters + 1] = { x, y, z } end
-- A flower, fern or tuft of grass on some of a room's ground, where it's clear.
local function plants(room, F, list, chance)
  eachCell(room, function(x, z)
    local below = get(x, F + 1, z)
    local ok = below and (below:find("grass_block", 1, true) or below:find("moss_block", 1, true) or below:find("podzol", 1, true))
    if ok and get(x, F + 2, z) == nil and noise(x, F + 2, z) < chance then
      set(x, F + 2, z, pick(list, noise(z, x, F)))
    end
  end)
end
-- A round leafy crown: layers { y, radius }, round (x, z).
local function crown(cx, cz, layers, leaves, light)
  for _, l in ipairs(layers) do
    local y, r = l[1], l[2]
    for dz = -math.ceil(r), math.ceil(r) do
      for dx = -math.ceil(r), math.ceil(r) do
        if dx * dx + dz * dz <= r * r + 0.5 and get(cx + dx, y, cz + dz) == nil then set(cx + dx, y, cz + dz, leaves) end
      end
    end
  end
  if light then set(cx + light[1], light[2], cz + light[3], light[4]) end
end
local function trunk(x, z, y0, y1, log) for y = y0, y1 do set(x, y, z, log) end end

---------------------------------------------------------------- ground floor: lobby and meadow

do
  local F = 0
  local lobby, meadow = floors[0].lobby, floors[0].meadow
  wallZ(4, 4, 9, F); wallX(9, 4, 14, F)
  -- the front: a wall at z 13 with the doors, a porch in front of it
  wallZ(13, 1, 8, F)
  wallX(2, 14, 14, F); wallX(7, 14, 14, F)
  fill(1, 1, 14, 1, 7, 14, WALL); fill(8, 1, 14, 8, 7, 14, WALL)
  fill(3, 1, 15, 6, 3, 15, nil) -- the porch's opening
  fill(3, 4, 15, 6, 5, 15, WALL); set(3, 4, 15, "sea_lantern"); set(6, 4, 15, "sea_lantern")
  set(2, 4, 15, WALL); set(2, 5, 15, WALL); set(7, 4, 15, WALL); set(7, 5, 15, WALL)
  for z = 14, 15 do for x = 3, 6 do set(x, 0, z, "polished_andesite") end end
  set(3, 1, 14, "lantern"); set(6, 1, 14, "lantern")
  door(4, 13, F, "south", "dark_oak_door"); door(5, 13, F, "south", "dark_oak_door")

  -- lobby floor: a quartz and diorite check
  eachCell(lobby, function(x, z) set(x, F, z, (x + z) % 2 == 0 and "smooth_quartz" or "polished_diorite") end)
  -- a rug: red border, white, a yellow sun in the middle
  for z = 8, 11 do
    for x = 3, 6 do
      local border = x == 3 or x == 6 or z == 8 or z == 11
      set(x, F + 1, z, border and "red_carpet" or (x == 4 or x == 5) and (z == 9 or z == 10) and "yellow_carpet" or "white_carpet")
    end
  end
  -- the healing counter, shelves behind it
  for x = 6, 8 do
    set(x, F + 1, 6, "quartz_bricks")
    for y = F + 1, F + 3 do set(x, y, 5, "bookshelf") end
  end
  set(5, F + 1, 6, "smooth_quartz_stairs[facing=west]")
  if COBBLEMON then set(7, F + 2, 6, "cobblemon:healing_machine[facing=south]") else set(7, F + 2, 6, "lantern") end
  set(8, F + 2, 6, "lantern")
  -- a PC by the west wall, with room above for its top half
  if COBBLEMON then set(1, F + 1, 10, "cobblemon:pc[facing=east]"); set(1, F + 2, 10, nil) end
  set(1, F + 1, 9, "chiseled_bookshelf[facing=east]"); set(1, F + 1, 11, "chiseled_bookshelf[facing=east]")
  -- a table with three seats
  set(2, F + 1, 12, "spruce_fence"); set(2, F + 2, 12, "spruce_pressure_plate")
  set(1, F + 1, 12, "spruce_stairs[facing=west]"); set(3, F + 1, 12, "spruce_stairs[facing=east]")
  set(2, F + 1, 11, "spruce_stairs[facing=north]")
  -- plants in the corners, a jukebox
  for _, c in ipairs({ { 1, 5 }, { 8, 12 }, { 8, 8 } }) do set(c[1], F + 1, c[2], "moss_block"); set(c[1], F + 2, c[2], "flowering_azalea") end
  set(1, F + 1, 7, "jukebox")
  -- lights in the ceiling (under the lagoon's sand)
  for _, c in ipairs({ { 6, 7 }, { 2, 10 }, { 6, 10 }, { 4, 14 } }) do set(c[1], STOREY, c[2], "sea_lantern") end
  -- windows from the lobby into the meadow
  for _, z in ipairs({ 6, 7, 8, 12 }) do for y = F + 2, F + 4 do set(9, y, z, "glass") end end

  -- the meadow
  soil(meadow, F)
  for _, c in ipairs({ { 12, 10 }, { 13, 10 }, { 12, 11 }, { 13, 11 }, { 11, 11 }, { 12, 12 }, { 13, 12 } }) do
    water(c[1], F + 1, c[2]); set(c[1], F, c[2], "clay")
  end
  for _, c in ipairs({ { 11, 10 }, { 11, 12 } }) do set(c[1], F + 2, c[2], "sugar_cane"); set(c[1], F + 3, c[2], "sugar_cane") end
  trunk(12, 6, F + 2, F + 5, "cherry_log")
  crown(12, 6, { { F + 5, 2 }, { F + 6, 2 }, { F + 7, 1 } }, "cherry_leaves", { 0, F + 6, 0, "cherry_log" })
  set(13, F + 2, 1, "hay_block"); set(14, F + 2, 1, "hay_block"); set(14, F + 3, 1, "hay_block"); set(14, F + 2, 2, "hay_block")
  set(10, F + 2, 14, "oak_fence"); set(10, F + 3, 14, "lantern")
  pad(7, F, 2); pad(10, F, 12); pad(14, F, 9); pad(13, F, 14)
  plants(meadow, F, { "poppy", "dandelion", "cornflower", "oxeye_daisy", "allium", "azure_bluet", "lily_of_the_valley", "short_grass", "short_grass", "short_grass" }, 0.4)
  door(9, 10, F, "east", nil, 10, 10)
  wallLights(meadow, F)
end

---------------------------------------------------------------- landings (floors 1 to 4)

local function landing(f)
  local F = f * STOREY
  for z = 5, 7 do for x = 1, 3 do set(x, F, z, (x + z) % 2 == 0 and "smooth_quartz" or "polished_diorite") end end
  wallX(4, 4, f == 3 and 7 or 8, F)
  if f ~= 3 then wallZ(8, 0, 4, F) end
  set(1, F + 1, 7, "lantern")
  set(1, F + 1, 5, "moss_block"); set(1, F + 2, 5, "azalea")
end

---------------------------------------------------------------- 1st floor: the lagoon

do
  local f, F = 1, STOREY
  local lagoon = floors[1].lagoon
  landing(f)
  soil(lagoon, F)
  -- the fish tank against the north wall: glass three deep, water inside
  for y = F + 1, F + 4 do
    for z = 1, 4 do set(5, y, z, "glass"); set(10, y, z, "glass") end
    for x = 5, 10 do set(x, y, 4, "glass") end
  end
  for z = 1, 3 do
    for x = 6, 9 do
      set(x, F, z, (x == 7 or x == 8) and z == 2 and "sea_lantern" or "dark_prismarine")
      for y = F + 1, F + 3 do water(x, y, z) end
    end
  end
  -- the pool: an oval in the sand with an island in it
  for z = 9, 13 do
    for x = 7, 14 do
      local dx, dz = (x + 0.5 - 11) / 3.3, (z + 0.5 - 11.5) / 2.5
      local island = (x == 10 or x == 11) and z == 11
      if dx * dx + dz * dz <= 1 and not island then
        water(x, F + 1, z)
        set(x, F, z, noise(x, F, z) < 0.2 and "sea_lantern" or pick({ "prismarine", "prismarine_bricks", "dark_prismarine" }, noise(z, F, x)))
      end
    end
  end
  -- a palm on the island
  trunk(10, 11, F + 2, F + 6, "jungle_log")
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    set(10 + d[1], F + 7, 11 + d[2], "jungle_leaves")
    set(10 + 2 * d[1], F + 6, 11 + 2 * d[2], "jungle_leaves")
  end
  set(10, F + 7, 11, "jungle_leaves")
  set(11, F + 2, 11, "dead_bush")
  -- a pier from the west shore
  for x = 7, 9 do set(x, F + 2, 12, "spruce_slab") end
  set(7, F + 2, 13, "spruce_fence"); set(7, F + 3, 13, "lantern")
  -- a sunshade and towels on the beach
  trunk(13, 6, F + 2, F + 4, "spruce_fence")
  for z = 5, 7 do for x = 12, 14 do set(x, F + 5, z, (x + z) % 2 == 0 and "red_wool" or "white_wool") end end
  set(12, F + 2, 7, "red_carpet"); set(14, F + 2, 5, "yellow_carpet")
  -- rocks and kelp-green prismarine along the beach
  for _, c in ipairs({ { 14, 14 }, { 1, 14 }, { 2, 14 }, { 14, 12 } }) do set(c[1], F + 2, c[2], pick({ "prismarine", "prismarine_bricks", "mossy_cobblestone" }, noise(c[1], F, c[2]))) end
  set(1, F + 3, 14, "sea_lantern")
  pad(7, F, 6); pad(12, F, 2); pad(3, F, 11); pad(14, F, 9)
  door(4, 6, F, "east", nil, 5, 6)
  wallLights(lagoon, F)
end

---------------------------------------------------------------- 2nd floor: grove and grotto

do
  local f, F = 2, 2 * STOREY
  local grove, grotto = floors[2].grove, floors[2].grotto
  landing(f)
  local function rock(x, y, z) return pick({ "stone", "stone", "tuff", "andesite", "deepslate", "cobbled_deepslate", "dripstone_block" }, noise(x, y, z)) end
  fill(5, F + 1, 8, 14, F + STOREY - 1, 8, WALL)
  for y = F + 1, F + STOREY - 1 do for x = 0, 14 do set(x, y, 8, rock(x, y, 8)) end end -- rock on the grotto's side

  -- the grove
  soil(grove, F)
  trunk(8, 3, F + 2, F + 4, "oak_log")
  crown(8, 3, { { F + 4, 2 }, { F + 5, 2 }, { F + 6, 1.5 }, { F + 7, 1 } }, "oak_leaves", { 0, F + 6, 0, "shroomlight" })
  trunk(12, 3, F + 2, F + 5, "birch_log")
  crown(12, 3, { { F + 5, 1.5 }, { F + 6, 1.5 }, { F + 7, 1 } }, "birch_leaves", { 0, F + 6, 0, "shroomlight" })
  for _, c in ipairs({ { 6, 1 }, { 14, 6 }, { 9, 6 } }) do set(c[1], F + 1, c[2], "moss_block"); set(c[1], F + 2, c[2], pick({ "azalea", "flowering_azalea" }, noise(c[1], F, c[2]))) end
  set(13, F + 2, 6, "oak_log"); set(13, F + 3, 6, "moss_carpet") -- a mossy stump
  for _, c in ipairs({ { 11, 6 }, { 12, 6 } }) do water(c[1], F + 1, c[2]); set(c[1], F, c[2], "mossy_cobblestone") end
  pad(6, F, 6); pad(13, F, 1); pad(10, F, 1)
  -- mushrooms on the podzol, ferns and flowers on the grass and moss
  eachCell(grove, function(x, z)
    if get(x, F + 1, z) == "minecraft:podzol" and get(x, F + 2, z) == nil then
      set(x, F + 2, z, noise(x, z, F) < 0.5 and "brown_mushroom" or "red_mushroom")
    end
  end)
  plants(grove, F, { "fern", "fern", "short_grass", "lily_of_the_valley", "blue_orchid", "short_grass" }, 0.45)

  -- the grotto: rock, pillars, stalagmites, rock hanging from the roof
  soil(grotto, F)
  for _, c in ipairs({ { 5, 11 }, { 6, 11 }, { 10, 13 } }) do
    for y = F + 2, F + STOREY - 1 do set(c[1], y, c[2], rock(c[1], y, c[2])) end
  end
  eachCell(grotto, function(x, z)
    if noise(x, F + 7, z) < 0.35 then set(x, F + 7, z, rock(x, F + 7, z)) end
    if get(x, F + 7, z) and noise(x, F + 6, z) < 0.2 then set(x, F + 6, z, rock(x, F + 6, z)) end
  end)
  for _, c in ipairs({ { 8, 10 }, { 12, 11 }, { 3, 14 }, { 7, 13 }, { 13, 9 } }) do
    set(c[1], F + 1, c[2], "stone")
    set(c[1], F + 2, c[2], "pointed_dripstone[vertical_direction=up]")
  end
  -- an amethyst corner, glowing a little
  for _, c in ipairs({ { 1, 9 }, { 2, 9 }, { 1, 10 } }) do set(c[1], F + 1, c[2], "amethyst_block"); set(c[1], F + 2, c[2], "amethyst_cluster[facing=up]") end
  set(1, F + 2, 9, "amethyst_block"); set(1, F + 3, 9, "amethyst_cluster[facing=up]")
  for _, c in ipairs({ { 12, 13 }, { 13, 13 }, { 12, 14 }, { 13, 14 } }) do water(c[1], F + 1, c[2]); set(c[1], F, c[2], "gravel") end
  set(14, F + 2, 14, "glowstone")
  pad(4, F, 12); pad(9, F, 11)
  door(4, 6, F, "east", nil, 5, 6)
  door(2, 8, F, "south", nil, 2, 9)
  wallLights(grove, F); wallLights(grotto, F)
end

---------------------------------------------------------------- 3rd floor: the hall, ember, frost and dunes

do
  local f, F = 3, 3 * STOREY
  local ember, frost, dunes = floors[3].ember, floors[3].frost, floors[3].dunes
  landing(f)
  for x = 1, 14 do set(x, F, 8, x % 3 == 0 and "polished_andesite" or "polished_diorite") end
  wallZ(7, 4, 14, F); wallZ(9, 0, 14, F); wallX(8, 9, 14, F)
  -- windows from the hall into each room
  for _, x in ipairs({ 6, 7, 11, 12 }) do for y = F + 2, F + 3 do set(x, y, 7, ember.glass) end end
  for _, x in ipairs({ 5, 6 }) do for y = F + 2, F + 3 do set(x, y, 9, frost.glass) end end
  for _, x in ipairs({ 12, 13 }) do for y = F + 2, F + 3 do set(x, y, 9, dunes.glass) end end
  for _, x in ipairs({ 5, 9, 13 }) do set(x, F + STOREY, 8, "sea_lantern") end -- under the aviary's soil

  -- ember hollow: walled-in magma pits, basalt columns, crimson growth
  soil(ember, F)
  local function pit(x0, z0, x1, z1)
    for z = z0 - 1, z1 + 1 do
      for x = x0 - 1, x1 + 1 do
        if x < x0 or x > x1 or z < z0 or z > z1 then set(x, F + 2, z, "blackstone_wall") else set(x, F + 1, z, "magma_block") end
      end
    end
  end
  pit(8, 3, 9, 4); pit(13, 2, 13, 2)
  for _, c in ipairs({ { 14, 5, 4 }, { 13, 6, 2 }, { 6, 1, 3 }, { 11, 1, 5 } }) do
    for y = F + 2, F + 1 + c[3] do set(c[1], y, c[2], y == F + 1 + c[3] and "polished_basalt" or "basalt") end
  end
  set(11, F + 7, 1, "basalt")
  set(6, F + 2, 4, "gilded_blackstone"); set(10, F + 2, 6, "gilded_blackstone")
  eachCell(ember, function(x, z)
    if get(x, F + 1, z) == "minecraft:crimson_nylium" and get(x, F + 2, z) == nil then
      set(x, F + 2, z, noise(x, z, F) < 0.6 and "crimson_roots" or "crimson_fungus")
    end
  end)
  pad(6, F, 6); pad(11, F, 4)

  -- frost cavern: snow and ice, spikes, a snowy spruce
  soil(frost, F)
  for _, c in ipairs({ { 2, 11, 4 }, { 1, 12, 2 }, { 6, 14, 3 }, { 7, 13, 1 } }) do
    for y = F + 2, F + 1 + c[3] do set(c[1], y, c[2], y == F + 1 + c[3] and "blue_ice" or "packed_ice") end
  end
  trunk(5, 12, F + 2, F + 5, "spruce_log")
  crown(5, 12, { { F + 3, 1.5 }, { F + 4, 1 }, { F + 5, 1.5 }, { F + 6, 1 }, { F + 7, 0 } }, "spruce_leaves")
  set(5, F + 7, 12, "snow_block")
  pad(3, F, 13); pad(7, F, 10)

  -- sunset dunes: sand hills, sandstone ruins, a terracotta mesa
  soil(dunes, F)
  eachCell(dunes, function(x, z)
    if x >= 12 and z >= 12 and noise(x, F + 2, z) < 0.7 then set(x, F + 2, z, "sand") end
  end)
  local mesa = { "orange_terracotta", "yellow_terracotta", "white_terracotta", "red_terracotta", "terracotta" }
  for _, c in ipairs({ { 14, 14, 5 }, { 13, 14, 3 }, { 14, 13, 4 }, { 14, 12, 2 } }) do
    for y = F + 2, F + 1 + c[3] do set(c[1], y, c[2], mesa[(y - F - 2) % #mesa + 1]) end
  end
  for _, x in ipairs({ 9, 11 }) do
    set(x, F + 2, 14, "cut_sandstone"); set(x, F + 3, 14, "cut_sandstone"); set(x, F + 4, 14, "chiseled_sandstone")
  end
  set(10, F + 4, 14, "smooth_sandstone_slab")
  set(9, F + 2, 12, "sandstone_stairs[facing=east]")
  for _, c in ipairs({ { 10, 11 }, { 13, 10 }, { 9, 13 } }) do if get(c[1], F + 2, c[2]) == nil then set(c[1], F + 2, c[2], "dead_bush") end end
  pad(10, F, 12); pad(12, F, 11)

  door(4, 6, F, "east", nil, 5, 6)
  door(3, 9, F, "south", nil, 3, 10)
  door(11, 9, F, "south", nil, 11, 10)
  wallLights(ember, F); wallLights(frost, F); wallLights(dunes, F)
end

---------------------------------------------------------------- top floor: the sky garden and its dome

-- The dome: a half ellipsoid on the roof, glass with white ribs and a lit
-- crown. Below the roof the top floor's walls hold the aviary in.
local function inDome(x, y, z)
  if x < 0 or x >= SIZE or z < 0 or z >= SIZE then return false end
  if y < ROOF then return true end
  local dx, dz, dy = (x + 0.5 - SIZE / 2) / DOME_R, (z + 0.5 - SIZE / 2) / DOME_R, (y - ROOF) / DOME_H
  return dx * dx + dz * dz + dy * dy <= 1
end

do
  local f, F = 4, 4 * STOREY
  local aviary = floors[4].aviary
  landing(f)
  -- the core and landing reach the roof; the rest of the roof is the dome
  wallX(4, 4, 8, F); wallZ(8, 0, 4, F)
  for z = 1, 14 do
    for x = 1, 14 do
      set(x, ROOF, z, (x <= 4 and z <= 8 or not inDome(x, ROOF, z)) and WALL or nil)
    end
  end
  for y = ROOF, ROOF + DOME_H do
    for z = 0, SIZE - 1 do
      for x = 0, SIZE - 1 do
        if inDome(x, y, z) and not (y == ROOF and x <= 4 and z <= 8) then
          local shell = not (inDome(x + 1, y, z) and inDome(x - 1, y, z) and inDome(x, y + 1, z) and inDome(x, y, z + 1) and inDome(x, y, z - 1))
          if shell then
            local rib = x == 7 or x == 8 or z == 7 or z == 8
            set(x, y, z, rib and WALL or "glass")
          end
        end
      end
    end
  end
  for z = 7, 8 do for x = 7, 8 do set(x, ROOF + DOME_H - 1, z, "sea_lantern") end end
  -- planters on the roof round the dome
  for _, c in ipairs({ { 13, 13 }, { 13, 2 }, { 2, 13 }, { 2, 2 } }) do
    set(c[1], ROOF + 1, c[2], "moss_block"); set(c[1], ROOF + 2, c[2], "flowering_azalea")
  end

  soil(aviary, F)
  -- the great tree in the middle: a 2x2 dark oak trunk, branches to perch on
  for z = 7, 8 do for x = 7, 8 do trunk(x, z, F + 2, ROOF + 1, "dark_oak_log") end end
  for _, b in ipairs({ { 6, F + 5, 7 }, { 5, F + 5, 7 }, { 9, F + 6, 8 }, { 10, F + 6, 8 }, { 11, F + 7, 8 },
    { 7, F + 4, 9 }, { 7, F + 4, 10 }, { 8, F + 7, 6 }, { 8, F + 7, 5 } }) do
    set(b[1], b[2], b[3], "dark_oak_wood")
  end
  local canopy = { { F + 6, 1.5 }, { F + 7, 3 }, { ROOF, 4 }, { ROOF + 1, 4 }, { ROOF + 2, 3.5 }, { ROOF + 3, 2.5 }, { ROOF + 4, 1.5 } }
  for _, l in ipairs(canopy) do
    local y, r = l[1], l[2]
    for dz = -5, 5 do
      for dx = -5, 5 do
        local x, z = 8 + dx, 8 + dz
        local cx, cz = x + 0.5 - 8, z + 0.5 - 8
        local inside = cx * cx + cz * cz <= r * r
        local clear = not (x <= 4 and z <= 8) and x >= 1 and x <= 14 and z >= 1 and z <= 14
        if inside and clear and get(x, y, z) == nil then
          local shell = y >= ROOF and not (inDome(x + 1, y, z) and inDome(x - 1, y, z) and inDome(x, y + 1, z) and inDome(x, y, z + 1) and inDome(x, y, z - 1))
          if not shell then
            set(x, y, z, noise(x, y, z) < 0.25 and "flowering_azalea_leaves" or "dark_oak_leaves")
          end
        end
      end
    end
  end
  for _, c in ipairs({ { 6, ROOF + 1, 9 }, { 10, ROOF, 7 }, { 8, ROOF + 2, 10 }, { 9, F + 7, 9 } }) do set(c[1], c[2], c[3], "shroomlight") end
  -- two floating islands for flyers
  local function island(cx, cz, y)
    set(cx, y - 2, cz, "stone")
    for dz = -1, 1 do
      for dx = -1, 1 do
        set(cx + dx, y - 1, cz + dz, (dx == 0 or dz == 0) and "dirt" or "stone")
        set(cx + dx, y, cz + dz, "grass_block")
      end
    end
    set(cx, y + 1, cz, "flowering_azalea"); set(cx + 1, y + 1, cz - 1, "poppy"); set(cx - 1, y + 1, cz + 1, "cornflower")
  end
  island(12, 4, F + 6); island(3, 12, F + 6)
  -- perches, a pond, bushes
  for _, c in ipairs({ { 6, 12 }, { 13, 6 } }) do trunk(c[1], c[2], F + 2, F + 3, "oak_fence"); set(c[1], F + 4, c[2], "lantern") end
  for _, c in ipairs({ { 12, 12 }, { 13, 12 }, { 12, 13 }, { 13, 13 } }) do water(c[1], F + 1, c[2]); set(c[1], F, c[2], "clay") end
  for _, c in ipairs({ { 14, 14 }, { 5, 1 }, { 1, 14 } }) do set(c[1], F + 1, c[2], "moss_block"); set(c[1], F + 2, c[2], "flowering_azalea") end
  pad(6, F, 3); pad(13, F, 9); pad(3, F, 10); pad(10, F, 13)
  plants(aviary, F, { "poppy", "dandelion", "cornflower", "allium", "pink_tulip", "short_grass", "short_grass" }, 0.35)
  door(4, 6, F, "east", nil, 5, 6)
  wallLights(aviary, F)
end

---------------------------------------------------------------- checks

-- Water is placed last in its layer: every pool must be held in on all
-- sides and below, so it can't run off. Pasture spots need two clear blocks.
local function solid(x, y, z)
  local b = get(x, y, z)
  return b ~= nil
end
for _, w in ipairs(waters) do
  local x, y, z = w[1], w[2], w[3]
  for _, d in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, -1, 0 } }) do
    if not solid(x + d[1], y + d[2], z + d[3]) then error(("water at %d %d %d can run off"):format(x, y, z), 0) end
  end
end
for _, p in ipairs(pads) do
  if get(p[1], p[2] + 1, p[3]) or get(p[1], p[2] + 2, p[3]) then error(("pasture spot at %d %d %d isn't clear"):format(p[1], p[2], p[3]), 0) end
end

local paradise = { name = "Pokemon Paradise", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  paradise.blocks[#paradise.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return paradise
