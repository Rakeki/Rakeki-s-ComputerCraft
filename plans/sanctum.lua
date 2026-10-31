-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Sanctum: a deepslate hall for the 41x41x26 hole 'excavate sanctum' digs.
-- At its north end, a pool round an island of crying obsidian, where an
-- amethyst tree rises on a trunk and four branches to a crown studded with
-- clusters and lit from inside by froglights. Two waterfalls pour from
-- spouts in the north wall into the pool. Two deepslate brick towers flank
-- it, banded with oxidized copper, with soul lanterns on every band, green
-- glowing windows, sea lanterns at their feet and stepped roofs. A mud
-- brick path edged with moss leads from the south wall to the pool between
-- soul lantern posts; the walls have polished deepslate pilasters with
-- copper bands, and moss creeps over the floor near them.
--
-- Coordinates are the hole's: x and z from its north-west corner, y 0 its
-- floor. hole is the size to dig; home is the builder turtle's spot
-- (facing south, chests behind and to its left), which the plan keeps
-- clear. The top layer is one below the ceiling: the builder stands a
-- block above what it places. Built inside the dug hole, so "clear" is false.
local W, L, H = 41, 41, 26
local TOP = H - 2
local HOME = { x = 20, z = 37 }
local sanctum = { name = "Sanctum", clear = false, hole = { W, L, H }, home = HOME, blocks = {} }

local CX = 20 -- the hall's middle (x)
local POOL = { x = 20, z = 9, rx = 9, rz = 8 } -- an ellipse
local CROWN = { y = 16, r = 5 } -- the tree's crown, round the trunk
local FALLS = { 16, 24 } -- waterfall x's, from spouts in the north wall
local FALL_Y = 16
local TOWERS = { { x = 8, z = 19 }, { x = 32, z = 19 } } -- 7x7 each
local BANDS = { [6] = true, [12] = true, [18] = true } -- copper bands round the towers
local PATH = { x0 = 18, x1 = 22 } -- from the pool to the south wall

local COPPER = "minecraft:oxidized_cut_copper"
local SOUL = "minecraft:soul_lantern"
local GLOW = "minecraft:verdant_froglight"

local grid = {}
local function set(x, y, z, block) grid[x .. "," .. y .. "," .. z] = block end
local function get(x, y, z) return grid[x .. "," .. y .. "," .. z] end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function bricks(x, y, z)
  local n = noise(x, y, z)
  return n < 0.15 and "minecraft:cracked_deepslate_bricks" or n < 0.25 and "minecraft:deepslate_tiles"
    or "minecraft:deepslate_bricks"
end
local function inPool(x, z)
  local dx, dz = (x - POOL.x) / POOL.rx, (z - POOL.z) / POOL.rz
  return z >= 1 and dx * dx + dz * dz <= 1
end

---------------------------------------------------------------- shell

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      if x == 0 or z == 0 or x == W - 1 or z == L - 1 then
        set(x, y, z, bricks(x, y, z))
      elseif y == 0 then
        local n = noise(x, y, z)
        set(x, y, z, n < 0.5 and "minecraft:deepslate_tiles" or n < 0.75 and "minecraft:cobbled_deepslate"
          or "minecraft:polished_deepslate")
      end
    end
  end
end

-- pilasters against the walls, banded with copper; none where the falls are
for _, a in ipairs({ 6, 12, 28, 34 }) do
  for y = 1, TOP do
    local block = (y == 8 or y == 16) and COPPER or "minecraft:polished_deepslate"
    set(a, y, 1, block)
    set(a, y, L - 2, block)
    set(1, y, a, block)
    set(W - 2, y, a, block)
  end
end

---------------------------------------------------------------- pool, island and falls

for z = 1, L - 2 do
  for x = 1, W - 2 do
    if inPool(x, z) then
      set(x, 0, z, "minecraft:water")
    else
      -- a low wall round the pool, open to the path, soul lanterns on it
      local rim = inPool(x - 1, z) or inPool(x + 1, z) or inPool(x, z - 1) or inPool(x, z + 1)
      if rim and not (x >= PATH.x0 and x <= PATH.x1 and z > POOL.z) then
        set(x, 1, z, "minecraft:deepslate_brick_wall")
        if (x + z) % 5 == 0 then set(x, 2, z, SOUL) end
      end
    end
  end
end
for z = POOL.z - 1, POOL.z + 1 do
  for x = POOL.x - 1, POOL.x + 1 do set(x, 0, z, "minecraft:crying_obsidian") end
end

-- each fall: a source in a notch of the north wall, flowing out over the
-- block below it and dropping straight into the pool
for _, x in ipairs(FALLS) do
  set(x - 1, FALL_Y, 1, bricks(x - 1, FALL_Y, 1))
  set(x + 1, FALL_Y, 1, bricks(x + 1, FALL_Y, 1))
  set(x, FALL_Y - 1, 1, COPPER)
  set(x, FALL_Y, 1, "minecraft:water")
end

---------------------------------------------------------------- the amethyst tree

