-- Storage system. Either every chest and barrel on the wired modem network
-- becomes one big store, or an Applied Energistics 2 / Refined Storage
-- system does the storing, through an Advanced Peripherals ME Bridge or RS
-- Bridge (chests.lua and bridge.lua; 'storage setup' picks). Drop items in
-- the input chest and they get put away; type to search on the terminal and
-- press Enter to have a stack sent to the output chest. A monitor, if
-- attached, shows what's stored most.
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
--
--   storage          start (asks how it's set up the first time)
--   storage setup    choose the store and the input, output, shared delivery, crafter, fuel and transfer chests again
--   storage test     check deliveries (one item there and back), the fuel chest and the crafting turtle
--   storage tidy     show the storage's slot sizes and sort bulk items into the roomiest now
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
local bridges = fs.exists("bridge.lua") and require("bridge")

local SETUP_FILE = "/.storage_setup"

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
local MONITOR_SCALE = 0.5 -- text size on the monitor
local NET_PROTOCOL = "storage" -- rednet protocol turtles ask for items on
local SWEEP_EVERY = 5 -- seconds between clear-outs of the delivery chest
local HOLD = 600 -- seconds items a turtle asked for wait in the delivery chest before going back
local CRAFT_PROTOCOL = "storage_crafter" -- rednet protocol the crafting turtle takes jobs on
local CRAFT_WAIT = 60 -- seconds to wait for the crafting turtle to finish one batch
local MAX_BATCH_OUTPUT = 384 -- most items one batch may make (6 stacks: they must fit in the turtle)
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
--   deliveries = { [turtle id] = name } }
-- deliveries are the turtles' own chests, and crafter can be, too: each
-- turtle finds its chest on the network itself (lib/claim.lua, the "claim"
-- request). delivery is the shared one for turtles without their own.
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

local function storeInput()
  local ok, list = pcall(peripheral.call, setup.input, "list")
  if not ok or not next(list) then return false end
  local full = false
  for slot, item in pairs(list) do
    if putAway(setup.input, slot, item, item.count) > 0 then full = true end
  end
  if full then
    message = { "Storage is full: some items are still in the input chest.", "red" }
    if report then report.log("storage full") end
  end
  return true
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

-- The search hits in the open tab, plus those in each tab (for their counts).
local function matches()
  local q, stored, craft = query:lower(), {}, {}
  for _, it in ipairs(totals()) do
    if q == "" or it.displayName:lower():find(q, 1, true) or it.key:lower():find(q, 1, true) then
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
local monScreen = screen.find({ scales = { MONITOR_SCALE } }) -- the monitor's, if there is one

