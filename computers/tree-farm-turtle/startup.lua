-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep the tree farm going after a reboot or chunk reload.
if fs.exists("/.treefarm_job") or fs.exists("/.treefarm_job.tmp") then
  shell.run("treefarm", "resume")
end
