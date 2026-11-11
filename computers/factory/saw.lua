-- The factory's saw (factory.lua loads it). Runs Create Mechanical Saws on
-- request: nothing is cut until someone asks. A saw does Create's cutting
-- recipes, every stonecutter recipe, and the wood ones Create makes for
-- itself: a log into its stripped kind, a stripped log into 6 planks,
-- planks into stairs, slabs, fences, doors and so on. They come from
-- /saw_pack.lua if it's there (a modpack's, from tools/saw-recipes.mjs),
-- else /saw_recipes.lua (vanilla and Create, from the same tool), plus
-- config's own. Requests come from its page (tap +1, +8 or +64 by what you
-- want, on the terminal or the monitor's Saw page), from 'factory saw', or
-- from the craft overseer: it's told what the saws here can make, so a
-- crafting plan that needs stripped logs (or anything only a saw makes) has
-- this make it first.
--
-- CC can't see a saw at all, so a sawing line (lib/mekfeed.lua) is only two
-- chests on the storage network: its feeder, which a funnel empties onto a
-- belt running into the saw (facing up, in line with the belt), and its
-- output chest, which the saw puts what it cuts out into. One saw is one
-- cut. What arrives in the output chest is counted towards the requests,
-- then goes into storage; an input that comes out uncut ends its request.
--
-- An item with several recipes (planks: stairs, slabs, a fence...; stone:
-- bricks, slabs...) makes them in turn unless the saw's filter picks one,
-- and CC can't set it. So each line can be told what its saw's filter is
-- set to (the setup screen, or 'factory saw filter'): then it only gets
-- what makes that. A line with no filter only gets items with one recipe
-- (logs, stripped logs). Only what some line can make is offered.
--
-- The items a request waits on are left alone by the smelter (rank 0 in the
-- chain), so a charcoal order doesn't burn its logs first.
local screen = require("lib.screen") -- flicker-free drawing
local mekfeed = require("lib.mekfeed") -- Create lines and their feeders
local files = require("lib.files") -- crash-safe save files

local M = {}

local PACK_FILE = "/saw_pack.lua" -- a modpack's recipes (tools/saw-recipes.mjs): used instead of the built-in ones
local BUILT_IN_FILE = "/saw_recipes.lua" -- the recipes that come with the factory: vanilla and Create
local REQUEST_DIR = "/.factory_saw" -- a file per request, so a request typed in another tab is never lost
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local GIVE_UP = 600 -- seconds a craft overseer's request may go with nothing loaded or made before it's handed back
local SHORT_AFTER = 60 -- seconds with everything sent, none of it in a feeder and nothing made, before more is sent
local MAKES_EVERY = 60 -- seconds between telling the craft overseer what the saws can make
local QUEUE_SHOWN = 3 -- requests listed under the recipes
local BUTTONS = { 1, 8, 64 } -- the request buttons by each recipe
local KINDS = { "Create cutting", "stonecutter", "Create wood" } -- a recipe's kind, by number, for 'factory saw find'

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function escape(name) return "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "$" end

local function capital(text) return (text:gsub("^%l", string.upper)) end

-- A recipe file as tools/saw-recipes.mjs writes it: { names, recipes = {
-- { make, count, from, kind } } } with names numbered. nil and why if it
-- can't be read.
local function readRecipes(path)
  if not fs.exists(path) then return nil, "missing" end
  local fn, err = loadfile(path, "t", {})
  if not fn then return nil, err end
  local ok, t = pcall(fn)
  if not ok or type(t) ~= "table" or type(t.names) ~= "table" or type(t.recipes) ~= "table" then
    return nil, ok and "not a saw recipe file" or tostring(t)
  end
  return t
end

