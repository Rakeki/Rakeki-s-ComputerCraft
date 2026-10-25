-- Tells the storage computer which chest on its wired network is the one
-- next to this turtle, so the player never has to pick it in 'storage setup':
-- place the turtle against a chest that has a wired modem on the storage
-- cable, and it hooks itself up.
--
--   local claim = require("lib.claim")
--   local ok, chest = claim.chest(askStorage, "delivery", "front")
--   -- ok: true, chest = its name on the network ("minecraft:chest_12")
--   --     false, chest = why not (no chest there, not on the network, ...)
--   --     nil: no storage system answered
--
-- askStorage(msg) is the program's own request function: it sends msg on
-- the "storage" protocol with an id and returns the matching reply, or nil
-- (see the storage-system skill). role is "delivery" (the storage computer
-- sends this turtle's orders there) or "crafter" (the crafting turtle's chest).
--
-- How it finds the chest: the turtle sends what its chest holds. If that's
-- the chest the storage computer already has for it, that's that. Otherwise
-- the storage computer puts one item in each chest that could be it, one at
-- a time, and the turtle says whether it turned up in its own chest. The
-- item is taken back each time.
local claim = {}

local MAX_PROBES = 1000 -- most chests tried before giving up (one round trip each)

local SIDES = { front = "in front of me", back = "behind me", top = "above me", bottom = "below me",
  left = "to my left", right = "to my right" }

local function count(list, name)
  local n = 0
  for _, it in pairs(list) do
    if it.name == name then n = n + it.count end
  end
  return n
end

function claim.chest(ask, role, side)
  local chest = peripheral.wrap(side)
  local noChest = "there's no chest " .. (SIDES[side] or side)
  if not (chest and chest.list) then return false, noChest end
  local ok, list = pcall(chest.list)
  if not ok then return false, noChest end
  local r = ask({ type = "claim", role = role, items = list })
  for _ = 1, MAX_PROBES do
    if type(r) ~= "table" then return nil end
    if r.ok then return true, r.chest end
    if not r.probe then return false, r.error or "the storage system didn't say why" end
    -- it has just put one r.probe in one of its chests: did it land in mine?
    local okNow, now = pcall(chest.list)
    if not okNow then return false, noChest end
    r = ask({ type = "claim", role = role, seen = count(now, r.probe) > count(list, r.probe) })
    list = now
  end
  return false, "tried too many chests"
end

return claim
