-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Pick the village back up after a reboot or chunk reload.
if fs.exists("/.village_job") or fs.exists("/.village_job.tmp") then
  shell.run("village", "resume")
end
