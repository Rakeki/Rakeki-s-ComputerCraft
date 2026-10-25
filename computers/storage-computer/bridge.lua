-- Storage backend for an Applied Energistics 2 or Refined Storage system,
-- through an Advanced Peripherals ME Bridge or RS Bridge on the wired
-- network. Same functions as chests.lua (see there), plus:
--
--   B.canCraft(name)          the system has a pattern for it
--   B.craft(name, n)          start the system crafting n; returns ok, err
--   B.isCrafting(name)        the system is still crafting it
--   B.clearTransfer()         put anything left in the transfer chest back
--   B.problem                 why the bridge isn't answering, or nil
--
-- Works with both bridge APIs: the older one (Minecraft 1.20 and before:
-- listItems, exportItemToPeripheral, craftItem returning true) and the newer
-- one (1.21: getItems, exportItem(filter, target), craftItem returning a job).
-- The bridge can't put an item in a chosen slot, so moves that need one
-- (furnaces, the crafting turtle's grid) go through the transfer chest.

local REFRESH = 5 -- seconds a read of the system's items is used before reading it again
local CRAFTABLE_REFRESH = 30 -- seconds the list of what the system can craft is kept
local MAX_CALLS = 64 -- most transfer calls per move (newer bridges move one stack per call)

-- Peripheral types of the bridges (they changed in Minecraft 1.21).
local TYPES = { meBridge = "ME", me_bridge = "ME", rsBridge = "RS", rs_bridge = "RS" }

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local M = {}

-- The bridge's peripheral name and "ME" or "RS", or nil.
function M.find()
  for _, name in ipairs(peripheral.getNames()) do
    for _, t in ipairs({ peripheral.getType(name) }) do
      if TYPES[t] then return name, TYPES[t] end
    end
  end
end

function M.new(setup)
  local name, kind = M.find()
  if not name then return nil, "no ME Bridge or RS Bridge on the network" end
  local b = peripheral.wrap(name)
  local B = { kind = kind, bridge = name, scanEvery = REFRESH }
  local cache, readAt, dirty = {}, -math.huge, true
  local used, total
  local craftable, craftableAt = {}, -math.huge

  local function has(method) return type(b[method]) == "function" end

  local function call(method, ...)
    if not has(method) then return nil, "the bridge has no " .. method end
    local ok, r, err = pcall(b[method], ...)
    if not ok then return nil, tostring(r) end
    return r, err
  end

  -- How many moved: the newer bridge may answer with the moved stack.
  local function movedOf(r)
    if type(r) == "number" then return r end
    if type(r) == "table" then return tonumber(r.count or r.amount) or 0 end
    return 0
  end

  local function refresh()
    local list, err
    if has("getItems") then list, err = call("getItems", {}) else list, err = call("listItems") end
    if type(list) ~= "table" then
      B.problem = type(err) == "string" and err or "the bridge didn't list its items (is the system powered?)"
      return
    end
    B.problem = nil
    local out, sum = {}, 0
    for _, e in pairs(list) do
      local n = tonumber(e.count or e.amount) or 0
      if type(e.name) == "string" and n > 0 then
        local nbt = (type(e.nbt) == "string" and e.nbt ~= "" and e.nbt ~= "{}")
          or (type(e.nbt) == "table" and next(e.nbt) ~= nil)
        local key = nbt and (e.name .. "#" .. tostring(e.fingerprint or "nbt")) or e.name
        local it = out[key]
        if not it then
          -- some versions put the name in [brackets]
          local shown = type(e.displayName) == "string" and (e.displayName:gsub("^%[(.*)%]$", "%1")) or shortName(e.name)
          it = { key = key, name = e.name, nbt = nbt, count = 0, displayName = shown,
            maxCount = tonumber(e.maxStackSize) or 64, fingerprint = e.fingerprint }
          out[key] = it
        end
        it.count = it.count + n
        sum = sum + n
      end
    end
    cache, readAt, dirty = out, os.clock(), false
    -- ME counts its space in bytes, RS in items; either makes a fair bar
    used = tonumber((call("getUsedItemStorage")))
    total = tonumber((call("getTotalItemStorage"))) or tonumber((call("getMaxItemDiskStorage")))
    if total and not used then used = sum end
  end

  function B.scan() refresh() end

  function B.items()
    -- re-read soon after a move, and every few seconds anyway (things move
    -- in and out of the system without us)
    local age = os.clock() - readAt
    if (dirty and age > 0.5) or age > REFRESH then refresh() end
    return cache
  end

  function B.space()
    local items = 0
    for _, it in pairs(B.items()) do items = items + it.count end
    if used and total and total > 0 then
      return used, total, ("%s system, %d%% full"):format(kind, math.floor(used / total * 100))
    end
    return nil, nil, ("%s system, %d items"):format(kind, items)
  end

  local function export(filter, amount, to)
    local sent, err = 0, nil
    for _ = 1, MAX_CALLS do
      if sent >= amount then break end
      local r, e
      if has("exportItemToPeripheral") then
        r, e = call("exportItemToPeripheral", filter(amount - sent), to)
      else
        r, e = call("exportItem", filter(amount - sent), to)
      end
      if r == nil then err = type(e) == "string" and e or nil end
      local n = movedOf(r)
      if n <= 0 then break end
      sent = sent + n
    end
    dirty = true
    return sent, sent == 0 and err or nil
  end

  local function import(filter, amount, from)
    local got = 0
    for _ = 1, MAX_CALLS do
      if got >= amount then break end
      local r
      if has("importItemFromPeripheral") then
        r = call("importItemFromPeripheral", filter(amount - got), from)
      else
        r = call("importItem", filter(amount - got), from)
      end
      local n = movedOf(r)
      if n <= 0 then break end
      got = got + n
    end
    dirty = true
    return got
  end

  -- The bridge takes items by name from anywhere in the chest, not from one
  -- slot, so what's left over may come from another slot of the same item.
  function B.putAway(from, _, item, count)
    local got = import(function(n) return { name = item.name, count = n } end, count, from)
    return count - math.min(count, got)
  end

  function B.clearTransfer()
    if not setup.transfer then return end
    local ok, list = pcall(peripheral.call, setup.transfer, "list")
    for slot, item in pairs(ok and list or {}) do B.putAway(setup.transfer, slot, item, item.count) end
  end

  function B.fetch(key, amount, to, toSlot)
    local it = B.items()[key]
    if not it then return 0 end
    local function filter(n)
      if it.nbt and it.fingerprint then return { fingerprint = it.fingerprint, count = n } end
      return { name = it.name, count = n }
    end
    if not toSlot then return export(filter, amount, to) end
    if not setup.transfer then return 0, "no transfer chest: run 'storage setup'" end
    B.clearTransfer()
    local got, err = export(filter, amount, setup.transfer)
    local sent = 0
    if got > 0 then
      local ok, list = pcall(peripheral.call, setup.transfer, "list")
      for slot, item in pairs(ok and list or {}) do
        if sent < amount and item.name == it.name then
          local okP, moved = pcall(peripheral.call, setup.transfer, "pushItems", to, slot, amount - sent, toSlot)
          if okP then sent = sent + moved else err = err or tostring(moved) end
        end
      end
    end
    B.clearTransfer()
    return sent, err
  end

  ---------------------------------------------------------------- crafting

  local function refreshCraftable()
    craftable, craftableAt = {}, os.clock()
    local list
    if has("getCraftableItems") then list = call("getCraftableItems", {})
    elseif has("listCraftableItems") then list = call("listCraftableItems") end
    if type(list) ~= "table" then return false end
    for _, e in pairs(list) do
      if type(e.name) == "string" then craftable[e.name] = true end
    end
    return true
  end
  local canList = true

  function B.canCraft(item)
    if os.clock() - craftableAt > CRAFTABLE_REFRESH then canList = refreshCraftable() end
    if craftable[item] == nil and not canList then
      -- no list on this bridge: ask about this item (one call each)
      local method = has("isItemCraftable") and "isItemCraftable" or "isCraftable"
      craftable[item] = call(method, { name = item }) == true
    end
    return craftable[item] == true
  end

  function B.craft(item, count)
    local r, err = call("craftItem", { name = item, count = count })
    if r then return true end -- true, or a crafting job on newer bridges
    return false, type(err) == "string" and err or ("the %s system wouldn't start crafting it"):format(kind)
  end

  function B.isCrafting(item)
    local method = has("isItemCrafting") and "isItemCrafting" or "isCrafting"
    return call(method, { name = item }) == true
  end

  return B
end

return M
