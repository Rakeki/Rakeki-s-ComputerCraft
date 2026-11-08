-- Display: a monitor that shows animations, a different one every hour.
-- Animations are files in /animations, installed from the website one by
-- one like building plans ('install animations' lists them, 'install
-- animation <name>' adds one). It goes through them in name order, picks up
-- new ones as they're installed and remembers where it was across reboots.
--
--   display                    start showing (startup.lua runs it)
--   display list               the animations here, and which one is on
--   display next               show the next one now
--   display show <name>        show this one now (its hour starts now)
--   display every <minutes>    how long each one stays on (60 unless set)
--   display monitor [name]     pick the monitor ('none': this computer's screen)
--
-- Without a monitor it shows them on the computer's own screen.
local screen = require("lib.screen") -- flicker-free drawing
local files = require("lib.files") -- crash-safe save files
local anim = require("anim") -- loads and paints animations
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local DIR = "/animations" -- where 'install animation' puts them
local STATE_FILE = "/.display_state" -- which one is on and since when
local EVERY_SETTING = "display.every" -- minutes each animation stays on
local DEFAULT_EVERY = 60 -- minutes, when the setting isn't set
local RESCAN = 5 -- seconds between looks for new, changed or removed animations
local MONITOR_SCALES = { 0.5 } -- text size on the monitor (0.5: the most room for the art)
local EVENT = "display_next" -- queued by the commands, so a running copy follows at once

settings.define(EVERY_SETTING, { type = "number", default = DEFAULT_EVERY,
  description = "Minutes each animation stays on the display before the next." })

---------------------------------------------------------------- animations here

local function now() return os.epoch("utc") end

local function names()
  local list = {}
  if fs.isDir(DIR) then
    for _, f in ipairs(fs.list(DIR)) do
      local name = f:match("^(.+)%.lua$")
      if name and not fs.isDir(fs.combine(DIR, f)) then list[#list + 1] = name end
    end
  end
  table.sort(list)
  return list
end

local function pathOf(name) return fs.combine(DIR, name .. ".lua") end

local function modified(name)
  local ok, attr = pcall(fs.attributes, pathOf(name))
  return ok and attr and attr.modified or 0
end

local function loadAnim(name)
  local f = fs.open(pathOf(name), "r")
  if not f then return nil, "it isn't there any more" end
  local source = f.readAll()
  f.close()
  return anim.load(source, name)
end

local function indexOf(list, name)
  for i, n in ipairs(list) do
    if n == name then return i end
  end
end

-- The one after name in list (round to the first), skipping any in skip.
local function after(list, name, skip)
  local start = indexOf(list, name) or 0
  for i = 1, #list do
    local n = list[(start + i - 1) % #list + 1]
    if not (skip and skip[n]) then return n end
  end
end

local function readState() return files.read(STATE_FILE) or {} end
local function saveState(name) files.write(STATE_FILE, { name = name, since = now() }) end

local function every() return math.max(1, tonumber(settings.get(EVERY_SETTING)) or DEFAULT_EVERY) * 60000 end

---------------------------------------------------------------- commands

local args = { ... }

local function command()
  local list = names()
  local state = readState()
  if args[1] == "list" then
    if #list == 0 then
      print("No animations here yet.")
      print("See them with: install animations")
      return print("Add one with: install animation <name>")
    end
    print(("Animations here (each on for %d min):"):format(every() / 60000))
    for _, n in ipairs(list) do
      local a, err = loadAnim(n)
      local line = ("  %s%s"):format(n, a and a.title ~= n and (" - " .. a.title) or "")
      if not a then line = line .. " (can't show it: " .. tostring(err) .. ")" end
      if n == state.name then line = line .. "  <- on now" end
      print(line)
    end
  elseif args[1] == "next" then
    local n = after(list, state.name)
    if not n then return print("No animations here yet: install animation <name>") end
    saveState(n)
    print(("Showing %s now."):format(n))
  elseif args[1] == "show" and args[2] then
    if not indexOf(list, args[2]) then
      print(("There's no animation called %s here."):format(args[2]))
      return print("Install it with: install animation " .. args[2])
    end
    saveState(args[2])
    print(("Showing %s now."):format(args[2]))
  elseif args[1] == "every" and tonumber(args[2]) and tonumber(args[2]) >= 1 then
    settings.set(EVERY_SETTING, tonumber(args[2]))
    settings.save()
    print(("Each animation now stays on for %d min."):format(tonumber(args[2])))
  elseif args[1] == "monitor" then
    local pick = screen.choose("display.monitor", args[2])
    if pick then print(("Showing them on %s from now on."):format(pick)) end
  else
    print("Usage: display                  start showing")
    print("       display list             what's here")
    print("       display next             the next one now")
    print("       display show <name>      this one now")
    print("       display every <minutes>  how long each stays on")
    print("       display monitor [name]   pick the monitor")
    return
  end
  os.queueEvent(EVENT) -- a copy running in another tab follows at once
end

if args[1] then return command() end

---------------------------------------------------------------- showing

local display -- lib/screen.lua on the monitor, or this computer's screen
local current -- { name, a, stamp, frames = { [t] = rows }, w, h }
local broken = {} -- name -> why it can't be shown (until its file changes)
local brokenStamp = {}

local function where() return display.name and ("on " .. display.name) or "on this computer's screen" end

local function announce()
  if display.name then
    term.clear()
    term.setCursorPos(1, 1)
    print(("Showing animations %s."):format(where()))
    print(current and ("Now: " .. current.a.title) or "Nothing to show yet.")
    print("'display list' shows what's here, 'display next' moves on.")
    print("Hold Ctrl+T to stop.")
  end
  if report then
    report.set(current and "running" or "idle", current and ("showing " .. current.a.title .. " " .. where())
      or "no animations installed")
  end
end

local function markBroken(name, err)
  broken[name], brokenStamp[name] = tostring(err), modified(name)
  if errlog then errlog.warn(("Animation %s can't be shown: %s"):format(name, tostring(err))) end
end

-- Works out which animation should be on (the saved one, the next after its
-- time is up, the first when it's gone) and loads it if it isn't already.
local function choose()
  local list = names()
  for n in pairs(broken) do
    if not indexOf(list, n) or modified(n) ~= brokenStamp[n] then broken[n] = nil end -- fixed or gone: try again
  end
  local state = readState()
  local name = state.name
  if not indexOf(list, name) or broken[name] then
    name = after(list, name, broken)
  elseif now() - (state.since or 0) >= every() then
    name = after(list, name, broken)
  end
  if not name then
    if current then current = nil; announce() end
    return
  end
  if name ~= state.name or now() - (state.since or 0) >= every() then saveState(name) end

  local stamp = modified(name)
  if current and current.name == name and current.stamp == stamp then return end
  local a, err = loadAnim(name)
  if not a then
    markBroken(name, err)
    return choose() -- the next one; ends once every one is marked broken
  end
  current = { name = name, a = a, stamp = stamp, frames = {} }
  announce()
end

local function centre(win, w, y, text, fg)
  screen.put(win, math.max(1, math.floor((w - #text) / 2) + 1), y, text, fg)
end

local function message(win, w, h)
  local lines = { { "No animations to show yet.", "yellow" }, { "", "white" },
    { "On this computer, type:", "lightGray" }, { "install animations", "white" },
    { "install animation <name>", "white" } }
  local n = 0
  for _ in pairs(broken) do n = n + 1 end
  if n > 0 then lines[1] = { ("%d animation%s here can't be shown."):format(n, n == 1 and "" or "s"), "orange" } end
  local top = math.max(1, math.floor((h - #lines) / 2) + 1)
  for i, l in ipairs(lines) do centre(win, w, top + i - 1, l[1], l[2]) end
end

-- Frame t of the current animation; each frame is painted once per screen size.
local function draw(t)
  local win, w, h = display:frame()
  if not current then
    message(win, w, h)
    return display:show()
  end
  if current.w ~= w or current.h ~= h then current.frames, current.w, current.h = {}, w, h end
  local rows = current.frames[t]
  if not rows then
    local ok, res = pcall(anim.frame, current.a, t, w, h)
    if not ok then
      markBroken(current.name, res)
      current = nil
      choose()
      return
    end
    rows, current.frames[t] = res, res
  end
  for r = 1, h do
    win.setCursorPos(1, r)
    win.blit(rows[r][1], rows[r][2], rows[r][3])
  end
  display:show()
end

local function main()
  display = screen.find({ scales = MONITOR_SCALES, setting = "display.monitor", fallback = term.current() })
  choose()
  announce()
  local t, timer, lookAt = 1, os.startTimer(0), now() + RESCAN * 1000
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == timer then
      if now() >= lookAt then
        lookAt = now() + RESCAN * 1000
        local was = current
        choose()
        if current ~= was then t = 1 end
      end
      if current and t > current.a.length then t = 1 end
      draw(t)
      t = current and (t % current.a.length + 1) or 1
      timer = os.startTimer(current and current.a.frameTime or 1)
    elseif ev[1] == EVENT then
      if display:refresh() then announce() end -- 'display monitor' may have picked another
      choose()
      t = 1
    elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
      -- also fired by turtles driving past: only acts if the monitor came or went
      if display:refresh() then announce() end
    end
  end
end

if report then report.init("display") end
if errlog then errlog.init("display") end

local function run()
  local ok, err
  if errlog then ok, err = errlog.pcall(main) else ok, err = pcall(main) end
  if not ok then
    if report then report.set("error", tostring(err)) end
    error(err, 0)
  end
end

if report then parallel.waitForAny(run, report.loop) else run() end
