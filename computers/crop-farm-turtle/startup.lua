-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep the crop farm going after a reboot or chunk reload.
if fs.exists("/.cropfarm_job") or fs.exists("/.cropfarm_job.tmp") then
  shell.run("cropfarm", "resume")
end
