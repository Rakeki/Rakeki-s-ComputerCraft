-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Cavern: a whole cave turned into a base, for the 63x63x30 hole 'excavate
-- cavern' digs. Rough rock walls of stone, tuff and dripstone bulge in and
-- curve over at the top, mossy up high, with stalactites and glowstone
-- specks on the ceiling and stalagmites on the floor. In the middle, a great
-- stalagnate pillar flares into the ceiling; a stair winds three sides round
-- it up to a lookout deck, and a bridge on stone piers runs from the deck to
-- the roof terrace of a three-storey house against the north wall: a hall
-- with a fireplace and kitchen, bedrooms and a storeroom, a library, and a
-- little tower on the roof. To the south-east, a lake fed by a waterfall
-- from high on the east wall, with a pier and a bridge to an island with an
-- azalea tree. To the south-west, a grove of giant mushrooms on mycelium.
-- Along the west wall, three farm terraces (sugar cane, berries and
-- pumpkins, mushrooms) with stairs up them; along the east wall, a mine
-- depot: a track out of a timbered tunnel, ore heaps and a smithy. In the
-- north-west corner a blackstone grotto with a portal on a dais; in the
-- north-east an amethyst grotto with an enchanting table. Cobbled paths join
-- them all, lit by froglights set into the floor.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 63, 63, 30
local TOP = H - 2
local C = 31 -- the middle (x and z): the pillar
local HOME = { x = 22, z = 36 }
local cavern = { name = "Cavern", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local DECK = 15 -- the lookout deck, bridge and roof terrace (you stand on them at 16)
local STAIR = "minecraft:spruce_stairs"
local PLANKS = "minecraft:spruce_planks"
local FENCE = "minecraft:spruce_fence"
local POST = "minecraft:stripped_dark_oak_log"
local BEAM = "minecraft:stripped_dark_oak_wood"
local LAMP = "minecraft:lantern"

local grid = {}
local function key(x, y, z) return (y * L + z) * W + x end
local function set(x, y, z, block)
  if x >= 0 and x < W and z >= 0 and z < L and y >= 0 and y <= TOP then grid[key(x, y, z)] = block end
end
local function get(x, y, z) return grid[key(x, y, z)] end
local function fill(x0, y0, z0, x1, y1, z1, block)
  for y = y0, y1 do
    for z = z0, z1 do
      for x = x0, x1 do set(x, y, z, block) end
    end
  end
end
local function carve(x0, y0, z0, x1, y1, z1) fill(x0, y0, z0, x1, y1, z1, nil) end
local function stair(facing, base) return (base or STAIR) .. "[facing=" .. facing .. "]" end

-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 73856093 + y * 19349663 + z * 83492791) % 1000003
  h = h * h % 1000003
  return (h * 7919 + 13) % 1000003 / 1000003
end
-- noise that changes smoothly over about s blocks: for patches and bulges.
-- Corner values are cached: the walls alone ask for this some 40,000 times.
local corners = {}
local function corner(x, y, z)
  local k = (y * 64 + z) * 64 + x
  local v = corners[k]
  if not v then
    v = noise(x + 101, y + 57, z + 31)
    corners[k] = v
  end
  return v
end
local function smooth(x, y, z, s)
  local fx, fy, fz = x / s, y / s, z / s
  local x0, y0, z0 = math.floor(fx), math.floor(fy), math.floor(fz)
  local tx, ty, tz = fx - x0, fy - y0, fz - z0
  tx, ty, tz = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty), tz * tz * (3 - 2 * tz)
  local a = corner(x0, y0, z0) + (corner(x0 + 1, y0, z0) - corner(x0, y0, z0)) * tx
  local b = corner(x0, y0 + 1, z0) + (corner(x0 + 1, y0 + 1, z0) - corner(x0, y0 + 1, z0)) * tx
  local c = corner(x0, y0, z0 + 1) + (corner(x0 + 1, y0, z0 + 1) - corner(x0, y0, z0 + 1)) * tx
  local d = corner(x0, y0 + 1, z0 + 1) + (corner(x0 + 1, y0 + 1, z0 + 1) - corner(x0, y0 + 1, z0 + 1)) * tx
  local ab, cd = a + (b - a) * ty, c + (d - c) * ty
  return ab + (cd - ab) * tz
end

---------------------------------------------------------------- where things are

local LAKE = { x = 46, z = 48, rx = 13, rz = 11 }
local ISLAND = { x = 48, z = 50, r = 2.6 }
local FALL = { x = W - 1, y = 22, z = 47 } -- the waterfall's spring
local function isIsland(x, z) return (x - ISLAND.x) ^ 2 + (z - ISLAND.z) ^ 2 <= ISLAND.r ^ 2 end
local lake = {} -- x, z -> is it lake: worked out once
for z = 0, L - 1 do
  for x = 0, W - 1 do
    local dx, dz = (x - LAKE.x) / LAKE.rx, (z - LAKE.z) / LAKE.rz
    local yes = z >= FALL.z - 1 and z <= FALL.z + 1 and x >= LAKE.x -- the channel to the falls
      or x < W - 1 and z < L - 1 and dx * dx + dz * dz < 0.8 + smooth(x, 0, z, 4) * 0.4
    lake[z * W + x] = yes and not isIsland(x, z)
  end
end
local function isLake(x, z) return x >= 0 and x < W and z >= 0 and z < L and lake[z * W + x] end
local function nearLake(x, z)
  for dz = -1, 1 do
    for dx = -1, 1 do
      if isLake(x + dx, z + dz) then return true end
    end
  end
  return false
end

local function region(x, z)
  if x >= 19 and x <= 43 and z <= 13 then return "house" end
  if x >= 46 and z <= 13 then return "grotto" end
  if x <= 17 and z <= 13 then return "portal" end
  if x <= 12 and z >= 15 and z <= 37 then return "farm" end
  if x >= 46 and z >= 15 and z <= 29 then return "depot" end
  if x <= 27 and z >= 39 then return "grove" end
  if isLake(x, z) then return "lake" end
  return "cave"
