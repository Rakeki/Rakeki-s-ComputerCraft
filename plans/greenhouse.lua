-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Greenhouse: a tall glasshouse under a barrel-vaulted glass roof. The
-- glass sits back behind its frame: oak ribs every fourth row stand out
-- over the vault, and posts stand out from the side walls on stone feet.
-- Both ends are a timber-framed front three layers deep: glass at the
-- back, then oak posts, spruce bands and arched window surrounds, then
-- the main posts again on stone plinths with ledges, a thick oak rim with
-- spruce trim, spires on top. Planters and lamp posts outside. Inside is
-- an empty stone floor, left for you to fill. Wood, stone and glass mix a
-- few kinds of each for texture. y 0 is the ground; x runs east, z south;
-- x and z are from the middle.
local HW, HL = 12, 16 -- the walls at x -HW..HW, the fronts' glass at z -HL and HL
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
local function has(list, v)
  for _, w in ipairs(list) do if w == v then return true end end
  return false
end
-- A block from a mix, picked by the cell: { { block, share }, ... }, shares adding up to 1.
local function pick(mix, x, y, z)
  local n, sum = noise(x, y, z), 0
  for _, m in ipairs(mix) do
    sum = sum + m[2]
    if n < sum then return m[1] end
  end
  return mix[#mix][1]
end
local OAK = { { "oak_planks", 0.55 }, { "stripped_oak_wood", 0.25 }, { "stripped_oak_log", 0.12 }, { "spruce_planks", 0.08 } }
local SPRUCE = { { "spruce_planks", 0.6 }, { "stripped_spruce_wood", 0.32 }, { "dark_oak_planks", 0.08 } }
local STONE = { { "stone_bricks", 0.5 }, { "mossy_stone_bricks", 0.2 }, { "cracked_stone_bricks", 0.15 }, { "andesite", 0.08 }, { "cobblestone", 0.07 } }
local GLASS = { { "glass", 0.9 }, { "light_blue_stained_glass", 0.1 } }
local FLOOR = { { "polished_andesite", 0.6 }, { "stone_bricks", 0.2 }, { "andesite", 0.1 }, { "mossy_stone_bricks", 0.1 } }
local function oak(x, y, z) return pick(OAK, x, y, z) end
local function spruce(x, y, z) return pick(SPRUCE, x, y, z) end
local function stone(x, y, z) return pick(STONE, x, y, z) end
local function glass(x, y, z) return pick(GLASS, x, y, z) end

-- the vault's cross-section (x, y): straight walls up to SPRING, then a half ellipse
local function inProfile(x, y)
  if y < 1 then return false end
  if y < SPRING then return math.abs(x) <= HW end
  return (x / RX) ^ 2 + ((y - SPRING) / RY) ^ 2 <= 1
end
local function shell(x, y)
  return inProfile(x, y) and not (inProfile(x - 1, y) and inProfile(x + 1, y) and inProfile(x, y + 1))
end
-- the cells just outside the shell: where ribs and rims stand out
local function rim(x, y)
  return y >= 1 and not inProfile(x, y) and (inProfile(x - 1, y) or inProfile(x + 1, y) or inProfile(x, y - 1))
end
local TOP = SPRING + RY
local function topAt(x)
  for y = TOP + 1, 1, -1 do if inProfile(x, y) or rim(x, y) then return y end end
end
local function isPost(x, y) return has(POSTS, x) or (x == 0 and y > BANDS[2]) end

---------------------------------------------------------------- floor and vault

for z = -HL, HL do
  for x = -HW, HW do set(x, 0, z, stone(x, 0, z)) end
end
for z = -HL + 1, HL - 1 do
  local rib = z % 4 == 0
  for y = 1, TOP + 1 do
    for x = -HW - 1, HW + 1 do
      if shell(x, y) then
        local block
        if y < SPRING then -- the straight side walls
          if y == 1 then block = stone(x, y, z)
          elseif rib then block = "stripped_oak_log"
          elseif y == BANDS[1] then block = spruce(x, y, z)
          else block = glass(x, y, z) end
        elseif rib then block = oak(x, y, z)
        elseif x % 4 == 0 then block = spruce(x, y, z)
        else block = glass(x, y, z) end
        set(x, y, z, block)
      elseif rim(x, y) then
        -- ribs stand out from the glass: posts on stone feet up the walls, oak caps over the vault
        if rib then
          if y < SPRING then
            local feet = { "chiseled_stone_bricks", stone(x, 2, z), "polished_andesite" }
            set(x, y, z, feet[y] or "stripped_oak_log")
            if y == 1 then set(x, 0, z, stone(x, 0, z)) end
          else set(x, y, z, oak(x, y, z)) end
        elseif y == 1 then set(x, y, z, noise(x, y, z) < 0.3 and "mossy_stone_brick_slab" or "stone_brick_slab")
        elseif y == BANDS[1] then set(x, y, z, "spruce_slab") end
      end
    end
  end
  if rib then set(0, TOP + 2, z, "spruce_fence"); set(0, TOP + 3, z, "lightning_rod") end
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
-- an arched window's corners, filled in over the glass
local function archCorner(x, y)
  local x0, x1, y1 = bay(x, y)
  local wide = x1 - x0 + 1
  return wide >= 3 and y1 < TOP and (
    (y == y1 and (x == x0 or x == x1)) or
    (wide >= 5 and y == y1 and (x == x0 + 1 or x == x1 - 1)) or
    (wide >= 5 and y == y1 - 1 and (x == x0 or x == x1)))
end

local function front(z, s) -- s: -1 for the north front, 1 for the south one
  local l1, l2, l3 = z + s, z + 2 * s, z + 3 * s
  for y = 1, TOP + 1 do
    for x = -HW - 1, HW + 1 do
      local inside, edge = inProfile(x, y), shell(x, y)
      local post = isPost(x, y) and not (edge and y >= SPRING)
      if inside then
        -- the back layer: glass between the posts and bands
        local block
        if post then block = "stripped_oak_log"
        elseif edge then block = oak(x, y, z)
        elseif has(BANDS, y) then block = spruce(x, y, z)
        elseif y == 1 then block = stone(x, y, z)
        else block = glass(x, y, z) end
        set(x, y, z, block)
        -- the frame in front of it: posts, bands, the windows' arches and the rim
        if post then
          local plinth = { "chiseled_stone_bricks", stone(x, 2, l1), "polished_andesite" }
          set(x, y, l1, (y <= 3 and x ~= 0) and plinth[y] or "stripped_oak_log")
        elseif edge and y >= SPRING then set(x, y, l1, oak(x, y, l1))
        elseif has(BANDS, y) then set(x, y, l1, spruce(x, y, l1))
        elseif y == 1 and math.abs(x) > 1 then set(x, y, l1, noise(x, y, l1) < 0.3 and "mossy_stone_brick_slab" or "stone_brick_slab")
        elseif archCorner(x, y) then set(x, y, l1, oak(x, y, l1)) end
        -- the front layer: the main posts again, ledges under the bands
        if has(POSTS, x) and y <= (math.abs(x) == 3 and BANDS[3] or math.abs(x) == 8 and BANDS[2] or SPRING) then
          local plinth = { stone(x, 1, l2), "chiseled_stone_bricks", "polished_andesite" }
          set(x, y, l2, y <= 3 and plinth[y] or "stripped_oak_log")
        elseif has(BANDS, y) and not post then set(x, y, l2, "spruce_slab") end
      end
      -- a thick oak rim round the vault's edge, spruce trim in front of it
      if rim(x, y) and y >= SPRING then
        set(x, y, z, oak(x, y, z)); set(x, y, l1, oak(x, y, l1))
      end
      if edge and y >= SPRING then set(x, y, l2, spruce(x, y, l2)) end
    end
  end
  -- caps on the main posts where they stop
  for _, x in ipairs(POSTS) do
    local y = (math.abs(x) == 3 and BANDS[3] or math.abs(x) == 8 and BANDS[2] or SPRING) + 1
    if not get(x, y, l2) then set(x, y, l2, "spruce_slab") end
  end
  -- the doorway, set back in its arch, with a lamp post either side
  set(0, 1, z, "spruce_door[facing=" .. (s < 0 and "north" or "south") .. "]"); set(0, 2, z, nil)
  for _, x in ipairs({ -2, 2 }) do
    for y = 1, 3 do set(x, y, l2, "spruce_fence") end
    set(x, 4, l2, "lantern")
  end
  -- spires on the posts, the middle one tallest
  for _, x in ipairs({ -12, -8, -3, 0, 3, 8, 12 }) do
    local top, n = topAt(x), x == 0 and 3 or 2
    for i = 1, n do set(x, top + i, l1, "spruce_fence") end
    set(x, top + n + 1, l1, "lightning_rod")
  end
  -- stone blocks in front of the plinths, planters between them, a gravel path
  for x = -HW, HW do
    if has(POSTS, x) then
      set(x, 0, l3, "chiseled_stone_bricks"); set(x, 1, l3, stone(x, 1, l3))
      set(x, 2, l3, math.abs(x) == 3 and "stone_brick_wall" or noise(x, 2, l3) < 0.4 and "mossy_stone_brick_slab" or "stone_brick_slab")
      if math.abs(x) == 3 then set(x, 3, l3, "lantern") end
    elseif math.abs(x) >= 2 then
      for _, l in ipairs({ l2, l3 }) do
        if not get(x, 1, l) then
          set(x, 0, l, "moss_block")
          local bamboo = l == l3 and (math.abs(x) == 10 or math.abs(x) == 11)
          local n = noise(x, 1, l)
          set(x, 1, l, bamboo and "bamboo" or n < 0.15 and "flowering_azalea" or n < 0.22 and "fern" or FLOWERS[math.floor(noise(x, 2, l) * #FLOWERS) + 1])
          if bamboo then for y = 2, math.abs(x) == 10 and 5 or 3 do set(x, y, l, "bamboo") end end
        end
      end
    end
  end
  for d = 1, 6 do
    for x = -1, 1 do
      local n = noise(x, 0, z + s * d)
      if d > 1 or x == 0 then set(x, 0, z + s * d, n < 0.4 and "gravel" or n < 0.7 and "coarse_dirt" or n < 0.85 and "cobblestone" or "mossy_cobblestone") end
    end
  end
end
front(-HL, -1)
front(HL, 1)

---------------------------------------------------------------- the floor inside

-- left empty for whatever you grow in it
for z = -HL + 1, HL - 1 do
  for x = -HW + 1, HW - 1 do set(x, 0, z, pick(FLOOR, x, 0, z)) end
end

local green = { name = "Greenhouse", blocks = {} }
for key, block in pairs(grid) do
  local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
  green.blocks[#green.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return green
