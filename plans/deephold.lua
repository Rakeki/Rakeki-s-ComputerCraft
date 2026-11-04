-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Deep Hold: a home for Create contraptions and a train station, for the
-- 57x57x30 hole 'excavate deephold deep' digs just above bedrock.
--
--   The contraption hall (the north 33 blocks): 55 x 33 and 27 high, its
--   floor left clear and marked out in bays, lights set into the floor so
--   nothing spawns between machines, iron beams under the ceiling for rope
--   pulleys and gantries, a water pool for pumps, and a gallery round it
--   halfway up, reached by two long stairs on the north wall.
--
--   The station (the south 21 blocks): two through tracks east-west, out
--   through tunnel mouths in both side walls, with a platform each side and
--   an island between, benches and lanterns, iron beams on pillars, and a
--   footbridge over both tracks. A cargo door 11 wide and two side doors
--   lead from the north platform into the hall.
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
local BAY_Z = { 12, 23 } -- z of the hall's cross lines
local FLOOR_LIGHTS = { 8, 15, 22, 29 } -- z of the lights in the hall floor, on each bay line
local TRACKS = { 41, 50 } -- each track's z; it keeps 2 clear either side
local ISLAND = { 44, 47 } -- the island platform between them
local BRIDGE = { 27, 29 } -- the footbridge's x
local BRIDGE_Y = 7 -- its deck: trains up to 5 blocks tall pass under
local HATCHES = { 14, 42 } -- x of the middle of each loading hatch
local TRACK = nil -- set to "create:track" to have the turtle lay the track too (check its direction)

local BRICKS = "minecraft:deepslate_bricks"
local CRACKED = "minecraft:cracked_deepslate_bricks"
local TILES = "minecraft:deepslate_tiles"
local CTILES = "minecraft:cracked_deepslate_tiles"
local POLISHED = "minecraft:polished_deepslate"
local CHISELED = "minecraft:chiseled_deepslate"
local RAIL = "minecraft:polished_deepslate_wall"
local FLOOR = "minecraft:smooth_stone"
local PLATFORM = "minecraft:polished_andesite"
local EDGE = "minecraft:yellow_concrete" -- the platform edge
local BALLAST = "minecraft:gravel"
local PIT = "minecraft:smooth_basalt"
local GLOW = "minecraft:shroomlight" -- ceiling lights
local LIGHT = "minecraft:ochre_froglight" -- wall and floor lights
local LANTERN = "minecraft:lantern"
local BENCH = "minecraft:spruce_stairs"
local WATER = "minecraft:water"
-- Create blocks; swap in the vanilla ones in the comments without Create
local BEAM = "create:industrial_iron_block" -- or "minecraft:polished_basalt"
local CAP = "create:andesite_casing" -- or "minecraft:polished_andesite"
local WINDOW = "create:framed_glass" -- or "minecraft:glass"

local abs = math.abs
local grid = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function set(x, y, z, block) grid[key(x, y, z)] = block end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function bricks(x, y, z) return noise(x, y, z) < 0.1 and CRACKED or BRICKS end
local function tiles(x, y, z) return noise(x, y, z) < 0.1 and CTILES or TILES end
local function among(list, v)
  for _, w in ipairs(list) do if w == v then return true end end
  return false
end
local function bench(dir) return BENCH .. "[facing=" .. dir .. "]" end
local function steps(dir) return "minecraft:deepslate_brick_stairs[facing=" .. dir .. "]" end

-- what part of the station a z is in
local function stationPart(z)
  for _, t in ipairs(TRACKS) do
    if abs(z - t) <= 2 then return "track", t end
  end
  if z >= ISLAND[1] and z <= ISLAND[2] then return "island" end
  return "platform"
end

---------------------------------------------------------------- the shell

-- outer walls: a band at the upper floor, lights at three heights
for y = 0, TOP do
  for z = 0, N do
    for x = 0, N do
      if x == 0 or z == 0 or x == N or z == N then
        local along = (x == 0 or x == N) and z or x
        local block = y == UPPER and POLISHED or bricks(x, y, z)
        if (y == 5 or y == 12 or y == 21) and along % 6 == 1 and along > 0 and along < N then block = LIGHT end
        set(x, y, z, block)
      end
    end
  end
end

