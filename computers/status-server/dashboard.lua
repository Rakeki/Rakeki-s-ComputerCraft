-- Dashboard for the status server: a card per computer, tap one for details
-- and recent activity.
local screen = require("lib.screen") -- flicker-free drawing
local dashboard = {}
dashboard.__index = dashboard

local CARD_W, CARD_H = 25, 7

local STATE_COLOR = {
  running = colors.lime, working = colors.lime, mining = colors.lime, digging = colors.lime,
  building = colors.lime, serving = colors.lime, sealing = colors.lime, farming = colors.lime,
  crafting = colors.lime, clearing = colors.lime, paving = colors.lime, surveying = colors.lime,
  restocking = colors.lightBlue, checking = colors.lightBlue, stuck = colors.orange,
  alert = colors.red,
  idle = colors.lightGray, starting = colors.lightGray, done = colors.green,
  waiting = colors.yellow, paused = colors.orange,
  docking = colors.lightBlue, returning = colors.lightBlue, traveling = colors.lightBlue, travelling = colors.lightBlue,
  unloading = colors.lightBlue,
  error = colors.red,
}

local put, fit = screen.put, screen.fit

local function ago(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

local function sortedIds(computers)
  local ids = {}
  for id in pairs(computers) do table.insert(ids, id) end
  table.sort(ids, function(a, b)
    local ca, cb = computers[a], computers[b]
    if ca.offline ~= cb.offline then return not ca.offline end -- online first
    local la, lb = (ca.label or ""):lower(), (cb.label or ""):lower()
    if la ~= lb then return la < lb end
    return a < b
  end)
  return ids
end

local function stateColor(c)
  if c.offline then return colors.gray end
  return STATE_COLOR[c.state] or colors.white
end

-- "219, 64, -341", marked when it's the turtle's own count rather than GPS
local function posText(c)
  if not c.pos then return nil end
  local text = ("%d, %d, %d"):format(c.pos.x, c.pos.y, c.pos.z)
  if c.posFrom == "tracked" then text = text .. " (tracked)" end
  return text
end

local POS_FROM = { gps = "GPS", fixed = "known spot (doesn't move)", tracked = "its own tracking" }

local function fuelText(c)
  if c.fuel == nil then return nil end
  if c.fuel == "unlimited" then return "fuel unlimited" end
  return "fuel " .. c.fuel
end

-- On the first monitor found, with the largest text that still fits two
-- columns of cards, else on this computer's screen.
function dashboard.new()
  local display = screen.find({ setting = "server.monitor", scales = { 1, 0.5 }, minW = CARD_W * 2 + 3,
    fallback = term.current() })
  -- self.win is the window the frame being drawn goes into (set by draw)
  return setmetatable({ display = display, page = 1, buttons = {} }, dashboard)
end

function dashboard:button(x, y, label, fg, bg, action)
  local text = " " .. label .. " "
  put(self.win, x, y, text, fg, bg)
  table.insert(self.buttons, { x1 = x, x2 = x + #text - 1, y = y, action = action })
  return x + #text + 1
end

function dashboard:drawCard(c, id, x, y, w, t)
  local win = self.win
  local bg = c.offline and colors.black or colors.gray
  local dim = c.offline and colors.gray or colors.lightGray
  for row = 0, CARD_H - 2 do put(win, x, y + row, string.rep(" ", w), colors.white, bg) end

  local idText = "#" .. id
  put(win, x + 1, y, fit(c.label or ("Computer " .. id), w - #idText - 3), c.offline and colors.gray or colors.white, bg)
  put(win, x + w - #idText - 1, y, idText, dim, bg)
  put(win, x + 1, y + 1, fit((c.role or "?") .. " \7 " .. (c.kind or "?"), w - 2), dim, bg)
  local stateText = c.offline and ("offline " .. ago(t - c.lastSeen)) or (c.state or "?")
  put(win, x + 1, y + 2, fit(stateText, w - 2), stateColor(c), bg)
  put(win, x + 1, y + 3, fit(c.detail or "", w - 2), c.offline and colors.gray or colors.white, bg)
  put(win, x + 1, y + 4, fit(posText(c) or "position unknown", w - 2), dim, bg)

  local bottom = fuelText(c) or ""
  if c.fuel and c.fuel ~= "unlimited" and c.fuelLimit and c.fuelLimit > 0 then
    -- small fuel bar
    local barW = 8
    local filled = math.floor(math.min(1, c.fuel / c.fuelLimit) * barW + 0.5)
    put(win, x + 1, y + 5, string.rep(" ", filled), colors.white, c.fuel < 500 and colors.red or colors.green)
    put(win, x + 1 + filled, y + 5, string.rep(" ", barW - filled), colors.white, colors.black)
    bottom = " " .. tostring(c.fuel)
    put(win, x + 1 + barW, y + 5, fit(bottom, w - barW - 7), dim, bg)
  else
    put(win, x + 1, y + 5, fit(bottom, w - 7), dim, bg)
  end
  if not c.offline then
    local seen = ago(t - c.lastSeen)
    put(win, x + w - #seen - 1, y + 5, seen, dim, bg)
  end
  table.insert(self.buttons, { x1 = x, x2 = x + w - 1, y1 = y, y2 = y + CARD_H - 2, action = function()
    self.selected = id
  end })
end

function dashboard:drawGrid(computers, t)
  local win = self.win
  local w, h = win.getSize()
  local ids = sortedIds(computers)
  local online = 0
  for _, id in ipairs(ids) do
    if not computers[id].offline then online = online + 1 end
  end

  local cols = math.max(1, math.floor((w - 1) / (CARD_W + 1)))
  local cardW = math.floor((w - 1) / cols) - 1 -- stretch cards to fill the width
  local rows = math.max(1, math.floor((h - 2) / CARD_H))
  local perPage = cols * rows
  local pages = math.max(1, math.ceil(#ids / perPage))
  self.page = math.min(self.page, pages)

  put(win, 1, 1, string.rep(" ", w), colors.white, colors.gray)
  local right = w -- header text stops before the pager
  if pages > 1 then
    local pageText = ("%d/%d"):format(self.page, pages)
    local x = w - #pageText - 8
    right = x - 1
    self:button(x, 1, "\27", colors.white, colors.lightGray, function() self.page = math.max(1, self.page - 1) end)
    put(win, x + 4, 1, pageText, colors.white, colors.gray)
    self:button(x + 5 + #pageText, 1, "\26", colors.white, colors.lightGray,
      function() self.page = math.min(pages, self.page + 1) end)
  end
  local counts = ("%d online, %d offline"):format(online, #ids - online)
  if 12 + #counts > right then counts = ("%d on, %d off"):format(online, #ids - online) end
  put(win, 2, 1, "Computers", colors.yellow, colors.gray)
  put(win, 12, 1, fit(counts, math.max(0, right - 12)), colors.lightGray, colors.gray)

  if #ids == 0 then
    put(win, 2, 3, "Waiting for computers to report in...", colors.lightGray, colors.black)
    put(win, 2, 5, "Add lib/report.lua to a computer and", colors.gray, colors.black)
    put(win, 2, 6, "call report.init() / report.set().", colors.gray, colors.black)
    return
  end

  local first = (self.page - 1) * perPage
  for i = 1, perPage do
    local id = ids[first + i]
    if not id then break end
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    self:drawCard(computers[id], id, 2 + col * (cardW + 1), 3 + row * CARD_H, cardW, t)
  end
end

function dashboard:drawDetail(c, id, t)
  local win = self.win
  local w, h = win.getSize()
  put(win, 1, 1, string.rep(" ", w), colors.white, colors.gray)
  local x = self:button(1, 1, "\27 Back", colors.white, colors.lightGray, function() self.selected = nil end)
  put(win, x, 1, fit(c.label or ("Computer " .. id), w - x - 9), colors.yellow, colors.gray)
  self:button(w - 7, 1, "Forget", colors.white, colors.red, function()
    self.selected = nil
    return { type = "forget", id = id }
  end)

  local y = 3
  local function row(name, value, color)
    if value == nil or y > h then return end
    put(win, 2, y, fit(name, 10), colors.lightGray, colors.black)
    put(win, 12, y, fit(value, w - 12), color or colors.white, colors.black)
    y = y + 1
  end
  row("ID", "#" .. id)
  row("Type", (c.kind or "?") .. ", " .. (c.role or "?"))
  row("State", c.offline and "offline" or c.state, stateColor(c))
  row("Doing", c.detail)
  row("Fuel", c.fuel and (tostring(c.fuel) .. (c.fuelLimit and c.fuel ~= "unlimited" and (" / " .. c.fuelLimit) or "")))
  row("Position", posText(c))
  row("From", c.pos and POS_FROM[c.posFrom or ""])
  row("Uptime", c.uptime and ago(c.uptime))
  row("Last seen", ago(t - c.lastSeen) .. " ago", c.offline and colors.red or nil)

  y = y + 1
  if y < h then
    put(win, 2, y, "Recent activity", colors.yellow, colors.black)
    y = y + 1
    for i = #c.events, 1, -1 do
      if y > h then break end
      local e = c.events[i]
      put(win, 2, y, os.date("%H:%M", math.floor(e.t)), colors.gray, colors.black)
      put(win, 8, y, fit(e.text, w - 8), colors.lightGray, colors.black)
      y = y + 1
    end
  end
end

-- Everything the frame shows, as text, so an unchanged frame isn't sent again.
function dashboard:key(computers, t)
  local parts = { tostring(self.selected), self.page }
  for _, id in ipairs(sortedIds(computers)) do
    local c = computers[id]
    local shown = { id, c.label, c.kind, c.role, c.state, c.detail, c.fuel, c.fuelLimit,
      posText(c), c.posFrom, c.offline, ago(t - c.lastSeen) }
    for i = 1, 12 do shown[i] = tostring(shown[i]) end
    table.insert(parts, table.concat(shown, "\0"))
  end
  local c = self.selected and computers[self.selected]
  if c then
    local last = c.events[#c.events]
    table.insert(parts, ("%s|%d|%s|%s"):format(tostring(c.uptime and ago(c.uptime)), #c.events,
      tostring(last and last.t), tostring(last and last.text)))
  end
  return table.concat(parts, "\1")
end

-- Called every second and on every message; a frame that would look the same
-- is skipped (the last frame's buttons still match it).
function dashboard:draw(computers, t)
  if self.selected and not computers[self.selected] then self.selected = nil end
  if self.display:same(self:key(computers, t)) then return end
  self.win = self.display:frame()
  self.buttons = {}
  if self.selected then
    self:drawDetail(computers[self.selected], self.selected, t)
  else
    self:drawGrid(computers, t)
  end
  self.display:show()
end

-- Returns an action for the server ({ type = "forget", id }) or nil.
function dashboard:click(x, y)
  for _, b in ipairs(self.buttons) do
    local y1, y2 = b.y1 or b.y, b.y2 or b.y
    if x >= b.x1 and x <= b.x2 and y >= y1 and y <= y2 then return b.action() end
  end
end

return dashboard
