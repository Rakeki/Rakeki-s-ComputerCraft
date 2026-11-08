-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Deep Hold: a home for Create factories and an underground subway, for
-- the 69x89x30 hole 'excavate deephold deep' digs just above bedrock. Built
-- rustic: rough deepslate walls framed in spruce, timber beams under the
-- ceiling, plank floors upstairs and on the platforms, fences, barrels.
-- It's the same both ways: mirrored east-west and north-south.
--
--   The station (across the middle): a grand hall the full height, two
--   subway tracks running east-west through a double portal in each side
--   wall, a plank platform along each wall and an island between them with
--   benches, lantern posts and log pillars up to the ceiling beams. A
--   footbridge crosses the middle, stairs up to it from both sides of every
--   platform, and a gallery runs along each side at the upper floor.
--
--   The works (the north and south wings, one the mirror of the other):
--   five cells along the end wall in two tiers, each 11 deep with a
--   framed-glass front and a door, for a machine line of its own; the
--   logistics lane in front of them (a spruce strip down the floor for a
--   belt or chain conveyor, a plank walkway above for the upper tier); and
--   a machine hall 67 wide and 27 high, timber beams under its ceiling for
--   pulleys and gantries, a sea lantern grid in its floor, and galleries
--   along both side walls. A great arch opens each half of it onto the
--   station, and the middle opens straight onto the platform.
--
--   The towers (one in the middle of each wing): an elevator shaft, 7 x 7
--   inside, beside the station, and a power shaft, 7 x 5 inside, for Create
--   shafts carrying rotation between the floors, beside the lane. Both are
--   spruce and glass, empty inside and open through the ceiling deck, with
--   doors at the floor and at the upper floor, where a walkway round the
--   tower joins the lane's walkway and the station's gallery.
--
-- The elevators aren't built: they come down from above, so dig on up from
-- each shaft to the surface and put an elevator contact by a door at each
-- floor. Tracks and station blocks aren't placed (the turtle can't turn a
-- track the right way): lay track along the gravel and put your station on
-- it. The portals open on the rock; dig the line out from there.
--
-- Beams are spruce wood (bark on every side), not logs: a turtle places
-- every log upright, and wood looks the same whichever way it stands.
--
-- Coordinates are the hole's: x east and z south from its north-west
-- corner, y 0 its floor. hole is the size to dig; home is the builder
-- turtle's spot in the north hall (facing south, chests behind and to its
-- left), which the plan keeps clear. The top layer is the ceiling deck,
-- one below the hole's ceiling: the builder stands a block above what it
-- places. Built inside the dug hole, so "clear" is false.
--
-- Only the north-west quarter is laid out here (x up to CX, z up to CZ);
-- it's mirrored to make the rest, then the rough stone is mixed.
local W, L, H = 69, 89, 30
local TOP = H - 2 -- the ceiling deck
local CX, CZ = math.floor((W - 1) / 2), math.floor((L - 1) / 2) -- the middle lines, x 34 and z 44
local HOME = { x = 20, z = 26 }
local hold = { name = "Deep Hold", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local UPPER = 15 -- the upper floor: cells' second tier, walkways, galleries
local BAND = TOP - 1 -- the timber band and beams under the deck
local LOW, HIGH = 1, UPPER + 1 -- the bottom of each floor's doors

-- the north wing, z
local CELL_Z = 11 -- the cells run z 1..CELL_Z
local FRONT = 12 -- the cells' glass front
local LANE = { 13, 15 } -- the logistics lane
local HALL = { 16, 31 } -- the machine hall
local STATION_WALL = 32 -- between the hall and the station
-- the cells, x (the middle one is mirrored into one 11 wide)
local CELLS = { { 1, 13 }, { 15, 27 }, { 29, CX } }
local DIVIDERS = { 14, 28 }
local GALLERY = 3 -- width of the galleries and the walkway round the tower
local HALL_LINES_X = { 10, 22 } -- the hall's floor strips, beams and the island's pillars
local HALL_LINE_Z = 24

-- the tower: the power shaft and the elevator, x 31..37 inside
local TOWER_X = 30 -- its west wall
local DUCT = { 17, 21 } -- inside, z
local LIFT = { 23, 29 }

-- the station, z
local TRACK_Z = 39 -- track A's middle (track B is its mirror, z 49); 2 clear either side
local PLATFORM = { 33, 36 } -- the north platform
local ISLAND = 42 -- the island's north edge (it runs to the mirror, z 46)
local BRIDGE_X = 31 -- the footbridge's west edge (to x 37)
local BRIDGE_Y = 8 -- its deck: trains up to 6 blocks tall pass under
local STAIR_X = 24 -- the foot of each stair up to it
local TRACK = nil -- set to "create:track" to have the turtle lay the track too (check its direction)

local CRACKED = "minecraft:cracked_deepslate_bricks"
local BRICKS = "minecraft:deepslate_bricks"
local COBBLED = "minecraft:cobbled_deepslate"
local TILES = "minecraft:deepslate_tiles"
local CTILES = "minecraft:cracked_deepslate_tiles"
local POLISHED = "minecraft:polished_deepslate"
local LOG = "minecraft:spruce_log" -- posts and pillars (upright)
local TIMBER = "minecraft:spruce_wood" -- beams, bands and lintels
local CAP = "minecraft:stripped_spruce_wood" -- post heads, trim and floor strips
local PLANKS = "minecraft:spruce_planks"
local RAIL = "minecraft:spruce_fence"
local BALLAST = "minecraft:gravel"
local LIGHT = "minecraft:sea_lantern"
local LANTERN = "minecraft:lantern"
local BARREL = "minecraft:barrel"
-- a Create block; swap in the vanilla one in the comment without Create
local WINDOW = "create:framed_glass" -- or "minecraft:glass"
-- rough stone, mixed once the quarter is mirrored
local ROUGH, TILED, STONE = "@bricks", "@tiles", "@floor"

local abs = math.abs
local grid = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
-- only the north-west quarter is kept
local function set(x, y, z, block)
  if x >= 0 and x <= CX and z >= 0 and z <= CZ then grid[key(x, y, z)] = block end
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
-- a wall with its posts, bands and lights; along is how far from the
-- middle, so they match on both sides
local function wallBlock(y, along)
  local block = ROUGH
  if y <= 1 then block = COBBLED end
  if (y == 5 or y == 21) and along % 12 == 3 then block = LIGHT end
  if y >= 1 and along % 6 == 0 then block = LOG end
  if y == UPPER or y == BAND then block = TIMBER end
  return block
end
local function post(x, z, y0, y1)
  for y = y0, y1 do set(x, y, z, y == y0 and (y0 == 1 and COBBLED or CAP) or y == y1 and CAP or LOG) end
end

---------------------------------------------------------------- the shell

for y = 0, TOP do
  for z = 0, CZ do set(0, y, z, wallBlock(y, CZ - z)) end
  for x = 0, CX do set(x, y, 0, wallBlock(y, CX - x)) end
  if y >= 1 then set(0, y, 0, LOG) end
end

-- the ceiling deck, lights on a 12 grid from the middle
for z = 1, CZ do
  for x = 1, CX do
    set(x, TOP, z, ((CX - x) % 12 == 0 and (CZ - z) % 12 == 0) and LIGHT or TILED)
  end
end

---------------------------------------------------------------- the works

-- floors: polished in the cells, tiles in the lane with a spruce strip for
-- the conveyor, stone in the hall marked out by spruce strips, a sea
-- lantern where they cross
for z = 1, HALL[2] do
  for x = 1, CX do
    local block
    if z <= CELL_Z then block = POLISHED
    elseif z <= LANE[2] then block = z == LANE[1] + 1 and CAP or TILED
    else
      block = STONE
      local line, cross = among(HALL_LINES_X, x), z == HALL_LINE_Z
      if line or cross then block = CAP end
      if line and cross then block = LIGHT end
    end
    set(x, 0, z, block)
  end
end

-- the cells: walls between them, a plank floor for the upper tier (a
-- timber strip down its middle), barrels in the corner by the door
for _, d in ipairs(DIVIDERS) do
  for y = 1, BAND do
    for z = 1, CELL_Z do set(d, y, z, (y == UPPER or y == BAND) and TIMBER or ROUGH) end
  end
end
local function middle(c) return c[2] == CX and CX or math.floor((c[1] + c[2]) / 2) end
for _, c in ipairs(CELLS) do
  local m = middle(c)
  for z = 1, CELL_Z do
    for x = c[1], c[2] do set(x, UPPER, z, x == m and TIMBER or PLANKS) end
  end
  for _, y in ipairs({ LOW, HIGH }) do
    set(c[1] + 1, y, CELL_Z, BARREL)
    set(c[1] + 2, y, CELL_Z, BARREL)
    set(c[1] + 1, y + 1, CELL_Z, BARREL)
  end
end

-- the cells' front: a log post at each cell wall, framed-glass windows on
-- both tiers (mullions every third block), a door into each, timber at
-- each floor and trim above the lower windows
local function cellDoor(x)
  for _, c in ipairs(CELLS) do
    if abs(x - middle(c)) <= 1 then return true end
  end
  return false
end
for y = 1, BAND do
  for x = 1, CX do
    local block = ROUGH
    if among(DIVIDERS, x) then block = LOG
    else
      local window = (y >= 3 and y <= 11) or (y >= HIGH + 2 and y <= BAND - 3)
      if window and (CX - x) % 3 ~= 0 then block = WINDOW end
      if cellDoor(x) and ((y >= LOW and y <= LOW + 2) or (y >= HIGH and y <= HIGH + 2)) then block = nil end
    end
    if y == FRONT or y == UPPER or y == BAND then block = TIMBER end
    if y == 14 and block then block = CAP end
    set(x, y, FRONT, block)
  end
end

-- the lane's walkway for the upper tier, fenced on the hall side but where
-- it meets the side gallery and the tower's walkway
for z = LANE[1], LANE[2] do
  for x = 1, CX do set(x, UPPER, z, z == LANE[2] and TIMBER or PLANKS) end
end
for x = GALLERY + 1, TOWER_X - GALLERY - 1 do
  set(x, UPPER + 1, LANE[2], RAIL)
  if (CX - x) % 8 == 4 then set(x, UPPER + 2, LANE[2], LANTERN) end
end

-- a gallery along the side wall, and a walkway round the tower, on log posts
for z = HALL[1], HALL[2] do
  for x = 1, GALLERY do set(x, UPPER, z, x == GALLERY and TIMBER or PLANKS) end
  set(GALLERY, UPPER + 1, z, RAIL)
  for x = TOWER_X - GALLERY, TOWER_X - 1 do set(x, UPPER, z, x == TOWER_X - GALLERY and TIMBER or PLANKS) end
  if z < HALL[2] then set(TOWER_X - GALLERY, UPPER + 1, z, RAIL) end
  if (CZ - z) % 6 == 2 then
    set(GALLERY, UPPER + 2, z, LANTERN)
    set(TOWER_X - GALLERY, UPPER + 2, z, LANTERN)
  end
end
for x = TOWER_X, CX do set(x, UPPER, HALL[2], PLANKS) end
for _, z in ipairs({ 20, 28 }) do
  post(GALLERY, z, 1, UPPER - 1)
  post(TOWER_X - GALLERY, z, 1, UPPER - 1)
end

-- timber beams under the deck: along the hall's strips, across its middle
for _, x in ipairs(HALL_LINES_X) do
  for z = 1, HALL[2] do set(x, BAND, z, TIMBER) end
end
for x = 1, TOWER_X - 1 do set(x, BAND, HALL_LINE_Z, TIMBER) end

---------------------------------------------------------------- the tower

-- spruce posts at the corners, glass banded in timber, a plank floor; empty
-- inside and open through the deck. doors: which faces have one, the x or
-- z of its middle and how far either side
local function shaft(z0, z1, doors)
  for y = 0, TOP do
    for z = z0 - 1, z1 + 1 do
      for x = TOWER_X, CX do
        local ex, ez = x == TOWER_X, z == z0 - 1 or z == z1 + 1
        local block = nil
        if y == 0 then block = (ex or ez) and TIMBER or PLANKS
        elseif ex and ez then block = LOG
        elseif ex or ez then
          block = (y == 5 or y == UPPER or y == 20 or y == BAND or y == TOP) and TIMBER or WINDOW
          local floor = (y >= LOW and y <= LOW + 3) or (y >= HIGH and y <= HIGH + 3)
          if floor and ex and doors.west and abs(z - doors.west) <= 1 then block = nil end
          if floor and z == z0 - 1 and doors.north and x >= doors.north then block = nil end
          if floor and z == z1 + 1 and doors.south and x >= doors.south then block = nil end
        end
        set(x, y, z, block)
      end
    end
  end
end
shaft(DUCT[1], DUCT[2], { west = 19, north = CX - 1 })
shaft(LIFT[1], LIFT[2], { west = 26, south = CX - 2 })

---------------------------------------------------------------- the station wall

-- a great arch into each half of the hall, windows over it onto the
-- gallery, the middle open under the tower's walkway, doors at both ends
-- of the gallery and onto the tower's walkway
for y = 0, TOP do
  for x = 1, CX do
    local block = wallBlock(y, CX - x)
    if x >= 5 and x <= 23 then
      if y >= 1 and y <= 10 then block = nil end
      if y == 11 then block = TIMBER end
      if y == 12 or y == 13 then block = WINDOW end
    end
    if x == 4 or x == 24 then
      if y == 11 then block = TIMBER end
    end
    if x >= 6 and x <= 22 and y >= HIGH + 2 and y <= BAND - 3 and block ~= LOG and (CX - x) % 3 ~= 0 then block = WINDOW end
    if x >= TOWER_X - GALLERY and y >= 1 and y < UPPER then block = nil end
    if (x <= GALLERY or x >= CX - 2) and y >= HIGH and y <= HIGH + 3 then block = nil end
    -- a step up to the platform (a block above the hall floor)
    if y == 1 and not block then block = stairs("south") end
    set(x, y, STATION_WALL, block)
  end
end

---------------------------------------------------------------- the station

local function part(z)
  if abs(z - TRACK_Z) <= 2 then return "track" end
  if z >= ISLAND then return "island" end
  return "platform"
end
for z = PLATFORM[1], CZ do
  for x = 1, CX do
    local p = part(z)
    if p == "track" then
      set(x, 0, z, abs(z - TRACK_Z) <= 1 and BALLAST or COBBLED)
      if TRACK and z == TRACK_Z then set(x, 1, z, TRACK) end
    else
      set(x, 0, z, COBBLED)
      set(x, 1, z, (z == PLATFORM[2] or z == ISLAND) and CAP or PLANKS)
    end
  end
end

-- the portal in the side wall: a timber frame round the track, a log post
-- either side, a stripped band over it
for z = TRACK_Z - 2, TRACK_Z + 2 do
  for y = 1, 7 do set(0, y, z, nil) end
  set(0, 0, z, BALLAST)
  set(0, 8, z, TIMBER)
  if TRACK and z == TRACK_Z then set(0, 1, z, TRACK) end
end
for y = 1, 8 do
  set(0, y, TRACK_Z - 3, LOG)
  set(0, y, TRACK_Z + 3, LOG)
end
for z = TRACK_Z - 3, TRACK_Z + 3 do set(0, 9, z, CAP) end

-- the gallery over the platform, fenced, on log posts at its edge
for z = PLATFORM[1], PLATFORM[2] do
  for x = 1, CX do set(x, UPPER, z, z == PLATFORM[2] and TIMBER or PLANKS) end
end
for x = 1, CX do
  set(x, UPPER + 1, PLATFORM[2], RAIL)
  if (CX - x) % 6 == 3 then set(x, UPPER + 2, PLATFORM[2], LANTERN) end
end
for _, x in ipairs(HALL_LINES_X) do post(x, PLATFORM[2], 2, UPPER - 1) end

-- log pillars on the island up to the ceiling beams, beams across the hall
for _, x in ipairs(HALL_LINES_X) do
  for z = ISLAND + 1, CZ do post(x, z, 2, BAND - 1) end
end
for x = 2, CX, 8 do
  for z = PLATFORM[1], CZ do set(x, BAND, z, TIMBER) end
end
for _, x in ipairs(HALL_LINES_X) do
  for z = PLATFORM[1], CZ do set(x, BAND, z, TIMBER) end
end

-- the footbridge over both tracks, and a stair up to it on each platform
-- (both sides of it, once mirrored)
for z = PLATFORM[1], CZ do
  for x = BRIDGE_X, CX do set(x, BRIDGE_Y, z, z % 4 == 0 and TIMBER or PLANKS) end
end
local STAIRS = { { PLATFORM[1] + 1, PLATFORM[2] }, { ISLAND + 1, CZ } }
local function landing(z)
  for _, r in ipairs(STAIRS) do
    if z >= r[1] and z <= r[2] then return true end
  end
  return false
end
for z = PLATFORM[1], CZ do
  if not landing(z) then set(BRIDGE_X, BRIDGE_Y + 1, z, RAIL) end
end
for _, r in ipairs(STAIRS) do
  for i = 0, BRIDGE_Y - 2 do
    local x = STAIR_X + i
    for z = r[1], r[2] do
      for y = 2, 1 + i do set(x, y, z, COBBLED) end
      set(x, 2 + i, z, i == BRIDGE_Y - 2 and PLANKS or stairs("east"))
    end
  end
end
for _, z in ipairs({ PLATFORM[2], ISLAND }) do
  for y = 2, BRIDGE_Y - 1 do set(BRIDGE_X, y, z, LOG) end
end

-- benches back to back down the island, lantern posts between
for x = 1, STAIR_X - 2 do
  if not near(HALL_LINES_X, x, 1) then
    local spot = (CX - x) % 9
    if spot == 3 or spot == 4 then set(x, 2, ISLAND + 1, stairs("south"))
    elseif spot == 6 then
      set(x, 2, ISLAND + 1, RAIL)
      set(x, 3, ISLAND + 1, LANTERN)
    end
  end
end

---------------------------------------------------------------- out

-- mirror the quarter both ways, turning what faces east-west or north-south
local SWAP = { east = "west", west = "east", north = "south", south = "north" }
local function turn(block, axis)
  return (block:gsub("facing=(%a+)", function(f)
    local flip = (axis == "x" and (f == "east" or f == "west")) or (axis == "z" and (f == "north" or f == "south"))
    return "facing=" .. (flip and SWAP[f] or f)
  end))
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function rough(block, x, y, z)
  local n = noise(x, y, z)
  if block == ROUGH then return n < 0.12 and CRACKED or n < 0.27 and COBBLED or BRICKS end
  if block == TILED then return n < 0.1 and CTILES or TILES end
  if block == STONE then return n < 0.35 and (n < 0.035 and CTILES or TILES) or n < 0.45 and COBBLED or POLISHED end
  return block
end
local full = {}
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  for _, m in ipairs({ { x, z, block }, { W - 1 - x, z, turn(block, "x") }, { x, L - 1 - z, turn(block, "z") }, { W - 1 - x, L - 1 - z, turn(turn(block, "x"), "z") } }) do
    full[key(m[1], y, m[2])] = rough(m[3], m[1], y, m[2])
  end
end

-- the builder's home column, and the floor under its two chests, stay empty
for y = 0, TOP do full[key(HOME.x, y, HOME.z)] = nil end
full[key(HOME.x, 0, HOME.z - 1)] = nil
full[key(HOME.x + 1, 0, HOME.z)] = nil

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = full[key(x, y, z)]
      if block then hold.blocks[#hold.blocks + 1] = { x, y, z, block } end
    end
  end
end
return hold
