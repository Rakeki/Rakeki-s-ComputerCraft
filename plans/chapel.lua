-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Chapel: a stone village church. A long nave with buttresses and tall
-- stained-glass windows in turn of blue, yellow, red and purple, under a
-- steep slate roof; a square bell tower at the front with a bell in its
-- open belfry and a slate spire with a gold top. Inside, pews either side
-- of a red carpet up to a raised altar with candles, a lectern, and a
-- round window in the end wall. y 0 is the ground; x runs east, z south,
-- the door faces north.
local W, L = 10, 22 -- the nave's walls on x 0..W, z 0..L
local EAVES = 8 -- the roof's lowest course
local GLASS = { "light_blue", "yellow", "red", "purple" }

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
local function fill(x0, y0, z0, x1, y1, z1, block)
  for y = y0, y1 do for z = z0, z1 do for x = x0, x1 do set(x, y, z, block) end end end
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function stone(x, y, z)
  local n = noise(x, y, z)
  return n < 0.12 and "cracked_stone_bricks" or n < 0.24 and "mossy_stone_bricks" or "stone_bricks"
end
local MID = math.floor(W / 2)

---------------------------------------------------------------- the nave

fill(0, 0, 0, W, 0, L, "stone_bricks")
fill(1, 0, 1, W - 1, 0, L - 1, "polished_andesite")
for y = 1, EAVES - 1 do
  for z = 0, L do
    for x = 0, W do
      if x == 0 or x == W or z == 0 or z == L then set(x, y, z, stone(x, y, z)) end
    end
  end
end
-- buttresses along both sides, tall windows between them
for z = 2, L - 2, 4 do
  for _, x in ipairs({ -1, W + 1 }) do
    for y = 0, 5 do set(x, y, z, stone(x, y, z)) end
    set(x, 6, z, "stone_brick_stairs[facing=" .. (x < 0 and "east" or "west") .. "]")
  end
end
for k, z in ipairs({ 4, 8, 12, 16, 20 }) do
  local glass = GLASS[(k - 1) % #GLASS + 1] .. "_stained_glass_pane"
  for y = 2, 5 do set(0, y, z, glass); set(W, y, z, glass) end
  set(0, 6, z, "chiseled_stone_bricks"); set(W, 6, z, "chiseled_stone_bricks")
end
-- a round window high in the end wall behind the altar (south)
for y = 2, 7 do
  for x = 1, W - 1 do
    local d = math.sqrt((x - MID) ^ 2 + (y - 5) ^ 2)
    if d <= 2.6 then set(x, y, L, d <= 0.8 and "yellow_stained_glass_pane" or d <= 1.8 and "red_stained_glass_pane" or "light_blue_stained_glass_pane") end
  end
end

-- pews either side of the carpet, the altar on a step at the south end
for z = 3, 15, 2 do
  for x = 1, 3 do set(x, 1, z, "spruce_stairs[facing=north]") end
  for x = W - 3, W - 1 do set(x, 1, z, "spruce_stairs[facing=north]") end
end
for z = 1, 17 do set(MID, 1, z, "red_carpet") end
for x = 1, W - 1 do set(x, 1, 18, "stone_brick_stairs[facing=south]") end
fill(1, 1, 19, W - 1, 1, L - 1, "polished_andesite")
set(MID - 1, 2, 20, "quartz_block"); set(MID, 2, 20, "quartz_block"); set(MID + 1, 2, 20, "quartz_block")
set(MID - 1, 3, 20, "candle"); set(MID + 1, 3, 20, "candle")
set(MID, 3, 20, "gold_block")
set(W - 2, 2, 19, "lectern")
for _, x in ipairs({ 1, W - 1 }) do
  set(x, 2, 19, "dark_oak_fence"); set(x, 3, 19, "lantern")
  set(x, 1, 2, "dark_oak_fence"); set(x, 2, 2, "lantern")
end

---------------------------------------------------------------- roof

local i = 0
while -1 + i < W + 1 - i do
  for z = -1, L + 1 do
    set(-1 + i, EAVES + i, z, "deepslate_tile_stairs[facing=east]")
    set(W + 1 - i, EAVES + i, z, "deepslate_tile_stairs[facing=west]")
  end
  for x = i, W - i do set(x, EAVES + i, 0, stone(x, EAVES + i, 0)); set(x, EAVES + i, L, stone(x, EAVES + i, L)) end
  i = i + 1
end
for z = -1, L + 1 do set(MID, EAVES + i, z, "deepslate_tile_slab") end

---------------------------------------------------------------- the bell tower

local T0, T1, TZ0, TZ1 = MID - 2, MID + 2, -4, 0 -- shares the nave's front wall
local TOP = 17
for y = 0, TOP do
  for z = TZ0, TZ1 do
    for x = T0, T1 do
      if x == T0 or x == T1 or z == TZ0 or z == TZ1 then set(x, y, z, stone(x, y, z))
      elseif y == 0 or y == 12 then set(x, y, z, "spruce_planks")
      else set(x, y, z, nil) end
    end
  end
end
-- the door, through into the nave, windows on the way up
set(MID, 1, TZ0, "spruce_door[facing=north]"); set(MID, 2, TZ0, nil); set(MID, 3, TZ0, "chiseled_stone_bricks")
set(MID, 1, TZ1, nil); set(MID, 2, TZ1, nil); set(MID, 3, TZ1, nil)
for _, y in ipairs({ 6, 9 }) do set(MID, y, TZ0, "glass_pane"); set(T0, y, -2, "glass_pane"); set(T1, y, -2, "glass_pane") end
-- the belfry: open on every side, the bell hanging in the middle
for y = 13, 15 do
  set(MID, y, TZ0, nil); set(T0, y, -2, nil); set(T1, y, -2, nil)
  if y < 15 then set(MID - 1, y, TZ0, nil); set(MID + 1, y, TZ0, nil); set(T0, y, -3, nil); set(T0, y, -1, nil); set(T1, y, -3, nil); set(T1, y, -1, nil) end
end
set(MID, 13, -2, "bell")
-- a parapet, then the spire
for z = TZ0 - 1, TZ1 + 1 do
  for x = T0 - 1, T1 + 1 do
    if x == T0 - 1 or x == T1 + 1 or z == TZ0 - 1 or z == TZ1 + 1 then
      set(x, TOP, z, "stone_bricks")
      if (x + z) % 2 == 0 then set(x, TOP + 1, z, "stone_brick_wall") end
    end
  end
end
for k, r in ipairs({ 2, 2, 1, 1, 1, 0, 0, 0, 0 }) do
  local y = TOP + k
  for z = -2 - r, -2 + r do for x = MID - r, MID + r do
    if math.abs(x - MID) == r or math.abs(z + 2) == r then set(x, y, z, "deepslate_tiles") end
  end end
end
set(MID, TOP + 10, -2, "gold_block"); set(MID, TOP + 11, -2, "lightning_rod")

-- the path up to the door
for z = -8, TZ0 - 1 do set(MID, 0, z, "gravel"); set(MID - 1, 0, z, "gravel"); set(MID + 1, 0, z, "gravel") end
for _, x in ipairs({ MID - 2, MID + 2 }) do set(x, 1, -7, "stone_brick_wall"); set(x, 2, -7, "lantern") end

local chapel = { name = "Chapel", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  chapel.blocks[#chapel.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return chapel
