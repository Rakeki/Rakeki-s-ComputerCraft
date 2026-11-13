-- The factory's Applied Energistics 2 part (factory.lua loads it). Runs the
-- AE2 machines on the cable, found by themselves like furnaces:
--   Inscribers     printed circuits (with the press in the top slot), the
--                  three processors, certus / sky stone / ender / fluix dust,
--                  and copies of the presses (a block of iron)
--   Chargers       charged certus quartz, the meteorite compass
--   Vibration chambers  kept fuelled from the fuel chest (they power the network)
-- Inscribers and chargers only work on request: tap +1, +8 or +64 on the
-- AE2 page (terminal or the monitor's AE2 page), type 'factory ae2 <name>
-- <count>', or let the craft overseer ask: it's told what the machines here
-- can make (via "ae2"), so a crafting plan that needs a logic processor has
-- this make it, printed circuits first.
--
-- An inscriber is seen through its own inventory (Separate Sides off, the
-- default): slot 1 top, 2 bottom, 3 middle, 4 the result, which is taken out
-- into storage and counted. A press is never taken out: an inscriber with
-- one in its top slot makes only that press's circuits. A request for
-- printed circuits with no inscriber holding its press puts the press from
-- storage into an empty one (config: presses), always leaving one inscriber
-- without a press for processors and dust. A charger takes one item at a
-- time and gives back the charged one in the same slot.
--
-- Not run: the Molecular Assembler (the ME system and crafting turtles
-- craft), the Condenser (it destroys what goes in, and CC can't set its
-- mode), the Crystal Growth Accelerator (it has no inventory).
local screen = require("lib.screen") -- flicker-free drawing
local files = require("lib.files") -- crash-safe save files

local M = {}

local REQUEST_DIR = "/.factory_ae2" -- a file per request, so a request typed in another tab is never lost
local GIVE_UP = 600 -- seconds a craft overseer's request may go with nothing loaded or made before it's handed back
local RESEND_AFTER = 30 -- seconds with everything sent, none of it in a machine and nothing made, before the rest is sent again
local STUCK_AFTER = 60 -- seconds an inscriber's contents may stay the same with nothing made before it's shown as stuck
local ORDER_EVERY = 30 -- seconds between asking the craft overseer to make a request's missing input
local MAKES_EVERY = 60 -- seconds between telling the craft overseer what the machines here can make
local CHAMBER_LOW = 64 -- smelts' worth of fuel in a vibration chamber below which it's topped up (8 coal)
local CHAMBER_FILL = 256 -- smelts' worth it's topped up to (32 coal)
local QUEUE_SHOWN = 3 -- requests listed under the recipes
local BUTTONS = { 1, 8, 64 } -- the request buttons by each recipe
-- fuel a vibration chamber burns, as the storage computer sends it, with smelts per item
local FUELS = { ["minecraft:charcoal"] = 8, ["minecraft:coal"] = 8, ["minecraft:coal_block"] = 80 }

local TYPES = { -- peripheral type -> kind
  ["ae2:inscriber"] = "inscriber", ["ae2:charger"] = "charger", ["ae2:vibration_chamber"] = "chamber",
}
local KIND_TITLE = { inscriber = "Inscriber", charger = "Charger", chamber = "Vibration chamber" }

-- AE2's own recipes (1.20 / 1.21). machine: inscriber or charger; middle:
-- what goes in the middle slot (the charger's only slot); top / bottom: the
-- inscriber's other slots; keep: top and bottom aren't used up (presses).
local RECIPES = {
  { make = "ae2:printed_calculation_processor", middle = "ae2:certus_quartz_crystal", top = "ae2:calculation_processor_press", keep = true },
  { make = "ae2:printed_engineering_processor", middle = "minecraft:diamond", top = "ae2:engineering_processor_press", keep = true },
  { make = "ae2:printed_logic_processor", middle = "minecraft:gold_ingot", top = "ae2:logic_processor_press", keep = true },
  { make = "ae2:printed_silicon", middle = "ae2:silicon", top = "ae2:silicon_press", keep = true },
  { make = "ae2:calculation_processor", top = "ae2:printed_calculation_processor", middle = "minecraft:redstone", bottom = "ae2:printed_silicon" },
  { make = "ae2:engineering_processor", top = "ae2:printed_engineering_processor", middle = "minecraft:redstone", bottom = "ae2:printed_silicon" },
  { make = "ae2:logic_processor", top = "ae2:printed_logic_processor", middle = "minecraft:redstone", bottom = "ae2:printed_silicon" },
  { make = "ae2:certus_quartz_dust", middle = "ae2:certus_quartz_crystal" },
  { make = "ae2:sky_dust", middle = "ae2:sky_stone_block" },
  { make = "ae2:ender_dust", middle = "minecraft:ender_pearl" },
  { make = "ae2:fluix_dust", middle = "ae2:fluix_crystal" },
  { make = "ae2:calculation_processor_press", middle = "minecraft:iron_block", top = "ae2:calculation_processor_press", keep = true, title = "Calculation press copy" },
  { make = "ae2:engineering_processor_press", middle = "minecraft:iron_block", top = "ae2:engineering_processor_press", keep = true, title = "Engineering press copy" },
  { make = "ae2:logic_processor_press", middle = "minecraft:iron_block", top = "ae2:logic_processor_press", keep = true, title = "Logic press copy" },
  { make = "ae2:silicon_press", middle = "minecraft:iron_block", top = "ae2:silicon_press", keep = true, title = "Silicon press copy" },
  { make = "ae2:charged_certus_quartz_crystal", middle = "ae2:certus_quartz_crystal", machine = "charger" },
  { make = "ae2:meteorite_compass", middle = "minecraft:compass", machine = "charger" },
}

local function nice(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function capital(text) return (text:gsub("^%l", string.upper)) end

local function escape(name) return "^" .. name:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "$" end

-- Every AE2 machine on the wired network (not ones touching this computer:
-- the storage computer can't reach those), sorted by name.
local function findMachines()
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local kind = not sides[name] and TYPES[peripheral.getType(name) or ""]
    if kind then list[#list + 1] = { name = name, kind = kind } end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- f: the factory (factory.lua): ask, craft, work, config, mine, wake, changed, log.
function M.new(f)
  local config = f.config("ae2")
  local KEEP = config.keep or {} -- item -> how many to leave in storage
  local HIDE = config.hide or {} -- recipes not to make, by what they make
  local OFFER = config.offer ~= false -- tell the craft overseer what the machines here can make
  local ORDER = config.order ~= false -- have the craft overseer make a request's short input
  local PRESSES = config.presses ~= false -- put a press from storage into an empty inscriber when a request needs it
  local CHAMBERS = config.chambers ~= false -- keep vibration chambers fuelled
  local NAMES = config.names or {} -- peripheral name -> its name on the screen

  -- the recipes: AE2's, then config's own (one for the same make and middle
  -- takes its place), less the hidden ones
  local recipes, byKey, byMake = {}, {}, {}
  do
    local hidden = {}
    for _, name in ipairs(HIDE) do hidden[name] = true end
    for _, list in ipairs({ RECIPES, config.recipes or {} }) do
      for _, r in ipairs(list) do
        if type(r) == "table" and type(r.make) == "string" and type(r.middle) == "string" and not hidden[r.make] then
          local rc = { make = r.make, middle = r.middle, top = r.top, bottom = r.bottom, keep = r.keep and true or false,
            machine = r.machine == "charger" and "charger" or "inscriber", count = math.max(1, math.floor(tonumber(r.count) or 1)),
            title = r.title or capital(nice(r.make)) }
          if rc.machine == "charger" then rc.top, rc.bottom, rc.keep = nil, nil, false end
          if not rc.top and not rc.bottom then rc.keep = false end
          rc.key = rc.make .. "<" .. rc.middle
          local old = byKey[rc.key]
          if old then
            for i, x in ipairs(recipes) do
              if x == old then recipes[i] = rc end
            end
          else
            recipes[#recipes + 1] = rc
          end
          byKey[rc.key] = rc
        end
      end
    end
    for _, rc in ipairs(recipes) do
      byMake[rc.make] = byMake[rc.make] or {}
      table.insert(byMake[rc.make], rc)
    end
  end

  -- What a recipe uses up per craft: middle, and top / bottom unless they stay.
  local function usedUp(rc)
    local out = { rc.middle }
    if not rc.keep then
      if rc.top then out[#out + 1] = rc.top end
      if rc.bottom then out[#out + 1] = rc.bottom end
    end
    return out
  end

  local self = { id = "ae2", title = "AE2", short = "AE2", rank = 0, every = 5,
    what = "Requests -> processors, charged certus, dust" }
  local machines = {} -- this round's: { name, kind, title, slots, size, state, tile }
  local requests = {} -- every request, oldest first (REQUEST_DIR)
  local counts = {} -- the storage computer's counts, for the screen
  local shown = {} -- the recipes the page lists
  local progress = {} -- request at -> when it last had something loaded or made (os.clock)
  local stuck = {} -- inscriber name -> { sig, since }: its contents and since when they're unchanged
  local limits = {} -- inscriber name -> { [slot] = most it holds }, read once
  local news -- { text, colour, untilTime }
  local makesKey, makesAt, makesNote = nil, -math.huge, nil
  local scroll, picked = 0, 1
  local zones = {}
  self.message = { "Looking for the storage computer...", "lightGray" }
  self.status = { "starting", "" }

  local function say(text, colour)
    self.message = { text, colour or "lightGray" }
    f.changed()
  end

  local function tell(text, colour)
    news = { text, colour, os.clock() + 60 }
    say(text, colour)
  end

  local function status(state, detail) self.status = { state, detail } end

  local function mine()
    local out = {}
    for _, m in ipairs(findMachines()) do
      if f.mine(m.name) then out[#out + 1] = m end
    end
    return out
  end

  function self.found()
    local out = {}
    for _, m in ipairs(findMachines()) do out[#out + 1] = { name = m.name, kind = KIND_TITLE[m.kind] } end
    return out
  end

  function self.uses() return {} end

  function self.active() return #mine() > 0 end

  local function have(kind)
    for _, m in ipairs(machines) do
      if m.kind == kind then return true end
    end
    return false
  end

  ---------------------------------------------------------------- requests

  local function loadRequests()
    local list = {}
    if fs.isDir(REQUEST_DIR) then
      for _, file in ipairs(fs.list(REQUEST_DIR)) do
        local r = files.read(REQUEST_DIR .. "/" .. file)
        if type(r) == "table" and type(r.count) == "number" and type(r.key) == "string" then
          r.file = REQUEST_DIR .. "/" .. file
          r.made, r.sent = r.made or 0, r.sent or 0
          r.recipe = byKey[r.key]
          list[#list + 1] = r
        end
      end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    return list
  end

  local function plain(r)
    return { key = r.key, count = r.count, made = r.made, sent = r.sent, at = r.at, job = r.job, done = r.done,
      ok = r.ok, why = r.why }
  end

  -- Only while its file is there: a request cancelled in another tab stays cancelled.
  local function saveRequest(r)
    if fs.exists(r.file) then files.write(r.file, plain(r)) end
  end

  local function newRequest(key, count, job)
    if not fs.isDir(REQUEST_DIR) then fs.makeDir(REQUEST_DIR) end
    local at = os.epoch("utc")
    local file = ("%s/%.0f"):format(REQUEST_DIR, at)
    while fs.exists(file) do
      at = at + 1
      file = ("%s/%.0f"):format(REQUEST_DIR, at)
    end
    files.write(file, { key = key, count = count, made = 0, sent = 0, at = at, job = job })
    return file
  end

  -- count more of what rc makes: added to a request of yours for it that's still waiting, else a new one
  local function request(rc, count)
    count = math.ceil(count / rc.count) * rc.count
    for _, q in ipairs(loadRequests()) do
      if q.key == rc.key and not q.job and not q.done then
        q.count = q.count + count
        saveRequest(q)
        f.wake()
        return count
      end
    end
    newRequest(rc.key, count)
    f.wake()
    return count
  end

  local function left(q) return math.max(0, q.count - q.made) end
  local function toSend(q) return math.max(0, math.ceil(q.count / q.recipe.count) - q.sent) end

  local function spare(avail, name) return math.max(0, (avail[name] or 0) - (KEEP[name] or 0)) end

  -- How many of what rc makes what's stored would do (a press it keeps isn't counted).
  local function canMake(rc, avail)
    local n = math.huge
    for _, name in ipairs(usedUp(rc)) do n = math.min(n, spare(avail, name)) end
    return n * rc.count
  end

  -- What came out, counted towards the requests for it, oldest first.
  local function credit(name, n)
    for _, q in ipairs(requests) do
      if n <= 0 then return end
      if not q.done and q.recipe and q.recipe.make == name then
        local k = math.min(n, left(q))
        if k > 0 then
          q.made, n = q.made + k, n - k
          progress[q.at], q.dirty = os.clock(), true
        end
      end
    end
  end

  -- A request made here (not the overseer's: its plan already makes the
  -- inputs first) whose input is short has the craft overseer make the rest:
  -- printed circuits for a processor, silicon for printed silicon. 'prepare'
  -- tops up to a total, so asking again never orders twice.
  local orderAt, orderNote = {}, {}
  local function orderInputs(avail)
    local need = {}
    for _, q in ipairs(requests) do
      if ORDER and q.recipe and not q.job and not q.done then
        for _, name in ipairs(usedUp(q.recipe)) do need[name] = (need[name] or 0) + toSend(q) end
      end
    end
    local now = os.clock()
    for item, n in pairs(need) do
      local got = spare(avail, item)
      if n <= got then
        orderNote[item] = nil
      elseif now - (orderAt[item] or -math.huge) >= ORDER_EVERY then
        orderAt[item] = now
        local reply = f.craft({ type = "prepare", items = { [item] = (avail[item] or 0) + n - got } }, 5)
        local making = reply and type(reply.crafting) == "table" and tonumber(reply.crafting[item]) or 0
        local why = reply and type(reply.cantCraft) == "table" and reply.cantCraft[item]
        orderNote[item] = not reply and "no craft overseer answered"
          or why and ("can't be made: " .. tostring(why))
          or making > 0 and ("making %d first"):format(making)
          or nil
      end
    end
    for item in pairs(orderNote) do
      if not need[item] then orderNote[item], orderAt[item] = nil, nil end
    end
  end

  ---------------------------------------------------------------- the craft overseer

  -- The presses in an inscriber here.
  local function pressesHere()
    local out = {}
    for _, m in ipairs(machines) do
      if m.kind == "inscriber" and m.slots[1] then out[m.slots[1].name] = true end
    end
    return out
  end

  -- Can a machine here run rc (now, or once a press from storage is put in)?
  local function runnable(rc, presses)
    if rc.machine == "charger" then return have("charger") end
    if not have("inscriber") then return false end
    if rc.keep then return presses[rc.top] or (PRESSES and (counts[rc.top] or 0) > 0) or false end
    return true
  end

  -- The recipes as the overseer plans them: a row of top, middle, bottom
  -- (only what's used up: a press stays in the inscriber).
  local function asCrafts()
    local out, presses = {}, pressesHere()
    for _, rc in ipairs(recipes) do
      if runnable(rc, presses) then
        local row, keys = "", {}
        local function add(letter, item)
          if item then
            row = row .. letter
            keys[letter] = item
          end
        end
        add("A", not rc.keep and rc.top or nil)
        add("B", rc.middle)
        add("C", not rc.keep and rc.bottom or nil)
        out[#out + 1] = { make = rc.make, count = rc.count, rows = { row }, keys = keys }
      end
    end
    return out
  end

  local function offer()
    if not OFFER then return end
    local crafts = asCrafts()
    local key = tostring(#crafts)
    for _, c in ipairs(crafts) do key = key .. "," .. c.make .. "<" .. c.keys.B end
    if key == makesKey and os.clock() - makesAt < MAKES_EVERY then return end
    if #crafts == 0 and makesKey == nil then return end
    local reply = f.craft({ type = "makes", via = "ae2", recipes = crafts }, 5)
    makesAt = os.clock()
    if reply and reply.ok then
      makesKey, makesNote = key, nil
    else
      makesKey = nil
      makesNote = reply and reply.error or nil
    end
  end

  -- A craft overseer's request is finished (or given up on): tell it. True once it has heard.
  local function report(q)
    if not q.job then return true end
    return f.craft({ type = "jobdone", job = q.job, ok = q.ok, why = q.why }, 5) ~= nil
  end

  -- From the craft overseer (factory protocol): 'ae2' (make this for one of its plans) and 'cancel'.
  function self.request(_, msg)
    if msg.type == "ae2" then
      if not self.active() then return { ok = false, why = "no AE2 machines here" } end
      local grid = type(msg.grid) == "table" and msg.grid or {}
      local rc
      for _, x in ipairs(byMake[tostring(msg.make)] or {}) do
        for _, item in pairs(grid) do
          if item == x.middle then rc = rc or x end
        end
      end
      local count = math.floor(tonumber(msg.count) or 0)
      if not rc or count < 1 then return { ok = false, why = "no AE2 recipe here for it" } end
      newRequest(rc.key, count, msg.job)
      f.wake()
      return { ok = true }
    elseif msg.type == "cancel" then
      for _, q in ipairs(loadRequests()) do
        if q.job and q.job == msg.job then fs.delete(q.file) end
      end
      f.wake()
      return { ok = true }
    end
    return nil
  end

  -- What the smelter leaves alone: what open requests use up.
  local taking = {}
  function self.takes() return taking end

  function self.summary()
    local n = { inscriber = 0, charger = 0, chamber = 0 }
    for _, m in ipairs(mine()) do n[m.kind] = n[m.kind] + 1 end
    local parts = {}
    for _, kind in ipairs({ "inscriber", "charger", "chamber" }) do
      if n[kind] > 0 then parts[#parts + 1] = ("%d %s%s"):format(n[kind], KIND_TITLE[kind]:lower(), n[kind] == 1 and "" or "s") end
    end
    local waiting = 0
    for _, q in ipairs(requests) do
      if not q.done then waiting = waiting + 1 end
    end
    if waiting > 0 then parts[#parts + 1] = ("%d requests"):format(waiting) end
    return table.concat(parts, ", ")
  end

  ---------------------------------------------------------------- a round

  -- Every machine read at once (each call takes a tick).
  function self.read()
    local list = mine()
    local counted = { inscriber = 0, charger = 0, chamber = 0 }
    local jobs = {}
    for _, m in ipairs(list) do
      counted[m.kind] = counted[m.kind] + 1
      m.title = NAMES[m.name] or ("%s %d"):format(KIND_TITLE[m.kind], counted[m.kind])
      jobs[#jobs + 1] = function()
        local ok, slots = pcall(peripheral.call, m.name, "list")
        m.slots = ok and type(slots) == "table" and slots or {}
        if m.kind == "inscriber" then
          local okSize, size = pcall(peripheral.call, m.name, "size")
          m.size = okSize and size or 0
          if m.size == 4 and not limits[m.name] then
            local lim = {}
            for slot = 1, 3 do
              local okL, n = pcall(peripheral.call, m.name, "getItemLimit", slot)
              lim[slot] = okL and tonumber(n) or 64
            end
            limits[m.name] = lim
          end
        end
      end
    end
    if #jobs > 0 then parallel.waitForAll(table.unpack(jobs)) end
    machines = list
    requests = loadRequests()
    local seen = {}
    taking = {}
    for _, q in ipairs(requests) do
      if q.recipe and not q.done then
        for _, name in ipairs(usedUp(q.recipe)) do
          if not seen[name] then
            seen[name] = true
            taking[#taking + 1] = escape(name)
          end
        end
      end
    end
  end

  -- Does an inscriber's contents fit rc (more of it can go in)?
  local function fits(m, rc)
    local top, bottom, mid = m.slots[1], m.slots[2], m.slots[3]
    if mid and mid.name ~= rc.middle then return false end
    if rc.keep then
      -- the press must be in already; nothing else but its own bottom
      if not top or top.name ~= rc.top then return false end
      if rc.bottom then return bottom ~= nil and bottom.name == rc.bottom end
      return bottom == nil
    end
    if top and top.name ~= rc.top then return false end
    if bottom and bottom.name ~= rc.bottom then return false end
    return true
  end

  local function isPress(name)
    for _, rc in ipairs(recipes) do
      if rc.keep and (rc.top == name or rc.bottom == name) then return true end
    end
    return false
  end

  local function empty(m) return not m.slots[1] and not m.slots[2] and not m.slots[3] end

  function self.round(r)
    local work = f.work
    counts = r.stock.counts
    local input = r.input
    local problem = r.feedProblem
    offer()
    if #machines == 0 then
      say("No AE2 machines yet: join inscribers, chargers or vibration chambers to the cable with wired modems.", "orange")
      status("waiting", "no machines")
      return
    end
    local avail = {}
    for name, n in pairs(counts) do avail[name] = n end
    local now = os.clock()

    -- results out first (an inscriber's slot 4; a charger's one slot once
    -- what's in it isn't something it charges), counted towards the requests
    local chargeable = {}
    for _, rc in ipairs(recipes) do
      if rc.machine == "charger" then chargeable[rc.middle] = true end
    end
    local blocked = false
    for _, m in ipairs(machines) do
      local slot = m.kind == "inscriber" and m.size == 4 and 4 or m.kind == "charger" and 1 or nil
      local item = slot and m.slots[slot]
      if item and not (m.kind == "charger" and chargeable[item.name]) then
        local ok, moved = pcall(peripheral.call, m.name, "pushItems", input, slot)
        if not ok then problem, moved = tostring(moved), 0 end
        if moved > 0 then credit(item.name, moved) end
        if moved < item.count then blocked = true else m.slots[slot] = nil end
      end
    end

    -- finished requests: done, or a craft overseer's that waited too long
    for _, q in ipairs(requests) do
      progress[q.at] = progress[q.at] or now
      if not q.done and not q.recipe then
        q.done, q.ok, q.why = true, false, "this factory has no AE2 recipe for it any more"
      elseif not q.done and left(q) == 0 then
        q.done, q.ok = true, true
        if not q.job then tell(("Made %d %s."):format(q.made, q.recipe.title), "lime") end
        f.log(("made %d %s%s"):format(q.made, q.recipe.title, q.job and " for the craft overseer" or ""))
      elseif q.job and not q.done and now - progress[q.at] > GIVE_UP then
        q.done, q.ok, q.why = true, false, q.state or "nothing to make it from"
      end
      if q.done then
        saveRequest(q)
        if report(q) and fs.exists(q.file) then fs.delete(q.file) end
      end
    end
    local open = {}
    for _, q in ipairs(requests) do
      if not q.done and fs.exists(q.file) then open[#open + 1] = q end
    end
    requests = open

    -- everything sent, nothing of it left in a machine, not all made, a
    -- while since anything happened: what didn't come back is sent again
    for _, q in ipairs(requests) do
      local rc = q.recipe
      if toSend(q) == 0 and left(q) > 0 and now - progress[q.at] > RESEND_AFTER then
        local inside = false
        for _, m in ipairs(machines) do
          local s = m.kind == "inscriber" and m.slots[3] or m.kind == "charger" and m.slots[1] or nil
          if s and s.name == rc.middle then inside = true end
        end
        if not inside then
          q.sent = math.ceil(q.made / rc.count)
          q.dirty, progress[q.at] = true, now
        end
      end
    end

    -- what goes where: { item, to, slot, n, q (middle loads count as sent), fuel }
    local loads = {}
    local used = {} -- machine name -> taken by a request this round
    local function load(item, m, slot, n, q)
      if n <= 0 then return end
      loads[#loads + 1] = { item = item, to = m.name, slot = slot, n = n, q = q }
      avail[item] = (avail[item] or 0) - n
      if q then q.plan = (q.plan or 0) + n end
    end
    -- what a request still has to send, less what's planned this round
    local function want(q) return toSend(q) - (q.plan or 0) end

    local inscribers, chargers, chambers = {}, {}, {}
    for _, m in ipairs(machines) do
      m.state, m.tile = nil, nil
      if m.kind == "inscriber" then
        if m.size ~= 4 then
          m.state, m.tile = "turn its Separate Sides off", "red"
        else
          inscribers[#inscribers + 1] = m
        end
      elseif m.kind == "charger" then
        chargers[#chargers + 1] = m
      else
        chambers[#chambers + 1] = m
      end
    end
    -- inscribers without a press, so one is always kept free of them
    local function pressFree()
      local n = 0
      for _, m in ipairs(inscribers) do
        if not (m.slots[1] and isPress(m.slots[1].name)) and not m.pressIn then n = n + 1 end
      end
      return n
    end

    for _, q in ipairs(requests) do
      q.state, q.plan = nil, 0
      local rc = q.recipe
      if rc.machine == "inscriber" then
        local any = false
        for _, m in ipairs(inscribers) do
          if not used[m.name] and want(q) > 0 and fits(m, rc) then
            any = true
            used[m.name] = true
            local lim = limits[m.name] or { 64, 64, 64 }
            local function count(slot) return m.slots[slot] and m.slots[slot].count or 0 end
            local mid = count(3)
            local k = math.min(want(q), lim[3] - mid, spare(avail, rc.middle))
            if not rc.keep then
              for _, s in ipairs({ { 1, rc.top }, { 2, rc.bottom } }) do
                if s[2] then k = math.min(k, lim[s[1]] - mid, spare(avail, s[2]) + count(s[1]) - mid) end
              end
            end
            k = math.max(0, k)
            if not rc.keep then
              -- top and bottom kept level with the middle (one of each per craft)
              for _, s in ipairs({ { 1, rc.top }, { 2, rc.bottom } }) do
                if s[2] then load(s[2], m, s[1], math.min(mid + k - count(s[1]), spare(avail, s[2])), nil) end
              end
            end
            load(rc.middle, m, 3, k, q)
            if k > 0 then m.state, m.tile = "making " .. rc.title:lower(), "yellow" end
          end
        end
        -- a press from storage into an empty inscriber, keeping one without a press
        if not any and rc.keep and want(q) > 0 then
          local free
          for _, m in ipairs(inscribers) do
            if not used[m.name] and empty(m) then free = free or m end
          end
          local others = pressFree() - (free and 1 or 0)
          if not PRESSES then
            q.state = ("needs an inscriber with the %s in its top slot"):format(nice(rc.top))
          elseif spare(avail, rc.top) < 1 then
            q.state = ("needs the %s: put it in an inscriber's top slot, or in storage"):format(nice(rc.top))
          elseif not free or (#inscribers > 1 and others < 1) then
            q.state = ("waiting for a free inscriber for the %s"):format(nice(rc.top))
          else
            used[free.name], free.pressIn = true, true
            load(rc.top, free, 1, 1, nil)
            free.state, free.tile = "taking the " .. nice(rc.top), "yellow"
            tell(("Putting the %s in %s: it stays there."):format(nice(rc.top), free.title), "lightBlue")
          end
        elseif not any and want(q) > 0 then
          q.state = "waiting for a free inscriber"
        end
      else
        for _, m in ipairs(chargers) do
          if not used[m.name] and not m.slots[1] and want(q) > 0 and spare(avail, rc.middle) > 0 then
            used[m.name] = true
            load(rc.middle, m, 1, 1, q)
            m.state, m.tile = "charging " .. nice(rc.middle), "yellow"
          end
        end
        if #chargers == 0 then q.state = "needs a charger" end
      end
      if not q.state and want(q) > 0 and canMake(rc, avail) == 0 then
        local short
        for _, name in ipairs(usedUp(rc)) do
          if spare(avail, name) == 0 then short = short or name end
        end
        q.state = "waiting for " .. nice(short or rc.middle)
      end
    end

    -- vibration chambers: fuel for CHAMBER_FILL smelts once below CHAMBER_LOW
    local fuels = {} -- { m, smelts, item }
    if CHAMBERS then
      for _, m in ipairs(chambers) do
        local s = m.slots[1]
        local smelts = s and (FUELS[s.name] or 0) * s.count or 0
        if s and not FUELS[s.name] then
          m.state, m.tile = "burning " .. nice(s.name), "lime"
        elseif smelts < CHAMBER_LOW then
          fuels[#fuels + 1] = { m = m, smelts = CHAMBER_FILL - smelts, item = s and s.name }
          m.state, m.tile = "fuelling", "yellow"
        else
          m.state, m.tile = ("%d %s"):format(s.count, nice(s.name)), "lime"
        end
      end
    end

    -- through the work chest in one go, else straight in with 'send'
    local function went(ld, n)
      if ld.q and n > 0 then
        ld.q.sent = ld.q.sent + n
        progress[ld.q.at], ld.q.dirty = now, true
      end
      if n < ld.n then avail[ld.item] = (avail[ld.item] or 0) + (ld.n - n) end
    end
    if r.useWork then
      local items, fuel = {}, 0
      for _, ld in ipairs(loads) do items[ld.item] = (items[ld.item] or 0) + ld.n end
      for _, x in ipairs(fuels) do fuel = fuel + x.smelts end
      if next(items) or fuel > 0 then
        local reply, why = work:fill(items, fuel)
        if reply and reply.error and not reply.nochest then problem = problem or reply.error end
        if not reply then problem = problem or why end
        for _, ld in ipairs(loads) do went(ld, work:move(ld.item, ld.to, ld.slot, ld.n)) end
        for _, x in ipairs(fuels) do
          for name, per in pairs(FUELS) do
            if (not x.item or x.item == name) and x.smelts > 0 then
              local n = work:move(name, x.m.name, 1, math.min(64, math.ceil(x.smelts / per)))
              x.smelts = x.smelts - n * per
            end
          end
        end
        work:empty(input)
      end
    else
      for _, ld in ipairs(loads) do
        local reply = f.ask({ type = "send", to = ld.to, slot = ld.slot, items = { [ld.item] = ld.n } })
        local n = reply and type(reply.sent) == "table" and reply.sent[ld.item] or 0
        if reply and reply.error then
          problem = problem or (reply.error:find("AE2", 1, true) and reply.error
            or "the storage computer can't load AE2 machines yet: 'install update' it")
        end
        if not reply then problem = problem or "the storage computer didn't answer" end
        went(ld, n)
      end
      for _, x in ipairs(fuels) do
        local reply = f.ask({ type = "send", to = x.m.name, fuel = x.smelts, item = x.item })
        if reply and reply.error then problem = problem or reply.error end
        if reply and type(reply.sent) == "table" and not next(reply.sent) then x.m.state, x.m.tile = "no fuel in storage", "orange" end
      end
    end
    for _, q in ipairs(requests) do
      if q.dirty then saveRequest(q) end
      q.dirty = nil
    end

    -- what's short is made first (printed circuits for processors), and the request says so
    orderInputs(avail)
    for _, q in ipairs(requests) do
      if q.state and q.state:find("^waiting for ") then
        for item, note in pairs(orderNote) do
          if q.state == "waiting for " .. nice(item) then q.state = q.state .. ": " .. note end
        end
      end
      if not q.state then q.state = toSend(q) > 0 and "queued" or "in the machines" end
    end

    -- how each machine is doing: an inscriber whose contents haven't changed
    -- for a while with nothing made has no power, or holds a mix that makes nothing
    local working, broken = 0, 0
    for _, m in ipairs(machines) do
      if m.kind == "inscriber" and m.size == 4 then
        local parts = {}
        for slot = 1, 3 do
          local s = m.slots[slot]
          parts[slot] = s and (s.name .. "*" .. s.count) or "-"
        end
        local sig = table.concat(parts, "|")
        local busy = m.slots[3] ~= nil
        local st = stuck[m.name]
        if not busy then
          stuck[m.name] = nil
        elseif not st or st.sig ~= sig then
          stuck[m.name] = { sig = sig, since = now }
        elseif now - st.since > STUCK_AFTER then
          m.state, m.tile = "nothing made for a minute: power, or a mix that makes nothing?", "red"
        end
        if not m.state then
          if busy then
            m.state, m.tile = "making from " .. nice(m.slots[3].name), "yellow"
          else
            local press = m.slots[1] and isPress(m.slots[1].name) and nice(m.slots[1].name)
            m.state, m.tile = press and ("idle, " .. press) or "idle", "lime"
          end
        end
      elseif m.kind == "charger" and not m.state then
        m.state, m.tile = m.slots[1] and ("charging " .. nice(m.slots[1].name)) or "idle",
          m.slots[1] and "yellow" or "lime"
      end
      m.state, m.tile = m.state or "idle", m.tile or "lime"
      if m.tile == "red" then broken = broken + 1 elseif m.tile == "yellow" then working = working + 1 end
    end

    -- the page's list: what the machines here can make, then what's asked for
    local presses, seen = pressesHere(), {}
    shown = {}
    for _, q in ipairs(requests) do
      if not seen[q.recipe.key] then
        seen[q.recipe.key] = true
        shown[#shown + 1] = q.recipe
      end
    end
    local rest = {}
    for _, rc in ipairs(recipes) do
      if not seen[rc.key] and runnable(rc, presses) then rest[#rest + 1] = rc end
    end
    table.sort(rest, function(a, b)
      local ca, cb = canMake(a, counts) > 0, canMake(b, counts) > 0
      if ca ~= cb then return ca end
      return a.title < b.title
    end)
    for _, rc in ipairs(rest) do shown[#shown + 1] = rc end

    if news and os.clock() < news[3] then
      self.message = { news[1], news[2] }
    elseif problem then
      say("Couldn't move items: " .. problem, "red")
    elseif blocked then
      say(("The %s is full: results are waiting in the machines."):format(work.remote and "ender chest" or "storage input chest"), "orange")
    elseif work.problem then
      say(("Not using the work chest: %s."):format(work.problem), "orange")
    elseif broken > 0 then
      local m
      for _, x in ipairs(machines) do
        if x.tile == "red" then m = m or x end
      end
      say(("%s: %s."):format(m.title, m.state), "red")
    elseif makesNote and #requests == 0 then
      say(makesNote, "orange")
    elseif #requests == 0 then
      say("Tap +1, +8 or +64 by what you want made.")
    else
      say(("%s: %s."):format(requests[1].recipe.title, requests[1].state))
    end
    status(broken > 0 and "alert" or working > 0 and "running" or "idle",
      ("%d of %d AE2 machines working, %d requests"):format(working, #machines, #requests))
  end

  ---------------------------------------------------------------- screen

  local function zone(target, x1, x2, y, action)
    zones[target] = zones[target] or {}
    local list = zones[target]
    list[#list + 1] = { x1, x2, y, action }
  end

  local function button(win, target, x, y, text, action, fg, bg)
    screen.put(win, x, y, text, fg or "black", bg or "lightGray")
    zone(target, x, x + #text - 1, y, action)
    return x + #text + 1
  end

  -- The recipes with how many could be made and the request buttons, then
  -- the requests (tap x to cancel one).
  local function drawRequests(win, w, h, target, footer)
    zones[target] = {}
    local fit = screen.fit
    local btnW = 0
    for _, n in ipairs(BUTTONS) do btnW = btnW + #(" +" .. n .. " ") + 1 end
    local bx = w - btnW + 1
    local canR = bx - 2
    screen.put(win, 2, 3, "Make", "yellow")
    screen.put(win, canR - 2, 3, "Can", "yellow")
    screen.put(win, bx, 3, "Request", "yellow")
    local queueRows = math.min(QUEUE_SHOWN, #requests)
    local rows = h - 4 - #footer - (queueRows > 0 and queueRows + 1 or 0)
    local keyed = target == "terminal"
    if keyed then
      picked = math.max(1, math.min(picked, #shown))
      if picked <= scroll then scroll = picked - 1 end
      if picked > scroll + rows then scroll = picked - rows end
    end
    scroll = math.max(0, math.min(scroll, #shown - rows))
    for i = 1, rows do
      local rc, y = shown[scroll + i], 3 + i
      if rc then
        local n = canMake(rc, counts)
        local bg = keyed and scroll + i == picked and "gray" or "black"
        local nameW = canR - 7
        screen.put(win, 1, y, (" "):rep(canR + 1), "white", bg)
        screen.put(win, 2, y, fit(rc.title, nameW), n > 0 and "white" or "lightGray", bg)
        local from = rc.machine == "charger" and " (charger)" or (" from " .. nice(rc.middle))
        if #rc.title + 2 < nameW then
          screen.put(win, 2 + #rc.title, y, fit(from, nameW - #rc.title), bg == "gray" and "lightGray" or "gray", bg)
        end
        local can = n > 9999 and "9999+" or tostring(n)
        screen.put(win, canR - #can + 1, y, can, n > 0 and "lime" or bg == "gray" and "lightGray" or "gray", bg)
        local x = bx
        for _, k in ipairs(BUTTONS) do
          x = button(win, target, x, y, (" +%d "):format(k), { add = rc, n = k }, "black", n > 0 and "lightGray" or "gray")
        end
      end
    end
    if #shown == 0 then
      screen.put(win, 2, 4, fit(#machines == 0 and "No AE2 machines yet." or "Nothing the machines here can make.", w - 2), "gray")
    end
    if #shown > rows then
      screen.put(win, w, 4, scroll > 0 and "^" or " ", "yellow")
      screen.put(win, w, 3 + rows, scroll + rows < #shown and "v" or " ", "yellow")
      zone(target, w, w, 4, { scroll = -rows })
      zone(target, w, w, 3 + rows, { scroll = rows })
    end
    if queueRows > 0 then
      local y = 4 + rows
      screen.put(win, 2, y, ("Requests (%d)"):format(#requests), "yellow")
      for i = 1, queueRows do
        local q = requests[i]
        local text = ("%s %d/%d%s: %s"):format(q.recipe and q.recipe.title or q.key, q.made, q.count, q.job and " (overseer)" or "", q.state or "queued")
        screen.put(win, 2, y + i, fit(text, w - 6), "white")
        button(win, target, w - 3, y + i, " x ", { cancel = q.file }, "white", "red")
      end
    end
    for i, line in ipairs(footer) do screen.put(win, 1, h - #footer + i, fit(line[1], w), line[2]) end
  end

  function self.key()
    local key = { self.message[1], self.message[2], scroll, picked, #shown }
    for _, rc in ipairs(shown) do key[#key + 1] = rc.key .. "=" .. canMake(rc, counts) end
    for _, q in ipairs(requests) do key[#key + 1] = table.concat({ q.key, q.made, q.count, q.state or "" }, "/") end
    for _, m in ipairs(machines) do key[#key + 1] = table.concat({ m.title, m.state or "" }, "/") end
    return table.concat(key, "|")
  end

  function self.draw(win, w, h)
    local n = { inscriber = 0, charger = 0, chamber = 0 }
    for _, m in ipairs(machines) do n[m.kind] = n[m.kind] + 1 end
    screen.put(win, 2, 2, screen.fit(("%d inscribers, %d chargers, %d vibration chambers"):format(n.inscriber, n.charger,
      n.chamber), w - 2), "lightGray")
    local footer = {}
    for _, line in ipairs(screen.wrap(self.message[1], w, (self.message[2] == "red" or self.message[2] == "orange") and 4 or 2)) do
      footer[#footer + 1] = { line, self.message[2] }
    end
    footer[#footer + 1] = { w >= 50 and "Arrows pick. Enter +1, 8 +8, 6 +64. X cancels last" or "Enter +1, 8 +8, 6 +64, X cancels",
      "gray" }
    drawRequests(win, w, h, "terminal", footer)
  end

  self.monitorPage = { title = "AE2",
    key = function() return self.key() end,
    draw = function(win, w, h) drawRequests(win, w, h, "monitor", {}) end,
  }

  function self.tiles()
    local tiles = {}
    for _, m in ipairs(machines) do tiles[#tiles + 1] = { m.title, m.state or "idle", m.tile or "lime" } end
    return tiles
  end

  local function cancel(file)
    local q = files.read(file)
    if fs.exists(file) then fs.delete(file) end
    if type(q) == "table" and q.job then
      q.ok, q.why = false, "cancelled at the factory"
      report(q)
    end
    for i = #requests, 1, -1 do
      if requests[i].file == file then table.remove(requests, i) end
    end
  end

  local function act(a)
    if a.add then
      local n = request(a.add, a.n * a.add.count)
      tell(("Asked for %d %s."):format(n, a.add.title), "lime")
    elseif a.scroll then
      scroll = math.max(0, scroll + a.scroll)
      picked = math.max(1, math.min(#shown, picked + a.scroll))
    elseif a.cancel then
      cancel(a.cancel)
      tell("Cancelled. What's already in a machine still gets made.", "lime")
      f.wake()
    end
  end

  local function tap(target, x, y)
    for _, z in ipairs(zones[target] or {}) do
      if y == z[3] and x >= z[1] and x <= z[2] then
        act(z[4])
        return true
      end
    end
    return false
  end

  function self.monitorPage.touch(x, y) return tap("monitor", x, y) end

  function self.event(ev, x, y)
    local e = ev[1]
    if e == "key" and ev[2] == keys.up then picked = math.max(1, picked - 1)
    elseif e == "key" and ev[2] == keys.down then picked = math.min(#shown, picked + 1)
    elseif e == "key" and ev[2] == keys.pageUp then picked = math.max(1, picked - 8)
    elseif e == "key" and ev[2] == keys.pageDown then picked = math.min(#shown, picked + 8)
    elseif e == "key" and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) and shown[picked] then
      act({ add = shown[picked], n = 1 })
    elseif e == "char" and (ev[2] == "8" or ev[2] == "6") and shown[picked] then
      act({ add = shown[picked], n = ev[2] == "8" and 8 or 64 })
    elseif e == "char" and ev[2]:lower() == "x" and #requests > 0 then
      act({ cancel = requests[#requests].file })
    elseif e == "mouse_scroll" then picked = math.max(1, math.min(#shown, picked + ev[2]))
    elseif x then tap("terminal", x, y)
    end
    return false
  end

  ---------------------------------------------------------------- commands

  -- Recipes matching text: the exact name or id first, then any containing it.
  local function matching(text)
    text = text:lower()
    local exact, part = {}, {}
    for _, rc in ipairs(recipes) do
      local name = rc.title:lower()
      if name == text or rc.make == text then exact[#exact + 1] = rc
      elseif name:find(text, 1, true) or rc.make:find(text, 1, true) then part[#part + 1] = rc end
    end
    for _, rc in ipairs(part) do exact[#exact + 1] = rc end
    return exact
  end

  local function describe(rc, stock)
    local how = rc.machine == "charger" and "charger" or rc.keep and ("inscriber, " .. nice(rc.top) .. " on top")
      or (rc.top and ("inscriber: %s / %s / %s"):format(nice(rc.top), nice(rc.middle), nice(rc.bottom or "nothing")))
      or "inscriber, middle only"
    return ("%s from %s (%s)%s"):format(rc.title, nice(rc.middle), how,
      stock and (", can make %d"):format(canMake(rc, stock)) or "")
  end

  -- 'factory ae2 [what count | cancel [n]]'. True if args was it.
  function self.command(args)
    if args[1] ~= "ae2" then return false end
    local queued = loadRequests()
    if args[2] == "cancel" then
      local n = tonumber(args[3] or "")
      local gone = 0
      for i, q in ipairs(queued) do
        if not n or n == i then
          cancel(q.file)
          gone = gone + 1
        end
      end
      print(gone > 0 and ("Cancelled %d request(s)."):format(gone) or "Nothing to cancel.")
      f.wake()
      return true
    end
    local count = tonumber(args[#args] or "")
    if args[2] and count and #args >= 3 then
      local rc = matching(table.concat(args, " ", 2, #args - 1))[1]
      if not rc then
        print("No AE2 recipe called that: 'factory ae2' lists them.")
        return true
      end
      print(("Asked for %d %s. It starts on the factory's next round."):format(request(rc, count), rc.title))
      return true
    end
    local reply = f.ask({ type = "stock" })
    local stock = reply and type(reply.counts) == "table" and reply.counts or nil
    local _, h = term.getSize()
    local room = h - 3 - #queued
    for i = 1, math.min(#recipes, room) do print(describe(recipes[i], stock)) end
    if #recipes > room then print(("...and %d more."):format(#recipes - room)) end
    for i, q in ipairs(queued) do
      print(("Request %d: %s %d/%d%s"):format(i, q.recipe and q.recipe.title or q.key, q.made, q.count,
        q.job and " (for the craft overseer)" or ""))
    end
    print("factory ae2 <name> <count> | cancel [n]")
    return true
  end

  return self
end

return M
