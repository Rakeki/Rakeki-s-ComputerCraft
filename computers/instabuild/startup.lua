-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Serving the blueprint projector before the reboot: carry on.
if fs.exists("/.instabuild_serve") then shell.run("instabuild", "serve") end
