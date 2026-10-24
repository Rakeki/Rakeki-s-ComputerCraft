-- Keep the colony dashboard running: if it ever stops or crashes, start it again.
while true do
  shell.run("colony")
  print("Colony dashboard stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