end

-- cobbled paths, { x0, z0, x1, z1 }
local PATHS = {
  { 14, 14, 50, 15 }, -- along the house front, from grotto to grotto
  { 30, 16, 32, 27 }, -- house door to the pillar
  { 13, 30, 27, 32 }, -- pillar to the farm
  { 13, 24, 15, 29 }, -- up to the farm's stairs
  { 35, 30, 47, 32 }, -- pillar to the depot
  { 30, 35, 32, 51 }, -- pillar south to the lake
  { 30, 49, 36, 51 }, -- to the island bridge
  { 20, 43, 29, 45 }, -- to the mushroom grove
}
local function onPath(x, z)
  for _, p in ipairs(PATHS) do
    if x >= p[1] and x <= p[3] and z >= p[2] and z <= p[4] then return true end
  end
  return false
end

---------------------------------------------------------------- rock

-- the cave's rock, by place: a geode in the north-east, blackstone in the
-- north-west, deepslate low down, moss high up, dripstone in patches.
-- inner is how far this block is from the rock's face (0 = on the face).
local function rock(x, y, z, inner)
  local reg, n = region(x, z), noise(x, y, z)
  if reg == "grotto" then
    return inner == 0 and (n < 0.7 and "minecraft:amethyst_block" or "minecraft:calcite")
      or inner == 1 and "minecraft:calcite" or "minecraft:smooth_basalt"
  elseif reg == "portal" then
    return n < 0.45 and "minecraft:blackstone" or n < 0.8 and "minecraft:basalt"
      or n < 0.95 and "minecraft:polished_blackstone" or "minecraft:gilded_blackstone"
  end
  if y > TOP - 9 and smooth(x, y, z, 4) > 0.55 then return n < 0.85 and "minecraft:moss_block" or "minecraft:mossy_cobblestone" end
  if smooth(z, y, x, 6) > 0.62 then return n < 0.8 and "minecraft:dripstone_block" or "minecraft:calcite" end
  if y < 7 + n * 4 then return n < 0.5 and "minecraft:deepslate" or n < 0.8 and "minecraft:tuff" or "minecraft:cobbled_deepslate" end
  return n < 0.5 and "minecraft:stone" or n < 0.72 and "minecraft:andesite" or n < 0.9 and "minecraft:tuff" or "minecraft:cobblestone"
end

-- walls: rock bulges in up to three blocks, and curves in under the ceiling
for y = 1, TOP do
  local extra = y > TOP - 6 and math.floor((y - (TOP - 6)) / 2) or 0
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local d = math.min(x, z, W - 1 - x, L - 1 - z)
      if d < 3 + extra then
        local s = smooth(x, y, z, 5)
        local depth = (s < 0.42 and 0 or s < 0.68 and 1 or s < 0.86 and 2 or 3) + extra
        if d < depth then set(x, y, z, rock(x, y, z, depth - 1 - d)) end
      end
    end
  end
end

-- stalactites from the ceiling, and glowstone specks between them
for gz = 3, L - 4, 6 do
  for gx = 3, W - 4, 6 do
    local n = noise(gx, TOP, gz)
    if n < 0.6 then
      local x, z = gx + math.floor(noise(gz, 1, gx) * 3) - 1, gz + math.floor(noise(gx, 2, gz) * 3) - 1
      local len = 1 + math.floor(n * 8)
      for y = TOP - len + 1, TOP do set(x, y, z, "minecraft:dripstone_block") end
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        set(x + d[1], TOP, z + d[2], noise(x + d[1], TOP, z + d[2]) < 0.6 and "minecraft:dripstone_block" or "minecraft:tuff")
        if len >= 4 then set(x + d[1], TOP - 1, z + d[2], "minecraft:dripstone_block") end
      end
    end
  end
end
for z = 4, L - 5 do
  for x = 4, W - 5 do
    if noise(x, 99, z) < 0.012 and not get(x, TOP, z) then set(x, TOP, z, "minecraft:glowstone") end
  end
end

---------------------------------------------------------------- floor

local plain = {} -- floor cells that may get a stalagmite or a floor light
for z = 0, L - 1 do
  for x = 0, W - 1 do
    local reg, n, s = region(x, z), noise(x, 0, z), smooth(x, 0, z, 6)
    local block
    if reg == "lake" then
      block = "minecraft:water"
    elseif isIsland(x, z) then
      block = "minecraft:moss_block"
    elseif onPath(x, z) and reg ~= "house" then
      block = n < 0.5 and "minecraft:cobblestone" or n < 0.8 and "minecraft:mossy_cobblestone" or "minecraft:stone_bricks"
    elseif nearLake(x, z) then
      block = n < 0.5 and "minecraft:sand" or n < 0.75 and "minecraft:clay" or "minecraft:gravel"
    elseif reg == "grove" then
      block = s < 0.6 and "minecraft:mycelium" or n < 0.6 and "minecraft:podzol" or "minecraft:moss_block"
    elseif reg == "grotto" then
      block = n < 0.7 and "minecraft:calcite" or n < 0.92 and "minecraft:smooth_basalt" or "minecraft:amethyst_block"
    elseif reg == "portal" then
      block = n < 0.5 and "minecraft:blackstone" or n < 0.85 and "minecraft:polished_blackstone" or "minecraft:basalt"
    else
      local g, m = smooth(z, 0, x, 5), smooth(x, 3, z, 7)
      block = m > 0.66 and "minecraft:moss_block" or g < 0.3 and "minecraft:gravel"
        or n < 0.4 and "minecraft:stone" or n < 0.6 and "minecraft:tuff" or n < 0.8 and "minecraft:andesite"
        or "minecraft:cobblestone"
    end
    set(x, 0, z, block)
    if reg ~= "lake" and reg ~= "house" and reg ~= "farm" and not isIsland(x, z) then plain[z * W + x] = true end
  end
