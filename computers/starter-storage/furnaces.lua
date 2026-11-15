-- The stash's furnaces (stash.lua loads it): every furnace, blast furnace
-- and smoker on the wired network, kept busy from storage the way the
-- factory's smelter does it. Raw metals and ores go in by themselves (blast
-- furnaces first), raw food into the smokers; with config.charcoal set,
-- logs are burnt into charcoal whenever there's less than that much fuel
-- (with no coal at all, planks and other starter fuels get it going).
-- Everything else is smelted on request: stone, glass, smooth stone,
-- bricks... or any stored item (F1 on the item list). What's smelted goes
-- straight back into storage (coal and charcoal into the fuel chest first).
--
--   local furnaces = require("furnaces").new(stores, setup, config)
--   furnaces.discover()            find the furnaces on the cable again
--   furnaces.round()               empty, load and fuel every furnace once
--   furnaces.order(title, from, n) smelt n of the first of from (item keys) there is
--   furnaces.cancel(i)             drop order i
--   furnaces.list(), .orders(), .recipes(), .fuelText()   for the screens
local files = require("lib.files")

local ORDERS_FILE = "/.stash_smelt" -- the smelting orders, so they carry on after a reboot
local LOAD_MIN = 8 -- fewest items put into an empty furnace at once (what one coal smelts)
local LOAD_MAX = 64 -- most items put into a furnace at once
local LOGS_KEPT = 16 -- logs of each kind never burnt into charcoal by themselves (for planks)
local STUCK_AFTER = 120 -- seconds a fuelled furnace may sit on an item without smelting it before it's taken out
-- Fuel, in the order it's used, and how many items one smelts. Logs are never
-- burnt: they're for charcoal.
local FUELS = { { "minecraft:charcoal", 8 }, { "minecraft:coal", 8 }, { "minecraft:coal_block", 80 } }
-- Used only while there's none of FUELS, so a new world with no coal can get
-- its first charcoal going; planks (any "*_planks") last.
local STARTER = { { "minecraft:dried_kelp_block", 20 }, { "minecraft:blaze_rod", 12 } }
local PLANKS = "_planks$" -- matched on the item id
local PLANK_SMELTS = 1.5 -- items one plank smelts

-- What can be ordered: make from the first of from there is. kind "ore"
-- may go in blast furnaces, "food" in smokers; the rest only in furnaces.
local LOGS = { "minecraft:oak_log", "minecraft:spruce_log", "minecraft:birch_log", "minecraft:jungle_log",
  "minecraft:acacia_log", "minecraft:dark_oak_log", "minecraft:mangrove_log", "minecraft:cherry_log",
  "minecraft:pale_oak_log" }
local RECIPES = {
  { title = "Stone", from = { "minecraft:cobblestone" } },
  { title = "Glass", from = { "minecraft:sand", "minecraft:red_sand" } },
  { title = "Charcoal", from = LOGS },
  { title = "Smooth stone", from = { "minecraft:stone" } },
  { title = "Deepslate", from = { "minecraft:cobbled_deepslate" } },
  { title = "Brick", from = { "minecraft:clay_ball" } },
  { title = "Terracotta", from = { "minecraft:clay" } },
  { title = "Nether brick", from = { "minecraft:netherrack" } },
  { title = "Cracked stone bricks", from = { "minecraft:stone_bricks" } },
  { title = "Smooth sandstone", from = { "minecraft:sandstone" } },
  { title = "Smooth quartz", from = { "minecraft:quartz_block" } },
  { title = "Green dye", from = { "minecraft:cactus" } },
  { title = "Sponge", from = { "minecraft:wet_sponge" } },
  { title = "Dried kelp", from = { "minecraft:kelp" }, kind = "food" },
}
-- Smelted by themselves (Lua patterns on the item id), unless SKIP matches.
local ORES = { ":raw_", "_ore$", ":ancient_debris$", ":crushed_raw_", ":dust_iron$", ":dust_gold$", ":dust_copper$" }
local SKIP = { "_block$", "coal_ore$", "diamond_ore$", "emerald_ore$", "lapis_ore$", "redstone_ore$", "quartz_ore$" }
local FOOD = { "^minecraft:beef$", "^minecraft:porkchop$", "^minecraft:chicken$", "^minecraft:mutton$",
  "^minecraft:rabbit$", "^minecraft:cod$", "^minecraft:salmon$", "^minecraft:potato$" }
-- Kept in storage, never smelted by themselves (potatoes to plant).
local KEEP = { ["minecraft:potato"] = 16 }

local function any(name, patterns)
  for _, p in ipairs(patterns) do
    if name:find(p) then return true end
  end
  return false
end

local M = {}

