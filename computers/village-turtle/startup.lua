-- Pick the village back up after a reboot or chunk reload.
if fs.exists("/.village_job") or fs.exists("/.village_job.tmp") then
  shell.run("village", "resume")
end
