-- Blueprint projector: loads a building plan and projects it into the world
-- with a CC: Spatial Projector, so anyone wearing bound Spatial Goggles sees
-- the building before it's built. A monitor (or this computer's screen) moves
-- and turns it, and steps through its layers so you can build from it block
-- by block. Plans are files in /plans/ (.json or .lua, see lib/plan.lua):
-- 'install plan <name>' gets more from the website.
--
-- Usage:
--   projector                 show the last plan (startup runs this)
--   projector <plan>          show a plan: /plans/<plan>.json or .lua, or a file path
--   projector village         show what a village turtle is building, where it's building it
--   projector build           have a builder turtle (computers/builder-turtle) build the plan where it's shown
--                             (or a command computer running 'instabuild serve' place it, in creative)
--   projector list            list the plans
--   projector check <plan>    load a plan and print its size and blocks
--   projector clear           remove the projection (stays hidden after a reboot)
local ui = require("ui")
local plans = require("lib.plan") -- loading plans and placing them in the world
local crew = require("lib.crew") -- hands the plan to builder turtles
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local STATE_FILE = "/.projector_state"
local PLAN_COPY = "/.projector_build_plan" -- the plan being built, copied when Build was tapped (.json or .lua)
local MAX_SHAPES = 1000     -- never use more projector objects than this (the mod allows 1024)
local BATCH = 16            -- projector calls sent together; each one waits for a server tick
local DEBOUNCE = 0.6        -- seconds to wait after the last tap before redrawing the building
local SOUTH_GAP = 2         -- "Here" puts the building this many blocks south of the projector
local STEPS = { 1, 5, 16 }  -- move step sizes the Step button cycles through
local VIEWS = { "whole", "layer", "outline" }
local BOX_WIDTH = 0.0625    -- line width of the building's blocks
local FRAME_WIDTH = 0.03    -- line width of the outline and layer guide
local FRAME_COLOR = 0x9a9a9a
local SLAB_COLOR = 0xffffff -- the layer you're building, in layer view
local MIXED_COLOR = 0x33ff88 -- shapes that mix materials, when a plan is too big for one colour each
local INSET_BLOCK = 0.04    -- shrink single blocks a little so neighbours' outlines don't merge
local INSET_MERGED = 0.01
local VILLAGE_FILE = "/.projector_village" -- the last building heard from a village turtle
local PLAN_PROTOCOL = "village_plan" -- rednet protocol village turtles share their building on
local INSTA_PROTOCOL = "instabuild" -- a command computer running 'instabuild serve' places plans sent on this
local INSTA_WAIT = 10 -- seconds to wait for it to take a building
local INSTA_RETRY = 30 -- seconds before looking for one again after none was found

local args = { ... }

---------------------------------------------------------------- files

-- Crash-safe save files (lib/files.lua).
local writeFile, readFile = files.write, files.read

-- The last building a village turtle shared: { from, key, name, world, blocks,
-- stage, y, step, total }. world is true when its coordinates are real ones
-- (the turtle has GPS), so the projection can go exactly where it's building.
local village = readFile(VILLAGE_FILE)

---------------------------------------------------------------- colours

