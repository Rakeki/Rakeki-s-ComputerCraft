-- AutoMine server: hands out chunk jobs to mining turtles and shows the chunk
-- map. Needs a wireless or ender modem; monitors are optional.
local ui = require("ui")
local statusBoard = require("status")
local report = require("lib.report")
local errlog = require("lib.errlog") -- saves errors to /errors.log

local dir = fs.getDir(shell.getRunningProgram())
local config = dofile(fs.combine(dir, "config.lua"))

local PROTOCOL = "automine"
local STATE_FILE = "/.automine_state"
local DOCK_TIMEOUT = 60 -- free the dock if the turtle holding it goes quiet this long
local SAVE_INTERVAL = 30
local MAX_EVENTS = 30

-- chunks: "cx,cz" -> { cx, cz, state = queued|active|player|done, order, turtle, progress }
-- turtles: id -> { label, pos, fuel, state, msg, job, progress, lastSeen }
-- dock: who is using the dock, so a restart can't send two turtles into it
-- events: recent log lines, newest last
local state = { chunks = {}, turtles = {}, nextOrder = 1, paused = false, dock = {}, events = {} }
local saveDue, lastSave = false, 0

local baseCx, baseCz = math.floor(config.dock.x / 16), math.floor(config.dock.z / 16)

local function now() return os.epoch("utc") / 1000 end
local function key(cx, cz) return cx .. "," .. cz end

-- Write to a temp file first so a crash mid-save never leaves a broken state file.
local function save()
  local tmp = STATE_FILE .. ".tmp"
  local f = fs.open(tmp, "w")
  f.write(textutils.serialize(state))
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
        state = s
        state.dock = state.dock or {}
        state.events = state.events or {}
        -- give the turtle that held the dock time to report in before reassigning it
        if state.dock.holder then state.dock.since = now() end
        return
      end
    end
  end
end

---------------------------------------------------------------- displays

local screen = term.current()
local mapMonitorName -- nil when the map is on the computer's screen
local view, board

local function log(text)
  table.insert(state.events, { t = now(), text = text })
  while #state.events > MAX_EVENTS do table.remove(state.events, 1) end
  saveDue = true
  if mapMonitorName then print(text) end -- the computer's screen is free for logging
  report.log(text)
end

local function monitorNamed(name)
  if name and peripheral.getType(name) == "monitor" then return peripheral.wrap(name) end
end

-- (Re)pick displays from config and whatever monitors are attached right now.
local function setupDisplays()
  local mapMon = monitorNamed(config.mapMonitor)
  mapMonitorName = mapMon and peripheral.getName(mapMon)

  local statusMon
  if config.statusMonitor ~= false then
    statusMon = monitorNamed(config.statusMonitor) or (not config.statusMonitor and peripheral.find("monitor",
      function(name) return name ~= mapMonitorName end))
  end

  local old = view
  if mapMon then
    mapMon.setTextScale(0.5)
    view = ui.new(mapMon)
    screen.setBackgroundColor(colors.black)
    screen.clear()
    screen.setCursorPos(1, 1)
    print("AutoMine server running. The map is on monitor " .. mapMonitorName .. ".")
  else
    view = ui.new(screen)
  end
  if old then
    view.viewX, view.viewZ, view.brush, view.selected = old.viewX, old.viewZ, old.brush, old.selected
  else
    view.viewX, view.viewZ = baseCx, baseCz
  end

  board = statusMon and statusBoard.new(statusMon) or nil
end

---------------------------------------------------------------- jobs

local function assignedTo(id)
  for _, c in pairs(state.chunks) do
    if c.state == "active" and c.turtle == id then return c end
  end
end

local function nextQueued()
  local best
  for _, c in pairs(state.chunks) do
    if c.state == "queued" and (not best or c.order < best.order) then best = c end
  end
  return best
end

local function newJob(c)
  return { cx = c.cx, cz = c.cz, yTop = config.yTop, yBottom = config.yBottom }
end

local function turtleConfig()
  return {
    dock = config.dock,
    cruiseY = config.cruiseY,
    lanes = config.lanes,
    targetFuel = config.targetFuel,
    minFuel = config.minFuel,
    junk = config.junk,
  }
end

local function controlMsg(id)
  local c = assignedTo(id)
  return { type = "control", paused = state.paused, job = c and { cx = c.cx, cz = c.cz } }
end

local function sendControl(id)
  rednet.send(id, controlMsg(id), PROTOCOL)
end

local function touch(id, msg)
  local t = state.turtles[id]
  if not t then
    t = {}
    state.turtles[id] = t
  end
  t.label = msg.label or t.label
  t.lastSeen = now()
  return t
end

---------------------------------------------------------------- messages

local handlers = {}

function handlers.hello(id, msg)
  touch(id, msg)
  log("#" .. id .. " " .. tostring(msg.label) .. " connected")
  local c = assignedTo(id)
  return { type = "welcome", config = turtleConfig(), paused = state.paused, job = c and newJob(c) }
end

function handlers.request_job(id, msg)
  touch(id, msg)
  local c = assignedTo(id)
  if not c and not state.paused then
    c = nextQueued()
    if c then
      c.state, c.turtle, c.progress, c.order = "active", id, 0, nil
      log("#" .. id .. " took chunk " .. key(c.cx, c.cz))
      save()
    end
  end
  return {
    type = "job",
    paused = state.paused,
    config = turtleConfig(),
    job = c and not state.paused and newJob(c) or nil,
  }
