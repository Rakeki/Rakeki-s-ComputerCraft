-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Pokemon Paradise: an overgrown greenhouse of two glass halls side by
-- side under barrel vaults ribbed in pale oak, leaves spilling over the
-- glass and hanging down the walls, on a mossy stone base with a raised
-- deck and steps at the front and trees at its corners. Inside, closed
-- habitats for Cobblemon pastures (chiseled stone brick tiles in the
-- ground mark each pasture spot, two clear blocks above it):
--
--   west hall, ground  the foyer (front doors, a healing counter, a PC, a
--                      fountain, benches), a corridor along the west
--                      wall, the Coral Lagoon (a beach round a pool with a
--                      palm island, a pier, a sunshade and a glass fish
--                      tank) and the Sunny Meadow (a cherry tree, a pond,
--                      flowers, hay)
--   west hall, upper   a landing looking out through the front gable, a
--                      corridor, and under the vault Ember Hollow (basalt,
--                      walled-in magma pits), Sunset Dunes (sand hills, a
--                      terracotta mesa, ruins) and Frost Cavern (snow, ice
--                      spikes, a snowy spruce)
--   east hall          the Rainforest, open to the vault: a giant jungle
--                      tree, a mossy cliff with a waterfall into a pond,
--                      and a canopy walk from the upper landing out to a
--                      deck round the tree
--
-- A Create elevator joins the floors: a 3x3 shaft in the foyer's
-- north-west corner, the pulley at the top, the cabin parked under it at
-- the upper floor, an elevator contact and a door on each floor; you glue
-- the cabin and power the pulley. Habitats have one block of soil over
-- their floor, so their doors have a step up inside.
--
-- 'cobblemon=false' after the plan's name leaves out the healing machine
-- and PC (projector paradise cobblemon=false). y 0 is the ground layer
-- (grass round the building, stone under it); x runs east, z south; the
-- deck and the front doors are on the south side.
local opts = ... or {}
local COBBLEMON = not (opts.cobblemon == "false" or opts.cobblemon == "no" or opts.cobblemon == "off")

local G, U = 1, 10 -- the ground floor's and the upper floor's floor layers
local BASE, R = 10, 8.5 -- the vaults spring from y BASE with this radius
local Z0, Z1 = 1, 29 -- the back and front walls
local HALLS = { { x0 = 2, x1 = 18 }, { x0 = 18, x1 = 34 } } -- west and east, sharing x 18
local PLOT = { x0 = 0, x1 = 36, z0 = 0, z1 = 37 } -- the ground the plan covers
local DECK = { x0 = 6, x1 = 30, z0 = 30, z1 = 34 }
local FRAME = "stripped_oak_wood" -- ribs, posts and beams
local PAD = "chiseled_stone_bricks" -- marks a pasture spot
local HABITAT_DOOR = "birch_door"
local LEAVES = { "oak_leaves", "oak_leaves", "azalea_leaves", "azalea_leaves", "flowering_azalea_leaves", "jungle_leaves" }

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

---------------------------------------------------------------- the vaults

-- Inside either hall's cross-section (walls up to BASE, a half circle above).
local function inVault(x, y)
  if x < HALLS[1].x0 or x > HALLS[2].x1 then return false end
  if y < BASE then return true end
  for _, h in ipairs(HALLS) do
    local dx = x + 0.5 - (h.x0 + h.x1 + 1) / 2
    if dx * dx + (y - BASE) * (y - BASE) < R * R then return true end
  end
  return false
end
-- The glass skin: vault cells with open air beside or above them.
local function shell(x, y)
  return y >= BASE and inVault(x, y) and not (inVault(x - 1, y) and inVault(x + 1, y) and inVault(x, y + 1))
end
-- Open space under the vault (walls below BASE are built separately).
local function interior(x, y) return inVault(x, y) and not shell(x, y) end
local function colTop(x)
  for y = BASE + 12, BASE, -1 do if interior(x, y) then return y end end
  return BASE - 1
end

---------------------------------------------------------------- rooms

