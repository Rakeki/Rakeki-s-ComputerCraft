-- Control panel for the blueprint projector: buttons to move, turn and step
-- through the projected building, a top-down map of the current layer and
-- the blocks it needs. Draws to a monitor or the computer's own screen and
-- turns clicks into action names for projector.lua.
local screen = require("lib.screen") -- flicker-free drawing
local ui = {}
ui.__index = ui

local MIN_W, MIN_H = 32, 16 -- smallest panel with the buttons and a few rows of map
local COUNTS_W = 18         -- block list beside the map, when there's room
local VIEW_LABEL = { whole = "Whole", layer = "Layer", outline = "Outline" }

local put, fit = screen.put, screen.fit

-- On the first advanced (colour) monitor found, with the largest text that
-- still fits the panel, else on this computer's screen.
function ui.new()
  local display = screen.find({ setting = "projector.monitor", filter = function(_, m) return m.isColor() end,
    scales = { 1, 0.5 }, minW = MIN_W, minH = MIN_H, fallback = term.current() })
  -- self.win is the window the panel being drawn goes into (set by draw)
  return setmetatable({ display = display, buttons = {} }, ui)
end

function ui:button(x, y, label, action, fg, bg)
  local text = " " .. label .. " "
  put(self.win, x, y, text, fg or colors.black, bg or colors.lightGray)
  table.insert(self.buttons, { x1 = x, x2 = x + #text - 1, y = y, action = action })
  return x + #text + 1
end

function ui:label(x, y, text, fg)
  put(self.win, x, y, text, fg or colors.lightGray, colors.black)
  return x + #text
end

function ui:click(x, y)
  for _, b in ipairs(self.buttons) do
    if y == b.y and x >= b.x1 and x <= b.x2 then return b.action end
  end
end

-- Top-down map of the layer, north up, cropped around the middle if the
-- building is bigger than the space.
function ui:drawMap(m, x0, y0, cols, rows)
  local map = m.map
  local cropX = math.max(0, math.floor((map.w - cols) / 2))
  local cropZ = math.max(0, math.floor((map.d - rows) / 2))
  for row = 1, math.min(rows, map.d) do
    local z = row + cropZ
    for col = 1, math.min(cols, map.w) do
      local x = col + cropX
      local mat = map.cells[z][x]
      if mat then
        put(self.win, x0 + col - 1, y0 + row - 1, mat.char, mat.light and colors.black or colors.white, mat.term)
      elseif map.below[z][x] then
        put(self.win, x0 + col - 1, y0 + row - 1, "\183", colors.lightGray, colors.gray)
      else
        put(self.win, x0 + col - 1, y0 + row - 1, " ", colors.white, colors.gray)
      end
    end
  end
end

function ui:drawCounts(m, x0, y0, width, rows)
  put(self.win, x0, y0, fit(m.countTitle, width), colors.yellow, colors.black)
  for i, c in ipairs(m.counts) do
    if i >= rows then break end
    local name = c.mat.block:gsub("^.-:", ""):gsub("%[.*$", "")
    local n = tostring(c.n)
    put(self.win, x0, y0 + i, c.mat.char, c.mat.light and colors.black or colors.white, c.mat.term)
    put(self.win, x0 + 2, y0 + i, fit(name, width - #n - 3), colors.white, colors.black)
    put(self.win, x0 + width - #n, y0 + i, n, colors.lightGray, colors.black)
  end
end

function ui:draw(m)
  local s = m.state
  local win, w, h = self.display:frame()
  self.win = win
  self.buttons = {}

  -- header: which plan, and arrows to change it
  put(win, 1, 1, string.rep(" ", w), colors.white, colors.gray)
  self:button(1, 1, "\17", "prevPlan", colors.white, colors.lightGray)
  local count = (" %d/%d"):format(m.index, m.planCount)
  put(win, 5, 1, fit(m.plan.name, w - 9 - #count), colors.yellow, colors.gray)
  put(win, w - 4 - #count, 1, count, colors.lightGray, colors.gray)
  self:button(w - 2, 1, "\16", "nextPlan", colors.white, colors.lightGray)

  put(win, 1, 2, fit((" X %d  Y %d  Z %d   front faces %s"):format(s.x, s.y, s.z, m.facing), w), colors.lightGray, colors.black)

  local x = self:label(2, 4, "Move ")
  x = self:button(x, 4, "N", "north")
  x = self:button(x, 4, "S", "south")
  x = self:button(x, 4, "W", "west")
  x = self:button(x, 4, "E", "east")
  x = self:label(x, 4, "Step ")
  self:button(x, 4, tostring(s.step), "step", colors.white, colors.blue)

  x = self:label(2, 5, "     ")
  x = self:button(x, 5, "Up", "up")
  x = self:button(x, 5, "Down", "down")
  x = self:label(x, 5, "Turn ")
  x = self:button(x, 5, "\27", "turnLeft")
  self:button(x, 5, "\26", "turnRight")

  x = self:label(2, 6, "View ")
  x = self:button(x, 6, VIEW_LABEL[s.view], "view", colors.white, colors.cyan)
  x = self:label(x, 6, "Layer ")
  x = self:button(x, 6, "-", "layerDown")
  x = self:label(x, 6, ("%d/%d "):format(s.layer, m.plan.h), colors.white)
  self:button(x, 6, "+", "layerUp")

  x = self:button(7, 7, "Here", "here", colors.white, colors.blue)
  if s.hidden then
    x = self:button(x, 7, "Show", "hide", colors.white, colors.green)
  else
    x = self:button(x, 7, "Hide", "hide", colors.white, colors.red)
  end
  -- a builder turtle builds it where it's shown
  if m.building then
    self:button(x, 7, "Stop", "build", colors.white, colors.red)
  elseif m.canBuild then
    self:button(x, 7, "Build", "build", colors.white, colors.green)
  end

  put(win, 2, 9, fit(m.status.text, w - 2), m.status.color, colors.black)
  if m.note then put(win, 2, 10, fit(m.note, w - 2), colors.orange, colors.black) end

  -- the layer: map, and the blocks it needs beside it or underneath
  local top = m.note and 12 or 11
  put(win, 2, top, fit(("Layer %d, north is up"):format(s.layer), w - 2), colors.yellow, colors.black)
  local rows = h - top
  local side = w - 2 - math.min(m.map.w, w - 2) >= COUNTS_W + 2
  if side then
    local cols = math.min(m.map.w, w - COUNTS_W - 4)
    self:drawMap(m, 2, top + 1, cols, rows)
    self:drawCounts(m, cols + 4, top + 1, w - cols - 4, rows)
  else
    local mapRows = math.min(m.map.d, math.max(3, rows - #m.counts - 2))
    self:drawMap(m, 2, top + 1, w - 2, mapRows)
    if rows - mapRows >= 3 then self:drawCounts(m, 2, top + mapRows + 2, w - 2, rows - mapRows - 1) end
  end

  self.display:show()
end

return ui
