-- The factory's enricher (factory.lua loads it). Keeps every Mekanism
-- Enrichment Chamber (and Enriching Factory) added here fed with ores from
-- storage. An ore block gives 2 dust, 3 raw ores give 4 and a raw ore block
-- 12; the dust goes back into storage, and the smelter (here or on another
-- factory computer) smelts it into ingots: twice the ingots from ore blocks,
-- a third more from raw ores. Gem ores come out as gems (2 diamonds, 12
-- redstone, ...). Create crushing wheels work too (crushing lines): ore
-- blocks give 1.75 crushed ores on average, raw ores 1 (and XP nuggets), and
-- they take Create's zinc and other mods' ores the chambers can't. Create
-- washing fans (washers) wash crushed ores into 9 nuggets and a byproduct
-- (redstone from iron, quartz from gold, ...), and the storage computer
-- crafts the nuggets back into ingots.
--
-- CC can't put items into a Mekanism machine (its computer port hides the
-- slots), so each chamber has a feeder (lib/mekfeed.lua): a hopper on top,
-- or a barrel or chest that a pipe empties into it. It ejects its dust out
-- of its bottom into the chest under it: its output chest, emptied into
-- storage each round, or a storage input chest. A crushing line or washer
-- is only a feeder and an output chest: CC can't see Create's machines, so
-- the feeder is kept topped up and the line shown red when it stops going
-- down. Chambers are loaded first (more dust per ore); crushers take what's
-- left (config share), and the ores only they crush (zinc, silver, ...).
-- Washers take every crushed ore, and once a minute the storage computer is
-- asked to craft each 9 nuggets into an ingot ('prepare'), unless config
-- compact is false.
--
-- Every smelter (rank 2 in the chain) leaves the ores it takes alone.
local screen = require("lib.screen") -- flicker-free drawing
local mekfeed = require("lib.mekfeed") -- Mekanism machines fed through a hopper or barrel

local M = {}

