-- Mystical Agriculture essence for the storage system. Empties every
-- Hopper Botany Pot on the storage computer's wired network into the
-- storage input chest, and looks up what the stored essence can be crafted
-- into (iron ingots, dirt, diamonds, ...), so you can order it: the storage
-- system's crafting turtle makes it.
--
--   essence                         start (startup.lua runs this)
--   essence setup                   the setup screen: the pots it found and what each needs, the recipes and
--                                   the storage computer (in the running program if there is one; or Setup
--                                   at the top right of its screen, or F1)
--   essence find <text>             list the recipes for items matching text, and how many you can make
--   essence make <count> <text>     order count of an item (the first match for text)
--
-- The recipes come from the storage computer: Mystical Agriculture's are in
-- the modpack's pack_recipes.lua (tools/recipes.mjs), or teach one with
-- 'crafter learn'. A pot shows CC only its harvest, and only through its
-- bottom, so each pot stands on a full-block wired modem; the seed and soil
-- are never touched.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local setupui = require("lib.setupui") -- the setup screen
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local config = fs.exists("config.lua") and require("config") or {}

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local EVERY = 10 -- seconds between rounds of emptying the pots
local RECIPES_EVERY = 300 -- seconds between asking the storage computer for its recipes again
local REPLY_WAIT = 30 -- seconds to wait for the storage computer to answer (a busy one answers late)
local POT_SLOTS = 12 -- harvest slots in a pot

-- Used if config.lua has none; see config.lua for what they mean.
local ESSENCE = config.essence or "^mysticalagriculture:.+_essence$"
local POTS = config.pots or "botany_pot"
local LEAVE = config.leave or {}
local NAMES = config.names or {}

local pots = {} -- what the Pots tab shows, one entry per pot
local recipes = {} -- best recipe per item made: { make, count, need = { { key, n } }, from }
local recipesAt -- os.clock() when the recipes last came
local counts = {} -- item -> how many are stored
local taken, takenSince = {}, os.epoch("utc") -- item -> how many came out of the pots since starting
local lastCrop = {} -- pot -> what came out of it last, to name its crop
local message = { "Looking for the storage computer...", "lightGray" }
local news -- { text, colour, untilTime }: how an order went, kept on screen a while

---------------------------------------------------------------- helpers

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("essence_changed")
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

local function status(state, detail)
  if report then report.set(state, detail) end
end

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

-- The crop a pot grows, from what it gives: "iron essence" -> "iron".
local function cropOf(name) return (nice(name):gsub(" essence$", "")) end

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
  local reply, err = ask({ type = "recipes", uses = ESSENCE })
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
  local fresh = ask({ type = "count", items = { r.make } })
  if not fresh or type(fresh.counts) ~= "table" then return "The storage computer didn't answer.", "red" end
  local stored = fresh.counts[r.make] or 0
  -- prepare tops up to a total, counting what's being made: find that first
  local now = ask({ type = "prepare", items = { [r.make] = 0 } })
  local making = now and type(now.crafting) == "table" and now.crafting[r.make] or 0
  local reply = ask({ type = "prepare", items = { [r.make] = stored + making + want } })
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