end

---------------------------------------------------------------- the pillar, its stair and the lookout deck

carve(C - 7, 1, C - 7, C + 7, DECK + 4, C + 7)
local function pillarRock(x, y, z)
  local s = smooth(x, y, z, 3)
  return s < 0.35 and "minecraft:dripstone_block" or s < 0.65 and "minecraft:tuff"
    or s < 0.78 and "minecraft:calcite" or "minecraft:dripstone_block"
end
-- a 5x5 trunk floor to ceiling, flaring out over the deck into the ceiling
for y = 0, TOP do
  local r = y < DECK + 5 and 0 or 2.5 + (y - DECK - 4) * 0.55
  for dz = -8, 8 do
    for dx = -8, 8 do
      local inTrunk = math.abs(dx) <= 2 and math.abs(dz) <= 2
      if inTrunk or dx * dx + dz * dz <= r * r then set(C + dx, y, C + dz, pillarRock(C + dx, y, C + dz)) end
    end
  end
end
for _, y in ipairs({ 3, 8, 13 }) do
  for _, d in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
    set(C + d[1], y, C + d[2], "minecraft:pearlescent_froglight")
  end
end
-- froglights round the flare's underside
for dz = -4, 4 do
  for dx = -4, 4 do
    local r2 = dx * dx + dz * dz
    if r2 > 4 and r2 <= 9.5 and noise(dx + 50, DECK + 5, dz + 50) < 0.35 then
      set(C + dx, DECK + 5, C + dz, "minecraft:ochre_froglight")
    end
  end
end

-- the stair: from the floor at the north-west corner, round three sides
-- (east, south, west) of a ring one block out from the trunk, a block up a step
local SIDES = {
  { from = { -3, -3 }, step = { 1, 0 }, facing = "east", out = { 0, -1 } },
  { from = { 3, -3 }, step = { 0, 1 }, facing = "south", out = { 1, 0 } },
  { from = { 3, 3 }, step = { -1, 0 }, facing = "west", out = { 0, 1 } },
}
local stepAt = {} -- ring cell -> height of the step on it
local sy = 0
stepAt[(C - 3) .. "," .. (C - 3)] = 0
for _, side in ipairs(SIDES) do
  for i = 1, 6 do
    local x, z = C + side.from[1] + side.step[1] * i, C + side.from[2] + side.step[2] * i
    if i <= 5 then
      sy = sy + 1
      set(x, sy, z, stair(side.facing))
      -- a handrail on the outside, where the deck isn't
      if sy + 1 < DECK then set(x + side.out[1], sy + 1, z + side.out[2], FENCE) end
    else
      set(x, sy, z, PLANKS) -- the corner landing
    end
    stepAt[x .. "," .. z] = sy
  end
end

-- the deck: round the trunk out to 6.5, open above the last steps
for dz = -7, 7 do
  for dx = -7, 7 do
    local x, z = C + dx, C + dz
    local r = math.sqrt(dx * dx + dz * dz)
    local cheb = math.max(math.abs(dx), math.abs(dz))
    local step = stepAt[x .. "," .. z]
    if cheb >= 3 and r <= 6.5 and (not step or step <= DECK - 3) then
      set(x, DECK, z, r > 5.5 and "minecraft:stripped_spruce_wood" or PLANKS)
      local bridgeGap = dz < 0 and math.abs(dx) <= 1
      if r > 5.5 and not bridgeGap then
        set(x, DECK + 1, z, FENCE)
        if dx == 0 or dz == 0 or math.abs(dx) == math.abs(dz) then set(x, DECK + 2, z, LAMP) end
      end
    end
  end
end
-- posts under the deck, a few barrels and benches on it
for _, d in ipairs({ { 4, 4 }, { -4, 4 }, { 4, -4 }, { -4, -4 } }) do
  fill(C + d[1], 1, C + d[2], C + d[1], DECK - 1, C + d[2], POST)
end
set(C + 5, DECK + 1, C + 1, "minecraft:barrel")
set(C + 5, DECK + 1, C + 2, "minecraft:barrel")
set(C + 5, DECK + 2, C + 2, "minecraft:candle")
set(C - 5, DECK + 1, C - 1, stair("east")) -- benches facing out
set(C - 5, DECK + 1, C + 1, stair("east"))
set(C + 3, DECK + 1, C - 4, "minecraft:cartography_table")

---------------------------------------------------------------- the bridge to the house

local BZ0, BZ1 = 14, C - 7 -- the house's roof terrace to the deck
carve(C - 2, DECK - 1, BZ0, C + 2, DECK + 4, BZ1)
for z = BZ0, BZ1 do
  for x = C - 1, C + 1 do set(x, DECK, z, x == C and "minecraft:stripped_spruce_wood" or PLANKS) end
  set(C - 2, DECK + 1, z, FENCE)
  set(C + 2, DECK + 1, z, FENCE)
  if (z - BZ0) % 4 == 2 then
    set(C - 2, DECK + 2, z, LAMP)
    set(C + 2, DECK + 2, z, LAMP)
  end
end
-- two stone piers either side of the path, a beam across under the deck
local PIER_Z = 20
for _, x in ipairs({ C - 2, C + 2 }) do
  for y = 1, DECK - 1 do
    set(x, y, PIER_Z, y % 4 == 0 and "minecraft:chiseled_stone_bricks"
      or noise(x, y, PIER_Z) < 0.3 and "minecraft:mossy_stone_bricks" or "minecraft:stone_bricks")
  end
end
fill(C - 1, DECK - 1, PIER_Z, C + 1, DECK - 1, PIER_Z, BEAM)

---------------------------------------------------------------- the house

local HX0, HX1, HZ0, HZ1 = 19, 43, 0, 13
local FLOORS = { 0, 5, 10, DECK } -- the storeys' floors, and the roof terrace
carve(HX0, 1, HZ0, HX1, TOP - 2, HZ1)
local isPostX = { [19] = true, [25] = true, [31] = true, [37] = true, [43] = true }
local isPostZ = { [0] = true, [7] = true, [13] = true }

