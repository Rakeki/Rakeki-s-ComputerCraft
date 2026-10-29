-- Standalone excavator (no server). Clears a hall, digs two floors of rooms
-- off its walls, then builds a ledge around the hall at the upper floor with
-- stairs up to it.
--
--   excavate [width] [length] [height] [up|down|deep]    (default 21 21 16 up)
--   excavate atrium [up|down|deep]   21x21x16 with a sunken garden pit, for plans/atrium.lua
--   excavate resume
--   excavate here       you put me back on my start block (no GPS): carry on from there
--   excavate cancel
--
-- Place the turtle in a corner of the area, facing along one edge. The hall
-- runs forward (length), to the right (width), and up or down (height) from
-- the turtle's block. Put a chest directly behind the turtle for loot.
--
-- "deep" digs a shaft straight down from the turtle and builds the hall
-- centred underneath it, with its floor ABOVE_BEDROCK layers above bedrock.
-- The turtle comes back up the shaft to the chest.
--
-- The layout is mirror-symmetric when the width and length are odd (rooms
-- line up evenly and every wall has a centre block for its middle door).
--
-- "atrium" digs the default hall plus a stepped pit in the middle of its
-- floor and leaves out the ledge and stairs: the atrium plan builds those,
-- with the pillars, arches, railing and garden, through build-control and
-- builder turtles. It prints the build command when it's done.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.excavate_job"

-- Layout. Heights are counted from the hall floor.
local ROOM_WIDTH = 5 -- along the wall
local ROOM_DEPTH = 10 -- away from the wall
local ROOM_HEIGHT = 6
local ROOM_GAP = 1 -- solid blocks between neighbouring rooms (a single wall)
local WALL = 1 -- wall between the hall and each room
local DOOR_HEIGHT = 3 -- 2 or 3; doorways are 1 wide
local UPPER_FLOOR = 7 -- standing height of the upper floor (top of the ledge)
local LEDGE_WIDTH = 3 -- walkway around the hall at the upper floor
local STAIR_WIDTH = 2 -- split staircase on every wall, rising from its middle to both ends

-- After digging, walk the edge of the hall, rooms and doorways and fill any
-- gap in the walls, floor or ceiling (cave, ravine, water, lava) with
-- cobblestone. Adds several thousand moves (and fuel); set to false to skip.
local SEAL_WALLS = true
local SEAL_SPARE = 192 -- cobblestone carried while digging, for patching (3 slots)

-- "deep" mode: hall floor goes at BEDROCK_TOP + ABOVE_BEDROCK.
-- BEDROCK_TOP is -60 in Minecraft 1.18+ (use 4 for 1.17 and older).
local BEDROCK_TOP = -60
local ABOVE_BEDROCK = 10

-- "atrium": the pit dug into the middle of the hall floor, for the garden
-- and pond in plans/atrium.lua. Change these and that plan together.
local ATRIUM_SIZE = { 21, 21, 16 } -- width, length, height the plan fits
local PIT_RADIUS = 3 -- 7x7 garden beds...
local PIT_DEPTH = 3 -- ...3 deep
local POND_RADIUS = 1 -- 3x3 pond in the middle...
local POND_DEPTH = 1 -- ...1 deeper still
local BUILDER_HOME = { x = 5, z = 5 } -- a spot on the floor the plan leaves clear above, for the builder turtle

-- Kept while digging for patching walls (only SEAL_SPARE of them).
local PATCH_BLOCKS = { ["minecraft:cobblestone"] = true, ["minecraft:cobbled_deepslate"] = true }

-- The ledge and stairs are built from blocks you choose. Before building, the
-- turtle goes home, empties out, and asks you to load these slots.
local LEDGE_SLOTS = { 1, 4 } -- the ledge walkway (and the top steps, which are level with it)
local STAIR_SLOTS = { 5, 8 } -- the stairs; real stair blocks work and are placed facing up the flight
local STAIR_FLIP = false -- set to true if stair blocks come out facing the wrong way

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

