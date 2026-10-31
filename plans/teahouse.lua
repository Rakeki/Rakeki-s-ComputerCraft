-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Tea house: a Japanese-style house in a walled garden. The house stands on
-- a stone plinth with a veranda all round, dark posts and paper screens
-- (white glass panes), a bamboo-mat floor with a low table and cushions,
-- and a hipped slate roof whose corners turn up. In the garden: raked
-- gravel, a pond (39 water buckets) crossed by a little red bridge,
-- stone lanterns, a cherry tree dropping petals, bamboo, and a red gate at
-- the entrance in the bamboo fence. y 0 is the ground; x runs east, z
-- south; the house and gate face south.
local GX0, GX1, GZ0, GZ1 = -16, 16, -7, 15 -- the garden
local HX, HZ0, HZ1 = 5, -2, 4 -- the house's walls: x -HX..HX, z HZ0..HZ1
local POND = { x = -3, z = 10, rx = 5.2, rz = 2.2 }

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
local function inPond(x, z, grow) return ((x - POND.x) / (POND.rx + grow)) ^ 2 + ((z - POND.z) / (POND.rz + grow)) ^ 2 <= 1 end

---------------------------------------------------------------- the garden floor

for z = GZ0, GZ1 do
  for x = GX0, GX1 do
    local mossy = x <= -10 or x >= 10 or inPond(x, z, 1.4)
    set(x, 0, z, mossy and "moss_block" or "gravel")
  end
end
-- the pond: a block deep, stones round the edge, a couple of rocks standing up
for z = GZ0, GZ1 do
  for x = GX0, GX1 do
    if inPond(x, z, 0) then set(x, 0, z, "water"); set(x, -1, z, "clay")
    elseif inPond(x, z, 1) then
      set(x, 0, z, noise(x, 0, z) < 0.5 and "mossy_cobblestone" or "cobblestone")
      if noise(z, 1, x) < 0.12 then set(x, 1, z, "mossy_cobblestone") end
    end
  end
end
set(-4, 1, 10, "lily_pad"); set(-6, 1, 9, "lily_pad")
-- stepping stones from the gate to the bridge, and the bridge to the house
for z = 6, GZ1 do if not inPond(0, z, 1) then set(0, 0, z, z % 2 == 0 and "smooth_stone" or "polished_andesite") end end

---------------------------------------------------------------- the house

-- plinth and veranda one block up, the walls set in a block from its edge
fill(-HX - 1, 0, HZ0 - 1, HX + 1, 0, HZ1 + 1, "stone_bricks")
fill(-HX - 1, 1, HZ0 - 1, HX + 1, 1, HZ1 + 1, "dark_oak_planks")
fill(-HX + 1, 1, HZ0 + 1, HX - 1, 1, HZ1 - 1, "bamboo_mosaic")
for y = 2, 5 do
  for z = HZ0, HZ1 do
    for x = -HX, HX do
      if x == -HX or x == HX or z == HZ0 or z == HZ1 then
        local post = (x + 1) % 2 == 0 and (z == HZ0 or z == HZ1) or (z % 2 == 0 and (x == -HX or x == HX))
        local corner = (x == -HX or x == HX) and (z == HZ0 or z == HZ1)
        set(x, y, z, (y == 5 or post or corner) and "dark_oak_log" or "white_stained_glass_pane")
      end
    end
  end
end
-- a band of dark timber above the screens, up under the roof
for y = 6, 8 do
  for z = HZ0, HZ1 do for x = -HX, HX do if x == -HX or x == HX or z == HZ0 or z == HZ1 then set(x, y, z, "dark_oak_planks") end end end
end
-- the door at the front, a step down to the path
set(0, 2, HZ1, "dark_oak_door[facing=south]"); set(0, 3, HZ1, nil); set(0, 4, HZ1, "dark_oak_log")
set(0, 1, HZ1 + 2, "stone_brick_stairs[facing=north]")
-- posts round the veranda holding up the eaves
for _, x in ipairs({ -HX - 1, -3, 3, HX + 1 }) do
  for y = 2, 7 do set(x, y, HZ0 - 1, "dark_oak_log"); set(x, y, HZ1 + 1, "dark_oak_log") end
end
for y = 2, 7 do set(-HX - 1, y, 1, "dark_oak_log"); set(HX + 1, y, 1, "dark_oak_log") end
-- inside: a low table with cushions, a lamp in each corner, a scroll alcove at the back
set(0, 2, 1, "dark_oak_slab"); set(1, 2, 1, "dark_oak_slab")
set(-1, 2, 1, "red_carpet"); set(2, 2, 1, "red_carpet"); set(0, 2, 0, "green_carpet"); set(1, 2, 2, "green_carpet")
for _, c in ipairs({ { -HX + 1, HZ0 + 1 }, { HX - 1, HZ0 + 1 }, { -HX + 1, HZ1 - 1 }, { HX - 1, HZ1 - 1 } }) do set(c[1], 2, c[2], "lantern") end
set(-1, 2, HZ0 + 1, "spruce_slab"); set(0, 2, HZ0 + 1, "spruce_slab"); set(1, 2, HZ0 + 1, "flower_pot")

