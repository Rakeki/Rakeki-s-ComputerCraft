-- Endless items from a Create Creative Crate. The turtle sits between the
-- crate (set its item by right-clicking the filter slot on its top) and a chest, and
-- moves the crate's item into the chest a stack at a time: keeping the chest
-- full, sending a set amount, keeping a set amount in the chest, or keeping
-- a set amount in the storage system (the chest is then its input chest).
--
--   crate                fill the chest, then keep it full
--   crate <n>            send n items, then stop
--   crate keep <n>       keep n of the item in the chest
--   crate stock <n>      keep n in the storage system (my chest = its input chest)
--   crate stop           forget the job, so it doesn't start again on boot
--   crate resume         carry on with the saved job (startup.lua runs this)
--
-- The crate goes in front of, above or below the turtle, and the chest on
-- another of those three sides (below first, then above, then in front). It
-- never needs fuel: it doesn't move. 'crate stock' needs a wireless or ender
-- modem to ask the storage computer how many it has.
local files = require("lib.files") -- crash-safe job file
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log
local net = fs.exists("lib/net.lua") and require("lib.net") -- only 'crate stock' needs it

local JOB_FILE = "/.crate_job" -- the running job, so it carries on after a reboot
local CRATE_SIDE = nil -- "front", "top" or "bottom" if the crate isn't found by itself
local FULL_WAIT = 5 -- seconds between tries while the chest is full
local KEEP_WAIT = 2 -- seconds between checks while the chest has enough ('crate keep')
local STOCK_WAIT = 15 -- seconds between checks while storage has enough ('crate stock')
local EMPTY_WAIT = 10 -- seconds between tries while the crate gives nothing (no filter set)
local STORAGE_PROTOCOL = "storage" -- the storage computer answers counts on this
local STORAGE_WAIT = 10 -- seconds to wait for the storage computer to answer

local job -- { mode = "fill" | "count" | "keep" | "stock", n, sent, item }
local crateSide, chestSide

---------------------------------------------------------------- helpers

local function status(state, detail)
  if report then report.set(state, detail) end
end

local function shortName(name) return name and (name:gsub("^[%w_]+:", ""):gsub("_", " ")) or "?" end

local function save() files.write(JOB_FILE, job) end

-- Print a line once, not again until something else is said.
local said
local function say(text)
  if text ~= said then print(text) said = text end
end

local MOVES = {
  front = { suck = turtle.suck, drop = turtle.drop },
  top = { suck = turtle.suckUp, drop = turtle.dropUp },
  bottom = { suck = turtle.suckDown, drop = turtle.dropDown },
}

local function isCrate(side)
  for _, t in ipairs({ peripheral.getType(side) }) do
    if t:find("creative_crate") then return true end
  end
  return false
end

local function isInventory(side)
  return peripheral.hasType(side, "inventory") and not isCrate(side)
end