-- Job coordinates are local to the hall's corner: x to the right, z forward,
-- y up. The turtle starts at job.start: the corner (0, 0, 0), or the middle
-- of the hall in deep mode.
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
  local W, L, H = job.width, job.length, job.height
  local F = 0 -- hall floor
  if job.dir == "down" then F = -(H - 1) elseif job.dir == "deep" then F = job.floor end
  plan = {
    hall = { x0 = 0, x1 = W - 1, y0 = F, y1 = F + H - 1, z0 = 0, z1 = L - 1 },
    rooms = {},
    builds = {}, -- { x, y, z } spots to stand on and place a block below
    start = job.start or { x = 0, y = 0, z = 0 }, -- jobs saved before job.start existed
    -- nothing is built at or above this height, so it's safe to fly across
    flyY = F + UPPER_FLOOR,
    symmetric = true,
  }
  -- deep mode: a 1x1 shaft from the start block down into the hall
  if job.dir == "deep" then plan.shaftBottom = { x = plan.start.x, y = F + H - 1, z = plan.start.z } end
  local half = math.floor(ROOM_WIDTH / 2)

  -- n evenly spaced rooms centred along a wall of length len
  local function along(len, make)
    local n = math.floor((len + ROOM_GAP) / (ROOM_WIDTH + ROOM_GAP))
    local spare = len - (n * ROOM_WIDTH + (n - 1) * ROOM_GAP)
    if spare % 2 == 1 then plan.symmetric = false end
    for i = 0, n - 1 do make(math.floor(spare / 2) + i * (ROOM_WIDTH + ROOM_GAP)) end
  end

  for _, level in ipairs({ 0, UPPER_FLOOR }) do
    local fy = F + level
    local cy = fy + 1 -- travel height through doorways
    -- door: wall cells from the hall outwards; hallSide: last hall cell; inner: first room cell
    local function add(x0, x1, z0, z1, door, hallSide, inner)
      table.insert(plan.rooms, {
        box = { x0 = x0, x1 = x1, y0 = fy, y1 = fy + ROOM_HEIGHT - 1, z0 = z0, z1 = z1 },
        door = door, hallSide = hallSide, inner = inner,
      })
    end
    local function doorLine(fixed, axis, from, step)
      local cells = {}
      for i = 0, WALL - 1 do
        local c = { y = cy }
        c[axis] = from + i * step
        c[axis == "x" and "z" or "x"] = fixed
        cells[#cells + 1] = c
      end
      return cells
    end

    along(W, function(a) -- far wall (+z)
      local dx = a + half
      add(a, a + ROOM_WIDTH - 1, L + WALL, L + WALL + ROOM_DEPTH - 1, doorLine(dx, "z", L, 1),
        { x = dx, y = cy, z = L - 1 }, { x = dx, y = cy, z = L + WALL })
    end)
    along(W, function(a) -- near wall (-z)
      local dx = a + half
      add(a, a + ROOM_WIDTH - 1, -WALL - ROOM_DEPTH, -WALL - 1, doorLine(dx, "z", -1, -1),
        { x = dx, y = cy, z = 0 }, { x = dx, y = cy, z = -WALL - 1 })
    end)
    along(L, function(a) -- right wall (+x)
      local dz = a + half
      add(W + WALL, W + WALL + ROOM_DEPTH - 1, a, a + ROOM_WIDTH - 1, doorLine(dz, "x", W, 1),
        { x = W - 1, y = cy, z = dz }, { x = W + WALL, y = cy, z = dz })
    end)
    along(L, function(a) -- left wall (-x)
      local dz = a + half
      add(-WALL - ROOM_DEPTH, -WALL - 1, a, a + ROOM_WIDTH - 1, doorLine(dz, "x", -1, -1),
        { x = 0, y = cy, z = dz }, { x = -WALL - 1, y = cy, z = dz })
    end)
  end

  -- ledge: a ring LEDGE_WIDTH wide around the hall, snaking row by row
  local standY = F + UPPER_FLOOR
  for z = 0, L - 1 do
    for i = 0, W - 1 do
      local x = z % 2 == 0 and i or W - 1 - i
      if math.min(x, W - 1 - x, z, L - 1 - z) < LEDGE_WIDTH then
        table.insert(plan.builds, { x = x, y = standY, z = z, mat = "ledge" })
      end
    end
  end

  -- Split staircase just inside the ledge on every wall: a landing at floor
  -- level in the middle of the wall, with a flight rising to each end. Where
  -- two flights meet in a corner the lower step wins, so every corner is
  -- walkable from both sides.
  local steps = UPPER_FLOOR
  local heights = {} -- "x,z" -> step number (standing height above the floor)
  local function step(x, z, k)
    local key = x .. "," .. z
    if not heights[key] or k < heights[key] then heights[key] = k end
  end
  local function fits(len) return math.floor((len - 1) / 2) - steps >= LEDGE_WIDTH end
  plan.hasStairs = fits(W) and fits(L)
  if plan.hasStairs then
    local lowZ, highZ = math.floor((L - 1) / 2), math.ceil((L - 1) / 2)
    local lowX, highX = math.floor((W - 1) / 2), math.ceil((W - 1) / 2)
    for i = 0, STAIR_WIDTH - 1 do
      for k = 1, steps do
        -- left and right walls: flights run along z
        for _, x in ipairs({ LEDGE_WIDTH + i, W - 1 - LEDGE_WIDTH - i }) do
          step(x, highZ + k, k)
          step(x, lowZ - k, k)
        end
        -- near and far walls: flights run along x
        for _, z in ipairs({ LEDGE_WIDTH + i, L - 1 - LEDGE_WIDTH - i }) do
          step(highX + k, z, k)
          step(lowX - k, z, k)
        end
      end
    end
    -- Each step faces up the flight: towards the neighbour one step higher,
    -- looking along the wall first. Steps with nothing higher beside them
    -- (the top steps, level with the ledge, and the inside corner where two
    -- flights meet) act as landings, so they're built from ledge blocks.
    local function heightAt(x, z)
      if math.min(x, W - 1 - x, z, L - 1 - z) < LEDGE_WIDTH then return steps end
      return heights[x .. "," .. z] or 0
    end
    local SIDES = { [0] = { 0, 1 }, [1] = { 1, 0 }, [2] = { 0, -1 }, [3] = { -1, 0 } }
    for z = 0, L - 1 do
      for i = 0, W - 1 do
        local x = z % 2 == 0 and i or W - 1 - i
        local k = heights[x .. "," .. z]
        if k then
          local b = { x = x, y = F + k, z = z, mat = "ledge" }
          local alongZ = x < LEDGE_WIDTH + STAIR_WIDTH or x > W - 1 - LEDGE_WIDTH - STAIR_WIDTH
          for _, d in ipairs(alongZ and { 0, 2, 1, 3 } or { 1, 3, 0, 2 }) do
            if heightAt(x + SIDES[d][1], z + SIDES[d][2]) == k + 1 then
              b.mat, b.face = "stairs", d
              break
            end
          end
          table.insert(plan.builds, b)
        end
      end
    end
  end
  -- atrium: the plan builds the gallery and stairs, so they're left out here,
  -- and a stepped pit goes into the middle of the floor
  plan.pits = {}
  if job.atrium then
    plan.builds = {}
    local cx, cz = math.floor(W / 2), math.floor(L / 2)
    local function pit(r, top, depth)
      table.insert(plan.pits, { x0 = cx - r, x1 = cx + r, y0 = top - depth + 1, y1 = top, z0 = cz - r, z1 = cz + r })
    end
    pit(PIT_RADIUS, F - 1, PIT_DEPTH)
    pit(POND_RADIUS, F - 1 - PIT_DEPTH, POND_DEPTH)
  end
  plan.need = { ledge = 0, stairs = 0 }
  for _, b in ipairs(plan.builds) do plan.need[b.mat] = plan.need[b.mat] + 1 end

  -- Cells on the edge of the dig, and which of their sides face solid ground
  -- that should be there. The seal phase visits them and fills any gaps.
  plan.seals = {}
  if SEAL_WALLS then
    local hall = plan.hall
    local function inBox(b, x, y, z)
      return x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 and z >= b.z0 and z <= b.z1
    end
    local function inside(x, y, z)
      if inBox(hall, x, y, z) then return true end
      for _, p in ipairs(plan.pits) do
        if inBox(p, x, y, z) then return true end
      end
      if plan.shaftBottom and x == plan.start.x and z == plan.start.z and y > hall.y1 then return true end
      for _, r in ipairs(plan.rooms) do
        if inBox(r.box, x, y, z) then return true end
        for _, d in ipairs(r.door) do
          if d.x == x and d.z == z and y >= r.box.y0 and y < r.box.y0 + DOOR_HEIGHT then return true end
        end
      end
      return false
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
    -- top and bottom layers: every cell, snaking; layers between: just the rim
    local function sealBox(b)
      for y = b.y1, b.y0, -1 do
        if y == b.y0 or y == b.y1 then
          for z = b.z0, b.z1 do
            for i = 0, b.x1 - b.x0 do
              check((z - b.z0) % 2 == 0 and b.x0 + i or b.x1 - i, y, z)
            end
          end
        else
          for x = b.x0, b.x1 do check(x, y, b.z0) end
          for z = b.z0 + 1, b.z1 do check(b.x1, y, z) end
          if b.z1 > b.z0 then for x = b.x1 - 1, b.x0, -1 do check(x, y, b.z1) end end
          if b.x1 > b.x0 then for z = b.z1 - 1, b.z0 + 1, -1 do check(b.x0, y, z) end end
        end
      end
    end
    sealBox(hall)
    for _, p in ipairs(plan.pits) do sealBox(p) end
    for _, r in ipairs(plan.rooms) do
      for _, d in ipairs(r.door) do
        for y = r.box.y0, r.box.y0 + DOOR_HEIGHT - 1 do check(d.x, y, d.z) end
      end
      sealBox(r.box)
    end
  end

  -- phase 0 is the hall, phases 1..#rooms are rooms, then the pits (atrium
  -- only), then sealing, then building
  plan.pitPhase = #plan.rooms + 1
  plan.sealPhase = plan.pitPhase + #plan.pits
  plan.buildPhase = plan.sealPhase + 1
