-- Digital Miner manager for Mekanism. Every Digital Miner on this
-- computer's wired network on one monitor: what each is doing, blocks left,
-- radius, Y range and power. Tap a miner to start, stop or reset it, change
-- its radius and Y range, silk touch and auto eject, and add or remove
-- filters. Mined items go wherever the miner ejects them: put the storage
-- system's input chest (or a pipe to it) at the miner's eject port.
--
--   dminer                          start the monitor (startup.lua runs it)
--   dminer list                     every miner with its number
--   dminer start <n|all>            start a miner, or all of them
--   dminer stop <n|all>             stop (pause) a miner, or all of them
--   dminer reset <n>                reset a miner so its settings can change
--   dminer filter <n>               list a miner's filters
--   dminer filter <n> add tag c:ores        mine a tag (also: item <name>, mod <id>)
--   dminer filter <n> remove <i>    remove filter number i
--
-- Mekanism only takes orders from a computer when the miner's security is
-- set to Public.
local screen = require("lib.screen") -- flicker-free drawing
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local config = fs.exists("config.lua") and require("config") or {}

local REFRESH = 2 -- seconds between reads
local MONITOR_SCALE = 0.5 -- text size on the monitor (0.5 fits the most)
local UNIT = config.unit or "FE" -- "FE" or "J"
local JOULES_PER_FE = config.joulesPerFE or 2.5 -- Mekanism's default conversion rate
local AUTO_EJECT = config.autoEject ~= false -- turn Auto Eject on for every miner at start
local PRESETS = config.presets or { "c:ores" } -- tags offered as one-tap filters
local NAMES = config.names or {} -- peripheral name -> name shown
local RADIUS_STEPS = { { "-8", -8 }, { "-1", -1 }, { "+1", 1 }, { "+8", 8 } }
local Y_STEPS = { { "-16", -16 }, { "-1", -1 }, { "+1", 1 }, { "+16", 16 } }

local READS = {
  "isRunning", "getState", "getToMine", "getRadius", "getMaxRadius", "getMinY", "getMaxY",
  "getSilkTouch", "getAutoEject", "getEnergyFilledPercentage", "getEnergyUsage", "getFilters",
}

local miners = {} -- { name, title, values }, in a fixed order
local ui = { page = nil, zones = {}, msg = nil, msgColour = "white" } -- page: a miner's name, or nil for the list

---------------------------------------------------------------- miners