-- floors, with shroomlights set in them to light the storey below
for i, fy in ipairs(FLOORS) do
  for z = HZ0, HZ1 do
    for x = HX0, HX1 do
      local edge = x == HX0 or x == HX1 or z == HZ0 or z == HZ1
      local inner = i == 1 and (noise(x, 0, z) < 0.15 and "minecraft:cracked_deepslate_tiles" or "minecraft:deepslate_tiles")
        or (z == 4 or z == 10) and "minecraft:stripped_spruce_wood" or PLANKS
      set(x, fy, z, edge and fy > 0 and BEAM or inner)
    end
  end
  if fy > 0 then
    for _, x in ipairs({ 22, 28, 34, 40 }) do set(x, fy, 7, "minecraft:shroomlight") end
  end
end
-- walls: dark oak posts, deepslate below, spruce above, windows in each bay
for y = 1, DECK - 1 do
  local storey = math.floor(y / 5) -- 0, 1, 2
  local wy = y % 5
  if wy ~= 0 then
    for z = HZ0, HZ1 do
      for x = HX0, HX1 do
        local front, back, side = z == HZ1, z == HZ0, x == HX0 or x == HX1
        if front or back or side then
          local post = (front or back) and isPostX[x] or side and isPostZ[z]
          local bay = (front or back) and (x - HX0) % 6 or 0
          local window = (wy == 2 or wy == 3) and not back
            and ((front and bay >= 2 and bay <= 4) or (side and (z == 2 or z == 3 or z == 10 or z == 11)))
          local wall = storey == 0 and (noise(x, y, z) < 0.12 and "minecraft:cracked_deepslate_bricks" or "minecraft:deepslate_bricks")
            or PLANKS
          set(x, y, z, post and POST or window and "minecraft:glass_pane" or wall)
        end
      end
    end
  end
end
-- the front door, with a lamp post either side
fill(C - 1, 1, HZ1, C + 1, 3, HZ1, nil)
for _, x in ipairs({ C - 2, C + 2 }) do
  set(x, 1, HZ1 + 1, FENCE)
  set(x, 2, HZ1 + 1, LAMP)
end

-- ground floor: a fireplace and dining table to the west, a kitchen east
fill(20, 1, 5, 20, 4, 9, "minecraft:bricks")
set(20, 1, 7, "minecraft:campfire")
set(20, 2, 7, nil)
set(20, 4, 6, "minecraft:polished_deepslate")
set(20, 4, 8, "minecraft:polished_deepslate")
set(20, 4, 7, "minecraft:chiseled_stone_bricks")
for z = 6, 8 do
  for x = 21, 23 do set(x, 1, z, "minecraft:brown_carpet") end
end
set(24, 1, 6, stair("east"))
set(24, 1, 8, stair("east"))
for x = 22, 28 do
  set(x, 1, 3, "minecraft:stripped_spruce_wood")
  if x % 2 == 0 then
    set(x, 1, 2, stair("north"))
    set(x, 1, 4, stair("south"))
  end
  if x == 23 or x == 27 then set(x, 2, 3, "minecraft:candle") end
end
set(25, 2, 3, LAMP)
for _, x in ipairs({ 25, 37 }) do fill(x, 1, 7, x, 4, 7, POST) end
local COUNTER = { "minecraft:smoker[facing=west]", "minecraft:furnace[facing=west]", "minecraft:crafting_table",
  "minecraft:barrel", "minecraft:cauldron", "minecraft:barrel", "minecraft:blast_furnace[facing=west]", "minecraft:composter" }
for i, block in ipairs(COUNTER) do set(42, 1, i + 3, block) end
set(42, 2, 7, LAMP)
for x = 34, 36 do
  for z = 7, 8 do set(x, 1, z, "minecraft:stripped_spruce_wood") end
end
set(34, 2, 7, "minecraft:candle")
set(36, 2, 8, "minecraft:candle")
for x = 34, 40 do set(x, 1, 12, "minecraft:chest[facing=north]") end
set(41, 1, 12, "minecraft:barrel")
set(41, 2, 12, LAMP)

-- first floor: a bedroom west, a storeroom east, a wall with a door between
for z = 1, 12 do
  for y = 6, 9 do
    if not ((z == 6 or z == 7) and y <= 8) then set(C, y, z, PLANKS) end
  end
end
for _, z in ipairs({ 5, 8, 11 }) do
  set(20, 6, z, "minecraft:red_carpet")
  set(21, 6, z, "minecraft:red_carpet")
  set(20, 6, z + 1, "minecraft:barrel")
  set(20, 7, z + 1, "minecraft:candle")
end
for z = 5, 11 do set(24, 6, z, "minecraft:white_carpet") end
for z = 3, 11 do
  if z < 6 or z > 7 then
    for y = 6, 8 do set(30, y, z, "minecraft:bookshelf") end
  end
end
set(29, 6, 5, "minecraft:chest[facing=west]")
set(29, 6, 8, "minecraft:chest[facing=west]")
set(29, 7, 8, LAMP)
for x = 33, 40 do
  for _, z in ipairs({ 5, 9 }) do
    set(x, 6, z, "minecraft:chest[facing=" .. (z == 5 and "south" or "north") .. "]")
    set(x, 7, z, "minecraft:barrel")
  end
end
for x = 33, 41 do set(x, 6, 12, "minecraft:barrel") end
set(36, 8, 5, LAMP)
set(36, 8, 9, LAMP)

-- second floor: the library and map room
for z = 3, 12 do
  for y = 11, 13 do set(20, y, z, "minecraft:bookshelf") end
end
for _, z in ipairs({ 6, 9 }) do
  for x = 22, 28 do
    for y = 11, 12 do set(x, y, z, "minecraft:bookshelf") end
  end
  set(25, 13, z, LAMP)
