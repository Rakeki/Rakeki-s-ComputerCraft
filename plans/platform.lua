-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Mossy platform: a raised square of moss to build on. Its sides are old
-- stonework, stone and mossy stone bricks mixed with cobblestone and mossy
-- cobblestone, with raised panels standing out of the face in staggered
-- rows like big bricks. On top, a field of moss blocks inside a rim of the
-- same stone, and a stair up the middle of the south side. Packed with dirt
-- underneath. y 0 is the ground; x runs east, z south, the stair faces south.
local W, L = 21, 21 -- the platform on x 0..W-1, z 0..L-1
local TOP = 4 -- the moss layer; the sides run from the ground up to it
local PANEL, GAP = 3, 1 -- raised panels: how long, and the gap between them
local STAIR = 3 -- how wide the stair is

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function stone(x, y, z)
  local n = noise(x, y, z)
  return n < 0.3 and "stone_bricks" or n < 0.55 and "mossy_stone_bricks" or n < 0.75 and "cobblestone"
    or n < 0.95 and "mossy_cobblestone" or "cracked_stone_bricks"
end

local MID = math.floor((W - 1) / 2)
local S0, S1 = MID - math.floor(STAIR / 2), MID + math.floor(STAIR / 2) -- the stair's columns
local function onStair(x, z) return z >= L and x >= S0 - 1 and x <= S1 + 1 end

---------------------------------------------------------------- the body

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local edge = x == 0 or x == W - 1 or z == 0 or z == L - 1
      if edge then set(x, y, z, stone(x, y, z))
      elseif y == TOP then set(x, y, z, "moss_block")
      else set(x, y, z, "dirt") end
    end
  end
end

---------------------------------------------------------------- raised panels

-- each row of the face is cut into panels that stand one block out, the
-- rows staggered so they lap like brickwork; none at the corners
local function panels(len, y, at)
  local step = PANEL + GAP
  local shift = (y % 2) * math.floor(step / 2)
  for i = 1, len - 2 do
    if (i - 1 + shift) % step < PANEL then at(i) end
  end
end
for y = 0, TOP - 1 do
  panels(W, y, function(x)
    set(x, y, -1, stone(x, y, -1))
    if not onStair(x, L) then set(x, y, L, stone(x, y, L)) end
  end)
  panels(L, y, function(z)
    set(-1, y, z, stone(-1, y, z))
    set(W, y, z, stone(W, y, z))
  end)
end

---------------------------------------------------------------- the stair

-- climbs north to the top, one step a block, on solid stone with a low
-- wall either side
for k = 0, TOP do
  local z = L + TOP - k
  for x = S0 - 1, S1 + 1 do
    for y = 0, k - 1 do set(x, y, z, stone(x, y, z)) end
    if x < S0 or x > S1 then
      set(x, k, z, stone(x, k, z)); set(x, k + 1, z, stone(x, k + 1, z))
    else
      set(x, k, z, "stone_brick_stairs[facing=north]")
    end
  end
end

local platform = { name = "Mossy platform", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  platform.blocks[#platform.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return platform
