-- Furnace turtle: places a row of furnaces straight ahead of itself and
-- keeps them smelting whatever turns up in the chest behind it (raw ore,
-- sand, logs, clay, food), fuelled with the coal or charcoal in that chest.
-- Everything smelted, and anything it can't smelt, goes into the chest on
-- its left. No modems or cables: it works the furnaces the way hoppers do,
-- from above (what to smelt) and from below (fuel in, results out).
--
-- A crafty turtle (crafting table and pickaxe) makes its own furnaces from
-- cobblestone, 8 each. Otherwise put furnaces in the chest or the turtle.
--
--   furnace [count]    a row of count furnaces (default 4, up to 16), then keep them going
--   furnace resume
--   furnace here       you put me back on my start block (no GPS): carry on from there
--   furnace cancel     forget the job; the furnaces stay
--
-- With a modem it waits for GPS like every turtle that moves; a crafty
-- turtle has no room for one, so it counts its moves (it never goes more
-- than a block or two from its row).
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.furnace_job"
local DEFAULT_COUNT = 4 -- furnaces in the row when no count is given
local MAX_COUNT = 16 -- the longest row
local ROUND_EVERY = 20 -- seconds between rounds while something is smelting (a furnace takes 10 s an item)
local CHECK_EVERY = 30 -- seconds between looks in the chest when there's nothing to do
local GIVE_UP_AFTER = 6 -- rounds with nothing out of a fuelled furnace before I stop expecting anything from it
local FUEL_CARRY = 128 -- most fuel items kept on board; it takes only what the smelting on hand needs, so a shared chest keeps the rest
local KEEP_FREE = 4 -- empty slots left when taking from the chest, for what comes out of the furnaces
local REFUEL_TO = 400 -- my own fuel, topped up from the furnaces' fuel when it gets low
local FURNACE = "minecraft:furnace"

-- Fuel for the furnaces, best first, and how many items each smelts.
local FUELS = {
  { name = "minecraft:coal", smelts = 8 },
  { name = "minecraft:charcoal", smelts = 8 },
  { name = "minecraft:blaze_rod", smelts = 12 },
  { name = "minecraft:dried_kelp_block", smelts = 20 },
  { name = "minecraft:coal_block", smelts = 80 },
}

-- What it smelts: patterns for the part of the name after the colon, any mod.
-- Anything else in the chest goes straight to the output chest.
local SMELTABLE = {
  "^raw_%a+$", "_ore$", "^ancient_debris$", "^sand$", "^red_sand$", "_log$", "^clay_ball$", "^cactus$", "^kelp$",
  "^beef$", "^porkchop$", "^chicken$", "^mutton$", "^rabbit$", "^cod$", "^salmon$", "^potato$",
}

-- Furnaces are crafted from 8 of one of these.
local COBBLE = { ["minecraft:cobblestone"] = true, ["minecraft:cobbled_deepslate"] = true, ["minecraft:blackstone"] = true }

-- The crafting grid's slots that a furnace fills (the 3x3 at the top left, all but the middle).
local GRID = { 1, 2, 3, 5, 7, 9, 10, 11 }

local FUEL_SET, SMELTS_PER = {}, {}
for _, f in ipairs(FUELS) do FUEL_SET[f.name], SMELTS_PER[f.name] = true, f.smelts end

local job

-- The row, in the job's own frame (x right, y up, z forward, from the start
-- block): furnace i is at z = i, y = 0. The turtle loads them from the lane
-- above (y = 1) and fuels and empties them from the lane below (y = -1); the
-- two lanes meet at the start (z = 0) and one past the last furnace.

---------------------------------------------------------------- coordinates

local DIRS = { [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 } }

local function here()
  local o, w = job.origin, nav.getPos()
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  local dx, dz = w.x - o.x, w.z - o.z
  return { x = dx * r.x + dz * r.z, y = w.y - o.y, z = dx * f.x + dz * f.z }
end

local function toWorld(p)
  local o = job.origin
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  return o.x + p.x * r.x + p.z * f.x, o.y + p.y, o.z + p.x * r.z + p.z * f.z
end

local function save() nav.writeFile(JOB_FILE, job) end

local function faceForward() nav.face(job.origin.heading) end
local function faceSupply() nav.face((job.origin.heading + 2) % 4) end -- the chest behind the start
local function faceOutput() nav.face((job.origin.heading + 3) % 4) end -- the chest on its left

