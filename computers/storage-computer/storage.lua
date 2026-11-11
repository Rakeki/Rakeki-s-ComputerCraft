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
-- crafter and smelter work with either. It only keeps items: it knows no
-- recipes. Crafting is the craft overseer's (computers/craft-overseer, the
-- recipe server): it plans from this computer's stock, and has this computer
-- load its crafting turtles' chests ("load", "clear") and, with an ME or RS
-- system, start the system's own crafts from its patterns ("syscraft"). An
-- optional fuel chest holds the coal and charcoal: fuel that comes in is put
-- there first, turtles asking for coal are served from it, and the smelter
-- (computers/factory) fuels its furnaces from it.
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
--   storage test     check deliveries (one item there and back) and the fuel chest
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
local chests = require("chests")
local setupui = require("lib.setupui") -- the setup screen, on the monitor and the terminal
local bridges = fs.exists("bridge.lua") and require("bridge")

local SETUP_FILE = "/.storage_setup"
local DUMP_FILE = "/.storage_dump" -- { chest, at, moved }: a 'storage dump' that's running

local INPUT_EVERY = 2 -- seconds between checks of the input chest
local RESCAN_EVERY = 60 -- seconds between full rescans of the chests (catches items moved by hand)
local TIDY_EVERY = 10 -- seconds between tidies (moving bulk items into storage with stack upgrades)
local DUMP_WAIT = 2 -- seconds between looks at a full dump chest (and for a new dump job)
local MONITOR_SCALE = 0.5 -- text size on the monitor
local MONITOR_AMOUNTS = { 1, 16, 64 } -- the monitor's buttons for how many of the picked item to send
local MONITOR_COLUMN = 26 -- fewest characters per column of items on the monitor (wide monitors get more columns)
local NET_PROTOCOL = "storage" -- rednet protocol turtles ask for items on
local SWEEP_EVERY = 5 -- seconds between clear-outs of the delivery chest
local HOLD = 600 -- seconds items a turtle asked for wait in the delivery chest before going back
-- far-away computers with a work chest host these (enricher and smelter: before they were the factory)
local WORKER_PROTOCOLS = { factory = "factory", enricher = "enricher", smelter = "smelter" }
local STATUS_PROTOCOL = "cc_status" -- lib/report.lua's broadcasts: the services' states for the monitor
-- report roles shown on the monitor even before they've asked for anything
local SERVICE_ROLES = { factory = true, smelter = true, enricher = true, cooker = true, crafter = true, ["craft overseer"] = true,
  essence = true, crate = true, remote = true, ["digital miners"] = true }
local SERVICE_QUIET = 30 -- seconds without a status before a service shows as offline
local SERVICE_FORGET = 900 -- seconds without a status or a request before it's dropped from the monitor
local SYSCRAFT_EVERY = 10 -- seconds between looks at whether the ME/RS system has finished its crafts
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
-- What the ME/RS system is crafting from its patterns for the craft
-- overseer ("syscraft"): name -> how many, until it's done (the overseer
-- reads them in "stock").
local systemCrafts = {}
-- The monitor's network view: every chest the storage system serves (not
-- its own storage: ender chests, turtles' and computers' chests, input,
-- output, fuel), what's waiting in each and what's been moved into or out
-- of each lately, and the request being answered. Items piling up in one,
-- or requests queueing, show where things are stuck.
local links = {
  WINDOW = 300, -- seconds of moves each chest's row adds up
  EVERY = 10, -- seconds between looks at what's waiting in each chest (only with a monitor)
  ACTIVE = 30, -- seconds after a move that a chest shows as busy
  moves = {}, -- chest -> { { at, name, n, dir = "out" or "in" }, ... }, oldest first
  seen = {}, -- chest -> { used, size, count, top, topN, at } or { missing = true }
  sizes = {}, -- chest -> slots (asked once)
  rows = {}, -- the chests, from the last look: { chest, kind, owner, ender }
  busy = nil, -- the request being answered: { type, from, at }
  slow = nil, -- the slowest lately: { type, from, took, at }
  view = "network", -- what the monitor shows: "network" or "items"
  page = 1,
}