function M.new(stores, setup, config)
  config = config or {}
  local ores, skip, food = config.ores or ORES, config.skip or SKIP, config.food or FOOD
  local keep = config.keep or KEEP
  local recipes = {}
  for _, list in ipairs({ RECIPES, config.recipes or {} }) do
    for _, r in ipairs(list) do recipes[#recipes + 1] = r end
  end
  local smelts = {}
  for _, list in ipairs({ FUELS, STARTER }) do
    for _, f in ipairs(list) do smelts[f[1]] = f[2] end
  end
  local function smeltsOf(name)
    return smelts[name] or (name:find(PLANKS) and PLANK_SMELTS) or 8
  end

  local F = {}
  local furnaces = {} -- { name, kind = "furnace"/"blast"/"smoker", input, fuel, output, seen, since }
  local orders = files.read(ORDERS_FILE) or {} -- { title, from = { keys }, n, loaded }
  local noSmelt = {} -- "<kind>:<item>" found not to smelt there (until restart)
  F.message = nil -- the last thing worth saying ("Out of fuel")

  local function save() files.write(ORDERS_FILE, orders) end

  function F.discover()
    local old, list = {}, {}
    for _, fu in ipairs(furnaces) do old[fu.name] = fu end
    for _, name in ipairs(peripheral.getNames()) do
      if require("stores").kindOf(name) == "furnace" then
        local t = peripheral.getType(name)
        list[#list + 1] = old[name] or { name = name,
          kind = t:find("blast", 1, true) and "blast" or t:find("smoker", 1, true) and "smoker" or "furnace" }
      end
    end
    table.sort(list, function(a, b)
      if (a.kind == "furnace") ~= (b.kind == "furnace") then return a.kind ~= "furnace" end -- the fast ones first
      return a.name < b.name
    end)
    furnaces = list
  end

  -- "ore", "food" or "plain": where an item may smelt.
  local function kindOf(name)
    if any(name, ores) and not any(name, skip) then return "ore" end
    if any(name, food) then return "food" end
    return "plain"
  end
  local function fits(fu, key, kind)
    if noSmelt[fu.kind .. ":" .. key] then return false end
    if fu.kind == "blast" then return kind == "ore" end
    if fu.kind == "smoker" then return kind == "food" end
    return true
  end

  -- Coal and charcoal stored, in smelts (what decides making charcoal).
  local function coalStored()
    local n = 0
    for _, f in ipairs(FUELS) do n = n + stores.count(f[1]) * f[2] end
    return n
  end
  -- The fuels to use now: FUELS, else the starter fuels and planks there are.
  local function fuels()
    if coalStored() > 0 then return FUELS end
    local list = {}
    for _, f in ipairs(STARTER) do
      if stores.count(f[1]) > 0 then list[#list + 1] = f end
    end
    for _, it in ipairs(stores.items()) do
      if not it.nbt and it.name:find(PLANKS) then list[#list + 1] = { it.key, PLANK_SMELTS } end
    end
    return list
  end
  -- Every fuel there is to use now, in smelts.
  local function fuelStored()
    local n = 0
    for _, f in ipairs(fuels()) do n = n + stores.count(f[1]) * f[2] end
    return n
  end

  -- What to smelt now, in turn: orders first, then ores, food and charcoal.
  local function jobs()
    local list = {}
    for i, o in ipairs(orders) do
      for _, key in ipairs(o.from) do
        if stores.count(key) > 0 then
          local r
          for _, rec in ipairs(recipes) do
            if rec.title == o.title then r = rec end
          end
          list[#list + 1] = { key = key, left = o.n - o.loaded, order = i, kind = r and r.kind or kindOf(key) }
          break
        end
      end
    end
    for _, it in ipairs(stores.items()) do
      if not it.nbt then
        local k = kindOf(it.name)
        local auto = k == "ore" or (k == "food" and config.cook ~= false)
        if auto then list[#list + 1] = { key = it.key, left = it.count - (keep[it.name] or 0), kind = k } end
      end
    end
    local charcoal = config.charcoal or 32
    if charcoal > 0 and coalStored() < charcoal * 8 then
      for _, log in ipairs(LOGS) do
        local spare = math.min(64, stores.count(log) - (keep[log] or LOGS_KEPT))
        if spare > 0 then list[#list + 1] = { key = log, left = spare, kind = "plain" } end
      end
    end
    return list
  end

  -- Reads every furnace at once.
  local function readAll()
    local fns = {}
    for _, fu in ipairs(furnaces) do
      fns[#fns + 1] = function()
        local ok, list = pcall(peripheral.call, fu.name, "list")
        list = ok and type(list) == "table" and list or {}
        fu.input, fu.fuel, fu.output, fu.ok = list[1], list[2], list[3], ok
      end
    end
    for i = 1, #fns, 100 do parallel.waitForAll(table.unpack(fns, i, math.min(#fns, i + 99))) end
  end

  local function fuelIn(fu)
    if not fu.fuel then return 0 end
    return fu.fuel.count * smeltsOf(fu.fuel.name)
  end

  -- Fuel for what's in the furnace: more of what's in its fuel slot, else
  -- the first fuel there is (the fuel chest first).
  local function addFuel(fu)
    local need = (fu.input and fu.input.count or 0) - fuelIn(fu)
    if need <= 0 then return end
    for _, f in ipairs(fuels()) do
      local name, per = f[1], f[2]
      if (not fu.fuel or fu.fuel.name == name:match("^[^#]+")) and stores.count(name) > 0 then
        local n = math.min(64 - (fu.fuel and fu.fuel.count or 0), math.ceil(need / per))
        local sent = n > 0 and stores.fetch(name, n, fu.name, 2, { fuelFirst = true }) or 0
        if sent > 0 then
          fu.fuel = { name = name:match("^[^#]+"), count = (fu.fuel and fu.fuel.count or 0) + sent }
          return
        end
      end
    end
    if not fu.fuel then F.message = "Out of fuel: put coal, charcoal or planks in." end
  end

  function F.round()
    F.message = nil
    readAll()
    local now = os.clock()
    -- results back into storage, and anything stuck taken back out
    for _, fu in ipairs(furnaces) do
      if fu.output then
        local left = stores.putAway(fu.name, 3, fu.output, fu.output.count)
        if left > 0 then F.message = "Storage is full: smelted items are waiting in the furnaces." end
      end
      local inp = fu.input
      if inp and fu.seen == inp.count and fu.seenName == inp.name then
        if fu.fuel and now - (fu.since or now) > STUCK_AFTER then
          noSmelt[fu.kind .. ":" .. stores.keyOf(inp)] = true
          if stores.putAway(fu.name, 1, inp, inp.count) == 0 then fu.input = nil end
          F.message = ("%s won't smelt in %s: took it back out."):format(stores.shortName(inp.name), fu.name)
        end
      else
        fu.seen, fu.seenName, fu.since = inp and inp.count, inp and inp.name, now
      end
    end

    -- empty furnaces get the first job they can do, shared out
    local list = jobs()
    local empty = 0
    for _, fu in ipairs(furnaces) do
      if fu.ok and not fu.input then empty = empty + 1 end
    end
    local taken = {}
    for _, fu in ipairs(furnaces) do
      if fu.ok and not fu.input and fuelStored() + fuelIn(fu) > 0 then
        for _, j in ipairs(list) do
          local avail = math.min(j.left, stores.count(j.key)) - (taken[j.key] or 0)
          if avail > 0 and fits(fu, j.key, j.kind) then
            local n = math.min(LOAD_MAX, avail, math.max(LOAD_MIN, math.ceil(avail / math.max(1, empty))))
            local sent = stores.fetch(j.key, n, fu.name, 1, { noFuel = true })
            if sent > 0 then
              taken[j.key] = (taken[j.key] or 0) + sent
              j.left = j.left - sent
              fu.input = { name = j.key:match("^[^#]+"), count = sent }
              fu.seen, fu.seenName, fu.since = sent, fu.input.name, now
              if j.order then
                local o = orders[j.order]
                o.loaded = o.loaded + sent
              end
              break
            end
          end
        end
        empty = empty - 1
      end
      if fu.input then addFuel(fu) end
    end

    -- orders that are all loaded, or have nothing left to smelt, are done
    local kept = {}
    for _, o in ipairs(orders) do
      local stocked = false
      for _, key in ipairs(o.from) do
        if stores.count(key) > 0 then stocked = true end
      end
      if o.loaded < o.n and stocked then
        kept[#kept + 1] = o
      else
        F.message = o.loaded < o.n and ("%s: ran out after %d."):format(o.title, o.loaded) or ("%s: all %d in the furnaces."):format(o.title, o.n)
      end
    end
    if #kept ~= #orders then orders = kept end
    save()
    stores.refresh()
  end

  function F.order(title, from, n)
    orders[#orders + 1] = { title = title, from = from, n = n, loaded = 0 }
    save()
  end

  function F.cancel(i)
    table.remove(orders, i)
    save()
  end

  function F.list() return furnaces end
  function F.orders() return orders end

  -- The recipes with something to smelt: { title, from, have }.
  function F.recipes()
    local out = {}
    for _, r in ipairs(recipes) do
      local have = 0
      for _, key in ipairs(r.from) do have = have + stores.count(key) end
      if have > 0 then out[#out + 1] = { title = r.title, from = r.from, have = have } end
    end
    return out
  end

  function F.fuelText()
    local n = fuelStored()
    return n > 0 and ("fuel for %d"):format(n) or "no fuel"
  end

  function F.busy()
    local n = 0
    for _, fu in ipairs(furnaces) do
      if fu.input then n = n + 1 end
    end
    return n, #furnaces
  end

  return F
end

return M
