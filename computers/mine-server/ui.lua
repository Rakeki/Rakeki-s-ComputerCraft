-- Chunk map and turtle panel for the AutoMine server. Draws to a terminal or
-- monitor and turns clicks into actions for server.lua.
local screen = require("lib.screen") -- flicker-free drawing
local ui = {}
ui.__index = ui

local STYLE = {
  none = { fg = colors.gray, bg = colors.black },
  queued = { fg = colors.black, bg = colors.yellow },
  active = { fg = colors.black, bg = colors.orange },
  done = { fg = colors.black, bg = colors.green },
  player = { fg = colors.white, bg = colors.purple },
  base = { fg = colors.white, bg = colors.blue },
}

-- Bottom-bar tools: tap one, then tap (or drag across) chunks on the map.
local BRUSHES = {
  { id = "look", label = "Look" },
  { id = "queued", label = "Queue" },
  { id = "player", label = "Me" },
  { id = "none", label = "Clear" },
  { id = "done", label = "Done" },
}

local PANEL_W = 20
local OFFLINE_AFTER = 30

local put = screen.put

local function chunkOf(p) return math.floor(p.x / 16), math.floor(p.z / 16) end

-- The map on the monitor named in config (small text, so it shows plenty of
-- chunks), else on this computer's screen.
function ui.new(monitorName)
  local display = monitorName and screen.find({ name = monitorName, scales = { 0.5 }, fallback = term.current() })
    or screen.new(term.current())
  -- self.win is the window the frame being drawn goes into (set by draw)
  return setmetatable({ display = display, viewX = 0, viewZ = 0, brush = "look", buttons = {} }, ui)
end

function ui:layout()
  local w, h = self.display:size()
  local panelW = w >= 40 and PANEL_W or 0
  return { w = w, h = h, panelX = w - panelW + 1, panelW = panelW, cols = math.floor((w - panelW) / 2), rows = h - 2 }
end

-- Chunk shown at map cell (col, row), both 0-based. North is up.
function ui:chunkAt(L, col, row)
  return self.viewX - math.floor(L.cols / 2) + col, self.viewZ - math.floor(L.rows / 2) + row
end