-- Projection colour from words in the block name. Earlier entries win, so
-- dye colours beat "glass"/"wool"/"terracotta" and "dark_oak" beats "oak".
local COLOR_WORDS = {
  { "light_blue", 0x3ab3da }, { "light_gray", 0x9d9d97 }, { "white", 0xf0f0f0 }, { "gray", 0x5a6266 },
  { "black", 0x1d1d21 }, { "brown", 0x835432 }, { "red", 0xb02e26 }, { "orange", 0xf9801d },
  { "yellow", 0xfed83d }, { "lime", 0x80c71f }, { "green", 0x5e7c16 }, { "cyan", 0x169c9c },
  { "blue", 0x3c44aa }, { "purple", 0x8932b8 }, { "magenta", 0xc74ebd }, { "pink", 0xf38baa },
  { "dark_oak", 0x4f3218 }, { "oak", 0xb8945f }, { "spruce", 0x72543a }, { "birch", 0xd7cb8d },
  { "jungle", 0xb88764 }, { "acacia", 0xba6337 }, { "mangrove", 0x773934 }, { "cherry", 0xe4b4a5 },
  { "bamboo", 0xd2bd5a }, { "crimson", 0x7e3a56 }, { "warped", 0x2b6963 },
  { "nether", 0x5a2a2e }, { "mossy", 0x6a7d4f }, { "cobblestone", 0x7a7a7a }, { "deepslate", 0x4d4d52 },
  { "blackstone", 0x2a2328 }, { "sandstone", 0xd8cb9b }, { "sand", 0xdbcfa3 }, { "gravel", 0x847f7e },
  { "andesite", 0x888889 }, { "diorite", 0xbcbcbc }, { "granite", 0x956755 }, { "tuff", 0x6c6d66 },
  { "calcite", 0xdfe0dc }, { "stone", 0x8f8f8f }, { "bricks", 0x976253 }, { "brick", 0x976253 },
  { "quartz", 0xebe5de }, { "prismarine", 0x63a598 }, { "purpur", 0xa77aa7 }, { "terracotta", 0x985e43 },
  { "mud", 0x8c6a4f }, { "dirt", 0x866043 }, { "grass", 0x5d9a3a }, { "leaves", 0x3f8a2f },
  { "hay", 0xc9a42a }, { "glass", 0xa8d8ea }, { "ice", 0x91b7fd }, { "snow", 0xf6fefe },
  { "water", 0x3f76e4 }, { "lava", 0xd96415 }, { "iron", 0xd8d8d8 }, { "gold", 0xf5cd3c },
  { "oxidized", 0x4fa58a }, { "amethyst", 0x8d63c8 }, { "obsidian", 0x1e1530 }, { "pearlescent", 0xe6c6dc },
  { "verdant", 0xd4e8b8 }, { "shroomlight", 0xf0a050 }, { "moss", 0x5a7a2c }, { "barrel", 0x86643a },
  { "bookshelf", 0x7a5a32 }, { "crafting", 0x9c6a3a }, { "smithing", 0x3a3a46 }, { "cartography", 0x8a7050 },
  { "fletching", 0xc9b27a }, { "enchanting", 0x7a2030 }, { "brewing", 0x8a8a6a }, { "cauldron", 0x3c3c40 },
  { "campfire", 0xe08a2c }, { "candle", 0xe8dcb0 }, { "azalea", 0x5f8a30 }, { "fern", 0x4f7f30 }, { "poppy", 0xc0282a },
  { "cornflower", 0x4a64c8 }, { "cane", 0x8cbf5a },
  { "copper", 0xc0704c }, { "lantern", 0xf2b84a }, { "torch", 0xf2c84a }, { "glowstone", 0xf8d58a },
  { "log", 0x6b5131 }, { "wood", 0x6b5131 }, { "planks", 0xb8945f },
}
local FALLBACK_COLORS = { 0xff6b6b, 0xffd166, 0x06d6a0, 0x4cc9f0, 0xb388eb, 0xf78c6b, 0x83e377, 0xf15bb5 }