local AM = "minecraft:amethyst_block"
for y = 1, CROWN.y - 2 do set(POOL.x, y, POOL.z, AM) end
for z = POOL.z - 1, POOL.z + 1 do
  for x = POOL.x - 1, POOL.x + 1 do
    if (x == POOL.x or z == POOL.z) then set(x, 1, z, AM) end
  end
end
-- four branches climbing out into the crown
for k = 1, 3 do
  local y = CROWN.y - 5 + k
  set(POOL.x + k, y, POOL.z, AM)
  set(POOL.x - k, y, POOL.z, AM)
  set(POOL.x, y, POOL.z + k, AM)
  set(POOL.x, y, POOL.z - k, AM)
end
-- the crown: a ragged shell, lit from inside, clusters on top
local crown = {}
for dy = -CROWN.r, CROWN.r do
  for dz = -CROWN.r, CROWN.r do
    for dx = -CROWN.r, CROWN.r do
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      local x, y, z = POOL.x + dx, CROWN.y + dy, POOL.z + dz
      if d <= CROWN.r + 0.2 and d > CROWN.r - 1.3 and noise(x, y, z) > 0.2 and y <= TOP then
        set(x, y, z, noise(z, x, y) < 0.08 and "minecraft:pearlescent_froglight" or AM)
        crown[#crown + 1] = { x, y, z }
      end
    end
  end
end
for _, c in ipairs(crown) do
  local x, y, z = c[1], c[2], c[3]
  if y + 1 <= TOP and y > CROWN.y and get(x, y + 1, z) == nil and noise(y, z, x) < 0.45 then
    set(x, y + 1, z, "minecraft:amethyst_cluster")
  end
end

---------------------------------------------------------------- towers

for _, t in ipairs(TOWERS) do
  for dz = -4, 4 do
    for dx = -4, 4 do
      local x, z = t.x + dx, t.z + dz
      local ring = math.max(math.abs(dx), math.abs(dz))
      local face = (dx == 0 or dz == 0)
      for y = 1, 19 do
        if ring == 3 then
          set(x, y, z, face and (y == 4 or y == 10 or y == 16) and GLOW or bricks(x, y, z))
        elseif ring == 4 and BANDS[y] then
          set(x, y, z, COPPER)
          if math.abs(dx) == 4 and math.abs(dz) == 4 then set(x, y + 1, z, SOUL) end
        end
      end
      -- feet: copper steps leaning on the tower, sea lanterns at the corners
      if ring == 4 then
        if math.abs(dx) == 4 and math.abs(dz) == 4 then
          set(x, 1, z, "minecraft:sea_lantern")
        else
          local facing = dx == -4 and "east" or dx == 4 and "west" or dz == -4 and "south" or "north"
          set(x, 1, z, "minecraft:oxidized_cut_copper_stairs[facing=" .. facing .. "]")
        end
      end
      -- stepped roof
      if ring <= 4 then
        set(x, 20, z, ring == 4 and COPPER or "minecraft:deepslate_tiles")
      end
      if ring <= 2 then set(x, 21, z, "minecraft:deepslate_tiles") end
      if ring <= 1 then set(x, 22, z, "minecraft:deepslate_tiles") end
    end
  end
  set(t.x, 23, t.z, GLOW)
  set(t.x, 24, t.z, SOUL)
end

---------------------------------------------------------------- path and lanterns

for z = POOL.z + POOL.rz, L - 2 do
  for x = PATH.x0 - 1, PATH.x1 + 1 do
    if not inPool(x, z) then
      if x < PATH.x0 or x > PATH.x1 then
        if noise(x, 0, z) < 0.75 then set(x, 0, z, "minecraft:moss_block") end
      else
        set(x, 0, z, "minecraft:mud_bricks")
      end
    end
  end
end
for z = 21, 36, 5 do
  for _, x in ipairs({ PATH.x0 - 2, PATH.x1 + 2 }) do
    set(x, 1, z, "minecraft:deepslate_brick_wall")
    set(x, 2, z, "minecraft:deepslate_brick_wall")
    set(x, 3, z, SOUL)
  end
end

-- moss creeping over the floor near the walls
for z = 2, L - 3 do
  for x = 2, W - 3 do
    local wallDist = math.min(x, z, W - 1 - x, L - 1 - z)
    local open = get(x, 1, z) == nil and not inPool(x, z) and not (x >= PATH.x0 - 1 and x <= PATH.x1 + 1)
    if wallDist <= 3 and open and noise(x, 1, z) < 0.25 - wallDist * 0.05 then
      set(x, 1, z, "minecraft:moss_carpet")
    end
  end
end

---------------------------------------------------------------- out

-- the builder's home column, and the floor under its two chests, stay empty
for y = 0, TOP do set(HOME.x, y, HOME.z, nil) end
set(HOME.x, 0, HOME.z - 1, nil)
set(HOME.x + 1, 0, HOME.z, nil)

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local block = grid[x .. "," .. y .. "," .. z]
      if block then sanctum.blocks[#sanctum.blocks + 1] = { x, y, z, block } end
    end
  end
end
return sanctum
