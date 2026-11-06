-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep the furnaces going after a reboot or chunk reload ('furnace cancel' stops it).
if fs.exists("/.furnace_job") or fs.exists("/.furnace_job.tmp") then
  shell.run("furnace", "resume")
end
