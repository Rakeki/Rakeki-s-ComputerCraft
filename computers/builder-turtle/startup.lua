-- Keep the builder running: it carries on with an unfinished building, or
-- waits for one from a projector. If it ever stops or crashes, start it again.
while true do
  shell.run("builder")
  print("Builder stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
