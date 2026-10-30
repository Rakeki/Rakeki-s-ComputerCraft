-- A work chest: one chest that the storage computer fills for one program
-- (the smelter, the enricher) in a single request, which the program then
-- shares out into its own furnaces or hoppers. One request a round instead
-- of one per furnace or hopper, and with an ME or RS bridge the items skip
-- the transfer chest. Whatever is left in it at the end of a round goes back
-- through the input chest, so nothing sits there unseen by the storage
-- system for long.
--
-- Near the storage system the work chest is on its cable. Far away it's an
-- ender chest (EnderStorage and the like): the storage computer fills its
-- twin at home, found the way turtles find their chest (lib/claim.lua).
-- Things go home through the same chest: the program leaves what its
-- machines made and what it sends back in it, and each fill (with sweep)
-- first puts away everything in it that wasn't asked for. Or a second ender
-- chest pair carries everything back to an input chest at home (the return
-- chest), since the storage computer's own is out of reach.
--
--   local workchest = require("lib.workchest")
--   local work = workchest.new("smelter", ask)       -- remembers the chest in /.smelter_chest
--   work:set("minecraft:chest_3")                     -- 'smelter chest <name>'; work:set(nil) stops using one
--   work:setRemote("enderstorage:ender_chest_0")     -- far away: one ender chest both ways
--   work:setRemote("enderstorage:ender_chest_0", "enderstorage:ender_chest_1") -- or supply and return chests
--   if work:check(stock) or work.remote then          -- after each 'stock' reply: true while it's in use
--     local input = work:input(stock.input)           -- where finished items go back
--     local r, why = work:fill(items, fuel)           -- top it up to items (name -> n), fuel for that many smelts
--     local n = work:move(name, furnace, 1, 64)       -- from it into a machine (slot optional): how many went
--     work:empty(input)                               -- the rest back into storage
--   end
--   ui:open(work:setupPage(ui))                       -- on a lib/setupui.lua setup screen
--
-- ask(msg) is the program's own request function on the "storage" protocol
-- (it returns the reply, or nil and why). Without a work chest, or with a
-- storage computer too old to know one, check is false and a program on the
-- cable loads its machines with 'send' as before; a far-away one can't, so
-- it loads nothing until check is true again. work.problem says why a saved
-- chest isn't in use (nil when it is, or none is set).
local files = require("lib.files") -- crash-safe save files
local claim = require("lib.claim") -- finds the far-away work chest's twin

local workchest = {}

local RETRY = 60 -- seconds before asking the storage computer to take the saved chest again after it said no

local Work = {}
Work.__index = Work

