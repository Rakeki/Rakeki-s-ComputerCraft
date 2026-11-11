-- Update watcher: keeps every computer and turtle in range up to date with
-- the website. It checks the website's program list every few minutes, hears
-- which versions each computer has installed (they send them with their
-- status reports, lib/report.lua), and asks the ones that are out of date to
-- update: each runs 'install boot' and reboots if anything changed. One at a
-- time, a few seconds apart, so the base never goes down all at once. Then
-- it updates itself the same way.
--
-- Usage:
--   updates                      run the watcher (startup.lua does this)
--   updates auto on|off          off: only show what's out of date; U (or Update all) pushes
--   updates every <minutes>      how often to check the website (default 2)
--   updates monitor [name|none]  pick the monitor it shows the list on
local screen = require("lib.screen")
local net = require("lib.net")
local report = require("lib.report")
local hasErrlog, errlog = pcall(require, "lib.errlog")
if not hasErrlog then errlog = nil end

---------------------------------------------------------------- tunables

local STATUS = "cc_status" -- every computer's status report, with its installed versions
local PROTOCOL = "cc_update" -- what the computers answer on (lib/report.lua)
local INSTALLER = "/install.lua" -- the website's address is read from it
local FETCH_WAIT = 10 -- seconds to wait for the program list
local ASK_WAIT = 5 -- seconds to wait for a computer to say yes or no
local GAP = 5 -- seconds between asking one computer and the next
local RETRY = 180 -- seconds before asking a computer that's still out of date again
local MAX_TRIES = 5 -- asks per new version before giving up on a computer (U tries again)
local ONLINE = 40 -- a computer heard within this many seconds is in range (they report every 10)
local FORGET = 3600 -- a computer unheard this long drops off the list

local AUTO_SETTING = "updates.auto"
local EVERY_SETTING = "updates.every"
settings.define(AUTO_SETTING, { description = "Update out-of-date computers by itself (false: only when you press U).", default = true, type = "boolean" })
settings.define(EVERY_SETTING, { description = "Minutes between checks of the website for new versions.", default = 2, type = "number" })

local args = { ... }

---------------------------------------------------------------- commands

if args[1] == "monitor" then
  if screen.choose("updates.monitor", args[2]) then
    print("Saved. A running watcher moves there now.")
    os.queueEvent("updates_monitor")
  end
  return
elseif args[1] == "auto" then
  if args[2] ~= "on" and args[2] ~= "off" then return print("Usage: updates auto on|off") end
  settings.set(AUTO_SETTING, args[2] == "on")
  settings.save()
  print(args[2] == "on" and "It will update computers by itself." or "It will only show what's out of date. Press U to update them.")
  return
elseif args[1] == "every" then
  local m = tonumber(args[2])
  if not m or m < 1 then return print("Usage: updates every <minutes> (1 or more)") end
  settings.set(EVERY_SETTING, m)
  settings.save()
  print(("It will check the website every %d minutes."):format(m))
  return
elseif args[1] then
  return print("Usage: updates [auto on|off | every <minutes> | monitor [name|none]]")
end

---------------------------------------------------------------- the website

-- The installer knows the website's address (the build fills it in).
local function siteUrl()
  if not fs.exists(INSTALLER) then return nil end
  local f = fs.open(INSTALLER, "r")
  local body = f.readAll()
  f.close()
  local url = body:match('local SITE = "([^"]+)"')
  if not url or url:find("{{", 1, true) then return nil end
  return url
end

local SITE = siteUrl()
if not SITE then
  print("I need the installer to know where the website is.")
  print("Install me with: wget run <site>/install.lua update-watcher")
  return
end
if not http then
  print("http is turned off in the ComputerCraft config, so I can't see the website.")
  return
end

local manifest -- the website's program list, once fetched
local site = { at = nil, err = nil, count = 0 } -- when it was last fetched and what went wrong

-- http.get can hang when the website can't be reached: ask in the
-- background and give up after a deadline.
local function fetch(url)
  local ok, err = http.request(url)
  if not ok then return nil, err end
  local timer = os.startTimer(FETCH_WAIT)
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "http_success" and a == url then
      os.cancelTimer(timer)
      local body = b.readAll()
      b.close()
      return body
    elseif ev == "http_failure" and a == url then
      os.cancelTimer(timer)
      if c then c.close() end
      return nil, b
    elseif ev == "timer" and a == timer then
      return nil, "timed out"
    end
  end