local function colorFor(block)
  local words = "_" .. block:gsub("^.-:", ""):gsub("%[.*$", "") .. "_"
  for _, entry in ipairs(COLOR_WORDS) do
    if words:find("_" .. entry[1] .. "_", 1, true) then return entry[2] end
  end
  local hash = 0
  for i = 1, #block do hash = (hash * 31 + block:byte(i)) % 65536 end
  return FALLBACK_COLORS[hash % #FALLBACK_COLORS + 1]
end

-- Closest of the 16 terminal colours, for the monitor's map.
local function termColor(rgb)
  local r, g, b = colors.unpackRGB(rgb)
  local best, bestD = colors.white, math.huge
  for i = 0, 15 do
    local c = 2 ^ i
    local cr, cg, cb = term.nativePaletteColour(c)
    local d = (r - cr) ^ 2 + (g - cg) ^ 2 + (b - cb) ^ 2
    if d < bestD then best, bestD = c, d end
  end
  return best
end

local function isLight(rgb)
  local r, g, b = colors.unpackRGB(rgb)
  return 0.3 * r + 0.59 * g + 0.11 * b > 0.55
end

---------------------------------------------------------------- plans

-- Colours for the projection and the panel's map.
local function decorate(p)
  for _, m in ipairs(p.mats) do
    m.color = m.color or colorFor(m.block)
    m.term, m.light = termColor(m.color), isLight(m.color)
  end
  p.cache = {}
  return p
end

-- file: load from there instead of /plans (the copy a build was started with)
local function loadPlan(id, file)
  if id == "village" then
    if not village then return nil, "No village builder heard yet." end
    local ok, p = pcall(plans.fromTable, { name = village.name, blocks = village.blocks }, id)
    if not ok then return nil, "village: " .. p end
    local x0, y0, z0 = math.huge, math.huge, math.huge
    for _, b in ipairs(village.blocks) do x0, y0, z0 = math.min(x0, b[1]), math.min(y0, b[2]), math.min(z0, b[3]) end
    p.village, p.fixed, p.world0 = true, village.world, { x = x0, y = y0, z = z0 }
    return decorate(p)
  end
  local p, err = plans.load(file or id)
  if not p then return nil, err end
  p.id = id
  return decorate(p)
end

-- Every plan id: the ones in /plans/, the village builder's, then extra, a
-- file path that was asked for.
local function planIds(extra)
  local ids, seen = {}, {}
  local function add(id)
    if id and not seen[id] then ids[#ids + 1] = id; seen[id] = true end
  end
  for _, id in ipairs(plans.ids()) do add(id) end
  if village then add("village") end
  add(extra)
  return ids
end

---------------------------------------------------------------- shapes

-- Join neighbouring blocks into as few boxes as possible (rows, then
-- rectangles, then stacks): a projector holds a limited number of objects and
-- each one costs a sync to every goggle wearer. Blocks must be sorted bottom
-- up. With sameMaterial, only blocks of one material join; m is nil otherwise.
local function mergeBoxes(blocks, sameMaterial)
  local grid, used, boxes = {}, {}, {}
  local function key(x, y, z) return x .. "," .. y .. "," .. z end
  for _, b in ipairs(blocks) do grid[key(b.x, b.y, b.z)] = sameMaterial and b.m or 0 end
  local function free(x, y, z, m)
    local k = key(x, y, z)
    return grid[k] == m and not used[k]
  end
  local function rectFree(x0, x1, y, z0, z1, m)
    for z = z0, z1 do
      for x = x0, x1 do
        if not free(x, y, z, m) then return false end
      end
    end
    return true
  end
  for i, b in ipairs(blocks) do
    local m = grid[key(b.x, b.y, b.z)]
    if free(b.x, b.y, b.z, m) then
      local x1, y1, z1 = b.x, b.y, b.z
      while free(x1 + 1, b.y, b.z, m) do x1 = x1 + 1 end
      while rectFree(b.x, x1, b.y, z1 + 1, z1 + 1, m) do z1 = z1 + 1 end
      while rectFree(b.x, x1, y1 + 1, b.z, z1, m) do y1 = y1 + 1 end
      for y = b.y, y1 do
        for z = b.z, z1 do
          for x = b.x, x1 do used[key(x, y, z)] = true end
        end
      end
      boxes[#boxes + 1] = { x0 = b.x, y0 = b.y, z0 = b.z, x1 = x1, y1 = y1, z1 = z1, m = sameMaterial and m or nil }
    end
    if i % 2000 == 0 then os.queueEvent("projector_yield") os.pullEvent("projector_yield") end
  end
  return boxes
end

local function singleBoxes(blocks)
  local boxes = {}
  for i, b in ipairs(blocks) do
    boxes[i] = { x0 = b.x, y0 = b.y, z0 = b.z, x1 = b.x, y1 = b.y, z1 = b.z, m = b.m }
  end
  return boxes
end

---------------------------------------------------------------- state

local projector, origin, budget
local state = readFile(STATE_FILE) or {}
local plan
local builders -- the builder turtles building the plan (lib/crew.lua), set up below

-- Plan block (x, z) as an offset from where it's shown (state x, y, z, turn
-- are lib/plan.lua's "at"), and the ground it covers.
local function offset(x, z) return plans.offset(plan, state.turn, x, z) end
local function footprint() return plans.footprint(plan, state) end

-- state.build is lib/crew.lua's build while builder turtles are building
-- the plan, and state.buildPlan the copy of the plan it was started with.
local function save()
  writeFile(STATE_FILE, {
    plan = state.plan, x = state.x, y = state.y, z = state.z, turn = state.turn,
    view = state.view, layer = state.layer, step = state.step, hidden = state.hidden, build = state.build,
    buildPlan = state.buildPlan, page = state.page,
  })
end

local function placeHere()
  state.x, state.y, state.z = origin.x, origin.y, 0
  local _, z0 = footprint()
  state.z = origin.z + SOUTH_GAP - z0
end

-- In layer view, a village building shows the layer the turtle is on.
local function villageLayer()
  if not (plan.village and village.y) then return nil end
  return math.max(1, math.min(plan.h, village.y - plan.world0.y + 1))
end

local function usePlan(id, keepPlace)
  -- while it's being built, the plan comes from the copy taken at Build, so
  -- a reboot shows (and hands out) exactly what the builders are building
  local building = state.build and state.buildPlan and id == state.plan and fs.exists(state.buildPlan)
  local p, err = loadPlan(id, building and state.buildPlan or nil)
  if not p then return false, err end
  plan, state.plan = p, id
  state.layer = state.view == "layer" and (villageLayer() or 1) or plan.h
  if plan.fixed then
    -- real coordinates from the turtle: put it exactly where it's being built
    state.turn = 0
    state.x, state.y, state.z = plan.world0.x + plan.cx, plan.world0.y, plan.world0.z + plan.cz
  elseif not keepPlace or not state.x then
    placeHere()
  end
  return true
end

---------------------------------------------------------------- projection

local wanted, drawn = 1, 0  -- what the panel asked for vs what the projector shows
local shown = {}            -- every object id in the projector right now
local status = { text = "Starting...", color = colors.lightGray }
local note, loadNote -- why the projection isn't the whole plan; why a plan was skipped

local function setStatus(text, color)
  status.text, status.color = text, color or colors.lightGray
  os.queueEvent("projector_status")
end

local function tell(text)
  note = text
  os.queueEvent("projector_status")
end

-- Hand the plan to the builders (lib/crew.lua, in buildLoop): from a copy,
-- so a reboot mid-build or an update to /plans can't change what the strips
-- still waiting are cut from.
local function requestBuild()
  if plan.village then return tell("The village builder builds this one itself.") end
  local copy, err = plans.copy(state.plan, PLAN_COPY)
  if not copy then return tell(err) end
  state.buildPlan = copy
  save()
  os.queueEvent(crew.START)
end

local function box(id, x0, y0, z0, x1, y1, z1, color, width)
  return { id = id, x0 = x0, y0 = y0, z0 = z0, x1 = x1, y1 = y1, z1 = z1, color = color, width = width }
end

-- Everything the projector should show for the current state.
local function scene()
  if state.hidden then return {}, nil end
  local fx0, fz0, fx1, fz1 = footprint()
  local objs = { box("frame", fx0, state.y, fz0, fx1 + 1, state.y + plan.h, fz1 + 1, FRAME_COLOR, FRAME_WIDTH) }
  if state.view == "outline" then return objs, nil end

  local layer, why = state.layer, nil
  local cacheKey = state.view .. layer
  local cached = plan.cache[cacheKey]
  if not cached then
    local boxes, inset
    if state.view == "layer" then
      local blocks = plan.layers[layer]
      if #blocks <= budget then
        boxes, inset = singleBoxes(blocks), INSET_BLOCK
      else
        boxes, inset = mergeBoxes(blocks, true), INSET_MERGED
      end
    else
      local blocks = {}
      for _, b in ipairs(plan.blocks) do
        if b.y < layer then blocks[#blocks + 1] = b end
      end
      boxes, inset = mergeBoxes(blocks, true), INSET_MERGED
      if #boxes > budget then
        boxes, why = mergeBoxes(blocks, false), "Too big for one colour per block: shown in one colour"
      end
    end
    if #boxes > budget then
      why = ("Too big: only %d of %d shapes fit"):format(budget, #boxes)
      for i = #boxes, budget + 1, -1 do boxes[i] = nil end
    end
    cached = { boxes = boxes, inset = inset, why = why }
    plan.cache[cacheKey] = cached
  end

  if state.view == "layer" then
    local y = state.y + layer - 1
    objs[2] = box("slab", fx0, y, fz0, fx1 + 1, y + 1, fz1 + 1, SLAB_COLOR, FRAME_WIDTH)
  end
  local d = cached.inset
  for i, b in ipairs(cached.boxes) do
    local ax, az = offset(b.x0, b.z0)
    local bx, bz = offset(b.x1, b.z1)
    local x0, z0 = state.x + math.min(ax, bx), state.z + math.min(az, bz)
    local x1, z1 = state.x + math.max(ax, bx) + 1, state.z + math.max(az, bz) + 1
    local color = b.m and plan.mats[b.m].color or MIXED_COLOR
    objs[#objs + 1] = box("b" .. i, x0 + d, state.y + b.y0 + d, z0 + d, x1 - d, state.y + b.y1 + 1 - d, z1 - d, color, BOX_WIDTH)
  end
  return objs, cached.why
end

local function putBox(o)
  projector.box(o.id, o.x0, o.y0, o.z0, o.x1, o.y1, o.z1, { color = o.color, width = o.width })
  shown[o.id] = true
end

-- Run projector calls BATCH at a time: each call waits for the server, so
-- sending them together is many times faster than one by one. Stops early
-- (returns false) when the panel asks for something newer.
local function runCalls(calls, version)
  local failed
  for i = 1, #calls, BATCH do
    local group = {}
    for j = i, math.min(i + BATCH - 1, #calls) do
      local call = calls[j]
      group[#group + 1] = function()
        local ok, err = pcall(call)
        if not ok then failed = failed or err end
      end
    end
    parallel.waitForAll(table.unpack(group))
    if failed then error(failed, 0) end
    if version ~= wanted then return false end
    if #calls > BATCH then setStatus(("Drawing %d of %d..."):format(math.min(i + BATCH - 1, #calls), #calls)) end
  end
  return true
end

local function project(objs, version)
  local calls, keep = {}, {}
  for _, o in ipairs(objs) do keep[o.id] = true end
  -- removals first, so a full projector has room for the new shapes
  for id in pairs(shown) do
    if not keep[id] then
      calls[#calls + 1] = function() projector.remove(id); shown[id] = nil end
    end
  end
  for _, o in ipairs(objs) do
    calls[#calls + 1] = function() putBox(o) end
  end
  return runCalls(calls, version)
end

local function describe()
  if state.hidden then return "hidden" end
  return ("%s at %d, %d, %d, layer %d of %d"):format(plan.name, state.x, state.y, state.z, state.layer, plan.h)
end

local function drawLoop()
  while true do
    while drawn == wanted do os.pullEvent("projector_redraw") end
    local version = wanted
    local ok, err = pcall(function()
      local objs, why = scene()
      note, loadNote = why or loadNote, nil
      -- the outline moves straight away so taps feel instant; the building
      -- follows once the taps stop
      if objs[1] then
        putBox(objs[1])
        setStatus(drawn > 0 and "Moving..." or "Drawing...")
        sleep(DEBOUNCE)
        if version ~= wanted then return end
      end
      if not project(objs, version) then return end
      drawn = version
      if state.hidden then
        setStatus("Hidden. Tap Show to project it again.")
      else
        setStatus(("Showing %d shapes"):format(#objs), colors.lime)
      end
      if report then report.set(state.hidden and "idle" or "running", describe(), { pos = origin, posFrom = "fixed" }) end
    end)
    if not ok then
      if err == "Terminated" then error(err, 0) end
      drawn = version
      setStatus("Projector: " .. tostring(err), colors.red)
      if report then report.set("error", tostring(err), { pos = origin, posFrom = "fixed" }) end
    end
  end
end

local function redraw()
  wanted = wanted + 1
  os.queueEvent("projector_redraw")
end

---------------------------------------------------------------- panel

local FACING = { [0] = "north", "east", "south", "west" }
local MOVES = { north = { 0, 0, -1 }, south = { 0, 0, 1 }, west = { -1, 0, 0 }, east = { 1, 0, 0 }, up = { 0, 1, 0 }, down = { 0, -1, 0 } }

-- What the village turtle is up to, for the panel.
local function villageNote()
  local who = ("Village builder #%s: "):format(tostring(village.from))
  if village.stage == "build" and village.total then
    return who .. ("building, %d%%"):format(math.floor((village.step or 0) / village.total * 100))
  elseif village.stage == "clear" then return who .. "clearing the plot"
  elseif village.stage == "path" then return who .. "paving the street"
  elseif village.stage == "choose" then return who .. "getting materials"
  end
  return who .. (plan.fixed and "following" or "no GPS: move it into place")
end

-- What the panel shows: the current layer as a top-down map (north up) and
-- the blocks it needs.
local function model()
  local fx0, fz0, fx1, fz1 = footprint()
  local map = { w = fx1 - fx0 + 1, d = fz1 - fz0 + 1, cells = {}, below = {} }
  for row = 1, map.d do map.cells[row], map.below[row] = {}, {} end
  local function mark(t, b, value)
    local dx, dz = offset(b.x, b.z)
    t[state.z + dz - fz0 + 1][state.x + dx - fx0 + 1] = value
  end
  for _, b in ipairs(plan.layers[state.layer - 1] or {}) do mark(map.below, b, true) end
  for _, b in ipairs(plan.layers[state.layer]) do mark(map.cells, b, plan.mats[b.m]) end

  -- the list beside the map: this layer, the whole build, or what the
  -- builder turtles need now
  local page = state.page or "layer"
  local counts, title = {}, nil
  if page == "now" then
    title = "Turtles need now"
    -- an item needed, with the plan's colour for it when one of its blocks is that item
    local function matFor(item)
      for _, mat in ipairs(plan.mats) do
        if mat.block:gsub("%[.*$", "") == item then return mat end
      end
    end
    local list = state.build and builders:needs() or {}
    if not state.build then counts[1] = { text = "No build running.", colour = colors.gray } end
    if state.build and #list == 0 then counts[1] = { text = "Waiting for a builder.", colour = colors.gray } end
    for _, b in ipairs(list) do
      local doing = b.stage == "build" and "building" or b.stage == "clear" and "clearing" or b.note or b.stage or "starting"
      counts[#counts + 1] = { text = ("#%d %s"):format(b.builder, doing),
        colour = b.need and colors.orange or colors.lime }
      local items = {}
      for item, n in pairs(b.need or {}) do items[#items + 1] = { item = item, n = n } end
      table.sort(items, function(x, y) return x.n > y.n end)
      for _, it in ipairs(items) do
        counts[#counts + 1] = { mat = matFor(it.item), text = it.item:gsub("^.-:", ""), n = it.n }
      end
    end
  else
    local n, total = {}, 0
    local from = page == "build" and 1 or state.layer
    local to = page == "build" and plan.h or state.layer
    for y = from, to do
      for _, b in ipairs(plan.layers[y]) do n[b.m] = (n[b.m] or 0) + 1 end
    end
    for m, c in pairs(n) do counts[#counts + 1] = { mat = plan.mats[m], n = c }; total = total + c end
    table.sort(counts, function(a, b) return a.n > b.n end)
    title = page == "build" and ("Whole build: %d"):format(total) or ("Layer %d: %d"):format(state.layer, total)
  end

  local ids = planIds(state.plan)
  local index = 1
  for i, id in ipairs(ids) do if id == state.plan then index = i end end
  return {
    plan = plan, index = index, planCount = #ids, state = state, facing = FACING[state.turn % 4],
    status = status, note = note or (state.build and builders:note()) or (plan.village and villageNote()),
    map = map, counts = counts, building = state.build ~= nil, canBuild = not plan.village,
    countTitle = title, page = page,
  }
end

local function act(action)
  if not action then return end
  if action == "build" then
    -- the talking to the turtles happens in buildLoop, so the panel never waits
    if state.build then os.queueEvent(crew.STOP) else os.queueEvent("projector_build") end
    return
  end
  local moving = MOVES[action] or action == "turnLeft" or action == "turnRight" or action == "here"
  if plan.fixed and moving then
    note = "The village builder decides where this goes."
    os.queueEvent("projector_status")
    return
  end
  if state.build and (moving or action == "nextPlan" or action == "prevPlan") then
    note = "A builder turtle is building this: tap Stop first."
    os.queueEvent("projector_status")
    return
  end
  if MOVES[action] then
    local m = MOVES[action]
    state.x, state.y, state.z = state.x + m[1] * state.step, state.y + m[2] * state.step, state.z + m[3] * state.step
  elseif action == "turnLeft" or action == "turnRight" then
    state.turn = (state.turn + (action == "turnRight" and 1 or -1)) % 4
  elseif action == "step" then
    local i = 1
    for k, s in ipairs(STEPS) do if s == state.step then i = k end end
    state.step = STEPS[i % #STEPS + 1]
  elseif action == "layerUp" then
    state.layer = math.min(plan.h, state.layer + 1)
  elseif action == "layerDown" then
    state.layer = math.max(1, state.layer - 1)
  elseif action == "view" then
    local i = 1
    for k, v in ipairs(VIEWS) do if v == state.view then i = k end end
    state.view = VIEWS[i % #VIEWS + 1]
    -- layer view starts at the bottom, where you'd start building
    if state.view == "layer" then state.layer = 1 elseif state.view == "whole" then state.layer = plan.h end
  elseif action == "pageLayer" or action == "pageBuild" or action == "pageNow" then
    state.page = action:sub(5):lower()
  elseif action == "here" then
    placeHere()
  elseif action == "hide" then
    state.hidden = not state.hidden
  elseif action == "nextPlan" or action == "prevPlan" then
    local ids = planIds(state.plan)
    local index = 1
    for i, id in ipairs(ids) do if id == state.plan then index = i end end
    local step = action == "nextPlan" and 1 or -1
    -- skip plans that fail to load, but say why
    for _ = 1, #ids do
      index = (index - 1 + step) % #ids + 1
      local ok, err = usePlan(ids[index], true)
      if ok then break end
      loadNote = "Skipped " .. err
    end
  else
    return
  end
  save()
  redraw()
end

local KEYS = {
  [keys.up] = "north", [keys.down] = "south", [keys.left] = "west", [keys.right] = "east",
  [keys.pageUp] = "up", [keys.pageDown] = "down", [keys.q] = "turnLeft", [keys.e] = "turnRight",
  [keys.leftBracket] = "layerDown", [keys.rightBracket] = "layerUp", [keys.v] = "view",
  [keys.s] = "step", [keys.h] = "hide", [keys.n] = "nextPlan", [keys.p] = "prevPlan", [keys.home] = "here",
  [keys.b] = "build",
}

-- Events that change what the panel shows; projector replies and timers don't.
local PANEL_EVENTS = {
  projector_status = true, monitor_touch = true, mouse_click = true, key = true,
  peripheral = true, peripheral_detach = true, monitor_resize = true, term_resize = true,
}

local function panelLoop()
  local panel = ui.new()

  -- With the panel on a monitor, this computer's screen lists the keys.
  local function announce()
    local monitorName = panel.display.name
    if not monitorName then return end
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    print(("Projecting plans. Controls are on monitor %s."):format(monitorName))
    print("Keys here: arrows move, PgUp/PgDn up and down, Q/E turn, [ ] layer, V view, N/P plan, H hide, B build.")
  end

  local function show()
    local ok, err = pcall(panel.draw, panel, model())
    if not ok and panel.display.name then print("Display error: " .. tostring(err)) end
  end

  announce()
  show()
  while true do
    local ev = { os.pullEvent() }
    local name = ev[1]
    if PANEL_EVENTS[name] then
      local x, y, drag = panel.display:clicked(ev)
      if x and not drag then
        act(panel:click(x, y))
      elseif name == "key" then
        act(KEYS[ev[2]])
      elseif name == "peripheral" or name == "peripheral_detach" then
        -- also fired by turtles driving past: only acts if the monitor came or went
        if panel.display:refresh() then announce() end
      end
      -- monitor_resize / term_resize: the next frame is made at the new size
      show()
    end
  end
end

---------------------------------------------------------------- village turtle

local function openWireless() return net.open() end

-- A message from a village turtle: a whole building (when it picks a new
-- one, or when asked) or how far along it is.
local function onVillage(from, msg)
  if type(msg) ~= "table" then return end
  if msg.type == "plan" and type(msg.blocks) == "table" and #msg.blocks > 0 then
    local same = village and village.key == msg.key and village.from == from
    village = {
      from = from, key = msg.key, name = msg.name, world = msg.world, blocks = msg.blocks,
      stage = same and village.stage or "choose", y = same and village.y or nil,
      step = same and village.step or nil, total = same and village.total or nil,
    }
    writeFile(VILLAGE_FILE, village)
    if state.plan == "village" and not (same and plan.village) then
      local ok, err = usePlan("village", true)
      if not ok then loadNote = err end
      save()
      redraw()
    end
  elseif msg.type == "progress" and village and msg.key == village.key and from == village.from then
    village.stage, village.y, village.step, village.total = msg.stage, msg.y, msg.step, msg.total
    if state.plan == "village" and plan.village then
      local layer = villageLayer()
      if state.view == "layer" and layer and layer ~= state.layer then
        state.layer = layer
        save()
        redraw()
      end
      os.queueEvent("projector_status")
    end
  end
end

-- Listen for village turtles the whole time, so the village plan stays up
-- to date even while another plan is showing.
local function villageLoop()
  if not openWireless() then
    while true do sleep(3600) end
  end
  rednet.broadcast({ type = "request" }, PLAN_PROTOCOL)
  while true do
    local from, msg = rednet.receive(PLAN_PROTOCOL)
    onVillage(from, msg)
  end
end

-- 'projector village' before any village turtle has been heard: ask, and wait.
local function waitForVillage()
  if not openWireless() then
    error("'projector village' needs a wireless or ender modem on this computer to hear the turtle.", 0)
  end
  print("Waiting to hear from a village builder. It needs a wireless")
  print("modem too. Hold Ctrl+T to stop waiting.")
  while not village do
    rednet.broadcast({ type = "request" }, PLAN_PROTOCOL)
    local from, msg = rednet.receive(PLAN_PROTOCOL, 10)
    if from then onVillage(from, msg) end
  end
  print("Heard from it: " .. village.name .. ".")
end

---------------------------------------------------------------- builder turtles

local buildOnStart = false -- 'projector build': build once everything's running

builders = crew.new({
  -- the plan where it's shown, in world coordinates
  job = function()
    local mats, blocks = plans.world(plan, state)
    return { id = state.plan, name = plan.name, mats = mats, blocks = blocks, area = plans.area(plan, state), clear = plan.clear }
  end,
  build = state.build,
  save = function(build)
    state.build = build
    -- done or stopped: the copy of the plan it was built from goes
    if not build and state.buildPlan then
      if fs.exists(state.buildPlan) then fs.delete(state.buildPlan) end
      state.buildPlan = nil
    end
    save()
  end,
  tell = tell,
  -- in Layer view, follow the lowest layer being built
  changed = function()
    local low = builders:lowY()
    if state.view == "layer" and low then
      local layer = math.max(1, math.min(plan.h, low - state.y + 1))
      if layer ~= state.layer then
        state.layer = layer
        save()
        redraw()
      end
    end
    os.queueEvent("projector_status")
  end,
  finished = function(text) if report then report.log(text) end end,
})
state.build = builders.build

-- Starts and stops builds asked for on the panel, hears progress, and hands
-- out strips nobody has taken yet.
local function buildLoop()
  if buildOnStart and not state.build then os.queueEvent("projector_build") end
  builders:run()
end

---------------------------------------------------------------- instabuild

-- In creative, a command computer running 'instabuild serve' places the
-- plan where it's shown in one go. Build goes to it when there is one
-- ('set projector.instabuild false' skips it), else to the builder turtles.
local insta = net.peer(INSTA_PROTOCOL, { open = "any", retry = INSTA_RETRY })

local function instaLoop()
  while true do
    local ev, _, msg, protocol = os.pullEvent()
    if ev == "projector_build" and not state.build then
      if plan.village or settings.get("projector.instabuild") == false then
        requestBuild()
      else
        local mats, blocks = plans.world(plan, state)
        local reply, why = insta:ask({ type = "build", name = plan.name, mats = mats, blocks = blocks,
          area = plans.area(plan, state) }, INSTA_WAIT)
        if why == "none" or why == "no modem" then
          requestBuild()
        elseif not reply then
          tell("The instabuild computer didn't answer.")
        elseif reply.ok then
          tell(("Instabuild is placing %s..."):format(plan.name))
        else
          tell("Instabuild: " .. tostring(reply.why))
        end
      end
    elseif ev == "rednet_message" and protocol == INSTA_PROTOCOL and type(msg) == "table" and msg.type == "done" then
      tell(tostring(msg.text))
      if report then report.log(tostring(msg.text)) end
    end
  end
end

---------------------------------------------------------------- commands

local function findProjector()
  projector = peripheral.find("spatial_projector")
  if not projector then
    error("No Spatial Projector found. Place one next to this computer or connect it with a wired modem.", 0)
  end
  local stats = projector.stats()
  origin = { x = stats.sourceX, y = stats.sourceY, z = stats.sourceZ }
  local limits = projector.getLimits()
  -- room for the outline and layer guide
  budget = math.min(MAX_SHAPES, limits.maxObjectsPerProjector) - 2
end

local function listPlans()
  print("Plans:")
  for _, id in ipairs(planIds()) do
    local p, err = loadPlan(id)
    if p then
      print(("  %-14s %s, %d x %d x %d"):format(id, p.name, p.w, p.l, p.h))
    else
      printError("  " .. err)
    end
  end
  print(("Add your own as %s/<name>.json or .lua (see lib/plan.lua),"):format(plans.DIR))
  print("or get one from the website: install plan <name>")
end

local function checkPlan(id)
  local p, err = loadPlan(id)
  if not p then error(err, 0) end
  print(("%s: %d wide, %d deep, %d high, %d blocks"):format(p.name, p.w, p.l, p.h, #p.blocks))
  print(("Shows as %d shapes (whole view)."):format(#mergeBoxes(p.blocks, true)))
  local mats = {}
  for _, m in ipairs(p.mats) do mats[#mats + 1] = m end
  table.sort(mats, function(a, b) return a.total > b.total end)
  for _, m in ipairs(mats) do print(("  %s %-28s %d"):format(m.char, m.block, m.total)) end
end

local function main()
  local cmd = args[1]
  if cmd == "list" then return listPlans() end
  if cmd == "check" then
    if not args[2] then error("Usage: projector check <plan>", 0) end
    return checkPlan(args[2])
  end

  findProjector()
  if cmd == "clear" then
    projector.clear()
    state.hidden = true
    if state.plan then save() end
    print("Projection cleared. Run 'projector' to show it again.")
    return
  end

  state.turn, state.step = state.turn or 0, state.step or 1
  state.view = state.view or "whole"
  if cmd == "village" and not village then waitForVillage() end
  if cmd == "build" then
    -- build the plan that's showing, once everything's running (buildLoop)
    cmd, buildOnStart = nil, true
  end
  if cmd then
    local ok, err = usePlan(cmd, state.plan ~= nil)
    if not ok then error(err, 0) end
    state.hidden = false
  else
    local layer = state.layer
    local ok = state.plan and usePlan(state.plan, true)
    if ok then
      state.layer = math.max(1, math.min(plan.h, layer or plan.h))
    else
      local first = plans.ids()[1]
      if not first then error(("No plans in %s yet. Get one with: install plan cottage"):format(plans.DIR), 0) end
      local okFirst, err = usePlan(first, false)
      if not okFirst then error(err, 0) end
    end
  end
  save()

  -- start from a clean projector: older shapes may be from another program or run
  projector.clear()
  if report then report.init("blueprint projector") end
  redraw()
  parallel.waitForAny(panelLoop, drawLoop, villageLoop, buildLoop, instaLoop,
    report and report.loop or function() while true do sleep(3600) end end)
end

local ok, err = (errlog and errlog.pcall or pcall)(main)
if not ok then
  if err == "Terminated" then return end
  if report and report.set then pcall(report.set, "error", tostring(err)) end
  printError(err)
end
