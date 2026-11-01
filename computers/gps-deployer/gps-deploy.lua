-- GPS deployer: flies up and builds a 4-computer GPS constellation, installs
-- `gps host` on each one with its own coordinates, and turns them on.
-- With `satellite` it also builds a satellite around each host: a hull with
-- the computer inside, an antenna dish, solar wings and lights.
--
--   gps-deploy [height]              (default: as high as the turtle can go)
--   gps-deploy satellite [height]    hosts spread wider, each in a satellite
--
-- The turtle needs, anywhere in its inventory:
--   4 computers (normal or advanced)
--   4 wireless or ender modems (ender modems give unlimited range)
--   1 disk drive and 1 floppy disk (both come back afterwards)
--   about 750 fuel (about 3000 with satellites)
-- and for satellites (it lists what's missing before it starts):
--   100 hull blocks, 64 daylight detectors, 48 iron bars, 32 slabs,
--   12 lights (sea lanterns, glowstone, froglights), 8 end or lightning rods
-- Place it somewhere with open sky above: it flies straight up.
--
-- If anything goes wrong it lands back on the ground below where it started.
-- Running it again picks up where it left off: finished hosts are skipped.
local nav = require("lib.nav")
local inv = require("lib.inv") -- inventory and fuel
local errlog = require("lib.errlog") -- saves errors to /errors.log

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

-- With satellites: each satellite reaches 8 blocks east and west of its host
-- and 1 north and south, so the hosts sit further apart (a wider spread helps
-- GPS too), and the raised one is clear of the others' antennas.
local SAT_HOSTS = {
  { x = 9, y = 0, z = 4 },
  { x = 28, y = 0, z = 4 },
  { x = 9, y = 0, z = 22 },
  { x = 18, y = 9, z = 13 },
}
local SAT_FLY_ABOVE = 14 -- above the raised satellite's antenna
local SAT_TOP = 3 -- the antenna's tip, above the host; the turtle crosses a satellite just over it
local SAT_FUEL = 600 -- roughly what building one satellite burns

-- What each part of a satellite may be made of. Any of these will do; one
-- kind per part looks tidiest.
local SAT_ITEMS = {
  hull = { "minecraft:iron_block", "minecraft:white_concrete", "minecraft:light_gray_concrete",
    "minecraft:smooth_quartz", "minecraft:quartz_block" },
  panel = { "minecraft:daylight_detector", "minecraft:blue_stained_glass", "minecraft:light_blue_stained_glass",
    "minecraft:black_stained_glass" },
  strut = { "minecraft:iron_bars" },
  dish = { "minecraft:smooth_quartz_slab", "minecraft:quartz_slab", "minecraft:smooth_stone_slab",
    "minecraft:polished_andesite_slab" },
  light = { "minecraft:sea_lantern", "minecraft:glowstone", "minecraft:shroomlight", "minecraft:ochre_froglight",
    "minecraft:verdant_froglight", "minecraft:pearlescent_froglight" },
  antenna = { "minecraft:end_rod", "minecraft:lightning_rod" },
}
local SAT_PARTS = { -- in the order they're listed to the player
  { "hull", "hull blocks (iron blocks, white or light gray concrete, smooth quartz)" },
  { "panel", "solar panels (daylight detectors, or blue or black stained glass)" },
  { "strut", "iron bars" },
  { "dish", "slabs (smooth quartz, quartz, smooth stone or polished andesite)" },
  { "light", "lights (sea lanterns, glowstone, shroomlights or froglights)" },
  { "antenna", "end rods or lightning rods" },
}

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

local count = inv.count

local function selectItem(names)
  if not inv.select(names) then error("ran out of " .. names[1], 0) end
  return true
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

local fuelLevel = inv.fuelLevel

---------------------------------------------------------------- satellite

-- A satellite around a host, relative to its computer (+x east): a 3x3x3
-- hull with the computer at its heart and the modem set in its top, an
-- antenna on the modem in a ring of slabs, solar wings east and west on
-- iron-bar spines with a light at each tip, and a light underneath.
-- Listed in build order. The antenna goes first, so a re-run that finds it
-- knows the host inside is done. The rest goes up a layer at a time, and the
-- turtle crosses above the antenna and drops straight down onto each block,
-- so it never passes through anything it placed.
local function satelliteBlocks()
  local list = {}
  local function add(part, x, y, z, side) list[#list + 1] = { part = part, x = x, y = y, z = z, side = side } end
  add("antenna", 0, 2, 0)
  add("antenna", 0, 3, 0)
  -- the computer is above these two, so they're placed from the east side
  add("light", 0, -2, 0, true)
  add("hull", 0, -1, 0, true)
  for x = -1, 1 do
    for z = -1, 1 do
      if x ~= 0 or z ~= 0 then add("hull", x, -1, z) end
    end
  end
  for y = 0, 1 do
    for x = -1, 1 do
      for z = -1, 1 do
        if x ~= 0 or z ~= 0 then add("hull", x, y, z) end
      end
    end
    if y == 0 then
      for _, s in ipairs({ 1, -1 }) do
        for d = 2, 7 do add("strut", s * d, 0, 0) end
        for d = 4, 7 do
          add("panel", s * d, 0, -1)
          add("panel", s * d, 0, 1)
        end
        add("light", s * 8, 0, 0)
      end
    end
  end
  for x = -1, 1 do
    for z = -1, 1 do
      if x ~= 0 or z ~= 0 then add("dish", x, 2, z) end
    end
  end
  return list
end

-- How many of each part all four satellites take.
local function satelliteNeeds()
  local need = {}
  for _, b in ipairs(satelliteBlocks()) do need[b.part] = (need[b.part] or 0) + 4 end
  return need
end

-- Inside a satellite the turtle moves across just above the antenna, then
-- straight up or down.
local function hop(P, x, y, z)
  local p, cruise = nav.getPos(), P.y + SAT_TOP + 1
  if p.x ~= x or p.z ~= z then
    go(p.x, cruise, p.z)
    go(x, cruise, z)
  end
  go(x, y, z)
end

-- Build the satellite around the host at P. Blocks already there are
-- skipped, so a re-run carries on where it stopped.
local function buildSatellite(P)
  print("  building its satellite")
  for _, b in ipairs(satelliteBlocks()) do
    local x, y, z = P.x + b.x, P.y + b.y, P.z + b.z
    local detect, place
    if b.side then
      hop(P, x + 1, y, z)
      nav.face("west")
      detect, place = turtle.detect, turtle.place
    else
      hop(P, x, y + 1, z)
      detect, place = turtle.detectDown, turtle.placeDown
    end
    if not detect() then
      if not inv.select(SAT_ITEMS[b.part]) then
        for _, part in ipairs(SAT_PARTS) do
          if part[1] == b.part then error("ran out of " .. part[2], 0) end
        end
      end
      if not place() then error(("couldn't place a block of the satellite at %d, %d, %d"):format(x, y, z), 0) end
    end
  end
end

---------------------------------------------------------------- deploy

local base, flyY, satellite

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

  if satellite then
    -- its antenna is up: the host inside is done, carry on with the satellite
    travel(P.x, P.y + SAT_TOP + 1, P.z)
    if turtle.detectDown() then
      print("  already running")
      buildSatellite(P)
      return
    end
  end

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
    if satellite then buildSatellite(P) end
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
  if satellite then buildSatellite(P) end
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

local requested
for _, arg in ipairs({ ... }) do
  if arg == "satellite" or arg == "satellites" then
    satellite = true
  elseif tonumber(arg) and not requested then
    requested = tonumber(arg)
  else
    print("Usage: gps-deploy [satellite] [height]")
    return
  end
end
local hosts = satellite and SAT_HOSTS or HOSTS
local flyAbove = satellite and SAT_FLY_ABOVE or FLY_ABOVE
local again = "gps-deploy" .. (satellite and " satellite" or "") .. (requested and " " .. requested or "")

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
if satellite then
  local need, short = satelliteNeeds(), {}
  for _, part in ipairs(SAT_PARTS) do
    local have = count(SAT_ITEMS[part[1]])
    if have < need[part[1]] then short[#short + 1] = ("  %d more %s"):format(need[part[1]] - have, part[2]) end
  end
  if #short > 0 then
    -- fine when an earlier run already built some of the satellites
    print("For all four satellites I'm short of:")
    for _, line in ipairs(short) do print(line) end
    write("Continue anyway, e.g. to finish an earlier run? (y/n): ")
    if read():lower():sub(1, 1) ~= "y" then return end
  end
end
local fuelNeeded = 2 * math.max(0, 320 - start.y) + 200 + (satellite and 4 * SAT_FUEL or 0)
if fuelLevel() < fuelNeeded then
  print(("Needs about %d fuel, has %d. Add fuel and run 'refuel all'."):format(fuelNeeded, fuelLevel()))
  return
end

local rise = hosts[#hosts].y -- the raised host
if requested then
  print(("Building GPS hosts at Y %d-%d."):format(requested, requested + rise))
else
  print("I'll climb as high as I can go and build the GPS just below that.")
end
print("Make sure the sky above me is clear. Press Enter to start.")
read()

errlog.init("gps-deploy", function() return { pos = nav.getPos() } end)
local ok, err = errlog.pcall(function()
  local reached = climb(requested and requested + flyAbove or math.huge)
  local height = reached - flyAbove
  if requested and requested < height then height = requested end
  if requested and requested > height then
    print(("Can only go up to Y %d here, so building at Y %d instead."):format(reached, height))
  end
  base = { x = start.x, y = height, z = start.z }
  flyY = height + flyAbove
  print(("Building at Y %d-%d."):format(height, height + rise))
  for i, offset in ipairs(hosts) do
    deployHost(i, { x = base.x + offset.x, y = base.y + offset.y, z = base.z + offset.z })
  end
end)

land()
nav.face(startHeading)
if not ok then
  print("Stopped: " .. tostring(err))
  print(("I've come back down. Fix that and run '%s' again;"):format(again))
  print("anything already built is skipped.")
  return
end
print(satellite and "All 4 GPS satellites are up and running." or "All 4 GPS hosts are running.")

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
