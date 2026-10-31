-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Fortress: a Nether-style grand hall for the 27x61x15 hole 'excavate
-- fortress' digs. Polished blackstone walls with an alcove in every bay for
-- an armour-stand guard, soul lanterns either side and a glowing panel of
-- shroomlight and magma above. A lava channel runs the length of both walls
-- under an iron-bar grate. Deepslate brick pillars carry pointed ribs
-- across the hall, and lava glows through grates in the ceiling between
-- them. A red nether brick runner leads from the gate in the south wall to
-- a dais at the north end: an unlit portal frame of obsidian and crying
-- obsidian between two lavafalls behind bars, with soul fire braziers.
--
-- Mirror-symmetric east-west: the west half is drawn and mirrored (facings
-- too). Coordinates are the hole's: x and z from its north-west corner, y 0
-- its floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 27, 61, 15
local TOP = H - 2
local HOME = { x = 13, z = 56 }
local fortress = { name = "Fortress", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local N = W - 1 -- the east side (x mirrors to N - x)
local C = 13 -- the middle (x)
local PILLARS = { 6, 14, 22, 30, 38, 46, 54 } -- pillar z's; a bay between each pair
local LAVA = "minecraft:lava" -- or "minecraft:magma_block": the plan takes about 150 lava buckets
local CHANNEL = 2 -- the lava channel's x, under a grate (and N - 2)
local PILLAR_X = { 3, 4 } -- each pillar is 2 deep and 3 wide
local CAP = 9 -- the pillars' capital layer; ribs rise from it
local DECK = TOP -- the ceiling
local DAIS = 5 -- the dais runs from the north wall to here (z)

local BRICKS = "minecraft:polished_blackstone_bricks"
local CRACKED = "minecraft:cracked_polished_blackstone_bricks"
local DEEP = "minecraft:deepslate_bricks"
local TILES = "minecraft:deepslate_tiles"
local CHISELED = "minecraft:chiseled_polished_blackstone"

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
local function get(x, y, z) return grid[x .. "," .. y .. "," .. z] end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
-- a block on the west side and its mirror on the east, facings flipped
local FLIP = { east = "west", west = "east" }
local function sym(x, y, z, block)
  set(x, y, z, block)
  set(N - x, y, z, block and (block:gsub("facing=(%a+)", function(f) return "facing=" .. (FLIP[f] or f) end)))
end
local function bricks(x, y, z)
  local n = noise(x, y, z)
  return n < 0.12 and CRACKED or n < 0.2 and "minecraft:blackstone" or BRICKS
end

local isPillar = {}
for _, p in ipairs(PILLARS) do
  for z = p - 1, p + 1 do isPillar[z] = p end
end
-- the alcove in each bay: the middle three blocks between two pillars
local function inAlcove(z)
  for i = 1, #PILLARS - 1 do
    local mid = (PILLARS[i] + PILLARS[i + 1]) / 2
    if math.abs(z - mid) <= 1 then return mid end
  end
end

---------------------------------------------------------------- shell, walls and floor

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      if x == 0 or z == 0 or x == N or z == L - 1 then set(x, y, z, bricks(x, y, z)) end
    end
  end
end

for z = 1, L - 2 do
  local mid = inAlcove(z)
  for x = 1, C do
    -- the floor: deepslate tiles, a border of polished blackstone, the runner up the middle
    local floor
    if x == CHANNEL then floor = LAVA
    elseif x <= 4 then floor = BRICKS
    elseif x >= C - 2 then floor = (x == C - 2) and "minecraft:nether_bricks" or "minecraft:red_nether_bricks"
    elseif x == 5 or isPillar[z] then floor = "minecraft:polished_blackstone"
    else floor = noise(x, 0, z) < 0.1 and "minecraft:cracked_deepslate_tiles" or TILES end
    sym(x, 0, z, floor)
  end
  -- the grate over the channel
  sym(CHANNEL, 1, z, "minecraft:iron_bars")
  -- the inner wall, full height, with an alcove and a glowing panel in each bay
  for y = 1, DECK do
    local block = bricks(1, y, z)
    if mid then
      if y <= 4 then block = nil
      elseif y == 5 then block = CHISELED
      elseif y == 7 or y == 8 then block = z == mid and "minecraft:shroomlight" or "minecraft:magma_block"
      elseif y == 6 or y == 9 then block = "minecraft:polished_blackstone" end
    end
    sym(1, y, z, block)
  end
  if mid then
    if z == mid then
      sym(1, 0, z, "minecraft:gilded_blackstone") -- the guard stands here
    else
      sym(1, 1, z, "minecraft:soul_lantern")
    end
  end
end

---------------------------------------------------------------- pillars and ribs

-- Each rib rises from the capital towards the middle: the height of its
-- underside at a given x, a pointed arch peaking a block below the deck.
local function ribY(x)
  local d = C - x -- 0 in the middle
  if d >= 7 then return CAP + 1 elseif d >= 5 then return CAP + 2 else return DECK - 1 end
end

for _, p in ipairs(PILLARS) do
  for z = p - 1, p + 1 do
    for _, x in ipairs(PILLAR_X) do
      for y = 1, DECK - 1 do
        local block = DEEP
        if y == 1 or y == CAP then block = CHISELED
        elseif y == 2 then block = "minecraft:polished_blackstone" end
        if y > CAP then block = BRICKS end
        sym(x, y, z, block)
      end
    end
  end
  -- the rib, two thick on the pillar's middle row
  for x = PILLAR_X[2] + 1, C do
    local y0 = ribY(x)
    for y = y0, DECK - 1 do sym(x, y, p, (y == y0 and x == C) and "minecraft:shroomlight" or BRICKS) end
  end
  -- a soul lantern on a post in front of the pillar
  sym(5, 1, p, "minecraft:polished_blackstone_wall")
  sym(5, 2, p, "minecraft:soul_lantern")
end

---------------------------------------------------------------- the ceiling and its lava

-- The deck over the whole hall; in each bay a pool of lava in it over a
-- grate of iron bars, with a solid ring under the deck round each pool so a
-- spill while it's being built has somewhere to sit.
for z = 1, L - 2 do
  for x = 1, C do
    if not get(x, DECK, z) then sym(x, DECK, z, noise(x, DECK, z) < 0.15 and "minecraft:cracked_deepslate_tiles" or TILES) end
  end
end
for i = 1, #PILLARS - 1 do
  local z0, z1 = PILLARS[i] + 2, PILLARS[i + 1] - 2
  for z = z0 - 1, z1 + 1 do
    for x = C - 1, C do
      local edge = z < z0 or z > z1 or x == C - 1
      sym(x, DECK - 1, z, edge and BRICKS or "minecraft:iron_bars")
      if not edge then sym(x, DECK, z, LAVA) end
    end
  end
end

---------------------------------------------------------------- the dais and the portal

-- two steps up across the north end
for z = 1, DAIS do
  for x = 3, C do
    sym(x, 1, z, (z == DAIS) and "minecraft:polished_blackstone_brick_stairs[facing=north]" or BRICKS)
    if z < DAIS then sym(x, 2, z, (z == DAIS - 1) and "minecraft:polished_blackstone_brick_stairs[facing=north]" or TILES) end
  end
end
-- the portal frame against the north wall, 4 wide inside; light it yourself
for x = C - 2, C + 2 do
  for y = 3, 8 do
    if x == C - 2 or x == C + 2 or y == 3 or y == 8 then
      set(x, y, 1, (y == 3 or y == 8) and (x == C - 2 or x == C + 2) and "minecraft:crying_obsidian" or "minecraft:obsidian")
    else
      set(x, y, 1, nil)
    end
  end
end
-- lavafalls either side, in niches behind bars: a source at the top pours
-- down onto the hole's bare floor, and the niche holds the spread
local FALL_X = C - 5
for y = 0, DECK - 1 do
  for _, x in ipairs({ FALL_X - 1, FALL_X + 1 }) do sym(x, y, 1, DEEP) end
  sym(FALL_X, y, 1, nil)
  sym(FALL_X, y, 2, y == 0 and DEEP or "minecraft:iron_bars")
end
sym(FALL_X, DECK - 1, 1, LAVA)
-- braziers on the dais
for _, x in ipairs({ C - 4, C - 7 }) do
  sym(x, 3, 3, "minecraft:polished_blackstone_wall")
  sym(x, 4, 3, "minecraft:soul_campfire")
end

---------------------------------------------------------------- the gate

-- an arch in the south wall, 5 wide and 6 high, opening on the rock; dig
-- your tunnel in from there. Banners of crying obsidian and lanterns.
for x = C - 2, C + 2 do
  for y = 1, 6 do set(x, y, L - 1, nil) end
  set(x, 7, L - 1, CHISELED)
end
for y = 1, 7 do
  sym(C - 3, y, L - 1, "minecraft:polished_blackstone")
  sym(C - 3, y, L - 2, y <= 6 and DEEP or CHISELED)
end
sym(C - 4, 1, L - 2, "minecraft:polished_blackstone_wall")
sym(C - 4, 2, L - 2, "minecraft:soul_lantern")

---------------------------------------------------------------- out

-- the builder's home column, and the floor under its two chests, stay empty
for y = 0, TOP do set(HOME.x, y, HOME.z, nil) end
set(HOME.x, 0, HOME.z - 1, nil)
set(HOME.x + 1, 0, HOME.z, nil)

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = grid[x .. "," .. y .. "," .. z]
      if block then fortress.blocks[#fortress.blocks + 1] = { x, y, z, block } end
    end
  end
end
return fortress
