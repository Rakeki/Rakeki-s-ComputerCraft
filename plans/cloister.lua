-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Cloister: a garden court ringed by rooms, for the 35x35x10 hole
-- 'excavate cloister' digs. In the middle, a garden under froglights: four
-- cherry trees, pink petals and flowers on moss, gravel paths, and a
-- fountain whose spout pours down a calcite pillar into its basin. Round it,
-- an arcade of mossy stone columns and arches under a dark oak roof with a
-- railing and lanterns on top. Behind the arcade, sixteen rooms behind
-- doorways: libraries, an enchanting room and a study on the north side,
-- brewing and storerooms on the east, a dormitory of bed spots (marked with
-- carpet) on the south, kitchens and storerooms on the west; planters fill
-- the corners, open to the rooms either side.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 35, 35, 10
local TOP = H - 2
local HOME = { x = 17, z = 13 }
local cloister = { name = "Cloister", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local C = 17 -- the middle (x and z)
local N = W - 1 -- the far side
local INNER = 6 -- the rooms' inner wall, this far out from the hole's wall
local ARCADE = 10 -- the columns stand on this line; the garden is inside it
local ROOF = 5 -- the roof over the rooms and the arcade
local COLUMNS = { 10, 13, 17, 21, 24 } -- along each side of the garden
local PARTITIONS = { 12, 17, 22 } -- walls between the rooms on each side
local DOORS = { 9, 14, 20, 25 } -- a doorway into each room
local LIGHT = "minecraft:ochre_froglight"

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
local function get(x, y, z) return grid[x .. "," .. y .. "," .. z] end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function stone(x, y, z)
  local n = noise(x, y, z)
  return n < 0.3 and "minecraft:mossy_stone_bricks" or n < 0.4 and "minecraft:cracked_stone_bricks" or "minecraft:stone_bricks"
end

-- Each side is drawn in its own coordinates: u along it (0-34), v out from
-- the hole's wall. at() turns them into x and z; IN faces the garden.
local SIDES = {
  north = { at = function(u, v) return u, v end, IN = "south" },
  south = { at = function(u, v) return u, N - v end, IN = "north" },
  west = { at = function(u, v) return v, u end, IN = "east" },
  east = { at = function(u, v) return N - v, u end, IN = "west" },
}
local function sideSet(side, u, v, y, block)
  local x, z = side.at(u, v)
  set(x, y, z, block)
end

---------------------------------------------------------------- shell, floor, roof

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local garden = math.abs(x - C) < C - ARCADE and math.abs(z - C) < C - ARCADE
      if x == 0 or z == 0 or x == N or z == N then
        set(x, y, z, stone(x, y, z))
      elseif y == 0 then
        local walk = not garden and math.max(math.abs(x - C), math.abs(z - C)) >= C - ARCADE and math.max(math.abs(x - C), math.abs(z - C)) <= C - INNER - 1
        set(x, y, z, garden and "minecraft:moss_block" or walk and ((x + z) % 2 == 0 and "minecraft:stone_bricks" or "minecraft:polished_andesite")
          or "minecraft:spruce_planks")
      elseif y == ROOF and not garden then
        set(x, y, z, "minecraft:dark_oak_planks")
      end
    end
  end
end

---------------------------------------------------------------- the four sides

local isColumn, isPartition, isDoor = {}, {}, {}
for _, u in ipairs(COLUMNS) do isColumn[u] = true end
for _, u in ipairs(PARTITIONS) do isPartition[u] = true end
for _, u in ipairs(DOORS) do isDoor[u] = true end

for _, side in pairs(SIDES) do
  for u = INNER, N - INNER do
    -- the rooms' inner wall, a doorway into each room
    for y = 1, ROOF - 1 do
      local open = isDoor[u] and y <= 2
      sideSet(side, u, INNER, y, not open and (y == 1 and "minecraft:stone_bricks" or "minecraft:stripped_spruce_wood") or nil)
    end
    if isDoor[u] then sideSet(side, u, INNER, 3, "minecraft:spruce_planks") end
    -- walls between the rooms; the end rooms open into the corners
    if isPartition[u] then
      for v = 1, INNER - 1 do
        for y = 1, ROOF - 1 do sideSet(side, u, v, y, "minecraft:spruce_planks") end
      end
    end
    -- the arcade: columns, a beam over them, corbels beside each column
    if u >= ARCADE and u <= N - ARCADE then
      if isColumn[u] then
        for y = 1, ROOF - 1 do sideSet(side, u, ARCADE, y, (y == ROOF - 1) and "minecraft:chiseled_stone_bricks" or stone(u, y, ARCADE)) end
      else
        sideSet(side, u, ARCADE, ROOF - 1, "minecraft:stone_bricks")
        if isColumn[u - 1] or isColumn[u + 1] then sideSet(side, u, ARCADE, ROOF - 2, "minecraft:stone_bricks") end
      end
      -- the railing on the roof's edge, lanterns over the columns
      sideSet(side, u, ARCADE, ROOF + 1, "minecraft:dark_oak_fence")
      if isColumn[u] then sideSet(side, u, ARCADE, ROOF + 2, "minecraft:lantern") end
    end
  end
  -- lights in the roof over the walk and the rooms
  for _, u in ipairs({ 9, 14, 20, 25 }) do
    sideSet(side, u, 8, ROOF, "minecraft:shroomlight")
    sideSet(side, u, 3, ROOF, "minecraft:shroomlight")
  end
end

---------------------------------------------------------------- the rooms

-- A room in its side's coordinates: u from its first column (0 to w - 1),
-- v from the hole's wall (1 to 5), y up from the floor.
local function library(r)
  for u = 0, r.w - 1 do for y = 1, 3 do r.put(u, 1, y, "minecraft:bookshelf") end end
  for v = 2, 4 do for y = 1, 3 do r.put(0, v, y, "minecraft:bookshelf") end end
  r.put(r.w - 1, 3, 1, "minecraft:lectern[facing=" .. r.IN .. "]")
  r.put(r.w - 1, 2, 1, "minecraft:lantern")
end
local function enchant(r)
  for u = 0, r.w - 1 do for y = 1, 2 do r.put(u, 1, y, "minecraft:bookshelf") end end
  for y = 1, 2 do r.put(0, 2, y, "minecraft:bookshelf"); r.put(r.w - 1, 2, y, "minecraft:bookshelf") end
  r.put(1, 3, 1, "minecraft:enchanting_table")
  r.put(r.w - 1, 4, 1, "minecraft:candle")
  r.put(0, 4, 1, "minecraft:candle")
end
local function study(r)
  r.put(0, 1, 1, "minecraft:cartography_table")
  r.put(1, 1, 1, "minecraft:lectern[facing=" .. r.IN .. "]")
  r.put(2, 1, 1, "minecraft:bookshelf")
  r.put(2, 1, 2, "minecraft:lantern")
  r.put(r.w - 1, 1, 1, "minecraft:barrel")
  for u = 0, r.w - 1 do r.put(u, 3, 1, "minecraft:brown_carpet") end
end
local function brewing(r)
  r.put(0, 1, 1, "minecraft:barrel")
  r.put(1, 1, 1, "minecraft:brewing_stand")
  r.put(2, 1, 1, "minecraft:cauldron")
  r.put(r.w - 1, 1, 1, "minecraft:brewing_stand")
  r.put(0, 1, 2, "minecraft:lantern")
  for v = 2, 4 do r.put(r.w - 1, v, 1, "minecraft:barrel") end
  r.put(r.w - 1, 3, 2, "minecraft:candle")
end
local function storage(r)
  for u = 0, r.w - 1 do
    r.put(u, 1, 1, "minecraft:chest[facing=" .. r.IN .. "]")
    r.put(u, 1, 2, "minecraft:barrel")
  end
  for v = 2, 4 do
    for y = 1, 2 do r.put(0, v, y, "minecraft:barrel"); r.put(r.w - 1, v, y, "minecraft:barrel") end
  end
  r.put(1, 1, 3, "minecraft:lantern")
end
local function dorm(r)
  for _, u in ipairs({ 0, r.w - 1 }) do
    r.put(u, 1, 1, "minecraft:red_carpet")
    r.put(u, 2, 1, "minecraft:red_carpet")
    r.put(u, 3, 1, "minecraft:chest[facing=" .. r.IN .. "]")
  end
  r.put(1, 1, 1, "minecraft:barrel")
  r.put(1, 1, 2, "minecraft:candle")
  if r.w > 4 then
    r.put(2, 1, 1, "minecraft:red_carpet")
    r.put(2, 2, 1, "minecraft:red_carpet")
  end
end
local function kitchen(r)
  r.put(0, 1, 1, "minecraft:smoker[facing=" .. r.IN .. "]")
  r.put(1, 1, 1, "minecraft:furnace[facing=" .. r.IN .. "]")
  r.put(2, 1, 1, "minecraft:crafting_table")
  r.put(r.w - 1, 1, 1, "minecraft:barrel")
  r.put(r.w - 1, 1, 2, "minecraft:lantern")
  -- a long table with benches
  for u = 0, r.w - 2 do
    r.put(u, 3, 1, "minecraft:stripped_spruce_wood")
    r.put(u, 4, 1, "minecraft:spruce_stairs[facing=" .. r.IN .. "]")
  end
  r.put(0, 3, 2, "minecraft:candle")
end

local ROOMS = {
  north = { library, enchant, study, library },
  east = { brewing, storage, storage, brewing },
  south = { dorm, dorm, dorm, dorm },
  west = { kitchen, storage, storage, kitchen },
}
local ROOM_U = { { 7, 5 }, { 13, 4 }, { 18, 4 }, { 23, 5 } } -- first u and width
for name, side in pairs(SIDES) do
  for i, ru in ipairs(ROOM_U) do
    local r = { w = ru[2], IN = side.IN }
    function r.put(u, v, y, block) sideSet(side, ru[1] + u, v, y, block) end
    ROOMS[name][i](r)
  end
end

-- the corners: a moss planter with azaleas and a lantern, between the end rooms
for _, cx in ipairs({ 1, N - 5 }) do
  for _, cz in ipairs({ 1, N - 5 }) do
    for z = cz, cz + 4 do
      for x = cx, cx + 4 do
        local back = (cx == 1 and x <= cx + 1 or cx > 1 and x >= cx + 3) and (cz == 1 and z <= cz + 1 or cz > 1 and z >= cz + 3)
        if back then
          set(x, 0, z, "minecraft:moss_block")
          set(x, 1, z, noise(x, 1, z) < 0.5 and "minecraft:flowering_azalea" or "minecraft:azalea")
        end
      end
    end
    local lx, lz = cx == 1 and cx + 3 or cx + 1, cz == 1 and cz + 3 or cz + 1
    set(lx, 1, lz, "minecraft:dark_oak_fence")
    set(lx, 2, lz, "minecraft:lantern")
  end
end

---------------------------------------------------------------- the garden

local G0, G1 = ARCADE + 1, N - ARCADE - 1 -- 11 .. 23
for z = G0, G1 do
  for x = G0, G1 do
    local dx, dz = math.abs(x - C), math.abs(z - C)
    if dx <= 0 or dz <= 0 then
      set(x, 0, z, "minecraft:gravel") -- paths in a cross
    elseif dx <= 3 and dz <= 3 then
      -- the fountain's rim and basin, below
    else
      local n = noise(x, 1, z)
      local plant = n < 0.25 and "minecraft:pink_petals" or n < 0.32 and "minecraft:lily_of_the_valley"
        or n < 0.38 and "minecraft:allium" or n < 0.44 and "minecraft:fern" or nil
      set(x, 1, z, plant)
    end
  end
end
-- the fountain: a basin, a rim round it, a calcite pillar with a spout on
-- top; the water falls down its sides onto the basin and stays inside the rim
for z = C - 3, C + 3 do
  for x = C - 3, C + 3 do
    local d = math.max(math.abs(x - C), math.abs(z - C))
    if d == 3 then
      set(x, 0, z, "minecraft:calcite")
      set(x, 1, z, "minecraft:polished_andesite")
    elseif d == 0 then
      for y = 0, 3 do set(x, y, z, "minecraft:calcite") end
      set(x, 4, z, "minecraft:water")
    else
      set(x, 0, z, "minecraft:water")
    end
  end
end
-- a cherry tree in each quarter
for _, tx in ipairs({ C - 5, C + 5 }) do
  for _, tz in ipairs({ C - 5, C + 5 }) do
    for y = 1, 4 do set(tx, y, tz, "minecraft:cherry_log") end
    for y = 3, 6 do
      local r = (y == 3 or y == 6) and 1.5 or 2.5
      for dz = -3, 3 do
        for dx = -3, 3 do
          local x, z = tx + dx, tz + dz
          if math.sqrt(dx * dx + dz * dz) <= r and (dx ~= 0 or dz ~= 0 or y > 4) and noise(x, y, z) < 0.85
            and x >= G0 and x <= G1 and z >= G0 and z <= G1 then
            set(x, y, z, "minecraft:cherry_leaves")
          end
        end
      end
    end
  end
end
-- froglights high over the garden
for _, x in ipairs({ 12, 17, 22 }) do
  for _, z in ipairs({ 12, 17, 22 }) do set(x, TOP, z, LIGHT) end
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
      if block then cloister.blocks[#cloister.blocks + 1] = { x, y, z, block } end
    end
  end
end
return cloister
