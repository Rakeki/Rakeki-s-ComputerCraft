-- Saves errors to /errors.log on this computer, in one format shared by every
-- program, so a crash can be read after the screen has scrolled away or the
-- computer has rebooted. Read it with `edit /errors.log`.
--
--   local errlog = require("lib.errlog")
--   errlog.init("excavate", function() return { pos = nav.getPos() } end)
--   local ok, err = errlog.pcall(run)              -- pcall that logs the error and a stack trace
--   errlog.error("chest missing", { slot = 3 })    -- log an error you caught yourself
--   errlog.warn("fuel low")                        -- worth knowing, not fatal
--
-- The function given to init is called each time something is logged and its
-- fields are added to the entry (where the turtle was, which job, ...).
--
-- Each entry looks like this, with a blank line after it:
--
--   [2026-10-25 14:05:12 | day 12 06:30] ERROR excavate (Excavator-7 #7)
--     excavate.lua:312: Out of fuel
--     pos: x=10 y=64 z=-3
--     fuel: 0
--     stack traceback:
--       excavate.lua:312: in function 'refuel'
--
-- The same message again within REPEAT_GAP seconds isn't written twice; the
-- next different entry says how many were skipped. Holding Ctrl+T
-- ("Terminated") is never logged.
local errlog = {}

local PATH = "/errors.log"
local MAX_BYTES = 16 * 1024 -- trim the oldest entries past this; computers have little disk
local KEEP_BYTES = 8 * 1024 -- how much to keep when trimming
local REPEAT_GAP = 60 -- seconds; an identical message within this is counted, not written
local MAX_TRACE_LINES = 12 -- stack traces deeper than this are cut short

local program, contextFn
local last = { key = nil, at = -math.huge, skipped = 0 }

local function programName()
  if program then return program end
  if shell and shell.getRunningProgram then
    local name = fs.getName(shell.getRunningProgram() or ""):gsub("%.lua$", "")
    if name ~= "" then return name end
  end
  return "unknown"
end

local function stamp()
  local real = os.date and os.date("%Y-%m-%d %H:%M:%S") or "?"
  local game = ("day %d %s"):format(os.day(), textutils.formatTime(os.time(), true))
  return ("[%s | %s]"):format(real, game)
end

local function who()
  local id = "#" .. os.getComputerID()
  local label = os.getComputerLabel()
  return label and (label .. " " .. id) or id
end

local function describe(value)
  if type(value) == "table" then
    local parts = {}
    for k, v in pairs(value) do parts[#parts + 1] = ("%s=%s"):format(tostring(k), tostring(v)) end
    table.sort(parts)
    return table.concat(parts, " ")
  end
  return tostring(value)
end

-- Every line of an entry is indented, so an entry never contains a blank line
-- and "\n[" only ever starts a new entry.
local function addIndented(lines, text, indent)
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = indent .. line end
end

-- Keep the newest entries once the file gets big. Cuts at an entry boundary
-- and writes a temp file first, so a crash mid-trim never loses the log.
local function trim()
  if not fs.exists(PATH) or fs.getSize(PATH) <= MAX_BYTES then return end
  local f = fs.open(PATH, "r")
  local text = f.readAll() or ""
  f.close()
  local tail = text:sub(-KEEP_BYTES)
  local start = tail:find("\n%[")
  tail = start and tail:sub(start + 1) or tail
  local tmp = PATH .. ".tmp"
  f = fs.open(tmp, "w")
  f.write("(older entries removed to save space)\n\n" .. tail)
  f.close()
  fs.delete(PATH)
  fs.move(tmp, PATH)
end

-- A full disk or a read-only file must never turn one error into two.
local function append(lines)
  return (pcall(function()
    local f = fs.open(PATH, "a")
    if not f then return end
    f.write(table.concat(lines, "\n") .. "\n\n")
    f.close()
    trim()
  end))
end

---------------------------------------------------------------- api

-- name: what entries are filed under (defaults to the running program's file name).
-- context: optional function returning a table of fields added to every entry.
function errlog.init(name, context)
  program, contextFn = name, context
end

-- Write one entry. level: "ERROR" or "WARN". message: the error (any value).
-- context: optional table of extra fields, e.g. { job = "row 3" };
-- context.trace is written last as the stack trace.
function errlog.write(level, message, context)
  message = tostring(message)
  if message == "Terminated" then return false end

  local key = level .. "|" .. programName() .. "|" .. message
  local now = os.clock()
  if key == last.key and now - last.at < REPEAT_GAP then
    last.skipped, last.at = last.skipped + 1, now
    return false
  end

  local fields = {}
  if contextFn then
    local ok, extra = pcall(contextFn)
    if ok and type(extra) == "table" then for k, v in pairs(extra) do fields[k] = v end end
  end
  if context then for k, v in pairs(context) do fields[k] = v end end
  if turtle and fields.fuel == nil then fields.fuel = turtle.getFuelLevel() end
  local trace = fields.trace
  fields.trace = nil

  local lines = {}
  if last.skipped > 0 then
    lines[#lines + 1] = ("  (the entry above happened %d more times)"):format(last.skipped)
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = ("%s %s %s (%s)"):format(stamp(), level, programName(), who())
  addIndented(lines, message, "  ")
  local keys = {}
  for k in pairs(fields) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do lines[#lines + 1] = ("  %s: %s"):format(tostring(k), describe(fields[k])) end
  if trace then
    local traceLines = {}
    addIndented(traceLines, trace, "  ")
    for i = 1, math.min(#traceLines, MAX_TRACE_LINES) do lines[#lines + 1] = traceLines[i] end
    if #traceLines > MAX_TRACE_LINES then lines[#lines + 1] = "    ..." end
  end

  last.key, last.at, last.skipped = key, now, 0
  return append(lines)
end

function errlog.error(message, context) return errlog.write("ERROR", message, context) end
function errlog.warn(message, context) return errlog.write("WARN", message, context) end

-- A drop-in pcall(fn, ...) that logs the error, with a stack trace, before
-- returning it.
function errlog.pcall(fn, ...)
  local args = table.pack(...)
  local trace
  local result = table.pack(xpcall(function() return fn(table.unpack(args, 1, args.n)) end, function(e)
    if debug and debug.traceback then trace = debug.traceback(nil, 2) end
    return e
  end))
  if not result[1] then errlog.error(result[2], { trace = trace }) end
  return table.unpack(result, 1, result.n)
end

-- The newest entries, oldest first, each as one string (up to n, default 5).
function errlog.recent(n)
  if not fs.exists(PATH) then return {} end
  local f = fs.open(PATH, "r")
  local text = f.readAll() or ""
  f.close()
  local entries = {}
  for chunk in (text .. "\n\n"):gmatch("(.-)\n\n") do
    if chunk:sub(1, 1) == "[" then entries[#entries + 1] = chunk end
  end
  local out = {}
  for i = math.max(1, #entries - (n or 5) + 1), #entries do out[#out + 1] = entries[i] end
  return out
end

function errlog.clear()
  if fs.exists(PATH) then fs.delete(PATH) end
end

errlog.PATH = PATH

return errlog
