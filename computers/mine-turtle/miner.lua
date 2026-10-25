-- AutoMine turtle: asks the server for a chunk, strip-mines it top to bottom
-- in 3-high layers, and returns to the dock to unload and refuel when needed.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local net = require("lib.net") -- opening modems
local report = require("lib.report")
local errlog = require("lib.errlog") -- saves errors to /errors.log

local PROTOCOL = "automine"
local JOB_FILE = "/.automine_job"
local STATUS_INTERVAL = 5

local serverId
local config -- sent by the server: dock, cruiseY, lanes, targetFuel, minFuel, junk
local junk = {}
local job -- { cx, cz, yTop, yBottom, layer, cell }
local paused = false
local jobCancelled = false
local state, stateMsg = "starting", nil
local lastStatus = 0
local lastHeard, lastLookup = os.clock(), 0 -- for noticing the server went away
local SERVER_SILENT = 30

---------------------------------------------------------------- persistence

local function saveJob()
  if job then nav.writeFile(JOB_FILE, job) else nav.deleteFile(JOB_FILE) end
end

local function loadJob() return nav.readFile(JOB_FILE) end

---------------------------------------------------------------- network

local function openModem()
  if not net.open() then error("No wireless modem: equip a wireless or ender modem on this turtle", 0) end
end

local function send(msg)
  if serverId then rednet.send(serverId, msg, PROTOCOL) end
end

-- Send msg to the server and wait for a reply of the given type, retrying forever.
local function request(msg, replyType)
  while true do
    if not serverId then
      serverId = rednet.lookup(PROTOCOL, "server")
      if not serverId then
        print("Waiting for server...")
        sleep(5)
      end
    end
    if serverId then
      rednet.send(serverId, msg, PROTOCOL)
      local deadline = os.clock() + 5
      repeat
        local id, reply = rednet.receive(PROTOCOL, math.max(0.05, deadline - os.clock()))
        if id == serverId and type(reply) == "table" and reply.type == replyType then
          lastHeard = os.clock()
          return reply
        end
      until os.clock() >= deadline
      serverId = nil -- no answer; look the server up again
    end
  end
end

local function layerCount(j) return math.ceil((j.yTop - j.yBottom + 1) / 3) end

local function progress()
  if not job then return nil end
  return (job.layer * 256 + job.cell) / (layerCount(job) * 256)
end

local function sendStatus(force)
  -- status server (lib.report rate-limits itself, so this is cheap to call often)
  local detail = stateMsg
  if not detail and job then
    detail = ("chunk %d,%d  %d%%"):format(job.cx, job.cz, math.floor(progress() * 100))
  end
  report.set(state, detail, { pos = nav.getPos() })

  if not force and os.clock() - lastStatus < STATUS_INTERVAL then return end
  lastStatus = os.clock()
  -- Server quiet for a while (restarted, maybe with a new ID): look it up again.
  -- Keep mining in the meantime; status reports resume once it's back.
  if os.clock() - lastHeard > SERVER_SILENT and os.clock() - lastLookup > 60 then
    lastLookup = os.clock()
    serverId = rednet.lookup(PROTOCOL, "server") or serverId
  end
  send({
    type = "status",
    label = os.getComputerLabel(),
    pos = nav.getPos(),
    fuel = turtle.getFuelLevel(),
    state = state,
    msg = stateMsg,
    job = job and { cx = job.cx, cz = job.cz },
    progress = progress(),
  })
end

local function setState(s, msg)
  if s ~= state or msg ~= stateMsg then print(s .. (msg and (": " .. msg) or "")) end
  state, stateMsg = s, msg
  sendStatus(true)
end

local function applyConfig(c)
  if not c then return end
  config = c
  junk = {}
  for _, name in ipairs(c.junk or {}) do junk[name] = true end
end