end

-- The pit dug in this phase, if it's a pit phase.
local function phasePit(phase)
  if phase >= plan.pitPhase and phase < plan.sealPhase then return plan.pits[phase - plan.pitPhase + 1] end
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
  if phase == 0 then return boxCells(plan.hall) end
  if phase == plan.sealPhase then return #plan.seals end
  if phase == plan.buildPhase then return #plan.builds end
  if phasePit(phase) then return boxCells(phasePit(phase)) end
  return boxCells(plan.rooms[phase].box) + 1 -- +1 for the doorway
end

local function inBox(b, p)
  return p.x >= b.x0 and p.x <= b.x1 and p.y >= b.y0 and p.y <= b.y1 and p.z >= b.z0 and p.z <= b.z1
end

local function roomContaining(p)
  for _, r in ipairs(plan.rooms) do
    if inBox(r.box, p) then return r end
    for _, d in ipairs(r.door) do
      if d.x == p.x and d.z == p.z and math.abs(p.y - d.y) <= 1 then return r end
    end
  end
end

-- The room and doorway cell (middle height) that p is standing in, if any.
local function doorAt(p)
  for _, r in ipairs(plan.rooms) do
    for _, d in ipairs(r.door) do
      if d.x == p.x and d.z == p.z and math.abs(p.y - d.y) <= 1 then return r, d end
    end
  end
