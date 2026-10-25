# mine-turtle

- **Type:** mining turtle with an ender modem (or wireless modem) on the other side
- **Computer IDs:** (list each miner here)
- **Label:** 
- **Location:** wherever the server sends it; home is the server's dock
- **Peripherals:** diamond pickaxe + modem

The same code runs on every miner. Make as many as you like.

## What it does

1. Asks the [server](../mine-server/README.md) for the next queued chunk.
2. Flies there at its own cruise height, then mines the whole chunk from
   `yTop` down to `yBottom` in 3-high layers. Each pass digs the block above
   and the block below.
3. Throws away junk (cobble, dirt, etc.) as it goes. When its inventory is full or
   fuel is low, it flies home, empties into the deposit chest, refuels from
   the fuel chest, and goes back to where it stopped.
4. Reports progress to the server and repeats. With nothing queued, it parks
   beside the dock.

It never digs chests, barrels, furnaces, hoppers, spawners or ComputerCraft
blocks, including other turtles.

## Files

- `startup.lua`: starts the miner on boot and restarts it if it ever stops
- `miner.lua`: job loop, mining pattern, dock trips
- [`lib/nav.lua`](../../lib/nav.lua): position tracking and safe movement (shared; copy it to `/lib/nav.lua` on the turtle)
- [`lib/report.lua`](../../lib/report.lua): reports to the [status server](../status-server/README.md) (copy it to `/lib/report.lua`)
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

Position is saved to `/.nav_state` and the current job to `/.automine_job`,
so a turtle picks up where it left off after a reboot or chunk reload. Both
are written through a temp file so a crash mid-save can't corrupt them.

If the server goes down, turtles keep mining their current chunk and wait for
it to come back before asking for anything (a new job, the dock).

## Setup

1. Craft a mining turtle and an ender modem (or wireless modem) together.
2. Place it, put a bit of coal in it, and run `refuel all`.
3. Copy the files on and reboot. It names itself `Miner-<id>` so it keeps its
   files if you break it.
4. **With GPS** (recommended) it finds its own position and facing.
   **Without GPS** it asks once for its coordinates and facing (use F3).

## Things to know

- **Use ender modems** if you can. A wireless modem only reaches about 64 blocks
  underground, and a turtle out of range can't get the dock or a new job.
- **Chunk loading**: turtles freeze when their chunk unloads (when you're far
  away) and continue when it loads again.
- A full chunk (y 60 to -59) takes a few hours per turtle. Lower `yTop` in the
  server config for faster deep-ore runs.
- **GPS**: put 4 computers with wireless modems high up, not all in one plane,
  and run `gps host <x> <y> <z>` on each with its own coordinates.
