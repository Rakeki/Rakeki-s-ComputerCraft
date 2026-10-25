# strip-mine-turtle

- **Type:** mining turtle, plus a wireless or ender modem for GPS and the [status server](../status-server/README.md) (optional)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Digs a 3×3 main tunnel straight ahead, with 3×3 branch tunnels going off both
sides, and brings everything it finds back to a chest at the start. It works on
its own; no server needed.

Default layout (`stripmine` with no arguments):

- **Main tunnel:** 3 wide (centred on the turtle) × 3 high (from the turtle's
  block up) × 64 long, counting the start block.
- **Branches:** 3 wide × 3 high × 32 long, on both sides. Neighbouring
  branches have 3 solid blocks between them, so there's a pair every 6 blocks
  (10 pairs by default).

```
   ###   ###   ###
   ###   ###   ###
 C#################...   C = chest, turtle starts just in front of it
   ###   ###   ###
   ###   ###   ###
```

It digs the main tunnel and does each pair of branches as soon as the main
tunnel is open past them: left branch first, then right.

- **Junk:** cobblestone, dirt, deepslate and so on get thrown away when the
  inventory fills.
- **Unloading:** if it's still full after that, it goes back to the start,
  empties into the chest, and carries on where it stopped.
- **Fuel:** it tops itself up to 3000 from the chest, including any coal it
  mined and dropped off itself.
- **Torches:** put torches anywhere in its inventory and it places one every
  8 blocks along the floor of the main tunnel and each branch. It never drops
  or unloads them.

It never digs chests, barrels, furnaces, hoppers, spawners or ComputerCraft
blocks. It doesn't deal with water or lava: they stay where they are, and the
turtle mines straight through them.

## Files

- `stripmine.lua`: the program. Torch spacing, refuel level and the junk list are at the top.
- `startup.lua`: resumes an unfinished job after a reboot or chunk reload
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too, just without reporting.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

## Use

1. Place the turtle on the floor where the tunnel should start, facing the way
   to dig.
2. Put a chest **directly behind** it, with some coal in it.
3. Run:

   ```
   stripmine                 -- 64 long, 32 long branches, 3 blocks apart
   stripmine 100 48 2        -- main length, branch length, gap between branches
   stripmine 80 0            -- just the main tunnel, no branches
   stripmine resume          -- carry on after stopping it
   stripmine here            -- no GPS: "I've put you back on your start block", then carry on
   stripmine cancel          -- forget the current job
   ```

It prints the layout and roughly how much fuel the job needs (about 5,000
for the default size), then waits for Enter.

If the chest fills up or it runs out of fuel, it waits at the start until you
fix it. If something it won't dig (a chest, a spawner) blocks the way, it
stops, says where it's stuck, and keeps retrying.

## Staying on track

Same as the [excavator](../excavate-turtle/README.md#staying-on-track):

- **With GPS** at the start of the job, it checks its position every 20 steps
  and corrects itself. If it's been moved off the mine, it heads back to the
  start.
- **Without GPS**, on resume it waits 10 seconds. If you moved it, press a key,
  put it back on its start block facing the original way, and run
  `stripmine here`.
