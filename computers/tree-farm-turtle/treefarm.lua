-- Tree farm. Plants a grid of saplings, then walks the farm over and over:
-- chops every tree that has grown, replants it, picks up saplings and apples
-- that fell from the leaves, and takes the logs back to a chest.
--
--   treefarm [columns] [rows] [spacing]    (default 4 6 3)
--   treefarm resume
--   treefarm here
--   treefarm cancel
--
-- Place the turtle on the ground at a corner of the farm, facing along one
-- edge. Trees go forward and to the right of it, on dirt or grass. Put a chest
-- directly behind the turtle and give the turtle saplings, some coal, and
-- bone meal if you like.
--
-- The turtle walks in lanes beside each column of trees, so it never has to
-- go through a tree to get anywhere. Lanes run along the left of each column;
-- the end rows (in front of the first tree and past the last) link them.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.treefarm_job"

local ROUND_WAIT = 180 -- seconds to wait at the chest between rounds
local MAX_TRUNK = 32 -- never climbs higher than this while chopping
local KEEP_SAPLINGS = 64 -- saplings kept on board when unloading; the rest go in the chest
local BONEMEAL_TRIES = 2 -- bone meal used on each young sapling it passes (if it has any)

-- Fuel: coal or charcoal in its inventory is kept when unloading. It also
-- burns some of the logs it chops when its fuel runs low.
local BURN_LOGS = true
local LOG_FUEL_TO = 1000 -- burns logs up to this much fuel, at the chest

local FUEL = {
  ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true,
  ["minecraft:blaze_rod"] = true,
}
local BONE_MEAL = "minecraft:bone_meal"

local job, plan

---------------------------------------------------------------- coordinates

-- Job coordinates are local to the start block: x to the right, z forward,
-- y up. Directions are offsets from the job's forward heading: 0 forward,
-- 1 right, 2 back (the chest), 3 left.
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
local function faceL(d) nav.face((job.origin.heading + d) % 4) end

---------------------------------------------------------------- plan

-- Tree i (0-based), visited lane by lane, snaking: up the first lane, down
-- the next. The turtle stands in the lane just left of the tree.
local function buildPlan()
  local S = job.spacing
  plan = {
    start = { x = 0, y = 0, z = 0 },
    total = job.cols * job.rows,
    farZ = (job.rows - 1) * S + 2, -- the end row past the last tree
    lastLane = (job.cols - 1) * S,
  }
end

local function spot(i)
  local c, j = math.floor(i / job.rows), i % job.rows
  local r = c % 2 == 0 and j or job.rows - 1 - j
  local stand = { x = c * job.spacing, y = 0, z = 1 + r * job.spacing }
  return stand, { x = stand.x + 1, y = 0, z = stand.z }
end

local function isLane(p) return p.x % job.spacing == 0 and p.x >= 0 and p.x <= plan.lastLane end
local function isEndRow(p) return p.z == 0 or p.z == plan.farZ end

local function onPlan(p)
  if p.x < 0 or p.x > plan.lastLane + 1 or p.z < 0 or p.z > plan.farZ then return false end
  if p.y == 0 then return true end
  return p.y > 0 and p.y <= MAX_TRUNK and p.x % job.spacing == 1 -- up a tree, chopping
end

---------------------------------------------------------------- moving

-- One axis at a time along a lane or end row, picking up anything lying in
-- the way (saplings and apples dropped by the leaves).
local function walk(t)
  while true do
    local p = here()
    if p.x == t.x and p.z == t.z then return true end
    if p.x ~= t.x then faceL(t.x > p.x and 1 or 3) else faceL(t.z > p.z and 0 or 2) end
    turtle.suck()
    local ok, err = nav.forward()
    if not ok then return false, err end
  end
end

-- After a reboot part-way up a tree, or beside one: get back to the ground
-- and into a lane or end row, where it's safe to walk.
local function toLane()
  local p = here()
  if p.y ~= 0 then
    local ok, err = goL({ x = p.x, y = 0, z = p.z })
    if not ok then return false, err end
  end
  if isLane(p) or isEndRow(p) then return true end
  local m = p.x % job.spacing
  -- the tree column is just right of a lane; gaps are left of the next lane
  return walk({ x = m == 1 and p.x - 1 or p.x + job.spacing - m, z = p.z })
end

-- Lanes only meet at the end rows, so change lanes along the nearer one.
local function travel(t)
  local ok, err = toLane()
  if not ok then return false, err end
  local p = here()
  if p.x ~= t.x then
    local endZ = (p.z + t.z <= 2 * plan.farZ - p.z - t.z) and 0 or plan.farZ
    ok, err = walk({ x = p.x, z = endZ })
    if not ok then return false, err end
    ok, err = walk({ x = t.x, z = endZ })
    if not ok then return false, err end
  end
  return walk(t)
end

---------------------------------------------------------------- inventory and fuel

local function save() nav.writeFile(JOB_FILE, job) end

local fuelLevel = inv.fuelLevel

