-- Crafting turtle for the storage system. When a turtle asks the storage
-- computer for something it hasn't got but could make, the storage computer
-- puts the ingredients in this turtle's chest, laid out like the crafting
-- grid, and asks it to craft. It crafts and puts everything back in the
-- chest, and the storage computer puts the results away. With several
-- crafting turtles, a crafting overseer (computers/craft-overseer) hands
-- out the jobs instead; this turtle works the same for either.
--
--   crafter          start (startup.lua runs this)
--   crafter learn    teach the craft overseer a recipe: lay one set of it out
--                    in my crafting grid (slots 1-3, 5-7, 9-11) first
--
-- Needs a crafty turtle (a crafting table on one side) with a wireless or
-- ender modem on the other, or a full-block wired modem against it joined
-- to the storage cable (then the storage computer needs no wireless modem).
-- Put its chest directly in front of it (or below or above it) and connect the chest to the storage
-- network with a full-block wired modem: the turtle tells the storage
-- computer which chest is its own (lib/claim.lua), so there's nothing to pick
-- in 'storage setup'. Far from the storage system, its barrel goes on the
-- craft overseer's cable instead (the overseer's hub: an ender chest whose
-- twin is on the storage cable), and the overseer finds it the same way.
-- Or on an essence farm's cable (a far-away factory computer with botany
-- pots, computers/factory): the factory finds the barrel, hands out the
-- jobs from its own essence, and the storage computer never sees it.
local net = require("lib.net") -- rednet requests and answers
local claim = require("lib.claim") -- tells the storage computer which chest is mine
local crafts = require("lib.crafts") -- the craft overseer, which keeps the recipes ('crafter learn')
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local CRAFT_PROTOCOL = "storage_crafter" -- the storage computer sends crafting jobs on this
local STORAGE_PROTOCOL = "storage" -- recipes are taught to the storage computer on this
local OVERSEER_PROTOCOL = "craft_overseer" -- a craft overseer with an ender chest finds my barrel on this
local OVERSEER_WAIT = 60 -- seconds to wait for the overseer (each answer may wait its turn at its ender chest)
local FARM_PROTOCOL = "factory_crafter" -- an essence farm (a far-away factory) finds my barrel on this
local FARM_WAIT = 10 -- seconds to wait for the essence farm
local GRID = { 1, 2, 3, 5, 6, 7, 9, 10, 11 } -- turtle slots of the 3x3 crafting grid
local STAGE = { 4, 8, 12, 13, 14, 15 } -- slots outside the grid, for sorting ingredients into it
local OUT_SLOT = 16 -- crafted items land here first
local MAX_SUCKS = 64 -- most stacks taken from the chest for one batch, before giving up
local STORAGE_WAIT = 10 -- seconds to wait for the storage computer to answer
local CLAIM_EVERY = 300 -- seconds between checks that the storage computer still has my chest as its crafter chest

local made = 0 -- items crafted since starting, for the status
local busy = false -- crafting now: don't look for my chest meanwhile

---------------------------------------------------------------- helpers

-- Open every modem: wireless reaches the storage computer through the air,
-- wired (a full-block wired modem against me, on the storage cable) through
-- the cable.
local function openModems() return net.open("any") end

local function status(state, detail)
  if report then report.set(state, detail) end
end

-- My chest's side: in front, else below, else above (a turtle facing down
-- into a barrel). Found at start, with the turtle functions for that side.
local SIDE_WAYS = {
  { side = "front", drop = turtle and turtle.drop, suck = turtle and turtle.suck },
  { side = "bottom", drop = turtle and turtle.dropDown, suck = turtle and turtle.suckDown },
  { side = "top", drop = turtle and turtle.dropUp, suck = turtle and turtle.suckUp },
}
local chestWay = SIDE_WAYS[1]

local function findChest()
  for _, w in ipairs(SIDE_WAYS) do
    local c = peripheral.wrap(w.side)
    if c and c.list then
      chestWay = w
      return c
    end
  end
end

