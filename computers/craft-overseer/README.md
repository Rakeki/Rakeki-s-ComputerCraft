# craft-overseer

- **Type:** advanced computer, with a wired modem on the storage system's cable (and a wireless or ender modem if the crafting turtles talk by wireless)
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** advanced monitor (optional, 2 wide by 2 high or bigger), wired modem, wireless modem

## What it does

Runs the [storage system's](../storage-computer/README.md) crafting with as
many [crafting turtles](../crafter-turtle/README.md) as you like. The
storage computer still works out what to craft when a turtle (or you) asks
for something it hasn't got: with an overseer running, it hands every job
over, and the overseer shares them out:

1. Each job goes to a free crafting turtle. Steps of one order run in turn
   (planks before sticks, sticks before fences); different orders run side by
   side on different turtles.
2. For each batch it has the storage computer load that turtle's chest,
   tells the turtle to craft, and has the chest emptied back into storage.
3. When a job is done (or can't be), it tells the storage computer, so the
   turtle waiting for those items gets them.

The monitor (or the computer's own screen, without one) shows:

- **Turtles:** each crafting turtle and what it's doing ("#12 crafting 64
  oak planks"), or "not answering" in red.
- **Queue:** every job in order, with how many it makes and its state:
  *queued*, *on #12* (being crafted), *missing* (storage hasn't got enough
  for it yet, counting what the jobs before it use and make) or *short*
  (it tried to load and came up short). A job that's missing anything has a
  line under it saying what, e.g. "needs 3 iron ingot, 2 stick".
- The last thing that happened, at the bottom.

A job that stays short of ingredients for 10 minutes is given up on, along
with the rest of its order, and the storage computer is told why. A turtle
that stops answering is left out (its job goes to another) until it answers
again.

## Files

- `overseer.lua`: the program. How many turtles it uses and how long it waits are at the top.
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the monitor without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed.

## Setup

1. Set up the [storage computer](../storage-computer/README.md) first.
2. Place an advanced computer with a **wired modem** joined to the storage
   cable (right-click it so it turns red), and a **wireless or ender modem**
   if your crafting turtles use wireless. A monitor next to it is optional.
3. Set up one or more [crafting turtles](../crafter-turtle/README.md), each
   with **its own chest** in front of it on the storage cable. Each tells the
   storage computer which chest is its own when it starts.
4. Install this program on the computer and reboot it. Within a few seconds
   the storage computer's footer says "Gave the crafting overseer (#5) ...
   crafts" the next time it has something to craft.

   ```
   overseer                  -- start (startup.lua does this on boot)
   overseer clear            -- forget the queue
   ```

## Things to know

- Without an overseer the storage computer crafts on one turtle by itself,
  as before. Start the overseer and it takes over; stop it and the storage
  computer goes back to crafting itself (after about 30 seconds) for new
  orders.
- The queue is saved, so a reboot carries on where it was. A batch cut short
  by the reboot has its chest emptied before it's loaded again.
- The ME or RS system's own crafting (with a bridge) isn't shown here: the
  storage computer asks the ME or RS system directly.
- Up to 8 turtles are used at once (`MAX_CRAFTERS` at the top of
  `overseer.lua`).
- `storage test` on the storage computer says whether it found the overseer,
  and lists every crafting turtle and its chest.
