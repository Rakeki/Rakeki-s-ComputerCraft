-- Storage system. Either every chest and barrel on the wired modem network
-- becomes one big store, or an Applied Energistics 2 / Refined Storage
-- system does the storing, through an Advanced Peripherals ME Bridge or RS
-- Bridge (chests.lua and bridge.lua; 'storage setup' picks). Drop items in
-- the input chest and they get put away; type to search on the terminal and
-- press Enter to have a stack sent to the output chest. A touch monitor, if
-- attached, lists what's stored and sends what you tap there too.
--
-- Turtles and computers ask it for items over rednet ("storage" protocol)
-- and never see which kind of store is behind it, so the village builder,
-- crafter and smelter work with either. With a crafting turtle
-- (computers/crafter-turtle), anything asked for that isn't stored but can be
-- made from what is gets crafted (recipes.lua, plus recipes taught in-game);
-- an ME or RS system crafts from its own patterns first. An optional fuel
-- chest holds the coal and charcoal: fuel that comes in is put there first,
-- turtles asking for coal are served from it, and the smelter
-- (computers/smelter-computer) fuels its furnaces from it.
--
-- Turtles find their own chest: a village builder, builder or crafting turtle
-- placed against a chest on this network tells me which one it is
-- (lib/claim.lua), and its items go there. No need to pick it in setup.
-- The smelter and enricher can each have a work chest ('smelter chest',
-- 'enricher chest'; lib/workchest.lua): I fill it in one go each round and
-- they share it out into their furnaces and hoppers themselves.
--
--   storage          start (opens the setup screen the first time)
--   storage setup    the setup screen: the store and the input, output, shared delivery, crafter, fuel and
--                    transfer chests, the extra input chests and far-away enrichers' and smelters' ender chests
--                    (on the monitor and the terminal; in a running storage program if there is one)
--   storage config   the same; 'storage config fuel [chest|none]' changes one setting by typing
--   storage test     check deliveries (one item there and back), the fuel chest and the crafting turtle
--   storage tidy     show the storage's slot sizes and sort bulk items into the roomiest now
--   storage dump [chest]  move everything stored into an ender chest whose twin is another
--                         storage system's input chest (no chest: pick one); runs until it's all gone
--   storage dump stop     stop a dump
--
-- Connect the computer and every chest (and the bridge, if there is one)
-- with networking cable and wired modems: a full-block wired modem touching
-- each chest (small modems only go on full blocks like barrels). Right-click
-- each modem so it turns red.
local screen = require("lib.screen") -- flicker-free drawing on the terminal and monitor
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local crafting = fs.exists("crafting.lua") and require("crafting")
if crafting then crafting.load(fs.exists("recipes.lua") and require("recipes") or {}) end
-- a modpack's recipes, made with tools/recipes.mjs (see the README)
local packRecipes, packError = 0, nil
if crafting and fs.exists("pack_recipes.lua") then
  print("Loading the modpack's recipes...")
  local ok, pack = pcall(require, "pack_recipes")
  if ok and type(pack) == "table" then
    packRecipes = crafting.loadPack(pack)
    print(("Loaded %d modpack recipes."):format(packRecipes))
  else
    packError = tostring(pack)
    print("pack_recipes.lua didn't load: " .. packError)
  end
end
local chests = require("chests")
local setupui = require("lib.setupui") -- the setup screen, on the monitor and the terminal
local bridges = fs.exists("bridge.lua") and require("bridge")

local SETUP_FILE = "/.storage_setup"
local DUMP_FILE = "/.storage_dump" -- { chest, at, moved }: a 'storage dump' that's running

local INPUT_EVERY = 2 -- seconds between checks of the input chest
local RESCAN_EVERY = 60 -- seconds between full rescans of the chests (catches items moved by hand)
local TIDY_EVERY = 10 -- seconds between tidies (moving bulk items into storage with stack upgrades)
-- A Craftable tab listing everything that could be crafted from what's
-- stored. Off by default: with a big modpack it takes a long while to work
-- out. Turtles (village builder, builder, smelter) get crafted items either
-- way: anything they ask for that isn't stored is crafted on request.
local CRAFTABLE_TAB = false
local VIEW_EVERY = 30 -- fewest seconds between recounts of what could be crafted (the Craftable tab)
local REACH_EVERY = 10 -- seconds the list of what could be made at all is kept before working it out again
local VIEW_MAX = 999 -- the Craftable tab counts no higher than this (fewer tries per item)
local OUTPUT_EVERY = 2 -- seconds between checks for crafted items to send to the output chest
local DUMP_WAIT = 2 -- seconds between looks at a full dump chest (and for a new dump job)
local MONITOR_SCALE = 0.5 -- text size on the monitor
local MONITOR_AMOUNTS = { 1, 16, 64 } -- the monitor's buttons for how many of the picked item to send
local MONITOR_COLUMN = 26 -- fewest characters per column of items on the monitor (wide monitors get more columns)
local NET_PROTOCOL = "storage" -- rednet protocol turtles ask for items on
local SWEEP_EVERY = 5 -- seconds between clear-outs of the delivery chest
local HOLD = 600 -- seconds items a turtle asked for wait in the delivery chest before going back
local CRAFT_PROTOCOL = "storage_crafter" -- rednet protocol the crafting turtle takes jobs on
local CRAFT_WAIT = 60 -- seconds to wait for the crafting turtle to finish one batch
local MAX_BATCH_OUTPUT = 384 -- most items one batch may make (6 stacks: they must fit in the turtle)
local WORKER_PROTOCOLS = { enricher = "enricher", smelter = "smelter" } -- far-away computers with a work chest host these
local OVERSEER_PROTOCOL = "craft_overseer" -- a crafting overseer (computers/craft-overseer) takes the queue on this
local OVERSEER_EVERY = 30 -- seconds between looks for a crafting overseer while there isn't one
local OVERSEER_WAIT = 5 -- seconds to wait for the overseer to take the jobs
-- Kinds of inventory a turtle may claim as its chest (matched against the
-- peripheral type, e.g. "minecraft:chest"): never furnaces or hoppers.
local CLAIM_TYPES = { "chest", "barrel", "shulker_box", "crate" }

-- Fuel, in the order furnaces are given it, with how many items each one
-- smelts. These go into the fuel chest first when they're put away.
local FUEL = { { "minecraft:charcoal", 8 }, { "minecraft:coal", 8 }, { "minecraft:coal_block", 80 } }

-- { backend = "chests" or "bridge", input, output = name, delivery, crafter, fuel, transfer = name or nil,
--   inputs = { extra input chest names }, deliveries = { [turtle id] = name }, works = { [computer id] = name },
--   feeders = { [computer id] = { name, ... } } }
-- deliveries are the turtles' own chests, and crafter can be, too: each
-- turtle finds its chest on the network itself (lib/claim.lua, the "claim"
-- request). delivery is the shared one for turtles without their own.
-- works are the smelter's and enricher's work chests (lib/workchest.lua, the
-- "work" request), filled in one go with "fill". feeders are the barrels and
-- chests the enricher and smelter feed their Mekanism machines from (the "feeders" request).
local setup
local store -- the backend: chests.lua or bridge.lua
local fuelList = {} -- the fuel chest's list()
local message = { "", "lightGray" } -- shown in the footer
-- Items waiting in a delivery chest for a turtle: chest -> name -> { n, at }.
-- Everything else in those chests goes back into storage.
local reserved = {}
-- Crafting: jobs waiting for the crafting turtle (from crafting.plan), and
-- how many of each item asked for by a turtle are already being made.
local craftQueue = {}
local pendingCraft = {}
local planCount = 0
local jobCount = 0
local runId = os.epoch("utc") -- makes job ids unique across restarts (the overseer keeps its queue)
local systemCrafts = {} -- name -> how many the ME/RS system is crafting for turtles
-- Items that aren't stored but could be crafted, for the list:
-- { key, name, count (nil: the ME/RS system has a pattern), displayName, craftable = true }.
local craftView = {}
local craftViewReady = false -- the first count is done
-- Crafts asked for on the terminal, sent to the output chest once made:
-- name -> { want, sent }.
local outputOrders = {}

-- Items with NBT (enchanted books, named tools) are kept apart from plain ones.
local function keyOf(item) return item.nbt and (item.name .. "#" .. item.nbt) or item.name end

local fuelSmelts = {}
for _, f in ipairs(FUEL) do fuelSmelts[f[1]] = f[2] end
local function isFuel(item) return fuelSmelts[item.name] ~= nil and not item.nbt end

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function isInventory(name)
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t == "inventory" then return true end
  end
  return false
end

local function loadSetup() return files.read(SETUP_FILE) end
local function saveSetup(s) files.write(SETUP_FILE, s) end

-- Every delivery chest: the shared one and each turtle's own.
local function deliveryChests()
  local list, seen = {}, {}
  local function add(name)
    if name and not seen[name] then list[#list + 1], seen[name] = name, true end
  end
  add(setup.delivery)
  for _, name in pairs(setup.deliveries) do add(name) end
  return list
end

-- Crafter chests: each crafting turtle's own (it finds it itself:
-- setup.crafters = { [turtle id] = chest }), or the one picked in 'storage
-- setup' (setup.crafter), for a turtle that hasn't found its own.
local function crafterChest(id)
  return id and setup.crafters[id] or setup.crafter
end

local function hasCrafter() return setup.crafter ~= nil or next(setup.crafters) ~= nil end

