-- Crafting questions for the craft overseer (computers/craft-overseer), the
-- storage system's recipe server. The storage computer only keeps items:
-- ask it for what's stored, and this for what could be made and to have it
-- made. Each helper adds the overseer's answer to a storage computer's
-- reply, so a program reads crafting, cantCraft, craftProblem and craftable
-- in one place, as it did when the storage computer did both.
--
--   local crafts = require("lib.crafts")
--   local r = storage:ask({ type = "deliver", items = want })
--   crafts.deliver(r, want)            -- r.crafting, r.cantCraft, r.craftProblem for what's short
--   local c = storage:ask({ type = "count", items = names, need = need })
--   crafts.count(c, names, need)       -- c.craftable = { [name] = how many more could be made }
--   local p = crafts.prepare(items)    -- start crafting up to n of each in all: { crafting, cantCraft, craftProblem }
--   local reply, why = crafts.ask(msg) -- anything else on the craft_overseer protocol
--
-- Nothing waits long: with no overseer the answers say so ("no craft
-- overseer answered") and the program carries on with what's stored.
local net = require("lib.net")

local PROTOCOL = "craft_overseer" -- the overseer hosts this
local WAIT = 10 -- seconds to wait for it (planning a big order can take a few)
local NONE = "no craft overseer answered (computers/craft-overseer plans every craft)"

local crafts = {}
local peer = net.peer(PROTOCOL, { open = "any", wait = WAIT })

-- The overseer's answer, or nil and why.
function crafts.ask(msg, wait)
  local reply, why = peer:ask(msg, wait)
  if reply then return reply end
  return nil, why == "no answer" and "the craft overseer didn't answer" or NONE
end

-- Start crafting so there'll be n of each item in all (stored, being made,
-- and the new crafts): { crafting = { [name] = n being made }, cantCraft =
-- { [name] = why }, craftProblem }. Without an overseer, every item gets why.
function crafts.prepare(items)
  local reply, why = crafts.ask({ type = "prepare", items = items })
  if reply then
    reply.crafting, reply.cantCraft = reply.crafting or {}, reply.cantCraft or {}
    return reply
  end
  local cant = {}
  for name in pairs(items) do cant[name] = why end
  return { crafting = {}, cantCraft = cant, craftProblem = why }
end

-- After a storage computer's deliver reply r for want ({ [name] = n }, and
-- most like the request's): has what didn't arrive and isn't stored made,
-- and adds crafting, cantCraft and craftProblem to r. Returns r.
function crafts.deliver(r, want, most)
  if type(r) ~= "table" then return r end
  local ready, stock, total, short = r.ready or {}, r.stock or {}, {}, false
  for name, n in pairs(want) do
    local missing = n - (ready[name] or 0)
    local cap = type(most) == "table" and tonumber(most[name])
    if cap then missing = math.min(missing, cap - ((r.sent or {})[name] or 0)) end
    if missing > (stock[name] or 0) then
      -- the overseer counts what's stored, so ask for all there should be in storage
      total[name] = missing
      short = true
    end
  end
  r.crafting, r.cantCraft = r.crafting or {}, r.cantCraft or {}
  if not short then return r end
  local p = crafts.prepare(total)
  for name, n in pairs(p.crafting) do r.crafting[name] = n end
  for name, why in pairs(p.cantCraft) do r.cantCraft[name] = why end
  r.craftProblem = p.craftProblem
  return r
end

-- After a storage computer's count reply r for names (need: { [name] = n },
-- optional): adds r.craftable = { [name] = how many more could be made, those
-- being made included }. Returns r.
function crafts.count(r, names, need)
  if type(r) ~= "table" then return r end
  local reply = crafts.ask({ type = "canmake", items = names, need = need })
  r.craftable = reply and reply.counts or {}
  r.craftProblem = reply and reply.problem or nil
  return r
end

return crafts