function ui:button(x, y, label, fg, bg, action)
  local text = " " .. label .. " "
  put(self.win, x, y, text, fg, bg)
  table.insert(self.buttons, { x1 = x, x2 = x + #text - 1, y = y, action = action })
  return x + #text + 1
end

function ui:pan(dx, dz)
  local L = self:layout()
  local step = math.max(1, math.floor(math.min(L.cols, L.rows) / 3))
  self.viewX, self.viewZ = self.viewX + dx * step, self.viewZ + dz * step
end

function ui:draw(m)
  local win = self.display:frame()
  local L = self:layout()
  self.win = win
  self.buttons = {}

  local queue = {}
  for k, c in pairs(m.chunks) do
    if c.state == "queued" then table.insert(queue, { k = k, order = c.order }) end
  end
  table.sort(queue, function(a, b) return a.order < b.order end)
  local rank = {}
  for i, q in ipairs(queue) do rank[q.k] = i end

  local turtleAt = {}
  for id, t in pairs(m.turtles) do
    if t.pos then
      local cx, cz = chunkOf(t.pos)
      turtleAt[cx .. "," .. cz] = id
    end
  end

  -- header
  put(win, 1, 1, string.rep(" ", L.w), colors.white, colors.gray)
  put(win, 2, 1, "AutoMine", colors.yellow, colors.gray)
  if m.paused then put(win, 11, 1, "PAUSED", colors.red, colors.gray) end
  local x = L.w - 20
  x = self:button(x, 1, "\27", colors.white, colors.lightGray, function() self:pan(-1, 0) end)
  x = self:button(x, 1, "\24", colors.white, colors.lightGray, function() self:pan(0, -1) end)
  x = self:button(x, 1, "\25", colors.white, colors.lightGray, function() self:pan(0, 1) end)
  x = self:button(x, 1, "\26", colors.white, colors.lightGray, function() self:pan(1, 0) end)
  self:button(x, 1, "HQ", colors.white, colors.blue, function()
    if m.baseCx then self.viewX, self.viewZ = m.baseCx, m.baseCz end
  end)

  -- map
  for row = 0, L.rows - 1 do
    for col = 0, L.cols - 1 do
      local cx, cz = self:chunkAt(L, col, row)
      local k = cx .. "," .. cz
      local c = m.chunks[k]
      local style, label
      if m.homeChunks[k] then
        style, label = STYLE.base, "HQ"
      elseif not c then
        style, label = STYLE.none, " \183"
      elseif c.state == "queued" then
        style, label = STYLE.queued, rank[k] < 100 and string.format("%2d", rank[k]) or "++"
      elseif c.state == "active" then
        style, label = STYLE.active, string.format("%2d", c.turtle % 100)
      elseif c.state == "player" then
        style, label = STYLE.player, "Me"
      else
        style, label = STYLE.done, "  "
      end
      if turtleAt[k] and style ~= STYLE.base and style ~= STYLE.active then
        label = "T" .. (turtleAt[k] % 10)
      end
      local fg, bg = style.fg, style.bg
      if self.selected and self.selected[1] == cx and self.selected[2] == cz then
        fg, bg = colors.black, colors.white
      end
      put(win, col * 2 + 1, row + 2, label, fg, bg)
    end
  end

  -- side panel
  if L.panelW > 0 then
    local y = 2
    local function line(text, fg)
      if y > L.h - 1 then return end
      put(win, L.panelX, y, (" " .. text):sub(1, L.panelW), fg or colors.white, colors.black)
      y = y + 1
    end

    if not m.baseCx then
      line("No miners home yet.", colors.orange)
      line("Place one with a", colors.orange)
      line("chest behind it.", colors.orange)
      line("")
    end

    if self.selected then
      local cx, cz = self.selected[1], self.selected[2]
      local c = m.chunks[cx .. "," .. cz]
      line("Chunk " .. cx .. "," .. cz, colors.yellow)
      line(("x %d..%d"):format(cx * 16, cx * 16 + 15), colors.lightGray)
      line(("z %d..%d"):format(cz * 16, cz * 16 + 15), colors.lightGray)
      if m.homeChunks[cx .. "," .. cz] then
        line(("Home of #%d"):format(m.homeChunks[cx .. "," .. cz]))
      elseif not c then
        line("Not planned")
      elseif c.state == "queued" then
        line("Queued #" .. rank[cx .. "," .. cz])
      elseif c.state == "active" then
        line(("Turtle #%d %d%%"):format(c.turtle, math.floor((c.progress or 0) * 100)))
      elseif c.state == "player" then
        line("Reserved for you", colors.purple)
      else
        line("Mined", colors.green)
      end
    else
      line("Tap a chunk", colors.lightGray)
    end
    line("")

    local ids = {}
    for id in pairs(m.turtles) do table.insert(ids, id) end
    table.sort(ids)
    line(("Turtles (%d)"):format(#ids), colors.yellow)
    for _, id in ipairs(ids) do
      local t = m.turtles[id]
      local online = t.lastSeen and m.now - t.lastSeen < OFFLINE_AFTER
      line(("#%d %s"):format(id, t.label or ""), online and colors.white or colors.gray)
      local detail = online and (t.state or "?") or "offline"
      if t.job then detail = detail .. " " .. t.job.cx .. "," .. t.job.cz end
      if t.progress then detail = detail .. (" %d%%"):format(math.floor(t.progress * 100)) end
      line(" " .. detail, colors.lightGray)
      if online and t.state == "error" and t.msg then line(" " .. t.msg, colors.red) end
      line(" fuel " .. tostring(t.fuel or "?"), colors.lightGray)
    end
    line("")

    -- chunks marked "Me": the ones you said you'd mine yourself
    local mine = {}
    for _, c in pairs(m.chunks) do
      if c.state == "player" then table.insert(mine, c) end
    end
    table.sort(mine, function(a, b) return a.cx == b.cx and a.cz < b.cz or a.cx < b.cx end)
    line(("Your chunks (%d)"):format(#mine), colors.purple)
    for _, c in ipairs(mine) do
      line(("%d,%d  x%d z%d"):format(c.cx, c.cz, c.cx * 16, c.cz * 16))
    end
  end

  -- bottom bar
  put(win, 1, L.h, string.rep(" ", L.w), colors.white, colors.gray)
  local bx = 1
  for _, b in ipairs(BRUSHES) do
    local on = self.brush == b.id
    bx = self:button(bx, L.h, b.label, on and colors.black or colors.white, on and colors.white or colors.gray,
      function() self.brush = b.id end)
  end
  local label = m.paused and "Resume" or "Pause"
  self:button(L.w - #label - 1, L.h, label, colors.white, m.paused and colors.green or colors.red,
    function() return { type = "togglePause" } end)

  self.display:show()
end

-- Returns an action for the server ({type = "paint" | "togglePause"}) or nil.
function ui:click(x, y, isDrag)
  if not isDrag then
    for _, b in ipairs(self.buttons) do
      if y == b.y and x >= b.x1 and x <= b.x2 then return b.action() end
    end
  end
  local L = self:layout()
  if y >= 2 and y <= L.rows + 1 and x <= L.cols * 2 then
    local cx, cz = self:chunkAt(L, math.floor((x - 1) / 2), y - 2)
    self.selected = { cx, cz }
    if self.brush ~= "look" then return { type = "paint", cx = cx, cz = cz, state = self.brush } end
  end
end

function ui:key(k)
  if k == keys.left or k == keys.a then self:pan(-1, 0)
  elseif k == keys.right or k == keys.d then self:pan(1, 0)
  elseif k == keys.up or k == keys.w then self:pan(0, -1)
  elseif k == keys.down or k == keys.s then self:pan(0, 1)
  end
end

return ui
