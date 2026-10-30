-- Hands a building to the builder turtles (computers/builder-turtle) and
-- keeps track of them: the building is split into side-by-side strips across
-- its longer side, one per builder turtle in range (up to 4, busy ones
-- too), each turtle building its strip bottom layer up and crossing over at
-- a height of its own. The free ones start straight away; a strip nobody
-- could take yet goes to the next turtle that's free: one that finishes its
-- own strip, or one that's free when it looks again. Used by the blueprint
-- projector and build-control.
--
--   local crew = require("lib.crew")
--   local c = crew.new({
--     job = function() return { id, name, mats, blocks, area, clear } end, -- world coords (lib/plan.lua's world/area)
--     build = saved.build,               -- a build in progress after a restart, or nil
--     save = function(build) ... end,    -- keep it (nil once done) so a restart picks it up
--     tell = function(text) ... end,     -- what's going on, for the screen
--     changed = function() ... end,      -- optional: a builder said how far it's got
--     finished = function(text) ... end, -- optional: every strip is done or stopped
--   })
--   c:start()       -- or os.queueEvent(crew.START) from a UI handler
--   c:stop()        -- or os.queueEvent(crew.STOP); asked twice, gives up on silent turtles
--   c:run()         -- the loop: hears the turtles and hands out waiting strips (in parallel with the rest)
--   c.build, c:note(), c:lowY(), c:needs()
local net = require("lib.net")

local crew = {}

crew.PROTOCOL = "projector_build" -- builder turtles take buildings, and send progress, on this
crew.START, crew.STOP = "crew_start", "crew_stop" -- events a UI queues to start or stop the build
local MORE = "crew_more" -- a builder finished its strip and is free for another
local WAIT = 5 -- seconds to wait for each builder turtle to answer
local MAX_BUILDERS = 4 -- most builder turtles one building is split between
local MIN_STRIP = 3 -- narrowest strip of a building (blocks) one turtle is given
local RETRY_EVERY = 30 -- seconds between offers of strips nobody has taken yet to builders that are free
crew.TOP = 319 -- the build limit: builders fly over a building, so its top has to stay below this

local Crew = {}
Crew.__index = Crew

-- Why a building in this box can't be built by n builders, or nil: they
-- cross over it 2 blocks above its top, each a block higher than the last,
-- and can't go above the build limit.
function crew.tooHigh(area, n)
  local need = area.y1 + 2 + math.max(0, (n or 1) - 1)
  if need <= crew.TOP then return nil end
  return ("Too high: its top is at Y %d, and the builders fly over it up to Y %d, above the build limit (Y %d). Lower it by %d block%s."):format(
    area.y1, need, crew.TOP, need - crew.TOP, need - crew.TOP == 1 and "" or "s")
end

-- build, while builder turtles are building: { key, name, n (strips),
-- stopping, parts = { { key, builder, finished, stopped, stage, done, total,
-- y, skipped, note, cleared, toClear } } }, one part per strip, filled in
-- from its turtle's progress messages.
function crew.new(opts)
  local c = setmetatable({ opts = opts, build = opts.build }, Crew)
  local b = c.build
  -- a build saved by an older projector (one turtle, no strips) as one strip
  if b and not b.parts then
    c.build = { key = b.key, name = b.name, n = 1, parts = { {
      key = b.key, builder = b.builder, stage = b.stage, done = b.done, total = b.total, y = b.y,
      skipped = b.skipped, note = b.note, cleared = b.cleared, toClear = b.toClear } } }
  end
  return c
end

function Crew:tell(text) self.opts.tell(text) end
function Crew:save() self.opts.save(self.build) end

---------------------------------------------------------------- strips

-- Strip i of n: the area cut across its longer side.
local function stripBox(a, i, n)
  local alongX = a.x1 - a.x0 >= a.z1 - a.z0
  local lo, hi = alongX and a.x0 or a.z0, alongX and a.x1 or a.z1
  local len = hi - lo + 1
  local s0 = lo + math.floor((i - 1) * len / n)
  local s1 = lo + math.floor(i * len / n) - 1
  if alongX then return { x0 = s0, x1 = s1, z0 = a.z0, z1 = a.z1 } end
  return { x0 = a.x0, x1 = a.x1, z0 = s0, z1 = s1 }
end

-- How many strips for this many builder turtles: no more than MAX_BUILDERS,
-- and none narrower than MIN_STRIP.
local function stripCount(a, builders)
  local len = math.max(a.x1 - a.x0, a.z1 - a.z0) + 1
  return math.max(1, math.min(builders, MAX_BUILDERS, math.floor(len / MIN_STRIP)))
end

-- The blocks in a strip.
local function stripBlocks(blocks, part)
  local mine = {}
  for _, b in ipairs(blocks) do
    if b[1] >= part.x0 and b[1] <= part.x1 and b[3] >= part.z0 and b[3] <= part.z1 then mine[#mine + 1] = b end
  end
  return mine
end

function Crew:partFor(key)
  for i, p in ipairs(self.build and self.build.parts or {}) do
    if p.key == key then return p, i end
  end
end

function Crew:pending()
  local n = 0
  for _, p in ipairs(self.build.parts) do
    if not p.builder and not p.finished then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------- progress

-- What the builders are up to, in a line.
function Crew:note()
  local parts = self.build.parts
  if #parts > 1 then
    local done, total, working, waiting = 0, 0, 0, 0
    for _, p in ipairs(parts) do
      total = total + (p.total or 0)
      if p.finished then
        done = done + (p.total or 0)
      elseif p.builder then
        working = working + 1
        done = done + (p.stage == "build" and p.done or 0)
      else
        waiting = waiting + 1
      end
    end
    local text = ("%d builder%s: %d of %d (%d%%)"):format(working, working == 1 and "" or "s", done, total,
      total > 0 and math.floor(done / total * 100) or 0)
    if self.build.stopping then text = text .. ", stopping" end
    if waiting > 0 then text = text .. (", %d strips waiting"):format(waiting) end
    return text
  end
  local b = parts[1]
  local who = ("Builder #%s: "):format(tostring(b.builder))
  if b.stage == "build" and b.total and b.total > 0 then
    return who .. ("building, %d of %d (%d%%)"):format(b.done or 0, b.total, math.floor((b.done or 0) / b.total * 100))
  elseif b.stage == "clear" and b.toClear and b.toClear > 0 then
    return who .. ("clearing the plot, %d%%"):format(math.floor((b.cleared or 0) / b.toClear * 100))
  elseif b.stage == "waiting" or b.stage == "restocking" then
    return who .. (b.note or "fetching blocks")
  end
  return who .. "starting"
end

-- What each builder is doing and, while it waits or restocks, the items it
-- needs now: { { builder, stage, note, need = { [item] = n } or nil } }.
function Crew:needs()
  local out = {}
  for _, p in ipairs(self.build and self.build.parts or {}) do
    if p.builder and not p.finished then
      out[#out + 1] = { builder = p.builder, stage = p.stage, note = p.note, need = p.need }
    end
  end
  table.sort(out, function(a, b) return a.builder < b.builder end)
  return out
end

-- The lowest layer (world y) any builder is building, or nil.
function Crew:lowY()
  local low
  for _, q in ipairs(self.build and self.build.parts or {}) do
    if q.y and not q.finished and q.stage == "build" then low = math.min(low or q.y, q.y) end
  end
  return low
end

-- Every strip is finished (built, stopped, or given up on): say how it went.
function Crew:finish()
  local b = self.build
  local skipped, stopped, builders = 0, false, {}
  for _, p in ipairs(b.parts) do
    skipped = skipped + (p.skipped or 0)
    stopped = stopped or p.stopped
    if p.builder then builders[#builders + 1] = "#" .. p.builder end
  end
  local who = #builders == 1 and ("Builder " .. builders[1]) or ("Builders " .. table.concat(builders, ", "))
  local text
  if stopped then
    text = ("%s stopped."):format(who)
  elseif skipped > 0 then
    text = ("%s built %s, but skipped %d blocks."):format(who, b.name, skipped)
  else
    text = ("%s built %s."):format(who, b.name)
  end
  self.build = nil
  self:save()
  self:tell(text)
  if self.opts.finished then self.opts.finished(text) end
end

-- Progress from a builder turtle building one of the strips.
function Crew:onBuilder(from, msg)
  if type(msg) ~= "table" or msg.type ~= "progress" or not self.build then return end
  local p = self:partFor(msg.key)
  if not p then return end
  p.stage, p.done, p.total, p.y, p.skipped, p.note = msg.stage, msg.done, msg.total, msg.y, msg.skipped, msg.note
  p.cleared, p.toClear, p.builder = msg.cleared, msg.toClear, from
  -- what it's waiting for or fetching: only while it is
  p.need = (msg.stage == "waiting" or msg.stage == "restocking") and type(msg.need) == "table" and msg.need or nil
  if msg.stage == "done" or msg.stage == "stopped" then
    p.finished, p.stopped = true, msg.stage == "stopped"
    -- free again: it can take a strip nobody has yet
    if not p.stopped and not self.build.stopping and self:pending() > 0 then os.queueEvent(MORE, from) end
    for _, q in ipairs(self.build.parts) do
      if not q.finished then
        self:save()
        if self.opts.changed then self.opts.changed() end
        return
      end
    end
    return self:finish()
  end
  self:save()
  if self.opts.changed then self.opts.changed() end
end

---------------------------------------------------------------- handing out

-- The builder turtles that answer and aren't building anything: ids, and
-- how many there are in all.
function Crew:freeBuilders()
  local ids = { rednet.lookup(crew.PROTOCOL) }
  if #ids == 0 then return {}, 0 end
  local probe = ("free-%d"):format(os.epoch("utc"))
  for _, id in ipairs(ids) do rednet.send(id, { type = "status", id = 0, key = probe }, crew.PROTOCOL) end
  local free, seen = {}, {}
  local deadline = os.clock() + WAIT
  while os.clock() < deadline and #free < #ids do
    local from, msg = rednet.receive(crew.PROTOCOL, math.max(0.1, deadline - os.clock()))
    if from and type(msg) == "table" and msg.type == "idle" and msg.key == probe and not seen[from] then
      seen[from] = true
      free[#free + 1] = from
    elseif from then
      self:onBuilder(from, msg)
    end
  end
  table.sort(free)
  return free, #ids
end

-- Offer strip i to builder id. True if it took it, or false and why not.
function Crew:offer(i, id)
  local b = self.build
  local p = b.parts[i]
  local job = self.opts.job()
  local part = stripBox(job.area, i, b.n)
  local blocks = stripBlocks(job.blocks, part)
  -- the turtle answers accepted, busy or refused, with the strip's key
  local msg = net.ask(id, crew.PROTOCOL, { type = "build", key = p.key,
    name = b.n > 1 and ("%s (strip %d of %d)"):format(b.name, i, b.n) or b.name,
    mats = job.mats, blocks = blocks, area = job.area, part = b.n > 1 and part or nil, lane = i - 1,
    clear = job.clear },
    { wait = WAIT, match = function(reply) return reply.key == p.key and reply.type ~= "progress" end,
      other = function(from, m) self:onBuilder(from, m) end })
  if not msg then return false, ("Builder #%d didn't answer in time."):format(id) end
  if msg.type == "accepted" then
    p.builder, p.stage, p.done, p.total = id, "clear", 0, #blocks
    return true
  end
  return false, ("Builder #%d %s"):format(id, msg.type == "busy" and ("is busy with " .. tostring(msg.name))
    or ("refused: " .. tostring(msg.why)))
end

-- Give the strips nobody has yet to these free builders, one each.
-- Returns how many were taken, and why the last one wasn't.
function Crew:handOut(ids)
  local taken, why, k = 0, nil, 1
  for i, p in ipairs(self.build.parts) do
    if not p.builder and not p.finished then
      while k <= #ids do
        local id = ids[k]
        k = k + 1
        local ok, err = self:offer(i, id)
        if ok then
          taken = taken + 1
          break
        end
        why = err
      end
    end
  end
  return taken, why
end

-- Split the job between the builder turtles that are free. True if any
-- took a strip.
function Crew:start()
  if self.build then return self:tell("Already building: stop it first.") end
  if not net.open() then return self:tell("Needs a wireless or ender modem to reach the builder turtles.") end
  self:tell("Looking for free builder turtles...")
  local free, all = self:freeBuilders()
  if all == 0 then return self:tell("No builder turtle answered: is one running 'builder' nearby?") end
  if #free == 0 then return self:tell(("All %d builder turtles are busy."):format(all)) end
  local job = self.opts.job()
  -- a strip for every builder in range, busy ones too: one that's busy now
  -- takes a waiting strip when it's done, so it isn't left out of the work
  local n = stripCount(job.area, all)
  local high = crew.tooHigh(job.area, n)
  if high then return self:tell(high) end
  local key = ("%d-%s"):format(os.epoch("utc"), job.id or "plan")
  self.build = { key = key, name = job.name, n = n, parts = {} }
  for i = 1, n do
    local empty = #stripBlocks(job.blocks, stripBox(job.area, i, n)) == 0
    -- a strip with nothing in it needs no turtle (the plan has a gap there)
    self.build.parts[i] = { key = ("%s/%d"):format(key, i), total = 0, finished = empty }
  end
  self:tell(n > 1 and ("Sending %d blocks to %d builder turtles..."):format(#job.blocks, n)
    or ("Sending %d blocks to a builder turtle..."):format(#job.blocks))
  local taken, why = self:handOut(free)
  if taken == 0 then
    self.build = nil
    return self:tell(why or "No builder turtle took it.")
  end
  self:save()
  local left = self:pending()
  if n == 1 then
    self:tell(("Builder #%d is building %s."):format(self.build.parts[1].builder, job.name))
  else
    self:tell(("%d builder turtles are building %s%s."):format(taken, job.name,
      left > 0 and (", %d strips wait for the next free one"):format(left) or ""))
  end
  return true
end

function Crew:stop()
  local b = self.build
  if not b then return end
  if b.stopping then
    -- asked twice: a turtle that never answers (broken, unloaded) is given up on
    for _, p in ipairs(b.parts) do
      if not p.finished then p.finished, p.stopped = true, true end
    end
    return self:finish()
  end
  b.stopping = true
  local asked = 0
  for _, p in ipairs(b.parts) do
    if p.builder and not p.finished then
      if net.open() then rednet.send(p.builder, { type = "stop", id = 0, key = p.key }, crew.PROTOCOL) end
      asked = asked + 1
    elseif not p.finished then
      p.finished, p.stopped = true, true -- nobody had started it
    end
  end
  if asked == 0 then return self:finish() end
  self:save()
  self:tell(asked == 1 and "Asked the builder to stop..." or ("Asked %d builders to stop..."):format(asked))
end

-- Starts and stops builds asked for with crew.START / crew.STOP, hears
-- progress, and hands out strips nobody has taken yet.
function Crew:run()
  -- after a restart, ask the turtles where they've got to
  if self.build and net.open() then
    for _, p in ipairs(self.build.parts) do
      if p.builder and not p.finished then
        rednet.send(p.builder, { type = "status", id = 0, key = p.key }, crew.PROTOCOL)
      end
    end
  end
  local retry = os.startTimer(RETRY_EVERY)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == crew.START and not self.build then
      self:start()
    elseif ev[1] == crew.STOP and self.build then
      self:stop()
    elseif ev[1] == "rednet_message" and ev[4] == crew.PROTOCOL then
      self:onBuilder(ev[2], ev[3])
    elseif ev[1] == MORE and self.build and not self.build.stopping and self:pending() > 0 then
      if self:handOut({ ev[2] }) > 0 then
        self:save()
        if self.opts.changed then self.opts.changed() end
      end
    elseif ev[1] == "timer" and ev[2] == retry then
      -- strips still waiting: offer them to any builder that's free now
      if self.build and not self.build.stopping and self:pending() > 0 and net.open() then
        local free = self:freeBuilders()
        if #free > 0 and self:handOut(free) > 0 then
          self:save()
          if self.opts.changed then self.opts.changed() end
        end
      end
      retry = os.startTimer(RETRY_EVERY)
    end
  end
end

return crew
