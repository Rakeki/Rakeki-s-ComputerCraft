-- Mekanism power dashboard. Shows your Induction Matrix on a monitor: how
-- much is stored, what's going in and out, how long until it's full or
-- empty, and a graph of the last hour. Turbines and energy cubes on the same
-- network get a line each. Optionally switches a redstone signal on while
-- the stored power is low (to start generators) and off once it's full.
--
--   power             start the dashboard (startup.lua runs it)
--
-- Mekanism reports energy in joules; it's shown in FE (or J, see config.lua).
local screen = require("lib.screen") -- flicker-free drawing
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local config = fs.exists("config.lua") and require("config") or {}

local REFRESH = 1 -- seconds between reads
local MONITOR_SCALE = 0.5 -- text size on the monitor (0.5 fits the most)
local SMOOTH = 30 -- seconds the in/out rate is averaged over for "full in" / "empty in"
local GRAPH_SPAN = config.graphMinutes or 60 -- minutes the graph covers, right edge = now
local UNIT = config.unit or "FE" -- "FE" or "J"
local JOULES_PER_FE = config.joulesPerFE or 2.5 -- Mekanism's default conversion rate
local SIGNAL_SIDE = config.signalSide -- redstone side, or nil for no signal
local SIGNAL_ON = config.signalOn or 0.20 -- signal on at or below this fill
local SIGNAL_OFF = config.signalOff or 0.90 -- and off again at or above this
local ALERT_BELOW = config.alertBelow or 0.05 -- status server shows an alert below this fill
local NAMES = config.names or {} -- peripheral name -> name shown

local MATRIX_READS = { "isFormed", "getMinPos", "getEnergy", "getMaxEnergy", "getLastInput", "getLastOutput", "getTransferCap", "getInstalledCells", "getInstalledProviders" }
local TURBINE_READS = { "isFormed", "getMinPos", "getProductionRate", "getSteamFilledPercentage", "getFlowRate", "getMaxFlowRate" }
local CUBE_READS = { "getEnergy", "getMaxEnergy" }

local data = { matrices = {}, turbines = {}, cubes = {} } -- latest read
local samples = {} -- { t = os.clock(), e = stored } for the smoothed rate
local graph = {} -- fill fractions, one per graph step, oldest first
local signal = false -- the redstone signal is on

---------------------------------------------------------------- reading

