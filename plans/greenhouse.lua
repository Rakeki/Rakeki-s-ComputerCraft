-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Greenhouse: a long glasshouse with a white frame and a pitched glass
-- roof, crossed in the middle by a taller domed wing. Raised beds of moss
-- run down both sides full of azaleas, ferns, flowers and bamboo; a water
-- channel lined with sugar cane runs along the middle under the paths;
-- melons and pumpkins at the ends, and a fountain under the dome (31
-- water buckets in all). Doors at both ends. y 0 is the ground; x runs
-- east, z south; x and z are from the middle.
local HW, HL = 6, 15 -- the long hall's walls at x -HW..HW, z -HL..HL
local CW = 9 -- the cross wing reaches x -CW..CW at z -3..3
local WALL = 5 -- the glass walls' height
local FRAME = "white_concrete"

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function dist(x, z) return math.sqrt(x * x + z * z) end
local function inHall(x, z) return math.abs(x) <= HW and math.abs(z) <= HL end
local function inWing(x, z) return math.abs(x) <= CW and math.abs(z) <= 3 end
local function inside(x, z) return inHall(x, z) or inWing(x, z) end

---------------------------------------------------------------- floor, walls and frame

for z = -HL, HL do
  for x = -CW, CW do
    if inside(x, z) then set(x, 0, z, "stone_bricks") end
  end
end
for y = 1, WALL do
  for z = -HL, HL do
    for x = -CW, CW do
      local edge = inside(x, z) and not (inside(x + 1, z) and inside(x - 1, z) and inside(x, z + 1) and inside(x, z - 1))
      if edge then
        local post = (math.abs(x) == HW and z % 3 == 0) or (math.abs(z) == HL and x % 3 == 0) or (math.abs(z) == 3 and x % 3 == 0)
          or (math.abs(x) == CW) and z % 3 == 0 or y == WALL or y == 1
        set(x, y, z, post and (y == 1 and "stone_bricks" or FRAME) or "glass")
      end
    end
  end
end
-- doors at both ends
for _, z in ipairs({ -HL, HL }) do
  set(0, 1, z, "birch_door[facing=" .. (z < 0 and "north" or "south") .. "]"); set(0, 2, z, nil)
  set(0, 3, z, FRAME)
  for _, x in ipairs({ -2, 2 }) do
    local out = z + (z < 0 and -1 or 1)
    set(x, 0, out, "moss_block"); set(x, 1, out, "azalea")
  end
end

---------------------------------------------------------------- the roofs

-- the hall: glass pitched along its length, white ribs every third row
local i = 0
while -HW - 1 + i <= HW + 1 - i do
  for z = -HL - 1, HL + 1 do
    local rib = z % 3 == 0 or math.abs(z) == HL + 1
    local y = WALL + 1 + i
    if -HW - 1 + i == HW + 1 - i then set(0, y, z, rib and FRAME or "glass")
    else
      set(-HW - 1 + i, y, z, rib and FRAME or "glass")
      set(HW + 1 - i, y, z, rib and FRAME or "glass")
    end
  end
  for _, z in ipairs({ -HL, HL }) do for x = -HW + i, HW - i do set(x, WALL + 1 + i, z, "glass") end end
  i = i + 1
end
-- the cross wing: the same, the other way, and a glass dome where they meet
local j = 0
while -4 + j <= 4 - j do
  for x = -CW - 1, CW + 1 do
    if math.abs(x) > HW then
      local rib = x % 3 == 0 or math.abs(x) == CW + 1
      local y = WALL + 1 + j
      if -4 + j == 4 - j then set(x, y, 0, rib and FRAME or "glass")
      else set(x, y, -4 + j, rib and FRAME or "glass"); set(x, y, 4 - j, rib and FRAME or "glass") end
    end
  end
  for _, x in ipairs({ -CW, CW }) do for z = -3 + j, 3 - j do set(x, WALL + 1 + j, z, "glass") end end
  j = j + 1
