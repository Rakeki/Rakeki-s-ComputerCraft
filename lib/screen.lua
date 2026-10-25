-- Flicker-free drawing on monitors and terminals. Clearing a monitor and
-- redrawing it in place makes it flash, so each frame is drawn into a hidden
-- window over the screen and then shown in one go. A frame that would look
-- the same as the last one can be skipped, which also saves sending it to
-- every player who can see the monitor.
--
--   local screen = require("lib.screen")
--   local s = screen.new(monitor)              -- a monitor, or term.current()
--   if not s:same(key) then                    -- optional: key describes what the frame shows
--     local win, w, h = s:frame()              -- hidden and cleared, the size of the screen
--     screen.put(win, 1, 1, "Hello", "yellow", "gray")
--     s:show()                                 -- up it goes, all at once
--   end
--
--   s:setTarget(t)                   draw on another monitor from now on
--   s:size()                         the screen's size now
--   screen.put(t, x, y, text, fg, bg) write text; colours are names ("lime") or numbers (colors.lime), bg black if left out
--   screen.fit(text, w)              cut or pad text to exactly w characters
local screen = {}
screen.__index = screen

local function colour(c, default)
  if type(c) == "string" then return colors[c] or default end
  return c or default
end

function screen.new(target)
  return setmetatable({ target = target }, screen)
end

function screen:setTarget(target)
  if target ~= self.target then self.target, self.win, self.last = target, nil, nil end
end

function screen:size() return self.target.getSize() end

-- A hidden, cleared window to draw the next frame into, and its size. It's
-- made again when the screen changes size (a monitor resized or rescaled).
function screen:frame(bg)
  local w, h = self.target.getSize()
  local ww, wh = 0, 0
  if self.win then ww, wh = self.win.getSize() end
  if not self.win or ww ~= w or wh ~= h then self.win = window.create(self.target, 1, 1, w, h, false) end
  local win = self.win
  win.setVisible(false)
  win.setCursorBlink(false)
  win.setBackgroundColor(colour(bg, colors.black))
  win.clear()
  return win, w, h
end

-- Show the frame. Set the cursor on the window first if it should blink
-- somewhere (a search box): showing it puts the cursor there.
function screen:show()
  if self.win then self.win.setVisible(true) end
end

-- True when key matches the frame last asked about at this size, so drawing
-- it again can be skipped. Remembers key for next time otherwise.
function screen:same(key)
  local w, h = self.target.getSize()
  key = w .. "x" .. h .. "|" .. tostring(key)
  if self.win and key == self.last then return true end
  self.last = key
  return false
end

function screen.put(t, x, y, text, fg, bg)
  t.setCursorPos(x, y)
  t.setTextColor(colour(fg, colors.white))
  t.setBackgroundColor(colour(bg, colors.black))
  t.write(text)
end

function screen.fit(text, w)
  text = tostring(text or "")
  if w <= 0 then return "" end
  if #text > w then return text:sub(1, w) end
  return text .. (" "):rep(w - #text)
end

return screen
