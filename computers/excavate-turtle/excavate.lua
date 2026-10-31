-- Standalone excavator (no server). Digs out a box-shaped hole, then walks
-- its edge and fills every gap in the walls, floor and ceiling (caves,
-- ravines, water, lava) so the hole ends up dry and fully walled in. Nothing
-- is built inside it: builder turtles do the inner walls and details.
--
--   excavate [width] [length] [height] [up|down|deep]    (default 21 21 16 up)
--   excavate atrium [up|down|deep]   a 60x60x30 hole, for plans/atrium.lua
--   excavate resume
--   excavate here       you put me back on my start block (no GPS): carry on from there
--   excavate cancel
--
-- Place the turtle in a corner of the area, facing along one edge. The hole
-- runs forward (length), to the right (width), and up or down (height) from
-- the turtle's block. Put a chest directly behind the turtle for loot.
--
-- "deep" digs a shaft straight down from the turtle and digs the hole
-- centred underneath it, with its floor ABOVE_BEDROCK layers above bedrock.
-- The turtle comes back up the shaft to the chest.
--
-- "atrium" is the size plans/atrium.lua fills (a centre atrium between two
-- wings, two floors) through build-control and a builder turtle. It prints
-- the build command when it's done.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.excavate_job"
local JOB_VERSION = 2 -- jobs from before rooms, ledge and stairs were dropped have none

-- After digging, walk the edge of the hole (and the deep shaft) and fill any
-- gap in the walls, floor or ceiling with cobblestone. Adds a few thousand
-- moves (and fuel); set to false to skip, but then water can get in.
local SEAL_WALLS = true
local SEAL_SPARE = 192 -- cobblestone carried while digging, for patching (3 slots)

-- "deep" mode: hole floor goes at BEDROCK_TOP + ABOVE_BEDROCK.
-- BEDROCK_TOP is -60 in Minecraft 1.18+ (use 4 for 1.17 and older).
local BEDROCK_TOP = -60
local ABOVE_BEDROCK = 10

-- "atrium": the hole plans/atrium.lua fills. Change these and that plan together.
local ATRIUM_SIZE = { 60, 60, 30 } -- width, length, height
local BUILDER_HOME = { x = 29, z = 7 } -- a floor spot the plan never builds above, for the builder turtle

-- Kept while digging for patching walls (only SEAL_SPARE of them).
local PATCH_BLOCKS = { ["minecraft:cobblestone"] = true, ["minecraft:cobbled_deepslate"] = true }

-- Fuel it tops up to from the chest behind the start (coal it has mined,
-- or any fuel you put in there).
local REFUEL_TO = 5000

-- Thrown away instead of carried back to the chest.
local JUNK = {}
for _, name in ipairs({
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:deepslate",
  "minecraft:dirt", "minecraft:gravel", "minecraft:andesite", "minecraft:diorite", "minecraft:granite",
  "minecraft:tuff", "minecraft:calcite", "minecraft:netherrack",
}) do JUNK[name] = true end

local job, plan

---------------------------------------------------------------- coordinates

-- Job coordinates are local to the hole's corner: x to the right, z forward,
-- y up. The turtle starts at job.start: the corner (0, 0, 0), or the middle
-- of the hole in deep mode.
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

local function inBox(b, p)
  return p.x >= b.x0 and p.x <= b.x1 and p.y >= b.y0 and p.y <= b.y1 and p.z >= b.z0 and p.z <= b.z1
end

local function inShaft(p)
  return plan.shaftBottom and p.x == plan.start.x and p.z == plan.start.z and p.y > plan.hole.y1
end

