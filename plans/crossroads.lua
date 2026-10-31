-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Crossroads: a base dug into a hill, for the 45x45x10 hole 'excavate
-- crossroads' digs. In the middle, a raised courtyard of moss under a grid
-- of froglights like daylight: stone paths in a cross, planters with water
-- channels and sugar cane, and an enchanting table ringed by bookshelves on
-- a little plaza. Four oak-walled wings run out from it in a cross, sunk two
-- blocks below the courtyard with steps down into each: a bedroom (bed
-- spots marked with carpet), a library, a kitchen with storage, and a
-- workshop with brewing. Their roofs are turfed with moss and ferns.
-- Between the wings, four sunken gardens with an azalea tree, a pond with
-- sugar cane and flowers, each with steps up to the courtyard's corner.
--
-- Drawn for the north wing and the north-west garden, then turned round
-- the middle three times (facings too); only the wings' furniture differs.
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 45, 45, 10
local TOP = H - 2
local HOME = { x = 8, z = 8 }
local crossroads = { name = "Crossroads", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local C = 22 -- the middle (x and z)
local COURT = 7 -- the courtyard runs C - 7 to C + 7
local COURT_TOP = 2 -- the courtyard's surface layer (you stand on it at 3)
local WING_HALF = 5 -- wings are 11 wide: C - 5 to C + 5, walls included
local WING_TOP = 6 -- the wings' ceiling; their turf roof is the layer above
local LIGHT = "minecraft:ochre_froglight"
local PLANKS = "minecraft:oak_planks"
local POST = "minecraft:stripped_oak_log"
local FLOOR = "minecraft:spruce_planks"
local BEAM = "minecraft:stripped_spruce_wood"

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
local function get(x, y, z) return grid[x .. "," .. y .. "," .. z] end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end

-- k quarter turns clockwise round the middle, facings with it
local FACINGS = { north = 0, east = 1, south = 2, west = 3 }
local NAMES = { [0] = "north", "east", "south", "west" }
local function turn(x, z, k)
  local dx, dz = x - C, z - C
  for _ = 1, k do dx, dz = -dz, dx end
  return C + dx, C + dz
end
local function turnBlock(block, k)
  return (block:gsub("facing=(%a+)", function(f) return "facing=" .. NAMES[(FACINGS[f] + k) % 4] end))
end
-- set (and noise), for the quarter drawn north and its k-th turn
local function tnoise(k, x, y, z)
  local tx, tz = turn(x, z, k)
  return noise(tx, y, tz)
end
local function put(k, x, y, z, block)
  local tx, tz = turn(x, z, k)
  set(tx, y, tz, block and turnBlock(block, k))
end

-- what a column is: lining, court, wing or garden
local function inWing(x, z)
  local function north(px, pz) return math.abs(px - C) <= WING_HALF and pz >= 1 and pz < C - COURT end
  for k = 0, 3 do
    local dx, dz = x - C, z - C
    for _ = 1, k do dx, dz = dz, -dx end -- back to the north wing
    if north(C + dx, C + dz) then return true end
  end
  return false
end
local function zone(x, z)
  if x <= 0 or z <= 0 or x >= W - 1 or z >= L - 1 then return "lining" end
  if math.abs(x - C) <= COURT and math.abs(z - C) <= COURT then return "court" end
  if inWing(x, z) then return "wing" end
  return "garden"
end

---------------------------------------------------------------- lining

-- earth walls, mossier towards the top, as if dug into the hill
for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      if zone(x, z) == "lining" then
        local n = noise(x, y, z)
        set(x, y, z, n < 0.08 * y and "minecraft:moss_block" or n < 0.4 and "minecraft:coarse_dirt"
          or n < 0.55 and "minecraft:rooted_dirt" or n < 0.65 and "minecraft:cobblestone" or "minecraft:dirt")
      end
    end
  end
end

---------------------------------------------------------------- courtyard

for z = C - COURT, C + COURT do
  for x = C - COURT, C + COURT do
    local dx, dz = math.abs(x - C), math.abs(z - C)
    local edge = dx == COURT or dz == COURT
    for y = 0, COURT_TOP - 1 do
      set(x, y, z, edge and "minecraft:stone_bricks" or "minecraft:cobblestone")
    end
    local top, above
    if math.max(dx, dz) <= 3 then
      top = "minecraft:polished_andesite" -- the plaza
      if dx == 0 and dz == 0 then
        top, above = "minecraft:chiseled_stone_bricks", "minecraft:enchanting_table"
      end
    elseif dx <= 1 or dz <= 1 then
      top = noise(x, 2, z) < 0.3 and "minecraft:mossy_stone_bricks" or "minecraft:stone_bricks"
    elseif dz == 5 and dx >= 3 and dx <= 6 then
      top = "minecraft:water"
    else
      top = "minecraft:moss_block"
      if (dz == 4 or dz == 6) and dx >= 3 and dx <= 6 then
        above = "minecraft:sugar_cane"
      elseif not edge then
        local n = noise(x, 3, z)
        above = n < 0.2 and "minecraft:poppy" or n < 0.35 and "minecraft:cornflower"
          or n < 0.45 and "minecraft:oxeye_daisy" or n < 0.55 and "minecraft:fern" or nil
      end
    end
    set(x, COURT_TOP, z, top)
    if above then set(x, COURT_TOP + 1, z, above) end
    -- bookshelves round the table, open on the paths
    if math.max(dx, dz) == 2 and dx ~= 0 and dz ~= 0 then
      set(x, COURT_TOP + 1, z, "minecraft:bookshelf")
      set(x, COURT_TOP + 2, z, "minecraft:bookshelf")
      if dx == 2 and dz == 2 then set(x, COURT_TOP + 3, z, "minecraft:lantern") end
    end
  end
end

---------------------------------------------------------------- a wing and a garden, turned four ways

-- the north wing: walls on x = C - 5 and C + 5 and across z = 14, the
-- lining at its end; floor, ceiling and turf roof
local WX0, WX1 = C - WING_HALF, C + WING_HALF -- 17, 27
local WZ = C - COURT - 1 -- 14: its wall on the courtyard
local POSTS_Z = { 1, 5, 10, WZ }
local isPostZ = {}
for _, z in ipairs(POSTS_Z) do isPostZ[z] = true end
local STEP_X = { C - 1, C, C + 1 } -- the steps up to the courtyard

local function wingShell(k)
  for z = 1, WZ do
    for x = WX0, WX1 do
      local wall = x == WX0 or x == WX1 or z == WZ
      put(k, x, 0, z, wall and POST or FLOOR)
      put(k, x, WING_TOP, z, z % 4 == 3 and BEAM or PLANKS)
      put(k, x, WING_TOP + 1, z, "minecraft:moss_block")
      local n = tnoise(k, x, WING_TOP, z)
      if n < 0.15 then put(k, x, WING_TOP + 2, z, "minecraft:fern")
      elseif n < 0.2 then put(k, x, WING_TOP + 2, z, "minecraft:azalea") end
      if wall then
        local corner = (x == WX0 or x == WX1) and isPostZ[z] or (z == WZ and (x == WX0 + 4 or x == WX1 - 4))
        for y = 1, WING_TOP - 1 do
          local window = not corner and z ~= WZ and (y == 2 or y == 3) and (z == 3 or z == 7 or z == 8 or z == 12)
          put(k, x, y, z, corner and POST or window and "minecraft:glass_pane" or PLANKS)
        end
      end
    end
  end
  -- the steps: up out of the room, through a doorway in the wall
  for _, x in ipairs(STEP_X) do
    put(k, x, 1, WZ - 1, "minecraft:oak_stairs[facing=south]")
    put(k, x, 1, WZ, "minecraft:stone_bricks")
    put(k, x, 2, WZ, "minecraft:oak_stairs[facing=south]")
    put(k, x, 3, WZ, nil)
    put(k, x, 4, WZ, nil)
  end
  -- shroomlights in the ceiling, lanterns by the steps
  put(k, C, WING_TOP, 4, "minecraft:shroomlight")
  put(k, C, WING_TOP, 9, "minecraft:shroomlight")
  put(k, C - 2, 1, WZ - 1, "minecraft:lantern")
  put(k, C + 2, 1, WZ - 1, "minecraft:lantern")
end

-- the north-west garden: everything outside the court and wings in x, z 1-16
local function garden(k)
  for z = 1, C - WING_HALF - 1 do
    for x = 1, C - WING_HALF - 1 do
      local tx, tz = turn(x, z, k)
      if zone(tx, tz) == "garden" then
        local n = noise(tx, 0, tz)
        put(k, x, 0, z, n < 0.2 and "minecraft:rooted_dirt" or "minecraft:moss_block")
        local p = noise(tz, 1, tx)
        local plant = p < 0.1 and "minecraft:fern" or p < 0.16 and "minecraft:poppy"
          or p < 0.22 and "minecraft:cornflower" or p < 0.26 and "minecraft:azalea"
          or p < 0.3 and "minecraft:lily_of_the_valley" or nil
        if plant and n >= 0.2 then put(k, x, 1, z, plant) end
      end
    end
  end
  -- a pond, sugar cane along its north and south banks
  for z = 10, 12 do
    for x = 3, 6 do
      put(k, x, 0, z, "minecraft:water")
      put(k, x, 1, z, nil)
    end
  end
  for x = 3, 6 do
    put(k, x, 1, 9, "minecraft:sugar_cane")
    put(k, x, 1, 13, "minecraft:sugar_cane")
  end
  -- an azalea tree: an oak trunk under azalea leaves
  local TX, TZ = 11, 4
  for y = 1, 5 do put(k, TX, y, TZ, "minecraft:oak_log") end
  for y = 4, 7 do
    local r = y == 7 and 1 or y == 4 and 2 or 2.5
    for dz = -3, 3 do
      for dx = -3, 3 do
        local d = math.sqrt(dx * dx + dz * dz)
        local x, z = TX + dx, TZ + dz
        if d <= r and (dx ~= 0 or dz ~= 0 or y > 5) and x >= 1 and z >= 1
          and tnoise(k, x, y, z) + y * 0.01 < 0.9 then
          put(k, x, y, z, tnoise(k, z, y, x) < 0.3 and "minecraft:flowering_azalea_leaves" or "minecraft:azalea_leaves")
        end
      end
    end
  end
  -- an azalea bush by the wall and lantern posts by the steps
  put(k, 3, 1, 3, "minecraft:flowering_azalea")
  put(k, 4, 1, 3, "minecraft:azalea")
  for _, c in ipairs({ { 13, 13 }, { 9, 15 } }) do
    put(k, c[1], 1, c[2], "minecraft:oak_fence")
    put(k, c[1], 2, c[2], "minecraft:lantern")
  end
  -- steps up to the courtyard's corner
  put(k, C - COURT - 1, 1, C - COURT, "minecraft:stone_brick_stairs[facing=east]")
  put(k, C - COURT, COURT_TOP, C - COURT, "minecraft:stone_brick_stairs[facing=east]")
  put(k, C - COURT, COURT_TOP + 1, C - COURT, nil)
end

---------------------------------------------------------------- furniture

-- carpet pairs where the beds go, chests, barrels, a wall of books
local function bedroom(k)
  for _, z in ipairs({ 3, 7, 11 }) do
    for _, x in ipairs({ WX0 + 1, WX0 + 2, WX1 - 2, WX1 - 1 }) do put(k, x, 1, z, "minecraft:red_carpet") end
  end
  for _, z in ipairs({ 5, 9 }) do
    put(k, WX0 + 1, 1, z, "minecraft:chest[facing=east]")
    put(k, WX1 - 1, 1, z, "minecraft:chest[facing=west]")
    put(k, WX0 + 1, 1, z - 1, "minecraft:barrel")
    put(k, WX0 + 1, 2, z - 1, "minecraft:lantern")
    put(k, WX1 - 1, 1, z - 1, "minecraft:barrel")
    put(k, WX1 - 1, 2, z - 1, "minecraft:candle")
  end
  for x = WX0 + 1, WX1 - 1 do
    for y = 1, 3 do put(k, x, y, 1, "minecraft:bookshelf") end
  end
  for z = 3, 11 do put(k, C, 1, z, "minecraft:white_carpet") end
end

-- shelves down both walls, a lectern and map table
local function library(k)
  for z = 1, 11 do
    for _, x in ipairs({ WX0 + 1, WX1 - 1 }) do
      for y = 1, 3 do put(k, x, y, z, z == 6 and y == 1 and "minecraft:barrel" or "minecraft:bookshelf") end
    end
  end
  put(k, WX0 + 1, 4, 6, "minecraft:lantern")
  put(k, WX1 - 1, 4, 6, "minecraft:lantern")
  put(k, C, 1, 3, "minecraft:lectern[facing=south]")
  put(k, C - 2, 1, 7, "minecraft:cartography_table")
  put(k, C + 2, 1, 7, "minecraft:spruce_planks")
  put(k, C + 2, 2, 7, "minecraft:candle")
  for x = C - 1, C + 1 do
    for z = 5, 9 do put(k, x, 1, z, "minecraft:brown_carpet") end
  end
end

-- a cooking counter down one wall, storage down the other
local function kitchen(k)
  local COUNTER = { "minecraft:smoker[facing=west]", "minecraft:furnace[facing=west]",
    "minecraft:crafting_table", "minecraft:barrel", "minecraft:cauldron", "minecraft:barrel",
    "minecraft:blast_furnace[facing=west]", "minecraft:composter" }
  for i, block in ipairs(COUNTER) do put(k, WX1 - 1, 1, i + 1, block) end
  put(k, WX1 - 1, 2, 4, "minecraft:lantern")
  put(k, WX1 - 1, 2, 7, "minecraft:candle")
  for z = 1, 11 do
    put(k, WX0 + 1, 1, z, z % 3 == 0 and "minecraft:barrel" or "minecraft:chest[facing=east]")
    put(k, WX0 + 1, 2, z, "minecraft:barrel")
  end
  put(k, WX0 + 1, 3, 6, "minecraft:lantern")
  for x = WX0 + 2, WX1 - 2 do put(k, x, 1, 1, "minecraft:barrel") end
  -- a table with candles
  for z = 5, 7 do put(k, C, 1, z, "minecraft:stripped_oak_wood") end
  put(k, C, 2, 5, "minecraft:candle")
  put(k, C, 2, 7, "minecraft:candle")
end

-- smithing and brewing
local function workshop(k)
  local BENCH = { "minecraft:smithing_table", "minecraft:anvil[facing=east]", "minecraft:grindstone[facing=east]",
    "minecraft:stonecutter", "minecraft:loom[facing=east]", "minecraft:fletching_table" }
  for i, block in ipairs(BENCH) do put(k, WX0 + 1, 1, i + 1, block) end
  put(k, WX0 + 1, 1, 9, "minecraft:barrel")
  put(k, WX0 + 1, 2, 9, "minecraft:lantern")
  put(k, WX1 - 1, 1, 2, "minecraft:brewing_stand")
  put(k, WX1 - 1, 1, 3, "minecraft:cauldron")
  for z = 4, 8 do put(k, WX1 - 1, 1, z, "minecraft:barrel") end
  put(k, WX1 - 1, 2, 5, "minecraft:brewing_stand")
  put(k, WX1 - 1, 2, 7, "minecraft:candle")
  for x = WX0 + 1, WX1 - 1 do put(k, x, 1, 1, "minecraft:chest[facing=south]") end
  put(k, C, 2, 1, "minecraft:lantern")
end

local FURNISH = { [0] = bedroom, library, kitchen, workshop }
for k = 0, 3 do
  wingShell(k)
  FURNISH[k](k)
  garden(k)
end

---------------------------------------------------------------- courtyard edge and the daylight

-- a fence along the courtyard's edges above the gardens, lanterns at the corners
for z = C - COURT, C + COURT do
  for x = C - COURT, C + COURT do
    if math.abs(x - C) == COURT or math.abs(z - C) == COURT then
      local open = false
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if zone(x + d[1], z + d[2]) == "garden" then open = true end
      end
      local stairs = (get(x, COURT_TOP, z) or ""):find("stairs")
      if open and not stairs then
        local corner = math.abs(x - C) == COURT and math.abs(z - C) == COURT - 1
          or math.abs(z - C) == COURT and math.abs(x - C) == COURT - 1
        set(x, COURT_TOP + 1, z, "minecraft:oak_fence")
        if corner then set(x, COURT_TOP + 2, z, "minecraft:lantern") end
      end
    end
  end
end

-- froglights high over the courtyard and gardens
for z = 4, L - 5, 6 do
  for x = 4, W - 5, 6 do
    local zn = zone(x, z)
    if zn == "court" or zn == "garden" then set(x, TOP, z, LIGHT) end
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
      local block = grid[x .. "," .. y .. "," .. z]
      if block then crossroads.blocks[#crossroads.blocks + 1] = { x, y, z, block } end
    end
  end
end
return crossroads
