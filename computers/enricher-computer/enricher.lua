-- Enrichment chambers for the storage system. Keeps every Mekanism
-- Enrichment Chamber (and Enriching Factory) on the storage computer's wired
-- network fed with ores from storage. An ore block gives 2 dust, 3 raw ores
-- give 4 and a raw ore block 12; the dust goes back into storage, and the
-- smelter (computers/smelter-computer) smelts it into ingots: twice the
-- ingots from ore blocks, a third more from raw ores. Gem ores come out as
-- gems (2 diamonds, 12 redstone, ...).
--
--   enricher                        start (startup.lua runs this)
--   enricher add [chamber feeder [output]]  add a chamber, what feeds it (the hopper on top, or a barrel
--                                   or chest a pipe pulls from into it) and its output chest under it
--                                   (asks for what's not given)
--   enricher remove <n>             forget chamber n (no number: list them)
--   enricher chest [name|none]      use an empty chest on the network as the work chest
--                                   (no name: pick from a list; none: stop using one)
--   enricher chest remote           far from the storage system: one ender chest both ways, or a return
--                                   one too (the chests under the chambers then empty into it)
--
-- CC can't put items into a Mekanism machine (its computer port hides the
-- slots), so each chamber has a feeder (lib/mekfeed.lua): a hopper on top,
-- or a barrel or chest that a pipe (e.g. a logistical transporter set to
-- pull) empties into it. With a work chest, the storage computer fills that once a round and
-- the enricher fills the feeders from it (lib/workchest.lua); without one,
-- it asks the storage computer to fill each feeder. Barrel and chest
-- feeders on the storage cable are registered with the storage computer
-- ('feeders'), so it doesn't take them for storage.
-- The chamber ejects its dust out of its bottom into the chest under it:
-- its output chest, which the enricher empties into storage each round, or
-- a storage input chest. This program sets that side to Output and turns
-- Auto-eject on when the chamber's security is Public.
--
-- While it's running, the smelter leaves the ores it enriches alone (it asks
-- on the 'enricher' protocol), and smelts the dust instead.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local mekfeed = require("lib.mekfeed") -- Mekanism machines fed through a hopper or barrel
local workchest = require("lib.workchest") -- the chest the storage computer fills in one go
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local config = fs.exists("config.lua") and require("config") or {}

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local ENRICHER_PROTOCOL = "enricher" -- the smelter asks which ores to leave alone on this
local EVERY = 5 -- seconds between rounds of filling the feeders
local REPLY_WAIT = 30 -- seconds to wait for the storage computer to answer (a busy one answers late)
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local BOARD_SCALES = { 1, 0.5 } -- text sizes tried on the monitor, largest first
local WIDE = 48 -- characters across from which the queue and power columns are shown

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

local machines = {} -- what the screen shows: each chamber with its feeder and how it's doing
local message = { "Looking for the storage computer...", "lightGray" }
local news -- { text, colour, untilTime }: a put-back item, shown for a minute
local waiting = {} -- item -> how many in storage to enrich, for the screen
local taking = false -- a chamber is ready, so the smelter should leave the ores alone
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

---------------------------------------------------------------- talking to storage

-- over the cable (or wireless, if that's all there is)
local storage = net.peer(STORAGE_PROTOCOL, { open = "any", wait = REPLY_WAIT })

-- Ask the storage computer something and wait for its answer: nil and why
-- if there's none.
local function ask(msg, wait)
  local reply, why = storage:ask(msg, wait)
  if reply then return reply end
  return nil, why == "no answer" and "the storage computer didn't answer" or "no storage computer answered"
end

local work = workchest.new("enricher", ask)
local chambers = mekfeed.new({ name = "enricher", single = "enrichmentChamber", factory = "EnrichingFactory",
  what = "enrichment chamber", title = "Chamber", names = NAMES, setSides = SET_SIDES, ask = ask, tell = tell })

---------------------------------------------------------------- choosing

-- The item to send next: what's already in the feeder or (a chamber has
-- one slot) the chamber, else whatever there's most of.
local function pickItem(m, avail)
  local current = mekfeed.current(m)
  if current then return current end
  local best, most = nil, 0
  for name, n in pairs(avail) do
    if n >= perOp(name) and n > most and not noEnrich[name] then best, most = name, n end
  end
  return best
end

