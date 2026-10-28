-- AutoMine turtle: asks the server for a chunk, strip-mines it top to bottom
-- in 3-high layers, and goes home to unload and refuel when needed. Home is
-- where the player placed it, with its own chest right behind it; with
-- nothing to do it waits there.
--
--   miner          mine (startup.lua runs this)
--   miner home     make this spot my home (chest behind me), e.g. to move it
local args = { ... }
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local net = require("lib.net") -- opening modems
local report = require("lib.report")
local errlog = require("lib.errlog") -- saves errors to /errors.log

local PROTOCOL = "automine"
local JOB_FILE = "/.automine_job"
local HOME_FILE = "/.automine_home"
local GPS_FILE = "/.automine_gps" -- true once this miner has had GPS: from then on it won't move without it
local GPS_TRIES = 3 -- attempts before GPS counts as lost (one missed answer isn't a lost signal)
local GPS_RETRY = 15 -- seconds between GPS checks while waiting for it to come back
local STATUS_INTERVAL = 5
local POSITION_CHECK_CELLS = 32 -- cells mined between GPS checks of the tracked position

local serverId
local config -- sent by the server: cruiseY, lanes, targetFuel, minFuel, junk
local home -- { x, y, z, heading, chestDir, fuelDir }: this turtle's own spot and chests
local usesGps = false -- has had GPS (saved in GPS_FILE)
local gpsLost = false -- started without the GPS it had: main waits for it before doing anything
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
    home = home, -- the server never mines a chunk with a miner's home in it
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

local function fuelToHome()
  local p, d = nav.getPos(), home
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

---------------------------------------------------------------- travel and home

local function check(ok, err)
  if not ok then error("can't move: " .. tostring(err), 0) end
end

local function idleWait(seconds)
  for _ = 1, math.ceil(seconds / STATUS_INTERVAL) do
    sleep(STATUS_INTERVAL)
    sendStatus(true)
  end
end

local function gpsFix()
  for _ = 1, GPS_TRIES do
    local g = nav.locate()
    if g then return g end
  end
end

-- Once a miner has had GPS it won't move without it: tracking alone drifts
-- (a chunk unloading mid-move), and a wrong position sends it digging and
-- unloading in the wrong place. It stays where it is, tells the server where
-- that is (the error and its status carry the position), and waits.
local function waitForGps()
  local was, wasMsg = state, stateMsg
  local p = nav.getPos()
  local where = ("%d,%d,%d"):format(p.x, p.y, p.z)
  report.log("GPS lost at " .. where)
  setState("error", ("no GPS at %s: waiting for it"):format(where))
  local g
  repeat
    idleWait(GPS_RETRY)
    g = gpsFix()
  until g
  print("GPS is back.")
  report.log("GPS is back")
  setState(was, wasMsg)
  return g
end

-- Tracking can slip (a chunk unloading mid-move, a reboot), and every later
-- move would be off by the same amount, so compare it with GPS now and then
-- and recalibrate if they disagree.
local function checkPosition()
  local g = gpsFix()
  if not g then
    if not usesGps then return end -- set up without GPS: tracking is all it has
    g = waitForGps()
  end
  local p = nav.getPos()
  if g.x ~= p.x or g.y ~= p.y or g.z ~= p.z then
    print(("Position was off: thought %d,%d,%d, GPS says %d,%d,%d. Correcting."):format(p.x, p.y, p.z, g.x, g.y, g.z))
    report.log(("position corrected to %d,%d,%d"):format(g.x, g.y, g.z))
    nav.init(true)
  end
end

-- Long-distance travel: up to this turtle's lane, across, then down.
local function travelTo(x, y, z)
  checkPosition()
  local p = nav.getPos()
  check(nav.goTo(p.x, laneY(), p.z))
  check(nav.goTo(x, laneY(), z))
  check(nav.goTo(x, y, z))
end

-- Facing a chest: take fuel out of it until reaching target. Anything that
-- isn't fuel (or is left over) goes back in. Same as excavate-turtle's.
local function refuelFromChest(target)
  local putBack = {}
  for slot = 1, 16 do
    if fuelLevel() >= target then break end
    if turtle.getItemCount(slot) == 0 then
      turtle.select(slot)
      if not turtle.suck() then break end -- chest is empty
      if turtle.getItemCount(slot) == 0 then
        refuelFromInventory(target) -- it stacked onto fuel already on board
      else
        while fuelLevel() < target and turtle.refuel(1) do end
        if turtle.getItemCount(slot) > 0 then putBack[#putBack + 1] = slot end
      end
    end
  end
  for _, slot in ipairs(putBack) do
    turtle.select(slot)
    turtle.drop()
  end
  turtle.select(1)
end

-- At home: burn the coal it dug, empty everything into the chest behind
-- the home spot, top up fuel from the fuel chest beside it (or the home chest
-- itself), then face the way it was placed.
local function unloadAtHome()
  nav.face(home.chestDir)
  -- A wrong home (or a wrong GPS) would otherwise mean emptying everything
  -- onto the ground.
  if not peripheral.hasType("front", "inventory") then
    error(("No chest behind my home (%d,%d,%d). Put me back on my spot with my chest behind me and run 'miner home'."):format(home.x, home.y, home.z), 0)
  end
  refuelFromInventory(config.targetFuel)
  for slot = 1, 16 do
    turtle.select(slot)
    while turtle.getItemCount(slot) > 0 and not turtle.drop() do
      setState("error", "home chest full")
      sleep(10)
    end
  end
  turtle.select(1)
  nav.face(home.fuelDir or home.chestDir)
  while true do
    refuelFromChest(config.targetFuel)
    if fuelLevel() >= config.minFuel then break end
    setState("error", home.fuelDir and "fuel chest empty" or "no fuel in my chest")
    sleep(10)
  end
  nav.face(home.heading)
end

-- Fly home (up to this turtle's lane, across, straight down into its own
-- spot) and unload. Mining resumes from there: goToCell climbs back up.
local function visitHome()
  dropJunk()
  setState("returning")
  travelTo(home.x, home.y, home.z)
  setState("unloading")
  unloadAtHome()
end

-- Idle and paused turtles wait at home, emptied and fuelled.
local function park()
  local p = nav.getPos()
  if p.x == home.x and p.y == home.y and p.z == home.z and emptySlots() == 16 then
    return nav.face(home.heading)
  end
  visitHome()
end

local HEADING_NAMES = { [0] = "north", "east", "south", "west" }

-- A miner standing with a chest directly behind it is at home: the chest
-- takes what it mines, and a second chest on its left or right, if any, is
-- for fuel. Its position comes from GPS (or the player), so nobody types it twice.
local function homeHere()
  if not peripheral.hasType("back", "inventory") then return nil end
  local p, h = nav.getPos(), nav.getHeading()
  local spot = { x = p.x, y = p.y, z = p.z, heading = HEADING_NAMES[h], chestDir = HEADING_NAMES[(h + 2) % 4] }
  if peripheral.hasType("right", "inventory") then
    spot.fuelDir = HEADING_NAMES[(h + 1) % 4]
  elseif peripheral.hasType("left", "inventory") then
    spot.fuelDir = HEADING_NAMES[(h + 3) % 4]
  end
  return spot
end

local function setHome(spot)
  home = spot
  nav.writeFile(HOME_FILE, home)
  print(("Home: %d, %d, %d, chest to the %s%s."):format(home.x, home.y, home.z, home.chestDir,
    home.fuelDir and (", fuel chest to the " .. home.fuelDir) or ""))
  sendStatus(true)
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
      if job.cell % POSITION_CHECK_CELLS == 0 then checkPosition() end

      if emptySlots() <= 1 then
        dropJunk()
        if emptySlots() <= 2 then
          visitHome()
          setState("mining")
        end
      end
      local reserve = fuelToHome() + 200
      if fuelLevel() < reserve then
        refuelFromInventory(reserve + 1000)
        if fuelLevel() < reserve then
          visitHome()
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

local function step()
  if jobCancelled then
    job, jobCancelled = nil, false
    saveJob()
  end

  if gpsLost then
    gpsLost = false
    checkPosition() -- waits for GPS, then corrects the saved position if it was off
  end

  if not home then
    -- Nowhere to unload, so don't start anything. A turtle that hasn't
    -- started a job is still where the player put it: once a chest goes
    -- behind it, that's home.
    local here = not job and homeHere()
    if here then return setHome(here) end
    setState("waiting", job and "no home: put me on my spot, then 'miner home'" or "no home: put a chest behind me")
    idleWait(15)
    return
  end

  if paused then
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

-- The player's own F3 position is the block they stand on, not the turtle's,
-- so ask for the turtle's block ("Targeted Block", shown as "x, y, z").
local function askPosition()
  print("No GPS here, so tell me where I am. Press F3 and look")
  print("at my block: \"Targeted Block\" shows its X, Y, Z.")
  while true do
    write("X Y Z: ")
    local n = {}
    for num in read():gmatch("-?%d+") do n[#n + 1] = tonumber(num) end
    print("Stand behind me, looking the way I face, and read")
    print("\"Facing\" on F3.")
    write("Facing (north/east/south/west): ")
    local facing = read():lower():gsub("%s", "")
    if #n == 3 and nav.HEADINGS[facing] then
      nav.setPosition(n[1], n[2], n[3], facing)
      return
    end
    print("Didn't understand that, try again.")
  end
end

-- 'miner home': make this spot home, e.g. to move it, or for a miner that
-- was mid-job when it was set up.
local function markHome()
  if gpsLost then
    print("No GPS signal, so I can't tell where this spot is. Try again once GPS is back.")
    return
  end
  local spot = homeHere()
  if not spot then
    print("Put a chest directly behind me first: that's my chest.")
    return
  end
  setHome(spot)
  print("Saved. Reboot me to start mining.")
end

if args[1] and args[1] ~= "home" then
  print("Usage: miner [home]")
  return
end

openModem()
report.init("auto miner")
errlog.init("miner", function() return { pos = nav.getPos(), job = job } end)
if not os.getComputerLabel() then os.setComputerLabel("Miner-" .. os.getComputerID()) end
print("AutoMine turtle " .. os.getComputerLabel())
-- GPS works out the facing by stepping forward, which needs fuel.
if inv.fuelLevel() < 10 then inv.refuel(100) end
usesGps = nav.readFile(GPS_FILE) == true
if gpsFix() then
  nav.init(true)
  if not usesGps then
    usesGps = true
    nav.writeFile(GPS_FILE, true)
  end
elseif usesGps then
  -- It had GPS, so it doesn't guess: report the saved position and wait.
  nav.init(false)
  gpsLost = true
  print("No GPS signal. I won't move until it's back.")
elseif not nav.init(false) then
  askPosition()
elseif not nav.confirmResume("Then type my position again.") then
  askPosition()
end
local p = nav.getPos()
print(("I'm at %d, %d, %d, facing %s."):format(p.x, p.y, p.z, HEADING_NAMES[nav.getHeading()]))
home = nav.readFile(HOME_FILE)
if args[1] == "home" then return markHome() end

local saved = loadJob()
local welcome = request({ type = "hello", label = os.getComputerLabel(), home = home }, "welcome")
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
