-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Pick an unfinished levelling job back up after a reboot or chunk reload.
if fs.exists("/.level_job") or fs.exists("/.level_job.tmp") then
  shell.run("level", "resume")
end
