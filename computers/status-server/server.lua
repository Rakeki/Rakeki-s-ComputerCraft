-- Status server: collects status broadcasts from every computer using
-- lib/report.lua and shows them on a monitor (or this computer's screen).
local dashboard = require("dashboard")
local errlog = require("lib.errlog") -- saves errors to /errors.log
local net = require("lib.net") -- opening modems
local files = require("lib.files") -- crash-safe save files

local PROTOCOL = "cc_status"
local STATE_FILE = "/.status_state"
local OFFLINE_AFTER = 30 -- seconds without a heartbeat
local SAVE_INTERVAL = 30
local MAX_EVENTS = 25
local REDRAW_GAP = 0.5 -- seconds a status waits to be drawn: with many computers reporting, a burst draws once

-- computers: id -> { label, kind, role, state, detail, fuel, fuelLimit, pos,
--                    uptime, lastSeen, offline, events = { { t, text } } }
local computers = {}
local saveDue, lastSave = false, 0

local function now() return os.epoch("utc") / 1000 end

local function save()
  files.write(STATE_FILE, computers)
  saveDue, lastSave = false, now()
end

local function load()
  local s = files.read(STATE_FILE)
  if s then computers = s end
end

local function addEvent(c, text)
  table.insert(c.events, { t = now(), text = text })
  while #c.events > MAX_EVENTS do table.remove(c.events, 1) end
end

local function receive(id, msg)
  local c = computers[id]
  if not c then
    c = { events = {} }
    computers[id] = c
    addEvent(c, "first seen")
  elseif c.offline then
    addEvent(c, "back online")
  end
  for _, k in ipairs({ "label", "kind", "role", "state", "detail", "fuel", "fuelLimit", "uptime" }) do
    c[k] = msg[k]
  end
  -- keep the last known position if a message doesn't include one
  if msg.pos then c.pos, c.posFrom = msg.pos, msg.posFrom end
  if msg.event then addEvent(c, msg.event) end
  c.lastSeen, c.offline = now(), false
  saveDue = true
end

local function checkOffline()
  for _, c in pairs(computers) do
    if not c.offline and now() - c.lastSeen > OFFLINE_AFTER then
      c.offline = true
      addEvent(c, "went offline")
      saveDue = true
    end
  end
end

---------------------------------------------------------------- main

load()
require("lib.label").set("Status")
if not net.open("any") then error("Attach a wireless or ender modem", 0) end

local view = dashboard.new()

-- With the dashboard on a monitor, this computer's screen says where it is
-- and shows any errors.
local function announce()
  if not view.display.name then return end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Status server running. Dashboard is on monitor " .. view.display.name .. ".")
end
announce()

local function apply(action)
  if action and action.type == "forget" then
    computers[action.id] = nil
    save()
  end
end

local function handle(ev)
  local name = ev[1]
  local x, y, drag = view.display:clicked(ev)
  if name == "rednet_message" and ev[4] == PROTOCOL then
    if type(ev[3]) == "table" and ev[3].type == "status" then receive(ev[2], ev[3]) end
  elseif x and not drag then
    apply(view:click(x, y))
  elseif name == "peripheral" or name == "peripheral_detach" then
    if name == "peripheral" then net.open("any") end -- a modem that attached after boot
    -- also fired by turtles driving past: only acts if the monitor came or went
    if view.display:refresh() then announce() end
  end
end

-- Drawn every second, at once for taps and the monitor coming or going, and
-- REDRAW_GAP after a status. Not on every event: every rednet message heard
-- (two events each) redrew the whole grid, which kept a busy base's
-- dashboard working all the time and slowed the computers around it.
local timer, soon = os.startTimer(1), nil
view:draw(computers, now())
while true do
  local ev = { os.pullEvent() }
  local redraw = false
  if ev[1] == "timer" and ev[2] == timer then
    checkOffline()
    if saveDue and now() - lastSave > SAVE_INTERVAL then save() end
    timer, redraw = os.startTimer(1), true
  elseif ev[1] == "timer" and ev[2] == soon then
    soon, redraw = nil, true
  elseif ev[1] ~= "timer" then
    -- one bad message or touch shouldn't take the dashboard down
    local ok, err = errlog.pcall(handle, ev)
    if not ok and view.display.name then print("Error: " .. tostring(err)) end
    if ev[1] == "rednet_message" then
      if ev[4] == PROTOCOL then soon = soon or os.startTimer(REDRAW_GAP) end
    elseif ev[1] ~= "modem_message" then
      redraw = true -- taps, the monitor, the terminal
    end
  end
  if redraw then
    local ok, err = errlog.pcall(view.draw, view, computers, now())
    if not ok and view.display.name then print("Display error: " .. tostring(err)) end
  end
end