end
set(25, 11, 12, "minecraft:lectern[facing=north]")
for x = 34, 38 do
  for z = 6, 8 do set(x, 11, z, (x == 36 and z == 7) and "minecraft:cartography_table" or "minecraft:stripped_spruce_wood") end
end
set(34, 12, 6, "minecraft:candle")
set(38, 12, 8, "minecraft:candle")
set(42, 11, 6, "minecraft:barrel")
set(42, 11, 7, "minecraft:barrel")
set(42, 12, 7, LAMP)
for x = 33, 41 do set(x, 11, 12, "minecraft:bookshelf") end

-- the roof terrace: a parapet with lamps, planters, and a tower
for z = HZ0, HZ1 do
  for x = HX0, HX1 do
    local edge = x == HX0 or x == HX1 or z == HZ0 or z == HZ1
    if edge and not (z == HZ1 and math.abs(x - C) <= 1) then
      set(x, DECK + 1, z, "minecraft:deepslate_brick_wall")
      if isPostX[x] and (z == HZ0 or z == HZ1) or (x == HX0 or x == HX1) and isPostZ[z] then
        set(x, DECK + 2, z, LAMP)
      end
    end
  end
end
for _, p in ipairs({ { 21, 10 }, { 41, 10 }, { 21, 3 } }) do
  for dz = 0, 1 do
    for dx = 0, 1 do
      set(p[1] + dx, DECK + 1, p[2] + dz, "minecraft:moss_block")
      set(p[1] + dx, DECK + 2, p[2] + dz, (dx + dz) % 2 == 0 and "minecraft:flowering_azalea" or "minecraft:azalea")
    end
  end
end
for _, x in ipairs({ 25, 37 }) do set(x, DECK + 1, 11, stair("north")) end

local TX0, TX1, TZ0, TZ1, TTOP = 27, 35, 1, 7, DECK + 5 -- the tower: walls up to TTOP
for y = DECK + 1, TTOP do
  for z = TZ0, TZ1 do
    for x = TX0, TX1 do
      local corner = (x == TX0 or x == TX1) and (z == TZ0 or z == TZ1)
      local wall = x == TX0 or x == TX1 or z == TZ0 or z == TZ1
      if y == TTOP then
        set(x, y, z, wall and BEAM or PLANKS)
      elseif corner then
        set(x, y, z, POST)
      elseif wall then
        local window = (y == DECK + 2 or y == DECK + 3) and ((z == TZ0 or z == TZ1) and x % 2 == 0 or (x == TX0 or x == TX1) and z % 2 == 0)
        local door = z == TZ1 and x == C and y <= DECK + 2
        if not door then set(x, y, z, window and "minecraft:glass_pane" or "minecraft:dark_oak_planks") end
      else
        set(x, y, z, nil)
      end
    end
  end
end
set(C, DECK + 1, TZ0 + 1, "minecraft:lectern[facing=south]")
set(TX0 + 1, DECK + 1, TZ0 + 1, "minecraft:chest[facing=east]")
set(TX1 - 1, DECK + 1, TZ0 + 1, "minecraft:barrel")
set(TX1 - 1, DECK + 2, TZ0 + 1, LAMP)
set(TX0 + 1, DECK + 1, TZ1 - 1, LAMP)
-- its hipped roof, eaves out a block, stairs climbing to a ridge
for i = 0, 5 do
  local x0, x1, z0, z1, y = TX0 - 1 + i, TX1 + 1 - i, math.max(TZ0 - 1 + i, 0), TZ1 + 1 - i, TTOP + 1 + i
  if x0 > x1 or z0 > z1 then break end
  for z = z0, z1 do
    for x = x0, x1 do
      local block = "minecraft:dark_oak_planks"
      if z == z1 and z1 > z0 then block = stair("north", "minecraft:dark_oak_stairs")
      elseif z == z0 and z1 > z0 then block = stair("south", "minecraft:dark_oak_stairs")
      elseif x == x0 and x1 > x0 then block = stair("east", "minecraft:dark_oak_stairs")
      elseif x == x1 and x1 > x0 then block = stair("west", "minecraft:dark_oak_stairs") end
      set(x, y, z, block)
    end
  end
end

-- the stairs, two wide along the back wall: up east, up west, up east to
-- the roof. Each clears the room for your head, cutting its stairwell.
local function flight(x0, y0, dir, z0)
  for i = 0, 3 do
    local x, y = x0 + dir * i, y0 + i
    for z = z0, z0 + 1 do
      set(x, y, z, stair(dir > 0 and "east" or "west"))
      set(x, y + 1, z, nil)
      set(x, y + 2, z, nil)
    end
  end
end
local function well(x0, x1, y, rail)
  for x = x0, x1 do set(x, y, 3, FENCE) end
  set(rail, y, 1, FENCE)
  set(rail, y, 2, FENCE)
end
flight(37, 1, 1, 1)
well(39, 40, 6, 38)
flight(26, 6, -1, 1)
well(23, 24, 11, 25)
flight(37, 11, 1, 1)
well(39, 40, DECK + 1, 38)

---------------------------------------------------------------- the farm terraces (west wall)

