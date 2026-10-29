-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Underground atrium: the inside of the hall 'excavate atrium' digs (21x21,
-- 16 high, with a stepped pit in the middle of the floor). A spruce gallery
-- runs round the hall at the upper rooms' floor, held up by log pillars that
-- go on up to a grid of ceiling beams, with arches between them below the
-- gallery and below the beams. Split stairs climb to the gallery on every
-- side, a fence railing with lanterns runs along it, and shroomlights in the
-- beams light the hall. In the pit, flowering beds step down to a pond with
-- sugar cane round it.
--
-- Coordinates are the hall's: x and z 0-20 from its north-west corner, y 0
-- its floor (the pit and pond go below). Nothing is built above (5, 5): the
-- builder turtle's home, with its chests at (4, 5) and (5, 4), under the
-- stairs. Built inside the dug hall, so "clear" is false, and the top is 2
-- below the ceiling so the builders cross over it inside the hall. Change
-- the sizes here and excavate's ATRIUM_SIZE / PIT_* / POND_* together.
local atrium = { name = "Atrium", clear = false, blocks = {} }
local function put(x, y, z, block) atrium.blocks[#atrium.blocks + 1] = { x, y, z, block } end

local N = 20 -- far side of the hall
local C = 10 -- its middle
local LEDGE = 3 -- gallery width, as excavate's LEDGE_WIDTH
local GALLERY = 6 -- the gallery floor's layer (you stand on it at 7)
local TOP = 13 -- the ceiling beams' layer
local STEPS = GALLERY + 1 -- steps up to the gallery
local STAIR_WIDTH = 2

local LOG = "minecraft:stripped_spruce_log"
local PLANKS = "minecraft:spruce_planks"
local FENCE = "minecraft:spruce_fence"
local LIGHT = "minecraft:shroomlight"
local LANTERN = "minecraft:lantern"
local STAIRS = "minecraft:spruce_stairs"

local function ring(x, z) return math.min(x, N - x, z, N - z) end

---------------------------------------------------------------- pillars

-- On the gallery's inner edge: the corners, and between the rooms' doors.
local PILLAR_AT = { LEDGE - 1, 7, 13, N - LEDGE + 1 }
local pillar = {}
for _, a in ipairs(PILLAR_AT) do
  for _, e in ipairs({ LEDGE - 1, N - LEDGE + 1 }) do
    pillar[a .. "," .. e] = true
    pillar[e .. "," .. a] = true
  end
end
local function isPillar(x, z) return pillar[x .. "," .. z] == true end
for key in pairs(pillar) do
  local x, z = key:match("(%d+),(%d+)")
  for y = 0, TOP do put(tonumber(x), y, tonumber(z), LOG) end
end

---------------------------------------------------------------- gallery

for z = 0, N do
  for x = 0, N do
    if ring(x, z) < LEDGE and not isPillar(x, z) then put(x, GALLERY, z, PLANKS) end
  end
end

---------------------------------------------------------------- stairs

-- As excavate builds them: a landing at floor level in the middle of each
-- side, a flight rising to each end just inside the gallery, and where two
-- flights meet in a corner the lower step wins. heights["x,z"] = step k,
-- whose block is at k - 1.
local heights = {}
local function step(x, z, k)
  local key = x .. "," .. z
  if not heights[key] or k < heights[key] then heights[key] = k end
end
for i = 0, STAIR_WIDTH - 1 do
  for k = 1, STEPS do
    for _, e in ipairs({ LEDGE + i, N - LEDGE - i }) do
      step(e, C + k, k)
      step(e, C - k, k)
      step(C + k, e, k)
      step(C - k, e, k)
    end
  end
end
local function heightAt(x, z)
  if ring(x, z) < LEDGE then return STEPS end
  return heights[x .. "," .. z] or 0
end
-- each step faces up the flight, looking along the wall first; one with
-- nothing higher beside it is a landing
local SIDES = { { 0, 1, "south" }, { 1, 0, "east" }, { 0, -1, "north" }, { -1, 0, "west" } }
for key, k in pairs(heights) do
  local x, z = key:match("(%d+),(%d+)")
  x, z = tonumber(x), tonumber(z)
  local alongZ = x < LEDGE + STAIR_WIDTH or x > N - LEDGE - STAIR_WIDTH
  local block = PLANKS
  for _, d in ipairs(alongZ and { 1, 3, 2, 4 } or { 2, 4, 1, 3 }) do
    local s = SIDES[d]
    if heightAt(x + s[1], z + s[2]) == k + 1 then
      block = STAIRS .. "[facing=" .. s[3] .. "]"
      break
    end
  end
  put(x, k - 1, z, block)
end

---------------------------------------------------------------- arches, railing, beams

-- Along each side of the gallery's inner edge, between the pillars: an arch
-- under the gallery and one under the ceiling beams (a beam with a block
-- down beside each pillar), a light in the middle span, and the railing.
local EDGE = LEDGE - 1
-- f(e, at) for each of the four sides: e is its edge line, at(a, y, block)
-- puts a block a along it
local function alongEdge(f)
  for _, e in ipairs({ EDGE, N - EDGE }) do
    f(e, function(a, y, block) put(a, y, e, block) end)
    f(e, function(a, y, block) put(e, y, a, block) end)
  end
end
alongEdge(function(e, at)
  for a = EDGE + 1, N - EDGE - 1 do
    if not isPillar(a, e) then
      local nextToPillar = isPillar(a - 1, e) or isPillar(a + 1, e)
      for _, beam in ipairs({ GALLERY - 1, TOP }) do
        at(a, beam, a == C and LIGHT or PLANKS)
        if nextToPillar then at(a, beam - 1, PLANKS) end
      end
      -- railing, open where the top of a flight comes onto the gallery
      local inward = e == EDGE and e + 1 or e - 1
      if heightAt(a, inward) < STEPS - 1 then
        at(a, GALLERY + 1, FENCE)
        if a == C then at(a, GALLERY + 2, LANTERN) end
      end
    end
  end
end)

-- ceiling beams from pillar to pillar across the hall, lit where they cross
-- and in the middle
for _, a in ipairs({ 7, 13 }) do
  for b = EDGE + 1, N - EDGE - 1 do
    local lit = b == 7 or b == 13 or b == C
    put(a, TOP, b, lit and LIGHT or PLANKS)
    put(b, TOP, a, lit and LIGHT or PLANKS)
  end
end

---------------------------------------------------------------- garden

-- r = rings out from the middle. The pit's outer ring (3) is a moss bed one
-- block below the floor, the next (2) one lower again, round a pond two deep
-- whose surface is level with it, so the cane beside it grows. Moss, not
-- grass: it needs no silk touch, and everything here grows on it.
local function plantAt(r, t)
  if r == 3 then
    if math.abs(t) == 3 then return "minecraft:flowering_azalea" end
    if math.abs(t) == 2 then return "minecraft:bamboo" end
    if math.abs(t) == 1 then return "minecraft:azalea" end
    return "minecraft:poppy"
  end
  if math.abs(t) <= 1 then return "minecraft:sugar_cane" end
  return "minecraft:cornflower"
end
for dz = -3, 3 do
  for dx = -3, 3 do
    local x, z = C + dx, C + dz
    local r = math.max(math.abs(dx), math.abs(dz))
    local t = math.abs(dx) == r and dz or dx -- along the ring's side
    if r == 3 then
      put(x, -3, z, "minecraft:dirt")
      put(x, -2, z, "minecraft:moss_block")
      put(x, -1, z, plantAt(r, t))
    elseif r == 2 then
      put(x, -3, z, "minecraft:moss_block")
      put(x, -2, z, plantAt(r, t))
    else
      put(x, -4, z, "minecraft:water")
      put(x, -3, z, "minecraft:water")
    end
  end
end
-- lanterns on the floor at the pit's corners
for _, dz in ipairs({ -4, 4 }) do
  for _, dx in ipairs({ -4, 4 }) do put(C + dx, 0, C + dz, LANTERN) end
end

return atrium