---------------------------------------------------------------- a round

local function round()
  machines = chambers:read()
  local ready = 0
  for _, m in ipairs(machines) do
    if mekfeed.ready(m) then ready = ready + 1 end
  end
  taking = ready > 0
  if #machines == 0 then
    local free = #chambers:free()
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
  -- far away, put-backs go home through the ender chest (or the return one), and nothing
  -- is loaded without the work chest
  local useWork = work:check(reply) or work.remote
  local input, avail = work:input(reply.input), {}
  for name, n in pairs(reply.counts) do
    if takes(name) and n > (KEEP[name] or 0) then avail[name] = n - (KEEP[name] or 0) end
  end
  waiting = {}
  for name, n in pairs(avail) do waiting[name] = n end

  local unsure, problem = chambers:register(work.remote)
  -- the dust in the output chests goes home first, so they never fill up
  local _, outStuck = chambers:collect(machines, input)
  if outStuck then problem = problem or "the storage input chest is full: dust is waiting in the output chests" end
  chambers:unstick(machines, input, function(m, item)
    noEnrich[item.name] = true
    tell(("%s didn't go into %s: put it back. Is its hopper on top, or a pipe pulling from its barrel?")
      :format(nice(item.name), m.title), "orange")
  end)

  -- fill the feeders, chamber by chamber (they share what there is); with a
  -- work chest each load is noted down and fetched for all at once below
  local sent = 0
  local plan = useWork and {} or nil
  for _, m in ipairs(machines) do
    m.item = nil
    if mekfeed.ready(m) and not unsure[m.entry.feeder] then
      local name = pickItem(m, avail)
      m.item = name
      if name and (avail[name] or 0) > 0 then
        local n = math.min(mekfeed.space(m, name), avail[name], SEND_MAX)
        local per = perOp(name)
        if per > 1 then n = n - (mekfeed.inputOf(m, name) + (m.feed[name] or 0) + n) % per end
        if n > 0 and plan then
          plan[#plan + 1] = { m = m, name = name, n = n }
          avail[name] = avail[name] - n
        elseif n > 0 then
          local r = ask({ type = "send", to = m.entry.feeder, items = { [name] = n } })
          local got = r and type(r.sent) == "table" and r.sent[name] or 0
          if r and r.error then problem = r.error end
          if not r then problem = "the storage computer didn't answer while loading " .. m.title end
          mekfeed.added(m, name, got)
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
      local got = work:move(p.name, p.m.entry.feeder, nil, p.n)
      mekfeed.added(p.m, p.name, got)
      avail[p.name] = avail[p.name] + p.n - got
      sent = sent + got
    end
    work:empty(input)
  end

  -- how each chamber is doing, for the screen
  local working, broken = 0, 0
  for _, m in ipairs(machines) do
    local queued = mekfeed.inputOf(m) + (m.feedTotal or 0)
    m.queued = queued
    if not m.present then
      m.state, m.colour = "not on network", "red"
    elseif not m.feedOk then
      m.state, m.colour = "no feeder", "red"
    elseif not m.outOk then
      m.state, m.colour = "no output chest", "red"
    elseif (m.energy or 0) <= 0 then
      m.state, m.colour = "no power", "red"
    elseif mekfeed.full(m) then
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
    say("Couldn't fill a feeder: " .. problem, "red")
  elseif work.problem then
    say(("Not using the work chest: %s."):format(work.problem), "orange")
  elseif broken > 0 then
    local m
    for _, x in ipairs(machines) do
      if x.colour == "red" then m = m or x end
    end
    local why = {
      ["no feeder"] = "its hopper or barrel isn't on the network",
      ["no output chest"] = "its output chest isn't on the network",
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
-- doesn't flash. The computer's screen has the full table; a monitor
-- (enricher.monitor, or the first free one) is a status board: a tile per
-- chamber, lime idle, yellow working, orange flat out, red needs you.
local display = screen.new(term.current())
local board
local fitText = screen.fit
local LEGEND = { { "lime", "idle" }, { "yellow", "working" }, { "orange", "flat out" }, { "red", "help" } }

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
  -- a narrow monitor drops the queue and power columns, and wraps the message
  local wide = w >= WIDE
  local doingX = wide and 40 or w - 11
  local oreW = (wide and 29 or doingX) - 16
  put(1, 1, (" "):rep(w), "white", "gray")
  put(2, 1, fitText("Enrichment chambers", w - 2), "yellow", "gray")
  put(2, 3, "Chamber", "yellow")
  put(14, 3, "Ore", "yellow")
  if wide then
    put(29, 3, "Queue", "yellow")
    put(35, 3, "Pwr", "yellow")
  end
  put(doingX, 3, "Doing", "yellow")
  local footer = {}
  local function add(text, colour) footer[#footer + 1] = { text, colour } end
  add(total > 0 and ("To enrich: %d (%s)"):format(total, top) or "No ores in storage.", total > 0 and "white" or "gray")
  for _, line in ipairs(screen.wrap(message[1], w, wide and 1 or 3)) do add(line, message[2]) end
  add(wide and "Ctrl+T twice, then enricher add / remove / chest" or "Ctrl+T twice: enricher add", "gray")
  local rows = h - 4 - #footer
  for i = 1, math.min(rows, #machines) do
    local m, y = machines[i], 3 + i
    put(2, y, fitText(m.title, 11), "white")
    put(14, y, fitText(m.item and nice(m.item) or "-", oreW), "lightGray")
    if wide then
      put(29, y, fitText(tostring(m.queued or 0), 5), "white")
      local pct = math.floor((m.energy or 0) * 100 + 0.5)
      put(35, y, fitText(pct .. "%", 4), pct < 10 and "red" or pct < 50 and "orange" or "lime")
    end
    put(doingX, y, fitText(m.state or "...", w - doingX + 1), m.colour or "gray")
  end
  if #machines > rows then put(2, 4 + rows, ("...and %d more"):format(#machines - rows), "gray") end
  if #machines == 0 then put(2, 4, "No chambers yet.", "gray") end
  for i, line in ipairs(footer) do
    put(i == 1 and 2 or 1, h - #footer + i, fitText(line[1], i == 1 and w - 2 or w), line[2])
  end
  display:show()
end

local function drawBoard()
  if not board.target then return end
  local tiles, working = {}, 0
  for _, m in ipairs(machines) do
    local item = m.item or (m.inputs[1] and m.inputs[1].name)
    local colour, text = mekfeed.status(m, item and nice(item))
    if colour == "yellow" or colour == "orange" then working = working + 1 end
    tiles[#tiles + 1] = { m.title, text, colour, colour == "red" and "white" or "black" }
  end
  local key = { message[1], message[2] }
  for _, t in ipairs(tiles) do key[#key + 1] = table.concat(t, "/") end
  if board:same(table.concat(key, "|")) then return end

  local win, w, h = board:frame()
  screen.put(win, 1, 1, (" "):rep(w), "white", "gray")
  screen.put(win, 2, 1, fitText("Enricher", w - 2), "yellow", "gray")
  local count = ("%d of %d working"):format(working, #machines)
  if #count + 12 <= w then screen.put(win, w - #count, 1, count, "lightGray", "gray") end
  local left = screen.tiles(win, w, 3, h - 3, tiles)
  if left > 0 then screen.put(win, 2, h - 2, ("...and %d more"):format(left), "gray") end
  if #machines == 0 then screen.put(win, 2, 3, fitText("No chambers yet.", w - 2), "gray") end
  screen.put(win, 1, h - 1, fitText(message[1], w), message[2])
  screen.legend(win, 2, h, w - 2, LEGEND)
  board:show()
end

local function uiLoop()
  while true do
    draw()
    drawBoard()
    repeat
      local event = os.pullEvent()
      if event == "peripheral" or event == "peripheral_detach" then board:refresh() end
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

---------------------------------------------------------------- start

local args = { ... }
if chambers:command(args) then
  return
elseif args[1] == "chest" then
  if not net.open("any") then
    print("I need a wired modem on the storage computer's network first (far away: an ender modem too).")
    return
  end
  work:command(args[2])
  return
elseif args[1] then
  print("Usage: enricher [add [chamber feeder [output]] | remove <n> | chest [name|none]]")
  return
end

if not net.open("any") then
  print("I need a wired modem on the storage computer's network (far away: on my own, plus an ender modem).")
  print("Put one on me, join it to the network with cable and right-click it so it turns red.")
  return
end

board = screen.find({ setting = "enricher.monitor", scales = BOARD_SCALES, minW = 15, minH = 8 })
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
