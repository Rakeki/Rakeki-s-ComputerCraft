-- Reports this computer's status to the status server (computers/status-server).
-- Works on any computer, turtle or pocket computer with a wireless or ender modem;
-- without one it quietly does nothing.
--
--   local report = require("lib.report")
--   report.init("wheat farm")                    -- what this computer is for
--   report.set("harvesting", "row 3 of 8")       -- state + what it's doing right now
--   report.log("chest full")                     -- one-off event for the activity list
--   parallel.waitForAny(main, report.loop)       -- keep reporting while main runs
--
-- report.set can be called as often as you like; it only sends when something
-- changed (at most every 2 seconds) or every 10 seconds as a heartbeat.
--
-- Position: pass { pos = { x, y, z } } to report.set if the program tracks its
-- own (turtles do), adding posFrom = "fixed" if it never moves. Otherwise
-- report.init and report.loop fill it in from GPS, if there is one.
local report = {}

local PROTOCOL = "cc_status"
local HEARTBEAT = 10
local MIN_GAP = 2
local CALLER_POS_FRESH = 30 -- trust a position the program gave us for this long
local STILL_GPS_EVERY = 300 -- computers don't move; re-check GPS rarely

local info = { role = "computer", state = "starting" }
local fields = {}
local pendingEvent
local lastSent, changed = -math.huge, true
local callerPosAt, gpsAt = -math.huge, -math.huge

local function kind()
  if turtle then return "turtle" elseif pocket then return "pocket" end
  return "computer"
end

local function modemReady()
  if rednet.isOpen() then return true end
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then return false end
  rednet.open(peripheral.getName(modem))
  return true
end

local function send()
  if not modemReady() then return end
  local msg = {
    type = "status",
    label = os.getComputerLabel(),
    kind = kind(),
    role = info.role,
    state = info.state,
    detail = info.detail,
    event = pendingEvent,
    uptime = os.clock(),
  }
  if turtle then
    msg.fuel = turtle.getFuelLevel()
    msg.fuelLimit = turtle.getFuelLimit()
  end
  for k, v in pairs(fields) do msg[k] = v end
  rednet.broadcast(msg, PROTOCOL)
  pendingEvent, changed, lastSent = nil, false, os.clock()
end

-- Fill in the position from GPS, unless the program is giving us one.
-- Turtles move, so they ask every heartbeat; computers only now and then.
local function updateGpsPosition()
  if os.clock() - callerPosAt < CALLER_POS_FRESH then return end
  if not turtle and fields.posFrom == "gps" and os.clock() - gpsAt < STILL_GPS_EVERY then return end
  if not modemReady() then return end
  local x, y, z = gps.locate(1)
  if x then
    fields.pos = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
    fields.posFrom = "gps"
    gpsAt = os.clock()
  end
end

-- role: short description of what this computer is for, e.g. "auto miner".
function report.init(role)
  info.role = role
  updateGpsPosition()
  send()
end

-- state: one word like "mining", "idle", "error". detail: what it's doing.
-- extra: optional table of fields to show, e.g. { pos = { x = 1, y = 2, z = 3 } }.
function report.set(state, detail, extra)
  if state ~= info.state then
    pendingEvent = state .. (detail and (": " .. detail) or "")
    changed = true
  end
  if detail ~= info.detail then changed = true end
  info.state, info.detail = state, detail
  if extra then
    for k, v in pairs(extra) do fields[k] = v end
    if extra.pos then
      fields.posFrom = extra.posFrom or "tracked"
      -- "fixed" (a computer that knows exactly where it is) never needs GPS
      callerPosAt = fields.posFrom == "fixed" and math.huge or os.clock()
    end
  end
  local since = os.clock() - lastSent
  if pendingEvent or (changed and since >= MIN_GAP) or since >= HEARTBEAT then send() end
end

-- Add a line to this computer's activity list on the status server.
function report.log(text)
  pendingEvent = text
  send()
end

-- Heartbeat loop for parallel.waitForAny/waitForAll, so the computer keeps
-- showing as online while the main program is busy.
function report.loop()
  while true do
    sleep(HEARTBEAT / 2)
    updateGpsPosition()
    if os.clock() - lastSent >= HEARTBEAT or changed then send() end
  end
end

return report
