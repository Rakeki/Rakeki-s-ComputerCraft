-- Fusion reactor control for Mekanism. Shows a Fusion Reactor on a monitor
-- through its Logic Adapter (or a Reactor Port): plasma and case
-- temperature against their limits, injection rate, power made, the fuel
-- tanks and (when water-cooled) water and steam. Buttons change the
-- injection rate or stop it, and it warns when fuel or water runs low, the
-- case runs hot, or the reaction goes out.
--
--   fusion            start the control panel (startup.lua runs it)
--
-- Mekanism reports energy in joules; it's shown in FE (or J, see config.lua).
local screen = require("lib.screen") -- flicker-free drawing
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local config = fs.exists("config.lua") and require("config") or {}

local REFRESH = 1 -- seconds between reads
local MONITOR_SCALE = 0.5 -- text size on the monitor (0.5 fits the most)
local MAX_INJECTION = 98 -- Mekanism's limit; the rate must be even
local UNIT = config.unit or "FE" -- "FE" or "J"
local JOULES_PER_FE = config.joulesPerFE or 2.5 -- Mekanism's default conversion rate
local LOW_FUEL = config.lowFuel or 0.10 -- warn when deuterium, tritium or D-T fuel is this low
local LOW_WATER = config.lowWater or 0.10 -- warn when a water-cooled reactor's water is this low
local HOT_CASE = config.hotCase or 0.90 -- warn when the case is this close to its maximum
local ALARM = config.alarm ~= false -- beep a speaker when the reaction goes out
local STEPS = { { "-10", -10 }, { "-2", -2 }, { "+2", 2 }, { "+10", 10 } } -- injection buttons: label, mB/t

local READS = {
  "isFormed", "isIgnited", "getPlasmaTemperature", "getCaseTemperature", "getInjectionRate",
  "getProductionRate", "getDeuteriumFilledPercentage", "getTritiumFilledPercentage",
  "getDTFuelFilledPercentage", "getWater", "getWaterFilledPercentage", "getSteamFilledPercentage",
  "getHohlraum",
}
-- these take one argument: whether the reactor is water-cooled
local LIMITS = { "getMaxPlasmaTemperature", "getMaxCasingTemperature", "getIgnitionTemperature", "getMinInjectionRate" }

local reactor
local data = {}
local ui = { zones = {}, msg = nil, msgColour = "white", lastRate = nil }

---------------------------------------------------------------- reading

local function findReactor()
  reactor = peripheral.find("fusionReactorLogicAdapter") or peripheral.find("fusionReactorPort")
end

