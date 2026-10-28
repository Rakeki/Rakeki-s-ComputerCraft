-- Build control: hands a plan from /plans to the builder turtles
-- (computers/builder-turtle) at coordinates you give, no projector needed.
-- Runs on any computer or pocket computer with a wireless or ender modem.
-- The free builders (up to 4) each take a strip, as from the blueprint
-- projector's Build button; this keeps track of them, gives waiting strips
-- to the next free one, and says how they're getting on.
--
--   build list                          the plans here, with their sizes
--   build check <plan>                  size and the blocks it needs
--   build <plan> <x> <y> <z> [facing]   build it with its north-west bottom corner at x y z
--   build <plan> here [facing]          ...at this computer's position (GPS)
--   build watch                         follow the builders (startup.lua runs this)
--   build stop                          call them off (again: give up on ones that don't answer)
--
-- facing is where the plan's front (its first row) faces: north (the
-- default), east, south or west. Plans: 'install plan <name>', or your own
-- .json / .lua in /plans (see lib/plan.lua).
local plans = require("lib.plan") -- loading plans and placing them in the world
local crew = require("lib.crew") -- hands the plan to builder turtles
local net = require("lib.net")
local files = require("lib.files")
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local STATE_FILE = "/.build_control" -- the plan, where it goes, and the build in progress
local PLAN_COPY = "/.build_control_plan" -- the plan being built, copied when it started (.json or .lua)
local FACINGS = { north = 0, east = 1, south = 2, west = 3 }
local GPS_WAIT = 5 -- seconds to wait for a GPS fix ('build <plan> here')

local args = { ... }
local state = files.read(STATE_FILE) or {}

local function status(s, detail)
  if report then report.set(s, detail) end
end

local function facingName(turn)
  for name, t in pairs(FACINGS) do
    if t == turn % 4 then return name end
  end
end

---------------------------------------------------------------- the builders

local done = false
local job -- the plan in world coordinates, worked out once (a big plan takes a moment)
local builders = crew.new({
  job = function()
    if not job then
      local p, err = plans.load(state.plan)
      if not p then error(err, 0) end
      local mats, blocks = plans.world(p, state.at)
      job = { id = state.plan, name = p.name, mats = mats, blocks = blocks, area = plans.area(p, state.at), clear = p.clear }
    end
    return job
  end,
  build = state.build,
  save = function(build)
    state.build = build
    files.write(STATE_FILE, state)
  end,
  tell = function(text) print(text) end,
  finished = function(text)
    if report then report.log(text) end
    status("idle", text)
    done = true
    os.queueEvent("build_done")
  end,
})

-- Follow the builders until every strip is built or stopped: their progress
-- on screen, one line whenever it changes.
local function watch()
  if not builders.build then
    print("Nothing is being built. Start with: build <plan> <x> <y> <z>")
    return
  end
  if not net.open() then error("Needs a wireless or ender modem to hear the builder turtles.", 0) end
  print(("Following the builders of %s. Ctrl+T leaves them building;"):format(builders.build.name))
  print("'build watch' picks it up again.")
  local said
  parallel.waitForAny(function() builders:run() end, function()
    while not done do
      if builders.build then
        local text = builders:note()
        if text ~= said then
          print(text)
          status("building", text)
          said = text
        end
      end
      local timer = os.startTimer(5)
      repeat
        local ev, id = os.pullEvent()
      until ev == "build_done" or (ev == "timer" and id == timer)
    end
  end, report and report.loop or function() while true do sleep(3600) end end)
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

local function start(id, where, facingArg)
  if builders.build then
    error(("Already building %s: 'build stop' first, or 'build watch'."):format(builders.build.name), 0)
  end
  local p, err = plans.load(id)
  if not p then error(err, 0) end
  local turn = FACINGS[facingArg or "north"]
  if not turn then error("Facing must be north, east, south or west.", 0) end
  local x, y, z
  if where[1] == "here" then
    x, y, z = gps.locate(GPS_WAIT)
    if not x then error("No GPS fix: give the coordinates instead (build <plan> <x> <y> <z>).", 0) end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
  else
    x, y, z = tonumber(where[1]), tonumber(where[2]), tonumber(where[3])
    if not (x and y and z) then error("Usage: build <plan> <x> <y> <z> [facing]", 0) end
  end
  local at = plans.corner(p, turn, x, y, z)
  local a = plans.area(p, at)
  print(("%s facing %s: %d x %d x %d, %d blocks,"):format(p.name, facingName(turn), p.w, p.l, p.h, #p.blocks))
  print(("from %d,%d,%d to %d,%d,%d."):format(a.x0, a.y0, a.z0, a.x1, a.y1, a.z1))
  if p.clear then
    print("The builders dig out everything in that box first: keep chests and computers out of it.")
  else
    print("It's built in the air: nothing is dug out first.")
  end
  write("Build it? (y/n) ")
  local answer = read()
  if not answer or answer:lower():sub(1, 1) ~= "y" then return print("Not built.") end
  if not net.open() then error("Needs a wireless or ender modem to reach the builder turtles.", 0) end
  -- build from a copy: strips handed out after a reboot must come from the
  -- same plan, even if /plans/<id> is updated meanwhile
  local copy, copyErr = plans.copy(id, PLAN_COPY)
  if not copy then error(copyErr, 0) end
  state.plan, state.at = copy, at
  files.write(STATE_FILE, state)
  if builders:start() then watch() end
end

local function main()
  local cmd = args[1]
  if report then report.init("build control") end
  if cmd == nil then
    print("Usage: build <plan> <x> <y> <z> [facing], build <plan> here,")
    print("build list, build check <plan>, build watch, build stop")
  elseif cmd == "list" then
    listPlans()
  elseif cmd == "check" then
    if not args[2] then error("Usage: build check <plan>", 0) end
    checkPlan(args[2])
  elseif cmd == "watch" then
    watch()
  elseif cmd == "stop" then
    if not builders.build then return print("Nothing is being built.") end
    if not net.open() then error("Needs a wireless or ender modem to reach the builder turtles.", 0) end
    builders:stop()
    if builders.build then watch() end
  else
    start(cmd, { args[2], args[3], args[4] }, args[2] == "here" and args[3] or args[5])
  end
end

if errlog then errlog.init("build", function() return { plan = state.plan } end) end
local ok, err = (errlog and errlog.pcall or pcall)(main)
if not ok then
  if err == "Terminated" then return end
  status("error", tostring(err))
  printError(err)
end
