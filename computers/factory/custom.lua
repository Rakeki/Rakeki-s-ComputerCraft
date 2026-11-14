-- The factory's custom machines (factory.lua loads it): any machine at all,
-- run from the recipes the player gives it. CC doesn't need to know the
-- machine: a custom machine is two chests on the storage network, its feeder
-- (a hopper into the machine, or a barrel a pipe pulls from into it) and its
-- output chest (where the machine puts what it makes, by a hopper or pipe).
-- Each one has its own recipes: what goes in for one go (2 iron ingots and
-- a coal) and what comes out (1 steel ingot, maybe a byproduct too). They're
-- set on the setup screen (shown by putting one go's inputs, then outputs,
-- in its output chest) or typed with 'factory custom recipe'.
--
-- A recipe runs on request (its page's +1, +8 or +64, 'factory custom', or
-- the craft overseer, which is told what the custom machines make), or
-- keeps an amount in storage for good: with 'keep 64' it makes more whenever
-- storage holds fewer than 64 of what it makes, for as long as it's set.
-- What arrives in the output chest is counted towards the requests (the
-- first thing a recipe makes), then everything there goes into storage.
--
-- The items a request waits on are left alone by the smelter (rank 0 in the
-- chain), so it doesn't smelt them away first.
local screen = require("lib.screen") -- flicker-free drawing
local mekfeed = require("lib.mekfeed") -- the machines' feeders and output chests
local files = require("lib.files") -- crash-safe save files

local M = {}

local REQUEST_DIR = "/.factory_custom" -- a file per request, so a request typed in another tab is never lost
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local FILL = 64 -- items kept waiting in a machine's feeder (config.fill), never less than one go
local GIVE_UP = 600 -- seconds a craft overseer's request may go with nothing loaded or made before it's handed back
local SHORT_AFTER = 60 -- seconds with everything sent, none of it in a feeder and nothing made, before more is sent
local ORDER_EVERY = 30 -- seconds between asking the craft overseer to make a request's missing inputs
local MAKES_EVERY = 60 -- seconds between telling the craft overseer what the custom machines make
local KEEP_SETTLE = 15 -- seconds after something came out before a kept item is topped up (it may not be counted in storage yet)
local LEARN_FOR = 30 -- seconds the output chest is left alone after the learn page was last open
local QUEUE_SHOWN = 3 -- requests listed under the recipes
local BUTTONS = { 1, 8, 64 } -- the request buttons by each recipe
local KEEP_CHOICES = { 1, 16, 32, 64, 128, 256, 512, 1024, 4096 } -- the setup screen's keep amounts

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function escape(name) return "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "$" end

local function capital(text) return (text:gsub("^%l", string.upper)) end

-- A typed item: "iron_ingot" is minecraft:iron_ingot.
local function itemId(text)
  text = text:lower()
  return text:find(":", 1, true) and text or ("minecraft:" .. text)
end

