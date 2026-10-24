-- Building blueprints for the village turtle. Each one is generated from the
-- theme's style and returns a list of blocks named by palette role ("wall",
-- "roofStair", ...); village_themes.lua turns roles into real block names.
--
-- Blueprint frame: x runs across the front (0..w-1), z from the front wall (0)
-- to the back, y up from the floor (0). The door is in the front wall and the
-- front faces -z. Headings in this frame: 0 = +z (into the building),
-- 1 = +x, 2 = -z (out of the front), 3 = -x.
--
-- Block fields: x, y, z, m (role), f (heading for stairs and beds: stairs
-- climb towards f, a bed's head points towards f) and fwd (doors: placed
-- forwards from the cell behind, facing f, instead of downwards from above).
local B = {}

local function shape()
  local cells = {}
  local s = {}
  local function key(x, y, z) return x .. "," .. y .. "," .. z end
  function s.set(x, y, z, m, f, fwd) cells[key(x, y, z)] = { x = x, y = y, z = z, m = m, f = f, fwd = fwd } end
  function s.clear(x, y, z) cells[key(x, y, z)] = nil end
  function s.get(x, y, z) return cells[key(x, y, z)] end
  -- Build order: bottom layer first. Within a layer rows snake back and forth
  -- (alternating direction each layer) so each block is next to the last.
  -- Doors go last in their layer: the turtle steps down inside to place them.
  function s.list()
    local list = {}
    for _, c in pairs(cells) do list[#list + 1] = c end
    table.sort(list, function(a, b)
      if a.y ~= b.y then return a.y < b.y end
      if (a.fwd or false) ~= (b.fwd or false) then return not a.fwd end
      local up = a.y % 2 == 0
      if a.z ~= b.z then
        if up then return a.z < b.z end
        return a.z > b.z
      end
      if (a.z + a.y) % 2 == 0 then return a.x < b.x end
      return a.x > b.x
    end)
    return list
  end
  return s
end

---------------------------------------------------------------- roofs

-- Pitched roof with the ridge running front to back. rise = blocks up per
-- block in; 2 makes the steep Nordic roofs. Fills the gable ends with wall.
local function gableRoof(s, w, l, H, o, rise)
  local xl, xr, y = -o, w - 1 + o, H + 1
  local top = H
  while xl <= xr do
    for z = -o, l - 1 + o do
      if xl == xr then
        s.set(xl, y, z, "roofSlab")
        top = math.max(top, y)
      else
        for r = 0, rise - 2 do
          s.set(xl, y + r, z, "roofBlock")
          s.set(xr, y + r, z, "roofBlock")
        end
        s.set(xl, y + rise - 1, z, "roofStair", 1)
        s.set(xr, y + rise - 1, z, "roofStair", 3)
        top = math.max(top, y + rise - 1)
      end
    end
    for x = math.max(xl + 1, 0), math.min(xr - 1, w - 1) do
      for r = 0, rise - 1 do
        s.set(x, y + r, 0, "wall")
        s.set(x, y + r, l - 1, "wall")
      end
    end
    xl, xr, y = xl + 1, xr - 1, y + rise
  end
  return top
end

-- Hipped roof sloping on all four sides (Japanese style). upturn adds a slab
-- on each lowest corner so the eaves curl up.
local function hipRoof(s, x0, z0, x1, z1, y, upturn)
  local first = true
  while x0 <= x1 and z0 <= z1 do
    if x1 - x0 <= 1 or z1 - z0 <= 1 then
      for x = x0, x1 do for z = z0, z1 do s.set(x, y, z, "roofSlab") end end
      return y
    end
    for x = x0 + 1, x1 - 1 do
      s.set(x, y, z0, "roofStair", 0)
      s.set(x, y, z1, "roofStair", 2)
    end
    for z = z0 + 1, z1 - 1 do
      s.set(x0, y, z, "roofStair", 1)
      s.set(x1, y, z, "roofStair", 3)
    end
    for _, c in ipairs({ { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } }) do
      s.set(c[1], y, c[2], "roofBlock")
      if first and upturn then s.set(c[1], y + 1, c[2], "roofSlab") end
    end
    first = false
    x0, z0, x1, z1, y = x0 + 1, z0 + 1, x1 - 1, z1 - 1, y + 1
  end
  return y - 1
end

-- Flat roof with a crenellated parapet (desert style).
local function flatRoof(s, w, l, H)
  for x = 0, w - 1 do for z = 0, l - 1 do s.set(x, H + 1, z, "roofBlock") end end
  for x = 0, w - 1 do
    for z = 0, l - 1 do
      local edge = x == 0 or x == w - 1 or z == 0 or z == l - 1
      if edge and (x + z) % 2 == 0 then s.set(x, H + 2, z, "wall") end
    end
  end
  return H + 2
end

---------------------------------------------------------------- buildings

-- A house: timber-framed walls on a stone footing, windows, a door, a roof in
-- the theme's style, and some furniture inside.
local function house(style, o)
  local s = shape()
  local w, l, H = o.w, o.l, o.h
  local dx = math.floor((w - 1) / 2) -- door column
  local ov = style.overhang

  for x = 0, w - 1 do
    for z = 0, l - 1 do
      local edge = x == 0 or x == w - 1 or z == 0 or z == l - 1
      s.set(x, 0, z, edge and "foundation" or "floor")
    end
  end

  for y = 1, H do
    for x = 0, w - 1 do
      for z = 0, l - 1 do
        local side = x == 0 or x == w - 1
        local frontBack = z == 0 or z == l - 1
        if side or frontBack then
          local m
          if side and frontBack then m = "pillar"
          elseif side and z % 4 == 0 and style.posts then m = "pillar"
          elseif y == 1 then m = "wallBase"
          elseif y == H then m = "beam"
          else m = "wall" end
          s.set(x, y, z, m)
        end
      end
    end
  end

  -- windows: rows 2 up to the row under the top beam
  for y = 2, math.max(2, H - 2) do
    for z = 2, l - 3, 4 do
      s.set(0, y, z, "window")
      s.set(w - 1, y, z, "window")
    end
    for _, x in ipairs({ dx - 2, dx + 2 }) do
      if x >= 1 and x <= w - 2 then s.set(x, y, 0, "window") end
    end
    s.set(dx, y, l - 1, "window")
  end

  -- doorway: the door's top half fills (dx, 2, 0)
  s.clear(dx, 2, 0)
  s.set(dx, 1, 0, "door", 2, true)

  local top
  if style.roof == "flat" then
    top = flatRoof(s, w, l, H)
    if style.vigas then
      for x = 1, w - 2, 2 do
        s.set(x, H, -1, "beam")
        s.set(x, H, l, "beam")
      end
    end
  elseif style.roof == "hip" then
    top = hipRoof(s, -ov, -ov, w - 1 + ov, l - 1 + ov, H + 1, style.upturn)
  else
    top = gableRoof(s, w, l, H, ov, style.rise or 1)
    if s.get(dx, H + 2, 0) and s.get(dx, H + 2, 0).m == "wall" then
      s.set(dx, H + 2, 0, "window")
      s.set(dx, H + 2, l - 1, "window")
    end
  end

  if style.chimney then
    for y = 0, top + 1 do s.set(w - 2, y, l, "foundation") end
  end

  -- furniture on the floor (y = 1); the aisle from the door stays clear
  local function bed(x)
    s.set(x, 1, l - 3, "bed", 0)
    s.clear(x, 1, l - 2) -- the bed's head goes here
  end
  if o.kind == "tavern" then
    for x = 2, w - 3 do
      if x ~= dx then s.set(x, 1, l - 2, "storage") end
    end
    s.set(1, 1, l - 2, "table")
    s.set(w - 2, 1, l - 2, "table")
    for _, c in ipairs({ { 1, 1 }, { w - 2, 1 }, { 1, l - 4 }, { w - 2, l - 4 }, { dx - 2, math.floor(l / 2) }, { dx + 2, math.floor(l / 2) } }) do
      s.set(c[1], 1, c[2], "light")
    end
  else
    bed(1)
    if o.kind == "big" then bed(3) end
    s.set(w - 2, 1, l - 2, "table")
    s.set(w - 2, 1, l - 3, "storage")
    s.set(1, 1, 1, "light")
    s.set(w - 2, 1, 1, "light")
  end

  return { blocks = s.list(), entrance = dx, top = top }
end

-- Watchtower (or pagoda): a 7x7 stone tower with a spiral stair round the
-- inside up to a lookout platform.
local function tower(style, o)
  local s = shape()
  local n, H = 7, o.h
  local wallRole = style.towerWall or "masonry"
  for x = 0, n - 1 do
    for z = 0, n - 1 do
      local edge = x == 0 or x == n - 1 or z == 0 or z == n - 1
      s.set(x, 0, z, edge and "foundation" or "floor")
      if edge then
        local corner = (x == 0 or x == n - 1) and (z == 0 or z == n - 1)
        for y = 1, H do s.set(x, y, z, corner and style.towerPillar and "pillar" or wallRole) end
      end
    end
  end
  for _, y in ipairs({ 4, 5, 8, 9 }) do
    if y < H then
      s.set(3, y, n - 1, "window")
      s.set(0, y, 3, "window")
      s.set(n - 1, y, 3, "window")
    end
  end
  s.clear(3, 2, 0)
  s.set(3, 1, 0, "door", 2, true)

  -- inner ring, starting at the cell inside the door and going round clockwise
  local ring = {}
  for x = 3, 5 do ring[#ring + 1] = { x, 1 } end
  for z = 2, 5 do ring[#ring + 1] = { 5, z } end
  for x = 4, 1, -1 do ring[#ring + 1] = { x, 5 } end
  for z = 4, 1, -1 do ring[#ring + 1] = { 1, z } end
  ring[#ring + 1] = { 2, 1 }
  local function headingTo(a, b)
    if b[1] > a[1] then return 1 elseif b[1] < a[1] then return 3 elseif b[2] > a[2] then return 0 end
    return 2
  end
  for k = 1, H - 1 do
    local c, nxt = ring[k + 1], ring[(k + 1) % #ring + 1]
    s.set(c[1], k, c[2], "stair", headingTo(c, nxt))
  end
  -- lookout floor, with headroom left over the top of the stairs
  local hole = {}
  for k = H - 3, H - 1 do
    local c = ring[k + 1]
    hole[c[1] .. "," .. c[2]] = true
  end
  for x = 1, n - 2 do
    for z = 1, n - 2 do
      if not hole[x .. "," .. z] then s.set(x, H, z, "floor") end
    end
  end

  local top
  if style.tower == "pagoda" then
    -- a ring of eaves every 4 blocks, then a hipped roof
    for _, y in ipairs({ 4, 8 }) do
      if y < H then
        for x = 0, n - 1 do
          s.set(x, y, -1, "roofStair", 0)
          s.set(x, y, n, "roofStair", 2)
        end
        for z = 0, n - 1 do
          s.set(-1, y, z, "roofStair", 1)
          s.set(n, y, z, "roofStair", 3)
        end
        for _, c in ipairs({ { -1, -1 }, { n, -1 }, { -1, n }, { n, n } }) do
          s.set(c[1], y, c[2], "roofBlock")
          s.set(c[1], y + 1, c[2], "roofSlab")
        end
      end
    end
    top = hipRoof(s, -1, -1, n, n, H + 1, true)
    s.set(3, H + 1, 3, "light")
  else
    for x = 0, n - 1 do
      for z = 0, n - 1 do
        local edge = x == 0 or x == n - 1 or z == 0 or z == n - 1
        if edge and (x + z) % 2 == 0 then s.set(x, H + 1, z, wallRole) end
      end
    end
    for _, c in ipairs({ { 1, 1 }, { n - 2, 1 }, { 1, n - 2 }, { n - 2, n - 2 } }) do
      if not hole[c[1] .. "," .. c[2]] then s.set(c[1], H + 1, c[2], "light") end
    end
    top = H + 1
  end
  return { blocks = s.list(), entrance = 3, top = top }
end

-- Fenced 11x11 field: 9x9 of dirt round one water block (which keeps all of
-- it hydrated), ready for the player to till and plant.
local function farm()
  local s = shape()
  local n = 11
  for x = 0, n - 1 do
    for z = 0, n - 1 do
      local edge = x == 0 or x == n - 1 or z == 0 or z == n - 1
      s.set(x, 0, z, edge and "foundation" or "soil")
      if edge and not (x == 5 and z == 0) then s.set(x, 1, z, "fence") end
    end
  end
  s.set(5, 0, 5, "water")
  for _, c in ipairs({ { 0, 0 }, { n - 1, 0 }, { 0, n - 1 }, { n - 1, n - 1 } }) do s.set(c[1], 2, c[2], "light") end
  s.set(1, 1, 1, "composter")
  s.set(n - 2, 1, 1, "hay")
  return { blocks = s.list(), entrance = 5, top = 2 }
end

-- The plaza well in front of the turtle's home block.
local function well()
  local s = shape()
  for x = 0, 4 do
    for z = 0, 4 do
      s.set(x, 0, z, "foundation")
      local edge = x == 0 or x == 4 or z == 0 or z == 4
      if edge then
        s.set(x, 1, z, "masonry")
        s.set(x, 2, z, "masonry")
      end
      s.set(x, 5, z, "roofSlab")
    end
  end
  s.set(2, 1, 2, "water") -- flows out to fill the 3x3 basin
  for _, c in ipairs({ { 0, 0 }, { 4, 0 }, { 0, 4 }, { 4, 4 } }) do
    s.set(c[1], 3, c[2], "fence")
    s.set(c[1], 4, c[2], "fence")
  end
  s.set(2, 5, 2, "roofBlock")
  s.set(2, 6, 2, "light")
  return { blocks = s.list(), top = 6 }
end

-- Market stall: posts, a counter at the front, shelves at the back and a
-- striped canopy.
local function stall()
  local s = shape()
  local n = 7
  for x = 0, n - 1 do
    for z = 0, n - 1 do
      s.set(x, 0, z, "floor")
      s.set(x, 4, z, x % 2 == 0 and "accent" or "accent2")
    end
  end
  for _, c in ipairs({ { 0, 0 }, { n - 1, 0 }, { 0, n - 1 }, { n - 1, n - 1 } }) do
    for y = 1, 3 do s.set(c[1], y, c[2], "pillar") end
  end
  for x = 1, n - 2 do
    s.set(x, 1, 1, "storage")
    s.set(x, 1, n - 2, "storage")
  end
  s.set(3, 1, n - 2, "table")
  s.set(1, 2, 1, "light")
  s.set(n - 2, 2, 1, "light")
  return { blocks = s.list(), entrance = 3, top = 4 }
end

-- Wooden pier from the shore out over the water. The deck is one block above
-- the water, on log posts; y = -1 is the water surface.
local function dock()
  local s = shape()
  local w, l = 5, 13
  for z = 0, l - 1 do
    for x = 0, w - 1 do s.set(x, 0, z, "deck") end
    if z > 0 then
      s.set(0, 1, z, "fence")
      s.set(w - 1, 1, z, "fence")
    end
    if z % 4 == 0 then
      s.set(0, -1, z, "pillar")
      s.set(w - 1, -1, z, "pillar")
    end
  end
  for x = 1, w - 2 do s.set(x, 1, l - 1, "fence") end
  for _, z in ipairs({ 4, 8, 12 }) do
    s.set(0, 2, z, "light")
    s.set(w - 1, 2, z, "light")
  end
  return { blocks = s.list(), entrance = 2, top = 2, noFoundation = true, margin = 0 }
end

---------------------------------------------------------------- catalogue

-- suits: weight for each kind of site (flat, slope, shore); 0 or missing
-- means never. limit: how many of these per village size (nil = no limit).
B.catalogue = {
  cottage = {
    suits = { flat = 10, slope = 4 },
    make = function(style) return house(style, { w = 7, l = 9, h = 4 }) end,
  },
  townhouse = {
    suits = { flat = 6 },
    make = function(style) return house(style, { w = 9, l = 11, h = style.roof == "flat" and 4 or 5, kind = "big" }) end,
  },
  tavern = {
    suits = { flat = 3 },
    limit = function(total) return 1 + math.floor(total / 10) end,
    make = function(style) return house(style, { w = 11, l = 11, h = 5, kind = "tavern" }) end,
  },
  tower = {
    suits = { flat = 1, slope = 8 },
    limit = function(total) return 1 + math.floor(total / 5) end,
    make = function(style) return tower(style, { h = style.tower == "pagoda" and 11 or 12 }) end,
  },
  farm = {
    suits = { flat = 5 },
    limit = function(total, counts) return 1 + math.floor(((counts.cottage or 0) + (counts.townhouse or 0)) / 2) end,
    make = function() return farm() end,
  },
  stall = {
    suits = { flat = 3 },
    limit = function(total) return 1 + math.floor(total / 6) end,
    make = function() return stall() end,
  },
  dock = {
    suits = { shore = 10 },
    make = function() return dock() end,
  },
  well = {
    suits = {},
    make = function() return well() end,
  },
}

-- The blueprint for building `name` in `theme`.
function B.make(name, theme)
  local b = B.catalogue[name].make(theme.style)
  b.name = name
  b.margin = b.margin or 1
  return b
end

return B
