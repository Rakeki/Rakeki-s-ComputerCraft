-- Enrichment chambers for the storage system. Keeps every Mekanism
-- Enrichment Chamber (and Enriching Factory) on the storage computer's wired
-- network fed with ores from storage. An ore block gives 2 dust, 3 raw ores
-- give 4 and a raw ore block 12; the dust goes back into storage, and the
-- smelter (computers/smelter-computer) smelts it into ingots: twice the
-- ingots from ore blocks, a third more from raw ores. Gem ores come out as
-- gems (2 diamonds, 12 redstone, ...).
--
--   enricher                        start (startup.lua runs this)
--   enricher add [chamber hopper]   add a chamber and the hopper on top of it (asks for what's not given)
--   enricher remove <n>             forget chamber n (no number: list them)
--   enricher chest [name|none]      use an empty chest on the network as the work chest
--                                   (no name: pick from a list; none: stop using one)
--   enricher chest remote           far from the storage system: a supply and a return ender chest
--                                   (the chests under the chambers then empty into the return one)
--
-- CC can't put items into a Mekanism machine (its computer port hides the
-- slots), so each chamber has a hopper on top, which the storage computer
-- fills. With a work chest, the storage computer fills that once a round
-- instead and the enricher fills the hoppers from it (lib/workchest.lua).
-- The chamber ejects its dust out of its bottom into a storage input chest
-- under it; this program sets that side to Output and turns Auto-eject on
-- when the chamber's security is Public.
--
-- While it's running, the smelter leaves the ores it enriches alone (it asks
-- on the 'enricher' protocol), and smelts the dust instead.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local workchest = require("lib.workchest") -- the chest the storage computer fills in one go
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local config = fs.exists("config.lua") and require("config") or {}

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local ENRICHER_PROTOCOL = "enricher" -- the smelter asks which ores to leave alone on this
local MACHINES_FILE = "/.enricher_machines" -- { chamber, hopper } per chamber, changed by 'enricher add' etc.
local EVERY = 5 -- seconds between rounds of filling the hoppers
local REPLY_WAIT = 30 -- seconds to wait for the storage computer to answer (a busy one answers late)
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local STACK = 64 -- items to a slot in a chamber's input
local HOPPER_SLOTS = 5 -- slots in a hopper
local STUCK_AFTER = 60 -- seconds an item may sit in a hopper over an empty chamber before it's put back
local MONITOR_SCALE = 0.5 -- text size on the monitor (0.5 fits the most)
-- Process slots in each tier of Enriching Factory.
local FACTORY_SLOTS = { basic = 3, advanced = 5, elite = 7, ultimate = 9 }

-- Used if config.lua has none; see config.lua for what they mean.
local METALS = config.metals or { "iron", "gold", "copper", "osmium", "tin", "lead", "uranium" }
local GEMS = config.gems or { "coal", "diamond", "emerald", "lapis", "redstone", "quartz", "fluorite" }
local KEEP = config.keep or {}
local SET_SIDES = config.setSides ~= false
local NAMES = config.names or {}

