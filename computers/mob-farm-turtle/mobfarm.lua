-- Mob farm builder. Builds a dark spawning room high above its start, with
-- four water channels that wash mobs into a 2x2 drop shaft in the middle.
-- They fall onto hoppers at the bottom, which feed a double chest beside a
-- small pit you stand in to collect the loot (or, with a 22 block drop, to
-- finish the mobs off yourself for XP).
--
--   mobfarm [drop]          build a farm; drop is the fall height (default 32)
--   mobfarm list [drop]     what to put in the supply chest
--   mobfarm resume
--   mobfarm here
--   mobfarm cancel
--
-- Place the turtle on the ground where you want to collect, facing the way
-- the farm should go, with the supply chest directly behind it. The shaft
-- comes down one block in front of the turtle (2x2: in front and
-- front-right) and the room is centred on it, 18x18 inside.
--
-- Layout in local coordinates (x right, z forward, y up; the start is 0,0,0
-- and F is the drop height):
--   y -1       pit at z 0 (x 0-1), double chest at z 1, hoppers at z 2-3
--   y 0        bottom slabs at z 1; the gap above them is the kill window
--   y 0..F-2   shaft walls round x 0-1, z 2-3
--   y F-1, F   channel beds, then the floor with water channels in it
--   y F..F+2   outer walls, roof at F+3
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.mobfarm_job"

-- Fall from the spawning floor to the hoppers. Fall damage is the height
-- minus 3, so 32 kills everything that spawns (witches have 26 health).
-- 22 leaves zombies and skeletons on half a heart for you to finish off.
local DEFAULT_DROP = 32
local MIN_DROP = 8 -- any lower and the room would sit on the ground
local ROOM_HEIGHT = 2 -- headroom over the spawning floor; 2 keeps endermen out
-- Channel length out from the shaft. Water flows 7 blocks from its source,
-- so 8 carries mobs right up to the shaft without pouring down it.
local ARM = 8

local LOAD_SLOTS = 11 -- stacks of building blocks carried per trip
local REFUEL_TO = 3000 -- fuel it tops up to at the supply chest
local DEFAULT_BLOCK = "minecraft:cobblestone" -- built with this if slot 1 is empty at the start

local FUEL = {}
for _, n in ipairs({ "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block", "minecraft:lava_bucket",
  "minecraft:blaze_rod", "minecraft:dried_kelp_block" }) do FUEL[n] = true end

-- Thrown away instead of carried back to the chest.
local JUNK = {}
for _, name in ipairs({
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:deepslate",
  "minecraft:dirt", "minecraft:gravel", "minecraft:andesite", "minecraft:diorite", "minecraft:granite",
  "minecraft:tuff", "minecraft:calcite", "minecraft:netherrack",
}) do JUNK[name] = true end

-- Everything placed apart from building blocks: which item it is, and how
-- to tell it's already in place.
local SPECIAL = {
  hopper = { label = "hoppers", item = function(n) return n == "minecraft:hopper" end,
    placed = function(d) return d.name == "minecraft:hopper" end },
  chest = { label = "chests", item = function(n) return n == "minecraft:chest" end,
    placed = function(d) return d.name == "minecraft:chest" end },
  slab = { label = "slabs (any kind)", item = function(n) return n:sub(-5) == "_slab" end,
    placed = function(d) return d.name:sub(-5) == "_slab" end },
  water = { label = "water buckets", item = function(n) return n == "minecraft:water_bucket" end,
    placed = function(d) return d.name == "minecraft:water" and d.state and d.state.level == 0 end },
}
local SPECIAL_ORDER = { "hopper", "chest", "slab", "water" }

local PHASE_NAMES = {
  base = "pit, chests and hoppers", shaft = "drop shaft", channels = "channel beds",
  floor = "spawning floor", walls = "walls", water = "water", roof = "roof",
}

local HOME = { x = 0, y = 0, z = 0 }

local job, plan

---------------------------------------------------------------- coordinates

-- Job coordinates are local to the start: x to the right, z forward, y up.
local DIRS = { [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 } }
local WORLD_FACING = { [0] = "north", [1] = "east", [2] = "south", [3] = "west" }

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

-- Local headings: 0 = forward (+z), 1 = right (+x), 2 = back (-z), 3 = left (-x).
local function faceLocal(d) nav.face((job.origin.heading + d) % 4) end
local function faceChest() faceLocal(2) end

local function dist(a, b) return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z) end

local function P(x, y, z) return { x = x, y = y, z = z } end

