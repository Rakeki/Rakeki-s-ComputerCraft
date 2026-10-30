-- Instabuild: places a whole plan from /plans in a few seconds, from a
-- command computer (creative only). Uses the same plans and coordinates as
-- build-control, or places whatever the blueprint projector shows when its
-- Build is tapped ('instabuild serve'). It only ever places blocks into air:
-- nothing that's already there is replaced. It keeps a list of what it
-- placed, so the last build can be undone.
--
--   instabuild list                          the plans here, with their sizes
--   instabuild check <plan>                  size and the blocks it uses
--   instabuild <plan> <x> <y> <z> [facing]   north-west bottom corner at x y z
--   instabuild <plan> here [facing]          2 blocks south of this computer, on its level
--   instabuild serve                         place the projector's plan when Build is tapped on it
--   instabuild undo                          remove what the last build placed
--
-- facing is where the plan's front (its first row) faces: north (the
-- default), east, south or west. Plans: 'install plan <name>', or your own
-- in /plans.
local plans = require("lib.plan") -- loading plans and placing them in the world
local files = require("lib.files")
local net = require("lib.net") -- rednet requests and answers, for serve
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local UNDO_FILE = "/.instabuild_undo" -- what the last build placed, for 'instabuild undo'
local SERVE_FILE = "/.instabuild_serve" -- there while serving, so startup serves again after a reboot
local PROTOCOL = "instabuild" -- the blueprint projector sends buildings on this
local FACINGS = { north = 0, east = 1, south = 2, west = 3 }
local HERE_GAP = 2 -- 'here' puts the building this many blocks south of the computer
local WORLD_TOP, WORLD_BOTTOM = 319, -64 -- where blocks can go (1.18 and later)
local READ_MAX = 4096 -- most blocks one getBlockInfos call reads
local IN_FLIGHT = 128 -- commands sent before waiting for answers
local AIR = { ["minecraft:air"] = true, ["minecraft:cave_air"] = true, ["minecraft:void_air"] = true }

local args = { ... }

local function facingName(turn)
  for name, t in pairs(FACINGS) do
    if t == turn % 4 then return name end
  end
end

local function yes(question)
  write(question .. " (y/n) ")
  local answer = read()
  return answer and answer:lower():sub(1, 1) == "y"
end

---------------------------------------------------------------- reading the world

-- Where block i of a slab read (x0..x1, z0..z1) is, for each order the list
-- could come in: x changing fastest, or z.
local ORDERS = {
  xFirst = function(i, w, d) return (i - 1) % w, math.floor((i - 1) / w) end,
  zFirst = function(i, w, d) return math.floor((i - 1) / d), (i - 1) % d end,
}
local order -- the one this CC version uses, once checked

