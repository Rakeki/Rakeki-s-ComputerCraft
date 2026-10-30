-- Mekanism machines fed through a feeder. CC can't put items into a
-- Mekanism machine (its computer port hides the slots), so each machine has
-- a feeder: a hopper on top, or a barrel or chest that a pipe (a logistical
-- transporter set to pull, a Create funnel) empties into it. The program
-- fills the feeder; the machine ejects what it makes out of its bottom
-- (set to Output with Auto-eject here when its security is Public) into a
-- storage input chest under it. Used by the enricher (Enrichment Chambers)
-- and the smelter (Energized Smelters).
--
--   local mekfeed = require("lib.mekfeed")
--   local set = mekfeed.new({ name = "smelter",           -- machines saved in /.smelter_machines
--     single = "energizedSmelter", factory = "SmeltingFactory", -- peripheral types
--     what = "smelter", title = "Smelter",                -- for messages; "Smelter 1" on the screen
--     names = config.names, setSides = true, ask = ask, tell = tell })
--   local machines = set:read()                           -- every machine and its feeder, read at once
--   local unsure, problem = set:register(work.remote)     -- tell the storage computer which barrels are feeders
--   set:unstick(machines, input, function(m, item) ... end) -- put back what doesn't go in
--   local n = set.roomFor(m, name)                        -- how many more of an item it can take
--   set:command(args)                                     -- '<program> add ...' / 'remove ...'; false if neither
--
-- Each machine: { n, entry = { machine, feeder }, title, slots, factory,
-- present, inputs[i], outputs[i] (each { name, count } or nil), energy (0-1),
-- usage, feedOk, feedSize, feedList (list()), feed (name -> count),
-- feedTotal }. Mekanism runs each method on the game's main thread, one
-- tick per call, so every call runs side by side.
local files = require("lib.files") -- crash-safe save files

local mekfeed = {}

local STACK = 64 -- items to a slot in a machine's input
local STUCK_AFTER = 60 -- seconds an item may sit in a feeder over an empty machine before it's put back
local FEEDERS_WAIT = 5 -- seconds to wait for the storage computer to take the barrel feeders
local FEEDERS_RETRY = 60 -- seconds before asking again after it didn't
-- Process slots in each tier of factory.
local FACTORY_SLOTS = { basic = 3, advanced = 5, elite = 7, ultimate = 9 }

mekfeed.STACK = STACK

local function isHopper(t) return t:find("hopper", 1, true) ~= nil end
-- What can feed a machine: a hopper, or a barrel or chest a pipe pulls
-- from (never an ender chest: its items are shared with one elsewhere).
local function isFeeder(t)
  if isHopper(t) then return true end
  return (t:find("barrel", 1, true) or t:find("chest", 1, true)) ~= nil and not t:find("ender", 1, true)
end

