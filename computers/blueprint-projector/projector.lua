-- Blueprint projector: loads a building plan and projects it into the world
-- with a CC: Spatial Projector, so anyone wearing bound Spatial Goggles sees
-- the building before it's built. A monitor (or this computer's screen) moves
-- and turns it, and steps through its layers so you can build from it block
-- by block. Plans are built in (sample_plans.lua) or files in /plans/.
--
-- Usage:
--   projector                 show the last plan (startup runs this)
--   projector <plan>          show a plan: cottage, /plans/<plan>.lua, or a file path
--   projector village         show what a village turtle is building, where it's building it
--   projector build           have a builder turtle (computers/builder-turtle) build the plan where it's shown
--   projector list            list the plans
--   projector check <plan>    load a plan and print its size and blocks
--   projector clear           remove the projection (stays hidden after a reboot)
local ui = require("ui")
local samples = require("sample_plans")
local net = require("lib.net") -- rednet requests and answers
local files = require("lib.files") -- crash-safe save files
local report = fs.exists("lib/report.lua") and require("lib.report")
local errlog = fs.exists("lib/errlog.lua") and require("lib.errlog") -- saves errors to /errors.log

local STATE_FILE = "/.projector_state"
local PLAN_DIR = "/plans"
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
local BUILD_PROTOCOL = "projector_build" -- rednet protocol builder turtles take buildings on
local BUILD_WAIT = 5 -- seconds to wait for each builder turtle to answer
local MAX_BUILDERS = 4 -- most builder turtles one building is split between
local MIN_STRIP = 3 -- narrowest strip of a building (blocks) one turtle is given
local RETRY_EVERY = 30 -- seconds between offers of strips nobody has taken yet to builders that are free

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
  { "copper", 0xc0704c }, { "lantern", 0xf2b84a }, { "torch", 0xf2c84a }, { "glowstone", 0xf8d58a },
  { "log", 0x6b5131 }, { "wood", 0x6b5131 }, { "planks", 0xb8945f },
}
local FALLBACK_COLORS = { 0xff6b6b, 0xffd166, 0x06d6a0, 0x4cc9f0, 0xb388eb, 0xf78c6b, 0x83e377, 0xf15bb5 }

local function colorFor(block)
  local words = "_" .. block:gsub("^.-:", "") .. "_"
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

