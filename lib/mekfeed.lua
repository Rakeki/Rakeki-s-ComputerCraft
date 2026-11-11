-- Mekanism machines fed through a feeder. CC can't put items into a
-- Mekanism machine (its computer port hides the slots), so each machine has
-- a feeder: a hopper on top, or a barrel or chest that a pipe (a logistical
-- transporter set to pull, a Create funnel) empties into it. The program
-- fills the feeder; the machine ejects what it makes out of its bottom
-- (set to Output with Auto-eject here when its security is Public) into the
-- chest under it: its own output chest, which the program empties into
-- storage each round (collect), or a storage input chest. Used by the
-- factory's enricher (Enrichment Chambers) and smelter (Energized Smelters).
--
--   local mekfeed = require("lib.mekfeed")
--   local set = mekfeed.new({ name = "smelter",           -- machines saved in /.smelter_machines
--     single = "energizedSmelter", factory = "SmeltingFactory", -- peripheral types
--     what = "smelter", title = "Smelter",                -- for messages; "Smelter 1" on the screen
--     names = config.names, setSides = true, ask = ask, tell = tell,
--     far = function() return work.remote end,           -- far from storage: chests with items in can be picked
--     lines = { "blast", "smoke" }, pageTitle = "Smelters and fans" }) -- Create lines too (optional)
--   local machines = set:read()                           -- every machine and its feeder, read at once
--   local unsure, problem = set:register(work.remote)     -- tell the storage computer which barrels are feeders
--   mekfeed.register({ setA, setB }, work.remote)         -- the same for several sets on one computer (the
--                                                         -- storage computer keeps one feeder list per computer)
--   set:unstick(machines, input, function(m, item) ... end) -- put back what doesn't go in
--   local moved, stuck = set:collect(machines, input)    -- output chests into storage
--   local n = set.roomFor(m, name)                        -- how many more of an item it can take
--   set:command(args)                                     -- '<program> add ...' / 'remove ...'; false if neither
--   ui:open(set:setupPage(ui))                            -- the machines on a lib/setupui.lua setup screen
--   local parts = set:setupParts(ui)                      -- or its rows, to put on a page of your own:
--                                                         -- parts.entries() (each machine), parts.adds() (+ Add rows)
--
-- More opts: cmd (the command in printed hints, default name), event (queued
-- when the list changes, default name .. "_added"), taken(name) (another
-- computer's: left out of what can be added), sides (the item side config
-- set on each machine, default { BOTTOM = "OUTPUT" }), extra (a second
-- feeder for the machine's extra slot: { title, hint }, the Metallurgic
-- Infuser's infusion items), needOutput (an output chest has to be picked:
-- what comes out is counted), read(m, call) (more reads for each machine:
-- a list of functions, run alongside the rest), lineRows(ui, i, entry,
-- change(field, value, text)) (more rows on a Create line's setup page,
-- e.g. the saw's filter, saved in its entry by change).
--
-- Each machine: { n, entry = { machine, feeder, output (nil: none), extra },
-- title, slots, factory, present, inputs[i], outputs[i] (each { name,
-- count } or nil), energy (0-1), usage, feedOk, feedSize, feedList
-- (list()), feed (name -> count), feedTotal, outOk (true without an output
-- chest), outList; with opts.extra the same for the second feeder: extraOk,
-- extraSize, extraList, extraFeed, extraTotal }. Mekanism runs each method
-- on the game's main thread, one tick per call, so every call runs side by
-- side.
--
-- A set can also hold Create lines (opts.lines = { "crush" } etc., kinds
-- in mekfeed.LINES): Create's crushing wheels, saws and fans aren't peripherals
-- at all, so a line is only its feeder (a funnel or chute empties it into
-- the machine) and the chest what it makes ends up in. Its entry is
-- { line = kind, feeder, output }, and as a machine it has line = kind,
-- slots = 0, no energy, moving (its feeder went down or something came out
-- since last round) and stalled (its feeder hasn't gone down for a minute).
local files = require("lib.files") -- crash-safe save files

local mekfeed = {}

local STACK = 64 -- items to a slot in a machine's input
local STUCK_AFTER = 60 -- seconds an item may sit in a feeder over an empty machine before it's put back
local FEEDERS_WAIT = 5 -- seconds to wait for the storage computer to take the barrel feeders
local FEEDERS_RETRY = 60 -- seconds before asking again after it didn't
local LINE_FILL = 64 -- items kept waiting in a Create line's feeder (opts.lineFill)
local LINE_STUCK = 60 -- seconds a Create line's feeder may sit without going down before it shows as not moving
-- Process slots in each tier of factory.
local FACTORY_SLOTS = { basic = 3, advanced = 5, elite = 7, ultimate = 9 }
-- Create lines: word (typed after 'add'), title (on the screen), what (in
-- messages), feeds / out (what to pick as its feeder and output chest),
-- needOutput (it must have an output chest: what comes out is counted).
local LINES = {
  crush = { word = "crusher", title = "Crusher", what = "crushing line",
    feeds = "The chest a funnel or chute empties onto its crushing wheels.",
    out = "The chest what it crushes ends up in." },
  wash = { word = "washer", title = "Washer", what = "washing fan",
    feeds = "The chest a funnel empties onto the belt past the fan (blowing through water).",
    out = "The chest at the end of the belt." },
  blast = { word = "fan", title = "Blast fan", what = "blasting fan",
    feeds = "The chest a funnel empties onto the belt past the fan (blowing through lava).",
    out = "The chest at the end of the belt." },
  smoke = { word = "smokefan", title = "Smoke fan", what = "smoking fan",
    feeds = "The chest a funnel empties onto the belt past the fan (blowing through fire).",
    out = "The chest at the end of the belt." },
  saw = { word = "saw", title = "Saw", what = "sawing line", needOutput = true,
    feeds = "The chest a funnel empties onto the belt into the saw (facing up, in line with the belt).",
    out = "The chest the saw puts things out into, by a belt or chute: what it cuts is counted there." },
}

mekfeed.STACK = STACK
mekfeed.LINES = LINES

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
  self.lineFeed = {} -- a Create line's feeder -> { total (after last round's filling), since (last moved) }
  return self
