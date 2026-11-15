-- The stash's storage (stash.lua loads it): every chest, barrel, drawer and
-- Sophisticated Storage chest or barrel on the wired network, read as one
-- store, plus the optional Refined Storage chests picked in setup.
--
--   local stores = require("stores").new(setup, config)
--   stores.discover()                 find the inventories on the cable again
--   stores.scan()                     read every store again (all at once)
--   stores.refresh()                  read again only the stores items went into without a known slot
--   stores.items()                    sorted list of { key, name, nbt, count, displayName, maxCount, drawer, rs, fuel }
--   stores.count(key)                 how many of that item there are
--   stores.putAway(from, slot, item, n)   move n of a slot's item into storage; returns how many didn't fit
--   stores.fetch(key, n, to, toSlot, opts) send up to n to an inventory (slot); returns how many went
--   stores.tidy(most)                 move up to most stacks of bulk items into drawers and roomier storage
--   stores.space()                    used, total, text ("12 stores, 40/324 slots, 3 drawers")
--
-- Where things go, so the space lasts: an item already in a drawer goes
-- into that drawer, then onto its own part stacks. An item there's a lot of
-- (BULK) takes an empty drawer, then the roomiest storage (stack upgrades)
-- with a free slot. Small amounts go into plain chests first, so drawers and
-- upgraded storage stay free for bulk. When everything is full it overflows
-- into the Refined Storage input (an RS Interface, or a chest an RS Importer
-- empties). Items in the RS output (an Interface's export slots, or a chest
-- an RS Exporter fills) count as stored and are taken last.
--
-- Keys are the item name, or name#nbt for items with extra data (enchanted
-- books, named tools), so those are kept apart.

-- Types of storage, matched against the peripheral type
-- ("minecraft:chest", "sophisticatedstorage:barrel", "functionalstorage:oak_1").
local STORAGE_TYPES = { "chest", "barrel", "shulker_box", "crate", "drawer", "functionalstorage:", "storagedrawers:",
  "sophisticatedstorage:" }
-- Types that are never storage even if they match: an ender chest shares its
-- items with one far away, controllers show every drawer they reach (each
-- item would count twice), compacting drawers show one item as three.
local NEVER = { "ender", "controller", "compacting", "_io", "slave", "storage_link", "storage_input", "storage_output",
  "armory", "decoration" }
-- Kinds that hold one item per slot, a lot of it (drawers, limited barrels).
local DRAWER_TYPES = { "drawer", "functionalstorage:", "storagedrawers:", "limited_barrel" }
local BULK = 256 -- with this many of an item (or more), it goes in drawers and upgraded storage
local FUEL = { ["minecraft:charcoal"] = true, ["minecraft:coal"] = true, ["minecraft:coal_block"] = true }
local YIELD_AFTER = 0.05 -- seconds of work in a long loop before the screens get a turn

local function keyOf(item) return item.nbt and (item.name .. "#" .. item.nbt) or item.name end

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " "):gsub("^%l", string.upper)) end

local function has(t, list)
  for _, s in ipairs(list) do
    if t:find(s, 1, true) then return true end
  end
  return false
end

local function isInventory(name)
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t == "inventory" then return true end
  end
  return false
end

-- Yields now and then so CC never stops the program for running too long;
-- each yield waits for its own ticket so other loops' yields don't wake it.
local yieldedAt, tickets = os.clock(), 0
local function breathe()
  if os.clock() - yieldedAt < YIELD_AFTER then return end
  tickets = tickets + 1
  local mine = tickets
  os.queueEvent("stash_yield", mine)
  repeat
    local _, t = os.pullEvent("stash_yield")
  until t == mine
  yieldedAt = os.clock()
end

-- Runs fns side by side (each peripheral call takes a game tick on its own).
local function together(fns)
  for i = 1, #fns, 100 do parallel.waitForAll(table.unpack(fns, i, math.min(#fns, i + 99))) end