end
local DOME = WALL + 7
for z = -8, 8 do
  for y = DOME - 4, DOME + 4 do
    for x = -8, 8 do
      local d = math.sqrt(x * x + (y - DOME + 4) ^ 2 * 1.6 + z * z)
      if d <= 7.5 and d > 6.4 and y > WALL + 3 then
        local rib = x == 0 or z == 0 or x == z or x == -z
        set(x, y, z, rib and FRAME or "glass")
      elseif d <= 6.4 and y > WALL + 3 then set(x, y, z, nil) end
    end
  end
end
set(0, DOME + 4, 0, FRAME); set(0, DOME + 5, 0, "end_rod")

---------------------------------------------------------------- beds, channel and fountain

local FLOWERS = { "poppy", "cornflower", "dandelion", "allium", "oxeye_daisy", "azure_bluet", "red_tulip", "orange_tulip", "lily_of_the_valley", "blue_orchid" }
for z = -HL + 1, HL - 1 do
  if math.abs(z) > 4 then
    -- the channel along the middle, sugar cane either side of it
    set(0, 0, z, "water"); set(0, -1, z, "stone_bricks")
    set(-1, 0, z, "moss_block"); set(1, 0, z, "moss_block")
    if math.abs(z) % 4 ~= 0 then
      for y = 1, 2 do set(-1, y, z, "sugar_cane"); set(1, y, z, "sugar_cane") end
    else set(-1, 1, z, "stone_brick_slab"); set(1, 1, z, "stone_brick_slab") end
    -- the paths, then a raised bed of moss against each wall
    for _, s in ipairs({ -1, 1 }) do
      set(s * 2, 0, z, "polished_andesite"); set(s * 3, 0, z, "polished_andesite")
      set(s * 4, 1, z, "stone_brick_slab")
      set(s * 5, 1, z, "moss_block")
      local n = noise(s, 1, z)
      local plant
      if math.abs(z) >= HL - 2 then plant = n < 0.5 and "melon" or "pumpkin"
      elseif n < 0.2 then plant = "flowering_azalea"
      elseif n < 0.35 then plant = "azalea"
      elseif n < 0.5 then plant = "fern"
      elseif n < 0.62 then plant = "bamboo"
      else plant = FLOWERS[math.floor(noise(z, s, 3) * #FLOWERS) + 1] end
      set(s * 5, 2, z, plant)
      if plant == "bamboo" then set(s * 5, 3, z, "bamboo"); set(s * 5, 4, z, "bamboo") end
    end
  end
end
-- the channel's ends, and planks across it where the paths cross
set(0, 0, -HL + 1, "stone_bricks"); set(0, 0, HL - 1, "stone_bricks")
for _, z in ipairs({ -10, 10 }) do set(0, 1, z, "birch_slab") end
-- the fountain under the dome, in the middle of the cross
for z = -3, 3 do
  for x = -CW + 1, CW - 1 do
    local d = dist(x, z)
    if d <= 2.6 then
      set(x, 0, z, d <= 1.5 and "water" or "stone_bricks"); set(x, -1, z, "stone_bricks")
      if d > 1.5 then set(x, 1, z, "stone_brick_wall") end
    elseif math.abs(x) >= 6 then
      set(x, 1, z, "moss_block"); set(x, 2, z, noise(x, 2, z) < 0.5 and "flowering_azalea" or "fern")
    else set(x, 0, z, "polished_andesite") end
  end
end
set(0, 1, 0, "stone_bricks"); set(0, 2, 0, "stone_bricks"); set(0, 3, 0, "water")
set(0, 0, 0, "stone_bricks")
-- a bench at each end of the wing, lanterns on posts
for _, x in ipairs({ -4, 4 }) do set(x, 1, -3, "birch_stairs[facing=north]"); set(x, 1, 3, "birch_stairs[facing=south]") end
for _, c in ipairs({ { -3, -6 }, { 3, -6 }, { -3, 6 }, { 3, 6 } }) do set(c[1], 1, c[2], "birch_fence"); set(c[1], 2, c[2], "lantern") end

local green = { name = "Greenhouse", blocks = {} }
for key, block in pairs(grid) do
  local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
  green.blocks[#green.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return green
