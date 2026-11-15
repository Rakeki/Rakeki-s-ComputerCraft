-- Stash: a whole early-game storage room on one computer. Every chest,
-- barrel, drawer (Functional Storage, Storage Drawers) and Sophisticated
-- Storage chest or barrel on the wired network is one store; drop items in
-- the input chest and they're put away, search on the terminal (or tap the
-- monitor) and they're sent to the output chest. Every furnace, blast
-- furnace and smoker on the cable is kept busy: raw ores and food by
-- themselves, stone, glass and the rest on request (stores.lua and
-- furnaces.lua; config.lua has the settings).
--
-- Space comes first: items there's a lot of go into drawers and storage
-- with stack upgrades, small amounts into plain chests, and bulk is moved
-- out of plain chests now and then. When it's all full, items overflow into
-- Refined Storage through an RS Interface (or a chest an RS Importer
-- empties), and what's in an RS output (an Interface's export slots or an
-- RS Exporter's chest) is listed and taken too.
--
-- No rednet, no turtles, no other computers: made for the first day of a
-- world. Later the storage computer and the factory can take over the same
-- chests (computers/storage-computer, computers/factory).
--
--   stash                  start (opens the setup screen the first time)
--   stash setup            the setup screen (in the running stash if there is one)
--   stash monitor [name]   pick the monitor ('none' for no monitor)
--   stash check            list every inventory on the cable and what the stash makes of it
local screen = require("lib.screen") -- flicker-free drawing on the terminal and monitor
local files = require("lib.files") -- crash-safe save files
local setupui = require("lib.setupui") -- the setup screen
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local storesLib = require("stores")
local furnacesLib = require("furnaces")
local okConfig, config = pcall(require, "config")
if not okConfig or type(config) ~= "table" then config = {} end

local SETUP_FILE = "/.stash_setup"
local INPUT_EVERY = 2 -- seconds between looks in the input chest
local SMELT_EVERY = 5 -- seconds between rounds of the furnaces
local TIDY_EVERY = 15 -- seconds between moves of bulk items into drawers and roomier storage
local TIDY_MOVES = 8 -- most stacks one tidy moves
local SCAN_EVERY = 60 -- seconds between full reads of every chest (catches items moved by hand)
local AMOUNTS = { 64, 16, 1, "all" } -- how much Enter / a tap takes (Tab changes it)
local MONITOR_SCALE = 0.5
local MONITOR_COLUMN = 24 -- fewest characters per column of items on the monitor

local args = { ... }
local put, fit = screen.put, screen.fit

---------------------------------------------------------------- setup

local setup = files.read(SETUP_FILE) -- { input, output, fuel, rsIn, rsOut, ignore = { names } }

local termScreen = screen.new(term.current())
local monScreen = screen.find({ setting = "stash.monitor", scales = { MONITOR_SCALE } })

local SETTINGS = {
  { key = "input", what = "Input chest", need = true, hint = "Items dropped in here get put away." },
  { key = "output", what = "Output chest", need = true, hint = "What you take is sent here." },
  { key = "fuel", what = "Fuel chest", hint = "Coal and charcoal for the furnaces (or keep them in storage)." },
  { key = "rsIn", what = "RS input", hint = "An RS Interface, or a chest an RS Importer empties: overflow." },
  { key = "rsOut", what = "RS output", hint = "An RS Interface's export slots, or an RS Exporter's chest." },
}