-- Runs alongside the main loop and picks up pause/cancel orders from the server.
local function listener()
  while true do
    local id, msg = rednet.receive(PROTOCOL)
    if id == serverId and type(msg) == "table" and msg.type == "control" then
      lastHeard = os.clock()
      paused = msg.paused
      if job and not (msg.job and msg.job.cx == job.cx and msg.job.cz == job.cz) then
        jobCancelled = true
      end
    end
  end
end

---------------------------------------------------------------- fuel and inventory

local fuelLevel = inv.fuelLevel

-- Each turtle travels at its own altitude so they don't fly into each other.
local function laneY() return config.cruiseY + (os.getComputerID() % config.lanes) end

local function fuelToDock()
  local p, d = nav.getPos(), config.dock
  return math.abs(p.y - laneY()) + math.abs(p.x - d.x) + math.abs(p.z - d.z) + math.abs(laneY() - d.y)
end

-- anything that burns, so it uses the coal it digs up
local function refuelFromInventory(target) inv.refuel(target) end

local emptySlots = inv.emptySlots

local function dropJunk()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and junk[item.name] then
      turtle.select(slot)
      turtle.drop()
    end
  end
  turtle.select(1)
end

---------------------------------------------------------------- travel and dock

local function check(ok, err)
  if not ok then error("can't move: " .. tostring(err), 0) end
end

-- Long-distance travel: up to this turtle's lane, across, then down.
local function travelTo(x, y, z)
  local p = nav.getPos()
  check(nav.goTo(p.x, laneY(), p.z))
  check(nav.goTo(x, laneY(), z))
  check(nav.goTo(x, y, z))
end

local function acquireDock()
  setState("waiting", "dock busy")
  while true do
    local r = request({ type = "dock_request" }, "dock")
    if r.granted then return end
    sendStatus()
    sleep(3)
  end
end

-- Fly home, empty everything into the chest below the dock, refuel from the
-- fuel chest beside it, then climb back to cruising height.
local function visitDock()
  dropJunk()
  acquireDock()
  setState("docking")
  local d = config.dock
  local ok, err = pcall(function()
    travelTo(d.x, d.y, d.z)
    for slot = 1, 16 do
      turtle.select(slot)
      while turtle.getItemCount(slot) > 0 and not turtle.dropDown() do
        setState("error", "deposit chest full")
        sleep(10)
      end
    end
    nav.face(d.fuelDir)
    turtle.select(1)
    while fuelLevel() < config.targetFuel do
      if turtle.suck() then
        while fuelLevel() < config.targetFuel and turtle.refuel(1) do end
        if turtle.getItemCount(1) > 0 then
          -- put unused fuel back; pass empty buckets and non-fuel on to the deposit chest
          if turtle.refuel(0) then turtle.drop() else turtle.dropDown() end
        end
      elseif fuelLevel() >= config.minFuel then
        break
      else
        setState("error", "fuel chest empty")
        sleep(10)
      end
    end
    setState("docking")
    check(nav.goTo(d.x, laneY(), d.z))
  end)
  send({ type = "dock_release" })
  if not ok then error(err, 0) end
end

-- Idle turtles hover beside the dock column, each at its own lane height.
local function park()
  local d = config.dock
  travelTo(d.x + 2, laneY(), d.z)
end

---------------------------------------------------------------- mining

-- Cell i (0-255) of a layer, snaking across the chunk. Odd layers run in
-- reverse so each layer starts right below where the last one ended.
local function cellPos(j, layer, i)
  if layer % 2 == 1 then i = 255 - i end
  local row = math.floor(i / 16)
  local col = i % 16
  if row % 2 == 1 then col = 15 - col end
  -- the turtle stands in the middle of each 3-high layer and digs up and down
  local y = math.max(j.yTop - 1 - layer * 3, j.yBottom + 1)
  return j.cx * 16 + col, y, j.cz * 16 + row
end

