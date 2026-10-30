-- Flicker-free drawing on monitors and terminals. Clearing a monitor and
-- redrawing it in place makes it flash, so each frame is drawn into a hidden
-- window over the screen and then shown in one go. A frame that would look
-- the same as the last one can be skipped, which also saves sending it to
-- every player who can see the monitor.
--
--   local screen = require("lib.screen")
--   local s = screen.new(term.current())       -- or screen.find(...) for a monitor, below
--   if not s:same(key) then                    -- optional: key describes what the frame shows
--     local win, w, h = s:frame()              -- hidden and cleared, the size of the screen
--     screen.put(win, 1, 1, "Hello", "yellow", "gray")
--     s:show()                                 -- up it goes, all at once
--   end
--
-- A screen that finds its own monitor, picks its text scale once, and moves
-- to another monitor (or back to the terminal) when they come and go:
--
--   local s = screen.find({ scales = { 1, 0.5 }, minW = 40, fallback = term.current() })
--   -- on "peripheral" / "peripheral_detach":
--   if s:refresh() then ... end      -- true when it moved: s.name is the monitor's name, nil on the terminal
--   local x, y = s:clicked(ev)       -- a tap on its monitor, or a click when it's on the terminal
--
-- Turtles driving past and modems being placed fire peripheral events too;
-- refresh() leaves a monitor that is still there alone, so it's never
-- rescaled (which flashes it) for nothing. Nothing is needed on
-- monitor_resize / term_resize: the next frame() is made at the new size.
--
--   screen.find(opts)                opts: name (only this monitor), filter(name, monitor), scales (tried
--                                    largest first; default { 1 }), minW / minH (size the scale must fit),
--                                    fallback (drawn on when there's no monitor, e.g. term.current()),
--                                    setting (a settings key the player sets to a monitor's name, below),
--                                    named (only a monitor that setting names: none while it's unset)
--
-- Every computer on a wired network sees every monitor on it, so programs
-- sharing the storage cable could take each other's. With setting (e.g.
-- "smelter.monitor"), the player picks one: 'set smelter.monitor monitor_3'
-- (the name shows when its modem is right-clicked), or 'none' for no
-- monitor; unset, any free one is taken (none with named). It's read on
-- every refresh, so a change takes effect on the next peripheral event or
-- restart.
--   s.target, s.name                 what it draws on now (nil without a monitor or fallback), and the monitor's name
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
  local s = setmetatable({}, screen)
  s:setTarget(target)
  return s
end

function screen:setTarget(target)
  if target ~= self.target then
    self.target, self.win, self.last = target, nil, nil
    -- the terminal isn't a peripheral, so it has no name
    local ok, name = pcall(peripheral.getName, target)
    self.name = target and ok and name or nil
  end
end

function screen:size() return self.target.getSize() end

---------------------------------------------------------------- finding a monitor

function screen.find(opts)
  local s = setmetatable({ opts = opts or {} }, screen)
  if s.opts.setting then
    settings.define(s.opts.setting, { type = "string",
      description = "The monitor this program draws on (its network name, e.g. monitor_3), or none." })
  end
  s:refresh()
  return s
end

-- The monitor the player named for this screen (its setting, else opts.name),
-- false for none at all, or nil for any.
function screen:wanted()
  local o = self.opts
  if o.setting then
    local v = settings.get(o.setting)
    if v == "none" then return false end
    if type(v) == "string" and v ~= "" then return v end
    if o.named then return false end
  end
  return o.name
end

-- True when name is a monitor this screen may use.
function screen:fits(name)
  local o = self.opts
  if not (name and peripheral.isPresent(name) and peripheral.getType(name) == "monitor") then return false end
  local want = self:wanted()
  if want ~= nil then return name == want end
  return not o.filter or o.filter(name, peripheral.wrap(name)) and true or false
end

-- Look for the monitor again. Keeps the one it has while it's still there;
-- otherwise takes another (or the fallback) and sets its text scale. Returns
-- true when it moved.
function screen:refresh()
  local o = self.opts
  if not o then return false end
  if self.name and self:fits(self.name) then return false end
  local name
  local want = self:wanted()
  if want then
    if self:fits(want) then name = want end
  elseif want == nil then
    local mon = peripheral.find("monitor", function(n) return self:fits(n) end)
    name = mon and peripheral.getName(mon)
  end
  if name == nil and self.name == nil and self.target == o.fallback then return false end
  local target = name and peripheral.wrap(name) or o.fallback
  if name then
    -- largest text that still fits, set once for this monitor
    local scales = o.scales or { 1 }
    for _, scale in ipairs(scales) do
      target.setTextScale(scale)
      local w, h = target.getSize()
      if w >= (o.minW or 0) and h >= (o.minH or 0) then break end
    end
  end
  self:setTarget(target)
  return true
end

-- x, y when ev (a table of os.pullEvent results) taps this screen: a
-- monitor_touch on its monitor, or a mouse_click / mouse_drag when it's the
-- terminal. A third value is true for a drag.
function screen:clicked(ev)
  if not self.target then return nil end
  if ev[1] == "monitor_touch" then
    if self.name and ev[2] == self.name then return ev[3], ev[4], false end
  elseif (ev[1] == "mouse_click" or ev[1] == "mouse_drag") and not self.name then
    return ev[3], ev[4], ev[1] == "mouse_drag"
  end
end

---------------------------------------------------------------- drawing

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
