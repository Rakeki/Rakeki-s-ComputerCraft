-- Names this computer or turtle "<Name>-<id>" (e.g. "Storage-4",
-- "Excavator-12", "Factory-Smelt-Enrich-7"), so every one reads the same on
-- the status server, the turtle finder and the overseer map, and a turtle
-- keeps its files when it's broken (a labelled turtle keeps its disk).
--
--   local label = require("lib.label")
--   label.set("Storage")                     -- once at start
--   label.set("Factory", { "Smelt", "Saw" }) -- again whenever what it is changes
--
-- A label the player gave it is never touched: it only names a computer with
-- no label, or one still wearing the last label it gave it itself
-- (/.auto_label), so a factory's name follows its parts but a hand-typed
-- 'label set Base furnaces' stays.
local files = require("lib.files")

local label = {}

local AUTO_FILE = "/.auto_label" -- the label this lib last gave the computer
local MAX_LEN = 32 -- CC's longest label

local function build(name, extras)
  local id = "-" .. os.getComputerID()
  local room = MAX_LEN - #id
  local out = name:sub(1, room)
  -- extras that don't fit are left off, so the id is always at the end
  for _, e in ipairs(extras or {}) do
    if #out + 1 + #e > room then break end
    out = out .. "-" .. e
  end
  return out .. id
end

-- What this computer would call itself (nothing is changed).
function label.name(name, extras) return build(name, extras) end

-- Sets the label if it's ours to set. Returns the label it now has.
function label.set(name, extras)
  local want = build(name, extras)
  local now = os.getComputerLabel()
  if now == want then return now end
  if now and now ~= "" then
    local auto = files.read(AUTO_FILE)
    -- a label of the old "<Name>-<id>" kind the turtles always gave themselves counts as ours too
    local ours = (type(auto) == "table" and auto.label == now) or now == build(name)
    if not ours then return now end
  end
  os.setComputerLabel(want)
  files.write(AUTO_FILE, { label = want })
  return want
end

return label
