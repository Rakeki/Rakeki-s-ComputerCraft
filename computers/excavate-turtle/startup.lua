-- Pick an unfinished excavation back up after a reboot or chunk reload.
if fs.exists("/.excavate_job") or fs.exists("/.excavate_job.tmp") then
  shell.run("excavate", "resume")
end
