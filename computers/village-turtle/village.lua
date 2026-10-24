-- Village builder. Asks for a theme, then grows a village outward from where
-- it was started for as long as it survives: survey a plot, pick a building
-- that suits the ground there, clear and level it, build it, pave a street
-- to it, and move on to the next plot.
--
--   village             start a new village here (asks for a theme and size)
--   village resume      carry on after a reboot (startup.lua does this)
--   village here        you put me back on my home block: reset my position
--   village grow <r>    let a finished village grow out to radius r
--   village list        what each building needs, for stocking the chest
--   village status      what's been built so far
--   village cancel      forget the village
--
-- The turtle's starting block is the village centre ("home"). Put the SUPPLY
-- chest directly behind it and the SPOIL chest directly to its left. It takes
-- building blocks and fuel from the supply chest, and puts everything it digs
-- up into the spoil chest (and takes dirt and stone back out of it to fill in
-- foundations).
--
-- The village is a grid of 13x13 plots with 3-wide streets between them. The
-- middle plot is the plaza with a well; the rest are built ring by ring.
local nav = require("lib.nav")
local report = require("lib.report") -- status server; does nothing without a modem
local themes = require("village_themes")
local blueprints = require("village_blueprints")

local JOB_FILE = "/.village_job"

-- Layout
local PITCH = 18 -- plot centre to plot centre
local HALF = 6 -- plots reach 6 blocks either side of their centre; 5-wide streets fill the gap
local DEFAULT_RADIUS = 48 -- blocks from home; only plots whose centre is inside get built
local WELL_AT = { x = 0, z = 3 } -- the plaza well, in front of home
local SAMPLES = { -6, -3, 0, 3, 6 } -- survey grid across a plot (5 x 5 spots)

-- Terrain
local FLAT_RANGE = 2 -- up to this much height difference counts as flat
local SLOPE_RANGE = 5 -- up to this is a slope; anything rougher is skipped
local WATER_SHARE = 0.3 -- this share of water spots or more makes a shore (dock) or open water
local HILLTOP = 4 -- a site this much higher than home counts as a hilltop (towers like those)
local FILL_MAX = 8 -- deepest hole filled under a floor or road
local CUT_MAX = 8 -- deepest cutting dug for a road through higher ground

-- Inventory
local LOAD_SLOTS = 12 -- slots filled with building blocks per trip; the rest stay free for digging
local FILL_LOAD = 128 -- dirt/stone taken along for foundations
local FUEL_RESERVE = 300 -- refuel at home to at least this much plus the job ahead

-- If stairs (roofs, tower steps) come out facing the wrong way on your
-- server, flip this.
local STAIR_FLIP = false

-- With a wireless modem, share the building being worked on so a
-- blueprint-projector running 'projector village' can show it in the world.
local SHARE_PLAN = true
local PLAN_PROTOCOL = "village_plan"

-- With a wireless modem, ask a storage-computer for building blocks and
-- fuel. Its delivery chest must be this village's supply chest.
local USE_STORAGE = true
local STORAGE_PROTOCOL = "storage"
local STORAGE_RETRY = 60 -- seconds before looking for a storage computer again after not finding one
-- Fuel asked for when low, in this order, and how much of it.
local STORAGE_FUEL = { { "minecraft:coal", 64 }, { "minecraft:charcoal", 64 }, { "minecraft:coal_block", 8 } }

local FUEL = {}
for _, n in ipairs({ "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block", "minecraft:lava_bucket",
  "minecraft:blaze_rod", "minecraft:dried_kelp_block" }) do FUEL[n] = true end

-- Dug-up blocks that are good for filling in under floors.
local FILL = {}
for _, n in ipairs({ "minecraft:dirt", "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone",
  "minecraft:andesite", "minecraft:diorite", "minecraft:granite", "minecraft:tuff", "minecraft:deepslate",
  "minecraft:netherrack", "minecraft:sandstone", "minecraft:mud", "minecraft:clay" }) do FILL[n] = true end

local RETURN = { ["minecraft:bucket"] = true } -- goes back in the supply chest
local ITEM_BLOCK = { ["minecraft:water_bucket"] = "minecraft:water" } -- items that place a different block
local SAME = { -- already-there blocks that count as the one we'd place
  ["minecraft:dirt"] = { "minecraft:grass_block", "minecraft:podzol", "minecraft:coarse_dirt", "minecraft:rooted_dirt", "minecraft:mycelium" },
}
local STACK = { ["minecraft:water_bucket"] = 1, ["minecraft:lava_bucket"] = 1, ["minecraft:bucket"] = 16 }

-- Blocks a survey treats as somebody's build: plots containing them are left alone.
local BUILT = { "planks", "brick", "glass", "wool", "concrete", "door", "fence", "slab", "stairs", "_wall",
  "lantern", "torch", "chest", "barrel", "bed", "carpet", "polished", "smooth_", "cut_", "chiseled",
  "rail", "furnace", "crafting", "bookshelf", "lamp", "sign", "banner", "computercraft:", "hay_block", "composter" }
local TREE = { "leaves", "_log", "_wood", "mushroom_block", "vine", "bamboo", "cocoa" }
-- Small plants and snow layers: dug away so they don't count as the ground.
local PLANTS = { "minecraft:grass", "short_grass", "tall_grass", "fern", "flower", "tulip", "poppy", "dandelion",
  "orchid", "allium", "bluet", "daisy", "cornflower", "lily_of", "bush", "peony", "lilac", "sunflower", "sapling",
  "minecraft:snow", "seagrass" }
-- Things the turtle can just dig through on its way along a street.
local SOFT = { "leaves", "_log", "vine", "cactus", "bamboo", "sugar_cane", "pumpkin", "melon", "mushroom",
  "kelp", "azalea", "dripleaf" }

local job
local bld -- the building being worked on, worked out from job.cur

---------------------------------------------------------------- helpers

local function has(name, list)
  for _, p in ipairs(list) do
    if name:find(p, 1, true) then return true end
  end
  return false
end

local function isPlant(name)
  if name == "minecraft:grass_block" or name == "minecraft:snow_block" then return false end
  return has(name, PLANTS)
end

local function isSoft(name) return isPlant(name) or has(name, SOFT) end

local function save() nav.writeFile(JOB_FILE, job) end

local function plotKey(i, j) return i .. "," .. j end

---------------------------------------------------------------- coordinates

-- Village coordinates are local to home: x to the right, z forward, y up,
-- with home at 0,0,0. Local headings: 0 = forward (+z), 1 = right (+x),
-- 2 = back (-z), 3 = left (-x).
local DIRS = { [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 } }
local LDIR = { [0] = { x = 0, z = 1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = -1 }, [3] = { x = -1, z = 0 } }

local function toWorld(p)
  local o = job.origin
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  return o.x + p.x * r.x + p.z * f.x, o.y + p.y, o.z + p.x * r.z + p.z * f.z
end

local function here()
  local o, w = job.origin, nav.getPos()
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  local dx, dz = w.x - o.x, w.z - o.z
  return { x = dx * r.x + dz * r.z, y = w.y - o.y, z = dx * f.x + dz * f.z }
end

local function faceLocal(h) nav.face((job.origin.heading + h) % 4) end

local function headingOf(dx, dz)
  if dx > 0 then return 1 elseif dx < 0 then return 3 elseif dz > 0 then return 0 end
  return 2
end

local function goL(p) return nav.goTo(toWorld(p)) end

-- Rotate a blueprint offset r quarter turns clockwise (seen from above).
local function rotate(x, z, r)
  for _ = 1, r % 4 do x, z = z, -x end
  return x, z
end

---------------------------------------------------------------- the plot grid