-- rects { x0, z0, x1, z1 }; a habitat gets raised soil.
local rooms = {
  lagoon = { F = G, rects = { { 6, 2, 17, 11 } }, soil = { "sand" }, light = "sea_lantern" },
  meadow = { F = G, rects = { { 6, 13, 17, 21 } }, soil = { "grass_block" }, light = "shroomlight" },
  ember = { F = U, rects = { { 6, 2, 17, 7 } }, light = "ochre_froglight",
    soil = { "blackstone", "blackstone", "basalt", "smooth_basalt", "polished_blackstone", "crimson_nylium" } },
  dunes = { F = U, rects = { { 6, 9, 17, 14 } }, soil = { "sand" }, light = "glowstone" },
  frost = { F = U, rects = { { 6, 16, 17, 21 } }, light = "sea_lantern",
    soil = { "snow_block", "snow_block", "snow_block", "packed_ice", "blue_ice" } },
  forest = { F = G, rects = { { 19, 2, 33, 28 } }, light = "verdant_froglight",
    soil = { "grass_block", "grass_block", "grass_block", "moss_block", "moss_block", "podzol", "rooted_dirt", "coarse_dirt" } },
}
local function inRoom(room, x, z)
  for _, r in ipairs(room.rects) do
    if x >= r[1] and x <= r[3] and z >= r[2] and z <= r[4] then return true end
  end
  return false
end
local function eachCell(room, fn)
  for _, r in ipairs(room.rects) do
    for z = r[2], r[4] do for x = r[1], r[3] do fn(x, z) end end
  end
end

