# tree-farm-turtle

- **Type:** turtle with an axe (a felling or mining turtle), plus a wireless or ender modem for GPS and the [status server](../status-server/README.md) (optional)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Plants a grid of saplings and looks after it for ever: it walks the farm,
chops down every tree that has grown, plants a new sapling in its place, and
takes the logs back to a chest. Then it waits a few minutes and goes round
again. It works on its own; no server needed.

Default layout (`treefarm` with no arguments): 24 trees in 4 columns of 6,
3 blocks apart, so the farm is 11 wide and 18 long. The turtle walks in a lane
down the left of each column and along both ends, so it never has to cut
through a tree to get anywhere.

```
===========     T = tree (2 of the 6 rows shown)
|T |T |T |T     | = lane down the left of each column
|  |  |  |      = = end rows that link the lanes
|  |  |  |
|T |T |T |T
S==========     S = turtle's start, C = chest behind it
C
```

- **Chopping:** it climbs straight up the trunk, so it suits trees with a
  one-block trunk: oak, birch, spruce, jungle and cherry. Branches on big oaks
  and acacias are left behind.
- **Saplings:** leaves drop saplings as they decay. The turtle picks up any
  lying in its lanes and keeps up to 64 to replant with; the rest go in the
  chest with the logs, apples and sticks.
- **Bone meal:** put some in its inventory and it uses up to 2 on each young
  sapling it passes.
- **Fuel:** coal or charcoal in its inventory stays there and gets burned as
  needed. When its fuel drops below 1,000 it also burns some of the logs it
  chopped, so once the farm is growing it runs itself.
- **Chest full:** it waits at the start until there's room.

## Files

- `treefarm.lua`: the program. Wait between rounds, sapling count and fuel settings are at the top.
- `startup.lua`: keeps the farm going after a reboot or chunk reload
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too, just without reporting.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).

## Use

1. Clear a flat area of dirt or grass, at least as big as the farm (11 × 18
   for the default). Saplings need light to grow, so put torches in the gaps
   between trees (not in the lanes) if it gets dark.
2. Place the turtle on the ground at the near left corner, facing along the
   farm. Trees go forward and to the right of it.
3. Put a chest **directly behind** it.
4. Give the turtle saplings (one per tree to start), some coal, and bone meal
   if you have it.
5. Run:

   ```
   treefarm                  -- 4 columns of 6 trees, 3 apart
   treefarm 6 8              -- 6 columns of 8 trees
   treefarm 6 8 4            -- ...4 blocks apart, for bigger trees
   treefarm resume           -- carry on after stopping it
   treefarm here             -- no GPS: "I've put you back on your start block", then carry on
   treefarm cancel           -- stop farming and forget the farm
   ```

It prints the size of the farm and how many saplings it has, then waits for
Enter. The first round plants every spot; after that each round chops what's
grown.

## Staying on track

Same as the [excavator](../excavate-turtle/README.md#staying-on-track):

- **With GPS** at the start, it checks its position every 10 trees and
  corrects itself. If it's been moved off the farm, it heads back to the start.
- **Without GPS**, on resume it waits 10 seconds. If you moved it, press a key,
  put it back on its start block facing the original way, and run
  `treefarm here`.

If it reboots half way up a tree, it climbs back down and finishes chopping
that tree first.

## Things to know

- It digs anything in its lanes except chests, furnaces, spawners and other
  protected blocks, so keep the lanes free of things you want to keep.
- A spot it can't plant (stone underneath, something in the way) is skipped,
  and it says so once.
- Dark oak and big spruce need four saplings in a square and won't grow here.
