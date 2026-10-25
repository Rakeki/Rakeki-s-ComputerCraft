-- Crafting turtle for the storage system. When a turtle asks the storage
-- computer for something it hasn't got but could make, the storage computer
-- puts the ingredients in this turtle's chest, laid out like the crafting
-- grid, and asks it to craft. It crafts and puts everything back in the
-- chest, and the storage computer puts the results away. With several
-- crafting turtles, a crafting overseer (computers/craft-overseer) hands
-- out the jobs instead; this turtle works the same for either.
--
--   crafter          start (startup.lua runs this)
--   crafter learn    teach the storage system a recipe: lay one set of it out
--                    in my crafting grid (slots 1-3, 5-7, 9-11) first
--
-- Needs a crafty turtle (a crafting table on one side) with a wireless or
-- ender modem on the other, or a full-block wired modem against it joined
-- to the storage cable (then the storage computer needs no wireless modem).
-- Put its chest directly in front of it and connect the chest to the storage
-- network with a full-block wired modem: the turtle tells the storage
-- computer which chest is its own (lib/claim.lua), so there's nothing to pick
-- in 'storage setup'.
local claim = require("lib.claim") -- tells the storage computer which chest is mine
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local CRAFT_PROTOCOL = "storage_crafter" -- the storage computer sends crafting jobs on this
local STORAGE_PROTOCOL = "storage" -- recipes are taught to the storage computer on this
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
local function openModems()
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" and not rednet.isOpen(side) then rednet.open(side) end
  end
  return rednet.isOpen()
end

local function status(state, detail)
  if report then report.set(state, detail) end
end

local function frontChest()
  local c = peripheral.wrap("front")
  if c and c.list then return c end
end

local function shortName(name) return (name:gsub("^minecraft:", ""):gsub("_", " ")) end

-- Empty everything into the chest in front, waiting if it's full.
local function emptyOut()
  local warned = false
  for slot = 1, 16 do
    turtle.select(slot)
    while turtle.getItemCount(slot) > 0 do
      if not turtle.drop() then
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

local storageId
local requestId = 0

-- Ask the storage computer something; nil if it doesn't answer.
local function askStorage(msg)
  storageId = storageId or rednet.lookup(STORAGE_PROTOCOL)
  if not storageId then return nil end
  requestId = requestId + 1
  msg.id = requestId
  rednet.send(storageId, msg, STORAGE_PROTOCOL)
  local deadline = os.clock() + STORAGE_WAIT
  while os.clock() < deadline do
    local from, reply = rednet.receive(STORAGE_PROTOCOL, math.max(0.1, deadline - os.clock()))
    if from == storageId and type(reply) == "table" and reply.re == msg.type and reply.id == msg.id then return reply end
  end
  storageId = nil -- gone quiet: look it up again next time
  return nil
end

-- Make sure the storage computer uses the chest in front of me as its
-- crafter chest: on start, then now and then (it may have been set up
-- again), waiting while it's not running.
local function claimLoop()
  local said
  while true do
    while busy do sleep(1) end
    local ok, why = claim.chest(askStorage, "crafter", "front")
    local text
    if ok then
      text = ("The storage system uses my chest (%s)."):format(why)
    elseif ok == false then
      text = "Couldn't hook my chest up to the storage system: " .. why
    else
      text = "No storage system answered yet: is it running 'storage'?"
    end
    if text ~= said then print(text) said = text end
    if not ok then status("waiting", ok == false and why or "no storage system") end
    sleep(ok and CLAIM_EVERY or 30)
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
    if not turtle.suck() then return false, "not enough ingredients in my chest" end
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
    turtle.drop()
  end
  return true
end

-- Lay out the ingredients, craft, and put everything back in the chest.
-- grid (cell -> item name) comes from the storage computer; without it (an
-- older storage program) chest slot k holds cell k's ingredients, taken in
-- order (suck always takes the first non-empty slot).
local function craft(steps, grid)
  local chest = frontChest()
  if not chest then return 0, "no chest in front of me" end
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
        turtle.suck(list[k].count)
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
  local storage = rednet.lookup(STORAGE_PROTOCOL)
  if not storage then
    print("No storage system answered. Is it running? We need a")
    print("wireless modem each, or me on its cable by a wired modem.")
    return
  end
  rednet.send(storage, { type = "learn", recipe = recipe }, STORAGE_PROTOCOL)
  local id, reply = rednet.receive(STORAGE_PROTOCOL, 5)
  if id == storage and type(reply) == "table" and reply.ok then
    print("The storage system knows it now. Take the rest of the")
    print("ingredients and what I made back out of me (or let me put")
    print("them in my chest when I next start).")
  else
    print("The storage system didn't take it: " .. tostring(reply and reply.error or "no answer"))
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
if not frontChest() then
  print("Put my chest directly in front of me (with a full-block wired")
  print("modem on it, on the storage cable), then start me again.")
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
end, claimLoop, report and report.loop or function() while true do sleep(3600) end end)
