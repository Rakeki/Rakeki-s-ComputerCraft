-- Smelter for the storage system. Keeps every furnace and blast furnace on
-- the storage computer's wired network busy: ores and raw metals in storage
-- go into the furnaces, fuel comes from the storage computer's fuel chest,
-- and what's smelted goes back into storage through its input chest. It can
-- also burn spare logs into charcoal, which ends up in the fuel chest.
--
--   smelter                        start (startup.lua runs this)
--   smelter charcoal <n> [wood]    make n charcoal from logs, e.g. 'smelter charcoal 256 spruce'
--                                  (no wood: the kind there's most of)
--   smelter cancel                 stop making charcoal
--
-- Needs a wired modem on the storage computer's network, furnaces joined to
-- that network by wired modems too, and the storage computer
-- (computers/storage-computer) running. It asks the storage computer for
-- everything over rednet on the cable, so it needs no wireless modem. Which
-- items get smelted is set in config.lua.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local config = fs.exists("config.lua") and require("config") or {}

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local JOB_FILE = "/.smelter_job" -- the charcoal order, kept across reboots
local EVERY = 10 -- seconds between rounds of emptying and filling the furnaces
local REPLY_WAIT = 5 -- seconds to wait for the storage computer to answer
local LOAD_MIN = 8 -- fewest items put in an empty furnace at once (what one coal smelts)
local STUCK_AFTER = 120 -- seconds a fuelled furnace may sit on an item without smelting it before it's taken back out
-- Items one of each fuel smelts, for counting what's in a fuel slot.
local FUEL_SMELTS = { ["minecraft:charcoal"] = 8, ["minecraft:coal"] = 8, ["minecraft:coal_block"] = 80 }

-- Used if config.lua is missing; see config.lua for what they mean.
local SMELT = config.smelt or { ":raw_", "_ore$", ":ancient_debris$", ":crushed_raw_" }
local SKIP = config.skip or { "_block$", "coal_ore$", "diamond_ore$", "emerald_ore$", "lapis_ore$", "redstone_ore$",
  "quartz_ore$" }

local furnaces = {} -- what the screen shows: { name, blast, input, fuel, output } per furnace
local stock -- the storage computer's last answer to 'stock'
local job -- the charcoal order: { at, wood, count, loaded, made }
local message = { "Looking for the storage computer...", "lightGray" }
local stuckSince = {} -- furnace name -> { name, count, since }: an input that hasn't gone down since
local news -- { text, colour, untilTime }: a finished order or a put-back item, shown for a minute
local noSmelt = {} -- "furnace:<item>" / "blast:<item>" found not to smelt there (until restart)

---------------------------------------------------------------- helpers

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("smelter_changed")
end

local function tell(text, colour)
  news = { text, colour, os.clock() + 60 }
  say(text, colour)
end

local function status(state, detail)
  if report then report.set(state, detail) end
end

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function isOre(name)
  for _, p in ipairs(SKIP) do
    if name:find(p) then return false end
  end
  for _, p in ipairs(SMELT) do
    if name:find(p) then return true end
  end
  return false
end

-- Logs and wood (bark on all sides) of every tree burn into charcoal;
-- nether stems don't, and aren't called logs.
local function isWood(name) return (name:find("_log$") or name:find("_wood$")) ~= nil end

local function kindOf(f) return f.blast and "blast:" or "furnace:" end

-- Every furnace on the wired network (not ones touching this computer: the
-- storage computer can't reach those). Smokers only cook food, so not them.
local function findFurnaces()
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if not sides[name] and t and t:find("furnace", 1, true) then
      list[#list + 1] = { name = name, blast = t:find("blast", 1, true) ~= nil }
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

---------------------------------------------------------------- the charcoal order

local function readJob()
  local t = files.read(JOB_FILE)
  return type(t) == "table" and t or nil
end

local function writeJob(t) files.write(JOB_FILE, t) end

local function newJob(wood, count)
  writeJob({ at = os.epoch("utc"), wood = wood, count = count, loaded = 0, made = 0 })
  os.queueEvent("smelter_order")
end

-- A round only saves or ends the order it started with: one placed
-- meanwhile (from the keyboard, or 'smelter charcoal' in another tab) wins.
local function sameJob(t)
  local cur = readJob()
  return cur ~= nil and cur.at == t.at
end

-- The log an order burns: the item it names, or the matching log there's
-- most of (wood may be part of a name, like "spruce", or nil for any).
local function pickWood(want, counts)
  if want and (counts[want] or 0) > 0 and not noSmelt["furnace:" .. want] then return want end
  local best, most = nil, 0
  for name, n in pairs(counts) do
    if isWood(name) and n > most and not noSmelt["furnace:" .. name] and (not want or name:find(want, 1, true)) then
      best, most = name, n
    end
  end
  return best
end

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

---------------------------------------------------------------- a round

local function round()
  -- the furnaces first, so the screen shows them even while the storage
  -- computer isn't answering
  local list = findFurnaces()
  if #list == 0 then
    furnaces = list
    say("No furnaces on the network: join them to it with wired modems.", "orange")
    status("waiting", "no furnaces")
    return
  end
  -- each call takes a tick, so read every furnace at once
  local reads = {}
  for _, f in ipairs(list) do
    reads[#reads + 1] = function()
      local ok, slots = pcall(peripheral.call, f.name, "list")
      slots = ok and slots or {}
      f.input, f.fuel, f.output = slots[1], slots[2], slots[3]
    end
  end
  parallel.waitForAll(table.unpack(reads))
  furnaces = list
  job = readJob()

  local reply, err = ask({ type = "stock" })
  if not reply or type(reply.counts) ~= "table" then
    -- an older storage program neither listens on the cable nor knows "stock"
    say("Storage not answering: 'install update' on it.", "orange")
    status("waiting", ("storage computer: %s"):format(err or "too old to answer"))
    return
  end
  stock = reply
  local counts, input = reply.counts, reply.input
  local order = job

  -- what's smelted goes back through the input chest (charcoal is put in
  -- the fuel chest from there)
  local blocked, problem = false, nil
  for _, f in ipairs(furnaces) do
    if f.output then
      local ok, moved = pcall(peripheral.call, f.name, "pushItems", input, 3)
      if not ok then problem, moved = tostring(moved), 0 end
      if order and f.output.name == "minecraft:charcoal" then order.made = order.made + moved end
      f.output.count = f.output.count - moved
      if f.output.count > 0 then blocked = true else f.output = nil end
    end
  end

  -- a fuelled furnace with room for its output whose input hasn't gone down
  -- from what it was left with last round isn't lit: that item doesn't
  -- smelt in it
  local now = os.clock()
  for _, f in ipairs(furnaces) do
    local s = stuckSince[f.name]
    if f.input and f.fuel and not f.output then
      if s and s.count and s.name == f.input.name and f.input.count >= s.count then
        if now - s.since > STUCK_AFTER then
          pcall(peripheral.call, f.name, "pushItems", input, 1)
          noSmelt[kindOf(f) .. f.input.name] = true
          tell(("%s doesn't smelt in %s: put it back."):format(nice(f.input.name), nice(f.name)), "orange")
          f.input, stuckSince[f.name] = nil, nil
        end
      else
        stuckSince[f.name] = { name = f.input.name, since = now } -- count: what it's left with, below
      end
    else
      stuckSince[f.name] = nil
    end
  end

  -- the charcoal order: done once it's made, or once nothing's burning and
  -- there's nothing more to burn (every input was read before its output
  -- was emptied, so all the charcoal from finished logs has been counted)
  local wood
  if order then
    wood = pickWood(order.wood, counts)
    if not order.wood then order.wood = wood end -- 'any logs': stick to one kind
    local burning = false
    for _, f in ipairs(furnaces) do
      if f.input and isWood(f.input.name) then burning = true end
    end
    if order.made >= order.count or (not burning and (order.loaded >= order.count or not wood)) then
      local where = stock.fuelChest and "the fuel chest" or "storage"
      if order.made >= order.count then
        tell(("Made %d charcoal. It's in %s."):format(order.made, where), "lime")
      else
        tell(("Ran out of %s: made %d of %d charcoal."):format(order.wood and nice(order.wood) or "logs",
          order.made, order.count), "orange")
      end
      if report then report.log(("made %d charcoal"):format(order.made)) end
      if sameJob(order) then files.delete(JOB_FILE) end
      order, wood, job = nil, nil, nil
    end
  end

  -- what to load: every ore in storage, and the logs the order still needs
  local want = {}
  for name, n in pairs(counts) do
    if n > 0 and isOre(name) then want[name] = n end
  end
  if wood then want[wood] = math.min(counts[wood], order.count - order.loaded) end
  local function canTake(f, name)
    return (want[name] or 0) > 0 and not noSmelt[kindOf(f) .. name] and not (f.blast and name == wood)
  end
  local loaded, into = 0, 0
  local function load(f, name, n)
    local r = ask({ type = "send", to = f.name, slot = 1, items = { [name] = n } })
    local got = r and r.sent and r.sent[name] or 0
    if r and r.error then problem = r.error end
    if got > 0 then
      want[name] = want[name] - got
      if f.input then f.input.count = f.input.count + got else f.input = { name = name, count = got } end
      if name == wood then order.loaded = order.loaded + got end
      loaded, into = loaded + got, into + 1
    end
  end
  local haveFuel = (stock.fuel or 0) > 0

  -- top up what's already smelting
  for _, f in ipairs(furnaces) do
    if f.input and f.input.count < 64 and canTake(f, f.input.name) then
      load(f, f.input.name, math.min(64 - f.input.count, want[f.input.name]))
    end
  end
  -- then fill empty ones: blast furnaces first (twice as fast, ores only),
  -- and plain furnaces put a charcoal order ahead of ores
  local empty = {}
  for _, f in ipairs(furnaces) do
    if not f.input and (f.fuel or haveFuel) then empty[#empty + 1] = f end
  end
  table.sort(empty, function(a, b) return a.blast and not b.blast end)
  for _, f in ipairs(empty) do
    local pick
    if wood and canTake(f, wood) then
      pick = wood
    else
      local most = 0
      for name, n in pairs(want) do
        if name ~= wood and n > most and canTake(f, name) then pick, most = name, n end
      end
    end
    if pick then
      -- share it out between the furnaces still free that can take it
      local free = 0
      for _, g in ipairs(empty) do
        if not g.input and canTake(g, pick) then free = free + 1 end
      end
      load(f, pick, math.min(64, want[pick], math.max(LOAD_MIN, math.ceil(want[pick] / free))))
    end
  end

  -- fuel: enough for everything waiting in each furnace
  local unfuelled = false
  for _, f in ipairs(furnaces) do
    if f.input then
      local have = f.fuel and f.fuel.count * (FUEL_SMELTS[f.fuel.name] or 8) or 0
      if have < f.input.count and not (f.fuel and f.fuel.count >= 64) then
        local r = ask({ type = "send", to = f.name, slot = 2, fuel = f.input.count - have, item = f.fuel and f.fuel.name })
        if r then stock.fuel = r.fuel or stock.fuel end
        for name, n in pairs(r and r.sent or {}) do
          f.fuel = { name = name, count = (f.fuel and f.fuel.count or 0) + n }
        end
        if not f.fuel then unfuelled = true end
      end
    end
  end

  if order and sameJob(order) then writeJob(order) end
  if order then job = order end

  local busy = 0
  for _, f in ipairs(furnaces) do
    if f.input then
      busy = busy + 1
      local s = stuckSince[f.name]
      if s and s.name == f.input.name then s.count = f.input.count end
    end
  end
  if problem then
    say("Couldn't move items: " .. problem, "red")
  elseif news and os.clock() < news[3] then
    say(news[1], news[2])
  elseif blocked then
    say("The storage input chest is full: smelted items are waiting in the furnaces.", "orange")
  elseif unfuelled then
    say("Out of fuel: put coal or charcoal in the fuel chest.", "orange")
  elseif loaded > 0 then
    say(("Loaded %d items into %d furnaces."):format(loaded, into))
  elseif busy == 0 then
    say("Nothing to smelt.")
  else
    say(("Smelting in %d furnaces."):format(busy))
  end
  status(busy > 0 and "running" or "idle", ("%d of %d furnaces smelting"):format(busy, #furnaces))
end

---------------------------------------------------------------- screen

-- Drawn through lib/screen.lua (a hidden window shown in one go), so it
-- doesn't flash.
local display = screen.new(term.current())
local win
local fitText = screen.fit

local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end

local function draw()
  local w, h
  win, w, h = display:frame()
  put(1, 1, (" "):rep(w), "white", "gray")
  put(2, 1, "Smelter", "yellow", "gray")
  local stat = stock and ("fuel for %d items"):format(stock.fuel or 0) or "no storage yet"
  put(w - #stat, 1, stat, "lightGray", "gray")
  local fuelX = w - 12
  put(2, 3, "Furnace", "yellow")
  put(20, 3, "Smelting", "yellow")
  put(fuelX, 3, "Fuel", "yellow")
  local rows = h - 7
  for i = 1, math.min(rows, #furnaces) do
    local f, y = furnaces[i], 3 + i
    put(2, y, fitText(nice(f.name), 17), f.blast and "orange" or "white")
    put(20, y, fitText(f.input and ("%d %s"):format(f.input.count, nice(f.input.name)) or "idle", fuelX - 21),
      f.input and "white" or "gray")
    put(fuelX, y, fitText(f.fuel and ("%d %s"):format(f.fuel.count, nice(f.fuel.name)) or "-", 12), "lightGray")
  end
  if #furnaces > rows then put(2, h - 3, ("...and %d more"):format(#furnaces - rows), "gray") end
  if #furnaces == 0 then put(2, 4, "No furnaces yet.", "gray") end
  local order = job and ("Charcoal: %d of %d made from %s"):format(job.made, job.count, job.wood and nice(job.wood) or "logs")
  put(1, h - 2, fitText(" " .. (order or "No charcoal order."), w), order and "lightBlue" or "gray")
  put(1, h - 1, fitText(message[1], w), message[2])
  put(1, h, fitText("C: make charcoal  X: cancel charcoal", w), "gray")
  display:show()
end

-- Ask which logs to burn and how much charcoal to make, from what the
-- storage computer last said it holds.
local function charcoalPrompt()
  local _, h = term.getSize()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  local woods = {}
  for name, n in pairs(stock and stock.counts or {}) do
    if isWood(name) and n > 0 then woods[#woods + 1] = { name = name, n = n } end
  end
  table.sort(woods, function(a, b) return a.n > b.n end)
  if #woods == 0 then
    print(stock and "There are no logs in storage to make charcoal from." or "The storage computer hasn't answered yet.")
    print("Press any key.")
    os.pullEvent("key")
    return
  end
  if job then print(("This replaces the order for %d charcoal."):format(job.count)) end
  print("Make charcoal from which logs?")
  for i = 1, math.min(#woods, h - 5) do
    print(("%2d  %-26s %d"):format(i, nice(woods[i].name), woods[i].n))
  end
  write(("Which? [1 = %s] "):format(nice(woods[1].name)))
  local text = read()
  local pick = woods[text == "" and 1 or tonumber(text)]
  if not pick then return end
  write(("How much charcoal? (up to %d, Enter to cancel) "):format(pick.n))
  local n = tonumber(read())
  if not n or n < 1 then return end
  n = math.floor(n)
  newJob(pick.name, n)
  job = readJob()
  say(("Making %d charcoal from %s."):format(n, nice(pick.name)), "lightBlue")
end

local function uiLoop()
  while true do
    draw()
    local event, a = os.pullEvent()
    -- char, not key: read() in the prompt would otherwise get the "c" too
    if event == "char" and (a == "c" or a == "C") then
      charcoalPrompt()
    elseif event == "char" and (a == "x" or a == "X") and job then
      files.delete(JOB_FILE)
      job = nil
      say("Charcoal order cancelled. Logs already in furnaces still burn.")
    end
  end
end

local function workLoop()
  while true do
    round()
    os.queueEvent("smelter_changed")
    -- a new charcoal order starts straight away
    local timer = os.startTimer(EVERY)
    repeat
      local event, value = os.pullEvent()
    until (event == "timer" and value == timer) or event == "smelter_order"
  end
end

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "charcoal" then
  local n = tonumber(args[2])
  if not n or n < 1 then
    print("Usage: smelter charcoal <how many> [wood, e.g. spruce]")
    return
  end
  local wood = #args >= 3 and table.concat(args, "_", 3):lower() or nil
  newJob(wood, math.floor(n))
  print(("Charcoal order saved: %d from %s."):format(math.floor(n), wood and nice(wood) or "whichever logs there are most of"))
  print("The smelter starts on it within 10 seconds, or when it's next started.")
  return
elseif args[1] == "cancel" then
  files.delete(JOB_FILE)
  print("Charcoal order cancelled. Logs already in furnaces still burn.")
  return
end

if not net.open("any") then
  print("I need a wired modem on the storage computer's network.")
  print("Put one on me, join it to the network with cable and right-click it so it turns red.")
  return
end

job = readJob()
term.clear()
if report then report.init("smelter") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, workLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