local TIERS = {
  { x0 = 9, x1 = 12, top = 1, crop = "cane" },
  { x0 = 5, x1 = 8, top = 3, crop = "berry" },
  { x0 = 1, x1 = 4, top = 5, crop = "mushroom" },
}
local FZ0, FZ1, FSTAIR = 16, 36, 25 -- the terraces' ends, and their stairs (FSTAIR and FSTAIR + 1)
carve(1, 1, FZ0, 12, 12, FZ1)
for _, t in ipairs(TIERS) do
  for z = FZ0, FZ1 do
    for x = t.x0, t.x1 do
      local front, ends = x == t.x1, z == FZ0 or z == FZ1
      for y = 0, t.top - 1 do
        set(x, y, z, (front or ends) and (noise(x, y, z) < 0.3 and "minecraft:mossy_stone_bricks" or "minecraft:stone_bricks")
          or "minecraft:cobblestone")
      end
      local stairs = z == FSTAIR or z == FSTAIR + 1
      local top, above
      if front or ends or stairs then
        top = "minecraft:mossy_stone_bricks"
      elseif x == t.x0 + 1 then
        top = "minecraft:water"
      else
        local n = noise(x, t.top, z)
        if t.crop == "cane" then
          top, above = "minecraft:moss_block", "minecraft:sugar_cane"
        elseif t.crop == "berry" then
          top = "minecraft:moss_block"
          above = n < 0.6 and "minecraft:sweet_berry_bush" or n < 0.8 and "minecraft:pumpkin" or "minecraft:melon"
        else
          top = "minecraft:mycelium"
          above = n < 0.5 and "minecraft:red_mushroom" or "minecraft:brown_mushroom"
        end
      end
      set(x, t.top, z, top)
      if above then set(x, t.top + 1, z, above) end
    end
    if z % 6 == 1 and z ~= FSTAIR and z ~= FSTAIR + 1 then set(t.x1, t.top - 1, z, "minecraft:ochre_froglight") end
  end
  set(t.x1, t.top + 1, FZ0, "minecraft:composter")
  set(t.x1, t.top + 1, FZ1, "minecraft:barrel")
  set(t.x1, t.top + 2, FZ1, LAMP)
end
-- stairs up the fronts: one onto each tier from the one below
for z = FSTAIR, FSTAIR + 1 do
  for _, s in ipairs({ { 13, 1 }, { 9, 2 }, { 8, 3 }, { 5, 4 }, { 4, 5 } }) do
    set(s[1], s[2], z, stair("west"))
    set(s[1], s[2] + 1, z, nil)
    set(s[1], s[2] + 2, z, nil)
  end
end

---------------------------------------------------------------- the mine depot (east wall)

local TRACK_Z = 22
-- the tunnel mouth: rock walls and roof round timber frames, the track
-- running into the wall at its end (dig on from there)
carve(56, 1, TRACK_Z - 3, W - 1, 6, TRACK_Z + 3)
for x = 57, W - 1 do
  for y = 1, 6 do
    set(x, y, TRACK_Z - 3, rock(x, y, TRACK_Z - 3, 1))
    set(x, y, TRACK_Z + 3, rock(x, y, TRACK_Z + 3, 1))
  end
  for z = TRACK_Z - 2, TRACK_Z + 2 do set(x, 6, z, rock(x, 6, z, 1)) end
  for z = TRACK_Z - 2, TRACK_Z + 2 do set(x, 5, z, PLANKS) end
end
for _, x in ipairs({ 50, 54, 58, W - 1 }) do
  for y = 1, 4 do
    set(x, y, TRACK_Z - 2, "minecraft:spruce_log")
    set(x, y, TRACK_Z + 2, "minecraft:spruce_log")
  end
  for z = TRACK_Z - 2, TRACK_Z + 2 do set(x, 5, z, "minecraft:stripped_spruce_log") end
  if x < 56 then
    set(x + 1, 1, TRACK_Z - 2, FENCE)
    set(x + 1, 2, TRACK_Z - 2, LAMP)
  end
end
for x = 47, W - 1 do
  set(x, 0, TRACK_Z, "minecraft:gravel")
  set(x, 1, TRACK_Z, "minecraft:rail")
end
set(46, 1, TRACK_Z, "minecraft:hay_block") -- the buffer
-- ore heaps by the track, barrels stacked across it
for z = 17, 19 do
  for x = 48, 51 do
    local n = noise(x, 1, z)
    set(x, 1, z, n < 0.35 and "minecraft:raw_iron_block" or n < 0.6 and "minecraft:coal_block"
      or n < 0.8 and "minecraft:raw_copper_block" or "minecraft:cobblestone")
    if x > 48 and x < 51 and z == 18 then set(x, 2, z, n < 0.5 and "minecraft:raw_iron_block" or "minecraft:raw_gold_block") end
  end
end
for x = 53, 56 do
  for z = 17, 18 do
    set(x, 1, z, "minecraft:barrel")
    if x > 53 and x < 56 then set(x, 2, z, "minecraft:barrel") end
  end
end
-- the smithy along the south side, chests behind it
local SMITHY = { "minecraft:blast_furnace[facing=north]", "minecraft:furnace[facing=north]", "minecraft:smithing_table",
  "minecraft:anvil[facing=east]", "minecraft:grindstone[facing=north]", "minecraft:stonecutter", "minecraft:cauldron",
  "minecraft:barrel", "minecraft:crafting_table" }
for i, block in ipairs(SMITHY) do
  set(47 + i, 1, 27, block)
  set(47 + i, 1, 28, "minecraft:chest[facing=north]")
end
set(55, 2, 27, LAMP)
set(48, 2, 28, LAMP)
set(56, 2, 28, LAMP)

---------------------------------------------------------------- the amethyst grotto (north-east)

local EX, EZ = 54, 6 -- the enchanting table
carve(EX - 4, 1, EZ - 4, EX + 4, 6, EZ + 4)
for z = EZ - 3, EZ + 3 do
  for x = EX - 3, EX + 3 do
    local edge = math.max(math.abs(x - EX), math.abs(z - EZ)) == 3
    set(x, 1, z, edge and "minecraft:polished_deepslate" or "minecraft:calcite")
  end
end
set(EX, 1, EZ + 3, stair("north", "minecraft:deepslate_tile_stairs"))
set(EX, 2, EZ, "minecraft:enchanting_table")
for dz = -2, 2 do
  for dx = -2, 2 do
    if math.max(math.abs(dx), math.abs(dz)) == 2 and dx ~= 0 and dz ~= 0 then
      set(EX + dx, 2, EZ + dz, "minecraft:bookshelf")
      set(EX + dx, 3, EZ + dz, "minecraft:bookshelf")
    end
  end
