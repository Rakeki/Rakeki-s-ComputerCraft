-- Runs automatically when this computer boots: keeps the overseer bridge running.

-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

if not settings.get("overseer.url") then
  print("Overseer bridge isn't set up yet. Start the overseer")
  print("server on your PC, then type the two 'set' lines it")
  print("prints, then 'overseer test' and reboot.")
  return
end

-- If it ever stops or crashes, start it again.
while true do
  shell.run("overseer")
  print("Overseer bridge stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
