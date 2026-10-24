-- Storage system. Every chest and barrel on the wired modem network becomes
-- one big store. Drop items in the input chest and they get put away; type
-- to search on the terminal and press Enter to have a stack sent to the
-- output chest. A monitor, if attached, shows what's stored most.
--
-- With a wireless modem too, turtles can ask it over rednet how much of an
-- item is stored and have it sent to a delivery chest (the village builder
-- uses this to stock its supply chest). With a crafting turtle as well
-- (computers/crafter-turtle), anything asked for that isn't stored but can be
-- made from what is gets crafted (recipes.lua, plus recipes taught in-game).
--
--   storage          start (asks which chest is input and output the first time)
--   storage setup    choose the input, output, delivery and crafter chests again
--   storage test     check deliveries (one item there and back) and the crafting turtle
--
-- Connect the computer and every chest with networking cable and wired
-- modems: a full-block wired modem touching each chest (small modems only go
-- on full blocks like barrels). Right-click each modem so it turns red.
local report = fs.exists("lib/report.lua") and require("lib.report")
local crafting = fs.exists("crafting.lua") and require("crafting")
if crafting then crafting.load(fs.exists("recipes.lua") and require("recipes") or {}) end

local SETUP_FILE = "/.storage_setup"

local INPUT_EVERY = 2 -- seconds between checks of the input chest
local RESCAN_EVERY = 60 -- seconds between full rescans (catches items moved by hand)
local MONITOR_SCALE = 0.5 -- text size on the monitor
local NET_PROTOCOL = "storage" -- rednet protocol turtles ask for items on
local SWEEP_EVERY = 5 -- seconds between clear-outs of the delivery chest
local HOLD = 600 -- seconds items a turtle asked for wait in the delivery chest before going back
local CRAFT_PROTOCOL = "storage_crafter" -- rednet protocol the crafting turtle takes jobs on
local CRAFT_WAIT = 60 -- seconds to wait for the crafting turtle to finish one batch
local MAX_BATCH_OUTPUT = 384 -- most items one batch may make (6 stacks: they must fit in the turtle)

-- Inventories that count as storage, matched against the peripheral type
-- (e.g. "minecraft:chest"). Furnaces, hoppers and turtles never do.
local STORAGE_TYPES = { "chest", "barrel", "shulker_box", "crate", "drawer" }

local setup -- { input = name, output = name, delivery = name or nil, crafter = name or nil }
local stores = {} -- peripheral names of the storage inventories
local contents = {} -- store name -> its list() result
local sizes = {} -- store name -> number of slots
local details = {} -- item key -> { name, displayName }
local message = { "", "lightGray" } -- shown in the footer
-- Items waiting in the delivery chest for a turtle: name -> { n, at }.
-- Everything else in that chest goes back into storage.
local reserved = {}
-- Crafting: jobs waiting for the crafting turtle (from crafting.plan), and
-- how many of each item asked for by a turtle are already being made.
local craftQueue = {}
local pendingCraft = {}
local planCount = 0

---------------------------------------------------------------- inventories

local function isInventory(name)
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t == "inventory" then return true end
  end
  return false
end

local function isStorage(name)
  if name == setup.input or name == setup.output or name == setup.delivery or name == setup.crafter then return false end
  local t = peripheral.getType(name)
  for _, s in ipairs(STORAGE_TYPES) do
    if t:find(s, 1, true) then return true end
  end
  return false
end

-- Items with NBT (enchanted books, named tools) are kept apart from plain ones.
local function keyOf(item) return item.nbt and (item.name .. "#" .. item.nbt) or item.name end

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function rescan(name)
  local ok, list = pcall(peripheral.call, name, "list")
  contents[name] = ok and list or {}
  for slot, item in pairs(contents[name]) do
    local key = keyOf(item)
    if not details[key] then
      local okD, d = pcall(peripheral.call, name, "getItemDetail", slot)
      details[key] = { name = item.name, displayName = okD and d and d.displayName or shortName(item.name),
        maxCount = okD and d and d.maxCount or 64 }
    end
  end
