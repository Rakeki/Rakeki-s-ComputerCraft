-- Keep the smelter running: if it ever stops or crashes, start it again.
while true do
  shell.run("smelter")
  print("Smelter stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