end

local function inShaft(p)
  return plan.shaftBottom and p.x == plan.start.x and p.z == plan.start.z and p.y > plan.hall.y1
end

-- Move anywhere in the dig, going through doorways instead of through walls
-- and up and down the shaft instead of tunnelling a new one.
local function travel(t)
  local p = here()
  if inShaft(p) and inShaft(t) then return goL(t) end
  if inShaft(p) then
    goL(plan.shaftBottom)
    p = here()
  end
  local dest = inShaft(t) and plan.shaftBottom or t

  -- In a doorway: only move straight up or down within it, or step back to
  -- its middle and leave sideways, so the wall above the door stays intact.
  local doorRoom, door = doorAt(p)
  if doorRoom then
    local _, destDoor = doorAt(dest)
    if destDoor == door then return goL(dest) end
    goL(door)
    if roomContaining(dest) == doorRoom and not destDoor then goL(doorRoom.inner) else goL(doorRoom.hallSide) end
    p = here()
  end

  local from, to = roomContaining(p), roomContaining(dest)
  if from ~= to then
    if from then
      goL(from.inner)
      goL(from.hallSide)
    end
    if to then
      goL(to.hallSide)
      goL(to.inner)
    end
  end
  local ok, err = goL(dest)
  if dest ~= t then ok, err = goL(t) end
  return ok, err
end

---------------------------------------------------------------- position checks

local reach -- defined below; used by the trips home

local gpsPos = nav.locate

