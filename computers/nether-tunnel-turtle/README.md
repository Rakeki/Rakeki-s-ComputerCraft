# nether-tunnel-turtle

- **Type:** mining turtle, plus a wireless or ender modem for GPS and the [status server](../status-server/README.md) (optional)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Digs a straight 3×3 tunnel through the Nether and keeps it sealed, so you can
walk it without lava pouring in or falling out into a lava lake. It works on
its own; no server needed.

Default size (`nethertunnel` with no arguments): 3 wide (centred on the
turtle) × 3 high (from the turtle's block up) × 128 long, counting the start
block. That's about 1,000 blocks of travel in the Overworld.

It digs one 3×3 slice at a time and, from inside each block it opens up,
checks every side:

- **Holes get patched.** Where the walls, floor or ceiling are missing (a cave,
  open air over a lava lake, a ravine) it puts a block there. Over a lava
  lake you end up with a sealed bridge.
- **Lava never gets in.** Lava next to the tunnel is walled off, and lava
  in the way is covered with a block and then dug out. The part of the tunnel
  it hasn't dug yet is kept solid too, and each block it opens has the turtle
  in it until all its sides are sealed, so lava never has an open way in.
  The far end is sealed when it finishes.
- **Lava for fuel.** Give it an empty bucket and it scoops up the lava
  sources it meets and burns them (1,000 fuel each), as long as its tank has
  room.
- **Falling blocks and fire.** Gravel, sand, fire, vines, roots and fungus
  in the walls are cleared and replaced with a solid block, so nothing drops
  into the tunnel later.
- **Mobs** in its way get attacked.
- **Patch blocks.** It uses cobblestone, blackstone, stone and the like
  first (they stand up to ghast fireballs better), then netherrack, which it
  digs plenty of. It always keeps 128 of them when it throws junk away or
  unloads. If it runs out it stops where it is and waits for more.
- **Junk:** netherrack, soul sand, soul soil, basalt, blackstone, gravel and
  the usual stone get thrown away when the inventory fills.
- **Unloading:** if it's still full after that, it goes back to the start,
  empties into the chest, and carries on where it stopped. While there it
  tops up its fuel and takes patch blocks out of the chest if it's short.
- **Fuel:** it tops itself up to 3000 from the chest, including any coal it
  mined.
- **Torches:** put torches anywhere in its inventory and it places one
  every 8 blocks along the tunnel floor. It never drops or unloads them.

The start end is left open as the way in; that side is yours to deal with.
It never digs chests, barrels, furnaces, hoppers, spawners (Nether fortresses
have blaze spawners) or ComputerCraft blocks.

## Files

- `nethertunnel.lua`: the program. Default length, refuel level, patch blocks, torch spacing and the junk list are at the top.
- `startup.lua`: resumes an unfinished job after a reboot or chunk reload
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too, just without reporting.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

## Use

1. Place the turtle on the floor where the tunnel should start, facing the way
   to dig.
2. Put a chest **directly behind** it, with some coal in it. A few stacks of
   cobblestone in the chest or the turtle make stronger walls.
3. Optional: give the turtle an empty bucket (for lava fuel) and torches.
4. Run:

   ```
   nethertunnel              -- 128 long
   nethertunnel 300          -- 300 long
   nethertunnel resume       -- carry on after stopping it
   nethertunnel here         -- no GPS: "I've put you back on your start block", then carry on
   nethertunnel cancel       -- forget the current job
   ```

It prints the size and roughly how much fuel the job needs (about 1,500 for
the default length, more for trips home), then waits for Enter. When it's
done it says how many holes it patched and how much lava it scooped up.

If the chest fills up or it runs out of fuel, it waits at the start until you
fix it. If something it won't dig (bedrock, a spawner) is in the tunnel, it
stops, says where it's stuck, and keeps retrying: going round it would mean
digging outside the sealed tunnel.

## Staying on track

Same as the [excavator](../excavate-turtle/README.md#staying-on-track):

- **With GPS** at the start of the job, it checks its position every 2 blocks
  of tunnel and corrects itself. If it's been moved out of the tunnel, it
  heads back to the start.
- **Without GPS**, on resume it waits 10 seconds. If you moved it, press a key,
  put it back on its start block facing the original way, and run
  `nethertunnel here`.

## Things to know

- It's slower than the [strip miner](../strip-mine-turtle/README.md) for
  the same length: it steps into all nine blocks of each slice to check
  their sides.
- Keep the tunnel away from the bedrock floor and roof (y 0 to 4 and 123 to
  127): bedrock in the tunnel stops it.
- Holes made after it has passed (ghast fireballs, you) aren't fixed. Run a
  new job, or patch them yourself.
