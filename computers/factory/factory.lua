-- The factory: every machine that turns items in the storage system into
-- other items, run from one program. Put it on as many computers as you
-- like: each one works out what to do from the machines it has.
--   furnaces, blast furnaces, smokers, Mekanism smelters, Create blasting
--     and smoking fans                      the smelter (smelt.lua): ores and food, the rest on request
--   Mekanism enrichment chambers, Create crushing wheels and washing fans
--                                           the enricher (enrich.lua)
--   Mekanism metallurgic infusers           steel, alloys, circuits on request (infuse.lua)
--   Cobblemon cooking pots                  exp candy (cook.lua)
--   Hopper Botany Pots                      Mystical Agriculture essence (botany.lua)
-- Furnaces and botany pots are found by themselves; the rest are added on
-- the setup screen (or with 'factory add').
--
--   factory                         start (startup.lua runs this)
--   factory setup                   the setup screen, on the monitor and the terminal: machines, the chain,
--                                   the work chest and the monitor (in the running factory if there is one;
--                                   or Setup on its monitor or screen, or F1)
--   factory add <kind> [...]        add a machine: chamber, crusher, washer, smelter, fan, smokefan
--                                   ([machine] feeder [output]), infuser ([machine feeder extra output]),
--                                   pot ([recipe feed output relay]), or potbarrel ([barrel | all]: the one
--                                   Hopper Botany Pots empty into)
--   factory list                    every machine, its owner and what it is
--   factory remove [n]              forget machine n (no number: list them)
--   factory give <name|all> <id>    hand a furnace or botany pot (or all of them) to factory computer id
--   factory relay <n> [relay]       give cooking pot n its redstone relay
--   factory charcoal <n> [wood]     make n charcoal from logs, e.g. 'factory charcoal 256 spruce'
--   factory stone <n>               make n stone from cobblestone
--   factory glass <n> [red]         make n glass from sand (red: red sand only)
--   factory smelt [what count]      the smelting recipes, or request count of one (by number or name)
--   factory cancel [n|name]         cancel a smelting request (no name: all of them)
--   factory infuse [what count]     the infusing recipes, or request count of one (by number or name)
--   factory infuse cancel [n]       cancel infusing request n (no number: all of them)
--   factory find <text>             essence recipes for items matching text, and how many you can make
--   factory make <count> <text>     order count of an item made from essence (the first match)
--   factory chest [name|none]       use an empty chest on the network as the work chest
--   factory chest remote            far from the storage system: one ender chest both ways (or a return one too)
--   factory monitor [name|none]     the monitor for the status board
--
-- Several factory computers on one cable share it: each furnace and botany
-- pot belongs to whichever claimed it first (the others leave it alone), and
-- each says which items its machines take on the "factory" protocol, so the
-- smelters leave the ores an enricher anywhere takes to it (the chain: the
-- enricher is rank 1, the smelter rank 2). A computer that hasn't answered
-- for 10 minutes is forgotten and its items are taken again.
--
-- Needs a wired modem on the storage computer's network and the storage
-- computer (computers/storage-computer) running; far away, an ender modem
-- and an ender chest pair (the work chest). Settings are in config.lua.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local mekfeed = require("lib.mekfeed") -- Mekanism machines and Create lines
local workchest = require("lib.workchest") -- the chest the storage computer fills in one go
local setupui = require("lib.setupui") -- the setup screen
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local config = fs.exists("config.lua") and require("config") or {}

