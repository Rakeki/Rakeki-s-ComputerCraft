-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep the feeder running: if it ever stops or crashes, start it again.
while true do
  shell.run("cannon")
  print("Cannon feeder stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