local function myChest()
  local c = peripheral.wrap(chestWay.side)
  if c and c.list then return c end
end

local function shortName(name) return (name:gsub("^minecraft:", ""):gsub("_", " ")) end

-- Empty everything into my chest, waiting if it's full.
local function emptyOut()
  local warned = false
  for slot = 1, 16 do
    turtle.select(slot)
    while turtle.getItemCount(slot) > 0 do
      if not chestWay.drop() then
        if not warned then
          print("My chest is full. Waiting...")
          status("waiting", "chest full")
          warned = true
        end
        sleep(2)
      end
    end
  end
  turtle.select(1)
end

---------------------------------------------------------------- my chest

-- the storage computer, by wireless or over the cable
local storage = net.peer(STORAGE_PROTOCOL, { open = "any", wait = STORAGE_WAIT })

-- Ask the storage computer something; nil if it doesn't answer.
local function askStorage(msg) return (storage:ask(msg)) end

-- a craft overseer with an ender chest of its own (far from the storage
-- system) finds my barrel on its cable instead
local overseer = net.peer(OVERSEER_PROTOCOL, { open = "any", wait = OVERSEER_WAIT, retry = 60 })
local function askOverseer(msg) return (overseer:ask(msg)) end

-- an essence farm with crafting turtles of its own (a far-away factory computer)
local farm = net.peer(FARM_PROTOCOL, { open = "any", wait = FARM_WAIT, retry = 60 })
local function askFarm(msg) return (farm:ask(msg)) end

