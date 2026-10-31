-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Treehouse: a giant tree with a cabin in its crown. A thick spruce trunk
-- with roots spreading over the ground and branches reaching out, a stair
-- that winds round the trunk and comes up through the floor of a little
-- cabin with windows and a pitched roof, on a railed deck with a lantern
-- on every corner. Leaves (azalea, some flowering) in big clumps
-- round it all. y 0 is the ground; x and z are from the trunk's middle.
local DECK = 13 -- the deck's level

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
-- only fills air, so leaves never cover the wood, deck or cabin
local function soft(x, y, z, block)
  if not grid[x .. "," .. y .. "," .. z] then set(x, y, z, block) end
end
-- a rough ball of leaves
local function clump(cx, cy, cz, r)
  for y = cy - r, cy + r do
    for z = cz - r - 1, cz + r + 1 do
      for x = cx - r - 1, cx + r + 1 do
        local d = math.sqrt((x - cx) ^ 2 + ((y - cy) * 1.4) ^ 2 + (z - cz) ^ 2)
        local onDeck = math.abs(x) <= 5 and math.abs(z) <= 5 and y <= DECK + 3
        local cabin = x >= -4 and x <= 4 and z >= 0 and z <= 5 and y <= DECK + 6
        if d <= r + noise(x, y, z) * 0.9 and not onDeck and not cabin then soft(x, y, z, noise(z, x, y) < 0.3 and "flowering_azalea_leaves" or "azalea_leaves") end
      end
    end
  end
end

---------------------------------------------------------------- trunk, roots and branches

-- a 3x3 trunk with its corners cut in above the roots, wood (bark all round) so it looks solid
for y = 0, DECK + 8 do
  for z = -1, 1 do
    for x = -1, 1 do
      if not (math.abs(x) == 1 and math.abs(z) == 1 and y > 2 and y < DECK - 1) then set(x, y, z, "spruce_wood") end
    end
  end
end
-- roots: low ridges out along the ground
for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, -1 } }) do
  for k = 2, 4 do
    set(d[1] * k, 0, d[2] * k, "spruce_wood")
    if k < 4 then set(d[1] * k, 1, d[2] * k, "rooted_dirt") end
  end
end
-- branches up through the crown, each ending in a clump of leaves
local BRANCHES = { { 6, DECK + 4, 3 }, { -6, DECK + 5, -2 }, { 2, DECK + 7, -6 }, { -3, DECK + 3, 6 }, { 0, DECK + 10, 0 } }
for _, b in ipairs(BRANCHES) do
  local steps = math.max(math.abs(b[1]), math.abs(b[3]), 1)
  for s = 0, steps do
    local t = s / steps
    local x, z = math.floor(b[1] * t + 0.5), math.floor(b[3] * t + 0.5)
    local y = math.floor(DECK + 5 + (b[2] - DECK - 5) * t + 0.5)
    set(x, y, z, "spruce_wood")
  end
end

---------------------------------------------------------------- the stair round the trunk

-- a step a block higher each cell, round the ring two out from the middle
local RING = {}
for x = -2, 1 do RING[#RING + 1] = { x, -2, "east" } end
for z = -2, 1 do RING[#RING + 1] = { 2, z, "south" } end
for x = 2, -1, -1 do RING[#RING + 1] = { x, 2, "west" } end
for z = 2, -1, -1 do RING[#RING + 1] = { -2, z, "north" } end
for i = 0, DECK - 2 do
  local c = RING[i % #RING + 1]
  set(c[1], 1 + i, c[2], "spruce_stairs[facing=" .. c[3] .. "]")
end

---------------------------------------------------------------- deck and cabin

local D = 5 -- the deck reaches this far each way
for z = -D, D do
  for x = -D, D do
    if not (math.abs(x) <= 1 and math.abs(z) <= 1) then set(x, DECK, z, "spruce_planks") end
    if math.abs(x) == D or math.abs(z) == D then set(x, DECK + 1, z, "spruce_fence") end
  end
end
-- where the stair comes up: room to climb, and a gap in the floor
for k = 0, 1 do local c = RING[(DECK - 2 - k) % #RING + 1]; set(c[1], DECK, c[2], nil) end
local top = RING[(DECK - 1) % #RING + 1]
set(top[1], DECK, top[2], "spruce_stairs[facing=" .. top[3] .. "]")
-- braces under the deck
for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
  for k = 2, 4 do set(d[1] * k, DECK - 1 - (4 - k), d[2] * k, "spruce_wood") end
end
for _, c in ipairs({ { -D, -D }, { D, -D }, { -D, D }, { D, D } }) do set(c[1], DECK + 1, c[2], "spruce_planks"); set(c[1], DECK + 2, c[2], "lantern") end

-- the cabin on the south half of the deck, the trunk through its north wall
local CX0, CX1, CZ0, CZ1 = -3, 3, 1, 4
for y = DECK + 1, DECK + 3 do
  for z = CZ0, CZ1 do
    for x = CX0, CX1 do
      local wall = x == CX0 or x == CX1 or z == CZ0 or z == CZ1
      if wall then
        local corner = (x == CX0 or x == CX1) and (z == CZ0 or z == CZ1)
        set(x, y, z, corner and "stripped_spruce_log" or "oak_planks")
      elseif not (math.abs(x) <= 1 and z <= 1) then set(x, y, z, nil) end
    end
  end
end
set(CX0, DECK + 2, 3, "glass_pane"); set(CX1, DECK + 2, 3, "glass_pane"); set(-1, DECK + 2, CZ1, "glass_pane"); set(1, DECK + 2, CZ1, "glass_pane")
set(2, DECK + 1, CZ0, "spruce_door[facing=north]"); set(2, DECK + 2, CZ0, nil)
set(-2, DECK + 1, 3, "red_carpet"); set(-1, DECK + 1, 3, "red_carpet"); set(2, DECK + 1, 3, "barrel"); set(2, DECK + 2, 3, "lantern")
set(1, DECK + 1, 3, "crafting_table")
-- its roof, ridge running east-west
for i = 0, 2 do
  for x = CX0 - 1, CX1 + 1 do
    set(x, DECK + 4 + i, CZ0 - 1 + i, "spruce_stairs[facing=south]")
    set(x, DECK + 4 + i, CZ1 + 1 - i, "spruce_stairs[facing=north]")
  end
  for z = CZ0 + i, CZ1 - i do set(CX0, DECK + 4 + i, z, "oak_planks"); set(CX1, DECK + 4 + i, z, "oak_planks") end
end
for x = CX0 - 1, CX1 + 1 do if CZ0 + 2 == CZ1 - 1 then set(x, DECK + 6, CZ0 + 2, "spruce_slab") end end

---------------------------------------------------------------- leaves

clump(6, DECK + 5, 3, 3)
clump(-6, DECK + 6, -2, 3)
clump(2, DECK + 8, -6, 3)
clump(-3, DECK + 4, 6, 2)
clump(0, DECK + 12, 0, 4)
clump(-5, DECK + 9, 4, 2)
clump(5, DECK + 10, -2, 2)

local tree = { name = "Treehouse", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  tree.blocks[#tree.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return tree
