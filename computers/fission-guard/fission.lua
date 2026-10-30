-- Fission reactor guard for Mekanism. Watches a Fission Reactor through a
-- Logic Adapter (or a Reactor Port) twice a second and SCRAMs it before it
-- gets into trouble: too hot, damaged, short of coolant, or heated coolant or
-- waste backing up. A monitor shows every gauge with Start, SCRAM, Reset and
-- burn-rate buttons, and a speaker sounds the alarm. With an Induction Port
-- on the same network it also pauses the reactor while the matrix is full
-- and starts it again once there's room.
--
--   fission           start the guard (startup.lua runs it)
--
-- A safety SCRAM stays latched (even across reboots) until you tap Reset;
-- the reactor is SCRAMmed again if anything starts it while latched. The
-- limits are in config.lua.
local screen = require("lib.screen") -- flicker-free drawing
local files = require("lib.files") -- crash-safe save file for the latch
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local config = fs.exists("config.lua") and require("config") or {}

local CHECK_EVERY = 0.5 -- seconds between safety checks
local MONITOR_SCALE = 0.5 -- text size on the monitor (0.5 fits the most)
local LATCH_FILE = "/.fission_latch" -- why it SCRAMmed, kept until Reset
local DAMAGE_TEMP = 1200 -- K: Mekanism starts damaging the reactor above this
-- Limits, from config.lua (see there for what each means)
local MAX_TEMP = config.maxTemp or 1000
local MAX_DAMAGE = config.maxDamage or 1
local MIN_COOLANT = config.minCoolant or 0.10
local MAX_HEATED = config.maxHeated or 0.90
local MAX_WASTE = config.maxWaste or 0.80
local LOW_FUEL = config.lowFuel or 0.05
local PAUSE_POWER_AT = config.pausePowerAt == nil and 0.98 or config.pausePowerAt -- false: never
local RESUME_POWER_BELOW = config.resumePowerBelow or 0.80
local ALARM = config.alarm ~= false -- speaker alarm while latched
local ALARM_SIDE = config.alarmSide -- redstone side switched on while latched (nil: none)
local BURN_STEPS = { { "-1", -1 }, { "-.1", -0.1 }, { "+.1", 0.1 }, { "+1", 1 } } -- burn-rate buttons: label, mB/t

local READS = {
  "isFormed", "getStatus", "isForceDisabled", "getTemperature", "getDamagePercent",
  "getCoolantFilledPercentage", "getHeatedCoolantFilledPercentage", "getWasteFilledPercentage",
  "getFuelFilledPercentage", "getBurnRate", "getActualBurnRate", "getMaxBurnRate", "getHeatingRate",
}

local reactor, matrix -- peripherals (matrix: an Induction Port, optional)
local data = {} -- latest read of the reactor
local latch = files.read(LATCH_FILE) or {} -- { reason, time, pausedForPower }
local ui = { zones = {}, msg = nil, msgColour = "white" }

---------------------------------------------------------------- reading

-- Whole numbers for %d: Mekanism returns temperatures and fill levels as decimals.
local function int(n) return math.floor((n or 0) + 0.5) end
local function pct(f) return f and ("%d%%"):format(int(f * 100)) or "?" end

local function findDevices()
  reactor = peripheral.find("fissionReactorLogicAdapter") or peripheral.find("fissionReactorPort")
  matrix = peripheral.find("inductionPort")
end

