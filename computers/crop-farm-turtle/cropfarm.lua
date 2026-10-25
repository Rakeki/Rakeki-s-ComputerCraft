-- Crop farm. Flies over a field of wheat, carrots, potatoes, beetroot or
-- nether wart, harvests whatever is fully grown, replants it from the seeds it
-- just picked, and takes the harvest back to a chest. Then waits and goes
-- round again. Melons and pumpkins are picked too (their stems are left).
--
--   cropfarm [width] [length]    (default 9 9)
--   cropfarm resume
--   cropfarm here
--   cropfarm cancel
--
-- Place the turtle one block above the crops, over a corner of the field,
-- facing along one edge. The field runs forward (length) and to the right
-- (width) from the block under the turtle. Put a chest directly behind the
-- turtle, and some coal in the turtle.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.cropfarm_job"

local ROUND_WAIT = 600 -- seconds to wait at the chest between rounds
local KEEP_SEEDS = 64 -- of each kind of seed, kept on board when unloading
local USE_BONEMEAL = true -- put bone meal (if it has any) on crops that aren't ready yet

-- Crop block, the age it's ready at, and what replants it.
local CROPS = {
  ["minecraft:wheat"] = { age = 7, seed = "minecraft:wheat_seeds" },
  ["minecraft:carrots"] = { age = 7, seed = "minecraft:carrot" },
  ["minecraft:potatoes"] = { age = 7, seed = "minecraft:potato" },
  ["minecraft:beetroots"] = { age = 3, seed = "minecraft:beetroot_seeds" },
  ["minecraft:nether_wart"] = { age = 3, seed = "minecraft:nether_wart" },
}
-- Picked whenever it flies over one.
local GOURDS = { ["minecraft:melon"] = true, ["minecraft:pumpkin"] = true }

local FUEL = {
  ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true,
  ["minecraft:blaze_rod"] = true, ["minecraft:dried_kelp_block"] = true,
}
local BONE_MEAL = "minecraft:bone_meal"

local SEEDS = {} -- seed item -> true
for _, crop in pairs(CROPS) do SEEDS[crop.seed] = true end

local job, plan

---------------------------------------------------------------- coordinates

-- Job coordinates are local to the start block: x to the right, z forward,
-- y up. The crops are at y = -1, under the turtle.
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

local function buildPlan()
  plan = { start = { x = 0, y = 0, z = 0 }, total = job.width * job.length }
end

-- Cell i of the field, snaking row by row so each cell is next to the last.
local function cell(i)
  local z, j = math.floor(i / job.width), i % job.width
  return { x = z % 2 == 0 and j or job.width - 1 - j, y = 0, z = z }
end

local function onPlan(p)
  return p.y == 0 and p.x >= 0 and p.x < job.width and p.z >= 0 and p.z < job.length
end

---------------------------------------------------------------- inventory and fuel

local function save() nav.writeFile(JOB_FILE, job) end

local fuelLevel = inv.fuelLevel

local emptySlots = inv.emptySlots

local selectItem = inv.select

local function refuelFromInventory(target) inv.refuel(target, FUEL) end

local function homeDistance()
  local p = here()
  return math.abs(p.x) + math.abs(p.z) + 20
end

local function faceChest() nav.face((job.origin.heading + 2) % 4) end

local reach -- defined below

-- At the chest: keep coal, bone meal and up to KEEP_SEEDS of each seed;
-- everything else goes in the chest.
local function unload()
  reach(plan.start)
  faceChest()
  local kept, warned = {}, false
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      local keep = 0
      if SEEDS[item.name] then
        keep = math.max(0, math.min(item.count, KEEP_SEEDS - (kept[item.name] or 0)))
        kept[item.name] = (kept[item.name] or 0) + keep
      elseif FUEL[item.name] or item.name == BONE_MEAL then
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

local function waitForFuel(target)
  reach(plan.start)
  print(("Need %d fuel, have %d. Put coal or charcoal in my inventory."):format(target, fuelLevel()))
  report.set("waiting", ("needs fuel (%d)"):format(target))
  while fuelLevel() < target do
    os.pullEvent("turtle_inventory")
    refuelFromInventory(target)
  end
end

local function housekeeping()
  if emptySlots() <= 1 then unload() end
  local needed = homeDistance()
  if fuelLevel() < needed then
    refuelFromInventory(needed + 500)
    if fuelLevel() < needed then waitForFuel(needed + 500) end
  end
end

---------------------------------------------------------------- position checks

local gpsPos = nav.locate

