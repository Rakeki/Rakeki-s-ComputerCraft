-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Keep the stash running once it's set up: if it ever stops or crashes, start it again.
if fs.exists("/.stash_setup") then
  while true do
    shell.run("stash")
    print("Stash stopped. Restarting in 5s (Ctrl+T to cancel)")
    sleep(5)
  end
end