local function isSapling(name) return name:find("_sapling", 1, true) ~= nil or name == "minecraft:mangrove_propagule" end
local function isLog(name) return name:find("_log", 1, true) ~= nil or name:find("_stem", 1, true) ~= nil end

local emptySlots = inv.emptySlots

local function countItems(match)
  local n = 0
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and match(item.name) then n = n + item.count end
  end
  return n
end

local selectItem = inv.select

-- Burn items matching match until reaching target. Never burns saplings.
local function refuelWith(match, target)
  for slot = 1, 16 do
    if fuelLevel() >= target then break end
    local item = turtle.getItemDetail(slot)
    if item and match(item.name) then
      turtle.select(slot)
      while fuelLevel() < target and turtle.refuel(1) do end
    end
  end
  turtle.select(1)
end

local function isFuel(name) return FUEL[name] or (BURN_LOGS and isLog(name)) end

local function homeDistance()
  local p = here()
  return p.x + p.z + math.max(p.y, 0) + 2 * MAX_TRUNK + 20
end

local function faceChest() faceL(2) end

local reach -- defined below

-- At the chest: burn logs if fuel is low, then put everything in the chest
-- except saplings (up to KEEP_SAPLINGS), bone meal and coal.
local function unload()
  reach(plan.start)
  if BURN_LOGS and fuelLevel() < LOG_FUEL_TO then refuelWith(isLog, LOG_FUEL_TO) end
  faceChest()
  local saplings, warned = 0, false
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      local keep = 0
      if isSapling(item.name) then
        keep = math.max(0, math.min(item.count, KEEP_SAPLINGS - saplings))
        saplings = saplings + keep
      elseif item.name == BONE_MEAL or FUEL[item.name] then
        keep = item.count
      end
      turtle.select(slot)
      while turtle.getItemCount(slot) > keep do
        if not turtle.drop(turtle.getItemCount(slot) - keep) then
          if not warned then
            print("Chest behind the start is missing or full. Waiting...")
            report.set("waiting", "chest full or missing")
            warned = true
          end
          sleep(5)
        end
      end
    end
  end
  turtle.select(1)
end

-- Go home and wait for the player to give it fuel.
local function waitForFuel(target)
  reach(plan.start)
  faceChest()
  print(("Need %d fuel, have %d. Put coal or charcoal in my inventory."):format(target, fuelLevel()))
  report.set("waiting", ("needs fuel (%d)"):format(target))
  while fuelLevel() < target do
    os.pullEvent("turtle_inventory")
    refuelWith(isFuel, target)
  end
end

local function housekeeping()
  if emptySlots() <= 1 then unload() end
  local needed = homeDistance()
  if fuelLevel() < needed then
    refuelWith(isFuel, needed + 500)
    if fuelLevel() < needed then waitForFuel(needed + 500) end
  end
end

---------------------------------------------------------------- position checks

local gpsPos = nav.locate

local function rejoin()
  if onPlan(here()) then return end
  local w = nav.getPos()
  print(("Off the farm at %d,%d,%d. Heading back to the start first."):format(w.x, w.y, w.z))
  goL(plan.start)
end

local function checkPosition()
  if not job.gps then return end
  local g = gpsPos()
  if not g then return end
  local p = nav.getPos()
  if g.x ~= p.x or g.y ~= p.y or g.z ~= p.z then
    print(("Position was off: thought %d,%d,%d, GPS says %d,%d,%d. Correcting."):format(p.x, p.y, p.z, g.x, g.y, g.z))
    nav.init()
    rejoin()
  end
end

-- Get to p, retrying (and saying why) if something it won't dig is in the way.
reach = function(p)
  local tries = 0
  while true do
    local ok, err = travel(p)
    if ok then return end
    tries = tries + 1
    if err == "nofuel" then
      print("Out of fuel here. Put coal in my inventory.")
      report.set("waiting", "out of fuel")
      while fuelLevel() == 0 do
        refuelWith(isFuel, 500)
        if fuelLevel() == 0 then os.pullEvent("turtle_inventory") end
      end
    else
      local w = nav.getPos()
      local msg = ("Stuck at %d,%d,%d (%s)"):format(w.x, w.y, w.z, tostring(err))
      print(msg .. ". Clear the way; retrying.")
      report.set("stuck", msg)
      checkPosition()
      sleep(math.min(60, 5 * tries))
    end
  end
end

---------------------------------------------------------------- trees

local warnedSpots = {} -- trees it couldn't plant, so it only says so once

local function statusText()
  return ("round %d, tree %d/%d, %d logs so far"):format(job.round, math.min(job.tree + 1, plan.total), plan.total, job.logs)
end

-- Facing the trunk from the lane: step into it and chop straight up, then
-- come back down and out. Also finishes a tree it was part-way up.
local function chop(tree, stand)
  job.chopping = true
  save()
  local ok, data = turtle.inspect()
  if ok and isLog(data.name) then job.logs = job.logs + 1 end
  if not nav.forward() then return end
  local height = 0
  while height < MAX_TRUNK do
    local ok, above = turtle.inspectUp()
    if not (ok and isLog(above.name)) then break end
    if not nav.up() then break end
    job.logs = job.logs + 1
    height = height + 1
  end
  goL(tree)
  walk(stand)