-- Mekanism runs each method on the game's main thread, one tick per call, so
-- every call for every device is started at once and they finish together.
local function readDevices(devices)
  local jobs = {}
  for _, dev in ipairs(devices) do
    dev.values = {}
    for _, name in ipairs(dev.reads) do
      jobs[#jobs + 1] = function()
        local ok, value = pcall(peripheral.call, dev.name, name)
        if ok then dev.values[name] = value end
      end
    end
  end
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
end

local function isCube(name)
  local t = peripheral.getType(name)
  return t and t:find("EnergyCube$") ~= nil
end

local function devices()
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if t == "inductionPort" then list[#list + 1] = { name = name, kind = "matrix", reads = MATRIX_READS }
    elseif t == "turbineValve" then list[#list + 1] = { name = name, kind = "turbine", reads = TURBINE_READS }
    elseif isCube(name) then list[#list + 1] = { name = name, kind = "cube", reads = CUBE_READS, tier = t:gsub("EnergyCube$", "") } end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- A multiblock has many ports and valves: keep one per structure.
local function posKey(p) return p and ("%d,%d,%d"):format(p.x, p.y, p.z) end

local function read()
  local list = devices()
  readDevices(list)
  local d = { matrices = {}, turbines = {}, cubes = {}, stored = 0, max = 0, input = 0, output = 0 }
  local seen = {}
  for _, dev in ipairs(list) do
    local v = dev.values
    local key = posKey(v.getMinPos)
    if dev.kind == "cube" then
      if v.getMaxEnergy then d.cubes[#d.cubes + 1] = dev end
    elseif v.isFormed and not (key and seen[key]) then
      if key then seen[key] = true end
      if dev.kind == "matrix" then d.matrices[#d.matrices + 1] = dev else d.turbines[#d.turbines + 1] = dev end
    end
  end
  for _, dev in ipairs(d.matrices) do
    local v = dev.values
    d.stored = d.stored + (v.getEnergy or 0)
    d.max = d.max + (v.getMaxEnergy or 0)
    d.input = d.input + (v.getLastInput or 0)
    d.output = d.output + (v.getLastOutput or 0)
  end
  if #d.matrices == 0 then
    -- no matrix: the cubes are the store
    for _, dev in ipairs(d.cubes) do
      d.stored = d.stored + (dev.values.getEnergy or 0)
      d.max = d.max + (dev.values.getMaxEnergy or 0)
    end
  end
  d.fill = d.max > 0 and d.stored / d.max or nil
  return d
end

-- Joules per tick, averaged over the last SMOOTH seconds of stored energy.
local function smoothedRate()
  local now = os.clock()
  samples[#samples + 1] = { t = now, e = data.stored }
  while #samples > 2 and now - samples[1].t > SMOOTH do table.remove(samples, 1) end
  local first = samples[1]
  if now - first.t < 2 then return nil end
  return (data.stored - first.e) / ((now - first.t) * 20)
end

local lastGraph = nil
local function addToGraph(width)
  local step = GRAPH_SPAN * 60 / math.max(1, width)
  local now = os.clock()
  if lastGraph and now - lastGraph < step then return end
  lastGraph = now
  graph[#graph + 1] = data.fill or 0
  while #graph > 200 do table.remove(graph, 1) end
end

---------------------------------------------------------------- text helpers

local function int(n) return math.floor((n or 0) + 0.5) end
local function pct(f) return f and ("%d%%"):format(int(f * 100)) or "?" end

-- joules -> "1.23 MFE"
local function energy(j, suffix)
  if not j then return "?" end
  local n = UNIT == "J" and j or j / JOULES_PER_FE
  local units = { "", "k", "M", "G", "T", "P", "E" }
  local i = 1
  while math.abs(n) >= 1000 and i < #units do n, i = n / 1000, i + 1 end
  local num = i == 1 and ("%d"):format(int(n)) or ("%.2f"):format(n)
  return ("%s %s%s%s"):format(num, units[i], UNIT, suffix or "")
end

local function duration(seconds)
  if seconds >= 99 * 3600 then return "a long time" end
  local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
  if h > 0 then return ("%dh %dm"):format(h, m) end
  if m > 0 then return ("%dm %ds"):format(m, math.floor(seconds % 60)) end
  return ("%ds"):format(math.floor(seconds))
end

local function forecast(rate)
  if not (rate and data.fill) then return "Working out the rate...", "lightGray" end
  local threshold = data.max / 100000 -- ignore tiny drift
  if math.abs(rate) <= threshold then return "Steady", "lightGray" end
  if rate > 0 then
    if data.fill >= 0.999 then return "Full", "lime" end
    return "Full in " .. duration((data.max - data.stored) / rate / 20), "lime"
  end
  return "Empty in " .. duration(data.stored / -rate / 20), data.fill < SIGNAL_ON and "red" or "orange"
end

local function fillColour(f)
  if not f then return "gray" end
  return f < ALERT_BELOW and "red" or f < SIGNAL_ON and "orange" or f < 0.5 and "yellow" or "lime"
end

local fit = screen.fit

---------------------------------------------------------------- drawing

local display -- lib/screen.lua on the monitor, or this computer's screen
local win

local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end

local function bar(x, y, w, frac, colour)
  if w < 1 then return end
  local filled = math.floor(math.max(0, math.min(1, frac or 0)) * w + 0.5)
  put(x, y, (" "):rep(filled), "white", colour)
  put(x + filled, y, (" "):rep(w - filled), "white", "gray")
end

local function deviceLines()
  local lines = {}
  for i, dev in ipairs(data.turbines) do
    local v = dev.values
    local flow = v.getMaxFlowRate and v.getMaxFlowRate > 0 and (v.getFlowRate or 0) / v.getMaxFlowRate or 0
    lines[#lines + 1] = {
      NAMES[dev.name] or ("Turbine " .. i),
      energy(v.getProductionRate, "/t"),
      ("steam %s flow %s"):format(pct(v.getSteamFilledPercentage), pct(flow)),
      (v.getSteamFilledPercentage or 0) > 0.95 and "orange" or "white",
    }
  end
  for _, dev in ipairs(data.cubes) do
    local v = dev.values
    local tier = dev.tier:gsub("^%l", string.upper)
    local fill = v.getMaxEnergy and v.getMaxEnergy > 0 and (v.getEnergy or 0) / v.getMaxEnergy or 0
    lines[#lines + 1] = { NAMES[dev.name] or (tier .. " cube"), energy(v.getEnergy), pct(fill), fillColour(fill) }
  end
  return lines
end

local function draw(rate)
  local d = data
  local lines = deviceLines()
  local status, statusColour = forecast(rate)
  local keyParts = { energy(d.stored), pct(d.fill), energy(d.input, "/t"), energy(d.output, "/t"), status, tostring(signal), #graph, tostring(graph[#graph]) }
  for _, l in ipairs(lines) do keyParts[#keyParts + 1] = table.concat(l, "/") end
  if display:same(table.concat(keyParts, "|")) then return end

  local w, h
  win, w, h = display:frame()
  local title = #d.matrices > 1 and ("Power: %d Induction Matrices"):format(#d.matrices)
    or #d.matrices == 1 and "Power: Induction Matrix" or "Power: energy cubes"
  put(1, 1, (" "):rep(w), "white", "gray")
  put(2, 1, fit(title, w - 2), "yellow", "gray")

  if #d.matrices == 0 and #d.cubes == 0 then
    put(2, 3, "No Induction Port or energy cube found.", "red")
    put(2, 5, fit("Connect an Induction Port of your matrix (or energy", w - 2))
    put(2, 6, fit("cubes) to this computer, touching it or over wired", w - 2))
    put(2, 7, fit("modems.", w - 2))
    display:show()
    return
  end

  put(2, 3, "Stored", "lightGray")
  local stored = ("%s / %s"):format(energy(d.stored), energy(d.max))
  put(10, 3, fit(stored, w - 16), "white")
  put(w - 4, 3, fit(pct(d.fill), 4), fillColour(d.fill))
  bar(2, 4, w - 2, d.fill, fillColour(d.fill))

  local y = 6
  if #d.matrices > 0 then
    put(2, y, "In", "lightGray")
    put(6, y, fit(energy(d.input, "/t"), 16), "lime")
    put(23, y, "Out", "lightGray")
    put(28, y, fit(energy(d.output, "/t"), w - 28), "orange")
    y = y + 1
  end
  put(2, y, fit(status, w - 2), statusColour)
  if SIGNAL_SIDE then
    local text = "Signal " .. (signal and "ON" or "off")
    put(w - #text, y, text, signal and "lime" or "lightGray")
  end
  y = y + 1
  if #d.matrices > 0 then
    local cells, providers, cap = 0, 0, 0
    for _, m in ipairs(d.matrices) do
      cells = cells + (m.values.getInstalledCells or 0)
      providers = providers + (m.values.getInstalledProviders or 0)
      cap = cap + (m.values.getTransferCap or 0)
    end
    put(2, y, fit(("%d cells, %d providers, up to %s"):format(cells, providers, energy(cap, "/t")), w - 2), "lightGray")
    y = y + 1
  end

  -- devices take the bottom rows, the graph whatever is left (at least 3 rows)
  local deviceRows = math.min(#lines, math.max(0, h - y - 5))
  local graphTop, graphBottom = y + 1, h - deviceRows - (deviceRows > 0 and 1 or 0)
  if graphBottom - graphTop >= 2 then
    local gw = w - 2
    local rows = graphBottom - graphTop + 1
    local first = math.max(1, #graph - gw + 1)
    for i = first, #graph do
      local x = 2 + (gw - (#graph - first + 1)) + (i - first)
      local filled = math.floor(graph[i] * rows + 0.5)
      for r = 0, rows - 1 do
        local yy = graphBottom - r
        put(x, yy, " ", "white", r < filled and fillColour(graph[i]) or "gray")
      end
    end
    for x = 2, 1 + gw - (#graph - first + 1) do
      for yy = graphTop, graphBottom do put(x, yy, " ", "white", "gray") end
    end
    local label = ("last %d min"):format(GRAPH_SPAN)
    put(w - #label, graphTop, label, "white", "gray")
  end

  y = h - deviceRows + 1
  for i = 1, deviceRows do
    local l = lines[i]
    put(2, y, fit(l[1], 14), "lightGray")
    put(17, y, fit(l[2], 14), l[4])
    put(32, y, fit(l[3], w - 32), l[4])
    y = y + 1
  end
  display:show()
end

---------------------------------------------------------------- loops

local function updateSignal()
  if not SIGNAL_SIDE or not data.fill then return end
  if not signal and data.fill <= SIGNAL_ON then signal = true
  elseif signal and data.fill >= SIGNAL_OFF then signal = false end
  redstone.setOutput(SIGNAL_SIDE, signal)
end

local function reportState(rate)
  if not report then return end
  if not data.fill then return report.set("waiting", "no Induction Matrix or energy cube found") end
  local state = data.fill < ALERT_BELOW and "alert" or "running"
  report.set(state, ("%s stored (%s), %s"):format(energy(data.stored), pct(data.fill), (forecast(rate))))
end

local function refresh()
  data = read()
  local rate = data.fill and smoothedRate()
  addToGraph(display:size() - 2)
  updateSignal()
  draw(rate)
  reportState(rate)
end

local function refreshLoop()
  while true do
    local ok, err = (errlog and errlog.pcall or pcall)(refresh)
    if not ok then print("Read failed: " .. tostring(err)) end
    sleep(REFRESH)
  end
end

local function announce()
  if not display.name then return end
  term.clear()
  term.setCursorPos(1, 1)
  print("Power dashboard running on the monitor.")
  print("Hold Ctrl+T to stop.")
end

local function eventLoop()
  while true do
    local event = os.pullEvent()
    if event == "peripheral" or event == "peripheral_detach" then
      if display:refresh() then announce() end
    end
  end
end

---------------------------------------------------------------- start

display = screen.find({ setting = "power.monitor", scales = { MONITOR_SCALE }, fallback = term.current() })
announce()
if SIGNAL_SIDE then redstone.setOutput(SIGNAL_SIDE, false) end

if report then report.init("power dashboard") end
if errlog then errlog.init("power") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, refreshLoop, eventLoop,
  report and report.loop or function() sleep(math.huge) end)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
