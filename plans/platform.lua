-- Plan for the blueprint projector and build-control (see lib/plan.lua):
-- a Lua plan returns the same table a JSON plan holds, made by code.
--
-- Mossy platform: a raised square of moss to build on, its sides an old
-- stone wall. A wall of stone, stone bricks, andesite, tuff and dead coral
-- stands one block in from the edge, and mossy blocks stand out of it. Seen
-- from the side, top to bottom:
--
--   R~~~   R: a rim of tuff and tuff bricks, one out over the wall; moss inside
--   PW#    P: wall posts on every other block, joined back to the wall; W: stone bricks
--   BW#    B: a pillar under each post, two high
--   BW#
--   .W#    .: a sunken band
--   BW#    then rows of blocks two high, three long with a gap between, each
--   BW#    row staggered from the one above like brickwork, a sunken band
--   .W#    under each
--
-- Rows and posts are fitted to each side so both ends match, and a row of
-- blocks wraps round the corners. Packed with dirt underneath. y 0 is the
-- ground; x runs east, z south.
--
-- Any size: type it after the command, 31x25 (wide x long) or 31x25x8 (and
-- how high, moss included): 'build platform <x> <y> <z> north 31x25x8',
-- 'instabuild platform ... 31x25x8', 'projector platform 31x25x8'. Or set
-- it once, 'set platform.size 31x25x8' (the projector's monitor picks
-- plans without typing). The size is the whole footprint, rim included.
-- Every 3 more high is another row of blocks. Without either (and on the
-- website) it's 21x21, 11 high.
local DEFAULT_W, DEFAULT_L, DEFAULT_H = 21, 21, 11
local MIN_SIDE, MAX_SIDE = 7, 128 -- how small and big a side can be
local MIN_H, MAX_H = 5, 32 -- how low and high it can be: rim, posts, pillars, band
local PANEL, GAP = 3, 1 -- the blocks: at least how long, and the gap between them
local ROW, BAND = 2, 1 -- how high a row of blocks is, and the sunken band under it
local PILLAR = 2 -- how high the pillars under the posts are

-- each kind of block is picked from these, the weights as in the sample
-- wall the player built
local WALL = { { "stone", 34 }, { "stone_bricks", 25 }, { "andesite", 15 }, { "dead_brain_coral_block", 15 },
  { "tuff", 9 }, { "cobblestone", 2 } }
local BLOCK = { { "mossy_stone_bricks", 34 }, { "mossy_cobblestone", 26 }, { "stone_bricks", 21 },
  { "cobblestone", 7 }, { "stone", 6 }, { "andesite", 6 } }
local RIM = { { "tuff", 56 }, { "tuff_bricks", 44 } }
local POST = { { "stone_brick_wall", 1 }, { "cobblestone_wall", 1 }, { "mossy_stone_brick_wall", 1 },
  { "mossy_cobblestone_wall", 1 } }
local COURSE = "stone_bricks" -- the wall's top course, behind the posts

local function clamp(n, lo, hi) return math.max(lo, math.min(hi, math.floor(n))) end
local opts = ... -- what was typed after the command (lib/plan.lua), or nil on the website
local function size()
  local text = type(opts) == "table" and opts.size
    or type(settings) == "table" and settings.get("platform.size") or nil
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
local function pick(list, x, y, z)
  local total = 0
  for _, e in ipairs(list) do total = total + e[2] end
  local n = noise(x, y, z) * total
  for _, e in ipairs(list) do
    n = n - e[2]
    if n < 0 then return e[1] end
  end
  return list[#list][1]
end

---------------------------------------------------------------- fitting the rows

-- The blocks of one side, cells 1..n between its corners, as two rows of
-- { from, to } that lap like brickwork. The long row is as many blocks as
-- fit at PANEL long or more, stretched so they fill the side exactly; the
-- other row's gaps fall in the middle of its blocks (on a tiny side, one
-- gap in the middle).
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
  -- a one-block stub at an end is kept: it meets the next side's round the
  -- corner
  local cuts = {}
  for _, m in ipairs(mids) do
    if m >= 2 and m <= n - 1 then cuts[#cuts + 1] = m end
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

-- which cells of a side 1..n hold a block in the long row, the short row,
-- and the posts and pillars (every other one, counted in from both ends so
-- the side is mirrored; two together in the middle of an even side)
local function cells(n)
  local long, short = fit(n)
  local function mark(runs)
    local on = {}
    for _, p in ipairs(runs) do for i = p[1], p[2] do on[i] = true end end
    return on
  end
  local posts = {}
  for i = 1, n do posts[i] = math.min(i, n + 1 - i) % 2 == 1 end
  return { long = mark(long), short = mark(short), posts = posts }
end
local ALONG_X, ALONG_Z = cells(W - 2), cells(L - 2)

-- What the outer ring holds in layer y: "rim", "post", "pillar", "long" or
-- "short" (a row of blocks), or nil in a sunken band. The rows count down
-- from the band under the pillars; the first is long.
local function layer(y)
  if y == TOP then return "rim" end
  if y == TOP - 1 then return "post" end
  if y >= TOP - 1 - PILLAR then return "pillar" end
  local k = (TOP - 2 - PILLAR) - y
  local period = ROW + BAND
  if k % period < BAND then return nil end
  return math.floor(k / period) % 2 == 0 and "long" or "short"
end

---------------------------------------------------------------- building it

-- A wall post on the outer ring, joined back to the wall on its inner side.
local function post(x, y, z)
  local side = z == 0 and "south" or z == L - 1 and "north" or x == 0 and "east" or "west"
  return ("%s[up=true,%s=tall]"):format(pick(POST, x, y, z), side)
end

-- Whether ring cell (x, z) holds something in a layer of this kind; a
-- corner only in a row of blocks that reaches it from both sides.
local function ringHas(x, z, kind)
  local function at(cx, cz)
    local along, i
    if cz == 0 or cz == L - 1 then along, i = ALONG_X, cx else along, i = ALONG_Z, cz end
    if kind == "post" or kind == "pillar" then return along.posts[i] end
    return along[kind][i]
  end
  local cornerX, cornerZ = x == 0 or x == W - 1, z == 0 or z == L - 1
  if not (cornerX and cornerZ) then return at(x, z) end
  if kind == "post" or kind == "pillar" then return false end
  local inX, inZ = x == 0 and 1 or W - 2, z == 0 and 1 or L - 2
  return at(inX, z) and at(x, inZ)
end

for z = 0, L - 1 do
  for x = 0, W - 1 do
    local d = math.min(x, W - 1 - x, z, L - 1 - z) -- 0: the outer ring, 1: the wall
    for y = 0, TOP do
      local block
      if y == TOP then
        block = d == 0 and pick(RIM, x, y, z) or "moss_block"
      elseif d >= 2 then
        block = "dirt"
      elseif d == 1 then
        block = y == TOP - 1 and COURSE or pick(WALL, x, y, z)
      else
        local kind = layer(y)
        if kind and ringHas(x, z, kind) then
          block = kind == "post" and post(x, y, z) or pick(BLOCK, x, y, z)
        end
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
