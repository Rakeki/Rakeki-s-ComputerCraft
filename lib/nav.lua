-- Position tracking and safe movement for turtles.
-- Position and heading are saved after every move so a turtle can pick up
-- where it left off after a reboot or chunk unload. GPS corrects drift on boot.
local files = require("lib.files") -- crash-safe save files
local nav = {}

local STATE_FILE = "/.nav_state"
local GPS_RETRY = 5 -- seconds between tries while waiting for GPS
local RANGE_SETTING = "nav.range" -- blocks a turtle may go from where it started, along X or Z (0: no limit)
local DEFAULT_RANGE = 256 -- the range when nav.range isn't set
local MOVED_BY = 8 -- GPS this far from the saved position: the player moved it, so that's its new start
local TOO_FAR = "too far from where I started (nav.range)" -- the error a move past the range returns

-- Headings: 0 = north (-z), 1 = east (+x), 2 = south (+z), 3 = west (-x)
local DIRS = { [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 } }
local HEADINGS = { north = 0, east = 1, south = 2, west = 3 }
nav.HEADINGS = HEADINGS

-- Never dig these: storage, anything from ComputerCraft (including other turtles), spawners.
local PROTECTED = { "chest", "barrel", "shulker_box", "hopper", "furnace", "computercraft:", "spawner" }

local pos = { x = 0, y = 0, z = 0 }
local heading = 0
local onMap = false -- pos is in world coordinates (GPS, or typed from F3)
local origin -- { x, z, world }: where it started, the middle of its range

settings.define(RANGE_SETTING, {
  type = "number",
  default = DEFAULT_RANGE,
  description = "How far this turtle may go from where it started, in blocks along X or Z (0: no limit).",
})

-- Crash-safe save files (lib/files.lua): a temp file first, so a crash
-- mid-save never leaves a broken file.
nav.writeFile, nav.readFile, nav.deleteFile = files.write, files.read, files.delete

local function save()
  nav.writeFile(STATE_FILE, { x = pos.x, y = pos.y, z = pos.z, heading = heading, world = onMap, origin = origin })
end

local function load()
  local s = nav.readFile(STATE_FILE)
  if not s then return false end
  pos = { x = s.x, y = s.y, z = s.z }
  heading = s.heading
  onMap = s.world == true
  origin = type(s.origin) == "table" and s.origin or nil
  return true
end

---------------------------------------------------------------- range

-- A turtle never goes more than nav.range blocks (along X or Z) from where
-- it started: the first place it knew its position. Up and down are never
-- limited, so it can always climb out or dig down.
nav.TOO_FAR = TOO_FAR

-- The range in blocks, or nil for no limit.
function nav.range()
  local r = tonumber(settings.get(RANGE_SETTING))
  if not r then return DEFAULT_RANGE end
  if r <= 0 then return nil end
  return math.floor(r)
end

-- Where it started, { x, z }, or nil before it knows its position.
function nav.origin() return origin and { x = origin.x, z = origin.z } end

local function away(x, z) return math.max(math.abs(x - origin.x), math.abs(z - origin.z)) end

-- True when the column x, z is within range of where it started.
function nav.inRange(x, z)
  local r = nav.range()
  return not (r and origin) or away(x, z) <= r
end

-- A move onto column x, z is allowed within range, or (somehow already
-- out of it) when it brings the turtle closer.
local function mayMoveTo(x, z)
  local r = nav.range()
  if not (r and origin) then return true end
  local after = away(x, z)
  return after <= r or after < away(pos.x, pos.z)
end

-- Make here the start: the first time it knows its position, when its
-- position changes to another kind of coordinates (a job without GPS counts
-- from its own start), or when it's been moved.
local function anchor(moved)
  if not origin or origin.world ~= onMap or moved then
    if origin and moved then print("I've been moved: this is my new start.") end
    origin = { x = pos.x, z = pos.z, world = onMap }
  end
end

-- For a job that skips cells it can't reach: say once, the first time a
-- move is refused for being too far, that what's past the range is left out.
local toldTooFar = false
function nav.sayTooFar()
  if not toldTooFar then
    toldTooFar = true
    print(("That's past my range (%d blocks from where I started), so I'll leave out what's beyond it. 'set nav.range <blocks>' changes it."):format(nav.range() or 0))
  end
  return TOO_FAR
end