-- Note a move into (dir "out": sent from storage) or out of ("in": put away) a chest.
function links.note(chest, name, n, dir)
  if type(chest) ~= "string" or not n or n <= 0 then return end
  local list = links.moves[chest] or {}
  links.moves[chest] = list
  list[#list + 1] = { at = os.clock(), name = name, n = n, dir = dir }
  local old = os.clock() - links.WINDOW
  while #list > 0 and (list[1].at < old or #list > 60) do table.remove(list, 1) end
end

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

-- Every stored item, most first. Callers only read it. The store and fuel
-- chest each hand back a new table when they change, so the same two tables
-- mean the same list: typing a search doesn't sort everything again on each key.
local totals
do
  local cached, fromStore, fromFuel = nil, nil, nil

  function totals()
    local storeItems = store.items()
    if cached and fromStore == storeItems and fromFuel == fuelList then return cached end
    local list = {}
    for _, it in pairs(allItems()) do list[#list + 1] = it end
    table.sort(list, function(a, b) return a.count > b.count end)
    cached, fromStore, fromFuel = list, storeItems, fuelList
    return list
  end
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
  links.note(from, item.name, count - left, "in")
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
  links.note(to, (key:gsub("#.*", "")), sent, "out")
  return sent, err
end

---------------------------------------------------------------- screens

local query, selected, scroll = "", 1, 0

-- q is lower case already. Each item's lower-case name and id are worked out
-- once (weak keys: they go with the item), not for every item on every key.
local hit
do
  local lowered = setmetatable({}, { __mode = "k" })

  function hit(it, q)
    if q == "" then return true end
    local text = lowered[it]
    if not text then
      text = it.displayName:lower() .. "\n" .. it.key:lower()
      lowered[it] = text
    end
    return text:find(q, 1, true) ~= nil
  end
end

-- The search hits. all: totals(), if the caller has it already.
local function matches(all)
  local q, list = query:lower(), {}
  for _, it in ipairs(all or totals()) do
    if hit(it, q) then list[#list + 1] = it end
  end
  return list
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

local function drawTerminal(all)
  local t, w, h = termScreen:frame()
  local list = matches(all)
  put(t, 1, 1, (" "):rep(w), "white", "gray")
  put(t, 2, 1, "Storage", "yellow", "gray")
  local _, _, stat = store.space()
  -- the setup screen, like the monitor's button (or F1)
  put(t, w - 6, 1, " Setup ", "black", "lightGray")
  if #stat + 18 <= w then put(t, w - #stat - 8, 1, stat, "lightGray", "gray") end

  put(t, 1, 2, (" Stored %d "):format(#list), "black", "white")
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
      local count = countText(it.count)
      put(t, 1, 3 + i, fitText(" " .. it.displayName, w - #count - 1), "white", bg)
      put(t, w - #count, 3 + i, count .. " ", sel and "white" or "lightGray", bg)
    end
  end
  if #list == 0 then
    local empty
    if query ~= "" then empty = "No matches."
    else empty = "Nothing stored yet." end
    put(t, 2, 5, empty, "lightGray")
  end

  put(t, 1, h - 1, fitText(message[1], w), message[2])
  -- while searching, how to clear it matters more than the Tab hint (both don't fit)
  local keysText = "Enter: a stack  Right: one" .. (query ~= "" and "  Del: clear" or "")
  if #keysText + 11 <= w then keysText = keysText .. "  F1: setup" end
  put(t, 1, h, fitText(keysText, w), "gray")
  t.setCursorPos(9 + #query, 3)
  t.setTextColor(colors.white)
  t.setCursorBlink(true)
  termScreen:show()
end

-- The monitor is a touch screen of its own: sort, a search typed on an
-- on-screen keyboard, pages of items, and a bar for the picked item with
-- buttons that send that many to the output chest.
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

-- The programs working with this storage system (smelter, enricher, crafters,
-- ...): every computer that has asked for something, or reports a service's
-- role. Their states come from lib/report.lua's broadcasts, which reach us
-- over the cable or an ender / wireless modem. id -> { role, label, state,
-- detail, heard (os.clock of the last status), asked (of the last request) }
local services = {}

local function noteService(id, status)
  local s = services[id] or { asked = -math.huge, heard = -math.huge }
  services[id] = s
  if status then
    s.role, s.label, s.state, s.detail, s.heard = status.role, status.label, status.state, status.detail, os.clock()
  else
    s.asked = os.clock()
  end
end

-- What the monitor shows: { id, name, state, detail, colour } for each one,
-- by name. Offline: no status for a while (or none at all: no report lib or
-- no modem it can reach us on).
local function serviceList()
  local now, list = os.clock(), {}
  for id, s in pairs(services) do
    local last = math.max(s.heard, s.asked)
    if now - last > SERVICE_FORGET then
      services[id] = nil
    elseif s.asked > -math.huge or SERVICE_ROLES[s.role or ""] then
      local role = s.role and (s.role:sub(1, 1):upper() .. s.role:sub(2)) or "Computer"
      local quiet = now - s.heard > SERVICE_QUIET
      local state = quiet and (s.heard > -math.huge and "offline" or "no status") or s.state or "?"
      local colour = quiet and "gray"
        or (state == "error" or state == "alert") and "red"
        or (state == "waiting" or state == "stuck") and "orange"
        or state == "idle" and "lightGray"
        or "lime"
      list[#list + 1] = { id = id, name = role, label = s.label, state = state, detail = not quiet and s.detail or nil,
        colour = colour }
    end
  end
  table.sort(list, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.id < b.id end)
  -- two of one kind: tell them apart by id
  for i, sv in ipairs(list) do
    if (list[i - 1] and list[i - 1].name == sv.name) or (list[i + 1] and list[i + 1].name == sv.name) then
      sv.short = ("%s %d"):format(sv.name, sv.id)
    end
  end
  return list
end

-- 1234, 12.3k, 4.5M: fits next to a name in a narrow column.
local function shortCount(n)
  if n < 10000 then return tostring(n) end
  if n < 1000000 then return ("%.1fk"):format(n / 1000) end
  return ("%.1fM"):format(n / 1000000)
end

-- Who a chest is for, in a few words: "Builder-16's chest", "ender chest", "input".
local LINK_WORDS = { delivery = "chest", crafter = "crafter chest", work = "work chest", feeder = "feeder",
  dump = "dump", input = "input", output = "output", fuel = "fuel", transfer = "transfer", ender = "ender chest" }
local function linkName(r)
  local s = r.owner and services[r.owner]
  local who = r.owner and (s and (s.label or s.role) or ("#" .. r.owner))
  local what = LINK_WORDS[r.kind] or r.kind
  if r.ender and r.kind ~= "ender" then what = "ender " .. what end
  return who and (who .. " " .. what) or what
end

-- What's been moved lately: "> 128 cobblestone, 64 coal" (sent) and "< 30 raw iron" (put away).
local function flowText(r)
  local out, inn, last = {}, {}, nil
  for _, m in ipairs(links.moves[r.chest] or {}) do
    if os.clock() - m.at <= links.WINDOW then
      local t = m.dir == "out" and out or inn
      t[m.name] = (t[m.name] or 0) + m.n
      last = m.at
    end
  end
  local function words(t, sign)
    local list = {}
    for name, n in pairs(t) do list[#list + 1] = { name, n } end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for i = 1, math.min(3, #list) do parts[i] = shortCount(list[i][2]) .. " " .. shortName(list[i][1]) end
    if #list > 3 then parts[#parts + 1] = ("+%d more"):format(#list - 3) end
    return sign .. " " .. table.concat(parts, ", ")
  end
  local o, i = words(out, ">"), words(inn, "<")
  return (o and i) and (o .. "  " .. i) or o or i or "nothing moved lately", last
end

-- How it's doing: a colour and a word. Red when it's gone or full, orange
-- when things pile up in it, lime while items are moving, grey when idle.
local PILES = { ender = true, delivery = true, crafter = true, work = true, feeder = true, input = true, dump = true }
local function linkState(r, last)
  local seen = links.seen[r.chest]
  if seen and seen.missing then return "red", "gone" end
  if seen and seen.size and seen.size > 0 then
    if seen.used >= seen.size then return "red", "full" end
    if PILES[r.kind] and seen.used / seen.size >= 0.75 then return "orange", "piling" end
  end
  if last and os.clock() - last <= links.ACTIVE then return "lime", "busy" end
  return "lightGray", "idle"
end

local function ago(t)
  if not t then return "" end
  local s = math.floor(os.clock() - t)
  return s < 60 and (s .. "s") or s < 3600 and (math.floor(s / 60) .. "m") or (math.floor(s / 3600) .. "h")
end

-- The network view, between the title and the service tiles (bottom = last row).
function links.draw(text, button, w, h, bottom)
  -- requests: how many wait, what's being answered, the slowest lately
  local waiting = #(links.inbox or {})
  local line = ("Requests: %d waiting"):format(waiting)
  if links.busy then
    line = line .. ("  now %s for #%d, %ds"):format(links.busy.type, links.busy.from, math.floor(os.clock() - links.busy.at))
  end
  if links.slow and links.slow.took >= 1 and os.clock() - links.slow.at <= links.WINDOW then
    line = line .. ("  slowest %s %.1fs"):format(links.slow.type, links.slow.took)
  end
  local busyFor = links.busy and os.clock() - links.busy.at or 0
  text(1, 3, fitText(" " .. line, w), (waiting >= 5 or busyFor >= 5) and "red" or (waiting > 0 or busyFor >= 1) and "orange" or "lightGray")

  local rows = links.rows
  local top = 4
  local space = math.max(0, bottom - top + 1)
  local pages = math.max(1, math.ceil(#rows / math.max(1, space)))
  links.page = math.max(1, math.min(links.page, pages))
  if pages > 1 then
    local pageText = ("%d/%d"):format(links.page, pages)
    local px = w - #pageText - 5
    button(px, 3, " < ", "white", links.page > 1 and "gray" or "black", function() links.page = links.page - 1 end)
    text(px + 3, 3, pageText, "lightGray")
    button(px + 3 + #pageText, 3, " > ", "white", links.page < pages and "gray" or "black", function() links.page = links.page + 1 end)
  end
  text(1, h - 1, fitText(message[1], w), message[2])
  text(1, h, fitText(" Tap a chest to see what's in it and what moved.", w), "gray")
  if #rows == 0 then
    text(2, top, "Looking at the chests...", "lightGray")
    return
  end
  -- columns: who it's for | slots used | what moved lately | how long ago
  local nameW = math.max(10, math.min(26, math.floor(w * 0.4)))
  for i = 1, space do
    local r = rows[(links.page - 1) * space + i]
    if not r then break end
    local y = top + i - 1
    local seen = links.seen[r.chest] or {}
    local flow, last = flowText(r)
    local colour, word = linkState(r, last)
    local slots = seen.missing and "gone" or seen.size and ("%d/%d"):format(seen.used, seen.size) or "?"
    local when = ago(last)
    text(nameW + 1, y, fitText(slots, 7), colour == "lightGray" and "gray" or colour)
    local flowX = nameW + 9
    text(flowX, y, fitText(flow, math.max(0, w - flowX - #when - 1)), last and "white" or "gray")
    if when ~= "" then text(w - #when, y, when, "lightGray") end
    local name = linkName(r)
    button(1, y, fitText(" " .. name, nameW - 1), colour, "black", function()
      local holds = seen.top and (", most of it %d %s"):format(seen.topN, shortName(seen.top)) or ""
      message = { ("%s (%s): %s, %s%s; %s."):format(name, r.chest, word, seen.missing and "gone" or
        ("%d items in %s slots"):format(seen.count or 0, slots), holds, flow), colour == "lightGray" and "white" or colour }
    end)
  end
end

local function drawMonitor(all)
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

  -- the hits, worked out again only when what's stored, the search or the
  -- sort changed: with thousands of items an A-Z sort on every redraw was
  -- most of the screen's work
  local q = mon.query:lower()
  local c = mon.listCache
  if not (c and c.all == all and c.q == q and c.sort == mon.sort) then
    local list = {}
    for _, it in ipairs(all) do
      if hit(it, q) then list[#list + 1] = it end
    end
    if mon.sort == "name" then
      local lower = {}
      for _, it in ipairs(list) do lower[it] = it.displayName:lower() end
      table.sort(list, function(a, b) return lower[a] < lower[b] end)
    end
    c = { all = all, q = q, sort = mon.sort, list = list }
    mon.listCache = c
  end
  local list = c.list
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
  -- network view (where things go) or items view (what's stored)
  local other = links.view == "network" and " Items " or " Network "
  local ox = w - 7 - #other
  button(ox, 1, other, "black", "lightBlue", function()
    links.view, mon.typing, links.page = links.view == "network" and "items" or "network", false, 1
    if links.view == "network" then os.queueEvent("storage_links_now") end
  end)
  if #stat + #other + 19 <= w then text(ox - #stat - 1, 1, stat, "lightGray", "gray") end
  if used and total and total > 0 then
    local frac = math.min(1, used / total)
    local filled = math.floor(frac * w + 0.5)
    local bar = fitText((" %d%% full"):format(math.floor(frac * 100 + 0.5)), w)
    text(1, 2, bar:sub(1, filled), "white", frac > 0.9 and "red" or frac > 0.7 and "orange" or "green")
    text(filled + 1, 2, bar:sub(filled + 1), "white", "gray")
  end

  -- the services (smelter, enricher, ...): a row of tiles over the footer,
  -- coloured by state; tap one to read what it's doing
  local svc = not mon.typing and serviceList() or {}
  if #svc > 0 then
    local x, y = 1, h - 2
    for i, sv in ipairs(svc) do
      local label = " " .. (sv.short or sv.name) .. " "
      local more = #svc - i
      if x + #label - 1 > w - (more > 0 and 4 or 0) then
        text(x, y, fitText(("+%d"):format(more + 1), w - x + 1), "lightGray")
        break
      end
      button(x, y, label, sv.colour == "red" and "white" or "black", sv.colour, function()
        message = { ("%s (#%d%s): %s%s"):format(sv.name, sv.id, sv.label and (", " .. sv.label) or "", sv.state,
          sv.detail and (", " .. sv.detail) or ""), sv.colour == "gray" and "lightGray" or sv.colour }
      end)
      x = x + #label + 1
    end
  end

  if links.view == "network" then
    links.draw(text, button, w, h, #svc > 0 and h - 3 or h - 2)
  else
  -- the item area: columns of rows, filled down then across
  local top, bottom = 4, mon.typing and h - 5 or #svc > 0 and h - 3 or h - 2
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
        local count = shortCount(it.count)
        local on = it.key == mon.pick
        local bg = on and "blue" or "black"
        text(x0, y, fitText(" " .. it.displayName, cw - #count - 1), "white", bg)
        text(x0 + cw - #count - 1, y, count .. " ", on and "white" or "lightGray", bg)
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
    local verb = "Get"
    local name = picked.displayName .. " " .. tostring(picked.count)
    text(1, h, fitText(" " .. name, math.max(0, bx - #verb - 2)), "white")
    if bx - #verb - 1 > 1 then text(bx - #verb - 1, h, verb, "lightGray") end
    for i, label in ipairs(labels) do
      local n = MONITOR_AMOUNTS[i]
      button(bx, h, label, "black", "lime", function() takeItem(picked, n) end)
      bx = bx + #label + 1
    end
    button(bx, h, " x ", "white", "red", function() mon.pick = nil end)
  else
    text(1, h, fitText(" Tap an item to send some to the output chest.", w), "gray")
  end
  end

  mon.zones = zones
  local parts = {}
  for i, op in ipairs(ops) do parts[i] = table.concat(op, ",") end
  if monScreen:same(table.concat(parts, "|")) then return end
  local win = monScreen:frame()
  for _, op in ipairs(ops) do put(win, op[1], op[2], op[3], op[4], op[5]) end
  monScreen:show()
end

-- What's stored is gathered and sorted once a frame, for both screens and
-- the status: with a full store that's most of a redraw's work.
local function redraw()
  local all = totals()
  drawTerminal(all)
  drawMonitor(all)
  if report then
    local items = 0
    for _, it in ipairs(all) do items = items + it.count end
    local _, _, text = store.space()
    report.set(store.problem and "error" or "running", store.problem or ("%d items; %s"):format(items, text))
  end
end

---------------------------------------------------------------- loops

local editSetup -- in the setup section below

-- Send amount of an item from the list to the output chest (from the
-- terminal or a monitor button). Queued for the screen loop's sender: each
-- pull takes a game tick (more while the other loops are moving items), and
-- the screens froze until it was done.
mon.takes = {}
function takeItem(it, amount)
  mon.takes[#mon.takes + 1] = { it = it, amount = amount }
  message = { ("Sending %d %s..."):format(amount, it.displayName), "lightGray" }
  os.queueEvent("storage_take")
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

-- The main chunk is close to Lua's limit of 200 locals, so the screen loop's
-- settings live in this block instead of at the top of the file.
local uiLoop
do
  local REDRAW_EVERY = 5 -- seconds between redraws when nothing happens (services going quiet)
  local REDRAW_GAP = 0.2 -- seconds a change waits to be drawn, so a burst of changes draws once
  local CHANGE_EVERY = 1 -- fewest seconds between redraws for changes (busy turtles change it all the time); input draws at once
  -- Typing, clicks and taps: drawn straight away.
  local INPUT_EVENTS = { char = true, key = true, paste = true, mouse_click = true, mouse_scroll = true,
    monitor_touch = true, term_resize = true, monitor_resize = true }
  -- What changes the screens without the player: drawn REDRAW_GAP later, so a
  -- burst of them draws once. Everything else (rednet messages, the other
  -- loops' timers) leaves the screens alone: redrawing on every event kept the
  -- computer busy sorting the item list.
  local CHANGE_EVENTS = { storage_changed = true, storage_links = true, peripheral = true, peripheral_detach = true }

  -- The Get buttons' and Enter's moves, one after another, beside the screens.
  local function takeLoop()
    while true do
      while #mon.takes == 0 do os.pullEvent("storage_take") end
      local job = table.remove(mon.takes, 1)
      local sent = fetch(job.it.key, job.amount, setup.output)
      if sent > 0 then
        message = { ("Sent %d %s to the output chest."):format(sent, job.it.displayName), "lime" }
      else
        message = { "Couldn't send it: is the output chest full?", "red" }
      end
      os.queueEvent("storage_changed")
    end
  end

  local function screenLoop()
    -- queued: a "storage_redraw" is waiting behind the key presses already
    -- queued, so a burst of typing (a key and a char event each) draws once
    local soon, beat, draw, queued = nil, os.startTimer(REDRAW_EVERY), true, false
    local drawnAt = -math.huge
    while true do
      if draw then
        draw = false
        redraw()
        drawnAt = os.clock()
      end
      if mon.setup then
        mon.setup = false
        setupScreen()
        redraw()
      end
      local ev = { os.pullEvent() }
      if ev[1] == "timer" then
        if ev[2] == soon then
          soon, draw = nil, true
        elseif ev[2] == beat then
          beat, draw = os.startTimer(REDRAW_EVERY), true
        end
      elseif CHANGE_EVENTS[ev[1]] then
        soon = soon or os.startTimer(math.max(REDRAW_GAP, drawnAt + CHANGE_EVERY - os.clock()))
      elseif INPUT_EVENTS[ev[1]] then
        if not queued then
          os.queueEvent("storage_redraw")
          queued = true
        end
      elseif ev[1] == "storage_redraw" then
        queued, draw = false, true
      end
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
        elseif y >= 4 and y <= h - 2 then
          -- clicking the picked row again takes a stack, like Enter
          if selected == scroll + y - 3 then take(64) else selected = scroll + y - 3 end
        end
      end
    end
  end

  function uiLoop() parallel.waitForAny(screenLoop, takeLoop) end
end

local function inputLoop()
  while true do
    if storeInput() then os.queueEvent("storage_changed") end
    sleep(INPUT_EVERY)
  end
end

---------------------------------------------------------------- crafter chests

-- The craft overseer (computers/craft-overseer) plans and runs every craft.
-- What it needs from here is items: its turtles' chests loaded and emptied,
-- and with an ME or RS system the system's own crafts started.

local function nameOf(item)
  local it = allItems()[item]
  return it and it.displayName or shortName(item)
end

-- Once the ME/RS system stops crafting something, what it made is stored
-- and counted like anything else.
local function checkSystemCrafts()
  for name, n in pairs(systemCrafts) do
    if not store.isCrafting(name) then
      systemCrafts[name] = nil
      message = { ("The %s system is done crafting %d %s."):format(store.kind, n, nameOf(name)), "lime" }
      os.queueEvent("storage_changed")
    end
  end
end

local function sysCraftLoop()
  while true do
    sleep(SYSCRAFT_EVERY)
    if next(systemCrafts) then checkSystemCrafts() end
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

-- Requests from turtles over rednet:
--   { type = "count", items = { name, ... } }      -> { re = "count", counts = { [name] = n } }
--   { type = "deliver", items = { [name] = n } }   -> { re = "deliver", sent = { [name] = n }, ready, stock }
--                                                     (optional most = { [name] = n }: move no more than that now)
--   { type = "stock" }                              -> { re = "stock", counts, input, fuelChest, fuel, patterns,
--                                                     syscrafting }  (smelter, cooker, the craft overseer)
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
-- From the craft overseer, which plans and runs every craft:
--   { type = "crafters" }                           -> { re, crafters = { [turtle id] = chest }, shared }
--   { type = "load", crafter, grid, steps }         -> { re, steps (0: not loaded), error, missing = { [item] = n } }
--   { type = "clear", crafter }                     -> { re, ok }  (put its chest's contents away)
--   { type = "syscraft", item, count }              -> { re, ok, error }  (the ME/RS system crafts it from a pattern)
--   { type = "deliver", items, for = computer id }  -> as above, into that computer's chest (a craft terminal's order)
-- deliver sends to the turtle's own chest if it has claimed one ("own"),
-- else the shared delivery chest, else the output chest (reply field to).
-- Requests may carry an id, which the reply repeats. Nothing here knows
-- recipes: what isn't stored, ask the craft overseer for (lib/crafts.lua).
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
-- and that chest becomes its delivery chest, or the crafter chest. A craft
-- overseer far away claims the twin of its ender chest the same way, role
-- "hub": it's kept as that overseer's crafter chest, and the overseer
-- passes each batch on to its turtles' barrels.
--   { type = "claim", role = "delivery", "crafter" or "hub", items = its list() }
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

-- Markers other turtles' searches are using right now. Two searches at
-- once must never use the same item: the probe for one could land in the
-- other's chest (an ender chest's twin), and that turtle would take the
-- chest being tried for the first as its own. It did: every search picked
-- the same first item, and a cannon feeder got another's ender chest.
local CLAIM_IDLE = 60 -- seconds a search may go quiet before its marker is free again
local function markersInUse(from)
  local used = {}
  for id, other in pairs(claims) do
    if id ~= from and other.marker and os.clock() - (other.last or 0) < CLAIM_IDLE then used[other.marker] = true end
  end
  return used
end

-- Put one item in the next chest to try. The item is one that chest
-- doesn't already hold, and no other search is using, so the turtle can
-- tell it arrived.
local function nextProbe(from, c)
  local items = allItems()
  local used = markersInUse(from)
  c.last = os.clock()
  while c.i < #c.candidates do
    c.i = c.i + 1
    local name = c.candidates[c.i]
    local ok, list = pcall(peripheral.call, name, "list")
    if ok then
      local has = {}
      for _, item in pairs(list) do has[item.name] = true end
      local marker = c.marker and not has[c.marker] and not used[c.marker] and items[c.marker] and c.marker
      if not marker then
        for key, it in pairs(items) do
          if not it.nbt and it.count > 0 and not has[key] and not used[key] then marker = key break end
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
  local s = loadSetup() or setup
  s.deliveries, s.crafters = s.deliveries or {}, s.crafters or {}
  if role == "delivery" then
    -- A crafting turtle has it, yet the probe just turned up in this turtle's
    -- chest: the crafter's claim is the wrong one (an ender chest whose twin
    -- is here, taken back when two searches shared a probe item; two empty
    -- chests look alike, so the crafter kept confirming it). This turtle gets
    -- it, and the crafter finds its real chest on its next claim.
    for _, t in ipairs({ setup, s }) do
      for id, name in pairs(t.crafters) do
        if name == chest then
          t.crafters[id] = nil
          if t == setup and report then report.log(("crafter #%d lost %s to turtle #%d"):format(id, chest, from)) end
        end
      end
      if t.crafter == chest then t.crafter = nil end
    end
  end
  -- the chest it had before (a wrong one, say: items waited there that never
  -- reached it): what's in it goes home, or it would sit there for good
  local before = (role == "crafter" or role == "hub") and setup.crafters[from] or setup.deliveries[from]
  local othersToo = false -- it may be another turtle's real chest: then it stays as it is
  for id, name in pairs(setup.deliveries) do
    if name == before and id ~= from then othersToo = true end
  end
  for id, name in pairs(setup.crafters) do
    if name == before and id ~= from then othersToo = true end
  end
  if before and before ~= chest and not othersToo then
    local okB, listB = pcall(peripheral.call, before, "list")
    for slot, item in pairs(okB and listB or {}) do putAway(before, slot, item, item.count) end
    reserved[before] = nil
  end
  for _, t in ipairs({ setup, s }) do
    if role == "crafter" or role == "hub" then
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
  store.scan() -- it may have been storage until now
  message = { role == "hub" and ("Craft overseer #%d's ender chest is %s."):format(from, chest)
    or ("Turtle #%d's %s chest is %s."):format(from, role, chest), "lime" }
  if report then report.log(("turtle #%d uses %s"):format(from, chest)) end
  os.queueEvent("storage_changed")
  return { re = "claim", ok = true, chest = chest }
end

local function claimChest(from, msg, role)
  role = role or ((msg.role == "crafter" or msg.role == "hub") and msg.role or "delivery")
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
  local mine = (role == "crafter" or role == "hub") and setup.crafters[from] or role == "delivery" and setup.deliveries[from]
    or role == "work" and setup.works[from]
  if mine then
    local ok, list = pcall(peripheral.call, mine, "list")
    if ok and sameItems(list, msg.items) then
      claims[from] = nil
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
links.inbox = inbox -- for the monitor: how many requests are waiting
-- Questions answered from the cache, with no items moved: they go in their
-- own inbox and quickLoop answers them beside netLoop, so a count or the
-- craft overseer's stock check never waits behind chest loads and deliveries
-- (with several crafting turtles loading, that held every crafting answer up
-- for seconds).
local QUICK = { count = true, stock = true, crafters = true }
local quick = {}

local function netReceive()
  -- turtles reach us by wireless; the smelter can by the wired network's cable
  net.open("any")
  if not net.hasWireless() then
    message = { "No wireless modem: turtles can't ask me for items.", "orange" }
    os.queueEvent("storage_changed")
  end
  rednet.host(NET_PROTOCOL, os.getComputerLabel() or ("storage-" .. os.getComputerID()))
  while true do
    -- requests, and the services' status broadcasts for the monitor
    local from, msg, protocol = rednet.receive()
    if type(msg) == "table" and protocol == NET_PROTOCOL and QUICK[msg.type] then
      quick[#quick + 1] = { from = from, msg = msg }
      noteService(from)
      os.queueEvent("storage_quick")
    elseif type(msg) == "table" and protocol == NET_PROTOCOL then
      inbox[#inbox + 1] = { from = from, msg = msg }
      noteService(from)
      os.queueEvent("storage_inbox")
    elseif type(msg) == "table" and protocol == STATUS_PROTOCOL and msg.type == "status" then
      local before = services[from] and services[from].state
      noteService(from, msg)
      if before ~= msg.state then os.queueEvent("storage_changed") end
    end
  end
end

-- Replies carry the request's id, so a turtle never takes a late answer to
-- an earlier request for the answer to a new one.
local function answer(to, request, reply) net.answer(to, NET_PROTOCOL, request, reply) end

local function handleRequest(from, msg)
  if type(msg) == "table" and msg.type == "count" and type(msg.items) == "table" then
    answer(from, msg, { re = "count", counts = countPlain(msg.items) })
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
  elseif type(msg) == "table" and msg.type == "stock" then
    local counts = countAll()
    local okP, patterns = false, nil
    if store.craftables then okP, patterns = pcall(store.craftables) end
    answer(from, msg, { re = "stock", counts = counts, input = setup.input, fuelChest = setup.fuel, fuel = fuelValue(counts),
      work = setup.works[from], workRemote = setup.works[from] ~= nil and isEnder(setup.works[from]) or nil,
      patterns = okP and patterns or nil, syscrafting = systemCrafts })
  elseif type(msg) == "table" and msg.type == "syscraft" and type(msg.item) == "string" then
    -- the craft overseer: the ME/RS system crafts it from its own pattern
    local n = math.max(1, math.floor(tonumber(msg.count) or 1))
    local okC, err = false, ("this is a %s store: it has no patterns"):format(store.kind)
    if store.craft then okC, err = store.craft(msg.item, n) end
    if okC then
      systemCrafts[msg.item] = (systemCrafts[msg.item] or 0) + n
      message = { ("The %s system is crafting %d %s."):format(store.kind, n, nameOf(msg.item)), "lightBlue" }
    end
    answer(from, msg, { re = "syscraft", ok = okC and true or false, error = not okC and tostring(err) or nil })
    os.queueEvent("storage_changed")
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
    local forId = tonumber(msg["for"])
    local own = setup.deliveries[forId or from]
    -- for another computer (a craft terminal's order, from the overseer): only ever into its own chest
    if forId and not own then
      answer(from, msg, { re = "deliver", sent = {}, ready = {}, stock = {}, error = ("computer #%d has no chest here"):format(forId) })
      return
    end
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
        -- most: never move more than this many now, whatever the chest holds
        -- (the cannon feeder: the cannon empties its chest while we work)
        local want = n - have
        local cap = type(msg.most) == "table" and tonumber(msg.most[name])
        if cap then want = math.min(want, math.max(0, math.floor(cap))) end
        if want > 0 then
          local err
          sent[name], err = fetch(name, want, to)
          -- stored, yet none moved and no error: say so, or the turtle waits without a reason
          if not err and sent[name] == 0 and (countPlain({ name })[name] or 0) > 0 then
            err = ("%s took none of the %s asked for: is it full?"):format(to, nameOf(name))
          end
          failed = failed or err
        end
        ready[name] = have + sent[name]
        if ready[name] < n then short = true end
        total = total + sent[name]
        names[#names + 1] = name
        if held then held[name] = { n = ready[name], at = os.clock() } end
      end
    end
    answer(from, msg, { re = "deliver", sent = sent, ready = ready, stock = countPlain(names), error = failed,
      to = own and "own" or setup.delivery and "delivery" or "output" })
    if failed then
      message = { "Couldn't move items for a turtle: " .. failed, "red" }
    elseif total > 0 and to == setup.output then
      message = { ("Sent %d items to the output chest for turtle #%d: it has no chest here."):format(total, from), "orange" }
    elseif total > 0 then
      message = { ("Sent %d items to turtle #%d."):format(total, from), "lightBlue" }
    elseif short and not forId then
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
    local kind = type(req.msg) == "table" and tostring(req.msg.type) or "?"
    links.busy = { type = kind, from = req.from, at = os.clock() }
    handleRequest(req.from, req.msg)
    -- the slowest request in the last few minutes: where the queue comes from
    local took = os.clock() - links.busy.at
    if not links.slow or took >= links.slow.took or os.clock() - links.slow.at > links.WINDOW then
      links.slow = { type = kind, from = req.from, took = took, at = os.clock() }
    end
    links.busy = nil
  end
end

-- The quick questions (QUICK), answered while netLoop is busy moving items.
local function quickLoop()
  while true do
    while #quick == 0 do os.pullEvent("storage_quick") end
    local req = table.remove(quick, 1)
    handleRequest(req.from, req.msg)
  end
end

---------------------------------------------------------------- the network view

-- Every chest the storage system serves, ender chests first: { chest, kind, owner (computer id) }.
local LINK_ORDER = { ender = 1, delivery = 2, crafter = 3, work = 4, feeder = 5, dump = 6, input = 7, output = 8,
  fuel = 9, transfer = 10 }
function links.list()
  local out, have = {}, {}
  local function add(chest, kind, owner)
    if type(chest) ~= "string" or have[chest] then return end
    have[chest] = true
    local ok, ender = pcall(isEnder, chest)
    out[#out + 1] = { chest = chest, kind = kind, owner = owner, ender = ok and ender or false }
  end
  for id, c in pairs(setup.deliveries or {}) do add(c, "delivery", id) end
  for id, c in pairs(setup.crafters or {}) do add(c, "crafter", id) end
  for id, c in pairs(setup.works or {}) do add(c, "work", id) end
  for id, list in pairs(setup.feeders or {}) do
    for _, c in ipairs(type(list) == "table" and list or {}) do add(c, "feeder", id) end
  end
  local dump = files.read(DUMP_FILE)
  if type(dump) == "table" then add(dump.chest, "dump") end
  for _, c in ipairs(inputChests()) do add(c, "input") end
  add(setup.output, "output")
  add(setup.delivery, "delivery")
  add(setup.crafter, "crafter")
  add(setup.fuel, "fuel")
  add(setup.transfer, "transfer")
  -- any other ender chest on the cable: shared with a chest somewhere else
  for _, name in ipairs(peripheral.getNames()) do
    local ok, ender = pcall(isEnder, name)
    if ok and ender and isInventory(name) then add(name, "ender") end
  end
  table.sort(out, function(a, b)
    local ra, rb = a.ender and 0 or LINK_ORDER[a.kind] or 99, b.ender and 0 or LINK_ORDER[b.kind] or 99
    if ra ~= rb then return ra < rb end
    return a.chest < b.chest
  end)
  return out
end

-- Look in every one at once (a game tick each), for the monitor.
function links.scan()
  local rows, jobs = links.list(), {}
  for _, r in ipairs(rows) do
    jobs[#jobs + 1] = function()
      local okL, list = pcall(peripheral.call, r.chest, "list")
      if not okL then
        links.seen[r.chest] = { missing = true, at = os.clock() }
        return
      end
      if not links.sizes[r.chest] then
        local okS, size = pcall(peripheral.call, r.chest, "size")
        links.sizes[r.chest] = okS and size or 0
      end
      local used, count, by = 0, 0, {}
      for _, it in pairs(list) do
        used, count = used + 1, count + it.count
        by[it.name] = (by[it.name] or 0) + it.count
      end
      local top, topN = nil, 0
      for name, n in pairs(by) do
        if n > topN then top, topN = name, n end
      end
      links.seen[r.chest] = { used = used, size = links.sizes[r.chest], count = count, top = top, topN = topN, at = os.clock() }
    end
  end
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
  links.rows = rows
  os.queueEvent("storage_links")
end

local function linksLoop()
  while true do
    -- only worth the reads while a monitor shows it
    -- (a turtle driving past fires peripheral events too: at most one look every 2 s)
    if monScreen.target and links.view == "network" and setup and os.clock() - (links.at or -math.huge) >= 2 then
      links.at = os.clock()
      links.scan()
    end
    -- again in a while, or at once when the monitor switches to this view or comes back
    local timer = os.startTimer(links.EVERY)
    repeat
      local event, value = os.pullEvent()
    until (event == "timer" and value == timer) or event == "storage_links_now" or event == "peripheral"
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
  { key = "remote", what = "far-away factory computer's ender chest" },
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
  print("Looking for factory computers...")
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
  { key = "remote", what = "Far-away workers", hint = "Factory computers at another base, through an ender chest." },
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
    ui:say("Looking for factory computers...", "lightBlue")
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
  -- its own function, so its locals don't count towards the main chunk's 200
  (function()
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
      print(store.canCraft and store.canCraft(pick.name) and ("The %s system can craft %s."):format(store.kind, pick.displayName)
        or ("The %s system has no pattern for %s (fine: it's just a test item)."):format(store.kind, pick.displayName))
    end
    print(setup.fuel and ("Fuel chest: %s. Fuel stored for %d items."):format(setup.fuel, fuelValue(countAll()))
      or "No fuel chest: fuel is kept with everything else.")
    local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
    print(modem and ("Wireless modem on %s: turtles can ask me for items."):format(peripheral.getName(modem))
      or "No wireless modem: turtles can't ask me for items.")
    -- crafting is the craft overseer's: just say whether there is one, and the turtles' chests
    net.open("any")
    local overseer = rednet.lookup("craft_overseer")
    print(overseer and ("Craft overseer #%d plans and runs the crafting."):format(overseer)
      or "No craft overseer answered: nothing gets crafted (computers/craft-overseer).")
    for id, chest in pairs(setup.crafters) do print(("Crafting turtle #%s's chest: %s."):format(tostring(id), chest)) end
    if setup.crafter then print(("Shared crafter chest: %s."):format(setup.crafter)) end
  end)()
  return
end

term.clear()
if missingChest then message = { missingChest, "orange" } end
if fs.exists("pack_recipes.lua") then
  message = { "pack_recipes.lua does nothing here now: move it to the craft overseer.", "orange" }
end
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

local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, inputLoop, rescanLoop, netReceive, netLoop, quickLoop, sweepLoop, linksLoop, function() net.keepOpen("any") end,
  tidyLoop, sysCraftLoop, dumpLoop, setupLoop, report and report.loop or function() while true do sleep(3600) end end)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
