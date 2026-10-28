-- AutoMine server: hands out chunk jobs to mining turtles and shows the chunk
-- map. Needs a wireless or ender modem; monitors are optional.
local ui = require("ui")
local statusBoard = require("status")
local report = require("lib.report")
local errlog = require("lib.errlog") -- saves errors to /errors.log
local net = require("lib.net") -- opening modems
local files = require("lib.files") -- crash-safe save files

--   server         run the server (startup.lua runs this)
--   server clear   drop every queued and in-progress chunk from the plan
local args = { ... }
local dir = fs.getDir(shell.getRunningProgram())
local config = dofile(fs.combine(dir, "config.lua"))

local PROTOCOL = "automine"
local STATE_FILE = "/.automine_state"
local SAVE_INTERVAL = 30
local MAX_EVENTS = 30

-- chunks: "cx,cz" -> { cx, cz, state = queued|active|player|done, order, turtle, progress }
-- turtles: id -> { label, pos, fuel, state, msg, job, progress, home, lastSeen }
--   home: where the miner was placed, with its own chest behind it; it
--   unloads, refuels and waits there
-- events: recent log lines, newest last
local state = { chunks = {}, turtles = {}, nextOrder = 1, paused = false, events = {} }
local saveDue, lastSave = false, 0

local function now() return os.epoch("utc") / 1000 end
local function key(cx, cz) return cx .. "," .. cz end

-- Chunks holding a miner's home are never mined: homeChunks["cx,cz"] = turtle id.
-- baseCx/baseCz (the map's HQ) is the lowest-numbered miner's home chunk.
local homeChunks, baseCx, baseCz = {}, nil, nil
local function updateHomes()
  homeChunks, baseCx, baseCz = {}, nil, nil
  local first
  for id, t in pairs(state.turtles) do
    if t.home then
      local cx, cz = math.floor(t.home.x / 16), math.floor(t.home.z / 16)
      homeChunks[key(cx, cz)] = id
      if not first or id < first then first, baseCx, baseCz = id, cx, cz end
    end
  end
end

local function save()
  files.write(STATE_FILE, state)
  saveDue, lastSave = false, now()
end

local function load()
  local s = files.read(STATE_FILE)
  if not s then return end
  state = s
  state.events = state.events or {}
  -- from before each miner had its own home: one shared dock, now unused
  state.dock, state.dockPos = nil, nil
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
  for k, c in pairs(state.chunks) do
    if c.state == "queued" and not homeChunks[k] and (not best or c.order < best.order) then best = c end
  end
  return best
end

local function newJob(c)
  return { cx = c.cx, cz = c.cz, yTop = config.yTop, yBottom = config.yBottom }
end

local function turtleConfig()
  return {
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

-- Drop every queued and in-progress chunk (mined and "Me" chunks stay), and
-- return the turtles that were mining one so they can be told to stop.
local function clearPlan(why)
  local released = {}
  for k, c in pairs(state.chunks) do
    if c.state == "queued" or c.state == "active" then
      if c.turtle then released[#released + 1] = c.turtle end
      state.chunks[k] = nil
    end
  end
  log("Plan cleared: " .. why)
  save()
  return released
end

local function touch(id, msg)
  local t = state.turtles[id]
  if not t then
    t = {}
    state.turtles[id] = t
  end
  t.label = msg.label or t.label
  t.lastSeen = now()
  local h = msg.home
  if type(h) == "table" and tonumber(h.x) and tonumber(h.y) and tonumber(h.z)
    and not (t.home and t.home.x == h.x and t.home.y == h.y and t.home.z == h.z) then
    t.home = { x = h.x, y = h.y, z = h.z }
    updateHomes()
    -- a home chunk is never mined, so drop it from the plan if it was queued
    local k = key(math.floor(h.x / 16), math.floor(h.z / 16))
    local c = state.chunks[k]
    if c and c.state == "queued" then state.chunks[k] = nil end
    log(("#%d home: %d,%d,%d"):format(id, h.x, h.y, h.z))
    save()
  end
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

---------------------------------------------------------------- map actions

local function paint(cx, cz, newState)
  local k = key(cx, cz)
  if homeChunks[k] then return end -- a miner lives here: never mined
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
updateHomes()
if args[1] == "clear" then
  -- turtles hear about it when the server starts again (it tells each one)
  local released = clearPlan("by 'server clear'")
  print(("Cleared the plan (%d turtle%s taken off a chunk). Reboot to start the server."):format(#released, #released == 1 and "" or "s"))
  return
elseif args[1] then
  print("Usage: server [clear]")
  return
end
if not net.open("any") then error("Attach a wireless or ender modem", 0) end
rednet.host(PROTOCOL, "server")
report.init("mining server")
errlog.init("server")

-- Start the map on the first miner's home, or (none yet) on this computer, by GPS.
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
  report.set(state.paused and "paused" or "serving", ("%d/%d turtles, %d queued"):format(online, total, queued))
end
announce()
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
    events = state.events,
    homeChunks = homeChunks,
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
