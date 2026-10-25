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
--
-- Keys are the item name, or name#nbt for items with extra data (enchanted
-- books, named tools), so those are kept apart from plain ones.

-- Inventories that count as storage, matched against the peripheral type
-- (e.g. "minecraft:chest"). Furnaces, hoppers and turtles never do.
local STORAGE_TYPES = { "chest", "barrel", "shulker_box", "crate", "drawer" }

local function keyOf(item) return item.nbt and (item.name .. "#" .. item.nbt) or item.name end

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

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
  local details = {} -- item key -> { displayName, maxCount }

  local function isStorage(name)
    for _, which in ipairs({ "input", "output", "delivery", "crafter", "fuel", "transfer" }) do
      if name == setup[which] then return false end
    end
    local t = peripheral.getType(name)
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
        rescan(name)
      end
    end
    -- Each call takes a game tick, so ask every chest at once.
    if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
    for name in pairs(contents) do
      if not sizes[name] or not peripheral.isPresent(name) then contents[name], sizes[name] = nil, nil end
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

  -- Into chests that already hold that item first, then anywhere with space.
  function B.putAway(from, slot, item, count)
    local key, left = keyOf(item), count
    local order = {}
    for _, name in ipairs(stores) do
      for _, have in pairs(contents[name] or {}) do
        if keyOf(have) == key then order[#order + 1] = name break end
      end
    end
    for _, name in ipairs(stores) do order[#order + 1] = name end
    for _, name in ipairs(order) do
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

  return B
end

return M