-- A list of { name, count } from name -> count, by name.
local function listOf(map)
  local out = {}
  for name, n in pairs(map) do
    if n > 0 then out[#out + 1] = { name = name, count = n } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function sideText(list)
  local parts = {}
  for _, it in ipairs(list) do parts[#parts + 1] = ("%d %s"):format(it.count, nice(it.name)) end
  return table.concat(parts, " + ")
end

-- A saved recipe ({ ins, outs, keep }) made ready to use: the inputs by
-- name, the outputs as given (the first is what it's for), a key the same
-- recipe on two machines shares. nil if it's broken.
local function compile(raw)
  if type(raw) ~= "table" or type(raw.ins) ~= "table" or type(raw.outs) ~= "table" then return nil end
  local ins, outs, merged = {}, {}, {}
  for _, it in ipairs(raw.ins) do
    if type(it) == "table" and type(it.name) == "string" and tonumber(it.count) then
      merged[it.name] = (merged[it.name] or 0) + math.max(1, math.floor(tonumber(it.count)))
    end
  end
  ins = listOf(merged)
  for _, it in ipairs(raw.outs) do
    if type(it) == "table" and type(it.name) == "string" and tonumber(it.count) then
      outs[#outs + 1] = { name = it.name, count = math.max(1, math.floor(tonumber(it.count))) }
    end
  end
  if #ins == 0 or #outs == 0 then return nil end
  local perGo, most = 0, 0
  for _, it in ipairs(ins) do
    perGo = perGo + it.count
    most = math.max(most, it.count)
  end
  local key = {}
  for _, it in ipairs(ins) do key[#key + 1] = it.count .. "*" .. it.name end
  key[#key + 1] = ">"
  for _, it in ipairs(outs) do key[#key + 1] = it.count .. "*" .. it.name end
  return { ins = ins, outs = outs, make = outs[1].name, count = outs[1].count, perGo = perGo, most = most,
    key = table.concat(key, " "), keep = tonumber(raw.keep) and math.floor(tonumber(raw.keep)) or nil,
    title = capital(nice(outs[1].name)) }
end

-- 'in... = out...' typed: each side "[count] item", e.g. "2 iron_ingot coal =
-- steel_ingot". ins, outs (lists of { name, count }), or nil and why.
local function parse(words)
  local sides, side = { {}, {} }, 1
  local count
  for _, w in ipairs(words) do
    if w == "=" or w == "->" or w == ">" then
      if count then return nil, nil, "a count with no item after it" end
      side = side + 1
      if side > 2 then return nil, nil, "only one '=' between what goes in and what comes out" end
    elseif tonumber(w) and not count then
      count = math.floor(tonumber(w))
      if count < 1 then return nil, nil, "counts start at 1" end
    else
      local n, name = w:match("^(%d+)[x%*](.+)$") -- 2xcoal, 2*coal
      if n then count, w = tonumber(n), name end
      local map = sides[side]
      local id = itemId(w)
      map[id] = (map[id] or 0) + (count or 1)
      count = nil
    end
  end
  if count then return nil, nil, "a count with no item after it" end
  if side < 2 then return nil, nil, "put '=' between what goes in and what comes out" end
  if not next(sides[1]) then return nil, nil, "nothing goes in" end
  if not next(sides[2]) then return nil, nil, "nothing comes out" end
  return listOf(sides[1]), listOf(sides[2])
end

-- f: the factory (factory.lua): ask, craft, work, config, wake, changed, event, taken.
function M.new(f)
  local config = f.config("custom")
  local KEEP = config.keep or {} -- item -> how many of an input to leave in storage
  local OFFER = config.offer ~= false -- tell the craft overseer what the custom machines make
  local ORDER = config.order ~= false -- have the craft overseer make a request's inputs when there are too few
  local FILL_TO = tonumber(config.fill) or FILL

  local self = { id = "custom", title = "Custom", short = "Custom", rank = 0, every = 5,
    what = "Your recipes -> anything, kept in stock" }
  local machines = {}
  local recipes, byKey = {}, {} -- every recipe on a machine here, once each (by key), with keep = the most any asks
  local requests = {} -- every request, oldest first (REQUEST_DIR)
  local counts = {} -- the storage computer's counts, for the screen
  local progress = {} -- request at -> when it last had something loaded or made (os.clock)
  local lastOut = {} -- item -> when some last came out of an output chest (os.clock)
  local news -- { text, colour, untilTime }
  local outStuck, outWhy, collected
  local makesKey, makesAt, makesNote = nil, -math.huge, nil
  local learning = {} -- output chest -> until when (os.clock) the learn page has it: not emptied
  local scroll = 0 -- the first recipe shown
  local picked = 1 -- the recipe the terminal's keys ask for (a basic computer has no mouse)
  local zones = {} -- target -> { { x1, x2, y, action } }: what a tap does on the terminal or monitor
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

  ---------------------------------------------------------------- the machines and their recipes

  -- The recipes on every machine, once each: the same recipe on two machines
  -- is one, run on both, keeping the larger amount either asks for.
  local function refreshRecipes(entries)
    recipes, byKey = {}, {}
    for _, e in ipairs(entries) do
      for _, raw in ipairs(type(e.recipes) == "table" and e.recipes or {}) do
        local rc = compile(raw)
        if rc then
          local known = byKey[rc.key]
          if known then
            if rc.keep and (known.keep or 0) < rc.keep then known.keep = rc.keep end
          else
            recipes[#recipes + 1] = rc
            byKey[rc.key] = rc
          end
        end
      end
    end
    table.sort(recipes, function(a, b)
      if a.title ~= b.title then return a.title < b.title end
      return a.key < b.key
    end)
  end

  -- Whether a machine (its entry) has this recipe.
  local function hasRecipe(entry, rc)
    for _, raw in ipairs(type(entry.recipes) == "table" and entry.recipes or {}) do
      local c = compile(raw)
      if c and c.key == rc.key then return true end
    end
    return false
  end

  local lineList = {}
  local function refreshLines()
    lineList = self.set:entries()
    refreshRecipes(lineList)
  end

  local function anyLine(rc)
    for _, e in ipairs(lineList) do
      if hasRecipe(e, rc) then return true end
    end
    return false
  end

  -- A feeder holding another recipe's inputs isn't given this one's: the
  -- machine would get them mixed up.
  local function feederFree(m, rc)
    local mine = {}
    for _, it in ipairs(rc.ins) do mine[it.name] = true end
    for name, n in pairs(m.feed) do
      if n > 0 and not mine[name] then return false end
    end
    return true
  end

  local function isLearning(output)
    return output ~= nil and learning[output] ~= nil and os.clock() < learning[output]
  end

  -- What's in a chest, by name (the learn page).
  local function contents(name)
    local ok, list = pcall(peripheral.call, name, "list")
    local map = {}
    for _, it in pairs(ok and type(list) == "table" and list or {}) do map[it.name] = (map[it.name] or 0) + it.count end
    return listOf(map), ok and type(list) == "table"
  end

  ---------------------------------------------------------------- the setup screen

  local function keepText(keep) return keep and ("keep %d"):format(keep) or "on request" end

  -- A recipe's keep amount: off (on request only) or one of KEEP_CHOICES.
  local function keepPage(ui, i, j, change)
    return {
      title = "Keep in stock",
      hint = "It makes more whenever storage has fewer than this of what it makes. Off: only on request.",
      rows = function()
        local e = self.set:entries()[i]
        local raw = e and type(e.recipes) == "table" and e.recipes[j]
        if not raw then return { { label = "Removed.", dim = true } } end
        local function pick(n)
          return function()
            local list = e.recipes
            list[j].keep = n
            ui:back()
            change("recipes", list, n and ("Keeps %d %s in storage."):format(n, nice(list[j].outs[1].name))
              or "Only on request now.")
            f.wake()
          end
        end
        local out = { { label = "Off", value = "only on request", colour = raw.keep and "lightGray" or "lime", act = pick(nil) } }
        for _, n in ipairs(KEEP_CHOICES) do
          out[#out + 1] = { label = tostring(n), value = raw.keep == n and "now" or "",
            colour = raw.keep == n and "lime" or "white", act = pick(n) }
        end
        out[#out + 1] = { label = "Another amount", value = "factory custom keep " .. i .. " " .. j .. " <n>", colour = "gray" }
        return out
      end,
    }
  end

  -- Learning a recipe: one go's inputs, then its outputs, put in the
  -- machine's output chest and read from there (the factory leaves that
  -- chest alone meanwhile; what's put in goes into storage afterwards).
  local function learnPage(ui, i, j, change)
    local stage, ins = "in", nil
    local function entry() return self.set:entries()[i] end
    local page
    page = {
      title = function() return stage == "in" and "What goes IN" or "What comes OUT" end,
      hint = "Put ONE go's inputs in its output chest, then tap Use these.",
      tick = function()
        local e = entry()
        if e and e.output then learning[e.output] = os.clock() + LEARN_FOR end
      end,
      rows = function()
        local e = entry()
        if not e then return { { label = "Removed.", dim = true } } end
        if not e.output then return { { label = "It has no output chest: pick one first.", colour = "red" } } end
        learning[e.output] = os.clock() + LEARN_FOR
        local list, ok = contents(e.output)
        if not ok then return { { label = e.output .. " isn't on the network.", colour = "red" } } end
        local out = {}
        if stage == "out" then
          out[#out + 1] = { label = "In:", value = sideText(ins), colour = "lightGray", dim = true }
        end
        for _, it in ipairs(list) do
          out[#out + 1] = { label = capital(nice(it.name)), value = ("x%d"):format(it.count), colour = "white" }
        end
        if #list == 0 then out[#out + 1] = { label = ("(%s is empty)"):format(e.output), colour = "gray", dim = true } end
        return out
      end,
      buttons = function()
        return {
          { " Use these ", "black", "lime", function()
            local e = entry()
            if not e or not e.output then return end
            local list = contents(e.output)
            if #list == 0 then ui:say("The output chest is empty: put the items in it first.", "orange") return end
            if stage == "in" then
              ins, stage = list, "out"
              page.hint = "Take the inputs out, put ONE go's outputs in (what it's for in the first slot), tap Use these."
              ui:say("Inputs read.", "lime")
              return
            end
            -- what it's for: the item in the lowest slot
            local okL, raw = pcall(peripheral.call, e.output, "list")
            local first, low = nil, math.huge
            for slot, it in pairs(okL and type(raw) == "table" and raw or {}) do
              if slot < low then first, low = it.name, slot end
            end
            table.sort(list, function(a, b)
              if (a.name == first) ~= (b.name == first) then return a.name == first end
              return a.name < b.name
            end)
            local recs = type(e.recipes) == "table" and e.recipes or {}
            local new = { ins = ins, outs = list, keep = j and recs[j] and recs[j].keep or nil }
            if j and recs[j] then recs[j] = new else recs[#recs + 1] = new end
            learning[e.output] = nil
            ui:back()
            change("recipes", recs, ("%s = %s. What's in the chest goes into storage."):format(sideText(ins), sideText(list)))
            f.wake()
          end },
          { " Cancel ", "white", "gray", function()
            local e = entry()
            if e and e.output then learning[e.output] = nil end
            ui:back()
          end },
        }
      end,
    }
    return page
  end

  local function recipePage(ui, i, j, change)
    return {
      title = "Recipe",
      rows = function()
        local e = self.set:entries()[i]
        local raw = e and type(e.recipes) == "table" and e.recipes[j]
        local rc = raw and compile(raw)
        if not rc then return { { label = "Removed.", dim = true } } end
        return {
          { label = "In", value = sideText(rc.ins), colour = "lightGray", dim = false },
          { label = "Out", value = sideText(rc.outs), colour = "lightGray", dim = false },
          { label = "Keep in stock", value = rc.keep and tostring(rc.keep) or "off: only on request",
            colour = rc.keep and "lime" or "gray", act = function() ui:open(keepPage(ui, i, j, change)) end },
          { label = "Learn it again", colour = "white", act = function() ui:open(learnPage(ui, i, j, change)) end },
          { label = "Remove it", colour = "red", act = function()
            local list = e.recipes
            table.remove(list, j)
            ui:back()
            change("recipes", list, "Recipe removed.")
            f.wake()
          end },
        }
      end,
    }
  end

  -- The rows on a custom machine's setup page (lib/mekfeed.lua's lineRows).
  local function lineRows(ui, i, entry, change)
    local recs = type(entry.recipes) == "table" and entry.recipes or {}
    local rows = {}
    for j, raw in ipairs(recs) do
      local rc = compile(raw)
      rows[#rows + 1] = { label = rc and ("%s"):format(sideText(rc.outs)) or "(broken recipe)",
        value = rc and (("from %s, %s"):format(sideText(rc.ins), keepText(rc.keep))) or "",
        colour = rc and "white" or "red", act = function() ui:open(recipePage(ui, i, j, change)) end }
    end
    rows[#rows + 1] = { label = "+ Add a recipe", value = "shown in its output chest", colour = "lime",
      act = function() ui:open(learnPage(ui, i, nil, change)) end }
    return rows
  end

  self.set = mekfeed.new({ name = "custom", cmd = "factory", event = f.event, what = "custom machine", title = "Machine",
    names = config.names, ask = f.ask, tell = tell, far = function() return f.work.remote end,
    taken = f.taken, lines = { "custom" }, pageTitle = "Custom machines", lineRows = lineRows, lineFill = FILL_TO })

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
          r.recipe = byKey[r.key]
          list[#list + 1] = r
        end
      end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    return list
  end

  local function plain(r)
    return { key = r.key, count = r.count, made = r.made, sent = r.sent, at = r.at, job = r.job, keep = r.keep,
      done = r.done, ok = r.ok, why = r.why }
  end

  -- Only while its file is there: a request cancelled in another tab stays cancelled.
  local function saveRequest(r)
    if fs.exists(r.file) then files.write(r.file, plain(r)) end
  end

  local function newRequest(key, count, job, keep)
    if not fs.isDir(REQUEST_DIR) then fs.makeDir(REQUEST_DIR) end
    local at = os.epoch("utc")
    local file = ("%s/%.0f"):format(REQUEST_DIR, at)
    while fs.exists(file) do
      at = at + 1
      file = ("%s/%.0f"):format(REQUEST_DIR, at)
    end
    local r = { key = key, count = count, made = 0, sent = 0, at = at, job = job, keep = keep }
    files.write(file, r)
    r.file, r.recipe = file, byKey[key]
    return r
  end

  -- Whole goes: a recipe that makes 4 makes 4 at a time.
  local function whole(rc, count) return math.ceil(count / rc.count) * rc.count end

  -- Ask for count more of what a recipe makes: added to a request of yours
  -- for it that's still waiting, else a new one.
  local function request(rc, count)
    count = whole(rc, count)
    for _, q in ipairs(loadRequests()) do
      if q.key == rc.key and not q.job and not q.keep and not q.done then
        q.count = q.count + count
        saveRequest(q)
        f.wake()
        return
      end
    end
    newRequest(rc.key, count)
    f.wake()
  end

  -- How many a request still has to make, and how many goes to send.
  local function left(q) return math.max(0, q.count - q.made) end
  local function toSend(q) return math.max(0, math.ceil(q.count / q.recipe.count) - q.sent) end

  -- How many goes what's stored would do.
  local function goesFrom(rc, avail)
    local n = math.huge
    for _, it in ipairs(rc.ins) do
      n = math.min(n, math.floor(math.max(0, (avail[it.name] or 0) - (KEEP[it.name] or 0)) / it.count))
    end
    return n
  end

  -- Count what came out of the output chests towards the requests, oldest
  -- first (each by the first thing its recipe makes).
  local function credit(byName)
    local now = os.clock()
    for name, n in pairs(byName) do
      if n > 0 then lastOut[name] = now end
    end
    for _, q in ipairs(requests) do
      if not q.done and q.recipe then
        local n = math.min(byName[q.recipe.make] or 0, left(q))
        if n > 0 then
          q.made = q.made + n
          byName[q.recipe.make] = byName[q.recipe.make] - n
          progress[q.at] = now
          saveRequest(q)
        end
      end
    end
  end

  -- Every output chest but those the learn page has open.
  local function collectable()
    local out = {}
    for _, m in ipairs(machines) do
      if not isLearning(m.entry.output) then out[#out + 1] = m end
    end
    return out
  end

  -- A recipe kept in stock that's under its amount gets a request (one per
  -- recipe, topped up), counting what's stored and what open requests will
  -- still make. Not just after something came out: storage may not have
  -- counted it yet. A request for a recipe no longer kept ends.
  local function keepUp(now)
    local open = {}
    for _, q in ipairs(requests) do
      if q.recipe and not q.done then open[q.key] = (open[q.key] or 0) + left(q) end
    end
    for _, q in ipairs(requests) do
      if q.keep and not q.done and (not q.recipe or not q.recipe.keep) then
        q.done, q.ok = true, true
        q.count = q.made
      end
    end
    for _, rc in ipairs(recipes) do
      if rc.keep and rc.keep > 0 and now - (lastOut[rc.make] or -math.huge) >= KEEP_SETTLE and anyLine(rc) then
        local short = rc.keep - (counts[rc.make] or 0) - (open[rc.key] or 0)
        if short > 0 then
          local mine
          for _, q in ipairs(requests) do
            if q.keep and q.key == rc.key and not q.done then mine = q end
          end
          if mine then
            mine.count = mine.count + whole(rc, short)
            mine.dirty = true
          else
            requests[#requests + 1] = newRequest(rc.key, whole(rc, short), nil, true)
          end
        end
      end
    end
  end

  -- A request asked for here or kept in stock (not the overseer's own: its
  -- plan already makes their inputs first) whose inputs are short has the
  -- craft overseer make the rest. 'prepare' tops up to a total, stored and
  -- being made included, so asking again never orders twice.
  local orderAt, orderNote = {}, {} -- input -> when last asked (os.clock), what the overseer said
  local function orderInputs(avail)
    local need = {}
    for _, q in ipairs(requests) do
      local rc = q.recipe
      if ORDER and rc and not q.job and not q.done and anyLine(rc) then
        for _, it in ipairs(rc.ins) do need[it.name] = (need[it.name] or 0) + toSend(q) * it.count end
      end
    end
    local now = os.clock()
    for item, n in pairs(need) do
      local have = math.max(0, (avail[item] or 0) - (KEEP[item] or 0))
      if n <= have then
        orderNote[item] = nil
      elseif now - (orderAt[item] or -math.huge) >= ORDER_EVERY then
        orderAt[item] = now
        local reply = f.craft({ type = "prepare", items = { [item] = (avail[item] or 0) + n - have } }, 5)
        local making = reply and type(reply.crafting) == "table" and tonumber(reply.crafting[item]) or 0
        local why = reply and type(reply.cantCraft) == "table" and reply.cantCraft[item]
        orderNote[item] = not reply and "no craft overseer answered"
          or why and ("can't be made: " .. tostring(why))
          or reply.craftProblem and making > 0 and ("making it: " .. tostring(reply.craftProblem))
          or making > 0 and ("making %d first"):format(making)
          or nil
      end
    end
    for item in pairs(orderNote) do
      if not need[item] then orderNote[item], orderAt[item] = nil, nil end
    end
  end

  ---------------------------------------------------------------- the craft overseer

  -- A recipe as the craft overseer plans it: its inputs laid out in a grid
  -- (a cell each, so only recipes of at most 9 inputs), count of what it's for.
  local function asCraft(rc)
    if rc.perGo > 9 then return nil end
    local cells, keys, letter = {}, {}, 65
    for _, it in ipairs(rc.ins) do
      local ch = string.char(letter)
      letter = letter + 1
      keys[ch] = it.name
      for _ = 1, it.count do cells[#cells + 1] = ch end
    end
    local text = table.concat(cells)
    local rows = {}
    for r = 1, 3 do
      local row = text:sub(r * 3 - 2, r * 3)
      if row ~= "" then rows[#rows + 1] = row end
    end
    return { make = rc.make, count = rc.count, rows = rows, keys = keys }
  end

  local function offer()
    if not OFFER then return end
    local crafts, keys = {}, {}
    for _, rc in ipairs(recipes) do
      local c = anyLine(rc) and asCraft(rc)
      if c then
        crafts[#crafts + 1] = c
        keys[#keys + 1] = rc.key
      end
    end
    local key = table.concat(keys, "|")
    if key == makesKey and os.clock() - makesAt < MAKES_EVERY then return end
    local reply = f.craft({ type = "makes", via = "custom", recipes = crafts }, 5)
    makesAt = os.clock()
    if reply and reply.ok then
      makesKey, makesNote = key, nil
    else
      makesKey = nil
      makesNote = #crafts > 0 and (reply and reply.error
        or "the craft overseer doesn't take custom machine orders: is it running, and updated?") or nil
    end
  end

  -- A craft overseer's request is finished (or given up on): tell it. True once it has heard.
  local function report(q)
    if not q.job then return true end
    local reply = f.craft({ type = "jobdone", job = q.job, ok = q.ok, why = q.why }, 5)
    return reply ~= nil
  end

  -- The recipe a craft overseer's job is for: what it makes, and its grid's items.
  local function recipeFor(make, grid)
    local have = {}
    for _, item in pairs(type(grid) == "table" and grid or {}) do have[item] = (have[item] or 0) + 1 end
    for _, rc in ipairs(recipes) do
      if rc.make == make then
        local same = true
        for _, it in ipairs(rc.ins) do
          if have[it.name] ~= it.count then same = false end
        end
        local n = 0
        for _ in pairs(have) do n = n + 1 end
        if same and n == #rc.ins then return rc end
      end
    end
    return nil
  end

  -- From the craft overseer (factory protocol): 'custom' (make this for one
  -- of its plans) and 'cancel'. The reply, or nil if it isn't one.
  function self.request(from, msg)
    if msg.type == "custom" then
      refreshLines()
      local rc = recipeFor(tostring(msg.make), msg.grid)
      local count = math.floor(tonumber(msg.count) or 0)
      if not rc or count < 1 then return { ok = false, why = "no custom machine here has that recipe" } end
      if not anyLine(rc) then return { ok = false, why = "no custom machine here has that recipe any more" } end
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
    local waiting, kept = 0, 0
    for _, q in ipairs(requests) do
      if not q.done then waiting = waiting + 1 end
    end
    for _, rc in ipairs(recipes) do
      if rc.keep then kept = kept + 1 end
    end
    return ("%d machine%s%s%s"):format(n, n == 1 and "" or "s", kept > 0 and (", %d kept"):format(kept) or "",
      waiting > 0 and (", %d requests"):format(waiting) or "")
  end

  ---------------------------------------------------------------- a round

  function self.read(remote, remoteInput)
    machines = self.set:read()
    refreshLines()
    requests = loadRequests()
    local seen, list = {}, {}
    for _, q in ipairs(requests) do
      if q.recipe and not q.done then
        for _, it in ipairs(q.recipe.ins) do
          if not seen[it.name] then
            seen[it.name] = true
            list[#list + 1] = escape(it.name)
          end
        end
      end
    end
    taking = list
    outStuck, outWhy, collected = false, nil, false
    if remote then
      local _, byName
      _, outStuck, outWhy, byName = self.set:collect(collectable(), remoteInput)
      credit(byName)
      collected = true
    end
  end

  function self.round(r)
    local work = f.work
    counts = r.stock.counts
    local problem = r.feedProblem
    offer()
    if #machines == 0 then
      say("Nothing set up yet: add a custom machine on the setup screen ('factory add machine').", "orange")
      status("waiting", "nothing set up")
      return
    end
    if #recipes == 0 then
      say("No recipes yet: tap a custom machine on the setup screen, then + Add a recipe.", "orange")
      status("waiting", "no recipes")
    end
    local input = r.input
    local avail = {}
    for name, n in pairs(counts) do avail[name] = n end

    if not collected then
      local _, byName
      _, outStuck, outWhy, byName = self.set:collect(collectable(), input)
      credit(byName)
    end

    -- finished requests: done, or a craft overseer's that waited too long
    local now = os.clock()
    keepUp(now)
    for _, q in ipairs(requests) do
      progress[q.at] = progress[q.at] or now
      if not q.recipe and not q.done then
        q.done, q.ok, q.why = true, false, "no custom machine here has its recipe any more"
      elseif not q.done and left(q) == 0 then
        q.done, q.ok = true, true
        if not q.job and not q.keep then tell(("Made %d %s."):format(q.made, q.recipe.title), "lime") end
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

    -- the inputs, oldest request first, a whole number of goes into each
    -- machine with the recipe and room; with a work chest each load is noted
    -- down and fetched for all at once below
    local plan = r.useWork and {} or nil
    local sent = 0
    for _, q in ipairs(requests) do
      q.state = nil
      local rc = q.recipe
      -- everything sent, none of it waiting in a feeder, nothing made for a
      -- while: the machine gave fewer than the recipe says, so send the rest
      if toSend(q) == 0 and left(q) > 0 and now - progress[q.at] > SHORT_AFTER then
        local inFeeders = 0
        for _, m in ipairs(machines) do
          for _, it in ipairs(rc.ins) do inFeeders = inFeeders + (m.feed[it.name] or 0) end
        end
        if inFeeders == 0 then
          q.sent = math.max(0, q.sent - math.ceil(left(q) / rc.count))
          q.dirty, progress[q.at] = true, now
        end
      end
      local lines = 0
      for _, m in ipairs(machines) do
        if hasRecipe(m.entry, rc) then
          lines = lines + 1
          local want = toSend(q)
          if want > 0 and mekfeed.ready(m) and not r.unsure[m.entry.feeder] and m.outOk and feederFree(m, rc)
            and not isLearning(m.entry.output) then
            local fill = math.max(m.fill, rc.perGo)
            local room = math.floor(math.max(0, fill - m.feedTotal) / rc.perGo)
            local slots = math.floor(math.max(0, m.feedSize * mekfeed.STACK - m.feedTotal) / rc.perGo)
            local goes = math.min(want, goesFrom(rc, avail), room, slots, math.floor(SEND_MAX / rc.most))
            if goes > 0 then
              local items = {}
              for _, it in ipairs(rc.ins) do items[it.name] = it.count * goes end
              local got = {}
              if plan then
                plan[#plan + 1] = { m = m, q = q, rc = rc, items = items, goes = goes }
                got = items
              else
                local reply = f.ask({ type = "send", to = m.entry.feeder, items = items })
                got = reply and type(reply.sent) == "table" and reply.sent or {}
                if reply and reply.error then problem = reply.error end
                if not reply then problem = "the storage computer didn't answer while loading " .. m.title end
              end
              local done = goes
              for _, it in ipairs(rc.ins) do
                local n = tonumber(got[it.name]) or 0
                mekfeed.added(m, it.name, n)
                avail[it.name] = (avail[it.name] or 0) - n
                sent = sent + n
                done = math.min(done, math.floor(n / it.count))
              end
              q.sent = q.sent + done
              if done > 0 then progress[q.at], q.dirty = now, true end
            end
          end
        end
      end
      if lines == 0 then
        q.state = "no machine has this recipe"
      elseif toSend(q) > 0 and goesFrom(rc, avail) == 0 then
        local short, names = {}, {}
        for _, it in ipairs(rc.ins) do
          if math.max(0, (avail[it.name] or 0) - (KEEP[it.name] or 0)) < it.count then
            short[#short + 1] = it.name
            names[#names + 1] = nice(it.name)
          end
        end
        q.state = "waiting for " .. table.concat(names, ", ")
        q.short = short
      end
    end
    -- what's short is made first, and the request says so
    orderInputs(avail)
    for _, q in ipairs(requests) do
      for _, name in ipairs(q.short or {}) do
        if orderNote[name] then
          q.state = q.state .. ": " .. orderNote[name]
          break
        end
      end
      q.short = nil
    end
    if plan then
      local items = {}
      for _, p in ipairs(plan) do
        for name, n in pairs(p.items) do items[name] = (items[name] or 0) + n end
      end
      local reply, why = work:fill(items, 0)
      if reply and reply.error and not reply.nochest then problem = reply.error end
      if not reply and next(items) then problem = why end
      for _, p in ipairs(plan) do
        local done = p.goes
        for name, n in pairs(p.items) do
          local got = work:move(name, p.m.entry.feeder, nil, n)
          if got < n then
            mekfeed.added(p.m, name, got - n)
            sent = sent - (n - got)
          end
          for _, it in ipairs(p.rc.ins) do
            if it.name == name then done = math.min(done, math.floor(got / it.count)) end
          end
        end
        p.q.sent = p.q.sent - (p.goes - done)
      end
      work:empty(input)
    end
    for _, q in ipairs(requests) do
      if q.dirty then saveRequest(q) end
      q.dirty = nil
    end

    -- how each machine and request is doing
    local working, broken = 0, 0
    for _, m in ipairs(machines) do
      local item = mekfeed.current(m)
      local colour, text = mekfeed.status(m, item and ("making from " .. nice(item)))
      if isLearning(m.entry.output) then colour, text = "yellow", "learning a recipe" end
      m.state, m.tile = text, colour
      m.colour = ({ red = "red", orange = "lime", yellow = "lime", lime = "gray" })[colour] or "gray"
      if colour == "red" then broken = broken + 1
      elseif colour == "orange" or colour == "yellow" then working = working + 1 end
    end
    for _, q in ipairs(requests) do
      if not q.state then q.state = toSend(q) > 0 and "queued" or "in the machine" end
    end

    if outWhy then problem = problem or outWhy
    elseif outStuck then
      problem = problem or ("the %s is full: what's made is waiting in the output chests"):format(work.remote and "ender chest" or "storage input chest")
    end
    if news and os.clock() < news[3] then
      self.message = { news[1], news[2] }
    elseif problem then
      say("Couldn't move items: " .. problem, "red")
    elseif work.problem then
      say(("Not using the work chest: %s."):format(work.problem), "orange")
    elseif broken > 0 then
      local m
      for _, x in ipairs(machines) do
        if x.tile == "red" then m = m or x end
      end
      local why = {
        ["no feeder"] = "its feeder isn't on the network",
        ["no output chest"] = "its output chest isn't on the network",
        ["not moving"] = "nothing goes out of its feeder: is the machine running, and does a hopper or pipe take from the feeder?",
      }
      say(("%s: %s"):format(m.title, why[m.state] or m.state), "red")
    elseif #recipes == 0 then
      return
    elseif makesNote and #requests == 0 then
      say(makesNote, "orange")
    elseif #requests == 0 then
      say("Tap +1, +8 or +64 by what you want made. Everything kept is stocked.")
    elseif sent > 0 then
      say(("Sent %d items to the machine%s."):format(sent, #machines == 1 and "" or "s"))
    else
      say(("%s: %s."):format(requests[1].recipe.title, requests[1].state))
    end
    status(broken > 0 and "alert" or working > 0 and "running" or "idle",
      ("%d of %d machines working, %d requests"):format(working, #machines, #requests))
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

  -- Every recipe with how many are stored (and kept) and the request
  -- buttons, then the requests (tap x to cancel one).
  local function drawRequests(win, w, h, target, footer)
    zones[target] = {}
    local fit = screen.fit
    local btnW = 0
    for _, n in ipairs(BUTTONS) do btnW = btnW + #(" +" .. n .. " ") + 1 end
    local bx = w - btnW + 1
    local haveR = bx - 2
    screen.put(win, 2, 3, "Make", "yellow")
    screen.put(win, haveR - 3, 3, "Have", "yellow")
    screen.put(win, bx, 3, "Request", "yellow")
    local queueRows = math.min(QUEUE_SHOWN, #requests)
    local rows = h - 4 - #footer - (queueRows > 0 and queueRows + 1 or 0)
    local keyed = target == "terminal"
    if keyed then
      picked = math.max(1, math.min(picked, #recipes))
      if picked <= scroll then scroll = picked - 1 end
      if picked > scroll + rows then scroll = picked - rows end
    end
    scroll = math.max(0, math.min(scroll, #recipes - rows))
    for i = 1, rows do
      local rc, y = recipes[scroll + i], 3 + i
      if rc then
        local bg = keyed and scroll + i == picked and "gray" or "black"
        local nameW = haveR - 8
        local can = goesFrom(rc, counts) > 0
        screen.put(win, 1, y, (" "):rep(haveR + 1), "white", bg)
        local title = rc.title .. (rc.count > 1 and (" x" .. rc.count) or "")
        screen.put(win, 2, y, fit(title, nameW), can and "white" or "lightGray", bg)
        local note = rc.keep and (" keep " .. rc.keep) or (" from " .. sideText(rc.ins))
        if #title + 2 < nameW then
          screen.put(win, 2 + #title, y, fit(note, nameW - #title), rc.keep and "lime" or (bg == "gray" and "lightGray" or "gray"), bg)
        end
        local n = counts[rc.make] or 0
        local have = n > 9999 and "9999+" or tostring(n)
        screen.put(win, haveR - #have + 1, y, have, rc.keep and n < rc.keep and "orange" or "white", bg)
        local x = bx
        for _, k in ipairs(BUTTONS) do
          x = button(win, target, x, y, (" +%d "):format(k), { add = rc, n = k }, "black", can and "lightGray" or "gray")
        end
      end
    end
    if #recipes == 0 then
      screen.put(win, 2, 4, fit(#machines == 0 and "No custom machines yet." or "No recipes yet: add one on the setup screen.", w - 2), "gray")
    end
    if #recipes > rows then
      screen.put(win, w, 4, scroll > 0 and "^" or " ", "yellow")
      screen.put(win, w, 3 + rows, scroll + rows < #recipes and "v" or " ", "yellow")
      zone(target, w, w, 4, { scroll = -rows })
      zone(target, w, w, 3 + rows, { scroll = rows })
    end
    if queueRows > 0 then
      local y = 4 + rows
      screen.put(win, 2, y, ("Requests (%d)"):format(#requests), "yellow")
      for i = 1, queueRows do
        local q = requests[i]
        local text = ("%s %d/%d%s: %s"):format(q.recipe and q.recipe.title or "?", q.made, q.count,
          q.job and " (overseer)" or q.keep and " (kept)" or "", q.state or "queued")
        screen.put(win, 2, y + i, fit(text, w - 6), "white")
        button(win, target, w - 3, y + i, " x ", { cancel = q.file }, "white", "red")
      end
    end
    for i, line in ipairs(footer) do screen.put(win, 1, h - #footer + i, fit(line[1], w), line[2]) end
  end

  function self.key()
    local key = { self.message[1], self.message[2], scroll, picked, #recipes }
    for _, rc in ipairs(recipes) do key[#key + 1] = rc.key .. "=" .. (counts[rc.make] or 0) .. "/" .. (rc.keep or "") .. "/" .. goesFrom(rc, counts) end
    for _, q in ipairs(requests) do key[#key + 1] = table.concat({ q.key, q.made, q.count, q.state or "" }, "/") end
    for _, m in ipairs(machines) do key[#key + 1] = table.concat({ m.title, m.state or "" }, "/") end
    return table.concat(key, "|")
  end

  function self.draw(win, w, h)
    local busy = 0
    for _, m in ipairs(machines) do
      if m.colour == "lime" then busy = busy + 1 end
    end
    screen.put(win, 2, 2, screen.fit(("%d machine%s, %d working, %d recipes"):format(#machines, #machines == 1 and "" or "s",
      busy, #recipes), w - 2), "lightGray")
    local footer = {}
    for _, line in ipairs(screen.wrap(self.message[1], w, (self.message[2] == "red" or self.message[2] == "orange") and 4 or 2)) do footer[#footer + 1] = { line, self.message[2] } end
    footer[#footer + 1] = { w >= 50 and "Arrows pick. Enter +1, 8 +8, 6 +64. X cancels last" or "Enter +1, 8 +8, 6 +64, X cancels",
      "gray" }
    drawRequests(win, w, h, "terminal", footer)
  end

  -- The monitor's Custom page: the same, to tap.
  self.monitorPage = { title = "Custom",
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
      q.ok, q.why = false, "cancelled at the custom machine"
      report(q)
    end
    for i = #requests, 1, -1 do
      if requests[i].file == file then table.remove(requests, i) end
    end
  end

  local function act(a)
    if a.add then
      request(a.add, a.n * a.add.count)
      tell(("Asked for %d %s."):format(a.n * a.add.count, a.add.title), "lime")
    elseif a.scroll then
      scroll = math.max(0, scroll + a.scroll)
      picked = math.max(1, math.min(#recipes, picked + a.scroll))
    elseif a.cancel then
      cancel(a.cancel)
      tell("Cancelled. What's already in a feeder still gets made (a kept one is asked for again when it's short).", "lime")
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

  function self.event(ev, x, y)
    local e = ev[1]
    if e == "key" and ev[2] == keys.up then picked = math.max(1, picked - 1)
    elseif e == "key" and ev[2] == keys.down then picked = math.min(#recipes, picked + 1)
    elseif e == "key" and ev[2] == keys.pageUp then picked = math.max(1, picked - 8)
    elseif e == "key" and ev[2] == keys.pageDown then picked = math.min(#recipes, picked + 8)
    elseif e == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) and recipes[picked] then
      act({ add = recipes[picked], n = 1 })
    elseif e == "char" and (ev[2] == "8" or ev[2] == "6") and recipes[picked] then
      act({ add = recipes[picked], n = ev[2] == "8" and 8 or 64 })
    elseif e == "char" and ev[2]:lower() == "x" and #requests > 0 then
      act({ cancel = requests[#requests].file })
    elseif e == "mouse_scroll" then picked = math.max(1, math.min(#recipes, picked + ev[2]))
    elseif x then tap("terminal", x, y)
    end
    return false
  end

  ---------------------------------------------------------------- commands

  local function matching(text)
    text = text:lower()
    local exact, part = {}, {}
    for _, rc in ipairs(recipes) do
      local name = rc.title:lower()
      if name == text or rc.make == text or rc.make == itemId(text) then exact[#exact + 1] = rc
      elseif name:find(text, 1, true) or rc.make:find(text, 1, true) then part[#part + 1] = rc end
    end
    for _, rc in ipairs(part) do exact[#exact + 1] = rc end
    return exact
  end

  -- A machine by its number, or nil (and the list printed).
  local function lineArg(text)
    local list = self.set:entries()
    local n = tonumber(text or "")
    if n and list[n] then return list, n end
    local titles = self.set:titles(list)
    for i, e in ipairs(list) do print(("%d  %s: fed by %s, out to %s"):format(i, titles[i], e.feeder, e.output or "?")) end
    if #list == 0 then print("No custom machines yet: 'factory add machine'.") end
    return nil
  end

  local function usage()
    print("factory custom                              the machines, recipes and requests")
    print("factory custom <item> <count>               make count of it")
    print("factory custom recipe <machine> <in> = <out> e.g. recipe 1 2 iron_ingot coal = steel_ingot")
    print("factory custom keep <machine> <recipe> <n|off>  keep n in storage for good")
    print("factory custom forget <machine> <recipe>    remove a recipe")
    print("factory custom cancel [n]                   cancel request n (no number: all of them)")
  end

  -- 'factory custom ...'. True if args was it.
  function self.command(args)
    if args[1] ~= "custom" then return false end
    refreshLines()
    local queued = loadRequests()
    local verb = args[2]
    if verb == "cancel" then
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
    elseif verb == "recipe" then
      local list, i = lineArg(args[3])
      if not list then
        print("Usage: factory custom recipe <machine> <in> = <out>")
        return true
      end
      local words = {}
      for k = 4, #args do words[#words + 1] = args[k] end
      local ins, outs, why = parse(words)
      if not ins then
        print("Couldn't read that: " .. why .. ".")
        print("e.g. factory custom recipe 1 2 iron_ingot coal = steel_ingot (counts before items; mod:item for mods)")
        return true
      end
      local e = list[i]
      e.recipes = type(e.recipes) == "table" and e.recipes or {}
      e.recipes[#e.recipes + 1] = { ins = ins, outs = outs }
      self.set:save(list)
      print(("%s: %s = %s (recipe %d)."):format(self.set:titles(list)[i], sideText(ins), sideText(outs), #e.recipes))
      print(("Keep some in stock: factory custom keep %d %d <n>"):format(i, #e.recipes))
      return true
    elseif verb == "keep" or verb == "forget" then
      local list, i = lineArg(args[3])
      local j = tonumber(args[4] or "")
      local e = list and list[i]
      local recs = e and type(e.recipes) == "table" and e.recipes or {}
      if not e or not j or not recs[j] or (verb == "keep" and not args[5]) then
        for k, raw in ipairs(recs) do
          local rc = compile(raw)
          print(("  recipe %d: %s"):format(k, rc and ("%s = %s, %s"):format(sideText(rc.ins), sideText(rc.outs), keepText(rc.keep)) or "broken"))
        end
        print(verb == "keep" and "Usage: factory custom keep <machine> <recipe> <n|off>" or "Usage: factory custom forget <machine> <recipe>")
        return true
      end
      if verb == "forget" then
        table.remove(recs, j)
        print("Recipe removed.")
      else
        local n = tonumber(args[5])
        recs[j].keep = n and n > 0 and math.floor(n) or nil
        print(recs[j].keep and ("Keeps %d %s in storage from now on."):format(recs[j].keep, nice(recs[j].outs[1].name))
          or "Only on request now.")
      end
      self.set:save(list)
      f.wake()
      return true
    end
    local count = tonumber(args[#args] or "")
    if verb and count and #args >= 3 then
      local rc = matching(table.concat(args, " ", 2, #args - 1))[1]
      if not rc then
        print("No custom recipe makes that: 'factory custom' lists them.")
        return true
      end
      local wanted = whole(rc, count)
      request(rc, wanted)
      print(("Asked for %d %s. It starts on the factory's next round."):format(wanted, rc.title))
      return true
    end
    if verb then
      usage()
      return true
    end
    local list = self.set:entries()
    local titles = self.set:titles(list)
    for i, e in ipairs(list) do
      print(("%d  %s: fed by %s, out to %s"):format(i, titles[i], e.feeder, e.output or "?"))
      for j, raw in ipairs(type(e.recipes) == "table" and e.recipes or {}) do
        local rc = compile(raw)
        print(("   %d. %s"):format(j, rc and ("%s = %s, %s"):format(sideText(rc.ins), sideText(rc.outs), keepText(rc.keep)) or "broken"))
      end
    end
    if #list == 0 then print("No custom machines yet: 'factory add machine'.") end
    for i, q in ipairs(queued) do
      print(("Request %d: %s %d/%d%s"):format(i, q.recipe and q.recipe.title or q.key, q.made, q.count,
        q.job and " (for the craft overseer)" or q.keep and " (kept in stock)" or ""))
    end
    usage()
    return true
  end

  return self
end

return M
