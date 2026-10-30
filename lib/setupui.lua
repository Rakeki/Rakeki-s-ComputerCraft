-- Setup screens on the monitor and the terminal at once: a page of settings,
-- tap one (or click it, or pick it with the arrow keys and Enter) to open
-- its page, and chest lists that go a page at a time with what's in each
-- chest beside it, so a big network is as easy to set up as a small one.
-- The storage computer, the enricher and the smelter build their setup on it.
--
--   local setupui = require("lib.setupui")
--   local ui = setupui.new({ screens = { termScreen, monScreen } }) -- lib/screen.lua screens; the
--                                       -- first is the terminal (keyboard), one without a target is skipped
--   local result = ui:run(page)        -- shows page until ui:finish(result)
--
-- A page: { title = "Enricher setup", hint = "a line under it",
--   rows = function(ui) return { { label, value, colour, labelColour, dim, act = function() end }, ... } end,
--   buttons = function(ui) return { { " Save ", "black", "lime", function() end }, ... } end, -- optional:
--                                       -- else Back (Done on the first page)
--   filter = true,                     -- typing on the terminal narrows the rows (label or value)
--   empty = function(row) end }        -- optional: an Empty button shows only the rows this passes
--
--   ui:open(page) / ui:back()          -- go to a page, and back to the one before
--                                       -- (on the terminal, Backspace goes back and a button's first
--                                       -- letter presses it: there may be no mouse)
--   ui:say(text, colour)               -- the message line
--   ui:draw()                          -- draw now (before a slow call, after ui:say)
--   ui:finish(result)                  -- close; run returns result
--   ui:pickChest({ title, hint, names, current, none = "(none)", roleOf = f(name), only = f(name, info),
--     pick = f(name) })                -- a page of chests with their contents; pick(nil) for none
--   ui:monitorPage(setting, event)     -- pick the monitor for a lib/screen.lua setting (queues event)
--   setupui.contents(names)            -- name -> { stacks, top }: every chest's contents, read at once
--   setupui.onNetwork(test)            -- names on the wired network (not touching this computer) whose type passes
--
-- '<program> setup' typed in another tab opens the screen in the running
-- program (it has the monitor) when there is one:
--   if setupui.openInRunning("enricher") then return end   -- in the command: true when one answered
--   if setupui.wanted("enricher", ev) then ... end          -- in the running program's event loop
-- With opts.name, a screen that's open already answers for itself.
local screen = require("lib.screen")

local setupui = {}
local put, fit = screen.put, screen.fit

local UI = {}
UI.__index = UI

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