-- Find the crate and the chest. The chest is never the crate: anything
-- dropped into a Creative Crate is gone.
local function findSides()
  crateSide, chestSide = CRATE_SIDE, nil
  if not crateSide then
    for _, side in ipairs({ "front", "top", "bottom" }) do
      if isCrate(side) then crateSide = side break end
    end
  end
  if not crateSide then
    return false, "I can't see a Creative Crate in front of me, above or below me."
  end
  for _, side in ipairs({ "bottom", "top", "front" }) do
    if side ~= crateSide and isInventory(side) then chestSide = side break end
  end
  if not chestSide then
    -- say what is there, so a chest behind me or a modem in the way is easy to spot
    local seen = {}
    for _, side in ipairs({ "front", "top", "bottom" }) do
      seen[#seen + 1] = ("%s: %s"):format(side, peripheral.getType(side) or "nothing I can use")
    end
    return false, "Put a chest below me, above me or in front of me (not where the crate is), "
      .. "touching me: I can't reach one behind me or beside me. I see:\n  " .. table.concat(seen, "\n  ")
  end
  return true
end

-- How many of item the chest holds.
local function inChest(item)
  local n = 0
  if not item then return 0 end
  for _, stack in pairs(peripheral.call(chestSide, "list") or {}) do
    if stack.name == item then n = n + stack.count end
  end
  return n
end

-- Put everything the turtle holds into the chest, waiting while it's full.
local function unload()
  for slot = 1, 16 do
    turtle.select(slot)
    while turtle.getItemCount(slot) > 0 do
      if not MOVES[chestSide].drop() then
        say("The chest is full. Waiting...")
        status("waiting", "chest full")
        sleep(FULL_WAIT)
      end
    end
  end
  turtle.select(1)
end

---------------------------------------------------------------- moving

-- Take up to n items from the crate, a stack at a time, and put them in the
-- chest. Returns how many went in (0 when the crate gives nothing).
local function move(n)
  local moved = 0
  while moved < n do
    turtle.select(1)
    if not MOVES[crateSide].suck(math.min(64, n - moved)) then break end
    local got = turtle.getItemDetail(1)
    if not got then break end
    if got.name ~= job.item then
      job.item = got.name
      print(("The crate gives %s."):format(shortName(got.name)))
    end
    unload()
    moved = moved + got.count
    if job.mode == "count" then
      job.sent = (job.sent or 0) + got.count
      save()
      status("running", ("%d of %d %s"):format(job.sent, job.n, shortName(job.item)))
    end
  end
  return moved
end

-- The crate gave nothing: its filter is empty.
local function crateEmpty()
  say("The crate gives nothing. Right-click the slot on its top with the item. Waiting...")
  status("waiting", "crate has no item set")
  sleep(EMPTY_WAIT)
end

local storage = net and net.peer(STORAGE_PROTOCOL, { wait = STORAGE_WAIT, retry = 30 })

-- How many of the item the storage system holds, counting what's still in
-- its input chest (my chest) waiting to be put away. nil and why if no
-- storage computer answered.
local function inStorage(item)
  local reply, why = storage:ask({ type = "count", items = { item } })
  if not reply or type(reply.counts) ~= "table" then return nil, why or "no answer" end
  return (reply.counts[item] or 0) + inChest(item)
end

---------------------------------------------------------------- jobs

local function run()
  unload() -- anything left from before goes in the chest
  print(("Crate %s, chest %s."):format(crateSide, chestSide))
  while true do
    if job.mode == "fill" then
      status("running", ("filling with %s"):format(shortName(job.item)))
      if move(64) == 0 then crateEmpty() end
    elseif job.mode == "count" then
      local left = job.n - (job.sent or 0)
      if left <= 0 then
        print(("Done: sent %d %s."):format(job.sent, shortName(job.item)))
        files.delete(JOB_FILE)
        status("done", ("sent %d %s"):format(job.sent, shortName(job.item)))
        return
      end
      status("running", ("%d of %d %s"):format(job.sent or 0, job.n, shortName(job.item)))
      if move(left) == 0 then crateEmpty() end
    else
      -- keep / stock: the first item tells us what the crate gives
      local have, why = 0, nil
      if job.item then
        if job.mode == "keep" then
          have = inChest(job.item)
        else
          have, why = inStorage(job.item)
        end
      end
      local where = job.mode == "keep" and "in the chest" or "in storage"
      if not have then
        say("No storage system answered (" .. tostring(why) .. "). Is it running 'storage'? Trying again...")
        status("waiting", "no storage system")
        sleep(STOCK_WAIT)
      elseif have < job.n then
        status("running", ("%d/%d %s %s"):format(have, job.n, shortName(job.item), where))
        say(("Topping up %s: %d of %d."):format(where, have, job.n))
        -- one item first while we don't know what it is, so we never overshoot
        if move(job.item and math.min(job.n - have, 16 * 64) or 1) == 0 then crateEmpty() end
      else
        say(("%d %s %s. Waiting for it to drop below %d."):format(have, shortName(job.item), where, job.n))
        status("idle", ("%d %s %s"):format(have, shortName(job.item), where))
        sleep(job.mode == "keep" and KEEP_WAIT or STOCK_WAIT)
      end
    end
  end
end

---------------------------------------------------------------- start

local function usage()
  print("crate              fill the chest, keep it full")
  print("crate <n>          send n items, then stop")
  print("crate keep <n>     keep n of the item in the chest")
  print("crate stock <n>    keep n in the storage system")
  print("crate stop         forget the job")
end

if not turtle then
  print("This runs on a turtle.")
  return
end
if not os.getComputerLabel() then os.setComputerLabel("Crate-" .. os.getComputerID()) end

local args = { ... }
local function number(s)
  local n = tonumber(s)
  return n and n >= 1 and math.floor(n) or nil
end

if args[1] == "stop" then
  files.delete(JOB_FILE)
  print("Job forgotten. I won't start again on boot.")
  return
elseif args[1] == "resume" then
  job = files.read(JOB_FILE)
  if not job then
    print("No job to carry on with.")
    return
  end
elseif args[1] == nil then
  job = { mode = "fill" }
elseif (args[1] == "keep" or args[1] == "stock") and number(args[2]) then
  job = { mode = args[1], n = number(args[2]) }
elseif number(args[1]) and not args[2] then
  job = { mode = "count", n = number(args[1]), sent = 0 }
else
  usage()
  return
end

if job.mode == "stock" then
  if not net or not net.open() then
    print("'crate stock' needs a wireless or ender modem (and lib/net.lua)")
    print("to ask the storage computer how many it has.")
    return
  end
end

local ok, why = findSides()
if not ok then
  print(why)
  return
end
save()

if report then report.init("crate") end
if errlog then errlog.init("crate", function() return { mode = job.mode, item = job.item } end) end
parallel.waitForAny(function()
  local ok2, err = (errlog and errlog.pcall or pcall)(run)
  if not ok2 then
    status("error", tostring(err))
    error(err, 0)
  end
end, report and report.loop or function() while true do sleep(3600) end end)
