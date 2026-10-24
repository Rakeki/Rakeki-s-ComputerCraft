-- Keep the crop farm going after a reboot or chunk reload.
if fs.exists("/.cropfarm_job") or fs.exists("/.cropfarm_job.tmp") then
  shell.run("cropfarm", "resume")
end
