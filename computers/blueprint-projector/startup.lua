-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep the projection and its control panel running: if the program ever
-- stops or crashes, start it again.
while true do
  shell.run("projector")
  print("Projector stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
