-- The essence farm (botany.lua uses it): a factory computer far from the
-- storage system, on a cable of its own with its botany pots, the barrels
-- and chests they empty into, crafting turtles with a barrel each, and an
-- ender chest (its work chest) whose twin is at home.
--
-- The essence stays here: every barrel and chest on the cable (but the
-- ender chests, the turtles' barrels and whatever another machine uses) is
-- the farm's own store. It tells the storage computer what it can make
-- from it ('makes', via = "essence": recipes with nothing in them for
-- storage to send, and max = how many goes there's essence for), so a
-- crafting plan at home, a turtle's request or an order on the Essence tab
-- can use it. Each job: the ingredients go from the store into a turtle's
-- barrel, the turtle crafts (the storage_crafter protocol, as for the
-- storage computer), and what it made goes into the ender chest; the
-- storage computer is told the job is done ('jobdone').
--
-- The turtles find their barrel here (lib/claim.lua's 'claim', on
-- FARM_PROTOCOL): one item from the store goes into each barrel it could
-- be until the turtle sees it arrive.
local files = require("lib.files") -- crash-safe save files
local net = require("lib.net") -- rednet requests and answers

local farm = {}

local FARM_PROTOCOL = "factory_crafter" -- crafting turtles here find their barrel on this
local CRAFT_PROTOCOL = "storage_crafter" -- crafting turtles take jobs on this
local JOBS_FILE = "/.essence_jobs" -- the jobs waiting or under way
local CRAFTERS_FILE = "/.essence_crafters" -- turtle id -> its barrel
local CRAFT_WAIT = 60 -- seconds a turtle may take for one batch
local MAX_GOES = 64 -- most goes in one batch: a turtle's grid slot holds a stack
local OFFER_EVERY = 60 -- seconds between telling the storage computer what can be made, at most
local OFFER_SOON = 10 -- seconds, at least, between offers when the numbers change
local CLAIM_IDLE = 60 -- seconds a turtle may go quiet mid-search before its probe item is taken back
local NOT_MINE_FOR = 600 -- seconds a turtle whose barrel isn't on this cable is told so straight away

-- Types that are storage of some kind: what a pot can empty into.
local STORE_WORDS = { "barrel", "chest", "crate", "drawer", "shulker", "vault", "storage" }

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

-- A barrel, chest, crate, drawer... never an ender chest: its items are shared with one elsewhere.
function farm.isStore(name)
  local types = { peripheral.getType(name) }
  for _, t in ipairs(types) do
    if t:find("ender", 1, true) then return false end
  end
  for _, t in ipairs(types) do
    for _, w in ipairs(STORE_WORDS) do
      if t:find(w, 1, true) then return true end
    end
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

local function list(name)
  local ok, l = pcall(peripheral.call, name, "list")
  return ok and type(l) == "table" and l or nil
end

-- f: the factory (factory.lua); opts: pots (what's in a pot's name, so pots
-- aren't taken for stores), saved (the pot barrels added by hand: stores too).
function farm.new(f, opts)
  local self = {
    counts = {}, -- item -> how many the store holds
    jobs = {}, -- { id, job (the storage computer's, or nil for the tab's), make, count, made, by, state, why }
    crafters = {}, -- turtle id -> its barrel
    turtles = {}, -- turtle id -> { state, colour } for the screen
    stores = {}, -- the store's barrels and chests, from the last scan
  }
  local where = {} -- item -> { { store, slot, count } }
  local nextId = 1
  local offerKey, offerAt, offerNote = nil, -math.huge, nil
  local claims = {} -- turtle id -> { candidates, i, at, marker, from, last }
  local notMine = {} -- turtle id -> os.clock() when its barrel was found not to be on this cable

  local function save() files.write(JOBS_FILE, { next = nextId, jobs = self.jobs }) end
  local saved = files.read(JOBS_FILE)
  if type(saved) == "table" and type(saved.jobs) == "table" then
    self.jobs, nextId = saved.jobs, tonumber(saved.next) or 1
  end
  local c = files.read(CRAFTERS_FILE)
  if type(c) == "table" then self.crafters = c end

  local function turtleBarrel(name)
    for _, b in pairs(self.crafters) do
      if b == name then return true end
    end
    return false
  end

  -- Every barrel and chest on the cable that's the farm's: not an ender
  -- chest, a pot, a turtle's barrel, the work chest, what's touching the
  -- computer, or what another machine (here or on another factory computer) uses.
  function self.storeNames()
    local skip = {}
    for _, s in ipairs(rs.getSides()) do skip[s] = true end
    if f.work.chest then skip[f.work.chest] = true end
    if f.work.back then skip[f.work.back] = true end
    local added = {}
    for _, n in ipairs(opts.saved()) do added[n] = true end
    local out = {}
    for _, name in ipairs(peripheral.getNames()) do
      if not skip[name] and not name:find(opts.pots, 1, true) and farm.isStore(name) and not turtleBarrel(name)
        and (added[name] or (not f.mine(name) and not f.taken(name))) then
        out[#out + 1] = name
      end
    end
    table.sort(out)
    return out
  end

  -- Read every store at once: counts, and where each item is.
  function self.scan()
    local names = self.storeNames()
    local lists, jobs = {}, {}
    for i, name in ipairs(names) do jobs[i] = function() lists[i] = list(name) end end
    for i = 1, #jobs, 100 do parallel.waitForAll(table.unpack(jobs, i, math.min(#jobs, i + 99))) end
    self.counts, where, self.stores = {}, {}, {}
    for i, name in ipairs(names) do
      local l = lists[i]
      local total, kinds = 0, {}
      for slot, item in pairs(l or {}) do
        self.counts[item.name] = (self.counts[item.name] or 0) + item.count
        where[item.name] = where[item.name] or {}
        local w = where[item.name]
        w[#w + 1] = { name, slot, item.count }
        total = total + item.count
        kinds[item.name] = true
      end
      self.stores[i] = { name = name, ok = l ~= nil, items = total, kinds = kinds }
    end
  end

  -- Move up to n of item from the store into to. How many went.
  local function fromStore(item, to, n)
    local moved = 0
    for _, w in ipairs(where[item] or {}) do
      if moved >= n then break end
      if w[3] > 0 then
        local ok, m = pcall(peripheral.call, w[1], "pushItems", to, w[2], n - moved)
        m = ok and m or 0
        w[3] = w[3] - m
        moved = moved + m
      end
    end
    self.counts[item] = math.max(0, (self.counts[item] or 0) - moved)
    return moved
  end

  -- Put a slot of from back into the store: a store that has the item first, then any. How many went.
  local function toStore(from, slot, item)
    local tries, seen = {}, {}
    for _, w in ipairs(where[item.name] or {}) do
      if not seen[w[1]] then tries[#tries + 1], seen[w[1]] = w[1], true end
    end
    for _, s in ipairs(self.stores) do
      if not seen[s.name] then tries[#tries + 1], seen[s.name] = s.name, true end
    end
    local moved = 0
    for _, s in ipairs(tries) do
      if moved >= item.count then break end
      local ok, m = pcall(peripheral.call, from, "pushItems", s, slot, item.count - moved)
      moved = moved + (ok and m or 0)
    end
    self.counts[item.name] = (self.counts[item.name] or 0) + moved
    return moved
  end
  self.toStore = toStore

  ---------------------------------------------------------------- recipes

  -- The item of the store that fits a recipe key (a name, a name with *,
  -- or a list to choose from): the one there's most of.
  local function pick(key, avail)
    local names = type(key) == "table" and key or { key }
    local best, bestN = nil, 0
    for _, k in ipairs(names) do
      if k:find("*", 1, true) then
        local pattern = "^" .. k:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
        for item, n in pairs(avail) do
          if n > bestN and item:find(pattern) then best, bestN = item, n end
        end
      elseif (avail[k] or 0) > bestN then
        best, bestN = k, avail[k]
      end
    end
    return best, bestN
  end

  -- How many goes of a recipe (raw: { make, count, grid }) the store has the
  -- makings for, and the grid of item names for them; 0 if one's missing.
  local function goesOf(raw, avail)
    local per, keyOf = {}, {}
    for cell, key in pairs(raw.grid or {}) do
      local id = type(key) == "table" and table.concat(key, ",") or key
      per[id] = (per[id] or 0) + 1
      keyOf[id] = key
    end
    local goes, grid, chosen = math.huge, {}, {}
    for id, n in pairs(per) do
      local item, have = pick(keyOf[id], avail)
      if not item then return 0 end
      chosen[id] = item
      goes = math.min(goes, math.floor(have / n))
    end
    for cell, key in pairs(raw.grid or {}) do
      grid[cell] = chosen[type(key) == "table" and table.concat(key, ",") or key]
    end
    return goes == math.huge and 0 or goes, grid
  end

  -- The store's counts less what the jobs waiting will use.
  local function spare(byMake)
    local avail = {}
    for k, v in pairs(self.counts) do avail[k] = v end
    for _, j in ipairs(self.jobs) do
      local raw = byMake[j.make]
      if raw then
        local goes = math.ceil(math.max(0, j.count - j.made) / (raw.count or 1))
        local _, grid = goesOf(raw, avail)
        for _, item in pairs(grid or {}) do avail[item] = math.max(0, (avail[item] or 0) - goes) end
      end
    end
    return avail
  end

  -- Every recipe the store can make, as { raw, goes } by what it makes:
  -- only ones whose every ingredient can be here (all of them essence, or
  -- something else the store holds), the best one per item.
  function self.makeable(recipes)
    local avail = spare(self.byMake or {})
    local out = {}
    for _, raw in ipairs(recipes) do
      local goes = goesOf(raw, avail)
      local b = out[raw.make]
      if not b or goes * (raw.count or 1) > b.goes * (b.raw.count or 1) then out[raw.make] = { raw = raw, goes = goes } end
    end
    return out
  end

  -- Tell the storage computer what can be made here and how many goes,
  -- when the numbers change (not more than every OFFER_SOON) and every
  -- OFFER_EVERY, as it forgets in time. Nothing in the recipes: the
  -- storage computer sends nothing, the farm uses its own essence.
  function self.offer(recipes)
    self.byMake = {}
    for _, raw in ipairs(recipes) do
      if not self.byMake[raw.make] then self.byMake[raw.make] = raw end
    end
    local can = self.makeable(recipes)
    local crafts, parts = {}, {}
    for make, b in pairs(can) do
      self.byMake[make] = b.raw
      crafts[#crafts + 1] = { make = make, count = b.raw.count or 1, rows = {}, keys = {}, max = b.goes }
      parts[#parts + 1] = make .. "=" .. b.goes
    end
    table.sort(parts)
    local key = table.concat(parts, ",")
    local since = os.clock() - offerAt
    if (key == offerKey and since < OFFER_EVERY) or since < OFFER_SOON then return end
    local reply = f.ask({ type = "makes", via = "essence", recipes = next(self.crafters) and crafts or {} }, 5)
    offerAt = os.clock()
    if reply and reply.ok then
      offerKey, offerNote = key, nil
    else
      offerKey = nil
      offerNote = reply and reply.error or "the storage computer doesn't take essence orders: 'install update' it"
    end
  end
  function self.offerNote() return offerNote end

  ---------------------------------------------------------------- jobs

  local function newJob(make, count, job, by)
    local j = { id = nextId, job = job, make = make, count = count, made = 0, by = by, state = "waiting" }
    nextId = nextId + 1
    self.jobs[#self.jobs + 1] = j
    save()
    f.wake()
    return j
  end

  -- An order from the Essence tab: crafts goes of raw. What to tell the player.
  function self.order(raw, goes)
    if not next(self.crafters) then
      return "No crafting turtle here yet: put one by an empty barrel on this cable.", "orange"
    end
    local n = goes * (raw.count or 1)
    newJob(raw.make, n, nil, "the Essence tab")
    return ("Making %d %s here: it goes home through the ender chest."):format(n, nice(raw.make)), "lime"
  end

  -- The storage computer (factory protocol): 'essence' (make this for one of
  -- my plans) and 'cancel'. The reply, or nil if it isn't one.
  function self.request(from, msg)
    if msg.type == "essence" then
      local count = math.floor(tonumber(msg.count) or 0)
      if not (self.byMake or {})[msg.make] or count < 1 then return { ok = false, why = "this essence farm has no recipe for it" } end
      if not next(self.crafters) then return { ok = false, why = "this essence farm has no crafting turtle" } end
      newJob(msg.make, count, msg.job, "the storage computer")
      return { ok = true }
    elseif msg.type == "cancel" then
      for i = #self.jobs, 1, -1 do
        if self.jobs[i].job == msg.job then table.remove(self.jobs, i) end
      end
      save()
      return { ok = true }
    end
    return nil
  end

  -- A storage computer's job finished (or given up on): tell it. True once it heard.
  local function report(j)
    if not j.job then return true end
    return f.ask({ type = "jobdone", job = j.job, ok = j.ok, why = j.why }, 5) ~= nil
  end

  -- Empty a turtle's barrel: ingredients back into the store, anything else
  -- home (input: where finished things go). False if something wouldn't go.
  local function clearBarrel(barrel, input, make)
    local l = list(barrel)
    if not l then return false end
    local all = true
    for slot, item in pairs(l) do
      local moved
      if item.name == make or not where[item.name] then
        local ok, m = pcall(peripheral.call, barrel, "pushItems", input, slot)
        moved = ok and m or 0
      else
        moved = toStore(barrel, slot, item)
      end
      if moved < item.count then all = false end
    end
    return all
  end

  -- One batch of a job on one turtle: load, craft, unload. Fills in the
  -- turtle's state; returns how many of the job's item went home.
  local function batch(id, barrel, j, raw, input)
    local t = self.turtles[id]
    if not clearBarrel(barrel, input, j.make) then
      t.state, t.colour = "its barrel won't empty", "red"
      return 0
    end
    local goes, grid = goesOf(raw, self.counts)
    goes = math.min(goes, MAX_GOES, math.ceil((j.count - j.made) / (raw.count or 1)))
    if goes < 1 then return 0 end
    -- what each item goes in how many cells
    local per = {}
    for _, item in pairs(grid) do per[item] = (per[item] or 0) + 1 end
    for item, n in pairs(per) do
      if fromStore(item, barrel, n * goes) < n * goes then
        clearBarrel(barrel, input, j.make)
        t.state, t.colour = ("couldn't load %s"):format(nice(item)), "red"
        return 0
      end
    end
    t.state, t.colour = ("crafting %d %s"):format(goes * (raw.count or 1), nice(j.make)), "yellow"
    f.changed()
    local msg = { type = "craft", steps = goes, grid = grid }
    local reply = net.ask(id, CRAFT_PROTOCOL, msg,
      { wait = CRAFT_WAIT, match = function(r) return r.type == "crafted" and r.id == msg.id end })
    -- what it made goes home; the rest (ingredients it didn't use) back into the store
    local before = 0
    for _, item in pairs(list(barrel) or {}) do
      if item.name == j.make then before = before + item.count end
    end
    clearBarrel(barrel, input, j.make)
    local left = 0
    for _, item in pairs(list(barrel) or {}) do
      if item.name == j.make then left = left + item.count end
    end
    if not reply then
      t.state, t.colour = "not answering: is it running 'crafter'?", "red"
    elseif (reply.made or 0) == 0 then
      t.state, t.colour = "couldn't craft: " .. tostring(reply.error or "?"), "red"
    else
      t.state, t.colour = "idle", "lime"
    end
    return math.max(0, before - left)
  end

  -- A round: every turtle that's free takes a batch of the first job it can
  -- work on. input: the ender chest (where what's made goes).
  function self.run(input)
    for id in pairs(self.crafters) do
      self.turtles[id] = self.turtles[id] or { state = "idle", colour = "lime" }
    end
    for id in pairs(self.turtles) do
      if not self.crafters[id] then self.turtles[id] = nil end
    end
    local byMake = self.byMake or {}
    local work, given = {}, {}
    local ids = {}
    for id in pairs(self.crafters) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      for _, j in ipairs(self.jobs) do
        local raw = byMake[j.make]
        -- one turtle per job at a time: the store is read once a round
        if raw and not given[j.id] and j.made < j.count then
          given[j.id] = true
          work[#work + 1] = function()
            local got = batch(id, self.crafters[id], j, raw, input)
            j.made = j.made + got
            j.state = got > 0 and ("%d of %d made"):format(j.made, j.count) or j.state
          end
          break
        end
      end
    end
    if #work > 0 then parallel.waitForAll(table.unpack(work)) end
    -- finished jobs, and ones there's no essence (or recipe) left for
    local swept, sweepWhy = false, nil
    for i = #self.jobs, 1, -1 do
      local j = self.jobs[i]
      local raw = byMake[j.make]
      local short = j.made < j.count and (not raw or goesOf(raw, self.counts) < 1)
      if j.made >= j.count or short then
        -- one ender chest both ways: it goes home when the storage computer is asked to fill it
        if j.made > 0 and not swept and not f.work.back then
          local r, why = f.work:fill({}, 0)
          swept, sweepWhy = true, not r and why or r and r.error or nil
        end
        j.ok = not short and not sweepWhy
        j.why = short and (raw and ("ran out of essence after %d"):format(j.made) or "no recipe for it any more")
          or sweepWhy
        j.doneAt = os.clock()
        if report(j) then table.remove(self.jobs, i) end
        self.last = j
      end
    end
    save()
    return sweepWhy
  end

  -- Forget a turtle (the setup screen): its barrel is the store's again, until it claims it.
  function self.forget(id)
    self.crafters[id] = nil
    files.write(CRAFTERS_FILE, self.crafters)
    f.wake()
  end

  ---------------------------------------------------------------- turtles finding their barrel

  local function takeMarker(cl)
    if not cl.at then return end
    local at, marker = cl.at, cl.marker
    cl.at = nil
    for slot, item in pairs(list(at) or {}) do
      if item.name == marker then
        toStore(at, slot, { name = marker, count = 1 })
        return
      end
    end
  end

  local function nextProbe(from, cl)
    cl.last = os.clock()
    while cl.i < #cl.candidates do
      cl.i = cl.i + 1
      local name = cl.candidates[cl.i]
      local l = list(name)
      if l then
        local has = {}
        for _, item in pairs(l) do has[item.name] = true end
        -- one item from the store that the barrel doesn't hold
        local marker
        for item, n in pairs(self.counts) do
          if n > 0 and not has[item] then marker = item break end
        end
        if not marker then
          claims[from] = nil
          return { ok = false, error = "the essence farm's barrels are empty: I need one item to find your barrel with" }
        end
        if fromStore(marker, name, 1) == 1 then
          cl.at, cl.marker = name, marker
          return { probe = marker }
        end
      end
    end
    claims[from] = nil
    notMine[from] = os.clock()
    if self.crafters[from] then
      self.crafters[from] = nil
      files.write(CRAFTERS_FILE, self.crafters)
    end
    return { ok = false, error = "your barrel isn't on the essence farm's cable" }
  end

  --   { type = "claim", role = "crafter", items = its list() } -> { ok, chest } / { probe = item } / { ok = false, error }
  --   { type = "claim", role, seen = true or false }           -> the same answers
  local function claimBarrel(from, msg)
    local cl = claims[from]
    if msg.seen ~= nil then
      if not cl then return { ok = false, error = "I lost track of where I was: try again" } end
      takeMarker(cl)
      if not msg.seen then return nextProbe(from, cl) end
      local name = cl.candidates[cl.i]
      claims[from] = nil
      for id, b in pairs(self.crafters) do
        if b == name then self.crafters[id] = nil end
      end
      self.crafters[from] = name
      files.write(CRAFTERS_FILE, self.crafters)
      f.wake()
      return { ok = true, chest = name }
    end
    if cl then takeMarker(cl) claims[from] = nil end
    -- the barrel it has already, if it still holds what the turtle sees
    local mine = self.crafters[from]
    if mine and sameItems(list(mine), msg.items) then return { ok = true, chest = mine } end
    if notMine[from] and os.clock() - notMine[from] < NOT_MINE_FOR then
      return { ok = false, error = "your barrel isn't on the essence farm's cable" }
    end
    if not self.stores[1] then self.scan() end
    -- only barrels holding just what the turtle sees (a new turtle's is
    -- empty): a pot barrel full of essence is never its
    local candidates = {}
    for _, name in ipairs(peripheral.getNames()) do
      if farm.isStore(name) and name ~= f.work.chest and not name:find(opts.pots, 1, true) and sameItems(list(name), msg.items or {}) then
        candidates[#candidates + 1] = name
      end
    end
    table.sort(candidates)
    cl = { candidates = candidates, i = 0 }
    claims[from] = cl
    return nextProbe(from, cl)
  end

  -- Claims from turtles, beside the factory's rounds.
  function self.loop()
    rednet.host(FARM_PROTOCOL, ("farm-%d"):format(os.getComputerID()))
    while true do
      local from, msg = rednet.receive(FARM_PROTOCOL, 5)
      if from and type(msg) == "table" and msg.type == "claim" then
        net.answer(from, FARM_PROTOCOL, msg, claimBarrel(from, msg))
      end
      for id, cl in pairs(claims) do
        if os.clock() - (cl.last or 0) > CLAIM_IDLE then
          takeMarker(cl)
          claims[id] = nil
        end
      end
    end
  end

  return self
end

return farm
