-- Feeds a Create Schematicannon from the storage system. The cannon takes
-- its blocks (and gunpowder) from any chest touching it; this computer keeps
-- that chest topped up through the storage computer. Anything storage
-- hasn't got but can make is crafted on the way (the storage computer's
-- 'deliver' does that).
--
-- What to send comes from two places, either or both:
--   - An Advanced Peripherals Block Reader against the cannon: CC can't ask
--     the cannon anything, but its block data names the item it's waiting
--     for. That item is sent at once and remembered, so it's kept topped up
--     from then on, until the cannon says it's finished.
--   - A list typed in (or a plan's blocks), each sent until the whole amount
--     has gone: the cannon has it before it asks.
-- A monitor, or this computer's screen, shows the cannon's progress and each
-- item: in the chest, being crafted, or why it can't be had.
--
--   cannon                    start feeding (startup.lua runs this)
--   cannon add <item> <n>     add n of an item to the list ("stone_bricks" or "create:andesite_casing")
--   cannon remove <item>      take an item off the list
--   cannon plan <name>        add every block a building plan from /plans uses
--   cannon list               the list, and how much of each has been sent
--   cannon again              send everything again (same list, sent counts back to 0)
--   cannon clear              forget the list (and the items learnt from the cannon)
--   cannon chest [name]       pick the chest by the cannon (no name: from a list)
--
-- Needs a modem that reaches the storage computer (wired on its cable, or
-- wireless / ender), and a chest touching both this computer and the
-- cannon that's on the storage cable (a full-block wired modem on it), or
-- an ender chest whose twin is. The storage computer finds that chest
-- itself, the way turtles find theirs (lib/claim.lua). The Block Reader
-- touches the cannon, and this computer or its wired network.
local screen = require("lib.screen") -- flicker-free drawing on the monitor and terminal
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local claim = require("lib.claim") -- tells the storage computer which chest is ours
local plan = fs.exists("lib/plan.lua") and require("lib.plan") -- only for 'cannon plan'
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local JOB_FILE = "/.cannon_job" -- { items = { { name, need, sent, auto } }, chest }
local FEED_EVERY = 5 -- seconds between top-ups
local REPLY_WAIT = 10 -- seconds to wait for the storage computer to answer
local CLAIM_RETRY = 60 -- seconds before trying again to hook a chest up that the storage computer didn't take
local MAX_STACKS = 2 -- most stacks of one item kept in the chest at once
local STACK = 64 -- items in a stack (most blocks)
local GUNPOWDER = "minecraft:gunpowder" -- the cannon's fuel, also taken from the chest
local GUNPOWDER_KEEP = 32 -- gunpowder kept in the chest while feeding ('set cannon.gunpowder 0' for none)
local READER_TYPES = { "block_reader", "blockReader" } -- Advanced Peripherals' Block Reader (new name, old name)
local MONITOR_SCALES = { 1, 0.5 } -- text sizes to try on the monitor, largest first
local SIDES = { "top", "bottom", "left", "right", "front", "back" }
-- blocks whose item has another name (a plan lists blocks, the cannon takes items)
local AS_ITEM = { wall_torch = "torch", soul_wall_torch = "soul_torch", redstone_wall_torch = "redstone_torch",
  redstone_wire = "redstone", tripwire = "string" }
local NOT_ITEMS = { air = true, cave_air = true, void_air = true, water = true, lava = true, fire = true }

-- items: { name, need, sent }, in the order they were added; auto = true for
-- one the cannon asked for (no need: kept topped up while the cannon works)
local job = { items = {} }
local state = {} -- item name -> { inChest, stock, crafting, why }, from the last top-up
local cannon -- what the Block Reader last read: { state, status, placed, total, missing, fuel }, nil without one
local message = { "Starting...", "lightGray" }
local chest -- the chest by the cannon, nil if there's none

---------------------------------------------------------------- helpers

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("cannon_changed")
end

local function status(st, detail)
  if report then report.set(st, detail) end
end

local function save() files.write(JOB_FILE, job) end

local function load()
  local saved = files.read(JOB_FILE)
  if type(saved) == "table" and type(saved.items) == "table" then job = saved end
end

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function itemName(text)
  text = text:lower()
  if not text:find(":", 1, true) then text = "minecraft:" .. text end
  return text
end

local function find(name)
  for i, it in ipairs(job.items) do
    if it.name == name then return it, i end
  end
end

local function isInventory(name)
  local ok, yes = pcall(peripheral.hasType, name, "inventory")
  return ok and yes
end

-- Chests and barrels touching this computer.
local function nearChests()
  local list = {}
  for _, side in ipairs(SIDES) do
    if peripheral.isPresent(side) and isInventory(side) then list[#list + 1] = side end
  end
  return list
end

-- The one picked with 'cannon chest', else the only one touching me.
local function findChest()
  if job.chest and peripheral.isPresent(job.chest) then return job.chest end
  local list = nearChests()
  if #list == 1 then return list[1] end
  return nil, #list == 0 and "no chest next to me: put the one by the cannon there"
    or "more than one chest next to me: pick one with 'cannon chest'"
end

-- What's in the chest: item name -> count (plain items only), and its size.
local function contents()
  local ok, list = pcall(peripheral.call, chest, "list")
  local okS, size = pcall(peripheral.call, chest, "size")
  local have = {}
  for _, s in pairs(ok and list or {}) do
    if not s.nbt then have[s.name] = (have[s.name] or 0) + s.count end
  end
  return have, okS and size or 27
end

-- How many more of an item to send: the rest of its amount, or for one the
-- cannon asked for, as much as there's room for while the cannon works.
local function remaining(it, working)
  if it.auto then return working and math.huge or 0 end
  return it.need - it.sent
end

---------------------------------------------------------------- the cannon

-- A Block Reader facing the cannon ('set cannon.reader <name>' picks one).
local function findReader()
  local named = settings.get("cannon.reader")
  if named then return peripheral.isPresent(named) and named or nil end
  for _, name in ipairs(peripheral.getNames()) do
    for _, t in ipairs(READER_TYPES) do
      if peripheral.hasType(name, t) then
        local ok, block = pcall(peripheral.call, name, "getBlockName")
        if ok and type(block) == "string" and block:find("schematicannon", 1, true) then return name end
      end
    end
  end
end

-- An item stack from the block data ({ id, count } on 1.21, { id, Count } before).
local function stackName(stack)
  if type(stack) ~= "table" then return nil end
  local id = stack.id or stack.Id or stack.item
  if type(id) == "string" and id ~= "minecraft:air" then return id end
end

-- What the cannon is up to, from its block data (the same as its screen:
-- State is RUNNING / PAUSED / STOPPED, Status the message key).
local function readCannon()
  local reader = findReader()
  if not reader then return nil end
  local ok, data = pcall(peripheral.call, reader, "getBlockData")
  if not ok or type(data) ~= "table" then return nil end
  return {
    state = data.State, status = data.Status, missing = stackName(data.MissingItem),
    placed = tonumber(data.AmountPlaced), total = tonumber(data.AmountToPlace), fuel = tonumber(data.RemainingFuel),
  }
end

-- The cannon has a schematic and is placing it (or waiting for something).
local function working() return cannon ~= nil and (cannon.state == "RUNNING" or cannon.state == "PAUSED") end

-- The cannon's status as a line for the screen.
local function cannonText()
  if not cannon then return nil end
  local s = cannon.status
  if s == "missingBlock" and cannon.missing then return "waiting for " .. nice(cannon.missing), "orange" end
  if s == "noGunpowder" then return "out of gunpowder", "orange" end
  if s == "finished" then return "finished", "lime" end
  if cannon.state == "RUNNING" then return "placing", "lightBlue" end
  if cannon.state == "PAUSED" then return "paused", "yellow" end
  return "stopped", "gray"
end

-- Take in what the cannon says: the item it's waiting for joins the list
-- (it's sent this round); once it's finished, the items it asked for leave
-- it again, so what's left in the chest goes home.
local function followCannon()
  cannon = readCannon()
  if not cannon then return end
  local changed = false
  if cannon.missing and cannon.missing ~= GUNPOWDER and not find(cannon.missing) then
    job.items[#job.items + 1] = { name = cannon.missing, need = 0, sent = 0, auto = true }
    changed = true
  end
  if cannon.status == "finished" then
    for i = #job.items, 1, -1 do
      if job.items[i].auto then
        table.remove(job.items, i)
        changed = true
      end
    end
  end
  if changed then save() end
end

---------------------------------------------------------------- feeding

local storage = net.peer(STORAGE_PROTOCOL, { open = "any", retry = 30, wait = REPLY_WAIT })

local function ask(msg)
  local reply, why = storage:ask(msg)
  if reply then return reply end
  if why == "no modem" then return nil, "no modem on me" end
  return nil, why == "no answer" and "the storage computer didn't answer"
    or "no storage computer answered: is it running 'storage'?"
end

local supply = claim.tracker("delivery", CLAIM_RETRY)

-- What to ask for this round: item -> how many the chest should hold. Each
-- item gets a fair share of the chest (up to MAX_STACKS stacks) but never
-- more than is still to be sent; items already in the chest are asked for
-- too, so the storage computer leaves them there. The item the cannon is
-- waiting for goes first. Returns the targets and how many kinds had to
-- wait for room.
local function targets(have, size)
  local want, waiting = {}, 0
  local keep = tonumber(settings.get("cannon.gunpowder")) or GUNPOWDER_KEEP
  local busy = working()
  local active, more = {}, false
  local first = cannon and cannon.missing
  for _, it in ipairs(job.items) do
    local left = remaining(it, busy)
    if left > 0 then more = true end
    if left > 0 or (have[it.name] or 0) > 0 then
      if it.name == first then table.insert(active, 1, it) else active[#active + 1] = it end
    end
  end
  -- gunpowder only while there's more to send (or the cannon runs out): once
  -- it's all sent, what's left goes home
  local outOfPowder = cannon and cannon.status == "noGunpowder"
  if not (more or outOfPowder) or find(GUNPOWDER) then keep = 0 end
  local slots = size - math.ceil(keep / STACK)
  -- in list order, as many kinds as there are slots: the rest wait their turn
  if #active > slots then
    waiting = #active - slots
    for i = #active, slots + 1, -1 do active[i] = nil end
  end
  local per = math.max(1, math.min(MAX_STACKS, math.floor(slots / math.max(1, #active)))) * STACK
  for _, it in ipairs(active) do
    local inside = have[it.name] or 0
    want[it.name] = math.min(math.max(per, inside), inside + remaining(it, busy))
  end
  if keep > 0 and not want[GUNPOWDER] then want[GUNPOWDER] = keep end
  return want, waiting
end

-- One top-up: see what the cannon wants, hook the chest up if need be, ask
-- for this round's items, and count what was sent.
local function feed()
  followCannon()
  local why
  chest, why = findChest()
  if not chest then
    say("No chest yet: " .. why .. ".", "orange")
    status("waiting", "no chest")
    return
  end
  if #job.items == 0 then
    if cannon then
      say(cannon.status == "finished" and "The cannon has finished." or "Waiting for the cannon to ask for something.",
        cannon.status == "finished" and "lime" or "lightGray")
    else
      say("Nothing to send: 'cannon add <item> <n>', or a Block Reader on the cannon.", "lightGray")
    end
    status("idle", cannon and cannon.status == "finished" and "cannon finished" or "nothing to send")
    return
  end
  if supply:due() then
    local ok, err = supply:check(ask, chest)
    if ok == false then
      say(("The storage computer can't find my chest: %s."):format(err), "red")
      status("waiting", "chest not on the storage cable")
      return
    elseif not ok then
      say("Storage: " .. tostring(err or "no storage computer answered"), "orange")
      status("waiting", "no storage computer")
      return
    end
  end
  if not supply.done then return end
  local have, size = contents()
  local want, waiting = targets(have, size)
  local r, whyNot = ask({ type = "deliver", items = want })
  if not r then
    say("Storage: " .. whyNot, "orange")
    status("waiting", "no storage computer")
    return
  end
  supply:seen(r)
  if r.to ~= "own" then
    say("The storage computer sent it somewhere else: hooking my chest up again.", "orange")
    return
  end
  local sent, total = type(r.sent) == "table" and r.sent or {}, 0
  for _, it in ipairs(job.items) do
    local n = sent[it.name] or 0
    it.sent, total = it.sent + n, total + n
  end
  if total > 0 then save() end
  -- what each item is up to, for the screen
  have = contents()
  local crafting, cant, stock = r.crafting or {}, r.cantCraft or {}, r.stock or {}
  local left, short = 0, 0
  local busy = working()
  for _, it in ipairs(job.items) do
    state[it.name] = { inChest = have[it.name] or 0, stock = stock[it.name], crafting = crafting[it.name],
      why = cant[it.name] }
    if remaining(it, busy) > 0 then
      if not it.auto then left = left + remaining(it, busy) end
      if (stock[it.name] or 0) == 0 and not crafting[it.name] and (have[it.name] or 0) == 0 then short = short + 1 end
    end
  end
  state[GUNPOWDER] = state[GUNPOWDER] or {}
  state[GUNPOWDER].inChest = have[GUNPOWDER] or 0
  local missing = cannon and cannon.missing
  if r.error then
    say("Storage couldn't move items: " .. r.error, "red")
  elseif missing and state[missing] then
    local s = state[missing]
    if (s.inChest or 0) > 0 then
      say(("Sent %s: the cannon carries on."):format(nice(missing)), "lightBlue")
    elseif s.crafting then
      say(("The cannon waits for %s: crafting it."):format(nice(missing)), "lightBlue")
    else
      say(("The cannon waits for %s: %s."):format(nice(missing), s.why or "none stored"), "red")
    end
  elseif cannon and cannon.status == "finished" then
    say("The cannon has finished.", "lime")
  elseif left == 0 and not busy then
    say("All sent. The cannon has everything on the list.", "lime")
    status("idle", "all sent")
    return
  elseif short > 0 then
    say(short == 1 and "1 kind of item can't be had right now: see the list."
      or ("%d kinds of item can't be had right now: see the list."):format(short), "orange")
  elseif waiting > 0 then
    say(("%d more kind%s of item wait for room in the chest (a bigger one fits more)."):format(waiting,
      waiting == 1 and "" or "s"), "lightBlue")
  elseif total > 0 then
    say(("Sent %d items."):format(total), "lightBlue")
  end
  if cannon and cannon.total and cannon.total > 0 then
    status("working", ("cannon %d/%d placed"):format(cannon.placed or 0, cannon.total))
  else
    status("working", ("%d items still to send"):format(left))
  end
  if report and total > 0 then report.log(("sent %d items to the cannon"):format(total)) end
end

local function feedLoop()
  while true do
    load() -- 'cannon add' from another shell changes the file
    feed()
    os.queueEvent("cannon_changed")
    sleep(FEED_EVERY)
  end
end

---------------------------------------------------------------- screen

local display = screen.find({ setting = "cannon.monitor", scales = MONITOR_SCALES, minW = 36, minH = 10,
  fallback = term.current() })
local put, fit = screen.put, screen.fit

-- What an item is up to, and its colour.
local function stateText(it)
  local s = state[it.name] or {}
  if not it.auto and it.sent >= it.need then
    return (s.inChest or 0) > 0 and "in chest" or "done", "lime"
  elseif (s.inChest or 0) > 0 then
    return ("%d in chest"):format(s.inChest), "white"
  elseif s.crafting then
    return "crafting", "lightBlue"
  elseif s.why and (s.stock or 0) == 0 then
    return "can't: " .. s.why, "red"
  elseif s.stock == 0 then
    return "none stored", "orange"
  end
  return it.auto and not working() and "done" or "waiting", it.auto and not working() and "lime" or "gray"
end

local function draw()
  if not display.target then return end
  local win, w, h = display:frame()
  local need, sent = 0, 0
  for _, it in ipairs(job.items) do
    if not it.auto then need, sent = need + it.need, sent + math.min(it.sent, it.need) end
  end
  put(win, 1, 1, (" "):rep(w), "white", "gray")
  put(win, 2, 1, "Schematicannon", "yellow", "gray")
  local head
  if cannon and cannon.total and cannon.total > 0 then
    head = ("%d / %d placed"):format(cannon.placed or 0, cannon.total)
  else
    head = ("%d / %d sent"):format(sent, need)
  end
  put(win, w - #head, 1, head, "lightGray", "gray")
  -- the cannon, the chest and its gunpowder
  local text, colour = cannonText()
  if text then
    put(win, 2, 2, fit("Cannon: " .. text, w - 2), colour)
  else
    put(win, 2, 2, fit("No Block Reader on the cannon: sending the list", w - 2), "gray")
  end
  local where = chest and ("Chest: " .. chest) or "No chest"
  local powder = state[GUNPOWDER] and state[GUNPOWDER].inChest
  if powder then where = where .. ("   gunpowder %d"):format(powder) end
  put(win, 2, 3, fit(where, w - 2), chest and "gray" or "orange")
  local y = 5
  for _, it in ipairs(job.items) do
    if y > h - 2 then
      put(win, 2, h - 1, "...and more", "gray")
      break
    end
    local st, stColour = stateText(it)
    local count = it.auto and ("%d sent"):format(it.sent) or ("%d/%d"):format(math.min(it.sent, it.need), it.need)
    local right = count .. "  " .. st
    if #right > math.floor(w * 0.6) then right = fit(right, math.floor(w * 0.6)) end
    put(win, 2, y, fit(nice(it.name), w - #right - 3), cannon and it.name == cannon.missing and "orange" or "white")
    put(win, w - #right, y, right, stColour)
    y = y + 1
  end
  if #job.items == 0 then
    put(win, 2, y, cannon and "Nothing yet: items join as the cannon asks." or "The list is empty: 'cannon add <item> <n>'.",
      "gray")
  end
  put(win, 1, h, fit(message[1], w), message[2])
  display:show()
end

local function uiLoop()
  while true do
    draw()
    local ev = { os.pullEvent() }
    if ev[1] == "peripheral" or ev[1] == "peripheral_detach" then display:refresh() end
  end
end

---------------------------------------------------------------- commands

local function printList()
  if #job.items == 0 then
    print("The list is empty.")
    return
  end
  for _, it in ipairs(job.items) do
    if it.auto then
      print(("%-28s %d sent (the cannon asked)"):format(nice(it.name), it.sent))
    else
      print(("%-28s %d of %d sent"):format(nice(it.name), math.min(it.sent, it.need), it.need))
    end
  end
end

-- The items a plan's blocks need: name -> count.
local function planItems(id)
  if not plan then return nil, "lib/plan.lua is missing: 'install update'" end
  local p, err = plan.load(id)
  if not p then return nil, err end
  local out = {}
  for _, m in ipairs(p.mats) do
    local block = plan.base(m.block)
    local short = block:gsub("^minecraft:", "")
    if not NOT_ITEMS[short] and m.total > 0 then
      -- oak_wall_sign is placed from an oak_sign, soul_wall_torch from a soul_torch
      local item = AS_ITEM[short] and ("minecraft:" .. AS_ITEM[short]) or (block:gsub("_wall_", "_"))
      out[item] = (out[item] or 0) + m.total
    end
  end
  return out
end

-- Add n of an item to the list; one the cannon asked for gets an amount now.
local function add(name, n)
  local it = find(name)
  if it then
    if it.auto then it.auto, it.need = nil, it.sent end
    it.need = it.need + n
  else
    job.items[#job.items + 1] = { name = name, need = n, sent = 0 }
  end
end

local args = { ... }
load()
if args[1] == "add" then
  local n = tonumber(args[#args])
  local text = table.concat(args, "_", 2, #args - 1)
  if not n or n < 1 or text == "" then
    print("Usage: cannon add <item> <how many>")
    return
  end
  local name = itemName(text)
  add(name, math.floor(n))
  save()
  print(("%s: %d on the list."):format(nice(name), find(name).need))
  return
elseif args[1] == "remove" and args[2] then
  local name = itemName(table.concat(args, "_", 2))
  local it, i = find(name)
  if not it then
    print(nice(name) .. " isn't on the list.")
    return
  end
  table.remove(job.items, i)
  save()
  print(nice(name) .. " is off the list.")
  return
elseif args[1] == "plan" and args[2] then
  local items, err = planItems(args[2])
  if not items then
    print(err)
    return
  end
  local names = {}
  for name in pairs(items) do names[#names + 1] = name end
  table.sort(names, function(a, b) return items[a] > items[b] end)
  for _, name in ipairs(names) do add(name, items[name]) end
  save()
  print(("Added %d kinds of block from %s."):format(#names, args[2]))
  printList()
  return
elseif args[1] == "list" then
  printList()
  return
elseif args[1] == "again" then
  for _, it in ipairs(job.items) do it.sent = 0 end
  save()
  print("Everything on the list gets sent again.")
  return
elseif args[1] == "clear" then
  job.items = {}
  save()
  print("List forgotten.")
  return
elseif args[1] == "chest" then
  local name = args[2]
  if not name then
    local list = {}
    for _, n in ipairs(peripheral.getNames()) do
      if isInventory(n) then list[#list + 1] = n end
    end
    if #list == 0 then
      print("No chest here. Put one next to me, touching the cannon.")
      return
    end
    for i, n in ipairs(list) do print(("%2d  %s"):format(i, n)) end
    write("Which one? (Enter to cancel) ")
    local text = read()
    if text == "" then return end
    name = list[tonumber(text)] or text
  end
  if not (peripheral.isPresent(name) and isInventory(name)) then
    print(name .. " isn't a chest I can reach.")
    return
  end
  job.chest = name
  save()
  print(("Using %s. It needs to touch the cannon and be on the storage cable"):format(name))
  print("(or be an ender chest whose twin is).")
  return
elseif args[1] then
  print("Usage: cannon [add <item> <n> | remove <item> | plan <name> | list | again | clear | chest [name]]")
  return
end

if not net.open("any") then
  print("I need a modem: a wired one on the storage cable, or a")
  print("wireless or ender one that reaches the storage computer.")
  return
end

term.clear()
if errlog then errlog.init("cannon") end
if report then report.init("cannon feeder") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, feedLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
