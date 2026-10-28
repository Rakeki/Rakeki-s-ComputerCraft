-- Keep the guard running: if it ever stops or crashes, start it again.
while true do
  shell.run("fission")
  print("Fission guard stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