local STORAGE_PROTOCOL = "storage" -- the storage computer answers on this
local PROTOCOL = "factory" -- factory computers say what they take and own on this (and the storage computer finds them)
local EVERY = 5 -- seconds between rounds (each part runs every so many of its own, e.g. 10 for the smelter)
local REPLY_WAIT = 30 -- seconds to wait for the storage computer to answer (a busy one answers late)
local PEER_EVERY = 30 -- seconds between asking the other factory computers what they take and own
local PEER_WAIT = 2 -- seconds to wait for each of them
local PEER_FORGET = 600 -- seconds another factory computer may go unheard before its items are taken here
local ACTIVE_EVERY = 2 -- seconds a part's "has it got machines here" is kept (each look goes through every peripheral)
local REDRAW_EVERY = 2 -- seconds between redraws when nothing happens (the parts' messages as they work)
local REDRAW_GAP = 0.2 -- seconds a change waits to be drawn, so a burst of changes draws once
local CLAIMS_FILE = "/.factory_claims" -- { mine = { name = when }, released = { name = true }, off = { part = true } }
local OLD_NAMES = { "smelter", "enricher", "cooker" } -- the programs this replaced: their monitor settings carry on

local myId = os.getComputerID()

---------------------------------------------------------------- settings

-- config.lua has a table per part (smelter, enricher, infuser, cooker, essence). One
-- from before the factory has its settings at the top: they're used for
-- every part, as that computer only ran one of them.
local SECTIONS = { "smelter", "enricher", "infuser", "cooker", "essence" }
local sectioned = false
for _, s in ipairs(SECTIONS) do
  if type(config[s]) == "table" then sectioned = true end
end
local function section(name)
  if sectioned then return type(config[name]) == "table" and config[name] or {} end
  return config
end

if settings.get("factory.monitor") == nil then
  for _, old in ipairs(OLD_NAMES) do
    local v = settings.get(old .. ".monitor")
    if v ~= nil and settings.get("factory.monitor") == nil then
      settings.set("factory.monitor", v)
      settings.save()
    end
  end
end
if type(section("cooker").monitor) == "string" and settings.get("factory.monitor") == nil then
  settings.set("factory.monitor", section("cooker").monitor)
  settings.save()
end

---------------------------------------------------------------- talking to storage

-- over the cable (or wireless, if that's all there is)
local storage = net.peer(STORAGE_PROTOCOL, { open = "any", wait = REPLY_WAIT })

-- Ask the storage computer something and wait for its answer: nil and why
-- if there's none.
local function ask(msg, wait)
  local reply, why = storage:ask(msg, wait)
  if reply then return reply end
  return nil, why == "no answer" and "the storage computer didn't answer" or "no storage computer answered"
end

-- the smelter's and enricher's work chests become this one
local work = workchest.new("factory", ask, { "smelter", "enricher" })

---------------------------------------------------------------- claims and peers

local claims -- what this computer has claimed (CLAIMS_FILE)
local peers = {} -- id -> { heard, stages = { { id, title, rank, takes, summary } }, owns = { name = when } }
local myUses = {} -- name -> true: every peripheral the machines added here use (they always win)

local function readClaims()
  local t = files.read(CLAIMS_FILE)
  t = type(t) == "table" and t or {}
  t.mine, t.released, t.off = t.mine or {}, t.released or {}, t.off or {}
  claims = t
  return t
end

local function saveClaims() files.write(CLAIMS_FILE, claims) end

readClaims()

-- Who has a peripheral: "me", another factory computer's id, or nil for
-- nobody. A machine added by hand counts from the beginning of time, a
-- found one from when it was claimed: the earliest wins (the lower id, if
-- they're the same).
local function ownerOf(name)
  local best, bestT = nil, math.huge
  if myUses[name] then best, bestT = "me", 0
  elseif claims.mine[name] then best, bestT = "me", claims.mine[name] end
  for id, p in pairs(peers) do
    local t = p.owns and p.owns[name]
    if t and (t < bestT or (t == bestT and best == "me" and id < myId)) then best, bestT = id, t end
  end
  return best
end

local function matchAny(name, patterns)
  for _, p in ipairs(patterns) do
    if type(p) == "string" and name:find(p) then return true end
  end
  return false
end

---------------------------------------------------------------- the parts

local f = { work = work, ask = ask, event = "factory_added", config = section }
-- crafting goes to the craft overseer, the recipe server (the storage computer only keeps items):
-- prepare, recipes, and the machines' makes and jobdone
f.craft = require("lib.crafts").ask
local parts -- the parts below, in the chain's order

function f.wake() os.queueEvent("factory_added") end
function f.changed() os.queueEvent("factory_changed") end
function f.log(text) if report then report.log(text) end end
function f.mine(name) return ownerOf(name) == "me" end
-- Not to be offered when adding a machine: another factory computer's, or a
-- furnace or botany pot found here (a Hopper Botany Pot looks like a hopper).
function f.taken(name)
  if claims.mine[name] and not myUses[name] then return true end
  local who = ownerOf(name)
  return who ~= nil and who ~= "me"
end

-- A part that's switched on (the Chain page) and has machines here.
-- active() looks through every peripheral on the cable, and this is asked
-- for each item in the chain and on every redraw, so it's kept a moment
-- (and forgotten when a peripheral comes or goes, or a machine is added).
local activeKept = {} -- part id -> { at = os.clock(), yes = bool }
local function running(p)
  if claims.off[p.id] then return false end
  local kept = activeKept[p.id]
  if not kept or os.clock() - kept.at >= ACTIVE_EVERY then
    kept = { at = os.clock(), yes = p.active() and true or false }
    activeKept[p.id] = kept
  end
  return kept.yes
end
local function forgetActive() activeKept = {} end

-- True when an earlier part of the chain (a lower rank), here or on another
-- factory computer, takes the item: a part of rank leaves it alone.
function f.leave(rank, name)
  for _, p in ipairs(parts) do
    if p.rank and p.rank < rank and running(p) and matchAny(name, p.takes()) then return true end
  end
  for _, peer in pairs(peers) do
    if os.clock() - peer.heard < PEER_FORGET then
      for _, s in ipairs(peer.stages or {}) do
        if s.rank and s.rank < rank and type(s.takes) == "table" and matchAny(name, s.takes) then return true end
      end
    end
  end
  return false
end

parts = {
  require("enrich").new(f),
  require("smelt").new(f),
  require("infuse").new(f),
  require("cook").new(f),
  require("botany").new(f),
}
local byId = {}
for _, p in ipairs(parts) do byId[p.id] = p end

-- Every peripheral the machines added here use, and what this computer
-- tells the others it owns.
local function refreshUses()
  myUses = {}
  for _, p in ipairs(parts) do
    for _, name in ipairs(p.uses()) do myUses[name] = true end
  end
end

local function owns()
  local out = {}
  for name, t in pairs(claims.mine) do out[name] = t end
  for name in pairs(myUses) do out[name] = 0 end
  return out
end

-- What this computer says about itself: each part running here, what it takes and owns.
local function hello()
  local stages = {}
  for _, p in ipairs(parts) do
    if running(p) then
      stages[#stages + 1] = { id = p.id, title = p.title, rank = p.rank, takes = p.takes(), summary = p.summary() }
    end
  end
  return { stages = stages, owns = owns(), label = os.getComputerLabel() }
end

-- Ask every other factory computer what it takes and owns. One that misses
-- an answer keeps its last one (a busy round, a reboot) until PEER_FORGET.
local peersAt = -math.huge
local function askPeers(force)
  if not force and os.clock() - peersAt < PEER_EVERY then return end
  peersAt = os.clock()
  local jobs = {}
  for _, id in ipairs({ rednet.lookup(PROTOCOL) }) do
    if id ~= myId then
      jobs[#jobs + 1] = function()
        local reply = net.ask(id, PROTOCOL, { type = "hello" }, { wait = PEER_WAIT })
        if reply and type(reply.stages) == "table" then
          peers[id] = { heard = os.clock(), stages = reply.stages, owns = type(reply.owns) == "table" and reply.owns or {},
            label = reply.label }
        end
      end
    end
  end
  if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
  for id, p in pairs(peers) do
    if os.clock() - p.heard > PEER_FORGET then peers[id] = nil end
  end
end

-- Claim every furnace and botany pot nobody has (unless it was given away
-- here), and let go of any another computer had first.
local function settle()
  readClaims()
  refreshUses()
  local changed = false
  for _, p in ipairs(parts) do
    if not claims.off[p.id] then
      for _, m in ipairs(p.found()) do
        if not claims.mine[m.name] and not claims.released[m.name] and ownerOf(m.name) == nil then
          claims.mine[m.name] = os.epoch("utc")
          changed = true
        end
      end
    end
  end
  for name in pairs(claims.mine) do
    if ownerOf(name) ~= "me" then
      claims.mine[name] = nil
      changed = true
    end
  end
  if changed then saveClaims() end
end

-- Take a found machine (from another factory computer if it has it: it's
-- asked to let go first). true, or false and why.
local function claim(name)
  local who = ownerOf(name)
  if who and who ~= "me" then
    local reply = net.ask(who, PROTOCOL, { type = "give", names = { name } }, { wait = PEER_WAIT })
    if not reply or not reply.ok then return false, ("computer %d didn't let go of it"):format(who) end
    if peers[who] and peers[who].owns then peers[who].owns[name] = nil end
  end
  readClaims()
  claims.mine[name], claims.released[name] = os.epoch("utc"), nil
  saveClaims()
  return true
end

-- Let go of a found machine: another factory computer takes it as free.
local function release(name)
  readClaims()
  claims.mine[name], claims.released[name] = nil, true
  saveClaims()
end

---------------------------------------------------------------- a round

local message = { "Starting...", "lightGray" } -- the factory's own message, when no part has one
local due = {} -- part id -> os.clock() when it's next due a round

local function worst()
  local rank = { red = 3, orange = 2 }
  local best
  for _, p in ipairs(parts) do
    if running(p) then
      local m = p.message
      if not best or (rank[m[2]] or 0) > (rank[best[2]] or 0) then best = m end
    end
  end
  return best or message
end

local function round()
  askPeers()
  settle()
  local now = os.clock()
  local list = {}
  for _, p in ipairs(parts) do
    if running(p) and now >= (due[p.id] or 0) then list[#list + 1] = p end
  end
  local anyRunning = false
  for _, p in ipairs(parts) do
    if running(p) then anyRunning = true end
  end
  if not anyRunning then
    message = { "Nothing set up yet: tap Setup (or F1) and add a machine, or join furnaces to the cable.", "orange" }
    if report then report.set("waiting", "nothing set up") end
    return
  end
  if #list == 0 then return end
  for _, p in ipairs(list) do due[p.id] = now + (p.every or EVERY) end

  -- read every machine first (far away their output chests empty into the
  -- ender chest here, which needs no answer from the storage computer)
  work:reload()
  local remoteInput = work.remote and work:input(nil) or nil
  for _, p in ipairs(list) do
    local ok, err = (errlog and errlog.pcall or pcall)(p.read, work.remote, remoteInput)
    if not ok then p.message = { "Error: " .. tostring(err), "red" } end
  end

  local reply, err = ask({ type = "stock" })
  if not reply or type(reply.counts) ~= "table" then
    local text = work.remote and "Storage not answering over the ender modem: is it running, with an ender modem too?"
      or "Storage not answering: is it running, on the same cable? ('install update' an old one)"
    for _, p in ipairs(list) do
      p.message = { text, "orange" }
      p.status = { "waiting", ("storage computer: %s"):format(err or "too old to answer") }
    end
    return
  end
  -- far away, everything goes home through the ender chest (or the return one)
  local useWork = work:check(reply) or work.remote
  -- the pot barrels emptied first: the storage computer only takes an empty one as a feeder
  if running(byId.essence) then byId.essence.beforeRegister(work:input(reply.input)) end
  local unsure, feedProblem = mekfeed.register({ byId.enrich.set, byId.smelt.set, byId.infuse.set,
    byId.essence.barrelSet }, work.remote)
  local r = { stock = reply, useWork = useWork, input = work:input(reply.input), unsure = unsure,
    feedProblem = feedProblem }
  -- in the chain's order, so a smelter sees what the enricher takes this round
  for _, p in ipairs(list) do
    local ok, perr = (errlog and errlog.pcall or pcall)(p.round, r)
    if not ok then
      p.message = { "Error: " .. tostring(perr), "red" }
      p.status = { "error", tostring(perr) }
    end
  end
end

local function reportStatus()
  if not report then return end
  local order = { error = 5, alert = 4, waiting = 3, running = 2, idle = 1 }
  local state, details = nil, {}
  for _, p in ipairs(parts) do
    if running(p) then
      local s = p.status
      if not state or (order[s[1]] or 0) > (order[state] or 0) then state = s[1] end
      if s[2] and s[2] ~= "" then details[#details + 1] = s[2] end
    end
  end
  if state then report.set(state, table.concat(details, "; ")) end
end

---------------------------------------------------------------- screens

-- The terminal: a tab per part running here, its page under the tab bar.
-- The monitor: a status board, a coloured tile per machine (lime idle,
-- yellow working, orange flat out, red needs you), and the parts' own
-- monitor pages (the cooking pots' Candy).
local display = screen.new(term.current())
-- a small monitor (2 or 3 blocks wide) takes small text: big text would leave room for a few tiles
local board = screen.find({ setting = "factory.monitor", scales = { 1, 0.5 }, minW = 30, minH = 12 })
local LEGEND = { { "lime", "idle" }, { "yellow", "working" }, { "orange", "flat out" }, { "red", "help" } }
local tab -- the id of the part whose page the terminal shows
local boardPage = "machines" -- or a part's id, for its monitor page
local tabZones, boardZones = {}, {} -- { x1, x2, action } on row 1

local function runningParts()
  local out = {}
  for _, p in ipairs(parts) do
    if running(p) then out[#out + 1] = p end
  end
  return out
end

-- The tab bar on row 1: a tab per { id, title, short }, the one whose id is
-- on lit, and Setup at the right. Every tab is shown: their titles, else
-- their short ones, else cut to share the room. Returns the tap zones.
local function tabBar(win, w, list, on)
  screen.put(win, 1, 1, (" "):rep(w), "white", "gray")
  local room = w - 8 -- " Setup " and a space before it
  local function width(labels)
    local n = 0
    for _, l in ipairs(labels) do n = n + #l + 2 end
    return n
  end
  local labels = {}
  for i, p in ipairs(list) do labels[i] = p.title end
  if width(labels) > room then
    for i, p in ipairs(list) do labels[i] = p.short or p.title end
  end
  if width(labels) > room and #list > 0 then
    local each = math.max(1, math.floor(room / #list) - 2)
    for i, l in ipairs(labels) do labels[i] = l:sub(1, each) end
  end
  local zones, x = {}, 1
  for i, p in ipairs(list) do
    local label = " " .. labels[i] .. " "
    if x + #label - 1 <= room then
      local lit = p.id == on
      screen.put(win, x, 1, label, lit and "black" or "white", lit and "yellow" or "gray")
      zones[#zones + 1] = { x, x + #label - 1, p.id }
      x = x + #label
    end
  end
  screen.put(win, w - 6, 1, " Setup ", "black", "lightGray")
  zones[#zones + 1] = { w - 6, w, "setup" }
  return zones
end

local function draw()
  local list = runningParts()
  local current = byId[tab]
  if not current or not running(current) then
    current = list[1]
    tab = current and current.id
  end
  local w = display:size()
  local key = { tab or "-", message[1], message[2] }
  for _, p in ipairs(list) do key[#key + 1] = p.id end
  if current then key[#key + 1] = current.key() end
  if display:same(table.concat(key, "|")) then return end

  local win, _, h = display:frame()
  if current then
    current.draw(win, w, h)
  else
    screen.put(win, 2, 3, "Nothing set up yet.", "white")
    local help = "Furnaces and botany pots on the cable are found by themselves. Mekanism machines"
      .. " (infusers too), Create crushers, washers and fans, Cobblemon cooking pots and the barrels"
      .. " botany pots empty into are added on the setup screen: tap Setup, press F1, or type"
      .. " 'factory setup' in another tab. A botany computer on a cable of its own: pick its ender chest as the"
      .. " work chest (Setup, Work chest), and every barrel and chest there is a pot barrel."
    for i, line in ipairs(screen.wrap(help, w - 2, h - 8)) do screen.put(win, 2, 4 + i, screen.fit(line, w - 2), "lightGray") end
    local msg = screen.wrap(message[1], w, 2)
    for i, line in ipairs(msg) do screen.put(win, 1, h - 1 - #msg + i, screen.fit(line, w), message[2]) end
    screen.put(win, 1, h, screen.fit("F1: setup", w), "gray")
  end
  tabZones = tabBar(win, w, list, tab)
  if #list == 0 then screen.put(win, 2, 1, "Factory", "yellow", "gray") end
  -- not "a and b and f()": that keeps only f's first result
  local cx, cy
  if current and current.cursor then cx, cy = current.cursor(w) end
  if cx and cy then
    win.setCursorPos(cx, cy)
    win.setTextColor(colors.white)
    win.setCursorBlink(true)
  end
  display:show()
end

local function drawBoard()
  if not board.target then return end
  local list = runningParts()
  -- the pages: the machines, then each part's own
  local pages = { { id = "machines", title = "Machines" } }
  for _, p in ipairs(list) do
    if p.monitorPage then pages[#pages + 1] = { id = p.id, title = p.monitorPage.title, page = p.monitorPage } end
  end
  local page = pages[1]
  for _, pg in ipairs(pages) do
    if pg.id == boardPage then page = pg end
  end
  boardPage = page.id
  local msg = worst()
  local tiles, working = {}, 0
  if not page.page then
    for _, p in ipairs(list) do
      for _, t in ipairs(p.tiles()) do
        tiles[#tiles + 1] = { t[1], t[2], t[3], t[3] == "red" and "white" or "black" }
        if t[3] == "yellow" or t[3] == "orange" then working = working + 1 end
      end
    end
  end
  local key = { boardPage, #pages, msg[1], msg[2] }
  if page.page then key[#key + 1] = page.page.key() end
  for _, t in ipairs(tiles) do key[#key + 1] = table.concat(t, "/") end
  if board:same(table.concat(key, "|")) then return end

  local bwin, w, h = board:frame()
  if #pages == 1 then
    boardZones = tabBar(bwin, w, {}, nil)
    screen.put(bwin, 2, 1, "Factory", "yellow", "gray")
  else
    boardZones = tabBar(bwin, w, pages, boardPage)
  end
  if page.page then
    page.page.draw(bwin, w, h)
    screen.put(bwin, 1, h, screen.fit(msg[1], w), msg[2])
  else
    -- how many are working, under the tabs
    if #tiles > 0 then
      screen.put(bwin, 2, 2, screen.fit(("%d of %d machines working"):format(working, #tiles), w - 2), "lightGray")
    end
    local left = screen.tiles(bwin, w, 3, h - 3, tiles)
    if left > 0 then
      local more = ("...and %d more: see the computer's tabs"):format(left)
      if #more > w - 2 then more = ("+%d more"):format(left) end
      screen.put(bwin, 2, h - 2, screen.fit(more, w - 2), "gray")
    end
    if #tiles == 0 then screen.put(bwin, 2, 3, screen.fit("No machines yet: tap Setup.", w - 2), "gray") end
    screen.put(bwin, 1, h - 1, screen.fit(msg[1], w), msg[2])
    screen.legend(bwin, 2, h, w - 2, LEGEND)
  end
  board:show()
end

---------------------------------------------------------------- the setup screen

-- What kind of found machine a name is, from the parts that find them.
local function foundMachines()
  local out = {}
  for _, p in ipairs(parts) do
    for _, m in ipairs(p.found()) do out[#out + 1] = { name = m.name, kind = m.kind, part = p } end
  end
  return out
end

local function ownerText(name)
  local who = ownerOf(name)
  if who == "me" then return "mine", "lime" end
  if who then return ("#%d's"):format(who), "gray" end
  return claims.released[name] and "given away" or "free", "lightGray"
end

-- Machines (found ones and their owner, then each part's added ones), the
-- chain, the work chest and the monitor, on one screen (lib/setupui.lua), on
-- screens (the terminal first). Each change is saved as it's made.
local function setupScreen(screens)
  local ui = setupui.new({ screens = screens, name = "factory" })
  local setParts = {
    byId.smelt.set:setupParts(ui), byId.enrich.set:setupParts(ui), byId.infuse.set:setupParts(ui),
    byId.cook.setupParts(ui), byId.essence.setupParts(ui),
  }

  local function machinesPage()
    return {
      title = "Machines",
      hint = "Tap a found one to take it or give it up; tap an added one to change it.",
      rows = function()
        local out = {}
        settle()
        for _, m in ipairs(foundMachines()) do
          local text, colour = ownerText(m.name)
          out[#out + 1] = { label = ("%s  %s"):format(m.kind, m.name), value = text, colour = colour, act = function()
            local who = ownerOf(m.name)
            if who == "me" then
              release(m.name)
              ui:say(("Gave up %s: another factory computer takes it."):format(m.name), "lime")
            else
              ui:say(("Taking %s..."):format(m.name), "lightBlue")
              ui:draw()
              local ok, why = claim(m.name)
              ui:say(ok and ("%s is this computer's now."):format(m.name) or ("Couldn't: %s."):format(why),
                ok and "lime" or "red")
            end
            f.wake()
          end }
        end
        for _, sp in ipairs(setParts) do
          for _, row in ipairs(sp.entries()) do out[#out + 1] = row end
        end
        -- the + Add rows: Mekanism's first while there's a Mekanism machine here or on
        -- the cable, else Create's (a Create-only world); the pots last
        local anyMek = false
        for _, set in ipairs({ byId.smelt.set, byId.enrich.set, byId.infuse.set }) do
          if #set:free() > 0 then anyMek = true end
          for _, e in ipairs(set:entries()) do
            if e.machine then anyMek = true end
          end
        end
        local function rank(row)
          if row.label:find("cooking pot", 1, true) or row.label:find("pot barrel", 1, true) then return 3 end
          local create = row.label:find("Create", 1, true) ~= nil
          return (create == anyMek) and 2 or 1
        end
        local adds = {}
        for _, sp in ipairs(setParts) do
          for _, row in ipairs(sp.adds()) do adds[#adds + 1] = row end
        end
        for i, row in ipairs(adds) do row.order = i end
        table.sort(adds, function(a, b)
          if rank(a) ~= rank(b) then return rank(a) < rank(b) end
          return a.order < b.order
        end)
        for _, row in ipairs(adds) do out[#out + 1] = row end
        return out
      end,
    }
  end

  local function chainPage()
    return {
      title = "Chain",
      hint = "What happens where. Tap a step to switch it on or off here.",
      rows = function()
        askPeers()
        local out = {}
        for _, p in ipairs(parts) do
          local where = {}
          if running(p) then where[#where + 1] = "here: " .. p.summary() end
          local ids = {}
          for id in pairs(peers) do ids[#ids + 1] = id end
          table.sort(ids)
          for _, id in ipairs(ids) do
            for _, s in ipairs(peers[id].stages or {}) do
              if s.id == p.id then where[#where + 1] = ("#%d: %s"):format(id, s.summary or "") end
            end
          end
          local off = claims.off[p.id]
          local value = off and "off here" or #where > 0 and table.concat(where, "; ") or "nobody: add a machine"
          -- the part's name: its description (p.what) and where it runs don't both fit on a row
          out[#out + 1] = { label = p.title, value = value,
            colour = off and "gray" or #where > 0 and "lightGray" or "orange", act = function()
              readClaims()
              claims.off[p.id] = not claims.off[p.id] or nil
              saveClaims()
              ui:say(("%s is %s on this computer."):format(p.title, claims.off[p.id] and "off" or "on"), "lime")
              f.wake()
            end }
          if p.id == "enrich" and p.compacts() then
            out[#out + 1] = { label = "Nuggets -> ingots", value = "the storage computer crafts them", colour = "gray" }
          end
        end
        return out
      end,
    }
  end

  ui:say("Tap a setting to change it.")
  ui:run({
    title = ("Factory #%d setup"):format(myId),
    rows = function()
      local n = 0
      for _, m in ipairs(foundMachines()) do
        if ownerOf(m.name) == "me" then n = n + 1 end
      end
      for _, sp in ipairs(setParts) do n = n + #sp.entries() end
      local on = {}
      for _, p in ipairs(runningParts()) do on[#on + 1] = p.title end
      return {
        { label = "Machines", value = ("%d here"):format(n), act = function() ui:open(machinesPage()) end },
        { label = "Chain", value = #on > 0 and table.concat(on, ", ") or "nothing yet",
          act = function() ui:open(chainPage()) end },
        { label = "Work chest", value = work:describe(), act = function() ui:open(work:setupPage(ui)) end },
        { label = "Monitor", value = setupui.monitorText("factory.monitor"),
          act = function() ui:monitorPage("factory.monitor", "factory_monitor") end },
      }
    end,
  })
  f.wake() -- a round straight away, with the changes
end

---------------------------------------------------------------- loops

-- Typing, clicks and taps: drawn straight away.
local INPUT_EVENTS = { char = true, key = true, paste = true, mouse_click = true, mouse_scroll = true,
  monitor_touch = true, term_resize = true, monitor_resize = true }
-- What changes the screens without the player: drawn REDRAW_GAP later, so a
-- burst draws once. Everything else (rednet messages, other loops' timers)
-- leaves the screens alone: on a busy network redrawing on every event kept
-- the computer busy.
local CHANGE_EVENTS = { factory_changed = true, factory_added = true, factory_monitor = true, peripheral = true, peripheral_detach = true }

local function uiLoop()
  local soon, beat, redraw = nil, os.startTimer(REDRAW_EVERY), true
  while true do
    if redraw then
      redraw = false
      draw()
      drawBoard()
    end
    local ev = { os.pullEvent() }
    local event = ev[1]
    if event == "peripheral" or event == "peripheral_detach" or event == "factory_added" then forgetActive() end
    if event == "peripheral" or event == "peripheral_detach" or event == "factory_monitor" then board:refresh() end
    if event == "timer" and ev[2] == soon then
      soon, redraw = nil, true
    elseif event == "timer" and ev[2] == beat then
      beat, redraw = os.startTimer(REDRAW_EVERY), true
    elseif CHANGE_EVENTS[event] then
      soon = soon or os.startTimer(REDRAW_GAP)
    elseif INPUT_EVENTS[event] then
      redraw = true
    end
    local bx, by = board:clicked(ev)
    local tx, ty = display:clicked(ev)
    local function zoneAt(zones, x)
      for _, z in ipairs(zones) do
        if x >= z[1] and x <= z[2] then return z[3] end
      end
    end
    local tapTab = tx and ty == 1 and zoneAt(tabZones, tx)
    local tapBoard = bx and by == 1 and zoneAt(boardZones, bx)
    if setupui.wanted("factory", ev) or tapTab == "setup" or tapBoard == "setup" or (event == "key" and ev[2] == keys.f1) then
      setupScreen({ display, board })
      redraw = true
    elseif tapTab then
      tab = tapTab
    elseif tapBoard then
      boardPage = tapBoard
    elseif bx and by > 1 and byId[boardPage] and byId[boardPage].monitorPage and byId[boardPage].monitorPage.touch then
      -- a part's own monitor page (the infuser's request buttons)
      if byId[boardPage].monitorPage.touch(bx, by) then board.last = nil end
    elseif event == "key" and ev[2] == keys.tab then
      local list = runningParts()
      for i, p in ipairs(list) do
        if p.id == tab then
          tab = (list[i % #list + 1] or p).id
          break
        end
      end
    elseif byId[tab] and running(byId[tab]) and event ~= "factory_added" then
      -- everything else goes to the page showing (typing, its keys, clicks)
      if byId[tab].event(ev, tx, ty) then display.last, redraw = nil, true end
    end
  end
end

local function workLoop()
  while true do
    local ok, err = (errlog and errlog.pcall or pcall)(round)
    if not ok then message = { "Error: " .. tostring(err), "red" } end
    reportStatus()
    os.queueEvent("factory_changed")
    -- a machine added from another tab starts straight away
    local timer = os.startTimer(EVERY)
    repeat
      local event, value = os.pullEvent()
      if event == "factory_added" then due = {} end
    until (event == "timer" and value == timer) or event == "factory_added"
  end
end

-- Other factory computers ask what this one takes and owns, ask it to let
-- go of a machine ('give'), or hand it some ('take').
local function netLoop()
  -- the id too: rednet won't let two computers host under one name, and labels can be the same
  rednet.host(PROTOCOL, ("%s-%d"):format(os.getComputerLabel() or "factory", myId))
  while true do
    local from, msg = rednet.receive(PROTOCOL)
    if type(msg) == "table" then
      if msg.type == "hello" then
        net.answer(from, PROTOCOL, msg, hello())
      elseif msg.type == "give" and type(msg.names) == "table" then
        for _, name in ipairs(msg.names) do
          if claims.mine[name] then release(name) end
        end
        net.answer(from, PROTOCOL, msg, { ok = true })
        f.wake()
      elseif msg.type == "take" and type(msg.names) == "table" then
        readClaims()
        for _, name in ipairs(msg.names) do claims.mine[name], claims.released[name] = os.epoch("utc"), nil end
        saveClaims()
        net.answer(from, PROTOCOL, msg, { ok = true })
        f.wake()
      else
        -- the storage computer ordering from a part (the infuser, the essence
        -- farm); a cancel goes to every part, as only the one with the job acts on it
        local answered = false
        for _, p in ipairs(parts) do
          local reply = p.request and p.request(from, msg)
          if reply and not answered then
            net.answer(from, PROTOCOL, msg, reply)
            answered = true
            if msg.type ~= "cancel" then break end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------- commands

local KINDS = { -- 'factory add <kind>': which part and how
  chamber = { part = "enrich" }, crusher = { part = "enrich", line = true }, washer = { part = "enrich", line = true },
  smelter = { part = "smelt" }, fan = { part = "smelt", line = true }, smokefan = { part = "smelt", line = true },
  infuser = { part = "infuse", extra = true }, pot = { part = "cook" }, potbarrel = { part = "essence" },
}

-- Every machine added here, numbered for 'factory remove': { text, remove() }.
local function listed()
  local out = {}
  for _, id in ipairs({ "enrich", "smelt", "infuse" }) do
    local set = byId[id].set
    local list = set:entries()
    local titles = set:titles(list)
    for i, e in ipairs(list) do
      local text = e.line and ("%s: fed by %s, out to %s"):format(titles[i], e.feeder, e.output or "a storage input chest")
        or ("%s: %s, fed by %s%s, out to %s"):format(titles[i], e.machine, e.feeder,
          e.extra and (" and " .. e.extra) or "", e.output or "the chest under it")
      out[#out + 1] = { text = text, remove = function()
        local now = set:entries()
        table.remove(now, i)
        set:save(now)
        return ("Forgot %s. Empty its feeder%s%s by hand."):format(e.machine or e.feeder, e.extra and "s" or "",
          e.output and " and output chest" or "")
      end }
    end
  end
  for _, row in ipairs(byId.cook.listed()) do out[#out + 1] = row end
  for _, row in ipairs(byId.essence.listed()) do out[#out + 1] = row end
  return out
end

local function needModem()
  if net.open("any") then return true end
  print("I need a wired modem on the storage computer's network first (far away: an ender modem too).")
  return false
end

local args = { ... }
local verb = args[1]
if verb == "add" then
  local kind = KINDS[args[2] or ""]
  if not kind then
    print("Usage: factory add <kind> ...")
    print("  chamber, smelter [machine feeder [output]]  (Mekanism)")
    print("  infuser [machine feeder extra output]  (Mekanism)")
    print("  crusher, washer, fan, smokefan [feeder [output]]  (Create)")
    print("  pot [recipe feed output relay]  (Cobblemon)")
    print("  potbarrel [barrel | all]  (the barrel Hopper Botany Pots empty into; all: every free one)")
    return
  end
  if not needModem() then return end
  askPeers(true)
  refreshUses()
  if kind.part == "cook" then
    byId.cook.addCommand(args[3], args[4], args[5], args[6])
  elseif kind.part == "essence" then
    byId.essence.addCommand(args[3])
  elseif kind.extra then
    byId[kind.part].set:add(args[3], args[4], args[6], args[5])
  elseif kind.line then
    byId[kind.part].set:add(args[2], args[3], args[4])
  else
    byId[kind.part].set:add(args[3], args[4], args[5])
  end
  return
elseif verb == "list" or verb == "remove" then
  local list = listed()
  local n = tonumber(args[2] or "")
  if verb == "remove" and n and list[n] then
    print(list[n].remove())
    return
  end
  for i, row in ipairs(list) do print(("%2d  %s"):format(i, row.text)) end
  if #list == 0 then print("No machines added here yet.") end
  if verb == "list" then
    if needModem() then askPeers(true) end
    refreshUses()
    local found = foundMachines()
    if #found > 0 then print("Found on the cable:") end
    for _, m in ipairs(found) do print(("    %-14s %-28s %s"):format(m.kind, m.name, (ownerText(m.name)))) end
  else
    print("Usage: factory remove <number>")
  end
  return
elseif verb == "give" then
  local id = tonumber(args[3] or "")
  if not args[2] or not id then
    print("Usage: factory give <name|all> <computer id>")
    return
  end
  if not needModem() then return end
  local names = {}
  for name in pairs(readClaims().mine) do
    if args[2] == "all" or args[2] == name then names[#names + 1] = name end
  end
  if #names == 0 then
    print(("This computer has no %s to give."):format(args[2] == "all" and "found machines" or args[2]))
    return
  end
  local reply = net.ask(id, PROTOCOL, { type = "take", names = names }, { wait = PEER_WAIT })
  if not reply or not reply.ok then
    print(("Factory computer %d didn't answer: is it running, with a modem on this cable?"):format(id))
    return
  end
  for _, name in ipairs(names) do release(name) end
  print(("Gave %d machine(s) to computer %d."):format(#names, id))
  return
elseif verb == "monitor" then
  local pick = screen.choose("factory.monitor", args[2])
  if pick then
    -- a factory running in another tab moves to it now
    os.queueEvent("factory_monitor")
    print(pick == "none" and "No status board from now on." or ("The status board goes on %s."):format(pick))
  end
  return
elseif verb == "chest" then
  if needModem() then work:command(args[2]) end
  return
elseif verb == "setup" then
  if setupui.openInRunning("factory") then
    print("The setup screen is open in the factory (its tab) and on its monitor.")
    return
  end
  if not needModem() then return end
  askPeers(true)
  setupScreen({ display, board })
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)
  print("Setup saved. The factory uses it on its next round.")
  return
elseif verb then
  for _, p in ipairs(parts) do
    if p.command(args) then return end
  end
  print("Usage: factory [setup | add <kind> | list | remove [n] | give <name|all> <id> | relay <n> | charcoal <n> |")
  print("  stone <n> | glass <n> | smelt [what n] | cancel [n] | infuse [what n | cancel] | find <text> | make <n> <text> |")
  print("  chest [name|none|remote] | monitor]")
  return
end

if not net.open("any") then
  print("I need a wired modem on the storage computer's network (far away: on my own, plus an ender modem).")
  print("Put one on me, join it to the network with cable and right-click it so it turns red.")
  return
end

term.clear()
if errlog then errlog.init("factory") end
if report then report.init("factory") end
-- a part may run a loop of its own (the essence farm answers its crafting turtles)
local loops = { uiLoop, workLoop, netLoop, function() net.keepOpen("any") end,
  report and report.loop or function() while true do sleep(3600) end end }
for _, p in ipairs(parts) do
  if p.loop then loops[#loops + 1] = p.loop end
end
local ok, err = (errlog and errlog.pcall or pcall)(parallel.waitForAny, table.unpack(loops))
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  if report then pcall(report.set, "error", tostring(err)) end
  error(err, 0)
end
