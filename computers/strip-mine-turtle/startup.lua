-- Pick an unfinished strip mine back up after a reboot or chunk reload.
if fs.exists("/.stripmine_job") or fs.exists("/.stripmine_job.tmp") then
  shell.run("stripmine", "resume")
end
