-- Keep the storage system running: if it ever stops or crashes, start it again.
while true do
  shell.run("storage")
  print("Storage stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
