-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Smithy: a village blacksmith under one long spruce roof. The west end is
-- a closed shop of stone and timber with a door at the front; the east end
-- is an open workshop on posts round a brick forge with a pool of lava in
-- it and a chimney through the roof (the forge's bricks keep the lava's
-- heat off the wood). Anvil, smithing table, grindstone, blast furnace, a
-- water trough, coal and a woodpile. One lava bucket. y 0 is the ground;
-- x runs east, z south, the front faces north.
local W, L = 14, 10 -- the walls' east and south lines; the roof reaches a block past them
local EAVES = 5 -- the roof's lowest course

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
local function cobble(x, y, z) return noise(x, y, z) < 0.3 and "mossy_cobblestone" or "cobblestone" end

---------------------------------------------------------------- floor, shop and workshop

for z = 0, L do for x = 0, W do set(x, 0, z, cobble(x, 0, z)) end end
fill(1, 0, 1, 5, 0, L - 1, "spruce_planks")

-- the shop: stone to waist height, timber above, logs at the corners and every few blocks
for y = 1, EAVES - 1 do
  for z = 0, L do
    for x = 0, 6 do
      if x == 0 or x == 6 or z == 0 or z == L then
        local post = (x == 0 or x == 6) and z % 5 == 0 or (z == 0 or z == L) and (x == 0 or x == 3 or x == 6)
        set(x, y, z, post and "stripped_spruce_log" or y <= 2 and cobble(x, y, z) or "spruce_planks")
      end
    end
  end
end
set(3, 1, 0, nil); set(3, 2, 0, nil); set(2, 1, 0, "spruce_door[facing=north]"); set(2, 2, 0, nil)
set(3, 1, 0, "stripped_spruce_log"); set(3, 2, 0, "stripped_spruce_log")
for _, z in ipairs({ 2, 3, 7, 8 }) do set(0, 3, z, "glass_pane") end
set(4, 3, 0, "glass_pane"); set(5, 3, 0, "glass_pane"); set(2, 3, L, "glass_pane"); set(4, 3, L, "glass_pane")
set(6, 1, 5, "spruce_door[facing=east]"); set(6, 2, 5, nil) -- through to the workshop
-- inside the shop: a counter, chests and barrels
for z = 2, 6 do set(4, 1, z, "spruce_slab") end
set(4, 1, 2, "barrel"); set(4, 2, 2, "lantern")
set(1, 1, 1, "chest"); set(1, 1, 2, "chest"); set(1, 1, 9, "barrel"); set(2, 1, 9, "barrel"); set(1, 2, 9, "barrel")
set(5, 1, 9, "crafting_table"); set(1, 1, 5, "red_carpet"); set(1, 1, 6, "red_carpet")

-- the workshop: posts holding the roof, a low wall along the back
for _, p in ipairs({ { W, 0 }, { 10, 0 }, { W, 5 }, { W, L } }) do fill(p[1], 1, p[2], p[1], EAVES - 1, p[2], "stripped_spruce_log") end
for x = 7, W - 1 do set(x, 1, L, cobble(x, 1, L)) end
set(8, 2, L, "lantern")

---------------------------------------------------------------- the forge

-- 3x3 of bricks, lava in the middle, open at the front; the hood and
-- chimney above are brick all the way through the roof
local FX, FZ = 12, 8
for y = 1, 12 do
  for z = FZ - 1, FZ + 1 do
    for x = FX - 1, FX + 1 do
      local mid = x == FX and z == FZ
      if y == 1 then set(x, y, z, mid and "lava" or "bricks")
      elseif y == 2 and x == FX and z == FZ - 1 then set(x, y, z, nil)
      else set(x, y, z, mid and nil or "bricks") end
    end
  end
end
set(10, 1, 9, "blast_furnace"); set(10, 1, 8, "furnace")
set(9, 1, 6, "anvil"); set(8, 1, 8, "smithing_table"); set(8, 1, 4, "grindstone")
set(13, 1, 4, "cauldron"); set(13, 1, 3, "barrel")
set(11, 1, 2, "coal_block"); set(12, 1, 2, "coal_block"); set(11, 2, 2, "coal_block")

---------------------------------------------------------------- the roof

-- one ridge running east-west over both halves
local i = 0
while -1 + i < L + 1 - i do
  for x = -1, W + 1 do
    set(x, EAVES + i, -1 + i, "spruce_stairs[facing=south]")
    set(x, EAVES + i, L + 1 - i, "spruce_stairs[facing=north]")
  end
  -- gable ends under each course
  for z = i, L - i do
    for _, x in ipairs({ 0, 6, W }) do set(x, EAVES + i, z, "spruce_planks") end
  end
  i = i + 1
end
for x = -1, W + 1 do set(x, EAVES + i, -1 + i, "spruce_slab") end
-- the chimney keeps its flue through the roof
for y = EAVES, 12 do
  for z = FZ - 1, FZ + 1 do
    for x = FX - 1, FX + 1 do set(x, y, z, (x == FX and z == FZ) and nil or "bricks") end
  end
end

---------------------------------------------------------------- outside

-- a woodpile against the east end, a hitching rail by the door
for z = 7, 9 do set(W + 1, 1, z, "spruce_log"); set(W + 1, 2, z, "spruce_log") end
set(W + 1, 3, 8, "spruce_log")
for x = 7, 9 do set(x, 1, -2, "spruce_fence") end
set(7, 2, -2, "lantern")

local smithy = { name = "Smithy", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  smithy.blocks[#smithy.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return smithy
