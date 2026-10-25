-- Standalone strip miner (no server). Digs a 3x3 main tunnel straight ahead
-- with 3x3 branches off both sides, and brings everything it finds back to a
-- chest at the start.
--
--   stripmine [length] [branch] [gap]    (default 64 32 3)
--   stripmine resume
--   stripmine here
--   stripmine cancel
--
-- Place the turtle on the floor, facing the way to dig, with a chest directly
-- behind it. The main tunnel is 3 wide (centred on the turtle), 3 high (from
-- the turtle's block up) and [length] long, counting the start block. Branches
-- [branch] long go off both sides, with [gap] solid blocks between
-- neighbouring branches.
local nav = require("lib.nav")
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.stripmine_job"

local TORCH_EVERY = 8 -- blocks between torches, in the main tunnel and the branches
local TORCH = "minecraft:torch" -- never dropped or unloaded, so put them anywhere in the inventory

-- Fuel it tops up to from the chest behind the start (coal it has mined,
-- or any fuel you put in there).
local REFUEL_TO = 3000

-- Thrown away instead of carried back to the chest.
local JUNK = {}
for _, name in ipairs({
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:deepslate",
  "minecraft:dirt", "minecraft:gravel", "minecraft:andesite", "minecraft:diorite", "minecraft:granite",
  "minecraft:tuff", "minecraft:calcite", "minecraft:netherrack",
}) do JUNK[name] = true end

local job, plan

---------------------------------------------------------------- coordinates

-- Job coordinates are local to the start block: x to the right, z forward,
-- y up. The main tunnel runs along z from 0, with x from -1 to 1.
local DIRS = { [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 } }

local function toWorld(p)
  local o = job.origin
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  return o.x + p.x * r.x + p.z * f.x, o.y + p.y, o.z + p.x * r.z + p.z * f.z
end

local function here()
  local o, w = job.origin, nav.getPos()
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  local dx, dz = w.x - o.x, w.z - o.z
  return { x = dx * r.x + dz * r.z, y = w.y - o.y, z = dx * f.x + dz * f.z }
end

local function goL(p) return nav.goTo(toWorld(p)) end

---------------------------------------------------------------- plan

-- Every spot to stand on and dig above and below, in order. They're all at
-- y = 1, the middle of the tunnel, so each one clears a 1x3 column.
local function buildPlan()
  local spacing = job.gap + 3 -- branch centre to branch centre
  plan = { cells = {}, branches = {}, start = { x = 0, y = 0, z = 0 } }
  local function add(x, z, torch, where)
    table.insert(plan.cells, { x = x, y = 1, z = z, torch = torch, where = where })
  end
  for z = 0, job.length - 1 do
    -- one 3-wide slice of the main tunnel, snaking so each cell is next to the last
    for i = 0, 2 do
      local x = z % 2 == 0 and i - 1 or 1 - i
      add(x, z, x == 0 and z > 0 and z % TORCH_EVERY == 0, "main tunnel")
    end
    -- A branch is centred on bz. Dig it once the main tunnel is open on all
    -- three of its rows, so the way in is clear.
    local bz = z - 1
    if bz > 0 and bz % spacing == 0 then
      table.insert(plan.branches, bz)
      for _, side in ipairs({ -1, 1 }) do
        local where = ("branch %d %s"):format(#plan.branches, side < 0 and "left" or "right")
        for i = 0, job.branch - 1 do
          for j = 0, 2 do
            local dz = i % 2 == 0 and j - 1 or 1 - j
            add(side * (2 + i), bz + dz, dz == 0 and (i + 1) % TORCH_EVERY == 0, where)
          end
        end
      end
    end
  end
end

-- Which tunnel p is in: "main", a number for a branch (its centre z, negative
-- on the left), or nil if it's in solid rock.
local function tunnelOf(p)
  if math.abs(p.x) <= 1 then
    if p.z >= 0 and p.z < job.length then return "main" end
    return nil
  end
  if math.abs(p.x) > job.branch + 1 then return nil end
  for _, bz in ipairs(plan.branches) do
    if math.abs(p.z - bz) <= 1 then return p.x < 0 and -bz or bz end
  end
end

-- Move anywhere in the mine along the tunnels: out of a branch to the middle
-- of the main tunnel, along it, then into the other branch.
local function travel(t)
  local p = here()
  local from = tunnelOf(p)
  if from ~= nil and from == tunnelOf(t) then return goL(t) end
  if from ~= "main" then
    local ok, err = goL({ x = 0, y = 1, z = p.z })
    if not ok then return ok, err end
  end
  local ok, err = goL({ x = 0, y = 1, z = t.z })
  if not ok then return ok, err end
  return goL(t)
end

---------------------------------------------------------------- position checks

local reach -- defined below; used by the trips home

local function gpsPos()
  local x, y, z = gps.locate(2)
  if not x then return nil end
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
end

-- Somewhere the turtle is meant to be: in a tunnel, or on its start block.
local function onPlan(p)
  local s = plan.start
  return (tunnelOf(p) ~= nil and p.y >= 0 and p.y <= 2) or (p.x == s.x and p.y == s.y and p.z == s.z)
end

-- If the turtle finds itself off its route (picked up and put down
-- somewhere else, say), head for the start block before carrying on.
local function rejoin()
  local p = here()
  if onPlan(p) then return end
  print(("Off my route at %d,%d,%d. Heading back to the start first."):format(nav.getPos().x, nav.getPos().y, nav.getPos().z))
  goL(plan.start)
end

-- With GPS, compare where the turtle thinks it is with where it really is.
-- If they differ, re-check position and facing and get back on route.
local function checkPosition()
  if not job.gps then return end
  local g = gpsPos()
  if not g then return end -- out of GPS range just now
  local p = nav.getPos()
  if g.x ~= p.x or g.y ~= p.y or g.z ~= p.z then
    print(("Position was off: thought %d,%d,%d, GPS says %d,%d,%d. Correcting."):format(p.x, p.y, p.z, g.x, g.y, g.z))
    nav.init()
    rejoin()
  end
end

---------------------------------------------------------------- inventory and fuel

local function save() nav.writeFile(JOB_FILE, job) end

local function fuelLevel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

local function emptySlots()
  local n = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then n = n + 1 end
  end
  return n
end

-- Drop everything matching shouldDrop, except torches.
local function dropItems(shouldDrop, drop)
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and item.name ~= TORCH and shouldDrop(item) then
      turtle.select(slot)
      drop()
    end
  end
  turtle.select(1)
end

local function dropJunk()
  dropItems(function(item) return JUNK[item.name] end, turtle.drop)
end

local function refuelFromInventory(target)
  for slot = 1, 16 do
    if fuelLevel() >= target then break end
    turtle.select(slot)
    while fuelLevel() < target and turtle.refuel(1) do end
  end
  turtle.select(1)
end

-- The way home is along the tunnels, which is exactly this far.
local function homeDistance()
  local p = here()
  return math.abs(p.x) + math.abs(p.y) + math.abs(p.z) + 50
end

local function faceChest() nav.face((job.origin.heading + 2) % 4) end

-- Facing the chest at the start: take fuel out of it until reaching target.
-- Anything that isn't fuel (or fuel left over) goes back in.
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

local function unload(why)
  print(why .. ", emptying into the chest")
  report.set("unloading", why)
  reach(plan.start)
  -- junk goes on the ground in front, everything else in the chest
  nav.face(job.origin.heading)
  dropJunk()
  faceChest()
  local warned = false
  while true do
    local full = false
    dropItems(function() return true end, function()
      if not turtle.drop() then full = true end
    end)
    if not full then break end
    if not warned then
      print("Chest behind the start is missing or full. Waiting...")
      report.set("waiting", "chest full or missing")
      warned = true
    end
    sleep(5)
  end
  -- while here, top up from any fuel in the chest
  if fuelLevel() < REFUEL_TO then refuelFromChest(REFUEL_TO) end
end

-- Go home and refuel from the chest there. If it hasn't got enough, wait for
-- the player to add fuel to the chest or to the turtle.
local function waitForFuel(target)
  reach(plan.start)
  faceChest()
  if emptySlots() < 2 then dropItems(function() return true end, turtle.drop) end
  refuelFromChest(math.max(target, REFUEL_TO))
  if fuelLevel() >= target then return end
  print(("Need %d fuel, have %d. Put fuel in the chest behind me or in my inventory."):format(target, fuelLevel()))
  report.set("waiting", ("needs fuel (%d)"):format(target))
  while fuelLevel() < target do
    local timer = os.startTimer(10) -- the chest doesn't announce changes, so check it every 10s
    repeat
      local event, value = os.pullEvent()
    until event == "turtle_inventory" or (event == "timer" and value == timer)
    refuelFromInventory(target)
    refuelFromChest(math.max(target, REFUEL_TO))
  end
end

local function housekeeping()
  if emptySlots() <= 1 then
    dropJunk()
    if emptySlots() <= 2 then unload("Inventory full") end
  end
  local needed = homeDistance()
  if fuelLevel() < needed then
    refuelFromInventory(needed + 1000)
    if fuelLevel() < needed then waitForFuel(needed + 1000) end
  end
end

local function placeTorch()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and item.name == TORCH then
      turtle.select(slot)
      turtle.placeDown()
      break
    end
  end
  turtle.select(1)
end

-- Get to p. If the spot itself can't be cleared (bedrock or a protected
-- block like a spawner), give up on it. If something is blocking the way
-- there, stop and say so, and keep retrying, rather than skipping ahead.
reach = function(p)
  local tries = 0
  while true do
    local ok, err = travel(p)
    if ok then return true end
    local h = here()
    if err ~= "nofuel" and math.abs(h.x - p.x) + math.abs(h.y - p.y) + math.abs(h.z - p.z) <= 1 then
      return false, err
    end
    tries = tries + 1
    if err == "nofuel" then
      print("Out of fuel here. Put fuel in my inventory.")
      while fuelLevel() == 0 do
        refuelFromInventory(1000)
        if fuelLevel() == 0 then os.pullEvent("turtle_inventory") end
      end
    else
      local w = nav.getPos()
      local tx, ty, tz = toWorld(p)
      local msg = ("Stuck at %d,%d,%d (%s) on the way to %d,%d,%d"):format(w.x, w.y, w.z, tostring(err), tx, ty, tz)
      print(msg .. ". Clear the way; retrying.")
      report.set("stuck", msg)
      checkPosition()
      sleep(math.min(60, 5 * tries))
    end
  end
end

---------------------------------------------------------------- main

local function progressText()
  local c = plan.cells[math.min(job.cell + 1, #plan.cells)]
  return ("%s, %d%% overall"):format(c.where, math.floor(job.cell / #plan.cells * 100))
end

local function digCell(c)
  if not reach(c) then return end -- bedrock or a protected block: skip
  nav.digUp()
  nav.digDown()
  if c.torch then placeTorch() end
end

local function run()
  rejoin()
  while job.cell < #plan.cells do
    digCell(plan.cells[job.cell + 1])
    job.cell = job.cell + 1
    save()
    if job.cell % 20 == 0 then checkPosition() end
    housekeeping()
    if job.cell % 25 == 0 then print(progressText()) end
    -- only GPS jobs have real world coordinates; otherwise report.lua tries GPS itself
    report.set("mining", progressText(), job.gps and { pos = nav.getPos() } or nil)
  end
  unload("All dug out")
  nav.face(job.origin.heading)
  nav.deleteFile(JOB_FILE)
  print("Strip mine complete!")
  report.set("done", "strip mine complete")
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Job cancelled.")
  return
end

if not os.getComputerLabel() then os.setComputerLabel("StripMiner-" .. os.getComputerID()) end
job = nav.readFile(JOB_FILE)

-- With GPS, the turtle works in real world coordinates and re-checks its
-- position and facing every time it starts. A job started without GPS keeps
-- using the saved position, since its coordinates are relative to the start.
local hasGps = gpsPos() ~= nil
local useGps = hasGps and (not job or job.gps)
local knowsPosition = nav.init(useGps)

-- No GPS to check against: give the player a chance to say the turtle was moved.
local function confirmResume()
  print("No GPS, so I'm trusting my saved position.")
  print("Resuming in 10 seconds. If you moved me, press any key.")
  local timer = os.startTimer(10)
  while true do
    local event, value = os.pullEvent()
    if event == "timer" and value == timer then return true end
    if event == "key" then
      print("Put me back on my start block, facing the way I faced when")
      print("the job began, then run: stripmine here")
      return false
    end
  end
end

if args[1] == "resume" or args[1] == "here" then
  if not job then
    print("No job to resume.")
    return
  end
  buildPlan()
  if args[1] == "here" then
    -- the player has put the turtle back on its start block
    local x, y, z = toWorld(plan.start)
    nav.setPosition(x, y, z, job.origin.heading)
    print("Position reset to the start block.")
  elseif useGps then
    print("Checked my position with GPS.")
  else
    if job.gps then print("Can't reach GPS right now.") end
    if not knowsPosition then error("Lost track of position; can't resume. Run 'stripmine cancel'.", 0) end
    if not confirmResume() then return end
  end
  print("Resuming: " .. progressText())
elseif job then
  print("A job is already in progress. Run 'stripmine resume' or 'stripmine cancel'.")
  return
else
  local nums = {}
  for _, a in ipairs(args) do nums[#nums + 1] = tonumber(a) or -1 end
  local length, branch, gap = nums[1] or 64, nums[2] or 32, nums[3] or 3
  if length < 1 or branch < 0 or gap < 1 then
    print("Usage: stripmine [length] [branch] [gap]")
    return
  end
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  local p = nav.getPos()
  job = { length = length, branch = branch, gap = gap, cell = 0, gps = hasGps,
    origin = { x = p.x, y = p.y, z = p.z, heading = nav.getHeading() } }
  print(hasGps and "GPS found: I'll check my position as I go."
    or "No GPS: working from my own position count only.")
  buildPlan()

  local fuel = math.floor(#plan.cells * 1.3)
  print(("Main tunnel %d long, %d pairs of branches %d long, %d blocks apart."):format(
    length, #plan.branches, branch, gap))
  print(("Needs about %d fuel (have %s). I refuel from the chest"):format(fuel, tostring(turtle.getFuelLevel())))
  print("behind me, so put coal in it. Mined coal goes there too.")
  print(("Torches in my inventory get placed every %d blocks."):format(TORCH_EVERY))
  print("Chest goes directly behind me. Press Enter to start.")
  read()
  save()
  faceChest()
  refuelFromChest(REFUEL_TO)
  nav.face(job.origin.heading)
end

report.init("strip miner")
errlog.init("stripmine", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
