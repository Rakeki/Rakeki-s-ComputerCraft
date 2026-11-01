-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Mossy platform: a raised square of moss to build on. Its sides are old
-- stonework, stone and mossy stone bricks mixed with cobblestone and mossy
-- cobblestone: big blocks two high stand two out from the wall in rows,
-- with a sunken band between the rows and gaps between the blocks, each row
-- staggered from the one above like brickwork. Solid piers at the corners.
-- Seen from the side, top to bottom:
--
--   B~~~~   B: the rim, two wide, then the moss
--   WW#     W: a solid course under the rim
--   BB#     a row of blocks, two high (or a gap between two of them)
--   BB#
--   ..#     a sunken band, then the next row of blocks...
--
-- Packed with dirt underneath. y 0 is the ground; x runs east, z south.
--
-- Any size: 'set platform.size 31x25' (wide x long) or '31x25x7' (and how
-- high, moss included), or one number for a square; the size is the whole
-- footprint, blocks included. The blocks are fitted to each side so every
-- row ends cleanly. Without the setting (and on the website) it's 21x21,
-- 5 high.
local DEFAULT_W, DEFAULT_L, DEFAULT_H = 21, 21, 5
local MIN_SIDE, MAX_SIDE = 9, 128 -- how small and big a side can be
local MIN_H, MAX_H = 2, 32 -- how low and high it can be
local DEPTH = 2 -- how far the blocks stand out from the wall behind them
local PANEL, GAP = 4, 1 -- the blocks: at least how long, and the gap between them
local ROW, BAND = 2, 1 -- how high a row of blocks is, and the sunken band under it

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, math.floor(n))) end
local function size()
  local text = type(settings) == "table" and settings.get("platform.size") or nil
  local nums = {}
  for n in tostring(text or ""):gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
  local w = nums[1] or DEFAULT_W
  local l = nums[2] or w
  local h = nums[3] or DEFAULT_H
  return clamp(w, MIN_SIDE, MAX_SIDE), clamp(l, MIN_SIDE, MAX_SIDE), clamp(h, MIN_H, MAX_H)
end
local W, L, H = size() -- the platform on x 0..W-1, z 0..L-1, y 0..H-1
local TOP = H - 1 -- the moss layer and the rim

local grid = {}
local function set(x, y, z, block)
  grid[x .. "," .. y .. "," .. z] = block and (block:find(":", 1, true) and block or "minecraft:" .. block) or nil
end
-- 0 <= noise < 1, the same every time for a cell: for mixing blocks
local function noise(x, y, z)
  local h = (x * 374761 + y * 668265 + z * 1274126) % 2147483
  return (h * h + h * 7919) % 1000 / 1000
end
local function stone(x, y, z)
  local n = noise(x, y, z)
  return n < 0.3 and "stone_bricks" or n < 0.55 and "mossy_stone_bricks" or n < 0.75 and "cobblestone"
    or n < 0.95 and "mossy_cobblestone" or "cracked_stone_bricks"
end

---------------------------------------------------------------- fitting the blocks

-- The blocks of one side, cells 1..n between its corner piers, as two rows
-- of { from, to } that lap like brickwork. The long row is as many blocks
-- as fit at PANEL long or more, stretched so they fill the side exactly; the
-- other row's gaps fall in the middle of its blocks, and a stub too short
-- at either end joins its neighbour (on a tiny side, one gap in the middle).
local function fit(n)
  local k = math.max(1, math.floor((n + GAP) / (PANEL + GAP)))
  local room = n - (k - 1) * GAP
  -- the extra cells go to the blocks nearest the middle, in mirrored pairs,
  -- so the side reads the same from both ends; an odd one left over goes to
  -- the middle block, or widens the middle gap when there's none
  local lens, gaps, rem = {}, {}, room % k
  for j = 1, k do lens[j], gaps[j] = math.floor(room / k), GAP end
  local lo, hi = math.floor((k + 1) / 2), math.floor(k / 2) + 1
  if rem % 2 == 1 then
    if lo == hi then lens[lo] = lens[lo] + 1 else gaps[lo] = gaps[lo] + 1 end
    rem = rem - 1
  end
  if lo == hi then lo, hi = lo - 1, hi + 1 end
  while rem > 0 do
    lens[lo], lens[hi] = lens[lo] + 1, lens[hi] + 1
    lo, hi, rem = lo - 1, hi + 1, rem - 2
  end
  local long, mids, at = {}, {}, 1
  for j = 1, k do
    long[j] = { at, at + lens[j] - 1 }
    -- an even block's middle leans away from the side's middle, mirrored; one
    -- right on the side's middle gets a double gap. Whole numbers, or 5.0
    -- would end up in the block key
    local c = at + (lens[j] - 1) / 2
    if c % 1 == 0 then mids[#mids + 1] = math.floor(c)
    elseif c * 2 == n + 1 then mids[#mids + 1] = math.floor(c); mids[#mids + 1] = math.ceil(c)
    else mids[#mids + 1] = c < (n + 1) / 2 and math.floor(c) or math.ceil(c) end
    at = at + lens[j] + gaps[j]
  end
  local cuts = {}
  for _, m in ipairs(mids) do
    if m > 2 and m < n - 1 then cuts[#cuts + 1] = m end
  end
  if #cuts == 0 and n >= 5 then cuts = { math.floor((n + 1) / 2), math.ceil((n + 1) / 2) } end
  local short, from = {}, 1
  for _, c in ipairs(cuts) do
    if c > from then short[#short + 1] = { from, c - 1 } end
    from = c + 1
  end
  if from <= n then short[#short + 1] = { from, n } end
  return long, short
end

-- which cells of a side 1..n hold a block, for the long and the short row
local function cells(n)
  local long, short = fit(n)
  local function mark(runs)
    local on = {}
    for _, p in ipairs(runs) do for i = p[1], p[2] do on[i] = true end end
    return on
  end
  return { mark(long), mark(short) }
end
local ALONG_X, ALONG_Z = cells(W - 2 * DEPTH), cells(L - 2 * DEPTH)

-- Which row of blocks layer y is in, counted down from the course under the
-- rim (1 = long, 2 = short), or nil in a sunken band. The first row is long,
-- so every size looks alike at the top.
local function rowAt(y)
  local k = (TOP - 2) - y
  if k < 0 then return nil end
  local period = ROW + BAND
  if k % period >= ROW then return nil end
  return math.floor(k / period) % 2 + 1
end

---------------------------------------------------------------- building it

for z = 0, L - 1 do
  for x = 0, W - 1 do
    local dx, dz = math.min(x, W - 1 - x), math.min(z, L - 1 - z) -- in from the sides
    local d = math.min(dx, dz)
    for y = 0, TOP do
      local block
      if y == TOP then
        block = d < DEPTH and stone(x, y, z) or "moss_block"
      elseif y == TOP - 1 then
        block = d <= DEPTH and stone(x, y, z) or "dirt"
      elseif d > DEPTH then
        block = "dirt"
      elseif d == DEPTH or (dx < DEPTH and dz < DEPTH) then
        block = stone(x, y, z) -- the wall behind the blocks, and the corner piers
      else
        local row = rowAt(y)
        local on
        if row then
          if dz < DEPTH then on = ALONG_X[row][x - DEPTH + 1]
          else on = ALONG_Z[row][z - DEPTH + 1] end
        end
        if on then block = stone(x, y, z) end
      end
      if block then set(x, y, z, block) end
    end
  end
end

local platform = { name = ("Mossy platform %dx%d"):format(W, L), blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  platform.blocks[#platform.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return platform
