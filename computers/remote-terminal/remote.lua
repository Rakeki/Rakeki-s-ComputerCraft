-- Remote storage terminal. Far from the storage system, search what's
-- stored and pull it through a linked ender chest (EnderStorage and the
-- like: two chests on the same colours share what's in them, any distance
-- apart), or drop items in that chest to send them home.
--
--   remote                    start (startup.lua runs this)
--   remote get <n> <text>     pull n of the first stored item matching text
--   remote chest [name]       pick the ender chest (no name: from a list)
--
-- Needs an ender modem (it reaches the storage computer from anywhere) and
-- an ender chest next to it or on its wired network, whose twin is on the
-- storage computer's cable. The storage computer finds that twin itself,
-- the way turtles find their chest (lib/claim.lua), and sends what's asked
-- for there. Anything else put in it goes into storage within a few
-- seconds; what's asked for and not taken goes back after 10 minutes.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local claim = require("lib.claim") -- tells the storage computer which chest is ours
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local CHEST_FILE = "/.remote_chest" -- { chest }: the ender chest picked with 'remote chest'
local REFRESH = 15 -- seconds between fresh lists of what's stored
local REPLY_WAIT = 10 -- seconds to wait for the storage computer to answer
local STACK = 64 -- items Enter pulls

local items = {} -- what's stored: { name, label, count }, most first
local query, selected, scroll = "", 1, 0
local message = { "Looking for the storage computer...", "lightGray" }
local chest -- the ender chest's name here, nil if there's none

---------------------------------------------------------------- helpers

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("remote_changed")
end

local function status(state, detail)
  if report then report.set(state, detail) end
end

local function isInventory(name)
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t == "inventory" then return true end
  end
  return false
end

-- Every ender chest this computer can reach (touching it or on its cable).
local function enderChests()
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name) or ""
    if t:find("ender", 1, true) and isInventory(name) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- The one picked with 'remote chest', else the only ender chest there is.
local function findChest()
  local saved = files.read(CHEST_FILE)
  if type(saved) == "table" and saved.chest and peripheral.isPresent(saved.chest) then return saved.chest end
  local list = enderChests()
  if #list == 1 then return list[1] end
  return nil, #list == 0 and "no ender chest: put one next to me" or "more than one ender chest: pick one with 'remote chest'"
end

local function inChest(name)
  local ok, list = pcall(peripheral.call, chest, "list")
  local n = 0
  for _, s in pairs(ok and list or {}) do
    if s.name == name and not s.nbt then n = n + s.count end
  end
  return n
end

---------------------------------------------------------------- talking to storage

local storage = net.peer(STORAGE_PROTOCOL, { retry = 30, wait = REPLY_WAIT })

-- Ask the storage computer something and wait for its answer: nil and why
-- if there's none.
local function ask(msg)
  local reply, why = storage:ask(msg)
  if reply then return reply end
  if why == "no modem" then return nil, "no ender modem on me" end
  return nil, why == "no answer" and "the storage computer didn't answer"
    or "no storage computer answered: does it have a wireless or ender modem?"
end

