-- Runs automatically when this computer boots.
-- Reports to the status server; needs a wireless or ender modem and lib/report.lua.
local report = require("lib.report")

report.init("template") -- what this computer is for

local function main()
  report.set("idle", "nothing to do yet")
  print("Hello from " .. (os.getComputerLabel() or ("computer " .. os.getComputerID())))
  while true do
    sleep(60)
  end
end

parallel.waitForAny(main, report.loop)
