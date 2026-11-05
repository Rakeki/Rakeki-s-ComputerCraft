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
--     from then on (never more in the chest than the blocks the cannon has
--     left to place), until the cannon says it's finished.
--   - A list typed in (or a plan's blocks), each sent until the whole amount
--     has gone, and never more: the cannon has it before it asks. Only if
--     the cannon then waits for one of them with none in the chest is a
--     stack more sent.
-- A monitor and this computer's screen lead with what's missing now: the
-- item the cannon is stuck on and why, and every item storage hasn't got
-- enough of. Tap the monitor (or press Tab) for what has been sent.
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
local LATE_WAIT = 60 -- seconds to hold off after an unanswered top-up (it may still be done: never send twice)
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
local short = {} -- what can't be sent now: { name, left, stock, crafting, why, waits }, from the last top-up
local late = {} -- request id -> when, for top-ups the storage computer didn't answer in time
local view = "missing" -- the page on screen: "missing" (what can't be had) or "sent"
local version = 0 -- goes up whenever what's on screen changes

---------------------------------------------------------------- helpers

local function changed()
  version = version + 1
  os.queueEvent("cannon_changed")
end

local function say(text, colour)
  message = { text, colour or "lightGray" }
  changed()
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

-- Ender chests reached through a wired modem (a peripheral type with "ender"
-- in it, as the storage computer counts them): never storage, so if there's
-- just one it can only be the cannon's.
local function enderChests()
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) then
      for _, t in ipairs({ peripheral.getType(name) }) do
        if t:lower():find("ender", 1, true) then list[#list + 1] = name break end
      end
    end
  end
  return list
end

-- The one picked with 'cannon chest', else the only one touching me, else
-- the only ender chest on my wired modem.
local function findChest()
  if job.chest and peripheral.isPresent(job.chest) then return job.chest end
  local list = nearChests()
  if #list == 1 then return list[1] end
  if #list > 1 then return nil, "more than one chest next to me: pick one with 'cannon chest'" end
  local ender = enderChests()
  if #ender == 1 then return ender[1] end
  if #ender > 1 then return nil, "more than one ender chest on my modem: pick one with 'cannon chest'" end
  return nil, "can't see a chest: put it against me (a vanilla ender chest won't do), or 'cannon chest'"
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

-- The item the cannon is stuck on right now (MissingItem can outlast the
-- wait, so only while its status says a block is missing).
local function waitingFor()
  if not cannon or not cannon.missing or cannon.missing == GUNPOWDER then return nil end
  if cannon.status == nil or cannon.status == "missingBlock" then return cannon.missing end
end

-- Blocks the cannon still has to place, nil without a Block Reader (or before
-- it has a schematic): no item it asks for is ever kept above this.
local function blocksLeft()
  if not (cannon and cannon.total and cannon.total > 0) then return nil end
  return math.max(0, cannon.total - (cannon.placed or 0))
end

-- How many more of an item to send, with `inside` already in the chest:
--   - on the list: the rest of its amount, never more;
--   - one the cannon asked for: enough to keep the chest topped up while it
--     works, but never more in the chest than it has blocks left to place;
--   - on the list, all sent, and the cannon is stuck waiting for it with none
--     in the chest (the list said too few, or it went home): a stack more,
--     again no more than the blocks left.
local function remaining(it, inside)
  local left = blocksLeft()
  if it.auto then
    if not working() then return 0 end
    return left and math.max(0, left - inside) or math.huge
  end
  local rest = math.max(0, it.need - it.sent)
  if rest == 0 and inside == 0 and it.name == waitingFor() then rest = math.min(STACK, left or STACK) end
  return rest
end

-- The cannon's status as a line for the screen.
local function cannonText()
  if not cannon then return nil end
  local s = cannon.status
  local waits = waitingFor()
  if waits then return "waiting for " .. nice(waits), "orange" end
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
  local waits = waitingFor()
  if waits and not find(waits) then
    job.items[#job.items + 1] = { name = waits, need = 0, sent = 0, auto = true }
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

-- Ask the storage computer: the reply, or nil, why (for the screen) and
-- net's own reason ("no answer" when it may still be on its way).
local function ask(msg)
  local reply, why = storage:ask(msg)
  if reply then return reply end
  if why == "no modem" then return nil, "no modem on me", why end
  return nil, why == "no answer" and "the storage computer didn't answer"
    or "no storage computer answered: is it running 'storage'?", why
end

local supply = claim.tracker("delivery", CLAIM_RETRY)

-- Count what a deliver reply says was moved into my chest. Returns the total.
local function countSent(r)
  if r.to ~= "own" or type(r.sent) ~= "table" then return 0 end
  local total = 0
  for _, it in ipairs(job.items) do
    local n = tonumber(r.sent[it.name]) or 0
    it.sent, total = it.sent + n, total + n
  end
  if total > 0 then save() end
  return total
end

-- A deliver that wasn't answered in time may still be done: its items land
-- in the chest all the same. Its answer is counted when it turns up (uiLoop
-- sees every rednet message), and no new deliver goes out meanwhile, or
-- both would be sent.
local function lateReply(msg)
  if type(msg) ~= "table" or msg.re ~= "deliver" or not late[msg.id] then return end
  late[msg.id] = nil
  local n = countSent(msg)
  if n > 0 then say(("The storage computer's late answer: %d more items sent."):format(n), "lightBlue") end
end

local function awaitingLate()
  for id, at in pairs(late) do
    if os.clock() - at > LATE_WAIT then late[id] = nil else return true end
  end
  return false
end

-- What to ask for this round: item -> how many the chest should hold, and
-- item -> the most to move now (what's left to send). The storage computer
-- tops a chest *up to* a count, and the cannon empties it while the request
-- is on its way, so without `most` it would refill what the cannon used,
-- round after round, long past the amount. Each item gets a fair share of
-- the chest (up to MAX_STACKS stacks); items already in the chest are asked
-- for too (most 0), so the storage computer leaves them there. The item the
-- cannon is waiting for goes first. Returns the targets, the caps, and the
-- items that had to wait for room.
local function targets(have, size)
  local want, most, waiting = {}, {}, {}
  local keep = tonumber(settings.get("cannon.gunpowder")) or GUNPOWDER_KEEP
  local active, more = {}, false
  local first = waitingFor()
  for _, it in ipairs(job.items) do
    local left = remaining(it, have[it.name] or 0)
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
  for i = #active, slots + 1, -1 do
    table.insert(waiting, 1, active[i])
    active[i] = nil
  end
  local per = math.max(1, math.min(MAX_STACKS, math.floor(slots / math.max(1, #active)))) * STACK
  for _, it in ipairs(active) do
    local inside = have[it.name] or 0
    local left = remaining(it, inside)
    want[it.name] = math.min(math.max(per, inside), inside + left)
    if left ~= math.huge then most[it.name] = left end
  end
  if keep > 0 and not want[GUNPOWDER] then want[GUNPOWDER] = keep end
  return want, most, waiting
end

-- What can't be sent: each item with more to send that storage hasn't got
-- (or not enough of) and isn't making, the cannon's own wait first.
-- stock / crafting / craftable / cant: name -> what the storage computer said.
local function findShort(have, stock, crafting, craftable, cant)
  local list = {}
  local first = waitingFor()
  for _, it in ipairs(job.items) do
    local inside, s = have[it.name] or 0, stock[it.name]
    local waits = it.name == first and inside == 0
    local rest = not it.auto and it.need - it.sent or 0
    if s ~= nil then
      local got = s + (crafting[it.name] or 0) + (craftable[it.name] or 0)
      local entry
      if rest > 0 and rest > got then
        entry = { left = rest }
      elseif rest <= 0 and waits and got == 0 then
        entry = {} -- the cannon wants it and there's none: how many it needs, it doesn't say
      end
      if entry then
        entry.name, entry.stock, entry.crafting, entry.why, entry.waits = it.name, s, crafting[it.name], cant[it.name], waits
        if waits then table.insert(list, 1, entry) else list[#list + 1] = entry end
      end
    end
  end
  return list
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
    short = {}
    if cannon then
      say(cannon.status == "finished" and "The cannon has finished." or "Waiting for the cannon to ask for something.",
        cannon.status == "finished" and "lime" or "lightGray")
    else
      say("Nothing to send: 'cannon add <item> <n>', or a Block Reader on the cannon.", "lightGray")
    end
    status("idle", cannon and cannon.status == "finished" and "cannon finished" or "nothing to send")
    return
  end
  if awaitingLate() then
    say("Waiting for the storage computer to answer my last request...", "orange")
    status("waiting", "storage computer slow to answer")
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
  local want, most, waiting = targets(have, size)
  local msg = { type = "deliver", items = want, most = most }
  local r, whyNot, code = ask(msg)
  if not r then
    if code == "no answer" and msg.id then late[msg.id] = os.clock() end
    say("Storage: " .. whyNot, "orange")
    status("waiting", "no storage computer")
    return
  end
  supply:seen(r)
  if r.to ~= "own" then
    say("The storage computer sent it somewhere else: hooking my chest up again.", "orange")
    return
  end
  local total = countSent(r)
  -- the items that waited for room: just how many storage has of each
  local stock, craftable = r.stock or {}, {}
  local others, need = {}, {}
  for _, it in ipairs(waiting) do
    local left = remaining(it, have[it.name] or 0)
    if left > 0 and left ~= math.huge then others[#others + 1], need[it.name] = it.name, left end
  end
  if #others > 0 then
    local c = ask({ type = "count", items = others, need = need })
    if c then
      for name, n in pairs(c.counts or {}) do stock[name] = n end
      for name, n in pairs(c.craftable or {}) do craftable[name] = n end
    end
  end
  -- what each item is up to, for the screen
  have = contents()
  local crafting, cant = r.crafting or {}, r.cantCraft or {}
  local left = 0
  for _, it in ipairs(job.items) do
    state[it.name] = { inChest = have[it.name] or 0, stock = stock[it.name], crafting = crafting[it.name],
      why = cant[it.name] }
    if not it.auto then left = left + math.max(0, it.need - it.sent) end
  end
  short = findShort(have, stock, crafting, craftable, cant)
  state[GUNPOWDER] = state[GUNPOWDER] or {}
  state[GUNPOWDER].inChest = have[GUNPOWDER] or 0
  local busy = working()
  local waits = waitingFor()
  if r.error then
    say("Storage couldn't move items: " .. r.error, "red")
  elseif waits and state[waits] then
    local s = state[waits]
    if (s.inChest or 0) > 0 then
      say(("Sent %s: the cannon carries on."):format(nice(waits)), "lightBlue")
    elseif s.crafting then
      say(("The cannon waits for %s: crafting it."):format(nice(waits)), "lightBlue")
    else
      say(("The cannon waits for %s: %s."):format(nice(waits), s.why or "none stored"), "red")
    end
  elseif cannon and cannon.status == "finished" then
    say("The cannon has finished.", "lime")
  elseif left == 0 and not busy then
    say("All sent. The cannon has everything on the list.", "lime")
    status("idle", "all sent")
    return
  elseif #short > 0 then
    say(#short == 1 and "1 item can't be had right now: see Missing now."
      or ("%d items can't be had right now: see Missing now."):format(#short), "orange")
  elseif #waiting > 0 then
    say(("%d more kind%s of item wait for room in the chest (a bigger one fits more)."):format(#waiting,
      #waiting == 1 and "" or "s"), "lightBlue")
  elseif total > 0 then
    say(("Sent %d items."):format(total), "lightBlue")
  end
  if waits then
    status("waiting", "cannon waits for " .. nice(waits))
  elseif #short > 0 then
    status("waiting", ("%d items short"):format(#short))
  elseif cannon and cannon.total and cannon.total > 0 then
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
    changed()
    sleep(FEED_EVERY)
  end
end

---------------------------------------------------------------- screen

local display = screen.find({ setting = "cannon.monitor", scales = MONITOR_SCALES, minW = 36, minH = 10,
  fallback = term.current() })
-- With a monitor, the terminal shows the same picture, so the list can be
-- read at the computer too.
local console = screen.new(term.current())
local put, fit = screen.put, screen.fit

-- One row: name on the left, text on the right (up to 60% of the width).
local function row(win, w, y, name, nameColour, right, rightColour)
  if #right > math.floor(w * 0.6) then right = fit(right, math.floor(w * 0.6)) end
  put(win, 2, y, fit(name, w - #right - 3), nameColour)
  put(win, w - #right, y, right, rightColour)
end

-- Why a short item can't be had, and its colour.
local function shortText(e)
  if e.crafting then return ("crafting %d"):format(e.crafting), "lightBlue" end
  if e.why and e.stock == 0 then return "can't: " .. e.why, "red" end
  if e.stock == 0 then return "none stored", "red" end
  return ("only %d stored"):format(e.stock), "orange"
end

-- What a listed item is up to (the Sent page), and its colour.
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

-- The cannon and what it's stuck on: rows 2 and 3. Returns the next free row.
local function drawCannon(win, w)
  local text, colour = cannonText()
  if not text then
    put(win, 2, 2, fit("No Block Reader on the cannon: sending the list", w - 2), "gray")
    return 4
  end
  put(win, 2, 2, fit("Cannon: " .. text, w - 2), colour)
  local waits = waitingFor()
  if not waits then return 4 end
  local s = state[waits] or {}
  local why, whyColour
  if (s.inChest or 0) > 0 then
    why, whyColour = ("%d in the chest: it picks them up next"):format(s.inChest), "lightBlue"
  elseif s.crafting then
    why, whyColour = ("being crafted (%d)"):format(s.crafting), "lightBlue"
  elseif s.stock == nil then
    why, whyColour = "asking the storage computer...", "gray"
  elseif s.stock > 0 then
    why, whyColour = ("%d stored: on its way"):format(s.stock), "lightBlue"
  else
    why, whyColour = s.why and ("none stored, can't craft: " .. s.why) or "none stored", "red"
  end
  -- how many more it needs, when the list says
  for _, e in ipairs(short) do
    if e.name == waits and e.left then why = ("need %d: %s"):format(e.left, why) end
  end
  put(win, 4, 3, fit(why, w - 4), whyColour)
  return 5
end

-- Missing now: what the cannon can't be given, the most important page.
local function drawMissing(win, w, h, y)
  local others = {}
  local waits = waitingFor()
  for _, e in ipairs(short) do
    if not (e.waits and e.name == waits) then others[#others + 1] = e end
  end
  if #others == 0 then
    if #job.items > 0 then
      put(win, 2, y, fit(next(state) and "Nothing missing: storage has the rest." or "Checking storage...",
        w - 2), next(state) and "lime" or "gray")
    else
      put(win, 2, y, fit(cannon and "Nothing yet: items join as the cannon asks."
        or "The list is empty: 'cannon add <item> <n>'.", w - 2), "gray")
    end
    return
  end
  put(win, 2, y, fit(("Missing now: %d"):format(#others), w - 2), "yellow")
  y = y + 1
  for i, e in ipairs(others) do
    if y > h - 3 then
      put(win, 2, h - 2, fit(("...and %d more"):format(#others - i + 1), w - 2), "gray")
      break
    end
    local text, colour = shortText(e)
    row(win, w, y, nice(e.name), "white", (e.left and ("need %d  "):format(e.left) or "") .. text, colour)
    y = y + 1
  end
end

-- Sent: the list with how much of each has gone.
local function drawSent(win, w, h, y)
  for i, it in ipairs(job.items) do
    if y > h - 3 then
      put(win, 2, h - 2, fit(("...and %d more"):format(#job.items - i + 1), w - 2), "gray")
      break
    end
    local st, stColour = stateText(it)
    local count = it.auto and ("%d sent"):format(it.sent) or ("%d/%d"):format(it.sent, it.need)
    row(win, w, y, nice(it.name), it.name == waitingFor() and "orange" or "white", count .. "  " .. st, stColour)
    y = y + 1
  end
  if #job.items == 0 then put(win, 2, y, "Nothing sent yet.", "gray") end
end

local function draw(display)
  if not display.target then return end
  if display:same(version .. "|" .. view) then return end
  local win, w, h = display:frame()
  local need, sent, done, kinds = 0, 0, 0, 0
  for _, it in ipairs(job.items) do
    if not it.auto then
      need, sent, kinds = need + it.need, sent + math.min(it.sent, it.need), kinds + 1
      if it.sent >= it.need then done = done + 1 end
    end
  end
  put(win, 1, 1, (" "):rep(w), "white", "gray")
  put(win, 2, 1, "Schematicannon", "yellow", "gray")
  local left = blocksLeft()
  if left then
    local head = ("%d / %d placed"):format(cannon.placed or 0, cannon.total)
    put(win, w - #head, 1, head, "lightGray", "gray")
  end
  local y = drawCannon(win, w)
  if view == "sent" then drawSent(win, w, h, y) else drawMissing(win, w, h, y) end
  -- the small print: what's gone so far, the chest, and how to switch pages
  local tail = ("Sent %d/%d"):format(sent, need)
  if kinds > 0 then tail = tail .. ("  %d/%d done"):format(done, kinds) end
  local powder = state[GUNPOWDER] and state[GUNPOWDER].inChest
  if powder then tail = tail .. ("  powder %d"):format(powder) end
  local hint = view == "sent" and "[tap: missing]" or "[tap: sent]"
  put(win, 2, h - 1, fit(chest and tail or "No chest", w - #hint - 3), chest and "gray" or "orange")
  put(win, w - #hint, h - 1, hint, "gray")
  put(win, 1, h, fit(message[1], w), message[2])
  display:show()
end

local function uiLoop()
  while true do
    draw(display)
    if display.name then draw(console) end
    local ev = { os.pullEvent() }
    if ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
      display:refresh()
      changed()
    elseif ev[1] == "rednet_message" and ev[4] == STORAGE_PROTOCOL then
      lateReply(ev[3])
    elseif display:clicked(ev) or (display.name and console:clicked(ev))
      or (ev[1] == "key" and (ev[2] == keys.tab or ev[2] == keys.space)) then
      view = view == "sent" and "missing" or "sent"
    end
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
      local extra = it.sent > it.need and (" (+%d the cannon waited for)"):format(it.sent - it.need) or ""
      print(("%-28s %d of %d sent%s"):format(nice(it.name), math.min(it.sent, it.need), it.need, extra))
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