-- Mekanism runs each method on the game's main thread, one tick per call, so
-- every call is started at once and they all finish in the same tick.
local function readAll(p, names)
  local out, jobs = {}, {}
  for _, name in ipairs(names) do
    jobs[#jobs + 1] = function()
      local ok, value = pcall(p[name])
      if ok then out[name] = value end
    end
  end
  parallel.waitForAll(table.unpack(jobs))
  return out
end

local function read()
  if not reactor then return { missing = true } end
  local d = readAll(reactor, READS)
  if d.getStatus == nil then d.missing = d.isFormed == nil end
  if matrix then
    local m = readAll(matrix, { "isFormed", "getEnergyFilledPercentage" })
    if m.isFormed then d.power = m.getEnergyFilledPercentage end
  end
  return d
end

-- What's wrong right now, worst first. Each is a reason to SCRAM a running
-- reactor and a reason not to start a stopped one.
local function problems(d)
  local p = {}
  local function add(text) p[#p + 1] = text end
  if d.getDamagePercent and d.getDamagePercent >= MAX_DAMAGE then
    add(("damage %d%% (limit %d%%)"):format(int(d.getDamagePercent), int(MAX_DAMAGE)))
  end
  if d.getTemperature and d.getTemperature >= MAX_TEMP then
    add(("temperature %d K (limit %d K)"):format(int(d.getTemperature), int(MAX_TEMP)))
  end
  if d.getCoolantFilledPercentage and d.getCoolantFilledPercentage <= MIN_COOLANT then
    add(("coolant %s (limit %s)"):format(pct(d.getCoolantFilledPercentage), pct(MIN_COOLANT)))
  end
  if d.getHeatedCoolantFilledPercentage and d.getHeatedCoolantFilledPercentage >= MAX_HEATED then
    add(("heated coolant %s (limit %s)"):format(pct(d.getHeatedCoolantFilledPercentage), pct(MAX_HEATED)))
  end
  if d.getWasteFilledPercentage and d.getWasteFilledPercentage >= MAX_WASTE then
    add(("waste %s (limit %s)"):format(pct(d.getWasteFilledPercentage), pct(MAX_WASTE)))
  end
  return p
end

---------------------------------------------------------------- acting

local function stamp() return textutils.formatTime(os.time(), true) end

local function say(text, colour)
  ui.msg, ui.msgColour = text, colour or "white"
end

local function saveLatch() files.write(LATCH_FILE, latch) end

-- Mekanism's errors read "Reactor is already active." etc.: show them as they are.
local function attempt(method, ...)
  if not reactor then return false, "can't reach the reactor" end
  local ok, err = pcall(reactor[method], ...)
  return ok, not ok and tostring(err):gsub("^.-:%d+: ", "") or nil
end

local function scram(why)
  local ok, err = attempt("scram")
  print(("%s  SCRAM: %s"):format(stamp(), why))
  if report then report.log("SCRAM: " .. why) end
  if not ok and data.getStatus then
    say("SCRAM failed: " .. err, "red")
    if errlog then errlog.warn("SCRAM failed: " .. err) end
  end
  return ok
end

local function trip(why)
  latch.reason, latch.time, latch.pausedForPower = why, stamp(), nil
  saveLatch()
  scram(why)
  say(nil) -- the latch line says why
end

-- One safety check. Runs every CHECK_EVERY seconds.
local function guard(d)
  if d.missing or not d.isFormed then return end
  local p = problems(d)
  if d.getStatus then
    if latch.reason then
      scram("started while latched (" .. latch.reason .. ")")
    elseif #p > 0 then
      trip(p[1])
    elseif PAUSE_POWER_AT and d.power and d.power >= PAUSE_POWER_AT then
      latch.pausedForPower = true
      saveLatch()
      scram(("power full (%s)"):format(pct(d.power)))
      say("Paused: the Induction Matrix is full.", "orange")
    end
  elseif latch.pausedForPower and not latch.reason then
    if d.power and d.power < RESUME_POWER_BELOW and #p == 0 and not d.isForceDisabled then
      local ok, err = attempt("activate")
      if ok then
        latch.pausedForPower = nil
        saveLatch()
        print(("%s  Restarted: the matrix has room again."):format(stamp()))
        say("Restarted: the matrix has room again.", "lime")
      else
        say("Can't restart: " .. err, "orange")
      end
    elseif not d.power then
      latch.pausedForPower = nil -- the matrix went away: the player starts it again
      saveLatch()
    end
  end
end

local function start()
  if latch.reason then return say("Latched: tap Reset first.", "orange") end
  local p = problems(data)
  if #p > 0 then return say("Can't start: " .. p[1], "red") end
  local ok, err = attempt("activate")
  if ok then
    latch.pausedForPower = nil
    saveLatch()
    say("Started.", "lime")
  else
    say(err, "orange")
  end
end

local function stop()
  latch.pausedForPower = nil
  saveLatch()
  if not data.getStatus then return say("Already stopped.", "lightGray") end
  if scram("SCRAM button") then say("SCRAMmed by hand.", "orange") end
end

local function reset()
  if not latch.reason then return say("Nothing to reset.", "lightGray") end
  local p = problems(data)
  if #p > 0 then return say("Still unsafe: " .. p[1], "red") end
  latch = {}
  saveLatch()
  say("Reset. Tap Start when ready.", "lime")
end

local function changeBurn(step)
  if not data.getBurnRate then return end
  local max = data.getMaxBurnRate or 0
  local rate = math.max(0, math.min(max, math.floor((data.getBurnRate + step) * 10 + 0.5) / 10))
  local ok, err = attempt("setBurnRate", rate)
  if ok then
    data.getBurnRate = rate
    say(("Burn rate set to %.1f mB/t."):format(rate), "white")
  else
    say(err, "orange")
  end
end

---------------------------------------------------------------- drawing

local display -- lib/screen.lua on the monitor, or this computer's screen
local win -- the window the frame being drawn goes into
local fit = screen.fit

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

-- 1234567 -> "1.23M"
local function short(n)
  if not n then return "?" end
  local units = { "", "k", "M", "G", "T" }
  local i = 1
  while math.abs(n) >= 1000 and i < #units do n, i = n / 1000, i + 1 end
  return i == 1 and ("%d"):format(int(n)) or ("%.2f%s"):format(n, units[i])
end

-- green below the warning point, orange near the limit, red past it
local function above(value, limit)
  if not value then return "lightGray" end
  return value >= limit and "red" or value >= limit * 0.85 and "orange" or "lime"
end
local function below(value, limit)
  if not value then return "lightGray" end
  return value <= limit and "red" or value <= limit * 1.5 and "orange" or "lime"
end

local function status()
  if data.missing then return "NO REACTOR", "red" end
  if not data.isFormed then return "NOT FORMED", "red" end
  if latch.reason then return "SCRAMMED", "red" end
  if data.getStatus then return "RUNNING", "green" end
  if latch.pausedForPower then return "PAUSED: POWER FULL", "orange" end
  return "STOPPED", "gray"
end

local function draw()
  local d = data
  local word, colour = status()
  local warn = ""
  if d.getFuelFilledPercentage and d.getFuelFilledPercentage <= LOW_FUEL then warn = "Fuel is low." end
  if d.isForceDisabled then warn = "Mekanism has force-disabled the reactor." end
  local key = table.concat({
    word, short(d.getTemperature), tostring(d.getDamagePercent), pct(d.getCoolantFilledPercentage),
    pct(d.getHeatedCoolantFilledPercentage), pct(d.getFuelFilledPercentage), pct(d.getWasteFilledPercentage),
    tostring(d.getBurnRate), tostring(d.getActualBurnRate), short(d.getHeatingRate), pct(d.power),
    tostring(latch.reason), tostring(ui.msg), warn,
  }, "|")
  if display:same(key) then return end

  ui.zones = {}
  local w, h
  win, w, h = display:frame()
  put(1, 1, (" "):rep(w), "white", colour)
  put(2, 1, "Fission reactor", "white", colour)
  put(w - #word, 1, word, "white", colour)

  if d.missing then
    put(2, 3, "Can't find the reactor.", "red")
    put(2, 5, fit("Put a Fission Reactor Logic Adapter (or a Reactor", w - 2))
    put(2, 6, fit("Port) on the reactor and connect it to this", w - 2))
    put(2, 7, fit("computer, touching it or over a wired modem.", w - 2))
    display:show()
    return
  end

  local barX = 28
  local barW = w - barX
  local rows = {
    { "Temperature", d.getTemperature and ("%d K"):format(int(d.getTemperature)), (d.getTemperature or 0) / DAMAGE_TEMP, above(d.getTemperature, MAX_TEMP) },
    { "Damage", d.getDamagePercent and int(d.getDamagePercent) .. "%", (d.getDamagePercent or 0) / 100, (d.getDamagePercent or 0) > 0 and "red" or "lime" },
    { "Coolant", pct(d.getCoolantFilledPercentage), d.getCoolantFilledPercentage, below(d.getCoolantFilledPercentage, MIN_COOLANT) },
    { "Heated coolant", pct(d.getHeatedCoolantFilledPercentage), d.getHeatedCoolantFilledPercentage, above(d.getHeatedCoolantFilledPercentage, MAX_HEATED) },
    { "Fuel", pct(d.getFuelFilledPercentage), d.getFuelFilledPercentage, below(d.getFuelFilledPercentage, LOW_FUEL) },
    { "Waste", pct(d.getWasteFilledPercentage), d.getWasteFilledPercentage, above(d.getWasteFilledPercentage, MAX_WASTE) },
  }
  if d.power then rows[#rows + 1] = { "Matrix", pct(d.power), d.power, "lightBlue" } end
  local y = 3
  for _, r in ipairs(rows) do
    put(2, y, fit(r[1], 14), "lightGray")
    put(17, y, fit(r[2] or "?", 10), r[4])
    bar(barX, y, barW, r[3], r[4])
    y = y + 1
  end
  y = y + 1
  put(2, y, fit("Burn rate", 14), "lightGray")
  put(17, y, fit(d.getBurnRate and ("%.1f mB/t"):format(d.getBurnRate) or "?", 10), "white")
  put(barX, y, fit(("actual %.1f, max %d"):format(d.getActualBurnRate or 0, int(d.getMaxBurnRate)), barW), "lightGray")
  y = y + 1
  put(2, y, fit("Heating", 14), "lightGray")
  put(17, y, fit(short(d.getHeatingRate) .. " mB/t", w - 17), "white")
  y = y + 2

  if latch.reason then
    put(2, y, fit(("SCRAM at %s: %s"):format(latch.time or "?", latch.reason), w - 2), "red")
    y = y + 1
  end
  if warn ~= "" and y < h - 1 then
    put(2, y, fit(warn, w - 2), "orange")
    y = y + 1
  end
  if ui.msg and y < h - 1 then put(2, y, fit(ui.msg, w - 2), ui.msgColour) end

  local x = button(2, h - 1, "Start", "white", latch.reason and "gray" or "green", start)
  x = button(x, h - 1, "SCRAM", "white", "red", stop)
  x = button(x, h - 1, "Reset", latch.reason and "black" or "white", latch.reason and "yellow" or "gray", reset)
  put(x, h - 1, "Burn", "lightGray")
  x = x + 5
  for _, b in ipairs(BURN_STEPS) do
    x = button(x, h - 1, b[1], "white", "gray", function() changeBurn(b[2]) end)
  end
  local limits = ("Limits: %d K, coolant %s, heated %s, waste %s"):format(int(MAX_TEMP), pct(MIN_COOLANT), pct(MAX_HEATED), pct(MAX_WASTE))
  put(2, h, fit(limits, w - 2), "gray")
  display:show()
end

---------------------------------------------------------------- loops

local function summary()
  local word = status()
  if data.missing or not data.isFormed then return word:lower() end
  return ("%s, %d K, burn %.1f mB/t, waste %s"):format(word:lower(), int(data.getTemperature), data.getBurnRate or 0, pct(data.getWasteFilledPercentage))
end

local function reportState()
  if not report then return end
  local state = "idle"
  if data.missing or not data.isFormed then state = "waiting"
  elseif latch.reason then state = "alert"
  elseif data.getStatus then state = "running"
  elseif latch.pausedForPower then state = "paused" end
  report.set(state, latch.reason and ("SCRAM: " .. latch.reason) or summary())
end

local function check()
  data = read()
  guard(data)
  draw()
  reportState()
end

-- One bad check is logged and the next one runs: the guard never stops watching.
local function checkLoop()
  while true do
    local ok, err = (errlog and errlog.pcall or pcall)(check)
    if not ok then say("Check failed: " .. tostring(err), "red") end
    sleep(CHECK_EVERY)
  end
end

local function alarmLoop()
  while true do
    if ALARM_SIDE then redstone.setOutput(ALARM_SIDE, latch.reason ~= nil) end
    local speaker = ALARM and latch.reason and peripheral.find("speaker")
    if speaker then
      speaker.playNote("bell", 3, 18)
      sleep(0.3)
      speaker.playNote("bell", 3, 6)
    end
    sleep(1)
  end
end

-- With the guard on a monitor, this computer's screen says so (and logs SCRAMs).
local function announce()
  if not display.name then return end
  term.clear()
  term.setCursorPos(1, 1)
  print("Fission guard running on the monitor.")
  print("Hold Ctrl+T to stop (the reactor is then unguarded).")
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
      -- also fired by turtles driving past: only redraws if the monitor moved
      findDevices()
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

findDevices()
display = screen.find({ setting = "fission.monitor", scales = { MONITOR_SCALE }, fallback = term.current() })
announce()
if not reactor then
  print("No Fission Reactor Logic Adapter or Reactor Port found yet.")
  print("Connect one; the guard picks it up when it appears.")
end
if latch.reason then print(("Still latched from before: %s. Tap Reset when safe."):format(latch.reason)) end

if report then report.init("fission guard") end
if errlog then errlog.init("fission", function() return { latch = latch.reason } end) end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, checkLoop, touchLoop, alarmLoop,
  report and report.loop or function() sleep(math.huge) end)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
