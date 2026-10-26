-- AutoMine server: hands out chunk jobs to mining turtles and shows the chunk
-- map. Needs a wireless or ender modem; monitors are optional.
local ui = require("ui")
local statusBoard = require("status")
local report = require("lib.report")
local errlog = require("lib.errlog") -- saves errors to /errors.log
local net = require("lib.net") -- opening modems
local files = require("lib.files") -- crash-safe save files

local dir = fs.getDir(shell.getRunningProgram())
local config = dofile(fs.combine(dir, "config.lua"))

local PROTOCOL = "automine"
local STATE_FILE = "/.automine_state"
local DOCK_TIMEOUT = 60 -- free the dock if the turtle holding it goes quiet this long
local SAVE_INTERVAL = 30
local MAX_EVENTS = 30

-- dockPos: the dock a miner set by GPS (chest behind it), used over config.dock
-- chunks: "cx,cz" -> { cx, cz, state = queued|active|player|done, order, turtle, progress }
-- turtles: id -> { label, pos, fuel, state, msg, job, progress, lastSeen }
-- dock: who is using the dock, so a restart can't send two turtles into it
-- events: recent log lines, newest last
local state = { chunks = {}, turtles = {}, nextOrder = 1, paused = false, dock = {}, events = {} }
local saveDue, lastSave = false, 0

-- The old config.lua shipped this as an example; it was never anyone's dock,
-- and it sent every turtle thousands of blocks away.
local function realDock(d)
  return d and d.x and d.y and d.z and not (d.x == 0 and d.y == 64 and d.z == 0) and d or nil
end

local function dock() return realDock(state.dockPos) or realDock(config.dock) end

-- the home chunk (holds the dock; never mined), nil while there's no dock
local baseCx, baseCz
local function updateBase()
  local d = dock()
  if d then baseCx, baseCz = math.floor(d.x / 16), math.floor(d.z / 16) else baseCx, baseCz = nil, nil end
end

local function now() return os.epoch("utc") / 1000 end
local function key(cx, cz) return cx .. "," .. cz end

local function save()
  files.write(STATE_FILE, state)
  saveDue, lastSave = false, now()
end

local function load()
  local s = files.read(STATE_FILE)
  if not s then return end
  state = s
  state.dock = state.dock or {}
  state.events = state.events or {}
  -- give the turtle that held the dock time to report in before reassigning it
  if state.dock.holder then state.dock.since = now() end
end

---------------------------------------------------------------- displays

local view = ui.new(config.mapMonitor)
local board = config.statusMonitor ~= false and statusBoard.new(config.statusMonitor, view.display) or nil

local function log(text)
  table.insert(state.events, { t = now(), text = text })
  while #state.events > MAX_EVENTS do table.remove(state.events, 1) end
  saveDue = true
  if view.display.name then print(text) end -- the computer's screen is free for logging
  report.log(text)
end

-- With the map on a monitor, this computer's screen shows the log.
local function announce()
  if not view.display.name then return end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("AutoMine server running. The map is on monitor " .. view.display.name .. ".")
end

-- A monitor came or went, or a turtle drove past (same events): each screen
-- only moves (and rescales) if its own monitor changed.
local function refreshDisplays()
  if view.display:refresh() then announce() end
  if board then board.display:refresh() end
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
    dock = dock(), -- nil until one is set: turtles wait
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
  if not c and not state.paused and dock() then
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

-- A miner standing with a chest behind it (on its own when there's no dock
-- yet, or with 'miner dock') sends where it is (GPS), which side the chest is
-- on, and the side of a separate fuel chest if it has one.
function handlers.set_dock(id, msg)
  touch(id, msg)
  local d = msg.dock
  if type(d) ~= "table" or not (tonumber(d.x) and tonumber(d.y) and tonumber(d.z)) then return end
  state.dockPos = { x = d.x, y = d.y, z = d.z, chestDir = d.chestDir, fuelDir = d.fuelDir }
  updateBase()
  -- the home chunk is never mined, so drop it from the plan if it was queued
  local home = state.chunks[key(baseCx, baseCz)]
  if home and home.state ~= "active" then state.chunks[key(baseCx, baseCz)] = nil end
  log(("#%d set the dock to %d,%d,%d"):format(id, d.x, d.y, d.z))
  save()
  return { type = "dock_set", config = turtleConfig() }
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
updateBase()
if not net.open("any") then error("Attach a wireless or ender modem", 0) end
rednet.host(PROTOCOL, "server")
report.init("mining server")
errlog.init("server")

-- Start the map on the dock, or (no dock yet) on this computer, by GPS.
if baseCx then
  view.viewX, view.viewZ = baseCx, baseCz
else
  local x, _, z = gps.locate(2)
  if x then view.viewX, view.viewZ = math.floor(x / 16), math.floor(z / 16) end
end

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
  if not dock() then
    report.set("waiting", "no dock: put a chest behind a miner")
    return
  end
  report.set(state.paused and "paused" or "serving", ("%d/%d turtles, %d queued"):format(online, total, queued))
end
announce()
log("Server started")
if not dock() then log("No dock yet: place a miner with a chest right behind it") end
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
  elseif view.display:clicked(ev) then
    apply(view:click(view.display:clicked(ev))) -- x, y, and whether it's a drag
  elseif name == "key" then
    view:key(ev[2])
  elseif name == "peripheral" or name == "peripheral_detach" then
    refreshDisplays()
  end
  -- monitor_resize / term_resize: the next frame is made at the new size
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
