-- Crash-safe save files: a Lua table written to a temp file first and then
-- moved into place, so a crash or chunk unload mid-save never leaves a
-- broken file (the temp one is read if the move didn't happen).
--
--   local files = require("lib.files")
--   files.write("/.myjob_job", job)    -- any serialisable table
--   local job = files.read("/.myjob_job") -- nil if there's none
--   files.delete("/.myjob_job")
--
-- lib/nav.lua's writeFile / readFile / deleteFile are these same functions.
local files = {}

function files.write(path, value)
  local tmp = path .. ".tmp"
  local f = fs.open(tmp, "w")
  f.write(textutils.serialize(value))
  f.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
end

function files.read(path)
  for _, p in ipairs({ path, path .. ".tmp" }) do
    if fs.exists(p) then
      local f = fs.open(p, "r")
      local value = textutils.unserialize(f.readAll())
      f.close()
      if value ~= nil then return value end
    end
  end
end

function files.delete(path)
  for _, p in ipairs({ path, path .. ".tmp" }) do
    if fs.exists(p) then fs.delete(p) end
  end
end

return files
