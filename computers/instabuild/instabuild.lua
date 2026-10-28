-- Instabuild: places a whole plan from /plans in a few seconds, from a
-- command computer (creative only). Uses the same plans and coordinates as
-- build-control, and keeps what was there so the last build can be undone.
--
--   instabuild list                          the plans here, with their sizes
--   instabuild check <plan>                  size and the blocks it uses
--   instabuild <plan> <x> <y> <z> [facing]   north-west bottom corner at x y z
--   instabuild <plan> here [facing]          2 blocks south of this computer, on its level
--   instabuild undo                          put back what the last build replaced
--
-- facing is where the plan's front (its first row) faces: north (the
-- default), east, south or west. Plans built on the ground clear their box
-- (as builder turtles do); ones built in the air ("clear": false) only place
-- their blocks. Chests, computers and other blocks that hold things are
-- never replaced. Plans: 'install plan <name>', or your own in /plans.
local plans = require("lib.plan") -- loading plans and placing them in the world
local files = require("lib.files")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local UNDO_FILE = "/.instabuild_undo" -- what the last build replaced, for 'instabuild undo'
local FACINGS = { north = 0, east = 1, south = 2, west = 3 }
local HERE_GAP = 2 -- 'here' puts the building this many blocks south of the computer
local WORLD_TOP, WORLD_BOTTOM = 319, -64 -- where blocks can go (1.18 and later)
local READ_MAX = 4096 -- most blocks one getBlockInfos call reads
local IN_FLIGHT = 128 -- commands sent before waiting for answers
local AIR = { ["minecraft:air"] = true, ["minecraft:cave_air"] = true, ["minecraft:void_air"] = true }
-- never replaced, even without the block data that gives them away (a bulk
-- read may leave it out): anything that holds items or settings
local KEEP = {
  "chest", "barrel", "shulker_box", "furnace", "smoker", "hopper", "dispenser", "dropper", "sign",
  "beacon", "brewing_stand", "lectern", "jukebox", "crafter", "chiseled_bookshelf", "campfire",
  "decorated_pot", "banner", "command_block", "structure_block", "spawner", "vault",
  "computer", "turtle", "monitor",
}
local KEEP_MODS = { "computercraft:" } -- every block from these mods

local args = { ... }

local function facingName(turn)
  for name, t in pairs(FACINGS) do
    if t == turn % 4 then return name end
  end
end

-- A block as setblock takes it: name, then its state in brackets.
local function blockString(info)
  local parts = {}
  for k, v in pairs(info.state or {}) do parts[#parts + 1] = k .. "=" .. tostring(v) end
  table.sort(parts)
  return #parts > 0 and (info.name .. "[" .. table.concat(parts, ",") .. "]") or info.name
end

local function keep(info)
  if info.nbt then return true end
  for _, mod in ipairs(KEEP_MODS) do
    if info.name:sub(1, #mod) == mod then return true end
  end
  for _, word in ipairs(KEEP) do
    if info.name:find(word, 1, true) then return true end
  end
  return false
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
  print(("%s: %d wide, %d deep, %d high, %d blocks%s"):format(p.name, p.w, p.l, p.h, #p.blocks,
    p.clear and "" or ", built in the air"))
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
  if a.y1 > WORLD_TOP or a.y0 < WORLD_BOTTOM then
    error(("That goes outside the world: blocks can only go from Y %d to Y %d."):format(WORLD_BOTTOM, WORLD_TOP), 0)
  end
  print(p.clear and "Everything else in that box is cleared to air (chests and computers are kept)."
    or "It's built in the air: only its own blocks are placed.")
  write("Build it? (y/n) ")
  local answer = read()
  if not answer or answer:lower():sub(1, 1) ~= "y" then return print("Not built.") end

  -- what goes where: the plan's blocks, and air in the rest of the box when clearing
  local mats, blocks = plans.world(p, at)
  local want = {}
  local function key(bx, by, bz) return ((bx - a.x0) * (a.y1 - a.y0 + 1) + (by - a.y0)) * (a.z1 - a.z0 + 1) + (bz - a.z0) end
  for _, b in ipairs(blocks) do want[key(b[1], b[2], b[3])] = mats[b[4]] end

  print("Looking at what's there...")
  local todo, undo, kept, changing, halves = {}, {}, 0, {}, {}
  local ok, readErr = pcall(eachBlock, a, function(bx, by, bz, info)
    local target = want[key(bx, by, bz)] or (p.clear and "minecraft:air" or nil)
    if not target or not info then return end
    if AIR[info.name] and AIR[target] then return end
    if info.name == target then return end
    if keep(info) then
      kept = kept + 1
      return
    end
    todo[#todo + 1] = { bx, by, bz, target }
    undo[#undo + 1] = { bx, by, bz, AIR[info.name] and "minecraft:air" or blockString(info) }
    changing[key(bx, by, bz)] = true
    local half = info.state and info.state.half
    if half == "lower" or half == "upper" then halves[#halves + 1] = { bx, by + (half == "lower" and 1 or -1), bz, info.name } end
  end)
  if not ok then error("Couldn't read the blocks there: " .. tostring(readErr) .. " Is it all loaded (within render distance)?", 0) end
  if #todo == 0 then return print("It's already there: nothing to change.") end

  -- a door or tall plant loses its other half when one half is replaced:
  -- keep that half for undo too, if it isn't being replaced anyway
  for _, h in ipairs(halves) do
    local inside = h[2] >= a.y0 and h[2] <= a.y1
    if not (inside and changing[key(h[1], h[2], h[3])]) then
      local okInfo, info = pcall(commands.getBlockInfo, h[1], h[2], h[3])
      if okInfo and info and info.name == h[4] then undo[#undo + 1] = { h[1], h[2], h[3], blockString(info) } end
    end
  end

  local undoRuns = runs(undo)
  undo = nil
  -- the old copy goes first: two copies of a big build don't fit on the disk
  files.delete(UNDO_FILE)
  files.write(UNDO_FILE, { name = p.name, runs = undoRuns })
  local failed, why = place(runs(todo), "Building:")
  if failed > 0 then
    printError(("%d runs failed (%s): is all of it loaded?"):format(failed, tostring(why)))
  end
  print(("Built %s: %d blocks changed%s."):format(p.name, #todo,
    kept > 0 and (", %d kept (chests, computers...)"):format(kept) or ""))
  print("'instabuild undo' puts back what was there.")
end

local function undoLast()
  local u = files.read(UNDO_FILE)
  if not u then return print("Nothing to undo.") end
  write(("Put back what %s replaced? (y/n) "):format(u.name))
  local answer = read()
  if not answer or answer:lower():sub(1, 1) ~= "y" then return print("Left as it is.") end
  local failed, why = place(u.runs, "Undoing:")
  if failed > 0 then printError(("%d runs failed (%s): is all of it loaded?"):format(failed, tostring(why))) end
  files.delete(UNDO_FILE)
  print(("Undone %s."):format(u.name))
end

local function main()
  local cmd = args[1]
  if cmd == nil then
    print("Usage: instabuild <plan> <x> <y> <z> [facing], instabuild <plan> here,")
    print("instabuild list, instabuild check <plan>, instabuild undo")
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
  if cmd == "undo" then return undoLast() end
  build(cmd, { args[2], args[3], args[4] }, args[2] == "here" and args[3] or args[5])
end

if errlog then errlog.init("instabuild") end
local ok, err = (errlog and errlog.pcall or pcall)(main)
if not ok and err ~= "Terminated" then printError(err) end
