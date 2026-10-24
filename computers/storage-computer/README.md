# storage-computer

- **Type:** computer (advanced is nicer: colour and mouse)
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modems and networking cable to every chest; optional monitor, a wireless modem for turtles and the status server, and a [crafting turtle](../crafter-turtle/README.md)

## What it does

Turns a wall of chests into one searchable store. Every chest and barrel on
the computer's wired network is storage, except the ones you choose for:

- **Input chest:** anything you drop in here is put away within a couple of
  seconds, into a chest that already holds that item if there is one.
- **Output chest:** search on the computer, press Enter, and a stack of that
  item turns up here.
- **Delivery chest** (optional): where items asked for by turtles go, such
  as the [village builder's](../village-turtle/README.md#getting-blocks-from-the-storage-system)
  supply chest. It's kept clear: anything in it the turtle hasn't asked for
  goes back into storage. Without one, deliveries go to the output chest
  (which is never cleared out).
- **Crafter chest** (optional): the chest in front of a
  [crafting turtle](../crafter-turtle/README.md). See [Crafting](#crafting).

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

The delivery chest only ever holds what a turtle has asked for. Every 5
seconds anything else in it (leftovers from an earlier load, empty buckets,
things dropped in by hand) is put back into storage. Items a turtle asked
for wait there until it takes them, or for 10 minutes if it never does.

If a turtle says nothing arrives, run `storage test`. It moves one item into
the delivery chest and back, says why if it can't (usually a modem that
isn't red, or a chest not joined by cable to the others), and whether this
computer has the wireless modem turtles need to reach it. Without one, the
footer says "No wireless modem: turtles can't ask me for items."

### Crafting

With a [crafting turtle](../crafter-turtle/README.md), a turtle can ask for
things that aren't stored but could be made from what is. When the village
builder asks for 40 jungle fences and there are none, but there are jungle
logs, the storage computer plans the crafts (logs into planks, planks into
sticks, then the fences), puts each batch's ingredients in the crafter chest
and has the crafting turtle make them. The results go into storage, and the
turtle that asked gets them on its next request. It never crafts the same
order twice while one is already being made.

When a turtle asks how much of something there is, what could be crafted
counts as well, so the village builder doesn't wait for blocks that can be
made. While the village builder waits for a building's materials it also
asks the storage computer to start crafting what's short, so the crafting
happens while it clears the plot. The footer shows what it's crafting, and
why if it can't (no crafter chest, no crafting turtle answering, or not
enough to make it from). `storage test` checks the crafting side too.

The recipes are in `recipes.lua`: everything craftable that the village
themes use, plus the usual basics. Teach it more with `crafter learn` on the
crafting turtle; those are saved on this computer in `/.storage_recipes`.
Smelting isn't crafting: smooth sandstone, glass and the like still have to
be stocked.

## Files

- `storage.lua`: the program. Check intervals and which blocks count as storage are at the top.
- `crafting.lua`: works out what to craft, ingredients first
- `recipes.lua`: the built-in recipes
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
   asks which is the input, which is the output, which (if any) is the
   delivery chest for turtles, and which (if any) is the crafter chest.

   ```
   storage                   -- start
   storage setup             -- pick the input, output, delivery and crafter chests again
   storage test              -- check deliveries (one item there and back) and the crafting turtle
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
