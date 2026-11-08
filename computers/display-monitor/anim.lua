-- Animations for the display monitor: loads one (a file from /animations)
-- and paints its frames for a screen of any size, as blit rows. The website
-- runs this same file in the browser to preview every animation.
--
--   local anim = require("anim")
--   local a, err = anim.load(source, name)   -- the file's text; a = the animation, or nil and why
--   local rows = anim.frame(a, t, w, h)      -- frame t (1..a.length) for a w x h screen:
--                                            -- rows[r] = { text, fg, bg }, blit strings w long
--
-- An animation file is Lua that returns a table. It runs with no access to
-- the computer (only math, string and table), so any file is safe to show.
--
--   return {
--     title = "Campfire",     -- shown by 'display list' (default: the file name)
--     frameTime = 0.2,        -- seconds per frame (default 0.2)
--
--     -- pixel art, made bigger to fit the screen:
--     frames = {              -- each frame: rows of letters, one per pixel
--       { "..44..", ".4114.", ... },
--       { "...4..", ".4114.", ... },
--     },
--     colours = { Y = "4" },  -- letter -> blit colour (0-9, a-f; the digits stand for themselves)
--     background = "f",       -- around the art and for "." or " " (default "f", black)
--     pixel = 2,              -- characters across per pixel (default 2: about square on a monitor)
--
--     -- or code, for anything pixel art can't do:
--     length = 8,             -- frames in the loop
--     draw = function(t, w, h) return rows end, -- rows as anim.frame returns them
--   }
local anim = {}

local HEX = "0123456789abcdef"
local DEFAULT_FRAME_TIME = 0.2 -- seconds per frame when the file doesn't say
local MIN_FRAME_TIME = 0.05 -- a computer can't draw much faster than a frame a tick

-- What an animation's code may use. Copies, so one file can't change them for the next.
local function sandbox()
  local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
  end
  return {
    math = copy(math), string = copy(string), table = copy(table),
    ipairs = ipairs, pairs = pairs, next = next, select = select, type = type,
    tostring = tostring, tonumber = tonumber, error = error, assert = assert, pcall = pcall,
    setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
    unpack = table.unpack or unpack,
  }
end

local function isList(v) return type(v) == "table" and #v > 0 end

function anim.load(source, name)
  local fn, err = load(source, "=" .. (name or "animation"), "t", sandbox())
  if not fn then return nil, err end
  local ok, a = pcall(fn)
  if not ok then return nil, a end
  if type(a) ~= "table" then return nil, "it should return a table" end
  a.title = type(a.title) == "string" and a.title or name or "animation"
  a.frameTime = math.max(MIN_FRAME_TIME, tonumber(a.frameTime) or DEFAULT_FRAME_TIME)
  if type(a.draw) == "function" then
    a.length = math.floor(tonumber(a.length) or 0)
    if a.length < 1 then return nil, "a draw animation needs length (how many frames)" end
  elseif isList(a.frames) then
    a.length = #a.frames
    a.pixel = math.max(1, math.floor(tonumber(a.pixel) or 2))
    a.background = type(a.background) == "string" and HEX:find(a.background, 1, true) and a.background or "f"
    local colours = type(a.colours) == "table" and a.colours or {}
    a.lookup = {}
    for i = 1, #HEX do a.lookup[HEX:sub(i, i)] = HEX:sub(i, i) end
    for k, v in pairs(colours) do
      if type(k) == "string" and type(v) == "string" and #v == 1 and HEX:find(v, 1, true) then a.lookup[k] = v end
    end
    a.lookup["."], a.lookup[" "] = a.background, a.background
    a.artW, a.artH = 0, 0
    for i, f in ipairs(a.frames) do
      if not isList(f) then return nil, ("frame %d should be a list of rows"):format(i) end
      a.artH = math.max(a.artH, #f)
      for _, row in ipairs(f) do
        if type(row) ~= "string" then return nil, ("frame %d has a row that isn't text"):format(i) end
        a.artW = math.max(a.artW, #row)
      end
    end
  else
    return nil, "it needs frames (pixel art) or draw (code)"
  end
  return a
end

-- A blit string exactly w long: cut, padded with pad, odd colours made pad.
local function fix(s, w, pad, colours)
  s = type(s) == "string" and s or ""
  if colours then s = s:lower():gsub("[^0-9a-f]", pad) end
  if #s > w then return s:sub(1, w) end
  return s .. pad:rep(w - #s)
end

-- Pixel art: each pixel a.pixel * k characters across and k rows down, k the
-- biggest whole number that fits, centred.
local function paintPixels(a, t, w, h)
  local art = a.frames[t]
  local k = math.max(1, math.min(math.floor(w / (a.artW * a.pixel)), math.floor(h / a.artH)))
  local pw = a.pixel * k
  local xoff = math.floor((w - a.artW * pw) / 2)
  local yoff = math.floor((h - a.artH * k) / 2)
  local text, fg = (" "):rep(w), ("0"):rep(w)
  local rows = {}
  for r = 1, h do
    local line = art[math.floor((r - 1 - yoff) / k) + 1]
    local bg = {}
    for c = 1, w do
      local x = math.floor((c - 1 - xoff) / pw) + 1
      local ch = line and x >= 1 and line:sub(x, x) or ""
      bg[c] = a.lookup[ch] or a.background
    end
    rows[r] = { text, fg, table.concat(bg) }
  end
  return rows
end

-- Frame t of a for a w x h screen. Errors from an animation's own code
-- come out as errors, for the display to skip it.
function anim.frame(a, t, w, h)
  if a.draw then
    local rows = a.draw(t, w, h)
    if type(rows) ~= "table" then error("draw should return a list of rows", 0) end
    local out = {}
    for r = 1, h do
      local row = type(rows[r]) == "table" and rows[r] or {}
      out[r] = { fix(row[1], w, " "), fix(row[2], w, "0", true), fix(row[3], w, "f", true) }
    end
    return out
  end
  return paintPixels(a, t, w, h)
end

return anim
