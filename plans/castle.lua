-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Castle: a square curtain wall of weathered stone with a wall walk and
-- battlements, a round tower with a blue cone roof on each corner (a
-- spiral stair inside each up to the walk), and a gatehouse on the north
-- side with a raised portcullis and red banners. In the courtyard: a
-- three-storey keep with a corner turret, a throne room on its ground
-- floor and stairs up to a walkable roof, stables against the east wall,
-- a garden and archery targets on the west side. y 0 is the ground; x
-- and z are from the middle of the courtyard.
local R = 17 -- the curtain wall's outer face; it is two blocks thick
local WALL = 8 -- the wall walk's level
local TOWER = 13 -- the corner towers' last stone layer
local ROOF = "blue_terracotta"

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
  return n < 0.1 and "cracked_stone_bricks" or n < 0.22 and "mossy_stone_bricks" or n < 0.28 and "andesite" or "stone_bricks"
end
local function dist(x, z) return math.sqrt(x * x + z * z) end
-- a cone roof: shrinking rings of shingles
local function cone(cx, y0, cz, r0)
  local k = 0
  while true do
    local r = r0 - 0.7 * k
    if r < 0.5 then set(cx, y0 + k, cz, ROOF); set(cx, y0 + k + 1, cz, "lightning_rod") break end
    for z = cz - 6, cz + 6 do
      for x = cx - 6, cx + 6 do
        local d = dist(x - cx, z - cz)
        if d <= r and d > r - 1.3 then set(x, y0 + k, z, ROOF) end
      end
    end
    k = k + 1
  end
end
-- a spiral stair round a stone post: a step a block higher each cell
local RING = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
local GOING = { "east", "east", "south", "south", "west", "west", "north", "north" }

---------------------------------------------------------------- courtyard and curtain wall

for z = -R + 2, R - 2 do
  for x = -R + 2, R - 2 do
    local n = noise(x, 0, z)
    set(x, 0, z, n < 0.3 and "cobblestone" or n < 0.45 and "andesite" or "stone_bricks")
  end
end
for z = -R + 2, 0 do for x = -1, 1 do set(x, 0, z, "gravel") end end

for y = 0, WALL do
  for z = -R, R do
    for x = -R, R do
      if math.abs(x) >= R - 1 or math.abs(z) >= R - 1 then set(x, y, z, stone(x, y, z)) end
    end
  end
end
-- battlements on the outer edge of the walk
for z = -R, R do
  for x = -R, R do
    if (math.abs(x) == R or math.abs(z) == R) and (x + z) % 2 == 0 then set(x, WALL + 1, z, stone(x, WALL + 1, z)) end
  end
end
-- a solid stair up to the walk against the inside of the west wall
for i = 0, WALL - 1 do
  local z = -6 + i
  for y = 1, i do set(-R + 2, y, z, "stone_bricks") end
  set(-R + 2, 1 + i, z, "stone_brick_stairs[facing=south]")
end

---------------------------------------------------------------- corner towers

for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
  local cx, cz = s[1] * R, s[2] * R
  for y = 0, TOWER do
    for z = cz - 5, cz + 5 do
      for x = cx - 5, cx + 5 do
        local d = dist(x - cx, z - cz)
        if d <= 4.5 and d > 3.3 then set(x, y, z, stone(x, y, z))
        elseif d <= 3.3 then set(x, y, z, (y == 0 or y == WALL) and "spruce_planks" or nil) end
      end
    end
  end
  -- out onto the wall walk both ways, and a door from the courtyard
  for y = WALL + 1, WALL + 2 do
    set(cx - s[1] * 4, y, cz, nil); set(cx - s[1] * 4, y, cz - s[2], nil)
    set(cx, y, cz - s[2] * 4, nil); set(cx - s[1], y, cz - s[2] * 4, nil)
  end
  set(cx - s[1] * 3, 1, cz - s[2] * 3, "spruce_door[facing=" .. (s[2] < 0 and "south" or "north") .. "]")
  set(cx - s[1] * 3, 2, cz - s[2] * 3, nil)
  -- arrow slits
  for _, y in ipairs({ 4, 10 }) do set(cx + s[1] * 4, y, cz, "iron_bars"); set(cx, y, cz + s[2] * 4, "iron_bars") end
  -- the stair inside, up to the floor at the walk's level
  for y = 1, WALL do set(cx, y, cz, "stone_bricks") end
  for i = 0, WALL - 1 do
    local c = RING[i % 8 + 1]
    set(cx + c[1], 1 + i, cz + c[2], "stone_brick_stairs[facing=" .. GOING[i % 8 + 1] .. "]")
  end
  for k = WALL - 3, WALL - 2 do local c = RING[k % 8 + 1]; set(cx + c[1], WALL, cz + c[2], nil) end
  set(cx, WALL + 1, cz, "lantern")
  cone(cx, TOWER + 1, cz, 5.4)