local function drawTerminal()
  local t, w, h = termScreen:frame()
  if tab == "craft" and not canCraftAny() then tab = "stored" end
  local list, stored, craft = matches()
  put(t, 1, 1, (" "):rep(w), "white", "gray")
  put(t, 2, 1, "Storage", "yellow", "gray")
  local _, _, stat = store.space()
  put(t, w - #stat, 1, stat, "lightGray", "gray")

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
  local other = canCraftAny() and (tab == "craft" and "  Tab: stored" or "  Tab: craftable") or ""
  put(t, 1, h, fitText((tab == "craft" and "Enter: craft a stack  Right: craft one" or "Enter: a stack  Right: one")
    .. other, w), "gray")
  t.setCursorPos(9 + #query, 3)
  t.setTextColor(colors.white)
  t.setCursorBlink(true)
  termScreen:show()
end

local function drawMonitor()
  -- cheap while the monitor is still there; picks one up (and scales it once) when it's attached
  monScreen:refresh()
  if not monScreen.target then return end
  local w, h = monScreen:size()
  local list = totals()
  local used, total, text = store.space()
  -- the uiLoop redraws on every event: only touch the monitor when what it
  -- shows has changed (each change is sent to every player who can see it)
  local sig = { text, used or "", total or "" }
  for i = 1, h - 5 do
    local it = list[i]
    if not it then break end
    sig[#sig + 1] = it.displayName .. "=" .. tostring(it.count) .. (it.craftable and "+" or "")
  end
  if monScreen:same(table.concat(sig, "|")) then return end
  local mon
  mon, w, h = monScreen:frame()
  put(mon, 1, 1, (" "):rep(w), "white", "gray")
  put(mon, 2, 1, "Storage", "yellow", "gray")
  -- how full it is, as a bar (when the store can say)
  if used and total and total > 0 then
    local frac = used / total
    local barW = w - 2
    local filled = math.floor(frac * barW + 0.5)
    local barColour = frac > 0.9 and "red" or frac > 0.7 and "orange" or "green"
    put(mon, 2, 3, (" "):rep(filled), "white", barColour)
    put(mon, 2 + filled, 3, (" "):rep(barW - filled), "white", "gray")
  end
  put(mon, 2, 4, text, "lightGray")
  for i = 1, h - 5 do
    local it = list[i]
    if not it then break end
    local count = it.craftable and (it.count and ("+" .. it.count) or "craft") or tostring(it.count)
    put(mon, 2, 5 + i, fitText(it.displayName, w - #count - 3), it.craftable and "lightBlue" or "white")
    put(mon, w - #count, 5 + i, count, it.craftable and "lightBlue" or "lightGray")
  end
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

local function take(amount)
  local list = matches()
  local it = list[selected]
  if not it then return end
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

local function uiLoop()
  while true do
    redraw()
    local event, a, x, y = os.pullEvent()
    if event == "char" then
      query, selected, scroll = query .. a, 1, 0
    elseif event == "key" then
      if a == keys.tab and canCraftAny() then
        tab, selected, scroll = tab == "craft" and "stored" or "craft", 1, 0
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
      local _, h = term.getSize()
      if y == 2 then
        for name, z in pairs(tabZones) do
          if x >= z[1] and x <= z[2] and tab ~= name then tab, selected, scroll = name, 1, 0 end
        end
      elseif y >= 4 and y <= h - 2 then
        selected = scroll + y - 3
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
--   { type = "stock" }                              -> { re = "stock", counts, input, fuelChest, fuel }  (smelter)
--   { type = "send", to, slot = 1, items = { [name] = n } } -> { re = "send", sent, fuel }  (load a furnace)
--   { type = "send", to, slot = 2, fuel = n, item }  -> the same, with fuel for n more items (only item, if given)
--   { type = "claim", role, items }                 -> a turtle finding its chest (see claimChest)
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

-- Only furnaces are loaded for the smelter, so a stray message can't empty
-- the store into some other chest.
local function isFurnace(name)
  local t = type(name) == "string" and peripheral.isPresent(name) and peripheral.getType(name)
  return t and (t:find("furnace", 1, true) or t:find("smoker", 1, true)) and true or false
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
  if not isInventory(name) then return false end
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

-- The chest is the turtle's: record it (in the setup file too).
local function assign(from, role, chest)
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

local function claimChest(from, msg)
  local role = msg.role == "crafter" and "crafter" or "delivery"
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
  elseif type(msg) == "table" and msg.type == "stock" then
    local counts = countAll()
    answer(from, msg, { re = "stock", counts = counts, input = setup.input, fuelChest = setup.fuel, fuel = fuelValue(counts) })
  elseif type(msg) == "table" and msg.type == "send" then
    local sent, failed = {}, nil
    if not isFurnace(msg.to) then
      failed = ("%s isn't a furnace on my network"):format(tostring(msg.to))
    elseif msg.slot == 2 then
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
    elseif msg.slot == 1 and type(msg.items) == "table" then
      for name, n in pairs(msg.items) do
        if type(name) == "string" and type(n) == "number" and n > 0 then
          local err
          sent[name], err = fetch(name, math.min(64, math.floor(n)), msg.to, 1)
          failed = failed or err
        end
      end
    end
    answer(from, msg, { re = "send", sent = sent, fuel = fuelValue(countAll()), error = failed })
    if failed then message = { "Couldn't load a furnace: " .. failed, "red" } end
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

---------------------------------------------------------------- setup

local function chooseChests()
  local s = {}
  local bridgeName, kind = nil, nil
  if bridges then bridgeName, kind = bridges.find() end
  if bridgeName then
    print(("Found an %s Bridge (%s)."):format(kind, bridgeName))
    print(("Store items in the %s system, instead of in chests"):format(kind))
    write("on the network? [Y/n] ")
    local a = read():lower()
    s.backend = (a == "" or a:sub(1, 1) == "y") and "bridge" or "chests"
  else
    s.backend = "chests"
  end
  local need = s.backend == "bridge" and 2 or 3
  local invs = {}
  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) then invs[#invs + 1] = name end
  end
  table.sort(invs)
  if #invs < need then
    print(("I can only see %d chests. I need at least %d on the"):format(#invs, need))
    print(s.backend == "bridge" and "network: an input and an output."
      or "network: an input, an output, and one or more for storage.")
    print("Put a full-block wired modem against each chest, connect")
    print("them with cable, and right-click each modem so it turns red.")
    return nil
  end
  print("Chests on the network:")
  for i, name in ipairs(invs) do
    local ok, list = pcall(peripheral.call, name, "list")
    local n = 0
    for _ in pairs(ok and list or {}) do n = n + 1 end
    print(("%2d  %s%s"):format(i, name, n > 0 and (" (" .. n .. " stacks)") or ""))
  end
  print("Tip: right-clicking a modem shows its chest's name in chat.")
  local taken = {}
  local function ask(prompt, optional)
    while true do
      write(prompt)
      local text = read()
      if optional and text == "" then return nil end
      local n = tonumber(text)
      if n and invs[n] and not taken[invs[n]] then
        taken[invs[n]] = true
        return invs[n]
      end
      print("Type one of the numbers above" .. (optional and ", or just Enter." or "."))
    end
  end
  s.input = ask("Which is the input chest? ")
  s.output = ask("Which is the output chest? ")
  print("Turtles (village builder, builder, crafter) find their own")
  print("chest on the network when they start: no need to pick those.")
  print("A shared delivery chest is for turtles that can't: leave it")
  print("blank to send their items to the output chest.")
  s.delivery = ask("Which is the shared delivery chest? [none] ", true)
  print("The crafting turtle's chest sits in front of it. Leave blank")
  print("to let the turtle find it.")
  s.crafter = ask("Which is the crafter chest? [none] ", true)
  print("A fuel chest keeps the coal and charcoal for the smelter's")
  print("furnaces and for turtles. Leave blank if there isn't one.")
  s.fuel = ask("Which is the fuel chest? [none] ", true)
  if s.backend == "bridge" then
    print("The bridge can't put items in a chosen slot, so items for")
    print("furnaces and the crafting turtle pass through a transfer")
    print("chest. Leave blank if you use neither.")
    s.transfer = ask("Which is the transfer chest? [none] ", true)
  end
  -- the turtles' own chests stay theirs, unless picked for something else
  local old = loadSetup()
  s.deliveries, s.crafters = {}, {}
  for _, which in ipairs({ "deliveries", "crafters" }) do
    for id, name in pairs(old and old[which] or {}) do
      if not taken[name] then s[which][id] = name end
    end
  end
  if not s.crafter and old and old.crafter and not taken[old.crafter] then s.crafter = old.crafter end
  saveSetup(s)
  print(s.backend == "bridge" and ("Saved. Items are stored in the %s system."):format(kind)
    or "Saved. Every other chest is storage.")
  return s
end

local args = { ... }
if args[1] == "setup" or not loadSetup() then
  setup = chooseChests()
  if not setup then return end
  if args[1] == "setup" then return end
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
setup.deliveries, setup.crafters = setup.deliveries or {}, setup.crafters or {}
for _, list in ipairs({ setup.deliveries, setup.crafters }) do
  for id, name in pairs(list) do
    if not peripheral.isPresent(name) then
      print(("Can't find turtle #%s's chest (%s): it'll find it again when it next asks."):format(tostring(id), name))
      list[id] = nil
    end
  end
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
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, inputLoop, rescanLoop, netReceive, netLoop, sweepLoop, craftLoop,
  tidyLoop, craftViewLoop, outputLoop, report and report.loop or function() while true do sleep(3600) end end)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
