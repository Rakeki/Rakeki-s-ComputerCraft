-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Deep Hold: a three-storey deepslate base for the 57x57x30 hole
-- 'excavate deephold deep' digs just above bedrock. In the middle an open
-- well runs through every floor round a core pillar banded with copper and
-- froglights, a basin at its foot; a rotunda walk circles it on each floor
-- behind a railing with lanterns. Corridors 7 wide run from the rotunda to
-- the four walls, and between them on each floor is a room to a quarter:
--
--   ground (the works):  storage hall (NW), smithy (NE), sugar cane farm
--                        (SW), turtle bay (SE); a portal frame at the north
--                        end, lavafalls behind bars east and west, the way
--                        in through an arch in the south wall
--   first (living):      bedrooms (NW), kitchen and dining (NE), library
--                        with an enchanting table (SW), brewing room with
--                        a nether wart bed (SE)
--   top (the hall):      vault (NW), lounge with a fireplace (NE), garden
--                        with azalea trees and a pond (SW), armoury and
--                        archery range (SE)
--
-- Stairs climb the west corridor from the ground to the first floor and the
-- east corridor from the first to the top. Each room opens on both
-- corridors beside it and through an arch from the rotunda.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot in the
-- well (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is the ceiling deck, one below the hole's ceiling:
-- the builder stands a block above what it places. Built inside the dug
-- hole, so "clear" is false.
local W, L, H = 57, 57, 30
local TOP = H - 2 -- the ceiling deck
local N = W - 1 -- the east and south walls
local C = 28 -- the middle (x and z)
local HOME = { x = C, z = C + 6 }
local hold = { name = "Deep Hold", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local LEVELS = { 0, 9, 18 } -- each storey's floor layer; the deck at TOP closes the last
local WELL = 6.5 -- the open well's radius
local ROTUNDA = 11.5 -- the walk round it
local RING = 12.6 -- the rotunda's wall
local HALF = 3 -- corridors run 7 wide: the middle and 3 either side
local DOOR = { 18, 20 } -- doorways from the corridors into the rooms, this far from the middle
local DOOR_H = 4 -- doorway and arch height
local LAVA = "minecraft:lava" -- or "minecraft:magma_block": the two lavafalls take 2 lava buckets

local BRICKS = "minecraft:deepslate_bricks"
local CRACKED = "minecraft:cracked_deepslate_bricks"
local TILES = "minecraft:deepslate_tiles"
local CTILES = "minecraft:cracked_deepslate_tiles"
local POLISHED = "minecraft:polished_deepslate"
local CHISELED = "minecraft:chiseled_deepslate"
local RAIL = "minecraft:polished_deepslate_wall"
local GLOW = "minecraft:shroomlight" -- ceiling lights
local LIGHT = "minecraft:ochre_froglight" -- wall lights
local PANEL = "minecraft:verdant_froglight" -- the glowing panels at the corridor ends
local COPPER = "minecraft:waxed_cut_copper"
local LANTERN = "minecraft:lantern"
local WATER = "minecraft:water"
local MOSS = "minecraft:moss_block"
local BARREL = "minecraft:barrel"
local SHELF = "minecraft:bookshelf"

local abs, sqrt = math.abs, math.sqrt
local grid, lights = {}, {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function set(x, y, z, block) grid[key(x, y, z)] = block end
local function get(x, y, z) return grid[key(x, y, z)] end
-- a light: room floors laid later never cover one
local function light(x, y, z, block)
  set(x, y, z, block or GLOW)
  lights[key(x, y, z)] = true
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function bricks(x, y, z) return noise(x, y, z) < 0.1 and CRACKED or BRICKS end
local function tiles(x, y, z) return noise(x, y, z) < 0.1 and CTILES or TILES end

-- What a column of the hole is part of, the same on every floor.
local function kind(x, z)
  if x <= 0 or z <= 0 or x >= N or z >= N then return "outer" end
  local ax, az = abs(x - C), abs(z - C)
  local r = sqrt(ax * ax + az * az)
  if r <= WELL then return "well" end
  if r <= ROTUNDA then return "rotunda" end
  if ax <= HALF or az <= HALF then return "corridor" end
  if r <= RING then return "ring" end
  if ax == HALF + 1 or az == HALF + 1 then return "wall" end
  return "room"
end
-- a corridor cell's distance across (0 in the middle) and along it
local function corridorAt(x, z)
  local ax, az = abs(x - C), abs(z - C)
  if ax <= HALF then return ax, az end
  return az, ax
end
local function isDoor(x, z)
  local ax, az = abs(x - C), abs(z - C)
  local along = ax == HALF + 1 and az or ax
  return kind(x, z) == "wall" and along >= DOOR[1] and along <= DOOR[2]
end
-- the arch from the rotunda into each room, on the diagonals
local function isArch(x, z)
  return kind(x, z) == "ring" and abs(abs(x - C) - abs(z - C)) <= 2
end

---------------------------------------------------------------- floors and walls

for i, f in ipairs(LEVELS) do
  local top = (LEVELS[i + 1] or TOP) - 1 -- this storey's last layer
  for z = 1, N - 1 do
    for x = 1, N - 1 do
      local k = kind(x, z)
      local ax, az = abs(x - C), abs(z - C)
      local r = sqrt(ax * ax + az * az)
      -- the floor: the well is open above the ground
      if k == "corridor" then
        local across = corridorAt(x, z)
        set(x, f, z, (across == 0 or across == HALF) and POLISHED or tiles(x, f, z))
      elseif k == "rotunda" or (k == "well" and f == 0) then
        set(x, f, z, math.floor(r) % 3 == 0 and POLISHED or tiles(x, f, z))
      elseif k == "room" then
        set(x, f, z, (x + z) % 2 == 0 and POLISHED or tiles(x, f, z))
      elseif k == "wall" or k == "ring" then
        set(x, f, z, BRICKS)
      end
      -- the walls between corridors and rooms, with doorways and pilasters
      if k == "wall" then
        local along = ax == HALF + 1 and az or ax
        for y = f + 1, top do
          local block
          if isDoor(x, z) then
            block = y == f + DOOR_H + 1 and CHISELED or y > f + DOOR_H + 1 and bricks(x, y, z) or nil
          elseif along % 5 == 0 then
            block = y == f + 4 and LIGHT or POLISHED
          else
            block = y == top and POLISHED or bricks(x, y, z)
          end
          set(x, y, z, block)
        end
      -- the rotunda's wall, with an arch to each room and a light either side of each corridor
      elseif k == "ring" then
        local lamp = (ax == 11 and az == 5) or (ax == 5 and az == 11)
        for y = f + 1, top do
          local block
          if isArch(x, z) then
            block = y == f + DOOR_H + 1 and CHISELED or y > f + DOOR_H + 1 and tiles(x, y, z) or nil
          elseif lamp and y == f + 4 then
            block = LIGHT
          else
            block = y == top and POLISHED or tiles(x, y, z)
          end
          set(x, y, z, block)
        end
      end
    end
  end
end

-- the ceiling deck
for z = 1, N - 1 do
  for x = 1, N - 1 do
    local ax, az = abs(x - C), abs(z - C)
    set(x, TOP, z, kind(x, z) == "well" and POLISHED or tiles(x, TOP, z))
  end
end

-- the outer walls: a polished band at each floor, lights at head height
local LEVEL_AT = {}
for _, f in ipairs(LEVELS) do LEVEL_AT[f] = true end
for y = 0, TOP do
  for z = 0, N do
    for x = 0, N do
      if kind(x, z) == "outer" then
        local along = (x == 0 or x == N) and z or x
        local block = (LEVEL_AT[y] and y > 0) and POLISHED or bricks(x, y, z)
        for _, f in ipairs(LEVELS) do
          if y == f + 4 and (along - C) % 6 == 3 and along > 0 and along < N then block = LIGHT end
        end
        set(x, y, z, block)
      end
    end
  end
end

-- ceiling lights, set into the floor above (or the deck): a grid in the
-- rooms, a line down each corridor, eight round the rotunda
for _, y in ipairs({ LEVELS[2], LEVELS[3], TOP }) do
  for z = 1, N - 1 do
    for x = 1, N - 1 do
      local k = kind(x, z)
      local ax, az = abs(x - C), abs(z - C)
      if k == "room" and ax % 6 == 3 and az % 6 == 3 then
        light(x, y, z)
      elseif k == "corridor" then
        local across, along = corridorAt(x, z)
        if across == 0 and along % 6 == 0 then light(x, y, z) end
      elseif k == "rotunda" and ((ax == 0 and az == 9) or (az == 0 and ax == 9) or (ax == 7 and az == 7)) then
        light(x, y, z)
      end
    end
  end
end

---------------------------------------------------------------- the well

-- the core pillar, floor to deck: 3x3, hollow, copper bands at each floor,
-- a froglight in each face on every storey
local FACE_LIGHT = {}
for _, f in ipairs(LEVELS) do FACE_LIGHT[f + 4] = true end
for y = 0, TOP - 1 do
  for dz = -1, 1 do
    for dx = -1, 1 do
      local block
      if dx == 0 and dz == 0 then block = y == 0 and BRICKS or nil
      elseif y == 0 then block = POLISHED
      elseif y == 1 or y == TOP - 1 then block = CHISELED
      elseif LEVEL_AT[y] then block = COPPER
      elseif dx == 0 or dz == 0 then block = FACE_LIGHT[y] and LIGHT or POLISHED
      else block = BRICKS end
      set(C + dx, y, C + dz, block)
    end
  end
end

-- the basin round its foot
for z = C - 5, C + 5 do
  for x = C - 5, C + 5 do
    local ax, az = abs(x - C), abs(z - C)
    local r = sqrt(ax * ax + az * az)
    if (ax > 1 or az > 1) and r <= 3.6 then
      set(x, 0, z, WATER)
    elseif r > 3.6 and r <= 4.6 then
      set(x, 0, z, POLISHED)
      set(x, 1, z, "minecraft:deepslate_tile_wall")
    end
  end
end

-- the railing round the well on the upper floors, lanterns on eight posts
for _, f in ipairs({ LEVELS[2], LEVELS[3] }) do
  for z = C - 8, C + 8 do
    for x = C - 8, C + 8 do
      local ax, az = abs(x - C), abs(z - C)
      local r = sqrt(ax * ax + az * az)
      if r > WELL and r <= WELL + 1 then
        set(x, f + 1, z, RAIL)
        if (ax == 0 or az == 0 or ax == az) then set(x, f + 2, z, LANTERN) end
      end
    end
  end
end

---------------------------------------------------------------- stairs

-- One flight up a corridor: 8 steps on 3 of its 7 blocks, solid beneath,
-- the floor above opened over it and railed off.
--   x0: the first step's x, dir: +1 climbs east, -1 west; z0..z1 its width
local function flight(f, x0, dir, z0, z1, railZ)
  local facing = dir > 0 and "east" or "west"
  local above = f + 9 -- the next floor
  for i = 0, 7 do
    local x = x0 + dir * i
    for z = z0, z1 do
      for y = f + 1, f + i do set(x, y, z, BRICKS) end
      set(x, f + 1 + i, z, "minecraft:deepslate_brick_stairs[facing=" .. facing .. "]")
      set(x, above, z, nil)
    end
    set(x, above + 1, railZ, RAIL)
  end
  for z = z0, z1 do set(x0 - dir, above + 1, z, RAIL) end
end
flight(LEVELS[1], C - 14, -1, C + 1, C + HALF, C) -- the west corridor, ground to first
flight(LEVELS[2], C + 14, 1, C - HALF, C - 1, C) -- the east corridor, first to top

---------------------------------------------------------------- the corridor ends

-- a glowing panel in the outer wall at a corridor's end
local function panel(side, f)
  for a = C - 2, C + 2 do
    for y = f + 1, f + 5 do
      local block = (a == C - 2 or a == C + 2 or y == f + 1 or y == f + 5) and POLISHED or PANEL
      if side == "north" then set(a, y, 0, block)
      elseif side == "south" then set(a, y, N, block)
      elseif side == "west" then set(0, y, a, block)
      else set(N, y, a, block) end
    end
  end
end
for _, f in ipairs({ LEVELS[2], LEVELS[3] }) do
  for _, side in ipairs({ "north", "south", "east", "west" }) do panel(side, f) end
end

-- the ground floor's north end: a portal frame (light it yourself)
for x = C - 2, C + 2 do
  for y = 1, 6 do
    local edge = x == C - 2 or x == C + 2 or y == 1 or y == 6
    local corner = (x == C - 2 or x == C + 2) and (y == 1 or y == 6)
    set(x, y, 1, edge and (corner and "minecraft:crying_obsidian" or "minecraft:obsidian") or nil)
  end
end

-- east and west: a lavafall in a niche behind bars; the niche holds the spread
for _, side in ipairs({ { x = 1, dir = 1 }, { x = N - 1, dir = -1 } }) do
  for y = 1, 7 do
    set(side.x, y, C - 1, BRICKS)
    set(side.x, y, C + 1, BRICKS)
    set(side.x, y, C, y == 7 and LAVA or nil)
    set(side.x + side.dir, y, C, "minecraft:iron_bars")
  end
  set(side.x, 8, C, CHISELED)
end

-- south: the way in, an arch opening on the rock; dig your tunnel from there
for x = C - 2, C + 2 do
  for y = 1, 5 do set(x, y, N, nil) end
  set(x, 6, N, CHISELED)
end
for y = 1, 6 do
  set(C - 3, y, N - 1, POLISHED)
  set(C + 3, y, N - 1, POLISHED)
end
set(C - 3, 7, N - 1, LANTERN)
set(C + 3, 7, N - 1, LANTERN)

---------------------------------------------------------------- rooms

-- A quarter's room on one floor, in its own coordinates: u and v count out
-- from the middle (5 by the corridor walls, 27 by the outer wall), y up
-- from its floor (1 is where you stand).
local function room(sx, sz, f)
  local r = {}
  local function at(u, v) return C + sx * u, C + sz * v end
  function r.inside(u, v)
    local x, z = at(u, v)
    return kind(x, z) == "room"
  end
  -- room for furniture: not in front of a doorway or the arch
  function r.free(u, v)
    if not r.inside(u, v) then return false end
    if u <= 7 and v >= DOOR[1] - 2 and v <= DOOR[2] + 2 then return false end
    if v <= 7 and u >= DOOR[1] - 2 and u <= DOOR[2] + 2 then return false end
    return u + v > 22
  end
  function r.put(u, y, v, block)
    if r.free(u, v) then
      local x, z = at(u, v)
      set(x, f + y, z, block)
    end
  end
  function r.empty(u, y, v)
    local x, z = at(u, v)
    return get(x, f + y, z) == nil
  end
  -- lay a floor block; false where a light below keeps its place
  function r.floor(u, v, block)
    if r.inside(u, v) then
      local x, z = at(u, v)
      if not lights[key(x, f, z)] then
        set(x, f, z, block)
        return true
      end
    end
    return false
  end
  function r.ground(u, v)
    local x, z = at(u, v)
    return get(x, f, z)
  end
  function r.each(fn)
    for u = 5, 27 do
      for v = 5, 27 do
        if r.inside(u, v) then fn(u, v) end
      end
    end
  end
  -- the world facing for +u (s = 1) or -u (s = -1), and the same for v
  function r.du(s) return s * sx > 0 and "east" or "west" end
  function r.dv(s) return s * sz > 0 and "south" or "north" end
  function r.noise(u, v) return noise(C + sx * u, f, C + sz * v) end
  return r
end

-- a row along the outer wall at v = 27 (u from a to b) and one at u = 27
local function alongV(r, a, b, fn) for u = a, b do fn(u, 27) end end
local function alongU(r, a, b, fn) for v = a, b do fn(27, v) end end

-- a fireplace in the outer wall: a campfire under a hood, open to the room
-- at = the middle's u along v = 27 (wallV) or v along u = 27
local function fireplace(r, at, wallV)
  local function put(along, out, y, block)
    if wallV then r.put(along, y, out, block) else r.put(out, y, along, block) end
  end
  for y = 1, 8 do
    put(at - 1, 27, y, BRICKS)
    put(at + 1, 27, y, BRICKS)
    if y >= 4 then for a = at - 1, at + 1 do put(a, 26, y, BRICKS) end end
  end
  put(at, 27, 1, "minecraft:campfire")
  put(at - 1, 26, 1, POLISHED)
  put(at + 1, 26, 1, POLISHED)
  put(at - 1, 26, 2, POLISHED)
  put(at + 1, 26, 2, POLISHED)
  put(at - 1, 26, 3, CHISELED)
  put(at + 1, 26, 3, CHISELED)
end

local ROOMS = {}

-- ground, north-west: rows of barrels round the walls and two racks
ROOMS[#ROOMS + 1] = { -1, -1, 0, function(r)
  for y = 1, 3 do
    alongU(r, 6, 27, function(u, v) r.put(u, y, v, BARREL) end)
    alongV(r, 6, 26, function(u, v) r.put(u, y, v, BARREL) end)
  end
  for _, v in ipairs({ 13, 14, 20, 21 }) do
    for u = 11, 23 do
      if u ~= 17 and u ~= 18 then
        for y = 1, 2 do r.put(u, y, v, BARREL) end
      end
    end
  end
  r.put(9, 1, 26, "minecraft:crafting_table")
end }

-- ground, north-east: the smithy
ROOMS[#ROOMS + 1] = { 1, -1, 0, function(r)
  r.each(function(u, v) r.floor(u, v, r.noise(u, v) < 0.3 and CTILES or TILES) end)
  local machines = { "furnace", "blast_furnace", "smoker" }
  alongV(r, 7, 26, function(u, v)
    r.put(u, 1, v, "minecraft:" .. machines[u % 3 + 1] .. "[facing=" .. r.dv(-1) .. "]")
    r.put(u, 2, v, CHISELED)
  end)
  local stations = { "anvil", "smithing_table", "grindstone", "stonecutter", "anvil", "smithing_table" }
  for i, name in ipairs(stations) do r.put(27, 1, 6 + i * 3, "minecraft:" .. name) end
  -- a work island in the middle
  for u = 13, 21 do r.put(u, 1, 16, u % 2 == 0 and BARREL or "minecraft:crafting_table") end
  r.put(12, 1, 16, "minecraft:cauldron")
  r.put(22, 1, 16, "minecraft:cauldron")
end }

-- ground, south-west: sugar cane along three water channels in moss
ROOMS[#ROOMS + 1] = { -1, 1, 0, function(r)
  r.each(function(u, v) r.floor(u, v, MOSS) end)
  for _, cu in ipairs({ 10, 16, 22 }) do
    for v = 8, 26 do
      if r.inside(cu, v) then
        r.floor(cu, v, WATER)
        r.put(cu - 1, 1, v, "minecraft:sugar_cane")
        r.put(cu + 1, 1, v, "minecraft:sugar_cane")
      end
    end
  end
  for _, u in ipairs({ 13, 19, 25 }) do
    for v = 9, 25, 4 do r.put(u, 1, v, (u + v) % 8 == 0 and "minecraft:flowering_azalea" or "minecraft:azalea") end
  end
  for u = 8, 12 do r.put(u, 1, 27, "minecraft:composter") end
  for u = 13, 17 do r.put(u, 1, 27, BARREL) end
end }

-- ground, south-east: the turtle bay, chests with a pad in front of each,
-- and workstations along the south wall
ROOMS[#ROOMS + 1] = { 1, 1, 0, function(r)
  for v = 9, 24, 3 do
    r.put(27, 1, v, "minecraft:chest[facing=" .. r.du(-1) .. "]")
    r.put(26, 1, v, "minecraft:lime_carpet")
    r.put(27, 1, v + 1, BARREL)
  end
  local stations = { "crafting_table", "loom", "cartography_table", "fletching_table", "barrel", "smithing_table" }
  alongV(r, 7, 24, function(u, v) r.put(u, 1, v, "minecraft:" .. stations[u % #stations + 1]) end)
  -- a big table in the middle
  for u = 14, 20 do
    for v = 14, 17 do
      r.put(u, 1, v, (u == 14 or u == 20) and "minecraft:dark_oak_log" or "minecraft:dark_oak_planks")
    end
  end
end }

-- first, north-west: bedrooms; bed spots marked with carpet, a nightstand
-- with a lantern by each, a rug in the middle
ROOMS[#ROOMS + 1] = { -1, -1, 9, function(r)
  r.each(function(u, v) r.floor(u, v, "minecraft:spruce_planks") end)
  local colours = { "red", "blue", "green", "yellow", "purple", "cyan", "orange", "magenta", "lime" }
  local n = 0
  local function bed(u1, v1, u2, v2, su, sv)
    n = n + 1
    local carpet = "minecraft:" .. colours[n] .. "_carpet"
    r.put(u1, 1, v1, carpet)
    r.put(u2, 1, v2, carpet)
    r.put(su, 1, sv, BARREL)
    r.put(su, 2, sv, LANTERN)
  end
  for u = 8, 24, 4 do bed(u, 27, u, 26, u + 2, 27) end
  for v = 8, 20, 4 do bed(27, v, 26, v, 27, v + 2) end
  for u = 14, 21 do
    for v = 13, 20 do
      local edge = u == 14 or u == 21 or v == 13 or v == 20
      r.put(u, 1, v, edge and "minecraft:red_carpet" or "minecraft:white_carpet")
    end
  end
end }

-- first, north-east: the kitchen counter, a fireplace and a long table
ROOMS[#ROOMS + 1] = { 1, -1, 9, function(r)
  r.each(function(u, v) r.floor(u, v, "minecraft:dark_oak_planks") end)
  local counter = { "smoker", "barrel", "furnace", "crafting_table", "barrel", "cauldron" }
  alongV(r, 7, 26, function(u, v)
    local name = counter[u % #counter + 1]
    local faces = name == "smoker" or name == "furnace"
    r.put(u, 1, v, "minecraft:" .. name .. (faces and "[facing=" .. r.dv(-1) .. "]" or ""))
  end)
  fireplace(r, 16, false)
  for u = 12, 22 do
    r.put(u, 1, 16, "minecraft:dark_oak_fence")
    r.put(u, 2, 16, "minecraft:white_carpet")
    if u > 12 and u < 22 then
      r.put(u, 1, 15, "minecraft:spruce_stairs[facing=" .. r.dv(-1) .. "]")
      r.put(u, 1, 17, "minecraft:spruce_stairs[facing=" .. r.dv(1) .. "]")
    end
  end
end }

-- first, south-west: the library, shelves round the walls and an
-- enchanting table in a ring of fifteen
ROOMS[#ROOMS + 1] = { -1, 1, 9, function(r)
  r.each(function(u, v) r.floor(u, v, "minecraft:dark_oak_planks") end)
  for y = 1, 4 do
    alongU(r, 6, 27, function(u, v) r.put(u, y, v, SHELF) end)
    alongV(r, 6, 26, function(u, v) r.put(u, y, v, SHELF) end)
  end
  local cu, cv = 19, 19
  r.put(cu, 1, cv, "minecraft:enchanting_table")
  for a = -2, 2 do
    for b = -2, 2 do
      if (abs(a) == 2 or abs(b) == 2) and not (a == 0 and b == -2) then
        r.put(cu + a, 1, cv + b, SHELF)
        r.put(cu + a, 2, cv + b, SHELF)
      end
    end
  end
  r.put(12, 1, 24, "minecraft:lectern")
  r.put(24, 1, 12, "minecraft:lectern")
  for u = 13, 15 do r.put(u, 1, 24, "minecraft:brown_carpet") end
end }

-- first, south-east: brewing stands and cauldrons, a nether wart bed
ROOMS[#ROOMS + 1] = { 1, 1, 9, function(r)
  r.each(function(u, v) r.floor(u, v, "minecraft:polished_blackstone") end)
  local counter = { "brewing_stand", "cauldron", "barrel", "brewing_stand", "barrel", "cauldron" }
  alongV(r, 7, 18, function(u, v) r.put(u, 1, v, "minecraft:" .. counter[u % #counter + 1]) end)
  for v = 7, 17 do
    r.put(27, 1, v, BARREL)
    r.put(27, 2, v, BARREL)
  end
  for u = 19, 26 do
    for v = 19, 26 do
      if u == 19 or u == 26 or v == 19 or v == 26 then
        r.put(u, 1, v, "minecraft:polished_blackstone_wall")
      else
        if r.floor(u, v, "minecraft:soul_sand") then r.put(u, 1, v, "minecraft:nether_wart") end
      end
    end
  end
end }

-- top, north-west: the vault, chests round the walls and a dais with a
-- lodestone, ender chests and a respawn anchor
ROOMS[#ROOMS + 1] = { -1, -1, 18, function(r)
  r.each(function(u, v) if u == v then r.floor(u, v, COPPER) end end)
  for y = 1, 2 do
    alongU(r, 6, 26, function(u, v) r.put(u, y, v, "minecraft:chest[facing=" .. r.du(-1) .. "]") end)
    alongV(r, 6, 26, function(u, v) r.put(u, y, v, "minecraft:chest[facing=" .. r.dv(-1) .. "]") end)
  end
  for _, c in ipairs({ { 27, 27 } }) do
    for y = 1, 4 do r.put(c[1], y, c[2], CHISELED) end
  end
  for u = 15, 21 do
    for v = 15, 21 do
      local edge = u == 15 or u == 21 or v == 15 or v == 21
      r.put(u, 1, v, edge and CHISELED or POLISHED)
    end
  end
  r.put(18, 2, 18, "minecraft:lodestone")
  r.put(16, 2, 20, "minecraft:ender_chest")
  r.put(20, 2, 16, "minecraft:ender_chest")
  r.put(20, 2, 20, "minecraft:respawn_anchor")
  r.put(16, 2, 16, "minecraft:cartography_table")
end }

-- top, north-east: the lounge, couches round a rug before a fireplace,
-- shelves and a jukebox
ROOMS[#ROOMS + 1] = { 1, -1, 18, function(r)
  r.each(function(u, v) r.floor(u, v, "minecraft:dark_oak_planks") end)
  fireplace(r, 16, true)
  for u = 13, 19 do r.put(u, 1, 21, "minecraft:spruce_stairs[facing=" .. r.dv(-1) .. "]") end
  for v = 22, 24 do
    r.put(12, 1, v, "minecraft:spruce_stairs[facing=" .. r.du(-1) .. "]")
    r.put(20, 1, v, "minecraft:spruce_stairs[facing=" .. r.du(1) .. "]")
  end
  for u = 13, 19 do
    for v = 22, 24 do r.put(u, 1, v, (u + v) % 2 == 0 and "minecraft:red_carpet" or "minecraft:orange_carpet") end
  end
  for y = 1, 3 do alongU(r, 6, 20, function(u, v) r.put(u, y, v, SHELF) end) end
  r.put(27, 1, 23, "minecraft:jukebox")
  r.put(27, 1, 24, "minecraft:note_block")
end }

-- top, south-west: a garden of moss with three azalea trees, a raised pond
-- and mud brick paths
ROOMS[#ROOMS + 1] = { -1, 1, 18, function(r)
  r.each(function(u, v)
    local path = u <= 7 or v <= 7 or abs(u - v) <= 1
    r.floor(u, v, path and "minecraft:mud_bricks" or MOSS)
  end)
  for u = 14, 19 do
    for v = 14, 19 do
      local edge = u == 14 or u == 19 or v == 14 or v == 19
      r.put(u, 1, v, edge and "minecraft:mossy_stone_bricks" or WATER)
    end
  end
  for _, t in ipairs({ { 23, 11 }, { 11, 23 }, { 23, 23 } }) do
    local tu, tv = t[1], t[2]
    for y = 1, 5 do r.put(tu, y, tv, "minecraft:oak_log") end
    for y = 4, 7 do
      local reach = y <= 5 and 3 or y == 6 and 2 or 1
      for a = -2, 2 do
        for b = -2, 2 do
          if abs(a) + abs(b) <= reach and (a ~= 0 or b ~= 0 or y > 5) then
            local leaves = r.noise(tu + a, tv + b + y) < 0.4 and "minecraft:flowering_azalea_leaves" or "minecraft:azalea_leaves"
            r.put(tu + a, y, tv + b, leaves)
          end
        end
      end
    end
  end
  local flowers = { "poppy", "dandelion", "cornflower", "allium", "azure_bluet", "azalea" }
  r.each(function(u, v)
    local n = r.noise(u, v)
    if n > 0.93 and u > 7 and v > 7 and abs(u - v) > 1 and r.empty(u, 1, v) and r.ground(u, v) == MOSS then
      r.put(u, 1, v, "minecraft:" .. flowers[math.floor(n * 1000) % #flowers + 1])
    end
  end)
end }

-- top, south-east: the armoury and range; armour stand spots on smooth
-- stone slabs, targets on posts along the east wall, a firing line
ROOMS[#ROOMS + 1] = { 1, 1, 18, function(r)
  alongV(r, 8, 24, function(u, v)
    if u % 2 == 0 then r.put(u, 1, v, "minecraft:smooth_stone_slab") else r.put(u, 1, v, BARREL) end
  end)
  for v = 10, 22, 3 do
    r.put(27, 1, v, POLISHED)
    r.put(27, 2, v, "minecraft:target")
    r.put(27, 1, v + 1, "minecraft:hay_block")
  end
  for v = 10, 23 do r.put(13, 1, v, "minecraft:white_carpet") end
  r.put(10, 1, 25, "minecraft:anvil")
  r.put(12, 1, 25, "minecraft:smithing_table")
  r.put(14, 1, 25, "minecraft:grindstone")
end }

for _, def in ipairs(ROOMS) do def[4](room(def[1], def[2], def[3])) end

---------------------------------------------------------------- out

-- the builder's home column in the well, and the floor under its two chests, stay empty
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
