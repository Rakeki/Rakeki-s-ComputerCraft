# mob-farm-turtle

- **Type:** mining turtle, plus a wireless or ender modem for GPS and the [status server](../status-server/README.md)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Builds a classic drop-tower mob farm above where you place it. It works on
its own; no server needed.

- **Spawning room:** 18×18 floor, high in the air, closed in with walls and a
  roof so it's pitch dark inside. Headroom is 2 blocks, which keeps endermen out.
- **Water channels:** four 2-wide channels, one sunk into the floor towards
  each wall, with water flowing inwards to a 2×2 hole in the middle. Mobs that
  wander into a channel get washed into the hole.
- **Drop shaft:** a 2×2 shaft straight down from the hole to the ground.
- **Collection:** mobs land on 4 hoppers at the bottom, which feed a double
  chest. In front of the chest is a 1-deep, 2-wide pit for you to stand in. From
  there you can open the chest, and you can hit the mobs' legs through the gap
  above two bottom slabs (the kill window).

**Drop height** sets what the fall does (fall damage is the height minus 3):

- `mobfarm` (32, the default) kills everything that falls, witches included.
  Loot collects in the chest by itself.
- `mobfarm 22` leaves zombies, skeletons and creepers on half a heart. Finish
  them off through the kill window for XP. Spiders still die.

[Preview](preview/mobfarm.svg) of the default farm: finished, cut open, and a
close-up of the bottom of the shaft.

With the default drop the farm stands about 36 blocks tall. The turtle goes
back to the chest whenever it runs out of anything, and waits there if the
chest hasn't got it.

## Files

- `mobfarm.lua`: the program. Drop height, room height and how much it carries are at the top.
- `startup.lua`: resumes an unfinished job after a reboot or chunk reload
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too, just without reporting.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

## Use

1. Pick a spot with open sky above. Ideally build over an ocean or far from
   caves, because mobs spawning anywhere else nearby use up the mob cap.
2. Place the turtle on the ground where you want to stand to collect, facing
   the way the farm should go. The shaft comes down 1 block in front of it, and
   the room is centred on the shaft (it reaches about 9 blocks out each way).
3. Put a chest **directly behind** the turtle (the supply chest). Run
   `mobfarm list` to see what goes in it. For the default farm:
   - about 1,200 building blocks (cobblestone is fine)
   - 4 hoppers, 2 chests, 2 slabs (any kind)
   - 8 water buckets (it brings the empty buckets back)
   - fuel: a stack of coal or charcoal (it tops itself up to 3,000 and
     uses about 2,000)
4. To build with something other than cobblestone, put a stack of it in the
   turtle's **slot 1** (top left) before you start. That's the block it uses.
5. Run:

   ```
   mobfarm                  -- default farm, 32 block drop: mobs die on landing
   mobfarm 22               -- XP farm: mobs land on half a heart
   mobfarm list             -- what to put in the chest (what's still needed, if a job is running)
   mobfarm resume           -- carry on after stopping it
   mobfarm here             -- no GPS: "I've put you back on your start block", then carry on
   mobfarm cancel           -- forget the current job
   ```

It builds in this order: the pit, chests and hoppers; the shaft walls, from
the bottom up; the channel beds and spawning floor; the walls; the water; and
last the roof. Then it comes back down to its start block. Pick it up when it's done.

## Things to know

- **Mobs spawn only while you're 24 to 128 blocks away.** Standing in the pit
  of the default farm is over 30 blocks below the floor, which is fine. With
  `mobfarm 22` the pit is closer than 24 blocks to the middle of the floor,
  so not much spawns there while you wait in the pit. Wait somewhere about 30
  blocks from the room, then come down to finish the mobs off.
- **Light up the roof**, or mobs spawn on top of it at night and count
  towards the mob cap. Torches every 6 blocks or so do it.
- **Rates go up with trapdoors.** Mobs walk into the channels at random. Open
  trapdoors along the channel edges trick them into walking off, which makes the
  farm much faster. The turtle can't place open trapdoors, so add them by hand if
  you like.
- **Ground in the way is kept.** Where there's already solid ground (a hill
  under the shaft, say), the turtle leaves it as part of the wall instead of
  replacing it. So it may use fewer blocks than `list` says. Don't build into a
  mountain: the room itself needs open air.
- **Junk it digs up** (dirt, stone and so on) is dropped on the ground to the
  left of the start. Anything else goes in the supply chest.
- **Hoppers:** the turtle places each hopper facing back, so it points into
  the block behind it. If one comes out pointing the wrong way, the turtle says
  so. Break that hopper and place it again by hand: sneak and click the chest
  (or hopper) it should feed.
- **Getting to work:** the turtle goes up and down a column 9 blocks behind
  the start and 1 to the left, outside the farm, and flies across above the roof. It never digs
  through what it has built. Keep that column clear of chests and other
  storage.

## Staying on track

Same as the [excavate turtle](../excavate-turtle/README.md#staying-on-track):

- **With GPS** (a constellation in range at the start and a modem on the
  turtle), it checks its position every time it starts and every 20 steps.
- **Without GPS** it waits 10 seconds when it resumes. If you moved it, press
  a key, put it back on its start block facing the way it started, and run
  `mobfarm here`.
- **If it finds itself somewhere off its routes**, it stops rather than dig its
  way back through the farm. Put it back on its start block and run `mobfarm here`.
- **If its way is blocked** (by a protected block like a chest), it says where
  it's stuck and keeps retrying until the way is clear.