-- Off the field (picked up and put down somewhere else): back to the start.
-- It flies at crop height + 1, so going straight there is fine.
local function rejoin()
  if onPlan(here()) then return end
  local w = nav.getPos()
  print(("Off the field at %d,%d,%d. Heading back to the start first."):format(w.x, w.y, w.z))
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

reach = function(p)
  local tries = 0
  while true do
    local ok, err = goL(p)
    if ok then return end
    tries = tries + 1
    if err == "nofuel" then
      print("Out of fuel here. Put coal in my inventory.")
      report.set("waiting", "out of fuel")
      while fuelLevel() == 0 do
        refuelFromInventory(500)
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

---------------------------------------------------------------- crops

local lastCrop -- the crop most recently seen, planted on empty farmland
local warnedSeeds = {}

local function statusText()
  return ("round %d, %d%% of the field, %d harvested"):format(job.round, math.floor(job.cell / plan.total * 100), job.harvested)
end

local function plant(crop)
  local seed = CROPS[crop].seed
  if not selectItem(seed) then
    if not warnedSeeds[seed] then
      print(("Out of %s to replant with."):format(seed))
      warnedSeeds[seed] = true
    end
    return
  end
  warnedSeeds[seed] = nil
  turtle.placeDown()
  turtle.select(1)
end

local function tendCell()
  local ok, data = turtle.inspectDown()
  if ok and CROPS[data.name] then
    local crop = CROPS[data.name]
    lastCrop = data.name
    if data.state and data.state.age and data.state.age >= crop.age then
      turtle.digDown() -- the harvest and seeds go straight into the inventory
      job.harvested = job.harvested + 1
      plant(data.name)
    elseif USE_BONEMEAL and selectItem(BONE_MEAL) then
      turtle.placeDown()
      turtle.select(1)
    end
  elseif ok and GOURDS[data.name] then
    turtle.digDown()
    job.harvested = job.harvested + 1
  elseif not ok and lastCrop then
    -- Empty: farmland that was harvested and not replanted (out of seeds,
    -- or a reboot in between). Seeds only go on farmland, so trying is safe.
    plant(lastCrop)
  end
end

---------------------------------------------------------------- main

local function run()
  rejoin()
  while true do
    while job.cell < plan.total do
      reach(cell(job.cell))
      tendCell()
      job.cell = job.cell + 1
      save()
      if job.cell % 20 == 0 then checkPosition() end
      housekeeping()
      if job.cell % job.width == 0 then
        report.set("farming", statusText(), job.gps and { pos = nav.getPos() } or nil)
      end
    end
    print(("Round %d done: %d harvested so far."):format(job.round, job.harvested))
    report.set("unloading", "end of round")
    unload()
    nav.face(job.origin.heading)
    report.set("waiting", ("next round in %ds, %d harvested so far"):format(ROUND_WAIT, job.harvested), job.gps and { pos = nav.getPos() } or nil)
    sleep(ROUND_WAIT)
    job.cell, job.round = 0, job.round + 1
    save()
  end
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Farm stopped. Run 'cropfarm' to set up a new one.")
  return
end

if not os.getComputerLabel() then os.setComputerLabel("CropFarm-" .. os.getComputerID()) end
job = nav.readFile(JOB_FILE)

local hasGps = gpsPos() ~= nil
local useGps = hasGps and (not job or job.gps)
local knowsPosition = nav.init(useGps)

local function confirmResume()
  return nav.confirmResume("Put me back on my start block, facing the way I faced when\nthe farm began, then run: cropfarm here")
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
    if not knowsPosition then error("Lost track of position; can't resume. Run 'cropfarm cancel'.", 0) end
    if not confirmResume() then return end
  end
  print("Resuming: " .. statusText())
elseif job then
  print("A farm is already running. Run 'cropfarm resume' or 'cropfarm cancel'.")
  return
else
  local w, l = tonumber(args[1]) or 9, tonumber(args[2]) or 9
  if w < 1 or l < 1 then
    print("Usage: cropfarm [width] [length]")
    return
  end
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  local p = nav.getPos()
  job = { width = w, length = l, cell = 0, round = 1, harvested = 0, gps = hasGps,
    origin = { x = p.x, y = p.y, z = p.z, heading = nav.getHeading() } }
  buildPlan()
  print(hasGps and "GPS found: I'll check my position as I go."
    or "No GPS: working from my own position count only.")
  print(("Field %d wide and %d long, starting under me. About %d fuel a round."):format(w, l, plan.total + w + l))
  print("I fly one block above the crops, so keep that layer clear.")
  print("Coal in my inventory stays there. Chest goes directly behind me.")
  print("Press Enter to start.")
  read()
  save()
end

report.init("crop farm")
errlog.init("cropfarm", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