end

-- A block touching the computer (named by its side) isn't on the wired
-- network, and CC only moves items between blocks on the same network: every
-- pushItems to or from it fails. It's left out, and setup chests there are
-- refused.
local function touching(name)
  for _, side in ipairs(rs.getSides()) do
    if side == name then return true end
  end
  return false
end

local M = { keyOf = keyOf, shortName = shortName, isInventory = isInventory, touching = touching, FUEL = FUEL }

-- What a peripheral is to the stash, from its type: "drawer", "store",
-- "furnace" or nil (not ours: hoppers, machines, ender chests, turtles).
function M.kindOf(name)
  local t = peripheral.getType(name)
  if not t or not isInventory(name) or touching(name) then return nil end
  if t:find("furnace", 1, true) or t:find("smoker", 1, true) then return "furnace" end
  if has(t, NEVER) then return nil end
  if has(t, DRAWER_TYPES) then return "drawer" end
  if has(t, STORAGE_TYPES) then return "store" end
  return nil
end

-- Why a peripheral is or isn't storage, for 'stash check': its kind (as
-- kindOf), or nil and the reason.
function M.explain(name)
  local t = peripheral.getType(name)
  if not t then return nil, "gone" end
  if not isInventory(name) then return nil, "not an inventory CC can reach" end
  if touching(name) then return nil, "touches the computer, so items can't move to or from it: put a wired modem on it" end
  local kind = M.kindOf(name)
  if kind then return kind end
  if has(t, NEVER) then return nil, "never storage (ender chest, controller, compacting...)" end
  return nil, "not a kind of storage it knows"
end

