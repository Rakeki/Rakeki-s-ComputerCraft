-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Deep Hold: a home for Create factories and an underground subway, for
-- the 69x89x30 hole 'excavate deephold deep' digs just above bedrock. Built
-- rustic: rough deepslate walls framed in spruce, timber beams under the
-- ceiling, plank floors upstairs and on the platforms, fences, barrels.
-- It runs north-south, in three strips side by side:
--
--   The works (the west 26 blocks): six cells along the west wall in two
--   tiers, each 11 deep with a framed-glass front and a door, for a
--   machine line of its own; the logistics lane in front of them (a spruce
--   strip down the floor for a belt or chain conveyor, a plank walkway
--   above for the upper tier); and the assembly hall, 27 high, for big
--   contraptions, with timber beams under the ceiling for pulleys and
--   gantries, a sea lantern grid in its floor and a pump pool.
--
--   The concourse (down the middle): where both elevators come down from
--   the surface. Their shafts (spruce and glass, open at the top) stand on
--   the centre line, one near each end; each opens west and east at the
--   floor and at the balconies, which run the length of the hall at the
--   upper floor on log posts. A checkered floor, timber arches overhead, a
--   lit plinth in the middle, and arches and doors into the works and the
--   station on both floors.
--
--   The station (the east 26 blocks): two subway lines running north-south
--   in from the rock, Line A through a timber portal in the north wall and
--   Line B through one in the south wall, with a plank platform each side
--   and an island between (benches, lantern posts, log pillars carrying
--   timber beams), a footbridge over both, and six freight docks behind
--   the far platform. Over it the machine hall, 12 high, with a loading
--   hatch over each track at both ends for chutes and funnels down to the
--   trains.
--
-- The elevators aren't built: they come down from above. Each shaft is
-- clear inside (7 x 5, its walls round it) from the floor up through the
-- ceiling deck; dig on up from there to the surface, and put an elevator
-- contact by a door at each floor. Tracks and station blocks aren't placed
-- (the turtle can't turn a track the right way): lay track along the
-- gravel and put your station on it. The tunnel portals open on the rock;
-- dig the line out from there.
--
-- Beams are spruce wood (bark on every side), not logs: a turtle places
-- every log upright, and wood looks the same whichever way it stands.
--
-- Coordinates are the hole's: x east and z south from its north-west
-- corner, y 0 its floor. hole is the size to dig; home is the builder
-- turtle's spot in the assembly hall (facing south, chests behind and to
-- its left), which the plan keeps clear. The top layer is the ceiling deck,
-- one below the hole's ceiling: the builder stands a block above what it
-- places. Built inside the dug hole, so "clear" is false.
local W, L, H = 69, 89, 30
local TOP = H - 2 -- the ceiling deck
local NX, NZ = W - 1, L - 1 -- the east and south walls
local MID = 44 -- the middle (z)
local HOME = { x = 20, z = 33 }
local hold = { name = "Deep Hold", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local UPPER = 15 -- the upper floor: cells' second tier, balconies, the machine hall
local BAND = TOP - 1 -- the timber band and beams under the deck
local LIGHT_EVERY = 12 -- spacing of the wall and ceiling lights
local POST_EVERY = 6 -- spacing of the log posts framing the walls

-- across (x): the strips
local CELL_X = 11 -- the cells run x 1..CELL_X
local FRONT = 12 -- the cells' glass front
local LANE = { 13, 15 } -- the logistics lane
local HALL = { 16, 25 } -- the assembly hall
local WEST_WALL, EAST_WALL = 26, 42 -- the concourse's walls
local BALCONY = 3 -- balcony width, each side of the concourse
local STATION = { 43, 62 } -- platforms and tracks
local DOCK_WALL = 63 -- the freight docks behind it run to the east wall
-- along (z)
local DIVIDERS = { 14, 29, 44, 59, 74 } -- the cell walls (and the docks')
local BEAMS = { 9, 23, 37, 51, 65, 79 } -- z of the ceiling beams over the works and machine hall
local HALL_LINES = { 23, 44, 65 } -- z of the hall's floor strips
local HALL_LINE_X = 21 -- and the one along it

-- the elevators: the space each cabin passes through, x0..x1, z0..z1
local LIFTS = {
  { x0 = 31, x1 = 37, z0 = 17, z1 = 21 },
  { x0 = 31, x1 = 37, z0 = 67, z1 = 71 },
}
local DOOR_LOW, DOOR_HIGH = 1, UPPER + 1 -- the bottom of each floor's doors

-- the subway
local TRACKS = { 47, 57 } -- each track's x; it keeps 2 clear either side
local ISLAND = { 50, 54 } -- the island platform between them
local PORTS = { { x = 47, z = 0 }, { x = 57, z = NZ } } -- Line A north, Line B south
local PILLARS = { 8, 26, 62, 80 } -- z of the island's log pillars
local BRIDGE = { 42, 46 } -- the footbridge's z (deck, rails on the outer two)
local BRIDGE_Y = 8 -- its deck: trains up to 6 blocks tall pass under
local DOCKS = { 7, 22, 37, 51, 66, 81 } -- z of the middle of each freight dock
local HATCHES = { 11, 77 } -- z of the middle of each loading hatch
local TRACK = nil -- set to "create:track" to have the turtle lay the track too (check its direction)

local BRICKS = "minecraft:deepslate_bricks"
local CRACKED = "minecraft:cracked_deepslate_bricks"
local COBBLED = "minecraft:cobbled_deepslate"
local TILES = "minecraft:deepslate_tiles"
local CTILES = "minecraft:cracked_deepslate_tiles"
local POLISHED = "minecraft:polished_deepslate"
local LOG = "minecraft:spruce_log" -- posts and pillars (upright)
local TIMBER = "minecraft:spruce_wood" -- beams, bands and lintels
local CAP = "minecraft:stripped_spruce_wood" -- post heads, trim and floor strips
local PLANKS = "minecraft:spruce_planks"
local RAIL = "minecraft:spruce_fence"
local EDGE = "minecraft:stripped_spruce_wood" -- the platform edge, paler than the planks
local BALLAST = "minecraft:gravel"
local LIGHT = "minecraft:sea_lantern"
local LANTERN = "minecraft:lantern"
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
  return n < 0.35 and tiles(x, 0, z) or n < 0.45 and COBBLED or POLISHED
end
local function among(list, v)
  for _, w in ipairs(list) do if w == v then return true end end
  return false
end
local function near(list, v, d)
  for _, w in ipairs(list) do if abs(v - w) <= d then return true end end
  return false
end
local function stairs(dir) return "minecraft:spruce_stairs[facing=" .. dir .. "]" end
-- the lift whose shaft (walls included) a z is in, if any
local function liftAt(z)
  for _, l in ipairs(LIFTS) do
    if z >= l.z0 - 1 and z <= l.z1 + 1 then return l end
  end
end
-- a z in the middle three of a lift's doors
local function liftDoor(z)
  local l = liftAt(z)
  return l and z > l.z0 and z < l.z1
end
-- a wall block with its posts, bands and lights, along is how far along it
local function wallBlock(x, y, z, along)
  local block = bricks(x, y, z)
  if y <= 1 then block = COBBLED end
  if (y == 5 or y == 21) and along % LIGHT_EVERY == 1 then block = LIGHT end
  if y >= 1 and along % POST_EVERY == 4 then block = LOG end
  if y == UPPER or y == BAND then block = TIMBER end
  return block
end

---------------------------------------------------------------- the shell

for y = 0, TOP do
  for z = 0, NZ do
    for x = 0, NX do
      if x == 0 or z == 0 or x == NX or z == NZ then
        local corner = (x == 0 or x == NX) and (z == 0 or z == NZ)
        local block = wallBlock(x, y, z, (x == 0 or x == NX) and z or x)
        if corner and y >= 1 then block = LOG end
        set(x, y, z, block)
      end
    end
  end
end

-- the ceiling deck, lights every LIGHT_EVERY; open over each lift shaft
for z = 1, NZ - 1 do
  for x = 1, NX - 1 do
    set(x, TOP, z, (x % LIGHT_EVERY == 4 and z % LIGHT_EVERY == 4) and LIGHT or tiles(x, TOP, z))
  end
end

-- timber beams under the deck across the works and the machine hall
for _, z in ipairs(BEAMS) do
  for x = 1, WEST_WALL - 1 do set(x, BAND, z, TIMBER) end
  for x = EAST_WALL + 1, NX - 1 do set(x, BAND, z, TIMBER) end
end

---------------------------------------------------------------- the works

-- floors: polished in the cells, tiles in the lane with a spruce strip for
-- the conveyor, stone in the hall marked out by spruce strips, a sea
-- lantern where they cross
for z = 1, NZ - 1 do
  for x = 1, WEST_WALL - 1 do
    local block
    if x <= CELL_X then block = POLISHED
    elseif x <= LANE[2] then block = x == LANE[1] + 1 and CAP or tiles(x, 0, z)
    else
      block = floorStone(x, z)
      local line, cross = x == HALL_LINE_X, among(HALL_LINES, z)
      if line or cross then block = CAP end
      if line and cross then block = LIGHT end
    end
    set(x, 0, z, block)
  end
end

-- the cells: walls between them, a plank floor for the upper tier (a
-- timber strip down its middle), a barrel stack in each corner by the door
local cells = {}
do
  local a = 1
  for _, d in ipairs(DIVIDERS) do
    cells[#cells + 1] = { a, d - 1 }
    a = d + 1
  end
  cells[#cells + 1] = { a, NZ - 1 }
end
for _, d in ipairs(DIVIDERS) do
  for y = 1, BAND do
    for x = 1, CELL_X do set(x, y, d, (y == UPPER or y == BAND) and TIMBER or bricks(x, y, d)) end
  end
end
for _, c in ipairs(cells) do
  local mz = math.floor((c[1] + c[2]) / 2)
  for z = c[1], c[2] do
    for x = 1, CELL_X do set(x, UPPER, z, z == mz and TIMBER or PLANKS) end
  end
  for _, y in ipairs({ 1, UPPER + 1 }) do
    set(CELL_X, y, c[1], BARREL)
    set(CELL_X - 1, y, c[1], BARREL)
    set(CELL_X, y + 1, c[1], BARREL)
  end
end

-- the cells' front: a log post at each cell wall, framed-glass windows on
-- both tiers (mullions every third block), a door into each, timber at
-- each floor and trim above the lower windows
local function cellDoor(z)
  for _, c in ipairs(cells) do
    if abs(z - math.floor((c[1] + c[2]) / 2)) <= 1 then return true end
  end
  return false
end
for y = 1, BAND do
  for z = 1, NZ - 1 do
    local block = bricks(FRONT, y, z)
    if among(DIVIDERS, z) then block = LOG
    else
      local window = (y >= 3 and y <= 11) or (y >= UPPER + 3 and y <= BAND - 2)
      if window and z % 3 ~= 0 then block = WINDOW end
      if cellDoor(z) and ((y >= DOOR_LOW and y <= DOOR_LOW + 2) or (y >= DOOR_HIGH and y <= DOOR_HIGH + 2)) then block = nil end
    end
    if y == 12 or y == UPPER or y == BAND then block = TIMBER end
    if y == 14 and block then block = CAP end
    set(FRONT, y, z, block)
  end
end

-- the lane's walkway for the upper tier, fenced on the hall side, with a
-- walkway across the hall at each end to the concourse balconies
for z = 1, NZ - 1 do
  for x = LANE[1], LANE[2] do set(x, UPPER, z, PLANKS) end
  if z > 3 and z < NZ - 3 then
    set(LANE[2], UPPER + 1, z, RAIL)
    if z % 8 == 4 then set(LANE[2], UPPER + 2, z, LANTERN) end
  end
end
for _, ends in ipairs({ { 1, 3, 4 }, { NZ - 3, NZ - 1, NZ - 4 } }) do
  for z = ends[1], ends[2] do
    for x = HALL[1], HALL[2] do set(x, UPPER, z, PLANKS) end
  end
  for x = HALL[1], HALL[2] do set(x, UPPER + 1, ends[3], RAIL) end
  set(HALL[1], UPPER + 2, ends[3], LANTERN)
  set(HALL[2], UPPER + 2, ends[3], LANTERN)
end

-- log columns in the hall carrying a beam, on a stone foot
for _, z in ipairs({ HALL_LINES[1], HALL_LINES[3] }) do
  for _, x in ipairs({ 18, 23 }) do
    for y = 1, BAND - 1 do set(x, y, z, y == 1 and COBBLED or y == BAND - 1 and CAP or LOG) end
  end
  for x = HALL[1], HALL[2] do set(x, BAND - 1, z, TIMBER) end
end

-- a water pool for pumps and hose pulleys at the south end, timber rim
for z = 73, 82 do
  for x = 18, 24 do
    local rim = x == 18 or x == 24 or z == 73 or z == 82
    set(x, 1, z, rim and CAP or WATER)
  end
end

---------------------------------------------------------------- the concourse

-- the checkered floor
for z = 1, NZ - 1 do
  for x = WEST_WALL + 1, EAST_WALL - 1 do
    set(x, 0, z, (x + z) % 2 == 0 and POLISHED or tiles(x, 0, z))
  end
end

-- its walls: a great arch in the middle (the west one taller, into the
-- assembly hall), a door by each lift at the floor, doors at both ends
-- onto the upper floors
local function concourseWall(x, arch)
  for y = 0, TOP do
    for z = 1, NZ - 1 do
      local block = wallBlock(x, y, z, z)
      local fromMid = abs(z - MID)
      if fromMid <= 12 and y >= 1 and y <= arch then block = nil end
      if fromMid <= 13 and y == arch + 1 then block = TIMBER end
      if fromMid <= 12 and y == arch + 2 then block = WINDOW end
      if liftDoor(z) then
        if y >= DOOR_LOW and y <= DOOR_LOW + 3 then block = nil end
        if y == DOOR_LOW + 4 then block = TIMBER end
      end
      if (z <= 3 or z >= NZ - 3) and y >= DOOR_HIGH and y <= DOOR_HIGH + 3 then block = nil end
      set(x, y, z, block)
    end
  end
end
concourseWall(WEST_WALL, 11)
concourseWall(EAST_WALL, 7)
-- a step up to the platforms (a block above the floor) in each east doorway
for z = 1, NZ - 1 do
  if abs(z - MID) <= 12 or liftDoor(z) then set(EAST_WALL - 1, 1, z, stairs("east")) end
end

-- a balcony down each side at the upper floor, a timber edge with a fence
-- (open at each lift's doors), lanterns on it, log posts under it
local POSTS = { 4, 10, 28, 36, 52, 60, 78, 84 }
for _, side in ipairs({ { WEST_WALL + 1, WEST_WALL + BALCONY }, { EAST_WALL - BALCONY, EAST_WALL - 1 } }) do
  local edge = side[1] == WEST_WALL + 1 and side[2] or side[1]
  for z = 1, NZ - 1 do
    for x = side[1], side[2] do set(x, UPPER, z, x == edge and TIMBER or PLANKS) end
    if not liftAt(z) then
      set(edge, UPPER + 1, z, RAIL)
      if z % 6 == 2 then set(edge, UPPER + 2, z, LANTERN) end
    end
  end
  for _, z in ipairs(POSTS) do
    for y = 1, UPPER - 1 do set(edge, y, z, y == 1 and COBBLED or y == UPPER - 1 and CAP or LOG) end
  end
end

-- timber arches across under the deck, a lantern hanging from each
for z = 4, NZ - 4, 8 do
  if not liftAt(z) then
    for x = WEST_WALL + 1, EAST_WALL - 1 do set(x, BAND - 1, z, TIMBER) end
    set(WEST_WALL + BALCONY + 1, BAND - 2, z, CAP)
    set(EAST_WALL - BALCONY - 1, BAND - 2, z, CAP)
    set(34, BAND - 2, z, LANTERN)
  end
end

-- a lit plinth in the middle: a timber rim round planks, two sea lanterns
for z = MID - 3, MID + 3 do
  for x = 32, 36 do
    set(x, 1, z, (x == 32 or x == 36 or z == MID - 3 or z == MID + 3) and CAP or PLANKS)
  end
end
set(34, 2, MID - 1, LIGHT)
set(34, 2, MID + 1, LIGHT)
set(34, 2, MID, CAP)

-- the elevator shafts: spruce posts at the corners, glass walls banded in
-- timber, doors west and east at both floors, a plank floor; empty inside
-- and open through the deck, for the elevator that comes down from above
for _, l in ipairs(LIFTS) do
  for y = 0, TOP do
    for z = l.z0 - 1, l.z1 + 1 do
      for x = l.x0 - 1, l.x1 + 1 do
        local ex, ez = x == l.x0 - 1 or x == l.x1 + 1, z == l.z0 - 1 or z == l.z1 + 1
        local block = nil
        if y == 0 then block = (ex or ez) and TIMBER or PLANKS
        elseif ex and ez then block = LOG
        elseif ex or ez then
          block = (y == 5 or y == UPPER or y == 20 or y == BAND) and TIMBER or WINDOW
          if y == TOP then block = TIMBER end
          if ex and liftDoor(z) and ((y >= DOOR_LOW and y <= DOOR_LOW + 3) or (y >= DOOR_HIGH and y <= DOOR_HIGH + 3)) then
            block = nil
          end
        end
        set(x, y, z, block)
      end
    end
  end
end

---------------------------------------------------------------- the station

-- what part of the station an x is in
local function stationPart(x)
  for _, t in ipairs(TRACKS) do
    if abs(x - t) <= 2 then return "track", t end
  end
  if x >= ISLAND[1] and x <= ISLAND[2] then return "island" end
  return "platform"
end

for z = 1, NZ - 1 do
  for x = STATION[1], STATION[2] do
    local part, t = stationPart(x)
    if part == "track" then
      set(x, 0, z, abs(x - t) <= 1 and BALLAST or COBBLED)
      if TRACK and x == t then set(x, 1, z, TRACK) end
    else
      set(x, 0, z, COBBLED)
      local edge = stationPart(x - 1) == "track" or stationPart(x + 1) == "track"
      set(x, 1, z, edge and EDGE or PLANKS)
    end
  end
end

-- the subway portals: a timber frame round each line's opening, a log post
-- either side, a stripped band over it
for _, p in ipairs(PORTS) do
  for x = p.x - 2, p.x + 2 do
    for y = 1, 7 do set(x, y, p.z, nil) end
    set(x, 0, p.z, BALLAST)
    set(x, 8, p.z, TIMBER)
    if TRACK and x == p.x then set(x, 1, p.z, TRACK) end
  end
  for y = 1, 8 do
    set(p.x - 3, y, p.z, LOG)
    set(p.x + 3, y, p.z, LOG)
  end
  for x = p.x - 3, p.x + 3 do set(x, 9, p.z, CAP) end
end

-- log pillars on the island carrying timber beams across the station
for _, z in ipairs(PILLARS) do
  for x = ISLAND[1] + 1, ISLAND[2] - 1 do
    for y = 2, UPPER - 1 do set(x, y, z, (y == 2 or y == UPPER - 1) and CAP or LOG) end
  end
  for x = STATION[1], STATION[2] do set(x, UPPER - 1, z, TIMBER) end
end

-- benches and lantern posts back to back down the island, benches and
-- barrels against the dock wall
for z = 3, NZ - 3 do
  local clear = not near(PILLARS, z, 1) and not (z >= BRIDGE[1] - BRIDGE_Y - 1 and z <= BRIDGE[2] + 1)
  if clear then
    local spot = z % 9
    if spot == 3 or spot == 4 then
      set(ISLAND[1] + 1, 2, z, stairs("east"))
      set(ISLAND[2] - 1, 2, z, stairs("west"))
      if not near(DOCKS, z, 3) then set(STATION[2], 2, z, stairs("east")) end
    elseif spot == 6 then
      set(ISLAND[1] + 1, 2, z, RAIL)
      set(ISLAND[1] + 1, 3, z, LANTERN)
      set(ISLAND[2] - 1, 2, z, RAIL)
      set(ISLAND[2] - 1, 3, z, LANTERN)
      if not near(DOCKS, z, 3) then set(STATION[2], 2, z, BARREL) end
    end
  end
end

-- the footbridge: stairs up from each platform to a deck over both tracks,
-- fenced either side but where the stairs land
local LANDINGS = { { STATION[1], STATION[1] + 1 }, { ISLAND[1] + 1, ISLAND[2] - 1 }, { STATION[2] - 1, STATION[2] } }
local function landing(x)
  for _, r in ipairs(LANDINGS) do
    if x >= r[1] and x <= r[2] then return true end
  end
  return false
end
for _, r in ipairs(LANDINGS) do
  for i = 0, BRIDGE_Y - 2 do
    local z = BRIDGE[1] - (BRIDGE_Y - 1) + i
    for x = r[1], r[2] do
      for y = 2, 1 + i do set(x, y, z, COBBLED) end
      set(x, 2 + i, z, i == BRIDGE_Y - 2 and PLANKS or stairs("south"))
    end
  end
end
for x = STATION[1], STATION[2] do
  for z = BRIDGE[1], BRIDGE[2] do set(x, BRIDGE_Y, z, x % 4 == 0 and TIMBER or PLANKS) end
  if not landing(x) then set(x, BRIDGE_Y + 1, BRIDGE[1], RAIL) end
  set(x, BRIDGE_Y + 1, BRIDGE[2], RAIL)
end
-- log piers under it, against the wall, on the island and against the docks
for _, x in ipairs({ STATION[1], ISLAND[1] + 1, ISLAND[2] - 1, STATION[2] }) do
  for z = BRIDGE[1] + 1, BRIDGE[2] - 1 do
    for y = 2, BRIDGE_Y - 1 do set(x, y, z, LOG) end
  end
end

-- the dock wall: arched bays onto the far platform, a post between docks
for y = 0, UPPER do
  for z = 1, NZ - 1 do
    local block = wallBlock(DOCK_WALL, y, z, z)
    if among(DIVIDERS, z) and y >= 1 then block = LOG end
    for _, d in ipairs(DOCKS) do
      if abs(z - d) <= 3 and y >= 2 and y <= 7 then block = nil end
      if abs(z - d) <= 4 and y == 8 then block = TIMBER end
    end
    if y == UPPER then block = TIMBER end
    set(DOCK_WALL, y, z, block)
  end
end
-- the docks: plank floors at platform height, walls between, barrels
for z = 1, NZ - 1 do
  for x = DOCK_WALL + 1, NX - 1 do
    set(x, 0, z, COBBLED)
    set(x, 1, z, PLANKS)
  end
end
for _, d in ipairs(DIVIDERS) do
  for x = DOCK_WALL + 1, NX - 1 do
    for y = 2, UPPER - 1 do set(x, y, d, bricks(x, y, d)) end
  end
end
for _, d in ipairs(DOCKS) do
  set(NX - 1, 2, d - 2, BARREL)
  set(NX - 1, 3, d - 2, BARREL)
  set(NX - 1, 2, d + 2, BARREL)
end

-- the station's ceiling is the machine hall's plank floor: timber over the
-- pillars, a row of lights over each platform, a hatch railed off over
-- each track at both ends
for z = 1, NZ - 1 do
  for x = EAST_WALL + 1, NX - 1 do
    local block = among(PILLARS, z) and TIMBER or PLANKS
    if (x == STATION[1] + 1 or x == 52 or x == STATION[2] - 1) and z % LIGHT_EVERY == 2 then block = LIGHT end
    set(x, UPPER, z, block)
  end
end
for _, hz in ipairs(HATCHES) do
  for _, t in ipairs(TRACKS) do
    for z = hz - 2, hz + 2 do
      for x = t - 2, t + 2 do
        if abs(x - t) <= 1 and abs(z - hz) <= 1 then
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
