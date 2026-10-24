-- Position tracking and safe movement for turtles.
-- Position and heading are saved after every move so a turtle can pick up
-- where it left off after a reboot or chunk unload. GPS corrects drift on boot.
local nav = {}

local STATE_FILE = "/.nav_state"

-- Headings: 0 = north (-z), 1 = east (+x), 2 = south (+z), 3 = west (-x)
local DIRS = { [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 } }
local HEADINGS = { north = 0, east = 1, south = 2, west = 3 }
nav.HEADINGS = HEADINGS

-- Never dig these: storage, anything from ComputerCraft (including other turtles), spawners.
local PROTECTED = { "chest", "barrel", "shulker_box", "hopper", "furnace", "computercraft:", "spawner" }

local pos = { x = 0, y = 0, z = 0 }
local heading = 0

-- Write to a temp file first so a crash mid-save never leaves a broken file.
function nav.writeFile(path, value)
  local tmp = path .. ".tmp"
  local f = fs.open(tmp, "w")
  f.write(textutils.serialize(value))
  f.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
end

function nav.readFile(path)
  for _, p in ipairs({ path, path .. ".tmp" }) do
    if fs.exists(p) then
      local f = fs.open(p, "r")
      local value = textutils.unserialize(f.readAll())
      f.close()
      if value then return value end
    end
  end
end

function nav.deleteFile(path)
  for _, p in ipairs({ path, path .. ".tmp" }) do
    if fs.exists(p) then fs.delete(p) end
  end
end

local function save()
  nav.writeFile(STATE_FILE, { x = pos.x, y = pos.y, z = pos.z, heading = heading })
end

local function load()
  local s = nav.readFile(STATE_FILE)
  if not s then return false end
  pos = { x = s.x, y = s.y, z = s.z }
  heading = s.heading
  return true
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
      if err == "nofuel" or detours >= 8 then return false, err end
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

local function locate()
  local x, y, z = gps.locate(2)
  if not x then return nil end
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
end

local function headingBetween(p1, p2)
  for h, d in pairs(DIRS) do
    if p2.x - p1.x == d.x and p2.z - p1.z == d.z then return h end
  end
end

-- Work out position and heading from GPS by stepping forward once and back.
local function calibrate()
  local p1 = locate()
  if not p1 then return false end
  local moved = false
  for _ = 1, 4 do
    if turtle.forward() then moved = true break end
    nav.turnRight()
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

function nav.setPosition(x, y, z, h)
  pos = { x = x, y = y, z = z }
  heading = type(h) == "string" and HEADINGS[h] or h
  save()
end

return nav