-- Peripherals on the wired network (not ones touching this computer: the
-- storage computer can't reach those) that pass test(type).
local function findOnNetwork(test)
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if not sides[name] and t and test(t) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- Mekanism hands over an empty slot as air with count 0.
local function stackOf(s)
  if type(s) == "table" and type(s.name) == "string" and (s.count or 0) > 0 and s.name ~= "minecraft:air" then
    return { name = s.name, count = s.count }
  end
  return nil
end

local Set = {}
Set.__index = Set

function mekfeed.new(opts)
  local self = setmetatable({}, Set)
  self.opts = opts
  self.file = ("/.%s_machines"):format(opts.name)
  self.names = opts.names or {}
  self.configured = {} -- machine -> true once its sides have been set (or tried)
  self.stuckSince = {} -- feeder -> { name, count, since }: an item not going into an empty machine
  return self
end

function Set:isMachine(t)
  return t == self.opts.single or t:find(self.opts.factory .. "$") ~= nil
end

-- The saved machines: { machine, feeder } each.
function Set:entries()
  local t = files.read(self.file)
  t = type(t) == "table" and t or {}
  -- saved by the enricher before feeders could be barrels
  for _, entry in ipairs(t) do
    entry.machine = entry.machine or entry.chamber
    entry.feeder = entry.feeder or entry.hopper
  end
  return t
end

function Set:save(t)
  files.write(self.file, t)
  os.queueEvent(self.opts.name .. "_added") -- the running program, if this is another tab
end

-- Machines on the network that aren't added yet.
function Set:free()
  local used, out = {}, {}
  for _, entry in ipairs(self:entries()) do used[entry.machine] = true end
  for _, name in ipairs(findOnNetwork(function(t) return self:isMachine(t) end)) do
    if not used[name] then out[#out + 1] = name end
  end
  return out
end

---------------------------------------------------------------- reading

local function readOne(m)
  local jobs = {}
  local function call(method, ...)
    local ok, v = pcall(peripheral.call, m.entry.machine, method, ...)
    return ok and v or nil
  end
  for i = 1, m.slots do
    jobs[#jobs + 1] = function()
      if m.factory then
        m.inputs[i], m.outputs[i] = stackOf(call("getInput", i - 1)), stackOf(call("getOutput", i - 1))
      else
        m.inputs[i], m.outputs[i] = stackOf(call("getInput")), stackOf(call("getOutput"))
      end
    end
  end
  jobs[#jobs + 1] = function() m.energy = call("getEnergyFilledPercentage") end
  jobs[#jobs + 1] = function() m.usage = call("getEnergyUsage") end
  jobs[#jobs + 1] = function()
    local ok, list = pcall(peripheral.call, m.entry.feeder, "list")
    local okS, size = pcall(peripheral.call, m.entry.feeder, "size")
    m.feedOk = ok and type(list) == "table"
    m.feedSize = okS and size or 0
    m.feedList = m.feedOk and list or {}
    for _, item in pairs(m.feedList) do
      m.feed[item.name] = (m.feed[item.name] or 0) + item.count
      m.feedTotal = m.feedTotal + item.count
    end
  end
  parallel.waitForAll(table.unpack(jobs))
end

-- Set the machine's bottom to Output and turn Auto-eject on, once. Only
-- works when its security is Public.
function Set:configure(m)
  local name = m.entry.machine
  if self.configured[name] ~= nil or self.opts.setSides == false then return end
  local okM, mode = pcall(peripheral.call, name, "getMode", "ITEM", "BOTTOM")
  if okM and mode ~= "OUTPUT" then okM = pcall(peripheral.call, name, "setMode", "ITEM", "BOTTOM", "OUTPUT") end
  local okE, ejecting = pcall(peripheral.call, name, "isEjecting", "ITEM")
  if okE and not ejecting then okE = pcall(peripheral.call, name, "setEjecting", "ITEM", true) end
  self.configured[name] = okM and okE
  if not self.configured[name] and self.opts.tell then
    self.opts.tell(("Couldn't set %s's sides: make it Public, or set Bottom to Output and Auto-eject on by hand.")
      :format(m.title), "orange")
  end
end

-- Every saved machine with its feeder, read at once, and its sides set.
function Set:read()
  local list = {}
  for i, entry in ipairs(self:entries()) do
    local t = peripheral.getType(entry.machine) or ""
    local tier = t:match("^(%l+)" .. self.opts.factory .. "$")
    list[i] = { n = i, entry = entry, title = self.names[entry.machine] or ("%s %d"):format(self.opts.title, i),
      slots = tier and (FACTORY_SLOTS[tier] or 3) or 1, factory = tier ~= nil,
      present = peripheral.isPresent(entry.machine), inputs = {}, outputs = {}, feed = {}, feedList = {},
      feedTotal = 0, feedSize = 0 }
  end
  local reads = {}
  for _, m in ipairs(list) do
    if m.present then reads[#reads + 1] = function() readOne(m) end end
  end
  if #reads > 0 then parallel.waitForAll(table.unpack(reads)) end
  for _, m in ipairs(list) do
    if m.present then self:configure(m) end
  end
  return list
end

-- Powered, with a feeder that answers: ready to be fed.
function mekfeed.ready(m) return m.present and m.feedOk and (m.energy or 0) > 0 end

-- How much more of an item the machine's input slots can take (an empty
-- slot a stack, one holding the item the rest of its stack), less what's
-- waiting in the feeder.
function mekfeed.roomFor(m, name)
  local room = 0
  for i = 1, m.slots do
    local s = m.inputs[i]
    if not s then room = room + STACK elseif s.name == name then room = room + STACK - s.count end
  end
  return room - (m.feed[name] or 0)
end

-- How many of an item (nil: of anything) are in its input slots.
function mekfeed.inputOf(m, name)
  local n = 0
  for i = 1, m.slots do
    local s = m.inputs[i]
    if s and (not name or s.name == name) then n = n + s.count end
  end
  return n
end

-- The most a feeder may be sent of an item this round.
function mekfeed.space(m, name)
  return math.min(mekfeed.roomFor(m, name), m.feedSize * STACK - m.feedTotal)
end

-- What's in the feeder, else (a single machine has one slot) what's in the
-- machine; nil when it's free to take anything.
function mekfeed.current(m)
  local _, inFeed = next(m.feedList)
  if inFeed then return inFeed.name end
  if not m.factory and m.inputs[1] then return m.inputs[1].name end
  return nil
end

-- An output slot is full: what it makes isn't going anywhere.
function mekfeed.full(m)
  for i = 1, m.slots do
    if m.outputs[i] and m.outputs[i].count >= STACK then return true end
  end
  return false
end

-- Note a feeder was sent n of an item.
function mekfeed.added(m, name, n)
  m.feed[name] = (m.feed[name] or 0) + n
  m.feedTotal = m.feedTotal + n
end

---------------------------------------------------------------- the storage computer

-- A barrel or chest on the storage cable would be storage to the storage
-- computer (it'd put things in it and count what's in it): tell it which
-- are feeders ('feeders'), and fill none of them until it has said yes.
-- Far away (remote) the feeders aren't on its cable. Returns the feeders
-- not to fill (feeder -> true) and why, if any.
function Set:register(remote)
  local unsure = {}
  if remote then return unsure end
  local list = {}
  for _, entry in ipairs(self:entries()) do
    -- whether or not its machine is there: a missing machine's barrel isn't storage either
    local t = peripheral.isPresent(entry.feeder) and peripheral.getType(entry.feeder)
    if t and not isHopper(t) then list[#list + 1] = entry.feeder end
  end
  table.sort(list)
  local key, now = table.concat(list, ","), os.clock()
  if key ~= self.feedersKey and now >= (self.feedersRetry or 0) then
    -- an old storage computer doesn't answer at all: don't wait long, nor every round
    local r, why = self.opts.ask({ type = "feeders", chests = list }, FEEDERS_WAIT)
    -- hoppers only: nothing to hold back, even if it didn't take the empty list
    if r and r.ok or #list == 0 then
      self.feedersKey = key
    else
      self.feedersRetry = now + FEEDERS_RETRY
      self.feedersProblem = r and r.error or why == "the storage computer didn't answer"
        and "the storage computer doesn't know about barrel feeders: 'install update' it" or why
    end
  end
  if key == self.feedersKey then return unsure end
  for _, name in ipairs(list) do unsure[name] = true end
  return unsure, self.feedersProblem
end

-- An item sitting in a feeder over an empty, powered machine doesn't go in
-- (the machine doesn't take it, or nothing moves it in): after a minute it
-- goes back to input, and putBack(m, item) is told.
function Set:unstick(machines, input, putBack)
  local now = os.clock()
  for _, m in ipairs(machines) do
    local _, item = next(m.feedList)
    local feeder = m.entry.feeder
    local s = self.stuckSince[feeder]
    if item and mekfeed.inputOf(m) == 0 and (m.energy or 0) > 0 then
      if s and s.name == item.name and m.feed[item.name] >= s.count then
        if now - s.since > STUCK_AFTER and input then
          for slot in pairs(m.feedList) do pcall(peripheral.call, feeder, "pushItems", input, slot) end
          putBack(m, item)
          m.feedList, m.feed, m.feedTotal, self.stuckSince[feeder] = {}, {}, 0, nil
        end
      else
        self.stuckSince[feeder] = { name = item.name, count = m.feed[item.name], since = now }
      end
    else
      self.stuckSince[feeder] = nil
    end
  end
end

---------------------------------------------------------------- commands

-- Pick from a numbered list (or type a name); nil if cancelled.
local function choose(question, options)
  for i, o in ipairs(options) do print(("%2d  %s"):format(i, o)) end
  write(question .. " ")
  local text = read()
  if text == "" then return nil end
  return options[tonumber(text)] or text
end

local function isEmpty(name)
  local ok, items = pcall(peripheral.call, name, "list")
  return ok and type(items) == "table" and next(items) == nil
end

function Set:list()
  local list = self:entries()
  if #list == 0 then print(("No %ss yet. Add one with '%s add'."):format(self.opts.what, self.opts.name)) end
  for i, entry in ipairs(list) do
    print(("%d  %s: %s, fed by %s"):format(i, self.names[entry.machine] or ("%s %d"):format(self.opts.title, i),
      entry.machine, entry.feeder))
  end
end

function Set:add(machine, feeder)
  local list = self:entries()
  local used = {}
  for _, entry in ipairs(list) do used[entry.machine], used[entry.feeder] = true, true end
  if not machine or not feeder then print("Right-click a modem to see its block's name.") end
  if not machine then
    local machines = self:free()
    if #machines == 0 then
      print(("No %s on the network that isn't added already. Put a wired modem on it, join it to the cable and right-click it.")
        :format(self.opts.what))
      return
    end
    print(("The %s (or factory):"):format(self.opts.what:upper()))
    machine = #machines == 1 and machines[1] or choose("Which? (Enter to cancel)", machines)
    if not machine then return end
    if #machines == 1 then print(machine) end
  end
  if not feeder then
    -- every storage chest is a barrel or chest too: only empty ones are offered
    local feeders = {}
    for _, name in ipairs(findOnNetwork(isFeeder)) do
      if not used[name] and (isHopper(peripheral.getType(name)) or isEmpty(name)) then feeders[#feeders + 1] = name end
    end
    if #feeders == 0 then
      print(("Nothing free to feed it. Put a hopper on top of the %s, pointing down, or an empty barrel a pipe pulls from into it, with a wired modem on it joined to the cable.")
        :format(self.opts.what))
      return
    end
    print("What FEEDS it: the hopper on top of it, pointing down, or the barrel a pipe pulls from into it:")
    feeder = choose("Which? (Enter to cancel)", feeders)
    if not feeder then return end
  end
  if used[machine] or used[feeder] then print("That one is already added.") return end
  for _, name in ipairs({ machine, feeder }) do
    if not peripheral.isPresent(name) then print(name .. " isn't on the network.") return end
  end
  if not self:isMachine(peripheral.getType(machine) or "") then
    print(("%s isn't an %s."):format(machine, self.opts.what))
    return
  end
  local feederType = peripheral.getType(feeder) or ""
  if not isFeeder(feederType) then print(feeder .. " isn't a hopper, barrel or chest.") return end
  if not isHopper(feederType) and not isEmpty(feeder) then
    print(feeder .. " has items in it: empty it first (it might be a storage chest).")
    return
  end

  list[#list + 1] = { machine = machine, feeder = feeder }
  self:save(list)
  print(("%s %d added: %s, fed by %s."):format(self.opts.title, #list, machine, feeder))
  if not isHopper(feederType) then
    print("Something has to move its items into the machine: a logistical transporter set to pull, or a funnel.")
    print("The storage computer stops using it as storage once the program is running.")
  end
  print("Put a storage input chest under it (add it in 'storage setup'): what it makes comes out there.")
end

-- '<program> add [machine feeder]' and '<program> remove <n>': true if
-- args was one of them (and it's been done).
function Set:command(args)
  if args[1] == "add" then
    self:add(args[2], args[3])
    return true
  elseif args[1] == "remove" then
    local list = self:entries()
    local n = tonumber(args[2] or "")
    if not n or not list[n] then
      self:list()
      print(("Usage: %s remove <%s number>"):format(self.opts.name, self.opts.what))
      return true
    end
    local entry = table.remove(list, n)
    self:save(list)
    print(("Forgot %s. Empty its feeder by hand."):format(entry.machine))
    return true
  end
  return false
end

return mekfeed