local function findMiners()
  local names = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "digitalMiner" then names[#names + 1] = name end
  end
  table.sort(names)
  local old = {}
  for _, m in ipairs(miners) do old[m.name] = m end
  miners = {}
  for i, name in ipairs(names) do
    miners[i] = old[name] or { name = name, values = {} }
    miners[i].title = NAMES[name] or ("Miner " .. i)
  end
end

-- Mekanism runs each method on the game's main thread, one tick per call, so
-- every call for every miner is started at once and they finish together.
local function readAll()
  local jobs = {}
  for _, m in ipairs(miners) do
    local values = {}
    m.next = values
    for _, method in ipairs(READS) do
      jobs[#jobs + 1] = function()
        local ok, value = pcall(peripheral.call, m.name, method)
        if ok then values[method] = value end
      end
    end
  end
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
  for _, m in ipairs(miners) do m.values, m.next = m.next, nil end
end

-- Mekanism hands filters over as objects with getter methods. This turns
-- them into plain tables in the shape addFilter / removeFilter take (and
-- that can be compared and saved), all miners' filters in one go.
local FILTER_GETTERS = {
  type = "getFilterType", enabled = "isEnabled", tag = "getTagName", modid = "getModID",
  replace_target = "getReplaceTarget", requires_replacement = "getRequiresReplacement", item = "getItemStack",
}

local function plainFilters()
  local jobs = {}
  for _, m in ipairs(miners) do
    local raw = m.values.getFilters
    m.values.getFilters = nil
    m.values.filters = {}
    for i, f in ipairs(type(raw) == "table" and raw or {}) do
      local plain = {}
      m.values.filters[i] = plain
      for field, getter in pairs(FILTER_GETTERS) do
        if type(f[getter]) == "function" then
          jobs[#jobs + 1] = function()
            local ok, value = pcall(f[getter])
            if ok then plain[field] = field == "item" and type(value) == "table" and value.name or value end
          end
        elseif f[field] ~= nil then
          plain[field] = f[field] -- already plain
        end
      end
    end
  end
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
  for _, m in ipairs(miners) do
    for _, f in ipairs(m.values.filters) do
      if f.item == "minecraft:air" then f.item = nil end
    end
  end
end

local function minerByName(name)
  for _, m in ipairs(miners) do if m.name == name then return m end end
end

-- Mekanism's own error ("Requires miner to be stopped/reset first" etc.), without the position.
local function call(m, method, ...)
  local ok, err = pcall(peripheral.call, m.name, method, ...)
  if ok then return true end
  return false, (tostring(err):gsub("^.-:%d+: ", ""))
end

---------------------------------------------------------------- text helpers

local function int(n) return math.floor((n or 0) + 0.5) end
local function pct(f) return f and ("%d%%"):format(int(f * 100)) or "?" end

local function energy(j)
  if not j then return "?" end
  local n = UNIT == "J" and j or j / JOULES_PER_FE
  local units = { "", "k", "M", "G" }
  local i = 1
  while math.abs(n) >= 1000 and i < #units do n, i = n / 1000, i + 1 end
  return (i == 1 and ("%d "):format(int(n)) or ("%.1f %s"):format(n, units[i])) .. UNIT .. "/t"
end

-- What a miner is doing, as a word and colour.
local function stateOf(v)
  if v.getState == nil then return "offline", "red" end
  if v.isRunning then
    if (v.getEnergyFilledPercentage or 1) < 0.01 then return "no power", "red" end
    return v.getState == "SEARCHING" and "searching" or "mining", "lime"
  end
  if v.getState == "FINISHED" then return "finished", "green" end
  if v.getState == "PAUSED" then return "stopped", "orange" end
  if v.getState == "SEARCHING" then return "searching", "yellow" end
  return "idle", "lightGray"
end

local function filterText(f)
  local what = f.tag and ("tag " .. f.tag) or f.item and ("item " .. f.item) or f.modid and ("mod " .. f.modid) or tostring(f.type)
  if f.enabled == false then what = what .. " (off)" end
  if f.replace_target and f.replace_target ~= "minecraft:air" then what = what .. ", replace with " .. f.replace_target end
  return what
end

local function newFilter(kind, value)
  if kind == "tag" then return { type = "MINER_TAG_FILTER", tag = value, enabled = true } end
  if kind == "item" then return { type = "MINER_ITEMSTACK_FILTER", item = value, enabled = true } end
  if kind == "mod" then return { type = "MINER_MODID_FILTER", modid = value, enabled = true } end
end

local fit = screen.fit

---------------------------------------------------------------- acting

local function say(text, colour) ui.msg, ui.msgColour = text, colour or "white" end

local function act(m, method, ...)
  local ok, err = call(m, method, ...)
  if ok then return true end
  say(("%s: %s"):format(m.title, err), "orange")
  return false
end

local function all(method)
  local done = 0
  for _, m in ipairs(miners) do
    if act(m, method) then done = done + 1 end
  end
  if done == #miners then say(("%s sent to %d miners."):format(method == "start" and "Start" or "Stop", done), "lime") end
end

local function change(m, label, getter, setter, step, low, high)
  local value = (m.values[getter] or 0) + step
  value = math.max(low or -math.huge, math.min(high or math.huge, value))
  if act(m, setter, value) then
    m.values[getter] = value
    say(("%s: %s set to %d."):format(m.title, label, value), "white")
  end
end

---------------------------------------------------------------- drawing

local display -- lib/screen.lua on the monitor, or this computer's screen
local win

local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end

local function button(x, y, label, fg, bg, action)
  local text = " " .. label .. " "
  put(x, y, text, fg, bg)
  ui.zones[#ui.zones + 1] = { x1 = x, x2 = x + #text - 1, y = y, action = action }
  return x + #text + 1
end

local function rowZone(y, w, action) ui.zones[#ui.zones + 1] = { x1 = 1, x2 = w, y = y, action = action } end

local function stepButtons(x, y, steps, fn)
  for _, s in ipairs(steps) do x = button(x, y, s[1], "white", "gray", function() fn(s[2]) end) end
  return x
end

local function drawList(w, h)
  put(1, 1, (" "):rep(w), "white", "gray")
  put(2, 1, fit(("Digital Miners (%d)"):format(#miners), w - 2), "yellow", "gray")
  if #miners == 0 then
    put(2, 3, "No Digital Miner found.", "red")
    put(2, 5, fit("Put a wired modem on each miner, join them to this", w - 2))
    put(2, 6, fit("computer with networking cable and right-click each", w - 2))
    put(2, 7, fit("modem so it turns red.", w - 2))
    return
  end
  local x = button(2, 2, "Start all", "white", "green", function() all("start") end)
  button(x, 2, "Stop all", "white", "red", function() all("stop") end)
  put(2, 4, fit("Miner", 12), "yellow")
  put(15, 4, fit("State", 9), "yellow")
  put(25, 4, fit("Left", 7), "yellow")
  put(33, 4, fit("Rad", 3), "yellow")
  put(37, 4, fit("Y", 9), "yellow")
  put(47, 4, "Power", "yellow")
  local y = 5
  for i, m in ipairs(miners) do
    if y > h - 1 then
      put(2, h - 1, ("+%d more"):format(#miners - i + 1), "lightGray")
      break
    end
    local v = m.values
    local word, colour = stateOf(v)
    put(2, y, fit(m.title, 12), "white")
    put(15, y, fit(word, 9), colour)
    put(25, y, fit(tostring(v.getToMine or "?"), 7), "white")
    put(33, y, fit(tostring(v.getRadius or "?"), 3), "lightGray")
    put(37, y, fit(("%s..%s"):format(v.getMinY or "?", v.getMaxY or "?"), 9), "lightGray")
    put(47, y, fit(pct(v.getEnergyFilledPercentage), w - 46), (v.getEnergyFilledPercentage or 1) < 0.1 and "red" or "white")
    rowZone(y, w, function() ui.page = m.name; say(nil) end)
    y = y + 1
  end
  if ui.msg then put(2, h, fit(ui.msg, w - 2), ui.msgColour)
  else put(2, h, fit("Tap a miner to control it.", w - 2), "gray") end
end

local function drawMiner(m, w, h)
  local v = m.values
  local word, colour = stateOf(v)
  put(1, 1, (" "):rep(w), "white", "gray")
  button(1, 1, "<", "white", "lightGray", function() ui.page = nil; say(nil) end)
  put(5, 1, fit(m.title, w - 16), "yellow", "gray")
  put(w - #word, 1, word, colour, "gray")

  put(2, 3, fit(("Left %s blocks   Radius %s/%s   Y %s..%s"):format(
    v.getToMine or "?", v.getRadius or "?", v.getMaxRadius or "?", v.getMinY or "?", v.getMaxY or "?"), w - 2), "white")
  put(2, 4, fit(("Power %s, using %s"):format(pct(v.getEnergyFilledPercentage), energy(v.getEnergyUsage)), w - 2), "lightGray")

  local x = button(2, 6, "Start", "white", "green", function() if act(m, "start") then say(m.title .. " started.", "lime") end end)
  x = button(x, 6, "Stop", "white", "red", function() if act(m, "stop") then say(m.title .. " stopped.", "orange") end end)
  x = button(x, 6, "Reset", "black", "yellow", function() if act(m, "reset") then say(m.title .. " reset: settings can change now.", "white") end end)
  x = button(x + 1, 6, "Silk " .. (v.getSilkTouch and "on" or "off"), "white", v.getSilkTouch and "green" or "gray",
    function() if act(m, "setSilkTouch", not v.getSilkTouch) then v.getSilkTouch = not v.getSilkTouch end end)
  button(x, 6, "Eject " .. (v.getAutoEject and "on" or "off"), "white", v.getAutoEject and "green" or "gray",
    function() if act(m, "setAutoEject", not v.getAutoEject) then v.getAutoEject = not v.getAutoEject end end)

  put(2, 8, "Radius", "lightGray")
  stepButtons(9, 8, RADIUS_STEPS, function(s) change(m, "radius", "getRadius", "setRadius", s, 1, v.getMaxRadius) end)
  put(2, 9, "Min Y", "lightGray")
  stepButtons(9, 9, Y_STEPS, function(s) change(m, "min Y", "getMinY", "setMinY", s, nil, v.getMaxY) end)
  put(2, 10, "Max Y", "lightGray")
  stepButtons(9, 10, Y_STEPS, function(s) change(m, "max Y", "getMaxY", "setMaxY", s, v.getMinY, nil) end)

  local filters = v.filters or {}
  put(2, 12, ("Filters (%d)"):format(#filters), "yellow")
  local y = 13
  for i, f in ipairs(filters) do
    if y > h - 3 then
      put(2, y, ("+%d more: see 'dminer filter'"):format(#filters - i + 1), "lightGray")
      y = y + 1
      break
    end
    button(2, y, "x", "white", "red", function()
      if act(m, "removeFilter", f) then say("Filter removed.", "white") end
    end)
    put(6, y, fit(filterText(f), w - 6), "white")
    y = y + 1
  end
  if #filters == 0 then
    put(2, y, "None: it mines everything it finds.", "lightGray")
    y = y + 1
  end
  x = 2
  for _, tag in ipairs(PRESETS) do
    local have = false
    for _, f in ipairs(filters) do if f.tag == tag then have = true end end
    if not have and x + #tag + 4 <= w then
      x = button(x, h - 1, "+ " .. tag, "white", "blue", function()
        if act(m, "addFilter", newFilter("tag", tag)) then say(("Added tag %s."):format(tag), "lime") end
      end)
    end
  end
  if ui.msg then put(2, h, fit(ui.msg, w - 2), ui.msgColour)
  else put(2, h, fit("Settings and filters change after Reset.", w - 2), "gray") end
end

local function draw()
  local keyParts = { tostring(ui.page), tostring(ui.msg), #miners }
  for _, m in ipairs(miners) do
    keyParts[#keyParts + 1] = m.title .. ":" .. textutils.serialize(m.values, { compact = true })
  end
  if display:same(table.concat(keyParts, "|")) then return end

  ui.zones = {}
  local w, h
  win, w, h = display:frame()
  local m = ui.page and minerByName(ui.page)
  if m then drawMiner(m, w, h) else
    ui.page = nil
    drawList(w, h)
  end
  display:show()
end

---------------------------------------------------------------- loops

local function summary()
  local running, left, finished = 0, 0, 0
  for _, m in ipairs(miners) do
    if m.values.isRunning then running = running + 1 end
    if m.values.getState == "FINISHED" then finished = finished + 1 end
    left = left + (m.values.getToMine or 0)
  end
  return running, left, finished
end

local function refresh()
  readAll()
  plainFilters()
  draw()
  if report then
    local running, left, finished = summary()
    local state = #miners == 0 and "waiting" or running > 0 and "mining" or finished == #miners and "done" or "idle"
    report.set(state, #miners == 0 and "no Digital Miner found"
      or ("%d of %d mining, %d blocks left"):format(running, #miners, left))
  end
end

local function refreshLoop()
  while true do
    local ok, err = (errlog and errlog.pcall or pcall)(refresh)
    if not ok then say("Read failed: " .. tostring(err), "red") end
    sleep(REFRESH)
  end
end

local function announce()
  if not display.name then return end
  term.clear()
  term.setCursorPos(1, 1)
  print("Digital Miner manager running on the monitor.")
  print("Hold Ctrl+T to stop.")
end

local function setAutoEject()
  if not AUTO_EJECT then return end
  for _, m in ipairs(miners) do
    local ok, eject = pcall(peripheral.call, m.name, "getAutoEject")
    if ok and eject == false then
      local set, err = call(m, "setAutoEject", true)
      if not set then print(("%s: can't turn Auto Eject on (%s)"):format(m.title, err)) end
    end
  end
end

local function touchLoop()
  while true do
    local ev = { os.pullEvent() }
    local event = ev[1]
    local x, y, drag = display:clicked(ev)
    if x and not drag then
      for _, z in ipairs(ui.zones) do
        if y == z.y and x >= z.x1 and x <= z.x2 then
          z.action()
          draw()
          break
        end
      end
    elseif event == "peripheral" or event == "peripheral_detach" then
      findMiners()
      if event == "peripheral" then setAutoEject() end
      if display:refresh() then announce() end
      draw()
    elseif event == "monitor_resize" or event == "term_resize" then
      draw()
    end
  end
end

local function run()
  display = screen.find({ setting = "dminer.monitor", scales = { MONITOR_SCALE }, fallback = term.current() })
  announce()
  setAutoEject()
  if report then report.init("digital miners") end
  if errlog then errlog.init("dminer") end
  local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, refreshLoop, touchLoop,
    report and report.loop or function() sleep(math.huge) end)
  if not ok then
    if report then pcall(report.set, "error", tostring(err)) end
    error(err, 0)
  end
end

---------------------------------------------------------------- commands

local function pick(arg)
  local n = tonumber(arg)
  local m = n and miners[n]
  if not m then
    print(("No miner %s. 'dminer list' shows their numbers."):format(tostring(arg)))
  end
  return m
end

local function listMiners()
  readAll()
  if #miners == 0 then return print("No Digital Miner found on this computer's network.") end
  for i, m in ipairs(miners) do
    local v = m.values
    print(("%d  %s (%s): %s, %s blocks left, radius %s, Y %s..%s"):format(i, m.title, m.name,
      (stateOf(v)), tostring(v.getToMine or "?"), tostring(v.getRadius or "?"), tostring(v.getMinY or "?"), tostring(v.getMaxY or "?")))
  end
end

local function command(args)
  local cmd = args[1]
  if cmd == "list" then return listMiners() end
  if cmd == "start" or cmd == "stop" then
    local targets = args[2] == "all" and miners or { pick(args[2]) }
    for _, m in ipairs(targets) do
      local ok, err = call(m, cmd)
      print(ok and ("%s: %s."):format(m.title, cmd == "start" and "started" or "stopped") or ("%s: %s"):format(m.title, err))
    end
    return
  end
  if cmd == "reset" then
    local m = pick(args[2])
    if not m then return end
    local ok, err = call(m, "reset")
    return print(ok and (m.title .. ": reset.") or (m.title .. ": " .. err))
  end
  if cmd == "filter" then
    local m = pick(args[2])
    if not m then return end
    if args[3] == "add" then
      local filter = newFilter(args[4], args[5])
      if not (filter and args[5]) then return print("Usage: dminer filter <n> add tag|item|mod <name>") end
      local ok, err = call(m, "addFilter", filter)
      return print(ok and ("Added %s %s."):format(args[4], args[5]) or err)
    end
    readAll()
    plainFilters()
    local filters = m.values.filters
    if args[3] == "remove" then
      local f = filters[tonumber(args[4] or "")]
      if not f then return print("No such filter. 'dminer filter " .. args[2] .. "' lists them.") end
      local done, err = call(m, "removeFilter", f)
      return print(done and "Removed." or err)
    end
    if m.values.getState == nil then return print(m.title .. " isn't answering.") end
    if #filters == 0 then return print(m.title .. " has no filters: it mines everything it finds.") end
    for i, f in ipairs(filters) do print(("%d  %s"):format(i, filterText(f))) end
    return
  end
  print("Usage: dminer [list | start <n|all> | stop <n|all> | reset <n> | filter <n> [add tag|item|mod <name> | remove <i>]]")
end

local args = { ... }
findMiners()
if #args == 0 then run() else command(args) end
