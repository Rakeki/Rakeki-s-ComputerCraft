-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Market square: a paved square with a roofed well in the middle and eight
-- market stalls round it, each under a striped canopy of its own colour
-- with its wares on the counter: pumpkins, melons, hay, books, barrels,
-- chests, flowers and honey. Paths run north-south and east-west through
-- it between benches and lamp posts, and a flowering tree stands in each
-- corner. The well holds 9 water buckets. y 0 is the ground; x and z are
-- from the well.
local R = 13 -- the square reaches this far each way from the well

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

-- a hipped roof: rings of stairs climbing to the middle, a slab on top
local function hip(cx, cz, r0, y0, stair, top)
  for k = 0, r0 do
    local r, y = r0 - k, y0 + k
    if r == 0 then set(cx, y, cz, top) break end
    for z = cz - r, cz + r do
      for x = cx - r, cx + r do
        local facing = z == cz - r and "south" or z == cz + r and "north" or x == cx - r and "east" or x == cx + r and "west"
        if facing then set(x, y, z, stair .. "[facing=" .. facing .. "]") end
      end
    end
  end
end

---------------------------------------------------------------- paving

for z = -R, R do
  for x = -R, R do
    local n = noise(x, 0, z)
    local block = n < 0.25 and "cobblestone" or n < 0.4 and "andesite" or n < 0.5 and "mossy_stone_bricks" or "stone_bricks"
    if math.abs(x) <= 1 or math.abs(z) <= 1 then block = n < 0.2 and "gravel" or "polished_andesite" end
    if math.abs(x) == R or math.abs(z) == R then block = "polished_andesite" end
    set(x, 0, z, block)
  end
end

---------------------------------------------------------------- the well

fill(-1, -1, -1, 1, -1, 1, "cobblestone")
fill(-1, 0, -1, 1, 0, 1, "water")
for z = -2, 2 do
  for x = -2, 2 do
    if math.abs(x) == 2 or math.abs(z) == 2 then set(x, 0, z, "stone_bricks"); set(x, 1, z, "stone_brick_wall") end
  end
end
for _, c in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
  set(c[1], 1, c[2], "stone_bricks"); set(c[1], 2, c[2], "spruce_fence"); set(c[1], 3, c[2], "spruce_fence")
end
hip(0, 0, 2, 4, "spruce_stairs", "spruce_slab")
set(0, 3, 0, "chain") -- the rope down to the water
set(0, 2, 0, "cauldron")

---------------------------------------------------------------- stalls

local WARES = {
  { colour = "red", goods = { "pumpkin", "pumpkin", "carved_pumpkin" } },
  { colour = "lime", goods = { "melon", "melon", "melon" } },
  { colour = "yellow", goods = { "hay_block", "hay_block", "hay_block" } },
  { colour = "blue", goods = { "bookshelf", "lectern", "bookshelf" } },
  { colour = "orange", goods = { "barrel", "barrel", "barrel" } },
  { colour = "purple", goods = { "chest", "barrel", "chest" } },
  { colour = "magenta", goods = { "flowering_azalea", "azalea", "flowering_azalea" } },
  { colour = "brown", goods = { "honey_block", "beehive", "honey_block" } },
}
-- a stall facing in towards the well: 3 wide along the side, 3 deep
local function stall(sx, sz, inward, wares)
  local ax, az = inward[2] ~= 0 and 1 or 0, inward[1] ~= 0 and 1 or 0 -- along the stall's front
  for a = -1, 1 do
    for d = -1, 1 do
      local x, z = sx + ax * a + inward[1] * d, sz + az * a + inward[2] * d
      if a ~= 0 and d ~= 0 then for y = 1, 3 do set(x, y, z, "spruce_fence") end end
      -- canopy: stripes across the front
      set(x, 4, z, (a == 0 and "white" or wares.colour) .. "_wool")
    end
    -- the counter at the front, wares on top
    local fx, fz = sx + ax * a + inward[1], sz + az * a + inward[2]
    local good = wares.goods[a + 2]
    if good:find("azalea") then set(fx, 1, fz, "moss_block") else set(fx, 1, fz, "barrel") end
    set(fx, 2, fz, good)
  end
  -- the stallholder's stool behind the counter
  set(sx, 1, sz, "spruce_stairs[facing=" .. (inward[1] > 0 and "west" or inward[1] < 0 and "east" or inward[2] > 0 and "north" or "south") .. "]")
end
local SPOTS = {
  { -5, -9, { 0, 1 } }, { 5, -9, { 0, 1 } }, { 9, -5, { -1, 0 } }, { 9, 5, { -1, 0 } },
  { 5, 9, { 0, -1 } }, { -5, 9, { 0, -1 } }, { -9, 5, { 1, 0 } }, { -9, -5, { 1, 0 } },
}
for k, s in ipairs(SPOTS) do stall(s[1], s[2], s[3], WARES[k]) end

---------------------------------------------------------------- benches, lamps, trees

-- benches facing the well beside each path, lamp posts where the paths come in
for _, s in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
  local px, pz = s[1] * 5, s[2] * 5
  local facing = s[1] > 0 and "east" or s[1] < 0 and "west" or s[2] > 0 and "south" or "north"
  for k = -1, 1, 2 do
    local x, z = px + (s[2] ~= 0 and 3 * k or 0), pz + (s[1] ~= 0 and 3 * k or 0)
    set(x, 1, z, "spruce_stairs[facing=" .. facing .. "]")
    set(x + (s[2] ~= 0 and k or 0), 1, z + (s[1] ~= 0 and k or 0), "spruce_stairs[facing=" .. facing .. "]")
  end
  for k = -1, 1, 2 do
    local x, z = s[1] * (R - 1) + (s[2] ~= 0 and 2 * k or 0), s[2] * (R - 1) + (s[1] ~= 0 and 2 * k or 0)
    set(x, 1, z, "stone_brick_wall"); set(x, 2, z, "dark_oak_fence"); set(x, 3, z, "dark_oak_fence"); set(x, 4, z, "lantern")
  end
end
for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
  local tx, tz = c[1] * (R - 3), c[2] * (R - 3)
  for z = tz - 1, tz + 1 do for x = tx - 1, tx + 1 do set(x, 0, z, "moss_block") end end
  for y = 1, 4 do set(tx, y, tz, "dark_oak_log") end
  for y = 4, 7 do
    local r = (y == 4 or y == 7) and 1 or 2
    for z = tz - r, tz + r do
      for x = tx - r, tx + r do
        local corner = math.abs(x - tx) == r and math.abs(z - tz) == r and r == 2
        if not corner and not (x == tx and z == tz and y < 6) then
          set(x, y, z, noise(x, y, z) < 0.35 and "flowering_azalea_leaves" or "azalea_leaves")
        end
      end
    end
  end
  set(tx + c[1], 1, tz, "poppy"); set(tx, 1, tz + c[2], "cornflower"); set(tx - c[1], 1, tz, "dandelion")
end

local market = { name = "Market square", blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  market.blocks[#market.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return market
