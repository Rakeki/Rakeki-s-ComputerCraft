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
--                                    setting (a settings key the player sets to a monitor's name, below)
--
-- Every computer on a wired network sees every monitor on it, so programs
-- sharing the storage cable could take each other's. With setting (e.g.
-- "smelter.monitor"), the player picks one: 'set smelter.monitor monitor_3'
-- (the name shows when its modem is right-clicked), or 'none' for no
-- monitor; unset, a monitor touching the computer is taken first (it's
-- most likely this program's), else the first one on the cable. It's read on every refresh, so a change takes effect on the
-- next peripheral event or restart. screen.choose(setting) asks the player
-- to pick one from a list (a '<program> monitor' command).
--   s.target, s.name                 what it draws on now (nil without a monitor or fallback), and the monitor's name
--   s:setTarget(t)                   draw on another monitor from now on
--   s:size()                         the screen's size now
--   screen.put(t, x, y, text, fg, bg) write text; colours are names ("lime") or numbers (colors.lime), bg black if left out
--   screen.fit(text, w)              cut or pad text to exactly w characters
--   screen.wrap(text, w, most)       text in lines of up to w characters, broken at spaces (most: line limit)
--   screen.tiles(t, w, top, bottom, tiles, minW)  a status board: a coloured tile per { title, text, bg, fg }
--   screen.legend(t, x, y, w, { { colour, word }, ... })  what the tile colours mean, on one row
--   screen.choose(setting, arg)      pick a monitor from every one on the network (arg: a name, number or
--                                    'none' given on the command line); saves it, returns it or nil
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

-- Lists every monitor this computer can see and saves the one the player
-- picks (or 'none') in setting. arg skips the question. Returns the choice,
-- or nil when it was left as it was.
function screen.choose(setting, arg)
  local names = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "monitor" then names[#names + 1] = n end
  end
  table.sort(names)
  local now = settings.get(setting)
  if not arg then
    if #names == 0 then
      print("I can't see a monitor. Put a wired modem on one, join it to my cable and right-click the modem so it turns red.")
      return nil
    end
    print(("Monitors I can see (now: %s):"):format(now or "not picked"))
    for i, n in ipairs(names) do
      print(("  %d. %s%s%s"):format(i, n, onSide(n) and " (touching me)" or "", n == now and " <- this one" or ""))
    end
    print("Right-click a monitor's modem to see its name. Pick a number or name, 'none' for no monitor, Enter to keep it:")
    write("> ")
    arg = read()
    if arg == "" then return nil end
  end
  local pick = names[tonumber(arg) or 0] or arg
  if pick ~= "none" and not (peripheral.isPresent(pick) and peripheral.getType(pick) == "monitor") then
    print(("%s isn't a monitor I can see."):format(pick))
    return nil
  end
  settings.set(setting, pick)
  settings.save()
  return pick
end

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
  end
  return o.name
end

local function onSide(name)
  for _, side in ipairs(rs.getSides()) do
    if side == name then return true end
  end
  return false
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
    -- one touching this computer first: one on the cable may be another program's
    for _, side in ipairs(rs.getSides()) do
      if not name and self:fits(side) then name = side end
    end
    local mon = not name and peripheral.find("monitor", function(n) return self:fits(n) end)
    name = name or mon and peripheral.getName(mon)
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

-- A status board: one coloured tile per machine, { title, text, bg, fg
-- (default black) }, in a grid from row top to row bottom of t (w wide).
-- Each tile is 3 rows high (title, text, blank) and at least minW wide,
-- stretched to fill the width. Returns how many didn't fit.
function screen.tiles(t, w, top, bottom, tiles, minW)
  minW = minW or 12
  local cols = math.max(1, math.floor((w + 1) / (minW + 1)))
  local tileW = math.floor((w + 1) / cols) - 1
  local rows = math.floor((bottom - top + 2) / 4)
  for i, tile in ipairs(tiles) do
    local row, col = math.floor((i - 1) / cols), (i - 1) % cols
    if row >= rows then return #tiles - i + 1 end
    local x, y, fg = 1 + col * (tileW + 1), top + row * 4, tile[4] or "black"
    screen.put(t, x, y, screen.fit(" " .. tile[1], tileW), fg, tile[3])
    screen.put(t, x, y + 1, screen.fit(" " .. (tile[2] or ""), tileW), fg, tile[3])
    screen.put(t, x, y + 2, (" "):rep(tileW), fg, tile[3])
  end
  return 0
end

-- What the tile colours mean, on one row of t from x: { colour, word } pairs.
function screen.legend(t, x, y, w, keys)
  local right = x + w
  for _, p in ipairs(keys) do
    if x + #p[2] + 2 > right then return end
    screen.put(t, x, y, " ", "black", p[1])
    screen.put(t, x + 2, y, p[2], "lightGray")
    x = x + #p[2] + 4
  end
end

-- text in lines of at most w characters, broken at spaces where it can,
-- and at most most lines (the last one is cut by fit when drawn)
function screen.wrap(text, w, most)
  text, most = tostring(text or ""), most or math.huge
  local lines = {}
  while #text > w and #lines < most - 1 do
    local cut = text:sub(1, w + 1):match("^.*() ")
    if not cut or cut <= 1 then cut = w + 1 end
    lines[#lines + 1] = text:sub(1, cut - 1)
    text = text:sub(cut):gsub("^ +", "")
  end
  lines[#lines + 1] = text
  return lines
end

return screen