end

local function checkSite()
  local body, err = fetch(SITE .. "/manifest.json")
  local list = body and textutils.unserializeJSON(body)
  if type(list) == "table" and type(list.programs) == "table" then
    manifest, site.err, site.count = list, nil, #(list.order or {})
  else
    site.err = body and "the program list is broken" or tostring(err)
  end
  site.at = os.clock()
  os.queueEvent("updates_redraw")
end

-- What's out of date in a computer's versions (program -> version): a sorted
-- list of names, or nil when that can't be told yet.
local function staleOf(versions)
  if not manifest or type(versions) ~= "table" then return nil end
  local out = {}
  for name, version in pairs(versions) do
    local program = manifest.programs[name]
    -- an old name another program took the place of updates into it on boot
    if program and (program.alias or program.version ~= version) then
      out[#out + 1] = (name:gsub("^plan:", "plan "))
    end
  end
  table.sort(out)
  return out
end

---------------------------------------------------------------- computers

-- id -> { label, role, kind, state, versions, seen, ask = { key, tries, at, result, colour, done } }
local computers = {}

local function listen()
  while true do
    local from, msg = rednet.receive(STATUS)
    if type(msg) == "table" and msg.type == "status" then
      local c = computers[from] or { ask = { tries = 0, at = -math.huge } }
      computers[from] = c
      c.label, c.role, c.kind, c.state = msg.label, msg.role, msg.kind, msg.state
      c.versions = type(msg.versions) == "table" and msg.versions or nil
      c.seen = os.clock()
      os.queueEvent("updates_redraw")
    end
  end
end

-- One line on what's going on with a computer, and its colour.
local function describe(c)
  local now = os.clock()
  if not c.versions then return "doesn't send versions: updates on its next boot", "gray" end
  local stale = staleOf(c.versions)
  if not stale then return "waiting for the website", "gray" end
  if #stale == 0 then return "up to date", "lime" end
  local list = table.concat(stale, ", ")
  if now - c.seen > ONLINE then return "out of range, needs " .. list, "gray" end
  if c.state == "updating" then return "updating " .. list, "yellow" end
  local ask = c.ask
  if ask.key == list and ask.result then return ask.result .. ": " .. list, ask.colour end
  return "needs " .. list, "orange"
end

-- Ask the next computer that needs it; true if one was asked.
local function askNext()
  local auto = settings.get(AUTO_SETTING) ~= false
  local now = os.clock()
  local ids = {}
  for id in pairs(computers) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local c = computers[id]
    if now - c.seen > FORGET then
      computers[id] = nil
    else
      local stale = staleOf(c.versions)
      if stale and #stale > 0 and now - c.seen <= ONLINE and c.state ~= "updating" then
        local ask, key = c.ask, table.concat(stale, ", ")
        if ask.key ~= key then ask.key, ask.tries, ask.at, ask.result, ask.done = key, 0, -math.huge, nil, false end
        if (auto or ask.forced) and not ask.done and ask.tries < MAX_TRIES and now - ask.at >= RETRY then
          ask.tries, ask.at, ask.forced = ask.tries + 1, now, nil
          ask.result, ask.colour = "asking", "yellow"
          os.queueEvent("updates_redraw")
          local reply = net.ask(id, PROTOCOL, { type = "update" }, { wait = ASK_WAIT })
          if not reply then
            ask.result, ask.colour = "no answer (not running a program with lib/report.lua?)", "red"
          elseif reply.ok then
            ask.result, ask.colour = "asked to update", "yellow"
          else
            ask.result, ask.colour, ask.done = "says no, " .. tostring(reply.why), "red", true
          end
          if not reply and ask.tries >= MAX_TRIES then ask.result = "gave up, no answer" end
          os.queueEvent("updates_redraw")
          return true
        elseif ask.tries >= MAX_TRIES and ask.result == "asked to update" then
          -- it said yes every time but never came back newer
          ask.result, ask.colour = ("asked %d times, still old"):format(MAX_TRIES), "red"
        end
      end
    end
  end
  return false
end

-- U / Update all: every computer gets asked once more now, even ones it gave
-- up on or that said no, and even with auto off.
local function pushAll()
  for _, c in pairs(computers) do
    c.ask.tries, c.ask.done, c.ask.at, c.ask.forced = 0, false, -math.huge, true
  end
end

---------------------------------------------------------------- loops

-- Sleep for seconds, or until one of the named events comes; returns it.
local function nap(seconds, ...)
  local wanted = {}
  for _, e in ipairs({ ... }) do wanted[e] = true end
  local timer = os.startTimer(seconds)
  while true do
    local ev, a = os.pullEvent()
    if ev == "timer" and a == timer then return nil end
    if wanted[ev] then os.cancelTimer(timer) return ev end
  end
end

-- This computer's own versions, read like report.lua does.
local function readOwn()
  local versions
  if fs.exists("/.installed_versions") then
    local f = fs.open("/.installed_versions", "r")
    versions = textutils.unserialize(f.readAll() or "")
    f.close()
  end
  return type(versions) == "table" and versions or nil
end
local own = { versions = readOwn() }

local selfNote -- what happened when it last tried to update itself
local selfTriedAt -- the website check it last tried after

local function website()
  while true do
    checkSite()
    nap(math.max(1, settings.get(EVERY_SETTING) or 2) * 60, "updates_check")
  end
end

local function pusher()
  local forced = false -- U was pressed: this computer too, even with auto off
  while true do
    local asked = askNext()
    if not asked then
      -- everyone else is done (or can't be): now this computer
      local mine = staleOf(own.versions)
      -- once per look at the website (the installer fetches the list each try), or on U
      if mine and #mine > 0 and (forced or (settings.get(AUTO_SETTING) ~= false and selfTriedAt ~= site.at)) then
        selfTriedAt, forced = site.at, false
        local _, why = report.updateNow() -- reboots if it updated
        selfNote = why
      end
      forced = false
    end
    if nap(GAP, "updates_push") then
      pushAll()
      forced = true
    end
  end
end

---------------------------------------------------------------- screen

local term_ = screen.new(term.current())
local board = screen.find({ setting = "updates.monitor", scales = { 1, 0.5 }, minW = 39, minH = 10 })
local BUTTONS = { { "U", " Update all " }, { "C", " Check now " }, { "A", " Auto " } }

local function ago(t)
  if not t then return "never" end
  local s = math.floor(os.clock() - t)
  if s < 60 then return s .. "s ago" end
  return math.floor(s / 60) .. "m ago"
end

-- Rows to show, problems first.
local function rows()
  local out = {}
  for id, c in pairs(computers) do
    local text, colour = describe(c)
    local rank = (colour == "red" and 0) or (colour == "orange" and 1) or (colour == "yellow" and 2) or (colour == "gray" and 3) or 4
    out[#out + 1] = { id = id, name = c.label or ("#" .. id), role = c.role or c.kind or "", text = text, colour = colour, rank = rank }
  end
  table.sort(out, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.name < b.name
  end)
  return out
end

-- Where each button is on the bottom row: list of { key, x0, x1 }.
local function buttonSpots(w)
  local spots, x = {}, 1
  for _, b in ipairs(BUTTONS) do
    local label = b[1] == "A" and (" Auto: " .. (settings.get(AUTO_SETTING) ~= false and "on " or "off")) or b[2]
    spots[#spots + 1] = { key = b[1], x0 = x, x1 = x + #label - 1, label = label }
    x = x + #label + 1
  end
  return spots
end

local function draw(s)
  if not s.target then return end
  local list = rows()
  local w, h = s:size()
  local mine = staleOf(own.versions)
  local selfText = not own.versions and "this computer doesn't know its versions"
    or not mine and "" or #mine == 0 and "this computer is up to date"
    or ("this computer needs %s%s"):format(table.concat(mine, ", "), selfNote and (" (" .. selfNote .. ")") or "")
  local siteText = site.err and ("Website: can't reach it (%s), tried %s"):format(site.err, ago(site.at))
    or site.at and ("Website: %d programs, checked %s"):format(site.count, ago(site.at)) or "Website: checking..."
  local counts = { lime = 0, other = 0 }
  for _, r in ipairs(list) do
    if r.colour == "lime" then counts.lime = counts.lime + 1 else counts.other = counts.other + 1 end
  end
  local parts = { siteText, selfText, tostring(settings.get(AUTO_SETTING)) }
  for _, r in ipairs(list) do parts[#parts + 1] = r.name .. r.role .. r.text .. r.colour end
  if s:same(table.concat(parts, "|")) then return end

  local win
  win, w, h = s:frame()
  screen.put(win, 1, 1, screen.fit(" Update watcher", w), "white", "blue")
  local summary = ("%d up to date, %d not "):format(counts.lime, counts.other)
  if #summary < w - 16 then screen.put(win, w - #summary + 1, 1, summary, "white", "blue") end
  screen.put(win, 1, 2, screen.fit(siteText, w), site.err and "red" or "lightGray")
  screen.put(win, 1, 3, screen.fit(selfText, w), mine and #mine > 0 and "orange" or "lightGray")
  local nameW = math.min(16, math.floor(w / 3))
  local roleW = w >= 57 and 14 or 0 -- the status matters more on a computer's 51 columns
  local top, bottom = 5, h - 1
  if #list == 0 then
    screen.put(win, 1, top, screen.fit("No computers heard yet. They report every 10s", w), "gray")
    screen.put(win, 1, top + 1, screen.fit("once they run a program with lib/report.lua.", w), "gray")
  end
  local room = bottom - top + 1
  for i, r in ipairs(list) do
    local y = top + i - 1
    if i == room and #list > room then
      screen.put(win, 1, y, screen.fit(("+%d more"):format(#list - room + 1), w), "gray")
      break
    end
    screen.put(win, 1, y, screen.fit(r.name, nameW), "white")
    if roleW > 0 then screen.put(win, nameW + 2, y, screen.fit(r.role, roleW), "lightGray") end
    local x = nameW + 2 + (roleW > 0 and roleW + 1 or 0)
    screen.put(win, x, y, screen.fit(r.text, w - x + 1), r.colour)
  end
  for _, b in ipairs(buttonSpots(w)) do
    if b.x1 <= w then screen.put(win, b.x0, h, b.label, "black", b.key == "U" and "orange" or "lightGray") end
  end
  s:show()
end

local function press(key)
  if key == "U" then
    os.queueEvent("updates_push")
  elseif key == "C" then
    os.queueEvent("updates_check")
  elseif key == "A" then
    settings.set(AUTO_SETTING, settings.get(AUTO_SETTING) == false)
    settings.save()
  end
  os.queueEvent("updates_redraw")
end

local function ui()
  local timer = os.startTimer(1)
  while true do
    draw(term_)
    draw(board)
    local ev = { os.pullEvent() }
    if ev[1] == "timer" and ev[2] == timer then
      timer = os.startTimer(1)
    elseif ev[1] == "key" then
      local k = keys.getName(ev[2]) or ""
      if k == "u" or k == "c" or k == "a" then press(k:upper()) end
    elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" or ev[1] == "updates_monitor" then
      board:refresh()
    else
      for _, s in ipairs({ term_, board }) do
        local x, y = s:clicked(ev)
        if x and s.target then
          local _, h = s:size()
          if y == h then
            for _, b in ipairs(buttonSpots((s:size()))) do
              if x >= b.x0 and x <= b.x1 then press(b.key) end
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------- main

local function main()
  require("lib.label").set("Updater")
  report.init("update watcher")
  report.set("watching", "checking the website")
  if not net.open() then print("No wireless or ender modem: I can only see myself.") end
  -- what the status server shows for this computer
  local function status()
    while true do
      local n = 0
      for id, c in pairs(computers) do
        if #(staleOf(c.versions) or {}) > 0 then n = n + 1 end
      end
      report.set("watching", n == 0 and "everything is up to date" or ("%d computers out of date"):format(n))
      nap(2, "updates_redraw")
    end
  end
  parallel.waitForAny(listen, website, pusher, ui, status, report.loop, function() net.keepOpen() end)
end

if errlog then errlog.init("updates") end
local ok, err = (errlog and errlog.pcall or pcall)(main)
if not ok then
  report.set("error", tostring(err))
  printError(err)
end