-- Somewhere the turtle is meant to be: inside the dig, in the shaft, or on its start block.
local function onPlan(p)
  local s = plan.start
  for _, pit in ipairs(plan.pits) do
    if inBox(pit, p) then return true end
  end
  return inBox(plan.hall, p) or roomContaining(p) ~= nil or inShaft(p)
    or (p.x == s.x and p.y == s.y and p.z == s.z)
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
  local d = math.abs(p.x - s.x) + math.abs(p.y - s.y) + math.abs(p.z - s.z)
  if roomContaining(p) then d = d + 2 * (ROOM_DEPTH + WALL + ROOM_WIDTH) end
  return d + 50
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

-- The main item in a range of slots: its name and how many there are.
local function rangeContents(range)
  local name, count = nil, 0
  for slot = range[1], range[2] do
    local item = turtle.getItemDetail(slot)
    if item then
      name = name or item.name
      if item.name == name then count = count + item.count end
    end
  end
  return name, count
end

local function rangeCapacity(range) return (range[2] - range[1] + 1) * 64 end

-- Before building: get enough fuel to finish without going home (a trip home
-- could dig through the half-built ledge), empty out at the chest, and ask
-- the player which blocks to build with.
local function prepareBuild()
  -- the build route: up to the fly height, across, and down onto each spot
  local fuelNeeded, at = 200, { x = plan.start.x, y = plan.flyY, z = plan.start.z }
  for _, b in ipairs(plan.builds) do
    fuelNeeded = fuelNeeded + math.abs(at.y - plan.flyY) + math.abs(at.x - b.x) + math.abs(at.z - b.z)
      + math.abs(plan.flyY - b.y)
    at = b
  end
  fuelNeeded = fuelNeeded + math.abs(plan.flyY - plan.start.y) + plan.hall.x1 + plan.hall.z1 + 2 * plan.hall.y1 - 2 * plan.hall.y0
  if fuelLevel() < fuelNeeded then
    refuelFromInventory(fuelNeeded)
    if fuelLevel() < fuelNeeded then waitForFuel(fuelNeeded) end
  end
  reach(plan.start)
  faceChest()
  dropItems(function() return true end, turtle.drop)

  local need = {
    ledge = math.min(plan.need.ledge, rangeCapacity(LEDGE_SLOTS)),
    stairs = math.min(plan.need.stairs, rangeCapacity(STAIR_SLOTS)),
  }
  while true do
    local ledgeName, ledgeCount = rangeContents(LEDGE_SLOTS)
    local stairName, stairCount = rangeContents(STAIR_SLOTS)
    if ledgeCount >= need.ledge and stairCount >= need.stairs then
      job.materials = { ledge = ledgeName, stairs = stairName }
      save()
      print(("Building the ledge with %s%s."):format(tostring(ledgeName),
        need.stairs > 0 and (" and the stairs with " .. tostring(stairName)) or ""))
      return
    end
    print("Ready to build the ledge and stairs. What should I build them with?")
    print(("  Slots %d-%d: ledge blocks, %d needed (have %d)"):format(LEDGE_SLOTS[1], LEDGE_SLOTS[2], plan.need.ledge, ledgeCount))
    if need.stairs > 0 then
      print(("  Slots %d-%d: stair blocks, %d needed (have %d)"):format(STAIR_SLOTS[1], STAIR_SLOTS[2], plan.need.stairs, stairCount))
      print("  Real stair blocks work: I'll face them up the stairs.")
    end
    print("Fill the slots, then press Enter.")
    report.set("waiting", "needs blocks for the ledge and stairs")
    read()
  end
end

