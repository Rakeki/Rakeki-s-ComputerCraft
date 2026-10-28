-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- The deployer is started by hand ('gps-deploy'): nothing else runs on boot.
