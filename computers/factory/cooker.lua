-- The cooker is part of the factory now (factory.lua): 'cooker ...' still
-- works and runs 'factory ...' ('cooker add' adds a cooking pot).
local args = { ... }
if args[1] == "add" then table.insert(args, 2, "pot") end
if args[1] == "remove" and args[2] then
  print("Machines are numbered across the whole factory now: 'factory remove' lists them.")
  args = { "remove" }
end
shell.run("factory", table.unpack(args))
