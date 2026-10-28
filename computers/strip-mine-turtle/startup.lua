-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Pick an unfinished strip mine back up after a reboot or chunk reload.
if fs.exists("/.stripmine_job") or fs.exists("/.stripmine_job.tmp") then
  shell.run("stripmine", "resume")
end
