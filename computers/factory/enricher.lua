-- The enricher is part of the factory now (factory.lua): 'enricher ...'
-- still works and runs 'factory ...' ('enricher add' adds a chamber).
local args = { ... }
if args[1] == "add" and args[2] ~= "crusher" and args[2] ~= "washer" then table.insert(args, 2, "chamber") end
if args[1] == "remove" and args[2] then
  print("Machines are numbered across the whole factory now: 'factory remove' lists them.")
  args = { "remove" }
end
shell.run("factory", table.unpack(args))
