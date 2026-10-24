-- Keep the status server running: if it ever stops or crashes, start it again.
while true do
  shell.run("server")
  print("Status server stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
