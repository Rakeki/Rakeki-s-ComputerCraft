-- Overseer bridge: hears every rednet message in range (and every computer's
-- status report) and posts them to the overseer server on your PC
-- (tools/overseer/server.mjs), which shows them in your browser as a live map
-- of where everything is, what it's doing and the messages flying between them.
--
-- Rednet sends every message on the repeat channel (65533) as well as to its
-- recipient, so a modem listening there hears all traffic in range without any
-- other program changing. Use an ender modem to hear everything everywhere.
--
-- Usage:
--   set overseer.url http://127.0.0.1:8090   where the overseer server runs (it prints this)
--   set overseer.key <key>                   the key the server printed
--   overseer test                            send a ping and say what's wrong, if anything
--   overseer                                 run the bridge (startup.lua does this)
local screen = require("lib.screen")
local report = require("lib.report")
local hasErrlog, errlog = pcall(require, "lib.errlog")
if not hasErrlog then errlog = nil end

---------------------------------------------------------------- tunables

local REPEAT = rednet.CHANNEL_REPEAT or 65533 -- every rednet message is sent here too
local POST_EVERY = 1 -- seconds between posts to the server
local MAX_QUEUE = 2000 -- messages held while the server can't be reached; the oldest go first
local MAX_BATCH = 400 -- messages per post
local TIMEOUT = 5 -- seconds a post may take
local BACKOFF_MAX = 30 -- longest wait between tries while the server is down
local SEEN_FOR = 10 -- seconds a message id is remembered (one sent on two modems is heard twice)
local PEEK_FIELDS = 6 -- short fields of each message shown in the packet log
local PEEK_LEN = 40 -- longest text shown per field
local SIZE_FIELDS = 3000 -- fields counted when estimating a message's size
local GPS_EVERY = 300 -- seconds between GPS checks of the bridge's own position

local STATUS_FIELDS = { "label", "kind", "role", "state", "detail", "event", "fuel", "fuelLimit", "uptime", "posFrom" }

settings.define("overseer.url", { description = "Address of the overseer server, e.g. http://127.0.0.1:8090", type = "string" })
settings.define("overseer.key", { description = "The key the overseer server printed when it started", type = "string" })

---------------------------------------------------------------- settings

local function config()
  local url = settings.get("overseer.url")
  if url then url = url:gsub("/+$", "") end
  return url, settings.get("overseer.key")
end

local function ingestUrl(url) return url .. "/api/ingest" end

-- A failed post in plain English, with what to do about it.
local function explain(err, code, url)
  if not http then return "CC's HTTP API is turned off on this server (http.enabled in computercraft-server.toml)." end
  if code == 401 then return "Wrong key. Type 'set overseer.key <key>' with the key the server printed." end
  if code == 404 then return "Something answered at " .. url .. ", but not the overseer server. Check the port." end
  if code then return ("The server answered %d: %s"):format(code, tostring(err)) end
  local e = tostring(err or "no answer"):lower()
  if e:find("not permitted") or e:find("blocked") or e:find("denied") then
    return "CC blocks this address. Allow it in computercraft-server.toml under [[http.rules]] (see the README)."
  end
  if e:find("malformed") or e:find("invalid") then return "That address isn't a valid URL: " .. url end
  if e:find("unknown host") or e:find("resolve") then return "Can't find that host name: " .. url end
  if e:find("refused") or e:find("connect") or e:find("timed out") or e:find("timeout") then
    return "Nothing answered at " .. url .. ". Is the overseer server running, and is the address right?"
  end
  return tostring(err)
end

---------------------------------------------------------------- json-safe copies

local function clean(v)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return tostring(v) end
    return v
  elseif t == "string" then
    return #v > PEEK_LEN and (v:sub(1, PEEK_LEN - 1) .. "~") or v
  elseif t == "boolean" then
    return v
  end
  return nil
end

local function cleanPos(p)
  if type(p) ~= "table" then return nil end
  local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
  if not (x and y and z) then return nil end
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
end

-- Roughly how big a message is once serialised, without serialising it.
local function sizeOf(v, budget)
  local t = type(v)
  if t == "string" then return #v + 2 end
  if t == "number" then return 6 end
  if t == "boolean" then return 5 end
  if t ~= "table" then return 4 end
  local n = 2
  for k, x in pairs(v) do
    budget.left = budget.left - 1
    if budget.left <= 0 then return n end
    n = n + sizeOf(k, budget) + sizeOf(x, budget) + 2
  end
  return n
end

-- A few short fields of a message for the packet log: never the big ones.
local function peekOf(msg)
  local out, n = {}, 0
  for k, v in pairs(msg) do
    if type(k) == "string" and k ~= "type" and k ~= "re" and k ~= "id" and k ~= "sType" and type(v) ~= "table" then
      local c = clean(v)
      if c ~= nil then
        out[k] = c
        n = n + 1
        if n >= PEEK_FIELDS then break end
      end
    end
  end
  if n == 0 then return nil end
  return out
end