-- Start the range from here (e.g. a turtle given a new home).
function nav.resetOrigin()
  origin = { x = pos.x, z = pos.z, world = onMap }
  save()
end

local ACTIONS = {
  forward = { move = turtle.forward, dig = turtle.dig, detect = turtle.detect, inspect = turtle.inspect, attack = turtle.attack },
  up = { move = turtle.up, dig = turtle.digUp, detect = turtle.detectUp, inspect = turtle.inspectUp, attack = turtle.attackUp },
  down = { move = turtle.down, dig = turtle.digDown, detect = turtle.detectDown, inspect = turtle.inspectDown, attack = turtle.attackDown },
}

local function blockName(a)
  local ok, data = a.inspect()
  return ok and data.name or nil
end

local function isProtected(name)
  for _, p in ipairs(PROTECTED) do
    if name:find(p, 1, true) then return true end
  end
  return false
end

local function hasFuel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" or f > 0
end

-- Dig in direction dir unless the block is protected. Returns true once the space is clear.
local function dig(dir)
  local a = ACTIONS[dir]
  for _ = 1, 16 do -- falling gravel/sand can refill the space
    if not a.detect() then return true end
    local name = blockName(a) or ""
    if isProtected(name) then return false, "protected" end
    if not a.dig() then return false, name == "minecraft:bedrock" and "bedrock" or "undiggable" end
  end
  return not a.detect(), "blocked"
end

local function tryMove(dir)
  if not hasFuel() then return false, "nofuel" end
  if dir == "forward" and not mayMoveTo(pos.x + DIRS[heading].x, pos.z + DIRS[heading].z) then return false, TOO_FAR end
  local a = ACTIONS[dir]
  for _ = 1, 30 do
    if a.move() then return true end
    if a.detect() then
      if (blockName(a) or ""):find("computercraft:turtle", 1, true) then
        sleep(1) -- another miner passing through; give it a moment
      else
        local ok, err = dig(dir)
        if not ok then return false, err end
      end
    else
      a.attack() -- a mob is in the way
      sleep(0.2)
    end
  end
  return false, "blocked"
end

function nav.forward()
  local ok, err = tryMove("forward")
  if ok then
    pos.x, pos.z = pos.x + DIRS[heading].x, pos.z + DIRS[heading].z
    save()
  end
  return ok, err
end

function nav.up()
  local ok, err = tryMove("up")
  if ok then pos.y = pos.y + 1; save() end
  return ok, err
end

function nav.down()
  local ok, err = tryMove("down")
  if ok then pos.y = pos.y - 1; save() end
  return ok, err
end

function nav.turnLeft()
  turtle.turnLeft()
  heading = (heading + 3) % 4
  save()
end

function nav.turnRight()
  turtle.turnRight()
  heading = (heading + 1) % 4
  save()
end

-- h is a heading number or a name like "north".
function nav.face(h)
  if type(h) == "string" then h = HEADINGS[h] end
  local diff = (h - heading) % 4
  if diff == 1 then
    nav.turnRight()
  elseif diff == 2 then
    nav.turnRight(); nav.turnRight()
  elseif diff == 3 then
    nav.turnLeft()
  end
end

function nav.digUp() return dig("up") end
function nav.digDown() return dig("down") end

function nav.getPos() return { x = pos.x, y = pos.y, z = pos.z } end
function nav.getHeading() return heading end

-- Rise first, then move horizontally, then descend. Goes over protected or
-- unbreakable blocks that are in the way.
function nav.goTo(tx, ty, tz)
  while pos.y < ty do
    local ok, err = nav.up()
    if not ok then return false, err end
  end
  local detours = 0
  while pos.x ~= tx or pos.z ~= tz do
    if pos.x ~= tx then nav.face(tx > pos.x and 1 or 3) else nav.face(tz > pos.z and 2 or 0) end
    local ok, err = nav.forward()
    if not ok then
      -- going over doesn't help with the range: stop at once
      if err == "nofuel" or err == TOO_FAR or detours >= 8 then return false, err end
      detours = detours + 1
      local upOk, upErr = nav.up()
      if not upOk then return false, upErr end
    end
  end
  while pos.y > ty do
    local ok, err = nav.down()
    if not ok then return false, err end
  end
  while pos.y < ty do
    local ok, err = nav.up()
    if not ok then return false, err end
  end
  return true
end

