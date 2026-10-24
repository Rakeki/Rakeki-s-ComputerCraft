-- MineColonies dashboard. Reads your colony through an Advanced Peripherals
-- Colony Integrator and shows it on a monitor: citizens, happiness, buildings,
-- open requests and builder work orders, with a warning when it's under
-- attack. Tap the tabs along the top to switch pages.
--
--   colony           start the dashboard (startup.lua runs it)
--
-- The computer and its Colony Integrator must be inside the colony's borders.
-- Without a monitor it draws on the computer's own screen (click instead of tap).
local report = fs.exists("lib/report.lua") and require("lib.report")

local REFRESH = 5 -- seconds between reads of the colony
local MONITOR_SCALE = 0.5 -- text size on the monitor (0.5 fits the most)
local HUNGRY_BELOW = 5 -- saturation (out of 20) counted as hungry
local ALARM = true -- play a sound on a speaker (if there is one) while under attack

local TABS = { "Overview", "Citizens", "Buildings", "Requests", "Builds" }
local SHORT_TABS = { "Home", "People", "Huts", "Needs", "Builds" } -- on narrow screens

local colony -- the Colony Integrator
local data = {} -- latest read of the colony
local ui = { tab = 1, scroll = 0, zones = {} }

---------------------------------------------------------------- reading the colony

local function call(method, ...)
  local ok, value = pcall(colony[method], ...)
  if ok then return value end
end

local function read()
  local d = { inColony = call("isInColony") }
  if not d.inColony then return d end
  d.name = call("getColonyName") or "Colony"
  d.id = call("getColonyID")
  d.happiness = call("getHappiness") or 0
  d.attack = call("isUnderAttack") or false
  d.active = call("isActive")
  d.citizenCount = call("amountOfCitizens") or 0
  d.citizenMax = call("maxOfCitizens") or 0
  d.graves = call("amountOfGraves") or 0
  d.sites = call("amountOfConstructionSites") or 0
  d.citizens = call("getCitizens") or {}
  d.buildings = call("getBuildings") or {}
  d.requests = call("getRequests") or {}
  d.orders = call("getWorkOrders") or {}
  d.location = call("getLocation")

  table.sort(d.citizens, function(a, b) return (a.name or "") < (b.name or "") end)
  table.sort(d.buildings, function(a, b)
    if (a.type or "") ~= (b.type or "") then return (a.type or "") < (b.type or "") end
    return (a.level or 0) > (b.level or 0)
  end)
  table.sort(d.orders, function(a, b) return (a.priority or 0) > (b.priority or 0) end)

  d.idle, d.asleep, d.hungry, d.hurt = 0, 0, 0, 0
  for _, c in ipairs(d.citizens) do
    if c.isIdle then d.idle = d.idle + 1 end
    if c.isAsleep then d.asleep = d.asleep + 1 end
    if (c.saturation or 20) < HUNGRY_BELOW then d.hungry = d.hungry + 1 end
    if c.health and c.maxHealth and c.health < c.maxHealth / 2 then d.hurt = d.hurt + 1 end
  end
  return d
end

---------------------------------------------------------------- text helpers

-- "minecolonies:blacksmith" -> "Blacksmith"
local function pretty(s)
  s = tostring(s or ""):gsub("^[%w_]+:", ""):gsub("[_%.]", " ")
  return (s:gsub("^%l", string.upper))
end

