-- Crafting turtle for the storage system. When a turtle asks the storage
-- computer for something it hasn't got but could make, the storage computer
-- puts the ingredients in this turtle's chest, laid out like the crafting
-- grid, and asks it to craft. It crafts and puts everything back in the
-- chest, and the storage computer puts the results away.
--
--   crafter          start (startup.lua runs this)
--   crafter learn    teach the storage system a recipe: lay one set of it out
--                    in my crafting grid (slots 1-3, 5-7, 9-11) first
--
-- Needs a crafty turtle (a crafting table on one side) with a wireless or
-- ender modem on the other. Put its chest directly in front of it, connect
-- the chest to the storage network with a full-block wired modem, and choose
-- it as the crafter chest in 'storage setup'.
local report = fs.exists("lib/report.lua") and require("lib.report")

local CRAFT_PROTOCOL = "storage_crafter" -- the storage computer sends crafting jobs on this
local STORAGE_PROTOCOL = "storage" -- recipes are taught to the storage computer on this
local GRID = { 1, 2, 3, 5, 6, 7, 9, 10, 11 } -- turtle slots of the 3x3 crafting grid
local OUT_SLOT = 16 -- crafted items land here first

local made = 0 -- items crafted since starting, for the status

---------------------------------------------------------------- helpers

local function openWireless()
  if rednet.isOpen() then return true end
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then return false end
  rednet.open(peripheral.getName(modem))
  return true
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

---------------------------------------------------------------- crafting

-- The storage computer has put the ingredients in chest slots 1-9, one
-- slot per grid cell. Take them in order (suck always takes the first
-- non-empty slot), craft, and put everything back.
local function craft(steps)
  local chest = frontChest()
  if not chest then return 0, "no chest in front of me" end
  emptyOut()
  local list = chest.list()
  for k = 1, 9 do
    if list[k] then
      turtle.select(GRID[k])
      turtle.suck(list[k].count)
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
      status("crafting", ("%d crafts"):format(msg.steps))
      local n, err, name = craft(math.max(1, math.min(64, math.floor(msg.steps))))
      if n > 0 then
        print(("Crafted %d %s."):format(n, shortName(name)))
      else
        print("Couldn't craft: " .. tostring(err))
      end
      rednet.send(from, { type = "crafted", id = msg.id, made = n, error = err }, CRAFT_PROTOCOL)
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
  if not openWireless() then
    print("I need a wireless modem to tell the storage system.")
    return
  end
  local storage = rednet.lookup(STORAGE_PROTOCOL)
  if not storage then
    print("No storage system answered. Is it running, with a wireless modem, in range?")
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

if not openWireless() then
  print("I need a wireless or ender modem to hear the storage system.")
  return
end
if not frontChest() then
  print("Put my chest directly in front of me (connected to the storage")
  print("network with a full-block wired modem), then start me again.")
  return
end
rednet.host(CRAFT_PROTOCOL, os.getComputerLabel())
emptyOut() -- leftovers from last time go to the storage system

if report then report.init("crafter") end
parallel.waitForAny(function()
  local ok, err = pcall(serve)
  if not ok then
    status("error", tostring(err))
    error(err, 0)
  end
end, report and report.loop or function() while true do sleep(3600) end end)
