-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Start the stash (the first time it opens the setup screen) and keep it
-- running: if it ever stops or crashes, start it again. If it stopped before
-- it was set up (setup cancelled, chests not joined yet), leave its message on
-- screen instead of opening setup again.
while true do
  shell.run("stash")
  if not fs.exists("/.stash_setup") then break end
  print("Stash stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