local COMPACT_EVERY = 60 -- seconds between asking the storage computer to craft the washers' nuggets into ingots
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local WIDE = 48 -- characters across from which the queue and power columns are shown
-- Gem ores Create crushes (fluorite isn't one)
local CRUSH_GEMS = { coal = true, diamond = true, emerald = true, lapis = true, redstone = true, quartz = true }

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function matches(name, patterns)
  for _, p in ipairs(patterns) do
    if name:find(p) then return true end
  end
  return false
end

-- Raw ores go in 3 at a time (3 make 4 dust); everything else 1 at a time.
local function perOp(name)
  return (name:find("^[%w_]+:raw_") and not name:find("_block$")) and 3 or 1
end

-- f: the factory (factory.lua): ask, work, config, wake, taken.
function M.new(f)
  local config = f.config("enricher")
  -- Used if config.lua has none; see config.lua for what they mean.
  local METALS = config.metals or { "iron", "gold", "copper", "osmium", "tin", "lead", "uranium" }
  local GEMS = config.gems or { "coal", "diamond", "emerald", "lapis", "redstone", "quartz", "fluorite" }
  local KEEP = config.keep or {}
  -- Create crushing wheels also crush these metals' ores (none of them go into a chamber)
  local CRUSH_METALS = config.crushMetals or { "zinc", "silver", "nickel", "aluminum", "platinum", "quicksilver" }
  local SHARE = config.share ~= false -- crushers take the ores the chambers leave, not only the ones they can't take
  -- What washers take: Create's crushed ores
  local WASHES = config.washes or { "^create:crushed_raw_" }
  local COMPACT = config.compact ~= false -- with a washer, have the nuggets crafted into ingots
  -- Nuggets the washers make -> the ingot 9 of them craft into
  local NUGGETS = config.nuggets or {
    ["minecraft:iron_nugget"] = "minecraft:iron_ingot", ["minecraft:gold_nugget"] = "minecraft:gold_ingot",
    ["create:copper_nugget"] = "minecraft:copper_ingot", ["create:zinc_nugget"] = "create:zinc_ingot",
  }

  -- What goes in, as Lua patterns on item ids: ores of every kind above, and
  -- raw metals and their blocks. Smelters are sent these to leave alone.
  local TAKES = {}
  for _, m in ipairs(METALS) do
    TAKES[#TAKES + 1] = "[:_]" .. m .. "_ore$" -- iron_ore, deepslate_iron_ore, nether_gold_ore
    TAKES[#TAKES + 1] = "^[%w_]+:raw_" .. m .. "$"
    TAKES[#TAKES + 1] = "^[%w_]+:raw_" .. m .. "_block$"
  end
  for _, g in ipairs(GEMS) do TAKES[#TAKES + 1] = "[:_]" .. g .. "_ore$" end

  -- What crushing wheels take: the same ores and raw metals, more metals,
  -- and the gem ores Create has a recipe for.
  local CRUSHES = {}
  for _, list in ipairs({ METALS, CRUSH_METALS }) do
    for _, m in ipairs(list) do
      CRUSHES[#CRUSHES + 1] = "[:_]" .. m .. "_ore$"
      CRUSHES[#CRUSHES + 1] = "^[%w_]+:raw_" .. m .. "$"
      CRUSHES[#CRUSHES + 1] = "^[%w_]+:raw_" .. m .. "_block$"
    end
  end
  for _, g in ipairs(GEMS) do
    if CRUSH_GEMS[g] then CRUSHES[#CRUSHES + 1] = "[:_]" .. g .. "_ore$" end
  end

  local function takes(name) return matches(name, TAKES) end
  local function crushes(name) return matches(name, CRUSHES) end
  local function washes(name) return matches(name, WASHES) end

  local self = { id = "enrich", title = "Enricher", rank = 1, every = 5,
    what = "Ores -> dust, crushed ores, nuggets" }
  local machines = {} -- what the screen shows: each machine with its feeder and how it's doing
  local news -- { text, colour, untilTime }: a put-back item, shown for a minute
  local waiting = {} -- item -> how many in storage to enrich, for the screen
  local taking = {} -- the patterns smelters leave alone: what the chambers, crushers and washers set up take
  local compactAt = -math.huge -- when the nuggets were last sent to be crafted
  local compactNote -- why nuggets aren't being crafted into ingots, for the screen
  local noEnrich = {} -- item -> true: found not to go into a chamber (until restart)
  local anyChamber, anyCrusher, anyWasher = false, false, false
  local outStuck, outWhy, collected
  self.message = { "Looking for the storage computer...", "lightGray" }
  self.status = { "starting", "" }

  local function say(text, colour)
    self.message = { text, colour or "lightGray" }
    f.changed()
  end

  local function tell(text, colour)
    news = { text, colour, os.clock() + 60 }
    say(text, colour)
  end

  local function status(state, detail) self.status = { state, detail } end

  self.set = mekfeed.new({ name = "enricher", cmd = "factory", event = f.event, single = "enrichmentChamber",
    factory = "EnrichingFactory", what = "enrichment chamber", title = "Chamber", names = config.names,
    setSides = config.setSides ~= false, ask = f.ask, tell = tell, far = function() return f.work.remote end,
    taken = f.taken, lines = { "crush", "wash" }, pageTitle = "Chambers, crushers, washers" })

  -- Nothing is found by itself: every machine is added.
  function self.found() return {} end
  function self.uses() return self.set:uses() end
  function self.active() return #self.set:entries() > 0 end

  -- The patterns smelters leave alone (set every round, before anything waits).
  function self.takes() return taking end

  function self.summary()
    local c, k, w = 0, 0, 0
    for _, e in ipairs(self.set:entries()) do
      if e.line == "wash" then w = w + 1 elseif e.line then k = k + 1 else c = c + 1 end
    end
    local parts = {}
    local function add(n, what) if n > 0 then parts[#parts + 1] = ("%d %s"):format(n, what) end end
    add(c, "chambers")
    add(k, "crushers")
    add(w, "washers")
    return table.concat(parts, ", ")
  end

  -- With washers, the storage computer crafts their nuggets into ingots.
  function self.compacts() return anyWasher and COMPACT end

  ---------------------------------------------------------------- choosing

  -- The item to send next: what's already in the feeder or (a chamber has
  -- one slot) the chamber, else whatever there's most of that allowed(name).
  local function pickItem(m, avail, allowed)
    local current = mekfeed.current(m)
    if current then return current end
    local best, most = nil, 0
    for name, n in pairs(avail) do
      if allowed(name) and n >= (m.line and 1 or perOp(name)) and n > most then best, most = name, n end
    end
    return best
  end

  -- Washing makes nuggets: once a minute, have the storage computer craft
  -- every 9 of them into an ingot. 'prepare' tops up to a total that counts
  -- what's already being made, so an ingot already being crafted is left be.
  local function compact(counts)
    if os.clock() - compactAt < COMPACT_EVERY then return end
    compactAt, compactNote = os.clock(), nil
    for nugget, ingot in pairs(NUGGETS) do
      local n = math.floor(((counts[nugget] or 0) - (KEEP[nugget] or 0)) / 9)
      if n > 0 then
        local now = f.ask({ type = "prepare", items = { [ingot] = 0 } })
        local making = now and type(now.crafting) == "table" and now.crafting[ingot] or 0
        if now and making == 0 then
          local reply = f.ask({ type = "prepare", items = { [ingot] = (counts[ingot] or 0) + n } })
          local why = reply and type(reply.cantCraft) == "table" and reply.cantCraft[ingot]
          if why then
            compactNote = ("%ss aren't crafted into ingots: %s"):format(nice(nugget), why)
          elseif reply and reply.craftProblem then
            compactNote = ("Crafting %ss into ingots: %s"):format(nice(nugget), reply.craftProblem)
          end
        end
      end
    end
  end

  ---------------------------------------------------------------- a round

  -- Before the storage computer is asked: the machines are read, what the
  -- smelters leave alone is set (so a smelter never hears "none" mid-round;
  -- a machine that can't be loaded just now still means the ores wait for
  -- it, as dust and crushed ores give more ingots), and far away the output
  -- chests empty into the ender chest here first, so they never wait on it.
  function self.read(remote, remoteInput)
    machines = self.set:read()
    anyChamber, anyCrusher, anyWasher = false, false, false
    for _, m in ipairs(machines) do
      if m.line == "wash" then
        anyWasher = true
      elseif m.line then
        anyCrusher = true
      else
        anyChamber = true
      end
    end
    local leave = {}
    for _, p in ipairs(anyChamber and TAKES or {}) do leave[#leave + 1] = p end
    for _, p in ipairs(anyCrusher and CRUSHES or {}) do leave[#leave + 1] = p end
    for _, p in ipairs(anyWasher and WASHES or {}) do leave[#leave + 1] = p end
    taking = leave
    outStuck, outWhy, collected = false, nil, false
    if remote then
      local _
      _, outStuck, outWhy = self.set:collect(machines, remoteInput)
      collected = true
    end
  end

  function self.round(r)
    local work = f.work
    if #machines == 0 then
      say("Nothing set up yet: add a chamber, crusher or washer on the setup screen.", "orange")
      status("waiting", "nothing set up")
      return
    end
    local kinds = (anyChamber and 1 or 0) + (anyCrusher and 1 or 0) + (anyWasher and 1 or 0)
    local noun = kinds > 1 and "machines" or anyWasher and "washers" or anyCrusher and "crushers" or "chambers"

    -- far away, put-backs go home through the ender chest (or the return
    -- one), and nothing is loaded without the work chest
    local useWork = r.useWork
    local input, avail = r.input, {}
    for name, n in pairs(r.stock.counts) do
      if ((anyChamber and takes(name)) or (anyCrusher and crushes(name)) or (anyWasher and washes(name)))
        and n > (KEEP[name] or 0) then
        avail[name] = n - (KEEP[name] or 0)
      end
    end
    if anyWasher and COMPACT then compact(r.stock.counts) end
    waiting = {}
    for name, n in pairs(avail) do waiting[name] = n end

    local unsure, problem = r.unsure, r.feedProblem
    -- the dust in the output chests goes home first, so they never fill up
    if not collected then
      local _
      _, outStuck, outWhy = self.set:collect(machines, input)
    end
    if outWhy then
      problem = problem or outWhy
    elseif outStuck then
      problem = problem or ("the %s is full: dust is waiting in the output chests"):format(work.remote and "ender chest" or "storage input chest")
    end
    self.set:unstick(machines, input, function(m, item)
      noEnrich[item.name] = true
      tell(("%s didn't go into %s: put it back. Is its hopper on top, or a pipe pulling from its barrel?")
        :format(nice(item.name), m.title), "orange")
    end)

    -- fill the feeders, chambers first (more dust per ore), then the
    -- crushers and washers (they share what there is); with a work chest
    -- each load is noted down and fetched for all at once below
    local sent = 0
    local plan = useWork and {} or nil
    local function forChamber(name) return takes(name) and not noEnrich[name] end
    -- without config share, only what no chamber would take while there are chambers
    local function forCrusher(name) return crushes(name) and (SHARE or not anyChamber or not takes(name)) end
    local allowed = { crush = forCrusher, wash = washes }
    local order = {}
    for _, m in ipairs(machines) do
      if not m.line then order[#order + 1] = m end
    end
    for _, m in ipairs(machines) do
      if m.line then order[#order + 1] = m end
    end
    for _, m in ipairs(order) do
      m.item = nil
      if mekfeed.ready(m) and not unsure[m.entry.feeder] then
        local name = pickItem(m, avail, m.line and allowed[m.line] or forChamber)
        m.item = name
        if name and (avail[name] or 0) > 0 then
          local n = math.min(mekfeed.space(m, name), avail[name], SEND_MAX)
          local per = m.line and 1 or perOp(name)
          if per > 1 then n = n - (mekfeed.inputOf(m, name) + (m.feed[name] or 0) + n) % per end
          if n > 0 and plan then
            plan[#plan + 1] = { m = m, name = name, n = n }
            avail[name] = avail[name] - n
          elseif n > 0 then
            local reply = f.ask({ type = "send", to = m.entry.feeder, items = { [name] = n } })
            local got = reply and type(reply.sent) == "table" and reply.sent[name] or 0
            if reply and reply.error then problem = reply.error end
            if not reply then problem = "the storage computer didn't answer while loading " .. m.title end
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
      local reply, why = work:fill(items, 0)
      if reply and reply.error and not reply.nochest then problem = reply.error end
      if not reply and next(items) then problem = why end
      for _, p in ipairs(plan) do
        local got = work:move(p.name, p.m.entry.feeder, nil, p.n)
        mekfeed.added(p.m, p.name, got)
        avail[p.name] = avail[p.name] + p.n - got
        sent = sent + got
      end
      work:empty(input)
    end

    -- how each machine is doing, for the screen
    local working, broken = 0, 0
    for _, m in ipairs(machines) do
      local queued = mekfeed.inputOf(m) + (m.feedTotal or 0)
      m.queued = queued
      if m.line then
        -- nothing on a Create line can be read but its feeder
        local colour, text = mekfeed.status(m)
        if colour == "red" then
          m.state, m.colour = text, "red"
        elseif queued > 0 then
          m.state, m.colour = m.line == "wash" and "washing" or "crushing", "lime"
          m.item = m.item or mekfeed.current(m)
        else
          m.state, m.colour = "idle", "gray"
        end
      elseif not m.present then
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
      if m.colour == "red" then
        broken = broken + 1
      elseif m.state == "enriching" or m.state == "crushing" or m.state == "washing" then
        working = working + 1
      end
    end

    -- far away without a far-away work chest, the storage computer can't see
    -- the feeders: say what to do
    if problem and not work.chest and (problem:find("network") or problem:find("can't see") or problem:find("exist")) then
      problem = problem .. ". Far from the storage system? Setup, Work chest, Far away"
    end
    local noOutput
    for _, m in ipairs(machines) do
      if not m.entry.output then noOutput = noOutput or m end
    end

    if news and os.clock() < news[3] then
      self.message = { news[1], news[2] }
    elseif problem then
      say("Couldn't move items: " .. problem, "red")
    elseif work.problem then
      say(("Not using the work chest: %s."):format(work.problem), "orange")
    elseif anyWasher and COMPACT and compactNote then
      say(compactNote, "orange")
    elseif broken > 0 then
      local m
      for _, x in ipairs(machines) do
        if x.colour == "red" then m = m or x end
      end
      local why = {
        ["no feeder"] = "its feeder isn't on the network",
        ["not moving"] = "nothing goes through it: is it turning, and is the funnel taking from its feeder?",
        ["no output chest"] = "its output chest isn't on the network",
        ["no power"] = "it has no power",
        ["output full"] = "its dust isn't going anywhere: chest under it, Auto-eject on?",
        ["not on network"] = "it isn't on the network",
      }
      say(("%s: %s"):format(m.title, why[m.state] or m.state), "red")
    elseif work.remote and noOutput then
      -- far away nothing else empties the chest under it
      say(("%s has no output chest: pick the chest it puts things in (Setup, Machines), unless that's the ender chest.")
        :format(noOutput.title), "orange")
    elseif sent > 0 then
      say(("Sent %d ores to the %s."):format(sent, noun))
    elseif working == 0 then
      say("Nothing to enrich.")
    else
      say(("Working in %d of %d %s."):format(working, #machines, noun))
    end
    status(broken > 0 and "alert" or working > 0 and "running" or "idle",
      ("%d of %d %s working"):format(working, #machines, noun))
  end

  ---------------------------------------------------------------- screen

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

  function self.key()
    local total, top = waitingText()
    local key = { self.message[1], self.message[2], total, top }
    for _, m in ipairs(machines) do
      key[#key + 1] = table.concat({ m.title, m.item or "", m.queued or 0, m.energy or 0, m.state or "" }, "/")
    end
    return table.concat(key, "|")
  end

  -- The terminal page, under the factory's tab bar (row 1).
  function self.draw(win, w, h)
    local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end
    local fit = screen.fit
    local total, top = waitingText()
    -- a narrow screen drops the queue and power columns, and wraps the message
    local wide = w >= WIDE
    local doingX = wide and 40 or w - 11
    local oreW = (wide and 29 or doingX) - 16
    put(2, 3, "Machine", "yellow")
    put(14, 3, "Ore", "yellow")
    if wide then
      put(29, 3, "Queue", "yellow")
      put(35, 3, "Pwr", "yellow")
    end
    put(doingX, 3, "Doing", "yellow")
    local footer = {}
    local function add(text, colour) footer[#footer + 1] = { text, colour } end
    add(total > 0 and ("To enrich: %d (%s)"):format(total, top) or "No ores in storage.", total > 0 and "white" or "gray")
    for _, line in ipairs(screen.wrap(self.message[1], w, wide and 1 or 3)) do add(line, self.message[2]) end
    add(wide and "Tab: next page  F1 or Setup: the setup screen" or "F1: setup", "gray")
    local shown = h - 4 - #footer
    for i = 1, math.min(shown, #machines) do
      local m, y = machines[i], 3 + i
      put(2, y, fit(m.title, 11), "white")
      put(14, y, fit(m.item and nice(m.item) or "-", oreW), "lightGray")
      if wide then
        put(29, y, fit(tostring(m.queued or 0), 5), "white")
        local pct = math.floor((m.energy or 0) * 100 + 0.5)
        if m.line then
          put(35, y, "-", "gray") -- a Create line has no power to read
        else
          put(35, y, fit(pct .. "%", 4), pct < 10 and "red" or pct < 50 and "orange" or "lime")
        end
      end
      put(doingX, y, fit(m.state or "...", w - doingX + 1), m.colour or "gray")
    end
    if #machines > shown then put(2, 4 + shown, ("...and %d more"):format(#machines - shown), "gray") end
    if #machines == 0 then put(2, 4, "No machines yet.", "gray") end
    for i, line in ipairs(footer) do
      put(i == 1 and 2 or 1, h - #footer + i, fit(line[1], i == 1 and w - 2 or w), line[2])
    end
  end

  function self.tiles()
    local tiles = {}
    for _, m in ipairs(machines) do
      local item = m.item or (m.inputs[1] and m.inputs[1].name) or mekfeed.current(m)
      local colour, text = mekfeed.status(m, item and nice(item))
      tiles[#tiles + 1] = { m.title, text, colour }
    end
    return tiles
  end

  function self.event() return false end
  function self.command() return false end

  return self
end

return M
