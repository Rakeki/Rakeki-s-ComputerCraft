-- Storage backend: every chest and barrel on the wired network is storage,
-- apart from the chests chosen in 'storage setup'. storage.lua talks to this
-- or to bridge.lua (an ME or RS system) through the same functions:
--
--   B.kind                            "chests", for messages
--   B.scan()                          read everything again (each chest is one call)
--   B.items()                         key -> { key, name, nbt, count, displayName, maxCount }
--   B.space()                         used, total, text for the header ("12 chests, 40/324 slots")
--   B.putAway(from, slot, item, n)    move n of a chest slot's item into storage; returns how many didn't fit
--   B.fetch(key, n, to, toSlot)       send up to n of the item with that key to a chest (slot); returns sent, err
--   B.tidy()                          move a few stacks so bulk items sit in the roomiest storage; returns how
--                                     many stacks moved and what
--   B.roomInfo()                      how many stores hold more than 64 a slot, and the most any holds
--
-- Keys are the item name, or name#nbt for items with extra data (enchanted
-- books, named tools), so those are kept apart from plain ones.
--
-- Storage with stack upgrades (Sophisticated Storage) or big slots (drawers)
-- holds more per slot; getItemLimit says how much. Items there's a lot of go
-- to the roomiest storage, and small amounts to plain chests, so the roomy
-- ones stay free for bulk.

-- Inventories that count as storage, matched against the peripheral type
-- (e.g. "minecraft:chest"). Furnaces, hoppers and turtles never do.
local STORAGE_TYPES = { "chest", "barrel", "shulker_box", "crate", "drawer" }
local BULK = 256 -- items: with this many of an item stored, it goes in the roomiest storage first
local SMALL = 128 -- items: with fewer than this, it may be moved out of roomy storage to make room for bulk
local TIDY_MOVES = 16 -- most stacks one tidy moves (each move takes a few ticks)

local function keyOf(item) return item.nbt and (item.name .. "#" .. item.nbt) or item.name end

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

-- Yield now and then in long loops, so CC never stops the program for
-- running too long without yielding.
local calls = 0
local function breathe()
  calls = calls + 1
  if calls % 200 == 0 then
    os.queueEvent("chests_yield")
    os.pullEvent("chests_yield")
  end
end

local function isInventory(name)
  for _, t in ipairs({ peripheral.getType(name) }) do
    if t == "inventory" then return true end
  end
  return false
end

local M = {}

