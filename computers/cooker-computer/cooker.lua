-- Cooking pots for the storage system. Runs Cobblemon campfire pots on the
-- storage computer's wired network: makes exp candy XS from sculk and
-- honeycomb, and compresses it up the chain (6 XS -> S, 3 S -> M, 3 M -> L,
-- 3 L -> XL), or any other pot recipe set in config.lua. One pot per recipe.
--
--   cooker                                  start (startup.lua runs this)
--   cooker add [recipe feed output relay]   add a pot (asks for anything not given)
--   cooker relay <n> [relay]                give pot n its redstone relay
--   cooker remove <n>                       forget pot n (no number: list them)
--
-- CC can't reach into a pot, so every pot has, on the network: a feed hopper
-- pointing into its side, which the storage computer fills; an output hopper
-- under it, which this program empties into the storage computer's input
-- chest; and a comparator reading the pot into a redstone relay, which says
-- how full it is. Redstone power keeps the pot's lid shut, and it only cooks
-- with the lid shut.
--
-- A hopper puts each item in the pot's first slot that's empty or holds the
-- same item, so the pot's slots can't be picked, and a pot that gets an item
-- too many starts another slot and jams. So each round the cooker reads how
-- full the pot is (the comparator's 0-15, from which it works out the most
-- it could hold), adds what's still in the feed hopper, and sends no more
-- than the rest of what the pot can take:
--   * different items (sculk + honeycomb): one slot each, so at most a
--     stack between them in the pot, sent in whole sets with the first item
--     always ahead of the others in the feed hopper, so the first pot slot
--     is never empty while a later one isn't (the next item would land there
--     and jam the pot);
--   * one item n times (6 XS candy): slots fill one after the other, so the
--     pot cooks once n - 1 slots are full, and holds at most n stacks.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local config = fs.exists("config.lua") and require("config") or {}

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local POTS_FILE = "/.cooker_pots" -- the pots: { recipe, feed, out, relay }, changed by 'cooker add' etc.
local OLD_COUNTS_FILE = "/.cooker_counts" -- what older versions counted per pot; no longer needed
local EVERY = 10 -- seconds between rounds of emptying and filling the pots
local REPLY_WAIT = 30 -- seconds to wait for the storage computer to answer (a busy one answers late)
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local HOPPER_SLOTS = 5 -- slots in a hopper
local POT_SLOTS = 13 -- slots in a pot (result, 9 grid, 3 seasoning): the comparator reads how full all of them are
local STACK = 64 -- items to a stack, for items the feed hopper hasn't shown yet
local STUCK_AFTER = 120 -- seconds a pot that should be cooking may make nothing before the screen says so
local COOKING_FOR = 30 -- seconds a pot counts as cooking after something last came out of it
local SIDES = { "top", "bottom", "left", "right", "front", "back" } -- a relay's sides, to find the comparator

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
local made = {} -- feed hopper -> how many it has made since the cooker started
local madeAt = {} -- feed hopper -> os.clock() when something last came out of it
local stackOf = {} -- item -> items to a stack, from the feed hoppers

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
-- items = { name, ... }, same = n (one item n times) }, or nil and what's
-- wrong with it.
local function recipeOf(key)
  local r = RECIPES[key]
  if type(r) ~= "table" or type(r.make) ~= "string" or type(r[1]) ~= "string" then
    return nil, ("no recipe called %s in config.lua"):format(tostring(key))
  end
  local out = { key = key, make = r.make }
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
  os.queueEvent("cooker_added") -- the running cooker, if this is another tab
end

