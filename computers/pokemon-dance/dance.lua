-- Dance: Pikachu dancing on a monitor, on a seamless loop. Eight frames of
-- bouncing, swaying, waving arms, stamping feet and a wagging tail, under a
-- spotlight on a disco floor, with sparkles and music notes around it. The
-- last frame leads straight back into the first, so it never jumps. The
-- bigger the monitor, the bigger the dancer.
--
--   dance                  start dancing (startup.lua runs it)
--   dance monitor [name]   pick the monitor to dance on ('none': this computer's screen)
--
-- Without a monitor it dances on the computer's own screen.
local screen = require("lib.screen") -- flicker-free drawing
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local FRAME_TIME = 0.15 -- seconds per frame; the dance is FRAMES frames long
local MONITOR_SCALES = { 0.5 } -- text size on the monitor (0.5: smallest cells, so the biggest dancer)
local WALL = "f" -- blit colour of the dark stage behind everything (black)
local LIGHT = "7" -- the spotlight's colour (gray)
local SHADOW = "f" -- the shadow under the dancer's feet (black)
local TILES = { "2", "3", "5", "1" } -- disco floor colours: magenta, light blue, lime, orange
local SPARKS = { "0", "4", "3", "6" } -- sparkle colours: white, yellow, light blue, pink
local NOTE_COLOURS = { "2", "b", "e", "a" } -- music notes: magenta, blue, red, purple

---------------------------------------------------------------- the dancer

-- Pixel art; each pixel is two characters wide and one high (about square on
-- a monitor), times the scale that fits. "." is see-through.
local COLOURS = { Y = "4", K = "f", W = "0", R = "e", B = "c" } -- yellow, black, white, red, brown

local HEAD = { -- rows 0-10; leans with the dance
  "K...........K",
  "KK.........KK",
  ".YY.......YY.",
  "..YY.....YY..",
  "..YYYYYYYYY..",
  ".YYYYYYYYYYY.",
  ".YYKWYYYKWYY.",
  ".YYKKYYYKKYY.",
  "RRYYYYKYYYYRR",
  "RRYYYKYKYYYRR",
  ".YYYYYYYYYYY.",
}
local BODY = { -- rows 11-14
  "...YYYYYYY...",
  "..YYYYYYYYY..",
  "..YYYYYYYYY..",
  "...YYYYYYY...",
}
local TAIL = { -- rows 6-13 from column 11, behind the body; the tip sways
  "....YYY",
  "...YYYY",
  "....YY.",
  "..YYY..",
  "...YY..",
  ".YYY...",
  "..Y....",
  "BB.....",
}
local ARMS = { -- left arm pixels { x, y }; the right arm is its mirror image
  down = { { 1, 13 } },
  out = { { 1, 12 }, { 0, 12 }, { -1, 12 } },
  up = { { 1, 12 }, { 0, 11 }, { -1, 10 } },
}
local FEET = { -- row 15 on the floor, or row 14 and out to the side when lifted
  left = { { 2, 15 }, { 3, 15 } }, leftUp = { { 1, 14 }, { 2, 14 } },
  right = { { 9, 15 }, { 10, 15 } }, rightUp = { { 10, 14 }, { 11, 14 } },
}
local SPRITE_W, SPRITE_H = 19, 17 -- columns -1..17, rows 0..15 plus one for the bounce

-- One loop of the dance. The right arm does what the left did half a loop ago.
local FRAMES = 8
local BOB = { 0, -1, -1, 0, 0, -1, -1, 0 } -- up and down
local LEAN = { 0, 1, 1, 0, 0, -1, -1, 0 } -- head sways right, then left
local LEFT_ARM = { "up", "up", "up", "out", "down", "down", "down", "out" }
local LIFT = { "", "left", "left", "", "", "right", "right", "" } -- the foot off the floor

-- Sparkles on the stage: where (fractions of the screen) and their colour.
local SPARKLES = {
  { 0.06, 0.12 }, { 0.22, 0.38 }, { 0.91, 0.10 }, { 0.80, 0.42 },
  { 0.10, 0.66 }, { 0.94, 0.68 }, { 0.34, 0.06 }, { 0.68, 0.22 },
}
-- Music notes rising beside the dancer: pixels from its middle, and when each starts.
local NOTES = { { -11, 0 }, { 13, 4 }, { -15, 2 }, { 16, 6 } }

---------------------------------------------------------------- painting

-- Paints frame t into a cw x ch grid of pixels (blit colours). Returns the
-- grid, the first floor row and the dancer's middle column.
local function paint(t, cw, ch)
  local floorRows = math.max(2, math.floor(ch / 8))
  local floorTop = ch - floorRows + 1
  local ox = math.floor((cw - SPRITE_W) / 2) + 2 -- column of the dancer's x = 0
  local oy = floorTop - 16 -- row of its y = 0 with its feet on the floor
  local cx = ox + 6
  local beat = math.floor((t - 1) / 2) -- the floor changes every two frames: four times a loop

  local px = {}
  for y = 1, ch do
    local row = {}
    local half = math.max(2, 8 + math.floor((y - oy) / 2)) -- the spotlight widens downwards
    for x = 1, cw do
      if y >= floorTop then
        row[x] = TILES[(math.floor((x - 1) / 2) + (y - floorTop) + beat) % #TILES + 1]
      elseif math.abs(x - cx) <= half then
        row[x] = LIGHT
      else
        row[x] = WALL
      end
    end
    px[y] = row
  end

  -- its shadow is smaller while it's in the air
  local shadow = BOB[t] < 0 and 4 or 5
  for x = cx - shadow, cx + shadow do
    if px[floorTop][x] then px[floorTop][x] = SHADOW end
  end

  local by, lean = oy + BOB[t], LEAN[t]
  local function plot(x, y, c)
    local X, row = ox + x, px[by + y]
    if c ~= "." and row and X >= 1 and X <= cw then row[X] = COLOURS[c] or c end
  end

  for i, line in ipairs(TAIL) do
    local y = 5 + i
    local sway = math.floor(-lean * (13 - y) / 7 + 0.5) -- the tip moves most
    for j = 1, #line do plot(10 + j + sway, y, line:sub(j, j)) end
  end
  for i, line in ipairs(BODY) do
    for j = 1, #line do plot(j - 1, 10 + i, line:sub(j, j)) end
  end
  for _, p in ipairs(ARMS[LEFT_ARM[t]]) do plot(p[1], p[2], "Y") end
  for _, p in ipairs(ARMS[LEFT_ARM[(t + 3) % FRAMES + 1]]) do plot(12 - p[1], p[2], "Y") end
  for _, p in ipairs(FEET[LIFT[t] == "left" and "leftUp" or "left"]) do plot(p[1], p[2], "Y") end
  for _, p in ipairs(FEET[LIFT[t] == "right" and "rightUp" or "right"]) do plot(p[1], p[2], "Y") end
  for i, line in ipairs(HEAD) do
    for j = 1, #line do plot(j - 1 + lean, i - 1, line:sub(j, j)) end
  end
  return px, floorTop, cx
end

-- Every frame for a w x h screen, as blit rows, made once per screen size.
local cache = {}
local function build(w, h)
  local k = math.max(1, math.min(math.floor(w / ((SPRITE_W + 2) * 2)), math.floor(h / (SPRITE_H + 2))))
  local cw, ch = math.max(1, math.floor(w / (2 * k))), math.max(1, math.floor(h / k))
  local xoff = math.floor((w - cw * 2 * k) / 2) -- spare columns split either side
  local yoff = h - ch * k -- spare rows go on top, so the floor stays at the bottom
  local frames = {}
  for t = 1, FRAMES do
    local px, floorTop, cx = paint(t, cw, ch)
    local text, fg, bg = {}, {}, {}
    for r = 1, h do
      local prow = px[math.floor((r - 1 - yoff) / k) + 1]
      local tr, fr, br = {}, {}, {}
      for c = 1, w do
        tr[c], fr[c] = " ", "0"
        br[c] = prow and prow[math.floor((c - 1 - xoff) / (2 * k)) + 1] or WALL
      end
      text[r], fg[r], bg[r] = tr, fr, br
    end

    -- sparkles and notes go on the stage only, never over the dancer or the floor
    local floorCell = yoff + (floorTop - 1) * k + 1
    local function put(c, r, char, colour)
      local b = bg[r] and bg[r][c]
      if b == WALL or b == LIGHT then text[r][c], fg[r][c] = char, colour end
    end
    for i, s in ipairs(SPARKLES) do
      local phase = (t + i) % 4 -- twinkles four times a loop
      local char = ({ [0] = "*", "+", "." })[phase]
      if char then
        put(math.floor(s[1] * (w - 1)) + 1, math.floor(s[2] * math.max(1, floorCell - 2)) + 1, char, SPARKS[i % #SPARKS + 1])
      end
    end
    local step = math.max(1, math.floor((floorCell - 2) / FRAMES))
    local middle = xoff + (cx - 1) * 2 * k + k
    for i, n in ipairs(NOTES) do
      local s = (t - 1 + n[2]) % FRAMES -- how far it has risen
      if s < FRAMES - 1 then
        put(middle + n[1] * 2 * k + s % 2, floorCell - 1 - s * step, "\14", NOTE_COLOURS[i % #NOTE_COLOURS + 1])
      end
    end

    local rows = {}
    for r = 1, h do rows[r] = { table.concat(text[r]), table.concat(fg[r]), table.concat(bg[r]) } end
    frames[t] = rows
  end
  cache = { w = w, h = h, frames = frames }
end

---------------------------------------------------------------- running

local args = { ... }
local display -- lib/screen.lua on the monitor, or this computer's screen

if args[1] == "monitor" then
  local pick = screen.choose("dance.monitor", args[2])
  if pick then
    print(("Dancing on %s from now on."):format(pick))
    os.queueEvent("dance_monitor") -- a copy running in another tab moves at once
  end
  return
elseif args[1] then
  print("Usage: dance               start dancing")
  print("       dance monitor [name] pick the monitor")
  return
end

local function announce()
  local where = display.name and ("on " .. display.name) or "on this computer's screen"
  if display.name then
    term.clear()
    term.setCursorPos(1, 1)
    print(("Pikachu is dancing %s."):format(where))
    print("Hold Ctrl+T to stop. 'dance monitor' picks another monitor.")
  end
  if report then report.set("running", "dancing " .. where) end
end

local function draw(t)
  local win, w, h = display:frame() -- every cell is blitted below
  if cache.w ~= w or cache.h ~= h then build(w, h) end
  local rows = cache.frames[t]
  for r = 1, h do
    win.setCursorPos(1, r)
    win.blit(rows[r][1], rows[r][2], rows[r][3])
  end
  display:show()
end

local function main()
  display = screen.find({ scales = MONITOR_SCALES, setting = "dance.monitor", fallback = term.current() })
  announce()
  local t, timer = 1, os.startTimer(0)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == timer then
      draw(t)
      t = t % FRAMES + 1
      timer = os.startTimer(FRAME_TIME)
    elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" or ev[1] == "dance_monitor" then
      -- also fired by turtles driving past: only acts if the monitor came or went
      if display:refresh() then announce() end
    end
  end
end

if report then report.init("dance") end
if errlog then errlog.init("dance") end

local function run()
  local ok, err = true, nil
  if errlog then ok, err = errlog.pcall(main) else ok, err = pcall(main) end
  if not ok then
    if report then report.set("error", tostring(err)) end
    error(err, 0)
  end
end

if report then parallel.waitForAny(run, report.loop) else run() end