end

function handlers.status(id, msg)
  local t = touch(id, msg)
  if msg.state == "error" and (t.state ~= "error" or t.msg ~= msg.msg) then
    log("#" .. id .. " error: " .. tostring(msg.msg))
  end
  t.pos, t.fuel, t.state, t.msg = msg.pos, msg.fuel, msg.state, msg.msg
  local c = assignedTo(id)
  t.job = c and { cx = c.cx, cz = c.cz } or nil
  t.progress = c and msg.progress or nil
  if c and msg.job and msg.job.cx == c.cx and msg.job.cz == c.cz then c.progress = msg.progress end
  if state.dock.holder == id then state.dock.since = now() end
  saveDue = true
  return controlMsg(id)
end

function handlers.job_done(id, msg)
  touch(id, msg)
  local c = state.chunks[key(msg.cx, msg.cz)]
  if c and c.state == "active" and c.turtle == id then
    c.state, c.turtle, c.progress = "done", nil, nil
    log("#" .. id .. " finished chunk " .. key(c.cx, c.cz))
    save()
  end
  return { type = "ack" }
end

function handlers.dock_request(id, msg)
  touch(id, msg)
  local d = state.dock
  if not d.holder or d.holder == id or now() - d.since > DOCK_TIMEOUT then
    if d.holder ~= id then
      d.holder, d.since = id, now()
      save()
    end
    return { type = "dock", granted = true }
  end
  return { type = "dock", granted = false }
end

function handlers.dock_release(id)
  if state.dock.holder == id then
    state.dock.holder = nil
    save()
  end
end

---------------------------------------------------------------- map actions

local function paint(cx, cz, newState)
  if cx == baseCx and cz == baseCz then return end -- never touch the home chunk
  local k = key(cx, cz)
  local c = state.chunks[k]
  local current = c and c.state or "none"
  if current == newState or (current == "active" and newState == "queued") then return end

  local released = current == "active" and c.turtle
  if newState == "none" then
    state.chunks[k] = nil
  else
    state.chunks[k] = { cx = cx, cz = cz, state = newState }
    if newState == "queued" then
      state.chunks[k].order = state.nextOrder
      state.nextOrder = state.nextOrder + 1
    end
  end
  if released then log("#" .. released .. " taken off chunk " .. k) end
  save()
  if released then sendControl(released) end -- tell the turtle to drop the job
end

local function apply(action)
  if not action then return end
  if action.type == "paint" then
    paint(action.cx, action.cz, action.state)
  elseif action.type == "togglePause" then
    state.paused = not state.paused
    log(state.paused and "Paused: turtles returning home" or "Resumed")
    save()
    for id in pairs(state.turtles) do sendControl(id) end
  end
end

---------------------------------------------------------------- main

load()
peripheral.find("modem", rednet.open)
if not rednet.isOpen() then error("Attach a wireless or ender modem", 0) end
rednet.host(PROTOCOL, "server")
report.init("mining server")
errlog.init("server")

-- One-line summary for the status server.
local function reportStatus()
  local online, total, queued = 0, 0, 0
  for _, t in pairs(state.turtles) do
    total = total + 1
    if t.lastSeen and now() - t.lastSeen < 30 then online = online + 1 end
  end
  for _, c in pairs(state.chunks) do
    if c.state == "queued" then queued = queued + 1 end
  end
  report.set(state.paused and "paused" or "serving", ("%d/%d turtles, %d queued"):format(online, total, queued))
end
setupDisplays()
log("Server started")
save()

-- Tell turtles straight away, rather than waiting for their next status
-- report, in case the plan changed while the server was down.
for id in pairs(state.turtles) do sendControl(id) end

local function model()
  return {
    chunks = state.chunks,
    turtles = state.turtles,
    paused = state.paused,
    dockHolder = state.dock.holder,
    events = state.events,
    baseCx = baseCx,
    baseCz = baseCz,
    now = now(),
  }
end

local function redraw()
  local m = model()
  view:draw(m)
  if board then board:draw(m) end
end

local function handle(ev)
  local name = ev[1]
  if name == "rednet_message" and ev[4] == PROTOCOL then
    local id, msg = ev[2], ev[3]
    if type(msg) == "table" and handlers[msg.type] then
      local reply = handlers[msg.type](id, msg)
      if reply then rednet.send(id, reply, PROTOCOL) end
    end
  elseif name == "monitor_touch" and ev[2] == mapMonitorName then
    apply(view:click(ev[3], ev[4]))
  elseif (name == "mouse_click" or name == "mouse_drag") and not mapMonitorName then
    apply(view:click(ev[3], ev[4], name == "mouse_drag"))
  elseif name == "key" then
    view:key(ev[2])
  elseif name == "peripheral" or name == "peripheral_detach" or name == "monitor_resize" or name == "term_resize" then
    setupDisplays()
  end
end

local timer = os.startTimer(2)
redraw()
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == timer then
    if saveDue and now() - lastSave > SAVE_INTERVAL then save() end
    reportStatus()
    timer = os.startTimer(2)
  else
    -- one bad message or click shouldn't take the whole server down
    local ok, err = errlog.pcall(handle, ev)
    if not ok then log("Error: " .. tostring(err)) end
  end
  local ok, err = errlog.pcall(redraw)
  if not ok then log("Display error: " .. tostring(err)) end
end
