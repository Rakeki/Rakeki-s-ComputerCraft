-- A banana dancing: wiggling from side to side, bouncing, waving its arms in
-- turn and kicking out a leg, in front of stripes sliding past. Eight frames,
-- the last leading into the first.

local LOOP = 8
local STRIPES = { "a", "2", "b", "6" } -- purple, magenta, blue, pink: two pixels wide, sliding a pixel a frame
local YELLOW, TIP, LIMB = "4", "c", "f" -- banana, its brown ends, arms and legs

-- the banana, top to bottom: how far right of its middle each row starts
-- (it curves), and how wide it is
local BODY = {
  { 2, 1 }, { 1, 2 }, { 0, 3 }, { 0, 3 }, { -1, 4 }, { -1, 4 }, { -1, 4 },
  { -1, 4 }, { -1, 4 }, { 0, 3 }, { 0, 3 }, { 1, 2 }, { 2, 1 },
}
local EYES, MOUTH, SHOULDER = 5, 8, 8 -- rows

-- per frame: wiggle (-1, 0, 1), bounce, each arm and the leg kicked out
local WIGGLE = { 0, 1, 1, 0, 0, -1, -1, 0 }
local BOB = { 0, -1, 0, -1, 0, -1, 0, -1 }
local LEFT_ARM = { "up", "out", "down", "out", "up", "out", "down", "out" }
local RIGHT_ARM = { "down", "out", "up", "out", "down", "out", "up", "out" }
local KICK = { "", "left", "", "", "", "right", "", "" }
local ARM = { -- pixels out from the shoulder { across, down }, for the left arm
  up = { { -1, 0 }, { -2, -1 }, { -3, -2 }, { -3, -3 } },
  out = { { -1, 0 }, { -2, 0 }, { -3, 0 }, { -4, -1 } },
  down = { { -1, 0 }, { -2, 1 }, { -3, 2 }, { -3, 3 } },
}

local function draw(t, w, h)
  local c = canvas.new(w, h, 20, 19)
  for y = 1, c.h do
    for x = 1, c.w do
      c:set(x, y, STRIPES[math.floor((x + y + t) / 2) % #STRIPES + 1])
    end
  end

  local mid = math.floor(c.w / 2)
  local top = c.h - 16 + BOB[t] -- 13 rows of banana, 3 of legs
  local wig = WIGGLE[t]
  local left, right = {}, {}
  for i, row in ipairs(BODY) do
    -- the top and bottom lean opposite ways: a wiggle
    local lean = math.floor(wig * (7 - i) / 3 + 0.5)
    local x0 = mid + row[1] + lean
    local y = top + i - 1
    for x = x0, x0 + row[2] - 1 do c:set(x, y, (i == 1 or i == #BODY) and TIP or YELLOW) end
    left[i], right[i] = x0, x0 + row[2] - 1
  end
  local eyeY, mouthY = top + EYES - 1, top + MOUTH - 1
  c:set(left[EYES] + 1, eyeY, "f"); c:set(left[EYES] + 3, eyeY, "f")
  c:set(left[MOUTH] + 1, mouthY, "e"); c:set(left[MOUTH] + 2, mouthY, "e")

  local sy = top + SHOULDER - 1
  for _, p in ipairs(ARM[LEFT_ARM[t]]) do c:set(left[SHOULDER] + p[1], sy + p[2], LIMB) end
  for _, p in ipairs(ARM[RIGHT_ARM[t]]) do c:set(right[SHOULDER] - p[1], sy + p[2], LIMB) end

  -- legs from the bottom of the banana: straight down, or one kicked out
  local hip = top + #BODY
  local lx, rx = mid, mid + 2
  for dy = 0, 2 do
    c:set(KICK[t] == "left" and lx - dy or lx, hip + dy, LIMB)
    c:set(KICK[t] == "right" and rx + dy or rx, hip + dy, LIMB)
  end
  c:set((KICK[t] == "left" and lx - 3 or lx - 1), hip + 2, LIMB) -- feet
  c:set((KICK[t] == "right" and rx + 3 or rx + 1), hip + 2, LIMB)
  return c:rows()
end

return {
  title = "Dancing banana",
  frameTime = 0.15,
  length = LOOP,
  draw = draw,
}
