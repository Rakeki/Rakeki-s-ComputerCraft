-- The factory's cooking pots (factory.lua loads it). Runs Cobblemon
-- campfire pots on the storage computer's wired network: makes exp candy XS
-- from sculk and honeycomb, and compresses it up the chain (6 XS -> S, 3 S
-- -> M, 3 M -> L, 3 L -> XL), or any other pot recipe set in config.lua. One
-- pot per recipe. The monitor's Candy page shows how much candy there is:
-- each size in storage and in the pots, and the exp it's all worth.
--
-- CC can't reach into a pot, so every pot has, on the network: a feed hopper
-- pointing into its side, which the storage computer fills (or, with a work
-- chest, the factory from it: then the storage computer needn't see it); an
-- output hopper under it, emptied into the storage computer's input chest
-- (far away, the ender chest); and a
-- comparator reading the pot into a redstone relay, which says how full it
-- is. Redstone power keeps the pot's lid shut, and it only cooks with the
-- lid shut.
--
-- A hopper puts each item in the pot's first slot that's empty or holds the
-- same item, so the pot's slots can't be picked, and a pot that gets an item
-- too many starts another slot and jams. So each round the pot's fill is
-- read (the comparator's 0-15, from which the most it could hold is worked
-- out), what's still in the feed hopper added, and no more sent than the
-- rest of what the pot can take:
--   * different items (sculk + honeycomb): one slot each, so at most a
--     stack between them in the pot, sent in whole sets with the first item
--     always ahead of the others in the feed hopper, so the first pot slot
--     is never empty while a later one isn't (the next item would land there
--     and jam the pot);
--   * one item n times (6 XS candy): slots fill one after the other, so the
--     pot cooks once n - 1 slots are full, and holds at most n stacks.
--
-- What the pots are made from (sculk, honeycomb) is kept topped up: once a
-- minute the craft overseer is asked ('prepare') to craft each up to a
-- total, if it has a recipe for it, so the pots never run dry.
local screen = require("lib.screen") -- flicker-free drawing
local files = require("lib.files") -- crash-safe save files

local M = {}