---------------------------------------------------------------- the roof

-- rings of slate climbing inwards from the eaves, two blocks out past the walls
local RX0, RX1, RZ0, RZ1 = -HX - 3, HX + 3, HZ0 - 3, HZ1 + 3
local k = 0
while RZ0 + k < RZ1 - k do
  local x0, x1, z0, z1, y = RX0 + k, RX1 - k, RZ0 + k, RZ1 - k, 6 + k
  for z = z0, z1 do
    for x = x0, x1 do
      local facing = z == z0 and "south" or z == z1 and "north" or x == x0 and "east" or x == x1 and "west"
      if facing then set(x, y, z, "deepslate_tile_stairs[facing=" .. facing .. "]") end
    end
  end
  k = k + 1
end
for x = RX0 + k, RX1 - k do set(x, 6 + k, RZ0 + k, "deepslate_tile_slab") end
-- the corners turn up
for _, c in ipairs({ { RX0, RZ0, "south" }, { RX1, RZ0, "south" }, { RX0, RZ1, "north" }, { RX1, RZ1, "north" } }) do
  set(c[1], 6, c[2], nil); set(c[1], 7, c[2], "deepslate_tile_stairs[facing=" .. c[3] .. "]")
end

---------------------------------------------------------------- bridge, lanterns, tree, bamboo

-- a little arched bridge across the pond, red rails
set(0, 1, 7, "mangrove_stairs[facing=south]"); set(0, 1, 12, "mangrove_stairs[facing=north]")
for z = 8, 11 do set(0, 1, z, "mangrove_planks") end
set(0, 2, 9, "mangrove_slab"); set(0, 2, 10, "mangrove_slab")
set(0, 2, 8, "mangrove_stairs[facing=south]"); set(0, 2, 11, "mangrove_stairs[facing=north]")
for z = 8, 11 do set(-1, 2, z, "mangrove_fence"); set(1, 2, z, "mangrove_fence") end
for z = 8, 11 do set(-1, 1, z, "mangrove_planks"); set(1, 1, z, "mangrove_planks") end
-- stone lanterns by the pond
for _, c in ipairs({ { -9, 8 }, { 3, 12 }, { -7, 13 } }) do
  set(c[1], 1, c[2], "stone_brick_wall"); set(c[1], 2, c[2], "lantern"); set(c[1], 3, c[2], "stone_brick_slab")
end
-- the cherry tree, west of the house, with petals on the moss under it
local TX, TZ = -13, 0
for y = 1, 5 do set(TX, y, TZ, "dark_oak_log") end
set(TX + 1, 5, TZ, "dark_oak_log"); set(TX - 1, 5, TZ + 1, "dark_oak_log")
for y = 5, 8 do
  for z = TZ - 4, TZ + 4 do
    for x = TX - 4, TX + 4 do
      local d = ((x - TX) / 3.8) ^ 2 + ((y - 6.5) / 1.7) ^ 2 + ((z - TZ) / 3.6) ^ 2
      if d <= 1 + noise(x, y, z) * 0.3 and not grid[x .. "," .. y .. "," .. z] and x >= GX0 + 1 and x <= -9 then set(x, y, z, "cherry_leaves") end
    end
  end
end
for z = TZ - 3, TZ + 3 do
  for x = TX - 2, TX + 3 do
    if noise(x, 1, z) < 0.35 and not grid[x .. ",1," .. z] and x >= GX0 + 1 then set(x, 1, z, "pink_petals") end
  end
end
-- a stand of bamboo in the east corner
for z = -5, 1 do
  for x = 12, 14 do
    if noise(x, 2, z) < 0.45 then
      local h = 3 + math.floor(noise(z, 3, x) * 4)
      for y = 1, h do set(x, y, z, "bamboo") end
    end
  end
end

---------------------------------------------------------------- fence and gate

for z = GZ0, GZ1 do
  for x = GX0, GX1 do
    if (x == GX0 or x == GX1 or z == GZ0 or z == GZ1) and not (z == GZ1 and math.abs(x) <= 1) then set(x, 1, z, "bamboo_fence") end
  end
end
-- a red gate over the way in
for y = 1, 5 do set(-2, y, GZ1, "red_concrete"); set(2, y, GZ1, "red_concrete") end
for x = -2, 2 do set(x, 5, GZ1, "red_concrete") end
for x = -3, 3 do set(x, 6, GZ1, "black_concrete") end
set(-1, 1, GZ1, nil); set(1, 1, GZ1, nil)

local tea = { name = "Tea house", blocks = {} }
for key, block in pairs(grid) do
  local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
  tea.blocks[#tea.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return tea
