-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Longhouse: a Viking-style hall, long and low, its stone footing and
-- spruce walls almost hidden under a great dark roof that comes down
-- nearly to the ground. Painted shields line both sides, crossed beams
-- rise over each gable end, and a porch shelters the door. Inside, a long
-- fire trench runs down the middle between benches and tables, with the
-- chieftain's seat at the far end and barrels and chests by the door.
-- y 0 is the ground; x runs east, z south; the door faces north.
local W, L = 10, 26 -- walls on x 0..W, z 0..L
local MID = 5
local WALL = 3 -- the walls' top
local SHIELDS = { "red_wool", "blue_wool", "yellow_wool", "white_wool", "green_wool" }

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

---------------------------------------------------------------- floor and walls

for z = 0, L do for x = 0, W do set(x, 0, z, noise(x, 0, z) < 0.3 and "coarse_dirt" or "spruce_planks") end end
for y = 1, WALL do
  for z = 0, L do
    for x = 0, W do
      if x == 0 or x == W or z == 0 or z == L then
        local post = (x == 0 or x == W) and z % 3 == 0 or (z == 0 or z == L) and (x == 0 or x == W or x == 3 or x == 7)
        if y == 1 then set(x, y, z, noise(x, y, z) < 0.3 and "mossy_cobblestone" or "cobblestone")
        else set(x, y, z, post and "stripped_spruce_log" or "spruce_planks") end
      end
    end
  end
end
-- a shield on each side of every bay between the posts
for z = 1, L - 1, 3 do
  local k = math.floor(z / 3)
  set(-1, 2, z, SHIELDS[k % #SHIELDS + 1]); set(W + 1, 2, z, SHIELDS[(k + 2) % #SHIELDS + 1])
end

---------------------------------------------------------------- roof

local c = 0
while -1 + c < W + 1 - c do
  for z = -1, L + 1 do
    set(-1 + c, WALL + c, z, "dark_oak_stairs[facing=east]")
    set(W + 1 - c, WALL + c, z, "dark_oak_stairs[facing=west]")
  end
  for _, z in ipairs({ 0, L }) do for x = c, W - c do set(x, WALL + c, z, "spruce_planks") end end
  c = c + 1
end
for z = -1, L + 1 do set(MID, WALL + c, z, "dark_oak_slab") end
-- crossed beams over each gable, and a smoke hole along the ridge
for _, z in ipairs({ -1, L + 1 }) do
  set(MID, WALL + c, z, "stripped_spruce_wood")
  set(MID - 1, WALL + c + 1, z, "stripped_spruce_wood"); set(MID + 1, WALL + c + 1, z, "stripped_spruce_wood")
  set(MID - 2, WALL + c + 2, z, "stripped_spruce_wood"); set(MID + 2, WALL + c + 2, z, "stripped_spruce_wood")
end
for z = 10, 16, 3 do set(MID, WALL + c, z, nil) end
-- little windows high in the gables
for _, z in ipairs({ 0, L }) do set(MID, WALL + 3, z, "glass_pane"); set(MID - 2, WALL + 1, z, "glass_pane"); set(MID + 2, WALL + 1, z, "glass_pane") end

---------------------------------------------------------------- the door and porch

set(MID, 1, 0, "spruce_door[facing=north]"); set(MID, 2, 0, nil); set(MID, 3, 0, "stripped_spruce_log")
for _, x in ipairs({ MID - 2, MID + 2 }) do for y = 1, 3 do set(x, y, -2, "stripped_spruce_log") end end
for x = MID - 3, MID + 3 do
  set(x, 4, -3, "dark_oak_stairs[facing=south]")
  set(x, 4, -2, "dark_oak_planks")
end
for x = MID - 1, MID + 1 do set(x, 0, -1, "cobblestone"); set(x, 0, -2, "cobblestone") end
for x = MID - 2, MID + 2 do set(x, 4, -1, "dark_oak_planks") end

---------------------------------------------------------------- inside

-- the fire trench, a stone kerb round a row of campfires
for z = 7, 19 do
  set(MID, 0, z, "cobblestone")
  set(MID, 1, z, (z % 2 == 1 and z > 7 and z < 19) and "campfire" or nil)
  set(MID - 1, 1, z, "cobblestone_slab"); set(MID + 1, 1, z, "cobblestone_slab")
end
set(MID, 1, 7, "cobblestone_slab"); set(MID, 1, 19, "cobblestone_slab")
-- benches against the walls, a long table in front of each
for z = 4, 22 do
  if z % 3 ~= 0 then
    set(1, 1, z, "spruce_stairs[facing=west]"); set(W - 1, 1, z, "spruce_stairs[facing=east]")
  end
  if z >= 5 and z <= 21 then
    set(2, 1, z, "dark_oak_fence"); set(2, 2, z, "spruce_pressure_plate")
    set(W - 2, 1, z, "dark_oak_fence"); set(W - 2, 2, z, "spruce_pressure_plate")
  end
end
-- the chieftain's seat at the far end, lamps either side
set(MID, 1, L - 2, "spruce_stairs[facing=south]"); set(MID - 1, 1, L - 2, "spruce_planks"); set(MID + 1, 1, L - 2, "spruce_planks")
for x = MID - 1, MID + 1 do set(x, 1, L - 1, "red_carpet") end
for _, x in ipairs({ MID - 3, MID + 3 }) do set(x, 1, L - 2, "dark_oak_fence"); set(x, 2, L - 2, "lantern") end
for y = 2, 3 do set(MID, y, L - 1, "red_wool") end
-- by the door: barrels, chests, a crafting table
set(1, 1, 1, "barrel"); set(1, 2, 1, "barrel"); set(1, 1, 2, "barrel"); set(W - 1, 1, 1, "chest"); set(W - 1, 1, 2, "chest")
set(2, 1, 1, "crafting_table"); set(W - 2, 1, 1, "lantern")

---------------------------------------------------------------- outside

-- a woodpile against the east wall and a chopping block
for z = 20, 23 do set(W + 2, 1, z, "spruce_log"); set(W + 2, 2, z, "spruce_log") end
set(W + 2, 3, 21, "spruce_log"); set(W + 2, 3, 22, "spruce_log")
set(W + 3, 1, 17, "stripped_spruce_log")
-- a drying rack of fences by the porch
for x = MID + 4, MID + 6 do set(x, 1, -3, "spruce_fence"); set(x, 2, -3, "spruce_fence") end
set(MID + 4, 3, -3, "spruce_slab"); set(MID + 5, 3, -3, "spruce_slab"); set(MID + 6, 3, -3, "spruce_slab")

local hall = { name = "Longhouse", blocks = {} }
for key, block in pairs(grid) do
  local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
  hall.blocks[#hall.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return hall