-- Peripherals of a kind on the wired network (not ones touching this
-- computer: the storage computer can't reach those).
local function findOnNetwork(kind)
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if not sides[name] and t and t:find(kind, 1, true) then list[#list + 1] = name end
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

---------------------------------------------------------------- reading a pot

-- The comparator's reading (0-15) through the relay: the strongest signal
-- on any of its sides. nil if the relay can't be read.
local function relayLevel(name)
  local most = 0
  for _, side in ipairs(SIDES) do
    local ok, level = pcall(peripheral.call, name, "getAnalogInput", side)
    if not ok or type(level) ~= "number" then return nil end
    most = math.max(most, level)
  end
  return most
end

-- A comparator reads 1 + 14 * (stacks in the pot) / (its 13 slots), rounded
-- down (0 when it's empty). The most and fewest items, of stacks of 'stack',
-- the pot can hold at a reading.
local function mostAt(level, stack)
  if level <= 0 then return 0 end
  return math.ceil(POT_SLOTS * level * stack / 14) - 1
end

local function fewestAt(level, stack)
  if level <= 0 then return 0 end
  return math.max(1, math.ceil(POT_SLOTS * (level - 1) * stack / 14))
end

-- Items to a stack of the recipe's items: the biggest (for the most the pot
-- could hold) and the smallest (for what one slot of it takes).
local function stacks(r)
  local big, small = 0, math.huge
  for _, name in ipairs(r.items) do
    local n = stackOf[name] or STACK
    big, small = math.max(big, n), math.min(small, n)
  end
  return big, small
end

-- How many of each item to send to the feed hopper now: { { name, n, slot } }
-- in the order to send them. The pot and its feed hopper together never
-- hold more than the pot's slots for the recipe can take.
local function plan(p, avail)
  local r, out = p.recipe, {}
  local big, small = stacks(r)
  local inPot = mostAt(p.level, big)
  local inHopper = 0
  for _, name in ipairs(r.items) do inHopper = inHopper + (p.hopper[name] or 0) end
  local allHopper = 0
  for _, n in pairs(p.hopper) do allHopper = allHopper + n end
  if r.same then
    local name = r.items[1]
    local n = math.min(r.same * small - inPot - inHopper, avail[name] or 0, SEND_MAX,
      HOPPER_SLOTS * small - allHopper)
    if n > 0 then out[1] = { name, n } end
    return out
  end
  -- whole sets, a slot's worth between them at most (so no item can fill
  -- its slot and start another), into hopper slots in order: the first
  -- item's slot empties first, so it's never behind the others
  local n = math.floor((small - inPot - inHopper) / #r.items)
  for _, name in ipairs(r.items) do
    n = math.min(n, avail[name] or 0, small - (p.hopper[name] or 0), SEND_MAX)
  end
  if n > 0 then
    for i, name in ipairs(r.items) do out[i] = { name, n, i } end
  end
  return out
end

-- True if the pot holds enough that it must be cooking (lid shut, not jammed).
local function shouldCook(p, avail)
  local r = p.recipe
  local big, small = stacks(r)
  local inHopper = 0
  for _, name in ipairs(r.items) do inHopper = inHopper + (p.hopper[name] or 0) end
  if r.same then
    -- a few cooked items waiting in its result slot count in the reading too
    return fewestAt(p.level, big) > (r.same - 1) * small + 8
  end
  -- something in it, nothing on its way, and every item to hand: it's been
  -- sent full sets, so it holds at least one
  if p.level == 0 or inHopper > 0 then return false end
  for _, name in ipairs(r.items) do
    if (avail[name] or 0) == 0 then return false end
  end
  return true
end

---------------------------------------------------------------- a round

local stuckSince = {} -- feed hopper -> { at = os.clock(), made }: should have been cooking since, with nothing more made

local function round()
  local list = readPots()
  local nowPots = {}
  for i, entry in ipairs(list) do
    local r, why = recipeOf(entry.recipe)
    nowPots[i] = { n = i, entry = entry, recipe = r, problem = why, hopper = {} }
  end

  -- each call takes a tick, so read every pot at once: its feed hopper
  -- before its comparator, so an item that moves between the two reads is
  -- counted twice rather than missed
  local reads = {}
  for _, p in ipairs(nowPots) do
    reads[#reads + 1] = function()
      local okF, feed = pcall(peripheral.call, p.entry.feed, "list")
      p.feedOk = okF and type(feed) == "table"
      for slot, item in pairs(p.feedOk and feed or {}) do
        p.hopper[item.name] = (p.hopper[item.name] or 0) + item.count
        if not stackOf[item.name] then
          local okD, d = pcall(peripheral.call, p.entry.feed, "getItemDetail", slot)
          if okD and type(d) == "table" and d.maxCount then stackOf[item.name] = d.maxCount end
        end
      end
      p.level = p.entry.relay and relayLevel(p.entry.relay)
      local okO, out = pcall(peripheral.call, p.entry.out, "list")
      p.outOk = okO and type(out) == "table"
      p.outList = p.outOk and out or {}
    end
  end
  parallel.waitForAll(table.unpack(reads))
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
      if p.recipe and item.name == p.recipe.make and moved > 0 then
        made[p.entry.feed] = (made[p.entry.feed] or 0) + moved
        madeAt[p.entry.feed] = os.clock()
      end
      if moved < item.count then blocked = true end
    end
  end

  -- fill the feed hoppers, pot by pot (two pots making the same thing share
  -- what there is, first one first)
  local sent, oldReplies = 0, false
  for _, p in ipairs(pots) do
    if p.recipe and p.feedOk and p.outOk and p.level then
      local firstGot
      for _, step in ipairs(plan(p, avail)) do
        local name, n, slot = step[1], step[2], step[3]
        -- never more of the others than the first item got
        if firstGot then n = math.min(n, firstGot) end
        local got = 0
        if n > 0 then
          local r = ask({ type = "send", to = p.entry.feed, slot = slot, items = { [name] = n } })
          got = r and type(r.sent) == "table" and r.sent[name] or 0
          if r and r.error then
            problem = r.error
            if r.error:find("isn't a furnace on", 1, true) then oldReplies = true end
          end
          if not r then problem = "the storage computer didn't answer while loading pot " .. p.n end
        end
        p.hopper[name] = (p.hopper[name] or 0) + got
        avail[name] = math.max(0, (avail[name] or 0) - got)
        sent = sent + got
        if slot == 1 then firstGot = got end
      end
    end
  end

  -- how each pot is doing, for the screen
  local now, cooking, stuck = os.clock(), 0, 0
  for _, p in ipairs(pots) do
    local r = p.recipe
    local count = made[p.entry.feed] or 0
    if not r then
      p.state, p.colour = p.problem, "red"
    elseif not p.entry.relay then
      p.state, p.colour = ("no relay: 'cooker relay %d'"):format(p.n), "red"
    elseif not p.level then
      p.state, p.colour = "relay " .. p.entry.relay .. " not on the network", "red"
    elseif not p.feedOk then
      p.state, p.colour = "feed hopper " .. p.entry.feed .. " not on the network", "red"
    elseif not p.outOk then
      p.state, p.colour = "output hopper " .. p.entry.out .. " not on the network", "red"
    elseif shouldCook(p, avail) then
      local s = stuckSince[p.entry.feed]
      if not s or s.made ~= count then s = { at = now, made = count } end
      stuckSince[p.entry.feed] = s
      if now - s.at > STUCK_AFTER and not blocked then
        p.state, p.colour = "not cooking!", "red"
        stuck = stuck + 1
      else
        p.state, p.colour = "cooking", "lime"
        cooking = cooking + 1
      end
    elseif madeAt[p.entry.feed] and now - madeAt[p.entry.feed] < COOKING_FOR then
      -- a busy pot's reading hovers round where it stops being fed, so
      -- what comes out says whether it's cooking
      stuckSince[p.entry.feed] = nil
      p.state, p.colour = "cooking", "lime"
      cooking = cooking + 1
    else
      stuckSince[p.entry.feed] = nil
      local short
      for _, name in ipairs(r.items) do
        if (avail[name] or 0) == 0 and (p.hopper[name] or 0) == 0 then short = short or name end
      end
      if short then
        p.state, p.colour = "needs " .. nice(short), "orange"
      elseif r.same then
        local big, small = stacks(r)
        p.state = ("filling ~%d/%d"):format(fewestAt(p.level, big), (r.same - 1) * small + 1)
        p.colour = "lightBlue"
      else
        p.state, p.colour = "filling", "lightBlue"
      end
    end
  end

  if oldReplies then
    say("Storage too old: 'install update' on it, reboot.", "red")
  elseif problem then
    say("Couldn't move items: " .. problem, "red")
  elseif blocked then
    say("The storage input chest is full: cooked items are waiting in the output hoppers.", "orange")
  elseif stuck > 0 then
    say("A pot isn't cooking: is its lid powered? Or empty it by hand.", "red")
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
    put(21, y, fitText(tostring(made[p.entry.feed] or 0), 7), "white")
    put(29, y, fitText(p.state or "...", w - 29), p.colour or "gray")
  end
  if #pots > rows then put(2, h - 2, ("...and %d more"):format(#pots - rows), "gray") end
  if #pots == 0 then put(2, 4, "No pots yet.", "gray") end
  put(1, h - 1, fitText(message[1], w), message[2])
  put(1, h, fitText("cooker add / relay / remove in another tab", w), "gray")
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
    print(("%d  %s: feed %s, output %s, relay %s"):format(i, entry.recipe, entry.feed, entry.out,
      entry.relay or "none"))
  end
end

local function usedNames(list)
  local used = {}
  for _, entry in ipairs(list) do
    used[entry.feed], used[entry.out] = true, true
    if entry.relay then used[entry.relay] = true end
  end
  return used
end

-- Ask for the pot's relay (or check the one given): its name, or nil.
local function pickRelay(given, used)
  local relay = given
  if not relay then
    local free = {}
    for _, name in ipairs(findOnNetwork("redstone_relay")) do
      if not used[name] then free[#free + 1] = name end
    end
    if #free == 0 then
      print("I need a redstone relay on the network for the pot's comparator. Put a wired modem on it, join it to the cable and right-click it.")
      return nil
    end
    print("The RELAY the pot's comparator points into:")
    relay = choose("Which? (Enter to cancel)", free)
    if not relay then return nil end
  end
  if used[relay] then print("That relay is already another pot's.") return nil end
  if not peripheral.isPresent(relay) then print(relay .. " isn't on the network.") return nil end
  return relay
end

local function addPot(args)
  local list = readPots()
  local used = usedNames(list)
  local free = {}
  for _, name in ipairs(findOnNetwork("hopper")) do
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
    print("Right-click a modem to see its block's name.")
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
  local relay = pickRelay(args[5], used)
  if not relay then return end

  list[#list + 1] = { recipe = key, feed = feed, out = out, relay = relay }
  writePots(list)
  print(("Pot %d makes %s from %s."):format(#list, nice(r.make), recipeText(r)))
  if r.same then
    print(("It starts cooking once it holds %d, and keeps up to %d in it."):format((r.same - 1) * STACK + 1,
      r.same * STACK))
  end
  print("Keep the pot powered with redstone (lid shut), but not the hoppers, comparator or relay.")
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
elseif args[1] == "relay" then
  local list = readPots()
  local n = potNumber(args, list)
  if n then
    local used = usedNames(list)
    used[list[n].relay or ""] = nil -- its own relay may be picked again
    local relay = pickRelay(args[3], used)
    if relay then
      list[n].relay = relay
      writePots(list)
      print(("Pot %d reads its comparator through %s."):format(n, relay))
    end
  end
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
elseif args[1] then
  print("Usage: cooker [add | relay <n> | remove <n>]")
  return
end

if not net.open("any") then
  print("I need a wired modem on the storage computer's network.")
  print("Put one on me, join it to the network with cable and right-click it so it turns red.")
  return
end

files.delete(OLD_COUNTS_FILE)
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
