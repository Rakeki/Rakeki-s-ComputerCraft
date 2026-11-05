-- The factory's essence page (factory.lua loads it). Empties every Hopper
-- Botany Pot this computer owns into the storage input chest, and looks up
-- what the stored Mystical Agriculture essence can be crafted into (iron
-- ingots, dirt, diamonds, ...), so you can order it: the storage system's
-- crafting turtle makes it.
--
-- The recipes come from the storage computer: Mystical Agriculture's are in
-- the modpack's pack_recipes.lua (tools/recipes.mjs), or teach one with
-- 'crafter learn'. A pot shows CC only its harvest, and only through its
-- bottom, so each pot stands on a full-block wired modem; the seed and soil
-- are never touched. Or the pots empty themselves into a barrel (or chest)
-- under them or at the end of a pipe: a "pot barrel", added on the setup
-- screen or with 'factory add potbarrel', which this empties instead. It's
-- named to the storage computer as a feeder, so it isn't storage: else the
-- storage computer would fill it and the pots would have nowhere to go.
local screen = require("lib.screen") -- flicker-free drawing
local files = require("lib.files") -- crash-safe save files

local M = {}

local RECIPES_EVERY = 300 -- seconds between asking the storage computer for its recipes again
local POT_SLOTS = 12 -- harvest slots in a pot
local BARRELS_FILE = "/.factory_pot_barrels" -- the pot barrels: { name, ... }

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

-- The crop a pot grows, from what it gives: "iron essence" -> "iron".
local function cropOf(name) return (nice(name):gsub(" essence$", "")) end

-- Inventories on the wired network (not touching this computer) that can be
-- a pot barrel: a barrel or chest, never an ender chest or a pot (skip).
local function barrelsOnNetwork(skip)
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name) or ""
    if not sides[name] and (t:find("barrel", 1, true) or t:find("chest", 1, true)) and not t:find("ender", 1, true)
      and not name:find(skip, 1, true) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- f: the factory (factory.lua): ask, config, mine.
