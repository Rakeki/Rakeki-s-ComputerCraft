-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Deep Hold: a home for Create contraptions and a train station, for the
-- 57x57x30 hole 'excavate deephold deep' digs just above bedrock. Built
-- rustic: rough deepslate walls framed in spruce, timber beams under the
-- ceiling, plank floors upstairs and on the platforms, fences, barrels.
--
--   The contraption hall (the north 33 blocks): 55 x 33 and 27 high, its
--   stone floor left clear and marked out in bays by strips of spruce,
--   sea lanterns where the strips cross so nothing spawns between machines,
--   a grid of timber beams under the ceiling for rope pulleys and gantries,
--   a water pool for pumps, and a plank gallery round it halfway up on log
--   posts, reached by a Create elevator in a glass shaft on its west side.
--
--   The station (the south 21 blocks): two through tracks east-west, out
--   through tunnel mouths in both side walls, with a plank platform each
--   side and an island between, benches and lantern posts, timber beams on
--   log pillars, and a footbridge over both tracks. A cargo door 11 wide
--   and two side doors lead from the north platform into the hall.
--
--   The upper hall, over the station: 55 x 21 and 12 high for more
--   machines, a loading hatch over each track at both ends (for chutes and
--   funnels down to the trains), and a balcony looking out over the hall.
--   It opens on the hall's gallery.
--
-- Tracks and station blocks aren't placed (the turtle can't turn a track
-- the right way): lay track along the gravel and put your station on it.
-- The tunnel mouths open on the rock; dig the line out from there.
--
-- Beams are spruce wood (bark on every side), not logs: a turtle places
-- every log upright, and wood looks the same whichever way it stands.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot in the
-- hall (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is the ceiling deck, one below the hole's ceiling:
-- the builder stands a block above what it places. Built inside the dug
-- hole, so "clear" is false.
local W, L, H = 57, 57, 30
local TOP = H - 2 -- the ceiling deck
local N = W - 1 -- the east and south walls
local C = 28 -- the middle (x)
local HOME = { x = 24, z = 26 }
local hold = { name = "Deep Hold", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local HALL_Z = 33 -- the contraption hall runs z 1..HALL_Z
local DIVIDE = HALL_Z + 1 -- the wall between the hall and the station
local UPPER = 15 -- the gallery's floor, the station's ceiling and the upper hall's floor
local GALLERY = 3 -- gallery width
local BAYS = { 10, 19, 28, 37, 46 } -- x of the bay lines, beams and pilasters
local BAY_Z = { 12, 23 } -- z of the hall's cross lines (and its cross beams)
local LIGHT_EVERY = 12 -- spacing of the wall and ceiling lights
local POST_EVERY = 6 -- spacing of the log posts framing the outer walls
local STATION_LIGHTS = { 37, 46, 54 } -- z of the lights in the station's ceiling, one row per platform
local TRACKS = { 41, 50 } -- each track's z; it keeps 2 clear either side
local ISLAND = { 44, 47 } -- the island platform between them
local BRIDGE = { 27, 29 } -- the footbridge's x
local BRIDGE_Y = 7 -- its deck: trains up to 5 blocks tall pass under
local HATCHES = { 14, 42 } -- x of the middle of each loading hatch
local TRACK = nil -- set to "create:track" to have the turtle lay the track too (check its direction)

local BRICKS = "minecraft:deepslate_bricks"
local CRACKED = "minecraft:cracked_deepslate_bricks"
local COBBLED = "minecraft:cobbled_deepslate"
local TILES = "minecraft:deepslate_tiles"
local CTILES = "minecraft:cracked_deepslate_tiles"
local POLISHED = "minecraft:polished_deepslate"
local LOG = "minecraft:spruce_log" -- posts and pillars (upright)
local TIMBER = "minecraft:spruce_wood" -- beams, bands and lintels
local CAP = "minecraft:stripped_spruce_wood" -- post heads and trim
local PLANKS = "minecraft:spruce_planks"
local RAIL = "minecraft:spruce_fence"
local FLOOR = "minecraft:polished_deepslate" -- the hall floor, mixed with tiles
local EDGE = "minecraft:stripped_spruce_wood" -- the platform edge, paler than the planks
local BALLAST = "minecraft:gravel"
local PIT = "minecraft:cobbled_deepslate"
local LIGHT = "minecraft:sea_lantern" -- every light: wall, floor and ceiling
local LANTERN = "minecraft:lantern"
local BENCH = "minecraft:spruce_stairs"
local BARREL = "minecraft:barrel"
local WATER = "minecraft:water"
-- a Create block; swap in the vanilla one in the comment without Create
local WINDOW = "create:framed_glass" -- or "minecraft:glass"

local abs = math.abs
local grid = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function set(x, y, z, block) grid[key(x, y, z)] = block end
local function get(x, y, z) return grid[key(x, y, z)] end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
-- rough walls: bricks with cracked ones and patches of cobble
local function bricks(x, y, z)
  local n = noise(x, y, z)
  return n < 0.12 and CRACKED or n < 0.27 and COBBLED or BRICKS
end
local function tiles(x, y, z) return noise(x, y, z) < 0.1 and CTILES or TILES end
local function floorStone(x, z)
  local n = noise(x, 0, z)
  return n < 0.35 and tiles(x, 0, z) or n < 0.45 and COBBLED or FLOOR
end
local function among(list, v)
  for _, w in ipairs(list) do if w == v then return true end end
  return false
end
local function bench(dir) return BENCH .. "[facing=" .. dir .. "]" end
local function steps(dir) return "minecraft:spruce_stairs[facing=" .. dir .. "]" end

-- what part of the station a z is in
local function stationPart(z)
  for _, t in ipairs(TRACKS) do
    if abs(z - t) <= 2 then return "track", t end
  end
  if z >= ISLAND[1] and z <= ISLAND[2] then return "island" end
  return "platform"
end

---------------------------------------------------------------- the shell

-- outer walls: rough stone framed in spruce (log posts, a timber band at
-- the upper floor and under the ceiling), a cobble skirting, and lights low
-- down and in the upper hall between the posts
for y = 0, TOP do
  for z = 0, N do
    for x = 0, N do
      if x == 0 or z == 0 or x == N or z == N then
        local along = (x == 0 or x == N) and z or x
        local corner = (x == 0 or x == N) and (z == 0 or z == N)
        local block = bricks(x, y, z)
        if y <= 1 then block = COBBLED end
        if (y == 5 or y == 21) and along % LIGHT_EVERY == 1 and along > 0 and along < N then block = LIGHT end
        if y >= 1 and (corner or along % POST_EVERY == 4) then block = LOG end
        if y == UPPER or y == TOP - 1 then block = TIMBER end
        set(x, y, z, block)
      end
    end
  end
end

-- the ceiling deck, lights every LIGHT_EVERY
for z = 1, N - 1 do
  for x = 1, N - 1 do
    set(x, TOP, z, (x % LIGHT_EVERY == 4 and z % LIGHT_EVERY == 4) and LIGHT or tiles(x, TOP, z))
  end
end

-- timber beams under the deck: along every bay line, hall and upper hall,
-- and across the hall on its cross lines
for _, x in ipairs(BAYS) do
  for z = 1, N - 1 do
    if z ~= DIVIDE then set(x, TOP - 1, z, TIMBER) end
  end
end
for _, z in ipairs(BAY_Z) do
  for x = 1, N - 1 do set(x, TOP - 1, z, TIMBER) end
end

---------------------------------------------------------------- the contraption hall

-- stone floor, bay lines in spruce strips, a sea lantern where they cross
for z = 1, HALL_Z do
  for x = 1, N - 1 do
    local block = floorStone(x, z)
    if among(BAYS, x) or among(BAY_Z, z) then block = CAP end
    if among(BAYS, x) and among(BAY_Z, z) then block = LIGHT end
    set(x, 0, z, block)
  end
end

-- the plank gallery round the hall, fenced on its inner edge
local function onGallery(x, z)
  return x <= GALLERY or x >= N - GALLERY or z <= GALLERY or z > HALL_Z - GALLERY
end
for z = 1, HALL_Z do
  for x = 1, N - 1 do
    if onGallery(x, z) then
      local inner = (x == GALLERY or x == N - GALLERY) and z > GALLERY and z <= HALL_Z - GALLERY
        or (z == GALLERY or z == HALL_Z - GALLERY + 1) and x > GALLERY and x < N - GALLERY
      -- planks, edged in timber along the railing
      set(x, UPPER, z, inner and TIMBER or PLANKS)
      if inner then set(x, UPPER + 1, z, RAIL) end
    end
  end
end
-- lanterns on the railing over each bay line
for _, x in ipairs(BAYS) do
  set(x, UPPER + 2, GALLERY, LANTERN)
  set(x, UPPER + 2, HALL_Z - GALLERY + 1, LANTERN)
end
for _, z in ipairs(BAY_Z) do
  set(GALLERY, UPPER + 2, z, LANTERN)
  set(N - GALLERY, UPPER + 2, z, LANTERN)
end
-- log posts under the gallery's inner edge, on a stone foot
local function post(x, z)
  for y = 1, UPPER - 1 do
    set(x, y, z, y == 1 and COBBLED or y == UPPER - 1 and CAP or LOG)
  end
end
for _, z in ipairs(BAY_Z) do
  post(GALLERY, z)
  post(N - GALLERY, z)
end
for _, x in ipairs({ BAYS[1], BAYS[2], BAYS[4], BAYS[5] }) do
  post(x, GALLERY)
  post(x, HALL_Z - GALLERY + 1)
end

-- the elevator up to the gallery: a Create elevator in a timber-framed
-- glass shaft against the gallery's west edge. The cabin (a plank floor
-- flush with the hall floor, fence corners, a plank roof) waits at the
-- bottom; it opens east onto the hall floor and west onto the gallery.
-- An elevator contact in the shaft's north wall at each floor and a
-- redstone contact on the cabin at the same height line it up; the
-- elevator pulley hangs over the cabin's top stop, a hole beside it for
-- the shaft that turns it. Glue the cabin and give the pulley rotation.
local SHAFT = { x0 = GALLERY, x1 = GALLERY + 4, z0 = BAY_Z[1], z1 = BAY_Z[1] + 4 } -- its walls; 3 x 3 inside
local CAB_H = 4 -- the cabin's roof above its floor
local PULLEY_Y = UPPER + CAB_H + 1 -- right over the roof at the top stop
local SHAFT_TOP = PULLEY_Y + 1 -- the shaft's cap
local SX, SZ = math.floor((SHAFT.x0 + SHAFT.x1) / 2), math.floor((SHAFT.z0 + SHAFT.z1) / 2) -- its middle
local function shaftDoor(x, y, z)
  local across = z > SHAFT.z0 and z < SHAFT.z1
  return across and (x == SHAFT.x1 and y >= 1 and y <= 3 or x == SHAFT.x0 and y > UPPER and y <= UPPER + 3)
end
for y = 1, SHAFT_TOP do
  for z = SHAFT.z0, SHAFT.z1 do
    for x = SHAFT.x0, SHAFT.x1 do
      local wall = x == SHAFT.x0 or x == SHAFT.x1 or z == SHAFT.z0 or z == SHAFT.z1
      local corner = (x == SHAFT.x0 or x == SHAFT.x1) and (z == SHAFT.z0 or z == SHAFT.z1)
      local block = nil
      if y == SHAFT_TOP then block = wall and TIMBER or PLANKS
      elseif corner then block = LOG
      elseif wall then
        block = (y == UPPER or y == 4 or y == UPPER + 4) and TIMBER or WINDOW
        if shaftDoor(x, y, z) then block = nil end
      end
      -- the west wall at the gallery floor is the gallery's own edge
      if x == SHAFT.x0 and y == UPPER and not corner then block = TIMBER end
      set(x, y, z, block)
    end
  end
end
-- the cabin, at the bottom
for z = SHAFT.z0 + 1, SHAFT.z1 - 1 do
  for x = SHAFT.x0 + 1, SHAFT.x1 - 1 do
    set(x, 0, z, PLANKS)
    set(x, CAB_H, z, PLANKS)
    if (x == SHAFT.x0 + 1 or x == SHAFT.x1 - 1) and (z == SHAFT.z0 + 1 or z == SHAFT.z1 - 1) then
      for y = 1, CAB_H - 1 do set(x, y, z, RAIL) end
    end
  end
end
set(SX, 1, SHAFT.z0 + 1, "create:redstone_contact[facing=north]")
set(SX, 1, SHAFT.z0, "create:elevator_contact[facing=south]")
set(SX, UPPER + 1, SHAFT.z0, "create:elevator_contact[facing=south]")
set(SX, PULLEY_Y, SZ, "create:elevator_pulley[facing=east]")
set(SHAFT.x1, PULLEY_Y, SZ, nil) -- the hole for its drive shaft

-- a water pool for pumps and hose pulleys in the south-east corner, timber rim
for z = 25, 29 do
  for x = 47, 51 do
    local edge = x == 47 or x == 51 or z == 25 or z == 29
    set(x, 1, z, edge and CAP or WATER)
  end
end

-- barrels stacked under the gallery against the north wall, between the posts
for x = 7, N - 7, 12 do
  set(x, 1, 1, BARREL)
  set(x + 1, 1, 1, BARREL)
  set(x, 2, 1, BARREL)
end

---------------------------------------------------------------- the dividing wall

local CARGO = { C - 5, C + 5 } -- the cargo door's x
local SIDE_DOORS = { 12, 44 } -- the side doors' middles
local UPPER_DOORS = { 9, 47 } -- the upper hall's doors' middles
for y = 0, TOP do
  for x = 1, N - 1 do
    local block = bricks(x, y, DIVIDE)
    if y <= 1 then block = COBBLED end
    if among(BAYS, x) and y >= 1 then block = (y == 5 or y == 21) and LIGHT or LOG end
    if y == UPPER or y == TOP - 1 then block = TIMBER end
    local inCargo = x >= CARGO[1] and x <= CARGO[2]
    -- each ground door: a threshold at platform height, then the opening
    -- under a timber lintel
    if inCargo then
      if y == 1 then block = PLANKS
      elseif y <= 10 and y > 1 then block = nil
      elseif y == 11 then block = TIMBER
      elseif y >= 12 and y <= 13 then block = WINDOW end
    end
    for _, d in ipairs(SIDE_DOORS) do
      if abs(x - d) <= 1 then
        if y == 1 then block = PLANKS
        elseif y > 1 and y <= 5 then block = nil
        elseif y == 6 then block = TIMBER end
      end
    end
    for _, d in ipairs(UPPER_DOORS) do
      if abs(x - d) <= 1 and y > UPPER and y <= UPPER + 4 then block = nil end
      if abs(x - d) <= 1 and y == UPPER + 5 then block = TIMBER end
    end
    -- the balcony over the cargo door, fenced
    if inCargo and y > UPPER and y <= UPPER + 7 then block = y == UPPER + 1 and RAIL or nil end
    if inCargo and y == UPPER + 8 then block = TIMBER end
    set(x, y, DIVIDE, block)
  end
end
-- a step up from the hall floor to the platform in each doorway
local function inDoor(x)
  if x >= CARGO[1] and x <= CARGO[2] then return true end
  for _, d in ipairs(SIDE_DOORS) do
    if abs(x - d) <= 1 then return true end
  end
  return false
end
for x = 1, N - 1 do
  if inDoor(x) then set(x, 1, HALL_Z, steps("south")) end
end

---------------------------------------------------------------- the station

for z = DIVIDE + 1, N - 1 do
  local part, t = stationPart(z)
  for x = 1, N - 1 do
    if part == "track" then
      set(x, 0, z, abs(z - t) <= 1 and BALLAST or PIT)
      if TRACK and z == t then set(x, 1, z, TRACK) end
    else
      set(x, 0, z, COBBLED)
      -- the plank platform; a pale timber strip along the edge by a track
      local edge = stationPart(z - 1) == "track" or stationPart(z + 1) == "track"
      set(x, 1, z, edge and EDGE or PLANKS)
    end
  end
end
-- the tunnel mouths, both ends of both tracks: a timber frame round each
for _, t in ipairs(TRACKS) do
  for _, x in ipairs({ 0, N }) do
    for z = t - 2, t + 2 do
      for y = 1, 7 do set(x, y, z, nil) end
      set(x, 8, z, TIMBER)
    end
    for y = 1, 8 do
      set(x, y, t - 3, LOG)
      set(x, y, t + 3, LOG)
    end
    if TRACK then set(x, 1, t, TRACK) end
  end
end

-- log pillars on the island carrying timber beams across the station
-- the middle two stand back from the bay lines, so the footbridge stair
-- up from the island (its foot just west of the bridge) has room
local PILLARS = { BAYS[1], C - 12, C + 12, BAYS[5] }
for _, x in ipairs(PILLARS) do
  for z = ISLAND[1] + 1, ISLAND[2] - 1 do
    for y = 2, UPPER - 1 do set(x, y, z, (y == 2 or y == UPPER - 1) and CAP or LOG) end
  end
  for z = DIVIDE + 1, N - 1 do set(x, UPPER - 1, z, TIMBER) end
end

-- benches and lantern posts: back to back down the island, against the
-- walls on the side platforms; barrels by the benches on the side platforms
for x = 3, N - 3 do
  local nearPillar = false
  for _, p in ipairs(PILLARS) do nearPillar = nearPillar or abs(x - p) <= 1 end
  local nearBridge = x >= BRIDGE[1] - BRIDGE_Y - 1 and x <= BRIDGE[2] + 2
  if not nearPillar and not nearBridge then
    local spot = (x % 9) -- two benches, then a lantern post, then a gap
    if spot == 3 or spot == 4 then
      set(x, 2, ISLAND[1] + 1, bench("south"))
      set(x, 2, ISLAND[2] - 1, bench("north"))
      if not inDoor(x) then set(x, 2, DIVIDE + 1, bench("north")) end
      set(x, 2, N - 1, bench("south"))
    elseif spot == 6 then
      set(x, 2, ISLAND[1] + 1, RAIL)
      set(x, 3, ISLAND[1] + 1, LANTERN)
      set(x, 2, ISLAND[2] - 1, RAIL)
      set(x, 3, ISLAND[2] - 1, LANTERN)
      if not inDoor(x) then set(x, 2, DIVIDE + 1, BARREL) end
      set(x, 2, N - 1, BARREL)
    end
  end
end

-- the footbridge: stairs up from each platform to a deck over both tracks,
-- the walkway BRIDGE[1]..BRIDGE[2] with a fenced edge either side
local DECK_X = { BRIDGE[1] - 1, BRIDGE[2] + 1 }
local function bridgeStair(z0, z1)
  for i = 0, BRIDGE_Y - 2 do
    local x = DECK_X[1] - (BRIDGE_Y - 1) + i
    for z = z0, z1 do
      for y = 2, 1 + i do set(x, y, z, COBBLED) end
      set(x, 2 + i, z, i == BRIDGE_Y - 2 and PLANKS or steps("east"))
    end
  end
end
bridgeStair(DIVIDE + 2, DIVIDE + 3)
bridgeStair(ISLAND[1] + 1, ISLAND[2] - 1)
bridgeStair(N - 2, N - 1)
local function landing(z) return (z >= DIVIDE + 2 and z <= DIVIDE + 3) or (z > ISLAND[1] and z < ISLAND[2]) or z >= N - 2 end
for z = DIVIDE + 1, N - 1 do
  for x = DECK_X[1], DECK_X[2] do set(x, BRIDGE_Y, z, z % 4 == 0 and TIMBER or PLANKS) end
  if not landing(z) then set(DECK_X[1], BRIDGE_Y + 1, z, RAIL) end
  set(DECK_X[2], BRIDGE_Y + 1, z, RAIL)
end
-- log piers under it at the platform edges, clear of the cargo door
for _, z in ipairs({ DIVIDE + 4, N - 1 }) do
  for x = BRIDGE[1], BRIDGE[2] do
    for y = 2, BRIDGE_Y - 1 do set(x, y, z, LOG) end
  end
end
for x = BRIDGE[1], BRIDGE[2] do
  for _, z in ipairs(ISLAND) do
    for y = 2, BRIDGE_Y - 1 do set(x, y, z, LOG) end
  end
end

-- the station's ceiling is the upper hall's plank floor: timber along the
-- bay lines, a row of lights over each platform, a hatch railed off over
-- each track at both ends
for z = DIVIDE + 1, N - 1 do
  for x = 1, N - 1 do
    local block = among(BAYS, x) and TIMBER or PLANKS
    if among(STATION_LIGHTS, z) and x % LIGHT_EVERY == 4 then block = LIGHT end
    set(x, UPPER, z, block)
  end
end
for _, hx in ipairs(HATCHES) do
  for _, t in ipairs(TRACKS) do
    for z = t - 2, t + 2 do
      for x = hx - 2, hx + 2 do
        if abs(x - hx) <= 1 and abs(z - t) <= 1 then
          set(x, UPPER, z, nil)
        else
          set(x, UPPER + 1, z, RAIL)
        end
      end
    end
  end
end

---------------------------------------------------------------- out

-- the builder's home column, and the floor under its two chests, stay empty
for y = 0, TOP do set(HOME.x, y, HOME.z, nil) end
set(HOME.x, 0, HOME.z - 1, nil)
set(HOME.x + 1, 0, HOME.z, nil)

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = get(x, y, z)
      if block then hold.blocks[#hold.blocks + 1] = { x, y, z, block } end
    end
  end
end
return hold
