-- Keep the tree farm going after a reboot or chunk reload.
if fs.exists("/.treefarm_job") or fs.exists("/.treefarm_job.tmp") then
  shell.run("treefarm", "resume")
end