-- the ceiling deck, lights every 6
for z = 1, N - 1 do
  for x = 1, N - 1 do
    set(x, TOP, z, (x % 6 == 4 and z % 6 == 4) and GLOW or tiles(x, TOP, z))
  end
end

-- iron beams under the deck along every bay line, hall and upper hall
for _, x in ipairs(BAYS) do
  for z = 1, N - 1 do
    if z ~= DIVIDE then set(x, TOP - 1, z, BEAM) end
  end
end

---------------------------------------------------------------- the contraption hall

for z = 1, HALL_Z do
  for x = 1, N - 1 do
    local line = among(BAYS, x) or among(BAY_Z, z)
    local block = line and POLISHED or FLOOR
    if among(BAYS, x) and among(FLOOR_LIGHTS, z) then block = LIGHT end
    set(x, 0, z, block)
  end
end

-- the gallery round the hall, railed on its inner edge
local function onGallery(x, z)
  return x <= GALLERY or x >= N - GALLERY or z <= GALLERY or z > HALL_Z - GALLERY
end
-- where the two hall stairs arrive (the railing leaves a gap)
local STAIR_TOPS = { C - 4, C + 4 }
for z = 1, HALL_Z do
  for x = 1, N - 1 do
    if onGallery(x, z) then
      set(x, UPPER, z, tiles(x, UPPER, z))
      local inner = (x == GALLERY or x == N - GALLERY) and z > GALLERY and z <= HALL_Z - GALLERY
        or (z == GALLERY or z == HALL_Z - GALLERY + 1) and x > GALLERY and x < N - GALLERY
      local gap = z == GALLERY and (abs(x - STAIR_TOPS[1]) <= 1 or abs(x - STAIR_TOPS[2]) <= 1)
      if inner and not gap then set(x, UPPER + 1, z, RAIL) end
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
-- posts under the gallery's inner edge
local function post(x, z)
  for y = 1, UPPER - 1 do set(x, y, z, y == UPPER - 1 and CAP or POLISHED) end
end
for _, z in ipairs(BAY_Z) do
  post(GALLERY, z)
  post(N - GALLERY, z)
end
for _, x in ipairs({ BAYS[1], BAYS[2], BAYS[4], BAYS[5] }) do
  post(x, GALLERY)
  post(x, HALL_Z - GALLERY + 1)
end

-- two long stairs up the north wall to the gallery, meeting in the middle
local function hallStair(x0, dir)
  local facing = dir > 0 and "east" or "west"
  for i = 0, UPPER - 1 do
    local x = x0 + dir * i
    for z = GALLERY + 1, GALLERY + 2 do
      for y = 1, i do set(x, y, z, BRICKS) end
      set(x, i + 1, z, i == UPPER - 1 and POLISHED or steps(facing))
    end
    if i < UPPER - 1 then set(x, i + 2, GALLERY + 3, RAIL) end
  end
end
hallStair(STAIR_TOPS[1] - (UPPER - 1), 1)
hallStair(STAIR_TOPS[2] + (UPPER - 1), -1)

-- a water pool for pumps and hose pulleys in the south-east corner
for z = 25, 29 do
  for x = 47, 51 do
    local edge = x == 47 or x == 51 or z == 25 or z == 29
    set(x, 1, z, edge and POLISHED or WATER)
  end
end

---------------------------------------------------------------- the dividing wall

local CARGO = { C - 5, C + 5 } -- the cargo door's x
local SIDE_DOORS = { 12, 44 } -- the side doors' middles
local UPPER_DOORS = { 9, 47 } -- the upper hall's doors' middles
for y = 0, TOP do
  for x = 1, N - 1 do
    local block = bricks(x, y, DIVIDE)
    if y == UPPER then block = POLISHED
    elseif among(BAYS, x) then block = (y == 5 or y == 21) and LIGHT or POLISHED end
    local inCargo = x >= CARGO[1] and x <= CARGO[2]
    -- each ground door: a threshold at platform height, then the opening
    if inCargo then
      if y == 1 then block = PLATFORM
      elseif y <= 10 and y > 1 then block = nil
      elseif y == 11 then block = CHISELED
      elseif y >= 12 and y <= 13 then block = WINDOW end
    end
    for _, d in ipairs(SIDE_DOORS) do
      if abs(x - d) <= 1 then
        if y == 1 then block = PLATFORM
        elseif y > 1 and y <= 5 then block = nil
        elseif y == 6 then block = CHISELED end
      end
    end
    for _, d in ipairs(UPPER_DOORS) do
      if abs(x - d) <= 1 and y > UPPER and y <= UPPER + 4 then block = nil end
      if abs(x - d) <= 1 and y == UPPER + 5 then block = CHISELED end
    end
    -- the balcony over the cargo door, railed
    if inCargo and y > UPPER and y <= UPPER + 7 then block = y == UPPER + 1 and RAIL or nil end
    if inCargo and y == UPPER + 8 then block = CHISELED end
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
      set(x, 0, z, POLISHED)
      -- the platform's top; yellow along the edge by a track
      local edge = stationPart(z - 1) == "track" or stationPart(z + 1) == "track"
      set(x, 1, z, edge and EDGE or PLATFORM)
    end
  end