-- f: the factory (factory.lua): ask, craft, work, config, wake, changed, event, taken.
function M.new(f)
  local config = f.config("saw")
  local KEEP = config.keep or {} -- item -> how many to leave in storage
  local HIDE = config.hide or {} -- items not to make, e.g. { "minecraft:oak_button" }
  local OFFER = config.offer ~= false -- tell the craft overseer what the saws can make

  -- the recipes: the pack's (else the built-in ones), then config's own, less the hidden ones
  local recipes, byKey, byFrom = {}, {}, {}
  local source, loadNote = nil, nil
  local hidden = {}
  for _, name in ipairs(HIDE) do hidden[name] = true end
  local function addRecipe(make, from, count, kind, title)
    if type(make) ~= "string" or type(from) ~= "string" or make == from or hidden[make] then return end
    local key = make .. "<" .. from
    if byKey[key] then return end
    local rc = { make = make, from = from, count = math.max(1, math.floor(tonumber(count) or 1)), kind = kind,
      title = title, key = key }
    recipes[#recipes + 1] = rc
    byKey[key] = rc
    byFrom[from] = byFrom[from] or {}
    table.insert(byFrom[from], rc)
  end
  do
    local t, why = readRecipes(PACK_FILE)
    source = t and "saw_pack.lua"
    if not t then
      if why ~= "missing" then loadNote = ("saw_pack.lua can't be read (%s): using the built-in recipes"):format(why) end
      t, why = readRecipes(BUILT_IN_FILE)
      source = t and "saw_recipes.lua"
      if not t then loadNote = ("no saw recipes: saw_recipes.lua %s ('install update')"):format(why) end
    end
    for _, r in ipairs(t and t.recipes or {}) do
      if type(r) == "table" then addRecipe(t.names[r[1]], t.names[r[3]], r[2], r[4]) end
    end
  end
  for _, r in ipairs(config.recipes or {}) do
    if type(r) == "table" then addRecipe(r.make, r.from, r.count, 0, r.title) end
  end

  local function titleOf(rc)
    rc.title = rc.title or capital(nice(rc.make))
    return rc.title
  end
  -- An item with more than one recipe: the saw only picks one with its filter.
  local function several(from) return #(byFrom[from] or {}) > 1 end

  local self = { id = "saw", title = "Saw", short = "Saw", rank = 0, every = 5, what = "Requests -> stripped logs, planks, stone cuts" }
  local machines = {}
  local requests = {} -- every request, oldest first (REQUEST_DIR)
  local counts = {} -- the storage computer's counts, for the screen
  local shown = {} -- the recipes the page lists: ones a line here can make from what's stored, or that are asked for
  local hiddenCount = 0 -- stored items only a filtered saw could cut, for the page
  local progress = {} -- request at -> when it last had something loaded or made (os.clock)
  local lastCounts = {} -- item -> its stored count last round, for lines whose output is an ender chest
  local collectedPending = {} -- item -> how many output chests moved to storage that the stored count hasn't shown yet
  local news -- { text, colour, untilTime }
  local outStuck, outWhy, collected
  local makesKey, makesAt, makesNote = nil, -math.huge, nil
  local scroll = 0 -- the first recipe shown
  local picked = 1 -- the recipe the terminal's keys ask for (a basic computer has no mouse)
  local zones = {} -- target -> { { x1, x2, y, action } }: what a tap does on the terminal or monitor
  self.message = { loadNote or "Looking for the storage computer...", loadNote and "orange" or "lightGray" }
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

  ---------------------------------------------------------------- the lines

  -- A line can make a recipe when its saw's filter is set to what the
  -- recipe makes, or it has no filter and the item has only this recipe.
  local function canRun(entry, rc)
    if entry.filter then return entry.filter == rc.make end
    return not several(rc.from)
  end

  -- The lines' entries, read once a round (or command) rather than for each of thousands of recipes.
  local lineList = {}
  local function refreshLines() lineList = self.set:entries() end

  local function anyLine(rc)
    for _, e in ipairs(lineList) do
      if canRun(e, rc) then return true end
    end
    return false
  end

  -- The setup screen's Filter row for a line: the outputs of items with
  -- several recipes, those in storage first (typing narrows the list).
  local function filterRows(ui, _, entry, change)
    local function pickPage()
      local reply = f.ask({ type = "stock" }, 5)
      local stock = reply and type(reply.counts) == "table" and reply.counts or {}
      local seen, list = {}, {}
      for _, rc in ipairs(recipes) do
        if several(rc.from) and not seen[rc.make] then
          seen[rc.make] = true
          list[#list + 1] = { make = rc.make, stored = (stock[rc.from] or 0) > 0 }
        end
      end
      table.sort(list, function(a, b)
        if a.stored ~= b.stored then return a.stored end
        return a.make < b.make
      end)
      return {
        title = "What its saw's filter is set to",
        hint = "Set the same item in the saw's filter slot. Type to narrow the list.",
        filter = true,
        rows = function()
          local out = { { label = "(none)", value = "only items with one recipe: logs, stripped logs", colour = "gray",
            act = function()
              ui:back()
              change("filter", nil, "No filter: it only gets items with one recipe.")
              f.wake()
            end } }
          for _, x in ipairs(list) do
            out[#out + 1] = { label = capital(nice(x.make)), value = x.make, colour = x.stored and "white" or "gray",
              act = function()
                ui:back()
                change("filter", x.make, ("Filter: %s. Set the same in the saw's filter slot."):format(nice(x.make)))
                f.wake()
              end }
          end
          return out
        end,
      }
    end
    return { { label = "Filter", value = entry.filter and nice(entry.filter) or "none: one-recipe items only",
      colour = entry.filter and "lightGray" or "gray", act = function() ui:open(pickPage()) end } }
  end

  -- lines only: no Mekanism machine is a saw
  self.set = mekfeed.new({ name = "saw", cmd = "factory", event = f.event, what = "sawing line", title = "Saw",
    names = config.names, ask = f.ask, tell = tell, far = function() return f.work.remote end,
    taken = f.taken, lines = { "saw" }, pageTitle = "Saws", lineRows = filterRows })

  function self.found() return {} end
  function self.uses() return self.set:uses() end
  function self.active() return #self.set:entries() > 0 end

  ---------------------------------------------------------------- requests

  local function loadRequests()
    local list = {}
    if fs.isDir(REQUEST_DIR) then
      for _, file in ipairs(fs.list(REQUEST_DIR)) do
        local r = files.read(REQUEST_DIR .. "/" .. file)
        if type(r) == "table" and type(r.count) == "number" then
          r.file = REQUEST_DIR .. "/" .. file
          r.made, r.sent = r.made or 0, r.sent or 0
          r.enderSent, r.enderMade = r.enderSent or 0, r.enderMade or 0
          r.recipe = byKey[r.key]
          list[#list + 1] = r
        end
      end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    return list
  end

  local function plain(r)
    return { key = r.key, count = r.count, made = r.made, sent = r.sent, enderSent = r.enderSent, enderMade = r.enderMade,
      at = r.at, job = r.job, done = r.done,
      ok = r.ok, why = r.why }
  end

  -- Only while its file is there: a request cancelled in another tab stays cancelled.
  local function saveRequest(r)
    if fs.exists(r.file) then files.write(r.file, plain(r)) end
  end

  local function newRequest(key, count, job)
    if not fs.isDir(REQUEST_DIR) then fs.makeDir(REQUEST_DIR) end
    local at = os.epoch("utc")
    local file = ("%s/%.0f"):format(REQUEST_DIR, at)
    while fs.exists(file) do
      at = at + 1
      file = ("%s/%.0f"):format(REQUEST_DIR, at)
    end
    files.write(file, { key = key, count = count, made = 0, sent = 0, at = at, job = job })
    return file
  end

  -- Ask for count more of what recipe makes (whole cuts: slabs come in
  -- twos): added to a request of yours for it that's still waiting, else a new one.
  local function request(rc, count)
    count = math.ceil(count / rc.count) * rc.count
    for _, q in ipairs(loadRequests()) do
      if q.key == rc.key and not q.job and not q.done then
        q.count = q.count + count
        saveRequest(q)
        f.wake()
        return
      end
    end
    newRequest(rc.key, count)
    f.wake()
  end

  -- How many a request still has to make, and how many inputs to send.
  local function left(q) return math.max(0, q.count - q.made) end
  local function toSend(q) return math.max(0, math.ceil(q.count / q.recipe.count) - q.sent) end

  -- How many of what a recipe makes what's stored would do.
  local function canMake(rc, avail)
    return math.max(0, (avail[rc.from] or 0) - (KEEP[rc.from] or 0)) * rc.count
  end

  -- Count what came out of the output chests towards the requests, oldest
  -- first; then an input that came out uncut ends its requests.
  local function credit(byName)
    -- they reach storage later: not to be counted again from the stored counts
    for name, n in pairs(byName) do collectedPending[name] = (collectedPending[name] or 0) + n end
    for _, q in ipairs(requests) do
      if not q.done and q.recipe then
        local n = math.min(byName[q.recipe.make] or 0, left(q))
        if n > 0 then
          q.made = q.made + n
          byName[q.recipe.make] = byName[q.recipe.make] - n
          progress[q.at] = os.clock()
          saveRequest(q)
        end
      end
    end
    -- only what no request took: what one saw makes can be another's input
    for _, q in ipairs(requests) do
      if not q.done and q.recipe and (byName[q.recipe.from] or 0) > 0 then
        q.done, q.ok = true, false
        q.why = ("%s came out uncut: is the saw's filter set to %s, or to nothing?"):format(nice(q.recipe.from),
          nice(q.recipe.make))
        tell(capital(q.why), "orange")
        saveRequest(q)
      end
    end
  end

  -- A line whose output is an ender chest (its twin a storage input chest)
  -- sends what it cuts straight home, where the factory can't see it
  -- arrive: it's counted from the stored count going up since last round,
  -- never more than that line was sent and hasn't been counted (so other
  -- things coming into storage aren't taken for it), less what the output
  -- chests here moved in.
  local function creditStock()
    local makes = {}
    for _, q in ipairs(requests) do
      if not q.done and q.recipe then makes[q.recipe.make] = true end
    end
    for make in pairs(makes) do
      local now = counts[make] or 0
      local delta = lastCounts[make] and now - lastCounts[make] or 0
      lastCounts[make] = now
      local pending = collectedPending[make] or 0
      local taken = math.min(math.max(delta, 0), pending)
      collectedPending[make] = pending - taken
      delta = delta - taken
      for _, q in ipairs(requests) do
        local rc = q.recipe
        if delta > 0 and not q.done and rc and rc.make == make then
          local n = math.min(delta, left(q), math.max(0, q.enderSent * rc.count - q.enderMade))
          if n > 0 then
            q.made, q.enderMade = q.made + n, q.enderMade + n
            delta = delta - n
            progress[q.at] = os.clock()
            saveRequest(q)
          end
        end
      end
    end
    for make in pairs(lastCounts) do
      if not makes[make] then lastCounts[make], collectedPending[make] = nil, nil end
    end
  end

  ---------------------------------------------------------------- the craft overseer

  -- What a line here can make, as the craft overseer plans it: one in, count out.
  local function asCrafts()
    local out = {}
    for _, rc in ipairs(recipes) do
      if anyLine(rc) then out[#out + 1] = { make = rc.make, count = rc.count, rows = { "A" }, keys = { A = rc.from } } end
    end
    return out
  end

  -- Tell the craft overseer what the saws can make (none without a saw),
  -- when it changes and every so often, as it forgets in time.
  local function offer()
    if not OFFER then return end
    local crafts = asCrafts()
    local filters = {}
    for _, e in ipairs(lineList) do filters[#filters + 1] = e.filter or "-" end
    local key = #crafts .. "|" .. table.concat(filters, ",")
    if key == makesKey and os.clock() - makesAt < MAKES_EVERY then return end
    local reply = f.craft({ type = "makes", via = "saw", recipes = crafts }, 5)
    makesAt = os.clock()
    if reply and reply.ok then
      makesKey, makesNote = key, nil
    else
      makesKey = nil
      makesNote = reply and reply.error or "the craft overseer doesn't take sawing orders: is it running, and updated?"
    end
  end

  -- A craft overseer's request is finished (or given up on): tell it. True
  -- once it has heard.
  local function report(q)
    if not q.job then return true end
    local reply = f.craft({ type = "jobdone", job = q.job, ok = q.ok, why = q.why }, 5)
    return reply ~= nil
  end

  -- From the craft overseer (factory protocol): 'saw' (make this for one of
  -- its plans) and 'cancel'. The reply, or nil if it isn't one.
  function self.request(from, msg)
    if msg.type == "saw" then
      refreshLines()
      if not self.active() then return { ok = false, why = "no saw here" } end
      local rc
      for _, item in pairs(type(msg.grid) == "table" and msg.grid or {}) do
        rc = rc or byKey[tostring(msg.make) .. "<" .. tostring(item)]
      end
      local count = math.floor(tonumber(msg.count) or 0)
      if not rc or count < 1 then return { ok = false, why = "this saw has no recipe for it" } end
      if not anyLine(rc) then return { ok = false, why = "no saw here has its filter on " .. nice(rc.make) } end
      newRequest(rc.key, count, msg.job)
      f.wake()
      return { ok = true }
    elseif msg.type == "cancel" then
      for _, q in ipairs(loadRequests()) do
        if q.job and q.job == msg.job then fs.delete(q.file) end
      end
      f.wake()
      return { ok = true }
    end
    return nil
  end

  -- What the smelter leaves alone: the inputs of every request still waiting.
  local taking = {}
  function self.takes() return taking end

  function self.summary()
    local n = #self.set:entries()
    local waiting = 0
    for _, q in ipairs(requests) do
      if not q.done then waiting = waiting + 1 end
    end
    return ("%d saw%s%s"):format(n, n == 1 and "" or "s", waiting > 0 and (", %d requests"):format(waiting) or "")
  end

  ---------------------------------------------------------------- a round

  function self.read(remote, remoteInput)
    machines = self.set:read()
    refreshLines()
    requests = loadRequests()
    local seen, list = {}, {}
    for _, q in ipairs(requests) do
      if q.recipe and not q.done and not seen[q.recipe.from] then
        seen[q.recipe.from] = true
        list[#list + 1] = escape(q.recipe.from)
      end
    end
    taking = list
    outStuck, outWhy, collected = false, nil, false
    if remote then
      local _, byName
      _, outStuck, outWhy, byName = self.set:collect(machines, remoteInput)
      credit(byName)
      collected = true
    end
  end

  -- The page's list: recipes a line here can make from what's stored, and
  -- the ones asked for, by name.
  local function listShown()
    local list, seen, only = {}, {}, 0
    for _, q in ipairs(requests) do
      if q.recipe and not seen[q.recipe.key] then
        seen[q.recipe.key] = true
        list[#list + 1] = q.recipe
      end
    end
    for name, n in pairs(counts) do
      if n > (KEEP[name] or 0) and byFrom[name] then
        local any = false
        for _, rc in ipairs(byFrom[name]) do
          if anyLine(rc) then
            any = true
            if not seen[rc.key] then
              seen[rc.key] = true
              list[#list + 1] = rc
            end
          end
        end
        if not any then only = only + 1 end
      end
    end
    table.sort(list, function(a, b) return titleOf(a) < titleOf(b) end)
    shown, hiddenCount = list, only
  end

  function self.round(r)
    local work = f.work
    counts = r.stock.counts
    local problem = r.feedProblem
    offer()
    listShown()
    if #machines == 0 then
      say("Nothing set up yet: add a sawing line on the setup screen.", "orange")
      status("waiting", "nothing set up")
      return
    end
    local input = r.input
    local avail = {}
    for name, n in pairs(counts) do avail[name] = n end

    if not collected then
      local _, byName
      _, outStuck, outWhy, byName = self.set:collect(machines, input)
      credit(byName)
    end
    creditStock()

    -- finished requests: done, or a craft overseer's that waited too long
    local now = os.clock()
    for _, q in ipairs(requests) do
      progress[q.at] = progress[q.at] or now
      if not q.recipe and not q.done then
        q.done, q.ok, q.why = true, false, "this saw has no recipe for it any more"
      elseif not q.done and left(q) == 0 then
        q.done, q.ok = true, true
        if not q.job then tell(("Made %d %s."):format(q.made, titleOf(q.recipe)), "lime") end
      elseif q.job and not q.done and now - progress[q.at] > GIVE_UP then
        q.done, q.ok, q.why = true, false, q.state or "nothing to make it from"
      end
      if q.done then
        saveRequest(q)
        if report(q) then fs.delete(q.file) end
      end
    end
    local open = {}
    for _, q in ipairs(requests) do
      if not q.done and fs.exists(q.file) then open[#open + 1] = q end
    end
    requests = open

    -- the inputs, oldest request first, into whichever lines can make it and
    -- have room; with a work chest each load is noted down and fetched for
    -- all at once below
    local plan = r.useWork and {} or nil
    local sent = 0
    for _, q in ipairs(requests) do
      q.state = nil
      local rc = q.recipe
      -- everything sent, none of it waiting in a feeder, nothing made for a
      -- while: the saw gives fewer than the recipe says, so send the rest
      if toSend(q) == 0 and left(q) > 0 and now - progress[q.at] > SHORT_AFTER then
        local inFeeders = 0
        for _, m in ipairs(machines) do inFeeders = inFeeders + (m.feed[rc.from] or 0) end
        if inFeeders == 0 then
          q.sent = math.max(0, q.sent - math.ceil(left(q) / rc.count))
          q.dirty, progress[q.at] = true, now
        end
      end
      local lines = 0
      for _, m in ipairs(machines) do
        if canRun(m.entry, rc) then
          lines = lines + 1
          local want = toSend(q)
          local have = math.max(0, (avail[rc.from] or 0) - (KEEP[rc.from] or 0))
          if want > 0 and have > 0 and mekfeed.ready(m) and not r.unsure[m.entry.feeder] and m.outOk then
            local n = math.min(mekfeed.space(m, rc.from), have, want, SEND_MAX)
            if n > 0 then
              local got = n
              if plan then
                plan[#plan + 1] = { m = m, q = q, name = rc.from, n = n, ender = mekfeed.isEnder(m.entry.output) }
              else
                local reply = f.ask({ type = "send", to = m.entry.feeder, items = { [rc.from] = n } })
                got = reply and type(reply.sent) == "table" and reply.sent[rc.from] or 0
                if reply and reply.error then problem = reply.error end
                if not reply then problem = "the storage computer didn't answer while loading " .. m.title end
              end
              mekfeed.added(m, rc.from, got)
              avail[rc.from] = (avail[rc.from] or 0) - got
              q.sent = q.sent + got
              if mekfeed.isEnder(m.entry.output) then q.enderSent = q.enderSent + got end
              sent = sent + got
              if got > 0 then progress[q.at], q.dirty = now, true end
            end
          end
        end
      end
      if lines == 0 then
        q.state = ("needs a saw with its filter on %s"):format(nice(rc.make))
      elseif toSend(q) > 0 and canMake(rc, avail) == 0 then
        q.state = "waiting for " .. nice(rc.from)
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
        if got < p.n then
          mekfeed.added(p.m, p.name, got - p.n)
          p.q.sent = p.q.sent - (p.n - got)
          if p.ender then p.q.enderSent = p.q.enderSent - (p.n - got) end
          sent = sent - (p.n - got)
        end
      end
      work:empty(input)
    end
    for _, q in ipairs(requests) do
      if q.dirty then saveRequest(q) end
      q.dirty = nil
    end

    -- how each line and request is doing
    local working, broken = 0, 0
    for _, m in ipairs(machines) do
      local item = mekfeed.current(m)
      local colour, text = mekfeed.status(m, item and ("cutting " .. nice(item)))
      m.state, m.tile = text, colour
      m.colour = ({ red = "red", orange = "lime", yellow = "lime", lime = "gray" })[colour] or "gray"
      if colour == "red" then broken = broken + 1
      elseif colour == "orange" or colour == "yellow" then working = working + 1 end
    end
    for _, q in ipairs(requests) do
      if not q.state then q.state = toSend(q) > 0 and "queued" or "on the saw" end
    end

    if outWhy then problem = problem or outWhy
    elseif outStuck then
      problem = problem or ("the %s is full: what's cut is waiting in the output chests"):format(work.remote and "ender chest" or "storage input chest")
    end
    if news and os.clock() < news[3] then
      self.message = { news[1], news[2] }
    elseif problem then
      say("Couldn't move items: " .. problem, "red")
    elseif work.problem then
      say(("Not using the work chest: %s."):format(work.problem), "orange")
    elseif loadNote then
      say(capital(loadNote) .. ".", "orange")
    elseif broken > 0 then
      local m
      for _, x in ipairs(machines) do
        if x.tile == "red" then m = m or x end
      end
      local why = {
        ["no feeder"] = "its feeder isn't on the network",
        ["no output chest"] = "its output chest isn't on the network",
        ["not moving"] = "nothing goes through it: is the saw turning, and is the funnel taking from its feeder?",
      }
      say(("%s: %s"):format(m.title, why[m.state] or m.state), "red")
    elseif makesNote and #requests == 0 then
      say(makesNote, "orange")
    elseif #requests == 0 then
      say("Tap +1, +8 or +64 by what you want cut.")
    elseif sent > 0 then
      say(("Sent %d to the saw%s."):format(sent, #machines == 1 and "" or "s"))
    else
      say(("%s: %s."):format(titleOf(requests[1].recipe), requests[1].state))
    end
    status(broken > 0 and "alert" or working > 0 and "running" or "idle",
      ("%d of %d saws working, %d requests"):format(working, #machines, #requests))
  end

  ---------------------------------------------------------------- screen

  local function zone(target, x1, x2, y, action)
    zones[target] = zones[target] or {}
    local list = zones[target]
    list[#list + 1] = { x1, x2, y, action }
  end

  local function button(win, target, x, y, text, action, fg, bg)
    screen.put(win, x, y, text, fg or "black", bg or "lightGray")
    zone(target, x, x + #text - 1, y, action)
    return x + #text + 1
  end

  -- The recipes a line here can make from what's stored, each with how
  -- many and the request buttons, then the requests (tap x to cancel one).
  local function drawRequests(win, w, h, target, footer)
    zones[target] = {}
    local fit = screen.fit
    local btnW = 0
    for _, n in ipairs(BUTTONS) do btnW = btnW + #(" +" .. n .. " ") + 1 end
    local bx = w - btnW + 1
    local canR = bx - 2
    screen.put(win, 2, 3, "Make", "yellow")
    screen.put(win, canR - 2, 3, "Can", "yellow")
    screen.put(win, bx, 3, "Request", "yellow")
    local queueRows = math.min(QUEUE_SHOWN, #requests)
    local rows = h - 4 - #footer - (queueRows > 0 and queueRows + 1 or 0)
    local keyed = target == "terminal"
    if keyed then
      picked = math.max(1, math.min(picked, #shown))
      if picked <= scroll then scroll = picked - 1 end
      if picked > scroll + rows then scroll = picked - rows end
    end
    scroll = math.max(0, math.min(scroll, #shown - rows))
    for i = 1, rows do
      local rc, y = shown[scroll + i], 3 + i
      if rc then
        local n = canMake(rc, counts)
        local bg = keyed and scroll + i == picked and "gray" or "black"
        local nameW = canR - 7
        local title = titleOf(rc)
        screen.put(win, 1, y, (" "):rep(canR + 1), "white", bg)
        screen.put(win, 2, y, fit(title, nameW), n > 0 and "white" or "lightGray", bg)
        local from = " from " .. nice(rc.from)
        if #title + 2 < nameW then screen.put(win, 2 + #title, y, fit(from, nameW - #title), bg == "gray" and "lightGray" or "gray", bg) end
        local can = n > 9999 and "9999+" or tostring(n)
        screen.put(win, canR - #can + 1, y, can, n > 0 and "lime" or bg == "gray" and "lightGray" or "gray", bg)
        local x = bx
        for _, k in ipairs(BUTTONS) do
          x = button(win, target, x, y, (" +%d "):format(k), { add = rc, n = k }, "black", n > 0 and "lightGray" or "gray")
        end
      end
    end
    if #shown == 0 then
      screen.put(win, 2, 4, fit(#machines == 0 and "No saws yet." or "Nothing in storage a saw here can cut.", w - 2), "gray")
    end
    if hiddenCount > 0 and #shown < rows then
      screen.put(win, 2, 4 + math.max(#shown, 1), fit(("%d more stored items need a saw with a filter: 'factory saw find'"):format(hiddenCount), w - 2), "gray")
    end
    if #shown > rows then
      screen.put(win, w, 4, scroll > 0 and "^" or " ", "yellow")
      screen.put(win, w, 3 + rows, scroll + rows < #shown and "v" or " ", "yellow")
      zone(target, w, w, 4, { scroll = -rows })
      zone(target, w, w, 3 + rows, { scroll = rows })
    end
    if queueRows > 0 then
      local y = 4 + rows
      screen.put(win, 2, y, ("Requests (%d)"):format(#requests), "yellow")
      for i = 1, queueRows do
        local q = requests[i]
        local text = ("%s %d/%d%s: %s"):format(titleOf(q.recipe), q.made, q.count, q.job and " (overseer)" or "", q.state or "queued")
        screen.put(win, 2, y + i, fit(text, w - 6), "white")
        button(win, target, w - 3, y + i, " x ", { cancel = q.file }, "white", "red")
      end
    end
    for i, line in ipairs(footer) do screen.put(win, 1, h - #footer + i, fit(line[1], w), line[2]) end
  end

  function self.key()
    local key = { self.message[1], self.message[2], scroll, picked, #shown, hiddenCount }
    for _, rc in ipairs(shown) do key[#key + 1] = rc.key .. "=" .. canMake(rc, counts) end
    for _, q in ipairs(requests) do key[#key + 1] = table.concat({ q.key, q.made, q.count, q.state or "" }, "/") end
    for _, m in ipairs(machines) do key[#key + 1] = table.concat({ m.title, m.state or "" }, "/") end
    return table.concat(key, "|")
  end

  -- The terminal page, under the factory's tab bar (row 1).
  function self.draw(win, w, h)
    local busy = 0
    for _, m in ipairs(machines) do
      if m.colour == "lime" then busy = busy + 1 end
    end
    screen.put(win, 2, 2, screen.fit(("%d saw%s, %d working, %d recipes"):format(#machines, #machines == 1 and "" or "s",
      busy, #recipes), w - 2), "lightGray")
    local footer = {}
    for _, line in ipairs(screen.wrap(self.message[1], w, self.message[2] == "red" and 4 or 2)) do footer[#footer + 1] = { line, self.message[2] } end
    footer[#footer + 1] = { w >= 50 and "Arrows pick. Enter +1, 8 +8, 6 +64. X cancels last" or "Enter +1, 8 +8, 6 +64, X cancels",
      "gray" }
    drawRequests(win, w, h, "terminal", footer)
  end

  -- The monitor's Saw page: the same, to tap.
  self.monitorPage = { title = "Saw",
    key = function() return self.key() end,
    draw = function(win, w, h) drawRequests(win, w, h, "monitor", {}) end,
  }

  function self.tiles()
    local tiles = {}
    for _, m in ipairs(machines) do tiles[#tiles + 1] = { m.title, m.state or "idle", m.tile or "lime" } end
    return tiles
  end

  local function cancel(file)
    local q = files.read(file)
    if fs.exists(file) then fs.delete(file) end
    if type(q) == "table" and q.job then
      q.ok, q.why = false, "cancelled at the saw"
      report(q)
    end
    for i = #requests, 1, -1 do
      if requests[i].file == file then table.remove(requests, i) end
    end
  end

  local function act(a)
    if a.add then
      request(a.add, a.n * a.add.count)
      tell(("Asked for %d %s."):format(a.n * a.add.count, titleOf(a.add)), "lime")
    elseif a.scroll then
      scroll = math.max(0, scroll + a.scroll)
      picked = math.max(1, math.min(#shown, picked + a.scroll)) -- else the terminal snaps back to it
    elseif a.cancel then
      cancel(a.cancel)
      tell("Cancelled. What's already in a feeder still gets cut.", "lime")
      f.wake()
    end
  end

  local function tap(target, x, y)
    for _, z in ipairs(zones[target] or {}) do
      if y == z[3] and x >= z[1] and x <= z[2] then
        act(z[4])
        return true
      end
    end
    return false
  end

  function self.monitorPage.touch(x, y) return tap("monitor", x, y) end

  -- Keys, scrolling and clicks while its page is showing.
  function self.event(ev, x, y)
    local e = ev[1]
    if e == "key" and ev[2] == keys.up then picked = math.max(1, picked - 1)
    elseif e == "key" and ev[2] == keys.down then picked = math.min(#shown, picked + 1)
    elseif e == "key" and ev[2] == keys.pageUp then picked = math.max(1, picked - 8)
    elseif e == "key" and ev[2] == keys.pageDown then picked = math.min(#shown, picked + 8)
    elseif e == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) and shown[picked] then
      act({ add = shown[picked], n = 1 })
    elseif e == "char" and (ev[2] == "8" or ev[2] == "6") and shown[picked] then
      act({ add = shown[picked], n = ev[2] == "8" and 8 or 64 })
    elseif e == "char" and ev[2]:lower() == "x" and #requests > 0 then
      act({ cancel = requests[#requests].file })
    elseif e == "mouse_scroll" then picked = math.max(1, math.min(#shown, picked + ev[2]))
    elseif x then tap("terminal", x, y)
    end
    return false
  end

  ---------------------------------------------------------------- commands

  -- Every recipe matching text (part of what it makes, or "<make> from
  -- <input>"), the ones a line here can make first.
  local function matching(text)
    text = text:lower()
    local exact, can, other = {}, {}, {}
    for _, rc in ipairs(recipes) do
      local name = titleOf(rc):lower()
      local full = name .. " from " .. nice(rc.from)
      if name == text or rc.make == text or full == text then exact[#exact + 1] = rc
      elseif full:find(text, 1, true) or rc.make:find(text, 1, true) then
        if anyLine(rc) then can[#can + 1] = rc else other[#other + 1] = rc end
      end
    end
    local out = {}
    for _, list in ipairs({ exact, can, other }) do
      for _, rc in ipairs(list) do out[#out + 1] = rc end
    end
    return out
  end

  local function stockCounts()
    local reply = f.ask({ type = "stock" })
    return reply and type(reply.counts) == "table" and reply.counts or nil
  end

  local function describe(rc, stock)
    local how = anyLine(rc) and "" or (several(rc.from) and " [needs a filtered saw]" or " [no saw]")
    return ("%s x%d from %s (%s)%s%s"):format(titleOf(rc), rc.count, nice(rc.from), KINDS[rc.kind] or "config",
      stock and (", can make %d"):format(canMake(rc, stock)) or "", how)
  end

  -- 'factory saw [what count | find <text> | filter <n> <item|none> | cancel [n]]'. True if args was it.
  function self.command(args)
    if args[1] ~= "saw" then return false end
    refreshLines()
    local queued = loadRequests()
    if args[2] == "cancel" then
      local n = tonumber(args[3] or "")
      local gone = 0
      for i, q in ipairs(queued) do
        if not n or n == i then
          cancel(q.file)
          gone = gone + 1
        end
      end
      print(gone > 0 and ("Cancelled %d request(s)."):format(gone) or "Nothing to cancel.")
      f.wake()
      return true
    elseif args[2] == "find" and args[3] then
      local list = matching(table.concat(args, " ", 3))
      local stock = stockCounts()
      local _, h = term.getSize()
      for i = 1, math.min(#list, h - 3) do print(describe(list[i], stock)) end
      if #list > h - 3 then print(("...and %d more: say more of the name."):format(#list - (h - 3))) end
      if #list == 0 then print("No saw recipe makes that.") end
      return true
    elseif args[2] == "filter" then
      local list = self.set:entries()
      local titles = self.set:titles(list)
      local n = tonumber(args[3] or "")
      if not n or not list[n] or not args[4] then
        for i, e in ipairs(list) do print(("%d  %s: filter %s"):format(i, titles[i], e.filter or "none")) end
        if #list == 0 then print("No sawing lines yet: 'factory add saw'.") end
        print("Usage: factory saw filter <line> <item id or none>, e.g. factory saw filter 1 minecraft:oak_slab")
        return true
      end
      local item = args[4]
      if item == "none" then
        list[n].filter = nil
      else
        local found = false
        for _, rc in ipairs(recipes) do
          if rc.make == item then found = true end
        end
        if not found then
          print(("No saw recipe makes %s: 'factory saw find' looks one up (use its full id, mod:item)."):format(item))
          return true
        end
        list[n].filter = item
      end
      self.set:save(list)
      print(item == "none" and ("%s has no filter: it only gets items with one recipe."):format(titles[n])
        or ("%s makes %s from now on: set the same item in its saw's filter slot."):format(titles[n], item))
      return true
    end
    local count = tonumber(args[#args] or "")
    if args[2] and count and #args >= 3 then
      local list = matching(table.concat(args, " ", 2, #args - 1))
      local rc = list[1]
      if not rc then
        print("No saw recipe called that: 'factory saw find <text>' looks one up.")
        return true
      end
      local wanted = math.ceil(count / rc.count) * rc.count
      request(rc, wanted)
      print(("Asked for %d %s from %s. It starts on the factory's next round."):format(wanted, titleOf(rc), nice(rc.from)))
      if not anyLine(rc) then
        print(("No saw here can make it yet: set one's filter to %s (factory saw filter)."):format(rc.make))
      end
      return true
    end
    local stock = stockCounts()
    print(("%d saw recipes (%s)."):format(#recipes, source or "none"))
    if stock then
      local list = {}
      for name, n in pairs(stock) do
        for _, rc in ipairs(n > 0 and byFrom[name] or {}) do
          if anyLine(rc) then list[#list + 1] = rc end
        end
      end
      table.sort(list, function(a, b) return titleOf(a) < titleOf(b) end)
      local _, h = term.getSize()
      local room = h - 4 - #queued
      for i = 1, math.min(#list, room) do print(describe(list[i], stock)) end
      if #list > room then print(("...and %d more."):format(#list - room)) end
      if #list == 0 then print("Nothing stored that a saw here can cut.") end
    else
      print("(The storage computer didn't answer, so nothing to list.)")
    end
    for i, q in ipairs(queued) do
      print(("Request %d: %s %d/%d%s"):format(i, q.recipe and titleOf(q.recipe) or q.key, q.made, q.count,
        q.job and " (for the craft overseer)" or ""))
    end
    print("factory saw <name> <count> | find <text> | filter <line> <item> | cancel [n]")
    return true
  end

  return self
end

return M
