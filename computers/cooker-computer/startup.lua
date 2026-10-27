-- Keep the cooker running: if it ever stops or crashes, start it again.
while true do
  shell.run("cooker")
  print("Cooker stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
