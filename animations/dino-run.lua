-- A little dinosaur running through the desert, jumping every cactus that
-- comes its way, under drifting clouds. The ground scrolls past, so the
-- loop has no end: two cacti a loop, and the last frame leads into the first.

local LOOP = 32 -- frames; a cactus comes round every 16 (32 pixels at 2 a frame)
local SPEED = 2 -- pixels the ground moves a frame
local GAP = 32 -- pixels between cacti (and clouds)
local DINO_X = 3 -- the dinosaur's left column
local SKY, SAND, PEBBLE, CLOUD, SUN = "3", "4", "1", "0", "4"

local DINO = {
  "....GGGG",
  "....GfGG",
  "....GGGG",
  "....GG..",
  "G..GGGGG",
  "GGGGGGG.",
  ".GGGGG..",
}
local LEGS = { "..G..G..", "...GG..." } -- running: legs apart, then together
local CACTUS = {
  "..C..",
  "C.C..",
  "CCC.C",
  "..CCC",
  "..C..",
}
local CLOUD_ROWS = { ".0000.", "000000" }
local SUN_ROWS = { ".44.", "4444", "4444", ".44." }
local COLOURS = { G = "5", f = "f", C = "d", ["0"] = CLOUD, ["4"] = SUN }

-- How high it is on each frame of a jump: up and down in ten frames,
-- clearing the cactus while they overlap.
local JUMP = { 2, 5, 7, 8, 9, 9, 8, 7, 5, 2 }

local function draw(t, w, h)
  local c = canvas.new(w, h, 28, 19)
  c:fill(SKY)
  local ground = c.h - 2 -- the row the dinosaur and cacti stand on
  c:rect(1, ground + 1, c.w, c.h - ground, SAND)

  c:sprite(c.w - 5, 2, SUN_ROWS, COLOURS)
  -- clouds drift at half the ground's speed: once round in a loop
  for j = -1, math.ceil(c.w / GAP) do
    local x = (30 - (t - 1)) % GAP + GAP * j
    c:sprite(x, 3 + (j % 2) * 3, CLOUD_ROWS, COLOURS)
  end
  -- pebbles in the sand move with the ground
  for j = -1, math.ceil(c.w / 8) do
    local x = (7 - SPEED * (t - 1)) % 8 + 8 * j
    c:set(x, ground + 1 + (j % 2), PEBBLE)
  end

  -- d: how far ahead of the dinosaur the next cactus is
  local d = (30 - SPEED * (t - 1)) % GAP
  for j = -1, math.ceil(c.w / GAP) do
    c:sprite(DINO_X + d + GAP * j, ground - 4, CACTUS, COLOURS)
  end

  -- it jumps from 12 pixels before a cactus until it's past it
  local e = d > 12 and d - GAP or d
  local up = 0
  if e <= 12 and e >= -6 then up = JUMP[(12 - e) / SPEED + 1] end
  local legs = up > 0 and LEGS[1] or LEGS[t % 2 + 1]
  c:sprite(DINO_X, ground - up - 7, DINO, COLOURS)
  c:sprite(DINO_X, ground - up, { legs }, COLOURS)
  return c:rows()
end

return {
  title = "Dino run",
  frameTime = 0.1,
  length = LOOP,
  draw = draw,
}
