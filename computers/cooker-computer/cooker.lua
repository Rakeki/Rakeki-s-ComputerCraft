-- Cooking pots for the storage system. Runs Cobblemon campfire pots on the
-- storage computer's wired network: makes exp candy XS from sculk and
-- honeycomb, and compresses it up the chain (6 XS -> S, 3 S -> M, 3 M -> L,
-- 3 L -> XL), or any other pot recipe set in config.lua. One pot per recipe.
--
--   cooker                                start (startup.lua runs this)
--   cooker add [recipe feed output]       add a pot (asks for anything not given)
--   cooker remove <n>                     forget pot n (no number: list them)
--   cooker reset <n>                      after emptying pot n by hand
--
-- CC can't reach into a pot, so every pot has two hoppers on the network: a
-- feed hopper pointing into its side, which the storage computer fills, and
-- an output hopper under it, which this program empties into the storage
-- computer's input chest. Redstone power keeps the pot's lid shut, and it
-- only cooks with the lid shut.
--
-- A hopper puts each item in the pot's first slot that's empty or holds the
-- same item, so the pot's slots can't be picked. That's why the program
-- counts what went in and what came out, and never lets a slot overflow
-- into the next one:
--   * different items (sculk + honeycomb): one slot each, at most 64 of each
--     in the pot, and the first item always ahead of the others in the feed
--     hopper, so the first pot slot is never empty while a later one isn't
--     (the next item would land there and jam the pot);
--   * one item n times (6 XS candy): slots fill one after the other, so the
--     pot cooks once n - 1 slots are full, and holds at most n * 64.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local config = fs.exists("config.lua") and require("config") or {}

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local POTS_FILE = "/.cooker_pots" -- the pots: { recipe, feed, out, since }, changed by 'cooker add' etc.
local COUNTS_FILE = "/.cooker_counts" -- feed hopper -> { since, pushed = { [item] = n }, made }, kept by the running program
local EVERY = 10 -- seconds between rounds of emptying and filling the pots
local REPLY_WAIT = 5 -- seconds to wait for the storage computer to answer
local SLOT_MAX = 64 -- items a pot slot holds
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local HOPPER_SLOTS = 5 -- slots in a hopper
local STUCK_AFTER = 120 -- seconds a pot that should be cooking may make nothing before the screen says so

-- Used if config.lua has none; see config.lua for what they mean.
local RECIPES = config.recipes or {
  exp_candy_xs = { make = "cobblemon:exp_candy_xs", "minecraft:sculk", "minecraft:honeycomb" },
  exp_candy_s = { make = "cobblemon:exp_candy_s", "cobblemon:exp_candy_xs", times = 6 },
  exp_candy_m = { make = "cobblemon:exp_candy_m", "cobblemon:exp_candy_s", times = 3 },
  exp_candy_l = { make = "cobblemon:exp_candy_l", "cobblemon:exp_candy_m", times = 3 },
  exp_candy_xl = { make = "cobblemon:exp_candy_xl", "cobblemon:exp_candy_l", times = 3 },
}
local KEEP = config.keep or {}

local pots = {} -- what the screen shows: each pot with its recipe and how it's doing
local message = { "Looking for the storage computer...", "lightGray" }

---------------------------------------------------------------- helpers

local function say(text, colour)
  message = { text, colour or "lightGray" }
  os.queueEvent("cooker_changed")
end

local function status(state, detail)
  if report then report.set(state, detail) end
end

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