end
for _, d in ipairs({ { 2, 2 }, { -2, 2 }, { 2, -2 }, { -2, -2 } }) do set(EX + d[1], 4, EZ + d[2], "minecraft:amethyst_cluster") end
set(EX + 2, 2, EZ + 3, "minecraft:lectern[facing=north]")
set(EX - 2, 2, EZ + 3, "minecraft:anvil[facing=east]")
-- crystal spires round it, and clusters on the floor
for _, s in ipairs({ { 48, 3, 4 }, { 49, 10, 6 }, { 60, 4, 5 }, { 59, 11, 3 }, { 47, 7, 2 } }) do
  for y = 1, s[3] do set(s[1], y, s[2], y == 2 and "minecraft:sea_lantern" or "minecraft:amethyst_block") end
  set(s[1], s[3] + 1, s[2], "minecraft:amethyst_cluster")
  set(s[1] + 1, 1, s[2], "minecraft:calcite")
  set(s[1], 1, s[2] + 1, "minecraft:amethyst_block")
end
for z = 1, 13 do
  for x = 46, W - 2 do
    if not get(x, 1, z) and noise(x, 1, z) < 0.07 then set(x, 1, z, "minecraft:amethyst_cluster") end
  end
end

---------------------------------------------------------------- the portal grotto (north-west)

local PX, PZ = 8, 5 -- the portal frame's west end
fill(PX - 3, 1, PZ - 2, PX + 6, 1, PZ + 4, "minecraft:polished_blackstone_bricks")
carve(PX - 3, 2, PZ - 2, PX + 6, 8, PZ + 4)
for x = PX - 3, PX + 6 do set(x, 1, PZ + 5, stair("north", "minecraft:polished_blackstone_brick_stairs")) end
for x = PX, PX + 3 do
  set(x, 2, PZ, "minecraft:obsidian")
  set(x, 6, PZ, "minecraft:obsidian")
end
for y = 3, 5 do
  set(PX, y, PZ, "minecraft:obsidian")
  set(PX + 3, y, PZ, "minecraft:obsidian")
end
set(PX - 1, 2, PZ, "minecraft:crying_obsidian")
set(PX + 4, 2, PZ, "minecraft:crying_obsidian")
for _, x in ipairs({ PX - 2, PX + 5 }) do
  for y = 2, 4 do set(x, y, PZ - 1, "minecraft:polished_blackstone_wall") end
  set(x, 5, PZ - 1, "minecraft:soul_lantern")
  set(x, 2, PZ + 3, "minecraft:soul_campfire")
end
set(PX + 1, 2, PZ + 3, "minecraft:ender_chest")
for _, p in ipairs({ { 3, 11 }, { 16, 11 }, { 2, 3 } }) do
  set(p[1], 1, p[2], "minecraft:crying_obsidian")
  set(p[1], 2, p[2], "minecraft:soul_lantern")
end

---------------------------------------------------------------- the mushroom grove (south-west)

local MUSHROOMS = {
  { x = 12, z = 51, h = 13, r = 5, kind = "red", thick = true },
  { x = 22, z = 56, h = 8, r = 3, kind = "brown" },
  { x = 6, z = 43, h = 7, r = 3, kind = "red" },
  { x = 21, z = 47, h = 10, r = 4, kind = "brown" },
  { x = 5, z = 57, h = 6, r = 3, kind = "brown" },
}
for _, m in ipairs(MUSHROOMS) do
  local cx, cz = m.x + (m.thick and 0.5 or 0), m.z + (m.thick and 0.5 or 0)
  local cap = m.kind == "red" and "minecraft:red_mushroom_block" or "minecraft:brown_mushroom_block"
  for y = 1, m.h do
    for dz = -m.r - 1, m.r + 1 do
      for dx = -m.r - 1, m.r + 1 do
        local x, z = m.x + dx, m.z + dz
        local d = math.sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
        local stem = d < (m.thick and 1 or 0.5) and y < m.h
        local block
        if stem then
          block = "minecraft:mushroom_stem"
        elseif m.kind == "red" then
          -- a dome: a top, sides hanging three blocks down
          if y == m.h and d <= m.r - 0.7 or y < m.h and y >= m.h - 3 and d > m.r - 0.7 and d <= m.r + 0.3 then block = cap end
        elseif y == m.h and d <= m.r + 0.4 then
          block = cap -- a flat brown cap
        end
        if block == cap and d > 1 and noise(x, y, z) < 0.12 then block = "minecraft:shroomlight" end
        if block then set(x, y, z, block) end
      end
    end
  end
  -- a shroomlight in the middle of each cap, so the top's lit too
  set(m.x, m.h, m.z, "minecraft:shroomlight")
end
-- a campfire to sit round, small mushrooms everywhere
set(17, 1, 54, "minecraft:campfire")
set(17, 1, 56, stair("north"))
set(15, 1, 54, stair("east"))
set(19, 1, 54, stair("west"))
for z = 39, L - 2 do
  for x = 1, 27 do
    local floor = get(x, 0, z)
    if (floor == "minecraft:mycelium" or floor == "minecraft:podzol") and not get(x, 1, z) and not onPath(x, z) then
      local n = noise(x, 1, z)
      if n < 0.07 then set(x, 1, z, "minecraft:red_mushroom")
      elseif n < 0.14 then set(x, 1, z, "minecraft:brown_mushroom") end
    end
  end
end

---------------------------------------------------------------- the lake: falls, island, bridge, pier

-- the falls: one spring high on the east wall in a lip of rock, pouring
-- straight down into the channel
carve(FALL.x, 1, FALL.z, FALL.x, FALL.y - 1, FALL.z)
carve(FALL.x - 1, 1, FALL.z, FALL.x - 1, FALL.y, FALL.z)
for _, d in ipairs({ { 0, 1, 0 }, { -1, 1, 0 }, { 0, 0, -1 }, { 0, 0, 1 }, { -1, 0, -1 }, { -1, 0, 1 } }) do
  set(FALL.x + d[1], FALL.y + d[2], FALL.z + d[3], "minecraft:mossy_cobblestone")
