-- Keep the server running: if it ever stops or crashes, start it again.
while true do
  shell.run("server")
  print("Server stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
