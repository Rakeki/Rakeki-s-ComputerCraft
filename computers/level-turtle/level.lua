-- Standalone land leveller (no server). Flattens a rectangle of land into a
-- solid building platform: digs away everything above the ground the turtle
-- stands on (hills, trees, leaves, snow, tall grass), then fills every dip,
-- pond and hole below that level with the dirt and stone it dug up.
--
--   level <x> <z> [y]     x blocks to the right, z forward, y high to clear (default: until the air is empty)
--   level resume
--   level here            you put me back on my start block (no GPS): carry on from there
--   level cancel
--
-- Place the turtle on the ground at one corner of the area, facing along one
-- edge: the block under it is the height the platform will be. The area runs
-- forward (z) and to the right (x). Put a chest directly behind it with some
-- coal in: wood, saplings and anything else it digs up go in there too, and
-- spare dirt and stone, which it takes back out when it fills holes.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.level_job"

-- With no height given, it clears at most this high above the ground...
local MAX_HEIGHT = 64
-- ...and stops once this many 3-block layers in a row had nothing in them.
local EMPTY_LAYERS = 2

-- Deepest it fills a hole below the platform. Anything deeper (a cave, a
-- deep lake) gets a plug this thick instead of being filled to the bottom.
local FILL_DEPTH = 8

-- Fill blocks kept on board (8 stacks); the rest go in the chest for later.
local FILL_CARRY = 512

-- Fuel it tops up to from the chest behind the start.
local REFUEL_TO = 5000

-- Blocks it fills holes with: the ones it digs out of hills.
local FILL = {}
for _, name in ipairs({
  "minecraft:dirt", "minecraft:coarse_dirt", "minecraft:rooted_dirt", "minecraft:cobblestone",
  "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:deepslate", "minecraft:andesite",
  "minecraft:diorite", "minecraft:granite", "minecraft:tuff", "minecraft:calcite", "minecraft:netherrack",
  "minecraft:sandstone",
}) do FILL[name] = true end