end

---------------------------------------------------------------- gatehouse

local GX, GZ0, GZ1, GTOP = 6, -R - 3, -R + 3, 12
for y = 0, GTOP do
  for z = GZ0, GZ1 do
    for x = -GX, GX do
      local shell = math.abs(x) == GX or z == GZ0 or z == GZ1
      if shell then set(x, y, z, stone(x, y, z))
      elseif y == 0 or y == WALL or y == GTOP then set(x, y, z, y == WALL and "spruce_planks" or "stone_bricks")
      else set(x, y, z, nil) end
    end
  end
end
-- battlements round its roof
for z = GZ0, GZ1 do
  for x = -GX, GX do
    if (math.abs(x) == GX or z == GZ0 or z == GZ1) and (x + z) % 2 == 0 then set(x, GTOP + 1, z, stone(x, GTOP + 1, z)) end
  end
end
-- the passage through it, walled and roofed, with the portcullis raised at the front
for z = GZ0, GZ1 do
  for y = 1, 5 do
    set(-2, y, z, stone(-2, y, z)); set(2, y, z, stone(2, y, z))
    for x = -1, 1 do set(x, y, z, y == 5 and "stone_bricks" or nil) end
  end
  for x = -1, 1 do set(x, 0, z, "gravel") end
end
for x = -1, 1 do set(x, 4, GZ0, "iron_bars") end
set(-1, 4, GZ1, "stone_bricks"); set(1, 4, GZ1, "stone_bricks")
-- out onto the walk from its upper room, slits and banners on the front
for y = WALL + 1, WALL + 2 do
  for _, z in ipairs({ -R, -R + 1 }) do set(-GX, y, z, nil); set(GX, y, z, nil) end
end
for _, x in ipairs({ -4, 4 }) do
  set(x, 10, GZ0, "iron_bars"); set(x, 11, GZ0, "iron_bars")
  for y = 5, 9 do set(x, y, GZ0 - 1, "red_wool") end
end
set(-3, 1, GZ0 - 2, "dark_oak_fence"); set(-3, 2, GZ0 - 2, "lantern")
set(3, 1, GZ0 - 2, "dark_oak_fence"); set(3, 2, GZ0 - 2, "lantern")

---------------------------------------------------------------- the keep

local KX, KZ0, KZ1, KTOP = 8, 1, 13, 18
for y = 0, KTOP do
  for z = KZ0, KZ1 do
    for x = -KX, KX do
      local shell = math.abs(x) == KX or z == KZ0 or z == KZ1
      if shell then set(x, y, z, stone(x, y, z))
      elseif y % 6 == 0 then set(x, y, z, y == 0 and "polished_andesite" or y == KTOP and "stone_bricks" or "spruce_planks")
      else set(x, y, z, nil) end
    end
  end
end
for z = KZ0, KZ1 do
  for x = -KX, KX do
    if (math.abs(x) == KX or z == KZ0 or z == KZ1) and (x + z) % 2 == 0 then set(x, KTOP + 1, z, stone(x, KTOP + 1, z)) end
  end