-- Make sure the storage system uses my chest as my crafter
-- chest: the overseer's hub if my chest is on its cable, else the storage
-- computer's own cable. On start, then now and then (it may have been set
-- up again), waiting while it's not running.
local function claimLoop()
  local said
  -- always the overseer first: the storage computer takes an empty chest it
  -- had for me before as still mine (it can't tell two empty chests apart),
  -- so asked first it would keep me from the overseer's barrel for good
  -- an essence farm first: on its cable there's nothing else my barrel could belong to
  local ways = { { ask = askFarm, who = "essence farm" }, { ask = askOverseer, who = "craft overseer" },
    { ask = askStorage, who = "storage system" } }
  while true do
    while busy do sleep(1) end
    local ok, why, way
    local refused = {} -- why each one that answered didn't take it
    for _, w in ipairs(ways) do
      ok, why = claim.chest(w.ask, "crafter", chestWay.side)
      way = w
      if ok then break end
      if ok == false then refused[#refused + 1] = ("%s: %s"):format(w.who, why) end
    end
    if not ok and #refused > 0 then ok, why = false, table.concat(refused, "; ") end
    local text
    if ok then
      text = ("The %s uses my chest (%s)."):format(way.who, why)
    elseif ok == false then
      text = "Couldn't hook my chest up to the storage system: " .. why
    else
      text = "No storage system answered yet: is it running 'storage'?"
    end
    if text ~= said then print(text) said = text end
    if not ok then status("waiting", ok == false and why or "no storage system") end
    -- the overseer said no but the storage computer took it: the overseer may
    -- still be linking its ender chest, so ask it again soon
    sleep(not ok and 30 or (way ~= ways[1] and #refused > 0) and 60 or CLAIM_EVERY)
  end
end

---------------------------------------------------------------- crafting

-- Take the ingredients out of the chest a stack at a time and sort them
-- into the grid by name: steps of grid[k] into cell k. This works however
-- the chest arranges them (barrels with stack upgrades put matching items
-- together in one slot, whatever slot they were sent to).
local function layOut(grid, steps)
  local want = {} -- turtle slot -> item it needs
  for k = 1, 9 do
    if grid[k] then want[GRID[k]] = grid[k] end
  end
  local function full()
    for slot in pairs(want) do
      if turtle.getItemCount(slot) < steps then return false end
    end
    return true
  end
  local sucks = 0
  while not full() do
    local free
    for _, s in ipairs(STAGE) do
      if turtle.getItemCount(s) == 0 then free = s break end
    end
    if not free or sucks >= MAX_SUCKS then return false, "my chest has things in it the recipe doesn't use" end
    turtle.select(free)
    if not chestWay.suck() then return false, "not enough ingredients in my chest" end
    sucks = sucks + 1
    -- hand the stack out to the cells that need it
    local item = turtle.getItemDetail(free)
    for slot, name in pairs(want) do
      local have = turtle.getItemCount(slot)
      if item and name == item.name and have < steps and turtle.getItemCount(free) > 0 then
        turtle.transferTo(slot, steps - have)
      end
    end
  end
  -- what's left over goes back
  for _, s in ipairs(STAGE) do
    turtle.select(s)
    chestWay.drop()
  end
  return true
end

-- Lay out the ingredients, craft, and put everything back in the chest.
-- grid (cell -> item name) comes from the storage computer; without it (an
-- older storage program) chest slot k holds cell k's ingredients, taken in
-- order (suck always takes the first non-empty slot).
local function craft(steps, grid)
  local chest = myChest()
  if not chest then return 0, "my chest is gone" end
  emptyOut()
  if grid then
    local ok, err = layOut(grid, steps)
    if not ok then
      emptyOut()
      return 0, err
    end
  else
    local list = chest.list()
    for k = 1, 9 do
      if list[k] then
        turtle.select(GRID[k])
        chestWay.suck(list[k].count)
      end
    end
  end
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      local inGrid = false
      for _, g in ipairs(GRID) do
        if g == slot then inGrid = true end
      end
      if not inGrid then
        emptyOut()
        return 0, "my chest had more in it than the recipe"
      end
    end
  end
  turtle.select(OUT_SLOT)
  local before, had = {}, {} -- per grid slot, and per item name
  for _, g in ipairs(GRID) do before[g] = turtle.getItemCount(g) end
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then had[item.name] = (had[item.name] or 0) + item.count end
  end
  local ok, err = turtle.craft(steps)
  -- some versions count the limit in items rather than crafts: carry on
  -- while there are ingredients left and it still works
  for _ = 1, 64 do
    if not ok then break end
    local left = false
    for _, g in ipairs(GRID) do
      if before[g] > 0 and turtle.getItemCount(g) > 0 then left = true end
    end
    if not left then break end
    ok = turtle.craft()
  end
  -- what came out: the item there's now more of than before (output can
  -- land back in the grid once the ingredients there are used up)
  local now = {}
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then now[item.name] = (now[item.name] or 0) + item.count end
  end
  local out, outName = 0, nil
  for name, n in pairs(now) do
    local gained = n - (had[name] or 0)
    if gained > out then out, outName = gained, name end
  end
  emptyOut()
  if out == 0 then return 0, err or "that isn't a recipe I can make" end
  made = made + out
  return out, nil, outName
end

local function serve()
  print(("Crafter ready (computer #%d). Waiting for jobs from the storage system."):format(os.getComputerID()))
  status("idle", "waiting for jobs")
  while true do
    local from, msg = rednet.receive(CRAFT_PROTOCOL)
    if type(msg) == "table" and msg.type == "craft" and type(msg.steps) == "number" then
      busy = true
      status("crafting", ("%d crafts"):format(msg.steps))
      local grid = type(msg.grid) == "table" and msg.grid or nil
      local n, err, name = craft(math.max(1, math.min(64, math.floor(msg.steps))), grid)
      if n > 0 then
        print(("Crafted %d %s."):format(n, shortName(name)))
      else
        print("Couldn't craft: " .. tostring(err))
      end
      -- item: what came out, so the storage computer can tell a wrong craft
      rednet.send(from, { type = "crafted", id = msg.id, made = n, item = name, error = err }, CRAFT_PROTOCOL)
      busy = false
      status("idle", ("%d items crafted"):format(made))
    elseif type(msg) == "table" and msg.type == "ping" then
      rednet.send(from, { type = "pong", id = msg.id }, CRAFT_PROTOCOL)
    end
  end
end

---------------------------------------------------------------- learning

-- Read the recipe laid out in the grid, craft it once to see what it makes,
-- and send it to the storage computer.
local function learn()
  local cells, letters, keys, nextLetter = {}, {}, {}, 1
  for k, slot in ipairs(GRID) do
    local item = turtle.getItemDetail(slot)
    if item then
      if not letters[item.name] then
        local ch = ("ABCDEFGHI"):sub(nextLetter, nextLetter)
        letters[item.name], keys[ch], nextLetter = ch, item.name, nextLetter + 1
      end
      cells[k] = letters[item.name]
    end
  end
  for _, slot in ipairs({ 4, 8, 12, 13, 14, 15, 16 }) do
    if turtle.getItemCount(slot) > 0 then
      print(("Slot %d isn't part of the crafting grid: empty it first."):format(slot))
      return
    end
  end
  if nextLetter == 1 then
    print("Lay the recipe out in my crafting grid first:")
    print("slots 1-3 (top row), 5-7 (middle) and 9-11 (bottom).")
    return
  end
  -- rows, trimmed to start at the top left like the recipes file
  local rows = {}
  for row = 1, 3 do
    local line = ""
    for col = 1, 3 do line = line .. (cells[(row - 1) * 3 + col] or " ") end
    rows[row] = line
  end
  while #rows > 0 and rows[1]:match("^%s*$") do table.remove(rows, 1) end
  while #rows > 0 and rows[#rows]:match("^%s*$") do table.remove(rows) end
  local minCol = 3
  for _, line in ipairs(rows) do
    local first = line:find("%S")
    if first then minCol = math.min(minCol, first) end
  end
  for i, line in ipairs(rows) do rows[i] = line:sub(minCol):gsub("%s+$", "") end

  turtle.select(OUT_SLOT)
  if not turtle.craft(1) then
    print("That isn't a recipe: nothing came out.")
    return
  end
  local out = turtle.getItemDetail(OUT_SLOT)
  if not out then
    print("Something came out but I can't see it.")
    return
  end
  local recipe = { make = out.name, count = out.count, rows = rows, keys = keys }
  print(("That makes %d %s."):format(out.count, shortName(out.name)))
  if not openModems() then
    print("I need a modem to tell the storage system.")
    return
  end
  local reply, why = crafts.ask({ type = "learn", recipe = recipe })
  if not reply then
    print("No craft overseer answered (" .. tostring(why) .. "). It keeps")
    print("the recipes: is it running? We need a wireless modem each,")
    print("or me on its cable by a wired modem.")
    return
  end
  if reply.ok then
    print("The craft overseer knows it now. Take the rest of the")
    print("ingredients and what I made back out of me (or let me put")
    print("them in my chest when I next start).")
  else
    print("The craft overseer didn't take it: " .. tostring(reply.error or "no reason given"))
  end
  turtle.select(1)
end

---------------------------------------------------------------- start

if not turtle or not turtle.craft then
  print("This needs a crafty turtle: a turtle with a crafting table equipped.")
  return
end
if not os.getComputerLabel() then os.setComputerLabel("Crafter-" .. os.getComputerID()) end

local args = { ... }
if args[1] == "learn" then return learn() end

if not openModems() then
  print("I need a modem to hear the storage system: a wireless or")
  print("ender modem, or a full-block wired modem on its cable.")
  return
end
if not findChest() then
  print("Put my chest directly in front of me, or below or above")
  print("me (with a full-block wired modem on it, on the storage")
  print("cable, the craft overseer's or the essence farm's), then")
  print("start me again.")
  return
end
rednet.host(CRAFT_PROTOCOL, os.getComputerLabel())
emptyOut() -- leftovers from last time go to the storage system

if report then report.init("crafter") end
parallel.waitForAny(function()
  local ok, err = (errlog and errlog.pcall or pcall)(serve)
  if not ok then
    status("error", tostring(err))
    error(err, 0)
  end
end, claimLoop, function() net.keepOpen("any") end, report and report.loop or function() while true do sleep(3600) end end)