-- Thrown on the ground beside the start instead of filling the chest
-- (gravel falls, so it's no good for filling).
local JUNK = { ["minecraft:gravel"] = true, ["minecraft:flint"] = true }

-- Burnt before anything else.
local COAL = { "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block" }

-- Never burnt: the wood it chops is yours.
local WOOD = { "_log", "_wood", "planks", "sapling", "_stem", "hyphae", "leaves", "stick" }

local FLUIDS = { ["minecraft:water"] = true, ["minecraft:lava"] = true, ["minecraft:bubble_column"] = true }

-- Not ground, even below the platform: dug out and filled in.
local SOFT_TAGS = { "minecraft:leaves", "minecraft:logs", "minecraft:saplings", "minecraft:flowers",
  "minecraft:replaceable", "minecraft:replaceable_plants", "minecraft:wart_blocks" }
local SOFT_NAMES = { "leaves", "_log", "_wood", "_stem", "hyphae", "sapling", "mushroom", "vine", "snow",
  "grass", "fern", "flower", "bush", "roots", "carpet", "propagule", "kelp", "lily_pad", "sugar_cane",
  "bamboo", "cactus", "pumpkin", "melon", "cobweb", "dripleaf" }

local job, plan

local function isSoft(data)
  if data.name == "minecraft:grass_block" then return false end
  for _, t in ipairs(SOFT_TAGS) do
    if data.tags and data.tags[t] then return true end
  end
  for _, n in ipairs(SOFT_NAMES) do
    if data.name:find(n, 1, true) then return true end
  end
  return false
end

local function isGround(ok, data) return ok and not FLUIDS[data.name] and not isSoft(data) end

---------------------------------------------------------------- coordinates

-- Job coordinates are local to the start corner: x to the right, z forward,
-- y up. y = 0 is the turtle's start block, the first layer above the
-- platform; the platform's top is y = -1.
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
  local H = job.height or MAX_HEIGHT
  plan = { W = job.width, L = job.length, H = H, layers = math.ceil(H / 3), start = { x = 0, y = 0, z = 0 } }
  plan.per = plan.W * plan.L
end

-- Cell i of the clearing: 3-high layers from the ground up, snaking so
-- consecutive cells are next to each other. Returns where to stand and the layer.
local function clearCell(i)
  local layer, j = math.floor(i / plan.per), i % plan.per
  if layer % 2 == 1 then j = plan.per - 1 - j end
  local row, col = math.floor(j / plan.W), j % plan.W
  if row % 2 == 1 then col = plan.W - 1 - col end
  return { x = col, y = math.min(layer * 3 + 1, plan.H - 1), z = row }, layer
end

-- Cell i of the filling: one pass over the area just above the platform.
local function fillCell(i)
  local row, col = math.floor(i / plan.W), i % plan.W
  if row % 2 == 1 then col = plan.W - 1 - col end
  return { x = col, y = 0, z = row }
end

local function phaseSize(phase)
  if phase == 0 then return plan.layers * plan.per end
  return plan.per
end

---------------------------------------------------------------- position checks

local reach -- defined below; used by the trips home

local gpsPos = nav.locate

-- Somewhere the turtle is meant to be: over the area (or down a hole it's filling), or on its start block.
local function onPlan(p)
  return p.x >= 0 and p.x < plan.W and p.z >= 0 and p.z < plan.L and p.y >= 1 - FILL_DEPTH and p.y < plan.H
end

-- If the turtle finds itself off its route (picked up and put down
-- somewhere else, say), head for the start block before carrying on.
local function rejoin()
  if onPlan(here()) then return end
  local w = nav.getPos()
  print(("Off my route at %d,%d,%d. Heading back to the start first."):format(w.x, w.y, w.z))
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

local fuelLevel = inv.fuelLevel

local emptySlots = inv.emptySlots

local function burnable(name)
  for _, w in ipairs(WOOD) do
    if name:find(w, 1, true) then return false end
  end
  return true
end

-- coal first, then anything else that burns except wood
local function refuelFromInventory(target)
  inv.refuel(target, COAL)
  if fuelLevel() < target then inv.refuel(target, burnable) end
end

local function homeDistance()
  local p = here()
  return math.abs(p.x) + math.abs(p.y) + math.abs(p.z) + 50
end

local function faceChest() nav.face((job.origin.heading + 2) % 4) end

-- Outside the area, beside the start: where junk goes.
local function faceJunk() nav.face((job.origin.heading + 3) % 4) end

-- Facing the chest at the start: take fuel out of it until reaching target.
-- Anything that isn't fuel (or fuel left over, or wood) goes back in.
local function refuelFromChest(target)
  local putBack = {}
  for slot = 1, 16 do
    if fuelLevel() >= target then break end
    if turtle.getItemCount(slot) == 0 then
      turtle.select(slot)
      if not turtle.suck() then break end -- chest is empty
      local item = turtle.getItemDetail(slot)
      if not item then
        refuelFromInventory(target) -- it stacked onto fuel already on board
      else
        if burnable(item.name) then
          while fuelLevel() < target and turtle.refuel(1) do end
        end
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

-- Facing the chest: take fill blocks out of it, up to FILL_CARRY. Anything
-- else it pulls out on the way goes back in.
local function takeFill()
  local putBack = {}
  for slot = 1, 16 do
    if inv.count(FILL) >= FILL_CARRY then break end
    if turtle.getItemCount(slot) == 0 then
      turtle.select(slot)
      if not turtle.suck() then break end -- chest is empty
      local item = turtle.getItemDetail(slot)
      if item and not FILL[item.name] then putBack[#putBack + 1] = slot end
    end
  end
  for _, slot in ipairs(putBack) do
    turtle.select(slot)
    turtle.drop()
  end
  turtle.select(1)
end

-- At the start: fill blocks up to FILL_CARRY stay on board, everything else
-- goes in the chest. Junk, and fill the chest has no room for, goes on the
-- ground beside the start, outside the platform.
local function unload()
  print("Inventory full, emptying into the chest")
  report.set("unloading", "inventory full")
  reach(plan.start)
  faceChest()
  local warned = false
  while true do
    local full, kept = false, 0
    for slot = 1, 16 do
      local item = turtle.getItemDetail(slot)
      if item then
        if FILL[item.name] and kept < FILL_CARRY then
          kept = kept + item.count
        elseif not JUNK[item.name] then
          turtle.select(slot)
          if not turtle.drop() and not FILL[item.name] then full = true end
        end
      end
    end
    if not full then break end
    if not warned then
      print("Chest behind the start is missing or full. Waiting...")
      report.set("waiting", "chest full or missing")
      warned = true
    end
    sleep(5)
  end
  faceJunk()
  local kept = 0
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      if FILL[item.name] and kept < FILL_CARRY then
        kept = kept + item.count
      elseif FILL[item.name] or JUNK[item.name] then
        turtle.select(slot)
        turtle.drop()
      end
    end
  end
  turtle.select(1)
  -- while here, top up from any fuel in the chest
  faceChest()
  if fuelLevel() < REFUEL_TO then refuelFromChest(REFUEL_TO) end
end

-- Go home and refuel from the chest there. If it hasn't got enough, wait for
-- the player to add fuel to the chest or to the turtle.
local function waitForFuel(target)
  reach(plan.start)
  faceChest()
  if emptySlots() < 2 then unload() faceChest() end
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

-- Out of fill blocks: go home, empty out, take any from the chest, or wait
-- for the player to put some in the chest or the turtle.
local function restockFill()
  unload()
  faceChest()
  takeFill()
  if inv.select(FILL) then return end
  print("Out of dirt or stone to fill holes with. Put some in the chest behind me or in my inventory.")
  report.set("waiting", "needs dirt or stone")
  while not inv.select(FILL) do
    local timer = os.startTimer(10)
    repeat
      local event, value = os.pullEvent()
    until event == "turtle_inventory" or (event == "timer" and value == timer)
    takeFill()
  end
  turtle.select(1)
end

local function housekeeping()
  if emptySlots() <= 1 then unload() end
  local needed = homeDistance()
  if fuelLevel() < needed then
    refuelFromInventory(needed + 1000)
    if fuelLevel() < needed then waitForFuel(needed + 1000) end
  end
end

-- Get to p. If the spot itself can't be cleared (bedrock or a protected
-- block like a chest), give up on it. If something is blocking the way
-- there, stop and say so, and keep retrying, rather than skipping ahead.
reach = function(p)
  local tries = 0
  while true do
    local ok, err = goL(p)
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
  if job.phase == 0 then
    local layer = math.floor(job.cell / plan.per)
    return ("clearing %d-%d blocks up, %d%% of that layer"):format(layer * 3 + 1, math.min(layer * 3 + 3, plan.H),
      math.floor(job.cell % plan.per / plan.per * 100))
  end
  return ("filling holes, %d%%"):format(math.floor(job.cell / plan.per * 100))
end

-- Water or lava left above the platform would run onto it: turn the source
-- into a fill block and dig that out so the space ends up empty.
local function clearFluid(inspect, place, dig)
  local ok, data = inspect()
  if ok and FLUIDS[data.name] and inv.select(FILL) then
    place()
    dig()
  end
  turtle.select(1)
end

-- Clear one spot of a layer: the block it stands in, and the ones above and
-- below that are in the layer. Notes whether there was anything there, so
-- with no height given it knows when it has reached open sky.
local function clearAt(p, layer)
  local h = here()
  if h.y == p.y and math.abs(h.x - p.x) + math.abs(h.z - p.z) == 1 then
    -- the block it's about to step into is next door: look before it digs
    local d = p.z > h.z and 0 or p.x > h.x and 1 or p.z < h.z and 2 or 3
    nav.face((job.origin.heading + d) % 4)
    if turtle.detect() then job.found = true end
  end
  if not reach(p) then return end -- bedrock or a protected block: skip
  if p.y + 1 <= plan.H - 1 then
    if turtle.detectUp() then job.found = true end
    nav.digUp()
    clearFluid(turtle.inspectUp, turtle.placeUp, turtle.digUp)
  end
  if p.y - 1 >= layer * 3 then
    if turtle.detectDown() then job.found = true end
    nav.digDown()
    clearFluid(turtle.inspectDown, turtle.placeDown, turtle.digDown)
  end
end

-- Make the block under the turtle solid ground: dig out leaves, logs or
-- plants, then put a fill block in anything that isn't solid (air, water,
-- lava). False if it has no fill blocks left.
local function solidBelow()
  local ok, data = turtle.inspectDown()
  if isGround(ok, data) then return true end
  if ok and not FLUIDS[data.name] then nav.digDown() end
  if turtle.detectDown() then return true end -- a protected block: leave it
  if not inv.select(FILL) then return false end
  turtle.placeDown()
  turtle.select(1)
  return true
end

-- Fill the hole (if any) under one spot: go down through anything that isn't
-- ground, as far as FILL_DEPTH, then come back up filling in under itself.
local function fillAt(p)
  if not reach(p) then return end
  while here().y > 1 - FILL_DEPTH do
    local ok, data = turtle.inspectDown()
    if isGround(ok, data) then break end
    if ok and not FLUIDS[data.name] then nav.digDown() end
    if turtle.detectDown() or not nav.down() then break end
  end
  while true do
    if not solidBelow() then
      restockFill()
      return fillAt(p) -- what's filled already is ground now, so it stops on top of it
    end
    if here().y >= p.y or not nav.up() then break end
  end
end

local function sendStatus()
  -- only GPS jobs have real world coordinates; otherwise report.lua tries GPS itself
  report.set(job.phase == 0 and "clearing" or "filling", progressText(), job.gps and { pos = nav.getPos() } or nil)
end

local function run()
  rejoin()
  while job.phase == 0 and job.cell < phaseSize(0) do
    clearAt(clearCell(job.cell))
    job.cell = job.cell + 1
    if job.cell % plan.per == 0 then
      -- a whole layer done: with no height given, stop once the air above is empty
      job.emptyLayers = job.found and 0 or job.emptyLayers + 1
      job.found = false
      if not job.height and job.emptyLayers >= EMPTY_LAYERS then job.cell = phaseSize(0) end
    end
    save()
    if job.cell % 20 == 0 then checkPosition() end
    housekeeping()
    if job.cell % 25 == 0 then print(progressText()) end
    sendStatus()
  end
  if job.phase == 0 then
    job.phase, job.cell = 1, 0
    save()
    print("Cleared above. Now filling the holes.")
  end
  while job.cell < phaseSize(1) do
    fillAt(fillCell(job.cell))
    job.cell = job.cell + 1
    save()
    if job.cell % 20 == 0 then checkPosition() end
    housekeeping()
    if job.cell % 25 == 0 then print(progressText()) end
    sendStatus()
  end

  reach(plan.start)
  nav.face(job.origin.heading)
  nav.deleteFile(JOB_FILE)
  print("Levelling complete! The platform is flat and solid.")
  report.set("done", "levelling complete")
end

local USAGE = "Usage: level <x> <z> [y]   (x to my right, z forward, y high to clear)"

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Job cancelled.")
  return
end

if not os.getComputerLabel() then os.setComputerLabel("Leveller-" .. os.getComputerID()) end
job = nav.readFile(JOB_FILE)

-- With GPS, the turtle works in real world coordinates and re-checks its
-- position and facing every time it starts. A job started without GPS keeps
-- using the saved position, since its coordinates are relative to the start.
local hasGps = gpsPos() ~= nil
local useGps = hasGps and (not job or job.gps)
local knowsPosition = nav.init(useGps)

-- No GPS to check against: give the player a chance to say the turtle was moved.
local function confirmResume()
  return nav.confirmResume("Put me back on my start block, facing the way I faced when\nthe job began, then run: level here")
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
    if not knowsPosition then error("Lost track of position; can't resume. Run 'level cancel'.", 0) end
    if not confirmResume() then return end
  end
  print("Resuming: " .. progressText())
elseif job then
  print("A job is already in progress. Run 'level resume' or 'level cancel'.")
  return
else
  local w, l = tonumber(args[1]), tonumber(args[2])
  local h = args[3] and args[3] ~= "auto" and tonumber(args[3]) or nil
  if not w or not l or w < 1 or l < 1 or (args[3] and args[3] ~= "auto" and (not h or h < 1)) then
    print(USAGE)
    return
  end
  w, l = math.floor(w), math.floor(l)
  if h then h = math.floor(h) end
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  local p = nav.getPos()
  job = { width = w, length = l, height = h, phase = 0, cell = 0, found = false, emptyLayers = 0, gps = hasGps,
    origin = { x = p.x, y = p.y, z = p.z, heading = nav.getHeading() } }
  print(hasGps and "GPS found: I'll check my position as I go."
    or "No GPS: working from my own position count only.")
  buildPlan()

  -- with no height given, guess a few layers: most land needs two or three
  local layers = h and plan.layers or 4
  local fuel = math.floor(plan.per * (layers + 1.5) * 1.15)
  if h then
    print(("Platform %dx%d, clearing %d high above it."):format(w, l, h))
  else
    print(("Platform %dx%d, clearing up until the sky is clear."):format(w, l))
  end
  print(("Holes below get filled, up to %d deep."):format(FILL_DEPTH))
  print(("Needs about %d fuel (have %s). I refuel from the chest"):format(fuel, tostring(turtle.getFuelLevel())))
  print("behind me, so put coal in it. Wood goes there too.")
  print("Chest goes directly behind me. Press Enter to start.")
  read()
  save()
  faceChest()
  refuelFromChest(REFUEL_TO)
  nav.face(job.origin.heading)
end

report.init("leveller")
errlog.init("level", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
