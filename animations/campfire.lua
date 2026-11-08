-- A campfire flickering in the dark: four frames of pixel art (the flames
-- change, the logs stay), made bigger to fit the screen. A plain example of
-- the pixel-art format: each letter is a pixel, "." is the background.
local LOGS = {
  "...1444411....",
  "..114404411...",
  "..e1440441e...",
  "..e1144441e...",
  "...e114411e...",
  "..cce1111ecc..",
  ".cccccccccccc.",
  "..cc..cc..cc..",
}

-- the flames above the logs, one set of six rows per frame
local FLAMES = {
  {
    "..............",
    "......1.......",
    ".....11.......",
    ".....141...1..",
    "....1441..11..",
    "...114411.1...",
  },
  {
    "..............",
    ".......1......",
    ".......11.....",
    "..1...141.....",
    "..11..1441....",
    "...1.114411...",
  },
  {
    "........1.....",
    ".......11.....",
    "......141.....",
    "....11441..1..",
    "....144411.1..",
    "...1144411....",
  },
  {
    "..............",
    ".....1........",
    "....11...1....",
    "....141..11...",
    "...14441.1....",
    "...1144411....",
  },
}

local frames = {}
for i, flame in ipairs(FLAMES) do
  local f = {}
  for _, row in ipairs(flame) do f[#f + 1] = row end
  for _, row in ipairs(LOGS) do f[#f + 1] = row end
  frames[i] = f
end

return {
  title = "Campfire",
  frameTime = 0.25,
  frames = frames, -- blit colours as letters: 1 orange, 4 yellow, 0 white, e red, c brown
  background = "f",
}