-- A fresh list of what's stored.
local function refresh()
  local r, why = ask({ type = "list" })
  if not r then
    say("Storage: " .. why, "orange")
    status("waiting", why)
    return false
  end
  if type(r.items) ~= "table" then
    say("The storage computer is too old to list its items: 'install update' on it.", "orange")
    return false
  end
  items = r.items
  table.sort(items, function(a, b) return a.count > b.count end)
  os.queueEvent("remote_changed")
  status("idle", ("%d kinds of item stored"):format(#items))
  return true
end

-- Pull n of an item into the ender chest. The storage computer first checks
-- the chest is still ours (one round trip; it finds it again if not).
local function pull(it, n)
  local why
  chest, why = findChest()
  if not chest then
    say("Can't pull: " .. why .. ".", "red")
    return
  end
  local ok, err = claim.chest(ask, "delivery", chest)
  if not ok then
    say(("Can't hook the ender chest up: %s."):format(err or "no storage computer answered"), "red")
    return
  end
  local have = inChest(it.name)
  local r, whyNot = ask({ type = "deliver", items = { [it.name] = have + n } })
  if not r then
    say("Storage: " .. whyNot, "red")
    return
  end
  local got = type(r.sent) == "table" and r.sent[it.name] or 0
  local making = type(r.crafting) == "table" and r.crafting[it.name] or 0
  if r.to ~= "own" then
    say("The storage computer sent it somewhere else: try again.", "orange")
  elseif r.error then
    say("Storage couldn't move it: " .. r.error, "red")
  elseif got >= n then
    say(("Sent %d %s: it's in the ender chest."):format(got, it.label), "lime")
  elseif making > 0 then
    say(("Sent %d %s, crafting %d more: ask again in a bit."):format(got, it.label, making), "lightBlue")
  else
    say(("Sent %d %s: that's all there is."):format(got, it.label), got > 0 and "orange" or "red")
  end
  if report and got > 0 then report.log(("pulled %d %s"):format(got, it.label)) end
  refresh()
end

---------------------------------------------------------------- screen

-- q is lower case already.
local function matches()
  local q, out = query:lower(), {}
  for _, it in ipairs(items) do
    if q == "" or it.label:lower():find(q, 1, true) or it.name:lower():find(q, 1, true) then out[#out + 1] = it end
  end
  return out
end

local display = screen.new(term.current())
local put, fitText = screen.put, screen.fit

local function draw()
  local t, w, h = display:frame()
  local list = matches()
  put(t, 1, 1, (" "):rep(w), "white", "gray")
  put(t, 2, 1, "Remote storage", "yellow", "gray")
  local where = chest and chest:gsub("^[%w_]+:", "") or "no ender chest"
  put(t, w - #where, 1, where, chest and "lightGray" or "red", "gray")
  put(t, 1, 2, "Search: ", "lightGray")
  put(t, 9, 2, query, "white")

  local rows = h - 4
  selected = math.max(1, math.min(selected, #list))
  if selected <= scroll then scroll = selected - 1 end
  if selected > scroll + rows then scroll = selected - rows end
  for i = 1, rows do
    local it = list[scroll + i]
    if it then
      local sel = scroll + i == selected
      local bg = sel and "blue" or "black"
      local count = tostring(it.count)
      put(t, 1, 2 + i, fitText(" " .. it.label, w - #count - 1), "white", bg)
      put(t, w - #count, 2 + i, count .. " ", sel and "white" or "lightGray", bg)
    end
  end
  if #list == 0 then put(t, 2, 4, query ~= "" and "No matches." or "Nothing stored, or no answer yet.", "lightGray") end

  put(t, 1, h - 1, fitText(message[1], w), message[2])
  put(t, 1, h, fitText("Enter: a stack  Right: one  Drop items in the chest to send them home", w), "gray")
  t.setCursorPos(9 + #query, 2)
  t.setTextColor(colors.white)
  t.setCursorBlink(true)
  display:show()
end

local function uiLoop()
  while true do
    draw()
    local event, a = os.pullEvent()
    local list = matches()
    if event == "char" then
      query, selected = query .. a, 1
    elseif event == "key" then
      if a == keys.backspace then
        query, selected = query:sub(1, -2), 1
      elseif a == keys.delete then
        query, selected = "", 1
      elseif a == keys.up then
        selected = selected - 1
      elseif a == keys.down then
        selected = selected + 1
      elseif a == keys.pageUp then
        selected = selected - 10
      elseif a == keys.pageDown then
        selected = selected + 10
      elseif (a == keys.enter or a == keys.right) and list[selected] then
        say("Asking the storage computer...", "lightGray")
        draw()
        pull(list[selected], a == keys.enter and STACK or 1)
      end
    end
  end
end

-- A fresh list now and then, and a look for the ender chest (it may be
-- placed or broken while this runs).
local function refreshLoop()
  while true do
    local why
    chest, why = findChest()
    if not chest then say("No chest yet: " .. why .. ".", "orange") end
    refresh()
    sleep(REFRESH)
  end
end

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "chest" then
  local name = args[2]
  if not name then
    local list = enderChests()
    if #list == 0 then
      print("No ender chest here. Put one next to me, or on my wired network.")
      return
    end
    for i, n in ipairs(list) do print(("%2d  %s"):format(i, n)) end
    write("Which one? (Enter to cancel) ")
    local text = read()
    if text == "" then return end
    name = list[tonumber(text)] or text
  end
  if not peripheral.isPresent(name) then
    print(name .. " isn't here.")
    return
  end
  files.write(CHEST_FILE, { chest = name })
  print(("Using %s. Its twin needs a wired modem on the storage cable."):format(name))
  return
end

if not net.open() then
  print("I need an ender modem (or a wireless one near the storage computer).")
  return
end

if args[1] == "get" then
  local n, text = tonumber(args[2]), table.concat(args, " ", 3):lower()
  if not n or n < 1 or text == "" then
    print("Usage: remote get <how many> <item name>")
    return
  end
  if not refresh() then
    print(message[1])
    return
  end
  query = text
  local it = matches()[1]
  if not it then
    print(("Nothing stored matches '%s'."):format(text))
    return
  end
  pull(it, math.floor(n))
  print(message[1])
  return
end

term.clear()
if errlog then errlog.init("remote") end
if report then report.init("remote") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, refreshLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