function M.new(f)
  local config = f.config("essence")
  -- Used if config.lua has none; see config.lua for what they mean.
  local ESSENCE = config.essence or "^mysticalagriculture:.+_essence$"
  local POTS = config.pots or "botany_pot"
  local LEAVE = config.leave or {}
  local NAMES = config.names or {}

  local self = { id = "essence", title = "Essence", every = 10, what = "Botany pots -> essence" }
  local pots = {} -- what the Pots view shows, one entry per pot or pot barrel
  local barrelState = {} -- barrel name -> { items, took, state, colour } from its last emptying
  local recipes = {} -- best recipe per item made: { make, count, need = { { key, n } }, from }
  local recipesAt -- os.clock() when the recipes last came
  local counts = {} -- item -> how many are stored
  local taken, takenSince = {}, os.epoch("utc") -- item -> how many came out of the pots since starting
  local lastCrop = {} -- pot -> what came out of it last, to name its crop
  local news -- { text, colour, untilTime }: how an order went, kept on screen a while
  self.message = { "Looking for the storage computer...", "lightGray" }
  self.status = { "starting", "" }

  local function say(text, colour)
    self.message = { text, colour or "lightGray" }
    f.changed()
  end

  -- What an order did: stays up for 30 s, over the rounds' messages.
  local function tell(text, colour)
    news = { text, colour, os.clock() + 30 }
    say(text, colour)
  end

  -- A round's message, unless an order's is still showing.
  local function note(text, colour)
    if not news or os.clock() > news[3] then say(text, colour) end
  end

  local function status(state, detail) self.status = { state, detail } end

  local function leave(name)
    for _, p in ipairs(LEAVE) do
      if name:find(p) then return true end
    end
    return false
  end

  -- Peripherals on the wired network (not ones touching this computer: the
  -- storage computer can't reach those) whose name or type has POTS in it.
  local function findPots()
    local sides, list = {}, {}
    for _, s in ipairs(rs.getSides()) do sides[s] = true end
    for _, name in ipairs(peripheral.getNames()) do
      local hit = name:find(POTS, 1, true) ~= nil
      for _, t in ipairs({ peripheral.getType(name) }) do
        if t:find(POTS, 1, true) then hit = true end
      end
      if hit and not sides[name] then list[#list + 1] = name end
    end
    table.sort(list)
    return list
  end

  local function myPots()
    local out = {}
    for _, name in ipairs(findPots()) do
      if f.mine(name) then out[#out + 1] = name end
    end
    return out
  end

  function self.found()
    local out = {}
    for _, name in ipairs(findPots()) do out[#out + 1] = { name = name, kind = "Botany pot" } end
    return out
  end

  local function readBarrels()
    local t = files.read(BARRELS_FILE)
    return type(t) == "table" and t or {}
  end

  local function writeBarrels(t)
    files.write(BARRELS_FILE, t)
    f.wake() -- the running factory, if this is another tab
  end

  -- added by hand, so always this computer's
  function self.uses() return readBarrels() end
  function self.active() return #myPots() > 0 or #readBarrels() > 0 end
  function self.takes() return {} end

  function self.summary()
    local n, b = #myPots(), #readBarrels()
    local out = {}
    if n > 0 then out[#out + 1] = ("%d botany pots"):format(n) end
    if b > 0 then out[#out + 1] = ("%d pot barrel%s"):format(b, b == 1 and "" or "s") end
    return table.concat(out, ", ")
  end

  -- The pot barrels as a lib/mekfeed.lua set, so factory.lua names them to
  -- the storage computer (not storage) along with the Mekanism feeders.
  self.barrelSet = { entries = function()
    local out = {}
    for _, name in ipairs(readBarrels()) do out[#out + 1] = { feeder = name } end
    return out
  end }

  ---------------------------------------------------------------- recipes

  -- How many of a key's items are stored: a name, a name with *, or a list
  -- of names to choose from (they're added up).
  local function have(key)
    if type(key) == "table" then
      local n = 0
      for _, k in ipairs(key) do n = n + have(k) end
      return n
    end
    if not key:find("*", 1, true) then return counts[key] or 0 end
    local pattern = "^" .. key:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
    local n = 0
    for name, c in pairs(counts) do
      if name:find(pattern) then n = n + c end
    end
    return n
  end

  local function keyText(key)
    if type(key) == "table" then return #key == 1 and nice(key[1]) or ("any " .. nice(key[1])) end
    return nice((key:gsub("%*", "")))
  end

  -- How many crafts of a recipe the stored items are enough for.
  local function crafts(r)
    local n = math.huge
    for _, need in ipairs(r.need) do n = math.min(n, math.floor(have(need[1]) / need[2])) end
    return n == math.huge and 0 or n
  end

  -- A recipe from the storage computer, with its cells added up by item:
  -- 8 iron essence rather than eight cells of one.
  local function prepare(raw)
    local byKey, need = {}, {}
    for _, key in pairs(raw.grid or {}) do
      local id = type(key) == "table" and table.concat(key, ",") or key
      if not byKey[id] then
        byKey[id] = { key, 0 }
        need[#need + 1] = byKey[id]
      end
      byKey[id][2] = byKey[id][2] + 1
    end
    table.sort(need, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for i, x in ipairs(need) do parts[i] = ("%d %s"):format(x[2], keyText(x[1])) end
    return { make = raw.make, count = raw.count or 1, need = need, from = table.concat(parts, " + ") }
  end

  local function loadRecipes()
    local reply, err = f.ask({ type = "recipes", uses = ESSENCE })
    if not reply then return false, err end
    if type(reply.recipes) ~= "table" then return false, "the storage computer is too old: run 'install update' on it" end
    if reply.error then return false, reply.error end
    local list = {}
    for _, raw in ipairs(reply.recipes) do
      if type(raw.make) == "string" and type(raw.grid) == "table" then list[#list + 1] = prepare(raw) end
    end
    recipes, recipesAt = list, os.clock()
    return true
  end

  -- The recipes for items whose name has text in it (all of them for ""),
  -- one per item (the one the stored items go furthest with), with how many
  -- can be made: { r, crafts, items }, the ones it can make first, by name.
  local function lookup(text)
    text = (text or ""):lower():gsub("_", " ")
    local best = {}
    for _, r in ipairs(recipes) do
      local name = nice(r.make):lower()
      if text == "" or name:find(text, 1, true) then
        local n = crafts(r)
        local b = best[r.make]
        if not b or n * r.count > b.items then best[r.make] = { r = r, crafts = n, items = n * r.count } end
      end
    end
    local list = {}
    for _, b in pairs(best) do list[#list + 1] = b end
    table.sort(list, function(a, b)
      if (a.items > 0) ~= (b.items > 0) then return a.items > 0 end
      return nice(a.r.make) < nice(b.r.make)
    end)
    return list
  end

  -- Have the storage system make crafts more crafts' worth of r.make, on top
  -- of what's stored and already being made. Returns what to tell the player.
  local function order(r, n)
    local want = n * r.count
    local fresh = f.ask({ type = "count", items = { r.make } })
    if not fresh or type(fresh.counts) ~= "table" then return "The storage computer didn't answer.", "red" end
    local stored = fresh.counts[r.make] or 0
    -- prepare tops up to a total, counting what's being made: find that first
    local now = f.ask({ type = "prepare", items = { [r.make] = 0 } })
    local making = now and type(now.crafting) == "table" and now.crafting[r.make] or 0
    local reply = f.ask({ type = "prepare", items = { [r.make] = stored + making + want } })
    if not reply then return "The storage computer didn't answer.", "red" end
    local why = type(reply.cantCraft) == "table" and reply.cantCraft[r.make]
    local total = type(reply.crafting) == "table" and reply.crafting[r.make] or 0
    if total > making then
      local text = ("Crafting %d %s."):format(total - making, nice(r.make))
      if why then text = text .. " " .. why .. "." end
      if reply.craftProblem then return text .. " " .. reply.craftProblem, "orange" end
      return text, "lime"
    end
    return ("Can't craft %s: %s."):format(nice(r.make), why or "the storage computer didn't start it"), "red"
  end

  ---------------------------------------------------------------- the pots

  -- Empty one pot into the input chest. Fills in p.items (left in it), p.took
  -- and p.state.
  local function emptyPot(p, input)
    -- seen from any side but below, a pot has no slots at all
    local okS, size = pcall(peripheral.call, p.name, "size")
    local ok, list = pcall(peripheral.call, p.name, "list")
    if not okS or (size or 0) == 0 or not ok or type(list) ~= "table" then
      p.state, p.colour = "can't see inside", "red"
      return
    end
    p.items, p.took, p.slots = 0, 0, 0
    local stuck = 0
    for slot, item in pairs(list) do
      -- name the crop by its essence, not a seed it dropped
      if item.name:find(ESSENCE) or not lastCrop[p.name] then lastCrop[p.name] = item.name end
      if not leave(item.name) then
        local okP, moved = pcall(peripheral.call, p.name, "pushItems", input, slot)
        moved = okP and moved or 0
        if moved > 0 then
          taken[item.name] = (taken[item.name] or 0) + moved
          p.took = p.took + moved
        end
        if moved < item.count then stuck = stuck + 1 end
        p.items = p.items + item.count - moved
      else
        p.items, p.slots = p.items + item.count, p.slots + 1 -- slots kept back (config leave)
      end
    end
    p.crop = lastCrop[p.name] and cropOf(lastCrop[p.name])
    if stuck > 0 and not p.hopper then
      p.state, p.colour = "not a hopper pot", "red"
    elseif stuck > 0 then
      p.state, p.colour = "input chest full?", "red"
    elseif p.slots >= POT_SLOTS then
      p.state, p.colour = "full", "orange"
    elseif p.took > 0 then
      p.state, p.colour = "harvested", "lime"
    elseif not p.crop then
      p.state, p.colour = "waiting", "gray"
    else
      p.state, p.colour = "growing", "white"
    end
  end

  -- Empty every pot barrel into the input chest. factory.lua calls this just
  -- before it names the feeders, since the storage computer only takes an
  -- empty one (until then it's storage, so what's in it is counted anyway).
  function self.beforeRegister(input)
    local now = {}
    for _, name in ipairs(readBarrels()) do
      local b = { items = 0, took = 0 }
      local ok, list = pcall(peripheral.call, name, "list")
      if not peripheral.isPresent(name) or not ok or type(list) ~= "table" then
        b.state, b.colour = "not on the cable", "red"
      else
        local stuck, crops, seen = 0, {}, {}
        for slot, item in pairs(list) do
          if item.name:find(ESSENCE) and not seen[item.name] then
            seen[item.name] = true
            crops[#crops + 1] = cropOf(item.name)
          end
          local okP, moved = pcall(peripheral.call, name, "pushItems", input, slot)
          moved = okP and moved or 0
          if moved > 0 then
            taken[item.name] = (taken[item.name] or 0) + moved
            b.took = b.took + moved
          end
          if moved < item.count then stuck = stuck + 1 end
          b.items = b.items + item.count - moved
        end
        table.sort(crops)
        if #crops > 0 then lastCrop[name] = table.concat(crops, ", ") end
        if stuck > 0 then b.state, b.colour = "input chest full?", "red"
        elseif b.took > 0 then b.state, b.colour = "emptied", "lime"
        else b.state, b.colour = "waiting", "white" end
      end
      now[name] = b
    end
    barrelState = now
  end

  function self.read() end

  function self.round(r)
    counts = r.stock.counts
    if not recipesAt or os.clock() - recipesAt > RECIPES_EVERY then
      local ok, why = loadRecipes()
      if not ok then note("No recipes yet: " .. why, "orange") end
    end

    local now = {}
    for i, name in ipairs(myPots()) do
      now[i] = { name = name, title = NAMES[name] or ("Pot " .. i), hopper = name:find("hopper", 1, true) ~= nil }
    end
    local jobs = {}
    for _, p in ipairs(now) do jobs[#jobs + 1] = function() emptyPot(p, r.stock.input) end end
    if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
    for i, name in ipairs(readBarrels()) do
      local b = barrelState[name] or { state = "...", colour = "gray" }
      local p = { name = name, title = NAMES[name] or ("Barrel " .. i), crop = lastCrop[name],
        items = b.items, took = b.took, state = b.state, colour = b.colour }
      -- still storage to the storage computer, which may fill it with anything
      if r.unsure and r.unsure[name] and p.colour ~= "red" then
        p.state, p.colour = "still storage", "red"
        p.why = r.feedProblem or "the storage computer hasn't taken it as a pot barrel yet"
      end
      now[#now + 1] = p
    end
    pots = now

    local took, broken, first = 0, 0, nil
    for _, p in ipairs(pots) do
      took = took + (p.took or 0)
      if p.colour == "red" then
        broken = broken + 1
        first = first or p
      end
    end
    if #pots == 0 then
      note("No botany pots here: stand each on a wired modem, or add the barrel they empty into (Setup).", "orange")
      status("waiting", "no pots")
    elseif first then
      local why = {
        ["can't see inside"] = "stand it on a full-block wired modem (CC only sees a pot from below)",
        ["not a hopper pot"] = "only a Hopper Botany Pot lets its harvest be taken out",
        ["input chest full?"] = "nothing more fits in the storage input chest",
        ["not on the cable"] = "put a wired modem on it, join it to the cable and right-click it",
      }
      note(("%s: %s."):format(first.title, first.why or why[first.state] or first.state), "red")
      status("alert", ("%d of %d botany pots need attention"):format(broken, #pots))
    else
      if took > 0 then note(("Took %d items from the pots."):format(took)) end
      status(took > 0 and "running" or "idle", ("%d botany pots"):format(#pots))
    end
    if not recipesAt then return end
    if took == 0 and not first and #pots > 0 then
      local can = 0
      for _, b in ipairs(lookup("")) do
        if b.items > 0 then can = can + 1 end
      end
      note(("%s growing. Stored essence makes %d kinds of item."):format(self.summary(), can))
    end
  end

  ---------------------------------------------------------------- screen

  local view = "recipes" -- or "pots"
  local query = "" -- the Find box
  local list = {} -- the recipes shown, from lookup()
  local selected, scroll, amount = 1, 0, 1
  local buttons = {} -- { x1, x2, y, action } from the last frame

  local function current() return list[selected] end

  local function refreshList()
    local all = lookup(query)
    list = {}
    for _, b in ipairs(all) do
      -- browsing shows what you can make; a search finds everything
      if query ~= "" or b.items > 0 then list[#list + 1] = b end
    end
    selected = math.max(1, math.min(selected, #list))
  end

  local function essenceTotals()
    local total, kinds = 0, 0
    for name, n in pairs(counts) do
      if name:find(ESSENCE) then total, kinds = total + n, kinds + 1 end
    end
    return total, kinds
  end

  local function button(win, x, y, text, action, fg, bg)
    screen.put(win, x, y, text, fg or "black", bg or "lightGray")
    buttons[#buttons + 1] = { x, x + #text - 1, y, action }
    return x + #text + 1
  end

  local function drawRecipes(win, w, h)
    local fit = screen.fit
    local rows = h - 6
    screen.put(win, 1, 2, "Find: ", "yellow")
    screen.put(win, 7, 2, fit(query, w - 24), "white", "gray")
    screen.put(win, 2, 3, "Makes", "yellow")
    screen.put(win, 21, 3, "From", "yellow")
    screen.put(win, w - 12, 3, "  Can", "yellow")
    screen.put(win, w - 6, 3, "Stored", "yellow")
    if selected <= scroll then scroll = selected - 1 end
    if selected > scroll + rows then scroll = selected - rows end
    for i = 1, rows do
      local b, y = list[scroll + i], 3 + i
      if b then
        local on = scroll + i == selected
        local bg = on and "gray" or "black"
        local fg = b.items > 0 and "white" or "lightGray"
        screen.put(win, 1, y, (" "):rep(w), fg, bg)
        screen.put(win, 2, y, fit(nice(b.r.make), 18), fg, bg)
        screen.put(win, 21, y, fit(b.r.from, w - 34), "lightGray", bg)
        screen.put(win, w - 12, y, ("%5s"):format(b.items > 9999 and "9999+" or b.items), b.items > 0 and "lime" or "gray", bg)
        screen.put(win, w - 6, y, ("%6s"):format(math.min(counts[b.r.make] or 0, 999999)), "lightGray", bg)
        buttons[#buttons + 1] = { 1, w, y, { pick = scroll + i } }
      end
    end
    if #list == 0 then
      local text = #recipes == 0 and "No essence recipes yet (see Things to know)."
        or query ~= "" and "No recipe makes that."
        or "Not enough essence for anything yet."
      screen.put(win, 2, 4, text, "gray")
    end
    local b = current()
    if b then
      local y = h - 2
      local x = button(win, 1, y, " - ", { add = -1 })
      local sum = ("%d x %d = %d"):format(amount, b.r.count, amount * b.r.count)
      screen.put(win, x, y, sum, "white")
      x = x + #sum + 1
      x = button(win, x, y, " + ", { add = 1 })
      x = button(win, x, y, " Max ", { max = true })
      button(win, x, y, " Order ", { order = true }, "white", amount <= b.crafts and "green" or "orange")
    end
  end

  local function drawPots(win, w, h)
    local fit = screen.fit
    local mins = (os.epoch("utc") - takenSince) / 60000
    local total = 0
    for _, n in pairs(taken) do total = total + n end
    -- a rate from the first few rounds would be wildly off
    local rate = mins >= 5 and ("%d an hour"):format(math.floor(total / mins * 60)) or "rate after 5 minutes"
    screen.put(win, 2, 2, fit(("Taken: %d (%s)"):format(total, rate), w - 18), "white")
    screen.put(win, 2, 3, "Pot", "yellow")
    screen.put(win, 14, 3, "Crop", "yellow")
    screen.put(win, 31, 3, "Left", "yellow")
    screen.put(win, 37, 3, "Doing", "yellow")
    local rows = h - 6
    for i = 1, math.min(rows, #pots) do
      local p, y = pots[i], 3 + i
      screen.put(win, 2, y, fit(p.title, 11), "white")
      screen.put(win, 14, y, fit(p.crop or "-", 16), "lightGray")
      screen.put(win, 31, y, fit(tostring(p.items or 0), 5), "white")
      screen.put(win, 37, y, fit(p.state or "...", w - 37), p.colour or "gray")
    end
    if #pots > rows then screen.put(win, 2, h - 2, ("...and %d more"):format(#pots - rows), "gray") end
    if #pots == 0 then screen.put(win, 2, 4, "No botany pots or pot barrels here yet.", "gray") end
  end

  function self.key()
    local key = { view, query, selected, scroll, amount, #list, #recipes, self.message[1], self.message[2] }
    for name, n in pairs(counts) do
      if name:find(ESSENCE) then key[#key + 1] = name .. n end
    end
    for _, p in ipairs(pots) do key[#key + 1] = table.concat({ p.title, p.crop or "", p.items or 0, p.state or "" }, "/") end
    return table.concat(key, "|")
  end

  -- The terminal page, under the factory's tab bar (row 1): the recipe
  -- finder, or the pots.
  function self.draw(win, w, h)
    buttons = {}
    local x = w - 16
    for _, t in ipairs({ { "recipes", " Recipes " }, { "pots", " Pots " } }) do
      x = button(win, x, 2, t[2], { view = t[1] }, view == t[1] and "black" or "white", view == t[1] and "yellow" or "gray")
    end
    if view == "recipes" then drawRecipes(win, w, h) else drawPots(win, w, h) end
    local total, kinds = essenceTotals()
    screen.put(win, 1, h - 1, screen.fit(self.message[1], w), self.message[2])
    screen.put(win, 1, h, screen.fit(view == "recipes"
      and ("Essence %d (%d kinds). Type to find, arrows, Enter orders"):format(total, kinds)
      or "Tab: next page  F1: setup", w), "gray")
  end

  -- Where the cursor goes on the terminal (the Find box), if anywhere.
  function self.cursor(w)
    if view == "recipes" then return 7 + math.min(#query, w - 25), 2 end
  end

  function self.tiles()
    local tiles = {}
    local map = { lime = "yellow", white = "lime", gray = "lime", orange = "orange", red = "red" }
    for _, p in ipairs(pots) do
      tiles[#tiles + 1] = { p.title, p.crop or p.state or "...", map[p.colour] or "lime" }
    end
    return tiles
  end

  local function act(a)
    local b = current()
    if a.view then view = a.view
    elseif a.pick then
      if a.pick ~= selected then selected, amount = a.pick, 1 end
    elseif a.add and b then amount = math.max(1, amount + a.add)
    elseif a.max and b then amount = math.max(1, b.crafts)
    elseif a.order and b then
      say(("Ordering %d %s..."):format(amount * b.r.count, nice(b.r.make)))
      tell(order(b.r, amount))
      amount = 1
    end
  end

  -- Keys, typing and clicks while its page is showing (x, y: a click on the
  -- terminal). Never takes over the terminal, so false.
  function self.event(ev, x, y)
    local e = ev[1]
    if e == "char" and view == "recipes" then
      query = query .. ev[2]
      selected, amount = 1, 1
      refreshList()
    elseif e == "key" and view == "recipes" then
      local k = ev[2]
      if k == keys.backspace then
        query = query:sub(1, -2)
        selected = 1
        refreshList()
      elseif k == keys.up then selected, amount = math.max(1, selected - 1), 1
      elseif k == keys.down then selected, amount = math.min(#list, selected + 1), 1
      elseif k == keys.pageUp then amount = amount + 10
      elseif k == keys.pageDown then amount = math.max(1, amount - 10)
      elseif k == keys.right then act({ add = 1 })
      elseif k == keys.left then act({ add = -1 })
      elseif k == keys["end"] then act({ max = true })
      elseif k == keys.enter or k == keys.numPadEnter then act({ order = true })
      end
    elseif e == "mouse_scroll" and view == "recipes" then
      selected, amount = math.max(1, math.min(#list, selected + ev[2])), 1
    elseif e == "factory_changed" then
      refreshList()
    elseif x then
      for _, bt in ipairs(buttons) do
        if y == bt[3] and x >= bt[1] and x <= bt[2] then
          act(bt[4])
          break
        end
      end
    end
    return false
  end

  ---------------------------------------------------------------- pot barrels

  -- Why name can't be a pot barrel, or nil if it can.
  local function cantBe(name)
    if not peripheral.isPresent(name) then return name .. " isn't on the network." end
    for _, b in ipairs(readBarrels()) do
      if b == name then return name .. " is a pot barrel already." end
    end
    if f.taken(name) then return name .. " is used by another machine." end
    return nil
  end

  local function addBarrel(name)
    local list = readBarrels()
    list[#list + 1] = name
    writeBarrels(list)
    return ("Barrel %d: %s. It's emptied into storage every %d seconds."):format(#list, name, self.every)
  end

  -- 'factory add potbarrel [barrel]': asks which if it's not given.
  function self.addCommand(name)
    if not name then
      local free = {}
      for _, n in ipairs(barrelsOnNetwork(POTS)) do
        if not cantBe(n) then free[#free + 1] = n end
      end
      if #free == 0 then
        print("No free barrel or chest on the network: put a wired modem on it, join it to the cable and right-click it.")
        return
      end
      print("The barrel (or chest) the Hopper Botany Pots empty into. Right-click its modem to see its name.")
      for i, n in ipairs(free) do print(("%2d  %s"):format(i, n)) end
      write("Which? (Enter to cancel) ")
      local text = read()
      if text == "" then return end
      name = free[tonumber(text)] or text
    end
    local why = cantBe(name)
    if why then print(why) return end
    print(addBarrel(name))
  end

  -- Every pot barrel, for 'factory list' and 'factory remove': { text, remove() }.
  function self.listed()
    local out = {}
    for i, name in ipairs(readBarrels()) do
      out[#out + 1] = { text = ("Barrel %d: %s, botany pots empty into it"):format(i, name), remove = function()
        local list = readBarrels()
        table.remove(list, i)
        writeBarrels(list)
        return ("Forgot %s: it's storage again."):format(name)
      end }
    end
    return out
  end

  -- The pot barrels on the factory's Machines page (lib/setupui.lua): a row
  -- per barrel (tap to remove it) and + Add a botany pot barrel.
  function self.setupParts(ui)
    local function add()
      local list = readBarrels()
      ui:pickChest({ title = "Pick the pot barrel", hint = "The barrel or chest the Hopper Botany Pots empty into.",
        names = barrelsOnNetwork(POTS),
        nothing = "No barrels here: put a wired modem on it and right-click it.",
        roleOf = function(n)
          for _, b in ipairs(list) do
            if b == n then return "a pot barrel" end
          end
          return f.taken(n) and "in use" or nil
        end,
        pick = function(n)
          local why = cantBe(n)
          if why then ui:say(why, "orange") return end
          ui:back()
          ui:say(addBarrel(n), "lime")
        end })
    end
    local parts = {}
    function parts.entries()
      local out = {}
      for i, name in ipairs(readBarrels()) do
        out[#out + 1] = { label = ("Pot barrel %d"):format(i), value = name,
          colour = peripheral.isPresent(name) and "lightGray" or "red", act = function()
            ui:open({ title = ("Pot barrel %d"):format(i), hint = name, rows = function()
              return { { label = "Remove it", colour = "red", act = function()
                local now = readBarrels()
                if now[i] == name then table.remove(now, i) end
                writeBarrels(now)
                ui:back()
                ui:say(("Forgot %s: it's storage again."):format(name), "lime")
              end } }
            end })
          end }
      end
      return out
    end
    function parts.adds()
      return { { label = "+ Add a botany pot barrel", colour = "lime", act = add } }
    end
    return parts
  end

  ---------------------------------------------------------------- commands

  -- 'factory find <text>' / 'factory make <count> <text>': stock and recipes
  -- once, then out. True if args was one of them.
  function self.command(args)
    if args[1] ~= "find" and args[1] ~= "make" then return false end
    local n = args[1] == "make" and tonumber(args[2])
    local text = table.concat(args, " ", n and 3 or 2)
    if args[1] == "make" and (not n or n < 1 or text == "") then
      print("Usage: factory make <count> <item>")
      return true
    end
    local reply = f.ask({ type = "stock" })
    if not reply or type(reply.counts) ~= "table" then
      print("The storage computer didn't answer. Is it running, on the same cable?")
      return true
    end
    counts = reply.counts
    local ok, why = loadRecipes()
    if not ok then
      print("No recipes: " .. why)
      return true
    end
    local found = lookup(text)
    if #found == 0 then
      print(("No essence recipe makes anything called '%s'."):format(text))
      return true
    end
    if args[1] == "find" then
      for i = 1, math.min(#found, 15) do
        local b = found[i]
        print(("%-18s %s -> %d, can make %d"):format(nice(b.r.make), b.r.from, b.r.count, b.items))
      end
      if #found > 15 then print(("...and %d more."):format(#found - 15)) end
      return true
    end
    local b = found[1]
    local said, colour = order(b.r, math.ceil(n / b.r.count))
    if term.isColor() then term.setTextColor(colors[colour] or colors.white) end
    print(said)
    term.setTextColor(colors.white)
    return true
  end

  return self
end

return M
