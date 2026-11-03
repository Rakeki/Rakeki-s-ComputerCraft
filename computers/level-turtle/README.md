# level-turtle

- **Type:** mining turtle, plus a wireless or ender modem for GPS and the [status server](../status-server/README.md) (both optional)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Flattens a rectangle of land into a solid, level building platform. It works
on its own; no server needed. It needs GPS (see
[Staying on track](#staying-on-track)).

The height of the platform is the ground the turtle starts on: the block under
it is the platform's top. You give the size: `x` blocks to the turtle's right,
`z` blocks forward, and optionally `y`, how high above the ground to clear.

It works in two passes:

1. **Clearing.** Everything above the platform level comes out: hills, trees
   (trunks, leaves and all), bushes, tall grass, flowers, snow. It digs in
   3-high layers from the ground up. With no `y`, it keeps going up until two
   layers in a row had nothing in them (open sky), up to 64 blocks. Any water
   or lava it finds up there gets turned into a block and dug out, so it can't
   run onto the platform.
2. **Filling.** It flies over the whole area just above the platform and
   fills every dip, pond, lake and hole below it with the dirt and stone it dug
   out of the hills. Leaves, logs and plants below the platform level are dug
   out and filled too. It fills a hole up to 8 blocks deep; anything deeper
   (a cave, a deep lake) gets an 8-block plug of solid blocks on top instead of
   being filled to the bottom.

The finished platform is solid all the way across, with nothing on it. The
top is whatever was there or whatever it filled with: grass, dirt and stone
mixed.

**What goes where.** Wood, saplings, apples, ores and anything else go in the
chest behind the start. It keeps up to 8 stacks of dirt and stone on board for
filling, and puts the rest in the chest too; when it runs out while filling,
it takes them back out. If the chest is full of dirt and stone, the extra goes
on the ground beside the start (outside the platform), and gravel always does.
If the chest is full and it still has wood or loot, it waits at the start
until you make room.

## Files

- `level.lua`: the program. Settings (max height, fill depth, how much fill to carry, refuel level) are at the top.
- `startup.lua`: resumes an unfinished job after a reboot or chunk reload (first it fetches any newer version from the website)
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too, just without reporting.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

## Use

1. Stand the turtle **on the ground** in one corner of the area, at the
   height you want the platform: the block under it is the platform's top.
   Face it along one edge. The area runs **forward** and to the **right** of it.
2. Put a chest **directly behind** the turtle, with some coal in it.
3. **Fuel comes from the chest.** The turtle tops itself up to 5000 from the
   chest when it starts and whenever it's back to unload. It burns coal
   first, then other fuel, but never the wood it chops. A 32×32 area of
   ordinary land with a few trees takes about 6,000. If the chest runs dry,
   it waits at the start for you to add fuel to the chest or to the turtle.
4. Run:

   ```
   level 32 32                   -- 32 to my right, 32 forward, clear up until the sky is empty
   level 48 24 10                -- 48 by 24, clear only 10 blocks up
   level 32 32 auto              -- same as leaving the height out
   level 61 50 0                 -- clear nothing above, only fill the holes (it still digs through
                                 -- anything in its way just above the ground)
   level resume                  -- carry on after stopping it
   level here                    -- an old job from before GPS was needed: "I've put you back on your start block"
   level cancel                  -- forget the current job
   ```

It prints the size and the fuel it expects, waits for Enter, clears, fills,
and finally comes back to the start. If the chest fills up, or it runs out of
fuel or fill blocks, it waits at the start until you fix it.

## Staying on track

- It checks its position with GPS (see [gps-deployer](../gps-deployer/README.md))
  every 20 steps and when it starts up. If it was moved, it finds its own way back.
- **GPS is needed:** it won't move without it. If GPS doesn't answer when it
  starts (after a server restart the GPS computers may still be starting), it
  waits and says so on screen and on the status server. `level here` is only
  for a job started before GPS was needed.
- Keep the area loaded (stay nearby, or use a chunk loader) for big jobs. If
  the chunk unloads, the turtle stops and picks up again when it's loaded.

## Things to know

- **Out of dirt.** Flat land with a lake needs more fill than it digs. When it
  runs out it goes home, takes any dirt, cobblestone or stone from the chest,
  and otherwise waits there for you to put some in the chest or the turtle.
  It fills with dirt, coarse dirt, cobblestone, cobbled deepslate, stone,
  deepslate, andesite, diorite, granite, tuff, calcite, netherrack and
  sandstone.
- **Water from outside.** It fills the water inside the area, but a river or
  lake right next to it can still flow onto the edge. Wall it off, or make the
  area a block or two bigger than you need.
- **Chests, furnaces, spawners and other turtles** are never dug. They stay
  where they are, and so does the ground under them.
- **The top is mixed.** The platform's top layer is whatever was there or got
  filled in: grass, dirt and stone. Cover it with your own floor.