local function fit(text, w)
  text = tostring(text or "")
  if w <= 0 then return "" end
  if #text > w then return text:sub(1, w) end
  return text .. (" "):rep(w - #text)
end

local function jobOf(c)
  if c.work and c.work.job then return pretty(c.work.job) end
  if c.work and c.work.type then return pretty(c.work.type) end
  return "Unemployed"
end

local function requestItem(r)
  local item = r.items and r.items[1]
  return item and (item.displayName or pretty(item.name)) or r.name or r.desc or "?"
end

---------------------------------------------------------------- drawing

local screen -- the monitor, or term

local function put(x, y, text, fg, bg)
  screen.setCursorPos(x, y)
  screen.setTextColor(colors[fg or "white"])
  screen.setBackgroundColor(colors[bg or "black"])
  screen.write(text)
end

local function zone(x1, x2, y, action) ui.zones[#ui.zones + 1] = { x1 = x1, x2 = x2, y = y, action = action } end

local function bar(x, y, w, frac, colour)
  local filled = math.floor(math.max(0, math.min(1, frac)) * w + 0.5)
  put(x, y, (" "):rep(filled), "white", colour)
  put(x + filled, y, (" "):rep(w - filled), "white", "gray")
end

-- A scrolling list: rows from y0 to y1, with up/down buttons on the right
-- of the row under the tabs when it doesn't all fit.
local function list(items, y0, y1, row)
  local w = screen.getSize()
  local rows = y1 - y0 + 1
  local maxScroll = math.max(0, #items - rows)
  ui.scroll = math.max(0, math.min(ui.scroll, maxScroll))
  for i = 1, rows do
    local it = items[ui.scroll + i]
    if it then row(it, y0 + i - 1, w) end
  end
  if maxScroll > 0 then
    local range = ("%d-%d of %d"):format(ui.scroll + 1, math.min(#items, ui.scroll + rows), #items)
    put(w - 8 - #range, 3, range, "lightGray")
    put(w - 7, 3, " v ", "white", "lightGray")
    zone(w - 7, w - 5, 3, function() ui.scroll = ui.scroll + (rows - 1) end)
    put(w - 3, 3, " ^ ", "white", "lightGray")
    zone(w - 3, w - 1, 3, function() ui.scroll = ui.scroll - (rows - 1) end)
  end
  if #items == 0 then put(2, y0, "Nothing here.", "lightGray") end
end

local function drawTabs(w)
  put(1, 1, (" "):rep(w), "white", data.attack and "red" or "gray")
  local title = data.name or "Colony"
  if data.attack then title = title .. "  UNDER ATTACK!" end
  put(2, 1, fit(title, w - 2), data.attack and "white" or "yellow", data.attack and "red" or "gray")
  put(1, 2, (" "):rep(w), "white", "black")
  local names, width = TABS, #TABS - 1
  for _, name in ipairs(TABS) do width = width + #name + 2 end
  if width > w then names = SHORT_TABS end
  local x = 1
  for i, name in ipairs(names) do
    local label = " " .. name .. " "
    put(x, 2, label, i == ui.tab and "black" or "white", i == ui.tab and "white" or "gray")
    zone(x, x + #label - 1, 2, function() ui.tab, ui.scroll = i, 0 end)
    x = x + #label + 1
  end
end

local function drawOverview(w, h)
  local y = 4
  put(2, y, "Citizens", "lightGray")
  put(14, y, ("%d / %d"):format(data.citizenCount, data.citizenMax), "white")
  bar(26, y, math.max(4, w - 27), data.citizenMax > 0 and data.citizenCount / data.citizenMax or 0, "lime")
  y = y + 1
  put(2, y, "Happiness", "lightGray")
  put(14, y, ("%.1f / 10"):format(data.happiness), "white")
  local hc = data.happiness >= 7 and "lime" or data.happiness >= 5 and "yellow" or "red"
  bar(26, y, math.max(4, w - 27), data.happiness / 10, hc)
  y = y + 2

  local facts = {
    { "Idle", data.idle, data.idle > 0 and "yellow" or "white" },
    { "Asleep", data.asleep, "white" },
    { "Hungry", data.hungry, data.hungry > 0 and "orange" or "white" },
    { "Hurt", data.hurt, data.hurt > 0 and "red" or "white" },
    { "Graves", data.graves, data.graves > 0 and "red" or "white" },
    { "Buildings", #data.buildings, "white" },
    { "Building sites", data.sites, "white" },
    { "Work orders", #data.orders, "white" },
    { "Open requests", #data.requests, #data.requests > 0 and "yellow" or "white" },
  }
  local colW = math.max(20, math.floor((w - 2) / 2))
  for i, f in ipairs(facts) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local x = 2 + col * colW
    put(x, y + row, fit(f[1], colW - 6), "lightGray")
    put(x + colW - 6, y + row, fit(tostring(f[2]), 5), f[3])
  end
  y = y + math.ceil(#facts / 2) + 1

  if y < h then
    put(2, y, "Waiting for", "yellow")
    y = y + 1
    for i = 1, math.min(#data.requests, h - y + 1) do
      local r = data.requests[i]
      local count = ("%dx"):format(r.count or 1)
      put(2, y, count, "lightGray")
      put(3 + #count, y, fit(requestItem(r), w - #count - 4 - 16), "white")
      put(w - 15, y, fit(pretty(r.target), 15), "lightGray")
      y = y + 1
    end
    if #data.requests == 0 then put(2, y, "Nothing: every request is met.", "lime") end
  end
end

local function drawCitizens(w, h)
  put(2, 4, fit("Name", 20), "yellow")
  put(23, 4, fit("Job", 14), "yellow")
  put(38, 4, "Doing", "yellow")
  list(data.citizens, 5, h, function(c, y)
    local colour = c.isIdle and "yellow" or c.isAsleep and "lightGray" or "white"
    if c.health and c.maxHealth and c.health < c.maxHealth / 2 then colour = "red" end
    put(2, y, fit(c.name, 20), colour)
    put(23, y, fit(jobOf(c), 14), "lightGray")
    local doing = c.isAsleep and "Sleeping" or c.isIdle and "Idle" or pretty(c.state)
    if (c.saturation or 20) < HUNGRY_BELOW then doing = "Hungry - " .. doing end
    put(38, y, fit(doing, w - 38), colour)
  end)
end

local function drawBuildings(w, h)
  put(2, 4, fit("Building", 24), "yellow")
  put(27, 4, fit("Level", 7), "yellow")
  put(35, 4, "Workers", "yellow")
  list(data.buildings, 5, h, function(b, y)
    local level = ("%d/%d"):format(b.level or 0, b.maxLevel or 5)
    local colour = not b.built and "lightGray" or (b.level or 0) >= (b.maxLevel or 5) and "lime" or "white"
    put(2, y, fit(pretty(b.type or b.name), 24), colour)
    put(27, y, fit(level, 7), colour)
    local names = {}
    for _, c in ipairs(b.citizens or {}) do names[#names + 1] = c.name end
    local text = #names > 0 and table.concat(names, ", ") or (b.isWorkingOn and "being built" or "")
    put(35, y, fit(text, w - 35), b.isWorkingOn and "orange" or "lightGray")
  end)
end

local function drawRequests(w, h)
  put(2, 4, fit("Item", 30), "yellow")
  put(33, 4, fit("Count", 6), "yellow")
  put(40, 4, "For", "yellow")
  list(data.requests, 5, h, function(r, y)
    put(2, y, fit(requestItem(r), 30), "white")
    put(33, y, fit(tostring(r.count or 1), 6), "lightGray")
    put(40, y, fit(pretty(r.target), w - 40), "lightGray")
  end)
end

local function drawBuilds(w, h)
  put(2, 4, fit("Work order", 24), "yellow")
  put(27, 4, fit("Type", 10), "yellow")
  put(38, 4, "Builder", "yellow")
  list(data.orders, 5, h, function(o, y)
    local name = pretty(o.buildingName or o.type)
    if o.targetLevel then name = ("%s -> %d"):format(name, o.targetLevel) end
    put(2, y, fit(name, 24), "white")
    put(27, y, fit(pretty(o.workOrderType), 10), "lightGray")
    local who = o.isClaimed and o.builder and ("at %d,%d,%d"):format(o.builder.x, o.builder.y, o.builder.z) or "waiting for a builder"
    put(38, y, fit(who, w - 38), o.isClaimed and "lime" or "yellow")
  end)
end

local PAGES = { drawOverview, drawCitizens, drawBuildings, drawRequests, drawBuilds }

local function draw()
  ui.zones = {}
  screen.setBackgroundColor(colors.black)
  screen.clear()
  local w, h = screen.getSize()
  if not data.inColony then
    put(2, 2, "Not inside a colony.", "red")
    put(2, 4, "Move this computer and its Colony Integrator", "white")
    put(2, 5, "inside your colony's borders.", "white")
    return
  end
  drawTabs(w)
  PAGES[ui.tab](w, h)
end

---------------------------------------------------------------- loops

local function summary()
  if not data.inColony then return "not inside a colony" end
  return ("%d/%d citizens, happiness %.1f, %d requests"):format(data.citizenCount, data.citizenMax, data.happiness, #data.requests)
end

local function refreshLoop()
  local wasAttacked = false
  while true do
    data = read()
    draw()
    if data.attack and not wasAttacked then
      print(("%s  Colony is under attack!"):format(textutils.formatTime(os.time(), true)))
      if report then report.log("colony under attack") end
    end
    wasAttacked = data.attack
    if report then report.set(data.attack and "alert" or data.inColony and "running" or "waiting", data.attack and "under attack!" or summary()) end
    sleep(REFRESH)
  end
end

local function alarmLoop()
  local speaker = peripheral.find("speaker")
  if not (ALARM and speaker) then return sleep(math.huge) end
  while true do
    if data.attack then
      speaker.playNote("bell", 3, 18)
      sleep(0.4)
      speaker.playNote("bell", 3, 12)
    end
    sleep(1)
  end
end

local function touchLoop()
  while true do
    local event, _, x, y = os.pullEvent()
    if event == "monitor_touch" or (event == "mouse_click" and screen == term) then
      for _, z in ipairs(ui.zones) do
        if y == z.y and x >= z.x1 and x <= z.x2 then
          z.action()
          draw()
          break
        end
      end
    elseif event == "monitor_resize" or event == "term_resize" then
      draw()
    end
  end
end

---------------------------------------------------------------- start

colony = peripheral.find("colony_integrator") or peripheral.find("colonyIntegrator")
if not colony then
  print("No Colony Integrator found. Place one next to this computer")
  print("(it's a block from Advanced Peripherals).")
  return
end

local monitor = peripheral.find("monitor")
if monitor then
  monitor.setTextScale(MONITOR_SCALE)
  screen = monitor
  term.clear()
  term.setCursorPos(1, 1)
  print("Colony dashboard running on the monitor.")
  print("Hold Ctrl+T to stop.")
else
  screen = term
end

if report then report.init("colony dashboard") end
parallel.waitForAny(refreshLoop, touchLoop, alarmLoop,
  report and report.loop or function() sleep(math.huge) end)
