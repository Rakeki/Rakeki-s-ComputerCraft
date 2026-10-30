-- The storage setup screen, on the monitor and the terminal at once: every
-- setting on one page, tap one (or click it, or pick it with the arrow keys
-- and Enter) to change it, and the chest lists go a page at a time with what
-- each chest holds beside it, so a big storage system is as easy to set up
-- as a small one. storage.lua runs it for 'storage setup', 'storage config'
-- and the monitor's Setup button.
--
--   local setupui = require("setupui")
--   local saved = setupui.run({
--     setup = s,               -- edited in place; the caller saves it when run returns true
--     screens = { termScreen, monScreen },  -- lib/screen.lua screens (one without a target is skipped)
--     bridge = "ME",           -- an ME or RS bridge was found: its kind (offers the store choice)
--     first = true,            -- the first setup: says what's needed
--     isInventory = f, isEnder = f, usedIn = f,  -- storage.lua's
--     workers = f,             -- far-away enrichers and smelters: { { id, kind } } or nil, why
--     onEvent = f,             -- optional: sees every event (answers a 'storage config' in another tab)
--   })
local screen = require("lib.screen")

local setupui = {}
local put, fit = screen.put, screen.fit

-- the settings on the first page, and the line shown above each one's list
local SETTINGS = {
  { key = "input", what = "Input chest", need = true, hint = "Items dropped in here get put away." },
  { key = "inputs", what = "Extra input chests", hint = "Emptied like the input chest." },
  { key = "output", what = "Output chest", need = true, hint = "What you take from storage is sent here." },
  { key = "delivery", what = "Shared delivery chest", hint = "For turtles that can't find a chest of their own." },
  { key = "crafter", what = "Crafter chest", hint = "In front of the crafting turtle (or let it find its own)." },
  { key = "fuel", what = "Fuel chest", hint = "Coal and charcoal for the smelter and the turtles." },
  { key = "transfer", what = "Transfer chest", bridge = true, hint = "Items for furnaces and the crafter pass through it." },
  { key = "remote", what = "Far-away workers", hint = "Enrichers and smelters at another base, through an ender chest." },
}

-- the chests turtles and computers claim themselves: picking one for
-- something else takes it back (they find another). Mekanism feeders are
-- left alone: the enricher and smelter register them again every round.
local CLAIMS = { "deliveries", "crafters", "works" }

local function shortName(name) return (name:gsub("^[%w_]+:", ""):gsub("_", " ")) end

