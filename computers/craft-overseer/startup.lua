-- Keep the crafting overseer running: if it ever stops or crashes, start it again.
while true do
  shell.run("overseer")
  print("Overseer stopped. Restarting in 5s (Ctrl+T to cancel)")
  sleep(5)
end
