-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Mossy platform: a raised square of moss to build on. Its sides are old
-- stonework, stone and mossy stone bricks mixed with cobblestone and mossy
-- cobblestone, with raised panels standing out of the face in staggered
-- rows like big bricks. On top, a field of moss blocks inside a rim of the
-- same stone. Packed with dirt underneath. y 0 is the ground; x runs east,
-- z south.
--
-- Any size: 'set platform.size 31x25' (wide x long) or '31x25x7' (and how
-- high, moss included), or one number for a square. The panels are fitted
-- to each side so every row ends cleanly. Without the setting (and on the
-- website) it's 21x21, 5 high.
local DEFAULT_W, DEFAULT_L, DEFAULT_H = 21, 21, 5
local MIN_SIDE, MAX_SIDE = 5, 128 -- how small and big a side can be
local MIN_H, MAX_H = 2, 32 -- how low and high it can be
local PANEL, GAP = 3, 1 -- raised panels: about how long, and the gap between them

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
local TOP = H - 1 -- the moss layer; the sides run from the ground up to it

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


---------------------------------------------------------------- the body

for y = 0, TOP do
  for z = 0, L - 1 do
    for x = 0, W - 1 do
      local edge = x == 0 or x == W - 1 or z == 0 or z == L - 1
      if edge then set(x, y, z, stone(x, y, z))
      elseif y == TOP then set(x, y, z, "moss_block")
      else set(x, y, z, "dirt") end
    end
  end
end

---------------------------------------------------------------- raised panels

-- The panels of one side, cells 1..n between its corners, as two rows of
-- { from, to } that lap like brickwork. The long row is as many panels as
-- fit at PANEL long or more, stretched so they fill the side exactly; the
-- other row's gaps fall in the middle of its panels, and a stub too short
-- at either end joins its neighbour (on a tiny side, one gap in the middle).
local function fit(n)
  local k = math.max(1, math.floor((n + GAP) / (PANEL + GAP)))
  local room = n - (k - 1) * GAP
  -- the extra cells go to the panels nearest the middle, in mirrored pairs,
  -- so the side reads the same from both ends; an odd one left over goes to
  -- the middle panel, or widens the middle gap when there's none
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
    -- an even panel's middle leans away from the side's middle, mirrored; one
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

-- the top row under the rim is always a long row, so every size looks alike
local function panels(len, y, at)
  local long, short = fit(len - 2)
  for _, p in ipairs((TOP - 1 - y) % 2 == 0 and long or short) do
    for i = p[1], p[2] do at(i) end
  end
end
for y = 0, TOP - 1 do
  panels(W, y, function(x)
    set(x, y, -1, stone(x, y, -1))
    set(x, y, L, stone(x, y, L))
  end)
  panels(L, y, function(z)
    set(-1, y, z, stone(-1, y, z))
    set(W, y, z, stone(W, y, z))
  end)
end


local platform = { name = ("Mossy platform %dx%d"):format(W, L), blocks = {} }
for k, block in pairs(grid) do
  local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
  platform.blocks[#platform.blocks + 1] = { tonumber(x), tonumber(y), tonumber(z), block }
end
return platform