local function statusOf(msg)
  local s = {}
  for _, k in ipairs(STATUS_FIELDS) do s[k] = clean(msg[k]) end
  if type(msg.detail) == "string" then s.detail = msg.detail:sub(1, 120) end
  if type(msg.event) == "string" then s.event = msg.event:sub(1, 120) end
  s.pos = cleanPos(msg.pos)
  return s
end

---------------------------------------------------------------- what it heard

local queue, qHead, qTail = {}, 1, 0
local dropped = 0 -- since the last successful post
local seen = {} -- message id -> when to forget it
local heard, protoCount = 0, {}
local perSecond, thisSecond, secondAt = 0, 0, os.clock()

local function push(p)
  qTail = qTail + 1
  queue[qTail] = p
  if qTail - qHead + 1 > MAX_QUEUE then
    queue[qHead] = nil
    qHead = qHead + 1
    dropped = dropped + 1
  end
end

local function capture(replyChannel, wrapper, distance)
  if type(wrapper) ~= "table" or wrapper.nMessageID == nil then return end
  local id = wrapper.nMessageID
  if seen[id] then return end
  seen[id] = os.clock() + SEEN_FOR

  local proto = type(wrapper.sProtocol) == "string" and wrapper.sProtocol or "rednet"
  local body = wrapper.message
  local p = {
    t = os.epoch("utc"),
    from = tonumber(wrapper.nSender) or replyChannel,
    to = tonumber(wrapper.nRecipient) or -1,
    proto = proto,
    size = sizeOf(body, { left = SIZE_FIELDS }),
    dist = distance and math.floor(distance) or nil,
  }
  if type(body) == "table" then
    if type(body.type) == "string" then p.type = body.type:sub(1, 30) end
    if type(body.re) == "string" then p.re = body.re:sub(1, 30) end
    if proto == "dns" and type(body.sType) == "string" then
      p.type = body.sType
      p.peek = { protocol = clean(body.sProtocol), host = clean(body.sHostname) }
    else
      p.peek = peekOf(body)
    end
    if proto == "cc_status" then
      p.status = statusOf(body)
      p.peek = { state = clean(body.state) } -- the rest is in the status
    end
  elseif type(body) == "string" then
    p.type = clean(body)
  end

  push(p)
  heard = heard + 1
  thisSecond = thisSecond + 1
  protoCount[proto] = (protoCount[proto] or 0) + 1
end

local function forgetOld()
  local now = os.clock()
  for id, t in pairs(seen) do if t < now then seen[id] = nil end end
  if now - secondAt >= 1 then
    perSecond = thisSecond / (now - secondAt)
    thisSecond, secondAt = 0, now
  end
end

---------------------------------------------------------------- modems

local function openAll()
  local n = 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      if not peripheral.call(name, "isOpen", REPEAT) then peripheral.call(name, "open", REPEAT) end
      n = n + 1
    end
  end
  return n
end

local function modemNames()
  local wireless, wired = 0, 0
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      if peripheral.call(name, "isWireless") then wireless = wireless + 1 else wired = wired + 1 end
    end
  end
  return wireless, wired
end

---------------------------------------------------------------- posting

local link = { state = "starting", why = nil, lastOk = nil, posts = 0, failures = 0 }
local myPos, gpsAt = nil, -math.huge

local function selfStatus()
  if os.clock() - gpsAt > GPS_EVERY then
    local x, y, z = gps.locate(1)
    gpsAt = os.clock()
    if x then myPos = cleanPos({ x = x, y = y, z = z }) end
  end
  local detail = link.state == "posting"
    and ("%.1f msg/s to the overseer"):format(perSecond)
    or (link.why or "starting")
  return {
    label = os.getComputerLabel() or ("Bridge " .. os.getComputerID()),
    kind = turtle and "turtle" or (pocket and "pocket" or "computer"),
    role = "overseer bridge",
    state = link.state,
    detail = detail,
    uptime = os.clock(),
    pos = myPos,
    posFrom = myPos and "gps" or nil,
  }
end

-- Post one body; returns true, or false and why.
local function post(url, key, body)
  local ok, json = pcall(textutils.serializeJSON, body)
  if not ok then return false, "couldn't write the message list: " .. tostring(json) end
  local res, err, failed = http.post({
    url = ingestUrl(url),
    body = json,
    headers = { ["Content-Type"] = "application/json", ["X-Overseer-Key"] = key or "" },
    timeout = TIMEOUT,
  })
  if res then
    res.close()
    return true
  end
  local code
  if failed then
    code = failed.getResponseCode()
    failed.close()
  end
  return false, explain(err, code, url)
end

