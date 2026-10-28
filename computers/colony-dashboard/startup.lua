-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep the colony dashboard running: if it ever stops or crashes, start it again.
while true do
  shell.run("colony")
  print("Colony dashboard stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
