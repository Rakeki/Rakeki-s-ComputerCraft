-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Greenhouse: a tall glasshouse under a barrel-vaulted glass roof, oak
-- ribs every fourth row and spruce purlins along it. Both ends are a
-- timber-framed front: stripped oak posts on stone plinths, spruce bands
-- between the floors, arched oak windows and an arched doorway, with
-- spires on the posts and along the ridge, and flower planters outside.
-- Inside, raised beds of flowers, azaleas, ferns and bamboo along both
-- walls, sugar cane along a water channel down the middle, two azalea
-- trees and a fountain in the centre. y 0 is the ground; x runs east,
-- z south; x and z are from the middle.
local HW, HL = 12, 16 -- the walls at x -HW..HW, the fronts at z -HL and HL
local SPRING = 9 -- the vault starts curving inwards above this height
local RX, RY = 12.5, 12 -- the vault's half width and height above SPRING
local POSTS = { -12, -8, -3, 3, 8, 12 } -- the fronts' posts (x)
local BANDS = { 7, 13, 18 } -- the fronts' spruce bands between floors (y)

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
local function get(x, y, z) return grid[x .. "," .. y .. "," .. z] end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function dist(x, z) return math.sqrt(x * x + z * z) end
local function has(list, v)
  for _, w in ipairs(list) do if w == v then return true end end
  return false
end

-- the vault's cross-section (x, y): straight walls up to SPRING, then a half ellipse
local function inProfile(x, y)
  if y < 1 then return false end
  if y < SPRING then return math.abs(x) <= HW end
  return (x / RX) ^ 2 + ((y - SPRING) / RY) ^ 2 <= 1
end
local function shell(x, y)
  return inProfile(x, y) and not (inProfile(x - 1, y) and inProfile(x + 1, y) and inProfile(x, y + 1))
end
local TOP = SPRING + RY
local function topAt(x)
  for y = TOP, 1, -1 do if inProfile(x, y) then return y end end
end
local function isPost(x, y) return has(POSTS, x) or (x == 0 and y > BANDS[2]) end

---------------------------------------------------------------- floor and vault

for z = -HL, HL do
  for x = -HW, HW do set(x, 0, z, "stone_bricks") end
end
for z = -HL + 1, HL - 1 do
  local rib = z % 4 == 0
  for y = 1, TOP do
    for x = -HW, HW do
      if shell(x, y) then
        local block
        if y < SPRING then -- the straight side walls
          if y == 1 then block = "stone_bricks"
          elseif rib then block = "stripped_oak_log"
          elseif y == BANDS[1] then block = "spruce_planks"
          else block = "glass" end
        elseif rib then block = "oak_planks"
        elseif x % 4 == 0 then block = "spruce_planks"
        else block = "glass" end
        set(x, y, z, block)
      end
    end
  end
  -- stone feet under every other rib, and a spire on each rib along the ridge
  if z % 8 == 0 then
    for _, s in ipairs({ -1, 1 }) do
      set(s * (HW + 1), 0, z, "chiseled_stone_bricks"); set(s * (HW + 1), 1, z, "stone_bricks"); set(s * (HW + 1), 2, z, "stone_brick_wall")
    end
  end
  if rib then set(0, TOP + 1, z, "spruce_fence"); set(0, TOP + 2, z, "lightning_rod") end
end

---------------------------------------------------------------- the two fronts

local FLOWERS = { "poppy", "cornflower", "red_tulip", "azure_bluet", "allium", "oxeye_daisy", "dandelion", "blue_orchid" }

-- The bay (window) a front cell is in: its x and y bounds.
local function bay(x, y)
  local x0, x1 = x, x
  while not isPost(x0 - 1, y) and x0 - 1 > -HW do x0 = x0 - 1 end
  while not isPost(x1 + 1, y) and x1 + 1 < HW do x1 = x1 + 1 end
  local y1 = TOP
  for _, b in ipairs(BANDS) do if b > y and b - 1 < y1 then y1 = b - 1 end end
  return x0, x1, y1
end

