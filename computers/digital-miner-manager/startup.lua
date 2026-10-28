-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep the Digital Miner manager running: if it ever stops or crashes, start it again.
while true do
  shell.run("dminer")
  print("Digital Miner manager stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