end
-- windows: tall ones on the ground floor, single panes above
for _, y in ipairs({ 3, 4, 9, 15 }) do
  for _, x in ipairs({ -5, -2, 2, 5 }) do set(x, y, KZ1, "glass_pane"); if x ~= -2 and x ~= 2 or y > 4 then set(x, y, KZ0, "glass_pane") end end
  for _, z in ipairs({ 4, 7, 10 }) do set(-KX, y, z, "glass_pane"); set(KX, y, z, "glass_pane") end
end
set(0, 1, KZ0, "spruce_door[facing=north]"); set(0, 2, KZ0, nil); set(0, 3, KZ0, "chiseled_stone_bricks")
set(-1, 1, KZ0 - 1, "dark_oak_fence"); set(-1, 2, KZ0 - 1, "lantern"); set(1, 1, KZ0 - 1, "dark_oak_fence"); set(1, 2, KZ0 - 1, "lantern")
-- the throne room
for z = KZ0 + 1, KZ1 - 3 do set(0, 1, z, "red_carpet") end
set(0, 1, KZ1 - 2, "quartz_stairs[facing=south]"); set(-1, 1, KZ1 - 2, "gold_block"); set(1, 1, KZ1 - 2, "gold_block")
for _, x in ipairs({ -3, 3 }) do for y = 2, 5 do set(x, y, KZ1 - 1, "red_wool") end end
for _, c in ipairs({ { -7, 2 }, { -7, 12 }, { 7, 12 } }) do set(c[1], 1, c[2], "dark_oak_fence"); set(c[1], 2, c[2], "lantern") end
-- stairs up, east then west then east, through gaps in the floors
local FLIGHTS = { { x = 7, y = 1, z = 4, dz = 1 }, { x = -7, y = 7, z = 9, dz = -1 }, { x = 7, y = 13, z = 4, dz = 1 } }
for _, f in ipairs(FLIGHTS) do
  for i = 0, 5 do set(f.x, f.y + i, f.z + f.dz * i, "spruce_stairs[facing=" .. (f.dz > 0 and "south" or "north") .. "]") end
  set(f.x, f.y + 5, f.z + f.dz * 3, nil); set(f.x, f.y + 5, f.z + f.dz * 4, nil)
end
-- the corner turret, round, solid and tall, standing out from the keep's north-east corner
local TX, TZ = KX + 1, KZ0 - 1
for y = 0, KTOP + 5 do
  for z = TZ - 3, TZ + 3 do
    for x = TX - 3, TX + 3 do
      if dist(x - TX, z - TZ) <= 2.6 then set(x, y, z, stone(x, y, z)) end
    end
  end
end
set(TX + 2, KTOP + 3, TZ, "iron_bars"); set(TX, KTOP + 3, TZ - 2, "iron_bars")
cone(TX, KTOP + 6, TZ, 3.6)

---------------------------------------------------------------- stables, garden, targets

-- a lean-to against the east wall, its roof climbing to the walk
for _, z in ipairs({ -12, -7, -2 }) do for y = 1, 3 do set(11, y, z, "spruce_log") end end
for k = 0, 4 do
  for z = -13, -1 do set(11 + k, 4 + k, z, "spruce_stairs[facing=east]") end
end
for x = 12, 15 do set(x, 1, -7, "spruce_fence") end
set(15, 1, -11, "hay_block"); set(15, 2, -11, "hay_block"); set(15, 1, -10, "hay_block")
set(15, 1, -4, "hay_block"); set(15, 1, -3, "cauldron"); set(14, 1, -9, "cauldron")

-- planters with azaleas along the path, targets on hay against the west wall
for _, z in ipairs({ -12, -8, -4 }) do
  for _, x in ipairs({ -3, 3 }) do
    set(x, 0, z, "moss_block"); set(x, 1, z, noise(x, 1, z) < 0.5 and "flowering_azalea" or "azalea")
  end
end
for _, z in ipairs({ 6, 9, 12 }) do set(-R + 2, 1, z, "hay_block"); set(-R + 2, 2, z, "target") end
for z = -2, 2 do set(-10, 1, z, "spruce_fence") end
set(-10, 2, -2, "lantern"); set(-10, 2, 2, "lantern")

local castle = { name = "Castle", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  castle.blocks[#castle.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return castle
