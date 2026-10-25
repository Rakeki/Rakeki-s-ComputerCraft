-- A turtle's inventory and fuel: counting, finding and refuelling, the same
-- way in every turtle program.
--
--   local inv = require("lib.inv")
--   inv.count("minecraft:torch")           -- how many on board
--   inv.select(FUEL)                       -- select the first slot holding one of them
--   inv.emptySlots()                       -- empty slots left
--   inv.fuelLevel()                        -- fuel level ("unlimited" counts as math.huge)
--   inv.refuel(2000, FUEL)                 -- burn fuel items on board up to this level
--
-- What to look for (match) can be an item name, a list of names, a set
-- (name -> true, like a FUEL table) or a function(name) -> true/false.
local inv = {}

function inv.matcher(match)
  if type(match) == "function" then return match end
  if type(match) == "string" then return function(name) return name == match end end
  if type(match) == "table" and match[1] ~= nil then
    return function(name)
      for _, m in ipairs(match) do
        if m == name then return true end
      end
      return false
    end
  end
  if type(match) == "table" then return function(name) return match[name] and true or false end end
  return function() return true end -- nil: anything
end

function inv.count(match)
  local is, n = inv.matcher(match), 0
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and is(it.name) then n = n + it.count end
  end
  return n
end

-- Select the first slot holding a match. False if there's none.
function inv.select(match)
  local is = inv.matcher(match)
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and is(it.name) then
      turtle.select(slot)
      return true
    end
  end
  return false
end

function inv.emptySlots()
  local n = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then n = n + 1 end
  end
  return n
end

function inv.fuelLevel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

-- Burn fuel from the inventory, one item at a time, until the level reaches
-- target. fuels says which items may be burnt; without it, anything that
-- burns is (so a mining turtle burns the coal it digs up).
function inv.refuel(target, fuels)
  local is = fuels and inv.matcher(fuels)
  for slot = 1, 16 do
    if inv.fuelLevel() >= target then break end
    local it = is and turtle.getItemDetail(slot)
    if not is or (it and is(it.name)) then
      turtle.select(slot)
      while inv.fuelLevel() < target and turtle.refuel(1) do end
    end
  end
  turtle.select(1)
end

return inv
