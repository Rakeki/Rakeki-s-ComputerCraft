-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Workshop: a timber-framed hall for the 33x25x15 hole 'excavate workshop'
-- digs. An L-shaped spruce mezzanine runs along the north and east walls on
-- dark oak pillars that go up to ceiling trusses, with corbel arches, a
-- fence railing with lanterns, and a stair up the west wall. Under the
-- north side, four alcoves: storage, a library with an enchanting table, a
-- smithy counter and a brewing corner; under the east side, a long wall of
-- barrels. Upstairs, bookshelves, barrels and planters. On the floor, a
-- raised garden bed with a water channel, sugar cane and flowers, lantern
-- posts, and leaves climbing the open walls.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 33, 25, 15
local TOP = H - 2
local HOME = { x = 17, z = 12 }
local workshop = { name = "Workshop", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local MEZZ = 7 -- the mezzanine floor's layer (you stand on it at 8)
local EDGE_Z = 7 -- the north side's front edge
local EDGE_X = 24 -- the east side's front edge
local PILLARS_X = { 6, 12, 18, 24 } -- on the north edge (24 is the corner)
local PILLARS_Z = { 13, 18, 23 } -- on the east edge
local STAIR_X = { 1, 2 } -- the stair up the west wall, rising north

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function leaves(x, y, z)
  set(x, y, z, noise(z, y, x) < 0.3 and "minecraft:flowering_azalea_leaves" or "minecraft:azalea_leaves")
end

local pillar = {}
for _, x in ipairs(PILLARS_X) do pillar[x .. "," .. EDGE_Z] = true end
for _, z in ipairs(PILLARS_Z) do pillar[EDGE_X .. "," .. z] = true end
local function isPillar(x, z) return pillar[x .. "," .. z] == true end
local function onEdge(x, z) return (z == EDGE_Z and x <= EDGE_X) or (x == EDGE_X and z >= EDGE_Z) end
local function underMezz(x, z) return z < EDGE_Z or x > EDGE_X end

---------------------------------------------------------------- shell

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local n = noise(x, y, z)
      if x == 0 or z == 0 or x == W - 1 or z == L - 1 then
        set(x, y, z, n < 0.1 and "minecraft:cracked_stone_bricks" or n < 0.2 and "minecraft:mossy_stone_bricks"
          or "minecraft:stone_bricks")
      elseif y == 0 then
        set(x, y, z, n < 0.3 and "minecraft:cobblestone" or n < 0.6 and "minecraft:polished_andesite"
          or n < 0.8 and "minecraft:stone" or "minecraft:andesite")
      end
    end
  end
end

---------------------------------------------------------------- mezzanine and frame

for z = 1, L - 2 do
  for x = 1, W - 2 do
    if isPillar(x, z) then
      for y = 1, TOP do set(x, y, z, "minecraft:dark_oak_log") end
    elseif onEdge(x, z) then
      -- a two-deep fascia, a beam under the trusses, corbels beside pillars
      set(x, MEZZ, z, "minecraft:stripped_spruce_wood")
      set(x, MEZZ - 1, z, "minecraft:stripped_spruce_wood")
      set(x, TOP, z, "minecraft:stripped_dark_oak_wood")
      local byPillar = isPillar(x - 1, z) or isPillar(x + 1, z) or isPillar(x, z - 1) or isPillar(x, z + 1)
      if byPillar then
        set(x, MEZZ - 2, z, "minecraft:spruce_planks")
        set(x, TOP - 1, z, "minecraft:spruce_planks")
      end
      -- railing, open where the stair arrives; lanterns mid-span
      local stairTop = z == EDGE_Z and x <= STAIR_X[2]
      if not stairTop then
        set(x, MEZZ + 1, z, "minecraft:spruce_fence")
        if (z == EDGE_Z and (x == 3 or x == 9 or x == 15 or x == 21)) or (x == EDGE_X and (z == 10 or z == 15 or z == 20)) then
          set(x, MEZZ + 2, z, "minecraft:lantern")
        end
      end
    elseif underMezz(x, z) then
      set(x, MEZZ, z, "minecraft:spruce_planks")
    end
  end
end

-- trusses: posts up the back walls above the mezzanine, beams along the
-- back walls and across to each pillar
for _, x in ipairs(PILLARS_X) do
  for y = MEZZ + 1, TOP do set(x, y, 1, "minecraft:dark_oak_log") end
  for z = 2, EDGE_Z - 1 do set(x, TOP, z, "minecraft:stripped_dark_oak_wood") end
end
for _, z in ipairs(PILLARS_Z) do
  for y = MEZZ + 1, TOP do set(W - 2, y, z, "minecraft:dark_oak_log") end
  for x = EDGE_X + 1, W - 3 do set(x, TOP, z, "minecraft:stripped_dark_oak_wood") end
end
for x = 1, W - 2 do
  if grid[x .. "," .. TOP .. ",1"] == nil then set(x, TOP, 1, "minecraft:stripped_dark_oak_wood") end
end
for z = 2, L - 2 do
  if grid[(W - 2) .. "," .. TOP .. "," .. z] == nil then set(W - 2, TOP, z, "minecraft:stripped_dark_oak_wood") end
end

-- stair up the west wall: step k's block at layer k, the top one a landing
-- next to the mezzanine; solid stone under the steps, a fence on the open side
for k = 1, MEZZ do
  local z = EDGE_Z + 1 + MEZZ - k
  for _, x in ipairs(STAIR_X) do
    set(x, k, z, k == MEZZ and "minecraft:spruce_planks" or "minecraft:spruce_stairs[facing=north]")
    for y = 1, k - 1 do set(x, y, z, "minecraft:stone_bricks") end
  end
  if k < MEZZ then set(STAIR_X[2] + 1, k + 1, z, "minecraft:spruce_fence") end
end

---------------------------------------------------------------- under the north side

-- storage (x 1-5)
for x = 1, 5 do
  for y = 1, 4 do set(x, y, 1, "minecraft:barrel") end
end
set(3, 1, 4, "minecraft:lantern")

-- library (x 7-11), the enchanting table in front
for x = 7, 11 do
  for y = 1, 4 do set(x, y, 1, "minecraft:bookshelf") end
end
set(9, 1, 3, "minecraft:enchanting_table")
set(8, 5, 1, "minecraft:candle")
set(10, 5, 1, "minecraft:candle")

-- smithy (x 13-17): a counter, a shelf above it with a lantern
local SMITHY = { "minecraft:crafting_table", "minecraft:smithing_table", "minecraft:barrel",
  "minecraft:fletching_table", "minecraft:cartography_table" }
for i, block in ipairs(SMITHY) do
  set(12 + i, 1, 1, block)
  set(12 + i, 4, 1, "minecraft:spruce_planks")
end
set(13, 2, 1, "minecraft:lantern")
set(15, 5, 1, "minecraft:lantern")

-- brewing corner (x 19-23): barrels, the stand, a cauldron, a campfire
for x = 19, 23 do set(x, 1, 1, "minecraft:barrel") end
set(20, 2, 1, "minecraft:brewing_stand")
set(22, 2, 1, "minecraft:cauldron")
set(23, 2, 1, "minecraft:lantern")
set(21, 1, 3, "minecraft:campfire")

---------------------------------------------------------------- under the east side

for z = EDGE_Z + 2, L - 3 do
  for y = 1, 3 do set(W - 2, y, z, "minecraft:barrel") end
end
for _, z in ipairs({ 11, 16, 21 }) do set(W - 2, 4, z, "minecraft:lantern") end

---------------------------------------------------------------- upstairs

local U = MEZZ + 1
for x = 2, 10 do
  if not pillar[x .. "," .. EDGE_Z] then
    set(x, U, 1, "minecraft:bookshelf")
    set(x, U + 1, 1, "minecraft:bookshelf")
  end
end
set(6, U, 4, "minecraft:lantern")
for x = 13, 17 do set(x, U, 1, "minecraft:barrel") end
set(14, U + 1, 1, "minecraft:lantern")
set(16, U + 1, 1, "minecraft:candle")
for x = 19, 23 do
  set(x, U, 1, "minecraft:moss_block")
  set(x, U + 1, 1, ({ "minecraft:azalea", "minecraft:fern", "minecraft:flowering_azalea", "minecraft:fern",
    "minecraft:azalea" })[x - 18])
end
for x = 25, W - 3 do
  for y = U + 2, TOP - 1 do
    if noise(x, y, 1) < (y - U - 1) * 0.15 then leaves(x, y, 1) end
  end
end
-- along the east wall: bookshelves, barrels, planters
for z = 9, 22 do
  if not pillar[EDGE_X .. "," .. z] and grid[(W - 2) .. "," .. U .. "," .. z] == nil then
    if z <= 12 then
      set(W - 2, U, z, "minecraft:bookshelf")
      set(W - 2, U + 1, z, "minecraft:bookshelf")
    elseif z <= 17 then
      set(W - 2, U, z, "minecraft:barrel")
    else
      set(W - 2, U, z, "minecraft:moss_block")
      set(W - 2, U + 1, z, z % 2 == 0 and "minecraft:flowering_azalea" or "minecraft:fern")
    end
  end
end
set(W - 2, U + 1, 15, "minecraft:lantern")
set(28, U, 15, "minecraft:lantern")

---------------------------------------------------------------- garden bed

-- a raised bed of stripped spruce, moss inside, a water channel down the
-- middle with sugar cane beside it, flowers between, lanterns on the corners
local B = { x0 = 4, x1 = 14, z0 = 16, z1 = 20 }
local MID = 18
for z = B.z0, B.z1 do
  for x = B.x0, B.x1 do
    if x == B.x0 or x == B.x1 or z == B.z0 or z == B.z1 then
      set(x, 1, z, "minecraft:stripped_spruce_wood")
    elseif z == MID and x > B.x0 + 1 and x < B.x1 - 1 then
      set(x, 1, z, "minecraft:water")
    else
      set(x, 1, z, "minecraft:moss_block")
      if x > B.x0 + 1 and x < B.x1 - 1 then
        set(x, 2, z, x % 2 == 0 and "minecraft:sugar_cane" or (z < MID and "minecraft:poppy" or "minecraft:cornflower"))
      else
        set(x, 2, z, "minecraft:fern")
      end
    end
  end
end
for _, x in ipairs({ B.x0, B.x1 }) do
  for _, z in ipairs({ B.z0, B.z1 }) do set(x, 2, z, "minecraft:lantern") end
end

---------------------------------------------------------------- the open floor

-- lantern posts
for _, p in ipairs({ { 12, 11 }, { 20, 11 }, { 20, 19 } }) do
  set(p[1], 1, p[2], "minecraft:dark_oak_fence")
  set(p[1], 2, p[2], "minecraft:dark_oak_fence")
  set(p[1], 3, p[2], "minecraft:lantern")
end

-- leaves climbing the west wall past the garden and the south wall
for z = 16, L - 2 do
  for y = 2, TOP - 1 do
    if noise(1, y, z) < 0.35 - y * 0.02 and noise(z, y, 1) < 0.6 then leaves(1, y, z) end
  end
end
for x = 2, EDGE_X - 1 do
  for y = 2, TOP - 1 do
    local patch = (x >= 4 and x <= 9) or (x >= 15 and x <= 19)
    if patch and noise(x, y, L - 2) < 0.5 - math.abs(y - 7) * 0.06 then leaves(x, y, L - 2) end
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
      if block then workshop.blocks[#workshop.blocks + 1] = { x, y, z, block } end
    end
  end
end
return workshop