end

-- The Create line kind a word typed after 'add' names ("crusher"), if this set has it.
function Set:lineWord(word)
  for _, kind in ipairs(self.opts.lines or {}) do
    if LINES[kind] and LINES[kind].word == word then return kind end
  end
  return nil
end

-- Each saved entry's title: its name from config, else "Chamber 2" or
-- "Crusher 1", counted per kind.
function Set:titles(list)
  local out, count = {}, {}
  for i, entry in ipairs(list) do
    local kind = entry.line or ""
    count[kind] = (count[kind] or 0) + 1
    local title = entry.line and (LINES[entry.line] or LINES.crush).title or self.opts.title
    out[i] = self.names[entry.machine or entry.feeder] or ("%s %d"):format(title, count[kind])
  end
  return out
end

function Set:isMachine(t)
  if not self.opts.single then return false end -- a set of Create lines only (the saw)
  return t == self.opts.single or t:find(self.opts.factory .. "$") ~= nil
end

-- The saved machines: { machine, feeder, output } each.
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
  os.queueEvent(self.opts.event or (self.opts.name .. "_added")) -- the running program, if this is another tab
end

-- Another computer's (opts.taken): never offered here.
function Set:taken(name)
  return self.opts.taken ~= nil and self.opts.taken(name) or false
end