end

local function scanAll()
  stores = {}
  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) and isStorage(name) then stores[#stores + 1] = name end
  end
  table.sort(stores)
  local jobs = {}
  for _, name in ipairs(stores) do
    jobs[#jobs + 1] = function()
      local ok, size = pcall(peripheral.call, name, "size")
      sizes[name] = ok and size or 0
      rescan(name)
    end
  end
  -- Each call takes a game tick, so ask every chest at once.
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
  for name in pairs(contents) do
    if not sizes[name] or not peripheral.isPresent(name) then contents[name], sizes[name] = nil, nil end
  end
end

-- Every stored item: { key, count, displayName }, plus slot totals.
local function totals()
  local byKey, used, slots = {}, 0, 0
  for _, name in ipairs(stores) do
    slots = slots + (sizes[name] or 0)
    for _, item in pairs(contents[name] or {}) do
      local key = keyOf(item)
      byKey[key] = (byKey[key] or 0) + item.count
      used = used + 1
    end
  end
  local list = {}
  for key, count in pairs(byKey) do
    list[#list + 1] = { key = key, count = count, displayName = details[key] and details[key].displayName or key }
  end
  table.sort(list, function(a, b) return a.count > b.count end)
  return list, used, slots
end

---------------------------------------------------------------- moving items

-- Put everything in the input chest away: into chests that already hold
-- that item first, then anywhere with space.
-- Move up to count of the item in slot of chest from into storage. Returns
-- how many didn't fit.
local function putAway(from, slot, item, count)
  local key, left = keyOf(item), count
  local order = {}
  for _, name in ipairs(stores) do
    for _, have in pairs(contents[name] or {}) do
      if keyOf(have) == key then order[#order + 1] = name break end
    end
  end
  for _, name in ipairs(stores) do order[#order + 1] = name end
  for _, name in ipairs(order) do
    local okP, moved = pcall(peripheral.call, from, "pushItems", name, slot, left)
    if okP and moved > 0 then
      left = left - moved
      rescan(name)
    end
    if left <= 0 then break end
  end
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

-- Send up to amount of the items matching match(item) to the chest named to
-- (into slot toSlot, if given). Returns how many went, and the error if a
-- move failed outright.
local function fetch(match, amount, to, toSlot)
  local sent = 0
  for _, name in ipairs(stores) do
    local touched = false -- only re-read chests items came from: each read takes a tick
    for slot, item in pairs(contents[name] or {}) do
      if match(item) then
        touched = true
        local ok, moved = pcall(peripheral.call, to, "pullItems", name, slot, amount - sent, toSlot)
        if not ok then
          rescan(name)
          return sent, tostring(moved) -- e.g. the chest isn't on the same network
        end
        sent = sent + moved
        if moved == 0 then
          rescan(name)
          return sent -- that chest is full
        end
        if sent >= amount then break end
      end
    end
    if touched then rescan(name) end
    if sent >= amount then break end
  end
  return sent
end

---------------------------------------------------------------- screens

local query, selected, scroll = "", 1, 0

local function matches()
  local list, used, slots = totals()
  if query == "" then return list, used, slots end
  local q, out = query:lower(), {}
  for _, it in ipairs(list) do
    if it.displayName:lower():find(q, 1, true) or it.key:lower():find(q, 1, true) then out[#out + 1] = it end
  end
  return out, used, slots
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
  local list, used, slots = matches()
  term.setBackgroundColor(colors.black)
  term.clear()
  put(term, 1, 1, (" "):rep(w), "white", "gray")
  put(term, 2, 1, "Storage", "yellow", "gray")
  local stat = ("%d chests, %d/%d slots"):format(#stores, used, slots)
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
      local count = countText(it.count)
      put(term, 1, 2 + i, fitText(" " .. it.displayName, w - #count - 1), "white", bg)
      put(term, w - #count, 2 + i, count .. " ", sel and "white" or "lightGray", bg)
    end
  end
  if #list == 0 then put(term, 2, 4, query == "" and "Nothing stored yet." or "No matches.", "lightGray") end

  put(term, 1, h - 1, fitText(message[1], w), message[2])
  put(term, 1, h, fitText("Enter: a stack  Right: one  Up/Down: pick", w), "gray")
  term.setCursorPos(9 + #query, 2)
  term.setTextColor(colors.white)
  term.setCursorBlink(true)
end

local function drawMonitor()
  local mon = peripheral.find("monitor")
  if not mon then return end
  mon.setTextScale(MONITOR_SCALE)
  local w, h = mon.getSize()
  local list, used, slots = totals()
  mon.setBackgroundColor(colors.black)
  mon.clear()
  put(mon, 1, 1, (" "):rep(w), "white", "gray")
  put(mon, 2, 1, "Storage", "yellow", "gray")
  -- how full it is, as a bar
  local frac = slots > 0 and used / slots or 0
  local barW = w - 2
  local filled = math.floor(frac * barW + 0.5)
  local barColour = frac > 0.9 and "red" or frac > 0.7 and "orange" or "green"
  put(mon, 2, 3, (" "):rep(filled), "white", barColour)
  put(mon, 2 + filled, 3, (" "):rep(barW - filled), "white", "gray")
  put(mon, 2, 4, ("%d%% full, %d/%d slots in %d chests"):format(math.floor(frac * 100), used, slots, #stores), "lightGray")
  for i = 1, h - 5 do
    local it = list[i]
    if not it then break end
    local count = tostring(it.count)
    put(mon, 2, 5 + i, fitText(it.displayName, w - #count - 3), "white")
    put(mon, w - #count, 5 + i, count, "lightGray")
  end
end

local function redraw()
  drawTerminal()
  drawMonitor()
  if report then
    local list, used, slots = totals()
    local items = 0
    for _, it in ipairs(list) do items = items + it.count end
    report.set("running", ("%d items, %d/%d slots"):format(items, used, slots))
  end
end

---------------------------------------------------------------- loops

local function take(amount)
  local list = matches()
  local it = list[selected]
  if not it then return end
  local sent = fetch(function(item) return keyOf(item) == it.key end, amount, setup.output)
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

local function nameOf(item) return details[item] and details[item].displayName or shortName(item) end

-- Every plain item in storage, minus what queued crafts will use up, plus
-- what they'll make: what a new plan can count on.
local function planningStock()
  local avail = {}
  for _, store in ipairs(stores) do
    for _, item in pairs(contents[store] or {}) do
      if not item.nbt then avail[item.name] = (avail[item.name] or 0) + item.count end
    end
  end
  for _, job in ipairs(craftQueue) do
    for _, item in pairs(job.grid) do avail[item] = (avail[item] or 0) - job.steps end
    avail[job.name] = (avail[job.name] or 0) + job.steps * job.recipe.count
  end
  return avail
end

-- Queue the crafts that make count of name. Returns true if it can be done,
-- or false and why not.
local function orderCraft(name, count)
  if not crafting then return false, "crafting.lua is missing: run 'install update'" end
  if not crafting.canMake(name) then return false, "no recipe for it" end
  if not setup.crafter then return false, "no crafter chest: run 'storage setup'" end
  local jobs = crafting.plan(name, count, planningStock())
  if not jobs then return false, "not enough to make it from" end
  planCount = planCount + 1
  for _, job in ipairs(jobs) do
    job.plan = planCount
    craftQueue[#craftQueue + 1] = job
  end
  jobs[#jobs].top = count -- the item asked for: counted in pendingCraft until it's made
  pendingCraft[name] = (pendingCraft[name] or 0) + count
  os.queueEvent("storage_craft")
  return true
end

-- Put away anything in the crafter chest.
local function clearCrafter()
  local ok, list = pcall(peripheral.call, setup.crafter, "list")
  if not ok then return end
  for slot, item in pairs(list) do putAway(setup.crafter, slot, item, item.count) end
end

local crafterId -- the crafting turtle, once found
local jobId = 0

-- One job: in batches that fit the turtle, put the ingredients in the
-- crafter chest (grid cell k in chest slot k), have the turtle craft, and
-- put the results away.
local function runJob(job)
  local r = job.recipe
  local left = job.steps
  while left > 0 do
    local batch = math.min(left, 64, math.floor(MAX_BATCH_OUTPUT / r.count))
    for _, item in pairs(job.grid) do
      batch = math.min(batch, details[item] and details[item].maxCount or 64)
    end
    batch = math.max(1, batch)
    clearCrafter()
    for k = 1, 9 do
      local item = job.grid[k]
      if item then
        local got, err = fetch(function(it) return it.name == item and not it.nbt end, batch, setup.crafter, k)
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
      return false, "the crafting turtle didn't answer"
    end
    if (reply.made or 0) == 0 then return false, reply.error or "the recipe didn't work" end
    left = left - batch
  end
  return true
end

local function craftLoop()
  while true do
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
--   { type = "learn", recipe = { make, count, rows, keys } } -> { re = "learn", ok }  (from 'crafter learn')
-- count also answers craftable (how many more could be crafted), and deliver
-- answers crafting (how many it has started making).
-- Items with extra data (enchantments, names) are never counted or sent.
local function plain(name) return function(item) return item.name == name and not item.nbt end end

local function countPlain(names)
  local counts = {}
  for _, n in ipairs(names) do counts[n] = 0 end
  for _, store in ipairs(stores) do
    for _, item in pairs(contents[store] or {}) do
      if counts[item.name] and not item.nbt then counts[item.name] = counts[item.name] + item.count end
    end
  end
  return counts
end

local function netLoop()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then
    message = { "No wireless modem: turtles can't ask me for items.", "orange" }
    os.queueEvent("storage_changed")
    while true do sleep(3600) end
  end
  local side = peripheral.getName(modem)
  if not rednet.isOpen(side) then rednet.open(side) end
  rednet.host(NET_PROTOCOL, os.getComputerLabel() or ("storage-" .. os.getComputerID()))
  while true do
    local from, msg = rednet.receive(NET_PROTOCOL)
    if type(msg) == "table" and msg.type == "count" and type(msg.items) == "table" then
      local craftable = {}
      if crafting and setup.crafter then
        local avail = planningStock()
        for _, name in ipairs(msg.items) do
          if type(name) == "string" then craftable[name] = crafting.craftable(name, avail) + (pendingCraft[name] or 0) end
        end
      end
      rednet.send(from, { re = "count", counts = countPlain(msg.items), craftable = craftable }, NET_PROTOCOL)
    elseif type(msg) == "table" and msg.type == "prepare" and type(msg.items) == "table" then
      -- a turtle waiting for materials: start crafting what it'll need,
      -- beyond what's stored and what's already being made
      local stock, making, cantCraft = planningStock(), {}, {}
      for name, n in pairs(msg.items) do
        if type(name) == "string" and type(n) == "number" then
          local missing = math.floor(n) - math.max(0, stock[name] or 0) - (pendingCraft[name] or 0)
          if missing > 0 then
            local okC, why = orderCraft(name, missing)
            if okC then making[name] = missing else cantCraft[name] = why end
            stock = planningStock()
          end
          if (pendingCraft[name] or 0) > 0 then making[name] = pendingCraft[name] end
        end
      end
      rednet.send(from, { re = "prepare", crafting = making, cantCraft = cantCraft }, NET_PROTOCOL)
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
      rednet.send(from, { re = "learn", ok = okL and true or false, error = not okL and err or nil }, NET_PROTOCOL)
      if okL then message = { ("Learnt how to make %s."):format(nameOf(msg.recipe.make)), "lime" } end
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
            sent[name], err = fetch(plain(name), n - have, to)
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
          local okC, why = orderCraft(name, missing)
          if okC then making[name] = missing else cantCraft[name] = why end
        end
        if (pendingCraft[name] or 0) > 0 then making[name] = pendingCraft[name] end
      end
      rednet.send(from, { re = "deliver", sent = sent, ready = ready, stock = countPlain(names), crafting = making,
        cantCraft = cantCraft, to = setup.delivery and "delivery" or "output", error = failed }, NET_PROTOCOL)
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
  end
end

local function rescanLoop()
  while true do
    sleep(RESCAN_EVERY)
    scanAll()
    os.queueEvent("storage_changed")
  end
end

---------------------------------------------------------------- setup

local function chooseChests()
  local invs = {}
  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) then invs[#invs + 1] = name end
  end
  table.sort(invs)
  if #invs < 3 then
    print("I can only see " .. #invs .. " chests. I need at least three on the")
    print("network: an input, an output, and one or more for storage.")
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
  local function ask(prompt, taken, optional)
    while true do
      write(prompt)
      local text = read()
      if optional and text == "" then return nil end
      local n = tonumber(text)
      if n and invs[n] and not taken[invs[n]] then return invs[n] end
      print("Type one of the numbers above" .. (optional and ", or just Enter." or "."))
    end
  end
  local s = {}
  s.input = ask("Which is the input chest? ", {})
  s.output = ask("Which is the output chest? ", { [s.input] = true })
  print("Turtles (like the village builder) can have items sent to")
  print("their own chest. Leave it blank to use the output chest.")
  s.delivery = ask("Which is the delivery chest? [none] ", { [s.input] = true, [s.output] = true }, true)
  print("A crafting turtle can make what's asked for but not stored.")
  print("Its chest sits in front of it. Leave blank if there isn't one.")
  local taken = { [s.input] = true, [s.output] = true }
  if s.delivery then taken[s.delivery] = true end
  s.crafter = ask("Which is the crafter chest? [none] ", taken, true)
  local f = fs.open(SETUP_FILE, "w")
  f.write(textutils.serialize(s))
  f.close()
  print("Saved. Every other chest is storage.")
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
for _, which in ipairs({ "input", "output", "delivery", "crafter" }) do
  if setup[which] and not peripheral.isPresent(setup[which]) then
    print(("Can't find the %s chest (%s). Check its modem is red, or run 'storage setup'."):format(which, setup[which]))
    return
  end
end

print("Scanning chests...")
scanAll()

-- 'storage test': move one item into the delivery (or output) chest and back,
-- and say what went wrong if it can't.
if args[1] == "test" then
  local to = setup.delivery or setup.output
  print(("Testing a move into the %s chest (%s)..."):format(setup.delivery and "delivery" or "output", to))
  local pick
  for _, it in ipairs((totals())) do
    if not it.key:find("#", 1, true) then pick = it break end
  end
  if not pick then
    print("Storage is empty: put something in the input chest first.")
    return
  end
  local sent, err = fetch(function(item) return keyOf(item) == pick.key end, 1, to)
  if sent > 0 then
    print(("OK: moved 1 %s there."):format(pick.displayName))
    local okL, list = pcall(peripheral.call, to, "list")
    for slot, item in pairs(okL and list or {}) do
      if keyOf(item) == pick.key then
        putAway(to, slot, item, 1)
        break
      end
    end
    print("Moved it back. Deliveries work.")
  else
    print("Couldn't move it: " .. (err or "that chest is full"))
    print("Check its modem is red and joined by cable to the storage chests.")
  end
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

if report then report.init("storage") end
local ok, err = pcall(parallel.waitForAny, uiLoop, inputLoop, rescanLoop, netLoop, sweepLoop, craftLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