end

local function plant(i)
  faceL(1)
  if not selectItem(isSapling) then
    if not warnedSpots.none then
      print("Out of saplings. Put some in my inventory (they also drop from the leaves).")
      warnedSpots.none = true
    end
    return
  end
  if turtle.place() then
    warnedSpots.none = nil
  elseif not warnedSpots[i] then
    print(("Can't plant tree %d: it needs dirt or grass under it and nothing in the way."):format(i + 1))
    warnedSpots[i] = true
  end
  turtle.select(1)
end

local function bonemeal()
  for _ = 1, BONEMEAL_TRIES do
    if not selectItem(function(name) return name == BONE_MEAL end) then break end
    turtle.place()
    local ok, data = turtle.inspect()
    if not (ok and isSapling(data.name)) then break end -- it grew
  end
  turtle.select(1)
end

-- Visit tree i: chop it if it has grown, replant if the spot is empty.
local function tend(i)
  local stand, tree = spot(i)
  reach(stand)
  faceL(1)
  turtle.suck() -- anything dropped on the tree's spot
  local ok, data = turtle.inspect()
  if (ok and isLog(data.name)) or (job.chopping and not ok) then
    chop(tree, stand)
    faceL(1)
    ok, data = turtle.inspect()
  end
  if not ok or not (isSapling(data.name) or isLog(data.name)) then
    plant(i)
    ok, data = turtle.inspect()
  end
  if ok and isSapling(data.name) then bonemeal() end
  if job.chopping then
    job.chopping = false
    save()
  end
end

---------------------------------------------------------------- main

local function run()
  rejoin()
  while true do
    while job.tree < plan.total do
      report.set("farming", statusText(), job.gps and { pos = nav.getPos() } or nil)
      tend(job.tree)
      job.tree = job.tree + 1
      save()
      if job.tree % 10 == 0 then checkPosition() end
      housekeeping()
    end
    print(("Round %d done: %d logs so far."):format(job.round, job.logs))
    report.set("unloading", "end of round")
    unload()
    nav.face(job.origin.heading)
    report.set("waiting", ("next round in %ds, %d logs so far"):format(ROUND_WAIT, job.logs), job.gps and { pos = nav.getPos() } or nil)
    sleep(ROUND_WAIT)
    job.tree, job.round = 0, job.round + 1
    save()
  end
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Farm stopped. Run 'treefarm' to set up a new one.")
  return
end

if not os.getComputerLabel() then os.setComputerLabel("TreeFarm-" .. os.getComputerID()) end
job = nav.readFile(JOB_FILE)

local hasGps = gpsPos() ~= nil
local useGps = hasGps and (not job or job.gps)
local knowsPosition = nav.init(useGps)

local function confirmResume()
  return nav.confirmResume("Put me back on my start block, facing the way I faced when\nthe farm began, then run: treefarm here")
end

if args[1] == "resume" or args[1] == "here" then
  if not job then
    print("No farm to resume.")
    return
  end
  buildPlan()
  if args[1] == "here" then
    local x, y, z = toWorld(plan.start)
    nav.setPosition(x, y, z, job.origin.heading)
    print("Position reset to the start block.")
  elseif useGps then
    print("Checked my position with GPS.")
  else
    if job.gps then print("Can't reach GPS right now.") end
    if not knowsPosition then error("Lost track of position; can't resume. Run 'treefarm cancel'.", 0) end
    if not confirmResume() then return end
  end
  print("Resuming: " .. statusText())
elseif job then
  print("A farm is already running. Run 'treefarm resume' or 'treefarm cancel'.")
  return
else
  local cols, rows, spacing = tonumber(args[1]) or 4, tonumber(args[2]) or 6, tonumber(args[3]) or 3
  if cols < 1 or rows < 1 or spacing < 2 or spacing > 8 then
    print("Usage: treefarm [columns] [rows] [spacing]")
    print("Spacing is 2 to 8 blocks from one tree to the next.")
    return
  end
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  local p = nav.getPos()
  job = { cols = cols, rows = rows, spacing = spacing, tree = 0, round = 1, logs = 0, gps = hasGps,
    origin = { x = p.x, y = p.y, z = p.z, heading = nav.getHeading() } }
  buildPlan()
  print(hasGps and "GPS found: I'll check my position as I go."
    or "No GPS: working from my own position count only.")
  local width, length = plan.lastLane + 2, plan.farZ + 1
  print(("%d trees in %d columns of %d, %d apart. The farm is %d wide and %d long."):format(plan.total, cols, rows, spacing, width, length))
  local saplings = countItems(isSapling)
  if saplings < plan.total then
    print(("I have %d saplings; %d would plant every spot."):format(saplings, plan.total))
  end
  print("Coal in my inventory stays there; I burn logs too when I'm low.")
  print("Chest goes directly behind me. Press Enter to start.")
  read()
  save()
end

report.init("tree farm")
errlog.init("treefarm", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
