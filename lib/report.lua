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
--
-- Updates: each report carries the versions of the programs installed here
-- (/.installed_versions), and report.loop answers the update watcher
-- (computers/update-watcher) on cc_update: asked to "update", it runs
-- 'install boot' out of sight and reboots if anything changed. A program
-- with its own event loop instead of report.loop passes each event to
-- report.handle(ev). 'set install.remote false' (or install.autoupdate
-- false) makes this computer say no.
local report = {}

local PROTOCOL = "cc_status"
local HEARTBEAT = 10
local MIN_GAP = 2
local CALLER_POS_FRESH = 30 -- trust a position the program gave us for this long
local STILL_GPS_EVERY = 300 -- computers don't move; re-check GPS rarely
local UPDATE_PROTOCOL = "cc_update" -- the update watcher asks on this
local VERSIONS_FILE = "/.installed_versions" -- written by the installer: program -> version
local VERSIONS_EVERY = 60 -- seconds between re-reading it (an 'install' while running changes it)
local INSTALLER = "/install.lua"
local REMOTE_SETTING = "install.remote" -- false: say no to the update watcher

if settings.define then
  settings.define(REMOTE_SETTING, {
    description = "Let the update watcher update this computer and reboot it.",
    default = true, type = "boolean",
  })
end

local info = { role = "computer", state = "starting" }
local fields = {}
local pendingEvent
local lastSent, changed = -math.huge, true
local callerPosAt, gpsAt = -math.huge, -math.huge
local versions, versionsAt = nil, -math.huge

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

local function readVersions()
  if not fs.exists(VERSIONS_FILE) then return nil end
  local f = fs.open(VERSIONS_FILE, "r")
  if not f then return nil end
  local body = f.readAll()
  f.close()
  local t = textutils.unserialize(body or "")
  return type(t) == "table" and t or nil
end

local function send()
  if not modemReady() then return end
  if os.clock() - versionsAt >= VERSIONS_EVERY then
    versions, versionsAt = readVersions(), os.clock()
  end
  local msg = {
    type = "status",
    label = os.getComputerLabel(),
    kind = kind(),
    role = info.role,
    state = info.state,
    detail = info.detail,
    event = pendingEvent,
    uptime = os.clock(),
    versions = versions,
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

---------------------------------------------------------------- updates

-- Why this computer won't update itself now, or nil if it will.
local function cantUpdate()
  if settings.get(REMOTE_SETTING) == false then return "remote updates are off here (install.remote)" end
  if settings.get("install.autoupdate") == false then return "auto-update is off here (install.autoupdate)" end
  if not http then return "http is off in the ComputerCraft config" end
  if not fs.exists(INSTALLER) then return "no installer here" end
  return nil
end

-- Run 'install boot' now with its text kept off the screen, and reboot if it
-- updated anything. Returns false and why when nothing changed. The update
-- watcher uses it for itself.
function report.updateNow()
  local why = cantUpdate()
  if why then return false, why end
  local before = textutils.serialize(readVersions() or {})
  local w, h = term.getSize()
  local old = term.redirect(window.create(term.current(), 1, 1, w, h, false))
  local ok, err = pcall(os.run, {}, INSTALLER, "boot")
  term.redirect(old)
  if not ok then return false, tostring(err) end
  if textutils.serialize(readVersions() or {}) == before then
    return false, "nothing newer on the website yet"
  end
  report.log("updated from the website, rebooting")
  sleep(0.5) -- let the report go out
  os.reboot()
end

-- Pass every event here from a program's own event loop (report.loop does
-- it itself). True when it was a request from the update watcher.
function report.handle(ev)
  if ev[1] ~= "rednet_message" or ev[4] ~= UPDATE_PROTOCOL then return false end
  local from, msg = ev[2], ev[3]
  if type(msg) ~= "table" or msg.type ~= "update" then return false end
  local why = cantUpdate()
  rednet.send(from, { re = "update", id = msg.id, ok = not why, why = why }, UPDATE_PROTOCOL)
  if why then return true end
  local state, detail = info.state, info.detail
  report.set("updating", "from the website")
  local _, err = report.updateNow()
  report.set(state, detail)
  report.log("asked to update: " .. tostring(err))
  return true
end

-- Heartbeat loop for parallel.waitForAny/waitForAll, so the computer keeps
-- showing as online while the main program is busy. It also answers the
-- update watcher.
function report.loop()
  -- Two coroutines: gps.locate waits on its own events for a second, and a
  -- request arriving meanwhile would be lost if one loop did both.
  parallel.waitForAll(function()
    while true do
      sleep(HEARTBEAT / 2)
      updateGpsPosition()
      if os.clock() - lastSent >= HEARTBEAT or changed then send() end
    end
  end, function()
    while true do report.handle({ os.pullEvent("rednet_message") }) end
  end)
end

return report
