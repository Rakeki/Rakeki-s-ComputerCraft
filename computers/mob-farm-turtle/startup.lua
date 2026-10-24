-- Pick an unfinished mob farm back up after a reboot or chunk reload.
if fs.exists("/.mobfarm_job") or fs.exists("/.mobfarm_job.tmp") then
  shell.run("mobfarm", "resume")
end