---------------------------------------------------------------- plan

-- Every step of the build is an op: a spot to stand on, then dig below,
-- make sides solid (op.solid: "up", "down" or local headings) or place one
-- special item (op.place, on side op.dir). Ops are safe to redo, since a
-- reboot can land halfway through one.
local function buildPlan()
  local F = job.drop
  plan = { F = F, ops = {} }
  local ops = plan.ops
  local function add(phase, op)
    op.phase = phase
    op.index = #ops + 1
    ops[op.index] = op
  end

  -- Floor: 18x18 round the 2x2 hole at x 0-1, z 2-3. Walls one block outside.
  local X0, X1, Z0, Z1 = -ARM, 1 + ARM, 2 - ARM, 3 + ARM
  plan.wx0, plan.wx1, plan.wz0, plan.wz1 = X0 - 1, X1 + 1, Z0 - 1, Z1 + 1
  plan.C = F + ROOM_HEIGHT + 2 -- standing on the roof: nothing is ever built this high
  -- The way up from the start: a column outside the room, left of the supply chest.
  plan.lift = { x = -1, z = plan.wz0 - 2 }
  local function isHole(x, z) return x >= 0 and x <= 1 and z >= 2 and z <= 3 end
  local function isArm(x, z)
    if isHole(x, z) then return false end
    return (x >= 0 and x <= 1) or (z >= 2 and z <= 3)
  end
  local function snake(x0, x1, z0, z1, fn)
    for z = z0, z1 do
      for i = 0, x1 - x0 do fn((z - z0) % 2 == 0 and x0 + i or x1 - i, z) end
    end
  end

  -- The base is reached from the start along fixed paths (op.path, ending
  -- at the spot), so nothing already placed down there gets dug through.
  local up, right = P(0, 1, 0), P(1, 0, 0)
  local function base(path, op)
    op.path, op.at = path, path[#path] or HOME
    add("base", op)
  end
  base({}, { dig = true }) -- the pit you stand in
  base({ right }, { dig = true })
  base({ P(0, -1, 0) }, { solid = { "down", 3, 2 } }) -- pit floor, left wall, under the supply chest
  base({ right, P(1, -1, 0) }, { solid = { "down", 1, 2 } })
  -- ground under each slab, so the slab goes in as a bottom slab
  base({ P(0, 0, 1) }, { solid = { "down" } })
  base({ right, P(1, 0, 1) }, { solid = { "down" } })
  base({ up, P(0, 1, 1) }, { place = "slab", dir = "down" })
  base({ up, P(1, 1, 0), P(1, 1, 1) }, { place = "slab", dir = "down" })
  -- chests go under the slabs (the ground there is dug out), opening onto the pit
  base({ P(0, -1, 0) }, { place = "chest", dir = 0 })
  base({ right, P(1, -1, 0) }, { place = "chest", dir = 0 })
  -- Hoppers are placed facing back, so they point into the block beyond:
  -- the front ones into the chests, the back ones into the front ones.
  base({ up, P(0, 1, 3), P(0, -1, 3) }, { place = "hopper", dir = 2 })
  base({ up, P(1, 1, 0), P(1, 1, 3), P(1, -1, 3) }, { place = "hopper", dir = 2 })
  base({ up, P(0, 1, 4), P(0, -1, 4) }, { place = "hopper", dir = 2 })
  base({ up, P(1, 1, 0), P(1, 1, 4), P(1, -1, 4) }, { place = "hopper", dir = 2 })

  -- Shaft: climb the inside, walling in the sides. At the bottom the back
  -- wall is already the slabs. The top two layers are just cleared, as the
  -- channel beds close them in. Corners can be left out: nothing gets
  -- through a diagonal gap, light included.
  local CELLS = { { 0, 2, { 3, 2 } }, { 1, 2, { 1, 2 } }, { 1, 3, { 1, 0 } }, { 0, 3, { 3, 0 } } }
  for y = 0, F do
    for i = 1, 4 do
      local c = CELLS[y % 2 == 0 and i or 5 - i]
      add("shaft", { at = P(c[1], y, c[2]), solid = y <= F - 2 and c[3] or nil })
    end
  end

  -- Channel beds first, from just above them, while nothing else is up there.
  snake(X0, X1, Z0, Z1, function(x, z)
    if isArm(x, z) then add("channels", { at = P(x, F, z), solid = { "down" } }) end
  end)
  snake(X0, X1, Z0, Z1, function(x, z)
    if not isArm(x, z) and not isHole(x, z) then add("floor", { at = P(x, F + 1, z), solid = { "down" } }) end
  end)

  -- Walls a layer at a time, walking round on top of the layer below.
  local ring = {}
  for x = plan.wx0, plan.wx1 do ring[#ring + 1] = { x, plan.wz0 } end
  for z = plan.wz0 + 1, plan.wz1 do ring[#ring + 1] = { plan.wx1, z } end
  for x = plan.wx1 - 1, plan.wx0, -1 do ring[#ring + 1] = { x, plan.wz1 } end
  for z = plan.wz1 - 1, plan.wz0 + 1, -1 do ring[#ring + 1] = { plan.wx0, z } end
  for y = F, F + ROOM_HEIGHT do
    for _, c in ipairs(ring) do add("walls", { at = P(c[1], y + 1, c[2]), solid = { "down" } }) end
  end

  -- A pair of water sources at the outer end of each channel.
  for _, s in ipairs({ { 0, Z1 }, { 1, Z1 }, { X1, 3 }, { X1, 2 }, { 1, Z0 }, { 0, Z0 }, { X0, 2 }, { X0, 3 } }) do
    add("water", { at = P(s[1], F + 1, s[2]), place = "water", dir = "down" })
  end

  snake(plan.wx0, plan.wx1, plan.wz0, plan.wz1, function(x, z)
    add("roof", { at = P(x, plan.C, z), solid = { "down" } })
  end)
end

-- What the ops from step `first` on still need.
local function needsFrom(first)
  local left = { block = 0 }
  for kind in pairs(SPECIAL) do left[kind] = 0 end
  for i = first, #plan.ops do
    local op = plan.ops[i]
    if op.solid then left.block = left.block + #op.solid end
    if op.place then left[op.place] = left[op.place] + 1 end
  end
  return left
end

local function currentPhase()
  local op = plan.ops[job.step]
  return op and op.phase
end

---------------------------------------------------------------- inventory and fuel

local function save() nav.writeFile(JOB_FILE, job) end

local function shortName(n) return (n:gsub("^minecraft:", "")) end

local fuelLevel = inv.fuelLevel

local emptySlots = inv.emptySlots

local count = inv.count

local selectItem = inv.select

local function isBlock(n) return n == job.block end
local function isFuel(n) return FUEL[n] == true end

local function refuelFromInventory(target) inv.refuel(target, FUEL) end

-- Wait until ok() is true, re-checking when the inventory changes and every
-- 10 seconds (chests don't send events).
local function waitUntil(ok, lines, state)
  if ok() then return end
  for _, l in ipairs(lines) do print(l) end
  report.set("waiting", state)
  local timer = os.startTimer(10)
  while true do
    local e, a = os.pullEvent()
    if e == "timer" and a == timer then
      if ok() then return end
      timer = os.startTimer(10)
    elseif e == "turtle_inventory" then
      if ok() then return end
    end
  end
end

---------------------------------------------------------------- the supply chest

local function frontChest()
  local c = peripheral.wrap("front")
  if c and c.list then return c end
end

local function freeSlotFor(name)
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and it.name == name and turtle.getItemSpace(slot) > 0 then return slot end
  end
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return slot end
  end
end

-- Without inventory peripherals: suck stacks one by one, keep the wanted
-- ones and put the rest back.
local function suckSorting(match, want)
  local held = {}
  local got = 0
  while got < want and emptySlots() > 1 do
    local slot = freeSlotFor("")
    turtle.select(slot)
    if not turtle.suck() then break end
    local it = turtle.getItemDetail(slot)
    if it and match(it.name) then got = got + it.count else held[#held + 1] = slot end
  end
  for _, s in ipairs(held) do
    turtle.select(s)
    turtle.drop()
  end
  turtle.select(1)
end

-- With a buffer chest under the start block: the chest in front pushes exactly
-- what's wanted into it, from whatever slot it's in, and I take it from
-- there, so nothing in that chest is moved about and its order doesn't
-- matter (a barrel with stack upgrades). False when there's no buffer chest.
-- spare: slots to leave empty.
local function takeViaBuffer(match, want, current, spare)
  local chest, buffer = peripheral.wrap("front"), peripheral.wrap("bottom")
  if not (chest and chest.list and buffer and buffer.list and buffer.pushItems) then return false end
  spare = spare or 0
  -- anything left in it from last time goes back first
  for slot in pairs(buffer.list()) do pcall(buffer.pushItems, "front", slot) end
  for slot, it in pairs(chest.list()) do
    if match(it.name) then
      local left = it.count
      while left > 0 and current() < want and emptySlots() > spare do
        local ok, n = pcall(chest.pushItems, "bottom", slot, math.min(64, left, want - current()))
        if not ok or not n or n == 0 then break end
        left = left - n
        turtle.select(freeSlotFor(it.name) or 1)
        turtle.suckDown()
      end
    end
    if current() >= want or emptySlots() <= spare then break end
  end
  -- what didn't fit in me goes back
  for slot in pairs(buffer.list()) do pcall(buffer.pushItems, "front", slot) end
  turtle.select(1)
  return true
end

-- Move all count items in a chest slot to another slot. A barrel with
-- stack upgrades holds thousands in one slot, and each call moves a stack.
local function moveAll(c, self, from, count, to)
  local moved = 0
  for _ = 1, math.ceil(count / 64) + 1 do
    local ok, n = pcall(c.pushItems, self, from, count - moved, to)
    if not ok or not n or n == 0 then break end
    moved = moved + n
    if moved >= count then break end
  end
  return moved
end

local warnedReach = false -- said once that blocks in the supply chest are out of reach

-- Facing the chest: take items matching match() until carrying `want` of
-- them, always leaving a slot free for whatever gets dug up. turtle.suck
-- takes the chest's first stack, so without a buffer chest the wanted stack
-- is moved to the front of the chest first.
local function fetch(match, want)
  if takeViaBuffer(match, want, function() return count(match) end, 1) then return end
  local c = frontChest()
  if not c then return suckSorting(match, want - count(match)) end
  local self = peripheral.getName(c)
  for _ = 1, 40 do
    local have = count(match)
    if have >= want or emptySlots() <= 1 then break end
    local items = c.list()
    local from, first
    for slot, it in pairs(items) do
      if not first or slot < first then first = slot end
      if match(it.name) and (not from or slot < from) then from = slot end
    end
    if not from then break end
    local held -- my slot holding the chest's first stack for a moment (a full chest)
    if from ~= first then
      local moved = true
      if items[1] then
        -- clear slot 1 into a slot with the same item, else an empty one.
        -- Only what's needed is moved into it (below), so after the first
        -- time it holds a few leftovers, not a barrel's thousands
        local left, empty = items[1].count, false
        for s = 2, c.size() do
          if left <= 0 then break end
          if s ~= from and items[s] and items[s].name == items[1].name then left = left - moveAll(c, self, 1, left, s) end
        end
        for s = 2, c.size() do
          if left <= 0 then break end
          if not items[s] then
            empty = true
            left = left - moveAll(c, self, 1, left, s)
          end
        end
        if left <= 0 then
          moved = true
        elseif not empty and emptySlots() >= 2 and left <= 64 then
          -- no room in the chest: hold its first stack myself, and put it
          -- back once the wanted stack has left a gap
          held = freeSlotFor("")
          turtle.select(held)
          moved = turtle.suck()
          if not moved then held = nil end
        else
          moved = false
        end
      end
      if moved then
        -- some barrels (Sophisticated Storage) put what's pushed into them
        -- wherever they like, not in the slot asked for: check it's in slot 1
        moveAll(c, self, from, math.min(items[from].count, want - have), 1)
        local now = c.list()[1]
        moved = now ~= nil and match(now.name)
      end
      if not moved then
        if held then
          turtle.select(held)
          turtle.drop()
        end
        -- a barrel with stack upgrades puts back whatever is dropped into it
        -- in the same slot, so taking stacks off the front never gets past it
        local big = false
        for _, it in pairs(items) do
          if it.count > 64 then big = true end
        end
        if not big then suckSorting(match, want - have) end
        if count(match) == have and not warnedReach then
          print("Couldn't get to the blocks I need in my supply chest. Put an empty chest under me (a buffer chest): the supply chest hands me what I need through it.")
          warnedReach = true
        end
        turtle.select(1)
        return
      end
    end
    turtle.select(freeSlotFor(items[from].name) or 1)
    local took = turtle.suck(math.min(64, want - have))
    if held then
      turtle.select(held)
      turtle.drop()
    end
    if not took then break end
  end
  turtle.select(1)
end

local function refuel(target)
  local limit = turtle.getFuelLimit()
  if limit ~= "unlimited" then target = math.min(target, limit) end
  refuelFromInventory(target)
  if fuelLevel() < target then
    fetch(isFuel, 64)
    refuelFromInventory(target)
  end
end

-- At the chest: put away everything not needed for the rest of the job.
-- Junk goes on the ground to the left of the start. Building blocks go back
-- while the water goes in, to make room for the buckets.
local function dump()
  local phase = currentPhase()
  local left = needsFrom(job.step)
  local warned = false
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it then
      local keep = FUEL[it.name] or (it.name == job.block and phase ~= nil and phase ~= "water")
      for _, kind in ipairs(SPECIAL_ORDER) do
        if SPECIAL[kind].item(it.name) and left[kind] > 0 and (kind ~= "water" or phase == "water") then
          keep = true
        end
      end
      if not keep then
        turtle.select(slot)
        if JUNK[it.name] and it.name ~= job.block then
          faceLocal(3)
          turtle.drop()
        else
          faceChest()
          if not turtle.drop() then
            if not warned then
              print("Supply chest is full; leaving the extra on the ground.")
              warned = true
            end
            faceLocal(3)
            turtle.drop()
          end
        end
      end
    end
  end
  turtle.select(1)
  faceChest()
end

---------------------------------------------------------------- moving

local function walk(points)
  for _, w in ipairs(points) do
    local ok, err = goL(w)
    if not ok then return false, err end
  end
  return true
end

local function inShaft(p) return p.x >= 0 and p.x <= 1 and p.z >= 2 and p.z <= 3 and p.y >= 0 and p.y < plan.F end

-- On or above the platform, inside the walls' footprint.
local function inRoom(p)
  return p.y >= plan.F and p.x >= plan.wx0 and p.x <= plan.wx1 and p.z >= plan.wz0 and p.z <= plan.wz1
end

-- The start, or the walk along the ground from it to the bottom of the lift.
local function onGround(p)
  local L = plan.lift
  return p.y == 0 and ((p.x == 0 and p.z == 0) or (p.x == L.x and p.z <= 0 and p.z >= L.z))
end

-- Back along the base path the turtle is on, to the start.
local function retrace()
  local path = plan.ops[job.onPath].path
  local p = here()
  local from, best = 0, dist(p, HOME)
  for i, w in ipairs(path) do
    if dist(p, w) < best then from, best = i, dist(p, w) end
  end
  for i = from, 1, -1 do
    local ok, err = goL(path[i])
    if not ok then return false, err end
  end
  local ok, err = goL(HOME)
  if not ok then return false, err end
  job.onPath = nil
  save()
  return true
end

-- Straight moves inside the shaft and the room, and between them through
-- the hole. Anywhere else: straight up to roof height, across, and straight
-- down, using the lift column outside the room to get to and from the
-- start. The farm is built bottom-up, so those columns are always clear.
local function travel(t)
  if job.onPath then
    local ok, err = retrace()
    if not ok then return false, err end
  end
  local p = here()
  if dist(p, t) == 0 then return true end
  local function inside(q) return inShaft(q) or inRoom(q) end
  -- (from the channel level, going down the shaft would cross the floor)
  if inside(p) and inside(t) and not (inRoom(p) and p.y == plan.F and inShaft(t)) then return goL(t) end

  local L, C = plan.lift, plan.C
  local route
  if onGround(p) and onGround(t) then
    route = { P(L.x, 0, p.z), P(L.x, 0, t.z) }
  elseif onGround(p) then
    route = { P(L.x, 0, p.z), P(L.x, 0, L.z), P(L.x, C, L.z), P(t.x, C, t.z) }
  elseif onGround(t) then
    route = { P(p.x, math.max(p.y, C), p.z), P(L.x, C, L.z), P(L.x, 0, L.z), P(L.x, 0, t.z) }
  else
    route = { P(p.x, math.max(p.y, C), p.z), P(t.x, C, t.z) }
  end
  route[#route + 1] = t
  return walk(route)
end

-- Base ops: back to the start, then out along the op's own path.
local function goToOp(op)
  if not op.path then return travel(op.at) end
  if job.onPath ~= op.index then
    local ok, err
    if job.onPath then ok, err = retrace() else ok, err = travel(HOME) end
    if not ok then return false, err end
    job.onPath = op.index
    save()
  end
  return walk(op.path)
end

-- Keep trying to get to t, waiting for fuel or for the way to clear. Gives
-- up (returns false) only when right next to t and t itself can't be
-- cleared (bedrock or a protected block).
local function persist(attempt, t)
  local tries = 0
  while true do
    local ok, err = attempt()
    if ok then return true end
    if err ~= "nofuel" and dist(here(), t) <= 1 then return false, err end
    tries = tries + 1
    if err == "nofuel" then
      print("Out of fuel here. Put fuel in my inventory.")
      report.set("waiting", "out of fuel")
      while fuelLevel() == 0 do
        refuelFromInventory(1000)
        if fuelLevel() == 0 then os.pullEvent("turtle_inventory") end
      end
    else
      local w = nav.getPos()
      local tx, ty, tz = toWorld(t)
      local msg = ("Stuck at %d,%d,%d (%s) on the way to %d,%d,%d"):format(w.x, w.y, w.z, tostring(err), tx, ty, tz)
      print(msg .. ". Clear the way; retrying.")
      report.set("stuck", msg)
      sleep(math.min(60, 5 * tries))
    end
  end
end

local function reachOp(op) return persist(function() return goToOp(op) end, op.at) end
local function goHome() return persist(function() return travel(HOME) end, HOME) end

local function homeDistance()
  local p = here()
  if job.onPath or onGround(p) then return 60 end
  local L, C = plan.lift, plan.C
  return math.abs(C - p.y) + math.abs(p.x - L.x) + math.abs(p.z - L.z) + C + 10 + 50
end

---------------------------------------------------------------- position checks

local gpsPos = nav.locate

local function onSegment(p, a, b)
  return p.x >= math.min(a.x, b.x) and p.x <= math.max(a.x, b.x) and p.y >= math.min(a.y, b.y)
    and p.y <= math.max(a.y, b.y) and p.z >= math.min(a.z, b.z) and p.z <= math.max(a.z, b.z)
end

-- Somewhere the turtle's routes go, so it can travel on from here without
-- digging through the farm.
local function onRoute(p)
  if inShaft(p) or inRoom(p) or onGround(p) or p.y >= plan.C then return true end
  if p.x == plan.lift.x and p.z == plan.lift.z and p.y >= 0 then return true end
  for _, op in ipairs(plan.ops) do
    if op.path then
      local prev = HOME
      for _, w in ipairs(op.path) do
        if onSegment(p, prev, w) then return true end
        prev = w
      end
    end
  end
  return false
end

local function offRouteError()
  local w = nav.getPos()
  error(("I'm off my route at %d,%d,%d. Put me back on my start block, facing the way I faced when the job began, then run: mobfarm here")
    :format(w.x, w.y, w.z), 0)
end

-- With GPS, compare where the turtle thinks it is with where it really is.
-- If it's been moved, re-check position and facing; a turtle put down off
-- its routes stops rather than dig its way back through the farm.
local function checkPosition()
  if not job.gps then return end
  local g = gpsPos()
  if not g then return end -- out of GPS range just now
  local p = nav.getPos()
  if g.x ~= p.x or g.y ~= p.y or g.z ~= p.z then
    print(("Position was off: thought %d,%d,%d, GPS says %d,%d,%d. Correcting."):format(p.x, p.y, p.z, g.x, g.y, g.z))
    nav.init()
    if not onRoute(here()) then offRouteError() end
  end
end

---------------------------------------------------------------- building

-- Go back to the chest for what ran out (kind: "block" or a SPECIAL kind;
-- nil to just empty out and refuel), and wait there if there's none.
local stockUp

local function restock(kind)
  print(kind and "Going back to the chest for more." or "Going back to the chest.")
  report.set("returning", "restocking")
  goHome()
  stockUp(kind)
end

-- At the start: put away what isn't needed, top up fuel, and load up for the
-- work ahead (specials first, so building blocks don't crowd them out).
stockUp = function(kind)
  faceChest()
  dump()
  refuel(REFUEL_TO)
  local minimum = 2 * (plan.C + 40) + 100 -- out to the far corner of the roof and back
  if fuelLevel() < minimum then
    waitUntil(function()
      refuel(REFUEL_TO)
      return fuelLevel() >= minimum
    end, { ("Need at least %d fuel, have %d. Put coal in the chest behind me or in me."):format(minimum, fuelLevel()) },
    "needs fuel")
  end

  local phase = currentPhase()
  local left = needsFrom(job.step)
  for _, k in ipairs(SPECIAL_ORDER) do
    if left[k] > 0 and (k ~= "water" or phase == "water") then fetch(SPECIAL[k].item, left[k]) end
  end
  local blocks = math.min(left.block, LOAD_SLOTS * 64)
  if phase ~= "water" and blocks > 0 then fetch(isBlock, blocks) end

  if not kind then return end
  local match = kind == "block" and isBlock or SPECIAL[kind].item
  local label = kind == "block" and shortName(job.block) or SPECIAL[kind].label
  local want = kind == "block" and blocks or left[kind]
  waitUntil(function()
    fetch(match, want)
    return count(match) > 0
  end, { ("Out of %s. Put more in the chest behind me (%d more needed)."):format(label, kind == "block" and left.block or want) },
  "needs " .. label)
end

local ACT = {
  forward = { detect = turtle.detect, place = turtle.place, dig = turtle.dig, inspect = turtle.inspect, attack = turtle.attack },
  up = { detect = turtle.detectUp, place = turtle.placeUp, dig = turtle.digUp, inspect = turtle.inspectUp, attack = turtle.attackUp },
  down = { detect = turtle.detectDown, place = turtle.placeDown, dig = turtle.digDown, inspect = turtle.inspectDown, attack = turtle.attackDown },
}

-- Face side d ("up", "down" or a local heading) and return its actions.
local function side(d)
  if d == "up" or d == "down" then return ACT[d] end
  faceLocal(d)
  return ACT.forward
end

-- Place repeatedly in case a mob is standing in the way.
local function placeWithRetries(a, match)
  for _ = 1, 5 do
    if not selectItem(match) then return false end
    if a.place() then return true end
    a.attack()
    sleep(0.5)
  end
  local w = nav.getPos()
  print(("Couldn't place a block next to %d,%d,%d; skipping it."):format(w.x, w.y, w.z))
  return true
end

-- Make sure side d is solid, filling it with a building block if not.
-- Ground that's already there counts. Returns false when out of blocks.
local function makeSolid(d)
  local a = side(d)
  if a.detect() then return true end
  if not selectItem(isBlock) then return false end
  if not a.place() then
    a.dig() -- a flower or snow layer can be in the way
    return placeWithRetries(a, isBlock)
  end
  return true
end

-- Place a special item on side op.dir, clearing the spot first (it's ground
-- where the chests and hoppers go). Returns false when out of them.
local function placeSpecial(op)
  local s = SPECIAL[op.place]
  local a = side(op.dir)
  local ok, data = a.inspect()
  if ok and s.placed(data) then return true end
  if not selectItem(s.item) then return false end
  if ok and data.name ~= "minecraft:water" then a.dig() end
  if not placeWithRetries(a, s.item) then return false end
  if op.place == "hopper" then
    -- a hopper should point the way the turtle faces, into the block beyond
    local want = WORLD_FACING[(job.origin.heading + op.dir) % 4]
    local placed, got = a.inspect()
    if placed and got.state and got.state.facing and got.state.facing ~= want then
      print(("A hopper came out pointing %s instead of %s. Break it and place it again"):format(got.state.facing, want))
      print("by hand, clicking on the block it should feed.")
    end
  end
  return true
end

local function doOp(op)
  if not reachOp(op) then return end -- the spot itself can't be cleared: skip it
  if op.dig then nav.digDown() end
  for _, d in ipairs(op.solid or {}) do
    if not makeSolid(d) then
      restock("block")
      return doOp(op)
    end
  end
  if op.place and not placeSpecial(op) then
    restock(op.place)
    return doOp(op)
  end
end

local function housekeeping()
  if emptySlots() == 0 then restock() end
  local needed = homeDistance()
  if fuelLevel() < needed then
    refuelFromInventory(needed + 1000)
    if fuelLevel() < needed then restock() end
  end
end

---------------------------------------------------------------- main

local function progressText()
  local phase = currentPhase()
  return ("%s, %d%% overall"):format(phase and PHASE_NAMES[phase] or "done",
    math.floor((job.step - 1) / #plan.ops * 100))
end

local function printNeeds(left)
  print("Put these in the chest behind me (or in my inventory):")
  if left.block > 0 then
    print(("  %d %s (fewer if there's ground in the way)"):format(left.block, shortName(job.block)))
  end
  for _, k in ipairs(SPECIAL_ORDER) do
    if left[k] > 0 then print(("  %d %s"):format(left[k], SPECIAL[k].label)) end
  end
end

local function run()
  if not onRoute(here()) then offRouteError() end
  while job.step <= #plan.ops do
    doOp(plan.ops[job.step])
    job.step = job.step + 1
    save()
    if job.step % 20 == 0 then checkPosition() end
    if job.step <= #plan.ops then housekeeping() end
    if job.step % 25 == 0 then print(progressText()) end
    -- only GPS jobs have real world coordinates; otherwise report.lua tries GPS itself
    report.set("building", progressText(), job.gps and { pos = nav.getPos() } or nil)
  end

  goHome()
  dump() -- leftovers and empty buckets go back in the chest
  nav.face(job.origin.heading)
  nav.deleteFile(JOB_FILE)
  print("Mob farm finished! Pick me up, then stand in the pit")
  print("in front of the chests to collect. Mobs only spawn")
  print("while you're within 128 blocks, and not within 24.")
  report.set("done", "mob farm finished")
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Job cancelled.")
  return
end

job = nav.readFile(JOB_FILE)

if args[1] == "list" then
  if not job then
    local slot1 = turtle.getItemDetail(1)
    job = { drop = tonumber(args[2]) or DEFAULT_DROP, step = 1, block = slot1 and slot1.name or DEFAULT_BLOCK }
  end
  buildPlan()
  printNeeds(needsFrom(job.step))
  print("plus fuel. Water buckets come back empty.")
  return
end

if not os.getComputerLabel() then os.setComputerLabel("MobFarm-" .. os.getComputerID()) end

-- With GPS, the turtle works in real world coordinates and re-checks its
-- position and facing every time it starts. A job started without GPS keeps
-- using the saved position, since its coordinates are relative to the start.
local hasGps = gpsPos() ~= nil
local useGps = hasGps and (not job or job.gps)
local knowsPosition = nav.init(useGps)

-- No GPS to check against: give the player a chance to say the turtle was moved.
local function confirmResume()
  return nav.confirmResume("Put me back on my start block, facing the way I faced when\nthe job began, then run: mobfarm here")
end

if args[1] == "resume" or args[1] == "here" then
  if not job then
    print("No job to resume.")
    return
  end
  buildPlan()
  if args[1] == "here" then
    -- the player has put the turtle back on its start block
    local x, y, z = toWorld(HOME)
    nav.setPosition(x, y, z, job.origin.heading)
    job.onPath = nil
    save()
    print("Position reset to the start block.")
  elseif useGps then
    print("Checked my position with GPS.")
  else
    if job.gps then print("Can't reach GPS right now.") end
    if not knowsPosition then error("Lost track of position; can't resume. Run 'mobfarm here' from the start block.", 0) end
    if not confirmResume() then return end
  end
  print("Resuming: " .. progressText())
elseif job then
  print("A job is already in progress. Run 'mobfarm resume' or 'mobfarm cancel'.")
  return
else
  local drop = DEFAULT_DROP
  if args[1] then
    drop = tonumber(args[1])
    if not drop then
      print("Usage: mobfarm [drop height] | list | resume | here | cancel")
      return
    end
  end
  if drop < MIN_DROP then
    print(("The drop must be at least %d blocks."):format(MIN_DROP))
    return
  end
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  local p, heading = nav.getPos(), nav.getHeading()

  -- build with whatever is in slot 1, as long as it's an ordinary block
  local slot1 = turtle.getItemDetail(1)
  local block = slot1 and slot1.name or DEFAULT_BLOCK
  for _, s in pairs(SPECIAL) do
    if s.item(block) then block = DEFAULT_BLOCK end
  end
  if FUEL[block] then block = DEFAULT_BLOCK end

  job = { drop = drop, block = block, step = 1, gps = hasGps,
    origin = { x = p.x, y = p.y, z = p.z, heading = heading } }
  print(hasGps and "GPS found: I'll check my position as I go."
    or "No GPS: working from my own position count only.")
  buildPlan()

  local need = needsFrom(1)
  local moves, at = 0, HOME
  for _, op in ipairs(plan.ops) do
    moves = moves + dist(at, op.at)
    at = op.at
  end
  local trips = math.ceil(need.block / (LOAD_SLOTS * 64)) + 3
  local fuel = math.floor(moves * 1.2 + trips * 2 * (plan.C + 30))

  print(("Mob farm with a %d block drop: 18x18 spawning room %d blocks up,"):format(drop, drop))
  print(drop >= 29 and "high enough to kill everything that falls."
    or "so mobs land hurt and you finish them off.")
  print(("Building with %s (from slot 1)."):format(shortName(block)))
  printNeeds(need)
  print(("Needs about %d fuel (have %s); I refuel from the chest."):format(fuel, tostring(turtle.getFuelLevel())))
  print("Chest goes directly behind me. Press Enter to start.")
  read()
  save()
  stockUp()
end

report.init("mob farm builder")
errlog.init("mobfarm", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
