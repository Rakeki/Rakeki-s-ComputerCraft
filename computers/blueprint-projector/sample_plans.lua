-- Built-in plans for the blueprint projector, and examples of the plan format.
-- Your own plans go in /plans/<name>.lua and look just like one of these:
--
--   return {
--     name = "My house",                       -- shown on the monitor
--     legend = {                               -- one character per block
--       C = "minecraft:cobblestone",
--       G = { "minecraft:glass", 0x99ddff },   -- block + projection colour
--     },
--     layers = {                               -- bottom layer first
--       { "CCC",                               -- first row: the front (north
--         "CGC",                               -- at turn 0), across = east
--         "CCC" },
--       ...
--     },
--   }
--
-- "." and " " are air. Instead of layers, a plan can list its blocks:
-- blocks = { { x, y, z, "minecraft:stone" }, ... }, which is handy when a
-- loop makes the plan (see the watchtower).
local plans = {}

---------------------------------------------------------------- cottage

plans[#plans + 1] = {
  id = "cottage",
  name = "Cottage",
  legend = {
    C = "minecraft:cobblestone",
    P = "minecraft:oak_planks",
    L = "minecraft:oak_log",
    G = "minecraft:glass_pane",
    D = "minecraft:oak_door",
    S = "minecraft:spruce_planks",
  },
  layers = {
    { "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC",
      "CCCCCCC" },
    { "LPPDPPL",
      "P.....P",
      "P.....P",
      "P.....P",
      "P.....P",
      "P.....P",
      "LPPPPPL" },
    { "LPGDGPL",
      "P.....P",
      "G.....G",
      "P.....P",
      "G.....G",
      "P.....P",
      "LPPGPPL" },
    { "LPPPPPL",
      "P.....P",
      "P.....P",
      "P.....P",
      "P.....P",
      "P.....P",
      "LPPPPPL" },
    { "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS",
      "SSSSSSS" },
    { ".......",
      ".SSSSS.",
      ".SSSSS.",
      ".SSSSS.",
      ".SSSSS.",
      ".SSSSS.",
      "......." },
    { ".......",
      ".......",
      "..SSS..",
      "..SSS..",
      "..SSS..",
      ".......",
      "......." },
    { ".......",
      ".......",
      ".......",
      "...S...",
      ".......",
      ".......",
      "......." },
  },
}

---------------------------------------------------------------- watchtower