local function goToCell(x, y, z)
  local p = nav.getPos()
  if math.floor(p.x / 16) == job.cx and math.floor(p.z / 16) == job.cz then
    return nav.goTo(x, y, z)
  end
  local ok, err = nav.goTo(p.x, laneY(), p.z)
  if ok then ok, err = nav.goTo(x, laneY(), z) end
  if ok then ok, err = nav.goTo(x, y, z) end
  return ok, err
end

local function mineJob()
  setState("mining")
  local layers = layerCount(job)
  while job.layer < layers do
    while job.cell < 256 do
      if jobCancelled then return "cancelled" end
      if paused then return "paused" end

      local x, y, z = cellPos(job, job.layer, job.cell)
      local ok, err = goToCell(x, y, z)
      if ok then
        nav.digUp()
        nav.digDown()
      elseif err == "nofuel" then
        error("out of fuel", 0)
      end -- cells blocked by bedrock or protected blocks are skipped
      job.cell = job.cell + 1
      saveJob()

      if emptySlots() <= 1 then
        dropJunk()
        if emptySlots() <= 2 then
          visitDock()
          setState("mining")
        end
      end
      local reserve = fuelToDock() + 200
      if fuelLevel() < reserve then
        refuelFromInventory(reserve + 1000)
        if fuelLevel() < reserve then
          visitDock()
          setState("mining")
        end
      end
      sendStatus()
    end
    job.layer, job.cell = job.layer + 1, 0
    saveJob()
  end
  return "done"
end

---------------------------------------------------------------- main

local function idleWait(seconds)
  for _ = 1, math.ceil(seconds / STATUS_INTERVAL) do
    sleep(STATUS_INTERVAL)
    sendStatus(true)
  end
end

local function step()
  if jobCancelled then
    job, jobCancelled = nil, false
    saveJob()
  end

  if paused then
    setState("returning")
    if emptySlots() < 16 then visitDock() end
    park()
    setState("paused")
    while paused do idleWait(5) end
    return
  end

  if not job then
    local r = request({ type = "request_job" }, "job")
    applyConfig(r.config)
    paused = r.paused
    if not r.job then
      if emptySlots() < 16 then visitDock() end
      park()
      setState("idle")
      idleWait(15)
      return
    end
    job = r.job
    job.layer, job.cell = 0, 0
    jobCancelled = false
    saveJob()
  end

  if mineJob() == "done" then
    request({ type = "job_done", cx = job.cx, cz = job.cz }, "ack")
    job = nil
    saveJob()
  end
end

local function main()
  while true do
    local ok, err = errlog.pcall(step)
    if not ok then
      setState("error", tostring(err))
      idleWait(10)
    end
  end
end

local function askPosition()
  print("No GPS found. Stand behind the turtle facing the same way")
  print("it faces, press F3, and enter its coordinates.")
  while true do
    write("x y z: ")
    local x, y, z = read():match("^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$")
    write("Facing (north/east/south/west): ")
    local facing = read():lower()
    if x and nav.HEADINGS[facing] then
      nav.setPosition(tonumber(x), tonumber(y), tonumber(z), facing)
      return
    end
    print("Didn't understand that, try again.")
  end
end

openModem()
report.init("auto miner")
errlog.init("miner", function() return { pos = nav.getPos(), job = job } end)
if not os.getComputerLabel() then os.setComputerLabel("Miner-" .. os.getComputerID()) end
print("AutoMine turtle " .. os.getComputerLabel())
if not nav.init() then askPosition() end

local saved = loadJob()
local welcome = request({ type = "hello", label = os.getComputerLabel() }, "welcome")
applyConfig(welcome.config)
paused = welcome.paused
if saved and welcome.job and welcome.job.cx == saved.cx and welcome.job.cz == saved.cz then
  job = saved -- resume where we left off
elseif welcome.job then
  job = welcome.job
  job.layer, job.cell = 0, 0
end
saveJob()


parallel.waitForAny(main, listener, report.loop)