---------------------------------------------------------------- moving

local stuckSaid = false

local function waitToMove(err)
  if err == "nofuel" then
    inv.refuel(REFUEL_TO, FUEL_SET)
    if inv.fuelLevel() > 0 then return end
    print("Out of fuel. Put coal or charcoal in my inventory.")
    report.set("waiting", "out of fuel")
    os.pullEvent("turtle_inventory")
    return
  end
  if not stuckSaid then
    local p = nav.getPos()
    print(("Can't move (%s) at %d,%d,%d. Retrying..."):format(tostring(err), p.x, p.y, p.z))
    stuckSaid = true
  end
  report.set("stuck", ("can't move: %s"):format(tostring(err)))
  sleep(5)
end

local function headingFor(dx, dz)
  local h = job.origin.heading
  if dz > 0 then return h elseif dz < 0 then return (h + 2) % 4 elseif dx > 0 then return (h + 1) % 4 end
  return (h + 3) % 4
end

-- Move to p (local), along x, then z, then y: callers only ask for straight runs.
local function go(p)
  while true do
    local c = here()
    local ok, err
    if c.x ~= p.x then
      nav.face(headingFor(p.x - c.x, 0))
      ok, err = nav.forward()
    elseif c.z ~= p.z then
      nav.face(headingFor(0, p.z - c.z))
      ok, err = nav.forward()
    elseif c.y < p.y then
      ok, err = nav.up()
    elseif c.y > p.y then
      ok, err = nav.down()
    else
      stuckSaid = false
      return
    end
    if not ok then waitToMove(err) end
  end
end

-- Back to the start block from anywhere on the lanes (after a reboot too).
local function goHome()
  local c = here()
  if c.y == 0 and c.z > 0 then go({ x = c.x, y = 1, z = c.z }) end -- the far end, between the lanes
  c = here()
  go({ x = 0, y = c.y, z = 0 })
  go({ x = 0, y = 0, z = 0 })
  faceForward()
end

---------------------------------------------------------------- inventory

local function shortName(name) return (name:gsub("^minecraft:", ""):gsub("_", " ")) end

local function isSmeltable(name)
  local base = name:match(":(.+)$") or name
  for _, pattern in ipairs(SMELTABLE) do
    if base:find(pattern) then return true end
  end
  return false
end

local function kindOf(name)
  if FUEL_SET[name] then return "fuel" end
  if isSmeltable(name) then return "smelt" end
  if name == FURNACE then return "furnace" end
  if COBBLE[name] then return "cobble" end
  return "other"
end

local function crafty() return turtle.craft ~= nil end
local function furnacesWanted() return job.count - job.built end

local function onBoard(match)
  local is, n = match and inv.matcher(match), 0
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and (not is or is(it.name)) then n = n + it.count end
  end
  return n
end

-- Room left in the furnaces' input slots (furnaces still to place count as empty).
local function room()
  local n = 0
  for i = 1, job.count do n = n + 64 - (job.inside[i] or 0) end
  return n
end

local function smelting()
  local n = 0
  for i = 1, job.built do n = n + (job.inside[i] or 0) end
  return n
end

-- Is there a chest (or any inventory) in front? turtle.drop with nothing
-- there throws the items on the ground.
local function chestInFront()
  if peripheral.hasType and peripheral.hasType("front", "inventory") then return true end
  local ok, b = turtle.inspect()
  return ok and (b.name:find("chest") or b.name:find("barrel") or b.name:find("shulker")) ~= nil
end

-- Drop n from a slot in front. False if the chest took none.
local function dropSome(slot, n)
  turtle.select(slot)
  local before = turtle.getItemCount(slot)
  turtle.drop(math.min(n, before))
  return turtle.getItemCount(slot) < before
end

-- Fuel items the next round needs: for what the furnaces still have to
-- smelt, what I'm carrying to them, and my own moves.
local function fuelNeeded(smelts)
  for i = 1, job.built do smelts = smelts + math.max(0, -(job.credit[i] or 0)) end
  local mine = inv.fuelLevel() < REFUEL_TO and math.ceil((REFUEL_TO - inv.fuelLevel()) / 80) or 0
  return math.min(FUEL_CARRY, math.ceil(smelts / 8) + mine)
end