local function round()
  local reply, err = ask({ type = "stock" })
  if not reply or type(reply.counts) ~= "table" then
    note("Storage not answering: is it running, on the same cable?", "orange")
    status("waiting", ("storage computer: %s"):format(err or "too old to answer"))
    return
  end
  counts = reply.counts
  if not recipesAt or os.clock() - recipesAt > RECIPES_EVERY then
    local ok, why = loadRecipes()
    if not ok then note("No recipes yet: " .. why, "orange") end
  end

  local now = {}
  for i, name in ipairs(findPots()) do
    now[i] = { name = name, title = NAMES[name] or ("Pot " .. i), hopper = name:find("hopper", 1, true) ~= nil }
  end
  local jobs = {}
  for _, p in ipairs(now) do jobs[#jobs + 1] = function() emptyPot(p, reply.input) end end
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
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
    note("No botany pots on the network: stand each on a full-block wired modem joined to the cable.", "orange")
    status("waiting", "no pots")
  elseif first then
    local why = {
      ["can't see inside"] = "stand it on a full-block wired modem (CC only sees a pot from below)",
      ["not a hopper pot"] = "only a Hopper Botany Pot lets its harvest be taken out",
      ["input chest full?"] = "nothing more fits in the storage input chest",
    }
    note(("%s: %s."):format(first.title, why[first.state] or first.state), "red")
    status("alert", ("%d of %d pots need attention"):format(broken, #pots))
  else
    if took > 0 then note(("Took %d items from the pots."):format(took)) end
    status(took > 0 and "running" or "idle", ("%d pots"):format(#pots))
  end
  if not recipesAt then return end
  if took == 0 and not first and #pots > 0 then
    local can = 0
    for _, b in ipairs(lookup("")) do
      if b.items > 0 then can = can + 1 end
    end
    note(("%d pots growing. Stored essence makes %d kinds of item."):format(#pots, can))
  end
end

---------------------------------------------------------------- screen

local display = screen.new(term.current())
local fitText = screen.fit

local tab = "recipes" -- or "pots"
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
  local rows = h - 6
  screen.put(win, 1, 2, "Find: ", "yellow")
  screen.put(win, 7, 2, fitText(query, w - 7), "white", "gray")
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
      screen.put(win, 2, y, fitText(nice(b.r.make), 18), fg, bg)
      screen.put(win, 21, y, fitText(b.r.from, w - 34), "lightGray", bg)
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
    screen.put(win, x, y, ("%d x %d = %d"):format(amount, b.r.count, amount * b.r.count), "white")
    x = x + #("%d x %d = %d"):format(amount, b.r.count, amount * b.r.count) + 1
    x = button(win, x, y, " + ", { add = 1 })
    x = button(win, x, y, " Max ", { max = true })
    button(win, x, y, " Order ", { order = true }, "white", amount <= b.crafts and "green" or "orange")
  end
end

local function drawPots(win, w, h)
  local mins = (os.epoch("utc") - takenSince) / 60000
  local total = 0
  for _, n in pairs(taken) do total = total + n end
  -- a rate from the first few rounds would be wildly off
  local rate = mins >= 5 and ("%d an hour"):format(math.floor(total / mins * 60)) or "rate after 5 minutes"
  screen.put(win, 2, 2, fitText(("Taken: %d (%s)"):format(total, rate), w - 2), "white")
  screen.put(win, 2, 3, "Pot", "yellow")
  screen.put(win, 14, 3, "Crop", "yellow")
  screen.put(win, 31, 3, "Left", "yellow")
  screen.put(win, 37, 3, "Doing", "yellow")
  local rows = h - 6
  for i = 1, math.min(rows, #pots) do
    local p, y = pots[i], 3 + i
    screen.put(win, 2, y, fitText(p.title, 11), "white")
    screen.put(win, 14, y, fitText(p.crop or "-", 16), "lightGray")
    screen.put(win, 31, y, fitText(tostring(p.items or 0), 5), "white")
    screen.put(win, 37, y, fitText(p.state or "...", w - 37), p.colour or "gray")
  end
  if #pots > rows then screen.put(win, 2, h - 2, ("...and %d more"):format(#pots - rows), "gray") end
  if #pots == 0 then screen.put(win, 2, 4, "No botany pots on the network yet.", "gray") end
end

local function draw()
  buttons = {}
  local win, w, h = display:frame()
  screen.put(win, 1, 1, (" "):rep(w), "white", "gray")
  local total, kinds = essenceTotals()
  screen.put(win, 2, 1, fitText(("Essence %d (%d kinds)"):format(total, kinds), w - 28), "yellow", "gray")
  local x = w - 24
  for _, t in ipairs({ { "recipes", " Recipes " }, { "pots", " Pots " } }) do
    x = button(win, x, 1, t[2], { tab = t[1] }, tab == t[1] and "black" or "white", tab == t[1] and "yellow" or "gray")
  end
  button(win, w - 6, 1, " Setup ", { setup = true })
  if tab == "recipes" then drawRecipes(win, w, h) else drawPots(win, w, h) end
  screen.put(win, 1, h - 1, fitText(message[1], w), message[2])
  screen.put(win, 1, h, fitText(tab == "recipes" and "Type to find, arrows pick + amount, Enter orders, F1 setup"
    or "Tab: recipes  F1: setup", w), "gray")
  if tab == "recipes" then
    win.setCursorPos(7 + math.min(#query, w - 8), 2)
    win.setTextColor(colors.white)
    win.setCursorBlink(true)
  end
  display:show()
end

-- The pots it found (nothing to pick: every Hopper Botany Pot on the
-- cable is used), the recipes and the storage computer, on the terminal
-- (lib/setupui.lua), like the other programs' setup screens.
local function setupScreen()
  local ui = setupui.new({ screens = { display }, name = "essence" })
  ui:say("Every Hopper Botany Pot on the cable is used: nothing to pick.")
  ui:run({
    title = "Essence setup",
    rows = function()
      local found = findPots()
      return {
        { label = "Pots", value = ("%d on the network"):format(#found), act = function()
          ui:open({
            title = "Pots", hint = "Stand each pot on a full-block wired modem joined to the cable.",
            rows = function()
              local byName, out = {}, {}
              for _, p in ipairs(pots) do byName[p.name] = p end
              for i, name in ipairs(findPots()) do
                local p = byName[name]
                out[#out + 1] = { label = NAMES[name] or ("Pot " .. i),
                  value = p and ("%s: %s"):format(p.crop or "-", p.state or "...") or name,
                  colour = p and p.colour == "red" and "red" or "lightGray" }
              end
              if #out == 0 then out[1] = { label = "No botany pots on the network yet.", dim = true } end
              return out
            end,
          })
        end },
        { label = "Recipes", value = recipesAt and ("%d from the storage computer"):format(#recipes)
          or "not loaded yet", colour = #recipes > 0 and "lightGray" or "orange" },
        { label = "Storage computer", value = next(counts) and "answering" or "no answer yet",
          colour = next(counts) and "lightGray" or "orange" },
      }
    end,
  })
end

local function act(a)
  local b = current()
  if a.setup then setupScreen()
  elseif a.tab then tab = a.tab
  elseif a.pick then
    if a.pick ~= selected then selected, amount = a.pick, 1 end
  elseif a.add and b then amount = math.max(1, amount + a.add)
  elseif a.max and b then amount = math.max(1, b.crafts)
  elseif a.order and b then
    say(("Ordering %d %s..."):format(amount * b.r.count, nice(b.r.make)))
    draw()
    tell(order(b.r, amount))
    amount = 1
  end
end

local function uiLoop()
  refreshList()
  while true do
    draw()
    local ev = { os.pullEvent() }
    local e = ev[1]
    -- F1, or 'essence setup' in another tab (the Setup button is one of the buttons)
    if setupui.wanted("essence", ev) or (e == "key" and ev[2] == keys.f1) then
      setupScreen()
    elseif e == "char" and tab == "recipes" then
      query = query .. ev[2]
      selected, amount = 1, 1
      refreshList()
    elseif e == "key" then
      local k = ev[2]
      if k == keys.tab then tab = tab == "recipes" and "pots" or "recipes"
      elseif tab == "recipes" then
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
      end
    elseif e == "mouse_scroll" and tab == "recipes" then
      selected, amount = math.max(1, math.min(#list, selected + ev[2])), 1
    elseif e == "essence_changed" then
      refreshList()
    else
      local x, y = display:clicked(ev)
      if x then
        for _, bt in ipairs(buttons) do
          if y == bt[3] and x >= bt[1] and x <= bt[2] then
            act(bt[4])
            break
          end
        end
      end
    end
  end
end

local function workLoop()
  while true do
    local ok, err = (errlog and errlog.pcall or pcall)(round)
    if not ok then say("Error: " .. tostring(err), "red") end
    os.queueEvent("essence_changed")
    sleep(EVERY)
  end
end

---------------------------------------------------------------- commands

local function connect()
  if net.open("any") then return true end
  print("I need a wired modem on the storage computer's network.")
  print("Put one on me, join it to the network with cable and right-click it so it turns red.")
  return false
end

-- 'essence find' / 'essence make': stock and recipes once, then out.
local function fetch()
  local reply = ask({ type = "stock" })
  if not reply or type(reply.counts) ~= "table" then
    print("The storage computer didn't answer. Is it running, on the same cable?")
    return false
  end
  counts = reply.counts
  local ok, why = loadRecipes()
  if not ok then print("No recipes: " .. why) end
  return ok
end

local args = { ... }
if args[1] == "find" or args[1] == "make" then
  local n = args[1] == "make" and tonumber(args[2])
  local text = table.concat(args, " ", n and 3 or 2)
  if args[1] == "make" and (not n or n < 1 or text == "") then
    print("Usage: essence make <count> <item>")
    return
  end
  if not connect() or not fetch() then return end
  local found = lookup(text)
  if #found == 0 then
    print(("No essence recipe makes anything called '%s'."):format(text))
    return
  end
  if args[1] == "find" then
    for i = 1, math.min(#found, 15) do
      local b = found[i]
      print(("%-18s %s -> %d, can make %d"):format(nice(b.r.make), b.r.from, b.r.count, b.items))
    end
    if #found > 15 then print(("...and %d more."):format(#found - 15)) end
    return
  end
  local b = found[1]
  local text2, colour = order(b.r, math.ceil(n / b.r.count))
  if term.isColor() then term.setTextColor(colors[colour] or colors.white) end
  print(text2)
  term.setTextColor(colors.white)
  return
elseif args[1] == "setup" then
  if setupui.openInRunning("essence") then
    print("The setup screen is open in the essence program (its tab).")
    return
  end
  if connect() then fetch() end
  setupScreen()
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  return
elseif args[1] then
  print("Usage: essence [setup | find <item> | make <count> <item>]")
  return
end

if not connect() then return end
term.clear()
if errlog then errlog.init("essence") end
if report then report.init("essence") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, workLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
