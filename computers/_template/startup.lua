-- Runs automatically when this computer boots.
-- Reports to the status server; needs a wireless or ender modem and lib/report.lua.
-- Errors are saved to /errors.log through lib/errlog.lua.

-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

local report = require("lib.report")
local errlog = require("lib.errlog")

report.init("template") -- what this computer is for
errlog.init("template")

local function main()
  report.set("idle", "nothing to do yet")
  print("Hello from " .. (os.getComputerLabel() or ("computer " .. os.getComputerID())))
  while true do
    sleep(60)
  end
end

parallel.waitForAny(function()
  local ok, err = errlog.pcall(main)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
