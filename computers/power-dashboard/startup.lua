-- Keep the power dashboard running: if it ever stops or crashes, start it again.
while true do
  shell.run("power")
  print("Power dashboard stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