-- Where GPS says the turtle is, to the block; nil without GPS.
local function locate()
  local x, y, z = gps.locate(2)
  if not x then return nil end
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
end
nav.locate = locate

-- Turtles that move need GPS: without it a wrong saved position (a chunk
-- unloading mid-move, a turtle picked up) sends them digging in the wrong
-- place. Wait until it answers, saying why on screen and on the status
-- server: after a server restart the GPS hosts may still be starting.
function nav.waitForGps()
  local p = locate()
  if p then return p end
  local report = package.loaded["lib.report"] -- only if the program uses it
  print("Waiting for GPS: I need it to know where I am.")
  print("No GPS here yet? Build one with a gps-deployer turtle.")
  if report then report.set("waiting", "no GPS: waiting for it") end
  local said = os.clock()
  repeat
    sleep(GPS_RETRY)
    p = locate()
    if not p and os.clock() - said >= 60 then
      print("Still no GPS. Waiting...")
      said = os.clock()
    end
  until p
  print("GPS found.")
  return p
end

local function headingBetween(p1, p2)
  for h, d in pairs(DIRS) do
    if p2.x - p1.x == d.x and p2.z - p1.z == d.z then return h end
  end
end

-- Work out position and heading from GPS by stepping forward once and back.
-- Ends facing the way it started: jobs take the start facing as their
-- forward, so a turn left in here would turn the whole job.
-- The step needs fuel, and a new turtle has none burnt: without it the step
-- fails and the heading would be a guess (north). Burn one fuel item it
-- carries, or say so and wait for some.
local function fuelForStep()
  if hasFuel() then return end
  local function burnOne()
    for slot = 1, 16 do
      if turtle.getItemCount(slot) > 0 then
        turtle.select(slot)
        if turtle.refuel(1) then turtle.select(1) return true end
      end
    end
    turtle.select(1)
    return false
  end
  if burnOne() then return end
  print("I need a little fuel to step forward once and find which way I face.")
  print("Put some coal (or any fuel) in my inventory.")
  repeat os.pullEvent("turtle_inventory") until burnOne()
end

local function calibrate()
  local p1 = locate()
  if not p1 then return false end
  -- far from where it last saved itself (in world coordinates): picked up and placed elsewhere
  local moved = onMap and (math.abs(p1.x - pos.x) > MOVED_BY or math.abs(p1.z - pos.z) > MOVED_BY)
  fuelForStep()
  local moved, turns = false, 0
  for _ = 1, 4 do
    if turtle.forward() then moved = true break end
    nav.turnRight()
    turns = turns + 1
  end
  if not moved and dig("forward") then moved = turtle.forward() end
  if moved then
    local p2 = locate()
    if p2 then heading = headingBetween(p1, p2) or heading end
    if turtle.back() then
      pos = p1
    else
      pos = p2 or { x = p1.x + DIRS[heading].x, y = p1.y, z = p1.z + DIRS[heading].z }
    end
  else
    pos = p1 -- boxed in: position is right, heading is the last saved one
  end
  onMap = true
  anchor(moved)
  for _ = 1, turns % 4 do nav.turnLeft() end
  save()
  return true
end

-- Returns true if the turtle knows where it is (GPS or a saved position).
-- Pass false to skip GPS and use only the saved position.
function nav.init(useGps)
  local loaded = load()
  if useGps ~= false and calibrate() then return true end
  return loaded
end

-- world: these are world coordinates (from GPS or F3); leave it out for a
-- position counted from the job's own start. Either way the range starts
-- here if it hasn't started yet in that kind of coordinates.
function nav.setPosition(x, y, z, h, world)
  onMap = world == true
  pos = { x = x, y = y, z = z }
  heading = type(h) == "string" and HEADINGS[h] or h
  anchor(false)
  save()
end

-- Resuming without GPS to check against: give the player 10 seconds to say
-- the turtle was moved. True to carry on; false (after printing putBack,
-- what to do instead) if they pressed a key.
function nav.confirmResume(putBack)
  print("No GPS, so I'm trusting my saved position.")
  print("Resuming in 10 seconds. If you moved me, press any key.")
  local timer = os.startTimer(10)
  while true do
    local event, value = os.pullEvent()
    if event == "timer" and value == timer then return true end
    if event == "key" then
      print(putBack)
      return false
    end
  end
end

return nav
