-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep following a building the builder turtles were working on before the
-- reboot, so strips still waiting get handed out.
local state = require("lib.files").read("/.build_control")
if state and state.build then shell.run("build", "watch") end
