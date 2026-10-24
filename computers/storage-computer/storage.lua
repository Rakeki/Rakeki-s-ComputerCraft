-- Storage system. Every chest and barrel on the wired modem network becomes
-- one big store. Drop items in the input chest and they get put away; type
-- to search on the terminal and press Enter to have a stack sent to the
-- output chest. A monitor, if attached, shows what's stored most.
--
-- With a wireless modem too, turtles can ask it over rednet how much of an
-- item is stored and have it sent to a delivery chest (the village builder
-- uses this to stock its supply chest).
--
--   storage          start (asks which chest is input and output the first time)
--   storage setup    choose the input, output and delivery chests again
--
-- Connect the computer and every chest with networking cable and wired
-- modems: a full-block wired modem touching each chest (small modems only go
-- on full blocks like barrels). Right-click each modem so it turns red.
local report = fs.exists("lib/report.lua") and require("lib.report")

local SETUP_FILE = "/.storage_setup"

local INPUT_EVERY = 2 -- seconds between checks of the input chest
local RESCAN_EVERY = 60 -- seconds between full rescans (catches items moved by hand)
local MONITOR_SCALE = 0.5 -- text size on the monitor
local NET_PROTOCOL = "storage" -- rednet protocol turtles ask for items on

-- Inventories that count as storage, matched against the peripheral type
-- (e.g. "minecraft:chest"). Furnaces, hoppers and turtles never do.
local STORAGE_TYPES = { "chest", "barrel", "shulker_box", "crate", "drawer" }

local setup -- { input = name, output = name, delivery = name or nil }
local stores = {} -- peripheral names of the storage inventories
local contents = {} -- store name -> its list() result
local sizes = {} -- store name -> number of slots
local details = {} -- item key -> { name, displayName }
local message = { "", "lightGray" } -- shown in the footer

---------------------------------------------------------------- inventories

local function isInventory(name)
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t == "inventory" then return true end
  end
  return false
end

local function isStorage(name)
  if name == setup.input or name == setup.output or name == setup.delivery then return false end
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
      details[key] = { name = item.name, displayName = okD and d and d.displayName or shortName(item.name) }
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
local function storeInput()
  local ok, list = pcall(peripheral.call, setup.input, "list")
  if not ok or not next(list) then return false end
  local full = false
  for slot, item in pairs(list) do
    local key, left = keyOf(item), item.count
    local order = {}
    for _, name in ipairs(stores) do
      for _, have in pairs(contents[name] or {}) do
        if keyOf(have) == key then order[#order + 1] = name break end
      end
    end
    for _, name in ipairs(stores) do order[#order + 1] = name end
    for _, name in ipairs(order) do
      local okP, moved = pcall(peripheral.call, setup.input, "pushItems", name, slot, left)
      if okP and moved > 0 then
        left = left - moved
        rescan(name)
      end
      if left <= 0 then break end
    end
    if left > 0 then full = true end
  end
  if full then
    message = { "Storage is full: some items are still in the input chest.", "red" }
    if report then report.log("storage full") end
  end
  return true
end

-- Send up to amount of the items matching match(item) to the chest named to.
-- Returns how many went.
local function fetch(match, amount, to)
  local sent = 0
  for _, name in ipairs(stores) do
    for slot, item in pairs(contents[name] or {}) do
      if match(item) then
        local ok, moved = pcall(peripheral.call, to, "pullItems", name, slot, amount - sent)
        if ok then sent = sent + moved end
        if not ok or moved == 0 then
          rescan(name)
          return sent -- that chest is full
        end
        if sent >= amount then break end
      end
    end
    rescan(name)
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

-- Requests from turtles over rednet:
--   { type = "count", items = { name, ... } }      -> { re = "count", counts = { [name] = n } }
--   { type = "deliver", items = { [name] = n } }   -> { re = "deliver", sent = { [name] = n } }
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
    while true do sleep(3600) end
  end
  local side = peripheral.getName(modem)
  if not rednet.isOpen(side) then rednet.open(side) end
  rednet.host(NET_PROTOCOL, os.getComputerLabel() or ("storage-" .. os.getComputerID()))
  while true do
    local from, msg = rednet.receive(NET_PROTOCOL)
    if type(msg) == "table" and msg.type == "count" and type(msg.items) == "table" then
      rednet.send(from, { re = "count", counts = countPlain(msg.items) }, NET_PROTOCOL)
    elseif type(msg) == "table" and msg.type == "deliver" and type(msg.items) == "table" then
      local to, sent, total = setup.delivery or setup.output, {}, 0
      for name, n in pairs(msg.items) do
        if type(name) == "string" and type(n) == "number" and n > 0 then
          sent[name] = fetch(plain(name), math.floor(n), to)
          total = total + sent[name]
        end
      end
      rednet.send(from, { re = "deliver", sent = sent }, NET_PROTOCOL)
      if total > 0 then
        message = { ("Sent %d items to turtle #%d."):format(total, from), "lightBlue" }
        if report then report.log(("sent %d items to turtle #%d"):format(total, from)) end
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
for _, which in ipairs({ "input", "output", "delivery" }) do
  if setup[which] and not peripheral.isPresent(setup[which]) then
    print(("Can't find the %s chest (%s). Check its modem is red, or run 'storage setup'."):format(which, setup[which]))
    return
  end
end

print("Scanning chests...")
scanAll()
term.clear()

if report then report.init("storage") end
local ok, err = pcall(parallel.waitForAny, uiLoop, inputLoop, rescanLoop, netLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
