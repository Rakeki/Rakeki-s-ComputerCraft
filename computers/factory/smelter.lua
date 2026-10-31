-- The smelter is part of the factory now (factory.lua): 'smelter ...' still
-- works and runs 'factory ...' ('smelter add' adds a Mekanism smelter).
local args = { ... }
if args[1] == "add" and args[2] ~= "fan" and args[2] ~= "smokefan" then table.insert(args, 2, "smelter") end
if args[1] == "remove" and args[2] then
  print("Machines are numbered across the whole factory now: 'factory remove' lists them.")
  args = { "remove" }
end
shell.run("factory", table.unpack(args))