-- A recipe from config.lua in the form the program works with: { make,
-- makes, items = { name, ... }, same = n (one item n times) }, or nil and
-- what's wrong with it.
local function recipeOf(key)
  local r = RECIPES[key]
  if type(r) ~= "table" or type(r.make) ~= "string" or type(r[1]) ~= "string" then
    return nil, ("no recipe called %s in config.lua"):format(tostring(key))
  end
  local out = { key = key, make = r.make, makes = tonumber(r.makes) or 1 }
  if r.times then
    local n = math.floor(tonumber(r.times) or 0)
    if n < 2 or n > 9 or r[2] then return nil, ("%s: times must be 2 to 9, with one item"):format(key) end
    out.items, out.same = { r[1] }, n
  else
    local seen = {}
    for i, name in ipairs(r) do
      if seen[name] then
        -- a hopper would stack the two into one slot
        return nil, ("%s: an item twice needs 'times', and can't be mixed with others"):format(key)
      end
      seen[name] = i
    end
    if #r > HOPPER_SLOTS then return nil, ("%s: at most %d different items"):format(key, HOPPER_SLOTS) end
    out.items = { table.unpack(r) }
  end
  return out
end

local function recipeText(r)
  if r.same then return ("%d %s"):format(r.same, nice(r.items[1])) end
  local names = {}
  for i, name in ipairs(r.items) do names[i] = nice(name) end
  return table.concat(names, " + ")
end

local function readPots()
  local t = files.read(POTS_FILE)
  return type(t) == "table" and t or {}
end

local function writePots(t)
  files.write(POTS_FILE, t)
  os.queueEvent("cooker_changed") -- the running cooker, if this is another tab
end