local function front(z, s) -- s: -1 for the north front, 1 for the south one
  local out = z + s
  for y = 1, TOP do
    for x = -HW, HW do
      if inProfile(x, y) then
        -- the front wall itself
        local block
        if isPost(x, y) and not (shell(x, y) and y >= SPRING) then block = "stripped_oak_log"
        elseif shell(x, y) then block = "oak_planks"
        elseif has(BANDS, y) then block = "spruce_planks"
        elseif y == 1 then block = "stone_bricks"
        else
          local x0, x1, y1 = bay(x, y)
          local wide = x1 - x0 + 1
          local corner = wide >= 3 and y1 < TOP and (
            (y == y1 and (x == x0 or x == x1)) or
            (wide >= 5 and y == y1 and (x == x0 + 1 or x == x1 - 1)) or
            (wide >= 5 and y == y1 - 1 and (x == x0 or x == x1)))
          block = corner and "oak_planks" or "glass"
        end
        set(x, y, z, block)
        -- the frame standing out in front of it: posts on plinths, ledges, the rim
        if isPost(x, y) then
          local plinth = { "chiseled_stone_bricks", "stone_bricks", "polished_andesite" }
          set(x, y, out, (y <= 3 and x ~= 0) and plinth[y] or "stripped_oak_log")
        elseif shell(x, y) and y >= SPRING then set(x, y, out, "oak_planks")
        elseif has(BANDS, y) then set(x, y, out, "spruce_slab") end
      end
    end
  end
  -- the doorway, with a lamp post either side
  set(0, 1, z, "spruce_door[facing=" .. (s < 0 and "north" or "south") .. "]"); set(0, 2, z, nil)
  for _, x in ipairs({ -2, 2 }) do
    for y = 1, 3 do set(x, y, out, "spruce_fence") end
    set(x, 4, out, "lantern")
  end
  -- spires on the posts, the middle one tallest
  for _, x in ipairs({ -12, -8, -3, 0, 3, 8, 12 }) do
    local top, n = topAt(x), x == 0 and 3 or 2
    for i = 1, n do set(x, top + i, out, "spruce_fence") end
    set(x, top + n + 1, out, "lightning_rod")
  end
  -- stone blocks in front of the plinths, planters between them, a gravel path
  local far = out + s
  for x = -HW, HW do
    if has(POSTS, x) then
      set(x, 0, far, "chiseled_stone_bricks"); set(x, 1, far, noise(x, 1, far) < 0.4 and "mossy_stone_bricks" or "stone_bricks")
      set(x, 2, far, math.abs(x) == 3 and "stone_brick_wall" or "stone_brick_slab")
      if math.abs(x) == 3 then set(x, 3, far, "lantern") end
    elseif math.abs(x) >= 2 and get(x, 1, out) == nil then
      set(x, 0, out, "moss_block")
      local n = noise(x, 1, out)
      local plant = n < 0.15 and "flowering_azalea" or FLOWERS[math.floor(noise(x, 2, out) * #FLOWERS) + 1]
      set(x, 1, out, plant)
    end
    if not has(POSTS, x) and math.abs(x) >= 2 then
      set(x, 0, far, "moss_block")
      set(x, 1, far, (math.abs(x) == 10 or math.abs(x) == 11) and "bamboo" or FLOWERS[math.floor(noise(x, 3, far) * #FLOWERS) + 1])
      if math.abs(x) == 10 or math.abs(x) == 11 then
        for y = 2, math.abs(x) == 10 and 5 or 3 do set(x, y, far, "bamboo") end
      end
    end
  end
  for d = 1, 4 do
    for x = -1, 1 do
      local n = noise(x, 0, z + s * d)
      if d > 1 or x == 0 then set(x, 0, z + s * d, n < 0.45 and "gravel" or n < 0.8 and "coarse_dirt" or "cobblestone") end
    end
  end
end
front(-HL, -1)
front(HL, 1)

---------------------------------------------------------------- beds, channel, trees and fountain

local function sidePlant(s, z)
  local n = noise(s, 1, z)
  if math.abs(z) >= HL - 4 then return n < 0.5 and "melon" or "pumpkin"
  elseif n < 0.18 then return "flowering_azalea"
  elseif n < 0.3 then return "azalea"
  elseif n < 0.45 then return "fern"
  elseif n < 0.58 then return "bamboo" end
  return FLOWERS[math.floor(noise(z, s, 3) * #FLOWERS) + 1]
end

for z = -HL + 1, HL - 1 do
  for x = -HW + 1, HW - 1 do
    local n = noise(x, 0, z)
    set(x, 0, z, n < 0.7 and "polished_andesite" or n < 0.9 and "stone_bricks" or "andesite")
  end
  if math.abs(z) <= HL - 3 then
    -- raised beds along both walls
    for _, s in ipairs({ -1, 1 }) do
      set(s * 9, 1, z, "stone_brick_slab")
      for _, x in ipairs({ 10, 11 }) do
        set(s * x, 1, z, "moss_block")
        local plant = sidePlant(s * x, z)
        set(s * x, 2, z, plant)
        if plant == "bamboo" then for y = 3, 5 do set(s * x, y, z, "bamboo") end end
      end
    end
    -- the middle bed and its channel, round the fountain
    if math.abs(z) >= 5 then
      for x = -4, 4 do set(x, 1, z, math.abs(x) == 4 and "stone_bricks" or "moss_block") end
      local tree = math.abs(z) == 10
      if not tree then set(0, 1, z, "water") end
      for _, s in ipairs({ -1, 1 }) do
        if not tree and math.abs(z) >= 6 and math.abs(z) <= HL - 4 then
          set(s, 2, z, "sugar_cane"); set(s, 3, z, "sugar_cane")
        else set(s, 2, z, "fern") end
        for _, x in ipairs({ 2, 3 }) do
          local n = noise(s * x, 2, z)
          set(s * x, 2, z, n < 0.25 and "fern" or n < 0.4 and "azalea" or FLOWERS[math.floor(noise(z, x, s) * #FLOWERS) + 1])
        end
      end
    end
  end
end
-- the channel's ends
for _, z in ipairs({ -HL + 3, HL - 3, -5, 5 }) do set(0, 1, z, "stone_bricks") end

-- two azalea trees in the middle bed
for _, tz in ipairs({ -10, 10 }) do
  for y = 2, 7 do set(0, y, tz, "oak_log") end
  for y = 6, 10 do
    for z = tz - 3, tz + 3 do
      for x = -3, 3 do
        local d = math.sqrt(x * x + (y - 8) ^ 2 * 1.5 + (z - tz) ^ 2)
        if d <= 3.2 and get(x, y, z) == nil then
          set(x, y, z, noise(x, y, z) < 0.35 and "flowering_azalea_leaves" or "azalea_leaves")
        end
      end
    end
  end
  set(0, 8, tz, "oak_log")
end

-- the fountain in the middle
for z = -4, 4 do
  for x = -4, 4 do
    local d = dist(x, z)
    if d <= 2.5 then set(x, 1, z, "water")
    elseif d <= 3.5 then set(x, 1, z, "stone_bricks"); set(x, 2, z, "stone_brick_slab") end
  end
end
for y = 1, 3 do set(0, y, 0, y == 3 and "chiseled_stone_bricks" or "stone_bricks") end
set(0, 4, 0, "water")
-- benches facing the fountain, lanterns at the middle bed's corners
for z = -1, 1 do set(-6, 1, z, "spruce_stairs[facing=west]"); set(6, 1, z, "spruce_stairs[facing=east]") end
for _, c in ipairs({ { -4, -5 }, { 4, -5 }, { -4, 5 }, { 4, 5 }, { -4, -HL + 3 }, { 4, -HL + 3 }, { -4, HL - 3 }, { 4, HL - 3 } }) do
  set(c[1], 2, c[2], "spruce_fence"); set(c[1], 3, c[2], "lantern")
end

local green = { name = "Greenhouse", blocks = {} }
for key, block in pairs(grid) do
  local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
  green.blocks[#green.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return green