-- The first slab that isn't all one block settles the order: a few of its
-- blocks are read again one at a time where each order says they are.
local function checkOrder(infos, x0, y, z0, w, d)
  local samples = {}
  for i = 2, #infos do
    if infos[i].name ~= infos[1].name then samples[#samples + 1] = i end
    if #samples == 3 then break end
  end
  if #samples == 0 then return end -- all one block: either order reads the same
  for _, name in ipairs({ "xFirst", "zFirst" }) do
    local fits = true
    for _, i in ipairs(samples) do
      local dx, dz = ORDERS[name](i, w, d)
      local one = commands.getBlockInfo(x0 + dx, y, z0 + dz)
      if not one or one.name ~= infos[i].name then fits = false break end
    end
    if fits then
      order = name
      return
    end
  end
  error("This version of CC reads blocks in an order I don't know, so I can't tell what's there.", 0)
end

-- Every block in the box, a slab at a time (getBlockInfos reads at most
-- READ_MAX blocks): fn(x, y, z, info) for each.
local function eachBlock(a, fn)
  local w = a.x1 - a.x0 + 1
  if w > READ_MAX then error("That's too wide to read in one go.", 0) end
  local rows = math.max(1, math.floor(READ_MAX / w))
  for y = a.y0, a.y1 do
    for z0 = a.z0, a.z1, rows do
      local z1 = math.min(a.z1, z0 + rows - 1)
      local d = z1 - z0 + 1
      local infos = commands.getBlockInfos(a.x0, y, z0, a.x1, y, z1)
      -- a single row (or column) reads the same in either order
      if not order and w > 1 and d > 1 then checkOrder(infos, a.x0, y, z0, w, d) end
      local at = ORDERS[order or "xFirst"]
      for i = 1, w * d do
        local dx, dz = at(i, w, d)
        fn(a.x0 + dx, y, z0 + dz, infos[i])
      end
    end
  end
end

---------------------------------------------------------------- placing

-- Cells grouped into runs along x of one block: { x0, x1, y, z, block }.
-- One fill command places a whole run.
local function runs(cells)
  table.sort(cells, function(a, b)
    if a[2] ~= b[2] then return a[2] < b[2] end
    if a[3] ~= b[3] then return a[3] < b[3] end
    return a[1] < b[1]
  end)
  local out, cur = {}, nil
  for _, c in ipairs(cells) do
    if cur and c[2] == cur[3] and c[3] == cur[4] and c[1] == cur[2] + 1 and c[4] == cur[5] then
      cur[2] = c[1]
    else
      cur = { c[1], c[1], c[2], c[3], c[4] }
      out[#out + 1] = cur
    end
  end
  return out
end

local function command(r)
  if r[1] == r[2] then return ("setblock %d %d %d %s"):format(r[1], r[3], r[4], r[5]) end
  return ("fill %d %d %d %d %d %d %s"):format(r[1], r[3], r[4], r[2], r[3], r[4], r[5])
end

-- Run the commands for these runs, IN_FLIGHT at a time, showing progress.
-- Returns how many failed, and the first failure's message.
local function place(list, label)
  local failed, why, mine, waiting, done = 0, nil, {}, 0, 0
  local _, line = term.getCursorPos()
  local function show()
    term.setCursorPos(1, line)
    term.clearLine()
    write(("%s %d of %d runs"):format(label, done, #list))
  end
  -- wait for answers until no more than max are still out
  local function settle(max)
    while waiting > max do
      -- task_complete: id, whether it ran, then commands.exec's ok and output
      local _, id, ran, ok, out = os.pullEvent("task_complete")
      if mine[id] then
        mine[id], waiting, done = nil, waiting - 1, done + 1
        if not (ran and ok) then
          failed = failed + 1
          why = why or (type(out) == "table" and out[1]) or tostring(ok)
        end
        if done % 200 == 0 then show() end
      end
    end
  end
  show()
  for _, r in ipairs(list) do
    mine[commands.execAsync(command(r))] = true
    waiting = waiting + 1
    if waiting >= IN_FLIGHT then settle(IN_FLIGHT / 2) end
  end
  settle(0)
  show()
  print()
  return failed, why
end

-- Why a building in box a can't be placed, or nil.
local function outside(a)
  if a.y1 > WORLD_TOP or a.y0 < WORLD_BOTTOM then
    return ("That goes outside the world: blocks can only go from Y %d to Y %d."):format(WORLD_BOTTOM, WORLD_TOP)
  end
  if a.x1 - a.x0 + 1 > READ_MAX then return "That's too wide to read in one go." end
end

-- Place a building (block names mats, blocks { x, y, z, m } in world
-- coordinates, box a) into the air in its box: a block that's already there
-- is never replaced. Keeps the list of what it placed for undo. Returns
-- { name, placed, inWay (plan blocks left out: something else is there),
-- failed, why }.
local function placeBuilding(name, mats, blocks, a)
  local want = {}
  local function key(bx, by, bz) return ((bx - a.x0) * (a.y1 - a.y0 + 1) + (by - a.y0)) * (a.z1 - a.z0 + 1) + (bz - a.z0) end
  for _, b in ipairs(blocks) do
    local block = mats[b[4]]
    if block and not AIR[plans.base(block)] then want[key(b[1], b[2], b[3])] = block end
  end

  print("Looking at what's there...")
  local todo, inWay = {}, 0
  local ok, readErr = pcall(eachBlock, a, function(bx, by, bz, info)
    local target = want[key(bx, by, bz)]
    if not target or not info then return end
    if AIR[info.name] then
      todo[#todo + 1] = { bx, by, bz, target }
    elseif info.name ~= plans.base(target) then
      inWay = inWay + 1
    end
  end)
  if not ok then error("Couldn't read the blocks there: " .. tostring(readErr) .. " Is it all loaded (within render distance)?", 0) end
  local result = { name = name, placed = #todo, inWay = inWay, failed = 0 }
  if #todo == 0 then return result end

  -- undo puts air back wherever a block went in
  local undo = {}
  for i, c in ipairs(todo) do undo[i] = { c[1], c[2], c[3], "minecraft:air" } end
  -- the old copy goes first: two copies of a big build don't fit on the disk
  files.delete(UNDO_FILE)
  files.write(UNDO_FILE, { name = name, runs = runs(undo) })
  result.failed, result.why = place(runs(todo), "Building:")
  return result
end

-- What a build did, in a line.
local function summary(r)
  if r.placed == 0 then
    return r.inWay > 0 and ("Nothing placed for %s: all %d of its blocks have something there already."):format(r.name, r.inWay)
      or ("%s is already there: nothing to place."):format(r.name)
  end
  local text = ("Placed %s: %d blocks"):format(r.name, r.placed)
  if r.inWay > 0 then text = text .. (", %d left out (something already there)"):format(r.inWay) end
  if r.failed > 0 then text = text .. (", %d runs failed (%s): is all of it loaded?"):format(r.failed, tostring(r.why)) end
  return text .. "."
end

-- Remove what the last build placed. Returns a line saying what happened.
local function undoLast(ask)
  local u = files.read(UNDO_FILE)
  if not u then return "Nothing to undo." end
  if ask and not ask(("Remove what %s placed?"):format(u.name)) then return "Left as it is." end
  local failed, why = place(u.runs, "Undoing:")
  files.delete(UNDO_FILE)
  if failed > 0 then return ("Undone %s, but %d runs failed (%s): is all of it loaded?"):format(u.name, failed, tostring(why)) end
  return ("Undone %s."):format(u.name)
end

---------------------------------------------------------------- commands

local function listPlans()
  local ids = plans.ids()
  if #ids == 0 then print(("No plans in %s yet."):format(plans.DIR)) end
  for _, id in ipairs(ids) do
    local p, err = plans.load(id)
    if p then
      print(("  %-14s %s, %d x %d x %d, %d blocks"):format(id, p.name, p.w, p.l, p.h, #p.blocks))
    else
      printError("  " .. err)
    end
  end
  print("More from the website: install plan <name> (install plans lists them)")
end

local function checkPlan(id)
  local p, err = plans.load(id)
  if not p then error(err, 0) end
  print(("%s: %d wide, %d deep, %d high, %d blocks"):format(p.name, p.w, p.l, p.h, #p.blocks))
  table.sort(p.mats, function(a, b) return a.total > b.total end)
  for _, m in ipairs(p.mats) do print(("  %-34s %d"):format(m.block, m.total)) end
end

local function build(id, where, facingArg)
  local p, err = plans.load(id)
  if not p then error(err, 0) end
  local turn = FACINGS[facingArg or "north"]
  if not turn then error("Facing must be north, east, south or west.", 0) end
  local x, y, z
  if where[1] == "here" then
    x, y, z = commands.getBlockPosition()
    z = z + HERE_GAP
  else
    x, y, z = tonumber(where[1]), tonumber(where[2]), tonumber(where[3])
    if not (x and y and z) then error("Usage: instabuild <plan> <x> <y> <z> [facing]", 0) end
  end
  local at = plans.corner(p, turn, math.floor(x), math.floor(y), math.floor(z))
  local a = plans.area(p, at)
  print(("%s facing %s: %d x %d x %d, %d blocks,"):format(p.name, facingName(turn), p.w, p.l, p.h, #p.blocks))
  print(("from %d,%d,%d to %d,%d,%d."):format(a.x0, a.y0, a.z0, a.x1, a.y1, a.z1))
  local why = outside(a)
  if why then error(why, 0) end
  print("Blocks only go where there's air: nothing already there is replaced.")
  if not yes("Build it?") then return print("Not built.") end
  local mats, blocks = plans.world(p, at)
  local r = placeBuilding(p.name, mats, blocks, a)
  print(summary(r))
  if r.placed > 0 then print("'instabuild undo' removes it again.") end
end

---------------------------------------------------------------- serving the projector

-- Why a build request from the projector can't be placed, or nil.
local function badRequest(msg)
  local a = msg.area
  if type(msg.mats) ~= "table" or type(msg.blocks) ~= "table" or type(a) ~= "table" then return "that's not a building" end
  for _, k in ipairs({ "x0", "y0", "z0", "x1", "y1", "z1" }) do
    if type(a[k]) ~= "number" then return "that's not a building" end
  end
  return outside(a)
end

-- Wait for the blueprint projector's Build: it sends the plan where it's
-- shown, which goes in straight away (tapping Build is the go-ahead).
local function serve()
  if not net.open("any") then
    error("'instabuild serve' needs a modem (wired, wireless or ender) to hear the projector.", 0)
  end
  rednet.host(PROTOCOL, "instabuild-" .. os.getComputerID())
  files.write(SERVE_FILE, { since = os.epoch("utc") })
  print("Waiting for the blueprint projector: tap Build on it")
  print("to place its plan where it's shown.")
  print("U: undo the last build. Q: stop serving.")

  local busy, job = false, nil
  -- answers straight away, so the projector never waits for a big build
  local function listen()
    while true do
      local from, msg = rednet.receive(PROTOCOL)
      if type(msg) == "table" and msg.type == "build" then
        local why = busy and "busy placing another building" or badRequest(msg)
        net.answer(from, PROTOCOL, msg, { ok = not why, why = why })
        if not why then
          busy, job = true, { from = from, msg = msg }
          os.queueEvent("instabuild_job")
        end
      end
    end
  end
  local function work()
    while true do
      local ev, ch = os.pullEvent()
      if ev == "instabuild_job" and job then
        local from, msg = job.from, job.msg
        local name = type(msg.name) == "string" and msg.name or "the building"
        print(("Projector #%d: placing %s."):format(from, name))
        local ok, r = (errlog and errlog.pcall or pcall)(placeBuilding, name, msg.mats, msg.blocks, msg.area)
        local text = ok and summary(r) or ("Couldn't place %s: %s"):format(name, tostring(r))
        if ok then print(text) else printError(text) end
        rednet.send(from, { type = "done", id = msg.id, text = text, placed = ok and r.placed or 0 }, PROTOCOL)
        busy, job = false, nil
      elseif ev == "char" and (ch == "u" or ch == "U") and not busy then
        busy = true
        local ok, text = (errlog and errlog.pcall or pcall)(undoLast, yes)
        print(ok and text or tostring(text))
        busy = false
      elseif ev == "char" and (ch == "q" or ch == "Q") then
        return
      end
    end
  end
  parallel.waitForAny(listen, work)
  rednet.unhost(PROTOCOL)
  files.delete(SERVE_FILE)
  print("Stopped serving. 'instabuild serve' starts again.")
end

local function main()
  local cmd = args[1]
  if cmd == nil then
    print("Usage: instabuild <plan> <x> <y> <z> [facing], instabuild <plan> here,")
    print("instabuild serve, instabuild list, instabuild check <plan>, instabuild undo")
    return
  elseif cmd == "list" then
    return listPlans()
  elseif cmd == "check" then
    if not args[2] then error("Usage: instabuild check <plan>", 0) end
    return checkPlan(args[2])
  end
  if not commands then
    error("This needs a command computer (creative): /give @s computercraft:computer_command", 0)
  end
  if cmd == "undo" then return print(undoLast(yes)) end
  if cmd == "serve" then return serve() end
  build(cmd, { args[2], args[3], args[4] }, args[2] == "here" and args[3] or args[5])
end

if errlog then errlog.init("instabuild") end
local ok, err = (errlog and errlog.pcall or pcall)(main)
if not ok and err ~= "Terminated" then printError(err) end