-- Mekanism runs each method on the game's main thread, one tick per call, so
-- every call is started at once and they all finish in the same tick.
local function read()
  if not reactor then return { missing = true } end
  local d, jobs = { limits = { [true] = {}, [false] = {} } }, {}
  for _, name in ipairs(READS) do
    jobs[#jobs + 1] = function()
      local ok, value = pcall(reactor[name])
      if ok then d[name] = value end
    end
  end
  for _, name in ipairs(LIMITS) do
    for _, cooled in ipairs({ true, false }) do
      jobs[#jobs + 1] = function()
        local ok, value = pcall(reactor[name], cooled)
        if ok then d.limits[cooled][name] = value end
      end
    end
  end
  parallel.waitForAll(table.unpack(jobs))
  if d.isFormed == nil then d.missing = true end
  d.cooled = type(d.getWater) == "table" and (d.getWater.amount or 0) > 0
  d.limit = d.limits[d.cooled]
  return d
end

---------------------------------------------------------------- text helpers

local function int(n) return math.floor((n or 0) + 0.5) end
local function pct(f) return f and ("%d%%"):format(int(f * 100)) or "?" end

-- 123456789 -> "123.46 M"
local function scaled(n)
  local units = { "", "k", "M", "G", "T", "P" }
  local i = 1
  while math.abs(n) >= 1000 and i < #units do n, i = n / 1000, i + 1 end
  return i == 1 and ("%d "):format(int(n)) or ("%.2f %s"):format(n, units[i])
end

local function kelvin(k) return k and scaled(k) .. "K" or "?" end
local function energy(j, suffix)
  if not j then return "?" end
  return scaled(UNIT == "J" and j or j / JOULES_PER_FE) .. UNIT .. (suffix or "")
end

local fit = screen.fit

---------------------------------------------------------------- warnings

-- Things worth knowing, worst first: { text, colour }.
local function warnings(d)
  local list = {}
  local function add(text, colour) list[#list + 1] = { text, colour } end
  local rate = d.getInjectionRate or 0
  -- Mekanism ignites when the plasma is hot enough and a Hohlraum is in the
  -- reactor (it's used up); the laser is only needed to heat cold plasma.
  if not d.isIgnited then
    local hohlraum = type(d.getHohlraum) == "table" and (d.getHohlraum.count or 0) > 0
    local hot = d.limit.getIgnitionTemperature and (d.getPlasmaTemperature or 0) >= d.limit.getIgnitionTemperature
    if rate == 0 then
      add("Stopped: injection rate is 0.", "lightGray")
    elseif hot then
      add(hohlraum and "Plasma is hot enough: igniting." or "Plasma is still hot: add a filled Hohlraum to reignite.", "yellow")
    elseif hohlraum then
      add("Not ignited: fire a laser burst at the reactor.", "orange")
    else
      add("Not ignited: needs a filled Hohlraum and a laser burst.", "orange")
    end
  end
  if d.getCaseTemperature and d.limit.getMaxCasingTemperature and d.getCaseTemperature >= d.limit.getMaxCasingTemperature * HOT_CASE then
    add("The case is close to its maximum temperature.", "red")
  end
  for _, tank in ipairs({ { "Deuterium", d.getDeuteriumFilledPercentage }, { "Tritium", d.getTritiumFilledPercentage } }) do
    if tank[2] and tank[2] <= LOW_FUEL and rate > 0 then add(("Low on %s (%s)."):format(tank[1]:lower(), pct(tank[2])), "orange") end
  end
  if d.cooled then
    if d.getWaterFilledPercentage and d.getWaterFilledPercentage <= LOW_WATER then
      add(("Low on water (%s)."):format(pct(d.getWaterFilledPercentage)), "orange")
    end
    if d.getSteamFilledPercentage and d.getSteamFilledPercentage >= 0.95 then
      add("Steam is backing up: is a turbine taking it?", "orange")
    end
  end
  if d.limit.getMinInjectionRate and rate > 0 and rate < d.limit.getMinInjectionRate then
    add(("Injection is below the %d mB/t needed to keep it going."):format(int(d.limit.getMinInjectionRate)), "orange")
  end
  return list
end

---------------------------------------------------------------- acting

local function say(text, colour) ui.msg, ui.msgColour = text, colour or "white" end

local function setRate(rate)
  if not reactor then return end
  rate = math.max(0, math.min(MAX_INJECTION, rate))
  rate = rate - rate % 2
  local ok, err = pcall(reactor.setInjectionRate, rate)
  if ok then
    data.getInjectionRate = rate
    say(("Injection rate set to %d mB/t."):format(rate), "white")
  else
    say(tostring(err):gsub("^.-:%d+: ", ""), "orange")
  end
end

local function stop()
  local rate = data.getInjectionRate or 0
  if rate > 0 then ui.lastRate = rate end
  setRate(0)
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

local function bar(x, y, w, frac, colour)
  if w < 1 then return end
  local filled = math.floor(math.max(0, math.min(1, frac or 0)) * w + 0.5)
  put(x, y, (" "):rep(filled), "white", colour)
  put(x + filled, y, (" "):rep(w - filled), "white", "gray")
end

local function level(f, low)
  if not f then return "lightGray" end
  return f <= low and "red" or f <= low * 2 and "orange" or "lime"
end

local function heat(value, max)
  if not (value and max and max > 0) then return "lightGray" end
  local f = value / max
  return f >= HOT_CASE and "red" or f >= 0.75 and "orange" or "lime"
end

local function status(d)
  if d.missing then return "NO REACTOR", "red" end
  if not d.isFormed then return "NOT FORMED", "red" end
  if d.isIgnited then return "IGNITED", "green" end
  return "NOT IGNITED", "gray"
end

local function draw()
  local d = data
  local word, colour = status(d)
  local warn = d.missing and {} or warnings(d)
  local keyParts = {
    word, kelvin(d.getPlasmaTemperature), kelvin(d.getCaseTemperature), tostring(d.getInjectionRate),
    energy(d.getProductionRate), pct(d.getDeuteriumFilledPercentage), pct(d.getTritiumFilledPercentage),
    pct(d.getDTFuelFilledPercentage), pct(d.getWaterFilledPercentage), pct(d.getSteamFilledPercentage),
    tostring(ui.msg), tostring(ui.lastRate),
  }
  for _, wn in ipairs(warn) do keyParts[#keyParts + 1] = wn[1] end
  if display:same(table.concat(keyParts, "|")) then return end

  ui.zones = {}
  local w, h
  win, w, h = display:frame()
  put(1, 1, (" "):rep(w), "white", colour)
  put(2, 1, "Fusion reactor", "white", colour)
  put(w - #word, 1, word, "white", colour)

  if d.missing or not d.isFormed then
    put(2, 3, d.missing and "Can't find the reactor." or "The reactor isn't formed.", "red")
    put(2, 5, fit("Put a Fusion Reactor Logic Adapter (or a Reactor", w - 2))
    put(2, 6, fit("Port) in the reactor's casing and connect it to this", w - 2))
    put(2, 7, fit("computer, touching it or over a wired modem.", w - 2))
    display:show()
    return
  end

  local L = d.limit
  local barX = 28
  local rows = {
    { "Plasma", kelvin(d.getPlasmaTemperature), L.getMaxPlasmaTemperature and (d.getPlasmaTemperature or 0) / L.getMaxPlasmaTemperature, heat(d.getPlasmaTemperature, L.getMaxPlasmaTemperature) },
    { "Case", kelvin(d.getCaseTemperature), L.getMaxCasingTemperature and (d.getCaseTemperature or 0) / L.getMaxCasingTemperature, heat(d.getCaseTemperature, L.getMaxCasingTemperature) },
    { "Deuterium", pct(d.getDeuteriumFilledPercentage), d.getDeuteriumFilledPercentage, level(d.getDeuteriumFilledPercentage, LOW_FUEL) },
    { "Tritium", pct(d.getTritiumFilledPercentage), d.getTritiumFilledPercentage, level(d.getTritiumFilledPercentage, LOW_FUEL) },
    { "D-T fuel", pct(d.getDTFuelFilledPercentage), d.getDTFuelFilledPercentage, "lightBlue" },
  }
  if d.cooled then
    rows[#rows + 1] = { "Water", pct(d.getWaterFilledPercentage), d.getWaterFilledPercentage, level(d.getWaterFilledPercentage, LOW_WATER) }
    rows[#rows + 1] = { "Steam", pct(d.getSteamFilledPercentage), d.getSteamFilledPercentage, (d.getSteamFilledPercentage or 0) >= 0.95 and "orange" or "lightBlue" }
  end
  local y = 3
  for _, r in ipairs(rows) do
    put(2, y, fit(r[1], 14), "lightGray")
    put(16, y, fit(r[2], 11), r[4])
    bar(barX, y, w - barX, r[3], r[4])
    y = y + 1
  end
  y = y + 1
  put(2, y, fit("Injection", 14), "lightGray")
  put(16, y, fit(("%d mB/t"):format(int(d.getInjectionRate)), 11), "white")
  put(barX, y, fit(("needs %d+, max %d"):format(int(L.getMinInjectionRate), MAX_INJECTION), w - barX), "lightGray")
  y = y + 1
  put(2, y, fit("Making", 14), "lightGray")
  put(16, y, fit(energy(d.getProductionRate, "/t"), w - 16), d.isIgnited and "lime" or "white")
  y = y + 1
  put(2, y, fit("Cooling", 14), "lightGray")
  put(16, y, fit(d.cooled and "water-cooled (steam to turbines)" or "not water-cooled", w - 16), "white")
  y = y + 2

  for _, wn in ipairs(warn) do
    if y >= h - 1 then break end
    put(2, y, fit(wn[1], w - 2), wn[2])
    y = y + 1
  end
  if ui.msg and y < h - 1 then put(2, y, fit(ui.msg, w - 2), ui.msgColour) end

  put(2, h - 1, "Inject", "lightGray")
  local x = 9
  local rate = d.getInjectionRate or 0
  for _, s in ipairs(STEPS) do
    x = button(x, h - 1, s[1], "white", "gray", function() setRate((data.getInjectionRate or 0) + s[2]) end)
  end
  if rate == 0 and ui.lastRate then
    button(x, h - 1, ("Resume %d"):format(ui.lastRate), "white", "green", function() setRate(ui.lastRate) end)
  else
    button(x, h - 1, "Stop", "white", "red", stop)
  end
  put(2, h, fit(("Limits: plasma %s, case %s"):format(kelvin(L.getMaxPlasmaTemperature), kelvin(L.getMaxCasingTemperature)), w - 2), "gray")
  display:show()
end

---------------------------------------------------------------- loops

local wasIgnited = nil

local function beep()
  local speaker = ALARM and peripheral.find("speaker")
  if not speaker then return end
  for _ = 1, 3 do
    speaker.playNote("bell", 3, 12)
    sleep(0.3)
  end
end

local function refresh()
  data = read()
  local ignited = data.isIgnited
  if wasIgnited and ignited == false then
    local why = (data.getInjectionRate or 0) == 0 and "injection stopped" or "the reaction went out"
    print(("%s  Fusion stopped: %s"):format(textutils.formatTime(os.time(), true), why))
    if report then report.log("fusion stopped: " .. why) end
    if why ~= "injection stopped" then
      say("The reaction went out. Check fuel, then reignite.", "red")
      beep()
    end
  end
  if ignited ~= nil then wasIgnited = ignited end
  draw()
  if report then
    local state = data.missing and "waiting" or data.isIgnited and "running" or (data.getInjectionRate or 0) > 0 and "alert" or "idle"
    local detail = data.missing and "no fusion reactor found"
      or ("%s, %s, inject %d mB/t"):format(data.isIgnited and "ignited" or "not ignited", energy(data.getProductionRate, "/t"), int(data.getInjectionRate))
    report.set(state, detail)
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
  print("Fusion control running on the monitor.")
  print("Hold Ctrl+T to stop.")
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
      findReactor()
      if display:refresh() then
        announce()
        draw()
      end
    elseif event == "monitor_resize" or event == "term_resize" then
      draw()
    end
  end
end

---------------------------------------------------------------- start

findReactor()
display = screen.find({ scales = { MONITOR_SCALE }, fallback = term.current() })
announce()
if not reactor then
  print("No Fusion Reactor Logic Adapter or Reactor Port found yet.")
  print("Connect one; it's picked up when it appears.")
end

if report then report.init("fusion control") end
if errlog then errlog.init("fusion") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, refreshLoop, touchLoop,
  report and report.loop or function() sleep(math.huge) end)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