-- What's in each of names: { stacks, top = the item there's most of }. Read
-- side by side: each call takes a tick otherwise.
function setupui.contents(names)
  local info, jobs = {}, {}
  for _, n in ipairs(names) do
    jobs[#jobs + 1] = function()
      local ok, list = pcall(peripheral.call, n, "list")
      local stacks, most = 0, {}
      for _, it in pairs(ok and type(list) == "table" and list or {}) do
        stacks = stacks + 1
        most[it.name] = (most[it.name] or 0) + it.count
      end
      local top, topN = nil, 0
      for item, c in pairs(most) do
        if c > topN then top, topN = item, c end
      end
      info[n] = { stacks = stacks, top = top and shortName(top), ok = ok }
    end
  end
  for i = 1, #jobs, 100 do parallel.waitForAll(table.unpack(jobs, i, math.min(#jobs, i + 99))) end
  return info
end

function setupui.onNetwork(test)
  local sides, list = {}, {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if not sides[name] and t and test(t, name) then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

-- Ask a running copy of the program in another tab to open its setup
-- screen; true when one answered.
function setupui.openInRunning(name)
  os.queueEvent(name .. "_open_setup")
  local timer = os.startTimer(0.5)
  while true do
    local e, p = os.pullEvent()
    if e == name .. "_setup_opened" then return true end
    if e == "timer" and p == timer then return false end
  end
end

-- In the running program: true when ev asks it to open its setup screen
-- (and it says it will).
function setupui.wanted(name, ev)
  if ev[1] ~= name .. "_open_setup" then return false end
  os.queueEvent(name .. "_setup_opened")
  return true
end

function setupui.new(opts)
  return setmetatable({ opts = opts, screens = opts.screens, stack = {}, msg = { "", "lightGray" } }, UI)
end

function UI:say(text, colour) self.msg = { text, colour or "lightGray" } end

function UI:open(page)
  if self.page then self.stack[#self.stack + 1] = self.page end
  self.page, self.sel, self.filter, self.empty, self.pages = page, 1, "", false, {}
  if page.enter then page.enter(self) end
end

function UI:back()
  self.page = table.remove(self.stack) or self.page
  self.sel, self.filter, self.empty, self.pages = 1, "", false, {}
end

function UI:finish(result) self.done, self.result = true, result end

-- The rows shown: the page's, narrowed by the filter and the Empty button.
function UI:rows()
  local out, f = {}, self.filter:lower()
  for _, row in ipairs(self.page.rows(self)) do
    local keep = row.keep or f == "" or row.label:lower():find(f, 1, true)
      or (row.value or ""):lower():find(f, 1, true)
    if keep and self.empty and self.page.empty and not row.keep and not self.page.empty(row) then keep = false end
    if keep then out[#out + 1] = row end
  end
  return out
end

-- The page's buttons: its own, else Done on the first page and Back on the others.
function UI:buttons()
  local buttons = self.page.buttons and self.page.buttons(self)
  if buttons then return buttons end
  return #self.stack == 0 and { { " Done ", "black", "lime", function() self:finish() end } }
    or { { " Back ", "black", "lightGray", function() self:back(); self:say("") end } }
end

-- Draw one screen; returns its tap zones.
function UI:drawOne(i, scr, list)
  local page = self.page
  local w, h = scr:size()
  local per = math.max(1, h - 4)
  local pages = math.max(1, math.ceil(#list / per))
  -- the terminal's page follows the keyboard's row
  if i == 1 then self.pages[i] = math.floor((self.sel - 1) / per) + 1 end
  local pg = math.max(1, math.min(self.pages[i] or 1, pages))
  self.pages[i] = pg
  local ops, zones = {}, {}
  local function text(x, y, t, fg, bg) ops[#ops + 1] = { x, y, t, fg or "white", bg or "black" } end
  local function button(x, y, label, fg, bg, act)
    text(x, y, label, fg, bg)
    zones[#zones + 1] = { x, x + #label - 1, y, act }
    return x + #label + 1
  end

  local head = type(page.title) == "function" and page.title(self) or page.title
  text(1, 1, (" "):rep(w), "white", "gray")
  text(2, 1, fit(head, w - 2), "yellow", "gray")
  local right = self.filter ~= "" and ("find: " .. self.filter) or pages > 1 and ("%d/%d"):format(pg, pages) or ""
  if #right > 0 and #head + #right + 4 <= w then text(w - #right, 1, right, "lightGray", "gray") end
  if page.hint then text(2, 2, fit(page.hint, w - 2), "lightGray") end

  for r = 1, per do
    local n = (pg - 1) * per + r
    local row = list[n]
    if row then
      local y = 2 + r
      local on = i == 1 and n == self.sel
      local bg = on and "blue" or "black"
      local value = row.value or ""
      local vw = math.min(#value, math.floor((w - 3) * 0.5))
      text(1, y, (" "):rep(w), "white", bg)
      text(2, y, fit(row.label, w - 3 - (vw > 0 and vw + 1 or 0)),
        row.dim and "gray" or row.labelColour or row.value and "white" or row.colour or "white", bg)
      if vw > 0 then text(w - vw, y, fit(value, vw), row.colour or "lightGray", bg) end
      if row.act then zones[#zones + 1] = { 1, w, y, function() self.sel = n; row.act(self) end } end
    end
  end

  text(1, h - 1, fit(" " .. self.msg[1], w), self.msg[2])
  local x = 1
  local buttons = self:buttons()
  for _, b in ipairs(buttons) do x = button(x, h, b[1], b[2], b[3], b[4]) end
  if pages > 1 then
    x = button(x, h, " < ", "white", pg > 1 and "gray" or "black", function()
      if i == 1 then self.sel = math.max(1, self.sel - per) else self.pages[i] = pg - 1 end
    end)
    x = button(x, h, " > ", "white", pg < pages and "gray" or "black", function()
      if i == 1 then self.sel = math.min(#list, self.sel + per) else self.pages[i] = pg + 1 end
    end)
  end
  if page.empty and x + 7 <= w then
    x = button(x, h, " Empty ", self.empty and "black" or "white", self.empty and "yellow" or "gray", function()
      self.empty, self.sel, self.pages = not self.empty, 1, {}
    end)
  end
  -- the terminal's keys for the buttons (a basic computer has no mouse)
  if i == 1 then
    local letters = {}
    for _, b in ipairs(buttons) do letters[#letters + 1] = b[1]:match("%a") end
    local keyText = page.filter and "Bksp: back" or ("keys: " .. table.concat(letters, " "))
    if #self.stack == 0 and page.filter then keyText = "" end
    if x + #keyText <= w then text(x, h, keyText, "gray") end
  end

  local parts = {}
  for k, op in ipairs(ops) do parts[k] = table.concat(op, ",") end
  if not scr:same("setup|" .. table.concat(parts, "|")) then
    local win = scr:frame()
    for _, op in ipairs(ops) do put(win, op[1], op[2], op[3], op[4], op[5]) end
    scr:show()
  end
  return zones
end

function UI:draw()
  local list = self:rows()
  self.sel = math.max(1, math.min(self.sel, #list))
  self.zones = {}
  for i, scr in ipairs(self.screens) do
    if scr.target then self.zones[i] = self:drawOne(i, scr, list) end
  end
  return list
end

-- Look for the monitors again (one was attached, or its setting changed).
function UI:refresh()
  for _, scr in ipairs(self.screens) do
    if scr.opts then scr:refresh() end
  end
end

function UI:run(page)
  self:open(page)
  while not self.done do
    local list = self:draw()
    local ev = { os.pullEvent() }
    local e, a = ev[1], ev[2]
    if self.opts.onEvent then self.opts.onEvent(ev) end
    if self.opts.name then setupui.wanted(self.opts.name, ev) end
    local tapped
    for i, scr in ipairs(self.screens) do
      -- not 'scr.target and scr:clicked(ev)': that keeps only x
      local x, y
      if scr.target then x, y = scr:clicked(ev) end
      if x and self.zones[i] then
        for _, z in ipairs(self.zones[i]) do
          if y == z[3] and x >= z[1] and x <= z[2] then tapped = z[4] end
        end
      end
    end
    local per = math.max(1, select(2, self.screens[1]:size()) - 4)
    if tapped then
      tapped()
    elseif e == "peripheral" or e == "peripheral_detach" then
      self:refresh()
      if self.page.enter then self.page.enter(self) end -- a chest list reads its chests again
    elseif e == "key" then
      if a == keys.up then self.sel = self.sel - 1
      elseif a == keys.down then self.sel = self.sel + 1
      elseif a == keys.pageUp then self.sel = self.sel - per
      elseif a == keys.pageDown then self.sel = self.sel + per
      elseif a == keys.enter then
        local row = list[self.sel]
        if row and row.act then row.act(self) end
      elseif a == keys.backspace then
        if self.filter ~= "" then
          self.filter, self.sel = self.filter:sub(1, -2), 1
        elseif #self.stack > 0 then
          self:back()
          self:say("")
        end
      end
    elseif e == "char" and self.page.filter then
      self.filter, self.sel = self.filter .. a, 1
    elseif e == "char" then
      -- a button by its first letter: S for Save, B for Back, ...
      for _, b in ipairs(self:buttons()) do
        if (b[1]:match("%a") or ""):lower() == a:lower() then
          b[4]()
          break
        end
      end
    elseif e == "mouse_scroll" then
      self.sel = self.sel + a * per
    end
  end
  -- the program's own screens draw next: make sure they aren't skipped as unchanged
  for _, scr in ipairs(self.screens) do scr.last = nil end
  return self.result
end

---------------------------------------------------------------- ready-made pages

-- A page of chests (o.names) with what's in each: o.pick(name) when one is
-- tapped (nil for o.none, when given). o.roleOf(name) greys out one used for
-- something else and says what (o.pick still decides); o.only(name, info)
-- leaves some out.
function UI:pickChest(o)
  local info = {}
  self:open({
    title = o.title, hint = o.hint, filter = true,
    enter = function() info = setupui.contents(o.names) end,
    empty = function(row) return row.chest and (info[row.chest] or {}).stacks == 0 end,
    rows = function()
      local out = {}
      if o.none then
        out[#out + 1] = { label = o.none, colour = o.current and "white" or "yellow", keep = true, act = function() o.pick(nil) end }
      end
      for _, n in ipairs(o.names) do
        local i = info[n] or { stacks = 0 }
        if not o.only or o.only(n, i) then
          local role = n ~= o.current and o.roleOf and o.roleOf(n)
          local value = role or (i.stacks > 0 and ("%d: %s"):format(i.stacks, i.top) or "empty")
          out[#out + 1] = { label = n, chest = n, value = n == o.current and ("now  " .. value) or value,
            colour = n == o.current and "yellow" or role and "gray" or "lightGray", labelColour = role and "gray" or "white",
            act = function() o.pick(n) end }
        end
      end
      if #out == (o.none and 1 or 0) then out[#out + 1] = { label = o.nothing or "No chests here.", dim = true } end
      return out
    end,
  })
end

-- Pick the monitor a lib/screen.lua setting names: the first free one, none,
-- or one of every monitor this computer sees. Queues event so the running
-- program moves to it.
function UI:monitorPage(setting, event)
  local function set(v)
    if v == nil then settings.unset(setting) else settings.set(setting, v) end
    settings.save()
    if event then os.queueEvent(event) end
    self:refresh()
    self:back()
    self:say(v == nil and "Monitor: the first free one." or v == "none" and "No monitor." or ("Monitor: %s."):format(v), "lime")
  end
  self:open({
    title = "Monitor", hint = "Right-click a monitor's modem to see its name.",
    rows = function()
      local now = settings.get(setting)
      local out = {
        { label = "(the first free one)", colour = now == nil and "yellow" or "white", act = function() set(nil) end },
        { label = "(none)", colour = now == "none" and "yellow" or "white", act = function() set("none") end },
      }
      local sides = {}
      for _, s in ipairs(rs.getSides()) do sides[s] = true end
      for _, n in ipairs(peripheral.getNames()) do
        if peripheral.getType(n) == "monitor" then
          out[#out + 1] = { label = n, value = n == now and "now" or sides[n] and "touching me" or "",
            colour = n == now and "yellow" or "lightGray", act = function() set(n) end }
        end
      end
      return out
    end,
  })
end

-- What the monitor setting says, for a settings page.
function setupui.monitorText(setting)
  local v = settings.get(setting)
  return v == nil and "the first free one" or v
end

return setupui
