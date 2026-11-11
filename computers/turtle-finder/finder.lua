-- Turtle finder: points an arrow at a turtle (or any computer) you've lost.
-- Everything running lib/report.lua sends its status every 10 seconds with
-- its GPS position; this listens for those and, with GPS where you stand,
-- shows how far away the one you pick is, which way, and how far up or down.
-- Best on a pocket computer with a wireless or ender modem.
--
--   finder                list the turtles heard, nearest first; pick one to follow
--   finder <name or id>   follow the one whose label contains name (waits until it's heard)
--   finder all            list every computer, not just turtles
--
-- The arrow points relative to the way you last walked: walk a few blocks
-- towards where you're looking, then open the computer. C switches to a
-- compass (north up) instead.
local screen = require("lib.screen") -- flicker-free drawing
local net = require("lib.net") -- opening modems
local files = require("lib.files") -- crash-safe save files
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local PROTOCOL = "cc_status"
local SEEN_FILE = "/.finder_seen"

-- How far you have to walk (in blocks) before the arrow takes it as the way you're facing.
local WALK_MIN = 3
-- Heard within this long (seconds): shown as fresh; after STALE_AFTER, as old.
local FRESH = 30
local STALE_AFTER = 300
-- Most turtles and computers remembered between runs.
local REMEMBER = 60
-- Seconds between GPS checks of where you are.
local GPS_EVERY = 1

---------------------------------------------------------------- state

local seen = files.read(SEEN_FILE) or {} -- id -> { label, kind, role, state, detail, pos, heard, posAt }
local me, facing, anchor -- my GPS position, the bearing I last walked (degrees), where that walk began
local showAll, compass = false, false
local view, selected, target, want = "list", 1, nil, nil
local saveDue = false

local function now() return os.epoch("utc") / 1000 end

local function nameOf(id, c) return c.label or ("#" .. id) end

-- Keep only the REMEMBER most recently heard.
local function trim()
  local ids = {}
  for id in pairs(seen) do ids[#ids + 1] = id end
  if #ids <= REMEMBER then return end
  table.sort(ids, function(a, b) return seen[a].heard > seen[b].heard end)
  for i = REMEMBER + 1, #ids do seen[ids[i]] = nil end
end

---------------------------------------------------------------- directions

local atan2 = math.atan2 or math.atan
local DIRECTIONS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }
local SHORT = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Compass bearing from dx, dz: 0 is north (-z), 90 east (+x).
local function bearing(dx, dz) return math.deg(atan2(dx, -dz)) % 360 end

local function octant(deg) return math.floor((deg + 22.5) / 45) % 8 end

-- From me to c: horizontal distance, height difference, compass bearing.
local function toward(c)
  if not me or not c.pos then return nil end
  local dx, dz = c.pos.x - me.x, c.pos.z - me.z
  return math.sqrt(dx * dx + dz * dz), c.pos.y - me.y, bearing(dx, dz)
end

-- The arrow as 9x9 pixels, drawn two characters wide so it looks square:
-- straight up, and up-right. The other six are these turned.
local ARROWS = {
  { "....#....", "...###...", "..#####..", ".#######.", "#########", "...###...", "...###...", "...###...", "...###..." },
  { "...######", "....#####", ".....####", "....#####", "...###.##", "..###...#", ".###.....", "###......", ".#......." },
}

local function turned(rows)
  local n, out = #rows, {}
  for r = 1, n do
    local line = {}
    for c = 1, n do line[c] = rows[n + 1 - c]:sub(r, r) end
    out[r] = table.concat(line)
  end
  return out
end

-- ARROW[o] is the arrow for octant o (0 = up, clockwise).
local ARROW = {}
for o = 0, 7 do
  local rows = ARROWS[o % 2 + 1]
  for _ = 1, math.floor(o / 2) do rows = turned(rows) end
  ARROW[o] = rows
end

local function drawArrow(win, x, y, rows, colour)
  for r, line in ipairs(rows) do
    for c = 1, #line do
      if line:sub(c, c) == "#" then screen.put(win, x + (c - 1) * 2, y + r - 1, "  ", "white", colour) end
    end
  end
end

---------------------------------------------------------------- text

local function ago(t)
  local s = math.max(0, math.floor(now() - t))
  if s < 60 then return s .. "s ago" end
  if s < 3600 then return math.floor(s / 60) .. "m ago" end
  if s < 86400 then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / 86400) .. "d ago"
end

local function ageColour(t)
  local s = now() - t
  if s < FRESH then return "lime" elseif s < STALE_AFTER then return "yellow" end
  return "red"
end

local function blocks(n)
  n = math.floor(n + 0.5)
  return n == 1 and "1 block" or (n .. " blocks")