-- Take name back from a turtle's or computer's claim (it'll find another).
local function unclaim(s, name)
  for _, which in ipairs(CLAIMS) do
    for id, n in pairs(s[which]) do
      if n == name then s[which][id] = nil end
    end
  end
end

local function claimed(s, name)
  for _, which in ipairs(CLAIMS) do
    for _, n in pairs(s[which]) do
      if n == name then return true end
    end
  end
  return false
end

function setupui.run(o)
  local s = o.setup
  local st = {
    view = "main", -- main, pick, inputs, workers
    sel = 1, -- the keyboard's row
    pages = {}, -- each screen's page
    filter = "", -- typed on the terminal: only chests whose name or contents match
    empty = false, -- only empty chests
    msg = { o.first and "Pick the input and output chests, then Save." or "Tap a setting to change it.", "lightGray" },
  }
  local names, info = {}, {}

  -- Every chest on the network and what's in it, read all at once (a tick per call otherwise).
  local function readChests()
    names = {}
    for _, n in ipairs(peripheral.getNames()) do
      if o.isInventory(n) then names[#names + 1] = n end
    end
    table.sort(names)
    local jobs = {}
    for _, n in ipairs(names) do
      jobs[#jobs + 1] = function()
        local ok, list = pcall(peripheral.call, n, "list")
        local stacks, most = 0, {}
        for _, it in pairs(ok and list or {}) do
          stacks = stacks + 1
          most[it.name] = (most[it.name] or 0) + it.count
        end
        local top, topN = nil, 0
        for item, c in pairs(most) do
          if c > topN then top, topN = item, c end
        end
        info[n] = { stacks = stacks, top = top and shortName(top) }
      end
    end
    for i = 1, #jobs, 100 do parallel.waitForAll(table.unpack(jobs, i, math.min(#jobs, i + 99))) end
  end

  local function go(view, extra)
    st.view, st.sel, st.filter, st.pages = view, 1, "", {}
    for k, v in pairs(extra or {}) do st[k] = v end
  end

  local function say(text, colour) st.msg = { text, colour or "lightGray" } end

  -- Open a setting from the first page.
  local function open(c)
    if c.key == "inputs" then
      go("inputs")
    elseif c.key == "remote" then
      st.found, st.why = nil, nil
      go("workers")
    else
      go("pick", { c = c })
      say(c.need and "Tap a chest." or "Tap a chest, or (none).")
    end
  end

  -- The picked chest (nil: none) for the setting being picked.
  local function choose(name)
    local c = st.c
    if name and o.usedIn(s)[name] and not claimed(s, name) and name ~= (c.worker and s.works[c.worker.id] or s[c.key]) then
      say(("%s is already the %s."):format(name, o.usedIn(s)[name]), "orange")
      return
    end
    if name and claimed(s, name) and name ~= (c.worker and s.works[c.worker.id]) then unclaim(s, name) end
    if c.worker then
      s.works[c.worker.id] = name
      go("workers")
      say(name and ("On %s #%d, run '%s chest remote': it takes %s."):format(c.worker.kind, c.worker.id, c.worker.kind, name)
        or "Done. What's left in its old ender chest stays there.", "lime")
    elseif c.key == "newInput" then
      s.inputs[#s.inputs + 1] = name
      go("inputs")
      say(("%s is an input chest now."):format(name), "lime")
    else
      s[c.key] = name
      go("main")
      say(("%s: %s."):format(c.what, name or "none"), "lime")
    end
  end

  -- The rows of the page shown: { label, value, colour, act, dim }.
  local function rows()
    local out = {}
    if st.view == "main" then
      if o.bridge then
        out[#out + 1] = { label = "Store items in", value = s.backend == "bridge" and ("the " .. o.bridge .. " system") or "chests",
          act = function()
            s.backend = s.backend == "bridge" and "chests" or "bridge"
            if s.backend ~= "bridge" then s.transfer = nil end
          end }
      end
      for _, c in ipairs(SETTINGS) do
        if not c.bridge or s.backend == "bridge" then
          local value, colour = s[c.key], "lightGray"
          if c.key == "inputs" then
            value = #s.inputs == 0 and "none" or #s.inputs == 1 and s.inputs[1] or (#s.inputs .. " chests")
          elseif c.key == "remote" then
            value = "find them"
          elseif not value then
            value, colour = c.need and "not set" or "none", c.need and "orange" or "gray"
          end
          out[#out + 1] = { label = c.what, value = value, colour = colour, act = function() open(c) end }
        end
      end
    elseif st.view == "inputs" then
      out[#out + 1] = { label = "+ Add an input chest", colour = "lime",
        act = function()
          go("pick", { c = { key = "newInput", what = "New input chest", ender = true, need = true, hint = SETTINGS[2].hint } })
          say("Tap a chest.")
        end }
      for i, n in ipairs(s.inputs) do
        out[#out + 1] = { label = n, value = "tap to remove", colour = "gray",
          act = function()
            table.remove(s.inputs, i)
            say(("%s is storage again."):format(n), "lime")
          end }
      end
    elseif st.view == "workers" then
      for _, w in ipairs(st.found or {}) do
        out[#out + 1] = { label = ("%s #%d"):format(w.kind, w.id), value = s.works[w.id] or "no ender chest here",
          colour = s.works[w.id] and "lightGray" or "gray",
          act = function()
            go("pick", { c = { what = ("%s #%d's ender chest"):format(w.kind, w.id), worker = w, enderOnly = true,
              hint = "Its twin is at that computer." } })
            say("Tap an ender chest, or (none).")
          end }
      end
      if st.found and #st.found == 0 then
        out[#out + 1] = { label = st.why or "None answered: are they running, with an ender or wireless modem?", dim = true }
      end
      out[#out + 1] = { label = "Look again", colour = "lightBlue", act = function() st.found = nil end }
    else
      local c = st.c
      local used = o.usedIn(s)
      local cur = c.worker and s.works[c.worker.id] or s[c.key]
      if not c.need then out[#out + 1] = { label = "(none)", colour = cur and "white" or "yellow", act = function() choose(nil) end } end
      local f = st.filter:lower()
      for _, n in ipairs(names) do
        local ender = o.isEnder(n)
        local i = info[n] or { stacks = 0 }
        if (c.enderOnly and ender or not c.enderOnly and (c.ender or not ender))
          and not (st.empty and i.stacks > 0)
          and (f == "" or n:lower():find(f, 1, true) or (i.top or ""):lower():find(f, 1, true)) then
          local role = n ~= cur and used[n]
          local value = role or (i.stacks > 0 and ("%d: %s"):format(i.stacks, i.top) or "empty")
          out[#out + 1] = { label = n, value = n == cur and ("now  " .. value) or value,
            colour = n == cur and "yellow" or role and "gray" or "lightGray", labelColour = role and "gray" or "white",
            act = function() choose(n) end }
        end
      end
      if #out == 0 or #out == 1 and not c.need then out[#out + 1] = { label = "No chests match.", dim = true } end
    end
    return out
  end

  local function title()
    if st.view == "main" then return o.first and "Storage setup" or "Storage settings", nil end
    if st.view == "inputs" then return "Extra input chests", SETTINGS[2].hint end
    if st.view == "workers" then return "Far-away workers", SETTINGS[8].hint end
    return "Pick: " .. st.c.what, st.c.hint
  end

  -- Draw one screen; returns its tap zones.
  local function draw(i, scr, list)
    local w, h = scr:size()
    local per = math.max(1, h - 4)
    local pages = math.max(1, math.ceil(#list / per))
    -- the terminal's page follows the keyboard's row
    if i == 1 then st.pages[i] = math.floor((st.sel - 1) / per) + 1 end
    local page = math.max(1, math.min(st.pages[i] or 1, pages))
    st.pages[i] = page
    local ops, zones = {}, {}
    local function text(x, y, t, fg, bg) ops[#ops + 1] = { x, y, t, fg or "white", bg or "black" } end
    local function button(x, y, label, fg, bg, act)
      text(x, y, label, fg, bg)
      zones[#zones + 1] = { x, x + #label - 1, y, act }
      return x + #label + 1
    end

    local head, hint = title()
    text(1, 1, (" "):rep(w), "white", "gray")
    text(2, 1, fit(head, w - 2), "yellow", "gray")
    local right = st.filter ~= "" and ("find: " .. st.filter) or pages > 1 and ("%d/%d"):format(page, pages) or ""
    if #right > 0 and #head + #right + 4 <= w then text(w - #right, 1, right, "lightGray", "gray") end
    if hint then text(2, 2, fit(hint, w - 2), "lightGray") end

    for r = 1, per do
      local n = (page - 1) * per + r
      local row = list[n]
      if row then
        local y = 2 + r
        local on = i == 1 and n == st.sel
        local bg = on and "blue" or "black"
        local value = row.value or ""
        local vw = math.min(#value, math.floor((w - 3) * 0.5))
        text(1, y, (" "):rep(w), "white", bg)
        text(2, y, fit(row.label, w - 3 - (vw > 0 and vw + 1 or 0)), row.dim and "gray" or row.labelColour or row.value and "white" or row.colour or "white", bg)
        if vw > 0 then text(w - vw, y, fit(value, vw), row.colour or "lightGray", bg) end
        if row.act then zones[#zones + 1] = { 1, w, y, function() st.sel = n; row.act() end } end
      end
    end

    text(1, h - 1, fit(" " .. st.msg[1], w), st.msg[2])
    local x = 1
    if st.view == "main" then
      x = button(x, h, " Save ", "black", "lime", function() st.done = "save" end)
      x = button(x, h, " Cancel ", "white", "red", function() st.done = "cancel" end)
    else
      x = button(x, h, " Back ", "black", "lightGray", function()
        go(st.view == "pick" and st.c.key == "newInput" and "inputs" or st.view == "pick" and st.c.worker and "workers" or "main")
        say("Tap a setting to change it.")
      end)
    end
    if pages > 1 then
      x = button(x, h, " < ", "white", page > 1 and "gray" or "black", function()
        if i == 1 then st.sel = math.max(1, st.sel - per) else st.pages[i] = page - 1 end
      end)
      x = button(x, h, " > ", "white", page < pages and "gray" or "black", function()
        if i == 1 then st.sel = math.min(#list, st.sel + per) else st.pages[i] = page + 1 end
      end)
    end
    if st.view == "pick" and x + 7 <= w then
      button(x, h, " Empty ", st.empty and "black" or "white", st.empty and "yellow" or "gray", function()
        st.empty, st.sel, st.pages = not st.empty, 1, {}
      end)
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

  local function drawAll(list)
    local zones = {}
    for i, scr in ipairs(o.screens) do
      if scr.target then zones[i] = draw(i, scr, list) end
    end
    return zones
  end

  readChests()
  while not st.done do
    if st.view == "workers" and not st.found then
      say("Looking for enrichers and smelters...", "lightBlue")
      drawAll(rows())
      local found, why = o.workers()
      st.found, st.why = found or {}, why
      say(#st.found > 0 and "Tap one to pick its ender chest here." or "Nothing found.", #st.found > 0 and "lightGray" or "orange")
    end
    local list = rows()
    st.sel = math.max(1, math.min(st.sel, #list))
    local zones = drawAll(list)
    local ev = { os.pullEvent() }
    local e, a = ev[1], ev[2]
    if o.onEvent then o.onEvent(ev) end
    local tapped
    for i, scr in ipairs(o.screens) do
      local x, y = scr.target and scr:clicked(ev)
      if x and zones[i] then
        for _, z in ipairs(zones[i]) do
          if y == z[3] and x >= z[1] and x <= z[2] then tapped = z[4] end
        end
      end
    end
    if tapped then
      tapped()
    elseif e == "peripheral" or e == "peripheral_detach" then
      for _, scr in ipairs(o.screens) do
        if scr.opts then scr:refresh() end
      end
      readChests()
    elseif e == "key" then
      local per = math.max(1, select(2, o.screens[1]:size()) - 4)
      if a == keys.up then st.sel = st.sel - 1
      elseif a == keys.down then st.sel = st.sel + 1
      elseif a == keys.pageUp then st.sel = st.sel - per
      elseif a == keys.pageDown then st.sel = st.sel + per
      elseif a == keys.enter then
        local row = list[st.sel]
        if row and row.act then row.act() end
      elseif a == keys.backspace then
        if st.filter ~= "" then st.filter, st.sel = st.filter:sub(1, -2), 1 end
      end
    elseif e == "char" and st.view == "pick" then
      st.filter, st.sel = st.filter .. a, 1
    elseif e == "mouse_scroll" then
      local per = math.max(1, select(2, o.screens[1]:size()) - 4)
      st.sel = st.sel + a * per
    end
    if st.done == "save" and (not s.input or not s.output) then
      st.done = nil
      say("Pick the input and output chests first.", "orange")
    end
  end
  -- the program's own screens draw next: make sure they aren't skipped as unchanged
  for _, scr in ipairs(o.screens) do scr.last = nil end
  return st.done == "save"
end

return setupui
