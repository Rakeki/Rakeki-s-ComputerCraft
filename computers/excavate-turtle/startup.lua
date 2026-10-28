-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Pick an unfinished excavation back up after a reboot or chunk reload.
if fs.exists("/.excavate_job") or fs.exists("/.excavate_job.tmp") then
  shell.run("excavate", "resume")
end
