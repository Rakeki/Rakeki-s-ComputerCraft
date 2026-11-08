-- Craft overseer: the storage system's recipe server. It knows every
-- recipe (recipes.lua, a modpack's pack_recipes.lua, recipes taught with
-- 'crafter learn', and what the factory's machines can make), plans every
-- craft from the storage computer's stock, and shares the jobs out between
-- every crafting turtle (computers/crafter-turtle): each job goes to a free
-- turtle, the storage computer loads that turtle's chest, the turtle crafts,
-- and the next batch or job follows. Steps of the same order run in turn
-- (planks before sticks); different orders run side by side on different
-- turtles. The storage computer only keeps items: it knows no recipes.
--
-- Programs ask it on the craft_overseer protocol (lib/crafts.lua): how many
-- of something could be made ("canmake"), to have things made ("prepare"),
-- the craft terminal's list and orders ("craftable", "craft"), recipes using
-- an item ("recipes", the essence farm), new recipes ("learn"), and the
-- factory's machines' recipes and finished jobs ("makes", "jobdone").
--
-- A monitor (or this computer's screen) shows the crafting turtles, the
-- queue, and for each job what's missing from storage to make it. Its Craft
-- tab lists everything that can be made and orders it into storage: tap a
-- row, pick how many, Craft (on the terminal: type to search, Enter, a number).
--
--   overseer          start (startup.lua runs this)
--   overseer clear    forget the queue (after a mix-up)
--   overseer hub [name]  use the ender chest on my cable (or the one named) as
--                     the hub for crafting turtles far from the storage system
--   overseer hub off  stop using it
--
-- Needs a modem that reaches the storage computer (a wired modem on its
-- cable), and a wireless or ender modem for the turtles and programs that
-- ask it about crafting (builders, the village builder, the cannon feeder).
-- It opens every modem it has.
--
-- Far from the storage system: put an ender chest on this computer's own
-- cable, its twin on the storage cable, and each crafting turtle's barrel
-- on this cable too (the hub). The storage computer loads the twin, this
-- computer moves each batch on to the turtle's barrel and the results back,
-- one batch through the ender chest at a time. Turtles here ask this computer
-- which barrel is theirs (the "claim" request, like the storage computer's).
local screen = require("lib.screen") -- flicker-free drawing on the monitor and terminal
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local claim = require("lib.claim") -- tells the storage computer which chest is my ender chest's twin
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local crafting = require("crafting") -- plans: which recipes make what, from what's stored
crafting.load(fs.exists("recipes.lua") and require("recipes") or {})
-- a modpack's recipes, made with tools/recipes.mjs (see the README)
local packRecipes, packError = 0, nil
if fs.exists("pack_recipes.lua") then
  print("Loading the modpack's recipes...")
  local okP, pack = pcall(require, "pack_recipes")
  if okP and type(pack) == "table" then
    packRecipes = crafting.loadPack(pack)
    print(("Loaded %d modpack recipes."):format(packRecipes))
  else
    packError = tostring(pack)
    print("pack_recipes.lua didn't load: " .. packError)
  end
end

local OVERSEER_PROTOCOL = "craft_overseer" -- programs ask me about crafting on this (lib/crafts.lua)
local STORAGE_PROTOCOL = "storage" -- loading and clearing crafter chests, stock counts
local CRAFT_PROTOCOL = "storage_crafter" -- the crafting turtles take crafts on this
local QUEUE_FILE = "/.overseer_queue" -- the queue, kept across reboots
local BARRELS_FILE = "/.overseer_barrels" -- turtle id -> its barrel on my cable (hub only)
local HUB_SETTING = "overseer.hub" -- names the ender chest, when there's more than one on my cable
local CLAIM_TYPES = { "chest", "barrel", "shulker_box", "crate" } -- what a turtle's barrel can be
local HUB_CLAIM_EVERY = 300 -- seconds between checks that the storage computer still has my ender chest
local CLAIM_IDLE = 30 -- seconds a turtle finding its barrel may go quiet before I take my item back
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
local MACHINE_PROTOCOL = "factory" -- a factory computer takes machine jobs (infusing, essence) on this
local MACHINE_WAIT = 5 -- seconds to wait for it to take one
local MACHINE_FORGET = 300 -- seconds a machine's recipes are kept after it last sent them
local STOCK_FRESH = 2 -- seconds a stock count from the storage computer is planned with before asking again
local REACH_EVERY = 10 -- seconds the list of what could be made at all is kept before working it out again
local VIEW_EVERY = 30 -- fewest seconds between recounts of the craft terminal's list
local VIEW_REST = 3 -- and at least this many times as long as the last count took (a modpack's take a minute)
local VIEW_MAX = 999 -- the list counts no higher than this (fewer tries per item)
local VIEW_KEEP = 120 -- seconds the list is kept worked out after a craft terminal last asked for it
local ORDER_EVERY = 2 -- seconds between sending a craft terminal what's been made of its order
local ORDER_MAX = 9999 -- most of one item a craft terminal (or my own Craft page) may order at once
local ORDER_STACK = 64 -- how many an order on my Craft page starts at
local VIEW_TICK = 5 -- seconds between redraws of my Craft page (the list and what's being made)

-- jobs: in order, each { id, plan, name, steps, left, count, grid, top, via, state, crafter,
-- missing, since, why }; state is "queued", "working" or "waiting" (short of ingredients),
-- or for a machine's job (via) "machine" until it's sent, then "sent".
-- top: the job that makes what was asked for (how many), counted as being made until it's done.
local queue = { jobs = {}, plans = 0 }
local done = {} -- the last few finished jobs, for the screen: { name, n, ok, why }
local runId = os.epoch("utc") -- makes job ids unique across restarts
local jobCount = 0
local makers = {} -- via -> { id, at, key, n }: factory computers whose machines run some recipes
local orders = {} -- a craft terminal's orders sent to its chest: name .. "@" .. id -> { name, who, want, sent }
local view = { list = {}, ready = false, wanted = -math.huge } -- the craft terminal's list of what can be made
local craftProblem -- why crafting is stuck right now (nil when it isn't), for whoever waits on it
local crafters = {} -- turtle id -> { chest, online, job, note, hub = true for a barrel on my cable }
local stock -- item -> count, from the storage computer
local stockAt = -math.huge -- when it was counted
local patterns = {} -- item -> true: an ME/RS system behind the storage computer can craft it itself
local syscrafting = {} -- item -> how many that system is making
-- the ender chest on my cable: name, ready once the storage computer has
-- its twin, why not, busy while a batch passes through it
local hub = { busy = false }
local barrels = {} -- turtle id -> its barrel on my cable (saved in BARRELS_FILE)
local MY_ID = os.getComputerID() -- the storage computer keeps the ender chest's twin as my crafter chest
-- the storage computer, over the cable or by wireless
local storage = net.peer(STORAGE_PROTOCOL, { open = "any", wait = STORAGE_WAIT })
local message = { "Starting...", "lightGray" }

---------------------------------------------------------------- helpers

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function save() files.write(QUEUE_FILE, { jobs = queue.jobs, plans = queue.plans }) end

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

-- A job is finished (or given up on): on the screen's list of the last few.
local function finishJob(job, ok, why)
  table.insert(done, 1, { name = job.name, n = job.steps * job.count, ok = ok, why = why })
  while #done > KEEP_DONE do table.remove(done) end
  save()
end

local function removeJob(job)
  for i, j in ipairs(queue.jobs) do
    if j == job then
      table.remove(queue.jobs, i)
      return
    end
  end
end

-- A job failed: the rest of its order needed it, so those go too (a
-- machine already making its part is told to stop).
local function failPlan(job, why)
  removeJob(job)
  finishJob(job, false, why)
  for i = #queue.jobs, 1, -1 do
    local other = queue.jobs[i]
    if other.plan == job.plan and other.state ~= "working" then
      table.remove(queue.jobs, i)
      local maker = other.via and other.state == "sent" and makers[other.via]
      if maker then rednet.send(maker.id, { type = "cancel", job = other.id }, MACHINE_PROTOCOL) end
      finishJob(other, false, "an earlier step failed")
    end
  end
  save()
  os.queueEvent("overseer_changed")
end

---------------------------------------------------------------- the hub

local function isInventory(name)
  local ok, yes = pcall(peripheral.hasType, name, "inventory")
  return ok and yes
end

local function isEnder(name)
  local t = peripheral.getType(name)
  return t ~= nil and t:find("ender", 1, true) ~= nil
end

local function enderChests()
  local found = {}
  for _, name in ipairs(peripheral.getNames()) do
    if isEnder(name) and isInventory(name) then found[#found + 1] = name end
  end
  return found
end

-- One batch at a time passes through the ender chest: everything that
-- puts something in it or takes something out runs inside withHub.
local function withHub(fn)
  while hub.busy do os.pullEvent("overseer_hub") end
  hub.busy = true
  local res = table.pack(pcall(fn))
  hub.busy = false
  os.queueEvent("overseer_hub")
  if not res[1] then error(res[2], 0) end
  return table.unpack(res, 2, res.n)
end

-- Have the storage computer put away whatever is in the ender chest.
local function clearHub() askStorage({ type = "clear", crafter = MY_ID }, LOAD_WAIT) end

-- Move everything from one inventory on my cable to another. Returns
-- whether it all went, and whether anything did.
local function moveAll(from, to)
  local ok, list = pcall(peripheral.call, from, "list")
  if not ok then return false, false end
  local all, moved = true, false
  for slot, item in pairs(list) do
    local okM, n = pcall(peripheral.call, from, "pushItems", to, slot)
    n = okM and n or 0
    if n > 0 then moved = true end
    if n < item.count then all = false end
  end
  return all, moved
end

-- Put a turtle's barrel away through the ender chest (in withHub).
local function emptyBarrel(barrel)
  for _ = 1, 3 do
    local all, moved = moveAll(barrel, hub.name)
    if moved then clearHub() end
    if all then return true end
  end
  return false
end

-- Have the storage computer load the ender chest with a batch, then move
-- it into the turtle's barrel. Returns the storage computer's answer, as
-- for a chest on its own cable.
local function loadBarrel(barrel, grid, steps)
  return withHub(function()
    if not emptyBarrel(barrel) then return { steps = 0, error = "the turtle's barrel won't empty: is storage full?" } end
    local r = askStorage({ type = "load", crafter = MY_ID, grid = grid, steps = steps }, LOAD_WAIT)
    if r and (r.steps or 0) == 0 and tostring(r.error):find("has no chest here", 1, true) then
      hub.ready, hub.nextClaim = false, 0 -- the storage computer forgot my ender chest: claim it again
    end
    if r and (r.steps or 0) > 0 and not moveAll(hub.name, barrel) then
      moveAll(barrel, hub.name)
      clearHub()
      return { steps = 0, error = "the turtle's barrel didn't take all the ingredients" }
    end
    return r
  end)
end

-- Tell the storage computer which chest on its cable is my ender chest's
-- twin (it drops an item into each one it could be until it turns up here).
local function claimHub()
  if not peripheral.isPresent(hub.name) then
    hub.ready, hub.why = false, ("my ender chest %s isn't on my cable"):format(hub.name)
    hub.nextClaim = os.clock() + 60
    return
  end
  local ok, why = withHub(function() return claim.chest(askStorage, "hub", hub.name) end)
  hub.ready = ok == true
  if ok then
    hub.why, hub.nextClaim = nil, os.clock() + HUB_CLAIM_EVERY
  else
    hub.why = ok == false and ("the storage computer can't find my ender chest's twin: " .. why)
      or "no storage computer answered about my ender chest"
    hub.nextClaim = os.clock() + 60
  end
end

---------------------------------------------------------------- turtles finding their barrel

-- A crafting turtle here asks which barrel on my cable is in front of it,
-- the way turtles ask the storage computer (lib/claim.lua): I put one item
-- from the ender chest in each barrel it could be until it sees it arrive.
local claims = {} -- turtle id -> { candidates, i, at = barrel the item is in, marker, last }

local function claimable(name)
  if name == hub.name or isEnder(name) or not isInventory(name) then return false end
  local t = peripheral.getType(name) or ""
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

-- A barrel a turtle is crafting from right now: no probe item goes in it.
local function inUse(name)
  for _, c in pairs(crafters) do
    if c.hub and c.chest == name and c.job then return true end
  end
  return false
end

-- Take the probe item back into the ender chest.
local function takeMarker(c)
  if not c.at then return end
  local at, marker = c.at, c.marker
  c.at = nil
  withHub(function()
    local ok, list = pcall(peripheral.call, at, "list")
    for slot, item in pairs(ok and list or {}) do
      if item.name == marker then
        pcall(peripheral.call, at, "pushItems", hub.name, slot, 1)
        return
      end
    end
  end)
end

-- Put one item the barrel doesn't hold into it (in withHub), borrowed from
-- storage if the ender chest has none. Its name, or nil and why.
-- Never the item another turtle's search is using (its probe could land
-- in this turtle's barrel and be taken for this one's).
local function probeInto(barrel, has, from)
  local used = {}
  for id, other in pairs(claims) do
    if id ~= from and other.marker and os.clock() - (other.last or 0) <= CLAIM_IDLE then used[other.marker] = true end
  end
  local function pick()
    local ok, list = pcall(peripheral.call, hub.name, "list")
    for slot, item in pairs(ok and list or {}) do
      if not has[item.name] and not used[item.name] then return slot, item.name end
    end
  end
  local slot, marker = pick()
  if not slot then
    local want
    for name, n in pairs(stock or {}) do
      if n > 0 and not has[name] and not used[name] then want = name break end
    end
    if not want then return nil, "the storage system is empty: I need one item to find your barrel with" end
    local r = askStorage({ type = "load", crafter = MY_ID, grid = { want }, steps = 1 }, LOAD_WAIT)
    if not (r and (r.steps or 0) > 0) then return nil, "the storage computer couldn't lend me an item to find your barrel with" end
    slot, marker = pick()
    if not slot then return nil, "the item the storage computer lent me didn't arrive" end
  end
  local ok, n = pcall(peripheral.call, hub.name, "pushItems", barrel, slot, 1)
  if ok and n and n > 0 then return marker end
end

local function endClaim(from)
  claims[from] = nil
  withHub(clearHub)
end

local function nextProbe(from, c)
  c.last = os.clock()
  while c.i < #c.candidates do
    c.i = c.i + 1
    local name = c.candidates[c.i]
    local ok, list = pcall(peripheral.call, name, "list")
    if ok and not inUse(name) then
      local has = {}
      for _, item in pairs(list) do has[item.name] = true end
      local marker, why = withHub(function() return probeInto(name, has, from) end)
      if marker then
        c.at, c.marker = name, marker
        return { probe = marker }
      elseif why then
        endClaim(from)
        return { ok = false, error = why }
      end
    end
  end
  endClaim(from)
  if barrels[from] then
    barrels[from] = nil
    files.write(BARRELS_FILE, barrels)
  end
  return { ok = false, error = "your barrel isn't on my cable" }
end

--   { type = "claim", role = "crafter", items = its list() } -> { ok, chest } / { probe = item } / { ok = false, error }
--   { type = "claim", role, seen = true or false }           -> the same answers
local function claimBarrel(from, msg)
  if not hub.name then return { ok = false, error = "I have no ender chest of my own: use the storage cable" } end
  -- a turtle that starts with me mustn't go to the storage computer just
  -- because I haven't linked my ender chest yet
  if not hub.ready and os.clock() >= (hub.nextClaim or 0) then claimHub() end
  if not hub.ready then return { ok = false, error = hub.why or "the storage computer hasn't found my ender chest yet" } end
  local c = claims[from]
  if msg.seen ~= nil then
    if not c then return { ok = false, error = "I lost track of where I was: try again" } end
    takeMarker(c)
    if not msg.seen then return nextProbe(from, c) end
    local name = c.candidates[c.i]
    endClaim(from)
    for id, b in pairs(barrels) do
      if b == name then barrels[id] = nil end
    end
    barrels[from] = name
    files.write(BARRELS_FILE, barrels)
    say(("Crafting turtle #%d's barrel is %s."):format(from, name), "lime")
    return { ok = true, chest = name }
  end
  if c then
    takeMarker(c)
    endClaim(from)
  end
  -- the barrel I already have for it, if it still holds what the turtle sees
  local mine = barrels[from]
  if mine then
    local ok, list = pcall(peripheral.call, mine, "list")
    if ok and sameItems(list, msg.items) then return { ok = true, chest = mine } end
  end
  -- every barrel it could be: those holding just what the turtle sees
  -- first (often only one), other turtles' barrels last
  local taken = {}
  for id, b in pairs(barrels) do
    if id ~= from then taken[b] = true end
  end
  local candidates, rank = {}, {}
  for _, name in ipairs(peripheral.getNames()) do
    if claimable(name) then
      local ok, list = pcall(peripheral.call, name, "list")
      if ok then
        candidates[#candidates + 1] = name
        rank[name] = (sameItems(list, msg.items) and 0 or 2) + (taken[name] and 1 or 0)
      end
    end
  end
  table.sort(candidates, function(a, b)
    if rank[a] ~= rank[b] then return rank[a] < rank[b] end
    return a < b
  end)
  c = { candidates = candidates, i = 0 }
  claims[from] = c
  return nextProbe(from, c)
end

-- Claims from turtles here, beside netLoop (a claim can wait its turn at
-- the ender chest, and the storage computer's jobs mustn't wait for it).
local function claimLoop()
  while true do
    local from, msg = rednet.receive(OVERSEER_PROTOCOL, 5)
    if from and type(msg) == "table" and msg.type == "claim" then
      net.answer(from, OVERSEER_PROTOCOL, msg, claimBarrel(from, msg))
    end
    -- a turtle that went quiet mid-search: take my item back
    for id, c in pairs(claims) do
      if os.clock() - (c.last or 0) > CLAIM_IDLE then
        takeMarker(c)
        endClaim(id)
      end
    end
  end
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

---------------------------------------------------------------- planning

-- The stock to plan with: the storage computer's count, at most
-- STOCK_FRESH old (it answers stock quickly: it's a count of its cache).
-- Also what its ME/RS system has patterns for. False if it didn't answer.
local function freshStock()
  if stock and os.clock() - stockAt < STOCK_FRESH then return true end
  local s = askStorage({ type = "stock" })
  if not (s and s.counts) then return stock ~= nil end
  stock, stockAt = s.counts, os.clock()
  patterns = {}
  for _, name in ipairs(type(s.patterns) == "table" and s.patterns or {}) do patterns[name] = true end
  syscrafting = type(s.syscrafting) == "table" and s.syscrafting or {}
  return true
end

-- How many of name are being made for whoever asked: the queue's orders
-- of it, and the ME/RS system's crafts.
local function pending(name)
  local n = syscrafting[name] or 0
  for _, job in ipairs(queue.jobs) do
    if job.top and job.name == name then n = n + job.top end
  end
  return n
end

local function pendingAll()
  local out = {}
  for name, n in pairs(syscrafting) do out[name] = n end
  for _, job in ipairs(queue.jobs) do
    if job.top then out[job.name] = (out[job.name] or 0) + job.top end
  end
  return out
end

-- Every plain item stored, minus what queued jobs will use up, plus what
-- they'll make: what a new plan can count on.
local function planningStock()
  local avail = {}
  for name, n in pairs(stock or {}) do avail[name] = n end
  for _, job in ipairs(queue.jobs) do
    for _, item in pairs(job.grid) do avail[item] = (avail[item] or 0) - job.left end
    avail[job.name] = (avail[job.name] or 0) + job.left * job.count
  end
  return avail
end

-- What could be made at all from what's stored (crafting.reachable): plans
-- only try those, which keeps thousands of modded recipes quick.
local reachCache, reachAt = nil, -math.huge
local function reachNow(avail)
  if not reachCache or os.clock() - reachAt > REACH_EVERY then
    reachCache, reachAt = crafting.reachable(avail or planningStock()), os.clock()
  end
  return reachCache
end

local function nameOf(item) return nice(item) end

-- Have count of name made, or as many as can be: by the ME/RS system if it
-- has a pattern, else by queueing crafts. Returns how many it's making (and
-- why not all of them), or false and why. Plans with fresh stock.
local function orderCraft(name, count)
  if not freshStock() then return false, "the storage computer isn't answering" end
  if patterns[name] then
    local r = askStorage({ type = "syscraft", item = name, count = count })
    if not r then return false, "the storage computer isn't answering" end
    if not r.ok then return false, r.error or "the ME/RS system wouldn't craft it" end
    syscrafting[name] = (syscrafting[name] or 0) + count
    return count
  end
  if not crafting.canMake(name) then return false, "no recipe for it" end
  local avail = planningStock()
  local reach = reachNow(avail)
  local jobs, why = crafting.plan(name, count, avail, reach), nil
  if not jobs then
    -- make what we can, so a build gets as far as it can meanwhile
    local can = crafting.craftable(name, avail, count - 1, reach)
    if can == 0 then
      local none = crafting.missing(name, avail, reach)
      if type(none) == "table" then none = none[1] end
      if type(none) == "string" then return false, "no " .. (none:sub(1, 1) == "#" and none or nameOf(none)) .. " stored, and no way to make it" end
      return false, "not enough to make it from"
    end
    count, why = can, ("only enough to make %d"):format(can)
    jobs = crafting.plan(name, count, avail, reach)
    if not jobs then return false, "not enough to make it from" end
  end
  queue.plans = (queue.plans or 0) + 1
  for _, j in ipairs(jobs) do
    jobCount = jobCount + 1
    queue.jobs[#queue.jobs + 1] = { id = ("%d:%d"):format(runId, jobCount), plan = queue.plans, name = j.name,
      steps = j.steps, left = j.steps, count = j.recipe.count, grid = j.grid, via = j.recipe.via,
      state = j.recipe.via and "machine" or "queued" }
  end
  queue.jobs[#queue.jobs].top = count -- the item asked for: counted as being made until it's made
  reachCache = nil
  save()
  workOutMissing()
  os.queueEvent("overseer_work")
  os.queueEvent("overseer_changed")
  return count, why
end

-- Start crafting so there'll be n of each item (stored and being made
-- count): { crafting = { [name] = n being made }, cantCraft = { [name] = why } }.
local function prepare(items)
  local making, cant = {}, {}
  if not freshStock() then
    for name in pairs(items) do cant[name] = "the storage computer isn't answering" end
    return making, cant
  end
  for name, n in pairs(items) do
    if type(name) == "string" and type(n) == "number" then
      local missing = math.floor(n) - math.max(0, (stock or {})[name] or 0) - pending(name)
      if missing > 0 then
        local made, why = orderCraft(name, missing)
        if not made then cant[name] = why elseif why then cant[name] = why end
      end
      if pending(name) > 0 then making[name] = pending(name) end
    end
  end
  return making, cant
end

---------------------------------------------------------------- machines

-- Hand each machine's jobs whose turn it is (every earlier step of the
-- order done) to the factory computer that runs it; it reports back with
-- jobdone. A machine not heard from for a while is forgotten, with its recipes.
local function firstOfPlan(job)
  for _, other in ipairs(queue.jobs) do
    if other.plan == job.plan then return other == job end
  end
  return false
end

local function runMachineJobs()
  for via, maker in pairs(makers) do
    if os.clock() - maker.at > MACHINE_FORGET then
      makers[via] = nil
      crafting.setMachine(via, {})
      reachCache = nil
    end
  end
  for _, job in ipairs(queue.jobs) do
    if job.via and job.state == "machine" and firstOfPlan(job) then
      local maker = makers[job.via]
      if not maker then
        failPlan(job, "no factory computer can make it any more")
        return -- the queue changed
      end
      local n = job.steps * job.count
      local reply = net.ask(maker.id, MACHINE_PROTOCOL,
        { type = job.via, job = job.id, make = job.name, count = n, grid = job.grid }, { wait = MACHINE_WAIT })
      if reply and reply.ok then
        job.state = "sent"
        save()
        say(("Asked factory #%d to make %d %s."):format(maker.id, n, nice(job.name)), "lightBlue")
      elseif reply then
        failPlan(job, reply.why or "the factory computer said no")
        return
      else
        say(("Factory #%d didn't answer: %s waits."):format(maker.id, nice(job.name)), "orange")
      end
    end
  end
end

local function machineLoop()
  while true do
    if rednet.isOpen() then runMachineJobs() end
    local timer = os.startTimer(10)
    repeat
      local event, value = os.pullEvent()
    until event == "overseer_work" or (event == "timer" and value == timer)
  end
end

---------------------------------------------------------------- the work

-- The next job a free turtle may start: the first one queued (or waiting
-- long enough) whose earlier steps in the same order are all done.
local function nextJob()
  local busyPlans = {}
  for _, job in ipairs(queue.jobs) do
    local ready = not job.via and (job.state == "queued" or (job.state == "waiting" and os.clock() - (job.tried or 0) >= RETRY_MISSING))
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
    local r
    if c.hub then
      r = loadBarrel(c.chest, job.grid, want)
    else
      r = askStorage({ type = "load", crafter = id, grid = job.grid, steps = want }, LOAD_WAIT)
    end
    if not r then
      job.state, job.crafter, job.tried = "queued", nil, os.clock()
      say("The storage computer isn't answering.", "orange")
      return
    end
    if (r.steps or 0) == 0 then
      -- short of something: wait (the screen says what), or give up after a while
      job.since = job.since or os.clock()
      job.missing, job.why = r.missing, r.error
      -- planned with ingredients that have gone since (a delivery took them):
      -- have them made, or the job waits for something no one is making
      if type(r.missing) == "table" and not job.reordered then
        job.reordered = true
        for item, n in pairs(r.missing) do
          if pending(item) < n then
            local made, whyNot = orderCraft(item, n - pending(item))
            if made then say(("A craft ran short of %s: making %d."):format(nice(item), made), "lightBlue")
            elseif whyNot then say(("A craft ran short of %s: %s."):format(nice(item), whyNot), "orange") end
          end
        end
      end
      if os.clock() - job.since > GIVE_UP then
        failPlan(job, "still short of ingredients: " .. tostring(r.error))
        say(("Gave up on %s: %s."):format(nice(job.name), tostring(r.error)), "red")
      else
        job.state, job.crafter, job.tried = "waiting", nil, os.clock()
      end
      save()
      return
    end
    job.since, job.missing, job.why, job.reordered = nil, nil, nil, nil
    c.note = ("crafting %d %s"):format(r.steps * job.count, nice(job.name))
    os.queueEvent("overseer_changed")
    local craft = { type = "craft", steps = r.steps, grid = job.grid }
    local reply = net.ask(id, CRAFT_PROTOCOL, craft, { wait = CRAFT_WAIT,
      match = function(msg) return msg.type == "crafted" and msg.id == craft.id end })
    if c.hub then
      withHub(function() emptyBarrel(c.chest) end)
    else
      askStorage({ type = "clear", crafter = id }, LOAD_WAIT)
    end
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
    if hub.name and os.clock() >= (hub.nextClaim or 0) then claimHub() end
    local r = askStorage({ type = "crafters" })
    if r then
      local chests = r.crafters or {}
      local seen, sharedTaken = {}, false
      local online = { rednet.lookup(CRAFT_PROTOCOL) }
      table.sort(online)
      for _, id in ipairs(online) do
        -- a barrel on my cable (through the ender chest), else its chest on
        -- the storage cable; the chest picked in 'storage setup' goes to one
        -- turtle without a chest of its own
        local barrel = hub.ready and barrels[id] and peripheral.isPresent(barrels[id]) and barrels[id]
        local chest = barrel or chests[id]
        if not chest and r.shared and not sharedTaken then chest, sharedTaken = r.shared, true end
        if chest then
          seen[id] = true
          crafters[id] = crafters[id] or {}
          crafters[id].chest, crafters[id].online, crafters[id].hub = chest, true, barrel and true or nil
        end
      end
      for id, c in pairs(crafters) do
        if not seen[id] and not c.job then crafters[id] = nil end
      end
      stockAt = -math.huge
      freshStock()
      workOutMissing()
      local n = 0
      for _ in pairs(crafters) do n = n + 1 end
      local problem
      local turtleJobs = false
      for _, job in ipairs(queue.jobs) do
        if not job.via then turtleJobs = true break end
      end
      if turtleJobs and n == 0 then problem = "no crafting turtle is running 'crafter' with a chest" end
      craftProblem = problem
      if problem then say("No crafting turtles: " .. problem .. ".", "orange")
      elseif hub.why then say(hub.why:sub(1, 1):upper() .. hub.why:sub(2) .. ".", "orange")
      elseif message[1] == "Starting..." or message[1]:find("storage computer", 1, true)
        or message[1]:find("ender chest", 1, true) then
        say(("Ready: %d crafting turtles."):format(n), "lime")
      end
    else
      craftProblem = "the craft overseer can't reach the storage computer"
      say("Looking for the storage computer: is it running 'storage'?", "orange")
    end
    status(#queue.jobs > 0 and "crafting" or "idle", ("%d jobs queued"):format(#queue.jobs))
    os.queueEvent("overseer_work")
    os.queueEvent("overseer_changed")
    sleep(LOOK_EVERY)
  end
end

---------------------------------------------------------------- requests

-- Every request goes in an inbox the moment it arrives, and netLoop answers
-- them in turn: one that comes while a plan is being worked out (which can
-- take a while with a modpack) is never missed. Claims from turtles on my
-- cable are claimLoop's.
local inbox = {}
local function netReceive()
  rednet.host(OVERSEER_PROTOCOL, os.getComputerLabel() or ("overseer-" .. os.getComputerID()))
  while true do
    local from, msg = rednet.receive(OVERSEER_PROTOCOL)
    if type(msg) == "table" and msg.type ~= "claim" and msg.re == nil then
      inbox[#inbox + 1] = { from = from, msg = msg }
      os.queueEvent("overseer_inbox")
    end
  end
end

local function answer(to, request, reply) net.answer(to, OVERSEER_PROTOCOL, request, reply) end

--   { type = "canmake", items = { name, ... }, need = { [name] = n } } -> { counts = { [name] = more could be made }, problem }
--   { type = "prepare", items = { [name] = n } }   -> { crafting, cantCraft, craftProblem }  (start crafting)
--   { type = "craftable" }                          -> { items = { { name, label, count, stored } }, ready, making, queue, problem, crafter }
--   { type = "craft", item, count, to = "chest" }  -> { making, why, to }  (a craft terminal's order)
--   { type = "recipes", uses = pattern }            -> { recipes = { { make, count, grid } } }  (the essence farm)
--   { type = "learn", recipe = { make, count, rows, keys } } -> { ok, error }  ('crafter learn')
--   { type = "makes", via, recipes }                -> { ok }  (a factory computer's machines' recipes)
--   { type = "jobdone", job, ok, why }              -> { ok }  (from that machine)
--   { type = "ping" }                               -> { jobs }
local function handleRequest(from, msg)
  if msg.type == "canmake" and type(msg.items) == "table" then
    local counts = {}
    freshStock()
    local avail = planningStock()
    local reach = reachNow(avail)
    for _, name in ipairs(msg.items) do
      if type(name) == "string" then
        local need = type(msg.need) == "table" and tonumber(msg.need[name]) or nil
        local n = crafting.craftable(name, avail, need, reach)
        -- the ME/RS system doesn't say how many it could make: take it that it can make what's needed
        if patterns[name] then n = math.max(n, need or 64) end
        counts[name] = n + pending(name)
      end
    end
    answer(from, msg, { counts = counts, problem = craftProblem })
  elseif msg.type == "prepare" and type(msg.items) == "table" then
    local making, cant = prepare(msg.items)
    answer(from, msg, { crafting = making, cantCraft = cant, craftProblem = craftProblem })
    local kinds = 0
    for _ in pairs(making) do kinds = kinds + 1 end
    local first, why = next(cant)
    if kinds > 0 then say(("Crafting %d kinds of item for #%d."):format(kinds, from), "lightBlue")
    elseif first and why ~= "no recipe for it" then say(("Can't craft %s for #%d: %s."):format(nice(first), from, why), "orange") end
  elseif msg.type == "craftable" then
    -- a craft terminal: the list (worked out in viewLoop while one keeps asking)
    local wasOn = os.clock() - view.wanted < VIEW_KEEP
    view.wanted = os.clock()
    if not wasOn then os.queueEvent("overseer_view_wanted") end
    local items, making = {}, {}
    for _, it in ipairs(view.list) do
      items[#items + 1] = { name = it.name, label = it.label, count = it.count, stored = it.stored or 0 }
    end
    for name, n in pairs(pendingAll()) do
      if n > 0 then making[#making + 1] = { name = name, label = nice(name), count = n } end
    end
    local n = 0
    for _ in pairs(crafters) do n = n + 1 end
    answer(from, msg, { items = items, ready = view.ready, making = making, queue = #queue.jobs,
      problem = craftProblem, crafter = n > 0 or next(patterns) ~= nil })
  elseif msg.type == "craft" and type(msg.item) == "string" then
    local n = math.max(1, math.min(ORDER_MAX, math.floor(tonumber(msg.count) or 1)))
    local made, why = orderCraft(msg.item, n)
    local toChest = msg.to == "chest"
    if made and toChest then
      local key = msg.item .. "@" .. from
      local o = orders[key] or { name = msg.item, who = from, want = 0, sent = 0 }
      o.want = o.want + made
      orders[key] = o
    end
    answer(from, msg, { making = made or 0, why = why, to = toChest and "own" or "storage" })
    if made then say(("Crafting %d %s for computer #%d."):format(made, nice(msg.item), from), "lightBlue")
    else say(("Can't craft %s for computer #%d: %s."):format(nice(msg.item), from, why), "orange") end
  elseif msg.type == "recipes" and type(msg.uses) == "string" then
    local okR, list = pcall(crafting.using, msg.uses)
    answer(from, msg, { recipes = okR and list or {}, error = not okR and tostring(list) or nil })
  elseif msg.type == "learn" then
    local okL, err = crafting.learn(msg.recipe)
    answer(from, msg, { ok = okL and true or false, error = not okL and err or nil })
    if okL then
      reachCache = nil
      say(("Learnt how to make %s."):format(nice(msg.recipe.make)), "lime")
    end
  elseif msg.type == "makes" and type(msg.via) == "string" and type(msg.recipes) == "table" then
    -- a factory computer: what its machines can make (sent again every so often)
    local key = textutils.serialize(msg.recipes)
    local maker = makers[msg.via]
    local n = maker and maker.n
    if not maker or maker.key ~= key or maker.id ~= from then
      n = crafting.setMachine(msg.via, msg.recipes)
      reachCache = nil
      -- the essence farm sends again whenever its essence changes (how many goes): say so only when what it makes does
      if n > 0 and (not maker or maker.id ~= from or maker.n ~= n) then
        say(("Factory #%d can make %d things by %s."):format(from, n, msg.via), "lightBlue")
      end
    end
    makers[msg.via] = #msg.recipes > 0 and { id = from, at = os.clock(), key = key, n = n } or nil
    answer(from, msg, { ok = true })
    os.queueEvent("overseer_work")
  elseif msg.type == "jobdone" then
    for _, job in ipairs(queue.jobs) do
      if job.id == msg.job then
        if msg.ok then
          removeJob(job)
          finishJob(job, true)
          say(("Factory #%d made %d %s."):format(from, job.steps * job.count, nice(job.name)), "lime")
        else
          failPlan(job, msg.why or "the factory computer couldn't")
        end
        break
      end
    end
    answer(from, msg, { ok = true })
    workOutMissing()
    os.queueEvent("overseer_work")
    os.queueEvent("overseer_changed")
  elseif msg.type == "ping" then
    answer(from, msg, { jobs = #queue.jobs })
  end
end

-- An order from my own Craft page: made into storage.
local function handleOrder(o)
  local made, why = orderCraft(o.name, o.count)
  if made then
    say(("Crafting %d %s into storage%s."):format(made, nice(o.name), why and (" (" .. why .. ")") or ""), "lightBlue")
    if report then report.log(("ordered %d %s"):format(made, nice(o.name))) end
  else
    say(("Can't craft %s: %s."):format(nice(o.name), why), "orange")
  end
end

local function netLoop()
  while true do
    while #inbox == 0 do os.pullEvent("overseer_inbox") end
    local req = table.remove(inbox, 1)
    local ok, err
    if req.order then ok, err = (errlog and errlog.pcall or pcall)(handleOrder, req.order)
    else ok, err = (errlog and errlog.pcall or pcall)(handleRequest, req.from, req.msg) end
    if not ok then say("A request failed: " .. tostring(err), "red") end
  end
end

---------------------------------------------------------------- the craft terminal

-- Keep the list of what could be crafted up to date while a craft terminal
-- keeps asking for it: after stock changes, at most every VIEW_EVERY
-- seconds, and resting VIEW_REST times as long as the last count took
-- (counting thousands of modded items is most of this computer's work while
-- it runs; requests come first meanwhile, as every plan yields).
local function viewLoop()
  while true do
    while os.clock() - view.wanted >= VIEW_KEEP do os.pullEvent("overseer_view_wanted") end
    local started = os.clock()
    freshStock()
    local list, avail = {}, planningStock()
    local reach = crafting.reachable(avail)
    reachCache, reachAt = reach, os.clock()
    for _, name in ipairs(crafting.names()) do
      if reach[name] then
        local n = crafting.craftable(name, avail, VIEW_MAX, reach)
        if n > 0 then list[#list + 1] = { name = name, label = nice(name), count = n, stored = math.max(0, (stock or {})[name] or 0) } end
      end
    end
    local listed = {}
    for _, it in ipairs(list) do listed[it.name] = true end
    for name in pairs(patterns) do
      if not listed[name] then list[#list + 1] = { name = name, label = nice(name), stored = math.max(0, (stock or {})[name] or 0) } end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    view.list, view.ready = list, true
    os.queueEvent("overseer_changed")
    sleep(math.max(VIEW_EVERY, (os.clock() - started) * VIEW_REST))
  end
end

-- Send a craft terminal what's been made of its order, into its chest
-- (the storage computer's deliver, for that computer). Once nothing more is
-- being made, whatever didn't turn up is given up on.
local function orderLoop()
  while true do
    sleep(ORDER_EVERY)
    if next(orders) then
      stockAt = -math.huge
      freshStock()
      for key, o in pairs(orders) do
        local have = (stock or {})[o.name] or 0
        if have > 0 then
          local left = o.want - o.sent
          local r = askStorage({ type = "deliver", ["for"] = o.who, items = { [o.name] = 1e9 }, most = { [o.name] = math.min(have, left) } })
          local got = r and r.sent and r.sent[o.name] or 0
          o.sent = o.sent + got
          if r and r.error and got == 0 then
            orders[key] = nil
            say(("Couldn't send computer #%d its %s: %s."):format(o.who, nice(o.name), r.error), "orange")
          end
        end
        if orders[key] and o.sent >= o.want then
          orders[key] = nil
          say(("Crafted %d %s for computer #%d: sent to its chest."):format(o.sent, nice(o.name), o.who), "lime")
        elseif orders[key] and pending(o.name) == 0 and have == 0 then
          orders[key] = nil
          if o.sent > 0 then say(("Only %d of %d %s were made for computer #%d."):format(o.sent, o.want, nice(o.name), o.who), "orange") end
        end
      end
    end
  end
end

---------------------------------------------------------------- screen

-- Only a monitor touching this computer, unless one is named with 'set
-- overseer.monitor': it sits on the storage cable, and a monitor there is
-- usually the storage computer's.
local SIDES = {}
for _, side in ipairs(rs.getSides()) do SIDES[side] = true end
local display = screen.find({ setting = "overseer.monitor", scales = MONITOR_SCALES, minW = 39, minH = 15,
  filter = function(name) return SIDES[name] == true end, fallback = term.current() })
local termScreen = screen.new(term.current()) -- the computer's own screen, while the monitor shows the rest
local put, fit = screen.put, screen.fit

-- Each screen's page and the order being picked on it. The monitor is
-- worked by tapping (pages of the list, buttons for how many), the
-- terminal by typing (a search, a number) or clicking. hits: where the last
-- frame put something to tap, { y, x1, x2, fn }.
local uis = {
  mon = { view = "queue", query = "", selected = 1, scroll = 0, touch = true, hits = {} },
  term = { view = display.name and "craft" or "queue", query = "", selected = 1, scroll = 0, hits = {} },
}
local TABS = { { "queue", "Queue" }, { "craft", "Craft" } }
local STEPS = { -64, -8, -1, 0, 1, 8, 64 } -- the amount buttons (0: the amount itself)

local function missingText(short)
  local parts = {}
  for item, n in pairs(short or {}) do parts[#parts + 1] = ("%d %s"):format(n, nice(item)) end
  table.sort(parts)
  return table.concat(parts, ", ")
end

local function shortCount(n)
  if n >= 10000 then return ("%dk"):format(math.floor(n / 1000)) end
  return tostring(n)
end

local function hit(ui, y, x1, x2, fn) ui.hits[#ui.hits + 1] = { y = y, x1 = x1, x2 = x2, fn = fn } end

-- A tap or click: whatever the last frame put there.
local function tap(ui, x, y)
  for _, h in ipairs(ui.hits) do
    if h.y == y and x >= h.x1 and x <= h.x2 then
      h.fn()
      return true
    end
  end
  return false
end

local function header(win, w, ui)
  put(win, 1, 1, (" "):rep(w), "white", "gray")
  local x = 1
  for _, t in ipairs(TABS) do
    local on, label = ui.view == t[1], " " .. t[2] .. " "
    put(win, x, 1, label, on and "yellow" or "lightGray", on and "black" or "gray")
    hit(ui, 1, x, x + #label - 1, function() ui.view, ui.pick = t[1], nil end)
    x = x + #label + 1
  end
  local head = ("%d jobs"):format(#queue.jobs)
  put(win, w - #head, 1, head, "lightGray", "gray")
end

local function drawQueue(win, w, h)
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
    elseif job.via then
      state, colour = job.state == "sent" and ("by " .. job.via) or "machine", "lightBlue"
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
end

---------------------------------------------------------------- ordering from the screen

local function matches(ui)
  local q, out = ui.query:lower(), {}
  for _, it in ipairs(view.list) do
    if q == "" or it.label:lower():find(q, 1, true) or it.name:lower():find(q, 1, true) then out[#out + 1] = it end
  end
  return out
end

-- Start picking how many: a stack, or as many as can be made if fewer.
local function pickItem(ui, it)
  ui.pick = { it = it, n = it.count and math.max(1, math.min(ORDER_STACK, it.count)) or ORDER_STACK, typed = false }
end

-- The order goes in the inbox like a craft terminal's, so it's planned in
-- turn with every other request (two plans at once would count the same stock).
local function sendOrder(ui)
  local p = ui.pick
  ui.pick = nil
  if not p or p.n < 1 then return end
  inbox[#inbox + 1] = { order = { name = p.it.name, count = p.n } }
  os.queueEvent("overseer_inbox")
  say(("Ordering %d %s..."):format(p.n, p.it.label), "lightGray")
end

local function drawCraft(win, w, h, ui)
  local list = matches(ui)
  local rows = h - 5 -- rows 3 to h - 3
  ui.selected = math.max(1, math.min(ui.selected, #list))
  if ui.touch then
    -- whole pages, turned with the arrows
    local pages = math.max(1, math.ceil(#list / rows))
    local page = math.max(1, math.min(pages, math.floor(ui.scroll / rows) + 1))
    ui.scroll = (page - 1) * rows
    put(win, 2, 2, fit("Tap something to craft it.", w - 14), "lightGray")
    local pageText = ("%d/%d"):format(page, pages)
    local x = w - #pageText - 7
    put(win, x, 2, " < ", "white", page > 1 and "gray" or "black")
    put(win, x + 4, 2, pageText, "lightGray")
    put(win, w - 2, 2, " > ", "white", page < pages and "gray" or "black")
    hit(ui, 2, x, x + 2, function() ui.scroll = math.max(0, ui.scroll - rows) end)
    hit(ui, 2, w - 2, w, function() ui.scroll = ui.scroll + rows end)
  else
    if ui.selected <= ui.scroll then ui.scroll = ui.selected - 1 end
    if ui.selected > ui.scroll + rows then ui.scroll = ui.selected - rows end
    ui.scroll = math.max(0, math.min(ui.scroll, #list - rows))
    put(win, 1, 2, "Search: ", "lightGray")
    put(win, 9, 2, fit(ui.query, w - 9), "white")
  end

  for i = 1, rows do
    local index, it = ui.scroll + i, list[ui.scroll + i]
    if it then
      local sel = ui.pick and ui.pick.it.name == it.name or not ui.touch and not ui.pick and index == ui.selected
      local bg = sel and "blue" or "black"
      local can = it.count and ("make " .. shortCount(it.count)) or "pattern"
      local stored = (it.stored or 0) > 0 and (shortCount(it.stored) .. " stored  ") or ""
      local right = stored .. can
      put(win, 1, 2 + i, fit(" " .. it.label, w - #right - 2), "white", bg)
      put(win, w - #right - 1, 2 + i, " " .. stored, sel and "white" or "gray", bg)
      put(win, w - #can, 2 + i, can .. " ", sel and "white" or "lightBlue", bg)
      hit(ui, 2 + i, 1, w, function()
        if ui.touch or index == ui.selected then pickItem(ui, it) else ui.selected, ui.pick = index, nil end
      end)
    end
  end
  if #list == 0 then
    local any = next(crafters) ~= nil or next(patterns) ~= nil
    local empty = ui.query ~= "" and "Nothing craftable matches."
      or not view.ready and "Working out what can be crafted..."
      or not any and "No crafting turtle yet."
      or "Nothing can be crafted from what's stored."
    put(win, 2, 4, fit(empty, w - 2), "lightGray")
  end

  -- what's being made, or why it's stuck
  local busy
  if craftProblem then
    busy = { "Stuck: " .. craftProblem, "orange" }
  else
    local parts = {}
    for name, n in pairs(pendingAll()) do
      if n > 0 then parts[#parts + 1] = ("%d %s"):format(n, nice(name)) end
    end
    table.sort(parts)
    busy = #parts > 0 and { "Making: " .. table.concat(parts, ", "), "lightBlue" } or { "Nothing being crafted.", "gray" }
  end
  put(win, 1, h - 2, fit(busy[1], w), busy[2])

  local p = ui.pick
  if p then
    put(win, 1, h - 1, fit(("How many %s? Into storage."):format(p.it.label), w), "yellow")
    -- -64 -8 -1 [n] +1 +8 +64  Craft  x
    put(win, 1, h, (" "):rep(w), "white", "gray")
    local x = 1
    for _, step in ipairs(STEPS) do
      local text, fg, bg
      if step == 0 then
        text, fg, bg = (" %4s "):format(p.typed and p.n == 0 and "" or tostring(p.n)), "white", "black"
      else
        text, fg, bg = (step > 0 and "+" or "") .. step, "white", "gray"
        hit(ui, h, x, x + #text - 1, function() p.n, p.typed = math.max(1, math.min(ORDER_MAX, p.n + step)), false end)
      end
      put(win, x, h, text, fg, bg)
      x = x + #text + 1
    end
    put(win, x, h, " Craft ", "white", "green")
    hit(ui, h, x, x + 6, function() sendOrder(ui) end)
    x = x + 8
    put(win, x, h, " x ", "white", "red")
    hit(ui, h, x, x + 2, function() ui.pick = nil end)
  else
    put(win, 1, h - 1, fit(message[1], w), message[2])
    put(win, 1, h, fit(ui.touch and "Tap a row, pick how many, then Craft." or "Type to search  Enter: craft  Tab: queue", w), "gray")
  end
end

local function drawOn(s, ui)
  if not s.target then return end
  local win, w, h = s:frame()
  ui.hits = {}
  header(win, w, ui)
  if ui.view == "craft" then drawCraft(win, w, h, ui) else drawQueue(win, w, h) end
  if not ui.touch and ui.view == "craft" and not ui.pick then
    win.setCursorPos(math.min(w, 9 + #ui.query), 2)
    win.setTextColor(colors.white)
    win.setCursorBlink(true)
  else
    win.setCursorBlink(false)
  end
  s:show()
end

local function draw()
  if display.name then
    drawOn(display, uis.mon)
    drawOn(termScreen, uis.term)
  else
    drawOn(display, uis.term)
  end
end

-- Keys on the terminal: the search and the amount being typed.
local function onKey(ui, event, a)
  local p = ui.pick
  if p then
    if event == "char" and a:match("%d") then
      if not p.typed then p.n, p.typed = 0, true end
      p.n = math.min(ORDER_MAX, p.n * 10 + tonumber(a))
    elseif event == "key" and (a == keys.enter or a == keys.numPadEnter) then
      sendOrder(ui)
    elseif event == "key" and a == keys.backspace then
      if p.typed and p.n == 0 then ui.pick = nil else p.n, p.typed = math.floor(p.n / 10), true end
    elseif event == "key" and (a == keys.delete or a == keys.up or a == keys.down or a == keys.tab) then
      ui.pick = nil
    end
    return
  end
  if event == "char" then
    ui.view, ui.query, ui.selected = "craft", ui.query .. a, 1
  elseif event == "key" then
    if a == keys.tab then
      ui.view = ui.view == "craft" and "queue" or "craft"
    elseif ui.view == "craft" then
      local list = matches(ui)
      if a == keys.backspace then ui.query, ui.selected = ui.query:sub(1, -2), 1
      elseif a == keys.delete then ui.query, ui.selected = "", 1
      elseif a == keys.up then ui.selected = ui.selected - 1
      elseif a == keys.down then ui.selected = ui.selected + 1
      elseif a == keys.pageUp then ui.selected = ui.selected - 10
      elseif a == keys.pageDown then ui.selected = ui.selected + 10
      elseif (a == keys.enter or a == keys.numPadEnter) and list[ui.selected] then pickItem(ui, list[ui.selected])
      end
    end
  end
end

local QUIET = { rednet_message = true, modem_message = true } -- others' traffic: what it changes says so itself

-- While someone uses a Craft page, keep the list of what can be made worked
-- out (for VIEW_KEEP after the last tap or key: a page left open by itself
-- doesn't keep a modpack's minute-long count going).
local function wantList()
  if uis.term.view == "craft" or (display.name and uis.mon.view == "craft") then
    local wasOn = os.clock() - view.wanted < VIEW_KEEP
    view.wanted = os.clock()
    if not wasOn then os.queueEvent("overseer_view_wanted") end
  end
end

local INPUT = { monitor_touch = true, mouse_click = true, mouse_scroll = true, char = true, key = true }

local function uiLoop()
  local tick = os.startTimer(VIEW_TICK)
  wantList()
  while true do
    draw()
    local ev
    repeat ev = { os.pullEvent() } until not QUIET[ev[1]]
    if ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
      display:refresh()
    elseif ev[1] == "timer" and ev[2] == tick then
      tick = os.startTimer(VIEW_TICK)
    elseif ev[1] == "monitor_touch" then
      local x, y = display:clicked(ev)
      if x and display.name then tap(uis.mon, x, y) end
    elseif ev[1] == "mouse_click" then
      tap(uis.term, ev[3], ev[4])
    elseif ev[1] == "mouse_scroll" and uis.term.view == "craft" and not uis.term.pick then
      uis.term.selected = uis.term.selected + ev[2]
    elseif ev[1] == "char" or ev[1] == "key" then
      onKey(uis.term, ev[1], ev[2])
    end
    if INPUT[ev[1]] then wantList() end
  end
end

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "clear" then
  files.delete(QUEUE_FILE)
  print("Queue forgotten.")
  return
end

if args[1] == "hub" then
  if args[2] == "off" then
    settings.unset(HUB_SETTING)
    settings.save()
    files.delete(BARRELS_FILE)
    print("No ender chest: crafting turtles use chests on the storage cable.")
    return
  end
  local name = args[2]
  if not name then
    local found = enderChests()
    if #found == 0 then
      print("No ender chest on my cable. Put one there with a wired modem")
      print("(right-click it so it turns red), then try again.")
      return
    elseif #found > 1 then
      print("Ender chests on my cable:")
      for _, n in ipairs(found) do print("  " .. n) end
      print("Pick one: overseer hub <name>")
      return
    end
    name = found[1]
  end
  if not (peripheral.isPresent(name) and isEnder(name) and isInventory(name)) then
    print(name .. " isn't an ender chest on my cable.")
    return
  end
  settings.set(HUB_SETTING, name)
  settings.save()
  print(("My ender chest is %s. Put its twin (same colours, used by"):format(name))
  print("nothing else) on the storage cable with a wired modem, and each")
  print("crafting turtle's barrel on my cable. Then reboot me.")
  return
end

hub.name = settings.get(HUB_SETTING)
local savedBarrels = files.read(BARRELS_FILE)
if hub.name and type(savedBarrels) == "table" then barrels = savedBarrels end

if not net.open("any") then
  print("I need a modem: a wired one on the storage computer's cable, and")
  print("wireless if the crafting turtles talk by wireless (ender, far away).")
  return
end

local saved = load()
if saved then
  queue.jobs, queue.plans = saved.jobs or {}, saved.plans or 0
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
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, netReceive, netLoop, lookLoop, claimLoop,
  machineLoop, viewLoop, orderLoop, function() net.keepOpen("any") end,
  report and report.loop or function() while true do sleep(3600) end end, table.unpack(workers))
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