end
set(FALL.x, FALL.y, FALL.z, "minecraft:water")

-- the island: an azalea tree, a bench and a lamp
local TX, TZ = ISLAND.x, ISLAND.z
for y = 1, 6 do set(TX, y, TZ, "minecraft:oak_log") end
for y = 4, 8 do
  local r = y == 8 and 1.2 or y == 4 and 2 or 3
  for dz = -3, 3 do
    for dx = -3, 3 do
      local d = math.sqrt(dx * dx + dz * dz)
      if d <= r and (dx ~= 0 or dz ~= 0 or y > 6) and noise(TX + dx, y, TZ + dz) + y * 0.01 < 0.92 then
        set(TX + dx, y, TZ + dz, noise(TZ + dz, y, TX + dx) < 0.3 and "minecraft:flowering_azalea_leaves" or "minecraft:azalea_leaves")
      end
    end
  end
end
set(TX + 1, 1, TZ + 2, stair("north"))
set(TX - 1, 1, TZ + 2, stair("north"))
set(TX + 2, 1, TZ - 1, FENCE)
set(TX + 2, 2, TZ - 1, LAMP)

-- the bridge: from the path's end to the island, a step up at each end
local BRIDGE_Z = 50
local bx0, bx1
for x = 30, TX do
  if isLake(x, BRIDGE_Z) then
    bx0 = bx0 or x
    bx1 = x
  end
end
if bx0 then
  for x = bx0 - 1, bx1 + 1 do
    for z = BRIDGE_Z - 1, BRIDGE_Z + 1 do
      local block = x == bx0 - 1 and stair("east") or x == bx1 + 1 and stair("west") or PLANKS
      set(x, 1, z, block)
      set(x, 2, z, nil)
    end
    if x >= bx0 and x <= bx1 then
      set(x, 2, BRIDGE_Z - 2, FENCE)
      set(x, 2, BRIDGE_Z + 2, FENCE)
      if (x - bx0) % 4 == 1 then
        set(x, 3, BRIDGE_Z - 2, LAMP)
        set(x, 3, BRIDGE_Z + 2, LAMP)
      end
    end
  end
end

-- a pier out from the north shore, a barrel and lamps at its end
local PIER_X = 44
local pz0
for z = 30, L - 1 do
  if isLake(PIER_X, z) then
    pz0 = z
    break
  end
end
if pz0 then
  for z = pz0 - 1, pz0 + 5 do
    for x = PIER_X, PIER_X + 1 do
      set(x, 0, z, z % 3 == 0 and "minecraft:stripped_spruce_wood" or PLANKS)
      set(x, 1, z, nil)
    end
  end
  set(PIER_X, 1, pz0 + 5, FENCE)
  set(PIER_X, 2, pz0 + 5, LAMP)
  set(PIER_X + 1, 1, pz0 + 5, "minecraft:barrel")
end

-- sugar cane in clumps along the sandy banks, where water is right beside it
local function byWater(x, z)
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    if get(x + d[1], 0, z + d[2]) == "minecraft:water" then return true end
  end
  return false
end
for z = 30, L - 2 do
  for x = 30, W - 2 do
    local floor = get(x, 0, z)
    if floor == "minecraft:sand" and byWater(x, z) and not get(x, 1, z) and not onPath(x, z) and noise(x, 7, z) < 0.35 then
      set(x, 1, z, "minecraft:sugar_cane")
    end
  end
end

---------------------------------------------------------------- stalagmites and floor lights

local function nearHome(x, z) return math.abs(x - HOME.x) <= 2 and math.abs(z - HOME.z) <= 2 end
for gz = 2, L - 3, 5 do
  for gx = 2, W - 3, 5 do
    local x, z = gx + math.floor(noise(gz, 5, gx) * 3), gz + math.floor(noise(gx, 6, gz) * 3)
    local n = noise(x, 1, z)
    local clear = true
    for dz = -1, 1 do
      for dx = -1, 1 do
        local k = (z + dz) * W + x + dx
        if not plain[k] or onPath(x + dx, z + dz) or get(x + dx, 1, z + dz) then clear = false end
      end
    end
    local reg = region(x, z)
    if clear and n < 0.55 and reg == "cave" and not nearLake(x, z) and not nearHome(x, z) then
      local tall = 1 + math.floor(n * 6)
      for y = 1, tall do set(x, y, z, "minecraft:dripstone_block") end
      set(x, tall + 1, z, "minecraft:pointed_dripstone")
      if tall >= 3 then
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          if noise(x + d[1], 2, z + d[2]) < 0.6 then
            set(x + d[1], 1, z + d[2], "minecraft:dripstone_block")
            set(x + d[1], 2, z + d[2], "minecraft:pointed_dripstone")
          end
        end
      end
    end
  end
end

-- a froglight in the floor every eight blocks, so nothing spawns in the dark
local FLOOR_LIGHT = { grove = "minecraft:shroomlight", grotto = "minecraft:pearlescent_froglight",
  portal = "minecraft:shroomlight" }
for z = 4, L - 1, 8 do
  for x = 4, W - 1, 8 do
    if plain[z * W + x] and not get(x, 1, z) and not nearLake(x, z) then
      set(x, 0, z, FLOOR_LIGHT[region(x, z)] or "minecraft:ochre_froglight")
    end
  end
end

---------------------------------------------------------------- out

-- the builder's home column, and its two chests' spots, stay empty
for y = 0, TOP do set(HOME.x, y, HOME.z, nil) end
for y = 0, 3 do
  set(HOME.x, y, HOME.z - 1, nil)
  set(HOME.x + 1, y, HOME.z, nil)
end

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = grid[key(x, y, z)]
      if block then cavern.blocks[#cavern.blocks + 1] = { x, y, z, block } end
    end
  end
end
return cavern
