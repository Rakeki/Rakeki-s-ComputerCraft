-- Keep the crafter running: if it ever stops or crashes, start it again.
while true do
  shell.run("crafter")
  print("Crafter stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