-- Hoppers on the wired network (not ones touching this computer: the
-- storage computer can't reach those).
local function findHoppers()
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if not sides[name] and t and t:find("hopper", 1, true) then list[#list + 1] = name end
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

---------------------------------------------------------------- the pot model

-- Cooks done so far, from what came out.
local function cooks(p) return math.floor(p.count.made / p.recipe.makes) end

-- Items of each kind in the pot and its feed hopper together (at most:
-- cooked results still in the pot haven't been counted yet).
local function loaded(p, name) return (p.count.pushed[name] or 0) - cooks(p) * (p.recipe.same or 1) end

-- True if what has gone into the pot (not still in the feed hopper) is
-- enough for it to be cooking.
local function shouldCook(p)
  local r = p.recipe
  if r.same then
    local name = r.items[1]
    return loaded(p, name) - (p.hopper[name] or 0) >= (r.same - 1) * SLOT_MAX + 1
  end
  for _, name in ipairs(r.items) do
    if loaded(p, name) - (p.hopper[name] or 0) < 1 then return false end
  end
  return true
end

-- How many of each item to send to the feed hopper now, given what storage
-- can spare: { { name, n, slot } } in the order to send them.
local function plan(p, avail)
  local r, out = p.recipe, {}
  local inHopper = 0
  for _, n in pairs(p.hopper) do inHopper = inHopper + n end
  if r.same then
    local name = r.items[1]
    local n = math.min(r.same * SLOT_MAX - loaded(p, name), avail[name] or 0, SEND_MAX,
      HOPPER_SLOTS * SLOT_MAX - inHopper)
    if n > 0 then out[1] = { name, n } end
    return out
  end
  -- everything up to the same total, which keeps sets whole, at most a
  -- slot's worth in the pot; the first item (hopper slot 1, which empties
  -- first) never behind the others
  local made = cooks(p)
  local target = made + SLOT_MAX
  for _, name in ipairs(r.items) do
    target = math.min(target, (p.count.pushed[name] or 0) + (avail[name] or 0))
  end
  -- (round() stops after the first item if it gets fewer than asked for)
  local leadTotal = p.count.pushed[r.items[1]] or 0
  for i, name in ipairs(r.items) do
    local upTo = i == 1 and target or math.min(target, leadTotal)
    local n = math.min(upTo - (p.count.pushed[name] or 0), SLOT_MAX - (p.hopper[name] or 0), SEND_MAX)
    if n > 0 then out[#out + 1] = { name, n, i } end
    if i == 1 then leadTotal = leadTotal + math.max(0, n) end
  end
  return out
end

---------------------------------------------------------------- a round

local stuckSince = {} -- feed hopper -> { at = os.clock(), made }: should have been cooking since, with nothing more made

local function round()
  local list = readPots()
  local counts = files.read(COUNTS_FILE)
  counts = type(counts) == "table" and counts or {}
  local nowPots = {}
  for i, entry in ipairs(list) do
    local r, why = recipeOf(entry.recipe)
    nowPots[i] = { n = i, entry = entry, recipe = r, problem = why, hopper = {} }
  end

  -- each call takes a tick, so read every hopper at once
  local reads = {}
  for _, p in ipairs(nowPots) do
    reads[#reads + 1] = function()
      local okF, feed = pcall(peripheral.call, p.entry.feed, "list")
      local okO, out = pcall(peripheral.call, p.entry.out, "list")
      p.feedOk, p.outOk = okF and type(feed) == "table", okO and type(out) == "table"
      for _, item in pairs(p.feedOk and feed or {}) do p.hopper[item.name] = (p.hopper[item.name] or 0) + item.count end
      p.outList = p.outOk and out or {}
    end
  end
  parallel.waitForAll(table.unpack(reads))

  -- counts start again for a new or emptied pot: what's in its feed hopper
  -- now is on its way in
  for _, p in ipairs(nowPots) do
    local c = counts[p.entry.feed]
    if type(c) ~= "table" or c.since ~= p.entry.since then
      c = { since = p.entry.since, pushed = {}, made = 0 }
      for name, n in pairs(p.hopper) do c.pushed[name] = n end
      counts[p.entry.feed] = c
    end
    p.count = c
  end
  pots = nowPots
  if #pots == 0 then
    say("No pots yet: run 'cooker add' in another tab (Ctrl+T, or the + in multishell).", "orange")
    status("waiting", "no pots")
    return
  end

  local reply, err = ask({ type = "stock" })
  if not reply or type(reply.counts) ~= "table" then
    say("Storage not answering: is it running, on the same cable?", "orange")
    status("waiting", ("storage computer: %s"):format(err or "too old to answer"))
    files.write(COUNTS_FILE, counts)
    return
  end
  local input, avail = reply.input, {}
  for name, n in pairs(reply.counts) do avail[name] = math.max(0, n - (KEEP[name] or 0)) end

  -- what's cooked goes back through the input chest
  local problem, blocked = nil, false
  for _, p in ipairs(pots) do
    for slot, item in pairs(p.outList or {}) do
      local ok, moved = pcall(peripheral.call, p.entry.out, "pushItems", input, slot)
      if not ok then problem, moved = tostring(moved), 0 end
      if p.recipe and item.name == p.recipe.make then p.count.made = p.count.made + moved end
      if moved < item.count then blocked = true end
    end
  end

  -- fill the feed hoppers, pot by pot (two pots making the same thing share
  -- what there is, first one first)
  local sent, oldReplies = 0, false
  for _, p in ipairs(pots) do
    if p.recipe and p.feedOk and p.outOk then
      for _, step in ipairs(plan(p, avail)) do
        local name, n, slot = step[1], step[2], step[3]
        local r = ask({ type = "send", to = p.entry.feed, slot = slot, items = { [name] = n } })
        local got = r and type(r.sent) == "table" and r.sent[name]
        if r and r.error then
          problem = r.error
          if r.error:find("isn't a furnace on", 1, true) then oldReplies = true end
        end
        if not r then
          -- no answer: it may have sent them all, and too many is safe
          -- (the pot fills less), too few isn't
          got = n
          problem = "the storage computer didn't answer while loading pot " .. p.n
        end
        got = got or 0
        p.count.pushed[name] = (p.count.pushed[name] or 0) + got
        p.hopper[name] = (p.hopper[name] or 0) + got
        avail[name] = math.max(0, (avail[name] or 0) - got)
        sent = sent + got
        -- the next item would get ahead of the first in the hopper
        if got < n and slot == 1 then break end
      end
    end
  end
  files.write(COUNTS_FILE, counts)

  -- how each pot is doing, for the screen
  local now, cooking, stuck = os.clock(), 0, 0
  for _, p in ipairs(pots) do
    local r = p.recipe
    local made = p.count.made
    if not r then
      p.state, p.colour = p.problem, "red"
    elseif not p.feedOk then
      p.state, p.colour = "feed hopper " .. p.entry.feed .. " not on the network", "red"
    elseif not p.outOk then
      p.state, p.colour = "output hopper " .. p.entry.out .. " not on the network", "red"
    elseif shouldCook(p) then
      local s = stuckSince[p.entry.feed]
      if not s or s.made ~= made then s = { at = now, made = made } end
      stuckSince[p.entry.feed] = s
      if now - s.at > STUCK_AFTER and not blocked then
        p.state, p.colour = "not cooking!", "red"
        stuck = stuck + 1
      else
        p.state, p.colour = "cooking", "lime"
        cooking = cooking + 1
      end
    else
      stuckSince[p.entry.feed] = nil
      local short
      for _, name in ipairs(r.items) do
        if (avail[name] or 0) == 0 and (p.hopper[name] or 0) == 0 then short = short or name end
      end
      if short then
        p.state, p.colour = "needs " .. nice(short), "orange"
      elseif r.same then
        local need = (r.same - 1) * SLOT_MAX + 1
        p.state, p.colour = ("filling %d/%d"):format(math.max(0, loaded(p, r.items[1])), need), "lightBlue"
      else
        p.state, p.colour = "filling", "lightBlue"
      end
    end
  end

  if oldReplies then
    say("The storage computer only loads furnaces: 'install update' on it.", "red")
  elseif problem then
    say("Couldn't move items: " .. problem, "red")
  elseif blocked then
    say("The storage input chest is full: cooked items are waiting in the output hoppers.", "orange")
  elseif stuck > 0 then
    say("A pot isn't cooking. Power it with redstone, or empty it and 'cooker reset'.", "red")
  elseif sent > 0 then
    say(("Sent %d items to the pots."):format(sent))
  elseif cooking == 0 then
    say("Nothing to cook.")
  else
    say(("Cooking in %d pots."):format(cooking))
  end
  status(stuck > 0 and "stuck" or cooking > 0 and "running" or "idle",
    ("%d of %d pots cooking"):format(cooking, #pots))
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
  put(2, 1, "Cooking pots", "yellow", "gray")
  put(2, 3, "#", "yellow")
  put(5, 3, "Makes", "yellow")
  put(21, 3, "Made", "yellow")
  put(29, 3, "Doing", "yellow")
  local rows = h - 6
  for i = 1, math.min(rows, #pots) do
    local p, y = pots[i], 3 + i
    put(2, y, tostring(p.n), "lightGray")
    put(5, y, fitText(p.recipe and nice(p.recipe.make) or tostring(p.entry.recipe), 15), "white")
    put(21, y, fitText(tostring(p.count and p.count.made or 0), 7), "white")
    put(29, y, fitText(p.state or "...", w - 29), p.colour or "gray")
  end
  if #pots > rows then put(2, h - 2, ("...and %d more"):format(#pots - rows), "gray") end
  if #pots == 0 then put(2, 4, "No pots yet.", "gray") end
  put(1, h - 1, fitText(message[1], w), message[2])
  put(1, h, fitText("cooker add / remove / reset in another tab", w), "gray")
  display:show()
end

local function uiLoop()
  while true do
    draw()
    os.pullEvent("cooker_changed")
  end
end

local function workLoop()
  while true do
    round()
    os.queueEvent("cooker_changed")
    -- a pot added from another tab starts straight away
    local timer = os.startTimer(EVERY)
    repeat
      local event, value = os.pullEvent()
    until (event == "timer" and value == timer) or event == "cooker_added"
  end
end

---------------------------------------------------------------- commands

local function recipeKeys()
  local keys = {}
  for key in pairs(RECIPES) do
    if recipeOf(key) then keys[#keys + 1] = key end
  end
  table.sort(keys)
  return keys
end

-- Pick from a numbered list (or type a name); nil if cancelled.
local function choose(question, options, show)
  for i, o in ipairs(options) do print(("%2d  %s"):format(i, show and show(o) or o)) end
  write(question .. " ")
  local text = read()
  if text == "" then return nil end
  return options[tonumber(text)] or text
end

local function printPots(list)
  if #list == 0 then print("No pots yet. Add one with 'cooker add'.") end
  for i, entry in ipairs(list) do
    print(("%d  %s: feed %s, output %s"):format(i, entry.recipe, entry.feed, entry.out))
  end
end

local function addPot(args)
  local list = readPots()
  local used = {}
  for _, entry in ipairs(list) do used[entry.feed], used[entry.out] = true, true end
  local free = {}
  for _, name in ipairs(findHoppers()) do
    if not used[name] then free[#free + 1] = name end
  end

  local key = args[2]
  if not key then
    print("What should the pot make?")
    key = choose("Which? (Enter to cancel)", recipeKeys(), function(k)
      local r = recipeOf(k)
      return ("%-14s from %s"):format(k, recipeText(r))
    end)
    if not key then return end
  end
  local r, why = recipeOf(key)
  if not r then print(why) return end

  local feed, out = args[3], args[4]
  if not feed or not out then
    if #free < 2 then
      print("I need two hoppers on the network for each pot. Put a wired modem on each, join it to the cable and right-click it.")
      return
    end
    print("Right-click a hopper's modem to see its name.")
  end
  if not feed then
    print("The FEED hopper, pointing into the pot's side:")
    feed = choose("Which? (Enter to cancel)", free)
    if not feed then return end
  end
  if not out then
    local rest = {}
    for _, name in ipairs(free) do
      if name ~= feed then rest[#rest + 1] = name end
    end
    print("The OUTPUT hopper, under the pot:")
    out = choose("Which? (Enter to cancel)", rest)
    if not out then return end
  end
  if feed == out then print("The feed and output hoppers must be different.") return end
  if used[feed] or used[out] then print("That hopper is already one of another pot's.") return end
  for _, name in ipairs({ feed, out }) do
    if not peripheral.isPresent(name) then print(name .. " isn't on the network.") return end
  end

  list[#list + 1] = { recipe = key, feed = feed, out = out, since = os.epoch("utc") }
  writePots(list)
  os.queueEvent("cooker_added")
  print(("Pot %d makes %s from %s."):format(#list, nice(r.make), recipeText(r)))
  if r.same then
    print(("It starts cooking once it holds %d, and keeps up to %d in it."):format((r.same - 1) * SLOT_MAX + 1,
      r.same * SLOT_MAX))
  end
  print("Keep the pot powered with redstone (lid shut), but not the hoppers.")
end

local function potNumber(args, list)
  local n = tonumber(args[2])
  if not n or not list[n] then
    printPots(list)
    print(("Usage: cooker %s <pot number>"):format(args[1]))
    return nil
  end
  return n
end

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "add" then
  addPot(args)
  return
elseif args[1] == "remove" then
  local list = readPots()
  local n = potNumber(args, list)
  if n then
    local entry = table.remove(list, n)
    writePots(list)
    print(("Forgot pot %d (%s). Empty it and its hoppers by hand."):format(n, entry.recipe))
  end
  return
elseif args[1] == "reset" then
  local list = readPots()
  local n = potNumber(args, list)
  if n then
    list[n].since = os.epoch("utc")
    writePots(list)
    print(("Pot %d starts counting again: it should be empty now (its feed hopper may still hold items)."):format(n))
  end
  return
elseif args[1] then
  print("Usage: cooker [add | remove <n> | reset <n>]")
  return
end

if not net.open("any") then
  print("I need a wired modem on the storage computer's network.")
  print("Put one on me, join it to the network with cable and right-click it so it turns red.")
  return
end

term.clear()
if errlog then errlog.init("cooker") end
if report then report.init("cooker") end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, uiLoop, workLoop,
  report and report.loop or function() while true do sleep(3600) end end)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
