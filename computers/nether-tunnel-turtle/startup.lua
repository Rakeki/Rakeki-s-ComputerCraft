-- Pick an unfinished Nether tunnel back up after a reboot or chunk reload.
if fs.exists("/.nethertunnel_job") or fs.exists("/.nethertunnel_job.tmp") then
  shell.run("nethertunnel", "resume")
end
