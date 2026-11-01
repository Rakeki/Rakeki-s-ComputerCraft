# cannon-feeder

- **Type:** computer (advanced is nicer: colour), plus a modem that reaches the [storage computer](../storage-computer/README.md): wired on its cable, or wireless / ender
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** a chest touching both this computer and the Create Schematicannon, on the storage cable (or an ender chest whose twin is); a monitor (optional)

## What it does

Feeds a Create **Schematicannon** from your [storage
system](../storage-computer/README.md). The cannon takes its blocks, and its
gunpowder, from any chest touching it. This computer keeps that chest topped
up with everything on its list until the whole amount of each has been sent:

- You give it the list: each item and how many (`cannon add stone_bricks 340`),
  or every block a building plan from `/plans` uses (`cannon plan cottage`).
  The amounts are the ones on the cannon's material list.
- Every 5 seconds it asks the storage computer to top the chest up. Each item
  gets a fair share of the chest (up to 2 stacks), never more than is still
  to be sent, so the cannon always has some of everything to hand.
- Anything storage hasn't got but can make is crafted on the way, with the
  crafting turtles (or the craft overseer), the same as a builder turtle's
  order.
- It keeps 32 gunpowder in the chest while there's anything left to send.
- Once everything is sent it stops. What the cannon didn't use stays in the
  chest while it's on the list; take it off the list (or clear it) and the
  storage computer puts it away within 10 minutes.

The monitor (or the computer's screen) shows how much has been sent in all,
the chest and its gunpowder, and each item: sent of needed, and whether it's
*in chest*, *crafting*, *none stored*, *can't* (and why: no recipe, or what
the recipe needs that isn't there) or *done*.

If the list has more kinds of item than the chest has slots, the first ones
on the list go in first and the rest wait their turn as those are used up.
A double chest holds 54 kinds.

## Files

- `cannon.lua`: the program. How much of each item it keeps in the chest is at the top.
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): keeps the list across reboots (copy to `/lib/files.lua`). Needed.
- [`lib/claim.lua`](../../lib/claim.lua): tells the storage computer which chest is this feeder's (copy to `/lib/claim.lua`). Needed.
- [`lib/plan.lua`](../../lib/plan.lua): reads building plans for `cannon plan` (copy to `/lib/plan.lua`). Needed for `cannon plan`.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Put a **chest** against the Schematicannon, and this computer against the
   chest.
2. Join the chest to the storage system:
   - **Near the storage:** a full-block wired modem on the chest, on the
     storage cable (right-click it so it turns red). Give the computer a
     wired modem on the cable too, or a wireless one.
   - **Far away:** make the chest an **ender chest** (EnderStorage or the
     like) and put its twin (same colours, used by nothing else) on the
     storage cable with a wired modem. Give this computer and the storage
     computer an **ender modem**.

   Don't pick the chest in `storage setup`: the storage computer finds it by
   itself.
3. Install this program and reboot. The footer says what it's waiting for.
4. Load a schematic into the cannon, read its material list, and put the
   same on this computer's list. Then start the cannon.

   ```
   cannon                       -- start (startup.lua does this on boot)
   cannon add stone_bricks 340  -- add 340 stone bricks to the list
   cannon add create:andesite_casing 12   -- a modded item: its full name
   cannon remove oak_planks     -- take an item off the list
   cannon plan cottage          -- add every block the plan /plans/cottage uses
   cannon list                  -- the list, and how much of each is sent
   cannon again                 -- send it all again (the same build once more)
   cannon clear                 -- forget the list
   cannon chest                 -- pick the chest, if it touches more than one
   ```

   Stop it (hold Ctrl+T) to type these, or use them in a second shell on an
   advanced computer; it picks up the new list within 5 seconds.

## Things to know

- CC can't read the cannon or its schematic, so the list is yours to type.
  The cannon's own material list (or the checklist it prints) has the
  counts.
- It counts what it has sent, not what the cannon used. Take items out of
  the chest yourself and it won't send them again: add them back with
  `cannon add`.
- `cannon plan` counts blocks, and a few items place two (doors, beds, tall
  flowers), so it may ask for more of those than the cannon uses. What's
  left goes back into storage once you clear the list.
- `set cannon.gunpowder 64` keeps more gunpowder in the chest, `0` none (fill
  the cannon yourself).
- **Which monitor.** It uses the first free monitor it finds, next to it or on its wired network. When several computers share a cable, they can take each other's: give this one its own with `set cannon.monitor monitor_3` (the name shows when you right-click the monitor's modem) and reboot. `set cannon.monitor none` keeps it off monitors.
