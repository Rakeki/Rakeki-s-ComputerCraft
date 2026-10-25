-- Rednet the same way in every program: opening modems, asking another
-- computer something and waiting for its answer (never forever), and
-- answering. Requests carry an id that the answer repeats, along with re
-- (the request's type), so a late answer is never taken for a newer one.
--
--   local net = require("lib.net")
--   net.open()                                -- wireless or ender modems; net.open("any") opens wired ones too
--   local reply = net.ask(id, "storage", { type = "count", items = { ... } })
--   net.answer(from, "storage", request, { counts = counts })  -- adds re and id
--
--   local storage = net.peer("storage", { retry = 60 })  -- finds the computer hosting the protocol
--   local reply, why = storage:ask({ type = "deliver", items = order })
--   -- why, when reply is nil: "no modem", "none" (nobody hosts it) or "no answer"
--
-- net.ask's opts: wait (seconds, default 10), match(reply, from) to accept a
-- different kind of answer (default: re and id match), and other(from, msg)
-- for anything else that arrives on the protocol while waiting.
local net = {}

local nextId = 0 -- shared by every coroutine on this computer, so ids never repeat

-- Open modems: kind "wireless" (default) opens wireless and ender modems,
-- "any" every modem, wired ones too. True if rednet is open on any.
function net.open(kind)
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" and not rednet.isOpen(side)
      and (kind == "any" or peripheral.call(side, "isWireless")) then
      rednet.open(side)
    end
  end
  return rednet.isOpen()
end

-- A wireless or ender modem is attached (one that reaches turtles).
function net.hasWireless()
  return peripheral.find("modem", function(_, m) return m.isWireless() end) ~= nil
end

function net.newId()
  nextId = nextId + 1
  return nextId
end

-- Send msg (given a fresh id) to computer to and wait for its answer.
-- Returns the answer, or nil if none came in time.
function net.ask(to, protocol, msg, opts)
  opts = opts or {}
  msg.id = net.newId()
  rednet.send(to, msg, protocol)
  local match = opts.match or function(reply) return reply.re == msg.type and reply.id == msg.id end
  local deadline = os.clock() + (opts.wait or 10)
  while os.clock() < deadline do
    local from, reply = rednet.receive(protocol, math.max(0.1, deadline - os.clock()))
    if from == to and type(reply) == "table" and match(reply, from) then return reply end
    if from and opts.other then opts.other(from, reply) end
  end
  return nil
end

-- Answer a request: the reply repeats its id, and re says what it answers.
function net.answer(to, protocol, request, reply)
  reply.re, reply.id = request.type, request.id
  rednet.send(to, reply, protocol)
end

---------------------------------------------------------------- peers

local Peer = {}
Peer.__index = Peer

-- The computer hosting a protocol, looked up once and remembered until it
-- goes quiet. opts: open ("wireless" or "any", which modems to open),
-- retry (seconds before looking again after nobody was found), wait
-- (default seconds to wait for answers), host (only that hostname).
function net.peer(protocol, opts)
  return setmetatable({ protocol = protocol, opts = opts or {}, notBefore = -math.huge }, Peer)
end

-- The peer's id, looking it up if need be; nil and why if there's none.
function Peer:find()
  if not net.open(self.opts.open) then return nil, "no modem" end
  if self.id then return self.id end
  if os.clock() < self.notBefore then return nil, "none" end
  self.id = rednet.lookup(self.protocol, self.opts.host)
  if not self.id then
    self.notBefore = os.clock() + (self.opts.retry or 0)
    return nil, "none"
  end
  return self.id
end

-- Ask the peer something: the answer, or nil and why ("no modem", "none",
-- "no answer"). One that doesn't answer is looked up again next time.
function Peer:ask(msg, wait)
  local id, why = self:find()
  if not id then return nil, why end
  local reply = net.ask(id, self.protocol, msg, { wait = wait or self.opts.wait })
  if not reply then
    self.id = nil
    return nil, "no answer"
  end
  return reply
end

-- Forget the peer, so the next ask looks it up again.
function Peer:forget() self.id = nil end

return net
