# storage-computer

- **Type:** computer (advanced is nicer: colour and mouse)
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modems and networking cable to every chest; optional monitor, and a wireless modem for turtles and the status server

## What it does

Turns a wall of chests into one searchable store. Every chest and barrel on
the computer's wired network is storage, except the ones you choose for:

- **Input chest:** anything you drop in here is put away within a couple of
  seconds, into a chest that already holds that item if there is one.
- **Output chest:** search on the computer, press Enter, and a stack of that
  item turns up here.
- **Delivery chest** (optional): where items asked for by turtles go, such
  as the [village builder's](../village-turtle/README.md#getting-blocks-from-the-storage-system)
  supply chest. Without one, they go to the output chest.

The terminal shows every stored item with its count, biggest first. Type to
search (by name, as you'd see it in game), pick with the arrow keys or the
mouse, then Enter for a stack or Right arrow for just one. The top line shows
how many chests and slots are in use.

A monitor, if one is attached, shows a bar of how full the storage is and the
items there's most of. With a wireless modem it also reports to the
[status server](../status-server/README.md).

Enchanted books, named tools and other items with extra data are
listed separately from plain ones.

### Turtles asking for items

With a wireless modem, turtles can ask the storage computer over rednet how
much of an item it holds and have some sent to the delivery chest. The
village builder does this to get building blocks and coal. Turtles never see
or take items with extra data (enchanted or named ones). The footer shows
each delivery, e.g. "Sent 192 items to turtle #14."

## Files

- `storage.lua`: the program. Check intervals and which blocks count as storage are at the top.
- `startup.lua`: starts it on boot and restarts it if it stops
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional; it works without it.

## Setup

1. Place the computer and at least three chests (an input, an output, and one
   or more for storage). Double chests and barrels work.
2. Connect each chest to the network. A small wired modem only goes on a
   full block, so for a chest place a **full-block wired modem** (craft a
   small one on its own) touching it; one full-block modem between two chests
   connects both. **Barrels** are full blocks, so a small modem goes straight
   on them. Put a small wired modem on the computer.
3. Join all the modems with networking cable, and right-click each one so it
   turns red. Chat shows the name of each chest it connects.
4. Optional: put a monitor next to the computer (or on the network), and a
   wireless modem on it for turtles and the status server.
5. Run `storage`. The first time it lists the chests it can see by name and
   asks which is the input, which is the output, and which (if any) is the
   delivery chest for turtles.

   ```
   storage                   -- start
   storage setup             -- pick the input, output and delivery chests again
   ```

Then reboot, and it starts on its own from then on.

## Things to know

- Adding chests: connect them and wait up to a minute (it rescans every 60
  seconds), or reboot.
- Items you take out of the storage chests by hand are noticed at the next
  rescan.
- If the storage is full, items stay in the input chest and the footer says so.
- Furnaces, hoppers, droppers and turtles on the network are never used as
  storage.
