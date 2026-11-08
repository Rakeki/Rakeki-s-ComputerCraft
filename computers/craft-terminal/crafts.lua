-- Craft terminal. Lists everything the storage system has a recipe for (and,
-- once the overseer has counted, how many could be made now, and how many
-- are stored already), and orders crafts: pick an item, say how many, and
-- the craft overseer has them made, the part it hasn't the items for yet as
-- soon as they come in (ordering it again with 0 stops that). They
-- turn up in the chest next to this computer, or stay in storage. The
-- storage computer's own terminal (or a remote terminal) is for taking out
-- what's stored; this one is for having things made.
--
--   crafts                     start (startup.lua runs this)
--   crafts make <n> <text>     craft n of the first item with a recipe matching text
--   crafts chest [name|none]   pick the chest crafts go to (no name: from a list; none: keep them in storage)
--
-- Asks the craft overseer (computers/craft-overseer, the recipe server) for
-- the list and orders on "craft_overseer" ("craftable", "craft": lib/crafts.lua),
-- and the storage computer for its chest on "storage"; over the storage
-- cable's wired modem, or a wireless or ender modem. The overseer sends what's
-- made into the chest through the storage computer. The chest is found the way turtles find theirs (lib/claim.lua):
-- it needs a wired modem on the storage cable, or it can be a linked ender
-- chest whose twin is on that cable.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local claim = require("lib.claim") -- tells the storage computer which chest is ours
local crafts = require("lib.crafts") -- the craft overseer: the list and orders
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local CHEST_FILE = "/.crafts_chest" -- { chest } (or chest = "none"): picked with 'crafts chest'
local REFRESH = 10 -- seconds between fresh lists of what can be crafted
local NOT_READY_WAIT = 3 -- seconds between asks while the overseer is still working the list out
local REPLY_WAIT = 10 -- seconds to wait for the storage computer to answer
local STACK = 64 -- how many an order is for unless you type a number
local MAX_ORDER = 9999 -- most you can type (the storage computer caps it too)

local items = {} -- what can be ordered: { name, label, count (how many could be made now, if known), stored, pattern }
local all, allKey = nil, nil -- every recipe the overseer has ({ name, label, pattern }), and which list it is
local wanted = {} -- name -> { left, why }: my orders the overseer makes once there's enough
local making = {} -- what's being made now: { name, label, count }
local info = { ready = false } -- the rest of the last answer: ready, queue, problem, crafter
local query, selected, scroll = "", 1, 0
local asking -- the amount prompt: { it, text } while it's open
local toChest = true -- crafts go to the chest (if there is one), else into storage
local chest -- the chest crafts go to here, nil if there's none
local waiting = {} -- name -> { label, want, base }: ordered for the chest, not all there yet
local message = { "Looking for the storage computer...", "lightGray" }

---------------------------------------------------------------- helpers

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("crafts_changed")
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

-- The chest picked with 'crafts chest', else the first one touching this
-- computer. None: crafts stay in storage.
local function findChest()
  local saved = files.read(CHEST_FILE)
  if type(saved) == "table" and saved.chest == "none" then return nil, "set to keep crafts in storage" end
  if type(saved) == "table" and saved.chest then
    if peripheral.isPresent(saved.chest) then return saved.chest end
    return nil, saved.chest .. " is gone"
  end
  for _, side in ipairs(rs.getSides()) do
    if peripheral.isPresent(side) and isInventory(side) then return side end
  end
  return nil, "no chest next to me"
end

local function inChest(name)
  if not chest then return 0 end
  local ok, list = pcall(peripheral.call, chest, "list")
  local n = 0
  for _, s in pairs(ok and list or {}) do
    if s.name == name and not s.nbt then n = n + s.count end
  end
  return n
end

local function shortCount(n)
  if n >= 10000 then return ("%dk"):format(math.floor(n / 1000)) end
  return tostring(n)
end

---------------------------------------------------------------- talking to storage

local storage = net.peer(STORAGE_PROTOCOL, { open = "any", retry = 30, wait = REPLY_WAIT })

-- Ask the storage computer something and wait for its answer: nil and why
-- if there's none.
local function ask(msg)
  local reply, why = storage:ask(msg)
  if reply then return reply end
  if why == "no modem" then return nil, "no modem on me" end
  return nil, why == "no answer" and "the storage computer didn't answer"
    or "no storage computer answered: is my modem on its cable (and red), or in wireless range?"
end

