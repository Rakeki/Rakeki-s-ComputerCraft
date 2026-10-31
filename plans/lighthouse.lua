-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Lighthouse: a round tower in red and white bands on a rocky outcrop,
-- narrowing as it rises. A spiral stair winds round a stone core inside up
-- to the lamp room: a glass lantern round a glowstone light, with a walkway
-- and iron railing outside it and a red cap. A keeper's cottage leans on
-- the rock at the foot. y 0 is the ground; x and z are from the tower's
-- middle.
local TOWER = 24 -- the tower's top floor
local BAND = 4 -- height of each red or white band

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
local function dist(x, z) return math.sqrt(x * x + z * z) end

---------------------------------------------------------------- the rock

-- a lumpy mound, highest by the tower
for z = -10, 10 do
  for x = -10, 10 do
    local d = dist(x, z) + noise(x, 0, z) * 1.6
    local top = d < 6 and 3 or d < 8 and 2 or d < 9.5 and 1 or d < 10.5 and 0 or -1
    for y = 0, top do
      local n = noise(x, y, z)
      set(x, y, z, n < 0.2 and "andesite" or n < 0.35 and "cobblestone" or n < 0.45 and "mossy_cobblestone" or "stone")
    end
  end
end

---------------------------------------------------------------- the tower

-- radius at each height: 4.5 at the bottom, 3.5 at the top
local function radius(y) return 4.5 - (y - 4) / (TOWER - 4) end
for y = 4, TOWER do
  local r = radius(y)
  local band = math.floor((y - 4) / BAND) % 2 == 0 and "white_concrete" or "red_concrete"
  for z = -5, 5 do
    for x = -5, 5 do
      local d = dist(x, z)
      if d <= r and d > r - 1.2 then set(x, y, z, band)
      elseif d <= r - 1.2 then set(x, y, z, nil) end
    end
  end
end
-- floor inside, on the rock
for z = -3, 3 do for x = -3, 3 do if dist(x, z) <= 3.3 then set(x, 3, z, "smooth_stone") end end end

-- the spiral stair round a stone core: a step a block higher each cell, round and round
local RING = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
local GOING = { "east", "east", "south", "south", "west", "west", "north", "north" }
for y = 4, TOWER do set(0, y, 0, "stone_bricks") end
for i = 0, TOWER - 3 do
  local c = RING[i % 8 + 1]
  set(c[1], 4 + i, c[2], "stone_brick_stairs[facing=" .. GOING[i % 8 + 1] .. "]")
end

-- door at the front and small windows on the way up, in the white bands
set(0, 4, -4, "spruce_door[facing=north]"); set(0, 5, -4, nil)
for y = 4, TOWER - 2 do
  if math.floor((y - 4) / BAND) % 2 == 0 and (y - 4) % BAND == 2 then
    local r = math.floor(radius(y) + 0.5)
    local side = math.floor((y - 4) / (2 * BAND)) % 4
    local dx, dz = ({ 1, 0, -1, 0 })[side + 1], ({ 0, 1, 0, -1 })[side + 1]
    if not (side == 3 and y < 8) then set(dx * r, y, dz * r, "glass_pane") end
  end
end

---------------------------------------------------------------- the lamp room

local G = TOWER + 1 -- its floor
for z = -5, 5 do
  for x = -5, 5 do
    local d = dist(x, z)
    if d <= 5.2 then set(x, G, z, "smooth_stone_slab") end
    if d <= 5.2 and d > 4.3 then set(x, G + 1, z, "iron_bars") end
    if d <= 3.3 then set(x, G, z, "polished_andesite") end
  end
end
-- the stair comes up through here: headroom over its last steps
set(1, G, 0, nil); set(1, G, 1, nil); set(0, G, 1, "stone_brick_stairs[facing=west]")
for y = G + 1, G + 4 do
  for z = -3, 3 do
    for x = -3, 3 do
      local d = dist(x, z)
      if d <= 3.3 and d > 2.2 then
        set(x, y, z, (math.abs(x) == math.abs(z) and math.abs(x) == 2) and "red_concrete" or "glass")
      end
    end
  end
end
set(0, G + 1, -3, nil); set(0, G + 2, -3, nil) -- the way out onto the walkway
set(0, G + 1, 0, "polished_andesite"); set(0, G + 2, 0, "glowstone"); set(0, G + 3, 0, "glowstone")
set(0, G, 0, "stone_bricks")

-- red cap
for i = 0, 3 do
  local r = 3.6 - i
  for z = -4, 4 do for x = -4, 4 do if dist(x, z) <= r then set(x, G + 5 + i, z, "red_concrete") end end end
end
set(0, G + 9, 0, "iron_bars"); set(0, G + 10, 0, "end_rod")

---------------------------------------------------------------- the keeper's cottage

-- leaning on the rock to the east: stone walls, spruce roof running east-west
local CX0, CX1, CZ0, CZ1 = 5, 11, -3, 3
for y = 1, 3 do
  for z = CZ0, CZ1 do
    for x = CX0, CX1 do
      local wall = x == CX0 or x == CX1 or z == CZ0 or z == CZ1
      set(x, y, z, wall and ((x == CX0 or x == CX1) and (z == CZ0 or z == CZ1) and "stripped_spruce_log" or "cobblestone") or nil)
    end
  end
end
fill(CX0, 0, CZ0, CX1, 0, CZ1, "spruce_planks")
set(CX1, 2, 0, "glass_pane"); set(8, 2, CZ1, "glass_pane"); set(8, 2, CZ0, "glass_pane")
set(9, 1, CZ0, "spruce_door[facing=north]"); set(9, 2, CZ0, nil)
set(9, 1, CZ0 - 1, nil); set(9, 2, CZ0 - 1, nil) -- room in front of the door
for i = 0, 3 do
  for x = CX0, CX1 + 1 do
    set(x, 4 + i, CZ0 - 1 + i, "spruce_stairs[facing=south]")
    set(x, 4 + i, CZ1 + 1 - i, "spruce_stairs[facing=north]")
  end
  for z = CZ0 + i, CZ1 - i do
    if i < 3 then set(CX0, 4 + i, z, "spruce_planks"); set(CX1, 4 + i, z, "spruce_planks") end
  end
end
for x = CX0, CX1 + 1 do set(x, 7, 0, "spruce_slab") end
set(10, 1, 2, "furnace"); set(10, 1, 1, "barrel"); set(6, 1, 2, "crafting_table"); set(6, 1, 1, "chest")
set(10, 1, -2, "lantern")
-- brick chimney on the east wall
for y = 1, 8 do set(CX1 + 1, y, 2, "bricks") end
set(CX1 + 1, 9, 2, "campfire")

local lighthouse = { name = "Lighthouse", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  lighthouse.blocks[#lighthouse.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return lighthouse