local function poster(url, key)
  local wait = POST_EVERY
  while true do
    sleep(wait)
    local batch, last = {}, math.min(qTail, qHead + MAX_BATCH - 1)
    for i = qHead, last do batch[#batch + 1] = queue[i] end
    local body = {
      v = 1,
      now = os.epoch("utc"),
      bridge = { id = os.getComputerID(), label = os.getComputerLabel(), status = selfStatus() },
      packets = batch,
      dropped = dropped,
    }
    local ok, why = post(url, key, body)
    if ok then
      for i = qHead, last do queue[i] = nil end
      qHead = math.max(qHead, last + 1)
      dropped = 0
      link.state, link.why, link.lastOk = "posting", nil, os.clock()
      link.posts, link.failures = link.posts + 1, 0
      report.set("posting", "posting to the overseer server") -- the rate goes in selfStatus, so the dashboard isn't sent a new detail every second
      wait = (qTail - qHead + 1 > MAX_BATCH) and 0.2 or POST_EVERY -- catch up after an outage
    else
      link.failures = link.failures + 1
      link.state, link.why = "waiting", why
      report.set("waiting", why)
      if link.failures == 1 and errlog then errlog.warn("overseer post failed: " .. why) end
      wait = math.min(BACKOFF_MAX, 2 ^ math.min(link.failures, 5))
    end
  end
end

---------------------------------------------------------------- screen

local function ago(t)
  if not t then return "never" end
  local s = math.floor(os.clock() - t)
  if s < 60 then return s .. "s ago" end
  return math.floor(s / 60) .. "m ago"
end

local function draw(s, url)
  local win, w = s:frame()
  local put = screen.put
  put(win, 1, 1, screen.fit(" Overseer bridge", w), "white", "blue")
  put(win, 1, 3, "Server  ", "lightGray")
  put(win, 9, 3, screen.fit(url, w - 9), "white")
  local col = link.state == "posting" and "lime" or (link.state == "starting" and "lightGray" or "orange")
  put(win, 1, 4, "Link    ", "lightGray")
  put(win, 9, 4, screen.fit(link.state == "posting" and ("posting, last " .. ago(link.lastOk)) or link.state, w - 9), col)
  local y = 5
  if link.why then
    for _, line in ipairs(screen.wrap(link.why, w - 2, 4)) do
      put(win, 2, y, line, "orange")
      y = y + 1
    end
  end
  y = y + 1
  local wireless, wired = modemNames()
  put(win, 1, y, ("Heard   %d messages, %.1f/s"):format(heard, perSecond), "white")
  put(win, 1, y + 1, ("Waiting %d to send%s"):format(qTail - qHead + 1, dropped > 0 and (", " .. dropped .. " dropped") or ""), "lightGray")
  put(win, 1, y + 2, ("Modems  %d wireless/ender, %d wired"):format(wireless, wired), wireless + wired > 0 and "lightGray" or "red")
  y = y + 4
  local order = {}
  for p, n in pairs(protoCount) do order[#order + 1] = { p, n } end
  table.sort(order, function(a, b) return a[2] > b[2] end)
  if #order > 0 then put(win, 1, y, "Busiest protocols", "yellow") end
  local _, h = s:size()
  for i, e in ipairs(order) do
    if y + i > h - 1 then break end
    put(win, 2, y + i, screen.fit(e[1], w - 10), "lightGray")
    put(win, w - 7, y + i, ("%7d"):format(e[2]), "white")
  end
  put(win, 1, h, screen.fit("Ctrl+T to stop", w), "gray")
  s:show()
end

---------------------------------------------------------------- commands

local function usage()
  print("Overseer bridge")
  print("  set overseer.url http://<your PC>:8090")
  print("  set overseer.key <key the server printed>")
  print("  overseer test   check the server answers")
  print("  overseer        run the bridge")
end

local function test()
  local url, key = config()
  if not url then usage() return end
  if not http then print(explain(nil, nil, url)) return end
  print("Checking " .. ingestUrl(url) .. " ...")
  local okUrl, why = http.checkURL(ingestUrl(url))
  if not okUrl then print(explain(why, nil, url)) return end
  if not key then print("No key yet: type 'set overseer.key <key>' (the server prints it when it starts).") return end
  local ok, err = post(url, key, { v = 1, ping = true })
  if ok then
    print("The overseer server answered. All good!")
    print("Reboot (or type 'overseer') to start the bridge.")
  else
    print(err)
  end
end

local function run()
  local url, key = config()
  if not url then usage() return end
  if not http then error(explain(nil, nil, url), 0) end
  if openAll() == 0 then error("Attach a wireless or ender modem (or a wired one on the cable to listen to).", 0) end

  require("lib.label").set("Bridge")
  report.init("overseer bridge")
  local s = screen.new(term.current())

  local function listen()
    while true do
      local ev, _, channel, replyChannel, msg, distance = os.pullEvent()
      if ev == "modem_message" and channel == REPEAT then
        capture(replyChannel, msg, distance)
      elseif ev == "peripheral" then
        openAll()
      end
    end
  end

  local function screenLoop()
    while true do
      forgetOld()
      draw(s, url)
      sleep(1)
    end
  end

  parallel.waitForAny(listen, function() poster(url, key) end, screenLoop, report.loop)
end

---------------------------------------------------------------- main

local args = { ... }
if args[1] == "test" then
  test()
elseif args[1] == "help" or args[1] == "-h" then
  usage()
elseif args[1] then
  print("Unknown command: " .. args[1])
  usage()
else
  if errlog then errlog.init("overseer") end
  local ok, err
  if errlog then ok, err = errlog.pcall(run) else ok, err = pcall(run) end
  if not ok then
    report.set("error", tostring(err))
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    printError(err)
    error(err, 0)
  end
end
