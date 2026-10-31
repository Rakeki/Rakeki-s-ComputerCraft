-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Windmill: an eight-sided tower on a cobblestone plinth, stone below and
-- white plaster with dark oak corner posts above, narrowing halfway up. A
-- stepped dark oak cap, and four framed cloth sails on the front (north)
-- turning on a wooden axle. Inside, the drive shaft runs up the middle, a
-- stair climbs to the loft, and there are barrels, a grindstone and a
-- smoker for the miller; hay and a lamp post wait by the door. y 0 is the
-- ground; x and z are from the tower's middle.
local SAIL = 10 -- each sail's length from the hub
local HUB_Y = 12

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

-- an octagon of this radius: a square with its corners cut off
local function inside(x, z, r) return math.abs(x) <= r and math.abs(z) <= r and math.abs(x) + math.abs(z) <= r + math.floor(r / 2) end
local function edge(x, z, r)
  return inside(x, z, r) and not (inside(x + 1, z, r) and inside(x - 1, z, r) and inside(x, z + 1, r) and inside(x, z - 1, r))
end
local function corner(x, z, r) return edge(x, z, r) and (math.abs(x) == r or math.abs(z) == r) and math.abs(x) + math.abs(z) == r + math.floor(r / 2) end

---------------------------------------------------------------- plinth and tower

for z = -6, 6 do
  for x = -6, 6 do
    if inside(x, z, 6) then set(x, 0, z, noise(x, 0, z) < 0.3 and "mossy_cobblestone" or "cobblestone") end
  end
end

for y = 1, 12 do
  local r = y <= 6 and 5 or 4
  for z = -r, r do
    for x = -r, r do
      if edge(x, z, r) then
        local block
        if y <= 3 then block = noise(x, y, z) < 0.25 and "cracked_stone_bricks" or "stone_bricks"
        elseif corner(x, z, r) then block = "dark_oak_log"
        else block = "white_terracotta" end
        set(x, y, z, block)
      end
    end
  end
  -- a dark band where the tower steps in
  if y == 6 then for z = -5, 5 do for x = -5, 5 do if inside(x, z, 5) and not inside(x, z, 3) then set(x, 7, z, "dark_oak_planks") end end end end
end

-- windows on the sides and back, a door at the front
for _, y in ipairs({ 4, 9 }) do
  local r = y <= 6 and 5 or 4
  set(r, y, 0, "glass_pane"); set(-r, y, 0, "glass_pane"); set(0, y, r, "glass_pane")
end
set(0, 1, -5, "spruce_door[facing=north]"); set(0, 2, -5, nil)
set(0, 3, -5, "dark_oak_planks")

-- inside: the loft floor over the back half, a stair up the east side, the shaft
for z = 2, 4 do for x = -4, 4 do if inside(x, z, 4) and not edge(x, z, 5) then set(x, 7, z, "spruce_planks") end end end
for i = 0, 5 do set(2, 1 + i, -4 + i, "spruce_stairs[facing=south]") end
for y = 1, 12 do set(0, y, 0, "stripped_spruce_log") end
set(-3, 1, 2, "barrel"); set(-3, 1, 3, "barrel"); set(-3, 2, 3, "barrel"); set(-2, 1, 4, "chest")
set(-1, 1, 0, "grindstone"); set(-3, 1, -2, "smoker"); set(-3, 1, -3, "crafting_table")
set(3, 8, 3, "lantern"); set(-3, 8, 3, "hay_block"); set(-3, 1, 0, "lantern")

---------------------------------------------------------------- cap

for i = 0, 4 do
  local r = 5 - i
  for z = -r, r do
    for x = -r, r do
      if edge(x, z, r) or (i == 4 and inside(x, z, r)) then set(x, 13 + i, z, i == 0 and "dark_oak_slab" or "dark_oak_planks") end
    end
  end
end
set(0, 18, 0, "dark_oak_fence"); set(0, 19, 0, "lantern")

---------------------------------------------------------------- axle and sails

set(0, HUB_Y, -5, "stripped_spruce_wood"); set(0, HUB_Y, -6, "stripped_spruce_wood")
set(0, HUB_Y, -7, "dark_oak_planks")
-- up, right, down, left; each sail's cloth hangs on the same turning side
-- of its spar, framed in spruce
for _, d in ipairs({ { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }) do
  for along = 1, SAIL do
    set(d[1] * along, HUB_Y + d[2] * along, -7, "stripped_spruce_wood")
    if along >= 3 then
      for across = 1, 3 do
        local x, y = d[1] * along + d[2] * across, HUB_Y + d[2] * along - d[1] * across
        set(x, y, -7, (across == 3 or along == 3 or along == SAIL) and "spruce_planks" or "white_wool")
      end
    end
  end
end

---------------------------------------------------------------- by the door

set(-3, 1, -6, "hay_block"); set(-4, 1, -5, "hay_block"); set(-3, 2, -6, "hay_block")
set(3, 1, -6, "barrel"); set(4, 1, -5, "barrel")
set(2, 1, -6, "spruce_fence"); set(2, 2, -6, "spruce_fence"); set(2, 3, -6, "lantern")

local windmill = { name = "Windmill", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  windmill.blocks[#windmill.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return windmill
