-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Five-storey pagoda on a stepped stone plinth, 31x31 and 59 high. Each
-- storey is narrower than the one below, with a balcony and railing on the
-- roof below it, deep eaves that turn up at the corners, lanterns under the
-- corners, and a gold spire on top. Coordinates are from the centre.
local pagoda = { name = "Pagoda", blocks = {} }
local function put(x, y, z, block) pagoda.blocks[#pagoda.blocks + 1] = { x, y, z, block } end

-- the outline of a square of this radius, or all of it
local function ring(radius, y, block)
  for i = -radius, radius do
    put(i, y, -radius, block)
    put(i, y, radius, block)
    if i > -radius and i < radius then
      put(-radius, y, i, block)
      put(radius, y, i, block)
    end
  end
  if radius == 0 then put(0, y, 0, block) end
end
local function square(radius, y, block)
  for z = -radius, radius do
    for x = -radius, radius do put(x, y, z, block) end
  end
end

-- plinth, with steps up the front (north)
for y = 0, 2 do
  square(15 - y, y, "minecraft:stone_bricks")
  for x = -2, 2 do put(x, y, -16 + y, "minecraft:stone_brick_stairs") end
end

local STOREYS = {
  { radius = 12, height = 6 },
  { radius = 10, height = 5 },
  { radius = 8, height = 5 },
  { radius = 6, height = 4 },
  { radius = 4, height = 4 },
}
local EAVES = 3 -- how far each roof reaches past its walls

local y = 3
for level, storey in ipairs(STOREYS) do
  local r, h = storey.radius, storey.height
  local below = STOREYS[level - 1]

  -- floor: on the plinth, or the full width of the storey below so its
  -- edge makes a balcony with a railing
  local floor = below and below.radius or r
  square(floor, y, "minecraft:spruce_planks")
  if below then ring(floor, y + 1, "minecraft:dark_oak_fence") end

  -- walls: posts at the corners and every 4 blocks, windows between them,
  -- a dark beam along the top, and a doorway at the front
  for dy = 1, h do
    for i = -r, r do
      for _, side in ipairs({ { i, -r }, { i, r }, { -r, i }, { r, i } }) do
        local x, z = side[1], side[2]
        local along = (z == -r or z == r) and x or z
        local corner = (x == -r or x == r) and (z == -r or z == r)
        local door = z == -r and math.abs(x) <= (level == 1 and 1 or 0) and dy <= (level == 1 and 3 or 2)
        local block
        if door then
          block = nil
        elseif corner or along % 4 == 0 then
          block = "minecraft:mangrove_log"
        elseif dy == h then
          block = "minecraft:dark_oak_planks"
        elseif along % 4 == 2 and dy >= 2 and dy <= h - 2 then
          block = "minecraft:glass_pane"
        else
          block = "minecraft:birch_planks"
        end
        if block then put(x, y + dy, z, block) end
      end
    end
  end
  -- a ceiling closes the storey under its roof
  square(r - 1, y + h, "minecraft:dark_oak_planks")

  -- roof: rings stepping in from the eaves, corners turned up, lanterns
  -- hanging under the corners
  local top = y + h + 1
  local eave = r + EAVES
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    put(c[1] * eave, top + 1, c[2] * eave, "minecraft:deepslate_tile_slab")
    put(c[1] * eave, top - 1, c[2] * eave, "minecraft:lantern")
  end
  if level < #STOREYS then
    for j = 0, EAVES - 1 do
      ring(eave - j, top + j, j == 0 and "minecraft:deepslate_tile_stairs" or "minecraft:deepslate_tiles")
    end
    y = top + EAVES
  else
    -- the top roof closes to a point, with a spire on it
    for j = 0, eave do
      ring(eave - j, top + j, j == 0 and "minecraft:deepslate_tile_stairs" or "minecraft:deepslate_tiles")
    end
    local tip = top + eave
    for k = 1, 7 do
      put(0, tip + k, 0, k % 2 == 1 and "minecraft:gold_block" or "minecraft:iron_bars")
    end
    for _, c in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      put(c[1], tip + 3, c[2], "minecraft:gold_block")
    end
  end
end
return pagoda