local pads, waters = {}, {}
local function pad(x, F, z)
  set(x, F + 1, z, PAD); set(x, F + 2, z, nil); set(x, F + 3, z, nil)
  pads[#pads + 1] = { x, F + 1, z }
end
local function water(x, y, z) set(x, y, z, "water"); waters[#waters + 1] = { x, y, z } end
local function soil(room)
  eachCell(room, function(x, z) set(x, room.F + 1, z, pick(room.soil, noise(x, room.F, z))) end)
end
-- A flower, fern or tuft on some of a room's ground, where it's clear.
local function plants(room, list, chance)
  local F = room.F
  eachCell(room, function(x, z)
    local below = get(x, F + 1, z) or ""
    local ok = below:find("grass_block", 1, true) or below:find("moss_block", 1, true) or below:find("podzol", 1, true)
    if ok and get(x, F + 2, z) == nil and noise(x, F + 2, z) < chance then set(x, F + 2, z, pick(list, noise(z, x, F))) end
  end)
end
-- A round leafy crown: layers { y, radius } round (cx, cz), only into open space.
local function crown(cx, cz, layers, leaves, room)
  for _, l in ipairs(layers) do
    local y, r = l[1], l[2]
    for dz = -math.ceil(r), math.ceil(r) do
      for dx = -math.ceil(r), math.ceil(r) do
        local x, z = cx + dx, cz + dz
        local fits = room == nil or (inRoom(room, x, z) and interior(x, y))
        if dx * dx + dz * dz <= r * r + 0.5 and fits and get(x, y, z) == nil then
          set(x, y, z, type(leaves) == "table" and pick(leaves, noise(x, y, z)) or leaves)
        end
      end
    end
  end
end
local function trunk(x, z, y0, y1, log) for y = y0, y1 do set(x, y, z, log) end end
-- A door in a wall: the side it opens from stays empty (the builder stands
-- there); a habitat's side gets a stair up onto its raised ground.
local function door(x, z, F, facing, block, stepX, stepZ)
  set(x, F + 1, z, (block or HABITAT_DOOR) .. "[facing=" .. facing .. "]")
  set(x, F + 2, z, nil)
  if stepX then set(stepX, F + 1, stepZ, "birch_stairs[facing=" .. facing .. "]") end
end

-- A glass screen with oak posts every 4 blocks and an oak sill, from the
-- floor up to the ceiling (or into the vault), some posts lit.
local function screen(x0, z0, x1, z1, F, light)
  for z = z0, z1 do
    for x = x0, x1 do
      local along = x0 == x1 and z or x
      local top = F == G and U - 1 or colTop(x)
      for y = F + 1, top do
        local post = along % 4 == 1
        local block = (y == F + 1 or post) and FRAME or "glass"
        if post and y == F + 4 and light then block = light end
        set(x, y, z, block)
      end
    end
  end
end

---------------------------------------------------------------- the ground and the shell

-- the ground layer: stone under the building and deck, grass round it
for z = PLOT.z0, PLOT.z1 do
  for x = PLOT.x0, PLOT.x1 do
    local under = x >= 2 and x <= 34 and z >= Z0 and z <= Z1 or x >= DECK.x0 and x <= DECK.x1 and z >= DECK.z0 and z <= DECK.z1
    local n = noise(x, 0, z)
    set(x, 0, z, under and (n < 0.3 and "mossy_stone_bricks" or "stone_bricks")
      or n < 0.12 and "coarse_dirt" or n < 0.25 and "moss_block" or "grass_block")
  end
end
-- the floor
for z = Z0, Z1 do
  for x = 2, 34 do set(x, G, z, noise(x, G, z) < 0.3 and "mossy_stone_bricks" or "stone_bricks") end
end

-- The walls up to the vault: a stone footing, oak posts in line with the
-- ribs, glass between, an oak beam on top.
local function wallCell(x, y, z, along)
  if y == G + 1 then return noise(x, y, z) < 0.4 and "mossy_stone_bricks" or "stone_bricks" end
  if y == BASE - 1 or along % 4 == 1 then return FRAME end
  return "glass"
end
for y = G + 1, BASE - 1 do
  for z = Z0, Z1 do
    set(2, y, z, wallCell(2, y, z, z)); set(34, y, z, wallCell(34, y, z, z))
  end
  for x = 2, 34 do
    set(x, y, Z0, wallCell(x, y, Z0, x)); set(x, y, Z1, wallCell(x, y, Z1, x))
  end
end
-- the wall between the halls, glass up into the vault
for y = G + 1, colTop(18) do
  for z = Z0 + 1, Z1 - 1 do set(18, y, z, (y == G + 1 or y == BASE - 1 or z % 4 == 1) and FRAME or "glass") end
end
-- the vaults: glass between oak ribs every 4 blocks, two purlins and a ridge
for z = Z0, Z1 do
  for x = 2, 34 do
    for y = BASE, BASE + 10 do
      if shell(x, y) then
        local rib = (z - Z0) % 4 == 0 or z == Z1
        local purlin = y == BASE + 3 or y == BASE + 6 or x == 10 or x == 26
        set(x, y, z, (rib or purlin) and FRAME or "glass")
      elseif interior(x, y) and (z == Z0 or z == Z1) then
        -- the gables: glass in an oak grid, with a round window's frame
        local frame = x % 4 == 2 or (y - BASE) % 3 == 2
        set(x, y, z, frame and FRAME or "glass")
      end
    end
  end
end

---------------------------------------------------------------- the west hall: floors, corridors, screens

-- the upper floor, which is the ground floor's ceiling
fill(3, U, Z0 + 1, 17, U, Z1 - 1, "spruce_planks")
for z = 4, 28, 4 do
  for _, x in ipairs({ 8, 12, 16 }) do set(x, U, z, "sea_lantern") end
end
-- corridors along the west wall, x 3 and 4, on both floors
for z = Z0 + 1, 22 do
  for x = 3, 4 do set(x, G, z, "spruce_planks") end
end
for _, z in ipairs({ 4, 10, 16, 21 }) do set(3, G + 1, z, "lantern"); set(3, U + 1, z, "lantern") end
-- screens: the corridors' east side, then between rooms
for _, F in ipairs({ G, U }) do screen(5, 2, 5, 22, F) end
screen(6, 12, 17, 12, G, "sea_lantern"); screen(6, 22, 17, 22, G, "shroomlight")
screen(6, 8, 17, 8, U, "ochre_froglight"); screen(6, 15, 17, 15, U, "glowstone"); screen(6, 22, 17, 22, U, "sea_lantern")
-- lights in the screen along the corridors
for _, F in ipairs({ G, U }) do
  for z = 5, 21, 4 do set(5, F + 4, z, "sea_lantern") end
end

---------------------------------------------------------------- the elevator

-- A 3x3 shaft (x 3..5, z 26..28) from the foyer up into the vault, the
-- pulley at the top; the cabin waits under it at the upper floor (a pulley
-- picks up what touches it from below): floor, corner posts, a roof
-- against the pulley, a redstone contact and contraption controls. Each
-- floor has an elevator contact facing the cabin's and a door at (4, 25).
local PULLEY_Y = U + 4
for y = G + 1, colTop(6) do
  for z = 25, 28 do set(6, y, z, y == U and "spruce_planks" or FRAME) end
  for x = 2, 6 do if interior(x, y) or y < BASE then set(x, y, 25, y == U and "spruce_planks" or FRAME) end end
end
for x = 3, 5 do for z = 26, 28 do for y = G, colTop(x) do set(x, y, z, nil) end end end
for _, F in ipairs({ G, U }) do
  set(3, F + 1, 25, "create:elevator_contact[facing=south]")
  set(4, F + 1, 25, "spruce_door[facing=north]"); set(4, F + 2, 25, nil)
  set(5, F + 3, 25, "sea_lantern")
end
set(4, PULLEY_Y, 27, "create:elevator_pulley")
fill(3, U, 26, 5, U, 28, "spruce_planks")
fill(3, PULLEY_Y - 1, 26, 5, PULLEY_Y - 1, 28, "spruce_planks")
set(4, PULLEY_Y - 1, 27, "sea_lantern")
for _, c in ipairs({ { 3, 28 }, { 5, 26 }, { 5, 28 } }) do trunk(c[1], c[2], U + 1, PULLEY_Y - 2, "spruce_fence") end
set(3, U + 1, 26, "create:redstone_contact[facing=north]"); set(3, U + 2, 26, "spruce_fence")
set(5, U + 1, 27, "create:contraption_controls[facing=west]")

---------------------------------------------------------------- the foyer and the landing

do
  local F = G
  door(10, Z1, F, "south", "spruce_door"); door(11, Z1, F, "south", "spruce_door")
  -- a counter with the healing machine, shelves behind it
  for x = 13, 16 do
    set(x, F + 1, 24, FRAME)
    for y = F + 1, F + 3 do set(x, y, 23, "bookshelf") end
  end
  set(15, F + 2, 24, COBBLEMON and "cobblemon:healing_machine[facing=south]" or "lantern")
  set(13, F + 2, 24, "lantern")
  if COBBLEMON then set(17, F + 1, 28, "cobblemon:pc[facing=west]"); set(17, F + 2, 28, nil) end
  -- a fountain by the doors
  for z = 26, 28 do
    for x = 12, 15 do
      if x == 12 or x == 15 or z == 26 or z == 28 then set(x, F + 1, z, "mossy_stone_bricks") else water(x, F + 1, z) end
    end
  end
  set(12, F + 2, 26, "lantern"); set(15, F + 2, 26, "lantern")
  -- benches with their backs to the screen, planters
  for x = 8, 10 do set(x, F + 1, 23, "spruce_stairs[facing=north]") end
  for _, c in ipairs({ { 7, 23 }, { 11, 23 }, { 17, 23 }, { 7, 28 } }) do
    set(c[1], F + 1, c[2], "moss_block"); set(c[1], F + 2, c[2], pick({ "flowering_azalea", "azalea" }, noise(c[1], F, c[2])))
  end
  for z = 24, 27 do for x = 7, 11 do if get(x, F + 1, z) == nil and noise(x, F + 1, z) < 0.3 then set(x, F + 1, z, "moss_carpet") end end end
  door(18, 26, F, "east", nil, 19, 26) -- into the rainforest
end
do
  local F = U
  -- the landing: seats facing the front gable, plants, and a door out
  -- onto the canopy walk
  for x = 9, 12 do set(x, F + 1, 27, "spruce_stairs[facing=north]") end
  for _, c in ipairs({ { 7, 23 }, { 17, 23 }, { 8, 28 }, { 13, 28 } }) do
    set(c[1], F + 1, c[2], "moss_block"); set(c[1], F + 2, c[2], pick({ "flowering_azalea", "azalea" }, noise(c[1], F, c[2])))
  end
  set(16, F + 1, 28, "lantern"); set(10, F + 1, 24, "lantern")
  door(18, 26, F, "east", "spruce_door")
end

---------------------------------------------------------------- ground floor: lagoon and meadow

do
  local room, F = rooms.lagoon, G
  soil(room)
  -- the fish tank in the back corner: glass three deep
  for y = F + 1, F + 4 do
    for z = 2, 5 do set(10, y, z, "glass") end
    for x = 6, 10 do set(x, y, 5, "glass") end
  end
  for z = 2, 4 do
    for x = 6, 9 do
      set(x, F, z, (x == 7 or x == 8) and z == 3 and "sea_lantern" or "dark_prismarine")
      for y = F + 1, F + 3 do water(x, y, z) end
    end
  end
  -- the pool: an oval in the sand with an island in it
  for z = 6, 10 do
    for x = 10, 17 do
      local dx, dz = (x + 0.5 - 13.5) / 3.2, (z + 0.5 - 8.5) / 2.2
      local island = (x == 13 or x == 14) and z == 8
      if dx * dx + dz * dz <= 1 and not island then
        water(x, F + 1, z)
        set(x, F, z, noise(x, F, z) < 0.2 and "sea_lantern" or pick({ "prismarine", "prismarine_bricks", "dark_prismarine" }, noise(z, F, x)))
      end
    end
  end
  trunk(13, 8, F + 2, F + 6, "jungle_log")
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    set(13 + d[1], F + 7, 8 + d[2], "jungle_leaves")
    set(13 + 2 * d[1], F + 6, 8 + 2 * d[2], "jungle_leaves")
  end
  set(13, F + 7, 8, "jungle_leaves"); set(14, F + 2, 8, "dead_bush")
  for z = 8, 9 do set(10, F + 2, z, "spruce_slab") end -- a pier
  trunk(16, 3, F + 2, F + 4, "spruce_fence") -- a sunshade, towels
  for z = 2, 4 do for x = 15, 17 do set(x, F + 5, z, (x + z) % 2 == 0 and "red_wool" or "white_wool") end end
  set(15, F + 2, 4, "red_carpet"); set(17, F + 2, 2, "yellow_carpet")
  for _, c in ipairs({ { 17, 11 }, { 6, 11 }, { 12, 2 } }) do set(c[1], F + 2, c[2], pick({ "prismarine", "mossy_cobblestone" }, noise(c[1], F, c[2]))) end
  pad(7, F, 7); pad(13, F, 3); pad(8, F, 10); pad(16, F, 11)
  door(5, 9, F, "east", nil, 6, 9)
end
do
  local room, F = rooms.meadow, G
  soil(room)
  trunk(14, 16, F + 2, F + 5, "cherry_log")
  crown(14, 16, { { F + 5, 2.5 }, { F + 6, 3 }, { F + 7, 2.5 }, { F + 8, 1.5 } }, "cherry_leaves", room)
  set(14, F + 7, 16, "shroomlight")
  for _, c in ipairs({ { 8, 19 }, { 9, 19 }, { 8, 20 }, { 9, 20 }, { 10, 20 } }) do water(c[1], F + 1, c[2]); set(c[1], F, c[2], "clay") end
  for _, c in ipairs({ { 7, 19 }, { 10, 19 } }) do set(c[1], F + 2, c[2], "sugar_cane"); set(c[1], F + 3, c[2], "sugar_cane") end
  for _, c in ipairs({ { 17, 13, 2 }, { 16, 13, 1 }, { 17, 14, 1 } }) do trunk(c[1], c[2], F + 2, F + 1 + c[3], "hay_block") end
  set(6, F + 2, 21, "oak_fence"); set(6, F + 3, 21, "lantern")
  pad(7, F, 14); pad(11, F, 21); pad(17, F, 20); pad(11, F, 14)
  plants(room, { "poppy", "dandelion", "cornflower", "oxeye_daisy", "allium", "azure_bluet", "lily_of_the_valley", "short_grass", "short_grass", "short_grass" }, 0.4)
  door(5, 17, F, "east", nil, 6, 17)
end

---------------------------------------------------------------- upper floor: ember, dunes, frost

-- A column of blocks on a room's ground, as tall as asked or the vault lets it.
local function column(x, z, F, h, block)
  for y = F + 2, F + 1 + h do
    if interior(x, y) then set(x, y, z, type(block) == "function" and block(y - F - 1, h) or block) end
  end
end
do
  local room, F = rooms.ember, U
  soil(room)
  local function pit(x0, z0, x1, z1)
    for z = z0 - 1, z1 + 1 do
      for x = x0 - 1, x1 + 1 do
        if x < x0 or x > x1 or z < z0 or z > z1 then set(x, F + 2, z, "blackstone_wall") else set(x, F + 1, z, "magma_block") end
      end
    end
  end
  pit(10, 4, 11, 5); pit(15, 3, 15, 3)
  local function basalt(i, h) return i == h and "polished_basalt" or "basalt" end
  column(8, 2, F, 5, basalt); column(9, 2, F, 3, basalt); column(17, 6, F, 2, basalt); column(13, 7, F, 4, basalt)
  set(7, F + 2, 5, "gilded_blackstone"); set(14, F + 2, 6, "gilded_blackstone")
  eachCell(room, function(x, z)
    if get(x, F + 1, z) == "minecraft:crimson_nylium" and get(x, F + 2, z) == nil then
      set(x, F + 2, z, noise(x, z, F) < 0.6 and "crimson_roots" or "crimson_fungus")
    end
  end)
  pad(7, F, 3); pad(13, F, 2); pad(16, F, 7)
  door(5, 5, F, "east", nil, 6, 5)
end
do
  local room, F = rooms.dunes, U
  soil(room)
  eachCell(room, function(x, z)
    if x >= 14 and z >= 12 and noise(x, F + 2, z) < 0.7 and get(x, F + 2, z) == nil then set(x, F + 2, z, "sand") end
  end)
  local mesa = { "orange_terracotta", "yellow_terracotta", "white_terracotta", "red_terracotta", "terracotta" }
  for _, c in ipairs({ { 15, 9, 4 }, { 16, 9, 3 }, { 15, 10, 2 }, { 17, 9, 2 } }) do
    column(c[1], c[2], F, c[3], function(i) return mesa[(i - 1) % #mesa + 1] end)
  end
  for _, x in ipairs({ 9, 11 }) do column(x, 14, F, 3, function(i, h) return i == h and "chiseled_sandstone" or "cut_sandstone" end) end
  set(10, F + 4, 14, "smooth_sandstone_slab")
  set(12, F + 2, 9, "sandstone_stairs[facing=north]")
  for _, c in ipairs({ { 8, 11 }, { 13, 13 }, { 17, 11 } }) do if get(c[1], F + 2, c[2]) == nil then set(c[1], F + 2, c[2], "dead_bush") end end
  pad(8, F, 9); pad(12, F, 12)
  door(5, 12, F, "east", nil, 6, 12)
end
do
  local room, F = rooms.frost, U
  soil(room)
  local function ice(i, h) return i == h and "blue_ice" or "packed_ice" end
  column(7, 21, F, 4, ice); column(8, 21, F, 2, ice); column(16, 17, F, 3, ice); column(17, 18, F, 1, ice); column(14, 21, F, 2, ice)
  trunk(11, 19, F + 2, F + 5, "spruce_log")
  crown(11, 19, { { F + 3, 2 }, { F + 4, 1.5 }, { F + 5, 2 }, { F + 6, 1.5 }, { F + 7, 1 }, { F + 8, 0 } }, "spruce_leaves", room)
  pad(8, F, 16); pad(15, F, 20); pad(14, F, 16)
  door(5, 19, F, "east", nil, 6, 19)
end

---------------------------------------------------------------- the east hall: rainforest

do
  local room, F = rooms.forest, G
  soil(room)
  local function rock(x, y, z) return pick({ "stone", "mossy_cobblestone", "andesite", "tuff", "cobblestone", "mossy_stone_bricks" }, noise(x, y, z)) end
  -- a mossy cliff in the back corner, a waterfall off it into a pond
  local tops = { [2] = 9, [3] = 8, [4] = 6 }
  for z = 2, 4 do
    for x = 28, 33 do
      local top = tops[z] - math.max(0, 30 - x) * 2
      if not (x == 31 and z == 4) then
        for y = F + 1, F + top do set(x, y, z, y == F + top and "moss_block" or rock(x, y, z)) end
      end
    end
  end
  set(30, F + 8, 3, rock(30, 9, 3)); set(32, F + 8, 3, rock(32, 9, 3)); set(31, F + 8, 3, rock(31, 9, 3))
  set(30, F + 7, 3, rock(30, 8, 3)); set(31, F + 7, 3, rock(31, 8, 3))
  set(30, F + 9, 2, rock(30, 10, 2)); set(32, F + 9, 2, rock(32, 10, 2)); set(31, F + 9, 2, rock(31, 10, 2))
  set(30, F + 9, 3, "moss_block"); set(32, F + 9, 3, "moss_block")
  set(31, F + 9, 3, "water") -- the waterfall's source: it pours over the front and falls into the pond
  set(29, F + 4, 3, "glowstone"); set(33, F + 6, 2, "glowstone")
  for z = 4, 8 do
    for x = 28, 33 do
      local dx, dz = (x + 0.5 - 31) / 3, (z + 0.5 - 6.5) / 2.6
      if (dx * dx + dz * dz <= 1 and z >= 5) or (x == 31 and z == 4) then water(x, F + 1, z); set(x, F, z, pick({ "clay", "gravel", "mossy_cobblestone" }, noise(x, F, z))) end
    end
  end
  for _, c in ipairs({ { 27, 6 }, { 27, 7 } }) do if get(c[1], F + 2, c[2]) == nil then set(c[1], F + 2, c[2], "sugar_cane"); set(c[1], F + 3, c[2], "sugar_cane") end end

  -- the giant tree: a 2x2 jungle trunk, buttress roots, branches
  for z = 15, 16 do for x = 26, 27 do trunk(x, z, F + 2, colTop(x) - 3, "jungle_log") end end
  for _, c in ipairs({ { 25, 15, 2 }, { 28, 16, 3 }, { 26, 14, 2 }, { 27, 17, 1 }, { 25, 17, 1 }, { 28, 14, 1 } }) do
    trunk(c[1], c[2], F + 2, F + 1 + c[3], "jungle_wood")
  end
  for _, b in ipairs({ { 24, 13, 15 }, { 23, 13, 15 }, { 29, 13, 16 }, { 30, 13, 16 }, { 26, 14, 13 }, { 26, 14, 12 }, { 27, 13, 18 }, { 27, 13, 19 } }) do
    set(b[1], b[2], b[3], "jungle_wood")
  end
  crown(26, 15, { { 13, 3 }, { 14, 5 }, { 15, 6 }, { 16, 5.5 }, { 17, 4 }, { 18, 2.5 } }, { "jungle_leaves", "jungle_leaves", "jungle_leaves", "flowering_azalea_leaves" }, room)
  crown(27, 16, { { 15, 5 }, { 16, 4 } }, "jungle_leaves", room)
  for _, c in ipairs({ { 23, 15, 15 }, { 30, 15, 17 }, { 26, 17, 12 }, { 28, 16, 19 }, { 25, 14, 18 } }) do
    if interior(c[1], c[2]) then set(c[1], c[2], c[3], "shroomlight") end
  end

  -- boulders, bushes, lamp posts
  for _, c in ipairs({ { 20, 9 }, { 21, 9 }, { 32, 19 }, { 22, 27 } }) do set(c[1], F + 2, c[2], rock(c[1], F + 2, c[2])); set(c[1], F + 3, c[2], "moss_carpet") end
  for _, c in ipairs({ { 33, 12 }, { 19, 4 }, { 24, 22 }, { 31, 27 }, { 20, 16 }, { 33, 24 } }) do
    set(c[1], F + 1, c[2], "moss_block"); set(c[1], F + 2, c[2], pick({ "azalea", "flowering_azalea" }, noise(c[1], F, c[2])))
  end
  for _, c in ipairs({ { 21, 6 }, { 30, 11 }, { 22, 20 }, { 32, 22 }, { 25, 26 } }) do
    trunk(c[1], c[2], F + 2, F + 3, "oak_fence"); set(c[1], F + 4, c[2], room.light)
  end
  pad(20, F, 3); pad(23, F, 9); pad(32, F, 14); pad(21, F, 13); pad(29, F, 24); pad(25, F, 21)
  plants(room, { "fern", "fern", "short_grass", "blue_orchid", "allium", "lily_of_the_valley", "short_grass" }, 0.45)

  -- the canopy walk: a platform outside the landing's door, a bridge to a
  -- deck round the tree, fence rails along the open sides
  local walk = {}
  local function plank(x, z) walk[key(x, 0, z)] = true; set(x, U, z, "spruce_planks") end
  for z = 23, 28 do for x = 19, 22 do plank(x, z) end end
  for z = 17, 22 do for x = 20, 21 do plank(x, z) end end
  for x = 22, 24 do for z = 16, 17 do plank(x, z) end end
  for dz = -4, 4 do
    for dx = -4, 4 do
      local x, z = 27 + dx, 16 + dz
      local cx, cz = x + 0.5 - 27, z + 0.5 - 16
      if cx * cx + cz * cz <= 12.5 and not ((x == 26 or x == 27) and (z == 15 or z == 16)) then plank(x, z) end
    end
  end
  for k in pairs(walk) do
    local x, z = k:match("^(-?%d+),0,(-?%d+)$")
    x, z = tonumber(x), tonumber(z)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, nz = x + d[1], z + d[2]
      if not walk[key(nx, 0, nz)] and inRoom(room, nx, nz) and get(nx, U + 1, nz) == nil and get(nx, U, nz) == nil then
        set(nx, U + 1, nz, "spruce_fence")
      end
    end
  end
  for _, c in ipairs({ { 19, 23 }, { 22, 28 }, { 24, 13 }, { 30, 18 } }) do set(c[1], U + 1, c[2], "lantern") end
  -- the trunk and branches pass through the walk
  for z = 15, 16 do for x = 26, 27 do set(x, U, z, "jungle_log") end end
end

---------------------------------------------------------------- outside: deck, steps, trees, overgrowth

do
  local F = G
  fill(DECK.x0, F, DECK.z0, DECK.x1, F, DECK.z1, "oak_planks")
  for x = DECK.x0, DECK.x1 do
    if x < 9 or x > 12 then set(x, F + 1, DECK.z1, x % 4 == 2 and "stripped_oak_log" or "oak_fence") end
  end
  for z = DECK.z0, DECK.z1 do set(DECK.x0, F + 1, z, "oak_fence"); set(DECK.x1, F + 1, z, "oak_fence") end
  for _, x in ipairs({ DECK.x0, 8, 13, DECK.x1 }) do set(x, F + 2, DECK.z1, "lantern") end
  for x = 9, 12 do set(x, F, DECK.z1 + 1, "oak_stairs[facing=north]") end -- steps down to the ground
  for z = DECK.z1 + 2, PLOT.z1 do for x = 9, 12 do set(x, 0, z, "dirt_path") end end
  -- seats and planters along the front wall
  for _, x in ipairs({ 15, 16, 20, 21, 25, 26 }) do set(x, F + 1, DECK.z0, "oak_stairs[facing=north]") end
  for _, x in ipairs({ 7, 14, 17, 19, 22, 24, 27, 29 }) do
    set(x, F + 1, DECK.z0, "moss_block"); set(x, F + 2, DECK.z0, pick({ "azalea", "flowering_azalea" }, noise(x, F, DECK.z0)))
  end
end
-- trees at the front corners and the back
local function tree(x, z, h)
  trunk(x, z, 1, h, "oak_log")
  crown(x, z, { { h - 2, 2.5 }, { h - 1, 3.2 }, { h, 3.2 }, { h + 1, 2.5 }, { h + 2, 1.5 } }, LEAVES)
end
tree(3, 34, 7); tree(33, 34, 8)
-- bushes and flowers on the grass
for z = PLOT.z0, PLOT.z1 do
  for x = PLOT.x0, PLOT.x1 do
    local g = get(x, 0, z)
    if (g == "minecraft:grass_block" or g == "minecraft:moss_block") and get(x, 1, z) == nil then
      local n = noise(x, 1, z)
      if n < 0.06 then set(x, 1, z, pick(LEAVES, noise(z, 1, x)))
      elseif n < 0.2 then set(x, 1, z, pick({ "short_grass", "short_grass", "fern", "poppy", "dandelion", "azure_bluet" }, noise(z, x, 1))) end
    end
  end
end
-- leaves over the vaults, thickest low down, and hanging down the walls
for z = Z0, Z1 do
  for x = 2, 34 do
    for y = BASE, BASE + 10 do
      if shell(x, y) and not inVault(x, y + 1) and get(x, y + 1, z) == nil then
        local chance = 0.45 - (y - BASE) * 0.03
        if noise(x, y, z) < chance then
          set(x, y + 1, z, pick(LEAVES, noise(z, y, x)))
          if noise(z, x, y) < 0.15 then set(x, y + 2, z, pick(LEAVES, noise(y, z, x))) end
        end
      end
    end
  end
end
local function drape(x, z, along)
  local n = noise(x, 50, z)
  if n < 0.35 then
    local len = 1 + math.floor(noise(z, 51, x) * 6)
    for y = BASE, BASE - len + 1, -1 do
      if get(x, y, z) == nil then set(x, y, z, pick(LEAVES, noise(x, y, z))) end
    end
  end
end
for z = Z0, Z1 do drape(1, z); drape(35, z) end
for x = 2, 34 do drape(x, Z0 - 1) end
for x = 2, 34 do if x < 8 or x > 13 then drape(x, Z1 + 1) end end
-- the front doorway kept clear of hanging leaves
for x = 9, 12 do for y = 2, 4 do if get(x, y, Z1 + 1) and get(x, y, Z1 + 1):find("leaves") then set(x, y, Z1 + 1, nil) end end end

---------------------------------------------------------------- checks

-- Water is placed last in its layer: every pool must be held in on all
-- sides and below, so it can't run off. Pasture spots need two clear blocks.
for _, w in ipairs(waters) do
  local x, y, z = w[1], w[2], w[3]
  for _, d in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, -1, 0 } }) do
    if get(x + d[1], y + d[2], z + d[3]) == nil then error(("water at %d %d %d can run off"):format(x, y, z), 0) end
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
