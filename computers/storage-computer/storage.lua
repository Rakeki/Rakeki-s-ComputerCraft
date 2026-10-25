-- Storage system. Either every chest and barrel on the wired modem network
-- becomes one big store, or an Applied Energistics 2 / Refined Storage
-- system does the storing, through an Advanced Peripherals ME Bridge or RS
-- Bridge (chests.lua and bridge.lua; 'storage setup' picks). Drop items in
-- the input chest and they get put away; type to search on the terminal and
-- press Enter to have a stack sent to the output chest. A monitor, if
-- attached, shows what's stored most.
--
-- Turtles and computers ask it for items over rednet ("storage" protocol)
-- and never see which kind of store is behind it, so the village builder,
-- crafter and smelter work with either. With a crafting turtle
-- (computers/crafter-turtle), anything asked for that isn't stored but can be
-- made from what is gets crafted (recipes.lua, plus recipes taught in-game);
-- an ME or RS system crafts from its own patterns first. An optional fuel
-- chest holds the coal and charcoal: fuel that comes in is put there first,
-- turtles asking for coal are served from it, and the smelter
-- (computers/smelter-computer) fuels its furnaces from it.
--
--   storage          start (asks how it's set up the first time)
--   storage setup    choose the store and the input, output, delivery, crafter, fuel and transfer chests again
--   storage test     check deliveries (one item there and back), the fuel chest and the crafting turtle
--   storage tidy     show the storage's slot sizes and sort bulk items into the roomiest now
--
-- Connect the computer and every chest (and the bridge, if there is one)
-- with networking cable and wired modems: a full-block wired modem touching
-- each chest (small modems only go on full blocks like barrels). Right-click
-- each modem so it turns red.
local report = fs.exists("lib/report.lua") and require("lib.report")
local crafting = fs.exists("crafting.lua") and require("crafting")
if crafting then crafting.load(fs.exists("recipes.lua") and require("recipes") or {}) end
local chests = require("chests")
local bridges = fs.exists("bridge.lua") and require("bridge")

local SETUP_FILE = "/.storage_setup"

local INPUT_EVERY = 2 -- seconds between checks of the input chest
local RESCAN_EVERY = 60 -- seconds between full rescans of the chests (catches items moved by hand)
local TIDY_EVERY = 10 -- seconds between tidies (moving bulk items into storage with stack upgrades)
local VIEW_EVERY = 10 -- fewest seconds between recounts of what could be crafted (listed in light blue)
local OUTPUT_EVERY = 2 -- seconds between checks for crafted items to send to the output chest
local MONITOR_SCALE = 0.5 -- text size on the monitor
local NET_PROTOCOL = "storage" -- rednet protocol turtles ask for items on
local SWEEP_EVERY = 5 -- seconds between clear-outs of the delivery chest
local HOLD = 600 -- seconds items a turtle asked for wait in the delivery chest before going back
local CRAFT_PROTOCOL = "storage_crafter" -- rednet protocol the crafting turtle takes jobs on
local CRAFT_WAIT = 60 -- seconds to wait for the crafting turtle to finish one batch
local MAX_BATCH_OUTPUT = 384 -- most items one batch may make (6 stacks: they must fit in the turtle)

-- Fuel, in the order furnaces are given it, with how many items each one
-- smelts. These go into the fuel chest first when they're put away.
local FUEL = { { "minecraft:charcoal", 8 }, { "minecraft:coal", 8 }, { "minecraft:coal_block", 80 } }

-- { backend = "chests" or "bridge", input, output = name, delivery, crafter, fuel, transfer = name or nil }
local setup
local store -- the backend: chests.lua or bridge.lua
local fuelList = {} -- the fuel chest's list()
local message = { "", "lightGray" } -- shown in the footer
-- Items waiting in the delivery chest for a turtle: name -> { n, at }.
-- Everything else in that chest goes back into storage.
local reserved = {}
-- Crafting: jobs waiting for the crafting turtle (from crafting.plan), and
-- how many of each item asked for by a turtle are already being made.
local craftQueue = {}
local pendingCraft = {}
local planCount = 0
local systemCrafts = {} -- name -> how many the ME/RS system is crafting for turtles
-- Items that aren't stored but could be crafted, for the list:
-- { key, name, count (nil: the ME/RS system has a pattern), displayName, craftable = true }.
local craftView = {}
-- Crafts asked for on the terminal, sent to the output chest once made:
-- name -> { want, sent }.
local outputOrders = {}

-- Items with NBT (enchanted books, named tools) are kept apart from plain ones.
local function keyOf(item) return item.nbt and (item.name .. "#" .. item.nbt) or item.name end

local fuelSmelts = {}
for _, f in ipairs(FUEL) do fuelSmelts[f[1]] = f[2] end
local function isFuel(item) return fuelSmelts[item.name] ~= nil and not item.nbt end

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function isInventory(name)
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t == "inventory" then return true end
  end
  return false
end

---------------------------------------------------------------- what's stored

local function readFuel()
  if not setup.fuel then return end
  local ok, list = pcall(peripheral.call, setup.fuel, "list")
  fuelList = ok and list or {}
end

-- Everything stored, the fuel chest included:
-- key -> { key, name, nbt, count, displayName, maxCount }.
local function allItems()
  local out = {}
  for key, it in pairs(store.items()) do out[key] = it end
  for _, item in pairs(fuelList) do
    local key = keyOf(item)
    local base = out[key]
    out[key] = { key = key, name = item.name, nbt = item.nbt ~= nil, count = (base and base.count or 0) + item.count,
      displayName = base and base.displayName or shortName(item.name), maxCount = base and base.maxCount or 64 }
  end
  return out
end

-- Every stored item, most first, then what could be crafted, most first.
local function totals()
  local list, items = {}, allItems()
  for _, it in pairs(items) do list[#list + 1] = it end
  table.sort(list, function(a, b) return a.count > b.count end)
  local crafts = {}
  for _, it in ipairs(craftView) do
    if not items[it.key] then crafts[#crafts + 1] = it end
  end
  table.sort(crafts, function(a, b) return (a.count or 0) > (b.count or 0) end)
  for _, it in ipairs(crafts) do list[#list + 1] = it end
  return list
end

-- "jungle_fence" -> "Jungle Fence", for items not stored (so no name from the game).
local function titleName(name)
  return (shortName(name):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

---------------------------------------------------------------- moving items

-- Move up to count of the item in slot of chest from into storage, fuel
-- into the fuel chest first. Returns how many didn't fit.
local function putAway(from, slot, item, count)
  local left = count
  if setup.fuel and isFuel(item) then
    local ok, moved = pcall(peripheral.call, from, "pushItems", setup.fuel, slot, left)
    if ok and moved > 0 then
      left = left - moved
      readFuel()
    end
  end
  if left > 0 then left = store.putAway(from, slot, item, left) end
  return left
end

local function storeInput()
  local ok, list = pcall(peripheral.call, setup.input, "list")
  if not ok or not next(list) then return false end
  local full = false
  for slot, item in pairs(list) do
    if putAway(setup.input, slot, item, item.count) > 0 then full = true end
  end
  if full then
    message = { "Storage is full: some items are still in the input chest.", "red" }
    if report then report.log("storage full") end
  end
  return true
end

-- Send up to amount of the item with this key to the chest named to (into
-- slot toSlot, if given): from the store, then the fuel chest, or the fuel
-- chest first if fuelFirst. Returns how many went, and the error if a move
-- failed outright.
local function fetch(key, amount, to, toSlot, fuelFirst)
  local sent, err = 0, nil
  local function fromFuel()
    if not setup.fuel or sent >= amount then return end
    local touched = false
    for slot, item in pairs(fuelList) do
      if keyOf(item) == key and sent < amount then
        touched = true
        local ok, moved = pcall(peripheral.call, to, "pullItems", setup.fuel, slot, amount - sent, toSlot)
        if ok then sent = sent + moved else err = err or tostring(moved) end
      end
    end
    if touched then readFuel() end
  end
  local function fromStore()
    if sent >= amount then return end
    local n, e = store.fetch(key, amount - sent, to, toSlot)
    sent, err = sent + n, err or e
  end
  if fuelFirst then
    fromFuel()
    fromStore()
  else
    fromStore()
    fromFuel()
  end
  return sent, err
end

---------------------------------------------------------------- screens

local query, selected, scroll = "", 1, 0

local function matches()
  local list = totals()
  if query == "" then return list end
  local q, out = query:lower(), {}
  for _, it in ipairs(list) do
    if it.displayName:lower():find(q, 1, true) or it.key:lower():find(q, 1, true) then out[#out + 1] = it end
  end
  return out
end

local function put(t, x, y, text, fg, bg)
  t.setCursorPos(x, y)
  t.setTextColor(colors[fg])
  t.setBackgroundColor(colors[bg or "black"])
  t.write(text)
end

local function fitText(text, w)
  if #text > w then return text:sub(1, w) end
  return text .. (" "):rep(w - #text)
end

local function countText(n)
  if n >= 64 then
    local stacks, rest = math.floor(n / 64), n % 64
    return rest > 0 and ("%d (%dx64+%d)"):format(n, stacks, rest) or ("%d (%dx64)"):format(n, stacks)
  end
  return tostring(n)
end

local function drawTerminal()
  local w, h = term.getSize()
  local list = matches()
  term.setBackgroundColor(colors.black)
  term.clear()
  put(term, 1, 1, (" "):rep(w), "white", "gray")
  put(term, 2, 1, "Storage", "yellow", "gray")
  local _, _, stat = store.space()
  put(term, w - #stat, 1, stat, "lightGray", "gray")
  put(term, 1, 2, "Search: ", "lightGray")
  put(term, 9, 2, query, "white")

  local rows = h - 4
  selected = math.max(1, math.min(selected, #list))
  if selected <= scroll then scroll = selected - 1 end
  if selected > scroll + rows then scroll = selected - rows end
  for i = 1, rows do
    local it = list[scroll + i]
    if it then
      local sel = scroll + i == selected
      local bg = sel and "blue" or "black"
      -- light blue: not stored, but it can be crafted on request
      local count = it.craftable and (it.count and ("can make " .. it.count) or "pattern") or countText(it.count)
      put(term, 1, 2 + i, fitText(" " .. it.displayName, w - #count - 1), it.craftable and not sel and "lightBlue" or "white", bg)
      put(term, w - #count, 2 + i, count .. " ", sel and "white" or it.craftable and "lightBlue" or "lightGray", bg)
    end
  end
  if #list == 0 then put(term, 2, 4, query == "" and "Nothing stored yet." or "No matches.", "lightGray") end

  put(term, 1, h - 1, fitText(message[1], w), message[2])
  local picked = list[selected]
  put(term, 1, h, fitText(picked and picked.craftable and "Enter: craft a stack  Right: craft one"
    or "Enter: a stack  Right: one  Up/Down: pick", w), "gray")
  term.setCursorPos(9 + #query, 2)
  term.setTextColor(colors.white)
  term.setCursorBlink(true)
end

local function drawMonitor()
  local mon = peripheral.find("monitor")
  if not mon then return end
  mon.setTextScale(MONITOR_SCALE)
  local w, h = mon.getSize()
  local list = totals()
  local used, total, text = store.space()
  mon.setBackgroundColor(colors.black)
  mon.clear()
  put(mon, 1, 1, (" "):rep(w), "white", "gray")
  put(mon, 2, 1, "Storage", "yellow", "gray")
  -- how full it is, as a bar (when the store can say)
  if used and total and total > 0 then
    local frac = used / total
    local barW = w - 2
    local filled = math.floor(frac * barW + 0.5)
    local barColour = frac > 0.9 and "red" or frac > 0.7 and "orange" or "green"
    put(mon, 2, 3, (" "):rep(filled), "white", barColour)
    put(mon, 2 + filled, 3, (" "):rep(barW - filled), "white", "gray")
  end
  put(mon, 2, 4, text, "lightGray")
  for i = 1, h - 5 do
    local it = list[i]
    if not it then break end
    local count = it.craftable and (it.count and ("+" .. it.count) or "craft") or tostring(it.count)
    put(mon, 2, 5 + i, fitText(it.displayName, w - #count - 3), it.craftable and "lightBlue" or "white")
    put(mon, w - #count, 5 + i, count, it.craftable and "lightBlue" or "lightGray")
  end
end

local function redraw()
  drawTerminal()
  drawMonitor()
  if report then
    local items = 0
    for _, it in pairs(allItems()) do items = items + it.count end
    local _, _, text = store.space()
    report.set(store.problem and "error" or "running", store.problem or ("%d items; %s"):format(items, text))
  end
end

---------------------------------------------------------------- loops

local orderCraft -- in the crafting section below

local function take(amount)
  local list = matches()
  local it = list[selected]
  if not it then return end
  if it.craftable then
    -- not stored: have it made, and outputLoop sends it on once it's ready
    local made, why = orderCraft(it.name, it.count and math.min(amount, it.count) or amount)
    if made then
      local o = outputOrders[it.name] or { want = 0, sent = 0 }
      o.want = o.want + made
      outputOrders[it.name] = o
      message = { ("Crafting %d %s for the output chest..."):format(made, it.displayName), "lightBlue" }
    else
      message = { ("Can't craft %s: %s."):format(it.displayName, why), "red" }
    end
    return
  end
  local sent = fetch(it.key, amount, setup.output)
  if sent > 0 then
    message = { ("Sent %d %s to the output chest."):format(sent, it.displayName), "lime" }
  else
    message = { "Couldn't send it: is the output chest full?", "red" }
  end
end

local function uiLoop()
  while true do
    redraw()
    local event, a, _, y = os.pullEvent()
    if event == "char" then
      query, selected, scroll = query .. a, 1, 0
    elseif event == "key" then
      if a == keys.backspace then
        query, selected, scroll = query:sub(1, -2), 1, 0
      elseif a == keys.up then
        selected = selected - 1
      elseif a == keys.down then
        selected = selected + 1
      elseif a == keys.pageUp then
        selected = selected - 10
      elseif a == keys.pageDown then
        selected = selected + 10
      elseif a == keys.enter then
        take(64)
      elseif a == keys.right then
        take(1)
      end
    elseif event == "mouse_scroll" then
      selected = selected + a
    elseif event == "mouse_click" then
      local _, h = term.getSize()
      if y >= 3 and y <= h - 2 then selected = scroll + y - 2 end
    end
  end
end

local function inputLoop()
  while true do
    if storeInput() then os.queueEvent("storage_changed") end
    sleep(INPUT_EVERY)
  end
end

---------------------------------------------------------------- crafting

local function nameOf(item)
  local it = allItems()[item]
  return it and it.displayName or shortName(item)
end

-- Every plain item in storage, minus what queued crafts will use up, plus
-- what they'll make: what a new plan can count on.
local function planningStock()
  local avail = {}
  for _, it in pairs(allItems()) do
    if not it.nbt then avail[it.name] = (avail[it.name] or 0) + it.count end
  end
  for _, job in ipairs(craftQueue) do
    for _, item in pairs(job.grid) do avail[item] = (avail[item] or 0) - job.steps end
    avail[job.name] = (avail[job.name] or 0) + job.steps * job.recipe.count
  end
  return avail
end

-- The ME/RS system has a pattern for it.
local function systemCanCraft(name) return store.canCraft ~= nil and store.canCraft(name) end

-- Have count of name made, or as many as can be: by the ME/RS system if it
-- has a pattern, otherwise by queueing crafts for the crafting turtle.
-- Returns how many it's making (and why not all of them), or false and why.
function orderCraft(name, count)
  if systemCanCraft(name) then
    local ok, err = store.craft(name, count)
    if not ok then return false, err end
    systemCrafts[name] = (systemCrafts[name] or 0) + count
    pendingCraft[name] = (pendingCraft[name] or 0) + count
    return count
  end
  if not crafting then return false, "crafting.lua is missing: run 'install update'" end
  if not crafting.canMake(name) then return false, "no recipe for it" end
  if not setup.crafter then return false, "no crafter chest: run 'storage setup'" end
  local stock = planningStock()
  local jobs, why = crafting.plan(name, count, stock), nil
  if not jobs then
    -- make what we can, so a build gets as far as it can meanwhile
    local can = crafting.craftable(name, stock, count - 1)
    if can == 0 then return false, "not enough to make it from" end
    count, why = can, ("only enough to make %d"):format(can)
    jobs = crafting.plan(name, count, stock)
    if not jobs then return false, "not enough to make it from" end
  end
  planCount = planCount + 1
  for _, job in ipairs(jobs) do
    job.plan = planCount
    craftQueue[#craftQueue + 1] = job
  end
  jobs[#jobs].top = count -- the item asked for: counted in pendingCraft until it's made
  pendingCraft[name] = (pendingCraft[name] or 0) + count
  os.queueEvent("storage_craft")
  return count, why
end

-- Once the ME/RS system stops crafting something, what it made is stored
-- and counted like anything else.
local function checkSystemCrafts()
  for name, n in pairs(systemCrafts) do
    if not store.isCrafting(name) then
      systemCrafts[name] = nil
      pendingCraft[name] = math.max(0, (pendingCraft[name] or 0) - n)
      message = { ("The %s system is done crafting %s."):format(store.kind, nameOf(name)), "lime" }
      os.queueEvent("storage_changed")
    end
  end
end

-- Put away anything in the crafter chest. Returns false if it couldn't all
-- go (storage full), since the turtle would craft with it.
local function clearCrafter()
  local ok, list = pcall(peripheral.call, setup.crafter, "list")
  if not ok then return false end
  local empty = true
  for slot, item in pairs(list) do
    if putAway(setup.crafter, slot, item, item.count) > 0 then empty = false end
  end
  return empty
end

local crafterId -- the crafting turtle, once found
-- Why crafting is stuck right now (nil when it's working), so turtles
-- waiting on a craft can say so.
local craftProblem
local jobId = 0

-- One job: in batches that fit the turtle, put the ingredients in the
-- crafter chest (grid cell k in chest slot k), have the turtle craft, and
-- put the results away.
local function runJob(job)
  local r = job.recipe
  local left = job.steps
  local items = allItems()
  while left > 0 do
    local batch = math.min(left, 64, math.floor(MAX_BATCH_OUTPUT / r.count))
    for _, item in pairs(job.grid) do
      batch = math.min(batch, items[item] and items[item].maxCount or 64)
    end
    batch = math.max(1, batch)
    if not clearCrafter() then return false, "the crafter chest won't empty: is storage full?" end
    for k = 1, 9 do
      local item = job.grid[k]
      if item then
        local got, err = fetch(item, batch, setup.crafter, k)
        if got < batch then
          clearCrafter()
          return false, err or ("not enough " .. nameOf(item))
        end
      end
    end
    jobId = jobId + 1
    rednet.send(crafterId, { type = "craft", id = jobId, steps = batch }, CRAFT_PROTOCOL)
    local reply
    local deadline = os.clock() + CRAFT_WAIT
    while not reply and os.clock() < deadline do
      local from, msg = rednet.receive(CRAFT_PROTOCOL, deadline - os.clock())
      if from == crafterId and type(msg) == "table" and msg.type == "crafted" and msg.id == jobId then reply = msg end
    end
    clearCrafter()
    if not reply then
      crafterId = nil
      craftProblem = "its crafting turtle didn't answer"
      return false, "the crafting turtle didn't answer"
    end
    craftProblem = nil
    if (reply.made or 0) == 0 then return false, reply.error or "the recipe didn't work" end
    left = left - batch
  end
  return true
end

local function craftLoop()
  while true do
    checkSystemCrafts()
    if not (setup.crafter and #craftQueue > 0) then
      local timer = os.startTimer(10)
      repeat
        local event, value = os.pullEvent()
      until event == "storage_craft" or (event == "timer" and value == timer)
      if setup.crafter and #craftQueue == 0 then clearCrafter() end -- the turtle's leftovers
    elseif not crafterId and not rednet.isOpen() then
      sleep(5) -- netLoop opens the wireless modem
    else
      crafterId = crafterId or rednet.lookup(CRAFT_PROTOCOL)
      if not crafterId then
        message = { "No crafting turtle answered: is it running 'crafter'?", "orange" }
        craftProblem = "its crafting turtle isn't answering"
        os.queueEvent("storage_changed")
        sleep(10)
      else
        local job = table.remove(craftQueue, 1)
        local n = job.steps * job.recipe.count
        message = { ("Crafting %d %s..."):format(n, nameOf(job.name)), "lightBlue" }
        os.queueEvent("storage_changed")
        local ok, why = runJob(job)
        if job.top then pendingCraft[job.name] = math.max(0, (pendingCraft[job.name] or 0) - job.top) end
        if ok then
          message = { ("Crafted %d %s."):format(n, nameOf(job.name)), "lime" }
          if report then report.log(("crafted %d %s"):format(n, nameOf(job.name))) end
        else
          message = { ("Couldn't craft %s: %s"):format(nameOf(job.name), why), "red" }
          -- the rest of that plan needed this job
          for i = #craftQueue, 1, -1 do
            local other = craftQueue[i]
            if other.plan == job.plan then
              if other.top then pendingCraft[other.name] = math.max(0, (pendingCraft[other.name] or 0) - other.top) end
              table.remove(craftQueue, i)
            end
          end
        end
        os.queueEvent("storage_changed")
      end
    end
  end
end

-- Requests from turtles over rednet:
--   { type = "count", items = { name, ... } }      -> { re = "count", counts = { [name] = n } }
--   { type = "deliver", items = { [name] = n } }   -> { re = "deliver", sent = { [name] = n } }
--   { type = "prepare", items = { [name] = n } }   -> { re = "prepare", crafting, cantCraft }  (start crafting)
--   { type = "learn", recipe = { make, count, rows, keys } } -> { re = "learn", ok }  (from 'crafter learn')
--   { type = "stock" }                              -> { re = "stock", counts, input, fuelChest, fuel }  (smelter)
--   { type = "send", to, slot = 1, items = { [name] = n } } -> { re = "send", sent, fuel }  (load a furnace)
--   { type = "send", to, slot = 2, fuel = n, item }  -> the same, with fuel for n more items (only item, if given)
-- Requests may carry an id, which the reply repeats. count may carry need
-- (name -> how many the turtle wants), which keeps craftable quick.
-- count also answers craftable (how many more could be crafted), and deliver
-- answers crafting (how many it has started making).
-- Items with extra data (enchantments, names) are never counted or sent.

-- Every plain item stored, the fuel chest included: name -> count.
local function countAll()
  local counts = {}
  for _, it in pairs(allItems()) do
    if not it.nbt then counts[it.name] = (counts[it.name] or 0) + it.count end
  end
  return counts
end

local function countPlain(names)
  local all, counts = countAll(), {}
  for _, n in ipairs(names) do counts[n] = all[n] or 0 end
  return counts
end

-- How many items all the stored fuel would smelt.
local function fuelValue(counts)
  local n = 0
  for _, f in ipairs(FUEL) do n = n + (counts[f[1]] or 0) * f[2] end
  return n
end

-- Only furnaces are loaded for the smelter, so a stray message can't empty
-- the store into some other chest.
local function isFurnace(name)
  local t = type(name) == "string" and peripheral.isPresent(name) and peripheral.getType(name)
  return t and (t:find("furnace", 1, true) or t:find("smoker", 1, true)) and true or false
end

-- A request is handled start to finish before the next, and handling one
-- can take a while (moving items, planning crafts). Messages that arrive
-- meanwhile wait here, so none are missed.
local inbox = {}

local function netReceive()
  -- turtles reach us by wireless; the smelter can by the wired network's cable
  local wireless = false
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
      if not rednet.isOpen(side) then rednet.open(side) end
      wireless = wireless or peripheral.call(side, "isWireless")
    end
  end
  if not wireless then
    message = { "No wireless modem: turtles can't ask me for items.", "orange" }
    os.queueEvent("storage_changed")
  end
  rednet.host(NET_PROTOCOL, os.getComputerLabel() or ("storage-" .. os.getComputerID()))
  while true do
    local from, msg = rednet.receive(NET_PROTOCOL)
    if type(msg) == "table" then
      inbox[#inbox + 1] = { from = from, msg = msg }
      os.queueEvent("storage_inbox")
    end
  end
end

-- Replies carry the request's id, so a turtle never takes a late answer to
-- an earlier request for the answer to a new one.
local function answer(to, request, reply)
  reply.id = request.id
  rednet.send(to, reply, NET_PROTOCOL)
end

local function handleRequest(from, msg)
  if type(msg) == "table" and msg.type == "count" and type(msg.items) == "table" then
    local craftable = {}
    local avail = crafting and setup.crafter and planningStock()
    for _, name in ipairs(msg.items) do
      if type(name) == "string" then
        local need = type(msg.need) == "table" and tonumber(msg.need[name]) or nil
        local n = avail and crafting.craftable(name, avail, need) or 0
        -- the ME/RS system doesn't say how many it could make: take it that
        -- it can make what's needed
        if systemCanCraft(name) then n = math.max(n, need or 64) end
        craftable[name] = n + (pendingCraft[name] or 0)
      end
    end
    answer(from, msg, { re = "count", counts = countPlain(msg.items), craftable = craftable })
  elseif type(msg) == "table" and msg.type == "prepare" and type(msg.items) == "table" then
    -- a turtle waiting for materials: start crafting what it'll need,
    -- beyond what's stored and what's already being made
    local stock, making, cantCraft = planningStock(), {}, {}
    for name, n in pairs(msg.items) do
      if type(name) == "string" and type(n) == "number" then
        local missing = math.floor(n) - math.max(0, stock[name] or 0) - (pendingCraft[name] or 0)
        if missing > 0 then
          local made, why = orderCraft(name, missing)
          if made then making[name] = made end
          if why then cantCraft[name] = why end
          stock = planningStock()
        end
        if (pendingCraft[name] or 0) > 0 then making[name] = pendingCraft[name] end
      end
    end
    answer(from, msg, { re = "prepare", crafting = making, cantCraft = cantCraft, craftProblem = craftProblem })
    local first, why = next(cantCraft)
    local kinds = 0
    for _ in pairs(making) do kinds = kinds + 1 end
    if kinds > 0 then
      message = { ("Crafting %d kinds of item for turtle #%d."):format(kinds, from), "lightBlue" }
    elseif first and why ~= "no recipe for it" then
      message = { ("Can't craft %s for turtle #%d: %s."):format(nameOf(first), from, why), "orange" }
    end
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "learn" then
    local okL, err = false, "this storage computer can't craft (crafting.lua is missing)"
    if crafting then okL, err = crafting.learn(msg.recipe) end
    answer(from, msg, { re = "learn", ok = okL and true or false, error = not okL and err or nil })
    if okL then message = { ("Learnt how to make %s."):format(nameOf(msg.recipe.make)), "lime" } end
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "stock" then
    local counts = countAll()
    answer(from, msg, { re = "stock", counts = counts, input = setup.input, fuelChest = setup.fuel, fuel = fuelValue(counts) })
  elseif type(msg) == "table" and msg.type == "send" then
    local sent, failed = {}, nil
    if not isFurnace(msg.to) then
      failed = ("%s isn't a furnace on my network"):format(tostring(msg.to))
    elseif msg.slot == 2 then
      -- fuel for this many more items, of the first kind there is (a fuel
      -- slot only takes one kind), from the fuel chest first
      local want = tonumber(msg.fuel) or 0
      for _, f in ipairs(FUEL) do
        if want > 0 and (msg.item == nil or msg.item == f[1]) then
          local got, err = fetch(f[1], math.min(64, math.ceil(want / f[2])), msg.to, 2, true)
          failed = failed or err
          if got > 0 then
            sent[f[1]] = got
            break
          end
        end
      end
    elseif msg.slot == 1 and type(msg.items) == "table" then
      for name, n in pairs(msg.items) do
        if type(name) == "string" and type(n) == "number" and n > 0 then
          local err
          sent[name], err = fetch(name, math.min(64, math.floor(n)), msg.to, 1)
          failed = failed or err
        end
      end
    end
    answer(from, msg, { re = "send", sent = sent, fuel = fuelValue(countAll()), error = failed })
    if failed then message = { "Couldn't load a furnace: " .. failed, "red" } end
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "deliver" and type(msg.items) == "table" then
    -- top the chest up to n of each item: what's already there counts
    local to, sent, total = setup.delivery or setup.output, {}, 0
    local okL, list = pcall(peripheral.call, to, "list")
    local present = {}
    for _, item in pairs(okL and list or {}) do
      if not item.nbt then present[item.name] = (present[item.name] or 0) + item.count end
    end
    -- ready: how many now wait in the chest; stock: how many are left in storage
    local ready, names, short, failed = {}, {}, false, nil
    for name, n in pairs(msg.items) do
      if type(name) == "string" and type(n) == "number" and n > 0 then
        n = math.floor(n)
        local have = math.min(present[name] or 0, n)
        sent[name] = 0
        if have < n then
          local err
          sent[name], err = fetch(name, n - have, to)
          failed = failed or err
        end
        ready[name] = have + sent[name]
        if ready[name] < n then short = true end
        total = total + sent[name]
        names[#names + 1] = name
        if setup.delivery then reserved[name] = { n = ready[name], at = os.clock() } end
      end
    end
    -- what isn't there yet and isn't already being made: craft it if we can
    local making, cantCraft = {}, {}
    for _, name in ipairs(names) do
      local missing = math.floor(msg.items[name]) - ready[name] - (pendingCraft[name] or 0)
      if missing > 0 then
        local made, why = orderCraft(name, missing)
        if made then making[name] = made end
        if why then cantCraft[name] = why end
      end
      if (pendingCraft[name] or 0) > 0 then making[name] = pendingCraft[name] end
    end
    answer(from, msg, { re = "deliver", sent = sent, ready = ready, stock = countPlain(names), crafting = making,
      cantCraft = cantCraft, craftProblem = craftProblem, to = setup.delivery and "delivery" or "output", error = failed })
    if failed then
      message = { "Couldn't move items for a turtle: " .. failed, "red" }
    elseif total > 0 and not setup.delivery then
      message = { ("Sent %d items to the output chest for turtle #%d: no delivery chest set."):format(total, from), "orange" }
    elseif total > 0 then
      message = { ("Sent %d items to turtle #%d."):format(total, from), "lightBlue" }
    elseif short and next(making) then
      message = { ("Turtle #%d asked for items I'm crafting now."):format(from), "lightBlue" }
    elseif short and next(cantCraft) and select(2, next(cantCraft)) ~= "no recipe for it" then
      local item, why = next(cantCraft)
      message = { ("Can't craft %s for turtle #%d: %s."):format(nameOf(item), from, why), "orange" }
    elseif short then
      message = { ("Turtle #%d asked for items I don't have."):format(from), "orange" }
    end
    if total > 0 and report then report.log(("sent %d items to turtle #%d"):format(total, from)) end
    os.queueEvent("storage_changed")
  end
end

local function netLoop()
  while true do
    while #inbox == 0 do os.pullEvent("storage_inbox") end
    local req = table.remove(inbox, 1)
    handleRequest(req.from, req.msg)
  end
end

-- Keep the delivery chest clear apart from what a turtle has asked for (and
-- not yet taken, for up to HOLD seconds): anything else goes back into
-- storage. As the turtle takes its items, its reservations shrink to match.
local function sweepLoop()
  while true do
    sleep(SWEEP_EVERY)
    local ok, list = false, nil
    if setup.delivery then ok, list = pcall(peripheral.call, setup.delivery, "list") end
    if ok then
      local allow, held, swept = {}, {}, 0
      for name, r in pairs(reserved) do
        if os.clock() - r.at > HOLD then reserved[name] = nil else allow[name] = r.n end
      end
      for slot, item in pairs(list) do
        local keep = 0
        if not item.nbt and allow[item.name] then
          keep = math.min(allow[item.name], item.count)
          allow[item.name] = allow[item.name] - keep
          held[item.name] = (held[item.name] or 0) + keep
        end
        if item.count > keep then
          local extra = item.count - keep
          swept = swept + extra - putAway(setup.delivery, slot, item, extra)
        end
      end
      for name, r in pairs(reserved) do
        r.n = held[name] or 0
        if r.n == 0 then reserved[name] = nil end
      end
      if swept > 0 then
        message = { ("Put away %d items from the delivery chest."):format(swept), "lightGray" }
        os.queueEvent("storage_changed")
      end
    end
    -- turtles may refuel straight from the fuel chest: keep its count fresh
    readFuel()
  end
end

local function rescanLoop()
  while true do
    sleep(store.scanEvery or RESCAN_EVERY)
    store.scan()
    if store.problem then message = { ("The %s Bridge: %s"):format(store.kind, store.problem), "red" } end
    os.queueEvent("storage_changed")
  end
end

-- With stack upgrades on some storage, keep moving the items there's most
-- of into the roomiest storage, a few stacks at a time.
local function tidyLoop()
  if not store.tidy then
    while true do sleep(3600) end
  end
  while true do
    sleep(TIDY_EVERY)
    local moved, what = store.tidy()
    -- a quiet note: never cover up anything more important
    if moved > 0 and message[2] == "lightGray" then
      message = { what and ("Moved %s into roomier storage."):format(what)
        or "Made room in the roomiest storage for bulk items.", "lightGray" }
      os.queueEvent("storage_changed")
    end
  end
end

-- Keep the list of what could be crafted (but isn't stored) up to date: after
-- storage changes, at most every VIEW_EVERY seconds. Counting is a plan per
-- try, so it runs here rather than on every redraw.
local function craftViewLoop()
  while true do
    local view, avail = {}, planningStock()
    if crafting and setup.crafter then
      for _, name in ipairs(crafting.names()) do
        if (avail[name] or 0) <= 0 then
          local n = crafting.craftable(name, avail)
          if n > 0 then view[#view + 1] = { key = name, name = name, count = n, displayName = titleName(name), craftable = true } end
        end
      end
    end
    if store.craftables then
      local listed = {}
      for _, it in ipairs(view) do listed[it.name] = true end
      for _, name in ipairs(store.craftables()) do
        if not listed[name] and (avail[name] or 0) <= 0 then
          view[#view + 1] = { key = name, name = name, displayName = titleName(name), craftable = true }
        end
      end
    end
    craftView = view
    os.queueEvent("storage_view")
    sleep(VIEW_EVERY)
    os.pullEvent("storage_changed")
  end
end

-- Send crafts asked for on the terminal to the output chest as they're made.
-- Once nothing more is being made, whatever didn't turn up is given up on
-- (the footer has already said why the craft failed).
local function outputLoop()
  while true do
    sleep(OUTPUT_EVERY)
    for name, o in pairs(outputOrders) do
      local have = countAll()[name] or 0
      if have > 0 then
        o.sent = o.sent + fetch(name, math.min(have, o.want - o.sent), setup.output)
      end
      if o.sent >= o.want then
        outputOrders[name] = nil
        message = { ("Crafted %d %s: it's in the output chest."):format(o.sent, nameOf(name)), "lime" }
        os.queueEvent("storage_changed")
      elseif (pendingCraft[name] or 0) == 0 and have == 0 then
        outputOrders[name] = nil
        if o.sent > 0 then
          message = { ("Only %d of %d %s were made: they're in the output chest."):format(o.sent, o.want, nameOf(name)), "orange" }
        end
        os.queueEvent("storage_changed")
      end
    end
  end
end

---------------------------------------------------------------- setup

local function chooseChests()
  local s = {}
  local bridgeName, kind = nil, nil
  if bridges then bridgeName, kind = bridges.find() end
  if bridgeName then
    print(("Found an %s Bridge (%s)."):format(kind, bridgeName))
    print(("Store items in the %s system, instead of in chests"):format(kind))
    write("on the network? [Y/n] ")
    local a = read():lower()
    s.backend = (a == "" or a:sub(1, 1) == "y") and "bridge" or "chests"
  else
    s.backend = "chests"
  end
  local need = s.backend == "bridge" and 2 or 3
  local invs = {}
  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) then invs[#invs + 1] = name end
  end
  table.sort(invs)
  if #invs < need then
    print(("I can only see %d chests. I need at least %d on the"):format(#invs, need))
    print(s.backend == "bridge" and "network: an input and an output."
      or "network: an input, an output, and one or more for storage.")
    print("Put a full-block wired modem against each chest, connect")
    print("them with cable, and right-click each modem so it turns red.")
    return nil
  end
  print("Chests on the network:")
  for i, name in ipairs(invs) do
    local ok, list = pcall(peripheral.call, name, "list")
    local n = 0
    for _ in pairs(ok and list or {}) do n = n + 1 end
    print(("%2d  %s%s"):format(i, name, n > 0 and (" (" .. n .. " stacks)") or ""))
  end
  print("Tip: right-clicking a modem shows its chest's name in chat.")
  local taken = {}
  local function ask(prompt, optional)
    while true do
      write(prompt)
      local text = read()
      if optional and text == "" then return nil end
      local n = tonumber(text)
      if n and invs[n] and not taken[invs[n]] then
        taken[invs[n]] = true
        return invs[n]
      end
      print("Type one of the numbers above" .. (optional and ", or just Enter." or "."))
    end
  end
  s.input = ask("Which is the input chest? ")
  s.output = ask("Which is the output chest? ")
  print("Turtles (like the village builder) can have items sent to")
  print("their own chest. Leave it blank to use the output chest.")
  s.delivery = ask("Which is the delivery chest? [none] ", true)
  print("A crafting turtle can make what's asked for but not stored.")
  print("Its chest sits in front of it. Leave blank if there isn't one.")
  s.crafter = ask("Which is the crafter chest? [none] ", true)
  print("A fuel chest keeps the coal and charcoal for the smelter's")
  print("furnaces and for turtles. Leave blank if there isn't one.")
  s.fuel = ask("Which is the fuel chest? [none] ", true)
  if s.backend == "bridge" then
    print("The bridge can't put items in a chosen slot, so items for")
    print("furnaces and the crafting turtle pass through a transfer")
    print("chest. Leave blank if you use neither.")
    s.transfer = ask("Which is the transfer chest? [none] ", true)
  end
  local f = fs.open(SETUP_FILE, "w")
  f.write(textutils.serialize(s))
  f.close()
  print(s.backend == "bridge" and ("Saved. Items are stored in the %s system."):format(kind)
    or "Saved. Every other chest is storage.")
  return s
end

local function loadSetup()
  if not fs.exists(SETUP_FILE) then return nil end
  local f = fs.open(SETUP_FILE, "r")
  local s = textutils.unserialize(f.readAll())
  f.close()
  return s
end

local args = { ... }
if args[1] == "setup" or not loadSetup() then
  setup = chooseChests()
  if not setup then return end
  if args[1] == "setup" then return end
else
  setup = loadSetup()
end
for _, which in ipairs({ "input", "output" }) do
  if not peripheral.isPresent(setup[which]) then
    print(("Can't find the %s chest (%s). Check its modem is red, or run 'storage setup'."):format(which, setup[which]))
    return
  end
end
-- the optional ones: carry on without them, and say so
local missingChest
for _, which in ipairs({ "delivery", "crafter", "fuel", "transfer" }) do
  if setup[which] and not peripheral.isPresent(setup[which]) then
    print(("Can't find the %s chest (%s), so I'll do without it."):format(which, setup[which]))
    print("Check its modem is red, or run 'storage setup'.")
    missingChest = ("No %s chest found (%s): check its modem."):format(which, setup[which])
    setup[which] = nil
  end
end

if setup.backend == "bridge" then
  if not bridges then
    print("bridge.lua is missing: run 'install update'.")
    return
  end
  local err
  store, err = bridges.new(setup)
  if not store then
    print(("Can't use the ME or RS system: %s."):format(err))
    print("Put a wired modem on the bridge, join it to the network")
    print("and right-click the modem, or run 'storage setup'.")
    return
  end
  print(("Reading the %s system..."):format(store.kind))
  store.scan()
  store.clearTransfer() -- left over from a move cut short
else
  store = chests.new(setup)
  print("Scanning chests...")
  store.scan()
end
readFuel()

-- 'storage tidy': say what slot sizes the storage has, and sort the bulk
-- items into the roomiest storage now, saying each move (and why, if none).
if args[1] == "tidy" then
  if not store.tidy then
    print(("The %s system sorts its own storage: nothing to tidy."):format(store.kind))
    return
  end
  local _, _, bySize = store.roomInfo()
  print("Storage by how much one slot holds:")
  for _, s in ipairs(bySize) do print(("  %5d a slot: %d storages"):format(s[1], s[2])) end
  local total = 0
  for _ = 1, 500 do
    local n = store.tidy(print)
    total = total + n
    if n == 0 then break end
  end
  print(("Done: moved %d stacks."):format(total))
  return
end

-- 'storage test': move one item into the delivery (or output) chest and back,
-- and say what went wrong if it can't.
if args[1] == "test" then
  local _, _, space = store.space()
  print(("Storage: %s."):format(space))
  if store.roomInfo then
    local roomy, most = store.roomInfo()
    print(roomy > 0 and ("%d of them hold more than 64 a slot (up to %d): bulk items go there."):format(roomy, most)
      or "Every chest holds 64 a slot (no stack upgrades).")
  end
  if store.problem then print(("The %s Bridge says: %s"):format(store.kind, store.problem)) end
  local to = setup.delivery or setup.output
  print(("Testing a move into the %s chest (%s)..."):format(setup.delivery and "delivery" or "output", to))
  local pick
  for _, it in ipairs(totals()) do
    if not it.nbt and not it.craftable then pick = it break end
  end
  if not pick then
    print("Storage is empty: put something in the input chest first.")
    return
  end
  local function moveBack()
    local okL, list = pcall(peripheral.call, to, "list")
    for slot, item in pairs(okL and list or {}) do
      if keyOf(item) == pick.key then
        putAway(to, slot, item, 1)
        return
      end
    end
  end
  local sent, err = fetch(pick.key, 1, to)
  if sent > 0 then
    print(("OK: moved 1 %s there."):format(pick.displayName))
    moveBack()
    print("Moved it back. Deliveries work.")
  else
    print("Couldn't move it: " .. (err or "that chest is full"))
    print("Check its modem is red and joined by cable to the " .. (setup.backend == "bridge" and "bridge." or "storage chests."))
  end
  if setup.backend == "bridge" then
    -- a move into one slot goes through the transfer chest
    local okL, list = pcall(peripheral.call, to, "list")
    local okS, size = pcall(peripheral.call, to, "size")
    local free
    for slot = 1, okS and size or 0 do
      if not (okL and list[slot]) then free = slot break end
    end
    if not setup.transfer then
      print("No transfer chest: the bridge can't load the smelter's furnaces or the crafting turtle. Run 'storage setup'.")
    elseif free then
      local got, why = fetch(pick.key, 1, to, free)
      if got > 0 then
        print(("OK: moved 1 %s into slot %d through the transfer chest."):format(pick.displayName, free))
        moveBack()
      else
        print("Couldn't move it through the transfer chest: " .. (why or "no idea why"))
      end
    end
    print(systemCanCraft(pick.name) and ("The %s system can craft %s."):format(store.kind, pick.displayName)
      or ("The %s system has no pattern for %s (fine: it's just a test item)."):format(store.kind, pick.displayName))
  end
  print(setup.fuel and ("Fuel chest: %s. Fuel stored for %d items."):format(setup.fuel, fuelValue(countAll()))
    or "No fuel chest: fuel is kept with everything else.")
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  print(modem and ("Wireless modem on %s: turtles can ask me for items."):format(peripheral.getName(modem))
    or "No wireless modem: turtles can't ask me for items.")
  -- crafting
  if not crafting then
    print("crafting.lua is missing, so I can't craft: run 'install update'.")
  elseif not setup.crafter then
    print(("I know %d recipes, but there's no crafter chest: run 'storage setup'."):format(crafting.count()))
  else
    print(("I know %d recipes. Crafter chest: %s."):format(crafting.count(), setup.crafter))
    if modem then
      if not rednet.isOpen(peripheral.getName(modem)) then rednet.open(peripheral.getName(modem)) end
      local id = rednet.lookup(CRAFT_PROTOCOL)
      if id then
        rednet.send(id, { type = "ping", id = 0 }, CRAFT_PROTOCOL)
        local from, reply = rednet.receive(CRAFT_PROTOCOL, 5)
        print(from == id and type(reply) == "table" and reply.type == "pong"
          and ("Crafting turtle #%d answered: crafting works."):format(id)
          or ("Crafting turtle #%d didn't answer a ping."):format(id))
      else
        print("No crafting turtle answered: is it running 'crafter', with a wireless modem?")
      end
    end
  end
  return
end

term.clear()
if missingChest then message = { missingChest, "orange" } end
if store.problem then message = { ("The %s Bridge: %s"):format(store.kind, store.problem), "red" } end

if report then report.init("storage") end
local ok, err = pcall(parallel.waitForAny, uiLoop, inputLoop, rescanLoop, netReceive, netLoop, sweepLoop, craftLoop,
  tidyLoop, craftViewLoop, outputLoop, report and report.loop or function() while true do sleep(3600) end end)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