function M.new(setup, config)
  config = config or {}
  local bulk = config.bulk or BULK
  local S = { keyOf = keyOf, shortName = shortName }
  local stores = {} -- name -> { name, drawer, size, limit, slotLimits, rs = "in"/"out", fuel }
  local order = {} -- store names, sorted
  local contents = {} -- name -> list()
  local details = {} -- key -> { displayName, maxCount }
  local pending = {} -- name -> slots probably used since the last read (moves without a known slot)
  local dirty = {} -- names to read again
  local cache -- items() and the index, until something is read or moved
  local version = 0 -- goes up with every change, so a list built across a change isn't kept
  local function invalidate() cache, version = nil, version + 1 end

  local function roleOf(name)
    if name == setup.input or name == setup.output then return "chest" end
    if name == setup.fuel then return "fuel" end
    if name == setup.rsIn then return "rsIn" end
    if name == setup.rsOut then return "rsOut" end
    for _, n in ipairs(setup.ignore or {}) do
      if n == name then return "ignore" end
    end
    return nil
  end

  function S.discover()
    local found, list = {}, {}
    for _, name in ipairs(peripheral.getNames()) do
      local role = not touching(name) and roleOf(name)
      local kind = not role and M.kindOf(name)
      if role == "fuel" or role == "rsOut" then
        found[name] = stores[name] or { name = name, size = 0, limit = 64 }
        found[name].rs, found[name].fuel = role == "rsOut", role == "fuel"
        list[#list + 1] = name
      elseif kind == "drawer" or kind == "store" then
        found[name] = stores[name] or { name = name, drawer = kind == "drawer", size = 0, limit = 64 }
        list[#list + 1] = name
      end
      if found[name] and not contents[name] then dirty[name] = true end -- new: read it on the next refresh
    end
    for name in pairs(contents) do
      if not found[name] then contents[name] = nil end
    end
    table.sort(list)
    stores, order = found, list
    invalidate()
  end

  -- Reads one store: its slots, and what each slot holds (bigger with stack upgrades).
  local function read(name)
    local st = stores[name]
    if not st then return end
    local okL, list = pcall(peripheral.call, name, "list")
    contents[name] = okL and type(list) == "table" and list or {}
    pending[name], dirty[name] = nil, nil
    if st.size == 0 then
      local okS, size = pcall(peripheral.call, name, "size")
      st.size = okS and tonumber(size) or 0
    end
    if st.drawer then
      -- each drawer slot holds its own amount; read once (upgrades change it, a rescan reads them again)
      if not st.slotLimits then
        st.slotLimits = {}
        local fns = {}
        for slot = 1, math.min(st.size, 9) do
          fns[#fns + 1] = function()
            local ok, l = pcall(peripheral.call, name, "getItemLimit", slot)
            st.slotLimits[slot] = ok and tonumber(l) or 64
          end
        end
        together(fns)
      end
    elseif not st.limitRead then
      local ok, l = pcall(peripheral.call, name, "getItemLimit", 1)
      st.limit, st.limitRead = ok and tonumber(l) or 64, true
    end
    for slot, item in pairs(contents[name]) do
      local key = keyOf(item)
      if not details[key] then
        local okD, d = pcall(peripheral.call, name, "getItemDetail", slot)
        details[key] = { displayName = okD and d and d.displayName or shortName(item.name),
          maxCount = okD and d and d.maxCount or 64 }
      end
      -- a slot holding more than its store says (some don't report their upgrades)
      if not st.drawer then
        local seen = math.ceil(item.count * 64 / details[key].maxCount)
        if seen > st.limit then st.limit = seen end
      end
    end
  end

  function S.scan()
    local fns = {}
    for _, name in ipairs(order) do
      local st = stores[name]
      st.limitRead, st.slotLimits = nil, nil -- upgrades may have changed
      fns[#fns + 1] = function() read(name) end
    end
    together(fns)
    invalidate()
  end

  function S.refresh()
    local fns = {}
    for name in pairs(dirty) do fns[#fns + 1] = function() read(name) end end
    if #fns > 0 then
      together(fns)
      invalidate()
    end
  end

  -- The list and an index of where each item is: key -> { { name, slot }, ... }.
  local function build()
    if cache then return cache end
    local v = version
    local byKey, where = {}, {}
    for _, name in ipairs(order) do
      local st = stores[name] or {} -- gone since: the work loop found the chests again while this waited
      for slot, item in pairs(contents[name] or {}) do
        local key = keyOf(item)
        local it = byKey[key]
        if not it then
          local d = details[key] or { displayName = shortName(item.name), maxCount = 64 }
          it = { key = key, name = item.name, nbt = item.nbt, count = 0, displayName = d.displayName, maxCount = d.maxCount }
          byKey[key], where[key] = it, {}
        end
        it.count = it.count + item.count
        if st.drawer then it.drawer = true end
        if st.rs then it.rs = true end
        if st.fuel then it.fuel = true end
        local w = where[key]
        w[#w + 1] = { name = name, slot = slot }
      end
      breathe()
    end
    local list = {}
    for _, it in pairs(byKey) do list[#list + 1] = it end
    table.sort(list, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return a.displayName < b.displayName
    end)
    -- the screens build it too, yielding between chests: if anything moved
    -- meanwhile, use it once but don't keep it
    local built = { list = list, byKey = byKey, where = where }
    if v == version then cache = built end
    return built
  end

  function S.items() return build().list end
  function S.count(key) local it = build().byKey[key] return it and it.count or 0 end
  function S.info(key) return build().byKey[key] end

  local function maxOf(key) return (details[key] or {}).maxCount or 64 end
  -- items one slot of this store holds of this item
  local function slotRoom(st, slot, key)
    if st.drawer then return (st.slotLimits or {})[slot] or 64 end
    return math.max(1, math.floor(st.limit * maxOf(key) / 64))
  end
  local function used(name)
    local n = pending[name] or 0
    for _ in pairs(contents[name] or {}) do n = n + 1 end
    return n
  end
  local function freeSlots(name) return math.max(0, stores[name].size - used(name)) end

  -- Where up to n more of key go, best first: { name, slot } (slot nil = anywhere in it).
  local function targets(key, total)
    local out, seen = {}, {}
    local function add(name, slot)
      local id = name .. ":" .. tostring(slot)
      if not seen[id] then
        seen[id] = true
        out[#out + 1] = { name = name, slot = slot }
      end
    end
    local c = build()
    local here = c.where[key] or {}
    -- its own drawers, then its own part stacks (roomiest store first)
    local mine = {}
    for _, w in ipairs(here) do
      local st = stores[w.name]
      local item = (contents[w.name] or {})[w.slot]
      if st and not st.rs and not st.fuel and item and item.count < slotRoom(st, w.slot, key) then
        mine[#mine + 1] = { name = w.name, slot = w.slot, drawer = st.drawer, room = slotRoom(st, w.slot, key) }
      end
    end
    table.sort(mine, function(a, b)
      if a.drawer ~= b.drawer then return a.drawer end
      return a.room > b.room
    end)
    for _, m in ipairs(mine) do add(m.name, m.slot) end

    local drawers, roomy, plain = {}, {}, {}
    for _, name in ipairs(order) do
      local st = stores[name]
      if not st.rs and not st.fuel and freeSlots(name) > 0 then
        if st.drawer then drawers[#drawers + 1] = name
        elseif st.limit > 64 then roomy[#roomy + 1] = name
        else plain[#plain + 1] = name end
      end
    end
    table.sort(roomy, function(a, b) return stores[a].limit > stores[b].limit end)
    -- the fullest plain chest first, so items gather in a few and the rest stay empty
    table.sort(plain, function(a, b)
      local fa, fb = freeSlots(a), freeSlots(b)
      if fa ~= fb then return fa < fb end
      return a < b
    end)
    local groups = total >= bulk and { drawers, roomy, plain } or { plain, roomy, drawers }
    for _, g in ipairs(groups) do
      for _, name in ipairs(g) do add(name, nil) end
    end
    if setup.rsIn and peripheral.isPresent(setup.rsIn) then add(setup.rsIn, nil) end
    return out
  end

  -- Notes a move so the next choice knows (the store is read again later).
  local function moved(to, toSlot, key, item, n)
    if not stores[to] then return end
    local list = contents[to] or {}
    contents[to] = list
    if toSlot and list[toSlot] then
      list[toSlot].count = list[toSlot].count + n
    elseif toSlot then
      list[toSlot] = { name = item.name, nbt = item.nbt, count = n }
    else
      pending[to] = (pending[to] or 0) + math.ceil(n / maxOf(key))
      dirty[to] = true
    end
    invalidate()
  end
  local function took(from, slot, n)
    local list = contents[from]
    if not list or not list[slot] then return end
    list[slot].count = list[slot].count - n
    if list[slot].count <= 0 then list[slot] = nil end
    invalidate()
  end

  local function push(from, slot, to, n, toSlot)
    local ok, m = pcall(peripheral.call, from, "pushItems", to, slot, n, toSlot)
    return ok and tonumber(m) or 0
  end

  function S.putAway(from, slot, item, n)
    local key = keyOf(item)
    if not details[key] then
      local ok, d = pcall(peripheral.call, from, "getItemDetail", slot)
      details[key] = { displayName = ok and d and d.displayName or shortName(item.name), maxCount = ok and d and d.maxCount or 64 }
    end
    local left = n
    -- coal and charcoal go in the fuel chest first
    if setup.fuel and FUEL[item.name] and not item.nbt and peripheral.isPresent(setup.fuel) then
      local m = push(from, slot, setup.fuel, left)
      if m > 0 then
        left = left - m
        moved(setup.fuel, nil, key, item, m)
      end
    end
    if left > 0 then
      for _, t in ipairs(targets(key, S.count(key) + left)) do
        local m = push(from, slot, t.name, left, t.slot)
        if m > 0 then
          left = left - m
          moved(t.name, t.slot, key, item, m)
          if t.name == setup.rsIn then S.sentToRs = (S.sentToRs or 0) + m end
        end
        if left <= 0 then break end
      end
    end
    if stores[from] then took(from, slot, n - left) end
    return left
  end

  -- Where to take key from: part stacks in plain chests first (frees slots),
  -- then upgraded storage, drawers, the fuel chest (opts.fuelFirst: it
  -- first) and Refined Storage last.
  local function sources(key, opts)
    local list = {}
    for _, w in ipairs(build().where[key] or {}) do
      local st = stores[w.name]
      local item = st and (contents[w.name] or {})[w.slot]
      if item then
        local rank = st.rs and 5 or st.fuel and (opts.fuelFirst and 0 or 4) or st.drawer and 3 or st.limit > 64 and 2 or 1
        list[#list + 1] = { name = w.name, slot = w.slot, rank = rank, count = item.count }
      end
    end
    table.sort(list, function(a, b)
      if a.rank ~= b.rank then return a.rank < b.rank end
      return a.count < b.count
    end)
    return list
  end

  function S.fetch(key, n, to, toSlot, opts)
    opts = opts or {}
    local sent = 0
    local info = S.info(key)
    local item = { name = info and info.name or key, nbt = info and info.nbt }
    for _, src in ipairs(sources(key, opts)) do
      if sent >= n then break end
      local skip = (opts.noRs and src.rank == 5) or (opts.noFuel and stores[src.name].fuel)
      if not skip then
        local m = push(src.name, src.slot, to, math.min(n - sent, src.count), toSlot)
        if m > 0 then
          sent = sent + m
          took(src.name, src.slot, m)
          if stores[to] then moved(to, toSlot, key, item, m) end
        elseif toSlot then
          break -- the slot is full or won't take it
        end
      end
    end
    return sent
  end

  -- Moves up to most stacks of bulk items out of plain chests (or into a
  -- drawer they already have), so plain slots stay free for everything else.
  function S.tidy(most)
    local moves, done = 0, {}
    for _, it in ipairs(S.items()) do
      if moves >= most or it.count < bulk then break end
      local hasDrawer = false
      for _, w in ipairs(build().where[it.key] or {}) do
        if (stores[w.name] or {}).drawer then hasDrawer = true end
      end
      for _, w in ipairs(build().where[it.key] or {}) do
        if moves >= most then break end
        local st = stores[w.name] or {}
        local item = (contents[w.name] or {})[w.slot]
        local rank = st.drawer and 3 or (st.limit or 64) > 64 and 2 or 1
        if item and not st.rs and not st.fuel and (rank == 1 or (rank == 2 and hasDrawer)) then
          for _, t in ipairs(targets(it.key, it.count)) do
            local ts = stores[t.name]
            local tr = ts and (ts.drawer and 3 or ts.limit > 64 and 2 or 1) or 0
            if tr > rank then
              local m = push(w.name, w.slot, t.name, item.count, t.slot)
              if m > 0 then
                moves = moves + 1
                done[#done + 1] = ("%d %s to %s"):format(m, it.displayName, t.name)
                took(w.name, w.slot, m)
                moved(t.name, t.slot, it.key, item, m)
                break
              end
            end
          end
        end
      end
    end
    if moves > 0 then S.refresh() end
    return moves, done
  end

  function S.space()
    local usedSlots, total, n, drawers = 0, 0, 0, 0
    for _, name in ipairs(order) do
      local st = stores[name]
      if not st.rs and not st.fuel then
        if st.drawer then
          drawers = drawers + 1
        else
          n = n + 1
          total = total + st.size
          usedSlots = usedSlots + used(name)
        end
      end
    end
    local text = ("%d chests %d/%d slots"):format(n, usedSlots, total)
    if drawers > 0 then text = text .. (", %d drawers"):format(drawers) end
    return usedSlots, total, text
  end

  function S.names() return order end
  function S.store(name) return stores[name] end
  return S
end

return M
