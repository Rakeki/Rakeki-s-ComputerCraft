-- Standalone excavator (no server). Digs out a box-shaped hole, then walks
-- its edge and fills every gap in the walls, floor and ceiling (caves,
-- ravines, water, lava) so the hole ends up dry and fully walled in. Nothing
-- is built inside it: builder turtles do the inner walls and details.
--
--   excavate [width] [length] [height] [up|down|deep]    (default 21 21 16 up)
--   excavate <size> [up|down|deep]   a cube that size, e.g. 'excavate 30 deep'
--   excavate <plan> [up|down|deep]   the hole a plan in /plans needs (cellar, fortress, ...: any with a hole)
--   excavate resume
--   excavate here       you put me back on my start block (no GPS): carry on from there
--   excavate cancel
--   excavate join [id]  help another excavator (the lead) with its hole: run while it waits for Enter
--
-- A crew: start the job on one turtle (the lead) and, before pressing Enter
-- on it, run 'excavate join' on helpers placed in the lead's row (to its
-- right, same level and facing, each with its own chest behind it), or for
-- deep mode anywhere on the ground above the hole. Each turtle digs the
-- strip of columns nearest to it, then they wait for each other and each
-- seals its own strip. Needs GPS and a wireless or ender modem on each.
--
-- Place the turtle in a corner of the area, facing along one edge. The hole
-- runs forward (length), to the right (width), and up or down (height) from
-- the turtle's block. Put a chest directly behind the turtle for loot.
--
-- "deep" digs a shaft straight down from the turtle and digs the hole
-- centred underneath it, with its floor ABOVE_BEDROCK layers above bedrock.
-- The turtle comes back up the shaft to the chest. Place it above where the
-- middle of the hole should be.
--
-- A plan name digs the hole that plan says it needs (its "hole" field: width
-- east-west, length north-south, height), lined up with north whichever way
-- the turtle faces, so build-control can fill it unturned. It prints where
-- the builder turtle goes (the plan's "home") and the build command when
-- it's done.
--
-- With a storage computer in range, the chest behind the start can be one of
-- its chests (a wired modem on its cable, or an ender chest whose twin is on
-- it): the turtle claims it as its delivery chest, orders fuel and
-- cobblestone into it, and the loot it leaves there goes home on its own.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local net = require("lib.net") -- asking the storage computer for fuel and cobblestone
local claim = require("lib.claim") -- tells the storage computer the chest behind the start is mine
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

-- Where 'excavate <plan>' looks for the plan, as the projector and build-control do.
local PLAN_DIR = "/plans"

-- Kept while digging for patching walls (only SEAL_SPARE of them).
local PATCH_BLOCKS = { ["minecraft:cobblestone"] = true, ["minecraft:cobbled_deepslate"] = true }

-- Fuel it tops up to from the chest behind the start (coal it has mined,
-- or any fuel you put in there).
local REFUEL_TO = 5000

-- Order fuel and cobblestone from a storage computer, delivered to the chest
-- behind the start (it must be on the storage cable, or an ender chest whose
-- twin is), which also sends my loot home. False: the chest is all there is.
local USE_STORAGE = true
local STORAGE_WAIT = 10 -- seconds to wait for the storage computer to answer
local CLAIM_RETRY = 300 -- seconds before trying again to hook my chest up, if it didn't work

-- Crew: helpers join the lead on this protocol before it starts.
local CREW_PROTOCOL = "excavate_crew"
local CREW_POLL = 10 -- seconds between a waiting crew turtle's checks on the others
-- Fuel asked for when low, in this order, and how much of it.
local STORAGE_FUEL = { { "minecraft:coal", 64 }, { "minecraft:charcoal", 64 }, { "minecraft:coal_block", 8 } }
-- Asked for when patching runs out, in this order (SEAL_SPARE of it).
local STORAGE_PATCH = { "minecraft:cobblestone", "minecraft:cobbled_deepslate" }

-- Thrown away instead of carried back to the chest.
local JUNK = {}
for _, name in ipairs({
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:deepslate",
  "minecraft:dirt", "minecraft:gravel", "minecraft:andesite", "minecraft:diorite", "minecraft:granite",
  "minecraft:tuff", "minecraft:calcite", "minecraft:netherrack",
}) do JUNK[name] = true end

local job, plan

-- The hole a building plan in PLAN_DIR asks for: { width, length, height }
-- and the builder's home { x, z }, or nil and why.
local function planHole(name)
  local raw
  if fs.exists(("%s/%s.lua"):format(PLAN_DIR, name)) then
    local ok, p = pcall(dofile, ("%s/%s.lua"):format(PLAN_DIR, name))
    if not ok then return nil, ("plan %s won't load: %s"):format(name, tostring(p)) end
    raw = p
  elseif fs.exists(("%s/%s.json"):format(PLAN_DIR, name)) then
    local f = fs.open(("%s/%s.json"):format(PLAN_DIR, name), "r")
    raw = textutils.unserialiseJSON(f.readAll())
    f.close()
  else
    return nil, ("No plan called %s in %s. Install it: install plan %s"):format(name, PLAN_DIR, name)
  end
  local hole = type(raw) == "table" and raw.hole
  if type(hole) ~= "table" or not (tonumber(hole[1]) and tonumber(hole[2]) and tonumber(hole[3])) then
    return nil, ("Plan %s doesn't say what hole it needs (no \"hole\" in it)."):format(name)
  end
  return { tonumber(hole[1]), tonumber(hole[2]), tonumber(hole[3]) }, raw.home
end

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

local function toLocal(w)
  local o = job.origin
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  local dx, dz = w.x - o.x, w.z - o.z
  return { x = dx * r.x + dz * r.z, y = w.y - o.y, z = dx * f.x + dz * f.z }
end

local function here() return toLocal(nav.getPos()) end

local function goL(p) return nav.goTo(toWorld(p)) end

---------------------------------------------------------------- plan

local function inBox(b, p)
  return p.x >= b.x0 and p.x <= b.x1 and p.y >= b.y0 and p.y <= b.y1 and p.z >= b.z0 and p.z <= b.z1
end

-- My own shaft (deep mode), the one I travel up and down.
local function inShaft(p)
  return plan.shaftBottom and p.x == plan.start.x and p.z == plan.start.z and p.y > plan.hole.y1
end

-- Any crew turtle's shaft, from its start block down: part of the dig, so
-- never walled over.
local function inAnyShaft(p)
  if p.y <= plan.hole.y1 then return false end
  for _, s in ipairs(plan.shafts) do
    if p.x == s.x and p.z == s.z and p.y <= s.y then return true end
  end
  return false
end

local function buildPlan()
  local W, L, H = job.width, job.length, job.height
  local F = 0 -- hole floor
  if job.dir == "down" then F = -(H - 1) elseif job.dir == "deep" then F = job.floor end
  plan = {
    hole = { x0 = 0, x1 = W - 1, y0 = F, y1 = F + H - 1, z0 = 0, z1 = L - 1 },
    start = job.start or { x = 0, y = 0, z = 0 }, -- jobs saved before job.start existed
  }
  -- The part I dig and seal: the whole hole, or my strip of columns in a crew.
  local strip = job.strip or { x0 = 0, x1 = W - 1 }
  plan.dig = { x0 = strip.x0, x1 = strip.x1, y0 = F, y1 = F + H - 1, z0 = 0, z1 = L - 1 }
  -- deep mode: a 1x1 shaft from the start block down into the hole (one per crew turtle)
  plan.shafts = {}
  if job.dir == "deep" then
    plan.shaftBottom = { x = plan.start.x, y = F + H - 1, z = plan.start.z }
    plan.shafts = job.shafts or { plan.start }
  end

  -- Cells on the edge of the dig, and which of their sides face solid ground
  -- that should be there. The seal phase visits them and fills any gaps.
  plan.seals = {}
  if SEAL_WALLS then
    local hole = plan.hole
    local function inside(x, y, z)
      local p = { x = x, y = y, z = z }
      return inBox(hole, p) or inAnyShaft(p)
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
    -- The shafts first (below the start block, which sits among the chest
    -- and the junk pile), so nothing pours down them into the hole.
    for _, s in ipairs(plan.shafts) do
      for y = s.y - 1, hole.y1 + 1, -1 do check(s.x, y, s.z) end
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
    -- In a crew each turtle seals the cells in its own strip (its shaft is in it).
    if job.strip then
      local mine = {}
      for _, s in ipairs(plan.seals) do
        if s.x >= plan.dig.x0 and s.x <= plan.dig.x1 then mine[#mine + 1] = s end
      end
      plan.seals = mine
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
  if phase == 0 then return boxCells(plan.dig) end
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

---------------------------------------------------------------- the storage system

-- the storage computer, looked up again a minute after none answered
local storage = net.peer("storage", { retry = 60, wait = STORAGE_WAIT })
local supply = claim.tracker("delivery", CLAIM_RETRY) -- whether the storage system knows my chest
local saidHooked -- the chest last reported as hooked up, so it's said once

local function askStorage(msg)
  if not USE_STORAGE then return nil end
  return (storage:ask(msg))
end

-- Facing the chest: make sure the storage system knows it's mine. From then
-- on it takes away whatever I leave there, and sends my orders there.
local function hookChest()
  if not USE_STORAGE or not supply:due() then return end
  local ok, why = supply:check(askStorage, "front")
  if ok then
    if saidHooked ~= why then print(("My chest is hooked up to the storage system (%s): loot goes home from it."):format(why)) end
    saidHooked = why
  elseif ok == false then
    print("Couldn't hook my chest up to the storage system: " .. why)
  end
end

-- Facing the chest: have the storage system put up to n of the first of
-- choices ({ name, n } each) it has into my chest. True if some are there.
local function orderOne(choices)
  hookChest()
  if not supply.done then return false end -- never into someone else's chest
  for _, c in ipairs(choices) do
    local r = askStorage({ type = "deliver", items = { [c[1]] = c[2] } })
    if not r then return false end
    supply:seen(r) -- not sent to my own chest: find it again next time
    if r.to ~= "own" then return false end
    if type(r.ready) == "table" and (r.ready[c[1]] or 0) > 0 then return true end
  end
  return false
end

-- Facing the chest: fuel from it, and from the storage system if that's short.
local function topUpFuel(target)
  refuelFromChest(target)
  if fuelLevel() < target and orderOne(STORAGE_FUEL) then refuelFromChest(target) end
end

---------------------------------------------------------------- trips home

local function unload()
  print("Inventory full, emptying into the chest")
  report.set("unloading", "inventory full")
  reach(plan.start)
  -- junk goes on the ground in front, everything else in the chest
  nav.face(job.origin.heading)
  dropJunk()
  faceChest()
  hookChest()
  local warned = false
  while true do
    local full = false
    dropItems(function() return true end, function()
      if not turtle.drop() then full = true end
    end)
    if not full then break end
    if not warned then
      print(supply.done and "My chest is full and the storage system isn't emptying it (is storage full?). Waiting..."
        or "Chest behind the start is missing or full. Waiting...")
      report.set("waiting", "chest full or missing")
      warned = true
    end
    sleep(5)
  end
  -- while here, top up from any fuel in the chest
  if fuelLevel() < REFUEL_TO then topUpFuel(REFUEL_TO) end
end

-- Go home and refuel from the chest there (and the storage system). If that
-- hasn't got enough, wait for the player to add fuel.
local function waitForFuel(target)
  reach(plan.start)
  faceChest()
  if emptySlots() < 2 then dropItems(function() return true end, turtle.drop) end
  topUpFuel(math.max(target, REFUEL_TO))
  if fuelLevel() >= target then return end
  print(("Need %d fuel, have %d. Put fuel in the chest behind me or in my inventory%s."):format(target, fuelLevel(),
    supply.done and ", or coal in the storage system" or ""))
  report.set("waiting", ("needs fuel (%d)"):format(target))
  while fuelLevel() < target do
    local timer = os.startTimer(10) -- the chest doesn't announce changes, so check it every 10s
    repeat
      local event, value = os.pullEvent()
    until event == "turtle_inventory" or (event == "timer" and value == timer)
    refuelFromInventory(target)
    topUpFuel(math.max(target, REFUEL_TO))
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
    if err == nav.TOO_FAR then return false, nav.sayTooFar() end -- the job skips what's past its range
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

---------------------------------------------------------------- crew

-- A crew is the lead (job.crew.members: every helper's id, start, strip and
-- how far it's got) and its helpers (job.crew.lead). Helpers join before
-- the lead starts; each digs its own strip of columns, nobody seals until
-- every strip is dug, and the lead finishes once every strip is sealed.
local STAGES = { dug = 1, sealed = 2 }
local recruiting = false -- the lead is still waiting for Enter, taking helpers

local function isLead() return job.crew and job.crew.members ~= nil end
local function isHelper() return job.crew and job.crew.lead ~= nil end

local function member(id)
  for _, m in ipairs(job.crew.members) do
    if m.id == id then return m end
  end
end

local function reached(m, stage) return (STAGES[m.state] or 0) >= STAGES[stage] end

-- The helpers that haven't got to stage yet.
local function behind(stage)
  local ids = {}
  for _, m in ipairs(job.crew.members) do
    if not reached(m, stage) then ids[#ids + 1] = tostring(m.id) end
  end
  return ids
end

-- Where a helper at world position pos (facing heading) would start, or nil and why it can't.
local function helperStart(id, pos, heading)
  if heading ~= job.origin.heading then
    local names = { [0] = "north", "east", "south", "west" }
    return nil, ("Face %s, the same way as me."):format(names[job.origin.heading])
  end
  local p = toLocal(pos)
  if p.x < 0 or p.x >= job.width then
    return nil, ("Stand over the hole: within %d blocks to my right, counting me."):format(job.width)
  end
  if job.dir == "deep" then
    if p.z < 0 or p.z >= job.length or p.y <= plan.hole.y1 then
      return nil, "Stand on the ground somewhere above the hole."
    end
  elseif p.y ~= 0 or p.z ~= 0 then
    return nil, "Stand in my row: on my level, in line with me to my right."
  end
  if p.x == plan.start.x then return nil, "I'm in that column already. Move along a block or more." end
  for _, m in ipairs(job.crew.members) do
    if m.id ~= id and m.start.x == p.x then
      return nil, ("Turtle %d is in that column already. Move along."):format(m.id)
    end
  end
  return p
end

-- Split the hole's columns between the lead and the helpers: each gets
-- the ones nearest to it, so its own start is in its strip and it never
-- crosses another's on the way home.
local function splitStrips()
  local cols = { { x = plan.start.x } }
  for _, m in ipairs(job.crew.members) do cols[#cols + 1] = { x = m.start.x, m = m } end
  table.sort(cols, function(a, b) return a.x < b.x end)
  for i, c in ipairs(cols) do
    local strip = {
      x0 = i == 1 and 0 or math.floor((cols[i - 1].x + c.x) / 2) + 1,
      x1 = i == #cols and job.width - 1 or math.floor((c.x + cols[i + 1].x) / 2),
    }
    if c.m then c.m.strip = strip else job.strip = strip end
  end
  -- copies, not the start tables themselves: textutils won't save a table
  -- that holds the same table twice
  if job.dir == "deep" then
    local function at(p) return { x = p.x, y = p.y, z = p.z } end
    job.shafts = { at(plan.start) }
    for _, m in ipairs(job.crew.members) do job.shafts[#job.shafts + 1] = at(m.start) end
  end
end

-- The job a helper runs: the lead's hole, its own start and strip.
local function helperJob(m)
  return { v = JOB_VERSION, width = job.width, length = job.length, height = job.height, dir = job.dir,
    floor = job.floor, origin = job.origin, gps = true, phase = 0, cell = 0,
    start = m.start, strip = m.strip, shafts = job.shafts, crew = { lead = os.getComputerID() } }
end

-- The lead answers its crew: join (before it starts), ready (my job yet?)
-- and crew (how far a helper has got).
local function crewHandle(from, msg)
  if msg.type == "join" then
    if not recruiting then
      return net.answer(from, CREW_PROTOCOL, msg, { why = "My job has already started. Join before I start." })
    end
    if type(msg.pos) ~= "table" then return end
    local start, why = helperStart(from, msg.pos, msg.heading)
    if not start then return net.answer(from, CREW_PROTOCOL, msg, { why = why }) end
    local m = member(from)
    if not m then
      m = { id = from }
      table.insert(job.crew.members, m)
    end
    m.start = start
    print(("Turtle %d joins the crew, %d to my right (%d turtles)."):format(from, start.x - plan.start.x,
      #job.crew.members + 1))
    net.answer(from, CREW_PROTOCOL, msg, { ok = true, n = #job.crew.members + 1 })
  elseif msg.type == "ready" then
    local m = member(from)
    if not m then return net.answer(from, CREW_PROTOCOL, msg, { why = "You're not in my crew." }) end
    if recruiting then return net.answer(from, CREW_PROTOCOL, msg, { wait = true }) end
    net.answer(from, CREW_PROTOCOL, msg, { job = helperJob(m) })
  elseif msg.type == "crew" then
    local m = member(from)
    if not m then return net.answer(from, CREW_PROTOCOL, msg, { why = "You're not in my crew." }) end
    if STAGES[msg.state] and not reached(m, msg.state) then
      m.state = msg.state
      if not recruiting then save() end
    end
    net.answer(from, CREW_PROTOCOL, msg, { allDug = job.phase >= 1 and #behind("dug") == 0 })
  end
end

local function crewLoop()
  net.open()
  while true do
    local from, msg = rednet.receive(CREW_PROTOCOL)
    if type(msg) == "table" then errlog.pcall(crewHandle, from, msg) end
  end
end

-- The lead: wait until every helper has got to stage, saying who it waits for.
local function waitForHelpers(stage, doing)
  local said
  while true do
    local ids = behind(stage)
    if #ids == 0 then return end
    local text = ("Waiting for turtle%s %s to finish %s."):format(#ids > 1 and "s" or "", table.concat(ids, ", "), doing)
    if text ~= said then
      print(text)
      report.set("waiting", text)
      said = text
    end
    sleep(CREW_POLL)
  end
end

local function askLead(msg)
  return net.ask(job.crew.lead, CREW_PROTOCOL, msg, { wait = 5 })
end

-- Every strip dug before anyone seals, so no water runs onto a sealed floor
-- from a strip still being dug.
local function crewBeforeSealing()
  if isLead() then
    waitForHelpers("dug", "digging")
  else
    local said
    while true do
      local r = askLead({ type = "crew", state = "dug" })
      if r and r.allDug then break end
      local text = r and (r.why or "My strip is dug. Waiting for the rest of the crew.")
        or ("My strip is dug. Can't hear the lead (turtle %d); waiting."):format(job.crew.lead)
      if text ~= said then
        print(text)
        report.set("waiting", text)
        said = text
      end
      sleep(CREW_POLL)
    end
  end
  print("Every strip is dug. Sealing mine.")
end

-- Done with my strip: the lead waits for the rest; a helper tells it.
local function crewAfterSealing()
  if isLead() then
    waitForHelpers("sealed", "sealing")
  else
    for _ = 1, 12 do
      if askLead({ type = "crew", state = "sealed" }) then return end
      sleep(CREW_POLL)
    end
    print(("Couldn't tell the lead (turtle %d) I'm done."):format(job.crew.lead))
  end
end

-- A helper: join the crew of the lead (leadId, or whoever is taking helpers)
-- and wait for it to start. Returns my job, or nil if I can't join.
local function joinCrew(leadId)
  if not net.open() then
    print("Joining a crew needs a wireless or ender modem.")
    return nil
  end
  local lead = leadId or rednet.lookup(CREW_PROTOCOL)
  if not lead then
    print("No excavator is taking helpers. Start the job on the lead")
    print("turtle first, and run this while it waits for Enter.")
    return nil
  end
  local p = nav.getPos()
  local r = net.ask(lead, CREW_PROTOCOL, { type = "join", pos = p, heading = nav.getHeading() }, { wait = 5 })
  if not r then
    print(("Turtle %d didn't answer."):format(lead))
    return nil
  end
  if not r.ok then
    print(r.why or "Turtle " .. lead .. " won't take me.")
    return nil
  end
  print(("Joined turtle %d's crew (%d turtles). My chest goes"):format(lead, r.n or 2))
  print(("directly behind me. Press Enter on turtle %d to start."):format(lead))
  local said
  while true do
    sleep(3)
    r = net.ask(lead, CREW_PROTOCOL, { type = "ready" }, { wait = 5 })
    if r and r.job then return r.job end
    if r and r.why then
      print(r.why)
      return nil
    end
    if not r and not said then
      print(("Can't hear turtle %d just now; still waiting."):format(lead))
      said = true
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
  if job.crew then name = name .. " my strip" end
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

-- Facing the chest: take cobblestone from it, up to SEAL_SPARE. Anything
-- else taken out goes back in.
local function takePatchBlocks()
  local putBack = {}
  for slot = 1, 16 do
    if inv.count(PATCH_BLOCKS) >= SEAL_SPARE then break end
    if turtle.getItemCount(slot) == 0 then
      turtle.select(slot)
      if not turtle.suck() then break end -- chest is empty
      local item = turtle.getItemDetail(slot)
      if item and not PATCH_BLOCKS[item.name] then putBack[#putBack + 1] = slot end
    end
  end
  for _, slot in ipairs(putBack) do
    turtle.select(slot)
    turtle.drop()
  end
  turtle.select(1)
end

-- Out of cobblestone mid-seal (a really big cave): go home for more, from
-- the chest, the storage system or the player.
local function restockBlocks()
  reach(plan.start)
  faceChest()
  -- room to take them: loot goes in the chest
  if emptySlots() < 4 then dropItems(function(item) return not PATCH_BLOCKS[item.name] end, turtle.drop) end
  local said = false
  while true do
    takePatchBlocks()
    if not selectPatchBlock() then
      local choices = {}
      for i, name in ipairs(STORAGE_PATCH) do choices[i] = { name, SEAL_SPARE } end
      if orderOne(choices) then takePatchBlocks() end
    end
    if selectPatchBlock() then return end
    if not said then
      print(("Out of cobblestone for patching walls. Put some in my inventory or the chest behind me%s."):format(
        supply.done and ", or in the storage system" or ""))
      report.set("waiting", "needs cobblestone")
      said = true
    end
    local timer = os.startTimer(10) -- the chest doesn't announce changes, so check it every 10s
    repeat
      local event, value = os.pullEvent()
    until event == "turtle_inventory" or (event == "timer" and value == timer)
  end
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
    if job.crew and job.phase == plan.sealPhase and not job.sealOk then
      crewBeforeSealing()
      job.sealOk = true
      save()
    end
    local size = phaseSize(job.phase)
    while job.cell < size do
      if job.phase == 0 then
        digCell(plan.hole, boxCell(plan.dig, job.cell))
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
  if job.crew then crewAfterSealing() end
  nav.deleteFile(JOB_FILE)
  if isHelper() then
    print("My strip is dug and walled in. The lead has the rest.")
    report.set("done", "my strip of the crew's hole is done")
    return
  end
  print("Excavation complete! The hole is dug and walled in.")
  report.set("done", "excavation complete")
  if job.plan then
    -- the plan's north-west bottom corner is the hole's, on its floor
    local ax, _, az = toWorld({ x = 0, y = 0, z = 0 })
    local bx, _, bz = toWorld({ x = job.width - 1, y = 0, z = job.length - 1 })
    local x0, z0 = math.min(ax, bx), math.min(az, bz)
    local y0 = job.origin.y + plan.hole.y0
    local home = job.home or { x = 0, z = 0 }
    print(("Now for the %s plan. Put a builder turtle"):format(job.plan))
    if job.gps then
      print(("at %d %d %d facing south, its chests behind"):format(x0 + home.x, y0, z0 + home.z))
      print("and to its left, and run 'builder setup'. Then:")
      print(("  build %s %d %d %d"):format(job.plan, x0, y0, z0))
    else
      print(("%d east and %d south of the hole's north-west"):format(home.x, home.z))
      print("corner, facing south, chests behind and left.")
      print(("Then 'build %s <x> <y> <z>': that corner, on the floor."):format(job.plan))
    end
  end
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Job cancelled.")
  return
end

require("lib.label").set("Excavator")
job = nav.readFile(JOB_FILE)

-- Nothing moves without GPS: wait for it (nav.waitForGps says why on screen).
-- The turtle works in real world coordinates and re-checks its position and
-- facing every time it starts. A job from before GPS was needed keeps using
-- the saved position, since its coordinates are relative to the start.
local hasGps = nav.waitForGps() ~= nil
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
  -- an 'excavate atrium' job from before plans carried their own hole
  if job.atrium and not job.plan then job.plan, job.home = "atrium", { x = 29, z = 7 } end
  buildPlan()
  if args[1] == "here" then
    -- the player has put the turtle back on its start block
    local x, y, z = toWorld(plan.start)
    nav.setPosition(x, y, z, job.origin.heading, job.gps)
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
elseif args[1] == "join" then
  if not hasGps then
    print("Joining a crew needs GPS: I work in the lead's world coordinates.")
    return
  end
  if args[2] and not tonumber(args[2]) then
    print("Usage: excavate join [lead turtle's id]")
    return
  end
  job = joinCrew(tonumber(args[2]))
  if not job then return end
  buildPlan()
  print(("My strip: %d columns, %d to %d of %d."):format(job.strip.x1 - job.strip.x0 + 1, job.strip.x0 + 1,
    job.strip.x1 + 1, job.width))
  save()
  faceChest()
  hookChest()
  topUpFuel(REFUEL_TO)
  nav.face(job.origin.heading)
else
  -- numbers are width, length, height in that order; the mode word and a
  -- plan name can go anywhere
  local nums, dir, planName = {}, "up", nil
  for _, a in ipairs(args) do
    if tonumber(a) then
      nums[#nums + 1] = math.floor(tonumber(a))
    elseif a == "up" or a == "down" or a == "deep" then
      dir = a
    else
      planName = a
    end
  end
  local hole, home = { 21, 21, 16 }, nil
  if planName then
    local found, homeOrWhy = planHole(planName)
    if not found then
      print(homeOrWhy)
      print("Usage: excavate [width] [length] [height] [up|down|deep]")
      print("       excavate <plan> [up|down|deep]")
      return
    end
    hole, home = found, homeOrWhy
    if #nums > 0 then
      print(("The %s plan needs a %dx%dx%d hole: leave the sizes out."):format(planName, hole[1], hole[2], hole[3]))
      return
    end
  end
  -- one number is a cube that size
  if #nums == 1 then nums[2], nums[3] = nums[1], nums[1] end
  local w, l, h = nums[1] or hole[1], nums[2] or hole[2], nums[3] or hole[3]
  if w < 1 or l < 1 or h < 1 then
    print("Usage: excavate [width] [length] [height] [up|down|deep]")
    print("       excavate <size> [up|down|deep]   (a cube)")
    print("       excavate <plan> [up|down|deep]")
    return
  end
  if not knowsPosition then
    -- A plan's hole has to line up with north. Without GPS, ask which way that is.
    local facing = "north"
    if planName then
      facing = nil
      while not facing do
        write("Which way am I facing (north, east, south, west)? ")
        local answer = read():lower()
        if nav.HEADINGS[answer] then facing = answer end
      end
    end
    nav.setPosition(0, 0, 0, facing)
  end
  -- The turtle sits at the hole's corner, or above its middle in deep mode.
  -- The origin is the hole's corner, so shift it back from the turtle.
  local p, heading = nav.getPos(), nav.getHeading()
  -- width runs to the turtle's right: east-west when it faces north or
  -- south, north-south when it faces east or west; a plan's isn't turned
  if planName and heading % 2 == 1 then w, l = l, w end
  local start = { x = 0, y = 0, z = 0 }
  if dir == "deep" then start = { x = math.floor(w / 2), y = 0, z = math.floor(l / 2) } end
  local f, r = DIRS[heading], DIRS[(heading + 1) % 4]
  job = { v = JOB_VERSION, width = w, length = l, height = h, dir = dir, plan = planName, home = home, phase = 0, cell = 0,
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
  if planName then
    print(("Hole %dx%dx%d (%s) for the %s plan: %d east-west, %d north-south."):format(hole[1], hole[2], hole[3], dir,
      planName, hole[1], hole[2]))
  else
    print(("Hole %dx%dx%d (%s)."):format(w, l, h, dir))
  end
  if SEAL_WALLS then print("Then I wall in every gap and dry it out.") end
  print(("Needs about %d fuel (have %s). I refuel from the chest"):format(fuel, tostring(turtle.getFuelLevel())))
  print("behind me, so put coal in it. Mined coal goes there too.")
  if USE_STORAGE then
    print("If it's on a storage system's cable (or")
    print("an ender chest twin of one), I order fuel")
    print("through it and the loot goes home.")
  end
  -- Helpers can join until Enter: 'excavate join' on each.
  local hosting = hasGps and net.open()
  if hosting then
    job.crew = { members = {} }
    recruiting = true
    rednet.host(CREW_PROTOCOL, "excavate-" .. os.getComputerID())
    print("More turtles? Run 'excavate join' on each now.")
  end
  print("Chest goes directly behind me. Press Enter to start.")
  if hosting then
    parallel.waitForAny(read, crewLoop)
    rednet.unhost(CREW_PROTOCOL)
    recruiting = false
    if #job.crew.members == 0 then
      job.crew = nil
    else
      splitStrips()
      buildPlan()
      print(("A crew of %d. My strip: columns %d to %d of %d."):format(#job.crew.members + 1, job.strip.x0 + 1,
        job.strip.x1 + 1, job.width))
      for _, m in ipairs(job.crew.members) do
        print(("Turtle %d: columns %d to %d (%d wide)."):format(m.id, m.strip.x0 + 1, m.strip.x1 + 1,
          m.strip.x1 - m.strip.x0 + 1))
      end
    end
  else
    read()
  end
  save()
  faceChest()
  hookChest()
  topUpFuel(REFUEL_TO)
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
end, report.loop, function()
  -- the lead keeps answering its helpers while it works
  if isLead() then crewLoop() else os.pullEvent("never") end
end)
