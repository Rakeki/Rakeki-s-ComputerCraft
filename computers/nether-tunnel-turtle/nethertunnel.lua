-- Standalone Nether tunnel digger (no server). Digs a straight 3x3 tunnel
-- ahead and keeps it sealed as it goes: holes in the walls, floor and
-- ceiling (caves, open air over lava lakes) get patched with blocks it
-- carries, lava next to the tunnel is walled off and lava inside it is
-- filled in and dug out. With an empty bucket on board it scoops up lava
-- sources and burns them as fuel. Loot goes back to a chest at the start.
--
--   nethertunnel [length]    (default 128, about 1000 blocks in the Overworld)
--   nethertunnel resume
--   nethertunnel here
--   nethertunnel cancel
--
-- Place the turtle on the floor, facing the way to dig, with a chest directly
-- behind it. The tunnel is 3 wide (centred on the turtle), 3 high (from the
-- turtle's block up) and [length] long, counting the start block. The far
-- end is sealed; the start end is left open as the way in.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.nethertunnel_job"

local DEFAULT_LENGTH = 128 -- blocks of tunnel when no length is given

-- Fuel it tops up to from the chest behind the start.
local REFUEL_TO = 3000

local TORCH_EVERY = 8 -- blocks between torches on the tunnel floor; keep it even (see visitCell)
local TORCH = "minecraft:torch" -- never dropped or unloaded, so put them anywhere in the inventory

local BUCKET = "minecraft:bucket" -- an empty one on board scoops up lava sources for fuel
local LAVA_BUCKET = "minecraft:lava_bucket"
local LAVA_FUEL = 1000 -- fuel in a bucket of lava

-- Blocks it patches holes with, best first: cobblestone and the like stand up
-- to ghast fireballs better than netherrack, which also burns forever if lit.
local FILLER = {
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:blackstone", "minecraft:stone",
  "minecraft:deepslate", "minecraft:andesite", "minecraft:diorite", "minecraft:granite", "minecraft:tuff",
  "minecraft:basalt", "minecraft:netherrack",
}
local FILLER_KEEP = 128 -- patch blocks it holds on to when throwing junk away or unloading

-- Thrown away instead of carried back to the chest (patch blocks up to
-- FILLER_KEEP are kept). The usual junk plus the Nether's own.
local JUNK = {}
for _, name in ipairs({
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:deepslate",
  "minecraft:dirt", "minecraft:gravel", "minecraft:andesite", "minecraft:diorite", "minecraft:granite",
  "minecraft:tuff", "minecraft:calcite", "minecraft:netherrack",
  "minecraft:soul_sand", "minecraft:soul_soil", "minecraft:basalt", "minecraft:blackstone",
}) do JUNK[name] = true end

-- Blocks that don't count as wall: fire, plants and anything that falls
-- (gravel would drop into the tunnel and leave a hole behind). They're dug
-- out and replaced with a patch block. Matched anywhere in the name.
local LOOSE = { "fire", "vine", "roots", "sprouts", "fungus", "mushroom", "gravel", "concrete_powder" }
local FALLING = { ["minecraft:sand"] = true, ["minecraft:red_sand"] = true }

local FILLER_RANK = {}
for i, name in ipairs(FILLER) do FILLER_RANK[name] = i end

local job, plan

---------------------------------------------------------------- coordinates

-- Job coordinates are local to the start block: x to the right, z forward,
-- y up. The tunnel is x -1..1, y 0..2, z 0..length-1. "Slice" z is the 3x3
-- cross-section at that z.
local DIRS = { [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 } }

-- Directions in the job's frame, numbered like headings from the start
-- facing: forward, right, back, left.
local LOCAL = { [0] = { x = 0, z = 1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = -1 }, [3] = { x = -1, z = 0 } }

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

local function faceLocal(k) nav.face((job.origin.heading + k) % 4) end

---------------------------------------------------------------- plan

-- The order it walks the nine blocks of each slice ({ x, y }). Each slice
-- starts where the last one ended, one block further on. The first starts on
-- the start block (bottom middle), which can't begin a walk through all nine
-- without stepping back once, and ends top right; then they alternate.
local FIRST = { { 0, 0 }, { -1, 0 }, { -1, 1 }, { -1, 2 }, { 0, 2 }, { 0, 1 }, { 1, 1 }, { 1, 0 }, { 1, 1 }, { 1, 2 } }
local FROM_TOP = { { 1, 2 }, { 0, 2 }, { -1, 2 }, { -1, 1 }, { 0, 1 }, { 1, 1 }, { 1, 0 }, { 0, 0 }, { -1, 0 } }
local FROM_BOTTOM = { { -1, 0 }, { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 2 }, { 0, 2 }, { 1, 2 } }

local function buildPlan()
  plan = { start = { x = 0, y = 0, z = 0 } }
end

local function slicePath(z)
  if z == 0 then return FIRST end
  return z % 2 == 1 and FROM_TOP or FROM_BOTTOM
end

local function cellOf(z, i)
  local c = slicePath(z)[i]
  return { x = c[1], y = c[2], z = z }
end

-- Where p first comes in slice z's walk, or nil.
local function pathIndex(z, p)
  for i, c in ipairs(slicePath(z)) do
    if c[1] == p.x and c[2] == p.y then return i end
  end
end

local function inTunnel(p)
  return math.abs(p.x) <= 1 and p.y >= 0 and p.y <= 2 and p.z >= 0 and p.z < job.length
end

-- Does the block at p have to be solid while the turtle works next to it?
-- Everything around the dug-out part of the tunnel does: the walls, floor and
-- ceiling for good, and the part of the tunnel not dug yet until the turtle
-- gets there. That way lava never has an open way in.
local function mustBeSolid(p)
  if p.z < 0 then return false end -- behind the start: the way in, left as it is
  if not inTunnel(p) then return true end
  if p.z ~= job.slice then return p.z > job.slice end
  return pathIndex(job.slice, p) > job.step
end

-- One block at a time, y then x then z. Unlike nav.goTo it never detours
-- upwards, which would dig through the ceiling.
local function moveTo(t)
  local p = here()
  while p.y ~= t.y do
    local ok, err = (t.y > p.y and nav.up or nav.down)()
    if not ok then return false, err end
    p = here()
  end
  while p.x ~= t.x or p.z ~= t.z do
    if p.x ~= t.x then faceLocal(t.x > p.x and 1 or 3) else faceLocal(t.z > p.z and 0 or 2) end
    local ok, err = nav.forward()
    if not ok then return false, err end
    p = here()
  end
  return true
end

-- Along the current slice's walk, from step i to step j.
local function walkPath(i, j)
  local dir = i <= j and 1 or -1
  for k = i + dir, j, dir do
    local ok, err = moveTo(cellOf(job.slice, k))
    if not ok then return false, err end
  end
  return true
end

-- Move anywhere in the tunnel through blocks that are already dug and
-- sealed: in the slice being dug, only along its walk; behind it, along the
-- middle of the tunnel.
local function travel(t)
  local cur = job.slice
  local p = here()
  if p.z == cur then
    local i = pathIndex(cur, p)
    local j = t.z == cur and pathIndex(cur, t)
    if i and j then return walkPath(i, j) end
    if i then
      local ok, err = walkPath(i, 1)
      if not ok then return ok, err end
      if cur == 0 then return true end -- on the start block; nothing else is dug yet
      local e = cellOf(cur, 1)
      ok, err = moveTo({ x = e.x, y = e.y, z = cur - 1 })
      if not ok then return ok, err end
      p = here()
    end
  end
  -- A target in the slice being dug is reached through its first block,
  -- from the finished slice behind it.
  local entry = t.z == cur and cellOf(cur, 1)
  local goal = entry and { x = entry.x, y = entry.y, z = cur - 1 } or t
  if p.z ~= goal.z then
    local ok, err = moveTo({ x = 0, y = 1, z = p.z })
    if ok then ok, err = moveTo({ x = 0, y = 1, z = goal.z }) end
    if not ok then return ok, err end
  end
  local ok, err = moveTo(goal)
  if not ok or not entry then return ok, err end
  ok, err = moveTo(entry)
  if not ok then return ok, err end
  return walkPath(1, pathIndex(cur, t))
end

---------------------------------------------------------------- position checks

local reach -- defined below; used by the trips home

local gpsPos = nav.locate

-- Somewhere the turtle is meant to be: in the dug part of the tunnel.
local function onPlan(p)
  return math.abs(p.x) <= 1 and p.y >= 0 and p.y <= 2 and p.z >= 0 and p.z <= job.slice and p.z < job.length
end

-- If the turtle finds itself off its route (picked up and put down
-- somewhere else, say), head for the start block before carrying on.
local function rejoin()
  local p = here()
  if onPlan(p) then return end
  local w = nav.getPos()
  print(("Off my route at %d,%d,%d. Heading back to the start first."):format(w.x, w.y, w.z))
  nav.goTo(toWorld(plan.start))
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

local function fillerCount() return inv.count(FILLER_RANK) end

-- Slots of patch blocks to hang on to, best blocks first, up to FILLER_KEEP.
local function fillerToKeep()
  local slots = {}
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and FILLER_RANK[item.name] then
      slots[#slots + 1] = { slot = slot, rank = FILLER_RANK[item.name], count = item.count }
    end
  end
  table.sort(slots, function(a, b) return a.rank < b.rank end)
  local keep, n = {}, 0
  for _, s in ipairs(slots) do
    if n >= FILLER_KEEP then break end
    keep[s.slot] = true
    n = n + s.count
  end
  return keep
end

-- Drop everything matching shouldDrop(item, slot), except torches, buckets
-- and the patch blocks it's keeping.
local function dropItems(shouldDrop, drop)
  local keep = fillerToKeep()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and not keep[slot] and item.name ~= TORCH and item.name ~= BUCKET and item.name ~= LAVA_BUCKET
      and shouldDrop(item, slot) then
      turtle.select(slot)
      drop()
    end
  end
  turtle.select(1)
end

local function dropJunk()
  dropItems(function(item) return JUNK[item.name] end, turtle.drop)
end

-- anything that burns, so it uses the coal it digs up and lava it scoops
local function refuelFromInventory(target) inv.refuel(target) end

-- The way home is along the tunnel, which is exactly this far.
local function homeDistance()
  local p = here()
  return math.abs(p.x) + math.abs(p.y) + math.abs(p.z) + 50
end

local function faceChest() faceLocal(2) end

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

-- Facing the chest at the start: if it's short of patch blocks, take any
-- the player has put in the chest (a few stacks of cobblestone, say).
local function stockFiller()
  local putBack = {}
  for slot = 1, 16 do
    if fillerCount() >= FILLER_KEEP then break end
    if turtle.getItemCount(slot) == 0 then
      turtle.select(slot)
      if not turtle.suck() then break end -- chest is empty
      local item = turtle.getItemDetail(slot)
      if item and not FILLER_RANK[item.name] then putBack[#putBack + 1] = slot end
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
  faceLocal(0)
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
  -- while here, top up from any fuel and patch blocks in the chest
  if fuelLevel() < REFUEL_TO then refuelFromChest(REFUEL_TO) end
  if fillerCount() < FILLER_KEEP then stockFiller() end
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
  if emptySlots() <= 3 then
    dropJunk()
    if emptySlots() <= 4 then unload("Inventory full") end
  end
  local needed = homeDistance()
  if fuelLevel() < needed then
    refuelFromInventory(needed + 1000)
    if fuelLevel() < needed then waitForFuel(needed + 1000) end
  end
end

-- Get to p. If something it won't dig (bedrock, a spawner, a chest) is in
-- the way, stop and say so, and keep retrying rather than skipping ahead:
-- going round it would mean digging outside the sealed tunnel.
reach = function(p)
  local tries = 0
  while true do
    local ok, err = travel(p)
    if ok then return true end
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

---------------------------------------------------------------- sealing

local SIDES = {
  forward = { inspect = turtle.inspect, detect = turtle.detect, dig = turtle.dig, place = turtle.place, attack = turtle.attack },
  up = { inspect = turtle.inspectUp, detect = turtle.detectUp, dig = turtle.digUp, place = turtle.placeUp, attack = turtle.attackUp },
  down = { inspect = turtle.inspectDown, detect = turtle.detectDown, dig = turtle.digDown, place = turtle.placeDown, attack = turtle.attackDown },
}

local function isLoose(name)
  if FALLING[name] then return true end
  for _, part in ipairs(LOOSE) do
    if name:find(part, 1, true) then return true end
  end
  return false
end

local function blockAt(a)
  local ok, block = a.inspect()
  return ok and block or nil
end

local function selectFiller()
  for _, name in ipairs(FILLER) do
    if inv.select(name) then return true end
  end
  return false
end

-- Stays put (still plugging the gap it's next to) until it's given more.
local function waitForFiller()
  print("Out of blocks to patch holes with. Put cobblestone or netherrack in my inventory.")
  report.set("waiting", "needs patch blocks")
  repeat os.pullEvent("turtle_inventory") until fillerCount() > 0
end

-- A lava source on side a: scoop it up with an empty bucket and burn it,
-- if there's a bucket on board and room in the tank for it.
local function takeLava(a)
  local limit = turtle.getFuelLimit()
  if limit == "unlimited" or fuelLevel() + LAVA_FUEL > limit then return end
  if not inv.select(BUCKET) then return end
  if a.place() and inv.select(LAVA_BUCKET) then -- placing an empty bucket on lava fills it
    turtle.refuel()
    job.lava = job.lava + 1
  end
  turtle.select(1)
end

-- Make the block on side a solid: lava is scooped up or covered, fire,
-- plants and gravel are cleared, and the space gets a patch block. True once
-- it's solid. Only blocks it has just checked are loose are ever dug here,
-- so protected blocks stay safe without going through nav. wall: it's part
-- of the walls, floor or ceiling, so a patch there counts as a hole fixed.
local function seal(side, wall)
  local a = SIDES[side]
  local patched = false
  for _ = 1, 20 do
    local block = blockAt(a)
    if a.detect() and not (block and isLoose(block.name)) then
      if patched and wall then job.patched = job.patched + 1 end
      return true
    end
    if block and block.name:find("lava", 1, true) and block.state and block.state.level == 0 then takeLava(a) end
    if a.detect() and a.dig() then sleep(0.4) end -- give gravel above a moment to fall in
    block = blockAt(a)
    if not a.detect() or (block and isLoose(block.name)) then -- air, lava, or fire it can build over
      while not selectFiller() do waitForFiller() end
      if a.place() then patched = true else a.attack() end -- a mob in the way
      turtle.select(1)
    end
  end
  return false
end

-- Seal round the block the turtle is in: every side that has to be solid
-- (see mustBeSolid) and isn't gets made solid.
local function sealAround(c)
  local start = (nav.getHeading() - job.origin.heading) % 4
  for i = 0, 3 do
    local k = (start + i) % 4
    local d = LOCAL[k]
    local n = { x = c.x + d.x, y = c.y, z = c.z + d.z }
    if mustBeSolid(n) then
      faceLocal(k)
      if not seal("forward", not inTunnel(n)) then print("Couldn't seal a hole next to me; carrying on.") end
    end
  end
  for side, dy in pairs({ up = 1, down = -1 }) do
    local n = { x = c.x, y = c.y + dy, z = c.z }
    if mustBeSolid(n) and not seal(side, not inTunnel(n)) then
      print(("Couldn't seal the hole %s from me; carrying on."):format(side == "up" and "above" or "below"))
    end
  end
end

local function placeTorch()
  if inv.select(TORCH) then turtle.placeDown() end
  turtle.select(1)
end

---------------------------------------------------------------- main

local function progressText()
  return ("%d of %d blocks along, %d%%"):format(job.slice, job.length, math.floor(job.slice / job.length * 100))
end

-- Even slices from 2 on walk the bottom row first, so the middle block
-- (0, 1) is visited with the floor below it already dug: that's where a
-- torch can go.
local function visitCell(c)
  reach(c)
  sealAround(c)
  if c.x == 0 and c.y == 1 and c.z > 0 and c.z % TORCH_EVERY == 0 then placeTorch() end
end

local function run()
  rejoin()
  while job.slice < job.length do
    local path = slicePath(job.slice)
    while job.step < #path do
      visitCell(cellOf(job.slice, job.step + 1))
      job.step = job.step + 1
      save()
    end
    job.slice, job.step = job.slice + 1, 0
    save()
    if job.slice % 2 == 0 then checkPosition() end
    housekeeping()
    if job.slice % 16 == 0 then print(progressText()) end
    -- only GPS jobs have real world coordinates; otherwise report.lua tries GPS itself
    report.set("mining", progressText(), job.gps and { pos = nav.getPos() } or nil)
  end
  unload("Tunnel finished")
  faceLocal(0)
  nav.deleteFile(JOB_FILE)
  print(("Nether tunnel complete! Patched %d holes, scooped up %d lava."):format(job.patched, job.lava))
  report.set("done", "nether tunnel complete")
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Job cancelled.")
  return
end

if not os.getComputerLabel() then os.setComputerLabel("NetherTunnel-" .. os.getComputerID()) end
job = nav.readFile(JOB_FILE)

-- With GPS, the turtle works in real world coordinates and re-checks its
-- position and facing every time it starts. A job started without GPS keeps
-- using the saved position, since its coordinates are relative to the start.
local hasGps = gpsPos() ~= nil
local useGps = hasGps and (not job or job.gps)
local knowsPosition = nav.init(useGps)

-- No GPS to check against: give the player a chance to say the turtle was moved.
local function confirmResume()
  return nav.confirmResume("Put me back on my start block, facing the way I faced when\nthe job began, then run: nethertunnel here")
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
    if not knowsPosition then error("Lost track of position; can't resume. Run 'nethertunnel cancel'.", 0) end
    if not confirmResume() then return end
  end
  print("Resuming: " .. progressText())
elseif job then
  print("A job is already in progress. Run 'nethertunnel resume' or 'nethertunnel cancel'.")
  return
else
  local length = args[1] and tonumber(args[1]) or DEFAULT_LENGTH
  if not length or length < 1 or length ~= math.floor(length) then
    print("Usage: nethertunnel [length]")
    return
  end
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  local p = nav.getPos()
  job = { length = length, slice = 0, step = 0, patched = 0, lava = 0, gps = hasGps,
    origin = { x = p.x, y = p.y, z = p.z, heading = nav.getHeading() } }
  print(hasGps and "GPS found: I'll check my position as I go."
    or "No GPS: working from my own position count only.")
  buildPlan()

  local fuel = math.floor(length * 10 * 1.2)
  print(("Tunnel %d long, 3 wide and 3 high."):format(length))
  print(("Needs about %d fuel (have %s). I refuel from the chest"):format(fuel, tostring(turtle.getFuelLevel())))
  print("behind me, so put coal in it.")
  if inv.count(BUCKET) > 0 then
    print("I'll scoop up lava with my bucket and burn it.")
  else
    print("Give me an empty bucket and I'll burn the lava I find.")
  end
  print(("Patch blocks on board: %d. I use netherrack I dig, but"):format(fillerCount()))
  print("cobblestone makes stronger walls.")
  print("Chest goes directly behind me. Press Enter to start.")
  read()
  save()
  faceChest()
  refuelFromChest(REFUEL_TO)
  stockFiller()
  faceLocal(0)
end

report.init("nether tunnel")
errlog.init("nethertunnel", function() return { pos = nav.getPos(), slice = job and job.slice } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
