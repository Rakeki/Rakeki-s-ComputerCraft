-- A T-rex in sunglasses, whose arms are far too short, reaching a cookie on
-- the table with an extendo grabber: out it goes, the claw snaps shut, back
-- it comes, munch munch, and another cookie turns up. 32 frames, the last
-- leading into the first.

local LOOP = 32
local WALL, FLOOR, SKIRTING = "3", "8", "7"
local TABLE_COLOUR, STICK, CLAW = "c", "7", "1"
local COLOURS = { G = "5", D = "d", K = "f", W = "0", R = "e", a = "5" }

local REX = { -- facing right; rows 5-7 (the jaw) change when it chews
  ".......GGGGGG.",
  "......GGGGGGGG",
  "......GWKKKKKG",
  "......GKKGKKGG",
  "......GGGGGGGG",
  "......GGGGGGGG",
  "......GGGG....",
  ".....GGGG.....",
  "G...GGGGGa....",
  "GG.GGGGGG.....",
  "GGGGGGGGG.....",
  ".GGGGGGG......",
  "..GGGGGG......",
  "...GG.GG......",
  "...GG.GG......",
  "..DDD.DDD.....",
}
local JAW_OPEN = { "......GGGRRRR.", "......GGGGGGG." } -- rows 6 and 7 with its mouth open
local HAND_X, HAND_Y = 10, 9 -- the 'a' in REX: where the grabber is held
local COOKIE = { "ccc", "cfc", "ccc" } -- with a chocolate chip
local BITTEN = { "cc.", "cf.", "cc." }
local CRUMB = { "...", ".c.", "..." }

-- the claw at the end of the stick: open (prongs wide) or shut on the cookie
local function claw(c, x, y, open)
  c:rect(x, y - 1, 1, 3, CLAW)
  local spread = open and 2 or 1
  c:set(x + 1, y - spread, CLAW)
  c:set(x + 1, y + spread, CLAW)
end

local function ease(f) return f * f * (3 - 2 * f) end

local function draw(t, w, h)
  local c = canvas.new(w, h, 32, 19)
  c:fill(WALL)
  local floor = c.h - 1 -- the row its feet stand on
  c:rect(1, floor + 1, c.w, c.h - floor, FLOOR)
  c:rect(1, floor, c.w, 1, SKIRTING)

  local rx, ry = 2, floor - 15 -- the T-rex's top left
  local hx, hy = rx + HAND_X - 1, ry + HAND_Y - 1
  local cookieX = math.max(hx + 6, c.w - 5) -- the cookie's left column on the table
  local tableTop = hy + 2

  -- the table: a top under the cookie and two legs
  c:rect(cookieX - 2, tableTop, 7, 1, TABLE_COLOUR)
  c:rect(cookieX - 1, tableTop + 1, 1, floor - tableTop, TABLE_COLOUR)
  c:rect(cookieX + 3, tableTop + 1, 1, floor - tableTop, TABLE_COLOUR)

  -- how far the grabber reaches, and what the cookie is doing
  local full = cookieX - 2 - hx -- stick length that puts the claw on the cookie
  local reach, open, held, cookie = 0, true, false, COOKIE
  if t <= 10 then
    reach = math.floor(full * ease((t - 1) / 9) + 0.5)
  elseif t <= 12 then
    reach, open, held = full, false, true
  elseif t <= 22 then
    reach, open, held = math.floor(full * (1 - ease((t - 12) / 10)) + 0.5), false, true
  elseif t <= 28 then
    open, held = false, true
    cookie = t <= 24 and COOKIE or t <= 26 and BITTEN or CRUMB
  else
    cookie = t == 29 and CRUMB or t == 30 and BITTEN or COOKIE -- a new one appears
  end

  c:sprite(rx, ry, REX, COLOURS)
  if t >= 23 and t <= 28 and t % 2 == 1 then c:sprite(rx, ry + 5, JAW_OPEN, COLOURS) end -- munch

  c:rect(hx + 1, hy, reach, 1, STICK)
  local tip = hx + 1 + reach
  if held then
    c:sprite(tip + 1, hy - 1, cookie, COLOURS)
  else
    c:sprite(cookieX, tableTop - 3, cookie, COLOURS)
  end
  claw(c, tip, hy, open)
  return c:rows()
end

return {
  title = "T-rex with a grabber",
  frameTime = 0.12,
  length = LOOP,
  draw = draw,
}