-- 5x5 stone tower with a door, windows, and a wider lookout on top.
local tower = { id = "watchtower", name = "Watchtower", blocks = {} }
local function add(x, y, z, block) tower.blocks[#tower.blocks + 1] = { x, y, z, block } end

for y = 0, 7 do
  for z = 0, 4 do
    for x = 0, 4 do
      local edge = x == 0 or x == 4 or z == 0 or z == 4
      local middle = x == 2 or z == 2
      if y == 0 then
        add(x, y, z, "minecraft:stone_bricks")
      elseif edge then
        if z == 0 and x == 2 and y <= 2 then
          add(x, y, z, "minecraft:spruce_door")
        elseif middle and (y == 4 or y == 5) then
          add(x, y, z, "minecraft:glass_pane")
        else
          add(x, y, z, "minecraft:stone_bricks")
        end
      end
    end
  end
end
-- lookout floor hangs one block out on every side, with gaps in the parapet
for z = -1, 5 do
  for x = -1, 5 do
    local edge = x == -1 or x == 5 or z == -1 or z == 5
    add(x, 8, z, edge and "minecraft:stone_bricks" or "minecraft:spruce_planks")
    if edge then
      add(x, 9, z, "minecraft:stone_brick_wall")
      if (x + z) % 2 == 0 then add(x, 10, z, "minecraft:stone_brick_wall") end
    end
  end
end
plans[#plans + 1] = tower

---------------------------------------------------------------- pagoda

-- Five-storey pagoda on a stepped stone plinth, 31x31 and 59 high. Each
-- storey is narrower than the one below, with a balcony and railing on the
-- roof below it, deep eaves that turn up at the corners, lanterns under the
-- corners, and a gold spire on top. Coordinates are from the centre.
local pagoda = { id = "pagoda", name = "Pagoda", blocks = {} }
local function put(x, y, z, block) pagoda.blocks[#pagoda.blocks + 1] = { x, y, z, block } end

-- the outline of a square of this radius, or all of it
local function ring(radius, y, block)
  for i = -radius, radius do
    put(i, y, -radius, block)
    put(i, y, radius, block)
    if i > -radius and i < radius then
      put(-radius, y, i, block)
      put(radius, y, i, block)
    end
  end
  if radius == 0 then put(0, y, 0, block) end
end
local function square(radius, y, block)
  for z = -radius, radius do
    for x = -radius, radius do put(x, y, z, block) end
  end
end

-- plinth, with steps up the front (north)
for y = 0, 2 do
  square(15 - y, y, "minecraft:stone_bricks")
  for x = -2, 2 do put(x, y, -16 + y, "minecraft:stone_brick_stairs") end
end

local STOREYS = {
  { radius = 12, height = 6 },
  { radius = 10, height = 5 },
  { radius = 8, height = 5 },
  { radius = 6, height = 4 },
  { radius = 4, height = 4 },
}
local EAVES = 3 -- how far each roof reaches past its walls

local y = 3
for level, storey in ipairs(STOREYS) do
  local r, h = storey.radius, storey.height
  local below = STOREYS[level - 1]

  -- floor: on the plinth, or the full width of the storey below so its
  -- edge makes a balcony with a railing
  local floor = below and below.radius or r
  square(floor, y, "minecraft:spruce_planks")
  if below then ring(floor, y + 1, "minecraft:dark_oak_fence") end

  -- walls: posts at the corners and every 4 blocks, windows between them,
  -- a dark beam along the top, and a doorway at the front
  for dy = 1, h do
    for i = -r, r do
      for _, side in ipairs({ { i, -r }, { i, r }, { -r, i }, { r, i } }) do
        local x, z = side[1], side[2]
        local along = (z == -r or z == r) and x or z
        local corner = (x == -r or x == r) and (z == -r or z == r)
        local door = z == -r and math.abs(x) <= (level == 1 and 1 or 0) and dy <= (level == 1 and 3 or 2)
        local block
        if door then
          block = nil
        elseif corner or along % 4 == 0 then
          block = "minecraft:mangrove_log"
        elseif dy == h then
          block = "minecraft:dark_oak_planks"
        elseif along % 4 == 2 and dy >= 2 and dy <= h - 2 then
          block = "minecraft:glass_pane"
        else
          block = "minecraft:birch_planks"
        end
        if block then put(x, y + dy, z, block) end
      end
    end
  end
  -- a ceiling closes the storey under its roof
  square(r - 1, y + h, "minecraft:dark_oak_planks")

  -- roof: rings stepping in from the eaves, corners turned up, lanterns
  -- hanging under the corners
  local top = y + h + 1
  local eave = r + EAVES
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    put(c[1] * eave, top + 1, c[2] * eave, "minecraft:deepslate_tile_slab")
    put(c[1] * eave, top - 1, c[2] * eave, "minecraft:lantern")
  end
  if level < #STOREYS then
    for j = 0, EAVES - 1 do
      ring(eave - j, top + j, j == 0 and "minecraft:deepslate_tile_stairs" or "minecraft:deepslate_tiles")
    end
    y = top + EAVES
  else
    -- the top roof closes to a point, with a spire on it
    for j = 0, eave do
      ring(eave - j, top + j, j == 0 and "minecraft:deepslate_tile_stairs" or "minecraft:deepslate_tiles")
    end
    local tip = top + eave
    for k = 1, 7 do
      put(0, tip + k, 0, k % 2 == 1 and "minecraft:gold_block" or "minecraft:iron_bars")
    end
    for _, c in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      put(c[1], tip + 3, c[2], "minecraft:gold_block")
    end
  end
end
plans[#plans + 1] = pagoda

---------------------------------------------------------------- sky station

-- A space station to hang high in the sky, 63 wide and 77 high: a hollow
-- core with a glass dome and a spire on top and a spike below, and four
-- hollow rings round it, the upper three joined to the core by hollow
-- spokes. Each ring has a floor to walk round on, with a deck across the
-- core at the same height. It's built in the air, so builders don't clear
-- its box first (clear = false): raise it on the projector before Build.
local station = { id = "skystation", name = "Sky Station", clear = false, blocks = {} }

local TAU = 2 * math.pi
local atan2 = math.atan2 or math.atan

-- bottom to top: wall, the grooves between its panels, and either a red
-- stripe round the outside or a band of windows
local RINGS = {
  { y = 17, R = 14, r = 4.5, wall = "minecraft:white_concrete", rib = "minecraft:light_gray_concrete", stripe = "minecraft:red_concrete" },
  { y = 30, R = 24, r = 4.5, wall = "minecraft:gray_concrete", rib = "minecraft:black_concrete", window = "minecraft:light_blue_stained_glass", spokes = 0 },
  { y = 43, R = 27, r = 4.5, wall = "minecraft:white_concrete", rib = "minecraft:light_gray_concrete", stripe = "minecraft:red_concrete", spokes = 45 },
  { y = 55, R = 21, r = 4, wall = "minecraft:gray_concrete", rib = "minecraft:black_concrete", window = "minecraft:light_blue_stained_glass", spokes = 0 },
}
local SPOKE = 3 -- spokes are 7 blocks square (5 inside)

-- Every cell inside the station, and which part it belongs to. Only the
-- outside layer of it gets built (plus the floors), so the whole thing is
-- one hollow space you can walk through.
local inside = {}
local function cell(x, y, z) return ((x + 64) * 256 + y) * 128 + (z + 64) end
local function fill(reach, y0, y1, part, test)
  for y = y0, y1 do
    for z = -reach, reach do
      for x = -reach, reach do
        local k = cell(x, y, z)
        if not inside[k] and test(x, y, z) then inside[k] = part end
      end
    end
  end
end

local function inRing(ring, x, y, z)
  local d = math.sqrt(x * x + z * z) - ring.R
  return d * d + (y - ring.y) ^ 2 <= ring.r * ring.r
end

-- spike below, core, the hubs round the core's ends, the dome
fill(3, 0, 9, "spike", function(x, y, z) return x * x + z * z <= (y * 0.28) ^ 2 end)
fill(7, 10, 62, "core", function(x, y, z) return x * x + z * z <= 6.5 * 6.5 end)
fill(11, 12, 22, "hub", function(x, y, z) return (x * x + z * z) / 121 + (y - 17) ^ 2 / 25 <= 1 end)
fill(10, 54, 62, "hub", function(x, y, z) return (x * x + z * z) / 100 + (y - 58) ^ 2 / 16 <= 1 end)
fill(8, 62, 70, "dome", function(x, y, z) return x * x + z * z + (y - 62) ^ 2 <= 7.5 * 7.5 end)
for _, ring in ipairs(RINGS) do
  local r = math.ceil(ring.r)
  fill(math.ceil(ring.R + ring.r), ring.y - r, ring.y + r, ring, function(x, y, z) return inRing(ring, x, y, z) end)
  if ring.spokes then
    local axes = {}
    for k = 0, 3 do
      local a = math.rad(ring.spokes + 90 * k)
      axes[#axes + 1] = { math.cos(a), math.sin(a) }
    end
    fill(ring.R, ring.y - SPOKE, ring.y + SPOKE, ring, function(x, y, z)
      for _, c in ipairs(axes) do
        local along, across = x * c[1] + z * c[2], z * c[1] - x * c[2]
        if along >= 0 and along <= ring.R and math.abs(across) <= SPOKE then return true end
      end
      return false
    end)
  end
end

-- A block one wide every so far round a circle: the grooves between panels,
-- the dome's ribs, the core's windows.
local function onRib(x, z, count)
  local a = atan2(z, x) % TAU
  return (a % (TAU / count)) * math.sqrt(x * x + z * z) < 1
end

local floorAt = {}
for _, ring in ipairs(RINGS) do floorAt[ring.y - 2] = true end

local function blockFor(part, x, y, z)
  if part == "spike" then return "minecraft:iron_block" end
  if part == "core" then return onRib(x, z, 8) and "minecraft:glass" or "minecraft:light_gray_concrete" end
  if part == "hub" then return onRib(x, z, 16) and "minecraft:light_gray_concrete" or "minecraft:white_concrete" end
  if part == "dome" then return onRib(x, z, 8) and "minecraft:white_concrete" or "minecraft:glass" end
  if not inRing(part, x, y, z) then return part.wall end -- a spoke
  local out, dy = math.sqrt(x * x + z * z) > part.R, y - part.y
  if part.stripe and out and dy == 0 then return part.stripe end
  if onRib(x, z, 32) then return part.rib end
  if part.window and out and math.abs(dy) <= 1 then return part.window end
  return part.wall
end

local function put(x, y, z, block) station.blocks[#station.blocks + 1] = { x, y, z, block } end
local NEXT = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
for k, part in pairs(inside) do
  local z = k % 128 - 64
  local y = math.floor(k / 128) % 256
  local x = math.floor(k / (128 * 256)) - 64
  local edge = false
  for _, d in ipairs(NEXT) do
    if not inside[cell(x + d[1], y + d[2], z + d[3])] then edge = true break end
  end
  if edge then
    put(x, y, z, blockFor(part, x, y, z))
  elseif floorAt[y] then
    put(x, y, z, (x % 6 == 0 and z % 6 == 0) and "minecraft:sea_lantern" or "minecraft:smooth_stone")
  end
end
inside = nil

-- the spire on the dome
for y = 70, 76 do put(0, y, 0, y % 2 == 0 and "minecraft:iron_block" or "minecraft:iron_bars") end
put(0, 77, 0, "minecraft:end_rod")
plans[#plans + 1] = station

return plans
