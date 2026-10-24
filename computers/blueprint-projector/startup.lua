-- Keep the projection and its control panel running: if the program ever
-- stops or crashes, start it again.
while true do
  shell.run("projector")
  print("Projector stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
