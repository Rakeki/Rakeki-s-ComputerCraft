-- AutoMine settings. Edit these, then reboot the server. Turtles pick up
-- changes the next time they ask for a job.
return {
  -- Where turtles unload and refuel. Leave this nil and let a turtle set it:
  -- put a miner on the dock block and run 'miner dock'. It finds its position
  -- by GPS and the chests around it, and that dock is used over this one.
  -- Without GPS, set it here instead: stand on the deposit chest (your feet are
  -- then in the dock block), press F3 and copy the "Block:" line, not "XYZ:",
  -- e.g. dock = { x = 1499, y = 70, z = 8071, fuelDir = "north" },
  --   * deposit chest goes directly BELOW the dock block
  --   * fuel chest goes right next to the dock block, on the fuelDir side
  --   * keep the column above the dock open: turtles fly straight down into it
  -- The chunk containing the dock is never mined. No jobs go out until there's a dock.
  dock = nil,

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

  -- Fuel the turtle tops up to at the dock, and the minimum it will leave with
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
