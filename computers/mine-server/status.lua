-- Read-only status board for a monitor: job totals, every turtle's progress,
-- and recent events.
local screen = require("lib.screen") -- flicker-free drawing
local status = {}
status.__index = status

local OFFLINE_AFTER = 30

local STATE_COLOR = {
  mining = colors.lime,
  unloading = colors.lightBlue,
  waiting = colors.yellow,
  returning = colors.lightBlue,
  idle = colors.lightGray,
  paused = colors.orange,
  error = colors.red,
}

local put, pad = screen.put, screen.fit

-- On the monitor called monitorName, or (nil) any monitor that isn't the
-- map's, with the largest text that still fits a useful amount of information.
-- Draws nothing while there's no such monitor.
function status.new(monitorName, mapScreen)
  local display = screen.find({ name = monitorName, filter = function(name) return name ~= mapScreen.name end,
    scales = { 1.5, 1, 0.5 }, minW = 39, minH = 12 })
  return setmetatable({ display = display }, status)
end

function status:draw(m)
  if not self.display.target then return end
  local win, w, h = self.display:frame()

  put(win, 1, 1, string.rep(" ", w), colors.white, colors.gray)
  put(win, 2, 1, "AutoMine", colors.yellow, colors.gray)
  local mode = m.paused and "PAUSED" or "RUNNING"
  put(win, w - #mode, 1, mode, m.paused and colors.orange or colors.lime, colors.gray)

  -- totals
  local count = { queued = 0, active = 0, done = 0, player = 0 }
  for _, c in pairs(m.chunks) do count[c.state] = (count[c.state] or 0) + 1 end
  local ids, online = {}, 0
  for id, t in pairs(m.turtles) do
    table.insert(ids, id)
    if t.lastSeen and m.now - t.lastSeen < OFFLINE_AFTER then online = online + 1 end
  end
  table.sort(ids)

  local y = 3
  local x = 2
  for _, item in ipairs({
    { "Queued", count.queued, colors.yellow },
    { "Mining", count.active, colors.orange },
    { "Done", count.done, colors.green },
    { "Yours", count.player, colors.purple },
  }) do
    put(win, x, y, item[1] .. " ", colors.lightGray)
    put(win, x + #item[1] + 1, y, tostring(item[2]), item[3])
    x = x + #item[1] + #tostring(item[2]) + 3
  end
  y = y + 1
  put(win, 2, y, ("Turtles %d/%d online"):format(online, #ids), colors.lightGray)
  y = y + 2

  -- one row per turtle: name, state, chunk, progress bar, fuel
  local narrow = w < 50
  local nameW, stateW, chunkW, fuelW = narrow and 7 or 10, 9, narrow and 7 or 8, 6
  local barW = math.max(4, w - (2 + nameW + stateW + chunkW + fuelW + 5))
  for _, id in ipairs(ids) do
    if y > h - 3 then break end
    local t = m.turtles[id]
    local isOnline = t.lastSeen and m.now - t.lastSeen < OFFLINE_AFTER
    local st = isOnline and (t.state or "?") or "offline"
    local cx = 2
    put(win, cx, y, pad("#" .. id .. " " .. (t.label or ""), nameW), isOnline and colors.white or colors.gray)
    cx = cx + nameW + 1
    put(win, cx, y, pad(st, stateW), isOnline and (STATE_COLOR[st] or colors.white) or colors.gray)
    cx = cx + stateW + 1
    put(win, cx, y, pad(t.job and (t.job.cx .. "," .. t.job.cz) or "-", chunkW), colors.lightGray)
    cx = cx + chunkW + 1
    if t.progress then
      local filled = math.floor(t.progress * barW + 0.5)
      put(win, cx, y, string.rep(" ", filled), colors.white, colors.green)
      put(win, cx + filled, y, string.rep(" ", barW - filled), colors.white, colors.gray)
      local pct = math.floor(t.progress * 100) .. "%"
      put(win, cx + math.floor((barW - #pct) / 2), y, pct, colors.white,
        math.floor((barW - #pct) / 2) < filled and colors.green or colors.gray)
    end
    cx = cx + barW + 1
    put(win, cx, y, pad(tostring(t.fuel or "?"), fuelW), (tonumber(t.fuel) or math.huge) < 500 and colors.red or colors.lightGray)
    y = y + 1
    if isOnline and t.state == "error" and t.msg and y <= h - 3 then
      put(win, 4, y, pad(t.msg, w - 4), colors.red)
      y = y + 1
    end
  end
  if #ids == 0 then
    put(win, 2, y, "No turtles yet", colors.gray)
    y = y + 1
  end

  -- recent events fill whatever space is left, newest first
  y = y + 1
  if y < h then
    put(win, 2, y, "Recent", colors.yellow)
    y = y + 1
    for i = #m.events, 1, -1 do
      if y > h then break end
      local e = m.events[i]
      put(win, 2, y, os.date("%H:%M", math.floor(e.t)) .. " ", colors.gray)
      put(win, 8, y, pad(e.text, w - 8), colors.lightGray)
      y = y + 1
    end
  end

  self.display:show()
end

return status
