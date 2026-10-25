-- Status server: collects status broadcasts from every computer using
-- lib/report.lua and shows them on a monitor (or this computer's screen).
local dashboard = require("dashboard")
local errlog = require("lib.errlog") -- saves errors to /errors.log

local PROTOCOL = "cc_status"
local STATE_FILE = "/.status_state"
local OFFLINE_AFTER = 30 -- seconds without a heartbeat
local SAVE_INTERVAL = 30
local MAX_EVENTS = 25

-- computers: id -> { label, kind, role, state, detail, fuel, fuelLimit, pos,
--                    uptime, lastSeen, offline, events = { { t, text } } }
local computers = {}
local saveDue, lastSave = false, 0

local function now() return os.epoch("utc") / 1000 end

local function save()
  local tmp = STATE_FILE .. ".tmp"
  local f = fs.open(tmp, "w")
  f.write(textutils.serialize(computers))
  f.close()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
  fs.move(tmp, STATE_FILE)
  saveDue, lastSave = false, now()
end

local function load()
  for _, path in ipairs({ STATE_FILE, STATE_FILE .. ".tmp" }) do
    if fs.exists(path) then
      local f = fs.open(path, "r")
      local s = textutils.unserialize(f.readAll())
      f.close()
      if s then
        computers = s
        return
      end
    end
  end
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
peripheral.find("modem", rednet.open)
if not rednet.isOpen() then error("Attach a wireless or ender modem", 0) end

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
    -- also fired by turtles driving past: only acts if the monitor came or went
    if view.display:refresh() then announce() end
  end
end

local timer = os.startTimer(1)
view:draw(computers, now())
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == timer then
    checkOffline()
    if saveDue and now() - lastSave > SAVE_INTERVAL then save() end
    timer = os.startTimer(1)
  else
    -- one bad message or touch shouldn't take the dashboard down
    local ok, err = errlog.pcall(handle, ev)
    if not ok and view.display.name then print("Error: " .. tostring(err)) end
  end
  local ok, err = errlog.pcall(view.draw, view, computers, now())
  if not ok and view.display.name then print("Display error: " .. tostring(err)) end
end