local function crafterChests()
  local list, seen = {}, {}
  for _, name in pairs(setup.crafters) do
    if not seen[name] then list[#list + 1], seen[name] = name, true end
  end
  if setup.crafter and not seen[setup.crafter] then list[#list + 1] = setup.crafter end
  return list
end

---------------------------------------------------------------- what's stored

local function readFuel()
  if not setup.fuel then return end
  local ok, list = pcall(peripheral.call, setup.fuel, "list")
  fuelList = ok and list or {}
end

-- Everything stored, the fuel chest included:
-- key -> { key, name, nbt, count, displayName, maxCount }.
local function allItems()
  local out = {}
  for key, it in pairs(store.items()) do out[key] = it end
  for _, item in pairs(fuelList) do
    local key = keyOf(item)
    local base = out[key]
    out[key] = { key = key, name = item.name, nbt = item.nbt ~= nil, count = (base and base.count or 0) + item.count,
      displayName = base and base.displayName or shortName(item.name), maxCount = base and base.maxCount or 64 }
  end
  return out
end

-- Every stored item, most first, then what could be crafted, most first.
local function totals()
  local list, items = {}, allItems()
  for _, it in pairs(items) do list[#list + 1] = it end
  table.sort(list, function(a, b) return a.count > b.count end)
  local crafts = {}
  for _, it in ipairs(craftView) do
    if not items[it.key] then crafts[#crafts + 1] = it end
  end
  table.sort(crafts, function(a, b) return (a.count or 0) > (b.count or 0) end)
  for _, it in ipairs(crafts) do list[#list + 1] = it end
  return list
end

-- "jungle_fence" -> "Jungle Fence", for items not stored (so no name from the game).
local function titleName(name)
  return (shortName(name):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

---------------------------------------------------------------- moving items

-- Move up to count of the item in slot of chest from into storage, fuel
-- into the fuel chest first. Returns how many didn't fit.
local function putAway(from, slot, item, count)
  local left = count
  if setup.fuel and isFuel(item) then
    local ok, moved = pcall(peripheral.call, from, "pushItems", setup.fuel, slot, left)
    if ok and moved > 0 then
      left = left - moved
      readFuel()
    end
  end
  if left > 0 then left = store.putAway(from, slot, item, left) end
  return left
end

-- The input chest, then any extra ones (setup.inputs). Programs that send
-- items back (smelter, cooker) only use the first.
local function inputChests()
  local list = { setup.input }
  for _, name in ipairs(setup.inputs) do list[#list + 1] = name end
  return list
end

local function storeInput()
  local any, full = false, false
  for _, chest in ipairs(inputChests()) do
    local ok, list = pcall(peripheral.call, chest, "list")
    if ok and next(list) then
      any = true
      for slot, item in pairs(list) do
        if putAway(chest, slot, item, item.count) > 0 then full = true end
      end
    end
  end
  if full then
    message = { "Storage is full: some items are still in the input chest.", "red" }
    if report then report.log("storage full") end
  end
  return any
end

-- Send up to amount of the item with this key to the chest named to (into
-- slot toSlot, if given): from the store, then the fuel chest, or the fuel
-- chest first if fuelFirst. Returns how many went, and the error if a move
-- failed outright.
local function fetch(key, amount, to, toSlot, fuelFirst)
  local sent, err = 0, nil
  local function fromFuel()
    if not setup.fuel or sent >= amount then return end
    local touched = false
    for slot, item in pairs(fuelList) do
      if keyOf(item) == key and sent < amount then
        touched = true
        local ok, moved = pcall(peripheral.call, to, "pullItems", setup.fuel, slot, amount - sent, toSlot)
        if ok then sent = sent + moved else err = err or tostring(moved) end
      end
    end
    if touched then readFuel() end
  end
  local function fromStore()
    if sent >= amount then return end
    local n, e = store.fetch(key, amount - sent, to, toSlot)
    sent, err = sent + n, err or e
  end
  if fuelFirst then
    fromFuel()
    fromStore()
  else
    fromStore()
    fromFuel()
  end
  return sent, err
end

---------------------------------------------------------------- screens

local query, selected, scroll = "", 1, 0
local tab = "stored" -- the terminal's tab: "stored", or "craft" for what could be crafted
local tabZones = {} -- tab -> { x1, x2 } on the tab row, for mouse clicks

-- A Craftable tab only when it's turned on and something can craft: a
-- crafting turtle, or an ME/RS system's patterns.
local function canCraftAny()
  return CRAFTABLE_TAB and ((crafting and hasCrafter()) or store.craftables ~= nil) and true or false
end

-- q is lower case already.
local function hit(it, q)
  return q == "" or it.displayName:lower():find(q, 1, true) or it.key:lower():find(q, 1, true)
end

-- The search hits in the open tab, plus those in each tab (for their counts).
local function matches()
  local q, stored, craft = query:lower(), {}, {}
  for _, it in ipairs(totals()) do
    if hit(it, q) then
      if it.craftable then craft[#craft + 1] = it else stored[#stored + 1] = it end
    end
  end
  return tab == "craft" and craft or stored, stored, craft
end

local put, fitText = screen.put, screen.fit

local function countText(n)
  if n >= 64 then
    local stacks, rest = math.floor(n / 64), n % 64
    return rest > 0 and ("%d (%dx64+%d)"):format(n, stacks, rest) or ("%d (%dx64)"):format(n, stacks)
  end
  return tostring(n)
end

-- Both screens draw through lib/screen.lua, so they don't flash.
local termScreen = screen.new(term.current()) -- this program's terminal (its own tab on an advanced computer)
local monScreen = screen.find({ setting = "storage.monitor", scales = { MONITOR_SCALE } }) -- the monitor's, if there is one

local function drawTerminal()
  local t, w, h = termScreen:frame()
  if tab == "craft" and not canCraftAny() then tab = "stored" end
  local list, stored, craft = matches()
  put(t, 1, 1, (" "):rep(w), "white", "gray")
  put(t, 2, 1, "Storage", "yellow", "gray")
  local _, _, stat = store.space()
  -- the setup screen, like the monitor's button (or F1)
  put(t, w - 6, 1, " Setup ", "black", "lightGray")
  if #stat + 18 <= w then put(t, w - #stat - 8, 1, stat, "lightGray", "gray") end

  -- tabs: what's stored, and (light blue) what could be crafted
  tabZones = {}
  local x = 1
  local function tabButton(name, label, onColour)
    local text = " " .. label .. " "
    local on = tab == name
    put(t, x, 2, text, on and "black" or "white", on and onColour or "gray")
    tabZones[name] = { x, x + #text - 1 }
    x = x + #text + 1
  end
  tabButton("stored", ("Stored %d"):format(#stored), "white")
  if canCraftAny() then tabButton("craft", ("Craftable %d"):format(#craft), "lightBlue") end
  put(t, 1, 3, "Search: ", "lightGray")
  put(t, 9, 3, query, "white")

  local rows = h - 5
  selected = math.max(1, math.min(selected, #list))
  if selected <= scroll then scroll = selected - 1 end
  if selected > scroll + rows then scroll = selected - rows end
  for i = 1, rows do
    local it = list[scroll + i]
    if it then
      local sel = scroll + i == selected
      local bg = sel and "blue" or "black"
      local count = it.craftable and (it.count and ("can make " .. it.count) or "pattern") or countText(it.count)
      put(t, 1, 3 + i, fitText(" " .. it.displayName, w - #count - 1), it.craftable and not sel and "lightBlue" or "white", bg)
      put(t, w - #count, 3 + i, count .. " ", sel and "white" or it.craftable and "lightBlue" or "lightGray", bg)
    end
  end
  if #list == 0 then
    local empty
    if query ~= "" then empty = "No matches."
    elseif tab == "stored" then empty = "Nothing stored yet."
    elseif not craftViewReady then empty = "Working out what can be crafted..."
    else empty = "Nothing can be crafted from what's stored." end
    put(t, 2, 5, empty, "lightGray")
  end

  put(t, 1, h - 1, fitText(message[1], w), message[2])
  -- while searching, how to clear it matters more than the Tab hint (both don't fit)
  local other = query ~= "" and "  Del: clear"
    or canCraftAny() and (tab == "craft" and "  Tab: stored" or "  Tab: craftable") or ""
  local keysText = (tab == "craft" and "Enter: craft a stack  Right: craft one" or "Enter: a stack  Right: one") .. other
  if #keysText + 11 <= w then keysText = keysText .. "  F1: setup" end
  put(t, 1, h, fitText(keysText, w), "gray")
  t.setCursorPos(9 + #query, 3)
  t.setTextColor(colors.white)
  t.setCursorBlink(true)
  termScreen:show()
end

-- The monitor is a touch screen of its own: sort, a search typed on an
-- on-screen keyboard, pages of items, and a bar for the picked item with
-- buttons that send that many to the output chest (or craft them).
local mon = {
  sort = "count", -- "count" (most first) or "name"
  query = "",
  typing = false, -- the keyboard is open
  page = 1,
  pick = nil, -- key of the picked item
  zones = {}, -- { x1, x2, y, action } for each button on the last frame
}
local KEY_ROWS = { "abcdefghij", "klmnopqrst", "uvwxyz" } -- the third row ends in space, backspace and clear
local takeItem -- in the loops section below

-- 1234, 12.3k, 4.5M: fits next to a name in a narrow column.
local function shortCount(n)
  if n < 10000 then return tostring(n) end
  if n < 1000000 then return ("%.1fk"):format(n / 1000) end
  return ("%.1fM"):format(n / 1000000)
end

local function drawMonitor()
  -- cheap while the monitor is still there; picks one up (and scales it once) when it's attached
  monScreen:refresh()
  if not monScreen.target then return end
  local w, h = monScreen:size()
  -- Drawn as a list of writes first: the uiLoop redraws on every event, and
  -- the monitor is only touched when they differ from the last frame's (each
  -- change is sent to every player who can see it).
  local ops, zones = {}, {}
  local function text(x, y, s, fg, bg) ops[#ops + 1] = { x, y, s, fg or "white", bg or "black" } end
  local function button(x, y, label, fg, bg, action)
    text(x, y, label, fg, bg)
    zones[#zones + 1] = { x, x + #label - 1, y, action }
  end

  local all = totals()
  local q, list = mon.query:lower(), {}
  for _, it in ipairs(all) do
    if hit(it, q) then list[#list + 1] = it end
  end
  if mon.sort == "name" then
    table.sort(list, function(a, b) return a.displayName:lower() < b.displayName:lower() end)
  end
  local picked
  for _, it in ipairs(all) do
    if it.key == mon.pick then picked = it end
  end
  if not picked then mon.pick = nil end

  -- title, and how full it is as a bar (when the store can say)
  local used, total, stat = store.space()
  text(1, 1, (" "):rep(w), "white", "gray")
  text(2, 1, "Storage", "yellow", "gray")
  button(w - 6, 1, " Setup ", "black", "lightGray", function() mon.setup = true end)
  if #stat + 19 <= w then text(w - #stat - 8, 1, stat, "lightGray", "gray") end
  if used and total and total > 0 then
    local frac = math.min(1, used / total)
    local filled = math.floor(frac * w + 0.5)
    local bar = fitText((" %d%% full"):format(math.floor(frac * 100 + 0.5)), w)
    text(1, 2, bar:sub(1, filled), "white", frac > 0.9 and "red" or frac > 0.7 and "orange" or "green")
    text(filled + 1, 2, bar:sub(filled + 1), "white", "gray")
  end

  -- the item area: columns of rows, filled down then across
  local top, bottom = 4, mon.typing and h - 5 or h - 2
  local rows = math.max(0, bottom - top + 1)
  local cols = math.max(1, math.floor(w / MONITOR_COLUMN))
  local colW = math.floor(w / cols)
  local perPage = math.max(1, rows * cols)
  local pages = math.max(1, math.ceil(#list / perPage))
  mon.page = math.max(1, math.min(mon.page, pages))
  local first = (mon.page - 1) * perPage
  for c = 1, cols do
    local x0 = (c - 1) * colW + 1
    local cw = c == cols and w - x0 + 1 or colW - 1
    for r = 1, rows do
      local it = list[first + (c - 1) * rows + r]
      if it then
        local y = top + r - 1
        local count = it.craftable and (it.count and ("+" .. shortCount(it.count)) or "craft") or shortCount(it.count)
        local on = it.key == mon.pick
        local bg = on and "blue" or "black"
        text(x0, y, fitText(" " .. it.displayName, cw - #count - 1), it.craftable and not on and "lightBlue" or "white", bg)
        text(x0 + cw - #count - 1, y, count .. " ", on and "white" or it.craftable and "lightBlue" or "lightGray", bg)
        local key = it.key
        zones[#zones + 1] = { x0, x0 + cw - 1, y, function() mon.pick = mon.pick ~= key and key or nil end }
      end
    end
  end
  if #list == 0 and rows > 0 then
    text(2, top, mon.query ~= "" and "No matches." or "Nothing stored yet.", "lightGray")
  end

  -- controls: sort, search, pages
  local pageText = ("%d/%d"):format(mon.page, pages)
  local px = w - #pageText - 5
  if pages > 1 then
    button(px, 3, " < ", "white", mon.page > 1 and "gray" or "black", function() mon.page = mon.page - 1 end)
    text(px + 3, 3, pageText, "lightGray")
    button(px + 3 + #pageText, 3, " > ", "white", mon.page < pages and "gray" or "black", function() mon.page = mon.page + 1 end)
  else
    px = w + 1
  end
  local sortLabel = mon.sort == "count" and " Most " or " A-Z "
  button(1, 3, sortLabel, "black", "lightGray", function()
    mon.sort, mon.page = mon.sort == "count" and "name" or "count", 1
  end)
  local findX = #sortLabel + 2
  local findLabel = mon.typing and (" " .. mon.query .. "_ ") or mon.query ~= "" and (" " .. mon.query .. " ") or " Find "
  local room = px - findX - 1
  if #findLabel > room then findLabel = room > 0 and findLabel:sub(-room) or "" end -- keep the end: what's being typed
  if #findLabel > 0 then
    button(findX, 3, findLabel, "black", (mon.typing or mon.query ~= "") and "yellow" or "lightGray",
      function() mon.typing = not mon.typing end)
  end

  -- the keyboard for the search
  if mon.typing then
    local kw = math.max(1, math.min(4, math.floor(w / 10)))
    local kx = math.floor((w - kw * 10) / 2) + 1
    local function key(i, y, label, width, action)
      local x = kx + (i - 1) * kw
      local cell = kw > 1 and width * kw - 1 or width
      local pad = math.floor((cell - #label) / 2)
      local shade = (kw > 1 or (i + y) % 2 == 0) and "gray" or "lightGray"
      button(x, y, fitText((" "):rep(pad) .. label, cell), "white", shade, action)
    end
    local function typeChar(ch) return function() mon.query, mon.page = mon.query .. ch, 1 end end
    for r, chars in ipairs(KEY_ROWS) do
      local y = h - 5 + r
      for i = 1, #chars do key(i, y, chars:sub(i, i), 1, typeChar(chars:sub(i, i))) end
    end
    local y = h - 2
    key(7, y, "_", 1, typeChar(" "))
    key(8, y, "<", 1, function() mon.query, mon.page = mon.query:sub(1, -2), 1 end)
    local clearW = kw > 1 and 2 * kw - 1 or 2
    key(9, y, clearW >= 5 and "Clear" or clearW >= 3 and "Clr" or "C", 2, function() mon.query, mon.page = "", 1 end)
  end

  -- footer: what's going on, and the picked item's buttons
  text(1, h - 1, fitText(message[1], w), message[2])
  if picked then
    local labels, width = {}, 3 -- the " x " button
    for i, n in ipairs(MONITOR_AMOUNTS) do
      labels[i] = " " .. n .. " "
      width = width + #labels[i] + 1
    end
    while width > w and #labels > 1 do -- a narrow monitor gets the smaller amounts
      width = width - #labels[#labels] - 1
      labels[#labels] = nil
    end
    local bx = w - width + 1
    local verb = picked.craftable and "Craft" or "Get"
    local name = picked.displayName .. " " .. (picked.craftable and (picked.count and ("can make " .. picked.count) or "pattern")
      or tostring(picked.count))
    text(1, h, fitText(" " .. name, math.max(0, bx - #verb - 2)), picked.craftable and "lightBlue" or "white")
    if bx - #verb - 1 > 1 then text(bx - #verb - 1, h, verb, "lightGray") end
    for i, label in ipairs(labels) do
      local n = MONITOR_AMOUNTS[i]
      button(bx, h, label, "black", picked.craftable and "lightBlue" or "lime", function() takeItem(picked, n) end)
      bx = bx + #label + 1
    end
    button(bx, h, " x ", "white", "red", function() mon.pick = nil end)
  else
    text(1, h, fitText(" Tap an item to send some to the output chest.", w), "gray")
  end

  mon.zones = zones
  local parts = {}
  for i, op in ipairs(ops) do parts[i] = table.concat(op, ",") end
  if monScreen:same(table.concat(parts, "|")) then return end
  local win = monScreen:frame()
  for _, op in ipairs(ops) do put(win, op[1], op[2], op[3], op[4], op[5]) end
  monScreen:show()
end

local function redraw()
  drawTerminal()
  drawMonitor()
  if report then
    local items = 0
    for _, it in pairs(allItems()) do items = items + it.count end
    local _, _, text = store.space()
    report.set(store.problem and "error" or "running", store.problem or ("%d items; %s"):format(items, text))
  end
end

---------------------------------------------------------------- loops

local orderCraft -- in the crafting section below
local editSetup -- in the setup section below

-- Send amount of an item from the list to the output chest, or have it
-- crafted if it isn't stored (from the terminal or a monitor button).
function takeItem(it, amount)
  if it.craftable then
    -- not stored: have it made, and outputLoop sends it on once it's ready
    local made, why = orderCraft(it.name, it.count and math.min(amount, it.count) or amount)
    if made then
      local o = outputOrders[it.name] or { want = 0, sent = 0 }
      o.want = o.want + made
      outputOrders[it.name] = o
      message = { ("Crafting %d %s for the output chest..."):format(made, it.displayName), "lightBlue" }
    else
      message = { ("Can't craft %s: %s."):format(it.displayName, why), "red" }
    end
    return
  end
  local sent = fetch(it.key, amount, setup.output)
  if sent > 0 then
    message = { ("Sent %d %s to the output chest."):format(sent, it.displayName), "lime" }
  else
    message = { "Couldn't send it: is the output chest full?", "red" }
  end
end

-- The terminal's picked row.
local function take(amount)
  local it = matches()[selected]
  if it then takeItem(it, amount) end
end

-- The setup screen inside the running program (the monitor's Setup button,
-- or 'storage setup' / 'storage config' in another tab): what's saved is
-- used straight away (setupLoop).
local function setupScreen()
  local s = loadSetup() or setup
  local kind = setup.backend == "bridge" and store.kind or bridges and select(2, bridges.find())
  if editSetup(s, kind, false) then
    saveSetup(s)
    os.queueEvent("storage_setup")
  else
    message = { "Setup closed: nothing changed.", "lightGray" }
  end
end

local function uiLoop()
  while true do
    redraw()
    if mon.setup then
      mon.setup = false
      setupScreen()
      redraw()
    end
    local ev = { os.pullEvent() }
    -- 'storage setup' in another tab: open it here, where the monitor is
    if ev[1] == "storage_open_setup" then
      os.queueEvent("storage_setup_opened")
      mon.setup = true
    end
    local event, a, x, y = ev[1], ev[2], ev[3], ev[4]
    local mx, my = monScreen:clicked(ev)
    if mx then
      for _, z in ipairs(mon.zones) do
        if my == z[3] and mx >= z[1] and mx <= z[2] then
          z[4]()
          break
        end
      end
    elseif event == "char" then
      query, selected, scroll = query .. a, 1, 0
    elseif event == "key" then
      if a == keys.f1 then
        mon.setup = true
      elseif a == keys.tab and canCraftAny() then
        tab, selected, scroll = tab == "craft" and "stored" or "craft", 1, 0
      elseif a == keys.delete then
        query, selected, scroll = "", 1, 0
      elseif a == keys.backspace then
        query, selected, scroll = query:sub(1, -2), 1, 0
      elseif a == keys.up then
        selected = selected - 1
      elseif a == keys.down then
        selected = selected + 1
      elseif a == keys.pageUp then
        selected = selected - 10
      elseif a == keys.pageDown then
        selected = selected + 10
      elseif a == keys.enter then
        take(64)
      elseif a == keys.right then
        take(1)
      end
    elseif event == "mouse_scroll" then
      selected = selected + a
    elseif event == "mouse_click" then
      local w, h = term.getSize()
      if y == 1 and x >= w - 6 then
        mon.setup = true
      elseif y == 2 then
        for name, z in pairs(tabZones) do
          if x >= z[1] and x <= z[2] and tab ~= name then tab, selected, scroll = name, 1, 0 end
        end
      elseif y >= 4 and y <= h - 2 then
        -- clicking the picked row again takes a stack, like Enter
        if selected == scroll + y - 3 then take(64) else selected = scroll + y - 3 end
      end
    end
  end
end

local function inputLoop()
  while true do
    if storeInput() then os.queueEvent("storage_changed") end
    sleep(INPUT_EVERY)
  end
end

---------------------------------------------------------------- crafting

local function nameOf(item)
  local it = allItems()[item]
  return it and it.displayName or shortName(item)
end

-- Every plain item in storage, minus what queued crafts will use up, plus
-- what they'll make: what a new plan can count on.
local function planningStock()
  local avail = {}
  for _, it in pairs(allItems()) do
    if not it.nbt then avail[it.name] = (avail[it.name] or 0) + it.count end
  end
  for _, job in ipairs(craftQueue) do
    for _, item in pairs(job.grid) do avail[item] = (avail[item] or 0) - job.steps end
    avail[job.name] = (avail[job.name] or 0) + job.steps * job.recipe.count
  end
  return avail
end

-- What could be made at all from what's stored (crafting.reachable): plans
-- only try those, which keeps thousands of modded recipes quick. Kept a few
-- seconds, since a turtle's request may plan many items in a row.
local reachCache, reachAt = nil, -math.huge
local function reachNow()
  if not reachCache or os.clock() - reachAt > REACH_EVERY then
    reachCache, reachAt = crafting.reachable(planningStock()), os.clock()
  end
  return reachCache
end

-- The ME/RS system has a pattern for it.
local function systemCanCraft(name) return store.canCraft ~= nil and store.canCraft(name) end

-- Have count of name made, or as many as can be: by the ME/RS system if it
-- has a pattern, otherwise by queueing crafts for the crafting turtle.
-- Returns how many it's making (and why not all of them), or false and why.
function orderCraft(name, count)
  if systemCanCraft(name) then
    local ok, err = store.craft(name, count)
    if not ok then return false, err end
    systemCrafts[name] = (systemCrafts[name] or 0) + count
    pendingCraft[name] = (pendingCraft[name] or 0) + count
    return count
  end
  if not crafting then return false, "crafting.lua is missing: run 'install update'" end
  if not crafting.canMake(name) then return false, "no recipe for it" end
  if not hasCrafter() then return false, "no crafter chest: start a crafting turtle against one on my network" end
  local stock, reach = planningStock(), reachNow()
  local jobs, why = crafting.plan(name, count, stock, reach), nil
  if not jobs then
    -- make what we can, so a build gets as far as it can meanwhile
    local can = crafting.craftable(name, stock, count - 1, reach)
    if can == 0 then return false, "not enough to make it from" end
    count, why = can, ("only enough to make %d"):format(can)
    jobs = crafting.plan(name, count, stock, reach)
    if not jobs then return false, "not enough to make it from" end
  end
  planCount = planCount + 1
  for _, job in ipairs(jobs) do
    job.plan = planCount
    jobCount = jobCount + 1
    job.id = ("%d:%d"):format(runId, jobCount) -- the overseer says which job is done by this
    craftQueue[#craftQueue + 1] = job
  end
  jobs[#jobs].top = count -- the item asked for: counted in pendingCraft until it's made
  pendingCraft[name] = (pendingCraft[name] or 0) + count
  os.queueEvent("storage_craft")
  return count, why
end

-- Once the ME/RS system stops crafting something, what it made is stored
-- and counted like anything else.
local function checkSystemCrafts()
  for name, n in pairs(systemCrafts) do
    if not store.isCrafting(name) then
      systemCrafts[name] = nil
      pendingCraft[name] = math.max(0, (pendingCraft[name] or 0) - n)
      message = { ("The %s system is done crafting %s."):format(store.kind, nameOf(name)), "lime" }
      os.queueEvent("storage_changed")
    end
  end
end

-- Put away anything in a crafter chest. Returns false if it couldn't all
-- go (storage full), since the turtle would craft with it.
local function clearCrafter(chest)
  local ok, list = pcall(peripheral.call, chest, "list")
  if not ok then return false end
  local empty = true
  for slot, item in pairs(list) do
    if putAway(chest, slot, item, item.count) > 0 then empty = false end
  end
  return empty
end

-- Put one batch of a job's ingredients in a crafter chest: steps of each
-- grid cell's item (cell k in chest slot k where the chest allows). No
-- more steps than the smallest stack among the ingredients. Returns how
-- many steps went in, or 0, why, and what's short (item -> how many).
local function loadCrafter(chest, grid, steps)
  local items = allItems()
  local batch = steps
  for _, item in pairs(grid) do batch = math.min(batch, items[item] and items[item].maxCount or 64) end
  batch = math.max(1, batch)
  if not clearCrafter(chest) then return 0, "the crafter chest won't empty: is storage full?" end
  -- all there? (so a batch is never half loaded for want of one item)
  local need, missing = {}, nil
  for _, item in pairs(grid) do need[item] = (need[item] or 0) + batch end
  for item, n in pairs(need) do
    local have = items[item] and items[item].count or 0
    if have < n then
      missing = missing or {}
      missing[item] = n - have
    end
  end
  if missing then return 0, "not enough ingredients", missing end
  for k = 1, 9 do
    local item = grid[k]
    if item then
      local got, err = fetch(item, batch, chest, k)
      if got < batch then
        -- the chest wouldn't take it in that slot (a barrel with upgrades
        -- picks its own, or no transfer chest with a bridge): any slot
        -- will do, the turtle sorts them by name
        local more, why = fetch(item, batch - got, chest)
        got, err = got + more, why or err
      end
      if got < batch then
        clearCrafter(chest)
        return 0, err or ("not enough " .. nameOf(item)), { [item] = batch - got }
      end
    end
  end
  return batch
end

local crafterId -- the crafting turtle this computer uses itself (no overseer), once found
-- Why crafting is stuck right now (nil when it's working), so turtles
-- waiting on a craft can say so.
local craftProblem

-- A crafting turtle that answers and has a chest.
local function findCrafter()
  if crafterId and crafterChest(crafterId) then return crafterId end
  crafterId = nil
  for _, id in ipairs({ rednet.lookup(CRAFT_PROTOCOL) }) do
    if crafterChest(id) then
      crafterId = id
      return id
    end
  end
end

-- One job on my own crafting turtle: in batches that fit the turtle, put
-- the ingredients in its chest, have it craft, and put the results away.
local function runJob(job)
  local r = job.recipe
  local chest = crafterChest(crafterId)
  local left = job.steps
  while left > 0 do
    local batch, err = loadCrafter(chest, job.grid, math.min(left, 64, math.floor(MAX_BATCH_OUTPUT / r.count)))
    if batch == 0 then return false, err end
    -- grid tells the turtle which item goes in which cell, so it lays them
    -- out right whatever order its chest keeps them in
    local craft = { type = "craft", steps = batch, grid = job.grid }
    local reply = net.ask(crafterId, CRAFT_PROTOCOL, craft, { wait = CRAFT_WAIT,
      match = function(msg) return msg.type == "crafted" and msg.id == craft.id end })
    clearCrafter(chest)
    if not reply then
      crafterId = nil
      craftProblem = "its crafting turtle didn't answer"
      return false, "the crafting turtle didn't answer"
    end
    craftProblem = nil
    if (reply.made or 0) == 0 then return false, reply.error or "the recipe didn't work" end
    if reply.item and reply.item ~= job.name then
      return false, ("the crafting turtle made %s instead"):format(nameOf(reply.item))
    end
    left = left - batch
  end
  return true
end

-- A job is finished, here or by the overseer: it no longer counts as
-- coming, and if it failed the rest of its plan (which needed it) goes too.
local function jobFinished(job, ok, why)
  for i = #craftQueue, 1, -1 do
    if craftQueue[i] == job then table.remove(craftQueue, i) end
  end
  local n = job.steps * job.recipe.count
  if job.top then pendingCraft[job.name] = math.max(0, (pendingCraft[job.name] or 0) - job.top) end
  if ok then
    message = { ("Crafted %d %s."):format(n, nameOf(job.name)), "lime" }
    if report then report.log(("crafted %d %s"):format(n, nameOf(job.name))) end
  else
    message = { ("Couldn't craft %s: %s"):format(nameOf(job.name), tostring(why)), "red" }
    for i = #craftQueue, 1, -1 do
      local other = craftQueue[i]
      if other.plan == job.plan then
        if other.top then pendingCraft[other.name] = math.max(0, (pendingCraft[other.name] or 0) - other.top) end
        table.remove(craftQueue, i)
      end
    end
  end
  os.queueEvent("storage_changed")
end

-- The crafting overseer (computers/craft-overseer), if there is one: it
-- takes the queue and shares it between the crafting turtles.
local overseerId, overseerAt = nil, -math.huge
local function findOverseer()
  if not overseerId and os.clock() - overseerAt > OVERSEER_EVERY then
    overseerAt = os.clock()
    overseerId = rednet.lookup(OVERSEER_PROTOCOL)
  end
  return overseerId
end

-- Send the overseer the jobs it hasn't got yet. False if it didn't answer.
local function handOver()
  local list = {}
  for _, job in ipairs(craftQueue) do
    if not job.sent then
      list[#list + 1] = { id = job.id, plan = job.plan, name = job.name, steps = job.steps, count = job.recipe.count,
        grid = job.grid, top = job.top }
    end
  end
  if #list == 0 then return true end
  if net.ask(overseerId, OVERSEER_PROTOCOL, { type = "jobs", jobs = list }, { wait = OVERSEER_WAIT }) then
    for _, job in ipairs(craftQueue) do job.sent = true end
    message = { ("Gave the crafting overseer (#%d) %d crafts."):format(overseerId, #list), "lightBlue" }
    os.queueEvent("storage_changed")
    return true
  end
  overseerId, overseerAt = nil, os.clock()
  message = { "The crafting overseer didn't answer: crafting here.", "orange" }
  os.queueEvent("storage_changed")
  return false
end

local function craftLoop()
  while true do
    checkSystemCrafts()
    local unsent
    for _, job in ipairs(craftQueue) do
      if not job.sent then unsent = job break end
    end
    if not (hasCrafter() and unsent) then
      local timer = os.startTimer(10)
      repeat
        local event, value = os.pullEvent()
      until event == "storage_craft" or (event == "timer" and value == timer)
      -- the turtle's leftovers (never with an overseer: it may be mid-batch)
      if #craftQueue == 0 and rednet.isOpen() and not findOverseer() then
        for _, chest in ipairs(crafterChests()) do clearCrafter(chest) end
      end
    elseif not rednet.isOpen() then
      sleep(5) -- netReceive opens the modems
    elseif findOverseer() then
      if not handOver() then sleep(1) end
    elseif not findCrafter() then
      message = { net.hasWireless() and "No crafting turtle answered: is it running 'crafter'?"
        or "Crafter not answering: put a wireless modem on me.", "orange" }
      craftProblem = "its crafting turtle isn't answering"
      os.queueEvent("storage_changed")
      sleep(10)
    else
      -- out of the queue while it runs, as planning stock doesn't count it twice
      local job = unsent
      for i, j in ipairs(craftQueue) do
        if j == job then table.remove(craftQueue, i) break end
      end
      message = { ("Crafting %d %s..."):format(job.steps * job.recipe.count, nameOf(job.name)), "lightBlue" }
      os.queueEvent("storage_changed")
      local ok, why = runJob(job)
      jobFinished(job, ok, why)
    end
  end
end

-- Requests from turtles over rednet:
--   { type = "count", items = { name, ... } }      -> { re = "count", counts = { [name] = n } }
--   { type = "deliver", items = { [name] = n } }   -> { re = "deliver", sent = { [name] = n } }
--   { type = "prepare", items = { [name] = n } }   -> { re = "prepare", crafting, cantCraft }  (start crafting)
--   { type = "learn", recipe = { make, count, rows, keys } } -> { re = "learn", ok }  (from 'crafter learn')
--   { type = "stock" }                              -> { re = "stock", counts, input, fuelChest, fuel }  (smelter, cooker)
--   { type = "recipes", uses = pattern }            -> { re = "recipes", recipes = { { make, count, grid } } }  (essence computer)
--   { type = "send", to, slot = 1, items = { [name] = n } } -> { re = "send", sent, fuel }  (load a furnace)
--   { type = "send", to, slot = 2, fuel = n, item }  -> the same, with fuel for n more items (only item, if given)
--   { type = "send", to = hopper, slot, items }     -> the same, into a hopper (slot optional; the cooker's pots)
--                                                     or one of the asker's feeders
--   { type = "feeders", chests = { name, ... } }   -> { re = "feeders", ok, error }  (Mekanism machines' barrels: not storage)
--   { type = "claim", role, items }                 -> a turtle finding its chest (see claimChest)
--   { type = "list" }                               -> { re = "list", items = { { name, label, count } } }  (remote terminal)
--   { type = "work", chest }                        -> { re = "work", ok, chest, error }  (a computer's work chest; no chest: stop)
--   { type = "work", items } / { type = "work", seen } -> found through an ender chest, like "claim"
--   { type = "fill", items = { [name] = n }, fuel = n, sweep } -> { re = "fill", sent, ready, fuel, error, nochest, swept }  (top it up;
--                                                     sweep: first put away everything else in it, for one ender chest both ways)
-- From the crafting overseer, which runs the crafting queue when there is one:
--   { type = "crafters" }                           -> { re, crafters = { [turtle id] = chest }, shared }
--   { type = "load", crafter, grid, steps }         -> { re, steps (0: not loaded), error, missing = { [item] = n } }
--   { type = "clear", crafter }                     -> { re, ok }  (put its chest's contents away)
--   { type = "jobdone", job, ok, why }              -> { re, ok }  (job: the id it was handed it with)
--   { type = "problem", text }                      -> { re, ok }  (why crafting is stuck, or nil)
-- deliver sends to the turtle's own chest if it has claimed one ("own"),
-- else the shared delivery chest, else the output chest (reply field to).
-- Requests may carry an id, which the reply repeats. count may carry need
-- (name -> how many the turtle wants), which keeps craftable quick.
-- count also answers craftable (how many more could be crafted), and deliver
-- answers crafting (how many it has started making).
-- Items with extra data (enchantments, names) are never counted or sent.

-- Every plain item stored, the fuel chest included: name -> count.
local function countAll()
  local counts = {}
  for _, it in pairs(allItems()) do
    if not it.nbt then counts[it.name] = (counts[it.name] or 0) + it.count end
  end
  return counts
end

local function countPlain(names)
  local all, counts = countAll(), {}
  for _, n in ipairs(names) do counts[n] = all[n] or 0 end
  return counts
end

-- How many items all the stored fuel would smelt.
local function fuelValue(counts)
  local n = 0
  for _, f in ipairs(FUEL) do n = n + (counts[f[1]] or 0) * f[2] end
  return n
end

-- Only furnaces (for the smelter) and hoppers (for the cooker's pots) are
-- loaded, so a stray message can't empty the store into some other chest.
local function isFurnace(name)
  local t = type(name) == "string" and peripheral.isPresent(name) and peripheral.getType(name)
  return t and (t:find("furnace", 1, true) or t:find("smoker", 1, true)) and true or false
end

local function isHopper(name)
  local t = type(name) == "string" and peripheral.isPresent(name) and peripheral.getType(name)
  return t and t:find("hopper", 1, true) and true or false
end

---------------------------------------------------------------- turtles finding their chest

-- A turtle next to a chest on the network tells us what's in it (lib/claim.lua),
-- and that chest becomes its delivery chest, or the crafter chest:
--   { type = "claim", role = "delivery" or "crafter", items = its list() }
--     -> { re = "claim", ok = true, chest } when it's the one we have for it
--     -> { re = "claim", probe = item } once we've put one item in a chest it could be
--   { type = "claim", role, seen = true or false }  (did the item turn up?)
--     -> the same answers, or { ok = false, error } once no chest is left to try
-- The probe item is taken back each time.
local claims = {} -- turtle id -> { role, candidates, i, at = chest the item is in, marker }

-- Chests a turtle's chest could be: any chest or barrel apart from the ones
-- the storage computer needs for itself (furnaces and the like never).
local function claimable(name)
  for _, which in ipairs({ "input", "output", "fuel", "transfer" }) do
    if name == setup[which] then return false end
  end
  for _, list in ipairs({ setup.inputs, setup.works }) do
    for _, chest in pairs(list) do
      if name == chest then return false end
    end
  end
  for _, list in pairs(setup.feeders or {}) do
    for _, chest in ipairs(list) do
      if name == chest then return false end
    end
  end
  if not isInventory(name) then return false end
  -- a probe item dropped in the dump chest would be gone to the other side
  local dump = files.read(DUMP_FILE)
  if type(dump) == "table" and dump.chest == name then return false end
  local t = peripheral.getType(name)
  for _, kind in ipairs(CLAIM_TYPES) do
    if t:find(kind, 1, true) then return true end
  end
  return false
end

local function sameItems(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  local n = 0
  for slot, it in pairs(a) do
    local other = b[slot]
    if type(other) ~= "table" or other.name ~= it.name or other.count ~= it.count then return false end
    n = n + 1
  end
  for _ in pairs(b) do n = n - 1 end
  return n == 0
end

local function takeMarker(c)
  if not c.at then return end
  local ok, list = pcall(peripheral.call, c.at, "list")
  for slot, item in pairs(ok and list or {}) do
    if item.name == c.marker and not item.nbt then
      putAway(c.at, slot, item, 1)
      break
    end
  end
  c.at = nil
end

-- Put one item in the next chest to try. The item is one that chest
-- doesn't already hold, so the turtle can tell it arrived.
local function nextProbe(from, c)
  local items = allItems()
  while c.i < #c.candidates do
    c.i = c.i + 1
    local name = c.candidates[c.i]
    local ok, list = pcall(peripheral.call, name, "list")
    if ok then
      local has = {}
      for _, item in pairs(list) do has[item.name] = true end
      local marker = c.marker and not has[c.marker] and items[c.marker] and c.marker
      if not marker then
        for key, it in pairs(items) do
          if not it.nbt and it.count > 0 and not has[key] then marker = key break end
        end
      end
      if marker and fetch(marker, 1, name) > 0 then
        c.at, c.marker = name, marker
        return { re = "claim", probe = marker }
      end
    end
  end
  claims[from] = nil
  if not next(allItems()) then
    return { re = "claim", ok = false, error = "the storage system is empty: it needs one item to find your chest with" }
  end
  return { re = "claim", ok = false, error = "your chest isn't on its network: put a wired modem on it, on the storage cable, and right-click the modem so it turns red" }
end

local releaseWork, recordWork -- below, with the work chests
local isEnder -- below, with the dump

-- The chest is the turtle's: record it (in the setup file too).
local function assign(from, role, chest)
  if role == "work" then
    -- a far-away computer's work chest, found through an ender chest
    for id, name in pairs(setup.deliveries) do
      if name == chest then return { re = "claim", ok = false, error = ("that chest is turtle #%d's"):format(id) } end
    end
    for _, c in ipairs(crafterChests()) do
      if c == chest then return { re = "claim", ok = false, error = "that chest is a crafting turtle's" } end
    end
    return recordWork(from, chest)
  end
  if role == "delivery" then
    for _, c in ipairs(crafterChests()) do
      if c == chest then return { re = "claim", ok = false, error = "that chest is a crafting turtle's" } end
    end
  end
  local s = loadSetup() or setup
  s.deliveries, s.crafters = s.deliveries or {}, s.crafters or {}
  for _, t in ipairs({ setup, s }) do
    if role == "crafter" then
      -- each crafting turtle has a chest of its own
      for id, name in pairs(t.crafters) do
        if name == chest then t.crafters[id] = nil end
      end
      t.crafters[from] = chest
      if t.crafter == chest then t.crafter = nil end
      if t.delivery == chest then t.delivery = nil end
      for id, name in pairs(t.deliveries) do
        if name == chest then t.deliveries[id] = nil end
      end
    else
      t.deliveries[from] = chest
      if t.delivery == chest then t.delivery = nil end
    end
  end
  saveSetup(s)
  if role == "crafter" then crafterId = from end
  store.scan() -- it may have been storage until now
  message = { ("Turtle #%d's %s chest is %s."):format(from, role, chest), "lime" }
  if report then report.log(("turtle #%d uses %s"):format(from, chest)) end
  os.queueEvent("storage_changed")
  return { re = "claim", ok = true, chest = chest }
end

local function claimChest(from, msg, role)
  role = role or (msg.role == "crafter" and "crafter" or "delivery")
  local c = claims[from]
  if msg.seen ~= nil then
    if not c then return { re = "claim", ok = false, error = "I lost track of where I was: try again" } end
    takeMarker(c)
    if msg.seen then
      claims[from] = nil
      return assign(from, c.role, c.candidates[c.i])
    end
    return nextProbe(from, c)
  end
  if c then takeMarker(c) end
  -- the chest we already have for it, if it still holds what the turtle sees
  local mine = role == "crafter" and setup.crafters[from] or role == "delivery" and setup.deliveries[from]
    or role == "work" and setup.works[from]
  if mine then
    local ok, list = pcall(peripheral.call, mine, "list")
    if ok and sameItems(list, msg.items) then
      claims[from] = nil
      if role == "crafter" then crafterId = from end
      return { re = "claim", ok = true, chest = mine }
    end
  end
  -- every chest that could be it, those holding just what the turtle sees
  -- first (often only one), other turtles' chests last
  local names, lists = {}, {}
  for _, name in ipairs(peripheral.getNames()) do
    if claimable(name) then names[#names + 1] = name end
  end
  local jobs = {}
  for _, name in ipairs(names) do
    jobs[#jobs + 1] = function()
      local ok, list = pcall(peripheral.call, name, "list")
      lists[name] = ok and list or nil
    end
  end
  -- each call takes a game tick, so ask every chest at once
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
  local taken = {}
  for _, name in pairs(setup.deliveries) do taken[name] = true end
  for _, name in ipairs(crafterChests()) do taken[name] = true end
  local candidates, rank = {}, {}
  for _, name in ipairs(names) do
    if lists[name] then
      candidates[#candidates + 1] = name
      rank[name] = (sameItems(lists[name], msg.items) and 0 or 2) + (taken[name] and 1 or 0)
    end
  end
  table.sort(candidates, function(a, b)
    if rank[a] ~= rank[b] then return rank[a] < rank[b] end
    return a < b
  end)
  c = { role = role, candidates = candidates, i = 0 }
  claims[from] = c
  return nextProbe(from, c)
end

---------------------------------------------------------------- computers' work chests

-- A computer on my cable (smelter, enricher) names its work chest itself
-- (lib/workchest.lua); one far away finds it through an ender chest, the
-- way turtles find theirs (an item dropped into each chest it could be):
--   { type = "work", chest = name }  -> { re = "work", ok = true, chest } or { ok = false, error }
--   { type = "work", items = list() } / { type = "work", seen } -> as claimChest, role "work"
--   { type = "work" }                -> stop using one: what's in it is put away
-- A chest named outright must be empty, so a storage chest full of items
-- never is taken.

-- Put away what's in a work chest and stop treating it as one (in chests
-- mode it's storage again).
releaseWork = function(id)
  local chest = setup.works[id]
  if not chest then return end
  local ok, list = pcall(peripheral.call, chest, "list")
  for slot, item in pairs(ok and list or {}) do putAway(chest, slot, item, item.count) end
  local s = loadSetup() or setup
  s.works = s.works or {}
  setup.works[id], s.works[id] = nil, nil
  saveSetup(s)
  store.scan()
end

-- The chest is now this computer's work chest (in the setup file too).
recordWork = function(from, chest)
  if setup.works[from] ~= chest then releaseWork(from) end
  local s = loadSetup() or setup
  s.works = s.works or {}
  setup.works[from], s.works[from] = chest, chest
  saveSetup(s)
  store.scan() -- it may have been storage until now
  message = { ("Computer #%d's work chest is %s."):format(from, chest), "lime" }
  if report then report.log(("computer #%d's work chest is %s"):format(from, chest)) end
  os.queueEvent("storage_changed")
  return { re = "work", ok = true, chest = chest }
end

local function workChest(from, msg)
  if msg.items ~= nil or msg.seen ~= nil then return claimChest(from, msg, "work") end
  local chest = msg.chest
  if chest == nil then
    releaseWork(from)
    return { re = "work", ok = true }
  end
  if setup.works[from] == chest then return { re = "work", ok = true, chest = chest } end
  local function no(why) return { re = "work", ok = false, error = why } end
  if type(chest) ~= "string" or not peripheral.isPresent(chest) then
    return no(("I can't see %s: put a wired modem on it, on my cable, and right-click it"):format(tostring(chest)))
  end
  for id, name in pairs(setup.works) do
    if name == chest then return no(("it's computer #%d's work chest"):format(id)) end
  end
  for _, list in ipairs({ setup.deliveries, setup.crafters }) do
    for id, name in pairs(list) do
      if name == chest then return no(("it's turtle #%d's chest"):format(id)) end
    end
  end
  if chest == setup.delivery or chest == setup.crafter then return no("it's one of my own chests") end
  if not claimable(chest) then return no("it isn't a chest or barrel I can use (not the input, output, fuel or transfer chest)") end
  local ok, list = pcall(peripheral.call, chest, "list")
  if not ok then return no(tostring(list)) end
  if next(list) then return no("it has items in it: empty it first, or use an empty chest") end
  return recordWork(from, chest)
end

-- With sweep (a far-away computer with one ender chest both ways), first
-- put away everything in it that wasn't asked for: what its machines made
-- and what it sent back. What was asked for stays, up to n of each and fuel
-- for msg.fuel smelts.
local function sweepWork(to, msg)
  local keep, fuelLeft = {}, tonumber(msg.fuel) or 0
  for name, n in pairs(msg.items) do
    if type(name) == "string" and type(n) == "number" then keep[name] = math.floor(n) end
  end
  local okL, list = pcall(peripheral.call, to, "list")
  for slot, item in pairs(okL and list or {}) do
    local kept = 0
    if not item.nbt and keep[item.name] then
      kept = math.min(item.count, keep[item.name])
      keep[item.name] = keep[item.name] - kept
    elseif not item.nbt and fuelSmelts[item.name] and fuelLeft > 0 then
      kept = math.min(item.count, math.ceil(fuelLeft / fuelSmelts[item.name]))
      fuelLeft = fuelLeft - kept * fuelSmelts[item.name]
    end
    if item.count > kept then putAway(to, slot, item, item.count - kept) end
  end
end

-- Top a work chest up to n of each item and to fuel for msg.fuel smelts
-- (what's in it already counts), all in one request.
local function fillWork(from, msg)
  local to = setup.works[from]
  if not to or not peripheral.isPresent(to) then
    return { re = "fill", nochest = true, error = "you have no work chest here" }
  end
  if msg.sweep then sweepWork(to, msg) end
  local present = {}
  local okL, list = pcall(peripheral.call, to, "list")
  for _, item in pairs(okL and list or {}) do
    if not item.nbt then present[item.name] = (present[item.name] or 0) + item.count end
  end
  local sent, ready, failed = {}, {}, nil
  for name, n in pairs(msg.items) do
    if type(name) == "string" and type(n) == "number" and n > 0 then
      n = math.floor(n)
      local have = math.min(present[name] or 0, n)
      sent[name] = 0
      if have < n then
        local err
        sent[name], err = fetch(name, n - have, to)
        failed = failed or err
      end
      ready[name] = have + sent[name]
    end
  end
  -- fuel, from the fuel chest first, in FUEL's order
  local want = tonumber(msg.fuel) or 0
  for _, f in ipairs(FUEL) do want = want - (present[f[1]] or 0) * f[2] end
  for _, f in ipairs(FUEL) do
    if want > 0 then
      local got, err = fetch(f[1], math.ceil(want / f[2]), to, nil, true)
      failed = failed or err
      if got > 0 then
        sent[f[1]] = (sent[f[1]] or 0) + got
        want = want - got * f[2]
      end
    end
  end
  return { re = "fill", sent = sent, ready = ready, fuel = fuelValue(countAll()), error = failed,
    swept = msg.sweep and true or nil }
end

---------------------------------------------------------------- computers' feeders

-- The enricher and smelter feed each Mekanism machine from a hopper, or from
-- a barrel or chest a pipe empties into it (lib/mekfeed.lua). A barrel or chest on my cable would be
-- storage, so it names them (all of them, every time they change):
--   { type = "feeders", chests = { name, ... } } -> { re = "feeders", ok = true } or { ok = false, error }
-- They're kept out of storage, and "send" may fill them. One it didn't
-- have before must be empty, so a storage chest full of items never is taken.
local function isFeederOf(id, name)
  for _, chest in ipairs(setup.feeders[id] or {}) do
    if chest == name then return true end
  end
  return false
end

local function feeders(from, msg)
  local function no(why) return { re = "feeders", ok = false, error = why } end
  if type(msg.chests) ~= "table" then return no("no chests given") end
  local list = {}
  for _, chest in ipairs(msg.chests) do
    if type(chest) ~= "string" or not peripheral.isPresent(chest) or not isInventory(chest) then
      return no(("I can't see %s: put a wired modem on it, on my cable, and right-click it"):format(tostring(chest)))
    end
    if not isFeederOf(from, chest) then
      for id, names in pairs(setup.feeders) do
        for _, name in ipairs(names) do
          if name == chest then return no(("%s is computer #%d's feeder"):format(chest, id)) end
        end
      end
      if not claimable(chest) or chest == setup.delivery or chest == setup.crafter then
        return no(("%s is one of my own chests"):format(chest))
      end
      for _, names in ipairs({ setup.deliveries, setup.crafters }) do
        for id, name in pairs(names) do
          if name == chest then return no(("%s is turtle #%d's chest"):format(chest, id)) end
        end
      end
      local ok, items = pcall(peripheral.call, chest, "list")
      if not ok or next(items) then return no(("%s has items in it: empty it first"):format(chest)) end
    end
    list[#list + 1] = chest
  end
  local s = loadSetup() or setup
  s.feeders = s.feeders or {}
  setup.feeders[from] = #list > 0 and list or nil
  s.feeders[from] = setup.feeders[from]
  saveSetup(s)
  store.scan() -- they may have been storage until now, or be storage again
  os.queueEvent("storage_changed")
  return { re = "feeders", ok = true }
end

-- A request is handled start to finish before the next, and handling one
-- can take a while (moving items, planning crafts). Messages that arrive
-- meanwhile wait here, so none are missed.
local inbox = {}

local function netReceive()
  -- turtles reach us by wireless; the smelter can by the wired network's cable
  net.open("any")
  if not net.hasWireless() then
    message = { "No wireless modem: turtles can't ask me for items.", "orange" }
    os.queueEvent("storage_changed")
  end
  rednet.host(NET_PROTOCOL, os.getComputerLabel() or ("storage-" .. os.getComputerID()))
  while true do
    local from, msg = rednet.receive(NET_PROTOCOL)
    if type(msg) == "table" then
      inbox[#inbox + 1] = { from = from, msg = msg }
      os.queueEvent("storage_inbox")
    end
  end
end

-- Replies carry the request's id, so a turtle never takes a late answer to
-- an earlier request for the answer to a new one.
local function answer(to, request, reply) net.answer(to, NET_PROTOCOL, request, reply) end

local function handleRequest(from, msg)
  if type(msg) == "table" and msg.type == "count" and type(msg.items) == "table" then
    local craftable = {}
    local avail = crafting and hasCrafter() and planningStock()
    local reach = avail and reachNow()
    for _, name in ipairs(msg.items) do
      if type(name) == "string" then
        local need = type(msg.need) == "table" and tonumber(msg.need[name]) or nil
        local n = avail and crafting.craftable(name, avail, need, reach) or 0
        -- the ME/RS system doesn't say how many it could make: take it that
        -- it can make what's needed
        if systemCanCraft(name) then n = math.max(n, need or 64) end
        craftable[name] = n + (pendingCraft[name] or 0)
      end
    end
    answer(from, msg, { re = "count", counts = countPlain(msg.items), craftable = craftable })
  elseif type(msg) == "table" and msg.type == "prepare" and type(msg.items) == "table" then
    -- a turtle waiting for materials: start crafting what it'll need,
    -- beyond what's stored and what's already being made
    local stock, making, cantCraft = planningStock(), {}, {}
    for name, n in pairs(msg.items) do
      if type(name) == "string" and type(n) == "number" then
        local missing = math.floor(n) - math.max(0, stock[name] or 0) - (pendingCraft[name] or 0)
        if missing > 0 then
          local made, why = orderCraft(name, missing)
          if made then making[name] = made end
          if why then cantCraft[name] = why end
          stock = planningStock()
        end
        if (pendingCraft[name] or 0) > 0 then making[name] = pendingCraft[name] end
      end
    end
    answer(from, msg, { re = "prepare", crafting = making, cantCraft = cantCraft, craftProblem = craftProblem })
    local first, why = next(cantCraft)
    local kinds = 0
    for _ in pairs(making) do kinds = kinds + 1 end
    if kinds > 0 then
      message = { ("Crafting %d kinds of item for turtle #%d."):format(kinds, from), "lightBlue" }
    elseif first and why ~= "no recipe for it" then
      message = { ("Can't craft %s for turtle #%d: %s."):format(nameOf(first), from, why), "orange" }
    end
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "learn" then
    local okL, err = false, "this storage computer can't craft (crafting.lua is missing)"
    if crafting then okL, err = crafting.learn(msg.recipe) end
    answer(from, msg, { re = "learn", ok = okL and true or false, error = not okL and err or nil })
    if okL then message = { ("Learnt how to make %s."):format(nameOf(msg.recipe.make)), "lime" } end
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "claim" then
    answer(from, msg, claimChest(from, msg))
  elseif type(msg) == "table" and msg.type == "crafters" then
    -- the overseer: which crafting turtles have a chest
    local list = {}
    for id, chest in pairs(setup.crafters) do
      if peripheral.isPresent(chest) then list[id] = chest end
    end
    answer(from, msg, { re = "crafters", crafters = list, shared = setup.crafter })
  elseif type(msg) == "table" and msg.type == "load" and type(msg.grid) == "table" then
    -- the overseer: one batch into a crafting turtle's chest
    local chest = crafterChest(tonumber(msg.crafter))
    if not chest then
      answer(from, msg, { re = "load", steps = 0, error = ("crafting turtle #%s has no chest here"):format(tostring(msg.crafter)) })
    else
      local steps, why, missing = loadCrafter(chest, msg.grid, math.max(1, math.min(64, math.floor(tonumber(msg.steps) or 1))))
      answer(from, msg, { re = "load", steps = steps, error = why, missing = missing })
    end
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "clear" then
    local chest = crafterChest(tonumber(msg.crafter))
    answer(from, msg, { re = "clear", ok = chest ~= nil and clearCrafter(chest) })
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "jobdone" then
    -- the overseer finished (or gave up on) a job it was given
    for _, job in ipairs(craftQueue) do
      if job.id == msg.job then
        jobFinished(job, msg.ok, msg.why)
        break
      end
    end
    answer(from, msg, { re = "jobdone", ok = true })
  elseif type(msg) == "table" and msg.type == "problem" then
    -- the overseer: why crafting is stuck (nil: it isn't), for turtles waiting on it
    craftProblem = type(msg.text) == "string" and msg.text or nil
    answer(from, msg, { re = "problem", ok = true })
  elseif type(msg) == "table" and msg.type == "recipes" and type(msg.uses) == "string" then
    -- the essence computer: every recipe that uses an item matching a pattern
    local okR, list = false, nil
    if crafting then okR, list = pcall(crafting.using, msg.uses) end
    answer(from, msg, { re = "recipes", recipes = okR and list or {},
      error = not crafting and "this storage computer can't craft (crafting.lua is missing)" or not okR and tostring(list) or nil })
  elseif type(msg) == "table" and msg.type == "stock" then
    local counts = countAll()
    answer(from, msg, { re = "stock", counts = counts, input = setup.input, fuelChest = setup.fuel, fuel = fuelValue(counts),
      work = setup.works[from], workRemote = setup.works[from] ~= nil and isEnder(setup.works[from]) or nil })
  elseif type(msg) == "table" and msg.type == "list" then
    -- every plain item with the name the game shows, for the remote terminal
    local items = {}
    for _, it in pairs(allItems()) do
      if not it.nbt then items[#items + 1] = { name = it.name, label = it.displayName, count = it.count } end
    end
    answer(from, msg, { re = "list", items = items })
  elseif type(msg) == "table" and msg.type == "work" then
    answer(from, msg, workChest(from, msg))
  elseif type(msg) == "table" and msg.type == "fill" and type(msg.items) == "table" then
    local reply = fillWork(from, msg)
    answer(from, msg, reply)
    if reply.error and not reply.nochest then message = { "Couldn't fill a work chest: " .. reply.error, "red" } end
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "feeders" then
    answer(from, msg, feeders(from, msg))
  elseif type(msg) == "table" and msg.type == "send" then
    local sent, failed = {}, nil
    local furnace = isFurnace(msg.to)
    if not furnace and not isHopper(msg.to) and not isFeederOf(from, msg.to) then
      failed = ("%s isn't a furnace, hopper or your feeder on my network"):format(tostring(msg.to))
    elseif furnace and msg.slot == 2 then
      -- fuel for this many more items, of the first kind there is (a fuel
      -- slot only takes one kind), from the fuel chest first
      local want = tonumber(msg.fuel) or 0
      for _, f in ipairs(FUEL) do
        if want > 0 and (msg.item == nil or msg.item == f[1]) then
          local got, err = fetch(f[1], math.min(64, math.ceil(want / f[2])), msg.to, 2, true)
          failed = failed or err
          if got > 0 then
            sent[f[1]] = got
            break
          end
        end
      end
    elseif (msg.slot == 1 or not furnace) and type(msg.items) == "table" then
      -- a hopper: into the slot asked for, or any
      local slot = furnace and 1 or tonumber(msg.slot)
      for name, n in pairs(msg.items) do
        if type(name) == "string" and type(n) == "number" and n > 0 then
          local err
          sent[name], err = fetch(name, math.min(64, math.floor(n)), msg.to, slot)
          failed = failed or err
        end
      end
    end
    answer(from, msg, { re = "send", sent = sent, fuel = fuelValue(countAll()), error = failed })
    if failed then message = { "Couldn't load a furnace or hopper: " .. failed, "red" } end
    os.queueEvent("storage_changed")
  elseif type(msg) == "table" and msg.type == "deliver" and type(msg.items) == "table" then
    -- top the chest up to n of each item: what's already there counts
    local own = setup.deliveries[from]
    local to, sent, total = own or setup.delivery or setup.output, {}, 0
    local held = to ~= setup.output and (reserved[to] or {}) or nil
    reserved[to] = held
    local okL, list = pcall(peripheral.call, to, "list")
    local present = {}
    for _, item in pairs(okL and list or {}) do
      if not item.nbt then present[item.name] = (present[item.name] or 0) + item.count end
    end
    -- ready: how many now wait in the chest; stock: how many are left in storage
    local ready, names, short, failed = {}, {}, false, nil
    for name, n in pairs(msg.items) do
      if type(name) == "string" and type(n) == "number" and n > 0 then
        n = math.floor(n)
        local have = math.min(present[name] or 0, n)
        sent[name] = 0
        if have < n then
          local err
          sent[name], err = fetch(name, n - have, to)
          failed = failed or err
        end
        ready[name] = have + sent[name]
        if ready[name] < n then short = true end
        total = total + sent[name]
        names[#names + 1] = name
        if held then held[name] = { n = ready[name], at = os.clock() } end
      end
    end
    -- what isn't there yet and isn't already being made: craft it if we can
    local making, cantCraft = {}, {}
    for _, name in ipairs(names) do
      local missing = math.floor(msg.items[name]) - ready[name] - (pendingCraft[name] or 0)
      if missing > 0 then
        local made, why = orderCraft(name, missing)
        if made then making[name] = made end
        if why then cantCraft[name] = why end
      end
      if (pendingCraft[name] or 0) > 0 then making[name] = pendingCraft[name] end
    end
    answer(from, msg, { re = "deliver", sent = sent, ready = ready, stock = countPlain(names), crafting = making,
      cantCraft = cantCraft, craftProblem = craftProblem, error = failed,
      to = own and "own" or setup.delivery and "delivery" or "output" })
    if failed then
      message = { "Couldn't move items for a turtle: " .. failed, "red" }
    elseif total > 0 and to == setup.output then
      message = { ("Sent %d items to the output chest for turtle #%d: it has no chest here."):format(total, from), "orange" }
    elseif total > 0 then
      message = { ("Sent %d items to turtle #%d."):format(total, from), "lightBlue" }
    elseif short and next(making) then
      message = { ("Turtle #%d asked for items I'm crafting now."):format(from), "lightBlue" }
    elseif short and next(cantCraft) and select(2, next(cantCraft)) ~= "no recipe for it" then
      local item, why = next(cantCraft)
      message = { ("Can't craft %s for turtle #%d: %s."):format(nameOf(item), from, why), "orange" }
    elseif short then
      message = { ("Turtle #%d asked for items I don't have."):format(from), "orange" }
    end
    if total > 0 and report then report.log(("sent %d items to turtle #%d"):format(total, from)) end
    os.queueEvent("storage_changed")
  end
end

local function netLoop()
  while true do
    while #inbox == 0 do os.pullEvent("storage_inbox") end
    local req = table.remove(inbox, 1)
    handleRequest(req.from, req.msg)
  end
end

-- Keep the delivery chest clear apart from what a turtle has asked for (and
-- not yet taken, for up to HOLD seconds): anything else goes back into
-- storage. As the turtle takes its items, its reservations shrink to match.
local function sweepLoop()
  while true do
    sleep(SWEEP_EVERY)
    local swept = 0
    for _, chest in ipairs(deliveryChests()) do
      local ok, list = pcall(peripheral.call, chest, "list")
      if ok then
        local res = reserved[chest] or {}
        local allow, held = {}, {}
        for name, r in pairs(res) do
          if os.clock() - r.at > HOLD then res[name] = nil else allow[name] = r.n end
        end
        for slot, item in pairs(list) do
          local keep = 0
          if not item.nbt and allow[item.name] then
            keep = math.min(allow[item.name], item.count)
            allow[item.name] = allow[item.name] - keep
            held[item.name] = (held[item.name] or 0) + keep
          end
          if item.count > keep then
            local extra = item.count - keep
            swept = swept + extra - putAway(chest, slot, item, extra)
          end
        end
        for name, r in pairs(res) do
          r.n = held[name] or 0
          if r.n == 0 then res[name] = nil end
        end
      end
    end
    if swept > 0 then
      message = { ("Put away %d items from the delivery chests."):format(swept), "lightGray" }
      os.queueEvent("storage_changed")
    end
    -- turtles may refuel straight from the fuel chest: keep its count fresh
    readFuel()
  end
end

local function rescanLoop()
  while true do
    sleep(store.scanEvery or RESCAN_EVERY)
    store.scan()
    if store.problem then message = { ("The %s Bridge: %s"):format(store.kind, store.problem), "red" } end
    os.queueEvent("storage_changed")
  end
end

-- With stack upgrades on some storage, keep moving the items there's most
-- of into the roomiest storage, a few stacks at a time.
local function tidyLoop()
  if not store.tidy then
    while true do sleep(3600) end
  end
  while true do
    sleep(TIDY_EVERY)
    local moved, what = store.tidy()
    -- a quiet note: never cover up anything more important
    if moved > 0 and message[2] == "lightGray" then
      message = { what and ("Moved %s into roomier storage."):format(what)
        or "Made room in the roomiest storage for bulk items.", "lightGray" }
      os.queueEvent("storage_changed")
    end
  end
end

-- Keep the list of what could be crafted (but isn't stored) up to date: after
-- storage changes, at most every VIEW_EVERY seconds. Counting is a plan per
-- try, so it runs here rather than on every redraw.
local function craftViewLoop()
  if not CRAFTABLE_TAB then
    while true do sleep(3600) end
  end
  while true do
    local view, avail = {}, planningStock()
    if crafting and hasCrafter() then
      local reach = crafting.reachable(avail)
      reachCache, reachAt = reach, os.clock()
      for _, name in ipairs(crafting.names()) do
        if (avail[name] or 0) <= 0 and reach[name] then
          local n = crafting.craftable(name, avail, VIEW_MAX, reach)
          if n > 0 then view[#view + 1] = { key = name, name = name, count = n, displayName = titleName(name), craftable = true } end
        end
      end
    end
    if store.craftables then
      local listed = {}
      for _, it in ipairs(view) do listed[it.name] = true end
      for _, name in ipairs(store.craftables()) do
        if not listed[name] and (avail[name] or 0) <= 0 then
          view[#view + 1] = { key = name, name = name, displayName = titleName(name), craftable = true }
        end
      end
    end
    craftView, craftViewReady = view, true
    os.queueEvent("storage_view")
    sleep(VIEW_EVERY)
    os.pullEvent("storage_changed")
  end
end

-- Send crafts asked for on the terminal to the output chest as they're made.
-- Once nothing more is being made, whatever didn't turn up is given up on
-- (the footer has already said why the craft failed).
local function outputLoop()
  while true do
    sleep(OUTPUT_EVERY)
    for name, o in pairs(outputOrders) do
      local have = countAll()[name] or 0
      if have > 0 then
        o.sent = o.sent + fetch(name, math.min(have, o.want - o.sent), setup.output)
      end
      if o.sent >= o.want then
        outputOrders[name] = nil
        message = { ("Crafted %d %s: it's in the output chest."):format(o.sent, nameOf(name)), "lime" }
        os.queueEvent("storage_changed")
      elseif (pendingCraft[name] or 0) == 0 and have == 0 then
        outputOrders[name] = nil
        if o.sent > 0 then
          message = { ("Only %d of %d %s were made: they're in the output chest."):format(o.sent, o.want, nameOf(name)), "orange" }
        end
        os.queueEvent("storage_changed")
      end
    end
  end
end

---------------------------------------------------------------- dumping into an ender chest

-- 'storage dump <chest>' moves everything stored into an ender chest whose
-- twin is another storage system's input chest, which empties it as fast
-- as it fills. The job is a file, so the running program picks it up (the
-- command may be typed in another tab) and carries on after a reboot.

isEnder = function(name)
  local t = peripheral.getType(name)
  return t and t:find("ender", 1, true) ~= nil
end

-- Why this chest can't be dumped into, or nil if it can: only an ender
-- chest that isn't already one of mine, a turtle's or a computer's.
local function dumpProblem(chest)
  if not peripheral.isPresent(chest) then return ("I can't see %s on my network"):format(chest) end
  if not isEnder(chest) or not isInventory(chest) then
    return "only an ender chest (EnderStorage or the like) can be dumped into: its twin is the other storage system's input chest"
  end
  for _, which in ipairs({ "input", "output", "delivery", "crafter", "fuel", "transfer" }) do
    if setup[which] == chest then return ("it's my %s chest"):format(which) end
  end
  for _, list in ipairs({ setup.inputs, setup.deliveries, setup.crafters, setup.works }) do
    for _, name in pairs(list) do
      if name == chest then return "it's already in use (an input chest, a turtle's or a computer's)" end
    end
  end
  return nil
end

local function chestFull(chest)
  local okS, size = pcall(peripheral.call, chest, "size")
  local okL, list = pcall(peripheral.call, chest, "list")
  if not (okS and okL) then return true end
  local used = 0
  for _ in pairs(list) do used = used + 1 end
  return used >= size
end

local function dumpLoop()
  while true do
    local job = files.read(DUMP_FILE)
    if type(job) ~= "table" or not job.chest then
      sleep(DUMP_WAIT)
    else
      local why = dumpProblem(job.chest)
      local moved, left = 0, 0
      local room = not why and not chestFull(job.chest)
      if why then
        message = { ("Dump paused: %s."):format(why), "orange" }
      elseif room then
        -- biggest piles first; stop as soon as the chest is full
        local list = {}
        for _, it in pairs(allItems()) do list[#list + 1] = it end
        table.sort(list, function(a, b) return a.count > b.count end)
        for _, it in ipairs(list) do
          local n = fetch(it.key, it.count, job.chest)
          moved = moved + n
          if n < it.count then
            left = left + it.count - n
            if chestFull(job.chest) then break end
          end
        end
      end
      local cur = files.read(DUMP_FILE)
      if type(cur) == "table" and cur.at == job.at then -- not stopped or replaced meanwhile
        cur.moved = (cur.moved or 0) + moved
        -- done when nothing's left, or when there was room and nothing more
        -- would go (items the chest or the bridge won't move)
        if not why and (not next(allItems()) or (room and moved == 0)) then
          message = { ("Dump done: moved %d items into %s%s."):format(cur.moved, job.chest,
            left > 0 and (", %d wouldn't go"):format(left) or ""), left > 0 and "orange" or "lime" }
          if report then report.log(("dumped %d items"):format(cur.moved)) end
          files.delete(DUMP_FILE)
        else
          files.write(DUMP_FILE, cur)
          if not why then
            message = { ("Dumping into %s: %d moved so far%s."):format(job.chest, cur.moved,
              moved == 0 and ", waiting for the other side to empty it" or ""), "lightBlue" }
          end
        end
      end
      if moved > 0 or why then os.queueEvent("storage_changed") end
      sleep(moved > 0 and 0 or DUMP_WAIT)
    end
  end
end

---------------------------------------------------------------- changing one setting

-- 'storage config [what [chest|none]]': change one chest of the setup, the
-- extra input chests, or which ender chest on my cable a far-away enricher
-- or smelter works through, without the full setup. The running program
-- (this computer's other tab, or the next start) picks it up.
local CONFIG = {
  { key = "input", what = "input chest", need = true },
  { key = "inputs", what = "extra input chests" },
  { key = "output", what = "output chest", need = true },
  { key = "delivery", what = "shared delivery chest" },
  { key = "crafter", what = "crafter chest" },
  { key = "fuel", what = "fuel chest" },
  { key = "transfer", what = "transfer chest (ME or RS only)" },
  { key = "remote", what = "far-away enricher's or smelter's ender chest" },
}

-- Every chest the setup s already uses for something, but not its storage.
local function usedIn(s)
  local used = {}
  for _, which in ipairs({ "input", "output", "delivery", "crafter", "fuel", "transfer" }) do
    if s[which] then used[s[which]] = which .. " chest" end
  end
  for _, name in ipairs(s.inputs or {}) do used[name] = "an extra input chest" end
  for id, name in pairs(s.deliveries or {}) do used[name] = ("turtle #%s's chest"):format(tostring(id)) end
  for id, name in pairs(s.crafters or {}) do used[name] = ("crafting turtle #%s's chest"):format(tostring(id)) end
  for id, name in pairs(s.works or {}) do used[name] = ("computer #%s's work chest"):format(tostring(id)) end
  for id, list in pairs(s.feeders or {}) do
    for _, name in ipairs(list) do used[name] = ("computer #%s's feeder"):format(tostring(id)) end
  end
  return used
end

-- Pick from a numbered list (or type a name). nil on Enter, "none" for none.
local function pickFrom(question, list)
  for i, name in ipairs(list) do
    local ok, items = pcall(peripheral.call, name, "list")
    local n = 0
    for _ in pairs(ok and items or {}) do n = n + 1 end
    print(("%2d  %s%s"):format(i, name, n > 0 and (" (" .. n .. " stacks)") or ""))
  end
  write(question .. " ")
  local text = read()
  if text == "" then return nil end
  if text == "none" then return "none" end
  return list[tonumber(text)] or text
end

local function configChest(s, c, name)
  local used = usedIn(s)
  if not name then
    print(("The %s is %s."):format(c.what, s[c.key] or "not set"))
    local list = {}
    for _, n in ipairs(peripheral.getNames()) do
      -- an ender chest only as an input (a far-away return chest's home end)
      if isInventory(n) and (c.ender or not isEnder(n)) and (not used[n] or n == s[c.key]) then list[#list + 1] = n end
    end
    table.sort(list)
    print("Chests on the network (right-click a modem to see its chest's name):")
    name = pickFrom(("Which one?%s (Enter: keep it)"):format(c.need and "" or " 'none' for none."), list)
    if not name then return false end
  end
  if name == "none" then
    if c.need then print(("There has to be an %s."):format(c.what)) return false end
    s[c.key] = nil
    return true
  end
  if not peripheral.isPresent(name) or not isInventory(name) then print(name .. " isn't a chest on my network.") return false end
  if used[name] and name ~= s[c.key] then print(("%s is already the %s."):format(name, used[name])) return false end
  s[c.key] = name
  return true
end

local function configInputs(s, name)
  s.inputs = s.inputs or {}
  print("Extra input chests, emptied like the input chest:")
  if #s.inputs == 0 then print("  none") end
  for i, n in ipairs(s.inputs) do print(("  %d  %s"):format(i, n)) end
  if not name then
    write("Add one (a), remove one (r), or Enter to leave: ")
    local a = read():lower()
    if a == "r" then
      write("Remove which number? ")
      local i = tonumber(read())
      if not s.inputs[i] then return false end
      print(("%s is storage again."):format(table.remove(s.inputs, i)))
      return true
    elseif a ~= "a" then
      return false
    end
  end
  local c = { key = "newInput", what = "new extra input chest", ender = true }
  if not configChest(s, c, name) or not s.newInput then s.newInput = nil return false end
  s.inputs[#s.inputs + 1], s.newInput = s.newInput, nil
  return true
end

-- Every far-away enricher and smelter (they host their protocol), as
-- { { id, kind } }, or nil and why.
local function findWorkers()
  if not net.open("any") then return nil, "I need a wireless or ender modem to find them." end
  local found = {}
  for kind, protocol in pairs(WORKER_PROTOCOLS) do
    for _, id in ipairs({ rednet.lookup(protocol) }) do found[#found + 1] = { id = id, kind = kind } end
  end
  table.sort(found, function(a, b) return a.id < b.id end)
  return found
end

-- Far-away enrichers and smelters: found by wireless (they host their
-- protocol); pick which ender chest on my cable is each one's work chest,
-- so its own end needs no probing (Work chest, Far away on its setup screen takes it).
local function configRemote(s)
  s.works = s.works or {}
  print("Looking for enrichers and smelters...")
  local found, why = findWorkers()
  if not found then print(why) return false end
  if #found == 0 then
    print("None answered. Are they running, with an ender or wireless modem (and updated)?")
    write("Type a computer's ID to set it anyway (Enter to leave): ")
    local id = tonumber(read())
    if not id then return false end
    found[1] = { id = id, kind = "computer" }
  end
  for i, w in ipairs(found) do
    print(("%2d  %s #%d: %s"):format(i, w.kind, w.id, s.works[w.id] or "no work chest here"))
  end
  local w = found[1]
  if #found > 1 then
    write("Which one? (Enter to leave) ")
    w = found[tonumber(read())]
    if not w then return false end
  end
  local used, list = usedIn(s), {}
  for _, n in ipairs(peripheral.getNames()) do
    if isEnder(n) and isInventory(n) and (not used[n] or n == s.works[w.id]) then list[#list + 1] = n end
  end
  table.sort(list)
  if #list == 0 then
    print("No free ender chest on my network. Put the twin of its ender chest on my cable")
    print("with a wired modem (not as an input chest) and right-click the modem.")
    return false
  end
  print(("Ender chests on my cable. Which is %s #%d's? Its twin is at that computer."):format(w.kind, w.id))
  local name = pickFrom("Which? 'none' to stop. (Enter: keep it)", list)
  if not name then return false end
  if name == "none" then
    s.works[w.id] = nil
    print("Done. What's left in it stays there.")
    return true
  end
  if not isEnder(name) then print(name .. " isn't an ender chest on my network.") return false end
  s.works[w.id] = name
  print(("Done. On %s #%d, run '%s setup' and pick Work chest, Far away (nothing to do if it"):format(w.kind, w.id,
    w.kind == "computer" and "<program>" or w.kind))
  print("already works far away): it takes this one without a search.")
  return true
end

---------------------------------------------------------------- setup

-- The setup screen (setupui.lua) on this computer's terminal and the
-- monitor. s is edited in place; true when the player saved it.
-- The settings on the setup screen's first page, and the line shown above
-- each one's list.
local SETTINGS = {
  { key = "input", what = "Input chest", need = true, hint = "Items dropped in here get put away." },
  { key = "inputs", what = "Extra input chests", hint = "Emptied like the input chest." },
  { key = "output", what = "Output chest", need = true, hint = "What you take from storage is sent here." },
  { key = "delivery", what = "Shared delivery chest", hint = "For turtles that can't find a chest of their own." },
  { key = "crafter", what = "Crafter chest", hint = "In front of the crafting turtle (or let it find its own)." },
  { key = "fuel", what = "Fuel chest", hint = "Coal and charcoal for the smelter and the turtles." },
  { key = "transfer", what = "Transfer chest", bridge = true, hint = "Items for furnaces and the crafter pass through it." },
  { key = "remote", what = "Far-away workers", hint = "Enrichers and smelters at another base, through an ender chest." },
}

-- The chests turtles and computers claim themselves: picking one for
-- something else takes it back (they find another). Mekanism feeders are
-- left alone: the enricher and smelter register them again every round.
local CLAIMS = { "deliveries", "crafters", "works" }

-- The setup screen (lib/setupui.lua) on this computer's terminal and the
-- monitor: every setting on one page, chest lists a page at a time with
-- what's in each. s is edited in place; true when the player saved it.
editSetup = function(s, kind, first)
  for _, which in ipairs({ "inputs", "deliveries", "crafters", "works", "feeders" }) do s[which] = s[which] or {} end
  -- the store: chests, unless there's a bridge to use
  if not kind then s.backend = "chests" elseif not s.backend then s.backend = "bridge" end
  local ui = setupui.new({ screens = { termScreen, monScreen },
    -- a second 'storage setup' meanwhile: this one is open already
    onEvent = function(ev) if ev[1] == "storage_open_setup" then os.queueEvent("storage_setup_opened") end end })

  local function claimed(name)
    for _, which in ipairs(CLAIMS) do
      for _, n in pairs(s[which]) do
        if n == name then return true end
      end
    end
    return false
  end
  local function unclaim(name)
    for _, which in ipairs(CLAIMS) do
      for id, n in pairs(s[which]) do
        if n == name then s[which][id] = nil end
      end
    end
  end

  -- The chest list for setting c (c.ender: ender chests too, c.enderOnly:
  -- only those, c.worker: a far-away worker's), then done(name or nil).
  local function pickFor(c, done)
    local cur = c.worker and s.works[c.worker.id] or s[c.key]
    local names = {}
    for _, n in ipairs(peripheral.getNames()) do
      if isInventory(n) then
        local ender = isEnder(n)
        if c.enderOnly and ender or not c.enderOnly and (c.ender or not ender) then names[#names + 1] = n end
      end
    end
    table.sort(names)
    ui:pickChest({ title = "Pick: " .. c.what, hint = c.hint, names = names, current = cur,
      none = not c.need and "(none)" or nil, nothing = "No chests here.",
      roleOf = function(n) return usedIn(s)[n] end,
      pick = function(name)
        local role = name and name ~= cur and usedIn(s)[name]
        if role and not claimed(name) then
          ui:say(("%s is already the %s."):format(name, role), "orange")
          return
        end
        if role then unclaim(name) end
        ui:back()
        done(name)
      end })
    ui:say(c.need and "Tap a chest." or "Tap a chest, or (none).")
  end

  local inputsPage = {
    title = "Extra input chests", hint = SETTINGS[2].hint,
    rows = function()
      local out = { { label = "+ Add an input chest", colour = "lime", act = function()
        pickFor({ what = "New input chest", ender = true, need = true, hint = SETTINGS[2].hint }, function(name)
          s.inputs[#s.inputs + 1] = name
          ui:say(("%s is an input chest now."):format(name), "lime")
        end)
      end } }
      for i, n in ipairs(s.inputs) do
        out[#out + 1] = { label = n, value = "tap to remove", colour = "gray", act = function()
          table.remove(s.inputs, i)
          ui:say(("%s is storage again."):format(n), "lime")
        end }
      end
      return out
    end,
  }

  local found, why
  local function look()
    ui:say("Looking for enrichers and smelters...", "lightBlue")
    ui:draw()
    found, why = findWorkers()
    found = found or {}
    ui:say(#found > 0 and "Tap one to pick its ender chest here." or "Nothing found.", #found > 0 and "lightGray" or "orange")
  end
  local workersPage = {
    title = "Far-away workers", hint = SETTINGS[8].hint,
    enter = function() if not found then look() end end,
    rows = function()
      local out = {}
      for _, w in ipairs(found or {}) do
        out[#out + 1] = { label = ("%s #%d"):format(w.kind, w.id), value = s.works[w.id] or "no ender chest here",
          colour = s.works[w.id] and "lightGray" or "gray", act = function()
            pickFor({ what = ("%s #%d's ender chest"):format(w.kind, w.id), worker = w, enderOnly = true,
              hint = "Its twin is at that computer." }, function(name)
              s.works[w.id] = name
              ui:say(name and ("On %s #%d, run '%s setup' and pick Work chest, Far away: it takes %s."):format(w.kind,
                w.id, w.kind, name) or "Done. What's left in its old ender chest stays there.", "lime")
            end)
          end }
      end
      if found and #found == 0 then
        out[#out + 1] = { label = why or "None answered: are they running, with an ender or wireless modem?", dim = true }
      end
      out[#out + 1] = { label = "Look again", colour = "lightBlue", act = look }
      return out
    end,
  }

  local main = {
    title = first and "Storage setup" or "Storage settings",
    rows = function()
      local out = {}
      if kind then
        out[#out + 1] = { label = "Store items in", value = s.backend == "bridge" and ("the " .. kind .. " system") or "chests",
          act = function()
            s.backend = s.backend == "bridge" and "chests" or "bridge"
            if s.backend ~= "bridge" then s.transfer = nil end
          end }
      end
      for _, c in ipairs(SETTINGS) do
        if not c.bridge or s.backend == "bridge" then
          local value, colour = s[c.key], "lightGray"
          if c.key == "inputs" then
            value = #s.inputs == 0 and "none" or #s.inputs == 1 and s.inputs[1] or (#s.inputs .. " chests")
          elseif c.key == "remote" then
            value = "find them"
          elseif not value then
            value, colour = c.need and "not set" or "none", c.need and "orange" or "gray"
          end
          out[#out + 1] = { label = c.what, value = value, colour = colour, act = function()
            if c.key == "inputs" then
              ui:open(inputsPage)
            elseif c.key == "remote" then
              ui:open(workersPage)
            else
              pickFor(c, function(name)
                s[c.key] = name
                ui:say(("%s: %s."):format(c.what, name or "none"), "lime")
              end)
            end
          end }
        end
      end
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

-- A storage program running in another tab opens the setup screen itself
-- (it has the monitor): true when one answered.
local function openInRunning()
  os.queueEvent("storage_open_setup")
  local timer = os.startTimer(0.5)
  while true do
    local e, p = os.pullEvent()
    if e == "storage_setup_opened" then return true end
    if e == "timer" and p == timer then return false end
  end
end

local function clearTerminal()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

-- The first setup, or 'storage setup' with no storage program running.
-- Returns the saved setup, or nil.
local function chooseChests()
  local kind
  if bridges then kind = select(2, bridges.find()) end
  local invs = 0
  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) then invs = invs + 1 end
  end
  if invs < 2 then
    print(("I can only see %d chests. I need at least an input and an output"):format(invs))
    print("chest on the network, and chests to store in (or an ME or RS bridge).")
    print("Put a full-block wired modem against each chest, connect")
    print("them with cable, and right-click each modem so it turns red.")
    return nil
  end
  local old = loadSetup()
  local s = old or {}
  local saved = editSetup(s, kind, old == nil)
  clearTerminal()
  if not saved then
    print("Setup closed: nothing saved.")
    return nil
  end
  saveSetup(s)
  print(s.backend == "bridge" and ("Saved. Items are stored in the %s system."):format(kind)
    or "Saved. Every other chest is storage.")
  return s
end

-- 'storage setup' / 'storage config' with no setting: the setup screen, in
-- the running storage program if there is one (it has the monitor), else here.
local function setupCommand()
  if openInRunning() then
    print("The setup screen is open in the storage program (its tab) and on its monitor.")
    return
  end
  chooseChests()
end

local function configCommand(what, value)
  local s = loadSetup()
  if not s then print("Not set up yet: run 'storage' first.") return end
  local c
  for _, x in ipairs(CONFIG) do
    if x.key == what then c = x end
  end
  if not c then
    if what then
      local names = {}
      for _, x in ipairs(CONFIG) do names[#names + 1] = x.key end
      print(("No setting called %s. They are: %s."):format(what, table.concat(names, ", ")))
      return
    end
    return setupCommand()
  end
  if c.key == "transfer" and s.backend ~= "bridge" then
    print("Only an ME or RS system needs a transfer chest.")
    return
  end
  local changed
  if c.key == "remote" then
    changed = configRemote(s)
  elseif c.key == "inputs" then
    changed = configInputs(s, value)
  else
    changed = configChest(s, c, value)
  end
  if not changed then print("Nothing changed.") return end
  saveSetup(s)
  os.queueEvent("storage_setup") -- the running program, if this is another tab
  print("Saved. The running storage program uses it straight away (or when it next starts).")
end

local args = { ... }
if args[1] == "config" then
  configCommand(args[2], args[3])
  return
end
if args[1] == "setup" then
  setupCommand()
  return
end
if not loadSetup() then
  setup = chooseChests()
  if not setup then return end
else
  setup = loadSetup()
end
for _, which in ipairs({ "input", "output" }) do
  if not peripheral.isPresent(setup[which]) then
    print(("Can't find the %s chest (%s). Check its modem is red, or run 'storage setup'."):format(which, setup[which]))
    return
  end
end
-- the optional ones: carry on without them, and say so
local missingChest
for _, which in ipairs({ "delivery", "crafter", "fuel", "transfer" }) do
  if setup[which] and not peripheral.isPresent(setup[which]) then
    print(("Can't find the %s chest (%s), so I'll do without it."):format(which, setup[which]))
    print("Check its modem is red, or run 'storage setup'.")
    missingChest = ("No %s chest found (%s): check its modem."):format(which, setup[which])
    setup[which] = nil
  end
end
setup.inputs = setup.inputs or {}
for i = #setup.inputs, 1, -1 do
  local name = setup.inputs[i]
  if not peripheral.isPresent(name) then
    print(("Can't find the extra input chest (%s), so I'll do without it."):format(name))
    print("Check its modem is red, or run 'storage setup'.")
    missingChest = ("No input chest found (%s): check its modem."):format(name)
    table.remove(setup.inputs, i)
  end
end
setup.deliveries, setup.crafters = setup.deliveries or {}, setup.crafters or {}
for _, list in ipairs({ setup.deliveries, setup.crafters }) do
  for id, name in pairs(list) do
    if not peripheral.isPresent(name) then
      print(("Can't find turtle #%s's chest (%s): it'll find it again when it next asks."):format(tostring(id), name))
      list[id] = nil
    end
  end
end
-- work chests are kept even while missing: fill says so, and one that comes
-- back with items still in it is still theirs (a claim needs an empty chest)
setup.works = setup.works or {}
setup.feeders = setup.feeders or {}

-- 'storage dump [chest|stop]': save the job for the running program
if args[1] == "dump" then
  local cur = files.read(DUMP_FILE)
  if args[2] == "stop" then
    files.delete(DUMP_FILE)
    print(type(cur) == "table" and ("Dump stopped (%d items moved)."):format(cur.moved or 0) or "No dump was running.")
    return
  end
  if type(cur) == "table" then print(("A dump into %s is running: %d moved so far."):format(cur.chest, cur.moved or 0)) end
  local chest = args[2]
  if not chest then
    local list = {}
    for _, name in ipairs(peripheral.getNames()) do
      if not dumpProblem(name) then list[#list + 1] = name end
    end
    table.sort(list)
    if #list == 0 then
      print("No free ender chest on my network. Put one on the cable with a wired modem")
      print("(its twin is the other storage system's input chest) and right-click the modem.")
      return
    end
    print("Ender chests on my network:")
    for i, name in ipairs(list) do print(("%2d  %s"):format(i, name)) end
    write("Dump everything into which one? (Enter to cancel) ")
    local text = read()
    if text == "" then return end
    chest = list[tonumber(text)] or text
  end
  local why = dumpProblem(chest)
  if why then
    print(("Can't dump into %s: %s."):format(chest, why))
    return
  end
  files.write(DUMP_FILE, { chest = chest, at = os.epoch("utc"), moved = 0 })
  print(("Dump saved: everything stored goes into %s, as fast as the other side empties it."):format(chest))
  print("The storage program starts on it within a few seconds (or when it's next started).")
  print("'storage dump stop' stops it.")
  return
end

if setup.backend == "bridge" then
  if not bridges then
    print("bridge.lua is missing: run 'install update'.")
    return
  end
  local err
  store, err = bridges.new(setup)
  if not store then
    print(("Can't use the ME or RS system: %s."):format(err))
    print("Put a wired modem on the bridge, join it to the network")
    print("and right-click the modem, or run 'storage setup'.")
    return
  end
  print(("Reading the %s system..."):format(store.kind))
  store.scan()
  store.clearTransfer() -- left over from a move cut short
else
  store = chests.new(setup)
  print("Scanning chests...")
  store.scan()
end
readFuel()

-- 'storage tidy': say what slot sizes the storage has, and sort the bulk
-- items into the roomiest storage now, saying each move (and why, if none).
if args[1] == "tidy" then
  if not store.tidy then
    print(("The %s system sorts its own storage: nothing to tidy."):format(store.kind))
    return
  end
  local _, _, bySize = store.roomInfo()
  print("Storage by how much one slot holds:")
  for _, s in ipairs(bySize) do print(("  %5d a slot: %d storages"):format(s[1], s[2])) end
  local total = 0
  for _ = 1, 500 do
    local n = store.tidy(print)
    total = total + n
    if n == 0 then break end
  end
  print(("Done: moved %d stacks."):format(total))
  return
end

-- 'storage test': move one item into the delivery (or output) chest and back,
-- and say what went wrong if it can't.
if args[1] == "test" then
  local _, _, space = store.space()
  print(("Storage: %s."):format(space))
  if store.roomInfo then
    local roomy, most = store.roomInfo()
    print(roomy > 0 and ("%d of them hold more than 64 a slot (up to %d): bulk items go there."):format(roomy, most)
      or "Every chest holds 64 a slot (no stack upgrades).")
  end
  if store.problem then print(("The %s Bridge says: %s"):format(store.kind, store.problem)) end
  local turtles = 0
  for id, name in pairs(setup.deliveries) do
    print(("Turtle #%s's chest: %s."):format(tostring(id), name))
    turtles = turtles + 1
  end
  if turtles == 0 then print("No turtle has found its own chest yet (they do when they first ask for items).") end
  for id, name in pairs(setup.works) do
    print(("Computer #%s's work chest: %s%s."):format(tostring(id), name,
      peripheral.isPresent(name) and "" or " (not on the network)"))
  end
  local to = setup.delivery or setup.output
  print(("Testing a move into the %s chest (%s)..."):format(setup.delivery and "shared delivery" or "output", to))
  local pick
  for _, it in ipairs(totals()) do
    if not it.nbt and not it.craftable then pick = it break end
  end
  if not pick then
    print("Storage is empty: put something in the input chest first.")
    return
  end
  local function moveBack()
    local okL, list = pcall(peripheral.call, to, "list")
    for slot, item in pairs(okL and list or {}) do
      if keyOf(item) == pick.key then
        putAway(to, slot, item, 1)
        return
      end
    end
  end
  local sent, err = fetch(pick.key, 1, to)
  if sent > 0 then
    print(("OK: moved 1 %s there."):format(pick.displayName))
    moveBack()
    print("Moved it back. Deliveries work.")
  else
    print("Couldn't move it: " .. (err or "that chest is full"))
    print("Check its modem is red and joined by cable to the " .. (setup.backend == "bridge" and "bridge." or "storage chests."))
  end
  if setup.backend == "bridge" then
    -- a move into one slot goes through the transfer chest
    local okL, list = pcall(peripheral.call, to, "list")
    local okS, size = pcall(peripheral.call, to, "size")
    local free
    for slot = 1, okS and size or 0 do
      if not (okL and list[slot]) then free = slot break end
    end
    if not setup.transfer then
      print("No transfer chest: the bridge can't load the smelter's furnaces or the crafting turtle. Run 'storage setup'.")
    elseif free then
      local got, why = fetch(pick.key, 1, to, free)
      if got > 0 then
        print(("OK: moved 1 %s into slot %d through the transfer chest."):format(pick.displayName, free))
        moveBack()
      else
        print("Couldn't move it through the transfer chest: " .. (why or "no idea why"))
      end
    end
    print(systemCanCraft(pick.name) and ("The %s system can craft %s."):format(store.kind, pick.displayName)
      or ("The %s system has no pattern for %s (fine: it's just a test item)."):format(store.kind, pick.displayName))
  end
  print(setup.fuel and ("Fuel chest: %s. Fuel stored for %d items."):format(setup.fuel, fuelValue(countAll()))
    or "No fuel chest: fuel is kept with everything else.")
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  print(modem and ("Wireless modem on %s: turtles can ask me for items."):format(peripheral.getName(modem))
    or "No wireless modem: turtles can't ask me for items.")
  -- crafting
  if not crafting then
    print("crafting.lua is missing, so I can't craft: run 'install update'.")
  elseif not hasCrafter() then
    print(("I know %d recipes, but there's no crafter chest yet. Start a crafting"):format(crafting.count()))
    print("turtle against a chest on my network and it'll find it.")
  else
    print(("I know %d recipes."):format(crafting.count()))
    for id, chest in pairs(setup.crafters) do print(("Crafting turtle #%s's chest: %s."):format(tostring(id), chest)) end
    if setup.crafter then print(("Shared crafter chest: %s."):format(setup.crafter)) end
    if packError then
      print("pack_recipes.lua didn't load: " .. packError)
    elseif packRecipes > 0 then
      print(("%d of them come from pack_recipes.lua (the modpack)."):format(packRecipes))
    else
      print("No pack_recipes.lua: only vanilla recipes. See 'Modded recipes' in the README.")
    end
    -- the crafting turtle may answer by wireless or over the cable
    net.open("any")
    local overseer = rednet.lookup(OVERSEER_PROTOCOL)
    print(overseer and ("Crafting overseer #%d runs the crafting queue."):format(overseer)
      or "No crafting overseer: I run the crafting queue myself, on one turtle.")
    local ids = { rednet.lookup(CRAFT_PROTOCOL) }
    for _, id in ipairs(ids) do
      local ping = { type = "ping" }
      local ok = net.ask(id, CRAFT_PROTOCOL, ping, { wait = 5,
        match = function(reply) return reply.type == "pong" and reply.id == ping.id end }) ~= nil
      print(("Crafting turtle #%d %s%s."):format(id, ok and "answered" or "didn't answer a ping",
        crafterChest(id) and "" or ", but has no chest here yet"))
    end
    if #ids > 0 then
      -- each one answered (or not) above
    elseif not modem then
      print("No crafting turtle answered. It talks by wireless, so put a")
      print("wireless modem on me (or a full-block wired modem against the")
      print("turtle, on this cable). Is it running 'crafter'?")
    else
      print("No crafting turtle answered: is it running 'crafter', with a modem?")
    end
  end
  return
end

term.clear()
if missingChest then message = { missingChest, "orange" } end
if packError then message = { "pack_recipes.lua didn't load: run 'storage test'.", "red" } end
if store.problem then message = { ("The %s Bridge: %s"):format(store.kind, store.problem), "red" } end

if report then report.init("storage") end
-- 'storage config' in another tab saved a change: use it now (the table is
-- changed in place, since the store keeps it). A new kind of store needs a
-- restart.
local function setupLoop()
  while true do
    os.pullEvent("storage_setup")
    local s = loadSetup()
    if s and s.backend == setup.backend then
      for k in pairs(setup) do setup[k] = nil end
      for k, v in pairs(s) do setup[k] = v end
      for _, which in ipairs({ "inputs", "deliveries", "crafters", "works", "feeders" }) do
        setup[which] = setup[which] or {}
      end
      store.scan()
      readFuel()
      message = { "Setup changed: using it now.", "lime" }
    else
      message = { "The kind of store changed: restart me.", "orange" }
    end
    os.queueEvent("storage_changed")
  end
end

local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, inputLoop, rescanLoop, netReceive, netLoop, sweepLoop, craftLoop,
  tidyLoop, craftViewLoop, outputLoop, dumpLoop, setupLoop, report and report.loop or function() while true do sleep(3600) end end)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
