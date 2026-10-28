# mine-turtle

- **Type:** mining turtle with an ender modem (or wireless modem) on the other side
- **Computer IDs:** (list each miner here)
- **Label:** 
- **Location:** its home: where you place it, with its own chest behind it
- **Peripherals:** diamond pickaxe + modem

The same code runs on every miner. Make as many as you like.

## What it does

1. Asks the [server](../mine-server/README.md) for the next queued chunk.
2. Flies there at its own cruise height, then mines the whole chunk from
   `yTop` down to `yBottom` in 3-high layers. Each pass digs the block above
   and the block below.
3. Throws away junk (cobble, dirt, etc.) as it goes. When its inventory is full or
   fuel is low, it flies home, burns the coal it dug, empties into its own
   chest, tops up fuel from it (or from a fuel chest beside it), and goes back
   to where it stopped.
4. Reports progress to the server and repeats. With nothing queued (or when
   the server pauses), it goes home, unloads and waits there, facing the way
   you placed it.

Every miner has its own home and chest, so they never queue for a shared
dock. The server never mines a chunk that has a miner's home in it.

It never digs chests, barrels, furnaces, hoppers, spawners or ComputerCraft
blocks, including other turtles.

## Files

- `startup.lua`: starts the miner on boot and restarts it if it ever stops (first it fetches any newer version from the website)
- `miner.lua`: job loop, mining pattern, trips home
- [`lib/nav.lua`](../../lib/nav.lua): position tracking and safe movement (shared; copy it to `/lib/nav.lua` on the turtle)
- [`lib/report.lua`](../../lib/report.lua): reports to the [status server](../status-server/README.md) (copy it to `/lib/report.lua`)
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

Position is saved to `/.nav_state`, the current job to `/.automine_job` and
its home to `/.automine_home`, so a turtle picks up where it left off after a
reboot or chunk reload. All are written through a temp file so a crash
mid-save can't corrupt them.

If the server goes down, turtles keep mining their current chunk (and unload
at home as usual) and wait for it to come back before asking for a new job.

## Setup

1. Craft a mining turtle and an ender modem (or wireless modem) together.
2. Place it where it should live, with open sky above it, and put a chest
   **directly behind it**. That spot is its home: it unloads, refuels and
   waits there. A second chest on its left or right is used for fuel; without
   one it refuels from its own chest, which fills up with the coal it mines.
   Put a little coal in the chest to start with. Give every miner its own spot
   and chest; side by side is fine.
3. Put a bit of coal in the turtle and run `refuel all`.
4. Copy the files on and reboot. It names itself `Miner-<id>` so it keeps its
   files if you break it, and saves its spot as home on the first start.
5. **With GPS** (recommended) it finds its own position and facing. It steps
   forward once to work out its facing, so give it fuel and room in front first.
   **Without GPS** it asks once for its position and facing. Press F3, look at
   the turtle's block and type the X Y Z from **Targeted Block** (not your own
   position, which is the block you're standing on). For facing, stand behind it
   looking the same way and read "Facing".

```
miner home      -- make this spot my home (chest behind me), e.g. to move it
```

With GPS it also checks its position every 32 blocks mined and before each
trip, and corrects itself (and says so) if it has slipped. Without GPS, on
every reboot it trusts its saved position, but first waits 10 seconds: press
a key if you moved it, then type its position again.

## Things to know

- **Ending up somewhere wrong?** On the turtle, run `gps locate` and compare it
  with F3's Targeted Block while you look at the turtle. If they differ, the
  GPS hosts have the wrong coordinates. If they match, its home is wrong: put
  it on its spot (chest behind it), press Ctrl+T and run `miner home`.
  The turtle won't unload at a home with no chest: it stops and says so instead.
- **No home yet:** a miner waits (status "no home") until it has a chest right
  behind it. A miner that was mid-job when it updated to homes says so too:
  put it on its spot with a chest behind it, press Ctrl+T and run `miner home`.
- **Use ender modems** if you can. A wireless modem only reaches about 64 blocks
  underground, and a turtle out of range can't get a new job.
- **Chunk loading**: turtles freeze when their chunk unloads (when you're far
  away) and continue when it loads again.
- A full chunk (y 60 to -59) takes a few hours per turtle. Lower `yTop` in the
  server config for faster deep-ore runs.
- **GPS**: put 4 computers with wireless modems high up, not all in one plane,
  and run `gps host <x> <y> <z>` on each with its own coordinates.
