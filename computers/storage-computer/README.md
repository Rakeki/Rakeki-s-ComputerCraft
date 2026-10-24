# storage-computer

- **Type:** computer (advanced is nicer: colour and mouse)
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem connected by networking cable to every chest; optional monitor and wireless modem

## What it does

Turns a wall of chests into one searchable store. Every chest and barrel on
the computer's wired network is storage, except two you choose:

- **Input chest:** anything you drop in here is put away within a couple of
  seconds, into a chest that already holds that item if there is one.
- **Output chest:** search on the computer, press Enter, and a stack of that
  item turns up here.

The terminal shows every stored item with its count, biggest first. Type to
search (by name, as you'd see it in game), pick with the arrow keys or the
mouse, then Enter for a stack or Right arrow for just one. The top line shows
how many chests and slots are in use.

A monitor, if one is attached, shows a bar of how full the storage is and the
items there's most of. With a wireless modem it also reports to the
[status server](../status-server/README.md).

Enchanted books, named tools and other items with extra data are
listed separately from plain ones.

## Files

- `storage.lua`: the program. Check intervals and which blocks count as storage are at the top.
- `startup.lua`: starts it on boot and restarts it if it stops
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional; it works without it.

## Setup

1. Place the computer and at least three chests (an input, an output, and one
   or more for storage). Double chests and barrels work.
2. Put a wired modem on the computer and on every chest, connect them all
   with networking cable, and right-click each modem so it turns red.
3. Optional: put a monitor next to the computer (or on the network) and a
   wireless modem on it.
4. Run `storage`. The first time it lists the chests it can see by name and
   asks which is the input and which is the output. Right-clicking a modem
   shows its chest's name in chat.

   ```
   storage                   -- start
   storage setup             -- pick the input and output chests again
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
