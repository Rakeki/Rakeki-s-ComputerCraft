-- AutoMine settings. Edit these, then reboot the server. Turtles pick up
-- changes the next time they ask for a job.
return {
  -- Turtles travel at cruiseY + (turtle ID % lanes) so they don't collide.
  -- Set it above your tallest build: turtles dig through anything in their path
  -- (except chests, barrels, furnaces, hoppers, spawners and ComputerCraft blocks).
  cruiseY = 100,
  lanes = 8,

  -- Vertical range mined in each chunk. Keep yBottom at -59 or higher to stay clear of bedrock.
  -- Lower yTop (e.g. 16) for faster, deep-ore-only runs.
  yTop = 60,
  yBottom = -59,

  -- Monitors, by side ("top") or network name ("monitor_0"; run `peripherals` to list).
  --   mapMonitor: show the touch map on this monitor instead of the computer's screen.
  --   statusMonitor: status board. nil = use any other attached monitor, false = none.
  mapMonitor = nil,
  statusMonitor = nil,

  -- Fuel the turtle tops up to at home, and the minimum it will leave with
  -- if the fuel chest runs dry.
  targetFuel = 5000,
  minFuel = 1000,

  -- Thrown away while mining instead of being carried home.
  junk = {
    "minecraft:cobblestone",
    "minecraft:cobbled_deepslate",
    "minecraft:stone",
    "minecraft:deepslate",
    "minecraft:dirt",
    "minecraft:gravel",
    "minecraft:andesite",
    "minecraft:diorite",
    "minecraft:granite",
    "minecraft:tuff",
    "minecraft:calcite",
    "minecraft:netherrack",
  },
}
