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
-- sends this turtle's orders there), "crafter" (the crafting turtle's chest) or
-- "work" (a far-away computer's work chest, through an ender chest: lib/workchest.lua).
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
  local kind = role == "work" and "work" or "claim" -- a work chest has a request of its own
  local r = ask({ type = kind, role = role, items = list })
  for _ = 1, MAX_PROBES do
    if type(r) ~= "table" then return nil end
    if r.ok then return true, r.chest end
    if not r.probe then return false, r.error or "the storage system didn't say why" end
    -- it has just put one r.probe in one of its chests: did it land in mine?
    local okNow, now = pcall(chest.list)
    if not okNow then return false, noChest end
    r = ask({ type = kind, role = role, seen = count(now, r.probe) > count(list, r.probe) })
    list = now
  end
  return false, "tried too many chests"
end

-- For a turtle that orders items now and then: claim its chest the first
-- time, try again a while later if that didn't work, and again whenever a
-- delivery shows the storage computer has forgotten it (after being set up
-- again).
--
--   local supply = claim.tracker("delivery", 300)
--   if supply:due() then faceSupply(); local ok, why = supply:check(askStorage, "front") ... end
--   local r = askStorage({ type = "deliver", ... }); supply:seen(r)
--
-- check returns the same as claim.chest. After no answer at all (no storage
-- system yet) it tries again in a minute; after a refusal, in retry seconds.
function claim.tracker(role, retry)
  local t = { role = role, retry = retry or 300, done = false, after = -math.huge }
  function t:due() return not self.done and os.clock() >= self.after end
  function t:check(ask, side)
    local ok, why = claim.chest(ask, self.role, side)
    if ok then
      self.done = true
    else
      self.after = os.clock() + (ok == false and self.retry or 60)
    end
    return ok, why
  end
  function t:seen(reply)
    if reply and reply.to ~= "own" then self.done = false end
  end
  return t
end

return claim
