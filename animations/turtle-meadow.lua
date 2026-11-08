-- Turtles out for a walk: a few ComputerCraft turtles pottering across a
-- meadow full of flowers, under the sun and drifting clouds. Each one crosses
-- the whole screen a whole number of times a loop, so the loop never jumps,
-- however wide the monitor.

local LOOP = 120 -- frames
local SKY, GRASS, BLADE, SUN, CLOUD = "3", "d", "5", "4", "0"
local FLOWER_COLOURS = { "e", "0", "6", "4", "1", "2" }
local FLOWERS = 45 -- flowers scattered over the grass

local TURTLE = { -- facing right: grey body, the screen on its front
  ".777777.",
  "78888fff",
  "78888f5f",
  "78888fff",
  "78888887",
  ".777777.",
}
local FEET = { ".f....f.", "..f..f.." } -- little steps
local CLOUD_ROWS = { "..000...", ".000000.", "00000000" }
local SUN_ROWS = { ".444.", "44444", "44444", ".444." }

-- each turtle: where across it starts (0-1), how far down the grass (0-1)
-- and how many times it crosses the screen a loop
local WALKERS = {
  { 0.10, 0.15, 1 },
  { 0.55, 0.45, 1 },
  { 0.30, 0.80, 2 },
}

-- Flower spots from a fixed seed, so they're the same on every frame. Small
-- numbers, so it comes out the same in CC and in the website's Lua.
local spots = {}
local seed = 4321
local function random()
  seed = (seed * 75 + 74) % 65537
  return seed / 65537
end
for i = 1, FLOWERS do spots[i] = { random(), random(), FLOWER_COLOURS[i % #FLOWER_COLOURS + 1] } end

local function draw(t, w, h)
  local c = canvas.new(w, h, 30, 18)
  c:fill(SKY)
  local horizon = math.floor(c.h * 0.45)
  c:rect(1, horizon + 1, c.w, c.h - horizon, GRASS)
  for x = 1, c.w do
    if (x * 7) % 5 < 2 then c:set(x, horizon + 1 + (x % 3), BLADE) end -- blades of grass
  end
  for _, s in ipairs(spots) do
    c:set(1 + math.floor(s[1] * c.w), horizon + 2 + math.floor(s[2] * (c.h - horizon - 1)), s[3])
  end

  c:sprite(3, 2, SUN_ROWS, { ["4"] = SUN })
  -- clouds: once across a loop, like the turtles
  local span = c.w + 10
  for i, f in ipairs({ 0.2, 0.7 }) do
    local x = math.floor(((f + (t - 1) / LOOP) % 1) * span) - 9
    c:sprite(x, 1 + i * 2, CLOUD_ROWS, { ["0"] = CLOUD })
  end

  -- turtles further back go first, so nearer ones walk in front
  for _, wk in ipairs(WALKERS) do
    local x = math.floor(((wk[1] + wk[3] * (t - 1) / LOOP) % 1) * span) - 9
    local step = math.floor((t + wk[3]) / 2) % 2 -- a step every two frames
    local feet = horizon + 1 + math.floor(wk[2] * (c.h - horizon - 2))
    c:sprite(x, feet - 6 - step, TURTLE)
    c:sprite(x, feet - step, { FEET[step + 1] }) -- a little hop with each step
  end
  return c:rows()
end

return {
  title = "Turtle meadow",
  frameTime = 0.15,
  length = LOOP,
  draw = draw,
}