-- Keep what the next round needs; everything else goes into a chest: what
-- came from the chest behind (fuel, things to smelt) back there, the rest
-- (what I made, what I can't use) into the chest on the left.
local function sortOut()
  local smelts = math.min(onBoard(isSmeltable), room())
  local left = { smelt = smelts, fuel = fuelNeeded(smelts), furnace = math.max(0, furnacesWanted()), cobble = 0, other = 0 }
  if crafty() then left.cobble = math.max(0, furnacesWanted() - onBoard(FURNACE)) * 8 end
  local back, out = {}, {}
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it then
      local k = kindOf(it.name)
      local keep = math.min(it.count, left[k])
      left[k] = left[k] - keep
      if it.count > keep then
        -- charcoal I made is a product; coal and the rest of the fuel came from the chest
        if k == "smelt" or (k == "fuel" and it.name ~= "minecraft:charcoal") then back[slot] = it.count - keep
        else out[slot] = it.count - keep end
      end
    end
  end
  if next(back) then
    faceSupply()
    if chestInFront() then
      for slot, n in pairs(back) do dropSome(slot, n) end
    end
  end
  if next(out) then
    faceOutput()
    local warned = false
    for slot, n in pairs(out) do
      while turtle.getItemCount(slot) > 0 and n > 0 do
        local before = turtle.getItemCount(slot)
        if chestInFront() and dropSome(slot, n) then
          n = n - (before - turtle.getItemCount(slot))
        else
          if not warned then
            print("The chest on my left is full or missing. Waiting...")
            report.set("waiting", "output chest full or missing")
            warned = true
          end
          sleep(5)
        end
      end
    end
  end
  turtle.select(1)
  faceForward()
end

-- Everything out of the chest behind me (as far as I have room), then sort it.
local function takeSupplies()
  faceSupply()
  turtle.select(1)
  if chestInFront() then
    while inv.emptySlots() > KEEP_FREE and turtle.suck() do end
  end
  sortOut()
end

-- Is there anything in the chest behind me worth a round? Read without
-- moving: at home it's on my back.
local function chestHasWork()
  local ok, items = pcall(peripheral.call, "back", "list")
  if not ok or type(items) ~= "table" then return true end -- can't tell: go and look
  for _, it in pairs(items) do
    local k = kindOf(it.name)
    if k == "smelt" and room() > 0 then return true end
    if (k == "furnace" or (k == "cobble" and crafty())) and furnacesWanted() > 0 then return true end
    if k == "fuel" and onBoard(FUEL_SET) < fuelNeeded(0) then return true end
  end
  return false
end

-- Turn cobblestone into the furnaces still to place. The crafting grid must
-- be the only thing in the inventory, so the rest goes into the chest behind
-- me for a moment (the next takeSupplies brings it back).
local function craftFurnaces()
  local want = furnacesWanted() - onBoard(FURNACE)
  if want <= 0 or not crafty() then return end
  local best, most = nil, 0
  for name in pairs(COBBLE) do
    local n = onBoard(name)
    if n > most then best, most = name, n end
  end
  local n = math.min(want, math.floor(most / 8))
  if n < 1 then return end
  faceSupply()
  if not chestInFront() then return end
  -- everything but 8 * n of the cobblestone goes into the chest
  local keep = 8 * n
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it then
      local k = it.name == best and math.min(it.count, keep) or 0
      keep = keep - k
      if it.count > k and not dropSome(slot, it.count - k) then
        print("The chest behind me is full, so I can't craft furnaces just now.")
        faceForward()
        return
      end
    end
  end
  -- gather the cobblestone outside the grid, then n into each cell of it
  for slot = 1, 12 do
    turtle.select(slot)
    for to = 13, 16 do
      if turtle.getItemCount(slot) == 0 then break end
      turtle.transferTo(to)
    end
  end
  for _, cell in ipairs(GRID) do
    for from = 13, 16 do
      local short = n - turtle.getItemCount(cell)
      if short <= 0 then break end
      turtle.select(from)
      if turtle.getItemCount(from) > 0 then turtle.transferTo(cell, short) end
    end
  end
  turtle.select(16)
  local ok, err = turtle.craft(n)
  if ok then
    print(("Crafted %d furnace%s from %s."):format(n, n == 1 and "" or "s", shortName(best)))
  else
    print("Couldn't craft furnaces: " .. tostring(err))
  end
  turtle.select(1)
  faceForward()
end

-- Drop up to n of an item through drop (dropUp / dropDown), from any slots.
local function dropItem(name, n, drop)
  local moved = 0
  for slot = 1, 16 do
    if moved >= n then break end
    local it = turtle.getItemDetail(slot)
    if it and it.name == name then
      turtle.select(slot)
      drop(math.min(n - moved, it.count))
      local k = it.count - turtle.getItemCount(slot)
      moved = moved + k
      if turtle.getItemCount(slot) > 0 then break end -- it took no more
    end
  end
  turtle.select(1)
  return moved
end

local function topUpMyFuel()
  local need = 4 * job.count + 20
  if inv.fuelLevel() < need then inv.refuel(math.max(need, REFUEL_TO), FUEL_SET) end
end

---------------------------------------------------------------- furnaces

local said = {} -- messages printed once until things change

local function sayOnce(key, text)
  if said[key] then return end
  said[key] = true
  print(text)
end

-- Above spot i: a furnace there already, or place one.
local function placeFurnace(i)
  local ok, b = turtle.inspectDown()
  if ok and (b.name:find("furnace$") or b.name:find("smoker$")) then
    -- a furnace that was already there may have things in it: look underneath for a while
    job.built, job.inside[i], job.credit[i] = i, 1, 0
    return true
  end
  if not inv.select(FURNACE) then return false end
  if ok then nav.digDown() end
  if not inv.select(FURNACE) or not turtle.placeDown() then return false end
  job.built, job.inside[i], job.credit[i] = i, 0, 0
  print(("Furnace %d of %d is in."):format(i, job.count))
  if job.built == job.count then print("All the furnaces are in.") end
  return true
end

-- From above: things to smelt into the input slot. One kind per furnace, and
-- a fair share of what's on board, so every furnace gets some.
local function loadFurnace(i)
  if i > job.built and (i > job.built + 1 or not placeFurnace(i)) then return end
  local space = 64 - (job.inside[i] or 0)
  if space <= 0 then return end
  local totals, total = {}, 0
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and kindOf(it.name) == "smelt" then
      totals[it.name] = (totals[it.name] or 0) + it.count
      total = total + it.count
    end
  end
  if total == 0 then return end
  local name = job.kind[i]
  if not (name and (job.inside[i] or 0) > 0) then
    name = nil
    for n, count in pairs(totals) do
      if not name or count > totals[name] then name = n end
    end
  end
  if not totals[name] then return end
  local share = math.ceil(total / (job.count - i + 1))
  local moved = dropItem(name, math.min(space, share, totals[name]), turtle.dropDown)
  if moved > 0 then
    job.inside[i] = (job.inside[i] or 0) + moved
    job.kind[i] = name
    job.credit[i] = (job.credit[i] or 0) - moved
  end
end

-- From below: results out (the bottom face gives only the output slot),
-- then fuel in for whatever is still to smelt.
local function serveFurnace(i)
  local before = onBoard()
  turtle.select(1)
  while inv.emptySlots() > 0 and turtle.suckUp() do end
  local got = onBoard() - before
  job.made = job.made + got
  local inside = math.max(0, (job.inside[i] or 0) - got)
  -- nothing out of a furnace that has fuel: maybe someone emptied it by hand
  if got == 0 and inside > 0 and (job.credit[i] or 0) >= 0 then
    job.quiet[i] = (job.quiet[i] or 0) + 1
    if job.quiet[i] >= GIVE_UP_AFTER then inside, job.quiet[i] = 0, 0 end
  else
    job.quiet[i] = 0
  end
  job.inside[i] = inside
  if inside == 0 then job.kind[i] = nil end
  -- never owe more fuel than there is left to smelt
  local credit = math.max(job.credit[i] or 0, -inside)
  for _, f in ipairs(FUELS) do
    if credit >= 0 then break end
    local moved = dropItem(f.name, math.ceil(-credit / f.smelts), turtle.dropUp)
    credit = credit + moved * f.smelts
  end
  job.credit[i] = credit
  return credit >= 0
end

---------------------------------------------------------------- main

local function statusText()
  return ("%d/%d furnaces, %d smelting, %d made"):format(job.built, job.count, smelting(), job.made)
end

-- One trip: take from the chest, load the furnaces from above, fuel and
-- empty them from below, put the results in the output chest.
local function round()
  goHome()
  takeSupplies()
  if furnacesWanted() > onBoard(FURNACE) and crafty() then
    craftFurnaces()
    takeSupplies()
  end
  topUpMyFuel()
  report.set("smelting", statusText(), job.gps and { pos = nav.getPos() } or nil)
  go({ x = 0, y = 1, z = 0 })
  for i = 1, job.count do
    go({ x = 0, y = 1, z = i })
    loadFurnace(i)
    save()
  end
  go({ x = 0, y = 1, z = job.count + 1 })
  go({ x = 0, y = -1, z = job.count + 1 })
  local fuelled = true
  for i = job.count, 1, -1 do
    go({ x = 0, y = -1, z = i })
    if i <= job.built and not serveFurnace(i) then fuelled = false end
    save()
  end
  go({ x = 0, y = -1, z = 0 })
  go({ x = 0, y = 0, z = 0 })
  faceForward()
  sortOut()

  if furnacesWanted() > 0 then
    said.allIn = nil
    sayOnce("furnaces", ("I need %d more furnace%s: put them in the chest behind me%s."):format(furnacesWanted(),
      furnacesWanted() == 1 and "" or "s", crafty() and " (or cobblestone, 8 a furnace)" or ""))
  else
    said.furnaces = nil
  end
  if not fuelled then
    sayOnce("fuel", "No fuel for the furnaces: put coal or charcoal in the chest behind me.")
  else
    said.fuel = nil
  end
end

local function run()
  while true do
    round()
    local text = statusText()
    if smelting() > 0 or (onBoard(isSmeltable) > 0 and room() > 0) then
      report.set("smelting", text, job.gps and { pos = nav.getPos() } or nil)
      said.idle = nil
      sleep(ROUND_EVERY)
    else
      report.set("idle", "waiting for something to smelt: " .. text, job.gps and { pos = nav.getPos() } or nil)
      sayOnce("idle", "Nothing to smelt. Waiting for the chest behind me...")
      local event
      repeat
        local timer, value = os.startTimer(CHECK_EVERY), nil
        repeat
          event, value = os.pullEvent()
        until event == "turtle_inventory" or (event == "timer" and value == timer)
      until event == "turtle_inventory" or chestHasWork()
    end
  end
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Job cancelled. The furnaces stay where they are.")
  return
end

require("lib.label").set("Smelter")
job = nav.readFile(JOB_FILE)

-- With a modem, nothing moves without GPS (nav.waitForGps says why on
-- screen). A crafty turtle has no modem: it counts its moves from the start.
local hasModem = peripheral.find("modem") ~= nil
local useGps = hasModem and (not job or job.gps) and nav.waitForGps() ~= nil
local knowsPosition = nav.init(useGps)

if args[1] == "resume" or args[1] == "here" then
  if not job then
    print("No job to resume.")
    return
  end
  if args[1] == "here" then
    local x, y, z = toWorld({ x = 0, y = 0, z = 0 })
    nav.setPosition(x, y, z, job.origin.heading, job.gps)
    print("Position reset to the start block.")
  elseif not useGps then
    if not knowsPosition then error("Lost track of position; can't resume. Run 'furnace cancel'.", 0) end
    if not nav.confirmResume("Put me back on my start block, facing my furnaces,\nthen run: furnace here") then return end
  end
  print("Resuming: " .. statusText())
elseif job then
  print("A job is already in progress. Run 'furnace resume' or 'furnace cancel'.")
  return
else
  local count = tonumber(args[1] or DEFAULT_COUNT)
  if not count or count < 1 or count > MAX_COUNT then
    print(("Usage: furnace [count]   (1 to %d furnaces, default %d)"):format(MAX_COUNT, DEFAULT_COUNT))
    return
  end
  count = math.floor(count)
  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  local p = nav.getPos()
  job = { gps = useGps, origin = { x = p.x, y = p.y, z = p.z, heading = nav.getHeading() }, count = count,
    built = 0, inside = {}, kind = {}, credit = {}, quiet = {}, made = 0 }
  print(("A row of %d furnaces straight ahead of me, with a lane"):format(count))
  print("dug above and below it.")
  print("Chest behind me: ore, sand, logs, food and fuel go in.")
  print("Chest on my left: everything smelted comes out.")
  if crafty() then print("I craft my own furnaces from cobblestone.") end
  print(("I burn about %d fuel a round."):format(4 * count + 8))
  print("Press Enter to start.")
  read()
  save()
end

report.init("smelter")
errlog.init("furnace", function() return { pos = nav.getPos(), job = job and statusText() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
