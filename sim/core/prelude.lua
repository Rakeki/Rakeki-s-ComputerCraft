-- Runs in each simulated computer before CC's own bios.lua: turns the JS
-- natives (__m) into the globals CC's Java side would provide, and makes
-- Fengari's Lua 5.3 look like CC's Lua 5.2 where programs could tell.
local m = __m
__m = nil
local TASK = m.TASK

---------------------------------------------------------------- Lua 5.2 bits

loadstring = function(s, name) return load(s, name) end
unpack = table.unpack
math.pow = function(a, b) return a ^ b end
math.ldexp = function(x, e) return x * 2.0 ^ e end
math.log10 = function(x) return math.log(x, 10) end
math.cosh = function(x) return (math.exp(x) + math.exp(-x)) / 2 end
math.sinh = function(x) return (math.exp(x) - math.exp(-x)) / 2 end
math.tanh = function(x) return math.sinh(x) / math.cosh(x) end
math.frexp = function(x)
  if x == 0 then return 0, 0 end
  local e = math.floor(math.log(math.abs(x), 2)) + 1
  return x / 2 ^ e, e
end
table.maxn = function(t) local n = 0 for k in pairs(t) do if type(k) == "number" and k > n then n = k end end return n end

-- Lua 5.2's string.format takes 1.5 for %d (it truncates), and every number
-- is a double, so %d prints os.epoch("utc"); Fengari's integers are 32-bit
-- and 5.3 errors on both. Truncate, and print big ones with %.0f.
local format = string.format
string.format = function(fmt, ...)
  local args = table.pack(...)
  local i, n, f = 1, 0, tostring(fmt)
  local out = {}
  while true do
    local s = f:find("%", i, true)
    if not s then out[#out + 1] = f:sub(i) break end
    if f:sub(s + 1, s + 1) == "%" then
      out[#out + 1] = f:sub(i, s + 1)
      i = s + 2
    else
      local _, e, flags, spec = f:find("^([-+ #0]*%d*%.?%d*)(%a)", s + 1)
      if not e then out[#out + 1] = f:sub(i) break end
      n = n + 1
      local v = args[n]
      if type(v) == "string" and (spec == "d" or spec == "i") then v = tonumber(v) or v end
      if (spec == "d" or spec == "i" or spec == "x" or spec == "X" or spec == "o" or spec == "c") and type(v) == "number" and math.type(v) == "float" then
        if v ~= v or v == math.huge or v == -math.huge then v = 0
        else v = v >= 0 and math.floor(v) or math.ceil(v) end
        local int = math.tointeger(v)
        if int then v = int
        elseif spec == "d" or spec == "i" then spec = ".0f"; flags = flags:gsub("%.%d*", "") end
      end
      args[n] = v
      out[#out + 1] = f:sub(i, s) .. flags .. spec
      i = e + 1
    end
  end
  return format(table.concat(out), table.unpack(args, 1, args.n))
end

-- Fengari's integers are 32-bit signed, so bit32 works on those and hands
-- back unsigned values the way CC does
local function i32(x)
  x = math.floor(x) % 4294967296
  if x >= 2147483648 then x = x - 4294967296 end
  return math.tointeger(x)
end
local function u32(r) if r < 0 then return r + 4294967296 end return r end
bit32 = {
  band = function(...) local r = -1 for _, v in ipairs({ ... }) do r = r & i32(v) end return u32(r) end,
  bor = function(...) local r = 0 for _, v in ipairs({ ... }) do r = r | i32(v) end return u32(r) end,
  bxor = function(...) local r = 0 for _, v in ipairs({ ... }) do r = r ~ i32(v) end return u32(r) end,
  bnot = function(a) return u32(~i32(a)) end,
  lshift = function(a, n) if n >= 32 then return 0 end return u32(i32(a) << n) end,
  rshift = function(a, n) if n >= 32 then return 0 end return u32(i32(a) >> n) end,
  arshift = function(a, n)
    local x = i32(a)
    if x < 0 then
      if n >= 32 then return 4294967295 end
      return u32((x >> n) | ~(-1 >> n))
    end
    if n >= 32 then return 0 end
    return u32(x >> n)
  end,
  btest = function(...) return bit32.band(...) ~= 0 end,
  extract = function(n, f, w) w = w or 1 return u32((i32(n) >> f) & ((1 << w) - 1)) end,
}

-- Fengari's own libraries that CC doesn't have
local date = os.date
os = {}
io = nil
package = nil
require = nil
dofile = nil
loadfile = nil
print = nil

---------------------------------------------------------------- tasks

-- Wait for a task_complete event for this id (CC's main-thread calls).
local function await(id)
  while true do
    local ev = table.pack(coroutine.yield("task_complete"))
    if ev[1] == "terminate" then error("Terminated", 0) end
    if ev[1] == "task_complete" and ev[2] == id then
      if ev[3] then return table.unpack(ev, 4, ev.n) end
      error(ev[4], 3)
    end
  end
end
-- a native call that may hand back a task to wait for
local function tasked(f)
  return function(...)
    local r = table.pack(f(...))
    if r[1] == TASK then return await(r[2]) end
    return table.unpack(r, 1, r.n)
  end
end

---------------------------------------------------------------- os

for k, v in pairs(m.os) do os[k] = v end
os.date = date
os.computerID = os.getComputerID
os.computerLabel = os.getComputerLabel

---------------------------------------------------------------- the rest

term = m.term
fs = m.fs
peripheral = {}
for k, v in pairs(m.peripheral) do peripheral[k] = v end
peripheral.call = tasked(m.peripheral.call)
redstone = m.redstone
rs = redstone
if m.http then http = m.http end
if m.turtle then
  turtle = {}
  for k, v in pairs(m.turtle) do turtle[k] = tasked(v) end
end
if m.pocket then pocket = m.pocket end
if m.commands then
  commands = {}
  for k, v in pairs(m.commands) do commands[k] = tasked(v) end
end

_HOST = m.host
_CC_DEFAULT_SETTINGS = m.defaultSettings or ""

-- The bios, from CC's ROM
local bios, err = load(m.bios, "@bios.lua", "t", _G)
if not bios then error(err) end
__bios = bios