-- What goes in, as Lua patterns on item ids: ores of every kind above, and
-- raw metals and their blocks. The smelter is sent these to leave alone.
local TAKES = {}
for _, m in ipairs(METALS) do
  TAKES[#TAKES + 1] = "[:_]" .. m .. "_ore$" -- iron_ore, deepslate_iron_ore, nether_gold_ore
  TAKES[#TAKES + 1] = "^[%w_]+:raw_" .. m .. "$"
  TAKES[#TAKES + 1] = "^[%w_]+:raw_" .. m .. "_block$"
end
for _, g in ipairs(GEMS) do TAKES[#TAKES + 1] = "[:_]" .. g .. "_ore$" end

local machines = {} -- what the screen shows: each chamber with its hopper and how it's doing
local message = { "Looking for the storage computer...", "lightGray" }
local news -- { text, colour, untilTime }: a put-back item, shown for a minute
local waiting = {} -- item -> how many in storage to enrich, for the screen
local taking = false -- a chamber is ready, so the smelter should leave the ores alone
local configured = {} -- chamber -> true once its sides have been set (or tried)
local stuckSince = {} -- hopper -> { name, count, since }: an item not going into an empty chamber
local noEnrich = {} -- item -> true: found not to go into a chamber (until restart)

---------------------------------------------------------------- helpers

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("enricher_changed")
end

local function tell(text, colour)
  news = { text, colour, os.clock() + 60 }
  say(text, colour)
end

local function status(state, detail)
  if report then report.set(state, detail) end
end

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function takes(name)
  for _, p in ipairs(TAKES) do
    if name:find(p) then return true end
  end
  return false
end

-- Raw ores go in 3 at a time (3 make 4 dust); everything else 1 at a time.
local function perOp(name)
  return (name:find("^[%w_]+:raw_") and not name:find("_block$")) and 3 or 1
end

local function readMachines()
  local t = files.read(MACHINES_FILE)
  return type(t) == "table" and t or {}
end

local function writeMachines(t)
  files.write(MACHINES_FILE, t)
  os.queueEvent("enricher_added") -- the running program, if this is another tab
end

-- Peripherals on the wired network (not ones touching this computer: the
-- storage computer can't reach those) that pass test(type).
local function findOnNetwork(test)
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if not sides[name] and t and test(t) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

local function isChamber(t) return t == "enrichmentChamber" or t:find("EnrichingFactory$") ~= nil end
local function isHopper(t) return t:find("hopper", 1, true) ~= nil end

-- Process slots: 1 for a chamber, 3 to 9 for a factory (by its tier).
local function slotsOf(name)
  local t = peripheral.getType(name) or ""
  local tier = t:match("^(%l+)EnrichingFactory$")
  return tier and (FACTORY_SLOTS[tier] or 3) or 1, tier ~= nil
end

local function titleOf(entry, n) return NAMES[entry.chamber] or ("Chamber " .. n) end

---------------------------------------------------------------- talking to storage

-- over the cable (or wireless, if that's all there is)
local storage = net.peer(STORAGE_PROTOCOL, { open = "any", wait = REPLY_WAIT })

-- Ask the storage computer something and wait for its answer: nil and why
-- if there's none.
local function ask(msg)
  local reply, why = storage:ask(msg)
  if reply then return reply end
  return nil, why == "no answer" and "the storage computer didn't answer" or "no storage computer answered"
end

local work = workchest.new("enricher", ask)

---------------------------------------------------------------- reading a chamber

-- Mekanism hands over an empty slot as air with count 0.
local function stackOf(s)
  if type(s) == "table" and type(s.name) == "string" and (s.count or 0) > 0 and s.name ~= "minecraft:air" then
    return { name = s.name, count = s.count }
  end
  return nil
end

-- Everything about one chamber and its hopper. Mekanism runs each method on
-- the game's main thread, one tick per call, so the calls run side by side.
local function readMachine(m)
  local jobs = {}
  m.inputs, m.outputs, m.hopper, m.hopperTotal = {}, {}, {}, 0
  local function call(method, ...)
    local ok, v = pcall(peripheral.call, m.entry.chamber, method, ...)
    return ok and v or nil
  end
  for i = 1, m.slots do
    jobs[#jobs + 1] = function()
      if m.factory then
        m.inputs[i], m.outputs[i] = stackOf(call("getInput", i - 1)), stackOf(call("getOutput", i - 1))
      else
        m.inputs[i], m.outputs[i] = stackOf(call("getInput")), stackOf(call("getOutput"))
      end
    end
  end
  jobs[#jobs + 1] = function() m.energy = call("getEnergyFilledPercentage") end
  jobs[#jobs + 1] = function() m.usage = call("getEnergyUsage") end
  jobs[#jobs + 1] = function()
    local ok, list = pcall(peripheral.call, m.entry.hopper, "list")
    m.hopperOk = ok and type(list) == "table"
    m.hopperList = m.hopperOk and list or {}
    for _, item in pairs(m.hopperList) do
      m.hopper[item.name] = (m.hopper[item.name] or 0) + item.count
      m.hopperTotal = m.hopperTotal + item.count
    end
  end
  parallel.waitForAll(table.unpack(jobs))
end

-- Set the chamber's bottom to Output and turn Auto-eject on, once. Only
-- works when its security is Public; false if it couldn't.
local function configure(m)
  if configured[m.entry.chamber] ~= nil or not SET_SIDES then return end
  local name = m.entry.chamber
  local okM, mode = pcall(peripheral.call, name, "getMode", "ITEM", "BOTTOM")
  if okM and mode ~= "OUTPUT" then okM = pcall(peripheral.call, name, "setMode", "ITEM", "BOTTOM", "OUTPUT") end
  local okE, ejecting = pcall(peripheral.call, name, "isEjecting", "ITEM")
  if okE and not ejecting then okE = pcall(peripheral.call, name, "setEjecting", "ITEM", true) end
  configured[name] = okM and okE
  if not configured[name] then
    tell(("Couldn't set %s's sides: make it Public, or set Bottom to Output and Auto-eject on by hand.")
      :format(m.title), "orange")
  end
end

-- How much more of an item the chamber's input slots can take: an empty
-- slot takes a stack, one holding the item the rest of its stack.
local function roomFor(m, name)
  local room = 0
  for i = 1, m.slots do
    local s = m.inputs[i]
    if not s then room = room + STACK elseif s.name == name then room = room + STACK - s.count end
  end
  return room - (m.hopper[name] or 0)
end

local function inputOf(m, name)
  local n = 0
  for i = 1, m.slots do
    local s = m.inputs[i]
    if s and (not name or s.name == name) then n = n + s.count end
  end
  return n
end

-- The item to send next: what's already in the hopper, else (a chamber
-- has one slot) what's in the chamber, else whatever there's most of.
local function pickItem(m, avail)
  local _, inHopper = next(m.hopperList)
  if inHopper then return inHopper.name end
  if not m.factory and m.inputs[1] then return m.inputs[1].name end
  local best, most = nil, 0
  for name, n in pairs(avail) do
    if n >= perOp(name) and n > most and not noEnrich[name] then best, most = name, n end
  end
  return best
end

---------------------------------------------------------------- a round

local function round()
  local list = readMachines()
  local nowMachines = {}
  for i, entry in ipairs(list) do
    local slots, factory = slotsOf(entry.chamber)
    nowMachines[i] = { n = i, entry = entry, title = titleOf(entry, i), slots = slots, factory = factory,
      present = peripheral.isPresent(entry.chamber), inputs = {}, outputs = {}, hopper = {}, hopperList = {},
      hopperTotal = 0 }
  end
  local reads = {}
  for _, m in ipairs(nowMachines) do
    if m.present then reads[#reads + 1] = function() readMachine(m) end end
  end
  if #reads > 0 then parallel.waitForAll(table.unpack(reads)) end
  machines = nowMachines
  for _, m in ipairs(machines) do
    if m.present then configure(m) end
  end
  local ready = 0
  for _, m in ipairs(machines) do
    if m.present and m.hopperOk and (m.energy or 0) > 0 then ready = ready + 1 end
  end
  taking = ready > 0
  if #machines == 0 then
    local free = #findOnNetwork(isChamber)
    say(free > 0 and ("%d chamber(s) on the network: hold Ctrl+T twice, then 'enricher add'."):format(free)
      or "No chambers yet: put a wired modem on one, then hold Ctrl+T twice and 'enricher add'.", "orange")
    status("waiting", "no chambers")
    return
  end

  local reply, err = ask({ type = "stock" })
  if not reply or type(reply.counts) ~= "table" then
    say("Storage not answering: is it running, on the same cable?", "orange")
    status("waiting", ("storage computer: %s"):format(err or "too old to answer"))
    return
  end
  -- far away, put-backs go home through the return ender chest, and nothing
  -- is loaded without the work chest
  local useWork = work:check(reply) or work.remote
  local input, avail = work:input(reply.input), {}
  for name, n in pairs(reply.counts) do
    if takes(name) and n > (KEEP[name] or 0) then avail[name] = n - (KEEP[name] or 0) end
  end
  waiting = {}
  for name, n in pairs(avail) do waiting[name] = n end

  -- an item sitting in a hopper over an empty chamber doesn't go in (it
  -- isn't one Mekanism enriches, or the hopper isn't on top): put it back
  local now, problem = os.clock(), nil
  for _, m in ipairs(machines) do
    local _, item = next(m.hopperList)
    local s = stuckSince[m.entry.hopper]
    if item and inputOf(m) == 0 and (m.energy or 0) > 0 then
      if s and s.name == item.name and m.hopper[item.name] >= s.count then
        if now - s.since > STUCK_AFTER then
          for slot in pairs(m.hopperList) do pcall(peripheral.call, m.entry.hopper, "pushItems", input, slot) end
          noEnrich[item.name] = true
          tell(("%s didn't go into %s: put it back. Is the hopper on top, pointing down?")
            :format(nice(item.name), m.title), "orange")
          m.hopperList, m.hopper, m.hopperTotal, stuckSince[m.entry.hopper] = {}, {}, 0, nil
        end
      else
        stuckSince[m.entry.hopper] = { name = item.name, count = m.hopper[item.name], since = now }
      end
    else
      stuckSince[m.entry.hopper] = nil
    end
  end

  -- fill the hoppers, chamber by chamber (they share what there is); with a
  -- work chest each load is noted down and fetched for all at once below
  local sent = 0
  local plan = useWork and {} or nil
  for _, m in ipairs(machines) do
    m.item = nil
    if m.present and m.hopperOk and (m.energy or 0) > 0 then
      local name = pickItem(m, avail)
      m.item = name
      if name and (avail[name] or 0) > 0 then
        local n = math.min(roomFor(m, name), avail[name], SEND_MAX, HOPPER_SLOTS * STACK - m.hopperTotal)
        local per = perOp(name)
        if per > 1 then n = n - (inputOf(m, name) + (m.hopper[name] or 0) + n) % per end
        if n > 0 and plan then
          plan[#plan + 1] = { m = m, name = name, n = n }
          avail[name] = avail[name] - n
        elseif n > 0 then
          local r = ask({ type = "send", to = m.entry.hopper, items = { [name] = n } })
          local got = r and type(r.sent) == "table" and r.sent[name] or 0
          if r and r.error then problem = r.error end
          if not r then problem = "the storage computer didn't answer while loading " .. m.title end
          m.hopper[name] = (m.hopper[name] or 0) + got
          m.hopperTotal = m.hopperTotal + got
          avail[name] = avail[name] - got
          sent = sent + got
        end
      end
    end
  end
  if plan then
    local items = {}
    for _, p in ipairs(plan) do items[p.name] = (items[p.name] or 0) + p.n end
    local r, why = work:fill(items, 0)
    if r and r.error and not r.nochest then problem = r.error end
    if not r and next(items) then problem = why end
    for _, p in ipairs(plan) do
      local got = work:move(p.name, p.m.entry.hopper, nil, p.n)
      p.m.hopper[p.name] = (p.m.hopper[p.name] or 0) + got
      p.m.hopperTotal = p.m.hopperTotal + got
      avail[p.name] = avail[p.name] + p.n - got
      sent = sent + got
    end
    work:empty(input)
  end

  -- how each chamber is doing, for the screen
  local working, broken = 0, 0
  for _, m in ipairs(machines) do
    local queued = inputOf(m) + (m.hopperTotal or 0)
    local full = false
    for i = 1, m.slots do
      if m.outputs[i] and m.outputs[i].count >= STACK then full = true end
    end
    m.queued = queued
    if not m.present then
      m.state, m.colour = "not on network", "red"
    elseif not m.hopperOk then
      m.state, m.colour = "no hopper", "red"
    elseif (m.energy or 0) <= 0 then
      m.state, m.colour = "no power", "red"
    elseif full then
      m.state, m.colour = "output full", "red"
    elseif (m.usage or 0) > 0 then
      m.state, m.colour = "enriching", "lime"
      m.item = m.item or (m.inputs[1] and m.inputs[1].name)
    elseif queued > 0 and not m.factory and m.inputs[1] and m.inputs[1].count < perOp(m.inputs[1].name) then
      m.state, m.colour = ("needs %d more"):format(perOp(m.inputs[1].name) - m.inputs[1].count), "orange"
      m.item = m.inputs[1].name
    elseif queued > 0 then
      m.state, m.colour = "starting", "lightBlue"
    else
      m.state, m.colour = "idle", "gray"
    end
    if m.colour == "red" then broken = broken + 1 elseif m.state == "enriching" then working = working + 1 end
  end

  if news and os.clock() < news[3] then
    message = { news[1], news[2] }
  elseif problem then
    say("Couldn't fill a hopper: " .. problem, "red")
  elseif work.problem then
    say(("Not using the work chest: %s."):format(work.problem), "orange")
  elseif broken > 0 then
    local m
    for _, x in ipairs(machines) do
      if x.colour == "red" then m = m or x end
    end
    local why = {
      ["no hopper"] = "its hopper isn't on the network",
      ["no power"] = "it has no power",
      ["output full"] = "its dust isn't going anywhere: chest under it, Auto-eject on?",
      ["not on network"] = "it isn't on the network",
    }
    say(("%s: %s"):format(m.title, why[m.state] or m.state), "red")
  elseif sent > 0 then
    say(("Sent %d ores to the chambers."):format(sent))
  elseif working == 0 then
    say("Nothing to enrich.")
  else
    say(("Enriching in %d of %d chambers."):format(working, #machines))
  end
  status(broken > 0 and "alert" or working > 0 and "running" or "idle",
    ("%d of %d chambers enriching"):format(working, #machines))
end

---------------------------------------------------------------- screen

-- Drawn through lib/screen.lua (a hidden window shown in one go), so it
-- doesn't flash: on a monitor if there is one, else the terminal.
local display
local fitText = screen.fit

local function waitingText()
  local list, total = {}, 0
  for name, n in pairs(waiting) do
    list[#list + 1] = { name, n }
    total = total + n
  end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local parts = {}
  for i = 1, math.min(4, #list) do parts[i] = ("%s %d"):format(nice(list[i][1]), list[i][2]) end
  return total, table.concat(parts, ", ")
end

local function draw()
  local total, top = waitingText()
  local key = { message[1], message[2], total, top }
  for _, m in ipairs(machines) do
    key[#key + 1] = table.concat({ m.title, m.item or "", m.queued or 0, m.energy or 0, m.state or "" }, "/")
  end
  if display:same(table.concat(key, "|")) then return end

  local win, w, h = display:frame()
  local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end
  put(1, 1, (" "):rep(w), "white", "gray")
  put(2, 1, "Enrichment chambers", "yellow", "gray")
  put(2, 3, "Chamber", "yellow")
  put(15, 3, "Ore", "yellow")
  put(29, 3, "Queue", "yellow")
  put(35, 3, "Pwr", "yellow")
  put(40, 3, "Doing", "yellow")
  local rows = h - 7
  for i = 1, math.min(rows, #machines) do
    local m, y = machines[i], 3 + i
    put(2, y, fitText(m.title, 12), "white")
    put(15, y, fitText(m.item and nice(m.item) or "-", 13), "lightGray")
    put(29, y, fitText(tostring(m.queued or 0), 5), "white")
    local pct = math.floor((m.energy or 0) * 100 + 0.5)
    put(35, y, fitText(pct .. "%", 4), pct < 10 and "red" or pct < 50 and "orange" or "lime")
    put(40, y, fitText(m.state or "...", w - 40), m.colour or "gray")
  end
  if #machines > rows then put(2, h - 3, ("...and %d more"):format(#machines - rows), "gray") end
  if #machines == 0 then put(2, 4, "No chambers yet.", "gray") end
  put(2, h - 2, fitText(total > 0 and ("To enrich: %d (%s)"):format(total, top) or "No ores in storage.", w - 2),
    total > 0 and "white" or "gray")
  put(1, h - 1, fitText(message[1], w), message[2])
  put(1, h, fitText("Ctrl+T twice, then enricher add / remove / chest", w), "gray")
  display:show()
end

local function uiLoop()
  while true do
    draw()
    repeat
      local event = os.pullEvent()
      if event == "peripheral" or event == "peripheral_detach" then display:refresh() end
    until event == "enricher_changed" or event == "peripheral" or event == "peripheral_detach"
      or event == "monitor_resize" or event == "term_resize"
  end
end

local function workLoop()
  while true do
    local ok, err = (errlog and errlog.pcall or pcall)(round)
    if not ok then say("Error: " .. tostring(err), "red") end
    os.queueEvent("enricher_changed")
    -- a chamber added from another tab starts straight away
    local timer = os.startTimer(EVERY)
    repeat
      local event, value = os.pullEvent()
    until (event == "timer" and value == timer) or event == "enricher_added"
  end
end

-- The smelter asks which ores to leave for the chambers; none while no
-- chamber is ready, so it smelts them as it always has.
local function netLoop()
  rednet.host(ENRICHER_PROTOCOL, os.getComputerLabel() or ("enricher-" .. os.getComputerID()))
  while true do
    local from, msg = rednet.receive(ENRICHER_PROTOCOL)
    if type(msg) == "table" and msg.type == "takes" then
      net.answer(from, ENRICHER_PROTOCOL, msg, { takes = taking and TAKES or {} })
    end
  end
end

---------------------------------------------------------------- commands

-- Pick from a numbered list (or type a name); nil if cancelled.
local function choose(question, options)
  for i, o in ipairs(options) do print(("%2d  %s"):format(i, o)) end
  write(question .. " ")
  local text = read()
  if text == "" then return nil end
  return options[tonumber(text)] or text
end

local function printMachines(list)
  if #list == 0 then print("No chambers yet. Add one with 'enricher add'.") end
  for i, entry in ipairs(list) do
    print(("%d  %s: %s, hopper %s"):format(i, titleOf(entry, i), entry.chamber, entry.hopper))
  end
end

local function addMachine(args)
  local list = readMachines()
  local used = {}
  for _, entry in ipairs(list) do used[entry.chamber], used[entry.hopper] = true, true end
  local function free(test)
    local out = {}
    for _, name in ipairs(findOnNetwork(test)) do
      if not used[name] then out[#out + 1] = name end
    end
    return out
  end

  local chamber, hopper = args[2], args[3]
  if not chamber or not hopper then print("Right-click a modem to see its block's name.") end
  if not chamber then
    local chambers = free(isChamber)
    if #chambers == 0 then
      print("No chamber on the network that isn't added already. Put a wired modem on it, join it to the cable and right-click it.")
      return
    end
    print("The ENRICHMENT CHAMBER (or factory):")
    chamber = #chambers == 1 and chambers[1] or choose("Which? (Enter to cancel)", chambers)
    if not chamber then return end
    if #chambers == 1 then print(chamber) end
  end
  if not hopper then
    local hoppers = free(isHopper)
    if #hoppers == 0 then
      print("No free hopper on the network. Put one on top of the chamber, pointing down, with a wired modem on it joined to the cable.")
      return
    end
    print("The HOPPER on top of it, pointing down into it:")
    hopper = choose("Which? (Enter to cancel)", hoppers)
    if not hopper then return end
  end
  if used[chamber] or used[hopper] then print("That one is already added.") return end
  for _, name in ipairs({ chamber, hopper }) do
    if not peripheral.isPresent(name) then print(name .. " isn't on the network.") return end
  end
  if not isChamber(peripheral.getType(chamber) or "") then print(chamber .. " isn't an enrichment chamber.") return end

  list[#list + 1] = { chamber = chamber, hopper = hopper }
  writeMachines(list)
  print(("Chamber %d added: %s, fed by %s."):format(#list, chamber, hopper))
  print("Put a storage input chest under it (add it in 'storage setup'): its dust comes out there.")
end

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "add" then
  addMachine(args)
  return
elseif args[1] == "remove" then
  local list = readMachines()
  local n = tonumber(args[2] or "")
  if not n or not list[n] then
    printMachines(list)
    print("Usage: enricher remove <chamber number>")
    return
  end
  local entry = table.remove(list, n)
  writeMachines(list)
  print(("Forgot %s. Empty its hopper by hand."):format(entry.chamber))
  return
elseif args[1] == "chest" then
  if not net.open("any") then
    print("I need a wired modem on the storage computer's network first (far away: an ender modem too).")
    return
  end
  work:command(args[2])
  return
elseif args[1] then
  print("Usage: enricher [add [chamber hopper] | remove <n> | chest [name|none]]")
  return
end

if not net.open("any") then
  print("I need a wired modem on the storage computer's network (far away: on my own, plus an ender modem).")
  print("Put one on me, join it to the network with cable and right-click it so it turns red.")
  return
end

display = screen.find({ scales = { MONITOR_SCALE }, fallback = term.current() })
term.clear()
if errlog then errlog.init("enricher") end
if report then report.init("enricher") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, workLoop, netLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