function M.new(setup)
  local B = { kind = "chests" }
  local stores = {} -- peripheral names of the storage inventories
  local contents = {} -- store name -> its list() result
  local sizes = {} -- store name -> number of slots
  local limits = {} -- store name -> items one slot holds (64 for a plain chest, more with stack upgrades)
  local details = {} -- item key -> { displayName, maxCount }

  local function isStorage(name)
    for _, which in ipairs({ "input", "output", "delivery", "crafter", "fuel", "transfer" }) do
      if name == setup[which] then return false end
    end
    -- extra input chests, turtles' own delivery and crafter chests (lib/claim.lua)
    -- and computers' work chests (lib/workchest.lua)
    for _, list in ipairs({ setup.inputs or {}, setup.deliveries or {}, setup.crafters or {}, setup.works or {} }) do
      for _, chest in pairs(list) do
        if name == chest then return false end
      end
    end
    local t = peripheral.getType(name)
    -- an ender chest (EnderStorage and the like) shares its inventory with
    -- one somewhere else: items stored in it would turn up there
    if t and t:find("ender", 1, true) then return false end
    for _, s in ipairs(STORAGE_TYPES) do
      if t and t:find(s, 1, true) then return true end
    end
    return false
  end

  local function rescan(name)
    local ok, list = pcall(peripheral.call, name, "list")
    contents[name] = ok and list or {}
    for slot, item in pairs(contents[name]) do
      local key = keyOf(item)
      if not details[key] then
        local okD, d = pcall(peripheral.call, name, "getItemDetail", slot)
        details[key] = { displayName = okD and d and d.displayName or shortName(item.name),
          maxCount = okD and d and d.maxCount or 64 }
      end
      -- a slot holding more than a stack shows the slots are bigger than the
      -- store says (some don't report their stack upgrades)
      local seen = math.ceil(item.count * 64 / details[key].maxCount)
      if seen > (limits[name] or 64) then limits[name] = seen end
    end
  end

  function B.scan()
    stores = {}
    for _, name in ipairs(peripheral.getNames()) do
      if isInventory(name) and isStorage(name) then stores[#stores + 1] = name end
    end
    table.sort(stores)
    local jobs = {}
    for _, name in ipairs(stores) do
      jobs[#jobs + 1] = function()
        local ok, size = pcall(peripheral.call, name, "size")
        sizes[name] = ok and size or 0
        -- stack upgrades apply to every slot, so the first one tells
        local okL, limit = pcall(peripheral.call, name, "getItemLimit", 1)
        limits[name] = okL and tonumber(limit) or 64
        rescan(name) -- may raise it, from what the slots hold
      end
    end
    -- Each call takes a game tick, so ask every chest at once.
    if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
    for name in pairs(contents) do
      if not sizes[name] or not peripheral.isPresent(name) then contents[name], sizes[name], limits[name] = nil, nil, nil end
    end
  end

  function B.items()
    local out = {}
    for _, name in ipairs(stores) do
      for _, item in pairs(contents[name] or {}) do
        local key = keyOf(item)
        local it = out[key]
        if not it then
          local d = details[key] or {}
          it = { key = key, name = item.name, nbt = item.nbt ~= nil, count = 0,
            displayName = d.displayName or shortName(item.name), maxCount = d.maxCount or 64 }
          out[key] = it
        end
        it.count = it.count + item.count
      end
    end
    return out
  end

  function B.space()
    local used, total = 0, 0
    for _, name in ipairs(stores) do
      total = total + (sizes[name] or 0)
      for _ in pairs(contents[name] or {}) do used = used + 1 end
    end
    return used, total, ("%d chests, %d/%d slots"):format(#stores, used, total)
  end

  -- How many stores hold more than 64 a slot, the most any holds, and how
  -- many stores there are of each slot size: { { limit, count }, ... }.
  function B.roomInfo()
    local roomy, most, bySize = 0, 64, {}
    for _, name in ipairs(stores) do
      local l = limits[name] or 64
      if l > 64 then roomy = roomy + 1 end
      most = math.max(most, l)
      bySize[l] = (bySize[l] or 0) + 1
    end
    local sizesList = {}
    for l, n in pairs(bySize) do sizesList[#sizesList + 1] = { l, n } end
    table.sort(sizesList, function(a, b) return a[1] > b[1] end)
    return roomy, most, sizesList
  end

  ---------------------------------------------------------------- room

  local function limitOf(name) return limits[name] or 64 end

  -- How many of the item one slot of this store takes (a slot of ender
  -- pearls holds a quarter of a slot of cobblestone).
  local function slotCap(name, key)
    local max = details[key] and details[key].maxCount or 64
    return math.max(1, math.floor(max * limitOf(name) / 64))
  end

  local function holds(name, key)
    for _, item in pairs(contents[name] or {}) do
      if keyOf(item) == key then return true end
    end
    return false
  end

  -- Whether the store can take any more of the item: a free slot, or a slot
  -- of it that isn't full. Skipping full ones saves a wasted tick each.
  local function hasRoom(name, key)
    local used, cap = 0, slotCap(name, key)
    for _, item in pairs(contents[name] or {}) do
      used = used + 1
      if keyOf(item) == key and item.count < cap then return true end
    end
    return used < (sizes[name] or 0)
  end

  local function totalOf(key)
    local n = 0
    for _, name in ipairs(stores) do
      for _, item in pairs(contents[name] or {}) do
        if keyOf(item) == key then n = n + item.count end
      end
    end
    return n
  end

  -- Where to put an item, best first. Bulk: roomiest storage first, ones
  -- that already hold it first among equals. Otherwise: ones that hold it,
  -- then plain chests before roomy ones.
  local function placeOrder(key, bulk)
    local order, has = {}, {}
    for _, name in ipairs(stores) do
      breathe()
      if hasRoom(name, key) then
        order[#order + 1] = name
        has[name] = holds(name, key)
      end
    end
    table.sort(order, function(a, b)
      local la, lb = limitOf(a), limitOf(b)
      if bulk then
        if la ~= lb then return la > lb end
        if has[a] ~= has[b] then return has[a] end
      else
        if has[a] ~= has[b] then return has[a] end
        if la ~= lb then return la < lb end
      end
      return a < b
    end)
    return order
  end

  ---------------------------------------------------------------- moving

  function B.putAway(from, slot, item, count)
    local key, left = keyOf(item), count
    for _, name in ipairs(placeOrder(key, totalOf(key) + count >= BULK)) do
      local okP, moved = pcall(peripheral.call, from, "pushItems", name, slot, left)
      if okP and moved > 0 then
        left = left - moved
        rescan(name)
      end
      if left <= 0 then break end
    end
    return left
  end

  function B.fetch(key, amount, to, toSlot)
    local sent, misses = 0, 0
    for _, name in ipairs(stores) do
      local touched = false -- only re-read chests items came from: each read takes a tick
      for slot, item in pairs(contents[name] or {}) do
        if keyOf(item) == key then
          touched = true
          local ok, moved = pcall(peripheral.call, to, "pullItems", name, slot, amount - sent, toSlot)
          if not ok then
            rescan(name)
            return sent, tostring(moved) -- e.g. the chest isn't on the same network
          end
          sent = sent + moved
          if moved == 0 then
            -- the slot was emptied meanwhile, or the chest is full: after a
            -- few misses in a row, take it that it's full
            misses = misses + 1
            if misses >= 3 then
              rescan(name)
              return sent
            end
          else
            misses = 0
          end
          if sent >= amount then break end
        end
      end
      if touched then rescan(name) end
      if sent >= amount then break end
    end
    return sent
  end

  -- Move one slot's worth from store a to store b. Returns how many moved.
  local function move(a, slot, b, count)
    local ok, moved = pcall(peripheral.call, a, "pushItems", b, slot, count)
    if not ok or moved == 0 then return 0 end
    rescan(a)
    rescan(b)
    return moved
  end

  -- A few moves towards bulk items in the roomiest storage: a stack of a
  -- bulk item goes up into roomier storage with room for it; if the roomier
  -- storage is full, a stack of something there's little of comes out of it
  -- first, into plainer storage. Items only ever move up (bulk) or down
  -- (small), and the gap between BULK and SMALL stops them going back and
  -- forth.
  -- log, if given, is told each move, and why nothing moved.
  function B.tidy(log)
    log = log or function() end
    local roomy, most = B.roomInfo()
    if roomy == 0 then
      log("Every storage holds 64 a slot, so there's nothing to sort.")
      return 0
    end
    local totals, moved, what = {}, 0, nil
    for key, it in pairs(B.items()) do totals[key] = it.count end
    local bulk = {}
    for key, n in pairs(totals) do
      if n >= BULK then bulk[#bulk + 1] = key end
    end
    table.sort(bulk, function(a, b) return totals[a] > totals[b] end)
    if #bulk == 0 then
      log(("Nothing has %d or more stored yet, so nothing counts as bulk."):format(BULK))
      return 0
    end
    local function nameOf(key) return details[key] and details[key].displayName or key end
    local blocked = {} -- bulk items with no roomier storage to go to

    local evictFailed = {} -- slot sizes it couldn't make room above this pass
    for _, key in ipairs(bulk) do
      for _, from in ipairs(stores) do
        if moved >= TIDY_MOVES then return moved, what end
        breathe()
        if limitOf(from) < most and holds(from, key) then
          for slot, item in pairs(contents[from] or {}) do
            if keyOf(item) == key then
              local to
              for _, name in ipairs(placeOrder(key, true)) do
                if limitOf(name) > limitOf(from) then to = name break end
              end
              if not to and not evictFailed[limitOf(from)] then
                evictFailed[limitOf(from)] = true -- cleared below if room was made
                -- make room: move something there's little of out of the
                -- roomiest storage that's roomier than here
                for _, name in ipairs(stores) do
                  if not to and limitOf(name) > limitOf(from) then
                    for s, other in pairs(contents[name] or {}) do
                      breathe()
                      local k = keyOf(other)
                      if (totals[k] or 0) < SMALL then
                        for _, down in ipairs(placeOrder(k, false)) do
                          if limitOf(down) < limitOf(name) then
                            local n = move(name, s, down, other.count)
                            if n > 0 then
                              moved = moved + 1
                              log(("Moved %d %s out of %s (%d a slot) to make room."):format(n, nameOf(k), name,
                                limitOf(name)))
                              if hasRoom(name, key) then
                                to = name
                                evictFailed[limitOf(from)] = nil
                              end
                            end
                            break
                          end
                        end
                        if to or moved >= TIDY_MOVES then break end
                      end
                    end
                  end
                end
              end
              if to and moved < TIDY_MOVES then
                local n = move(from, slot, to, item.count)
                if n > 0 then
                  moved = moved + 1
                  what = nameOf(key)
                  log(("Moved %d %s from %s (%d a slot) to %s (%d a slot)."):format(n, what, from, limitOf(from),
                    to, limitOf(to)))
                end
              elseif not to then
                blocked[key] = true
              end
              break -- contents[from] changed: look at this store again next time
            end
          end
        end
      end
    end
    if moved == 0 then
      local n, first = 0, nil
      for key in pairs(blocked) do
        n = n + 1
        first = first or key
      end
      if n > 0 then
        log(("%d bulk items (like %s) are in smaller storage, but the roomier storage is full and has nothing"
          .. " small to move out."):format(n, nameOf(first)))
      else
        log(("All %d bulk items are already in the roomiest storage with space."):format(#bulk))
      end
    end
    return moved, what
  end

  return B
end

return M
