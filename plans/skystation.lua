-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- A space station to hang high in the sky, 63 wide and 77 high: a hollow
-- core with a glass dome and a spire on top and a spike below, and four
-- hollow rings round it, the upper three joined to the core by hollow
-- spokes. Each ring has a floor to walk round on, with a deck across the
-- core at the same height. It's built in the air, so builders don't clear
-- its box first (clear = false): raise it on the projector before Build.
local station = { name = "Sky Station", clear = false, blocks = {} }

local TAU = 2 * math.pi
local atan2 = math.atan2 or math.atan

-- bottom to top: wall, the grooves between its panels, and either a red
-- stripe round the outside or a band of windows
local RINGS = {
  { y = 17, R = 14, r = 4.5, wall = "minecraft:white_concrete", rib = "minecraft:light_gray_concrete", stripe = "minecraft:red_concrete" },
  { y = 30, R = 24, r = 4.5, wall = "minecraft:gray_concrete", rib = "minecraft:black_concrete", window = "minecraft:light_blue_stained_glass", spokes = 0 },
  { y = 43, R = 27, r = 4.5, wall = "minecraft:white_concrete", rib = "minecraft:light_gray_concrete", stripe = "minecraft:red_concrete", spokes = 45 },
  { y = 55, R = 21, r = 4, wall = "minecraft:gray_concrete", rib = "minecraft:black_concrete", window = "minecraft:light_blue_stained_glass", spokes = 0 },
}
local SPOKE = 3 -- spokes are 7 blocks square (5 inside)

-- Every cell inside the station, and which part it belongs to. Only the
-- outside layer of it gets built (plus the floors), so the whole thing is
-- one hollow space you can walk through.
local inside = {}
local function cell(x, y, z) return ((x + 64) * 256 + y) * 128 + (z + 64) end
local function fill(reach, y0, y1, part, test)
  for y = y0, y1 do
    for z = -reach, reach do
      for x = -reach, reach do
        local k = cell(x, y, z)
        if not inside[k] and test(x, y, z) then inside[k] = part end
      end
    end
  end
end

local function inRing(ring, x, y, z)
  local d = math.sqrt(x * x + z * z) - ring.R
  return d * d + (y - ring.y) ^ 2 <= ring.r * ring.r
end

-- spike below, core, the hubs round the core's ends, the dome
fill(3, 0, 9, "spike", function(x, y, z) return x * x + z * z <= (y * 0.28) ^ 2 end)
fill(7, 10, 62, "core", function(x, y, z) return x * x + z * z <= 6.5 * 6.5 end)
fill(11, 12, 22, "hub", function(x, y, z) return (x * x + z * z) / 121 + (y - 17) ^ 2 / 25 <= 1 end)
fill(10, 54, 62, "hub", function(x, y, z) return (x * x + z * z) / 100 + (y - 58) ^ 2 / 16 <= 1 end)
fill(8, 62, 70, "dome", function(x, y, z) return x * x + z * z + (y - 62) ^ 2 <= 7.5 * 7.5 end)
for _, ring in ipairs(RINGS) do
  local r = math.ceil(ring.r)
  fill(math.ceil(ring.R + ring.r), ring.y - r, ring.y + r, ring, function(x, y, z) return inRing(ring, x, y, z) end)
  if ring.spokes then
    local axes = {}
    for k = 0, 3 do
      local a = math.rad(ring.spokes + 90 * k)
      axes[#axes + 1] = { math.cos(a), math.sin(a) }
    end
    fill(ring.R, ring.y - SPOKE, ring.y + SPOKE, ring, function(x, y, z)
      for _, c in ipairs(axes) do
        local along, across = x * c[1] + z * c[2], z * c[1] - x * c[2]
        if along >= 0 and along <= ring.R and math.abs(across) <= SPOKE then return true end
      end
      return false
    end)
  end
end

-- A block one wide every so far round a circle: the grooves between panels,
-- the dome's ribs, the core's windows.
local function onRib(x, z, count)
  local a = atan2(z, x) % TAU
  return (a % (TAU / count)) * math.sqrt(x * x + z * z) < 1
end

local floorAt = {}
for _, ring in ipairs(RINGS) do floorAt[ring.y - 2] = true end

local function blockFor(part, x, y, z)
  if part == "spike" then return "minecraft:iron_block" end
  if part == "core" then return onRib(x, z, 8) and "minecraft:glass" or "minecraft:light_gray_concrete" end
  if part == "hub" then return onRib(x, z, 16) and "minecraft:light_gray_concrete" or "minecraft:white_concrete" end
  if part == "dome" then return onRib(x, z, 8) and "minecraft:white_concrete" or "minecraft:glass" end
  if not inRing(part, x, y, z) then return part.wall end -- a spoke
  local out, dy = math.sqrt(x * x + z * z) > part.R, y - part.y
  if part.stripe and out and dy == 0 then return part.stripe end
  if onRib(x, z, 32) then return part.rib end
  if part.window and out and math.abs(dy) <= 1 then return part.window end
  return part.wall
end

local function put(x, y, z, block) station.blocks[#station.blocks + 1] = { x, y, z, block } end
local NEXT = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
for k, part in pairs(inside) do
  local z = k % 128 - 64
  local y = math.floor(k / 128) % 256
  local x = math.floor(k / (128 * 256)) - 64
  local edge = false
  for _, d in ipairs(NEXT) do
    if not inside[cell(x + d[1], y + d[2], z + d[3])] then edge = true break end
  end
  if edge then
    put(x, y, z, blockFor(part, x, y, z))
  elseif floorAt[y] then
    put(x, y, z, (x % 6 == 0 and z % 6 == 0) and "minecraft:sea_lantern" or "minecraft:smooth_stone")
  end
end
inside = nil

-- the spire on the dome
for y = 70, 76 do put(0, y, 0, y % 2 == 0 and "minecraft:iron_block" or "minecraft:iron_bars") end
put(0, 77, 0, "minecraft:end_rod")
return station
