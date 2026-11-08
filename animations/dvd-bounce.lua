-- The bouncing DVD logo: it drifts across a black screen, bouncing off the
-- edges and changing colour on every bounce. Its path is worked out for the
-- screen it's on so that it bounces a whole number of times each way in a
-- loop and ends where it began, in the same colour: the loop never jumps.

local LOOP = 240 -- frames
local SPEED = 0.5 -- about how many pixels it moves a frame, each way
local COLOURS = { "3", "2", "4", "5" } -- light blue, magenta, yellow, lime (bounces a loop is a multiple of 4)
local LOGO = {
  "XX..X.X.XX.",
  "X.X.X.X.X.X",
  "X.X.X.X.X.X",
  "X.X.X.X.X.X",
  "XX...X..XX.",
  "...........",
  ".XXXXXXXXX.",
  "XXXX...XXXX",
  ".XXXXXXXXX.",
}
local LOGO_W, LOGO_H = 11, 9
local PHASE_X, PHASE_Y = 0.13, 0.37 -- where along each way it starts, so it doesn't begin in a corner

-- 0 -> 1 -> 0 as u goes from 0 to 1, and round again
local function zigzag(u)
  u = u % 1
  return 1 - math.abs(1 - 2 * u)
end

local function draw(t, w, h)
  local c = canvas.new(w, h, 24, 16)
  c:fill("f")
  local rangeX, rangeY = math.max(0, c.w - LOGO_W), math.max(0, c.h - LOGO_H)
  -- there and back (two bounces) this many times a loop, each way
  local nx = math.max(1, math.floor(LOOP * SPEED / (2 * math.max(1, rangeX)) + 0.5))
  local ny = math.max(1, math.floor(LOOP * SPEED / (2 * math.max(1, rangeY)) + 0.5))
  if ny == nx then ny = ny + 2 end -- not the same, or it just goes up and down a diagonal
  if (nx + ny) % 2 == 1 then ny = ny + 1 end -- so a loop's bounces are a multiple of 4: the colour comes round

  local s = (t - 1) / LOOP
  local ux, uy = PHASE_X + nx * s, PHASE_Y + ny * s
  local x = 1 + math.floor(zigzag(ux) * rangeX + 0.5)
  local y = 1 + math.floor(zigzag(uy) * rangeY + 0.5)
  local bounces = math.floor(2 * ux) - math.floor(2 * PHASE_X) + math.floor(2 * uy) - math.floor(2 * PHASE_Y)
  c:sprite(x, y, LOGO, { X = COLOURS[bounces % #COLOURS + 1] })
  return c:rows()
end

return {
  title = "DVD logo",
  frameTime = 0.08,
  length = LOOP,
  draw = draw,
}
