-- GPS deployer: flies up and builds a 4-computer GPS constellation, installs
-- `gps host` on each one with its own coordinates, and turns them on.
--
--   gps-deploy [height]        (default: as high as the turtle can go)
--
-- The turtle needs, anywhere in its inventory:
--   4 computers (normal or advanced)
--   4 wireless or ender modems (ender modems give unlimited range)
--   1 disk drive and 1 floppy disk (both come back afterwards)
--   about 750 fuel
-- Place it somewhere with open sky above: it flies straight up.
--
-- If anything goes wrong it lands back on the ground below where it started.
-- Running it again picks up where it left off: finished hosts are skipped.
local nav = require("lib.nav")

-- Host positions relative to the turtle's start, at the chosen height. One
-- sits higher than the others so they're not all in one plane (GPS needs
-- that). None is above the start, so the turtle's way up and down stays clear.
local HOSTS = {
  { x = 2, y = 0, z = 2 },
  { x = 10, y = 0, z = 2 },
  { x = 2, y = 0, z = 10 },
  { x = 6, y = 6, z = 6 },
}
local FLY_ABOVE = 9 -- travel between hosts at this height above the base, clear of everything

local ITEMS = {
  computer = { "computercraft:computer_normal", "computercraft:computer_advanced" },
  modem = { "computercraft:wireless_modem_normal", "computercraft:wireless_modem_advanced" },
  drive = { "computercraft:disk_drive" },
  disk = { "computercraft:disk" },
}

-- Program each host runs on boot. Coordinates are added in front of it.
local HOST_PROGRAM = [[
-- GPS host, placed by the gps-deployer turtle. Restarts if it ever stops.
local report = fs.exists("lib/report.lua") and require("lib.report")
while true do
  if report then
    report.init("gps host")
    report.set("serving", ("GPS at %d, %d, %d"):format(x, y, z), { pos = { x = x, y = y, z = z }, posFrom = "fixed" })
    parallel.waitForAny(function() shell.run("gps", "host", x, y, z) end, report.loop)
  else
    shell.run("gps", "host", x, y, z)
  end
  sleep(5)
end
]]

