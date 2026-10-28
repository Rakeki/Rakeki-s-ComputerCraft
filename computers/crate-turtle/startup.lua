-- Get newer versions from the website first ('set install.autoupdate false' turns this off).
if fs.exists("/install.lua") then shell.run("/install.lua", "boot") end

-- Carry on with the crate job after a reboot or chunk reload, and start it
-- again if it stops while there's still a job ('crate stop' forgets it).
if not (fs.exists("/.crate_job") or fs.exists("/.crate_job.tmp")) then
  print("No crate job yet. Type 'crate' to start (or 'crate stock 1000').")
end
while fs.exists("/.crate_job") or fs.exists("/.crate_job.tmp") do
  shell.run("crate", "resume")
  if fs.exists("/.crate_job") or fs.exists("/.crate_job.tmp") then
    print("Crate stopped. Restarting in 5s (Ctrl+T to cancel)")
    sleep(5)
  end
end