-- Machines on the network that aren't added yet (here or by another computer).
function Set:free()
  local used, out = {}, {}
  for _, entry in ipairs(self:entries()) do
    if entry.machine then used[entry.machine] = true end
  end
  for _, name in ipairs(findOnNetwork(function(t) return self:isMachine(t) end)) do
    if not used[name] and not self:taken(name) then out[#out + 1] = name end
  end
  return out
end

-- Every peripheral its machines use: machines, feeders and output chests.
function Set:uses()
  local out = {}
  for _, entry in ipairs(self:entries()) do
    for _, name in ipairs({ entry.machine or false, entry.feeder or false, entry.output or false, entry.extra or false }) do
      if name then out[#out + 1] = name end
    end
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
  if not m.line then
    jobs[#jobs + 1] = function() m.energy = call("getEnergyFilledPercentage") end
    jobs[#jobs + 1] = function() m.usage = call("getEnergyUsage") end
  end
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
  if m.entry.extra then
    jobs[#jobs + 1] = function()
      local ok, list = pcall(peripheral.call, m.entry.extra, "list")
      local okS, size = pcall(peripheral.call, m.entry.extra, "size")
      m.extraOk = ok and type(list) == "table"
      m.extraSize = okS and size or 0
      m.extraList = m.extraOk and list or {}
      for _, item in pairs(m.extraList) do
        m.extraFeed[item.name] = (m.extraFeed[item.name] or 0) + item.count
        m.extraTotal = m.extraTotal + item.count
      end
    end
  end
  if m.more then
    for _, job in ipairs(m.more(m, call)) do jobs[#jobs + 1] = job end
  end
  if m.entry.output then
    jobs[#jobs + 1] = function()
      local ok, list = pcall(peripheral.call, m.entry.output, "list")
      m.outOk = ok and type(list) == "table"
      m.outList = m.outOk and list or {}
    end
  end
  parallel.waitForAll(table.unpack(jobs))
end

-- Set the machine's item sides (opts.sides: its bottom to Output) and turn
-- Auto-eject on, once. Only works when its security is Public.
local SIDE_ORDER = { "TOP", "BOTTOM", "FRONT", "BACK", "LEFT", "RIGHT" }
function Set:configure(m)
  local name = m.entry.machine
  if self.configured[name] ~= nil or self.opts.setSides == false then return end
  local sides = self.opts.sides or { BOTTOM = "OUTPUT" }
  local okM = true
  for _, side in ipairs(SIDE_ORDER) do
    local want = sides[side]
    if want and okM then
      local ok, mode = pcall(peripheral.call, name, "getMode", "ITEM", side)
      if ok and mode ~= want then ok = pcall(peripheral.call, name, "setMode", "ITEM", side, want) end
      okM = ok
    end
  end
  local okE, ejecting = pcall(peripheral.call, name, "isEjecting", "ITEM")
  if okE and not ejecting then okE = pcall(peripheral.call, name, "setEjecting", "ITEM", true) end
  self.configured[name] = okM and okE
  if not self.configured[name] and self.opts.tell then
    self.opts.tell(("Couldn't set %s's sides: make it Public, or set %s and Auto-eject on by hand.")
      :format(m.title, self.opts.sidesText or "Bottom to Output"), "orange")
  end
end

-- Every saved machine with its feeder, read at once, and its sides set.
function Set:read()
  local list = {}
  local entries = self:entries()
  local titles = self:titles(entries)
  for i, entry in ipairs(entries) do
    if entry.line then
      -- a Create line: there's only its feeder to see
      list[i] = { n = i, entry = entry, line = entry.line, title = titles[i], slots = 0, factory = false,
        fill = self.opts.lineFill or LINE_FILL, present = peripheral.isPresent(entry.feeder), inputs = {},
        outputs = {}, feed = {}, feedList = {}, feedTotal = 0, feedSize = 0, outOk = entry.output == nil, outList = {} }
    else
      local t = peripheral.getType(entry.machine) or ""
      local tier = t:match("^(%l+)" .. self.opts.factory .. "$")
      list[i] = { n = i, entry = entry, title = titles[i],
        slots = tier and (FACTORY_SLOTS[tier] or 3) or 1, factory = tier ~= nil,
        present = peripheral.isPresent(entry.machine), inputs = {}, outputs = {}, feed = {}, feedList = {},
        feedTotal = 0, feedSize = 0, outOk = entry.output == nil, outList = {},
        extraOk = entry.extra == nil, extraSize = 0, extraList = {}, extraFeed = {}, extraTotal = 0, more = self.opts.read }
    end
  end
  local reads = {}
  for _, m in ipairs(list) do
    if m.present then reads[#reads + 1] = function() readOne(m) end end
  end
  if #reads > 0 then parallel.waitForAll(table.unpack(reads)) end
  local now = os.clock()
  for _, m in ipairs(list) do
    if m.line and m.present then
      -- nothing on a Create line can be read: it's moving if its feeder has
      -- gone down since it was filled last round, or something came out
      local t = self.lineFeed[m.entry.feeder]
      m.moving = (t ~= nil and m.feedTotal < t.total) or next(m.outList) ~= nil
      if not t or m.moving or m.feedTotal == 0 then t = { since = now } end
      t.total = m.feedTotal
      self.lineFeed[m.entry.feeder], m.track = t, t
      m.stalled = m.feedOk and m.feedTotal > 0 and now - t.since > LINE_STUCK
    elseif m.present then
      self:configure(m)
    end
  end
  return list
end

-- Powered (a Create line: no power to read), with a feeder that answers:
-- ready to be fed.
function mekfeed.ready(m)
  return m.present and m.feedOk and m.extraOk ~= false and (m.line ~= nil or (m.energy or 0) > 0)
end

-- How much more of an item the machine's input slots can take (an empty
-- slot a stack, one holding the item the rest of its stack), less what's
-- waiting in the feeder. A Create line's feeder is kept at m.fill.
function mekfeed.roomFor(m, name)
  if m.line then return m.fill - m.feedTotal end
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

-- Every process slot is busy and a stack is waiting: as fast as it goes.
function mekfeed.flatOut(m)
  for i = 1, m.slots do
    if not m.inputs[i] then return false end
  end
  return mekfeed.inputOf(m) + m.feedTotal >= STACK
end

-- Status board colour and words for a machine: red (needs you: no power,
-- missing, output full), orange (working flat out), yellow (working), lime
-- (ready and idle). working: what to say it's doing, e.g. the item.
function mekfeed.status(m, working)
  if m.line then
    if not m.present or not m.feedOk then return "red", "no feeder" end
    if not m.outOk then return "red", "no output chest" end
    if m.stalled then return "red", "not moving" end
    if m.feedTotal > 0 then return m.feedTotal >= STACK and "orange" or "yellow", working or "working" end
    return "lime", "idle"
  end
  if not m.present then return "red", "not on network" end
  if not m.feedOk then return "red", "no feeder" end
  if m.extraOk == false then return "red", "no infusion feeder" end
  if not m.outOk then return "red", "no output chest" end
  if (m.energy or 0) <= 0 then return "red", "no power" end
  if mekfeed.full(m) then return "red", "output full" end
  if (m.usage or 0) > 0 then return mekfeed.flatOut(m) and "orange" or "yellow", working or "working" end
  if mekfeed.inputOf(m) + m.feedTotal > 0 then return "yellow", "starting" end
  return "lime", "idle"
end

-- Note a feeder was sent n of an item.
function mekfeed.added(m, name, n)
  m.feed[name] = (m.feed[name] or 0) + n
  m.feedTotal = m.feedTotal + n
  -- next round's read checks the feeder went down from what it was left with
  if m.track then m.track.total = m.track.total + n end
end

---------------------------------------------------------------- the storage computer

-- A barrel or chest on the storage cable would be storage to the storage
-- computer (it'd put things in it and count what's in it): tell it which
-- are feeders ('feeders'), and fill none of them until it has said yes.
-- Far away (remote) the feeders aren't on its cable. Returns the feeders
-- not to fill (feeder -> true) and why, if any.
function Set:register(remote) return mekfeed.register({ self }, remote) end

-- The same for every set on this computer at once: the storage computer
-- keeps one list per computer, and each 'feeders' replaces it. The first
-- set remembers what was sent.
function mekfeed.register(sets, remote)
  local unsure = {}
  local self = sets[1]
  if remote or not self then return unsure end
  local list = {}
  for _, set in ipairs(sets) do
    for _, entry in ipairs(set:entries()) do
      -- whether or not its machine is there: a missing machine's barrel isn't storage either
      for _, name in ipairs({ entry.feeder, entry.output or false, entry.extra or false }) do
        local t = name and peripheral.isPresent(name) and peripheral.getType(name)
        if t and not isHopper(t) then list[#list + 1] = name end
      end
    end
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
    -- (a Create line that doesn't move shows red instead: most likely it isn't turning)
    if item and not m.line and mekfeed.inputOf(m) == 0 and (m.energy or 0) > 0 then
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

-- Empty each machine's output chest into input (the storage input chest,
-- or far away the ender chest). How many moved, true if some didn't fit,
-- why when a move failed outright (e.g. input isn't on this cable), and
-- item -> how many of it moved (the smelter counts its orders with it).
function Set:collect(machines, input)
  local moved, stuck, why, byName = 0, false, nil, {}
  if not input then return 0, false, nil, byName end
  for _, m in ipairs(machines) do
    if m.entry.output and m.outOk then
      for slot, item in pairs(m.outList) do
        local ok, n = pcall(peripheral.call, m.entry.output, "pushItems", input, slot)
        if not ok then
          why = ("can't move %s's output from %s into %s: %s"):format(m.title, m.entry.output, input, tostring(n))
        end
        n = ok and n or 0
        moved = moved + n
        byName[item.name] = (byName[item.name] or 0) + n
        if n < item.count then stuck = true end
      end
    end
  end
  return moved, stuck, why, byName
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

-- Far from the storage system nothing on this cable is a storage chest, so
-- a barrel the machine has already filled can still be picked.
function Set:far()
  return self.opts.far ~= nil and self.opts.far() == true
end

local function freeChest(self, name)
  return self:far() or isEmpty(name)
end

function Set:list()
  local list = self:entries()
  local titles = self:titles(list)
  if #list == 0 then print(("No %ss yet. Add one with '%s add'."):format(self.opts.what, self.opts.cmd or self.opts.name)) end
  for i, entry in ipairs(list) do
    if entry.line then
      print(("%d  %s: fed by %s, out to %s"):format(i, titles[i], entry.feeder, entry.output or "a storage input chest"))
    else
      print(("%d  %s: %s, fed by %s%s, out to %s"):format(i, titles[i], entry.machine, entry.feeder,
        entry.extra and (" and " .. entry.extra) or "", entry.output or "the chest under it"))
    end
  end
end

-- Every chest or machine an entry uses (skip: that entry's index).
local function usedBy(list, skip)
  local used = {}
  for i, entry in ipairs(list) do
    if i ~= skip then
      used[entry.feeder] = true
      if entry.machine then used[entry.machine] = true end
      if entry.output then used[entry.output] = true end
      if entry.extra then used[entry.extra] = true end
    end
  end
  return used
end

-- machine: its peripheral name, or a Create line's word ("crusher"). extra:
-- the second feeder (opts.extra).
function Set:add(machine, feeder, output, extra)
  local list = self:entries()
  local used = usedBy(list)
  local line = machine and self:lineWord(machine)
  local kind = line and LINES[line]
  local asking = not feeder -- an output chest is only asked for along with the feeder
  local wantExtra = self.opts.extra and not line
  -- what comes out is counted there: the infuser, a saw line
  local mustOut = (self.opts.needOutput and not line) or (kind and kind.needOutput)
  if not machine or not feeder then print("Right-click a modem to see its block's name.") end
  if line then
    machine = nil
  elseif not machine then
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
      if not used[name] and not self:taken(name) and (isHopper(peripheral.getType(name)) or freeChest(self, name)) then
        feeders[#feeders + 1] = name
      end
    end
    if #feeders == 0 then
      print(kind and "Nothing free to feed it: an empty chest or barrel with a wired modem on it, joined to the cable."
        or ("Nothing free to feed it. Put a hopper on top of the %s, pointing down, or an empty barrel a pipe pulls from into it, with a wired modem on it joined to the cable.")
          :format(self.opts.what))
      return
    end
    print(kind and ("What FEEDS it: %s"):format(kind.feeds)
      or "What FEEDS it: the hopper on top of it, pointing down, or the barrel a pipe pulls from into it:")
    feeder = choose("Which? (Enter to cancel)", feeders)
    if not feeder then return end
  end
  if wantExtra and not extra then
    local extras = {}
    for _, name in ipairs(findOnNetwork(isFeeder)) do
      if not used[name] and not self:taken(name) and name ~= feeder
        and (isHopper(peripheral.getType(name)) or freeChest(self, name)) then
        extras[#extras + 1] = name
      end
    end
    if #extras == 0 then
      print(("Nothing free for its %s: %s"):format(self.opts.extra.title, self.opts.extra.hint))
      return
    end
    print(("Its %s: %s"):format(self.opts.extra.title:upper(), self.opts.extra.hint))
    extra = choose("Which? (Enter to cancel)", extras)
    if not extra then return end
  end
  if asking then
    local outs = {}
    for _, name in ipairs(findOnNetwork(isFeeder)) do
      if not used[name] and not self:taken(name) and name ~= feeder and name ~= extra
        and not isHopper(peripheral.getType(name)) and freeChest(self, name) then
        outs[#outs + 1] = name
      end
    end
    if mustOut and #outs == 0 then
      print(("It needs an output chest%s (what it makes is counted there): an empty chest or barrel with a wired modem on it.")
        :format(kind and "" or " under it"))
      return
    elseif mustOut then
      print(kind and ("Its OUTPUT chest: %s"):format(kind.out)
        or "Its OUTPUT chest or barrel, under it: what it makes goes here, is counted, then goes into storage.")
      output = choose("Which? (Enter to cancel)", outs)
      if not output then return end
    elseif #outs > 0 then
      if kind then
        print(("Its OUTPUT chest: %s"):format(kind.out))
        print(self:far() and "Enter: none, it ends up in the ender chest itself."
          or "Enter: none, it ends up in a storage input chest.")
      elseif self:far() then
        print("Its OUTPUT chest or barrel, under it, where what it makes goes (sent home through the ender chest each round).")
        print("Enter: none, the ender chest itself is under it.")
      else
        print("Its OUTPUT chest, under it, where what it makes goes (emptied into storage each round).")
        print("Enter: none, the chest under it is a storage input chest.")
      end
      output = choose("Which?", outs)
    end
  end
  if (machine and used[machine]) or used[feeder] or (output and used[output]) or (extra and used[extra]) then
    print("That one is already added.")
    return
  end
  if output == feeder or (extra and (extra == feeder or extra == output)) then
    print("The feeders and the output chest have to be different chests.")
    return
  end
  if mustOut and not output then print("It needs an output chest.") return end
  if wantExtra and not extra then print(("It needs its %s."):format(self.opts.extra.title)) return end
  for _, name in ipairs({ machine or feeder, feeder, output or feeder, extra or feeder }) do
    if not peripheral.isPresent(name) then print(name .. " isn't on the network.") return end
  end
  if extra then
    local extraType = peripheral.getType(extra) or ""
    if not isFeeder(extraType) then print(extra .. " isn't a hopper, barrel or chest.") return end
    if not isHopper(extraType) and not freeChest(self, extra) then
      print(extra .. " has items in it: empty it first (it might be a storage chest).")
      return
    end
  end
  if machine and not self:isMachine(peripheral.getType(machine) or "") then
    print(("%s isn't an %s."):format(machine, self.opts.what))
    return
  end
  local feederType = peripheral.getType(feeder) or ""
  if not isFeeder(feederType) then print(feeder .. " isn't a hopper, barrel or chest.") return end
  if not isHopper(feederType) and not freeChest(self, feeder) then
    print(feeder .. " has items in it: empty it first (it might be a storage chest).")
    return
  end
  if output then
    local outType = peripheral.getType(output) or ""
    if not isFeeder(outType) or isHopper(outType) then print(output .. " isn't a barrel or chest.") return end
    if not freeChest(self, output) then print(output .. " has items in it: empty it first (it might be a storage chest).") return end
  end

  list[#list + 1] = { machine = machine, line = line, feeder = feeder, output = output, extra = extra }
  self:save(list)
  local title = self:titles(list)[#list]
  if extra then print(("Its %s: %s."):format(self.opts.extra.title, extra)) end
  if kind then
    print(("%s added, fed by %s."):format(title, feeder))
    print("A funnel or chute has to move its items into the machine; the computer can't see the machine itself.")
    if output then
      print(("What it makes has to end up in %s, and from there it goes into storage."):format(output))
    else
      print(self:far() and "What it makes has to end up in the ender chest, and goes home from there."
        or "What it makes has to end up in a storage input chest (add it in 'storage setup').")
    end
    return
  end
  print(("%s added: %s, fed by %s."):format(title, machine, feeder))
  if not isHopper(feederType) then
    print("Something has to move its items into the machine: a logistical transporter set to pull, or a funnel.")
    print("The storage computer stops using it as storage once the program is running.")
  end
  if output then
    print(("What it makes goes into %s (put it under the machine), and from there into storage."):format(output))
  elseif self:far() then
    print("Put the ender chest under it: what it makes comes out there and goes home.")
  else
    print("Put a storage input chest under it (add it in 'storage setup'): what it makes comes out there.")
  end
end

---------------------------------------------------------------- the setup screen

-- A lib/setupui.lua page of the machines (and Create lines): tap one to
-- change its feeder or output chest or remove it, or add one (machine,
-- then feeder, then output chest; a line has no machine to pick). Saved as
-- each change is made.
function Set:setupParts(ui)
  local opts = self.opts
  local function used(skip)
    return usedBy(self:entries(), skip)
  end
  -- kind: the Create line's LINES entry, nil for a Mekanism machine
  local function pickFeeder(skip, current, kind, done)
    local u = used(skip)
    ui:pickChest({ title = "Pick its feeder",
      hint = kind and kind.feeds or "The hopper on top of it, or the barrel a pipe pulls from into it.",
      names = findOnNetwork(isFeeder), current = current,
      nothing = kind and "Nothing free: an empty chest or barrel, with a wired modem on it."
        or "Nothing free: a hopper on top, or an empty barrel, with a wired modem on it.",
      roleOf = function(n) return u[n] and "another machine's" or self:taken(n) and "in use" or nil end,
      -- every storage chest is a barrel or chest too: only empty ones (far away, any)
      only = function(n, info)
        return n == current or self:far() or isHopper(peripheral.getType(n) or "") or info.stacks == 0
      end,
      pick = function(n)
        if u[n] or self:taken(n) then ui:say(("%s is taken."):format(n), "orange") return end
        ui:back()
        done(n)
      end })
    ui:say(kind and "Tap its feeder chest." or "Tap its hopper or barrel.")
  end
  -- the second feeder (opts.extra): a hopper or empty barrel, not its first feeder
  local function pickExtra(skip, current, feeder, done)
    local u = used(skip)
    ui:pickChest({ title = "Pick its " .. opts.extra.title, hint = opts.extra.hint,
      names = findOnNetwork(isFeeder), current = current,
      nothing = "Nothing free: a hopper into its side, or an empty barrel, with a wired modem on it.",
      roleOf = function(n)
        return u[n] and "another machine's" or n == feeder and "its feeder" or self:taken(n) and "in use" or nil
      end,
      only = function(n, info)
        return n == current or self:far() or isHopper(peripheral.getType(n) or "") or info.stacks == 0
      end,
      pick = function(n)
        if u[n] or n == feeder or self:taken(n) then ui:say(("%s is taken."):format(n), "orange") return end
        ui:back()
        done(n)
      end })
    ui:say("Tap the hopper or barrel for its " .. opts.extra.title .. ".")
  end
  local function pickOutput(skip, current, feeder, kind, done, extra)
    local u = used(skip)
    local far = self:far()
    local mustOut = (opts.needOutput and not kind) or (kind and kind.needOutput)
    local none = kind and (far and "(none: it ends up in the ender chest)" or "(none: it ends up in a storage input chest)")
      or far and "(none: the ender chest is under it)" or "(none: a storage input chest is under it)"
    local o = { title = "Pick its output chest",
      hint = kind and (kind.out .. (far and " It goes home through the ender chest." or " It goes into storage from there."))
        or mustOut and "Under it: what it makes goes here and is counted, then goes into storage."
        or far and "Under it: what it makes goes here, then home through the ender chest."
        or "Under it: what it makes goes here, then into storage.",
      names = findOnNetwork(function(t) return isFeeder(t) and not isHopper(t) end), current = current,
      none = not mustOut and none or nil,
      roleOf = function(n)
        return u[n] and "another machine's" or (n == feeder or n == extra) and "its feeder"
          or self:taken(n) and "in use" or nil
      end,
      only = function(n, info) return n == current or far or info.stacks == 0 end,
      pick = function(n)
        if n and (u[n] or n == feeder or n == extra or self:taken(n)) then ui:say(("%s is taken."):format(n), "orange") return end
        ui:back()
        done(n)
      end }
    -- near the storage an output chest starts empty, so dropping an item in
    -- it says which it is (it goes into storage with the first round);
    -- far away any chest could be one, so they're listed
    if ui.pickByDrop and not far then
      o.drop = "Put any item in its output chest now."
      o.list = function() ui:pickChest(o) end
      ui:pickByDrop(o)
      return
    end
    ui:pickChest(o)
    ui:say(kind and "Tap the chest it ends up in, or (none)." or "Tap the chest under it, or (none).")
  end
  local function change(i, field, value, text)
    local list = self:entries()
    if not list[i] then return end
    list[i][field] = value
    self:save(list)
    ui:say(text, "lime")
  end

  local function machinePage(i)
    return {
      title = function()
        local list = self:entries()
        return list[i] and self:titles(list)[i] or opts.title
      end,
      rows = function()
        local e = self:entries()[i]
        if not e then return { { label = "Removed.", dim = true } } end
        local kind = e.line and (LINES[e.line] or LINES.crush)
        local function there(n) return peripheral.isPresent(n) and "lightGray" or "red" end
        local noOutput = self:far() and "none: the ender chest" or "none: a storage input chest"
        local extraTitle = opts.extra and opts.extra.title:gsub("^%l", string.upper)
        local rows = {
          kind and { label = "Machine", value = "Create " .. kind.what, colour = "lightGray", dim = false }
            or { label = "Machine", value = e.machine, colour = there(e.machine), dim = false },
          { label = "Feeder", value = e.feeder, colour = there(e.feeder), act = function()
            pickFeeder(i, e.feeder, kind, function(n) change(i, "feeder", n, ("Feeder: %s."):format(n)) end)
          end },
          { label = "Output chest", value = e.output or noOutput,
            colour = e.output and there(e.output) or "gray",
            act = function()
              pickOutput(i, e.output, e.feeder, kind,
                function(n) change(i, "output", n, ("Output chest: %s."):format(n or "none")) end, e.extra)
            end },
          { label = "Remove it", colour = "red", act = function()
            local list = self:entries()
            local gone = table.remove(list, i)
            self:save(list)
            ui:back()
            ui:say(("Forgot %s. Empty its feeder%s by hand."):format(gone.machine or gone.feeder,
              gone.output and " and output chest" or ""), "lime")
          end },
        }
        -- the set's own settings for a line (the saw's filter), above Remove it
        if opts.lineRows and kind then
          for _, row in ipairs(opts.lineRows(ui, i, e, function(field, value, text) change(i, field, value, text) end)) do
            table.insert(rows, #rows, row)
          end
        end
        if opts.extra and not kind then
          table.insert(rows, 3, { label = extraTitle, value = e.extra or "none: add one",
            colour = e.extra and there(e.extra) or "red", act = function()
              pickExtra(i, e.extra, e.feeder, function(n) change(i, "extra", n, ("%s: %s."):format(extraTitle, n)) end)
            end })
        end
        return rows
      end,
    }
  end

  -- line: a Create line kind to add, nil for a Mekanism machine
  local function add(line)
    local kind = line and LINES[line]
    local function withMachine(machine)
      pickFeeder(nil, nil, kind, function(feeder)
        local function withExtra(extra)
          pickOutput(nil, nil, feeder, kind, function(output)
            local list = self:entries()
            list[#list + 1] = { machine = machine, line = line, feeder = feeder, output = output, extra = extra }
            self:save(list)
            local title = self:titles(list)[#list]
            if kind then
              ui:say(("%s added. A funnel or chute has to move its items in."):format(title), "lime")
            else
              local hopper = isHopper(peripheral.getType(feeder) or "")
              ui:say(("%s added.%s"):format(title, hopper and ""
                or " A pipe has to move its items in: a logistical transporter set to pull, or a funnel."), "lime")
            end
          end, extra)
        end
        if opts.extra and not kind then
          pickExtra(nil, nil, feeder, withExtra)
        else
          withExtra(nil)
        end
      end)
    end
    if kind then return withMachine(nil) end
    local free = self:free()
    if #free == 0 then
      ui:say(("No %s on the network that isn't added: put a wired modem on it and right-click it."):format(opts.what), "orange")
      return
    end
    if #free == 1 then return withMachine(free[1]) end
    ui:open({
      title = ("Pick the %s"):format(opts.what), hint = "Right-click a modem to see its block's name.",
      rows = function()
        local out = {}
        for _, n in ipairs(free) do
          out[#out + 1] = { label = n, act = function() ui:back(); withMachine(n) end }
        end
        return out
      end,
    })
  end

  local function an(what) return what:find("^[aeiou]") and "an" or "a" end
  local parts = { add = add }
  -- a row per machine: tap it to change it
  function parts.entries()
    local out = {}
    local list = self:entries()
    local titles = self:titles(list)
    for i, e in ipairs(list) do
      local here = peripheral.isPresent(e.machine or e.feeder)
      local value = e.line and ("fed by " .. e.feeder) or e.machine
      out[#out + 1] = { label = titles[i], value = here and value or (value .. " (missing)"),
        colour = here and "lightGray" or "red", act = function() ui:open(machinePage(i)) end }
    end
    return out
  end
  -- the + Add rows
  function parts.adds()
    -- a set of Create lines only has no machine of its own to add
    local adds = opts.single and { { label = ("+ Add %s %s"):format(an(opts.what), opts.what), colour = "lime",
      act = function() add(nil) end } } or {}
    for _, line in ipairs(opts.lines or {}) do
      local kind = LINES[line]
      if kind then
        adds[#adds + 1] = { label = ("+ Add a Create %s"):format(kind.what), colour = "lime",
          act = function() add(line) end }
      end
    end
    -- no Mekanism machine added or on the network (a Create-only world): the Create lines first
    local anyMachine = #self:free() > 0
    for _, e in ipairs(self:entries()) do
      if e.machine then anyMachine = true end
    end
    if opts.single and not anyMachine and #adds > 1 then table.insert(adds, table.remove(adds, 1)) end
    return adds
  end
  return parts
end

function Set:setupPage(ui)
  local parts = self:setupParts(ui)
  return {
    title = self.opts.pageTitle or (self.opts.title .. "s"),
    hint = ("Each %s, its feeder and its output chest."):format(self.opts.lines and "machine" or self.opts.what),
    rows = function()
      local out = parts.entries()
      for _, row in ipairs(parts.adds()) do out[#out + 1] = row end
      return out
    end,
  }
end

-- '<program> add [machine feeder [output]]' (machine: a Create line's word
-- too, e.g. 'add crusher') and '<program> remove <n>': true if args was one
-- of them (and it's been done).
function Set:command(args)
  if args[1] == "add" then
    self:add(args[2], args[3], args[4])
    return true
  elseif args[1] == "remove" then
    local list = self:entries()
    local n = tonumber(args[2] or "")
    if not n or not list[n] then
      self:list()
      print(("Usage: %s remove <number>"):format(self.opts.cmd or self.opts.name))
      return true
    end
    local entry = table.remove(list, n)
    self:save(list)
    print(("Forgot %s. Empty its feeder%s by hand."):format(entry.machine or entry.feeder,
      entry.output and " and output chest" or ""))
    return true
  end
  return false
end

return mekfeed