local POTS_FILE = "/.cooker_pots" -- the pots: { recipe, feed, out, relay } (the cooker's file, so pots carry on)
local SEND_MAX = 64 -- most of one item the storage computer sends at once
local HOPPER_SLOTS = 5 -- slots in a hopper
local POT_SLOTS = 13 -- slots in a pot (result, 9 grid, 3 seasoning): the comparator reads how full all of them are
local STACK = 64 -- items to a stack, for items the feed hopper hasn't shown yet
local STUCK_AFTER = 120 -- seconds a pot that should be cooking may make nothing before the screen says so
local COOKING_FOR = 30 -- seconds a pot counts as cooking after something last came out of it
local SIDES = { "top", "bottom", "left", "right", "front", "back" } -- a relay's sides, to find the comparator
local CRAFT_EVERY = 60 -- seconds between asking the craft overseer to craft the pots' raw items
local NO_RECIPE_WAIT = 600 -- seconds before asking again for an item the craft overseer has no recipe for
local CRAFT_UPTO = 128 -- how many of each raw item to keep crafted in storage, if config.lua doesn't say

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

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

local function commas(n)
  local text = tostring(math.floor(n))
  local k
  repeat text, k = text:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
  return text
end

-- f: the factory (factory.lua): ask, config, taken, wake.
function M.new(f)
  local config = f.config("cooker")
  -- Used if config.lua has none; see config.lua for what they mean.
  local RECIPES = config.recipes or {
    exp_candy_xs = { make = "cobblemon:exp_candy_xs", "minecraft:sculk", "minecraft:honeycomb" },
    exp_candy_s = { make = "cobblemon:exp_candy_s", "cobblemon:exp_candy_xs", times = 6 },
    exp_candy_m = { make = "cobblemon:exp_candy_m", "cobblemon:exp_candy_s", times = 3 },
    exp_candy_l = { make = "cobblemon:exp_candy_l", "cobblemon:exp_candy_m", times = 3 },
    exp_candy_xl = { make = "cobblemon:exp_candy_xl", "cobblemon:exp_candy_l", times = 3 },
  }
  local KEEP = config.keep or {}
  -- How many of each raw item to keep crafted: a number for all of them, a
  -- table by item, or false for none.
  local CRAFT = config.craft
  if CRAFT == nil then CRAFT = CRAFT_UPTO end
  -- The candy the Candy page lists: item, what to call it, and the exp one
  -- gives (Cobblemon's own amounts; rare candy depends on the Pokemon).
  local CANDY = config.candy or {
    { "cobblemon:exp_candy_xs", "XS", 100 },
    { "cobblemon:exp_candy_s", "S", 800 },
    { "cobblemon:exp_candy_m", "M", 3000 },
    { "cobblemon:exp_candy_l", "L", 10000 },
    { "cobblemon:exp_candy_xl", "XL", 30000 },
    { "cobblemon:rare_candy", "Rare" },
  }

  local self = { id = "cook", title = "Cooking", short = "Cook", every = 10, what = "Cooking pots (exp candy)" }
  local pots = {} -- what the screen shows: each pot with its recipe and how it's doing
  local made = {} -- feed hopper -> how many it has made since the factory started
  local stock = nil -- the storage computer's last counts: item -> how many
  local madeAt = {} -- feed hopper -> os.clock() when something last came out of it
  local stackOf = {} -- item -> items to a stack, from the feed hoppers
  local stuckSince = {} -- feed hopper -> { at = os.clock(), made }: should have been cooking since, with nothing more made
  local craftAt = -math.huge -- when the raw items were last ordered
  local noRecipe = {} -- item -> os.clock() when the craft overseer said it has no recipe for it
  local craftNote = nil -- { text, colour }: what the last order of raw items did, for the screen
  self.message = { "Looking for the storage computer...", "lightGray" }
  self.status = { "starting", "" }

  local function say(text, colour)
    self.message = { text, colour or "lightGray" }
    f.changed()
  end

  local function status(state, detail) self.status = { state, detail } end

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
    f.wake() -- the running factory, if this is another tab
  end

  function self.found() return {} end

  function self.uses()
    local out = {}
    for _, e in ipairs(readPots()) do
      out[#out + 1] = e.feed
      out[#out + 1] = e.out
      if e.relay then out[#out + 1] = e.relay end
    end
    return out
  end

  function self.active() return #readPots() > 0 end
  function self.takes() return {} end

  function self.summary()
    local n = #readPots()
    return n > 0 and ("%d pot%s"):format(n, n == 1 and "" or "s") or ""
  end

  ---------------------------------------------------------------- a pot's load

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

  ---------------------------------------------------------------- raw items

  -- How many of a raw item to keep in storage (on top of what 'keep' holds
  -- back), or 0 for none.
  local function craftTarget(name)
    local n = type(CRAFT) == "table" and CRAFT[name] or type(CRAFT) == "number" and CRAFT or 0
    n = math.floor(tonumber(n) or 0)
    return n > 0 and n + (KEEP[name] or 0) or 0
  end

  -- Have the craft overseer craft the set-up pots' raw items (sculk,
  -- honeycomb) up to their totals. 'prepare' tops up to a total that counts
  -- what's already being made, so asking again never orders twice. An item
  -- it has no recipe for is left alone for a while, then tried again (a
  -- recipe may have been learned since).
  local function craftRaw(counts)
    if not CRAFT or os.clock() - craftAt < CRAFT_EVERY then return end
    craftAt = os.clock()
    local items, any = {}, false
    for _, p in ipairs(pots) do
      if p.recipe and not p.recipe.same then
        for _, name in ipairs(p.recipe.items) do
          local n = craftTarget(name)
          local quiet = noRecipe[name] and os.clock() - noRecipe[name] < NO_RECIPE_WAIT
          if n > (counts[name] or 0) and not quiet then items[name], any = n, true end
        end
      end
    end
    if not any then
      craftNote = nil
      return
    end
    local reply = f.craft({ type = "prepare", items = items })
    if not reply then return end
    local making, cant = {}, {}
    for name in pairs(items) do
      local why = type(reply.cantCraft) == "table" and reply.cantCraft[name]
      local n = type(reply.crafting) == "table" and reply.crafting[name] or 0
      if why == "no recipe for it" then
        noRecipe[name] = os.clock()
      elseif why then
        cant[#cant + 1] = ("%s (%s)"):format(nice(name), why)
      end
      if n > 0 then making[#making + 1] = ("%d %s"):format(n, nice(name)) end
    end
    table.sort(making)
    table.sort(cant)
    if #cant > 0 then
      craftNote = { "Can't craft for the pots: " .. table.concat(cant, ", "), "orange" }
    elseif reply.craftProblem then
      craftNote = { "Crafting for the pots: " .. reply.craftProblem, "orange" }
    elseif #making > 0 then
      craftNote = { "Crafting " .. table.concat(making, " and ") .. " for the pots.", "lightBlue" }
    else
      craftNote = nil
    end
  end

  ---------------------------------------------------------------- a round

  -- Every pot is read before the storage computer is asked, so the screen
  -- shows them even while it isn't answering.
  function self.read()
    local list = readPots()
    local nowPots, before = {}, {}
    for _, p in ipairs(pots) do before[p.entry.feed] = p end
    for i, entry in ipairs(list) do
      local r, why = recipeOf(entry.recipe)
      -- what it was doing stays on screen until this round says otherwise (not "...")
      local old = before[entry.feed]
      nowPots[i] = { n = i, entry = entry, recipe = r, problem = why, hopper = {},
        state = old and old.state, colour = old and old.colour }
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
    if #reads > 0 then parallel.waitForAll(table.unpack(reads)) end
    pots = nowPots
  end

  function self.round(r)
    if #pots == 0 then
      say("No pots yet: add one on the setup screen, or 'factory add pot'.", "orange")
      status("waiting", "no pots")
      return
    end
    stock = r.stock.counts
    -- the cooked candy goes into storage, never near here: the input chest
    -- (far away, the work chest's way home)
    local input, avail = r.input or r.stock.input, {}
    local work = f.work
    for name, n in pairs(stock) do avail[name] = math.max(0, n - (KEEP[name] or 0)) end
    craftRaw(stock)

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
    -- what there is, first one first): with a work chest, what every pot
    -- needs comes in one fill and is moved into the hoppers from there (the
    -- storage computer needn't see the hoppers); else the storage computer
    -- sends to each hopper itself
    local sent, oldReplies = 0, false
    local loads = {} -- with a work chest: { p, steps }, the steps taken as sent until the fill comes
    for _, p in ipairs(pots) do
      if p.recipe and p.feedOk and p.outOk and p.level then
        local firstGot
        local steps = {}
        for _, step in ipairs(plan(p, avail)) do
          local name, n, slot = step[1], step[2], step[3]
          -- never more of the others than the first item got
          if firstGot then n = math.min(n, firstGot) end
          local got = 0
          if n > 0 and r.useWork then
            steps[#steps + 1] = { name, n, slot }
            got = n
          elseif n > 0 then
            local reply = f.ask({ type = "send", to = p.entry.feed, slot = slot, items = { [name] = n } })
            got = reply and type(reply.sent) == "table" and reply.sent[name] or 0
            if reply and reply.error then
              problem = reply.error
              if reply.error:find("isn't a furnace on", 1, true) then oldReplies = true end
            end
            if not reply then problem = "the storage computer didn't answer while loading pot " .. p.n end
          end
          avail[name] = math.max(0, (avail[name] or 0) - got)
          if not r.useWork then
            p.hopper[name] = (p.hopper[name] or 0) + got
            sent = sent + got
          end
          if slot == 1 then firstGot = got end
        end
        if #steps > 0 then loads[#loads + 1] = { p = p, steps = steps } end
      end
    end
    if r.useWork and #loads > 0 then
      local items = {}
      for _, l in ipairs(loads) do
        for _, s in ipairs(l.steps) do items[s[1]] = (items[s[1]] or 0) + s[2] end
      end
      local reply, why = work:fill(items, 0)
      if not reply then
        problem = why
      elseif reply.error and not reply.nochest then
        problem = reply.error
      end
      for _, l in ipairs(loads) do
        local firstGot
        for _, s in ipairs(l.steps) do
          local name, n, slot = s[1], s[2], s[3]
          -- the first item stays ahead of the others, as above
          if firstGot then n = math.min(n, firstGot) end
          local got = n > 0 and work:move(name, l.p.entry.feed, slot, n) or 0
          l.p.hopper[name] = (l.p.hopper[name] or 0) + got
          sent = sent + got
          if slot == 1 then firstGot = got end
        end
      end
      work:empty(input)
    end
    -- far away without a work chest the storage computer can't see the hoppers
    if problem and not work.chest and problem:find("network", 1, true) then
      problem = problem .. ". Not on the storage cable? Setup, Items come and go"
    end

    -- how each pot is doing, for the screen
    local now, cooking, stuck = os.clock(), 0, 0
    for _, p in ipairs(pots) do
      local rc = p.recipe
      local count = made[p.entry.feed] or 0
      if not rc then
        p.state, p.colour = p.problem, "red"
      elseif not p.entry.relay then
        p.state, p.colour = ("no relay: 'factory relay %d'"):format(p.n), "red"
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
        for _, name in ipairs(rc.items) do
          if (avail[name] or 0) == 0 and (p.hopper[name] or 0) == 0 then short = short or name end
        end
        if short then
          p.state, p.colour = "needs " .. nice(short), "orange"
        elseif rc.same then
          local big, small = stacks(rc)
          p.state = ("filling ~%d/%d"):format(fewestAt(p.level, big), (rc.same - 1) * small + 1)
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
    elseif craftNote then
      say(craftNote[1], craftNote[2])
    elseif cooking == 0 then
      say("Nothing to cook.")
    else
      say(("Cooking in %d pots."):format(cooking))
    end
    status(stuck > 0 and "alert" or cooking > 0 and "running" or "idle",
      ("%d of %d pots cooking"):format(cooking, #pots))
  end

  ---------------------------------------------------------------- screen

  function self.key()
    local key = { self.message[1], self.message[2] }
    for _, p in ipairs(pots) do key[#key + 1] = table.concat({ p.n, made[p.entry.feed] or 0, p.state or "" }, "/") end
    return table.concat(key, "|")
  end

  -- The terminal page, under the factory's tab bar (row 1).
  function self.draw(win, w, h)
    local function put(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end
    local fit = screen.fit
    put(2, 3, "#", "yellow")
    put(5, 3, "Makes", "yellow")
    put(21, 3, "Made", "yellow")
    put(29, 3, "Doing", "yellow")
    local msg = screen.wrap(self.message[1], w, 2) -- a second line rather than cut off
    local shown = h - 5 - #msg
    for i = 1, math.min(shown, #pots) do
      local p, y = pots[i], 3 + i
      put(2, y, tostring(p.n), "lightGray")
      put(5, y, fit(p.recipe and nice(p.recipe.make) or tostring(p.entry.recipe), 15), "white")
      put(21, y, fit(tostring(made[p.entry.feed] or 0), 7), "white")
      put(29, y, fit(p.state or "...", w - 29), p.colour or "gray")
    end
    if #pots > shown then put(2, h - 1 - #msg, ("...and %d more"):format(#pots - shown), "gray") end
    if #pots == 0 then put(2, 4, "No pots yet.", "gray") end
    for i, line in ipairs(msg) do put(1, h - 1 - #msg + i, fit(line, w), self.message[2]) end
    put(1, h, fit("Tab: next page  F1 or Setup: the setup screen", w), "gray")
  end

  -- A tile per pot: lime cooking, light blue filling, orange short of
  -- something, red needs you.
  function self.tiles()
    local tiles = {}
    local map = { lime = "yellow", lightBlue = "lime", orange = "orange", red = "red" }
    for _, p in ipairs(pots) do
      tiles[#tiles + 1] = { ("Pot %d"):format(p.n), p.state or "...", map[p.colour] or "lime" }
    end
    return tiles
  end

  function self.event() return false end

  -- What a recipe without "times" is made from (sculk and honeycomb): the
  -- Candy page shows how much is left for making more.
  local function rawItems()
    local seen, list = {}, {}
    for key in pairs(RECIPES) do
      local rc = recipeOf(key)
      if rc and not rc.same then
        for _, name in ipairs(rc.items) do
          if not seen[name] then seen[name], list[#list + 1] = true, name end
        end
      end
    end
    table.sort(list)
    return list
  end

  local function candyRows()
    -- candy in the compressing pots: at least what their comparators read
    local inPots = {}
    for _, p in ipairs(pots) do
      if p.recipe and p.recipe.same and p.level and p.level > 0 then
        local name = p.recipe.items[1]
        inPots[name] = (inPots[name] or 0) + fewestAt(p.level, (stacks(p.recipe)))
      end
    end
    local rows, total = {}, 0
    for _, c in ipairs(CANDY) do
      local n = stock and stock[c[1]] or 0
      total = total + n * (c[3] or 0)
      rows[#rows + 1] = { c[2], stock and commas(n) or "?", inPots[c[1]] and ("~" .. commas(inPots[c[1]])) or "",
        c[3] and stock and commas(n * c[3]) or "-" }
    end
    local raw = {}
    for _, name in ipairs(rawItems()) do
      raw[#raw + 1] = ("%s %s"):format(nice(name), stock and commas(stock[name] or 0) or "?")
    end
    return rows, total, raw
  end

  -- An extra monitor page: the candy there is, and the exp it's worth.
  self.monitorPage = { title = "Candy",
    key = function()
      local rows, total, raw = candyRows()
      local key = { stock and commas(total) or "?", table.concat(raw, " ") }
      for _, row in ipairs(rows) do key[#key + 1] = table.concat(row, "|") end
      return table.concat(key, "/")
    end,
    draw = function(win, w, h)
      local rows, total, raw = candyRows()
      local function at(x, y, text, fg, bg) screen.put(win, x, y, text, fg, bg) end
      local function right(x, y, text, fg) at(x - #text + 1, y, text, fg) end
      local expR = w - 1
      local potsR = expR - 11
      local storedR = potsR - 8
      at(2, 3, "Candy", "yellow")
      right(storedR, 3, "Stored", "yellow")
      right(potsR, 3, "In pots", "yellow")
      right(expR, 3, "Exp", "yellow")
      for i, row in ipairs(rows) do
        local y = 3 + i
        if y < h - 2 then
          at(2, y, row[1], "white")
          right(storedR, y, row[2], "white")
          right(potsR, y, row[3], "lightBlue")
          right(expR, y, row[4], "lightGray")
        end
      end
      local y = math.min(3 + #rows + 2, h - 2)
      at(2, y, "Exp stored", "white")
      right(expR, y, stock and commas(total) or "?", "lime")
      if #raw > 0 and y + 1 < h then at(2, y + 1, screen.fit("For more: " .. table.concat(raw, ", "), w - 2), "lightGray") end
    end }

  ---------------------------------------------------------------- adding pots

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
        if not used[name] and not f.taken(name) then free[#free + 1] = name end
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

  -- 'factory add pot [recipe feed output relay]': asks for what's not given.
  function self.addCommand(recipe, feed, out, relay)
    local list = readPots()
    local used = usedNames(list)
    local free = {}
    for _, name in ipairs(findOnNetwork("hopper")) do
      if not used[name] and not f.taken(name) then free[#free + 1] = name end
    end
    local key = recipe
    if not key then
      print("What should the pot make?")
      key = choose("Which? (Enter to cancel)", recipeKeys(), function(k)
        return ("%-14s from %s"):format(k, recipeText(recipeOf(k)))
      end)
      if not key then return end
    end
    local rc, why = recipeOf(key)
    if not rc then print(why) return end
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
    relay = pickRelay(relay, used)
    if not relay then return end
    list[#list + 1] = { recipe = key, feed = feed, out = out, relay = relay }
    writePots(list)
    print(("Pot %d makes %s from %s."):format(#list, nice(rc.make), recipeText(rc)))
    if rc.same then
      print(("It starts cooking once it holds %d, and keeps up to %d in it."):format((rc.same - 1) * STACK + 1,
        rc.same * STACK))
    end
    print("Keep the pot powered with redstone (lid shut), but not the hoppers, comparator or relay.")
  end

  -- Every pot, for 'factory list' and 'factory remove': { text, remove() }.
  function self.listed()
    local out = {}
    for i, e in ipairs(readPots()) do
      out[#out + 1] = { text = ("Pot %d: %s, feed %s, output %s, relay %s"):format(i, e.recipe, e.feed, e.out,
        e.relay or "none"), remove = function()
        local list = readPots()
        table.remove(list, i)
        writePots(list)
        return ("Forgot pot %d (%s). Empty it and its hoppers by hand."):format(i, e.recipe)
      end }
    end
    return out
  end

  -- 'factory relay <n> [relay]': give pot n its redstone relay.
  function self.command(args)
    if args[1] ~= "relay" then return false end
    local list = readPots()
    local n = tonumber(args[2])
    if not n or not list[n] then
      for _, row in ipairs(self.listed()) do print(row.text) end
      print("Usage: factory relay <pot number> [relay]")
      return true
    end
    local used = usedNames(list)
    used[list[n].relay or ""] = nil -- its own relay may be picked again
    local relay = pickRelay(args[3], used)
    if relay then
      list[n].relay = relay
      writePots(list)
      print(("Pot %d reads its comparator through %s."):format(n, relay))
    end
    return true
  end

  ---------------------------------------------------------------- setup screen

  -- The pots on the factory's Machines page (lib/setupui.lua): a row per pot
  -- to change it, and + Add a cooking pot. Each change is saved as it's made.
  function self.setupParts(ui)
    -- which pot uses each hopper and relay (skip: this pot)
    local function usedBy(skip)
      local u = {}
      for i, e in ipairs(readPots()) do
        if i ~= skip then
          u[e.feed], u[e.out] = i, i
          if e.relay then u[e.relay] = i end
        end
      end
      return u
    end
    local function pickRecipe(current, done)
      ui:open({ title = "What the pot makes", hint = "The recipes are in config.lua.",
        rows = function()
          local out = {}
          for _, key in ipairs(recipeKeys()) do
            local rc = recipeOf(key)
            out[#out + 1] = { label = key, value = ("from %s"):format(recipeText(rc)),
              colour = key == current and "yellow" or "lightGray", act = function()
                ui:back()
                done(key)
              end }
          end
          if #out == 0 then out[1] = { label = "No recipes in config.lua.", dim = true } end
          return out
        end })
    end
    local function pickHopper(title, hint, skip, current, other, done)
      local u = usedBy(skip)
      ui:pickChest({ title = title, hint = hint, names = findOnNetwork("hopper"), current = current,
        nothing = "No hoppers here: put a wired modem on each and right-click it.",
        roleOf = function(n)
          return u[n] and ("pot %d's"):format(u[n]) or n == other and "its other hopper"
            or f.taken(n) and "in use" or nil
        end,
        pick = function(n)
          if u[n] or n == other or f.taken(n) then ui:say(("%s is taken."):format(n), "orange") return end
          ui:back()
          done(n)
        end })
    end
    local function chooseRelay(skip, current, done)
      local u = usedBy(skip)
      ui:open({ title = "Its redstone relay", hint = "The relay the pot's comparator points into.",
        rows = function()
          local out = {}
          for _, n in ipairs(findOnNetwork("redstone_relay")) do
            local taken = u[n] and ("pot %d's"):format(u[n]) or f.taken(n) and "in use"
            out[#out + 1] = { label = n, value = n == current and "now" or taken or "",
              colour = n == current and "yellow" or taken and "gray" or "lightGray", act = function()
                if taken then ui:say(("%s is %s."):format(n, taken), "orange") return end
                ui:back()
                done(n)
              end }
          end
          if #out == 0 then
            out[1] = { label = "No redstone relay here: put a wired modem on one and right-click it.", dim = true }
          end
          return out
        end })
    end
    local function change(i, field, value, text)
      local list = readPots()
      if not list[i] then return end
      list[i][field] = value
      writePots(list)
      ui:say(text, "lime")
    end

    local function potPage(i)
      return {
        title = function()
          local e = readPots()[i]
          local rc = e and recipeOf(e.recipe)
          return ("Pot %d%s"):format(i, rc and (": " .. nice(rc.make)) or "")
        end,
        rows = function()
          local e = readPots()[i]
          if not e then return { { label = "Removed.", dim = true } } end
          local function there(n) return n and peripheral.isPresent(n) and "lightGray" or "red" end
          return {
            { label = "Makes", value = e.recipe, colour = recipeOf(e.recipe) and "lightGray" or "red", act = function()
              pickRecipe(e.recipe, function(k) change(i, "recipe", k, ("Pot %d makes %s now."):format(i, k)) end)
            end },
            { label = "Feed hopper", value = e.feed, colour = there(e.feed), act = function()
              pickHopper("Pick its feed hopper", "Pointing into the pot's side.", i, e.feed, e.out,
                function(n) change(i, "feed", n, ("Feed hopper: %s."):format(n)) end)
            end },
            { label = "Output hopper", value = e.out, colour = there(e.out), act = function()
              pickHopper("Pick its output hopper", "Under the pot.", i, e.out, e.feed,
                function(n) change(i, "out", n, ("Output hopper: %s."):format(n)) end)
            end },
            { label = "Relay", value = e.relay or "none", colour = there(e.relay), act = function()
              chooseRelay(i, e.relay, function(n) change(i, "relay", n, ("Relay: %s."):format(n)) end)
            end },
            { label = "Remove it", colour = "red", act = function()
              local list = readPots()
              table.remove(list, i)
              writePots(list)
              ui:back()
              ui:say(("Forgot pot %d. Empty it and its hoppers by hand."):format(i), "lime")
            end },
          }
        end,
      }
    end

    local function add()
      pickRecipe(nil, function(key)
        pickHopper("Pick its feed hopper", "Pointing into the pot's side.", nil, nil, nil, function(feed)
          pickHopper("Pick its output hopper", "Under the pot.", nil, nil, feed, function(out)
            chooseRelay(nil, nil, function(relay)
              local list = readPots()
              list[#list + 1] = { recipe = key, feed = feed, out = out, relay = relay }
              writePots(list)
              ui:say(("Pot %d added. Keep the pot powered (lid shut), but not its hoppers, comparator or relay.")
                :format(#list), "lime")
            end)
          end)
        end)
      end)
      ui:say("Tap what the pot makes.")
    end

    local parts = {}
    function parts.entries()
      local out = {}
      for i, e in ipairs(readPots()) do
        out[#out + 1] = { label = ("Pot %d"):format(i), value = ("%s, feed %s"):format(e.recipe, e.feed),
          act = function() ui:open(potPage(i)) end }
      end
      return out
    end
    function parts.adds()
      return { { label = "+ Add a cooking pot", colour = "lime", act = add } }
    end
    parts.add = add
    return parts
  end

  return self
end

return M
