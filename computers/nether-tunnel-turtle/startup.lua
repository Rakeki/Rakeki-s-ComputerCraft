-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Pick an unfinished Nether tunnel back up after a reboot or chunk reload.
if fs.exists("/.nethertunnel_job") or fs.exists("/.nethertunnel_job.tmp") then
  shell.run("nethertunnel", "resume")
end