-- A fresh list of what can be crafted and what's being made.
local function refresh()
  local r, why = crafts.ask({ type = "craftable", have = allKey })
  if not r then
    say("Crafting: " .. why, "orange")
    status("waiting", why)
    return false
  end
  if type(r.items) ~= "table" then
    say("The craft overseer is too old for a craft terminal: 'install update' on it.", "orange")
    status("waiting", "craft overseer too old")
    return false
  end
  making = type(r.making) == "table" and r.making or {}
  info = { ready = r.ready, queue = r.queue or 0, problem = r.problem, crafter = r.crafter }
  if type(r.all) == "table" then all, allKey = r.all, r.key end
  if r.key == nil then all, allKey = nil, nil end -- an older overseer: only what can be made now
  wanted = {}
  for _, w in ipairs(type(r.wanted) == "table" and r.wanted or {}) do wanted[w.name] = { left = w.left, why = w.why } end
  if all then
    -- every recipe, with how many could be made now where the overseer has counted it
    local now = {}
    for _, it in ipairs(r.items) do now[it.name] = it end
    items = {}
    for i, it in ipairs(all) do
      local c = now[it.name]
      items[i] = { name = it.name, label = it.label, pattern = it.pattern, count = c and c.count, stored = c and c.stored }
    end
  else
    items = r.items
    for _, it in ipairs(items) do it.pattern = it.count == nil end
    table.sort(items, function(a, b) return a.label:lower() < b.label:lower() end)
  end
  table.sort(making, function(a, b) return a.count > b.count end)
  -- orders for the chest that have all turned up, or that nothing is making or waiting to make any more
  local busy = {}
  for _, m in ipairs(making) do busy[m.name] = true end
  for name in pairs(wanted) do busy[name] = true end
  for name, w in pairs(waiting) do
    local got = inChest(name) - w.base
    if got >= w.want then
      waiting[name] = nil
      say(("%d %s: it's in the chest."):format(w.want, w.label), "lime")
    elseif not busy[name] then
      waiting[name] = nil
    end
  end
  local nWanted = 0
  for _ in pairs(wanted) do nWanted = nWanted + 1 end
  if #making > 0 then
    status("working", ("%d kinds of item being crafted"):format(#making))
  elseif nWanted > 0 then
    status("waiting", ("%d orders waiting for items"):format(nWanted))
  else
    status("idle", ("%d things can be crafted"):format(#items))
  end
  os.queueEvent("crafts_changed")
  return true
end

-- Order n of an item: into the chest if there is one (and toChest), else
-- into storage. The storage computer checks the chest is still ours first
-- (one round trip; it finds it again if not).
local function order(it, n)
  chest = findChest()
  local to = toChest and chest and "chest" or "store"
  if to == "chest" then
    local ok, err = claim.chest(ask, "delivery", chest)
    if not ok then
      say(("Can't hook the chest up: %s."):format(err or "no storage computer answered"), "red")
      return
    end
  end
  local base = to == "chest" and inChest(it.name) or 0
  -- wait: what can't be made yet is made once there's enough (an older overseer ignores it)
  local r, whyNot = crafts.ask({ type = "craft", item = it.name, count = n, to = to, wait = true })
  if not r then
    say("Crafting: " .. whyNot, "red")
    return
  end
  local made, later = tonumber(r.making) or 0, tonumber(r.waiting) or 0
  local where = to == "chest" and r.to == "own" and "it comes to the chest" or "into storage"
  if made + later <= 0 then
    say(("Can't craft %s: %s."):format(it.label, r.why or "the craft overseer didn't say why"), "red")
  else
    if to == "chest" and r.to == "own" then
      waiting[it.name] = { label = it.label, want = made + later + (waiting[it.name] and waiting[it.name].want or 0),
        base = waiting[it.name] and waiting[it.name].base or base }
    end
    if later <= 0 then
      say(("Crafting %d %s: %s%s."):format(made, it.label, where, r.why and " (" .. r.why .. ")" or ""), "lightBlue")
    elseif made > 0 then
      say(("Crafting %d %s now, %d more once there's enough: %s."):format(made, it.label, later, where), "lightBlue")
    else
      say(("%d %s will be made once there's enough (%s)."):format(later, it.label, r.why or "short"), "yellow")
    end
  end
  if report and made > 0 then report.log(("ordered %d %s"):format(made, it.label)) end
  refresh()
end

---------------------------------------------------------------- screen

local function matches()
  local q, out = query:lower(), {}
  for _, it in ipairs(items) do
    if q == "" or it.label:lower():find(q, 1, true) or it.name:lower():find(q, 1, true) then out[#out + 1] = it end
  end
  return out
end

-- How many the prompt starts at: a stack, or as many as can be made.
local function defaultAmount(it) return it.count and math.min(STACK, it.count) or STACK end

local display = screen.new(term.current())
local put, fitText = screen.put, screen.fit

local function whereText()
  if not (toChest and chest) then return "into storage" end
  for _, side in ipairs(rs.getSides()) do
    if chest == side then return ("to the chest (%s)"):format(side) end
  end
  return "to " .. (chest:gsub("^[%w_]+:", ""))
end

local function draw()
  local t, w, h = display:frame()
  local list = matches()
  put(t, 1, 1, (" "):rep(w), "white", "gray")
  put(t, 2, 1, "Crafting", "yellow", "gray")
  local where = whereText()
  put(t, w - #where, 1, where, toChest and chest and "lightGray" or "orange", "gray")
  put(t, 1, 2, "Search: ", "lightGray")
  put(t, 9, 2, query, "white")

  local rows = h - 5
  selected = math.max(1, math.min(selected, #list))
  if selected <= scroll then scroll = selected - 1 end
  if selected > scroll + rows then scroll = selected - rows end
  scroll = math.max(0, math.min(scroll, #list - rows))
  for i = 1, rows do
    local it = list[scroll + i]
    if it then
      local sel = scroll + i == selected
      local bg = sel and "blue" or "black"
      local can = wanted[it.name] and ("wanted " .. shortCount(wanted[it.name].left))
        or it.count and ("make " .. shortCount(it.count)) or it.pattern and "pattern" or ""
      local stored = (it.stored or 0) > 0 and (shortCount(it.stored) .. " stored  ") or ""
      local right = stored .. can
      put(t, 1, 2 + i, fitText(" " .. it.label, w - #right - 2), "white", bg)
      put(t, w - #right - 1, 2 + i, " " .. stored, sel and "white" or "gray", bg)
      put(t, w - #can, 2 + i, can .. " ", sel and "white" or wanted[it.name] and "yellow" or "lightBlue", bg)
    end
  end
  if #list == 0 then
    local empty = query ~= "" and "Nothing craftable matches."
      or all and "The craft overseer has no recipes yet."
      or not info.ready and "Working out what can be crafted..."
      or info.crafter == false and "No crafting turtle on the storage system."
      or "Nothing can be crafted from what's stored."
    put(t, 2, 4, empty, "lightGray")
  end

  -- what's being made, or why it's stuck
  local busy
  if info.problem then
    busy = { "Stuck: " .. info.problem, "orange" }
  elseif #making > 0 then
    local parts = {}
    for _, m in ipairs(making) do parts[#parts + 1] = ("%d %s"):format(m.count, m.label) end
    busy = { "Making: " .. table.concat(parts, ", "), "lightBlue" }
  elseif next(wanted) then
    -- nothing being made, but an order waits: say what it's short of
    local name, wnt = next(wanted)
    local label = name:gsub("^[%w_]+:", ""):gsub("_", " ")
    busy = { ("Waiting: %d %s, %s"):format(wnt.left, label, wnt.why or "short"), "yellow" }
  else
    busy = { "Nothing being crafted.", "gray" }
  end
  put(t, 1, h - 2, fitText(busy[1], w), busy[2])
  put(t, 1, h - 1, fitText(message[1], w), message[2])
  if asking then
    local prompt = wanted[asking.it.name] and ("How many more %s (0: stop waiting)? "):format(asking.it.label)
      or ("How many %s? "):format(asking.it.label)
    local shown = asking.text ~= "" and asking.text or tostring(defaultAmount(asking.it))
    put(t, 1, h, (" "):rep(w), "white", "gray")
    put(t, 1, h, fitText(prompt, w - 6), "yellow", "gray")
    put(t, math.min(#prompt, w - 6) + 1, h, shown, asking.text ~= "" and "white" or "lightGray", "gray")
    t.setCursorPos(math.min(#prompt, w - 6) + 1 + #asking.text, h)
  else
    local tab = chest and "  Tab: to chest/storage" or ""
    put(t, 1, h, fitText("Enter: craft  Right: one" .. tab, w), "gray")
    t.setCursorPos(9 + #query, 2)
  end
  t.setTextColor(colors.white)
  t.setCursorBlink(true)
  display:show()
end

-- Send the order the prompt is for, and close it.
local function confirm()
  local it, n = asking.it, tonumber(asking.text) or defaultAmount(asking.it)
  asking = nil
  if n < 1 and wanted[it.name] then
    local r, why = crafts.ask({ type = "cancel", item = it.name })
    if r then
      wanted[it.name], waiting[it.name] = nil, nil
      say(("Stopped waiting to craft %s."):format(it.label), "lightGray")
    else
      say("Crafting: " .. why, "red")
    end
    return
  end
  if n < 1 then return end
  say(("Ordering %d %s..."):format(n, it.label), "lightGray")
  draw()
  order(it, math.min(MAX_ORDER, math.floor(n)))
end

local function promptKey(event, a)
  if event == "char" then
    if a:match("%d") and #asking.text < #tostring(MAX_ORDER) then asking.text = asking.text .. a end
  elseif event == "key" then
    if a == keys.enter or a == keys.numPadEnter then
      confirm()
    elseif a == keys.backspace then
      if asking.text == "" then asking = nil else asking.text = asking.text:sub(1, -2) end
    elseif a == keys.delete or a == keys.up or a == keys.down then
      asking = nil
    end
  end
end

local function uiLoop()
  while true do
    draw()
    local event, a, x, y = os.pullEvent()
    local list = matches()
    local _, h = term.getSize()
    if asking and (event == "char" or event == "key") then
      promptKey(event, a)
    elseif event == "char" then
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
      elseif a == keys.tab and chest then
        toChest = not toChest
        say(toChest and "Crafts go to the chest." or "Crafts stay in storage.", "lightGray")
      elseif (a == keys.enter or a == keys.numPadEnter) and list[selected] then
        asking = { it = list[selected], text = "" }
      elseif a == keys.right and list[selected] then
        say(("Ordering 1 %s..."):format(list[selected].label), "lightGray")
        draw()
        order(list[selected], 1)
      end
    elseif event == "mouse_scroll" then
      selected = selected + a
    elseif event == "mouse_click" then
      if y == 1 and chest then
        toChest = not toChest
      elseif y >= 3 and y <= h - 3 then
        local i = scroll + y - 2
        if list[i] and i == selected then
          asking = { it = list[i], text = "" }
        elseif list[i] then
          selected, asking = i, nil
        end
      elseif y == h and asking then
        confirm()
      end
    end
  end
end

-- A fresh list now and then (sooner while the storage computer is still
-- working it out), and a look for the chest (it may be placed or broken).
local function refreshLoop()
  while true do
    chest = findChest()
    local ok = refresh()
    sleep(ok and not info.ready and not all and NOT_READY_WAIT or REFRESH)
  end
end

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "chest" then
  local name = args[2]
  if not name then
    local list = {}
    for _, n in ipairs(peripheral.getNames()) do
      if isInventory(n) then list[#list + 1] = n end
    end
    table.sort(list)
    for i, n in ipairs(list) do print(("%2d  %s"):format(i, n)) end
    print("none: keep crafts in storage")
    write("Which one? (Enter to cancel) ")
    local text = read()
    if text == "" then return end
    name = list[tonumber(text)] or text
  end
  if name ~= "none" and not peripheral.isPresent(name) then
    print(name .. " isn't here.")
    return
  end
  files.write(CHEST_FILE, { chest = name })
  print(name == "none" and "Crafts will stay in storage." or ("Crafts go to %s. It needs a wired modem on the storage cable (or be an ender chest whose twin is on it)."):format(name))
  return
end

if not net.open("any") then
  print("I need a modem: a wired one on the storage cable, or a wireless or ender one.")
  return
end

if args[1] == "make" then
  local n, text = tonumber(args[2]), table.concat(args, " ", 3):lower()
  if not n or n < 1 or text == "" then
    print("Usage: crafts make <how many> <item name>")
    return
  end
  -- the storage computer may need a moment to work out the list the first time
  for _ = 1, 20 do
    if not refresh() then
      print(message[1])
      return
    end
    if info.ready or all then break end
    print("Working out what can be crafted...")
    sleep(NOT_READY_WAIT)
  end
  query = text
  local it = matches()[1]
  if not it then
    print(("Nothing craftable matches '%s'."):format(text))
    return
  end
  order(it, math.min(MAX_ORDER, math.floor(n)))
  print(message[1])
  return
end

term.clear()
if errlog then errlog.init("crafts") end
if report then report.init("craft terminal") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, refreshLoop,
  function() net.keepOpen("any") end,
  report and report.loop or function() while true do sleep(3600) end end)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