-- Runs from the floppy when a new host first boots: installs the host
-- program (and lib/report.lua if it's on the disk), names the computer, starts.
local INSTALLER = [[
local program, name = %q, %q
local dir = fs.getDir(shell.getRunningProgram())
if fs.exists(fs.combine(dir, "report.lua")) then
  if fs.exists("lib/report.lua") then fs.delete("lib/report.lua") end
  fs.copy(fs.combine(dir, "report.lua"), "lib/report.lua")
end
local f = fs.open("startup.lua", "w")
f.write(program)
f.close()
os.setComputerLabel(name)
shell.run("startup.lua")
]]

---------------------------------------------------------------- helpers

local function count(names)
  local n = 0
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      for _, name in ipairs(names) do
        if item.name == name then n = n + item.count end
      end
    end
  end
  return n
end

local function selectItem(names)
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      for _, name in ipairs(names) do
        if item.name == name then
          turtle.select(slot)
          return true
        end
      end
    end
  end
  error("ran out of " .. names[1], 0)
end

local function selectEmpty()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then
      turtle.select(slot)
      return
    end
  end
end

local function check(ok, err)
  if not ok then error("can't move: " .. tostring(err), 0) end
end

local function go(x, y, z) check(nav.goTo(x, y, z)) end

local function blockBelowIs(fragment)
  local ok, data = turtle.inspectDown()
  return ok and data.name:find(fragment, 1, true) ~= nil
end

local function fuelLevel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

---------------------------------------------------------------- deploy

local base, flyY

-- Fly across above everything already built, then drop straight down.
local function travel(x, y, z)
  local p = nav.getPos()
  go(p.x, math.max(p.y, flyY), p.z)
  go(x, flyY, z)
  go(x, y, z)
end

-- Take the disk drive (and the floppy in it) back, if one was left beside P.
local function collectDrive(P)
  go(P.x + 1, P.y, P.z - 1)
  nav.face("west")
  local ok, data = turtle.inspect()
  if ok and data.name == "computercraft:disk_drive" then
    selectEmpty()
    turtle.suck()
    selectEmpty()
    turtle.dig()
  end
end

-- Build one host with its computer at P:
--   computer at P, modem on top of it (P+up),
--   disk drive temporarily on its north side (P+north).
-- Every step checks whether an earlier run already did it.
local function deployHost(i, P)
  local name = "GPS-" .. i
  print(("%s at %d, %d, %d"):format(name, P.x, P.y, P.z))

  travel(P.x, P.y + 2, P.z)
  if not blockBelowIs("modem") then
    go(P.x, P.y + 1, P.z)
    if not blockBelowIs("computer_") then
      selectItem(ITEMS.computer)
      if not turtle.placeDown() then error("couldn't place the computer for " .. name, 0) end
    end
    go(P.x, P.y + 2, P.z)
    selectItem(ITEMS.modem)
    turtle.placeDown() -- lands in the gap, attached to the top of the computer
    if not blockBelowIs("modem") then error("couldn't attach the modem for " .. name, 0) end
  end

  -- already installed and running from an earlier run?
  go(P.x + 1, P.y, P.z)
  nav.face("west")
  if peripheral.call("front", "getLabel") == name then
    print("  already running")
    collectDrive(P)
    return
  end

  -- disk drive beside the computer, with the installer on the floppy
  go(P.x, P.y + 1, P.z - 1)
  if not blockBelowIs("disk_drive") then
    selectItem(ITEMS.drive)
    if not turtle.placeDown() then error("couldn't place the disk drive", 0) end
  end
  if not disk.getMountPath("bottom") then
    selectItem(ITEMS.disk)
    turtle.dropDown()
  end
  local mount = disk.getMountPath("bottom")
  if not mount then error("the floppy didn't go into the disk drive", 0) end
  local program = ("local x, y, z = %d, %d, %d\n"):format(P.x, P.y, P.z) .. HOST_PROGRAM
  local f = fs.open(fs.combine(mount, "startup.lua"), "w")
  f.write(INSTALLER:format(program, name))
  f.close()
  local reportPath = fs.combine(mount, "report.lua")
  if fs.exists(reportPath) then fs.delete(reportPath) end
  if fs.exists("/lib/report.lua") then fs.copy("/lib/report.lua", reportPath) end

  -- go round to the computer's east side and switch it on
  go(P.x + 1, P.y, P.z)
  nav.face("west")
  peripheral.call("front", "turnOn")
  local started = false
  for _ = 1, 40 do
    sleep(0.5)
    if peripheral.call("front", "getLabel") == name then
      started = true
      break
    end
  end
  if not started then print("  " .. name .. " didn't confirm it started; check it later") end

  collectDrive(P)
end

local function askNumber(prompt)
  while true do
    write(prompt)
    local n = tonumber(read())
    if n and n == math.floor(n) then return n end
    print("Please enter a whole number.")
  end
end

-- There's no GPS yet, so the player reads these off F3. All of them matter:
-- every host serves its exact coordinates, and the turtle needs Y to know how
-- far to climb and its facing to know which way east is.
local function askPosition()
  print("Press F3 and look at the turtle's block.")
  print("(\"Targeted Block\" on the right shows its X, Y, Z.)")
  local x = askNumber("X: ")
  local y = askNumber("Y: ")
  local z = askNumber("Z: ")
  print("Which way is the turtle facing? Stand behind it, looking the")
  print("same way, and read \"Facing\" on F3.")
  while true do
    write("Facing (north/east/south/west): ")
    local facing = read():lower():gsub("%s", "")
    if nav.HEADINGS[facing] then
      nav.setPosition(x, y, z, facing)
      return
    end
    print("Please type north, east, south or west.")
  end
end

-- Climb straight up until the world stops the turtle (or it reaches limit).
-- Asking the world is more reliable than guessing the build limit from the
-- game version: modpacks and datapacks change it.
local function climb(limit)
  while nav.getPos().y < limit do
    local ok, err = nav.up()
    if not ok then
      if err == "nofuel" then error("ran out of fuel", 0) end
      if turtle.detectUp() then error("something above me I can't get through (" .. tostring(err) .. ")", 0) end
      break -- nothing there, but the world won't let it go higher: that's the top
    end
  end
  return nav.getPos().y
end

local start

-- Back down to the ground below where it started, over the top of anything built.
local function land()
  local p = nav.getPos()
  local high = math.max(p.y, flyY or p.y)
  nav.goTo(p.x, high, p.z)
  nav.goTo(start.x, high, start.z)
  while not turtle.detectDown() do
    if not nav.down() then break end
  end
end

---------------------------------------------------------------- main

local requested = ({ ... })[1]
if requested and not tonumber(requested) then
  print("Usage: gps-deploy [height]")
  return
end
requested = tonumber(requested)

-- There's no GPS yet, so the turtle has to be told where it is, unless it
-- still knows from an earlier run.
if nav.init(false) then
  local p, names = nav.getPos(), { [0] = "north", "east", "south", "west" }
  print(("Last known position: X %d, Y %d, Z %d, facing %s."):format(p.x, p.y, p.z, names[nav.getHeading()]))
  write("Is that still right? (y/n): ")
  if read():lower():sub(1, 1) ~= "y" then askPosition() end
else
  askPosition()
end
start = nav.getPos()
local startHeading = nav.getHeading()

if count(ITEMS.drive) < 1 or count(ITEMS.disk) < 1 then
  print("I need a disk drive and a floppy disk.")
  return
end
local computers, modems = count(ITEMS.computer), count(ITEMS.modem)
if computers < 4 or modems < 4 then
  -- fine when an earlier run already built some of the hosts
  print(("I only have %d computers and %d modems; a full set is 4 of each."):format(computers, modems))
  write("Continue anyway, e.g. to finish an earlier run? (y/n): ")
  if read():lower():sub(1, 1) ~= "y" then return end
end
local fuelNeeded = 2 * math.max(0, 320 - start.y) + 200
if fuelLevel() < fuelNeeded then
  print(("Needs about %d fuel, has %d. Add fuel and run 'refuel all'."):format(fuelNeeded, fuelLevel()))
  return
end

if requested then
  print(("Building GPS hosts at Y %d-%d."):format(requested, requested + 6))
else
  print("I'll climb as high as I can go and build the GPS just below that.")
end
print("Make sure the sky above me is clear. Press Enter to start.")
read()

local ok, err = pcall(function()
  local reached = climb(requested and requested + FLY_ABOVE or math.huge)
  local height = reached - FLY_ABOVE
  if requested and requested < height then height = requested end
  if requested and requested > height then
    print(("Can only go up to Y %d here, so building at Y %d instead."):format(reached, height))
  end
  base = { x = start.x, y = height, z = start.z }
  flyY = height + FLY_ABOVE
  print(("Building at Y %d-%d."):format(height, height + 6))
  for i, offset in ipairs(HOSTS) do
    deployHost(i, { x = base.x + offset.x, y = base.y + offset.y, z = base.z + offset.z })
  end
end)

land()
nav.face(startHeading)
if not ok then
  print("Stopped: " .. tostring(err))
  print("I've come back down. Fix that and run gps-deploy again;")
  print("anything already built is skipped.")
  return
end
print("All 4 GPS hosts are running.")

-- Check it works, if this turtle has a modem of its own.
if peripheral.find("modem", function(_, m) return m.isWireless() end) then
  local x, y, z = gps.locate(5)
  local p = nav.getPos()
  if x then
    print(("GPS says I'm at %d, %d, %d (expected %d, %d, %d)."):format(
      math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5), p.x, p.y, p.z))
  else
    print("Couldn't get a GPS fix from down here. Wireless modems may be out of")
    print("range at this height; ender modems on the hosts fix that.")
  end
end