-- saved: { chest } on the cable, { chest, back, home, remote = true } far
-- away (chest: the supply ender chest here, back: the return one, or nil
-- when chest goes both ways, home: the supply chest's twin on the storage
-- computer's network)
-- An ender chest (any type with "ender" in it): its twin is elsewhere, so
-- it's always a far-away work chest, never one the storage computer can see.
local function isEnder(name)
  local t = name and peripheral.isPresent(name) and peripheral.getType(name)
  return t and t:find("ender", 1, true) ~= nil or false
end

local function readSaved(self)
  local saved = files.read(self.file)
  saved = type(saved) == "table" and saved or {}
  self.chest, self.back, self.home, self.remote = saved.chest, saved.back, saved.home, saved.remote == true
  -- picked as a chest on the cable before ender chests counted as far away
  if self.chest and not self.remote and isEnder(self.chest) then self.remote = true end
end

function workchest.new(name, ask)
  local self = setmetatable({ file = ("/.%s_chest"):format(name), ask = ask, list = {} }, Work)
  readSaved(self)
  return self
end

-- Name the chest (nil: stop using one, and the storage computer puts back
-- what's in it). true, or false and why; nil and why if nobody answered.
function Work:set(chest)
  if chest and isEnder(chest) then return self:setRemote(chest) end
  local r, why = self.ask({ type = "work", chest = chest })
  if not r then return nil, why end
  if chest and not r.ok then return false, r.error or "the storage computer said no" end
  self.chest, self.back, self.home, self.remote = chest, nil, nil, false
  self.active, self.problem = chest, nil
  if chest then files.write(self.file, { chest = chest }) else files.delete(self.file) end
  return true
end

-- Far away: chest is the supply ender chest here, back the return one (its
-- twin at home is a storage input chest), or nil to send things home
-- through chest too. The storage computer finds the supply chest's twin by
-- dropping an item into each chest it could be. The same answers as set.
function Work:setRemote(chest, back)
  -- picked on the storage computer already ('storage config remote'): no search
  local stock = self.ask({ type = "stock" })
  local ok, home = true, stock and stock.workRemote and stock.work
  if not home then ok, home = claim.chest(self.ask, "work", chest) end
  -- far away either way: what the machines make goes into the ender chest
  -- (and so home) even before its twin is found, and check looks again
  local why = not ok and (home or "no storage computer answered") or nil
  self.chest, self.back, self.home, self.remote = chest, back, ok and home or nil, true
  self.active, self.problem = ok and chest or nil, why and ("its twin at home isn't found yet: %s"):format(why)
  self.tried = os.clock()
  files.write(self.file, { chest = chest, back = back, home = self.home, remote = true })
  if not ok then return false, why end
  return true
end

-- Read the saved chest again ('<program> chest' or the setup screen in
-- another tab may have changed it), so remote and input are up to date.
function Work:reload() readSaved(self) end

-- stock: the storage computer's reply to 'stock', whose work field is the
-- chest it has for this computer. Claims the saved chest again if it's
-- been forgotten (the storage computer was set up again, or the chest's
-- modem was off when it started), at most once a minute.
function Work:check(stock)
  self.active = nil
  readSaved(self) -- again: '<program> chest' may have been typed in another tab
  if not self.chest then
    self.problem = nil
    return false
  end
  if stock and stock.work == (self.remote and self.home or self.chest) then
    self.active, self.problem = self.chest, nil
    return true
  end
  -- far away, the storage computer may have been told which ender chest at
  -- home is ours ('storage config remote'): take it
  if self.remote and stock and stock.workRemote and type(stock.work) == "string" then
    self.home = stock.work
    files.write(self.file, { chest = self.chest, back = self.back, home = self.home, remote = true })
    self.active, self.problem = self.chest, nil
    return true
  end
  for _, c in ipairs({ self.chest, self.remote and self.back or nil }) do
    if not peripheral.isPresent(c) then
      self.problem = ("can't see %s: check its modem"):format(c)
      return false
    end
  end
  if self.tried and os.clock() - self.tried < RETRY then return false end
  self.tried = os.clock()
  local ok, why
  if self.remote then
    ok, why = self:setRemote(self.chest, self.back)
  else
    ok, why = self:set(self.chest)
  end
  if ok then return true end
  if self.remote then return false end -- setRemote said why
  -- an old storage computer doesn't answer 'work' at all
  self.problem = ok == false and ("the storage computer won't use %s: %s"):format(self.chest, why)
    or ("the storage computer didn't take the work chest (%s)"):format(why or "no answer")
  return false
end

-- Where finished items and leftovers go back into storage: far away the
-- return chest, or the work chest itself (the next fill sweeps them home),
-- else the storage computer's input chest.
function Work:input(stockInput)
  if self.remote then return self.back or self.chest end
  return stockInput
end

local function readList(chest)
  if not chest then return {} end
  local ok, list = pcall(peripheral.call, chest, "list")
  return ok and type(list) == "table" and list or {}
end

-- Top the chest up to n of each item (what's in it counts) and to fuel for
-- that many smelts, in one request; then read what's in it. The reply
-- (sent, ready, fuel, error), or nil and why.
function Work:fill(items, fuel)
  if not self.active then return nil, self.problem or "no work chest" end
  -- one ender chest both ways: ask every round, so what's made goes home
  local sweep = self.remote and not self.back
  local r, why
  if sweep or next(items) or (fuel or 0) > 0 then
    r, why = self.ask({ type = "fill", items = items, fuel = fuel, sweep = sweep or nil })
  end
  if sweep and r and not r.swept and not r.nochest then
    r.error = r.error or "the storage computer is too old to take things home through one ender chest: 'install update' it"
  end
  self.list = readList(self.active)
  if r and r.nochest then self.active = nil end
  return r, why
end

-- Move up to n of an item from the chest into to (into toSlot, if given).
-- Returns how many went.
function Work:move(name, to, toSlot, n)
  local moved = 0
  if not self.active then return 0 end
  for slot, item in pairs(self.list) do
    if moved >= n then break end
    if item.name == name and not item.nbt then
      local ok, m = pcall(peripheral.call, self.active, "pushItems", to, slot, n - moved, toSlot)
      if ok and m > 0 then
        moved = moved + m
        item.count = item.count - m
        if item.count <= 0 then self.list[slot] = nil end
      end
    end
  end
  return moved
end

-- Everything left goes back into storage (input: from work:input); what
-- doesn't fit stays for next round (fill counts it).
function Work:empty(input)
  -- one ender chest both ways: it stays, and the next fill sweeps it home
  if not self.active or not input or input == self.active then return end
  for slot in pairs(readList(self.active)) do
    pcall(peripheral.call, self.active, "pushItems", input, slot)
  end
  self.list = {}
end

---------------------------------------------------------------- the setup screen

-- What the work chest is now, in a few words.
function Work:describe()
  readSaved(self)
  if not self.chest then return "none" end
  return self.remote and ("far away: " .. self.chest) or self.chest
end

-- A lib/setupui.lua page for the work chest: one on the cable, far away
-- through an ender chest (and maybe a return one), or none.
function Work:setupPage(ui)
  local function done(ok, why, text)
    ui:back()
    if ok then ui:say(text, "lime") else ui:say(("Couldn't: %s."):format(why or "no answer"), "red") end
  end
  -- ender chests on the cable; one only touching the computer can't be
  -- reached by the machines' chests, so it's counted apart (touching)
  local function enders()
    local out, touching, sides = {}, 0, {}
    for _, s in ipairs(rs.getSides()) do sides[s] = true end
    for _, n in ipairs(peripheral.getNames()) do
      local t = peripheral.getType(n) or ""
      if t:find("ender", 1, true) and (t:find("chest", 1, true) or t:find("barrel", 1, true)) then
        if sides[n] then touching = touching + 1 else out[#out + 1] = n end
      end
    end
    table.sort(out)
    return out, touching
  end
  -- Far away: work comes in through the ender chest on this network and
  -- what's made goes home through it, so there's nothing to pick unless
  -- there are several. (A separate return chest: '<program> chest remote'.)
  local function far()
    local list, touching = enders()
    local function use(chest)
      ui:say("Finding its twin on the storage network...", "lightBlue")
      ui:draw()
      local ok, why = self:setRemote(chest, nil)
      ui:say(ok and ("Far away: work comes in and goes home through %s."):format(chest)
        or ("Far away through %s, but its twin at home isn't found yet (%s). It keeps looking; or pick it on the storage computer under Far-away workers.")
          :format(chest, why or "no answer"), ok and "lime" or "orange")
    end
    if #list == 0 and touching > 0 then
      ui:say("The ender chest only touches me: put a wired modem on it, join it to the cable and right-click it, so the machines' chests can reach it.", "orange")
    elseif #list == 0 then
      ui:say("No ender chest here: put one on my cable with a wired modem and right-click it.", "orange")
    elseif #list == 1 then
      use(list[1])
    else
      ui:pickChest({ title = "Which ender chest?", hint = "Its twin is on the storage cable (not an input chest).",
        names = list, current = self.remote and self.chest or nil,
        pick = function(chest)
          ui:back()
          use(chest)
        end })
      ui:say("There are several ender chests: tap the one for work.")
    end
  end
  return {
    title = "Work chest",
    hint = "The storage computer fills it in one go each round.",
    rows = function()
      return {
        { label = "Now", value = self:describe(), colour = self.chest and "lightGray" or "gray" },
        { label = "A chest on this cable", value = "near the storage", colour = "gray", act = function()
          local names = {}
          for _, n in ipairs(peripheral.getNames()) do
            local t = peripheral.getType(n) or ""
            if not t:find("ender", 1, true) and (t:find("chest", 1, true) or t:find("barrel", 1, true)) then names[#names + 1] = n end
          end
          table.sort(names)
          ui:pickChest({ title = "Pick the work chest", hint = "An empty chest on the storage cable.",
            names = names, current = not self.remote and self.chest or nil,
            only = function(n, info) return n == self.chest or info.stacks == 0 end,
            nothing = "No empty chest here: put a wired modem on one and right-click it.",
            pick = function(chest)
              ui:say("Asking the storage computer...", "lightBlue")
              ui:draw()
              local ok, why = self:set(chest)
              done(ok, why, ("Work chest: %s. The storage computer fills it from now on."):format(chest))
            end })
          ui:say("Tap an empty chest.")
        end },
        { label = "Far away: through the ender chest", value = "another base", colour = "gray", act = far },
        { label = "None", value = "load each machine in turn", colour = "gray", act = function()
          ui:say("Asking the storage computer...", "lightBlue")
          ui:draw()
          local ok, why = self:set(nil)
          ui:say(ok and "No work chest now: what was in it went back into storage." or ("Couldn't: %s."):format(why or "no answer"),
            ok and "lime" or "red")
        end },
      }
    end,
  }
end

---------------------------------------------------------------- the command

-- Chests on this computer's network (not touching it) that pass test(type, list).
local function chestsHere(test)
  local sides, out = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name) or ""
    if not sides[name] and (t:find("chest", 1, true) or t:find("barrel", 1, true)) then
      local ok, items = pcall(peripheral.call, name, "list")
      if ok and test(t, name, items) then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

local function pick(question, list)
  for i, name in ipairs(list) do print(("%2d  %s"):format(i, name)) end
  write(question .. " (Enter to cancel) ")
  local text = read()
  if text == "" then return nil end
  return list[tonumber(text)] or text
end

-- The '<program> chest [name|none|remote]' command: name the work chest,
-- pick one from the empty chests on the network, set up a far-away one
-- through one ender chest, or two ("remote"), or stop using one ("none"), and
-- print how it went. Needs a modem open (net.open) first: an ender modem
-- far away.
function Work:command(arg)
  if arg == "none" then
    local ok, why = self:set(nil)
    print(ok and "No work chest now: what was in it went back into storage." or ("Couldn't: %s."):format(why))
    return
  end
  print(self.chest and ("The work chest is %s%s."):format(self.chest, self.remote and " (far away)" or "")
    or "There's no work chest yet.")
  if arg == "remote" then
    local enders = chestsHere(function(t) return t:find("ender", 1, true) ~= nil end)
    if #enders == 0 then
      print("I need an ender chest on my network with a wired modem on it. Its twin goes on the")
      print("storage cable with a wired modem (not an input chest): the storage system fills it,")
      print("and takes back whatever else is in it.")
      return
    end
    print("The ender chest (its twin on the storage cable, not an input chest):")
    local chest = pick("Which?", enders)
    if not chest then return end
    local rest = {}
    for _, e in ipairs(enders) do
      if e ~= chest then rest[#rest + 1] = e end
    end
    local back
    if #rest > 0 then
      print("Things go home through that chest too. Or pick a RETURN ender chest (its twin is a storage")
      print("input chest) to send them through that instead:")
      for i, name in ipairs(rest) do print(("%2d  %s"):format(i, name)) end
      write("Which? (Enter: none, one chest both ways) ")
      local text = read()
      if text ~= "" then back = rest[tonumber(text)] or text end
    end
    print("Finding its twin on the storage network...")
    local ok, why = self:setRemote(chest, back)
    if ok then
      print(("Work chest set: %s, filled through %s; everything goes home through %s."):format(chest, self.home,
        back or "the same chest"))
    else
      print(("Far away through %s, but its twin at home isn't found yet: %s."):format(chest, why))
      print("It keeps looking once a minute. Or pick it on the storage computer: Setup, Far-away workers.")
    end
    return
  end
  local chest = arg
  if not chest then
    local list = chestsHere(function(t, name, items) return not next(items) or name == self.chest end)
    if #list == 0 then
      print("No empty chest on the network. Put a wired modem on one, join it to the cable and right-click it.")
      return
    end
    print("Empty chests on the network (right-click a modem to see its chest's name):")
    chest = pick("Which one?", list)
    if not chest then return end
  end
  local ok, why = self:set(chest)
  if ok then
    print(("Work chest set: %s. The storage computer fills it from now on."):format(chest))
  else
    print(("Couldn't use %s: %s."):format(chest, why))
  end
end

return workchest