end
-- the tunnel mouths, both ends of both tracks
for _, t in ipairs(TRACKS) do
  for _, x in ipairs({ 0, N }) do
    for z = t - 2, t + 2 do
      for y = 1, 7 do set(x, y, z, nil) end
      set(x, 8, z, CHISELED)
    end
    for y = 1, 8 do
      set(x, y, t - 3, POLISHED)
      set(x, y, t + 3, POLISHED)
    end
    if TRACK then set(x, 1, t, TRACK) end
  end
end

-- pillars on the island carrying iron beams across the station
local PILLARS = { BAYS[1], BAYS[2], BAYS[4], BAYS[5] }
for _, x in ipairs(PILLARS) do
  for z = ISLAND[1] + 1, ISLAND[2] - 1 do
    for y = 2, UPPER - 1 do set(x, y, z, (y == 2 or y == UPPER - 1) and CAP or POLISHED) end
  end
  for z = DIVIDE + 1, N - 1 do set(x, UPPER - 1, z, BEAM) end
end

-- benches and lanterns: back to back down the island, against the walls on the side platforms
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
    end
  end
end

-- the footbridge: stairs up from each platform to a deck over both tracks,
-- the walkway BRIDGE[1]..BRIDGE[2] with a railed edge either side
local DECK_X = { BRIDGE[1] - 1, BRIDGE[2] + 1 }
local function bridgeStair(z0, z1)
  for i = 0, BRIDGE_Y - 2 do
    local x = DECK_X[1] - (BRIDGE_Y - 1) + i
    for z = z0, z1 do
      for y = 2, 1 + i do set(x, y, z, BRICKS) end
      set(x, 2 + i, z, i == BRIDGE_Y - 2 and POLISHED or steps("east"))
    end
  end
end
bridgeStair(DIVIDE + 2, DIVIDE + 3)
bridgeStair(ISLAND[1] + 1, ISLAND[2] - 1)
bridgeStair(N - 2, N - 1)
local function landing(z) return (z >= DIVIDE + 2 and z <= DIVIDE + 3) or (z > ISLAND[1] and z < ISLAND[2]) or z >= N - 2 end
for z = DIVIDE + 1, N - 1 do
  for x = DECK_X[1], DECK_X[2] do set(x, BRIDGE_Y, z, z % 4 == 0 and CAP or TILES) end
  if not landing(z) then set(DECK_X[1], BRIDGE_Y + 1, z, RAIL) end
  set(DECK_X[2], BRIDGE_Y + 1, z, RAIL)
end
-- piers under it at the platform edges, clear of the cargo door
for _, z in ipairs({ DIVIDE + 4, N - 1 }) do
  for x = BRIDGE[1], BRIDGE[2] do
    for y = 2, BRIDGE_Y - 1 do set(x, y, z, POLISHED) end
  end
end
for x = BRIDGE[1], BRIDGE[2] do
  for z = ISLAND[1], ISLAND[2] do
    for y = 2, BRIDGE_Y - 1 do
      if z == ISLAND[1] or z == ISLAND[2] then set(x, y, z, POLISHED) end
    end
  end
end

-- the station's ceiling is the upper hall's floor: lights over the
-- platforms, a hatch railed off over each track at both ends
for z = DIVIDE + 1, N - 1 do
  local part = stationPart(z)
  for x = 1, N - 1 do
    local block = among(BAYS, x) and POLISHED or FLOOR
    if part ~= "track" and x % 6 == 4 then block = GLOW end
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
      local block = grid[key(x, y, z)]
      if block then hold.blocks[#hold.blocks + 1] = { x, y, z, block } end
    end
  end
end
return hold