-- Turn a plan table (layers + legend, or a block list) into one shape:
-- blocks { x, y, z, m } from 0 with m indexing mats, sorted bottom up.
local function normalize(raw, id)
  if type(raw) ~= "table" then error("the plan file must return a table", 0) end
  local mats, byKey, blocks, usedChars = {}, {}, {}, {}

  local function material(key, def, char)
    if byKey[key] then return byKey[key] end
    local block, color
    if type(def) == "string" then
      block = def
    elseif type(def) == "table" then
      block, color = def.block or def[1], def.color or def[2]
    end
    if type(block) ~= "string" then error(("the legend entry for '%s' needs a block name"):format(key), 0) end
    color = color or colorFor(block)
    mats[#mats + 1] = { block = block, char = char, color = color, term = termColor(color), light = isLight(color), total = 0 }
    byKey[key] = #mats
    if char then usedChars[char] = true end
    return #mats
  end

  local function add(x, y, z, m) blocks[#blocks + 1] = { x = x, y = y, z = z, m = m } end

  if raw.layers then
    local legend = raw.legend or {}
    for y, layer in ipairs(raw.layers) do
      if type(layer) ~= "table" then error(("layer %d should be a list of rows"):format(y), 0) end
      for z, row in ipairs(layer) do
        for x = 1, #row do
          local ch = row:sub(x, x)
          if ch ~= "." and ch ~= " " then
            if legend[ch] == nil then
              error(("layer %d row %d: '%s' isn't in the legend"):format(y, z, ch), 0)
            end
            add(x - 1, y - 1, z - 1, material(ch, legend[ch], ch))
          end
        end
      end
    end
  elseif raw.blocks then
    for i, b in ipairs(raw.blocks) do
      local x, y, z, block = b.x or b[1], b.y or b[2], b.z or b[3], b.block or b[4]
      if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or type(block) ~= "string" then
        error(("block %d should look like { x, y, z, \"minecraft:stone\" }"):format(i), 0)
      end
      add(math.floor(x), math.floor(y), math.floor(z), material(block, block))
    end
  else
    error("the plan needs either layers or blocks", 0)
  end
  if #blocks == 0 then error("the plan has no blocks", 0) end

  -- a map letter for materials from a block list: initial, then lower case, then anything free
  for _, m in ipairs(mats) do
    if not m.char then
      local initial = m.block:gsub("^.-:", ""):sub(1, 1)
      for _, ch in ipairs({ initial:upper(), initial:lower(), "#", "%", "&", "@", "$", "+", "=" }) do
        if not usedChars[ch] then m.char = ch break end
      end
      m.char = m.char or "?"
      usedChars[m.char] = true
    end
  end

  -- layers can be written in any order, and block lists can start anywhere
  local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
  for _, b in ipairs(blocks) do
    x0, y0, z0 = math.min(x0, b.x), math.min(y0, b.y), math.min(z0, b.z)
    x1, y1, z1 = math.max(x1, b.x), math.max(y1, b.y), math.max(z1, b.z)
  end
  local seen, unique = {}, {}
  for _, b in ipairs(blocks) do
    b.x, b.y, b.z = b.x - x0, b.y - y0, b.z - z0
    local k = b.x .. "," .. b.y .. "," .. b.z
    if seen[k] then unique[seen[k]].m = b.m else unique[#unique + 1] = b; seen[k] = #unique end
  end
  blocks = unique
  for _, b in ipairs(blocks) do mats[b.m].total = mats[b.m].total + 1 end
  table.sort(blocks, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.z ~= b.z then return a.z < b.z end
    return a.x < b.x
  end)

  local plan = {
    id = id, name = raw.name or id, mats = mats, blocks = blocks, layers = {},
    w = x1 - x0 + 1, h = y1 - y0 + 1, l = z1 - z0 + 1, cache = {},
  }
  for y = 1, plan.h do plan.layers[y] = {} end
  for _, b in ipairs(blocks) do table.insert(plan.layers[b.y + 1], b) end
  -- turning spins the plan about this block
  plan.cx, plan.cz = math.floor((plan.w - 1) / 2), math.floor((plan.l - 1) / 2)
  return plan
end

local function planPath(id)
  if fs.exists(id) and not fs.isDir(id) then return id end
  local path = fs.combine(PLAN_DIR, id .. ".lua")
  if fs.exists(path) then return path end
end

local function loadPlan(id)
  local raw
  local path = planPath(id)
  if id == "village" then
    if not village then return nil, "No village builder heard yet." end
    local ok, p = pcall(normalize, { name = village.name, blocks = village.blocks }, id)
    if not ok then return nil, "village: " .. p end
    local x0, y0, z0 = math.huge, math.huge, math.huge
    for _, b in ipairs(village.blocks) do x0, y0, z0 = math.min(x0, b[1]), math.min(y0, b[2]), math.min(z0, b[3]) end
    p.village, p.fixed, p.world0 = true, village.world, { x = x0, y = y0, z = z0 }
    return p
  elseif path then
    local fn, err = loadfile(path, nil, setmetatable({}, { __index = _G }))
    if not fn then return nil, err end
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    raw = result
  else
    for _, p in ipairs(samples) do
      if p.id == id then raw = p end
    end
    if not raw then return nil, ("No plan called '%s'. Try 'projector list'."):format(id) end
  end
  local ok, plan = pcall(normalize, raw, id)
  if not ok then return nil, ("%s: %s"):format(id, plan) end
  return plan
end

-- Every plan id: built-ins first, then /plans/ (a file there replaces a
-- built-in of the same name), then extra, a file path that was asked for.
local function planIds(extra)
  local ids, seen = {}, {}
  local function add(id)
    if id and not seen[id] then ids[#ids + 1] = id; seen[id] = true end
  end
  for _, p in ipairs(samples) do add(p.id) end
  if village then add("village") end
  if fs.isDir(PLAN_DIR) then
    local names = fs.list(PLAN_DIR)
    table.sort(names)
    for _, f in ipairs(names) do
      if f:sub(-4) == ".lua" then add(f:sub(1, -5)) end
    end
  end
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

-- Plan block (x, z) as an offset from the anchor, turned clockwise (seen
-- from above) a quarter turn per state.turn about the plan's centre.
local function offset(x, z)
  local dx, dz = x - plan.cx, z - plan.cz
  for _ = 1, state.turn % 4 do dx, dz = -dz, dx end
  return dx, dz
end

-- World block range the building covers on the ground.
local function footprint()
  local ax, az = offset(0, 0)
  local bx, bz = offset(plan.w - 1, plan.l - 1)
  return state.x + math.min(ax, bx), state.z + math.min(az, bz), state.x + math.max(ax, bx), state.z + math.max(az, bz)
end

-- state.build, while builder turtles are building the plan: { key, name, n
-- (strips), stopping, parts = { { key, builder, finished, stopped, stage,
-- done, total, y, skipped, note, cleared, toClear } } }, one part per strip,
-- filled in from its turtle's progress messages.
local function save()
  writeFile(STATE_FILE, {
    plan = state.plan, x = state.x, y = state.y, z = state.z, turn = state.turn,
    view = state.view, layer = state.layer, step = state.step, hidden = state.hidden, build = state.build,
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
  local p, err = loadPlan(id)
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

-- What the builder turtles are up to, for the panel.
local function buildNote()
  local parts = state.build.parts or { state.build }
  if #parts > 1 then
    local done, total, working, waiting = 0, 0, 0, 0
    for _, p in ipairs(parts) do
      total = total + (p.total or 0)
      if p.finished then
        done = done + (p.total or 0)
      elseif p.builder then
        working = working + 1
        done = done + (p.stage == "build" and p.done or 0)
      else
        waiting = waiting + 1
      end
    end
    local text = ("%d builder%s: %d of %d (%d%%)"):format(working, working == 1 and "" or "s", done, total,
      total > 0 and math.floor(done / total * 100) or 0)
    if state.build.stopping then text = text .. ", stopping" end
    if waiting > 0 then text = text .. (", %d strips waiting"):format(waiting) end
    return text
  end
  local b = parts[1]
  local who = ("Builder #%s: "):format(tostring(b.builder))
  if b.stage == "build" and b.total and b.total > 0 then
    return who .. ("building, %d of %d (%d%%)"):format(b.done or 0, b.total, math.floor((b.done or 0) / b.total * 100))
  elseif b.stage == "clear" and b.toClear and b.toClear > 0 then
    return who .. ("clearing the plot, %d%%"):format(math.floor((b.cleared or 0) / b.toClear * 100))
  elseif b.stage == "waiting" or b.stage == "restocking" then
    return who .. (b.note or "fetching blocks")
  end
  return who .. "starting"
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

  local counts, n = {}, {}
  local from = state.view == "whole" and 1 or state.layer
  for y = from, state.layer do
    for _, b in ipairs(plan.layers[y]) do n[b.m] = (n[b.m] or 0) + 1 end
  end
  local total = 0
  for m, c in pairs(n) do counts[#counts + 1] = { mat = plan.mats[m], n = c }; total = total + c end
  table.sort(counts, function(a, b) return a.n > b.n end)

  local ids = planIds(state.plan)
  local index = 1
  for i, id in ipairs(ids) do if id == state.plan then index = i end end
  return {
    plan = plan, index = index, planCount = #ids, state = state, facing = FACING[state.turn % 4],
    status = status, note = note or (state.build and buildNote()) or (plan.village and villageNote()),
    map = map, counts = counts, building = state.build ~= nil, canBuild = not plan.village,
    countTitle = (from == state.layer and "Layer %d: %d" or "Layers 1-%d: %d"):format(state.layer, total),
  }
end

local function act(action)
  if not action then return end
  if action == "build" then
    -- the talking to the turtle happens in buildLoop, so the panel never waits
    os.queueEvent(state.build and "projector_build_stop" or "projector_build_start")
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

---------------------------------------------------------------- builder turtle

local buildOnStart = false -- 'projector build': build once everything's running

local function tell(text)
  note = text
  os.queueEvent("projector_status")
end

-- The plan as it's shown: every block in world coordinates, and the block
-- names its materials stand for.
local function worldPlan()
  local mats, blocks = {}, {}
  for i, m in ipairs(plan.mats) do mats[i] = m.block end
  for i, b in ipairs(plan.blocks) do
    local dx, dz = offset(b.x, b.z)
    blocks[i] = { state.x + dx, state.y + b.y, state.z + dz, b.m }
  end
  return mats, blocks
end

-- With several builder turtles free, the building is split into side-by-side
-- strips across its longer side, one per turtle. Each turtle clears and
-- builds only its strip (bottom layer up, as on its own), and crosses over
-- at a height of its own. A strip nobody could take yet goes to the next
-- turtle that's free: one that finishes its own strip, or a new one.

-- The building's box, in world coordinates.
local function buildArea()
  local fx0, fz0, fx1, fz1 = footprint()
  return { x0 = fx0, z0 = fz0, x1 = fx1, z1 = fz1, y0 = state.y, y1 = state.y + plan.h - 1 }
end

-- Strip i of n: the area cut across its longer side.
local function stripBox(i, n)
  local a = buildArea()
  local alongX = a.x1 - a.x0 >= a.z1 - a.z0
  local lo, hi = alongX and a.x0 or a.z0, alongX and a.x1 or a.z1
  local len = hi - lo + 1
  local s0 = lo + math.floor((i - 1) * len / n)
  local s1 = lo + math.floor(i * len / n) - 1
  if alongX then return { x0 = s0, x1 = s1, z0 = a.z0, z1 = a.z1 } end
  return { x0 = a.x0, x1 = a.x1, z0 = s0, z1 = s1 }
end

-- How many strips for this many free turtles: no more than MAX_BUILDERS,
-- and none narrower than MIN_STRIP.
local function stripCount(free)
  local a = buildArea()
  local len = math.max(a.x1 - a.x0, a.z1 - a.z0) + 1
  return math.max(1, math.min(free, MAX_BUILDERS, math.floor(len / MIN_STRIP)))
end

-- The blocks of the plan in a strip.
local function stripBlocks(part)
  local _, blocks = worldPlan()
  local mine = {}
  for _, b in ipairs(blocks) do
    if b[1] >= part.x0 and b[1] <= part.x1 and b[3] >= part.z0 and b[3] <= part.z1 then mine[#mine + 1] = b end
  end
  return mine
end

-- A build saved by an older projector (one turtle, no strips) as one strip.
local function upgradeBuild()
  local b = state.build
  if b and not b.parts then
    state.build = { key = b.key, name = b.name, n = 1, parts = { {
      key = b.key, builder = b.builder, stage = b.stage, done = b.done, total = b.total, y = b.y,
      skipped = b.skipped, note = b.note, cleared = b.cleared, toClear = b.toClear } } }
  end
end

local function partFor(key)
  for i, p in ipairs(state.build and state.build.parts or {}) do
    if p.key == key then return p, i end
  end
end

local function pending()
  local n = 0
  for _, p in ipairs(state.build.parts) do
    if not p.builder and not p.finished then n = n + 1 end
  end
  return n
end

-- Every strip is finished (built, stopped, or given up on): say how it went.
local function finishBuild()
  local b = state.build
  local skipped, stopped, builders = 0, false, {}
  for _, p in ipairs(b.parts) do
    skipped = skipped + (p.skipped or 0)
    stopped = stopped or p.stopped
    if p.builder then builders[#builders + 1] = "#" .. p.builder end
  end
  local who = #builders == 1 and ("Builder " .. builders[1]) or ("Builders " .. table.concat(builders, ", "))
  state.build = nil
  if stopped then
    note = ("%s stopped. Tap Build to start again."):format(who)
  elseif skipped > 0 then
    note = ("%s built it, but skipped %d blocks."):format(who, skipped)
  else
    note = ("%s built it."):format(who)
  end
  if report then report.log(note) end
end

local function checkFinished()
  for _, p in ipairs(state.build.parts) do
    if not p.finished then return end
  end
  finishBuild()
end

-- Progress from a builder turtle building a strip of this projector's plan:
-- keep the panel up to date, and in Layer view follow the lowest layer
-- being built.
local function onBuilder(from, msg)
  if type(msg) ~= "table" or msg.type ~= "progress" or not state.build then return end
  local p = partFor(msg.key)
  if not p then return end
  p.stage, p.done, p.total, p.y, p.skipped, p.note = msg.stage, msg.done, msg.total, msg.y, msg.skipped, msg.note
  p.cleared, p.toClear, p.builder = msg.cleared, msg.toClear, from
  if msg.stage == "done" or msg.stage == "stopped" then
    p.finished, p.stopped = true, msg.stage == "stopped"
    -- free again: it can take a strip nobody has yet
    if not p.stopped and not state.build.stopping and pending() > 0 then os.queueEvent("projector_build_more", from) end
    checkFinished()
  elseif state.view == "layer" then
    local low
    for _, q in ipairs(state.build.parts) do
      if q.y and not q.finished and q.stage == "build" then low = math.min(low or q.y, q.y) end
    end
    local layer = low and math.max(1, math.min(plan.h, low - state.y + 1))
    if layer and layer ~= state.layer then
      state.layer = layer
      redraw()
    end
  end
  save()
  os.queueEvent("projector_status")
end

-- The builder turtles that answer and aren't building anything: ids.
local function freeBuilders()
  local ids = { rednet.lookup(BUILD_PROTOCOL) }
  if #ids == 0 then return {}, 0 end
  local probe = ("free-%d"):format(os.epoch("utc"))
  for _, id in ipairs(ids) do rednet.send(id, { type = "status", id = 0, key = probe }, BUILD_PROTOCOL) end
  local free, seen = {}, {}
  local deadline = os.clock() + BUILD_WAIT
  while os.clock() < deadline and #free < #ids do
    local from, msg = rednet.receive(BUILD_PROTOCOL, math.max(0.1, deadline - os.clock()))
    if from and type(msg) == "table" and msg.type == "idle" and msg.key == probe and not seen[from] then
      seen[from] = true
      free[#free + 1] = from
    elseif from then
      onBuilder(from, msg)
    end
  end
  table.sort(free)
  return free, #ids
end

-- Offer strip i to builder id. True if it took it, or false and why not.
local function offer(i, id)
  local b = state.build
  local p = b.parts[i]
  local mats = worldPlan()
  local part = stripBox(i, b.n)
  local blocks = stripBlocks(part)
  -- the turtle answers accepted, busy or refused, with the strip's key
  local msg = net.ask(id, BUILD_PROTOCOL, { type = "build", key = p.key,
    name = b.n > 1 and ("%s (strip %d of %d)"):format(b.name, i, b.n) or b.name,
    mats = mats, blocks = blocks, area = buildArea(), part = b.n > 1 and part or nil, lane = i - 1 },
    { wait = BUILD_WAIT, match = function(reply) return reply.key == p.key and reply.type ~= "progress" end,
      other = onBuilder })
  if not msg then return false, ("Builder #%d didn't answer in time."):format(id) end
  if msg.type == "accepted" then
    p.builder, p.stage, p.done, p.total = id, "clear", 0, #blocks
    return true
  end
  return false, ("Builder #%d %s"):format(id, msg.type == "busy" and ("is busy with " .. tostring(msg.name))
    or ("refused: " .. tostring(msg.why)))
end

-- Give the strips nobody has yet to these free builders, one each.
-- Returns how many were taken, and why the last one wasn't.
local function handOut(ids)
  local taken, why, k = 0, nil, 1
  for i, p in ipairs(state.build.parts) do
    if not p.builder and not p.finished then
      while k <= #ids do
        local id = ids[k]
        k = k + 1
        local ok, err = offer(i, id)
        if ok then
          taken = taken + 1
          break
        end
        why = err
      end
    end
  end
  return taken, why
end

-- Split the plan between the builder turtles that are free.
local function startBuild()
  if plan.village then return tell("The village builder builds this one itself.") end
  if not openWireless() then return tell("Needs a wireless modem to reach a builder turtle.") end
  tell("Looking for free builder turtles...")
  local free, all = freeBuilders()
  if all == 0 then return tell("No builder turtle answered: is one running 'builder' nearby?") end
  if #free == 0 then return tell(("All %d builder turtles are busy."):format(all)) end
  local n = stripCount(#free)
  local key = ("%d-%s"):format(os.epoch("utc"), state.plan)
  state.build = { key = key, name = plan.name, n = n, parts = {} }
  for i = 1, n do
    local empty = #stripBlocks(stripBox(i, n)) == 0
    -- a strip with nothing in it needs no turtle (the plan has a gap there)
    state.build.parts[i] = { key = ("%s/%d"):format(key, i), total = 0, finished = empty }
  end
  tell(n > 1 and ("Sending %d blocks to %d builder turtles..."):format(#plan.blocks, n)
    or ("Sending %d blocks to a builder turtle..."):format(#plan.blocks))
  local taken, why = handOut(free)
  if taken == 0 then
    state.build = nil
    return tell(why or "No builder turtle took it.")
  end
  save()
  local left = pending()
  if n == 1 then
    tell(("Builder #%d is building %s."):format(state.build.parts[1].builder, plan.name))
  else
    tell(("%d builder turtles are building %s%s."):format(taken, plan.name,
      left > 0 and (", %d strips wait for the next free one"):format(left) or ""))
  end
end

local function stopBuild()
  local b = state.build
  if b.stopping then
    -- asked twice: a turtle that never answers (broken, unloaded) is given up on
    for _, p in ipairs(b.parts) do
      if not p.finished then p.finished, p.stopped = true, true end
    end
    finishBuild()
    save()
    return tell(note)
  end
  b.stopping = true
  local asked = 0
  for _, p in ipairs(b.parts) do
    if p.builder and not p.finished then
      if openWireless() then rednet.send(p.builder, { type = "stop", id = 0, key = p.key }, BUILD_PROTOCOL) end
      asked = asked + 1
    elseif not p.finished then
      p.finished, p.stopped = true, true -- nobody had started it
    end
  end
  save()
  if asked == 0 then
    finishBuild()
    save()
    return tell(note)
  end
  tell(asked == 1 and "Asked the builder to stop..." or ("Asked %d builders to stop..."):format(asked))
end

-- Starts and stops builds asked for on the panel, hears progress, and hands
-- out strips nobody has taken yet.
local function buildLoop()
  upgradeBuild()
  -- after a restart, ask the turtles where they've got to
  if state.build and openWireless() then
    for _, p in ipairs(state.build.parts) do
      if p.builder and not p.finished then
        rednet.send(p.builder, { type = "status", id = 0, key = p.key }, BUILD_PROTOCOL)
      end
    end
  elseif buildOnStart then
    startBuild()
  end
  local retry = os.startTimer(RETRY_EVERY)
  while true do
    local ev = { os.pullEvent() }
    if ev[1] == "projector_build_start" and not state.build then
      startBuild()
    elseif ev[1] == "projector_build_stop" and state.build then
      stopBuild()
    elseif ev[1] == "rednet_message" and ev[4] == BUILD_PROTOCOL then
      onBuilder(ev[2], ev[3])
    elseif ev[1] == "projector_build_more" and state.build and not state.build.stopping and pending() > 0 then
      if handOut({ ev[2] }) > 0 then save() os.queueEvent("projector_status") end
    elseif ev[1] == "timer" and ev[2] == retry then
      -- strips still waiting: offer them to any builder that's free now
      if state.build and not state.build.stopping and pending() > 0 and openWireless() then
        local free = freeBuilders()
        if #free > 0 and handOut(free) > 0 then save() os.queueEvent("projector_status") end
      end
      retry = os.startTimer(RETRY_EVERY)
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
  print(("Add your own as %s/<name>.lua (see sample_plans.lua)."):format(PLAN_DIR))
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
      local okFirst, err = usePlan(samples[1].id, false)
      if not okFirst then error(err, 0) end
    end
  end
  save()

  -- start from a clean projector: older shapes may be from another program or run
  projector.clear()
  if report then report.init("blueprint projector") end
  redraw()
  parallel.waitForAny(panelLoop, drawLoop, villageLoop, buildLoop,
    report and report.loop or function() while true do sleep(3600) end end)
end

local ok, err = (errlog and errlog.pcall or pcall)(main)
if not ok then
  if err == "Terminated" then return end
  if report and report.set then pcall(report.set, "error", tostring(err)) end
  printError(err)
end
