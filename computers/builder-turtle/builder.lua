-- Builder turtle: builds the building a blueprint projector is showing, right
-- where it's projected. Tap Build on the projector's panel (or run
-- 'projector build') and the plan comes over rednet: every block, in world
-- coordinates. The turtle clears the building's box, then builds it layer by
-- layer from the bottom, placing each block from above. Blocks come from the
-- supply chest behind its home block (and from a storage system, if there is
-- one); what it digs up goes in the spoil chest to its left. It tells the
-- projector how far it's got, so the projection's Layer view follows it.
-- With several builder turtles about, the projector splits the building into
-- side-by-side strips and each turtle builds one: it clears and builds only
-- its strip, and crosses over at a height of its own so they don't meet.
--
--   builder            wait for a building from a projector (startup.lua runs this)
--   builder setup      make this block home (asks where I am if there's no GPS)
--   builder here       you put me back on my home block (no GPS): carry on from there
--   builder status     what I'm building and how far along I am
--   builder cancel     forget the building I'm working on
--
-- Needs a wireless or ender modem, and its real world position: from GPS, or
-- typed in once with 'builder setup' (press F3 to read it).
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log
local net = require("lib.net") -- rednet requests and answers
local claim = require("lib.claim") -- tells the storage computer my supply chest is my delivery chest

local JOB_FILE = "/.builder_job" -- the building: blocks and materials (written once per building)
local PROGRESS_FILE = "/.builder_progress" -- how far along it is (rewritten after every block, so kept small)
local HOME_FILE = "/.builder_home" -- home block and facing, and whether GPS checks it
local BUILD_PROTOCOL = "projector_build" -- the projector sends buildings, and hears progress, on this
local STORAGE_PROTOCOL = "storage" -- a storage computer's protocol, for ordering blocks

local CLEAR_FIRST = true -- dig out everything in the building's box before building
local LOAD_SLOTS = 13 -- stacks of building blocks taken per trip; the rest stay free for what's dug up
local REFUEL_TO = 2000 -- fuel level to fill up to at home
local FUEL_MARGIN = 100 -- spare fuel kept on top of what the trip home needs
local MAX_DISTANCE = 256 -- furthest a building may be from home, in blocks
local WORLD_TOP = 319 -- highest Y a turtle can be at (the build limit since 1.18)
local PLACE_TRIES = 3 -- tries at placing a block (a mob in the way) before skipping it
local REPORT_EVERY = 10 -- blocks between progress messages to the projector
local CHECK_EVERY = 50 -- blocks between GPS position checks
local USE_STORAGE = true -- order blocks from a storage computer, delivered to my supply chest (it needs a wired modem on the storage cable)
local STORAGE_WAIT = 10 -- seconds to wait for the storage computer to answer
local CLAIM_RETRY = 300 -- seconds before trying again to hook my supply chest up to the storage system, if it didn't work
-- Fuel asked for when low, in this order, and how much of it.
local STORAGE_FUEL = { { "minecraft:coal", 64 }, { "minecraft:charcoal", 64 }, { "minecraft:coal_block", 8 } }

-- Blocks that are placed with a different item.
local ITEM_FOR = {
  ["minecraft:wall_torch"] = "minecraft:torch", ["minecraft:soul_wall_torch"] = "minecraft:soul_torch",
  ["minecraft:redstone_wire"] = "minecraft:redstone", ["minecraft:water"] = "minecraft:water_bucket",
  ["minecraft:lava"] = "minecraft:lava_bucket", ["minecraft:tripwire"] = "minecraft:string",
}
local STACK = { ["minecraft:water_bucket"] = 1, ["minecraft:lava_bucket"] = 1 } -- items that stack below 64

local FUEL = {}
for _, n in ipairs({ "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block", "minecraft:blaze_rod" }) do FUEL[n] = true end

local args = { ... }
-- { key, name, from, mats, blocks = { { x, y, z, m } } } in world coordinates;
-- for one strip of a building shared by several turtles also area (the whole
-- building's box), part (this strip's x0, x1, z0, z1) and lane (0, 1, ...:
-- how many blocks higher than the others I cross over); clear = false for a
-- building in the air (nothing to dig out of its box first)
local job
local prog -- { stage = "clear" | "build", step }
local home -- { x, y, z, heading, gps }
local order, box -- derived from job: build order (block indexes), and the box it fills
local stopRequested = false

---------------------------------------------------------------- helpers

-- Plan blocks may carry a state, "minecraft:oak_stairs[facing=east]": the
-- block itself is the name without it.
local function baseName(block) return (block:gsub("%[.*$", "")) end
local function shortName(name) return (baseName(name):gsub("^minecraft:", ""):gsub("_", " ")) end
local function itemFor(block)
  local base = baseName(block)
  return ITEM_FOR[base] or base
end
-- The heading a block's facing state asks for (stairs climb towards it), or nil.
local function facingOf(block) return nav.HEADINGS[block:match("[%[,]facing=(%a+)") or ""] end
local function save() nav.writeFile(PROGRESS_FILE, prog) end

local fuelLevel = inv.fuelLevel

local emptySlots = inv.emptySlots

local count = inv.count

local selectName = inv.select

local function fuelItems() return inv.count(FUEL) end

local function refuelFromInventory(target) inv.refuel(target, FUEL) end

local gpsPos = nav.locate

local function status(state, detail)
  report.set(state, detail)
end

---------------------------------------------------------------- the building

-- The building's box, and the order to place its blocks: bottom layer
-- first, each layer in rows back and forth, doors last in their layer (a
-- door's top half sticks up into the next layer, where the turtle travels).
local function buildPlan()
  local doors = {}
  for m, name in ipairs(job.mats) do doors[m] = name:find("_door", 1, true) ~= nil end
  box = { x0 = math.huge, y0 = math.huge, z0 = math.huge, x1 = -math.huge, y1 = -math.huge, z1 = -math.huge }
  order = {}
  for i, b in ipairs(job.blocks) do
    order[i] = i
    box.x0, box.y0, box.z0 = math.min(box.x0, b[1]), math.min(box.y0, b[2]), math.min(box.z0, b[3])
    box.x1, box.y1, box.z1 = math.max(box.x1, b[1]), math.max(box.y1, b[2]), math.max(box.z1, b[3])
  end
  -- one strip of a shared building: clear the whole strip, all the way up
  if type(job.part) == "table" then
    box.x0, box.x1, box.z0, box.z1 = job.part.x0, job.part.x1, job.part.z0, job.part.z1
  end
  if type(job.area) == "table" then box.y0, box.y1 = job.area.y0, job.area.y1 end
  table.sort(order, function(a, c)
    local A, C = job.blocks[a], job.blocks[c]
    if A[2] ~= C[2] then return A[2] < C[2] end
    if doors[A[4]] ~= doors[C[4]] then return doors[C[4]] end
    if A[3] ~= C[3] then return A[3] < C[3] end
    if A[3] % 2 == 0 then return A[1] < C[1] end
    return A[1] > C[1]
  end)
end

-- The box is cleared in passes 3 blocks apart from the top down, digging
-- the block above and below at each spot (like the village builder).
local function clearCells()
  if box.y1 < box.y0 then return 0 end
  return math.ceil((box.y1 - box.y0 + 1) / 3) * (box.x1 - box.x0 + 1) * (box.z1 - box.z0 + 1)
end

local function clearCell(i)
  local w, l = box.x1 - box.x0 + 1, box.z1 - box.z0 + 1
  local per = w * l
  local layer, j = math.floor(i / per), i % per
  if layer % 2 == 1 then j = per - 1 - j end
  local row, col = math.floor(j / w), j % w
  if row % 2 == 1 then col = w - 1 - col end
  local y = math.min(math.max(box.y1 - 1 - layer * 3, box.y0 + 1), box.y1)
  if box.y1 == box.y0 then y = box.y0 end
  return { x = box.x0 + col, y = y, z = box.z0 + row }
end

local function total() return #job.blocks end

---------------------------------------------------------------- talking to the projector

local function openModem() return net.open() end

-- Tell the projector that sent the building how far along it is.
local function sendProgress(stage, note)
  if not job or not openModem() then return end
  local b = prog and prog.stage == "build" and order[prog.step] and job.blocks[order[prog.step]]
  rednet.send(job.from, {
    type = "progress", key = job.key, name = job.name, stage = stage,
    done = prog and prog.stage == "build" and prog.step - 1 or 0, total = total(),
    cleared = prog and prog.stage == "clear" and prog.step or nil, toClear = box and clearCells() or nil,
    y = b and b[2] or nil, skipped = prog and prog.skipped or 0, note = note,
  }, BUILD_PROTOCOL)
end

---------------------------------------------------------------- moving

-- Above the whole building (not just my strip of it, which may be lower than
-- the next), and with several turtles each at its own height.
local function cruiseHeight()
  local top = type(job.area) == "table" and job.area.y1 or box.y1
  -- never above the build limit: nothing can move up from there
  return math.min(WORLD_TOP, math.max(top + 2, home.y + 2) + (tonumber(job.lane) or 0))
end

-- A cell another turtle's strip of the building may fill: never stand there.
local function othersCell(x, z)
  local a = job.area
  if type(a) ~= "table" or type(job.part) ~= "table" then return false end
  local inArea = x >= a.x0 and x <= a.x1 and z >= a.z0 and z <= a.z1
  local mine = x >= box.x0 and x <= box.x1 and z >= box.z0 and z <= box.z1
  return inArea and not mine
end

local function inBox(p)
  return p.x >= box.x0 and p.x <= box.x1 and p.z >= box.z0 and p.z <= box.z1 and p.y >= box.y0 and p.y <= box.y1 + 1
end

-- Inside the building, move straight there: the turtle stays a block above
-- the layer it's working on, where nothing is built yet. Anywhere else, go
-- up above the building, across, and down, so nothing built gets dug.
local function travel(p)
  local cur = nav.getPos()
  -- already there (going home from home): don't fly up over the building and
  -- back, which a new turtle hasn't the fuel for
  if cur.x == p.x and cur.y == p.y and cur.z == p.z then return true end
  if inBox(cur) and inBox(p) then return nav.goTo(p.x, p.y, p.z) end
  local cruise = math.max(cur.y, p.y, cruiseHeight())
  local ok, err = nav.goTo(cur.x, cruise, cur.z)
  if not ok then return false, err end
  ok, err = nav.goTo(p.x, cruise, p.z)
  if not ok then return false, err end
  return nav.goTo(p.x, p.y, p.z)
end

local waitForFuelHere -- below

-- Get to p, waiting for the way to clear if need be. Gives up (false) when
-- right next to p and p itself can't be cleared (a chest, bedrock).
local function reach(p)
  local tries = 0
  while true do
    local ok, err = travel(p)
    if ok then return true end
    if err == "nofuel" then
      waitForFuelHere()
    else
      local h = nav.getPos()
      if math.abs(h.x - p.x) + math.abs(h.y - p.y) + math.abs(h.z - p.z) <= 1 then return false, err end
      tries = tries + 1
      local msg = ("Stuck at %d,%d,%d (%s)"):format(h.x, h.y, h.z, tostring(err))
      print(msg .. ". Clear the way; retrying.")
      status("stuck", msg)
      sleep(math.min(60, 5 * tries))
      if tries > 3 then return false, err end
    end
  end
end

local function goHome()
  reach(home)
  nav.face(home.heading)
end

local function homeDistance()
  local p = nav.getPos()
  local cruise = cruiseHeight()
  return math.abs(p.x - home.x) + math.abs(p.z - home.z) + math.abs(cruise - p.y) + math.abs(cruise - home.y) + FUEL_MARGIN
end

-- With GPS, check the counted position against it, and start again from
-- home if the turtle has been moved.
local function checkPosition()
  if not home.gps then return end
  local g = gpsPos()
  if not g then return end
  local p = nav.getPos()
  if g.x ~= p.x or g.y ~= p.y or g.z ~= p.z then
    print(("Position was off: thought %d,%d,%d, GPS says %d,%d,%d. Correcting."):format(p.x, p.y, p.z, g.x, g.y, g.z))
    nav.init(true)
    goHome()
  end
end

---------------------------------------------------------------- the chests at home

local function faceSupply() nav.face((home.heading + 2) % 4) end -- behind home
local function faceSpoil() nav.face((home.heading + 3) % 4) end -- left of home

local function freeSlotFor(name)
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and it.name == name and turtle.getItemSpace(slot) > 0 then return slot end
  end
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return slot end
  end
end

-- Without the chest as a peripheral: suck stacks one by one, keep the
-- wanted ones and put the rest back.
local function suckSorting(match, want)
  local held, got = {}, 0
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

-- With a buffer chest under my home block: the supply chest (in front)
-- pushes exactly what's wanted into it, from whatever slot it's in, and I
-- take it from there. Nothing in the supply chest is moved about, so its
-- order doesn't matter. False when there's no buffer chest.
local function takeViaBuffer(match, want, current)
  local supply, buffer = peripheral.wrap("front"), peripheral.wrap("bottom")
  if not (supply and supply.list and buffer and buffer.list and buffer.pushItems) then return false end
  -- anything left in it from last time goes back first
  for slot in pairs(buffer.list()) do pcall(buffer.pushItems, "front", slot) end
  for slot, it in pairs(supply.list()) do
    if match(it.name) then
      local left = it.count
      while left > 0 and current() < want and emptySlots() > 0 do
        local ok, n = pcall(supply.pushItems, "bottom", slot, math.min(64, left, want - current()))
        if not ok or not n or n == 0 then break end
        left = left - n
        turtle.select(freeSlotFor(it.name) or 1)
        turtle.suckDown()
      end
    end
    if current() >= want or emptySlots() == 0 then break end
  end
  -- what didn't fit in me goes back
  for slot in pairs(buffer.list()) do pcall(buffer.pushItems, "front", slot) end
  turtle.select(1)
  return true
end

local warnedReach = false -- said once that blocks in the supply chest are out of reach

-- Take up to want items matching match() from the chest in front.
-- turtle.suck takes the chest's first stack, so without a buffer chest the
-- wanted stack is moved to the front of the chest first (as the village
-- builder does).
local function takeFront(match, want, current)
  if takeViaBuffer(match, want, current) then return end
  local c = peripheral.wrap("front")
  if not (c and c.list) then return end
  local self = peripheral.getName(c)
  for _ = 1, 40 do
    local have = current()
    if have >= want or emptySlots() == 0 then break end
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
        if current() == have and not warnedReach then
          print("Couldn't get to the blocks I need in my supply chest. Put an empty chest under my home block (a buffer chest): the supply chest hands me what I need through it.")
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

-- Put away everything not in keep (item -> count): blocks the building
-- uses back into the supply chest, everything dug up into the spoil chest.
-- Fuel stays. If a chest is full, the extra is thrown out on top.
local function dump(keep)
  local kept, warned, uses = {}, false, {}
  for _, name in ipairs(job and job.mats or {}) do uses[itemFor(name)] = true end
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and not FUEL[it.name] then
      local k = math.max(0, math.min(it.count, (keep[it.name] or 0) - (kept[it.name] or 0)))
      kept[it.name] = (kept[it.name] or 0) + k
      local drop = it.count - k
      if drop > 0 then
        turtle.select(slot)
        if uses[it.name] then faceSupply() else faceSpoil() end
        if not turtle.drop(drop) then
          if not warned then
            print("Spoil chest is full or missing; throwing the extra out.")
            warned = true
          end
          turtle.dropUp(drop)
        end
      end
    end
  end
  turtle.select(1)
end

---------------------------------------------------------------- the storage system

-- the storage computer, looked up again a minute after none answered
local storage = net.peer(STORAGE_PROTOCOL, { retry = 60, wait = STORAGE_WAIT })
local supply = claim.tracker("delivery", CLAIM_RETRY) -- whether the storage system knows my supply chest

-- Ask a storage computer something; nil if there isn't one in range.
local function askStorage(msg)
  if not USE_STORAGE then return nil end
  return (storage:ask(msg))
end

-- Have the storage system top up my supply chest (its delivery chest) with
-- what's needed beyond what I'm carrying.
local function orderFromStorage(needs)
  local order, any = {}, false
  for item, n in pairs(needs) do
    local short = n - count(item)
    if short > 0 then order[item], any = short, true end
  end
  if not any then return nil end
  -- first time: tell the storage system which of its chests is my supply chest
  if supply:due() then
    faceSupply()
    local ok, why = supply:check(askStorage, "front")
    if ok then
      print(("The storage system sends my blocks to my supply chest (%s)."):format(why))
    elseif ok == false then
      print("Couldn't hook my supply chest up to the storage system: " .. why)
    end
  end
  local r = askStorage({ type = "deliver", items = order })
  supply:seen(r) -- not sent to my own chest: find it again next time
  if r then
    local sent = 0
    for _, n in pairs(r.sent or {}) do sent = sent + n end
    if sent > 0 then print(("The storage system sent %d blocks to %s."):format(sent,
      r.to == "output" and "its output chest" or "my supply chest")) end
  end
  return r
end

---------------------------------------------------------------- fuel and restocking

local function ensureFuel()
  local limit = turtle.getFuelLimit()
  local target = limit == "unlimited" and REFUEL_TO or math.min(REFUEL_TO, limit)
  if fuelLevel() >= target then return end
  refuelFromInventory(target)
  if fuelLevel() < target then
    faceSupply()
    takeFront(function(n) return FUEL[n] end, 64, fuelItems)
    refuelFromInventory(target)
  end
  if fuelLevel() < target then
    for _, f in ipairs(STORAGE_FUEL) do
      local r = orderFromStorage({ [f[1]] = f[2] })
      if r and r.ready and (r.ready[f[1]] or 0) > 0 then break end
    end
    faceSupply()
    takeFront(function(n) return FUEL[n] end, 64, fuelItems)
    refuelFromInventory(target)
  end
  -- enough to get out to the far corner of the building and back, at least
  local need = 2 * (math.abs(box.x1 - home.x) + math.abs(box.z1 - home.z) + math.abs(box.x0 - home.x)
    + math.abs(box.z0 - home.z) + cruiseHeight() - home.y) + FUEL_MARGIN
  local said = false
  while fuelLevel() < math.min(need, target) and not stopRequested do
    if not said then
      print(("Need fuel: have %d, want %d. Put coal in the chest behind my home, or in me."):format(fuelLevel(), need))
      status("waiting", "needs fuel")
      sendProgress("waiting", "needs fuel")
      said = true
    end
    local timer = os.startTimer(10)
    repeat
      local event, value = os.pullEvent()
    until event == "turtle_inventory" or (event == "timer" and value == timer)
    refuelFromInventory(target)
    faceSupply()
    takeFront(function(n) return FUEL[n] end, 64, fuelItems)
    refuelFromInventory(target)
  end
  nav.face(home.heading)
end

-- Out of fuel away from home: wait for some to be put in the turtle.
waitForFuelHere = function()
  local p = nav.getPos()
  print(("Out of fuel at %d,%d,%d. Put coal in me."):format(p.x, p.y, p.z))
  status("waiting", "out of fuel away from home")
  while fuelLevel() == 0 do
    os.pullEvent("turtle_inventory")
    refuelFromInventory(FUEL_MARGIN * 2)
  end
end

local function stackSize(item) return STACK[item] or 64 end

-- What to take for the next stretch of the build: LOAD_SLOTS stacks' worth
-- of the blocks coming up.
local function loadPlan(from)
  local want, slots = {}, 0
  for k = from, #order do
    local item = itemFor(job.mats[job.blocks[order[k]][4]])
    local n = want[item] or 0
    if n % stackSize(item) == 0 then
      if slots >= LOAD_SLOTS then break end
      slots = slots + 1
    end
    want[item] = n + 1
  end
  return want
end

-- Go home, put away what was dug up, refuel and load up for the next stretch.
local function restock(want, why)
  print("Going home: " .. why)
  status("restocking", why)
  sendProgress("restocking", why)
  goHome()
  dump(want)
  ensureFuel()
  if next(want) then orderFromStorage(want) end
  faceSupply()
  for item, n in pairs(want) do
    if count(item) < n then takeFront(function(x) return x == item end, n, function() return count(item) end) end
  end
  nav.face(home.heading)
end

-- Still none of item after restocking: wait for the player (or the storage
-- system) to put some in the supply chest. False if the build was stopped.
local function waitForItem(item, want)
  local said = false
  while count(item) == 0 do
    if stopRequested then return false end
    -- full of other blocks: put back what the next stretch doesn't need, to
    -- make room for this one
    if emptySlots() == 0 then dump(loadPlan(prog.step)) end
    orderFromStorage({ [item] = want })
    faceSupply()
    takeFront(function(x) return x == item end, want, function() return count(item) end)
    if count(item) > 0 then break end
    if not said then
      print(("Out of %s. Put some in the chest behind my home block."):format(shortName(item)))
      status("waiting", "needs " .. shortName(item))
      sendProgress("waiting", "needs " .. shortName(item))
      said = true
    end
    local timer = os.startTimer(10)
    repeat
      local event, value = os.pullEvent()
    until event == "turtle_inventory" or (event == "timer" and value == timer)
  end
  nav.face(home.heading)
  return true
end

-- Full, and some of it is what was dug up: time to go and empty it. Full of
-- blocks to build with (a good load split over part stacks) isn't.
local function fullOfSpoil()
  if emptySlots() > 0 then return false end
  local uses = {}
  for _, name in ipairs(job.mats) do uses[itemFor(name)] = true end
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and not uses[it.name] and not FUEL[it.name] then return true end
  end
  return false
end

local function housekeeping()
  if fullOfSpoil() then restock(loadPlan(math.max(1, prog.step)), "inventory full") end
  if fuelLevel() < homeDistance() then
    refuelFromInventory(homeDistance() + 500)
    if fuelLevel() < homeDistance() then restock(loadPlan(math.max(1, prog.step)), "low on fuel") end
  end
end

---------------------------------------------------------------- building

local function sameAt(inspect, name)
  local ok, data = inspect()
  return ok and data.name == baseName(name)
end

-- A door: from the cell beside it that the plan leaves empty, facing it, so
-- the door's top half has room. Returns "ok", "missing" or "skip".
local function placeDoor(b, name, item)
  local filled = {}
  for _, o in ipairs(job.blocks) do
    if o[2] == b[2] then filled[o[1] .. "," .. o[3]] = true end
  end
  for h = 0, 3 do
    local d = ({ [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } })[h]
    local side = { x = b[1] - d[1], y = b[2], z = b[3] - d[2] }
    if not filled[side.x .. "," .. side.z] and not othersCell(side.x, side.z) then
      if count(item) == 0 then return "missing" end
      if reach(side) then
        nav.face(h)
        if sameAt(turtle.inspect, name) then return "ok" end
        if turtle.detect() then turtle.dig() end
        selectName(item)
        local ok = turtle.place()
        turtle.select(1)
        if ok then return "ok" end
      end
    end
  end
  return "skip"
end

-- Place one block of the building from the block above it. Returns "ok",
-- "missing" (out of that block) or "skip" (couldn't get there or place it).
local function placeBlock(b)
  local name = job.mats[b[4]]
  local item = itemFor(name)
  local stand = { x = b[1], y = b[2] + 1, z = b[3] }
  -- already there? (after a reboot, the last block may already be placed)
  local p = nav.getPos()
  if p.x == stand.x and p.y == stand.y and p.z == stand.z and sameAt(turtle.inspectDown, name) then return "ok" end
  if name:find("_door", 1, true) then return placeDoor(b, name, item) end
  if count(item) == 0 then return "missing" end
  if not reach(stand) then return "skip" end
  if sameAt(turtle.inspectDown, name) then return "ok" end
  if turtle.detectDown() and not nav.digDown() then return "skip" end
  -- placed from above, a block faces the way the turtle does
  if facingOf(name) then nav.face(facingOf(name)) end
  selectName(item)
  for _ = 1, PLACE_TRIES do
    if turtle.placeDown() then
      turtle.select(1)
      return "ok"
    end
    turtle.attackDown()
    sleep(0.5)
  end
  turtle.select(1)
  return "skip"
end

local function finish(stage, text)
  sendProgress(stage, text)
  print(text)
  nav.deleteFile(JOB_FILE)
  nav.deleteFile(PROGRESS_FILE)
  job, prog, order, box = nil, nil, nil, nil
  stopRequested = false
end

local function runJob()
  buildPlan()
  print(("Building %s: %d blocks."):format(job.name, total()))
  if prog.stage == "clear" then
    if CLEAR_FIRST and job.clear ~= false then
      local size = clearCells()
      status("clearing", job.name)
      sendProgress("clear")
      while prog.step < size do
        if stopRequested then break end
        local p = clearCell(prog.step)
        if reach(p) then
          if p.y + 1 <= box.y1 then nav.digUp() end
          if p.y - 1 >= box.y0 then nav.digDown() end
        end
        prog.step = prog.step + 1
        save()
        if prog.step % REPORT_EVERY == 0 then
          status("clearing", ("%s: %d%%"):format(job.name, math.floor(prog.step / size * 100)))
          sendProgress("clear")
        end
        if prog.step % CHECK_EVERY == 0 then checkPosition() end
        if emptySlots() == 0 then restock({}, "inventory full") end
        if fuelLevel() < homeDistance() then restock({}, "low on fuel") end
      end
    end
    if not stopRequested then
      prog.stage, prog.step, prog.skipped = "build", 1, 0
      save()
      restock(loadPlan(1), "loading blocks")
    end
  end
  while not stopRequested and prog.stage == "build" and prog.step <= #order do
    local b = job.blocks[order[prog.step]]
    local r = placeBlock(b)
    if r == "missing" then
      local item = itemFor(job.mats[b[4]])
      local want = loadPlan(prog.step)
      restock(want, "loading blocks")
      if count(item) == 0 and not waitForItem(item, want[item] or 1) then break end
    else
      if r == "skip" then
        prog.skipped = (prog.skipped or 0) + 1
        print(("Couldn't place %s at %d,%d,%d; skipped it."):format(shortName(job.mats[b[4]]), b[1], b[2], b[3]))
      end
      prog.step = prog.step + 1
      save()
      if prog.step % REPORT_EVERY == 0 then
        status("building", ("%s: %d of %d"):format(job.name, prog.step - 1, total()))
        sendProgress("build")
      end
      if prog.step % CHECK_EVERY == 0 then checkPosition() end
      housekeeping()
    end
  end
  -- up out of the building, and home
  goHome()
  dump({})
  if stopRequested then
    finish("stopped", ("Stopped building %s."):format(job.name))
  else
    local skipped = prog.skipped or 0
    finish("done", skipped > 0 and ("Built %s, but skipped %d blocks I couldn't place."):format(job.name, skipped)
      or ("Built %s."):format(job.name))
  end
  status("idle", "waiting for a building")
end

---------------------------------------------------------------- listening

-- A building sent by a projector: take it if idle, or say what I'm busy with.
local function onMessage(from, msg)
  if type(msg) ~= "table" then return end
  local function answer(reply)
    reply.id, reply.key = msg.id, msg.key
    rednet.send(from, reply, BUILD_PROTOCOL)
  end
  if msg.type == "build" then
    if job then
      answer({ type = "busy", name = job.name, done = prog and prog.stage == "build" and prog.step - 1 or 0, total = total() })
      return
    end
    if type(msg.blocks) ~= "table" or #msg.blocks == 0 or type(msg.mats) ~= "table" then
      answer({ type = "refused", why = "the plan was empty" })
      return
    end
    local b = msg.blocks[1]
    local far = math.abs(b[1] - home.x) + math.abs(b[3] - home.z)
    if far > MAX_DISTANCE then
      answer({ type = "refused", why = ("it's %d blocks from my home, more than %d"):format(far, MAX_DISTANCE) })
      return
    end
    -- I fly over the top of it, so its top must leave me room under the build limit
    local top = type(msg.area) == "table" and msg.area.y1
    if not top then
      top = -math.huge
      for _, blk in ipairs(msg.blocks) do top = math.max(top, blk[2]) end
    end
    local need = top + 2 + (tonumber(msg.lane) or 0)
    if need > WORLD_TOP then
      answer({ type = "refused", why = ("its top is at Y %d: I'd fly over it at Y %d, above the build limit (Y %d). Lower it by %d"):format(
        top, need, WORLD_TOP, need - WORLD_TOP) })
      return
    end
    job = { key = msg.key, name = tostring(msg.name or "a building"), from = from, mats = msg.mats, blocks = msg.blocks,
      area = type(msg.area) == "table" and msg.area or nil, part = type(msg.part) == "table" and msg.part or nil,
      lane = tonumber(msg.lane), clear = msg.clear ~= false }
    prog = { stage = "clear", step = 0, skipped = 0 }
    nav.writeFile(JOB_FILE, job)
    save()
    answer({ type = "accepted", total = #msg.blocks })
    os.queueEvent("builder_job")
  elseif msg.type == "stop" and job and msg.key == job.key then
    stopRequested = true
    answer({ type = "stopping" })
  elseif msg.type == "status" then
    if job then sendProgress(prog.stage) else answer({ type = "idle" }) end
  end
end

local function listen()
  rednet.host(BUILD_PROTOCOL, os.getComputerLabel())
  while true do
    local from, msg = rednet.receive(BUILD_PROTOCOL)
    onMessage(from, msg)
  end
end

local function work()
  while true do
    if not job then
      print(("Builder ready (turtle #%d). Waiting for a building from a projector."):format(os.getComputerID()))
      status("idle", "waiting for a building")
      repeat os.pullEvent("builder_job") until job
    end
    runJob()
  end
end

---------------------------------------------------------------- setup

local function askNumber(prompt)
  while true do
    write(prompt)
    local n = tonumber(read())
    if n then return math.floor(n) end
    print("Type a whole number.")
  end
end

-- Make the block I'm on home: from GPS, or from what the player reads off F3.
local function setupHome()
  local useGps = gpsPos() ~= nil
  if useGps then
    print("Finding my position and facing with GPS...")
    nav.init(true)
  else
    print("No GPS here, so tell me where I am. Look at my block")
    print("with F3 open: it shows the block's X Y Z (Targeted Block).")
    local x, y, z = askNumber("X: "), askNumber("Y: "), askNumber("Z: ")
    local facing
    while not facing do
      write("Which way am I facing (north, east, south, west)? ")
      facing = nav.HEADINGS[read():lower()]
    end
    nav.setPosition(x, y, z, facing)
  end
  local p = nav.getPos()
  home = { x = p.x, y = p.y, z = p.z, heading = nav.getHeading(), gps = useGps }
  nav.writeFile(HOME_FILE, home)
  print(("Home is %d,%d,%d, facing %s."):format(p.x, p.y, p.z, ({ [0] = "north", "east", "south", "west" })[home.heading]))
  print("Put my supply chest behind me and a spoil chest to my left.")
end

-- No GPS to check against: give the player a chance to say the turtle was moved.
local function confirmResume()
  return nav.confirmResume("Put me back on my home block, facing the way I faced\nthere, then run: builder here")
end

---------------------------------------------------------------- start

if not os.getComputerLabel() then os.setComputerLabel("Builder-" .. os.getComputerID()) end
home = nav.readFile(HOME_FILE)
job = nav.readFile(JOB_FILE)
prog = nav.readFile(PROGRESS_FILE)
if job and not prog then prog = { stage = "clear", step = 0, skipped = 0 } end

if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  nav.deleteFile(PROGRESS_FILE)
  print("Forgot the building. Run 'builder' to wait for another.")
  return
elseif args[1] == "status" then
  if not job then
    print("Not building anything.")
  else
    buildPlan()
    print(("Building %s: %s, %d of %d blocks placed, %d skipped."):format(job.name,
      prog.stage == "clear" and "clearing the plot" or "building", prog.stage == "build" and prog.step - 1 or 0,
      total(), prog.skipped or 0))
  end
  return
elseif args[1] == "setup" or not home then
  setupHome()
  if args[1] == "setup" then return end
elseif args[1] == "here" then
  nav.setPosition(home.x, home.y, home.z, home.heading)
  print("Position reset to my home block.")
elseif home.gps then
  nav.init(true)
else
  if not nav.init(false) then error("Lost track of my position: run 'builder setup' on my home block.", 0) end
  if job and not confirmResume() then return end
end

if not openModem() then
  print("I need a wireless or ender modem to hear the projector.")
  return
end

report.init("builder")
errlog.init("builder", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(work)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, listen, report.loop)