end

-- Sorted list of what to show: nearest first, then the ones with no position, most recently heard first.
local function entries()
  local list = {}
  for id, c in pairs(seen) do
    if showAll or c.kind == "turtle" then list[#list + 1] = { id = id, c = c, dist = toward(c) } end
  end
  table.sort(list, function(a, b)
    if a.dist and b.dist then return a.dist < b.dist end
    if a.dist or b.dist then return a.dist ~= nil end
    return a.c.heard > b.c.heard
  end)
  return list
end

-- Does c (heard as id) match what the player typed?
local function matches(id, c, text)
  if tostring(id) == text then return true end
  return c.label ~= nil and c.label:lower():find(text:lower(), 1, true) ~= nil
end

---------------------------------------------------------------- drawing

local display = screen.new(term.current())

local function header(win, w, text)
  screen.put(win, 1, 1, screen.fit(" " .. text, w), "white", "gray")
end

local function drawList()
  local win, w, h = display:frame()
  local list = entries()
  selected = math.max(1, math.min(selected, #list))
  header(win, w, ("Finder: %s (%d)"):format(showAll and "everything" or "turtles", #list))
  if #list == 0 then
    local lines = screen.wrap(showAll and "Nothing heard yet. Anything running a program from here sends its status every 10 seconds, if it has a modem and its chunk is loaded."
      or "No turtles heard yet. A turtle needs a wireless or ender modem, and its chunk loaded, to send where it is.", w - 1)
    for i, line in ipairs(lines) do screen.put(win, 2, 2 + i, line, "lightGray") end
  end
  local rows = h - 3
  local first = math.max(1, selected - rows + 1)
  for i = first, math.min(#list, first + rows - 1) do
    local e, y = list[i], 2 + i - first
    local where = "no position"
    if e.dist then where = ("%d %s"):format(math.floor(e.dist + 0.5), SHORT[octant(select(3, toward(e.c))) + 1]) end
    if e.c.pos and not me then where = "no GPS here" end
    local bg = i == selected and "blue" or "black"
    screen.put(win, 1, y, screen.fit(" " .. nameOf(e.id, e.c), w), ageColour(e.c.heard), bg)
    screen.put(win, w - #where, y, where, "white", bg)
  end
  screen.put(win, 1, h - 1, screen.fit(me and ("You: %d %d %d"):format(me.x, me.y, me.z) or "You: no GPS signal", w), "lightGray")
  screen.put(win, 1, h, screen.fit(" Enter go  Tab kind  Q quit", w), "white", "gray")
  display:show()
end

local function drawFollow()
  local win, w, h = display:frame()
  local c = target and seen[target]
  if not c then
    header(win, w, "Finder")
    local lines = screen.wrap(("Waiting to hear from '%s'. It needs a wireless or ender modem, and its chunk loaded."):format(want or "?"), w - 1)
    for i, line in ipairs(lines) do screen.put(win, 2, 2 + i, line, "lightGray") end
    screen.put(win, 1, h, screen.fit(" \27 list  Q quit", w), "white", "gray")
    display:show()
    return
  end
  header(win, w, nameOf(target, c))
  local dist, dy, deg = toward(c)
  local lines = {} -- { text, colour } under the arrow
  local y = 3 -- where they start: under the arrow once one is drawn
  local ax = math.floor((w - 18) / 2) + 1
  if not c.pos then
    lines[#lines + 1] = { "It hasn't sent a position: no GPS where it is.", "orange" }
  elseif not me then
    lines[#lines + 1] = { "No GPS signal here, so I can't point.", "orange" }
    lines[#lines + 1] = { ("It's at %d %d %d."):format(c.pos.x, c.pos.y, c.pos.z), "white" }
  elseif dist < 1.5 then
    if math.abs(dy) <= 1 then
      lines[#lines + 1] = { "You're right next to it!", "lime" }
    else
      drawArrow(win, ax, 3, ARROW[dy > 0 and 0 or 4], "lightBlue")
      y = 13
      lines[#lines + 1] = { ("Straight %s: %s."):format(dy > 0 and "up" or "down", blocks(math.abs(dy))), "lightBlue" }
    end
  else
    local rel = compass and deg or (facing and deg - facing or deg)
    drawArrow(win, ax, 3, ARROW[octant(rel % 360)], ageColour(c.posAt or c.heard))
    y = 13
    if compass or not facing then screen.put(win, ax + 8, 2, "N", "white") end
    lines[#lines + 1] = { ("%s %s"):format(blocks(dist), DIRECTIONS[octant(deg) + 1]), "white" }
    lines[#lines + 1] = { math.abs(dy) <= 1 and "About your height" or ("%s %s you"):format(blocks(math.abs(dy)), dy > 0 and "above" or "below"), "white" }
  end
  if c.pos and me then lines[#lines + 1] = { ("At %d %d %d"):format(c.pos.x, c.pos.y, c.pos.z), "lightGray" } end
  local state = (c.state or "?") .. (c.detail and (": " .. c.detail) or "")
  for _, line in ipairs(screen.wrap(state, w - 1, 2)) do lines[#lines + 1] = { line, "yellow" } end
  lines[#lines + 1] = { "Heard " .. ago(c.heard) .. (c.posAt and c.posAt < c.heard - 30 and (", position " .. ago(c.posAt)) or ""), ageColour(c.heard) }
  local mode = compass and "Arrow: north is up" or facing and "Arrow: the way you walked" or "Walk a few blocks to aim"
  lines[#lines + 1] = { mode, "lightGray" }
  for _, line in ipairs(lines) do
    for _, part in ipairs(screen.wrap(line[1], w - 1)) do
      if y < h then screen.put(win, 2, y, part, line[2]) end
      y = y + 1
    end
  end
  screen.put(win, 1, h, screen.fit(" \27 list  C " .. (compass and "walk   " or "compass") .. "  Q quit", w), "white", "gray")
  display:show()
end

local function draw()
  if view == "list" then drawList() else drawFollow() end
end

---------------------------------------------------------------- events

local function follow(id)
  target, view = id, "follow"
end

local function heard(id, msg)
  local c = seen[id] or {}
  seen[id] = c
  c.label, c.kind, c.role, c.state, c.detail = msg.label, msg.kind, msg.role, msg.state, msg.detail
  c.heard = now()
  -- keep the last known position if a message doesn't include one
  if msg.pos then c.pos, c.posAt = msg.pos, c.heard end
  if want and not target and matches(id, c, want) then follow(id) end
  saveDue = true
end

-- Where I am, every GPS_EVERY seconds; walking WALK_MIN blocks sets the way I'm facing.
local function gpsLoop()
  while true do
    local p
    local x, y, z = gps.locate(1)
    if x then
      p = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
      if not anchor then anchor = p end
      local dx, dz = p.x - anchor.x, p.z - anchor.z
      if dx * dx + dz * dz >= WALK_MIN * WALK_MIN then
        facing, anchor = bearing(dx, dz), p
      end
    end
    me = p
    os.queueEvent("finder_gps")
    sleep(GPS_EVERY)
  end
end

local function main()
  local timer = os.startTimer(1)
  local lastSave = now()
  draw()
  while true do
    local ev = { os.pullEvent() }
    local name = ev[1]
    if name == "rednet_message" and ev[4] == PROTOCOL then
      if type(ev[3]) == "table" and ev[3].type == "status" then heard(ev[2], ev[3]) end
    elseif name == "timer" and ev[2] == timer then
      if saveDue and now() - lastSave > 10 then
        trim()
        files.write(SEEN_FILE, seen)
        saveDue, lastSave = false, now()
      end
      timer = os.startTimer(1)
    elseif name == "key" then
      local key = ev[2]
      if key == keys.q then
        if saveDue then trim() files.write(SEEN_FILE, seen) end
        return
      elseif view == "list" then
        local list = entries()
        if key == keys.up then selected = selected - 1
        elseif key == keys.down then selected = selected + 1
        elseif key == keys.tab then showAll, selected = not showAll, 1
        elseif key == keys.enter and list[selected] then follow(list[selected].id)
        end
      else
        if key == keys.backspace or key == keys.left then view, want = "list", nil
        elseif key == keys.c then compass = not compass
        end
      end
    elseif name == "mouse_click" and view == "list" then
      local _, h = display:size()
      local list, y = entries(), ev[4]
      if y >= 2 and y <= h - 2 then
        local i = math.max(1, selected - (h - 3) + 1) + y - 2
        if list[i] then follow(list[i].id) end
      end
    end
    draw()
  end
end

---------------------------------------------------------------- start

local args = { ... }
if args[1] == "all" then
  showAll = true
elseif args[1] then
  want = table.concat(args, " ")
  view = "follow"
  -- one heard on an earlier run may already match: the most recently heard
  local best
  for id, c in pairs(seen) do
    if matches(id, c, want) and (not best or c.heard > seen[best].heard) then best = id end
  end
  if best then target = best end
end

if not net.open() then
  print("Attach a wireless or ender modem: turtles send where they are over rednet.")
  return
end

require("lib.label").set("Finder")
if errlog then errlog.init("finder", function() return { target = target, want = want } end) end
local ok, err = (errlog and errlog.pcall or pcall)(function() parallel.waitForAny(main, gpsLoop) end)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok then error(err, 0) end
