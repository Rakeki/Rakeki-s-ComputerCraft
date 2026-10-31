-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Great Hall: everything you need in one big timber hall, for the 39x33x14
-- hole 'excavate greathall' digs. Dark oak pillars stand in a ring four
-- blocks in from the walls and carry beams under a spruce ceiling set with
-- shroomlights. Between the pillars and the walls, twenty alcoves under a
-- roof with a railing and lanterns along it: a portal frame, an ender chest
-- corner, brewing, libraries, an enchanting table with its shelves, armour
-- stand spots, storage, a smithy, a kitchen and a planter. In the middle, a
-- pool sunk in the floor with a conduit at its heart, a rim of prismarine
-- and sea lanterns, benches facing it and lantern posts at its corners.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 39, 33, 14
local TOP = H - 2
local HOME = { x = 19, z = 26 }
local hall = { name = "Great Hall", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local CX, CZ = 19, 16 -- the middle
local RING = 4 -- the pillars stand this far in from the walls
local PILLARS_X = { 4, 9, 14, 19, 24, 29, 34 } -- along the north and south walls
local PILLARS_Z = { 4, 10, 16, 22, 28 } -- along the west and east walls
local ROOF = 6 -- the alcoves' roof; the railing stands on it
local BEAM = TOP - 1 -- beams between the pillars, under the ceiling

local PLANKS = "minecraft:spruce_planks"
local PILLAR = "minecraft:dark_oak_log"
local BEAM_BLOCK = "minecraft:stripped_dark_oak_wood"
local LIGHT = "minecraft:shroomlight"

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
local function get(x, y, z) return grid[x .. "," .. y .. "," .. z] end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end

---------------------------------------------------------------- shell, floor and ceiling

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local wall = x == 0 or z == 0 or x == W - 1 or z == L - 1
      if wall then
        local post = (z == 0 or z == L - 1) and (x - 4) % 5 == 0 or (x == 0 or x == W - 1) and (z - 4) % 6 == 0
        local n = noise(x, y, z)
        set(x, y, z, y <= 1 and (n < 0.2 and "minecraft:mossy_stone_bricks" or "minecraft:stone_bricks")
          or post and "minecraft:stripped_dark_oak_log" or PLANKS)
      elseif y == 0 then
        local border = x == RING or x == W - 1 - RING or z == RING or z == L - 1 - RING
        set(x, y, z, border and "minecraft:dark_oak_planks" or PLANKS)
      elseif y == TOP then
        local lit = (x == 7 or x == 12 or x == 17 or x == 21 or x == 26 or x == 31) and (z == 8 or z == 13 or z == 19 or z == 24)
        set(x, y, z, lit and LIGHT or PLANKS)
      end
    end
  end
end

---------------------------------------------------------------- pillars, beams and the alcove roof

local function pillar(x, z)
  for y = 1, TOP - 1 do set(x, y, z, PILLAR) end
end
for _, x in ipairs(PILLARS_X) do
  pillar(x, RING)
  pillar(x, L - 1 - RING)
  for z = RING + 1, L - 2 - RING do set(x, BEAM, z, BEAM_BLOCK) end
end
for _, z in ipairs(PILLARS_Z) do
  pillar(RING, z)
  pillar(W - 1 - RING, z)
  for x = RING + 1, W - 2 - RING do set(x, BEAM, z, BEAM_BLOCK) end
end

-- the roof over the alcoves, with a railing along its edge and lanterns mid-span
for z = 1, L - 2 do
  for x = 1, W - 2 do
    local inX, inZ = x <= RING or x >= W - 1 - RING, z <= RING or z >= L - 1 - RING
    if inX or inZ then
      set(x, ROOF, z, get(x, ROOF, z) or PLANKS)
      local edge = (x == RING or x == W - 1 - RING) and z >= RING and z <= L - 1 - RING
        or (z == RING or z == L - 1 - RING) and x >= RING and x <= W - 1 - RING
      if edge and get(x, ROOF + 1, z) == nil then
        set(x, ROOF + 1, z, "minecraft:dark_oak_fence")
        local mid = (z == RING or z == L - 1 - RING) and (x - 4) % 5 == 2 or (x == RING or x == W - 1 - RING) and (z - 4) % 6 == 3
        if mid then set(x, ROOF + 2, z, "minecraft:lantern") end
      end
    end
  end
end

---------------------------------------------------------------- the alcoves

-- An alcove is drawn in its own coordinates: u along the wall, v out from
-- it (1-3; the pillars are at v 4), y up from the floor. at() turns that
-- into the hole's x and z for each wall; IN is the facing towards the hall.
local WALLS = {
  north = { at = function(u, v) return u, v end, IN = "south", pillars = PILLARS_X },
  south = { at = function(u, v) return u, L - 1 - v end, IN = "north", pillars = PILLARS_X },
  west = { at = function(u, v) return v, u end, IN = "east", pillars = PILLARS_Z },
  east = { at = function(u, v) return W - 1 - v, u end, IN = "west", pillars = PILLARS_Z },
}
local OUT = { south = "north", north = "south", east = "west", west = "east" }
local SIDE = { south = "east", north = "west", east = "north", west = "south" } -- along the wall, u rising

local function portal(a)
  for u = 0, 3 do
    for y = 0, 4 do
      local frame = u == 0 or u == 3 or y == 0 or y == 4
      a.put(u, 1, y, frame and ((u == 0 or u == 3) and (y == 0 or y == 4) and "minecraft:crying_obsidian" or "minecraft:obsidian") or nil)
    end
  end
  a.put(0, 3, 1, "minecraft:soul_lantern")
  a.put(a.w - 1, 3, 1, "minecraft:soul_lantern")
end
local function ender(a)
  for u = 0, a.w - 1 do a.put(u, 1, 0, "minecraft:obsidian") end
  a.put(1, 1, 1, "minecraft:ender_chest[facing=" .. a.IN .. "]")
  a.put(2, 1, 1, "minecraft:ender_chest[facing=" .. a.IN .. "]")
  a.put(0, 1, 1, "minecraft:crying_obsidian")
  a.put(0, 1, 2, "minecraft:end_rod")
  a.put(a.w - 1, 1, 1, "minecraft:crying_obsidian")
  a.put(a.w - 1, 1, 2, "minecraft:end_rod")
  a.put(1, 2, 1, "minecraft:purple_carpet")
  a.put(2, 2, 1, "minecraft:purple_carpet")
end
local function brewing(a)
  a.put(0, 1, 1, "minecraft:barrel")
  a.put(1, 1, 1, "minecraft:brewing_stand")
  a.put(2, 1, 1, "minecraft:cauldron")
  a.put(a.w - 1, 1, 1, "minecraft:barrel")
  a.put(a.w - 1, 1, 2, "minecraft:brewing_stand")
  a.put(0, 1, 2, "minecraft:candle")
  for u = 0, a.w - 1 do a.put(u, 1, 3, "minecraft:spruce_planks") end
  a.put(1, 1, 4, "minecraft:lantern")
  a.put(a.w - 2, 1, 4, "minecraft:candle")
end
local function library(a)
  for u = 0, a.w - 1 do
    for y = 1, 3 do a.put(u, 1, y, "minecraft:bookshelf") end
  end
  for v = 2, 3 do
    for y = 1, 3 do
      a.put(0, v, y, "minecraft:bookshelf")
      a.put(a.w - 1, v, y, "minecraft:bookshelf")
    end
  end
  a.put(1, 3, 1, "minecraft:lectern[facing=" .. OUT[a.IN] .. "]")
  a.put(1, 1, 4, "minecraft:lantern")
end
local function enchanting(a)
  -- shelves two away from the table, with air between
  for u = 0, a.w - 1 do
    for y = 1, 2 do a.put(u, 1, y, "minecraft:bookshelf") end
  end
  a.put(0, 2, 1, "minecraft:bookshelf")
  a.put(a.w - 1, 2, 1, "minecraft:bookshelf")
  a.put(1, 3, 1, "minecraft:enchanting_table")
  a.put(0, 1, 3, "minecraft:candle")
  a.put(a.w - 1, 1, 3, "minecraft:candle")
  a.put(2, 2, 1, "minecraft:purple_carpet")
end
local function armour(a)
  -- slabs for armour stands, a lantern between
  a.put(0, 2, 1, "minecraft:smooth_stone_slab")
  a.put(a.w - 1, 2, 1, "minecraft:smooth_stone_slab")
  for u = 1, a.w - 2 do a.put(u, 1, 0, "minecraft:polished_andesite") end
  a.put(1, 1, 1, "minecraft:chest[facing=" .. a.IN .. "]")
  a.put(2, 1, 1, "minecraft:lantern")
  for u = 0, a.w - 1 do a.put(u, 1, 4, "minecraft:stripped_dark_oak_wood") end
end
local function storage(a)
  for u = 0, a.w - 1 do
    for y = 1, 3 do a.put(u, 1, y, "minecraft:barrel") end
  end
  for y = 1, 3 do
    a.put(0, 2, y, "minecraft:barrel")
    a.put(a.w - 1, 2, y, "minecraft:barrel")
  end
  a.put(1, 2, 1, "minecraft:chest[facing=" .. a.IN .. "]")
  a.put(2, 2, 1, "minecraft:chest[facing=" .. a.IN .. "]")
  a.put(1, 1, 4, "minecraft:lantern")
end
local function smithy(a)
  a.put(0, 1, 1, "minecraft:blast_furnace[facing=" .. a.IN .. "]")
  a.put(1, 1, 1, "minecraft:smithing_table")
  a.put(2, 1, 1, "minecraft:anvil[facing=" .. SIDE[a.IN] .. "]")
  a.put(a.w - 1, 1, 1, "minecraft:grindstone[facing=" .. a.IN .. "]")
  a.put(0, 2, 1, "minecraft:stonecutter")
  a.put(0, 1, 2, "minecraft:lantern")
end
local function kitchen(a)
  a.put(0, 1, 1, "minecraft:smoker[facing=" .. a.IN .. "]")
  a.put(1, 1, 1, "minecraft:furnace[facing=" .. a.IN .. "]")
  a.put(2, 1, 1, "minecraft:crafting_table")
  a.put(a.w - 1, 1, 1, "minecraft:barrel")
  a.put(a.w - 1, 2, 1, "minecraft:barrel")
  a.put(a.w - 1, 1, 2, "minecraft:lantern")
  a.put(0, 2, 1, "minecraft:composter")
end
local function planter(a)
  for u = 0, a.w - 1 do
    for v = 1, 2 do a.put(u, v, 0, "minecraft:moss_block") end
  end
  local mid = math.floor(a.w / 2)
  a.put(mid, 1, 0, "minecraft:water")
  for u = 0, a.w - 1 do
    if u ~= mid then a.put(u, 1, 1, "minecraft:sugar_cane") end
    a.put(u, 2, 1, u % 2 == 0 and "minecraft:flowering_azalea" or "minecraft:fern")
  end
  a.put(mid, 2, 1, "minecraft:sugar_cane")
  for y = 3, 5 do
    for u = 0, a.w - 1 do
      if noise(u, y, a.w) < (y - 2) * 0.3 then a.put(u, 1, y, "minecraft:azalea_leaves") end
    end
  end
end

local ALCOVES = {
  north = { portal, ender, brewing, library, enchanting, library },
  south = { storage, storage, armour, armour, smithy, kitchen },
  west = { storage, storage, armour, planter },
  east = { library, armour, storage, brewing },
}
for name, wall in pairs(WALLS) do
  local ps = wall.pillars
  for i = 1, #ps - 1 do
    local u0, w = ps[i] + 1, ps[i + 1] - ps[i] - 1
    local a = { w = w, IN = wall.IN }
    function a.put(u, v, y, block)
      local x, z = wall.at(u0 + u, v)
      set(x, y, z, block)
    end
    -- the partition up to the roof at the pillar on its far side
    if i < #ps - 1 then
      for v = 1, RING - 1 do
        for y = 1, ROOF - 1 do
          local x, z = wall.at(ps[i + 1], v)
          set(x, y, z, PLANKS)
        end
      end
    end
    ALCOVES[name][i](a)
  end
end
-- the corners: a lantern on a barrel
for _, c in ipairs({ { 2, 2 }, { W - 3, 2 }, { 2, L - 3 }, { W - 3, L - 3 } }) do
  set(c[1], 1, c[2], "minecraft:barrel")
  set(c[1], 2, c[2], "minecraft:lantern")
end

---------------------------------------------------------------- the pool

-- water sunk in the floor, a conduit in the middle, a prismarine rim with
-- sea lanterns at its corners
for z = CZ - 4, CZ + 4 do
  for x = CX - 4, CX + 4 do
    local d = math.max(math.abs(x - CX), math.abs(z - CZ))
    if d == 4 then
      set(x, 0, z, (math.abs(x - CX) == 4 and math.abs(z - CZ) == 4) and "minecraft:sea_lantern" or "minecraft:prismarine")
    elseif d == 0 then
      set(x, 0, z, "minecraft:conduit")
    else
      set(x, 0, z, "minecraft:water")
    end
  end
end
-- benches facing the pool, lantern posts at its corners
for i = -2, 2 do
  set(CX + i, 1, CZ - 6, "minecraft:spruce_stairs[facing=north]")
  set(CX + i, 1, CZ + 6, "minecraft:spruce_stairs[facing=south]")
  set(CX - 6, 1, CZ + i, "minecraft:spruce_stairs[facing=west]")
  set(CX + 6, 1, CZ + i, "minecraft:spruce_stairs[facing=east]")
end
for _, dx in ipairs({ -6, 6 }) do
  for _, dz in ipairs({ -6, 6 }) do
    set(CX + dx, 1, CZ + dz, "minecraft:dark_oak_fence")
    set(CX + dx, 2, CZ + dz, "minecraft:dark_oak_fence")
    set(CX + dx, 3, CZ + dz, "minecraft:lantern")
  end
end
-- a rug of dark planks round the pool
for z = CZ - 5, CZ + 5 do
  for x = CX - 5, CX + 5 do
    if math.max(math.abs(x - CX), math.abs(z - CZ)) == 5 then set(x, 0, z, "minecraft:stripped_spruce_wood") end
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
      if block then hall.blocks[#hall.blocks + 1] = { x, y, z, block } end
    end
  end
end
return hall
