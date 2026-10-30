-- Crafting overseer for the storage system. The storage computer
-- (computers/storage-computer) still works out what to craft for whoever
-- asked; with an overseer running it hands the queue over, and the overseer
-- shares it out between every crafting turtle (computers/crafter-turtle):
-- each job goes to a free turtle, the storage computer loads that turtle's
-- chest, the turtle crafts, and the next batch or job follows. Steps of the
-- same order run in turn (planks before sticks); different orders run side
-- by side on different turtles.
--
-- A monitor (or this computer's screen) shows the crafting turtles, the
-- queue, and for each job what's missing from storage to make it.
--
--   overseer          start (startup.lua runs this)
--   overseer clear    forget the queue (after a mix-up; the storage computer
--                     stops waiting for those crafts when it restarts)
--
-- Needs a modem that reaches the storage computer (a wired modem on its
-- cable) and the crafting turtles (wireless, or wired if they're on the
-- cable too). It opens every modem it has.
local screen = require("lib.screen") -- flicker-free drawing on the monitor and terminal
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local OVERSEER_PROTOCOL = "craft_overseer" -- the storage computer hands over jobs on this
local STORAGE_PROTOCOL = "storage" -- loading and clearing crafter chests, stock counts
local CRAFT_PROTOCOL = "storage_crafter" -- the crafting turtles take crafts on this
local QUEUE_FILE = "/.overseer_queue" -- the queue, kept across reboots
local MAX_CRAFTERS = 8 -- most crafting turtles used at once
local MAX_BATCH_OUTPUT = 384 -- most items one batch may make (6 stacks: they must fit in the turtle)
local STORAGE_WAIT = 10 -- seconds to wait for the storage computer to answer
local LOAD_WAIT = 30 -- seconds to wait for it to load a chest (it loads one at a time, so with many turtles some wait their turn)
local CRAFT_WAIT = 60 -- seconds to wait for a crafting turtle to finish one batch
local LOOK_EVERY = 15 -- seconds between looks for crafting turtles and the storage stock
local RETRY_MISSING = 15 -- seconds before a job that was short of ingredients is tried again
local GIVE_UP = 600 -- seconds a job may wait for missing ingredients before it's given up on
local MONITOR_SCALES = { 1, 0.5 } -- text sizes to try on the monitor, largest first
local KEEP_DONE = 5 -- finished jobs still listed, newest first

-- jobs: in order, each { id, plan, name, steps, left, count, grid, top, state, crafter,
-- missing, since, why }; state is "queued", "working" or "waiting" (short of ingredients).
local queue = { jobs = {} }
local done = {} -- the last few finished jobs, for the screen: { name, n, ok, why }
local outbox = {} -- jobdone reports the storage computer hasn't taken yet
local crafters = {} -- turtle id -> { chest, online, job, note }
local stock -- item -> count, from the storage computer
-- the storage computer, over the cable or by wireless
local storage = net.peer(STORAGE_PROTOCOL, { open = "any", wait = STORAGE_WAIT })
local message = { "Starting...", "lightGray" }

---------------------------------------------------------------- helpers

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function save() files.write(QUEUE_FILE, { jobs = queue.jobs, outbox = outbox }) end

local function load()
  local data = files.read(QUEUE_FILE)
  return type(data) == "table" and data or nil
end

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("overseer_changed")
end

local function status(state, detail)
  if report then report.set(state, detail) end
end

-- Ask the storage computer something; nil if it doesn't answer. Replies
-- carry the request's id, so several turtles' work can ask at once.
local function askStorage(msg, wait) return (storage:ask(msg, wait)) end

-- Tell the storage computer a job is finished (or given up on), now or as
-- soon as it answers again.
local function finishJob(job, ok, why)
  outbox[#outbox + 1] = { type = "jobdone", job = job.id, ok = ok, why = why }
  table.insert(done, 1, { name = job.name, n = job.steps * job.count, ok = ok, why = why })
  while #done > KEEP_DONE do table.remove(done) end
  save()
end

local function flushOutbox()
  while #outbox > 0 do
    local msg = outbox[1]
    if not askStorage({ type = msg.type, job = msg.job, ok = msg.ok, why = msg.why }) then return false end
    table.remove(outbox, 1)
    save()
  end
  return true
end

local function removeJob(job)
  for i, j in ipairs(queue.jobs) do
    if j == job then
      table.remove(queue.jobs, i)
      return
    end
  end
end

-- A job failed: the rest of its order needed it, so those go too.
local function failPlan(job, why)
  removeJob(job)
  finishJob(job, false, why)
  for i = #queue.jobs, 1, -1 do
    local other = queue.jobs[i]
    if other.plan == job.plan and other.state ~= "working" then
      table.remove(queue.jobs, i)
      finishJob(other, false, "an earlier step failed")
    end
  end
  save()
end

---------------------------------------------------------------- what's missing

-- Going down the queue, what each job still needs from storage beyond
-- what the jobs before it use up (and plus what they make): item -> short.
local function workOutMissing()
  if not stock then return end
  local avail = {}
  for name, n in pairs(stock) do avail[name] = n end
  for _, job in ipairs(queue.jobs) do
    local need = {}
    for _, item in pairs(job.grid) do need[item] = (need[item] or 0) + job.left end
    local short
    for item, n in pairs(need) do
      local have = math.max(0, avail[item] or 0)
      if have < n then
        short = short or {}
        short[item] = n - have
      end
      avail[item] = (avail[item] or 0) - n
    end
    job.short = short
    avail[job.name] = (avail[job.name] or 0) + job.left * job.count
  end
end

---------------------------------------------------------------- the work

-- The next job a free turtle may start: the first one queued (or waiting
-- long enough) whose earlier steps in the same order are all done.
local function nextJob()
  local busyPlans = {}
  for _, job in ipairs(queue.jobs) do
    local ready = job.state == "queued" or (job.state == "waiting" and os.clock() - (job.tried or 0) >= RETRY_MISSING)
    if ready and not busyPlans[job.plan] then return job end
    busyPlans[job.plan] = true -- anything later in this order waits for this one
  end
end

-- Run one job on crafting turtle id, a batch at a time.
local function runJob(id, job)
  local c = crafters[id]
  job.state, job.crafter = "working", id
  c.job = job
  save()
  os.queueEvent("overseer_changed")
  while job.left > 0 do
    local want = math.min(job.left, 64, math.floor(MAX_BATCH_OUTPUT / job.count))
    local r = askStorage({ type = "load", crafter = id, grid = job.grid, steps = want }, LOAD_WAIT)
    if not r then
      job.state, job.crafter, job.tried = "queued", nil, os.clock()
      say("The storage computer isn't answering.", "orange")
      return
    end
    if (r.steps or 0) == 0 then
      -- short of something: wait (the screen says what), or give up after a while
      job.since = job.since or os.clock()
      job.missing, job.why = r.missing, r.error
      if os.clock() - job.since > GIVE_UP then
        failPlan(job, "still short of ingredients: " .. tostring(r.error))
        say(("Gave up on %s: %s."):format(nice(job.name), tostring(r.error)), "red")
      else
        job.state, job.crafter, job.tried = "waiting", nil, os.clock()
      end
      save()
      return
    end
    job.since, job.missing, job.why = nil, nil, nil
    c.note = ("crafting %d %s"):format(r.steps * job.count, nice(job.name))
    os.queueEvent("overseer_changed")
    local craft = { type = "craft", steps = r.steps, grid = job.grid }
    local reply = net.ask(id, CRAFT_PROTOCOL, craft, { wait = CRAFT_WAIT,
      match = function(msg) return msg.type == "crafted" and msg.id == craft.id end })
    askStorage({ type = "clear", crafter = id }, LOAD_WAIT)
    c.note = nil
    if not reply then
      -- the turtle went quiet: someone else can have the job
      c.online = false
      job.state, job.crafter = "queued", nil
      say(("Crafting turtle #%d didn't answer: it's left out until it does."):format(id), "orange")
      save()
      return
    end
    if (reply.made or 0) == 0 or (reply.item and reply.item ~= job.name) then
      local why = (reply.made or 0) == 0 and (reply.error or "the recipe didn't work")
        or ("turtle #%d made %s instead"):format(id, nice(reply.item))
      failPlan(job, why)
      say(("Couldn't craft %s: %s."):format(nice(job.name), why), "red")
      return
    end
    job.left = job.left - r.steps
    save()
  end
  removeJob(job)
  finishJob(job, true)
  say(("Crafted %d %s on turtle #%d."):format(job.steps * job.count, nice(job.name), id), "lime")
  if report then report.log(("crafted %d %s"):format(job.steps * job.count, nice(job.name))) end
end

-- One of these per crafting turtle slot: the slot's turtle takes jobs.
local function worker(slot)
  return function()
    while true do
      local ids = {}
      for id, c in pairs(crafters) do
        if c.online then ids[#ids + 1] = id end
      end
      table.sort(ids)
      local id = ids[slot]
      local job = id and not crafters[id].job and nextJob()
      if job then
        runJob(id, job)
        crafters[id].job = nil
        flushOutbox()
        os.queueEvent("overseer_changed")
      else
        local timer = os.startTimer(5)
        repeat
          local event, value = os.pullEvent()
        until event == "overseer_work" or (event == "timer" and value == timer)
      end
    end
  end
end

-- Find the crafting turtles (those that answer and that the storage
-- computer has a chest for), count the stock, and work out what's missing.
local function lookLoop()
  while true do
    flushOutbox()
    local r = askStorage({ type = "crafters" })
    if r then
      local chests = r.crafters or {}
      local seen, sharedTaken = {}, false
      local online = { rednet.lookup(CRAFT_PROTOCOL) }
      table.sort(online)
      for _, id in ipairs(online) do
        -- the chest picked in 'storage setup' goes to one turtle without a chest of its own
        local chest = chests[id]
        if not chest and r.shared and not sharedTaken then chest, sharedTaken = r.shared, true end
        if chest then
          seen[id] = true
          crafters[id] = crafters[id] or {}
          crafters[id].chest, crafters[id].online = chest, true
        end
      end
      for id, c in pairs(crafters) do
        if not seen[id] and not c.job then crafters[id] = nil end
      end
      local s = askStorage({ type = "stock" })
      if s and s.counts then stock = s.counts end
      workOutMissing()
      local n = 0
      for _ in pairs(crafters) do n = n + 1 end
      local problem
      if #queue.jobs > 0 and n == 0 then problem = "no crafting turtle is running 'crafter' with a chest" end
      askStorage({ type = "problem", text = problem })
      if problem then say("No crafting turtles: " .. problem .. ".", "orange")
      elseif message[1] == "Starting..." or message[1]:find("storage computer", 1, true) then
        say(("Ready: %d crafting turtles."):format(n), "lime")
      end
    else
      say("Looking for the storage computer: is it running 'storage'?", "orange")
    end
    status(#queue.jobs > 0 and "crafting" or "idle", ("%d jobs queued"):format(#queue.jobs))
    os.queueEvent("overseer_work")
    os.queueEvent("overseer_changed")
    sleep(LOOK_EVERY)
  end
end

-- Jobs from the storage computer.
local function netLoop()
  rednet.host(OVERSEER_PROTOCOL, os.getComputerLabel() or ("overseer-" .. os.getComputerID()))
  while true do
    local from, msg = rednet.receive(OVERSEER_PROTOCOL)
    if type(msg) == "table" and msg.type == "jobs" and type(msg.jobs) == "table" then
      local have = {}
      for _, job in ipairs(queue.jobs) do have[job.id] = true end
      local added = 0
      for _, j in ipairs(msg.jobs) do
        if type(j) == "table" and type(j.grid) == "table" and tonumber(j.steps) and not have[j.id] then
          queue.jobs[#queue.jobs + 1] = { id = j.id, plan = j.plan, name = j.name, steps = j.steps, left = j.steps,
            count = j.count or 1, grid = j.grid, top = j.top, state = "queued" }
          added = added + 1
        end
      end
      storage.id = from
      save()
      net.answer(from, OVERSEER_PROTOCOL, msg, { ok = true })
      if added > 0 then say(("The storage computer sent %d crafts."):format(added), "lightBlue") end
      workOutMissing()
      os.queueEvent("overseer_work")
    elseif type(msg) == "table" and msg.type == "ping" then
      net.answer(from, OVERSEER_PROTOCOL, msg, { jobs = #queue.jobs })
    end
  end
end

---------------------------------------------------------------- screen

local display = screen.find({ setting = "overseer.monitor", scales = MONITOR_SCALES, minW = 39, minH = 15,
  fallback = term.current() })
local put, fit = screen.put, screen.fit

local function missingText(short)
  local parts = {}
  for item, n in pairs(short or {}) do parts[#parts + 1] = ("%d %s"):format(n, nice(item)) end
  table.sort(parts)
  return table.concat(parts, ", ")
end

local function draw()
  if not display.target then return end
  local win, w, h = display:frame()
  put(win, 1, 1, (" "):rep(w), "white", "gray")
  put(win, 2, 1, "Crafting", "yellow", "gray")
  local head = ("%d jobs"):format(#queue.jobs)
  put(win, w - #head, 1, head, "lightGray", "gray")

  -- the crafting turtles
  local ids = {}
  for id in pairs(crafters) do ids[#ids + 1] = id end
  table.sort(ids)
  put(win, 2, 3, "Turtles", "yellow")
  local y = 4
  for _, id in ipairs(ids) do
    if y > 3 + math.min(MAX_CRAFTERS, math.floor(h / 3)) then break end
    local c = crafters[id]
    local text = not c.online and "not answering" or c.note or (c.job and ("loading " .. nice(c.job.name))) or "idle"
    put(win, 2, y, fit(("#%d %s"):format(id, text), w - 2), not c.online and "red" or c.job and "lightBlue" or "gray")
    y = y + 1
  end
  if #ids == 0 then
    put(win, 2, y, "None yet: start 'crafter' on a crafty turtle.", "orange")
    y = y + 1
  end

  -- the queue, with what each job is short of
  y = y + 1
  put(win, 2, y, "Queue", "yellow")
  y = y + 1
  local rows = h - 2 - y
  local shown = 0
  for _, job in ipairs(queue.jobs) do
    if shown >= rows then break end
    local what = ("%d %s"):format(job.left * job.count, nice(job.name))
    local state, colour
    if job.state == "working" then
      state, colour = ("on #%d"):format(job.crafter or 0), "lightBlue"
    elseif job.state == "waiting" then
      state, colour = "short", "orange"
    elseif job.short then
      state, colour = "missing", "orange"
    else
      state, colour = "queued", "white"
    end
    put(win, 2, y, fit(what, w - #state - 3), "white")
    put(win, w - #state, y, state, colour)
    y, shown = y + 1, shown + 1
    local short = job.state == "waiting" and job.missing or job.short
    if short and shown < rows then
      put(win, 4, y, fit("needs " .. missingText(short), w - 4), "orange")
      y, shown = y + 1, shown + 1
    end
  end
  if #queue.jobs == 0 then
    local last = done[1]
    put(win, 2, y, last and fit(("Nothing queued. Last: %d %s%s"):format(last.n, nice(last.name),
      last.ok and "" or (" (failed: " .. tostring(last.why) .. ")")), w - 2) or "Nothing queued.",
      last and not last.ok and "red" or "gray")
  elseif #queue.jobs > shown then
    put(win, 2, h - 2, "...and more", "gray")
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

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "clear" then
  files.delete(QUEUE_FILE)
  print("Queue forgotten.")
  return
end

if not net.open("any") then
  print("I need a modem: a wired one on the storage computer's cable, and")
  print("wireless if the crafting turtles talk by wireless.")
  return
end

local saved = load()
if saved then
  queue.jobs, outbox = saved.jobs or {}, saved.outbox or {}
  -- a batch cut short by the reboot: its chest gets cleared before the next one
  for _, job in ipairs(queue.jobs) do
    if job.state == "working" then job.state, job.crafter = "queued", nil end
    job.tried, job.since = nil, nil -- os.clock times, which start again at 0
  end
end

local workers = {}
for slot = 1, MAX_CRAFTERS do workers[slot] = worker(slot) end
term.clear()
if report then report.init("craft overseer") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, netLoop, lookLoop,
  report and report.loop or function() while true do sleep(3600) end end, table.unpack(workers))
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
