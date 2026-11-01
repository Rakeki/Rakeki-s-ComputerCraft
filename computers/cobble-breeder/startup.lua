-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Not set up yet: leave the terminal free for 'breed setup'.
if not fs.exists("/.breed_setup") then
  print("Breeder: type 'breed setup' to get started.")
  return
end

-- Keep the breeder running: if it ever stops or crashes, start it again.
while true do
  shell.run("breed")
  print("Breeder stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