-- Plots in the order they get built: the plaza, then ring by ring outward.
local function plotOrder()
  local list = {}
  local n = math.floor(job.radius / PITCH)
  for i = -n, n do
    for j = -n, n do
      local d = (i * i + j * j) * PITCH * PITCH
      if d <= job.radius * job.radius then list[#list + 1] = { i = i, j = j, d = d } end
    end
  end
  table.sort(list, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    if a.i ~= b.i then return a.i < b.i end
    return a.j < b.j
  end)
  return list
end

local function nextPlot()
  for _, p in ipairs(plotOrder()) do
    if not job.plots[plotKey(p.i, p.j)] then return p end
  end
end

-- Which way a building on plot i,j faces: towards the plaza.
local function towardsCentre(i, j)
  if math.abs(i) >= math.abs(j) then return i > 0 and 3 or 1 end
  return j > 0 and 2 or 0
end

---------------------------------------------------------------- streets

-- Street centre lines run between the plots, at x = a*PITCH + 9 and
-- z = b*PITCH + 9. Corner (a, b) is where two of them cross. A segment is the
-- stretch of street between two neighbouring corners: "h,a,b" runs along x
-- from corner a,b to a+1,b; "v,a,b" runs along z from a,b to a,b+1.
--
-- Streets are 5 wide: a 3-wide road with a curb on each side and a street
-- lamp on alternate curbs every 6 blocks. The main roads (the four lines
-- along the plaza's sides, running out to the edge of the village) are paved
-- all the way across in a finer block, with lamps on both sides.
local STREET = PITCH / 2
local LAMP_EVERY = 6

local function parseSeg(key)
  local kind, a, b = key:match("^(%a),(%-?%d+),(%-?%d+)$")
  return kind, tonumber(a), tonumber(b)
end

local function isMain(key)
  local kind, a, b = parseSeg(key)
  if kind == "h" then return b == -1 or b == 0 end
  return a == -1 or a == 0
end

-- Every cell of a segment, lane by lane (snaking), with its palette role
-- ("path", "edge" or "avenue") and whether a lamp post stands on it.
local function segCells(key)
  local kind, a, b = parseSeg(key)
  local main = isMain(key)
  local cells = {}
  for li, lane in ipairs({ -2, -1, 0, 1, 2 }) do
    local from, to, step = 0, PITCH, 1
    if li % 2 == 0 then from, to, step = PITCH, 0, -1 end
    for t = from, to, step do
      local junction = t <= 2 or t >= PITCH - 2 -- crossroads: road all the way across
      local curb = math.abs(lane) == 2 and not junction
      local c = { t = t, m = main and "avenue" or curb and "edge" or "path" }
      if curb and t % LAMP_EVERY == 0 then
        c.lamp = main or (t / LAMP_EVERY) % 2 == (lane > 0 and 1 or 0)
      end
      if kind == "h" then
        c.x, c.z = a * PITCH + STREET + t, b * PITCH + STREET + lane
      else
        c.x, c.z = a * PITCH + STREET + lane, b * PITCH + STREET + t
      end
      cells[#cells + 1] = c
    end
  end
  return cells
end

-- The street along the given side of plot i,j, then the shortest way along
-- the streets from there to the plaza. Already-paved stretches are left out.
local function routeToPlaza(i, j, side)
  local segs, corners = {}, nil
  if side == 2 then segs[1], corners = ("h,%d,%d"):format(i - 1, j - 1), { { i - 1, j - 1 }, { i, j - 1 } }
  elseif side == 0 then segs[1], corners = ("h,%d,%d"):format(i - 1, j), { { i - 1, j }, { i, j } }
  elseif side == 3 then segs[1], corners = ("v,%d,%d"):format(i - 1, j - 1), { { i - 1, j - 1 }, { i - 1, j } }
  else segs[1], corners = ("v,%d,%d"):format(i, j - 1), { { i, j - 1 }, { i, j } } end
  local function dist(c) return math.abs(2 * c[1] + 1) + math.abs(2 * c[2] + 1) end
  local c = dist(corners[1]) <= dist(corners[2]) and corners[1] or corners[2]
  local a, b = c[1], c[2]
  local ta, tb = math.max(-1, math.min(0, a)), math.max(-1, math.min(0, b))
  while a ~= ta do
    local na = a + (ta > a and 1 or -1)
    segs[#segs + 1] = ("h,%d,%d"):format(math.min(a, na), b)
    a = na
  end
  while b ~= tb do
    local nb = b + (tb > b and 1 or -1)
    segs[#segs + 1] = ("v,%d,%d"):format(a, math.min(b, nb))
    b = nb
  end
  local out = {}
  for _, s in ipairs(segs) do
    if not job.paved[s] then out[#out + 1] = s end
  end
  return out
end

local PLAZA_SEGS = { "h,-1,-1", "h,-1,0", "v,-1,-1", "v,0,-1" }

---------------------------------------------------------------- the current building

-- Work out the building for job.cur: every block in build order in village
-- coordinates (y relative to the plot's floor level), what it needs, and the
-- box it takes up.
local function building()
  local c = job.cur
  local key = ("%d,%d,%s,%d,%d"):format(c.i, c.j, c.bp, c.rot, c.base)
  if bld and bld.key == key then return bld end
  local theme = themes[job.theme]
  local b = blueprints.make(c.bp, theme)
  local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
  for _, k in ipairs(b.blocks) do
    x0, x1, z0, z1 = math.min(x0, k.x), math.max(x1, k.x), math.min(z0, k.z), math.max(z1, k.z)
  end
  local mx, mz = math.floor((x0 + x1) / 2), math.floor((z0 + z1) / 2)
  local function tf(x, z)
    local rx, rz = rotate(x - mx, z - mz, c.rot)
    return c.ax + rx, c.az + rz
  end
  local steps, needs, top = {}, {}, 0
  for _, k in ipairs(b.blocks) do
    local item = theme.palette[k.m]
    if item then
      local x, z = tf(k.x, k.z)
      local f = k.f and (k.f + c.rot) % 4
      if f and STAIR_FLIP and k.m:find("tair", 1, true) then f = (f + 2) % 4 end
      steps[#steps + 1] = { x = x, y = k.y, z = z, item = item, f = f, fwd = k.fwd }
      needs[item] = (needs[item] or 0) + 1
      top = math.max(top, k.y)
    end
  end
  local ax0, az0 = tf(x0, z0)
  local ax1, az1 = tf(x1, z1)
  local box = { x0 = math.min(ax0, ax1), x1 = math.max(ax0, ax1), z0 = math.min(az0, az1), z1 = math.max(az0, az1) }
  -- clearing box: the building plus a margin, kept inside the plot (the
  -- streets and their lamps are left alone)
  local m, cx, cz = b.margin, c.i * PITCH, c.j * PITCH
  local clear = {
    x0 = math.max(box.x0 - m, cx - HALF), x1 = math.min(box.x1 + m, cx + HALF),
    z0 = math.max(box.z0 - m, cz - HALF), z1 = math.min(box.z1 + m, cz + HALF),
  }
  -- the path out of the front door to the plot's edge
  local front = (2 + c.rot) % 4
  local door = {}
  if b.entrance then
    local x, z = tf(b.entrance, -1)
    while math.abs(x - cx) <= HALF and math.abs(z - cz) <= HALF do
      door[#door + 1] = { x = x, z = z }
      x, z = x + LDIR[front].x, z + LDIR[front].z
    end
  end
  bld = { key = key, steps = steps, needs = needs, box = box, clear = clear, top = top,
    front = front, door = door, noFoundation = b.noFoundation }
  return bld
end

local function inBox(b, p) return p.x >= b.x0 and p.x <= b.x1 and p.z >= b.z0 and p.z <= b.z1 end

-- Inside the area being worked on, at or above its floor: it's safe to move
-- straight there, digging if needed.
local function inWork(p)
  local c = job.cur
  return c and c.base and bld and inBox(bld.clear, p) and p.y >= c.base
end

---------------------------------------------------------------- inventory

local function fuelLevel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

local function count(name)
  local n = 0
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and it.name == name then n = n + it.count end
  end
  return n
end

local function countFill()
  local n = 0
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and FILL[it.name] then n = n + it.count end
  end
  return n
end

local function emptySlots()
  local n = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then n = n + 1 end
  end
  return n
end

local function selectItem(match)
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and match(it.name) then
      turtle.select(slot)
      return true
    end
  end
  return false
end

local function selectName(name) return selectItem(function(n) return n == name end) end
local function selectFill() return selectItem(function(n) return FILL[n] end) end

local function refuelFromInventory(target)
  for slot = 1, 16 do
    if fuelLevel() >= target then break end
    local it = turtle.getItemDetail(slot)
    if it and FUEL[it.name] then
      turtle.select(slot)
      while fuelLevel() < target and turtle.refuel(1) do end
    end
  end
  turtle.select(1)
end

local function stackSize(name)
  if STACK[name] then return STACK[name] end
  if name:find("_bed", 1, true) then return 1 end
  return 64
end

---------------------------------------------------------------- waiting for the player

-- Wait until ok() is true, re-checking when the inventory changes and every
-- 10 seconds (chests don't send events). With allowSkip, pressing S gives up
-- and returns false.
local function waitUntil(ok, lines, state, allowSkip)
  if ok() then return true end
  for _, l in ipairs(lines) do print(l) end
  if allowSkip then print("Press S to skip this and pick something else.") end
  report.set("waiting", state)
  local timer = os.startTimer(10)
  while true do
    local e, a = os.pullEvent()
    if e == "timer" and a == timer then
      if ok() then return true end
      timer = os.startTimer(10)
    elseif e == "turtle_inventory" then
      if ok() then return true end
    elseif e == "char" and allowSkip and (a == "s" or a == "S") then
      return false
    end
  end
end

local function waitForFuel()
  waitUntil(function()
    refuelFromInventory(FUEL_RESERVE)
    return fuelLevel() > 0
  end, { "Out of fuel here. Put coal or charcoal in my inventory." }, "out of fuel")
end

---------------------------------------------------------------- moving

local function solidBelow() return turtle.detectDown() end

local function fluidAt(inspect)
  local ok, data = inspect()
  return ok and (data.name == "minecraft:water" or data.name == "minecraft:lava" or data.name:find("water", 1, true) ~= nil)
end

local function cruiseHeight() return job.topY + 2 end

-- Long-distance travel: straight up, across without digging sideways (go
-- over whatever is in the way), then straight down onto p. With p.y nil, land
-- on whatever is there (stopping at water). opts.low skips the climb, for
-- hopping between survey spots on open ground.
local function fly(p, opts)
  opts = opts or {}
  local cur = here()
  if cur.x == p.x and cur.z == p.z and p.y then return goL(p) end
  local cruise = opts.low and cur.y or math.max(cur.y, p.y or cur.y, cruiseHeight())
  while here().y < cruise do
    local ok, err = nav.up()
    if not ok then return false, err end
  end
  local climbs = 0
  while true do
    cur = here()
    if cur.x == p.x and cur.z == p.z then break end
    faceLocal(cur.x ~= p.x and headingOf(p.x - cur.x, 0) or headingOf(0, p.z - cur.z))
    if turtle.detect() then
      climbs = climbs + 1
      if climbs > 64 then return false, "blocked" end
      local ok, err = nav.up()
      if not ok then return false, err end
    else
      local ok, err = nav.forward()
      if not ok then return false, err end
    end
  end
  if p.y then return goL(p) end
  for _ = 1, 64 do
    local ok, data = turtle.inspectDown()
    if ok and isPlant(data.name) then
      turtle.digDown()
    elseif solidBelow() or fluidAt(turtle.inspectDown) then
      return true
    else
      local moved, err = nav.down()
      if not moved then return false, err end
    end
  end
  return true
end

local function travel(p, opts)
  if p.y and inWork(here()) and inWork(p) then return goL(p) end
  return fly(p, opts)
end

-- Get to p, waiting for fuel or for the way to clear if need be. Gives up
-- (returns false) only when right next to p and p itself can't be cleared.
local function reach(p, opts)
  local tries = 0
  while true do
    local ok, err = travel(p, opts)
    if ok then return true end
    local h = here()
    if err ~= "nofuel" and math.abs(h.x - p.x) + math.abs(h.y - (p.y or h.y)) + math.abs(h.z - p.z) <= 1 then
      return false, err
    end
    tries = tries + 1
    if err == "nofuel" then
      waitForFuel()
    else
      local w = nav.getPos()
      local msg = ("Stuck at %d,%d,%d (%s)"):format(w.x, w.y, w.z, tostring(err))
      print(msg .. ". Clear the way; retrying.")
      report.set("stuck", msg)
      sleep(math.min(60, 5 * tries))
      if tries > 3 then return false, err end
    end
  end
end

local function goHome()
  reach({ x = 0, y = 0, z = 0 })
  faceLocal(0)
end

local function homeDistance()
  local p = here()
  return math.abs(p.x) + math.abs(p.z) + math.abs(cruiseHeight() - p.y) + cruiseHeight() + 20
end

---------------------------------------------------------------- position checks

local function gpsPos()
  local x, y, z = gps.locate(2)
  if not x then return nil end
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
end

-- With GPS, compare where the turtle thinks it is with where it is. If it's
-- been moved, re-check position and facing and head home before carrying on.
local function checkPosition()
  if not job.gps then return end
  local g = gpsPos()
  if not g then return end
  local p = nav.getPos()
  if g.x ~= p.x or g.y ~= p.y or g.z ~= p.z then
    print(("Position was off: thought %d,%d,%d, GPS says %d,%d,%d. Correcting."):format(p.x, p.y, p.z, g.x, g.y, g.z))
    nav.init()
    goHome()
  end
end

---------------------------------------------------------------- the chests at home

local function faceSupply() faceLocal(2) end -- behind home
local function faceSpoil() faceLocal(3) end -- left of home

local function frontChest()
  if not peripheral then return nil end
  local c = peripheral.wrap("front")
  if c and c.list then return c end
end

local function addChest(t)
  local c = frontChest()
  if not c then return false end
  for _, it in pairs(c.list()) do t[it.name] = (t[it.name] or 0) + it.count end
  return true
end

-- Everything at home: both chests and the turtle's own inventory.
local function stockAtHome()
  local t = {}
  faceSpoil()
  addChest(t)
  faceSupply()
  local supply = addChest(t)
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it then t[it.name] = (t[it.name] or 0) + it.count end
  end
  faceLocal(0)
  return t, supply
end

local function freeSlotFor(name)
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and it.name == name and turtle.getItemSpace(slot) > 0 then return slot end
  end
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return slot end
  end
end

-- Without inventory peripherals: suck stacks one by one, keep the wanted
-- ones and put the rest back.
local function suckSorting(match, want)
  local held = {}
  local got = 0
  while got < want and emptySlots() > 1 do
    local slot = freeSlotFor("")
    turtle.select(slot)
    if not turtle.suck() then break end
    local it = turtle.getItemDetail(slot)
    if it and match(it.name) then got = got + it.count else held[#held + 1] = slot end
  end
  for _, s in ipairs(held) do
    turtle.select(s)
    turtle.drop()
  end
  turtle.select(1)
end

-- Take up to `want` items matching match() from the chest in front.
-- turtle.suck takes the chest's first stack, so the wanted stack is moved to
-- the front of the chest first.
local function takeFront(match, want, current)
  local c = frontChest()
  if not c then return end
  local self = peripheral.getName(c)
  for _ = 1, 40 do
    local have = current()
    if have >= want or emptySlots() == 0 then break end
    local items = c.list()
    local from, first
    for slot, it in pairs(items) do
      if not first or slot < first then first = slot end
      if match(it.name) and (not from or slot < from) then from = slot end
    end
    if not from then break end
    if from ~= first then
      local moved = true
      if items[1] then
        local empty
        for s = 2, c.size() do
          if not items[s] then empty = s break end
        end
        local ok, n = false, 0
        if empty then ok, n = pcall(c.pushItems, self, 1, 64, empty) end
        moved = ok and n and n > 0
      end
      if moved then
        local ok, n = pcall(c.pushItems, self, from, 64, 1)
        moved = ok and n and n > 0
      end
      if not moved then return suckSorting(match, want - have) end
    end
    turtle.select(freeSlotFor(items[from].name) or 1)
    if not turtle.suck(math.min(64, want - have)) then break end
  end
  turtle.select(1)
end

-- Fetch from the spoil chest first (reuse what was dug up), then the supply.
local function fetch(match, want, current)
  faceSpoil()
  takeFront(match, want, current)
  if current() < want then
    faceSupply()
    takeFront(match, want, current)
  end
end

-- Put away everything not in keep (name -> count). Fuel stays; buckets go
-- back to the supply chest. If the spoil chest is full, junk is thrown away.
local function dump(keep, keepFill)
  local kept = {}
  local fillKept = 0
  local warned = false
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it then
      local drop = 0
      if FUEL[it.name] then
        drop = 0
      elseif RETURN[it.name] then
        drop = it.count
      elseif keep[it.name] then
        local k = math.max(0, math.min(it.count, keep[it.name] - (kept[it.name] or 0)))
        kept[it.name] = (kept[it.name] or 0) + k
        drop = it.count - k
      elseif FILL[it.name] then
        local k = math.max(0, math.min(it.count, keepFill - fillKept))
        fillKept = fillKept + k
        drop = it.count - k
      else
        drop = it.count
      end
      if drop > 0 then
        turtle.select(slot)
        if RETURN[it.name] then faceSupply() else faceSpoil() end
        if not turtle.drop(drop) then
          if not warned then
            print("Spoil chest is full or missing; throwing the extra away.")
            warned = true
          end
          turtle.dropUp(drop)
        end
      end
    end
  end
  turtle.select(1)
end

-- Defined with the storage system further down (it needs the chest helpers).
local orderFromStorage

local function fuelItems()
  local n = 0
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it and FUEL[it.name] then n = n + it.count end
  end
  return n
end

-- At home: top up to target from the chests, and wait for the player if
-- there isn't even enough to carry on.
local function ensureFuel(target)
  local limit = turtle.getFuelLimit()
  if limit ~= "unlimited" then target = math.min(target, limit) end
  if fuelLevel() >= target then return end
  local function topUp()
    refuelFromInventory(target)
    if fuelLevel() < target then
      fetch(function(n) return FUEL[n] end, 64, fuelItems)
      refuelFromInventory(target)
    end
    if fuelLevel() < target then
      -- whichever fuel the storage system has: coal first
      for _, f in ipairs(STORAGE_FUEL) do
        local r = orderFromStorage({ [f[1]] = f[2] })
        if not r or r.enough or (r.ready[f[1]] or 0) > 0 then break end
      end
      fetch(function(n) return FUEL[n] end, 64, fuelItems)
      refuelFromInventory(target)
    end
    faceLocal(0)
  end
  topUp()
  local need = math.min(target, FUEL_RESERVE + homeDistance())
  if fuelLevel() < need then
    waitUntil(function()
      topUp()
      return fuelLevel() >= need
    end, { ("Need fuel: have %d, want %d."):format(fuelLevel(), need), "Put coal in the supply chest or in me." },
    "needs fuel")
  end
end

---------------------------------------------------------------- shopping lists

local function shortName(item) return (item:gsub("^minecraft:", "")) end

-- What's still missing for needs (name -> count), given stock at home.
local function shortfall(needs, stock)
  local missing = {}
  for item, n in pairs(needs) do
    local have = stock[item] or 0
    if have < n then missing[#missing + 1] = { item = item, n = n - have } end
  end
  table.sort(missing, function(a, b) return a.n > b.n end)
  return missing
end

local function missingLines(title, missing)
  local lines = { title }
  for k, m in ipairs(missing) do
    if k > 8 then
      lines[#lines + 1] = ("  ...and %d more"):format(#missing - 8)
      break
    end
    lines[#lines + 1] = ("  %4d %s"):format(m.n, shortName(m.item))
  end
  return lines
end

local function missingText(missing)
  local parts = {}
  for k, m in ipairs(missing) do
    if k > 3 then break end
    parts[#parts + 1] = m.n .. " " .. shortName(m.item)
  end
  return "needs " .. table.concat(parts, ", ") .. (#missing > 3 and ", ..." or "")
end

---------------------------------------------------------------- survey

local function classify(name)
  if name:find("lava", 1, true) then return "lava" end
  if name:find("water", 1, true) then return "water" end
  if has(name, BUILT) then return "built" end
  if has(name, TREE) then return "tree" end
  return "ground"
end

-- Drop onto one survey spot and note what's there and how high.
local function surveySpot(x, z, first)
  reach({ x = x, z = z }, { low = not first })
  local ok, data = turtle.inspectDown()
  local y = here().y - 1
  if not ok then return { x = x, z = z, y = y, kind = "pit" } end
  return { x = x, z = z, y = y, kind = classify(data.name) }
end

local function median(list)
  table.sort(list)
  return list[math.floor((#list + 1) / 2)]
end

-- Decide what kind of site a plot is from its survey.
local function analyse(samples, cx, cz)
  local land, waterY, trees, top = {}, {}, 0, -math.huge
  local lx, lz = 0, 0
  local why
  for _, s in ipairs(samples) do
    top = math.max(top, s.y)
    if s.kind == "built" then why = "something's already built there" end
    if s.kind == "lava" then why = "lava" end
    if s.kind == "pit" then why = "a deep hole" end
  end
  if why then return { class = "skip", why = why, top = top, trees = 0 } end
  for _, s in ipairs(samples) do
    if s.kind == "water" then
      waterY[#waterY + 1] = s.y
    elseif s.kind == "tree" then
      trees = trees + 1
    else
      land[#land + 1] = s.y
      lx, lz = lx + s.x - cx, lz + s.z - cz
    end
  end
  local site = { top = top, trees = trees, water = #waterY, land = #land }
  if #waterY >= #samples * WATER_SHARE then
    if #land < 3 then site.class, site.why = "skip", "open water" return site end
    site.class = "shore"
    site.base = median(waterY) + 1
    -- the dock's root goes on the side where the land is
    if math.abs(lx) >= math.abs(lz) then site.landDir = lx > 0 and 1 or 3 else site.landDir = lz > 0 and 0 or 2 end
    return site
  end
  if #land < 4 then site.class, site.why = "skip", "too many trees to see the ground" return site end
  table.sort(land)
  -- ignore the single highest and lowest spot (a boulder, a dip)
  local lo, hi = land[1], land[#land]
  if #land >= 8 then lo, hi = land[2], land[#land - 1] end
  site.range = hi - lo
  site.base = median(land)
  if site.range <= FLAT_RANGE then site.class = "flat"
  elseif site.range <= SLOPE_RANGE then site.class = "slope"
  else site.class, site.why = "skip", ("too steep (%d blocks)"):format(site.range) end
  site.hilltop = site.base >= HILLTOP
  return site
end

---------------------------------------------------------------- choosing

local function builtCounts()
  local counts, total = {}, 0
  for _, b in ipairs(job.built) do
    if b.bp ~= "well" then
      counts[b.bp] = (counts[b.bp] or 0) + 1
      total = total + 1
    end
  end
  return counts, total
end

-- Pick a building that suits the site, weighted by how well it suits it and
-- kept in proportion with the rest of the village.
local function pickBuilding(c)
  local theme = themes[job.theme]
  local counts, total = builtCounts()
  local cands, sum = {}, 0
  for _, name in ipairs(theme.buildings) do
    local def = blueprints.catalogue[name]
    local w = def.suits[c.site.class] or 0
    if name == "tower" and c.site.hilltop then w = w + 8 end
    if name == "cottage" and c.site.trees >= 6 then w = w + 3 end -- a cabin in the woods
    if def.limit and (counts[name] or 0) >= def.limit(total, counts) then w = 0 end
    if c.rejected[name] then w = 0 end
    if w > 0 then
      cands[#cands + 1] = { name = name, w = w }
      sum = sum + w
    end
  end
  if sum == 0 then return nil end
  math.randomseed(job.seed + c.i * 7919 + c.j * 104729 + #job.built * 31)
  local r = math.random() * sum
  for _, cand in ipairs(cands) do
    r = r - cand.w
    if r <= 0 then return cand.name end
  end
  return cands[#cands].name
end

local function niceName(bp) return themes[job.theme].names[bp] or bp end

---------------------------------------------------------------- sharing with a projector

local function openWireless()
  if rednet.isOpen() then return true end
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then return false end
  rednet.open(peripheral.getName(modem))
  return true
end

local function planModem() return SHARE_PLAN and openWireless() end

-- Once a building is chosen its place is known (job.cur has bp, rot, ax, base).
local function hasPlan()
  local c = job and job.cur
  return c and c.bp and c.rot and c.ax and c.base and true or false
end

-- The whole building in world coordinates, one { x, y, z, block } per block.
-- Without GPS they're only counted from where the village started.
local function planMessage()
  local c, b = job.cur, building()
  local blocks = {}
  for i, st in ipairs(b.steps) do
    local x, y, z = toWorld({ x = st.x, y = c.base + st.y, z = st.z })
    blocks[i] = { x, y, z, ITEM_BLOCK[st.item] or st.item }
  end
  return { type = "plan", key = b.key, name = ("%s, plot %d,%d"):format(niceName(c.bp), c.i, c.j),
    world = job.gps, blocks = blocks }
end

local function progressMessage()
  local c, b = job.cur, building()
  local msg = { type = "progress", key = b.key, stage = c.stage }
  if c.stage == "build" then
    local st = b.steps[math.min(c.step + 1, #b.steps)]
    if st then
      local _, y = toWorld({ x = 0, y = c.base + st.y, z = 0 })
      msg.y = y
    end
    msg.step, msg.total = c.step, #b.steps
  end
  return msg
end

-- full: send the whole building as well as how far along it is.
local function sharePlan(full)
  if not hasPlan() or not planModem() then return end
  if full then rednet.broadcast(planMessage(), PLAN_PROTOCOL) end
  rednet.broadcast(progressMessage(), PLAN_PROTOCOL)
end

-- A projector that starts up asks for the building; answer whenever asked.
local function planServer()
  while true do
    if planModem() then
      local _, msg = rednet.receive(PLAN_PROTOCOL, 60)
      if type(msg) == "table" and msg.type == "request" then sharePlan(true) end
    else
      sleep(60)
    end
  end
end

---------------------------------------------------------------- the storage system

local storageId -- the storage computer, once found
local noStorageUntil = 0 -- don't look again before this (os.clock)

-- Say what the storage system did, but not the same thing over and over
-- (orders repeat every 10 seconds while waiting).
local lastNotes = {}
local function storageNote(text)
  if lastNotes[text] and os.clock() - lastNotes[text] < 120 then return end
  lastNotes[text] = os.clock()
  print(text)
end

-- Send msg to the storage computer and wait for its reply. nil when there's
-- no storage computer in range (or USE_STORAGE is off).
local function askStorage(msg)
  if not USE_STORAGE or os.clock() < noStorageUntil then return nil end
  if not openWireless() then
    storageNote("I have no wireless modem, so I can't ask the storage system for blocks.")
    noStorageUntil = os.clock() + STORAGE_RETRY
    return nil
  end
  if not storageId then
    storageId = rednet.lookup(STORAGE_PROTOCOL)
    if not storageId then
      storageNote("No storage system answered. It needs a wireless or ender modem, to be running")
      storageNote("'storage', and to be in range (wireless modems reach about 64 blocks).")
      noStorageUntil = os.clock() + STORAGE_RETRY
      return nil
    end
    print(("Found the storage system (computer #%d)."):format(storageId))
  end
  rednet.send(storageId, msg, STORAGE_PROTOCOL)
  while true do
    local id, reply = rednet.receive(STORAGE_PROTOCOL, 10)
    if not id then
      storageNote(("The storage system (computer #%d) stopped answering."):format(storageId))
      storageId = nil -- gone quiet: look it up again next time
      return nil
    end
    if id == storageId and type(reply) == "table" and reply.re == msg.type then return reply end
  end
end

-- How much of each item the storage system has (name -> count), or nil.
local function storageCounts(names)
  if #names == 0 then return nil end
  local r = askStorage({ type = "count", items = names })
  return r and r.counts
end

-- At home: have the storage system fill the supply chest with what's needed
-- (name -> count) beyond what's on board and in the spoil chest. It counts
-- what's already in the supply chest itself and holds it there for us;
-- anything else in that chest goes back into storage.
orderFromStorage = function(needs)
  if not USE_STORAGE then return end
  local have = {}
  faceSpoil()
  addChest(have)
  faceLocal(0)
  for slot = 1, 16 do
    local it = turtle.getItemDetail(slot)
    if it then have[it.name] = (have[it.name] or 0) + it.count end
  end
  local order, any = {}, false
  for item, n in pairs(needs) do
    local short = n - (have[item] or 0)
    if short > 0 then order[item], any = short, true end
  end
  if not any then return { enough = true } end
  local r = askStorage({ type = "deliver", items = order })
  if not r then return nil end
  local total = 0
  for _, n in pairs(r.sent or {}) do total = total + n end
  if r.error then
    storageNote("The storage system couldn't move items: " .. tostring(r.error))
    storageNote("Run 'storage test' on it to check its delivery chest.")
  end
  if r.to == "output" then
    storageNote("The storage system has no delivery chest, so it sends to its output chest. Run 'storage setup' on it and pick my supply chest.")
  elseif total > 0 then
    storageNote(("The storage system sent %d items to the supply chest."):format(total))
  end
  for item, n in pairs(order) do
    local ready = r.ready and r.ready[item] or 0
    if ready < n and r.stock and r.stock[item] == 0 then
      storageNote(("The storage system has no %s (left)."):format(shortName(item)))
    elseif ready < n then
      storageNote(("Only part of the %s fitted in my supply chest."):format(shortName(item)))
    end
  end
  r.ready = r.ready or {}
  return r
end

local function skipPlot(why)
  local c = job.cur
  print(("Skipping plot %d,%d: %s."):format(c.i, c.j, why))
  report.log(("skipped plot %d,%d: %s"):format(c.i, c.j, why))
  job.plots[plotKey(c.i, c.j)] = { status = "skipped", why = why }
  job.cur, bld = nil, nil
  save()
end

-- The blocks one street cell needs: its surface, plus the lamp post on it.
local function cellItems(cell, add)
  local pal = themes[job.theme].palette
  add(pal[cell.m or "path"], 1)
  if cell.lamp then
    add(pal.fence, 2)
    add(pal.light, 1)
  end
end

-- Blocks for this building's door path and streets. Stairs on slopes depend
-- on the ground, so allow a few per stretch of street.
local function streetNeeds(c, into)
  local pal = themes[job.theme].palette
  local function add(item, n) into[item] = (into[item] or 0) + n end
  for _ = 1, #building().door do add(pal.path, 1) end
  for _, seg in ipairs(c.segs) do
    for _, cell in ipairs(segCells(seg)) do cellItems(cell, add) end
    add(pal.roadStair, 6)
  end
  return into
end

local function streetCells(c)
  local n = #building().door
  for _, seg in ipairs(c.segs) do n = n + #segCells(seg) end
  return n
end

---------------------------------------------------------------- stages

local function status(state, detail)
  report.set(state, detail, job.gps and { pos = nav.getPos() } or nil)
end

local function doSurvey(c)
  local cx, cz = c.i * PITCH, c.j * PITCH
  status("surveying", ("plot %d,%d"):format(c.i, c.j))
  local spots = {}
  for zi, dz in ipairs(SAMPLES) do
    for k = 1, #SAMPLES do
      local dx = zi % 2 == 1 and SAMPLES[k] or SAMPLES[#SAMPLES + 1 - k]
      spots[#spots + 1] = { x = cx + dx, z = cz + dz }
    end
  end
  while #c.samples < #spots do
    local s = spots[#c.samples + 1]
    c.samples[#c.samples + 1] = surveySpot(s.x, s.z, #c.samples == 0)
    save()
  end
  local site = analyse(c.samples, cx, cz)
  job.topY = math.max(job.topY, site.top + 1)
  if c.i == 0 and c.j == 0 then
    site.class, site.base = "plaza", -1
  end
  c.site = site
  if site.class == "skip" then return skipPlot(site.why) end
  c.stage = "choose"
  save()
end

local function doChoose(c)
  local site = c.site
  if site.class == "plaza" then
    c.bp, c.rot, c.ax, c.az = "well", 0, WELL_AT.x, WELL_AT.z
  else
    c.bp = pickBuilding(c)
    if not c.bp then return skipPlot("nothing left that suits a " .. site.class .. " site") end
    local face = site.class == "shore" and site.landDir or towardsCentre(c.i, c.j)
    c.rot = (face - 2) % 4
    c.ax, c.az = c.i * PITCH, c.j * PITCH
  end
  c.base = site.base
  bld = nil
  local b = building()
  sharePlan(true)
  c.segs = site.class == "plaza" and {} or routeToPlaza(c.i, c.j, b.front)
  if site.class == "plaza" then
    for _, s in ipairs(PLAZA_SEGS) do
      if not job.paved[s] then c.segs[#c.segs + 1] = s end
    end
  end
  local what = site.class == "slope" and ("sloped (%d blocks)"):format(site.range)
    or site.class == "shore" and "on the shore" or site.class
  print(("Plot %d,%d is %s%s: building a %s."):format(c.i, c.j, what, site.hilltop and ", a hilltop" or "",
    niceName(c.bp)))

  -- Everything for the building and its streets must be at home before starting.
  local needs = {}
  for item, n in pairs(b.needs) do needs[item] = n end
  streetNeeds(c, needs)
  goHome()
  status("checking", "materials for a " .. niceName(c.bp))
  local missing
  local function check()
    local stock, supply = stockAtHome()
    missing = shortfall(needs, stock)
    -- what the storage system holds counts too: it's sent over as the build needs it
    local names = {}
    for _, m in ipairs(missing) do names[#names + 1] = m.item end
    local counts = storageCounts(names)
    if counts then
      for item, n in pairs(counts) do stock[item] = (stock[item] or 0) + n end
      missing = shortfall(needs, stock)
    end
    if not supply then table.insert(missing, 1, { item = "supply chest (behind me)", n = 1 }) end
    return #missing == 0
  end
  local ready = true
  if not check() then
    ready = waitUntil(check, missingLines(("A %s still needs:"):format(niceName(c.bp)), missing),
      missingText(missing), c.bp ~= "well")
  end
  if not ready then
    print("Skipped the " .. niceName(c.bp) .. ".")
    c.rejected[c.bp] = true
    c.bp = nil
    save()
    return
  end
  local cl = b.clear
  local area = (cl.x1 - cl.x0 + 1) * (cl.z1 - cl.z0 + 1)
  local clearH = math.max(0, site.top + 1 - c.base)
  ensureFuel(FUEL_RESERVE + #b.steps * 4 + area * math.ceil(clearH / 3) * 2 + streetCells(c) * 3 + homeDistance() * 6)
  c.clearTop = c.base + clearH
  c.stage, c.step = "clear", 0
  sharePlan(false)
  report.log(("building a %s at plot %d,%d"):format(niceName(c.bp), c.i, c.j))
  save()
end

-- Clearing works top down in 3-high layers, snaking, like excavate.
local function clearBox()
  local cl, c = building().clear, job.cur
  return { x0 = cl.x0, x1 = cl.x1, z0 = cl.z0, z1 = cl.z1, y0 = c.base + 1, y1 = c.clearTop }
end

local function boxCells(b)
  if b.y1 < b.y0 then return 0 end
  return math.ceil((b.y1 - b.y0 + 1) / 3) * (b.x1 - b.x0 + 1) * (b.z1 - b.z0 + 1)
end

local function boxCell(b, i)
  local w, l = b.x1 - b.x0 + 1, b.z1 - b.z0 + 1
  local per = w * l
  local layer, j = math.floor(i / per), i % per
  if layer % 2 == 1 then j = per - 1 - j end
  local row, col = math.floor(j / w), j % w
  if row % 2 == 1 then col = w - 1 - col end
  local y = math.min(math.max(b.y1 - 1 - layer * 3, b.y0 + 1), b.y1)
  if b.y1 == b.y0 then y = b.y0 end
  return { x = b.x0 + col, y = y, z = b.z0 + row }
end

-- Take only what's needed for the next stretch of the build: LOAD_SLOTS
-- stacks' worth of upcoming blocks.
local function loadPlan(from)
  local b = building()
  local steps = b.steps
  local want, slots, floors = {}, 0, false
  -- while there's floor still to lay, two of the slots carry fill
  local budget = LOAD_SLOTS
  if not b.noFoundation and steps[from] and steps[from].y <= 0 then budget = LOAD_SLOTS - math.ceil(FILL_LOAD / 64) end
  for k = from, #steps do
    local s = steps[k]
    local n = want[s.item] or 0
    if n % stackSize(s.item) == 0 then
      if slots >= budget then break end
      slots = slots + 1
    end
    want[s.item] = n + 1
    if s.y == 0 then floors = true end
  end
  return want, floors and not b.noFoundation and FILL_LOAD or 0
end

-- Go home, put away the junk and load up for the next stretch of work.
local function restock(want, fillWant, why)
  print("Going home: " .. why)
  status("restocking", why)
  goHome()
  dump(want, fillWant)
  ensureFuel(FUEL_RESERVE + 2 * homeDistance()) -- before the slots fill up
  if next(want) then orderFromStorage(want) end
  for item, n in pairs(want) do
    if count(item) < n then fetch(function(x) return x == item end, n, function() return count(item) end) end
  end
  if fillWant > 0 and countFill() < fillWant then
    fetch(function(x) return FILL[x] end, fillWant, countFill)
  end
  faceLocal(0)
end

local function housekeeping()
  if emptySlots() <= 1 then restock({}, 0, "inventory full") end
  if fuelLevel() < homeDistance() then restock({}, 0, "low on fuel") end
end

local function doClear(c)
  local box = clearBox()
  local size = boxCells(box)
  while c.step < size do
    local p = boxCell(box, c.step)
    if reach(p) then
      if p.y + 1 <= box.y1 then nav.digUp() end
      if p.y - 1 >= box.y0 then nav.digDown() end
    end
    c.step = c.step + 1
    save()
    if c.step % 25 == 0 then
      checkPosition()
      status("clearing", ("%s at %d,%d: %d%%"):format(niceName(c.bp), c.i, c.j, math.floor(c.step / size * 100)))
    end
    housekeeping()
  end
  c.stage, c.step = "build", 0
  save()
end

local function matches(name, block)
  if name == block then return true end
  for _, n in ipairs(SAME[block] or {}) do
    if n == name then return true end
  end
  return false
end

-- Fill any gap under a floor (or road) block at height level: drop down to
-- solid ground, then fill back up to just under it. Returns false if out of fill.
local function fillUnder(level)
  local depth = 0
  while depth < FILL_MAX and not solidBelow() do
    if not nav.down() then break end
    depth = depth + 1
  end
  local ok = true
  while depth > 0 do
    nav.up()
    depth = depth - 1
    if here().y - 1 < level then
      if selectFill() then turtle.placeDown() else ok = false end
    end
  end
  turtle.select(1)
  return ok
end

-- Place one block of the building. Returns "ok", "skip" (couldn't get there),
-- "missing" (out of that block) or "nofill".
local function placeStep(s)
  local c = job.cur
  local block = ITEM_BLOCK[s.item] or s.item
  if s.fwd then
    -- doors: from the cell inside, facing out through the doorway
    if count(s.item) == 0 then return "missing" end
    local d = LDIR[s.f]
    if not reach({ x = s.x - d.x, y = c.base + s.y, z = s.z - d.z }) then return "skip" end
    faceLocal(s.f)
    local ok, data = turtle.inspect()
    if ok and data.name == block then return "ok" end
    if turtle.detect() then turtle.dig() end
    selectName(s.item)
    turtle.place()
    turtle.select(1)
    return "ok"
  end
  -- already there? (after a reboot the last block may have been placed)
  local stand = { x = s.x, y = c.base + s.y + 1, z = s.z }
  local p = here()
  if p.x == stand.x and p.y == stand.y and p.z == stand.z then
    local ok, data = turtle.inspectDown()
    if ok and matches(data.name, block) then return "ok" end
  end
  if count(s.item) == 0 then return "missing" end
  if not reach(stand) then return "skip" end
  if s.y == 0 and not building().noFoundation and not solidBelow() then
    if not fillUnder(c.base) then return "nofill" end
  end
  local ok, data = turtle.inspectDown()
  if ok and matches(data.name, block) then return "ok" end
  if turtle.detectDown() then
    local dug = nav.digDown()
    if not dug then return "skip" end
  end
  if s.f then faceLocal(s.f) end
  selectName(s.item)
  if not turtle.placeDown() then
    turtle.attackDown()
    sleep(0.5)
    turtle.placeDown()
  end
  turtle.select(1)
  return "ok"
end

local function doBuild(c)
  local b = building()
  local steps = b.steps
  sharePlan(false)
  while c.step < #steps do
    local s = steps[c.step + 1]
    local r = placeStep(s)
    if r == "missing" or r == "nofill" then
      local want, fillWant = loadPlan(c.step + 1)
      restock(want, fillWant, r == "nofill" and "need dirt or stone for the foundation" or "loading blocks")
      -- still nothing? wait for the player to bring some
      if r == "missing" and count(s.item) == 0 then
        waitUntil(function()
          orderFromStorage({ [s.item] = want[s.item] or 1 })
          fetch(function(x) return x == s.item end, want[s.item] or 1, function() return count(s.item) end)
          faceLocal(0)
          return count(s.item) > 0
        end, { "Out of " .. shortName(s.item) .. ". Put some in the supply chest." }, "needs " .. shortName(s.item))
      elseif r == "nofill" and countFill() == 0 then
        waitUntil(function()
          fetch(function(x) return FILL[x] end, FILL_LOAD, countFill)
          faceLocal(0)
          return countFill() > 0
        end, { "Out of dirt/cobblestone for foundations.", "Put some in the supply or spoil chest." }, "needs dirt or cobblestone")
      end
    else
      c.step = c.step + 1
      save()
      if c.step % 25 == 0 then
        checkPosition()
        status("building", ("%s at %d,%d: %d%%"):format(niceName(c.bp), c.i, c.j, math.floor(c.step / #steps * 100)))
        sharePlan(false)
      end
      if emptySlots() == 0 or fuelLevel() < homeDistance() then
        local want, fillWant = loadPlan(c.step + 1)
        restock(want, fillWant, emptySlots() == 0 and "inventory full" or "low on fuel")
      end
    end
  end
  job.topY = math.max(job.topY, c.base + b.top + 1)
  -- the street work starts above the roof
  local p = here()
  goL({ x = p.x, y = math.max(p.y, c.base + b.top + 1), z = p.z })
  -- door path: walk in from the plot's edge to the door, then back out
  local cells = {}
  -- (cells under the eaves are only ever walked to, never flown down onto)
  for k = #b.door, 1, -1 do cells[#cells + 1] = { x = b.door[k].x, z = b.door[k].z, door = inBox(b.box, b.door[k]) } end
  for k = 1, #b.door do
    cells[#cells + 1] = { x = b.door[k].x, z = b.door[k].z, door = inBox(b.box, b.door[k]), again = true }
  end
  for si, seg in ipairs(c.segs) do
    cells[#cells + 1] = { survey = si }
    for _, cell in ipairs(segCells(seg)) do
      cell.si = si
      cells[#cells + 1] = cell
    end
  end
  c.cells, c.profiles = cells, {}
  c.stage, c.step = "path", 0
  save()
  sharePlan(false)
end

---------------------------------------------------------------- streets

-- Each stretch of street gets one height profile across its whole width:
-- the turtle first walks the centre line to measure the ground, then works
-- out heights that never change by more than one block per block, cutting
-- into high ground and filling dips about equally (so a cliff becomes a ramp
-- centred on its edge), and matching any street already paved at the
-- crossroads. Every one-block step gets a stair, so the streets can all be
-- walked without jumping. Water is bridged with deck planks.

local function roadNames()
  local pal = themes[job.theme].palette
  local t = {}
  for _, r in ipairs({ "path", "edge", "avenue", "deck", "roadStair", "fence", "light" }) do
    if pal[r] then t[pal[r]] = true end
  end
  return t
end

-- Put a stair in the (empty) cell below, climbing towards local heading h.
local function stairDown(h)
  local item = themes[job.theme].palette.roadStair
  if not item or turtle.detectDown() or not selectName(item) then
    turtle.select(1)
    return
  end
  local before = nav.getHeading()
  faceLocal(STAIR_FLIP and (h + 2) % 4 or h)
  turtle.placeDown()
  nav.face(before)
  turtle.select(1)
end

-- Drop down onto whatever is below (stopping at water), clearing plants
-- (and with throughTrees, trees too).
local function land(throughTrees)
  for _ = 1, 16 do
    local ok, data = turtle.inspectDown()
    if ok and (isPlant(data.name) or (throughTrees and has(data.name, TREE))) then
      turtle.digDown()
    elseif solidBelow() or fluidAt(turtle.inspectDown) then
      return
    elseif not nav.down() then
      return
    end
  end
end

-- Step sideways into the next column without digging anything but plants
-- and trees: go over whatever else is in the way.
local function hop(t)
  local p = here()
  faceLocal(headingOf(t.x - p.x, t.z - p.z))
  for _ = 1, 12 do
    local ok, data = turtle.inspect()
    if not ok or isSoft(data.name) or fluidAt(turtle.inspect) then break end
    if not nav.up() then return false end
  end
  return nav.forward()
end

local function adjacent(t)
  local p = here()
  return math.abs(t.x - p.x) + math.abs(t.z - p.z) == 1
end

local function lineCell(seg, t)
  local kind, a, b = parseSeg(seg)
  if kind == "h" then return { x = a * PITCH + STREET + t, z = b * PITCH + STREET } end
  return { x = a * PITCH + STREET, z = b * PITCH + STREET + t }
end

-- Heights for a stretch from the ground measured along it. pinned cells
-- (already paved) keep their height.
local function profile(h, pinned)
  local n = #h
  local p = {}
  for t = 1, n do
    local lo, hi = math.huge, -math.huge
    for k = 1, n do
      lo = math.min(lo, h[k] + math.abs(t - k)) -- highest line under the ground
      hi = math.max(hi, h[k] - math.abs(t - k)) -- lowest line over the dips
    end
    p[t] = pinned[t] and h[t] or math.floor((lo + hi) / 2)
  end
  for _ = 1, 2 do -- keep every step to one block, working out from pinned cells
    for t = 2, n do
      if not pinned[t] then p[t] = math.max(p[t - 1] - 1, math.min(p[t - 1] + 1, p[t])) end
    end
    for t = n - 1, 1, -1 do
      if not pinned[t] then p[t] = math.max(p[t + 1] - 1, math.min(p[t + 1] + 1, p[t])) end
    end
  end
  return p
end

-- Walk the centre line of a stretch, measuring the ground, and work out its profile.
local function measureStretch(c, si, roads)
  local seg = c.segs[si]
  local stairName = themes[job.theme].palette.roadStair
  local h, pinned = {}, {}
  status("surveying", "street " .. seg)
  for t = 0, PITCH do
    local cell = lineCell(seg, t)
    if not (adjacent(cell) and hop(cell)) then reach(cell) end
    land(true)
    local ok, data = turtle.inspectDown()
    local g = here().y - 1
    if ok and data.name == stairName then
      g, pinned[t + 1] = g - 1, true
    elseif ok and roads[data.name] then
      pinned[t + 1] = true
    end
    h[t + 1] = g
  end
  c.profiles[si] = profile(h, pinned)
end

local function roadAbove(roads)
  local ok, data = turtle.inspectUp()
  return ok and roads[data.name]
end

-- Move to stand on the next street cell at height y (one above the road),
-- going over road blocks, stairs and lamps rather than digging them, and
-- cutting through anything else. Returns ok, whether it had to cut, and the
-- height it came in at.
local function goStreet(t, roads)
  local cut = false
  if not adjacent(t) then
    -- fly over and land on top of whatever is there, then work down from it
    if not reach({ x = t.x, z = t.z }) then return false end
    while here().y < t.y do
      if roadAbove(roads) or not nav.up() then return false end
    end
  else
    while here().y < t.y do
      if roadAbove(roads) or not nav.up() then return false end
    end
    local p = here()
    faceLocal(headingOf(t.x - p.x, t.z - p.z))
    for _ = 1, 6 do
      local ok, data = turtle.inspect()
      if not (ok and roads[data.name]) then break end
      if roadAbove(roads) or not nav.up() then return false end
    end
    local ok, data = turtle.inspect()
    if ok and not isSoft(data.name) and not fluidAt(turtle.inspect) then cut = true end
    if not nav.forward() then return false end
  end
  local entry = here().y
  while here().y > t.y do
    local ok, data = turtle.inspectDown()
    if ok and roads[data.name] then break end
    if ok and not isSoft(data.name) and not fluidAt(turtle.inspectDown) then cut = true end
    if not nav.down() then break end
  end
  return true, cut, entry
end

local function lampPost(fence, light)
  for _, item in ipairs({ fence, fence, light }) do
    if not nav.up() then break end
    if selectName(item) then turtle.placeDown() end
  end
  turtle.select(1)
end

-- Lay one street cell to its stretch's profile.
local function layStreet(c, cell, roads)
  local pal = themes[job.theme].palette
  local item = pal[cell.m]
  local prof = c.profiles[cell.si]
  local s = prof[cell.t + 1]
  local arrived, cut, entry = goStreet({ x = cell.x, y = s + 1, z = cell.z }, roads)
  if not arrived then return end
  local ok, data = turtle.inspectDown()
  if ok and roads[data.name] then return end -- already a street here (a crossroads)
  if here().y ~= s + 1 or roadAbove(roads) then return end -- (under an older, higher street)
  -- Where the road cuts into higher ground, open the cut right up to the sky
  -- (up to CUT_MAX blocks) rather than leaving a tunnel: back up through the
  -- way it came in, then on up through the ground. Trees over the road are
  -- only cleared to head height.
  if cut or turtle.detectUp() then
    local climbed = 0
    while climbed < CUT_MAX and not roadAbove(roads) do
      local ok, above = turtle.inspectUp()
      if ok and not fluidAt(turtle.inspectUp) then
        if has(above.name, TREE) and climbed >= 1 then break end
        nav.digUp()
      elseif here().y >= entry then
        break -- open air above the cut
      end
      if not nav.up() then break end
      climbed = climbed + 1
    end
    for _ = 1, climbed do nav.down() end
  end
  if fluidAt(turtle.inspectDown) then
    if selectName(pal.deck) or selectName(item) then turtle.placeDown() end -- bridge
  elseif not turtle.detectDown() then
    fillUnder(s) -- a dip: build it up
    if selectName(item) then turtle.placeDown() end
  elseif selectName(item) then
    local slot = turtle.getSelectedSlot()
    if nav.digDown() then
      turtle.select(slot)
      turtle.placeDown()
    end
  end
  turtle.select(1)
  if cell.lamp then
    lampPost(pal.fence, pal.light)
    return
  end
  -- a stair where the road climbs one block to the next cell
  local kind = parseSeg(c.segs[cell.si])
  local fwd = kind == "h" and 1 or 0
  local climb
  if prof[cell.t + 2] == s + 1 then climb = fwd elseif prof[cell.t] == s + 1 then climb = (fwd + 2) % 4 end
  if climb and nav.up() then stairDown(climb) end
end

-- Door paths are short and on the level yard: walk, pave, no stairs.
local function layDoorPath(c, cell, roads)
  local pal = themes[job.theme].palette
  if not adjacent(cell) then
    if cell.door then return end -- under the eaves: walk only
    if here().x ~= cell.x or here().z ~= cell.z then reach(cell) end
  elseif not hop(cell) then
    return
  end
  land()
  if cell.again then return end
  local ok, data = turtle.inspectDown()
  if ok and roads[data.name] then return end
  if not turtle.detectDown() or fluidAt(turtle.inspectDown) then
    if selectName(pal.deck) or selectName(pal.path) then turtle.placeDown() end
  elseif selectName(pal.path) then
    local slot = turtle.getSelectedSlot()
    if nav.digDown() then
      turtle.select(slot)
      turtle.placeDown()
    end
  end
  turtle.select(1)
end

local function finishPlot(c)
  for _, s in ipairs(c.segs) do job.paved[s] = true end
  job.plots[plotKey(c.i, c.j)] = { status = "built", bp = c.bp }
  job.built[#job.built + 1] = { i = c.i, j = c.j, bp = c.bp, rot = c.rot, base = c.base, ax = c.ax, az = c.az }
  job.cur, bld = nil, nil
  save()
  print(("Finished the %s at plot %d,%d (%d buildings so far)."):format(niceName(c.bp), c.i, c.j, #job.built))
  report.log(("finished a %s"):format(niceName(c.bp)))
end

-- What to carry for the next stretch of street.
local function streetLoad(c, from)
  local pal = themes[job.theme].palette
  local want, slots, full = {}, 0, false
  local function add(item, n)
    for _ = 1, n do
      local have = want[item] or 0
      if have % stackSize(item) == 0 then
        if slots >= LOAD_SLOTS - 4 then full = true return end
        slots = slots + 1
      end
      want[item] = have + 1
    end
  end
  for k = from, #c.cells do
    local cell = c.cells[k]
    if not cell.again and not cell.survey then cellItems(cell, add) end
    if full then break end
  end
  want[pal.roadStair] = (want[pal.roadStair] or 0) + 24
  want[pal.deck] = (want[pal.deck] or 0) + 24
  return want
end

local function doPath(c)
  local pal = themes[job.theme].palette
  local roads = roadNames()
  if c.step == 0 and #c.cells > 0 then restock(streetLoad(c, 1), math.floor(FILL_LOAD / 2), "loading street blocks") end
  while c.step < #c.cells do
    local cell = c.cells[c.step + 1]
    local item = pal[cell.m or "path"]
    if not cell.again and not cell.door and not cell.survey and count(item) == 0 then
      restock(streetLoad(c, c.step + 1), math.floor(FILL_LOAD / 2), "loading street blocks")
      if count(item) == 0 then
        local skip = not waitUntil(function()
          fetch(function(x) return x == item end, 64, function() return count(item) end)
          faceLocal(0)
          return count(item) > 0
        end, { "Out of " .. shortName(item) .. " for streets." }, "needs " .. shortName(item), true)
        if skip then
          c.step = #c.cells
          break
        end
      end
    end
    if cell.survey then
      measureStretch(c, cell.survey, roads)
    elseif cell.si then
      layStreet(c, cell, roads)
    else
      layDoorPath(c, cell, roads)
    end
    c.step = c.step + 1
    save()
    if c.step % 25 == 0 then
      checkPosition()
      status("paving", ("street to plot %d,%d: %d%%"):format(c.i, c.j, math.floor(c.step / #c.cells * 100)))
    end
    if not cell.door then housekeeping() end
  end
  finishPlot(c)
end


---------------------------------------------------------------- main

local function run()
  local p = here()
  if p.x == 0 and p.y == 0 and p.z == 0 then ensureFuel(FUEL_RESERVE * 3) end
  while true do
    if not job.cur then
      local p = nextPlot()
      if not p then
        goHome()
        print(("The village has reached its radius of %d with %d buildings."):format(job.radius, #job.built))
        print("Run 'village grow <radius>' to let it grow further.")
        status("done", ("%d buildings, radius %d"):format(#job.built, job.radius))
        return
      end
      job.cur = { i = p.i, j = p.j, stage = "survey", step = 0, samples = {}, rejected = {} }
      save()
    end
    local c = job.cur
    if c.stage == "survey" then doSurvey(c)
    elseif c.stage == "choose" then doChoose(c)
    elseif c.stage == "clear" then doClear(c)
    elseif c.stage == "build" then doBuild(c)
    elseif c.stage == "path" then doPath(c)
    end
  end
end

local function listBuildings(themeKey)
  local theme = themes[themeKey]
  local lines = { theme.name .. " buildings and what each needs:" }
  for _, name in ipairs(theme.buildings) do
    local b = blueprints.make(name, theme)
    local needs, total = {}, 0
    for _, k in ipairs(b.blocks) do
      local item = theme.palette[k.m]
      if item then
        needs[item] = (needs[item] or 0) + 1
        total = total + 1
      end
    end
    lines[#lines + 1] = ("%s (%d blocks):"):format(theme.names[name] or name, total)
    local sorted = {}
    for item, n in pairs(needs) do sorted[#sorted + 1] = { item = item, n = n } end
    table.sort(sorted, function(a, b) return a.n > b.n end)
    for _, s in ipairs(sorted) do lines[#lines + 1] = ("  %4d %s"):format(s.n, shortName(s.item)) end
  end
  for _, kind in ipairs({ { "side street", "h,1,1" }, { "main road", "h,1,0" } }) do
    local n = {}
    for _, cell in ipairs(segCells(kind[2])) do
      local item = theme.palette[cell.m]
      n[item] = (n[item] or 0) + 1
      if cell.lamp then
        n[theme.palette.fence] = (n[theme.palette.fence] or 0) + 2
        n[theme.palette.light] = (n[theme.palette.light] or 0) + 1
      end
    end
    lines[#lines + 1] = ("Each stretch of %s (%d blocks long):"):format(kind[1], PITCH + 1)
    for item, k in pairs(n) do lines[#lines + 1] = ("  %4d %s"):format(k, shortName(item)) end
  end
  lines[#lines + 1] = "Plus a few " .. shortName(theme.palette.roadStair) .. " for slopes, dirt or"
  lines[#lines + 1] = "cobblestone for foundations and dips, and fuel."
  textutils.pagedPrint(table.concat(lines, "\n"))
end

local args = { ... }
if args[1] == "cancel" then
  nav.deleteFile(JOB_FILE)
  print("Village forgotten. (The buildings stay.)")
  return
end
if args[1] == "list" then
  local key = args[2] or (nav.readFile(JOB_FILE) or {}).theme
  if not themes[key or ""] then
    print("Usage: village list <" .. table.concat(themes.order, "|") .. ">")
    return
  end
  listBuildings(key)
  return
end

if not os.getComputerLabel() then os.setComputerLabel("Villager-" .. os.getComputerID()) end
job = nav.readFile(JOB_FILE)

if args[1] == "status" then
  if not job then print("No village yet.") return end
  print(("%s village, radius %d, %d buildings:"):format(themes[job.theme].name, job.radius, #job.built))
  for _, b in ipairs(job.built) do print(("  %s at plot %d,%d"):format(niceName(b.bp), b.i, b.j)) end
  if job.cur then print(("Working on plot %d,%d (%s)."):format(job.cur.i, job.cur.j, job.cur.stage)) end
  return
end

local hasGps = gpsPos() ~= nil
local useGps = hasGps and (not job or job.gps)
local knowsPosition = nav.init(useGps)

-- No GPS to check against: give the player a chance to say the turtle was moved.
local function confirmResume()
  print("No GPS, so I'm trusting my saved position.")
  print("Resuming in 10 seconds. If you moved me, press any key.")
  local timer = os.startTimer(10)
  while true do
    local event, value = os.pullEvent()
    if event == "timer" and value == timer then return true end
    if event == "key" then
      print("Put me back on my home block, facing the way I faced when")
      print("the village began, then run: village here")
      return false
    end
  end
end

if args[1] == "resume" or args[1] == "here" or args[1] == "grow" then
  if not job then
    print("No village to resume.")
    return
  end
  if args[1] == "here" then
    local x, y, z = toWorld({ x = 0, y = 0, z = 0 })
    nav.setPosition(x, y, z, job.origin.heading)
    print("Position reset to home.")
  elseif args[1] == "grow" then
    local r = tonumber(args[2])
    if not r or r <= job.radius then
      print(("Usage: village grow <radius>, more than the current %d."):format(job.radius))
      return
    end
    job.radius = r
    save()
    print(("The village can now grow out to %d blocks."):format(r))
  elseif useGps then
    print("Checked my position with GPS.")
  else
    if job.gps then print("Can't reach GPS right now.") end
    if not knowsPosition then error("Lost track of position; can't resume. Run 'village here' from home.", 0) end
    if not confirmResume() then return end
  end
  print(("Resuming the %s village (%d buildings so far)."):format(themes[job.theme].name, #job.built))
elseif job then
  print("A village is already in progress. Run 'village resume' or 'village cancel'.")
  return
else
  print("Village themes:")
  for k, key in ipairs(themes.order) do print(("%d) %s: %s"):format(k, themes[key].name, themes[key].blurb)) end
  local theme
  while not theme do
    write(("Pick a theme (1-%d): "):format(#themes.order))
    local input = read()
    theme = themes.order[tonumber(input) or 0]
    if not theme then
      for _, key in ipairs(themes.order) do
        if key == input:lower() then theme = key end
      end
    end
  end
  write(("How far out may it grow, in blocks? [%d]: "):format(DEFAULT_RADIUS))
  local radius = tonumber(read()) or DEFAULT_RADIUS
  if radius < PITCH then radius = PITCH end

  if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
  local p = nav.getPos()
  job = {
    theme = theme, radius = radius, gps = hasGps, seed = os.getComputerID() * 1000 + math.floor(os.clock() * 100) % 1000,
    origin = { x = p.x, y = p.y, z = p.z, heading = nav.getHeading() },
    topY = 8, plots = {}, paved = {}, built = {},
  }
  faceSupply()
  local chest = frontChest()
  local found, behind = turtle.inspect()
  faceLocal(0)
  if not chest then
    if not found then
      print("There's nothing directly behind me.")
    elseif behind.name:find("modem", 1, true) then
      print("Behind me is a modem, not a chest. Put the supply chest")
      print("there and the modem against the chest's other side.")
    else
      print(("Behind me is %s, not a chest."):format(shortName(behind.name)))
    end
    print("I need a supply chest directly behind me (and a spoil")
    print("chest on my left). With a storage system I still need it:")
    print("that's where the storage sends my blocks.")
    print("Place them and run village again.")
    return
  end
  print(("%s village, up to %d blocks out (about %d plots)."):format(themes[theme].name, radius, #plotOrder()))
  print(hasGps and "GPS found: I'll check my position as I go." or "No GPS: working from my own position count only.")
  print("Supply chest behind me, spoil chest on my left.")
  print("'village list' shows what each building needs.")
  print("Press Enter to start.")
  read()
  save()
end

report.init("village builder")
parallel.waitForAny(function()
  local ok, err = pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop, planServer)
