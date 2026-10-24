-- Keep the miner running: if it ever stops or crashes, start it again.
while true do
  shell.run("miner")
  print("Miner stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