-- Every chest-like thing on the cable, for the lists (furnaces aren't).
local function chestNames()
  local names = {}
  for _, n in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(n)
    if storesLib.isInventory(n) and not (t:find("furnace", 1, true) or t:find("smoker", 1, true)) then
      names[#names + 1] = n
    end
  end
  table.sort(names)
  return names
end

local function roleIn(s, name)
  for _, c in ipairs(SETTINGS) do
    if s[c.key] == name then return c.what end
  end
  for _, n in ipairs(s.ignore or {}) do
    if n == name then return "not storage" end
  end
  return nil
end

-- The setup screen on the terminal and the monitor; s is edited in place,
-- true when saved.
local function editSetup(s, first)
  s.ignore = s.ignore or {}
  local ui = setupui.new({ screens = { termScreen, monScreen } })
  local function pickFor(c, done)
    local cur = s[c.key]
    ui:pickChest({ title = "Pick: " .. c.what, hint = c.hint, names = chestNames(), current = cur,
      none = not c.need and "(none)" or nil,
      roleOf = function(n) return roleIn(s, n) end,
      pick = function(name)
        local role = name and name ~= cur and roleIn(s, name)
        if role then
          ui:say(("%s is already the %s."):format(name, role), "orange")
          return
        end
        ui:back()
        done(name)
      end })
    ui:say(c.need and "Tap a chest." or "Tap a chest, or (none).")
  end
  local ignorePage = {
    title = "Not storage", hint = "Chests the stash leaves alone (yours to use by hand).",
    rows = function()
      local out = { { label = "+ Add a chest", colour = "lime", act = function()
        pickFor({ what = "Chest to leave alone", need = true }, function(name)
          s.ignore[#s.ignore + 1] = name
          ui:say(("%s is left alone now."):format(name), "lime")
        end)
      end } }
      for i, n in ipairs(s.ignore) do
        out[#out + 1] = { label = n, value = "tap to use it again", colour = "gray", act = function()
          table.remove(s.ignore, i)
          ui:say(("%s is storage again."):format(n), "lime")
        end }
      end
      return out
    end,
  }
  local main = {
    title = first and "Stash setup" or "Stash settings",
    rows = function()
      local out = {}
      for _, c in ipairs(SETTINGS) do
        local value, colour = s[c.key], "lightGray"
        if not value then value, colour = c.need and "not set" or "none", c.need and "orange" or "gray" end
        out[#out + 1] = { label = c.what, value = value, colour = colour, act = function()
          pickFor(c, function(name)
            s[c.key] = name
            ui:say(("%s: %s."):format(c.what, name or "none"), "lime")
          end)
        end }
      end
      out[#out + 1] = { label = "Not storage", value = #s.ignore == 0 and "none" or (#s.ignore .. " chests"),
        colour = "lightGray", act = function() ui:open(ignorePage) end }
      out[#out + 1] = { label = "Monitor", value = setupui.monitorText("stash.monitor"), colour = "lightGray",
        act = function() ui:monitorPage("stash.monitor", "stash_monitor") end }
      return out
    end,
    buttons = function()
      return {
        { " Save ", "black", "lime", function()
          if s.input and s.output then ui:finish(true) else ui:say("Pick the input and output chests first.", "orange") end
        end },
        { " Cancel ", "white", "red", function() ui:finish(false) end },
      }
    end,
  }
  ui:say(first and "Pick the input and output chests, then Save." or "Tap a setting to change it.")
  return ui:run(main)
end

local function clearTerminal()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

if args[1] == "monitor" then
  if screen.choose("stash.monitor", args[2]) ~= nil then os.queueEvent("stash_monitor") end
  return
elseif args[1] == "setup" or args[1] == "config" then
  if setupui.openInRunning("stash") then
    print("The setup screen is open in the running stash.")
    return
  end
  local s = setup or {}
  local saved = editSetup(s, not setup)
  clearTerminal()
  if saved then
    files.write(SETUP_FILE, s)
    print("Saved. Type 'stash' to start.")
  else
    print("Nothing changed.")
  end
  return
elseif args[1] == "check" then
  -- every inventory on the cable, what the stash takes it for, and its slots
  local roles = {}
  for _, st in ipairs(SETTINGS) do
    if setup and setup[st.key] then roles[setup[st.key]] = st.what end
  end
  for _, n in ipairs(setup and setup.ignore or {}) do roles[n] = "Not storage (setup)" end
  local lines, stores = {}, 0
  for _, name in ipairs(peripheral.getNames()) do
    if storesLib.isInventory(name) then
      local kind, why = storesLib.explain(name)
      local okS, size = pcall(peripheral.call, name, "size")
      local okL, list = pcall(peripheral.call, name, "list")
      local used = 0
      for _ in pairs(okL and type(list) == "table" and list or {}) do used = used + 1 end
      local what = roles[name] or (kind == "store" and "storage") or (kind == "drawer" and "drawer (bulk first)")
        or (kind == "furnace" and "furnace") or ("left alone: " .. why)
      if roles[name] == nil and (kind == "store" or kind == "drawer") then stores = stores + 1 end
      lines[#lines + 1] = ("%s (%s)\n  %s, %s/%s slots used"):format(name, peripheral.getType(name), what, used,
        okS and tostring(size) or "?")
    end
  end
  if #lines == 0 then
    print("No inventories on the cable. Right-click each wired modem so it turns red.")
  else
    textutils.pagedPrint(table.concat(lines, "\n"))
    print(("%d of them are storage."):format(stores))
  end
  return
elseif args[1] and args[1] ~= "start" then
  print("Usage: stash | stash setup | stash monitor [name|none] | stash check")
  return
end

if not setup then
  if #chestNames() < 3 then
    print("I can only see " .. #chestNames() .. " chests.")
    print("Put a wired modem on each chest, barrel and furnace, join them with networking cable to a modem on")
    print("this computer, and right-click every modem so it turns red. Then type 'stash' again.")
    return
  end
  local s = {}
  local saved = editSetup(s, true)
  clearTerminal()
  if not saved then
    print("Setup cancelled. Type 'stash' to try again.")
    return
  end
  setup = s
  files.write(SETUP_FILE, setup)
end

require("lib.label").set("Stash") -- names it Stash-<id> (unless you labelled it)
if report then report.init("stash") end
if errlog then errlog.init("stash") end

local stores = storesLib.new(setup, config)
local furnaces = furnacesLib.new(stores, setup, config)

---------------------------------------------------------------- work

local message = { "Starting up...", "lightGray" }
local actions = {} -- what the screens asked for, done by the work loop: { kind, ... }
local function say(text, colour) message = { text, colour or "lightGray" } end

local function ask(action)
  actions[#actions + 1] = action
  os.queueEvent("stash_action")
end

local function changed() os.queueEvent("stash_changed") end

-- Puts away everything in a chest (the input chest, or the output chest
-- for Put back). Returns how many stacks wouldn't fit.
local function empty(chest)
  local ok, list = pcall(peripheral.call, chest, "list")
  if not ok or type(list) ~= "table" then return 0, false end
  local full, any = 0, false
  for slot, item in pairs(list) do
    any = true
    if stores.putAway(chest, slot, item, item.count) > 0 then full = full + 1 end
  end
  stores.refresh()
  return full, any
end

local function doAction(a)
  if a.kind == "take" then
    local it = stores.info(a.key)
    if not it then return end
    local n = a.n == "all" and it.count or a.n
    local sent = stores.fetch(a.key, n, setup.output)
    if sent > 0 then say(("Sent %d %s."):format(sent, it.displayName), "lime")
    else say("Couldn't send it: is the output chest full?", "red") end
  elseif a.kind == "back" then
    local full, any = empty(setup.output)
    if not any then say("The output chest is empty.")
    elseif full > 0 then say("Storage is full: some are still in the output chest.", "orange")
    else say("Put back everything in the output chest.", "lime") end
  elseif a.kind == "rs" then
    local it = stores.info(a.key)
    if not it then return end
    if not setup.rsIn then return say("Pick an RS input in setup first.", "orange") end
    local n = a.n == "all" and it.count or a.n
    local sent = stores.fetch(a.key, n, setup.rsIn, nil, { noRs = true })
    say(sent > 0 and ("Sent %d %s to Refined Storage."):format(sent, it.displayName) or "The RS input took none: is it full?",
      sent > 0 and "lime" or "red")
  elseif a.kind == "smelt" then
    furnaces.order(a.title, a.from, a.n)
    say(("Smelting %d %s."):format(a.n, a.title), "lime")
  elseif a.kind == "cancel" then
    local o = furnaces.orders()[a.i]
    if o then
      furnaces.cancel(a.i)
      say(("Stopped %s (what's in the furnaces finishes)."):format(o.title))
    end
  end
  stores.refresh()
end

local function drain()
  while #actions > 0 do
    local a = table.remove(actions, 1)
    doAction(a)
    changed()
  end
end

local function workLoop()
  say("Reading every chest...")
  changed()
  stores.discover()
  stores.scan()
  furnaces.discover()
  local _, total = stores.space()
  say(("Ready: %d items in %d slots, %d furnaces."):format(#stores.items(), total, #furnaces.list()))
  changed()
  local last = { input = -math.huge, smelt = -math.huge, tidy = os.clock(), scan = os.clock() }
  local rediscover = false
  -- Work is due by the clock and woken by ticker()'s stash_tick, not by a
  -- timer of its own: a timer that fires while this loop waits inside a yield
  -- (building the item list for an action) is missed, and waiting for that
  -- one stopped the input chest being emptied. A missed tick is followed by
  -- another a second later.
  local due = os.clock()
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
      rediscover = true
    elseif ev[1] == "stash_setup" then
      local s = files.read(SETUP_FILE) or setup
      for k in pairs(setup) do setup[k] = nil end
      for k, v in pairs(s) do setup[k] = v end
      rediscover = true
    end
    drain()
    if os.clock() >= due then
      local now = os.clock()
      if rediscover then
        rediscover = false
        stores.discover()
        stores.refresh()
        furnaces.discover()
      end
      if now - last.input >= INPUT_EVERY then
        last.input = now
        local full, any = empty(setup.input)
        if full > 0 then say("Storage is full! Add chests, or an RS input.", "red") end
        if any then changed() end
        drain()
      end
      if now - last.smelt >= SMELT_EVERY then
        last.smelt = now
        furnaces.round()
        if furnaces.message then say(furnaces.message, "orange") end
        changed()
        drain()
      end
      if now - last.tidy >= TIDY_EVERY then
        last.tidy = now
        local moves, done = stores.tidy(TIDY_MOVES)
        if moves > 0 then
          say(("Tidied: %s%s."):format(done[1], moves > 1 and (" and %d more"):format(moves - 1) or ""), "lightBlue")
          changed()
        end
      end
      if now - last.scan >= SCAN_EVERY then
        last.scan = now
        stores.discover()
        stores.scan()
        furnaces.discover()
        changed()
      end
      due = os.clock() + 1
    end
  end
end

-- Wakes the work loop every second. It never waits on anything else, so its
-- own timer can't be missed.
local function ticker()
  while true do
    sleep(1)
    os.queueEvent("stash_tick")
  end
end

---------------------------------------------------------------- screens

local ui = { page = "items", query = "", selected = 1, scroll = 0, amount = 1 }
local mon = { page = "items", pageNo = 1, zones = {} }

local function amountText(a) return a == "all" and "All" or tostring(a) end

local function countText(n)
  if n >= 100000 then return ("%dk"):format(math.floor(n / 1000)) end
  return tostring(n)
end

local function matches()
  local q = ui.query:lower():gsub("_", " ")
  local list = {}
  for _, it in ipairs(stores.items()) do
    if q == "" or it.displayName:lower():find(q, 1, true) or it.name:gsub("_", " "):find(q, 1, true) then
      list[#list + 1] = it
    end
  end
  return list
end

local function tagOf(it)
  return (it.drawer and "D" or "") .. (it.rs and "R" or "") .. (it.fuel and "F" or "")
end

-- The furnace page's rows: { text, colour, kind = "order"/"recipe", ... }.
local function furnaceRows()
  local rows = {}
  for _, fu in ipairs(furnaces.list()) do
    local what = fu.input and ("%s %d"):format(storesLib.shortName(fu.input.name), fu.input.count) or "empty"
    local fuel = fu.fuel and (" | %s %d"):format(storesLib.shortName(fu.fuel.name), fu.fuel.count) or ""
    local title = fu.kind == "blast" and "Blast" or fu.kind == "smoker" and "Smoker" or "Furnace"
    rows[#rows + 1] = { text = ("%-8s %s%s"):format(title, what, fuel), colour = fu.input and "yellow" or "lime" }
  end
  if #rows == 0 then rows[#rows + 1] = { text = "No furnaces on the cable yet.", colour = "gray" } end
  local orders = furnaces.orders()
  if #orders > 0 then rows[#rows + 1] = { text = "Orders", colour = "lightBlue" } end
  for i, o in ipairs(orders) do
    rows[#rows + 1] = { text = ("  %s: %d of %d in"):format(o.title, o.loaded, o.n), colour = "white", kind = "order", i = i }
  end
  local recipes = furnaces.recipes()
  rows[#rows + 1] = { text = #recipes > 0 and "Smelt on request" or "Nothing to smelt on request.", colour = "lightBlue" }
  for _, r in ipairs(recipes) do
    rows[#rows + 1] = { text = ("  %s (%d to smelt)"):format(r.title, r.have), colour = "white", kind = "recipe", recipe = r }
  end
  return rows
end

local function orderRecipe(r, a)
  local n = a == "all" and r.have or math.min(a, r.have)
  ask({ kind = "smelt", title = r.title, from = r.from, n = n })
end

local function drawTerminal()
  local t, w, h = termScreen:frame()
  put(t, 1, 1, (" "):rep(w), "white", "gray")
  put(t, 2, 1, "Stash", "yellow", "gray")
  local busy, nf = furnaces.busy()
  local stat
  local _, _, space = stores.space()
  if ui.page == "items" then stat = space else stat = ("%d/%d furnaces, %s"):format(busy, nf, furnaces.fuelText()) end
  put(t, math.max(8, w - #stat), 1, fit(stat, w - 8), "lightGray", "gray")
  local amount = "Amount: " .. amountText(AMOUNTS[ui.amount])
  local listTop, rows = 3, h - 5
  local selectedRow
  if ui.page == "items" then
    local list = matches()
    put(t, 1, 2, "Find: ", "lightGray")
    put(t, 7, 2, ui.query, "white")
    put(t, w - #amount + 1, 2, amount, "lightGray")
    ui.selected = math.max(1, math.min(ui.selected, #list))
    if ui.selected <= ui.scroll then ui.scroll = ui.selected - 1 end
    if ui.selected > ui.scroll + rows then ui.scroll = ui.selected - rows end
    for i = 1, rows do
      local it = list[ui.scroll + i]
      if it then
        local sel = ui.scroll + i == ui.selected
        local bg = sel and "blue" or "black"
        local right = countText(it.count) .. " " .. fit(tagOf(it), 2)
        put(t, 1, listTop + i - 1, fit(" " .. it.displayName, w - #right - 1), "white", bg)
        put(t, w - #right, listTop + i - 1, right .. " ", sel and "white" or "lightGray", bg)
      end
    end
    if #list == 0 then put(t, 2, listTop + 1, ui.query ~= "" and "No matches." or "Nothing stored yet.", "lightGray") end
    put(t, 1, h - 1, fit("Enter take  Tab amount  F1 smelt it  F2 to RS", w), "gray")
    put(t, 1, h, fit("F3 furnaces  F4 put back output  F5 setup", w), "gray")
  else
    put(t, 1, 2, "Furnaces", "white")
    put(t, w - #amount + 1, 2, amount, "lightGray")
    local list = furnaceRows()
    local pick = {}
    for i, r in ipairs(list) do
      if r.kind then pick[#pick + 1] = i end
    end
    ui.fsel = math.max(1, math.min(ui.fsel or 1, #pick))
    selectedRow = pick[ui.fsel]
    local scroll = selectedRow and math.max(0, selectedRow - rows) or 0
    for i = 1, rows do
      local r = list[scroll + i]
      if r then
        local sel = scroll + i == selectedRow
        put(t, 1, listTop + i - 1, fit(" " .. r.text, w), sel and "white" or r.colour, sel and "blue" or "black")
      end
    end
    ui.fpick = selectedRow and list[selectedRow]
    put(t, 1, h - 1, fit("Enter smelt (amount)  Tab amount  Del stop order", w), "gray")
    put(t, 1, h, fit("F3 items  F5 setup", w), "gray")
  end
  put(t, 1, h - 2, fit(message[1], w), message[2])
  if ui.page == "items" then
    t.setCursorPos(7 + #ui.query, 2)
    t.setTextColor(colors.white)
    t.setCursorBlink(true)
  else
    t.setCursorBlink(false)
  end
  termScreen:show()
end

local function drawMonitor()
  monScreen:refresh()
  if not monScreen.target then return end
  local t, w, h = monScreen:frame()
  local zones = {}
  local function button(x, y, label, fg, bg, act)
    put(t, x, y, label, fg, bg)
    zones[#zones + 1] = { x, x + #label - 1, y, act }
  end
  put(t, 1, 1, (" "):rep(w), "white", "gray")
  put(t, 2, 1, "Stash", "yellow", "gray")
  local x = 8
  button(x, 1, mon.page == "items" and " Furnaces " or " Items ", "black", "lightBlue", function()
    mon.page, mon.pageNo = mon.page == "items" and "furnaces" or "items", 1
  end)
  x = x + (mon.page == "items" and 11 or 8)
  button(x, 1, " Put back ", "black", "orange", function() ask({ kind = "back" }) end)
  button(w - 6, 1, " Setup ", "black", "lightGray", function() mon.setup = true end)
  -- amounts
  x = 1
  for i, a in ipairs(AMOUNTS) do
    local label = " " .. amountText(a) .. " "
    button(x, 2, label, i == ui.amount and "black" or "white", i == ui.amount and "yellow" or "gray", function() ui.amount = i end)
    x = x + #label + 1
  end
  local top, bottom = 3, h - 1
  local rowsN = bottom - top + 1
  if mon.page == "items" then
    local list = stores.items()
    local cols = math.max(1, math.floor(w / MONITOR_COLUMN))
    local cw = math.floor(w / cols)
    local per = rowsN * cols
    local pages = math.max(1, math.ceil(#list / per))
    mon.pageNo = math.max(1, math.min(mon.pageNo, pages))
    for i = 1, per do
      local it = list[(mon.pageNo - 1) * per + i]
      if not it then break end
      local col, row = math.floor((i - 1) / rowsN), (i - 1) % rowsN
      local cx, cy = 1 + col * cw, top + row
      local count = countText(it.count)
      local bg = row % 2 == 0 and "black" or "gray"
      button(cx, cy, fit(" " .. it.displayName, cw - #count - 2) .. count .. "  ", "white", bg, function()
        ask({ kind = "take", key = it.key, n = AMOUNTS[ui.amount] })
      end)
      if it.drawer then put(t, cx + cw - 2, cy, "D", "lime", bg) elseif it.rs then put(t, cx + cw - 2, cy, "R", "cyan", bg) end
    end
    if #list == 0 then put(t, 2, top + 1, "Nothing stored yet.", "lightGray") end
    if pages > 1 then
      local p = (" %d/%d "):format(mon.pageNo, pages)
      button(w - #p - 7, 2, " < ", "black", "white", function() mon.pageNo = mon.pageNo - 1 end)
      put(t, w - #p - 3, 2, p, "white")
      button(w - 2, 2, " > ", "black", "white", function() mon.pageNo = mon.pageNo + 1 end)
    end
  else
    local list = furnaceRows()
    local pages = math.max(1, math.ceil(#list / rowsN))
    mon.pageNo = math.max(1, math.min(mon.pageNo, pages))
    for i = 1, rowsN do
      local r = list[(mon.pageNo - 1) * rowsN + i]
      if not r then break end
      local y = top + i - 1
      if r.kind == "recipe" then
        button(1, y, fit(" " .. r.text, w - 9), "white", "black", function() orderRecipe(r.recipe, AMOUNTS[ui.amount]) end)
        button(w - 8, y, " Smelt ", "black", "lime", function() orderRecipe(r.recipe, AMOUNTS[ui.amount]) end)
      elseif r.kind == "order" then
        put(t, 1, y, fit(" " .. r.text, w - 8), r.colour)
        button(w - 7, y, " Stop ", "white", "red", function() ask({ kind = "cancel", i = r.i }) end)
      else
        put(t, 1, y, fit(" " .. r.text, w), r.colour)
      end
    end
    if pages > 1 then
      button(w - 13, 2, " < ", "black", "white", function() mon.pageNo = mon.pageNo - 1 end)
      put(t, w - 9, 2, (" %d/%d "):format(mon.pageNo, pages), "white")
      button(w - 2, 2, " > ", "black", "white", function() mon.pageNo = mon.pageNo + 1 end)
    end
  end
  put(t, 1, h, fit(message[1], w), message[2])
  mon.zones = zones
  monScreen:show()
end

local function redraw()
  drawTerminal()
  drawMonitor()
  if report then
    local n = 0
    for _, it in ipairs(stores.items()) do n = n + it.count end
    local busy, nf = furnaces.busy()
    local _, _, space = stores.space()
    report.set("running", ("%d items; %s; %d/%d furnaces busy"):format(n, space, busy, nf))
  end
end

local function setupScreen()
  local s = files.read(SETUP_FILE) or {}
  if editSetup(s, false) then
    files.write(SETUP_FILE, s)
    os.queueEvent("stash_setup")
    say("Settings saved.", "lime")
  else
    say("Setup closed: nothing changed.")
  end
end

local function selectedItem()
  return matches()[ui.selected]
end

local function onKey(k)
  if k == keys.tab then
    ui.amount = ui.amount % #AMOUNTS + 1
  elseif k == keys.f3 then
    ui.page = ui.page == "items" and "furnaces" or "items"
  elseif k == keys.f5 then
    mon.setup = true
  elseif ui.page == "items" then
    local it = selectedItem()
    if k == keys.up then ui.selected = ui.selected - 1
    elseif k == keys.down then ui.selected = ui.selected + 1
    elseif k == keys.pageUp then ui.selected = ui.selected - 10
    elseif k == keys.pageDown then ui.selected = ui.selected + 10
    elseif k == keys.backspace then ui.query, ui.selected, ui.scroll = ui.query:sub(1, -2), 1, 0
    elseif k == keys.delete then ui.query, ui.selected, ui.scroll = "", 1, 0
    elseif k == keys.enter and it then ask({ kind = "take", key = it.key, n = AMOUNTS[ui.amount] })
    elseif k == keys.f1 and it then
      local a = AMOUNTS[ui.amount]
      ask({ kind = "smelt", title = it.displayName, from = { it.key }, n = a == "all" and it.count or math.min(a, it.count) })
    elseif k == keys.f2 and it then ask({ kind = "rs", key = it.key, n = AMOUNTS[ui.amount] })
    elseif k == keys.f4 then ask({ kind = "back" }) end
  else
    if k == keys.up then ui.fsel = (ui.fsel or 1) - 1
    elseif k == keys.down then ui.fsel = (ui.fsel or 1) + 1
    elseif k == keys.enter and ui.fpick and ui.fpick.kind == "recipe" then orderRecipe(ui.fpick.recipe, AMOUNTS[ui.amount])
    elseif k == keys.delete and ui.fpick and ui.fpick.kind == "order" then ask({ kind = "cancel", i = ui.fpick.i }) end
  end
end

local function uiLoop()
  local INPUT = { char = true, key = true, paste = true, mouse_click = true, mouse_scroll = true, monitor_touch = true,
    term_resize = true, monitor_resize = true, stash_monitor = true }
  -- Redraws go by the clock (soonAt, beatAt), checked on every wake, so a
  -- timer missed while redraw() yielded only delays them to the next
  -- stash_tick instead of stopping them.
  local soonAt, beatAt, draw = nil, os.clock() + 5, true
  while true do
    if mon.setup then
      mon.setup = false
      setupScreen()
      draw = true
    end
    if draw then
      draw = false
      redraw()
    end
    local ev = { os.pullEvent() }
    local e = ev[1]
    local now = os.clock()
    if e == "stash_changed" or e == "peripheral" or e == "peripheral_detach" then
      if not soonAt then
        soonAt = now + 0.3
        os.startTimer(0.3)
      end
    elseif INPUT[e] then draw = true end
    if soonAt and now >= soonAt then soonAt, draw = nil, true end
    if now >= beatAt then beatAt, draw = now + 5, true end
    if e == "stash_monitor" then monScreen:refresh() end
    if setupui.wanted("stash", ev) then mon.setup = true end
    local mx, my = monScreen:clicked(ev)
    if mx and monScreen.name then
      for _, z in ipairs(mon.zones) do
        if my == z[3] and mx >= z[1] and mx <= z[2] then z[4]() break end
      end
    elseif e == "char" and ui.page == "items" then
      ui.query, ui.selected, ui.scroll = ui.query .. ev[2], 1, 0
    elseif e == "paste" and ui.page == "items" then
      ui.query, ui.selected, ui.scroll = ui.query .. ev[2], 1, 0
    elseif e == "key" then
      onKey(ev[2])
    elseif e == "mouse_scroll" then
      if ui.page == "items" then ui.selected = ui.selected + ev[2] else ui.fsel = (ui.fsel or 1) + ev[2] end
    elseif e == "mouse_click" and ev[4] == 2 and ev[3] >= term.getSize() - 12 then
      onKey(keys.tab) -- the amount, top right
    elseif e == "mouse_click" and ui.page == "items" then
      local _, h = term.getSize()
      local y = ev[4]
      if y >= 3 and y <= h - 3 then
        local row = ui.scroll + y - 2
        if row == ui.selected then onKey(keys.enter) else ui.selected = row end
      end
    end
  end
end

---------------------------------------------------------------- start

local function main()
  parallel.waitForAny(workLoop, uiLoop, ticker)
end

parallel.waitForAny(function()
  local ok, err
  if errlog then ok, err = errlog.pcall(main) else ok, err = pcall(main) end
  if not ok then
    if report then report.set("error", tostring(err)) end
    clearTerminal()
    error(err, 0)
  end
end, report and report.loop or function() while true do sleep(3600) end end)