-- Select the ledge or stair material the player chose.
local function selectMaterial(mat)
  local range = mat == "stairs" and STAIR_SLOTS or LEDGE_SLOTS
  local want = job.materials and job.materials[mat]
  for slot = range[1], range[2] do
    local item = turtle.getItemDetail(slot)
    if item and (not want or item.name == want) then
      turtle.select(slot)
      return true
    end
  end
  return false
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
  for phase = 0, plan.buildPhase do
    local size = phaseSize(phase)
    total = total + size
    if phase < job.phase then done = done + size elseif phase == job.phase then done = done + job.cell end
  end
  local name = job.phase == 0 and "hall"
    or job.phase == plan.sealPhase and "sealing walls"
    or job.phase == plan.buildPhase and "ledge and stairs"
    or phasePit(job.phase) and "garden pit"
    or ("room %d/%d"):format(job.phase, #plan.rooms)
  return ("%s, %d%% overall"):format(name, math.floor(done / total * 100))
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

-- Out of cobblestone mid-seal: go home and wait for more.
-- Out of cobblestone mid-seal (a really big cave): go home and ask for more.
local function restockBlocks()
  reach(plan.start)
  faceChest()
  print("Out of cobblestone for patching walls. Add some to my inventory.")
  report.set("waiting", "needs cobblestone")
  while not selectPatchBlock() do os.pullEvent("turtle_inventory") end
end

-- Fill any gap on the outward sides of an edge cell.
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
    if not detect() then -- air or fluid where there should be a wall
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
  while job.phase <= plan.buildPhase do
    if job.phase == plan.buildPhase and job.cell == 0 and #plan.builds > 0 then prepareBuild() end
    local size = phaseSize(job.phase)
    while job.cell < size do
      if job.phase == 0 then
        digCell(plan.hall, boxCell(plan.hall, job.cell))
      elseif phasePit(job.phase) then
        digCell(phasePit(job.phase), boxCell(phasePit(job.phase), job.cell))
      elseif job.phase == plan.sealPhase then
        sealCell(plan.seals[job.cell + 1])
      elseif job.phase == plan.buildPhase then
        -- fly across above everything built, then drop straight down onto the spot
        local b = plan.builds[job.cell + 1]
        if reach({ x = b.x, y = plan.flyY, z = b.z }) and goL(b) then
          while not selectMaterial(b.mat) do
            local range = b.mat == "stairs" and STAIR_SLOTS or LEDGE_SLOTS
            print(("Out of %s blocks. Add more to slots %d-%d."):format(b.mat, range[1], range[2]))
            report.set("waiting", "needs more " .. b.mat .. " blocks")
            os.pullEvent("turtle_inventory")
          end
          -- stair blocks face the way the turtle faces, so face up the flight
          if b.face then nav.face((job.origin.heading + b.face + (STAIR_FLIP and 2 or 0)) % 4) end
          turtle.placeDown()
        end
      else
        local room = plan.rooms[job.phase]
        if job.cell == 0 then
          -- open the doorway on the way in
          reach(room.hallSide)
          for _, d in ipairs(room.door) do
            if goL(d) then
              nav.digDown()
              if DOOR_HEIGHT >= 3 then nav.digUp() end
            end
          end
          goL(room.inner)
        else
          digCell(room.box, boxCell(room.box, job.cell - 1))
        end
      end
      job.cell = job.cell + 1
      save()
      if job.cell % 20 == 0 then checkPosition() end
      if job.phase ~= plan.buildPhase then housekeeping() end
      if job.cell % 25 == 0 then print(progressText()) end
      -- only GPS jobs have real world coordinates; otherwise report.lua tries GPS itself
      report.set(job.phase == plan.buildPhase and "building" or job.phase == plan.sealPhase and "sealing" or "digging",
        progressText(), job.gps and { pos = nav.getPos() } or nil)
    end
    job.phase, job.cell = job.phase + 1, 0
    save()
  end

  -- Get home without walking through the ledge or stairs: climb above them,
  -- and if home is below them, come down the middle of the hall, where the
  -- stairs have their landings, and walk along the floor from there.
  local p = here()
  goL({ x = p.x, y = math.max(p.y, plan.flyY), z = p.z })
  if plan.start.y < plan.flyY then
    local cx, cz = math.floor(job.width / 2), math.floor(job.length / 2)
    goL({ x = cx, y = plan.flyY, z = cz })
    goL({ x = cx, y = plan.hall.y0, z = cz })
  end
  reach(plan.start)
  nav.face(job.origin.heading)
  nav.deleteFile(JOB_FILE)
  print("Excavation complete!")
  report.set("done", "excavation complete")
  if job.atrium then
    -- the plan's north-west bottom corner is the hall's, at the bottom of the pond
    local ax, _, az = toWorld({ x = 0, y = 0, z = 0 })
    local bx, _, bz = toWorld({ x = job.width - 1, y = 0, z = job.length - 1 })
    local x0, z0 = math.min(ax, bx), math.min(az, bz)
    local y0 = job.origin.y + plan.hall.y0 - PIT_DEPTH - POND_DEPTH
    print("Now for the atrium plan. Put a builder turtle")
    if job.gps then
      print(("at %d %d %d facing east, its chests behind"):format(x0 + BUILDER_HOME.x, y0 + PIT_DEPTH + POND_DEPTH, z0 + BUILDER_HOME.z))
      print("and to its left, and run 'builder setup'. Then:")
      print(("  build atrium %d %d %d"):format(x0, y0, z0))
    else
      print(("%d east and %d south of the hall's north-west"):format(BUILDER_HOME.x, BUILDER_HOME.z))
      print("corner, facing east, chests behind and left.")
      print(("Then 'build atrium <x> <y> <z>': that corner, %d below the floor."):format(PIT_DEPTH + POND_DEPTH))
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
    if tonumber(a) then nums[#nums + 1] = tonumber(a) elseif a == "atrium" then atrium = true else dir = a end
  end
  local w, l, h = nums[1] or 21, nums[2] or 21, nums[3] or 16
  if dir ~= "up" and dir ~= "down" and dir ~= "deep" then
    print("Usage: excavate [width] [length] [height] [up|down|deep]")
    print("       excavate atrium [up|down|deep]")
    return
  end
  if atrium and (w ~= ATRIUM_SIZE[1] or l ~= ATRIUM_SIZE[2] or h < ATRIUM_SIZE[3]) then
    print(("The atrium plan fits a %dx%dx%d hall: leave the sizes out."):format(ATRIUM_SIZE[1], ATRIUM_SIZE[2], ATRIUM_SIZE[3]))
    return
  end
  if h < UPPER_FLOOR + ROOM_HEIGHT then
    print(("Height must be at least %d to fit two floors of rooms."):format(UPPER_FLOOR + ROOM_HEIGHT))
    return
  end
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  -- The turtle sits at the hall's corner, or above its middle in deep mode.
  -- The origin is the hall's corner, so shift it back from the turtle.
  local p, heading = nav.getPos(), nav.getHeading()
  local start = { x = 0, y = 0, z = 0 }
  if dir == "deep" then start = { x = math.floor(w / 2), y = 0, z = math.floor(l / 2) } end
  local f, r = DIRS[heading], DIRS[(heading + 1) % 4]
  job = { width = w, length = l, height = h, dir = dir, atrium = atrium or nil, phase = 0, cell = 0, start = start, gps = hasGps,
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
      print(("The turtle must be above Y %d for the hall to fit below it."):format(floorY + h - 1))
      return
    end
    depth = startY - (floorY + h - 1)
    print(("Shaft %d blocks down; hall floor at Y %d (%d above bedrock)."):format(depth, floorY, ABOVE_BEDROCK))
  end
  buildPlan()

  local total = 0
  for phase = 0, plan.buildPhase do total = total + phaseSize(phase) end
  -- each trip to the chest goes up and down the shaft
  local fuel = math.floor(total * 1.3 + (total / 300) * 2 * depth + 2 * depth)
  if atrium then
    print(("Hall %dx%dx%d (%s), %d rooms on 2 floors, garden pit."):format(w, l, h, dir, #plan.rooms))
  else
    print(("Hall %dx%dx%d (%s), %d rooms on 2 floors, ledge%s."):format(w, l, h, dir, #plan.rooms,
      plan.hasStairs and " and stairs" or " (no room for stairs)"))
  end
  if not plan.symmetric then
    print("Note: rooms can't be spaced evenly at this size, so the layout won't be")
    print("perfectly symmetric. Odd sizes like 21 work best.")
  end
  print(("Needs about %d fuel (have %s). I refuel from the chest"):format(fuel, tostring(turtle.getFuelLevel())))
  print("behind me, so put coal in it. Mined coal goes there too.")
  if atrium then
    print("The ledge, stairs and the rest come from the")
    print("atrium plan afterwards (build-control).")
  else
    print(("When it's time to build I'll ask for %d ledge blocks (slots %d-%d)"):format(plan.need.ledge, LEDGE_SLOTS[1], LEDGE_SLOTS[2]))
  end
  if plan.need.stairs > 0 then
    print(("and %d stair blocks (slots %d-%d)."):format(plan.need.stairs, STAIR_SLOTS[1], STAIR_SLOTS[2]))
  end
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
