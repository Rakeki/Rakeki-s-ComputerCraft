# crop-farm-turtle

- **Type:** turtle with a hoe, axe or pickaxe (any tool that harvests), plus a wireless or ender modem for GPS and the [status server](../status-server/README.md) (optional)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Looks after a crop field for ever. It flies one block above the crops, row by
row, and harvests everything that's fully grown, replanting each spot with the
seeds that just came out of it. At the end of each pass it drops the harvest
in a chest, waits 10 minutes, and goes round again. It works on its own; no
server needed.

- **Crops:** wheat, carrots, potatoes, beetroot and nether wart, mixed however
  you like. Melons and pumpkins get picked too; their stems are left to grow
  more.
- **Default field:** 9 × 9 (`cropfarm` with no arguments), starting with the
  block under the turtle and running forward and to the right. That's the
  classic farm with a water block in the middle; the turtle skips water.
- **Seeds:** it keeps up to 64 of each kind of seed on board for replanting;
  the rest goes in the chest with the harvest. An empty bit of farmland gets
  planted with whatever crop it last flew over.
- **Bone meal:** put some in its inventory and it uses it on crops that aren't
  ready yet.
- **Fuel:** coal or charcoal in its inventory stays there and gets burned as
  needed. A 9 × 9 round takes about 100 fuel, so a stack of coal lasts for
  around 50 rounds.
- **Chest full:** it waits at the start until there's room.

## Files

- `cropfarm.lua`: the program. The wait between rounds, seeds kept and crop list are at the top.
- `startup.lua`: keeps the farm going after a reboot or chunk reload
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too, just without reporting.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).

## Use

1. Make or pick a field of farmland with crops on it. Keep the layer just
   above the crops clear: that's where the turtle flies.
2. Place the turtle on that layer, above one corner of the field, facing along
   one edge. The field runs forward and to the right from the crop under it.
3. Put a chest **directly behind** it, at the same height (stand it on a block
   if it needs one).
4. Give the turtle some coal, and seeds if the field isn't planted yet.
5. Run:

   ```
   cropfarm                  -- a 9 x 9 field
   cropfarm 15 20            -- width (to the right), length (forward)
   cropfarm resume           -- carry on after stopping it
   cropfarm here             -- no GPS: "I've put you back on your start block", then carry on
   cropfarm cancel           -- stop farming and forget the field
   ```

It prints the field size and fuel per round, then waits for Enter.

## Staying on track

Same as the [excavator](../excavate-turtle/README.md#staying-on-track):

- **With GPS** at the start, it checks its position every 20 blocks and
  corrects itself. If it's been moved off the field, it heads back to the start.
- **Without GPS**, on resume it waits 10 seconds. If you moved it, press a key,
  put it back on its start block facing the original way, and run
  `cropfarm here`.

## Things to know

- It digs anything in its flying layer except chests, furnaces, spawners and
  other protected blocks, so no torches or fences on that layer inside the
  field.
- Crops grow faster on wet farmland with light; a water block within 4 of
  every crop and a few torches outside the field help.
- Sugar cane, cocoa and sweet berries aren't harvested.