local function buildPlan()
  local W, L, H = job.width, job.length, job.height
  local F = 0 -- hole floor
  if job.dir == "down" then F = -(H - 1) elseif job.dir == "deep" then F = job.floor end
  plan = {
    hole = { x0 = 0, x1 = W - 1, y0 = F, y1 = F + H - 1, z0 = 0, z1 = L - 1 },
    start = job.start or { x = 0, y = 0, z = 0 }, -- jobs saved before job.start existed
  }
  -- deep mode: a 1x1 shaft from the start block down into the hole
  if job.dir == "deep" then plan.shaftBottom = { x = plan.start.x, y = F + H - 1, z = plan.start.z } end

  -- Cells on the edge of the dig, and which of their sides face solid ground
  -- that should be there. The seal phase visits them and fills any gaps.
  plan.seals = {}
  if SEAL_WALLS then
    local hole = plan.hole
    local function inside(x, y, z)
      local p = { x = x, y = y, z = z }
      return inBox(hole, p) or inShaft(p)
    end
    -- horizontal sides as heading offsets from the job's forward direction
    local SIDES = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
    local function check(x, y, z)
      local dirs = {}
      for d = 0, 3 do
        if not inside(x + SIDES[d][1], y, z + SIDES[d][2]) then dirs[#dirs + 1] = d end
      end
      if not inside(x, y + 1, z) then dirs[#dirs + 1] = "up" end
      if not inside(x, y - 1, z) then dirs[#dirs + 1] = "down" end
      if #dirs > 0 then table.insert(plan.seals, { x = x, y = y, z = z, dirs = dirs }) end
    end
    -- The shaft first (below the start block, which sits among the chest
    -- and the junk pile), so nothing pours down it into the hole.
    if plan.shaftBottom then
      for y = plan.start.y - 1, hole.y1 + 1, -1 do check(plan.start.x, y, plan.start.z) end
    end
    -- Then the hole from the top down: top and bottom layers every cell,
    -- snaking, layers between just the rim. The floor goes last, so any
    -- water that ran down while sealing above is gone over once it's shut in.
    for y = hole.y1, hole.y0, -1 do
      if y == hole.y0 or y == hole.y1 then
        for z = hole.z0, hole.z1 do
          for i = 0, hole.x1 - hole.x0 do
            check((z - hole.z0) % 2 == 0 and hole.x0 + i or hole.x1 - i, y, z)
          end
        end
      else
        for x = hole.x0, hole.x1 do check(x, y, hole.z0) end
        for z = hole.z0 + 1, hole.z1 do check(hole.x1, y, z) end
        if hole.z1 > hole.z0 then for x = hole.x1 - 1, hole.x0, -1 do check(x, y, hole.z1) end end
        if hole.x1 > hole.x0 then for z = hole.z1 - 1, hole.z0 + 1, -1 do check(hole.x0, y, z) end end
      end
    end
  end

  -- phase 0 digs the hole, phase 1 seals it
  plan.sealPhase = 1
end

local function boxCells(b)
  return math.ceil((b.y1 - b.y0 + 1) / 3) * (b.x1 - b.x0 + 1) * (b.z1 - b.z0 + 1)
end

-- Cell i of a box in 3-high layers, top layer first, snaking so consecutive
-- cells are next to each other. Returns where to stand.
local function boxCell(b, i)
  local w, l = b.x1 - b.x0 + 1, b.z1 - b.z0 + 1
  local per = w * l
  local layer, j = math.floor(i / per), i % per
  if layer % 2 == 1 then j = per - 1 - j end
  local row, col = math.floor(j / w), j % w
  if row % 2 == 1 then col = w - 1 - col end
  local y = math.min(math.max(b.y1 - 1 - layer * 3, b.y0 + 1), b.y1)
  return { x = b.x0 + col, y = y, z = b.z0 + row }
end

local function phaseSize(phase)
  if phase == 0 then return boxCells(plan.hole) end
  return #plan.seals
end

-- Move anywhere in the dig, going up and down the shaft instead of
-- tunnelling a new one.
local function travel(t)
  local p = here()
  if inShaft(p) and inShaft(t) then return goL(t) end
  if inShaft(p) then goL(plan.shaftBottom) end
  if inShaft(t) then goL(plan.shaftBottom) end
  return goL(t)
end

---------------------------------------------------------------- position checks

local reach -- defined below; used by the trips home

local gpsPos = nav.locate

-- Somewhere the turtle is meant to be: inside the dig, in the shaft, or on its start block.
local function onPlan(p)
  local s = plan.start
  return inBox(plan.hole, p) or inShaft(p) or (p.x == s.x and p.y == s.y and p.z == s.z)
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

local fuelLevel = inv.fuelLevel

local emptySlots = inv.emptySlots

-- Drop everything matching shouldDrop, but keep cobblestone for patching
-- walls until that's done.
local function dropItems(shouldDrop, drop)
  local reserve = (SEAL_WALLS and job.phase <= plan.sealPhase) and SEAL_SPARE or 0
  local kept = 0
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      if PATCH_BLOCKS[item.name] and kept < reserve then
        kept = kept + item.count
      elseif shouldDrop(item) then
        turtle.select(slot)
        drop()
      end
    end
  end
  turtle.select(1)
end

local function dropJunk()
  dropItems(function(item) return JUNK[item.name] end, turtle.drop)
end

-- anything that burns, so it uses the coal it digs up
local function refuelFromInventory(target) inv.refuel(target) end

local function homeDistance()
  local p, s = here(), plan.start
  return math.abs(p.x - s.x) + math.abs(p.y - s.y) + math.abs(p.z - s.z) + 50
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

local function unload()
  print("Inventory full, emptying into the chest")
  report.set("unloading", "inventory full")
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
    if emptySlots() <= 2 then unload() end
  end
  local needed = homeDistance()
  if fuelLevel() < needed then
    refuelFromInventory(needed + 1000)
    if fuelLevel() < needed then waitForFuel(needed + 1000) end
  end
end

-- Select cobblestone for patching walls.
local function selectPatchBlock()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and PATCH_BLOCKS[item.name] then
      turtle.select(slot)
      return true
    end
  end
  return false
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
  local done, total = 0, 0
  for phase = 0, plan.sealPhase do
    local size = phaseSize(phase)
    total = total + size
    if phase < job.phase then done = done + size elseif phase == job.phase then done = done + job.cell end
  end
  local name = job.phase == 0 and "digging" or "sealing walls"
  return ("%s, %d%% overall"):format(name, total > 0 and math.floor(done / total * 100) or 100)
end

-- Digging leaves water and lava source blocks behind. Turn them into
-- cobblestone and dig that out so the space ends up empty.
local function clearFluid(inspect, place, dig)
  local ok, data = inspect()
  if ok and (data.name == "minecraft:water" or data.name == "minecraft:lava") and selectPatchBlock() then
    place()
    dig()
  end
  turtle.select(1)
end

local function digCell(box, p)
  if not reach(p) then return end -- bedrock or a protected block: skip
  if p.y + 1 <= box.y1 then
    nav.digUp()
    clearFluid(turtle.inspectUp, turtle.placeUp, turtle.digUp)
  end
  if p.y - 1 >= box.y0 then
    nav.digDown()
    clearFluid(turtle.inspectDown, turtle.placeDown, turtle.digDown)
  end
end

-- Out of cobblestone mid-seal (a really big cave): go home and ask for more.
local function restockBlocks()
  reach(plan.start)
  faceChest()
  print("Out of cobblestone for patching walls. Add some to my inventory.")
  report.set("waiting", "needs cobblestone")
  while not selectPatchBlock() do os.pullEvent("turtle_inventory") end
end

-- Fill any gap on the outward sides of an edge cell. Standing in the cell
-- clears any water source in it; anything that isn't solid beside it
-- (air, water, lava) gets a block.
local function sealCell(s)
  if not reach(s) then return end
  for _, d in ipairs(s.dirs) do
    local detect, place
    if d == "up" then
      detect, place = turtle.detectUp, turtle.placeUp
    elseif d == "down" then
      detect, place = turtle.detectDown, turtle.placeDown
    else
      nav.face((job.origin.heading + d) % 4)
      detect, place = turtle.detect, turtle.place
    end
    if not detect() then
      if not selectPatchBlock() then
        restockBlocks()
        return sealCell(s)
      end
      place()
    end
  end
  turtle.select(1)
end

local function run()
  rejoin()
  while job.phase <= plan.sealPhase do
    local size = phaseSize(job.phase)
    while job.cell < size do
      if job.phase == 0 then
        digCell(plan.hole, boxCell(plan.hole, job.cell))
      else
        sealCell(plan.seals[job.cell + 1])
      end
      job.cell = job.cell + 1
      save()
      if job.cell % 20 == 0 then checkPosition() end
      housekeeping()
      if job.cell % 25 == 0 then print(progressText()) end
      -- only GPS jobs have real world coordinates; otherwise report.lua tries GPS itself
      report.set(job.phase == 0 and "digging" or "sealing", progressText(), job.gps and { pos = nav.getPos() } or nil)
    end
    job.phase, job.cell = job.phase + 1, 0
    save()
  end

  reach(plan.start)
  nav.face(job.origin.heading)
  nav.deleteFile(JOB_FILE)
  print("Excavation complete! The hole is dug and walled in.")
  report.set("done", "excavation complete")
  if job.atrium then
    -- the plan's north-west bottom corner is the hole's, on its floor
    local ax, _, az = toWorld({ x = 0, y = 0, z = 0 })
    local bx, _, bz = toWorld({ x = job.width - 1, y = 0, z = job.length - 1 })
    local x0, z0 = math.min(ax, bx), math.min(az, bz)
    local y0 = job.origin.y + plan.hole.y0
    print("Now for the atrium plan. Put a builder turtle")
    if job.gps then
      print(("at %d %d %d facing south, its chests behind"):format(x0 + BUILDER_HOME.x, y0, z0 + BUILDER_HOME.z))
      print("and to its left, and run 'builder setup'. Then:")
      print(("  build atrium %d %d %d"):format(x0, y0, z0))
    else
      print(("%d east and %d south of the hole's north-west"):format(BUILDER_HOME.x, BUILDER_HOME.z))
      print("corner, facing south, chests behind and left.")
      print("Then 'build atrium <x> <y> <z>': that corner, on the floor.")
    end
  end
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Job cancelled.")
  return
end

if not os.getComputerLabel() then os.setComputerLabel("Excavator-" .. os.getComputerID()) end
job = nav.readFile(JOB_FILE)

-- With GPS, the turtle works in real world coordinates and re-checks its
-- position and facing every time it starts. A job started without GPS keeps
-- using the saved position, since its coordinates are relative to the start.
local hasGps = gpsPos() ~= nil
local useGps = hasGps and (not job or job.gps)
local knowsPosition = nav.init(useGps)

-- No GPS to check against: give the player a chance to say the turtle was moved.
local function confirmResume()
  return nav.confirmResume("Put me back on my start block, facing the way I faced when\nthe job began, then run: excavate here")
end

if args[1] == "resume" or args[1] == "here" then
  if not job then
    print("No job to resume.")
    return
  end
  -- An older job was past the hall (rooms, sealing or the ledge): there are
  -- no rooms or ledge now, so just seal the hole.
  if job.v ~= JOB_VERSION then
    if job.phase > 0 then job.phase, job.cell = 1, 0 end
    job.v = JOB_VERSION
    save()
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
    if not knowsPosition then error("Lost track of position; can't resume. Run 'excavate cancel'.", 0) end
    if not confirmResume() then return end
  end
  print("Resuming: " .. progressText())
elseif job then
  print("A job is already in progress. Run 'excavate resume' or 'excavate cancel'.")
  return
else
  -- numbers are width, length, height in that order; the mode word can go anywhere
  local nums, dir, atrium = {}, "up", false
  for _, a in ipairs(args) do
    if tonumber(a) then nums[#nums + 1] = math.floor(tonumber(a)) elseif a == "atrium" then atrium = true else dir = a end
  end
  local defaults = atrium and ATRIUM_SIZE or { 21, 21, 16 }
  local w, l, h = nums[1] or defaults[1], nums[2] or defaults[2], nums[3] or defaults[3]
  if dir ~= "up" and dir ~= "down" and dir ~= "deep" or w < 1 or l < 1 or h < 1 then
    print("Usage: excavate [width] [length] [height] [up|down|deep]")
    print("       excavate atrium [up|down|deep]")
    return
  end
  if atrium and (w ~= ATRIUM_SIZE[1] or l ~= ATRIUM_SIZE[2] or h ~= ATRIUM_SIZE[3]) then
    print(("The atrium plan fits a %dx%dx%d hole: leave the sizes out."):format(ATRIUM_SIZE[1], ATRIUM_SIZE[2], ATRIUM_SIZE[3]))
    return
  end
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  -- The turtle sits at the hole's corner, or above its middle in deep mode.
  -- The origin is the hole's corner, so shift it back from the turtle.
  local p, heading = nav.getPos(), nav.getHeading()
  local start = { x = 0, y = 0, z = 0 }
  if dir == "deep" then start = { x = math.floor(w / 2), y = 0, z = math.floor(l / 2) } end
  local f, r = DIRS[heading], DIRS[(heading + 1) % 4]
  job = { v = JOB_VERSION, width = w, length = l, height = h, dir = dir, atrium = atrium or nil, phase = 0, cell = 0,
    start = start, gps = hasGps,
    origin = { x = p.x - start.x * r.x - start.z * f.x, y = p.y, z = p.z - start.x * r.z - start.z * f.z, heading = heading } }
  print(hasGps and "GPS found: I'll check my position as I go."
    or "No GPS: working from my own position count only.")

  local depth = 0
  if dir == "deep" then
    local startY = hasGps and p.y or nil
    while not startY do
      write("Enter this turtle's Y level (F3): ")
      startY = tonumber(read())
    end
    local floorY = BEDROCK_TOP + ABOVE_BEDROCK
    job.startY, job.floor = startY, floorY - startY
    if job.floor + h - 1 >= 0 then
      print(("The turtle must be above Y %d for the hole to fit below it."):format(floorY + h - 1))
      return
    end
    depth = startY - (floorY + h - 1)
    print(("Shaft %d blocks down; hole floor at Y %d (%d above bedrock)."):format(depth, floorY, ABOVE_BEDROCK))
  end
  buildPlan()

  local total = 0
  for phase = 0, plan.sealPhase do total = total + phaseSize(phase) end
  -- each trip to the chest goes up and down the shaft
  local fuel = math.floor(total * 1.3 + (total / 300) * 2 * depth + 2 * depth)
  print(("Hole %dx%dx%d (%s)%s."):format(w, l, h, dir, atrium and ", for the atrium plan" or ""))
  if SEAL_WALLS then print("Then I wall in every gap and dry it out.") end
  print(("Needs about %d fuel (have %s). I refuel from the chest"):format(fuel, tostring(turtle.getFuelLevel())))
  print("behind me, so put coal in it. Mined coal goes there too.")
  print("Chest goes directly behind me. Press Enter to start.")
  read()
  save()
  faceChest()
  refuelFromChest(REFUEL_TO)
  nav.face(job.origin.heading)
end

report.init("excavator")
errlog.init("excavate", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
