# storage-computer

- **Type:** computer (advanced is nicer: colour and mouse)
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modems and networking cable to every chest (or to an ME Bridge / RS Bridge); optional monitor, a wireless modem for turtles and the status server, a [crafting turtle](../crafter-turtle/README.md) and a [smelter](../smelter-computer/README.md)

## What it does

Turns a wall of chests into one searchable store, or puts a terminal and
turtle access on an **Applied Energistics 2** or **Refined Storage** system
(see [ME and RS systems](#me-and-rs-systems)). Either way, every turtle and
computer here talks to this computer the same way, so the
[village builder](../village-turtle/README.md),
[crafting turtle](../crafter-turtle/README.md) and
[smelter](../smelter-computer/README.md) work with whichever you use, and
keep working if you switch.

With chests, every chest and barrel on the computer's wired network is
storage, except the ones you choose for:

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
- **Fuel chest** (optional): where the coal and charcoal are kept, for the
  [smelter's](../smelter-computer/README.md) furnaces and for turtles. See
  [Fuel](#fuel).

The terminal shows every stored item with its count, biggest first. Type to
search (by name, as you'd see it in game), pick with the arrow keys or the
mouse, then Enter for a stack or Right arrow for just one. The top line shows
how many chests and slots are in use (or how full the ME or RS system is).

An optional **Craftable** tab can sit next to the stored items (see
[Crafting](#crafting)); it's off unless you turn it on.

A monitor, if one is attached, shows a bar of how full the storage is and the
items there's most of. With a wireless modem it also reports to the
[status server](../status-server/README.md).

Enchanted books, named tools and other items with extra data are
listed separately from plain ones.

### Stack upgrades

Storage that holds more than 64 a slot, like Sophisticated Storage barrels
and chests with **stack upgrades** (or drawers), is used for what you have
most of. The storage computer reads how much each one's slots hold:

- Items you have **256 or more** of go into the roomiest storage first.
  Smaller amounts go into plain chests first, so the roomy ones stay free
  for bulk.
- Every 10 seconds it tidies a little: up to 16 stacks of a bulk item already
  sitting in a plainer chest move up into roomier storage with space. If the
  roomy storage is full, a stack of something you have little of (under 128)
  moves out to a plain chest first to make room. Items only move up when
  there's a lot of them and down when there's little, so nothing goes back
  and forth.
- Upgrading a barrel later is noticed at the next rescan (within a minute),
  and the tidying moves bulk items into it from then on.

`storage tidy` lists how much one slot of your storage holds (e.g. "1024 a
slot: 6 storages, 64 a slot: 40 storages"), then sorts everything at once,
saying each move, or why nothing moved. Run it after adding upgrades, or if
things don't seem to be moving. With every chest the same size, none of
this does anything.

Some storage doesn't tell CC about its upgrades. Then the storage computer
works out the slot size from what's in it (a slot holding 300 cobblestone
is clearly bigger than 64), so such storage counts as roomy once it holds a
big stack.

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

With a [crafting turtle](../crafter-turtle/README.md), the turtles that ask
the storage computer for blocks (the [village builder](../village-turtle/README.md),
the [builder](../builder-turtle/README.md)) get things that aren't stored
but could be made from what is: it has them crafted on request. When the village
builder asks for 40 jungle fences and there are none, but there are jungle
logs, the storage computer plans the crafts (logs into planks, planks into
sticks, then the fences), puts each batch's ingredients in the crafter chest
and has the crafting turtle make them. The results go into storage, and the
turtle that asked gets them on its next request. It never crafts the same
order twice while one is already being made.

You can ask for crafts on the terminal too, with the **Craftable** tab. It's
off by default, because working out everything that could be made from a
big store with a big modpack takes a long while. To turn it on, set
`CRAFTABLE_TAB = true` near the top of `storage.lua` (`install update`
puts it back to off). Then there are two tabs under the top line,
**Stored** and **Craftable** (light blue); press Tab or click one to switch.
The Craftable tab lists everything that isn't stored but could be made,
with how many ("can make 40"). Pick one and press Enter for a stack (or
Right for one): it's crafted and sent to the output chest when it's ready.
The monitor lists craftable items in light blue after the stored ones, and
with an [ME or RS system](#me-and-rs-systems), items it has a pattern for
are listed too, marked "pattern". The list is worked out in the
background, again within 30 seconds of anything changing.

When a turtle asks how much of something there is, what could be crafted
counts as well, so the village builder doesn't wait for blocks that can be
made. While the village builder waits for a building's materials it also
asks the storage computer to start crafting what's short, so the crafting
happens while it clears the plot. The footer shows what it's crafting, and
why if it can't (no crafter chest, no crafting turtle answering, or not
enough to make it from). `storage test` checks the crafting side too.

If there isn't enough to make the whole order, it makes as many as it can
(the turtle that asked gets those, and is told why not the rest). If the
crafting turtle stops answering, waiting turtles are told that crafting is
stuck, and it carries on by itself once the turtle is back.

The recipes are in `recipes.lua`: everything craftable that the village
themes use, plus the usual basics. Teach it more with `crafter learn` on the
crafting turtle; those are saved on this computer in `/.storage_recipes`.
For every recipe in your modpack, see [Modded recipes](#modded-recipes).

### Modded recipes

CC can't read the game's recipe book, but every vanilla and mod recipe is
stored in the mod files, and [`tools/recipes.mjs`](../../tools/recipes.mjs)
pulls out all the crafting-table ones (shaped and shapeless, with tags like
"any planks"). Machine recipes (Create, Botany Pots and so on) are left out:
the crafting turtle can't make those. The result is one file,
`pack_recipes.lua`, which the storage computer loads next to `recipes.lua`
when it starts.

For the TRekt Mons pack the file is already made (7,600 recipes, 620 KB).
On the storage computer:

```
wget https://rakeki.github.io/Rakeki-s-ComputerCraft/computers/storage-computer/packs/trekt-mons.lua pack_recipes.lua
reboot
```

For another pack, or after adding mods, run this on your PC (it needs
Node.js) and copy the file it writes onto the storage computer as
`pack_recipes.lua` (dragging a file onto an open computer screen uploads
it):

```
node tools/recipes.mjs pack_recipes.lua <the Minecraft version jar> <your mods folder>
```

`install update` never touches `pack_recipes.lua`. A computer has 1 MB of
disk by default, so a file much bigger than about 700 KB won't fit next to
the programs.
Smelting isn't crafting: smooth sandstone, glass and the like aren't made
on request. The [smelter](../smelter-computer/README.md) smelts ores as they
come in, and anything else you add to its list.

### Fuel

With a fuel chest, coal, charcoal and coal blocks that come in (through the
input chest, or put back from the delivery or crafter chest) go into the
fuel chest first, and into storage only once it's full. Nothing else is
ever put in it.

The fuel chest still counts as part of the store: turtles that ask for coal
or charcoal (the village builder does when it's low) get it from there, and
it shows up in the search. The [smelter](../smelter-computer/README.md)
fuels its furnaces from the fuel chest before coal kept anywhere else, and
the charcoal it makes from spare logs comes back to it. A turtle parked
next to the fuel chest can also take fuel straight from it; the storage
computer re-counts it every 5 seconds. This works the same with an ME or RS
system: the fuel chest is a real chest beside it.

### ME and RS systems

With the Advanced Peripherals mod, an **ME Bridge** (Applied Energistics 2)
or **RS Bridge** (Refined Storage) on the wired network lets the system do
the storing instead of chests ([layout](#ae2-with-advanced-peripherals)).
`storage setup` asks whether to use it when it finds one. Then:

- The input chest is emptied into the system, searches and turtle requests
  are answered from it, and stacks are sent out of it to the output and
  delivery chests. Chests on the network aren't used as storage.
- When a turtle asks for something that isn't there, the system crafts it
  from its own **patterns** first. The crafting turtle and `recipes.lua` are
  only used for things the system has no pattern for, so with AE2 or RS the
  crafting turtle is optional.
- The bridge can't put an item into a chosen slot, which the smelter's
  furnaces and the crafting turtle's grid need. So those items pass through
  a **transfer chest**: any spare chest on the network, chosen in
  `storage setup`. Without one, the smelter and the crafting turtle can't be
  loaded.
- The top line shows how full the system is: by bytes for AE2, by items for
  RS.

It works with both versions of the bridges: the older ones (Minecraft 1.20
and before) and the new ones in Minecraft 1.21.

## Example layouts

The website shows each of these in 3D. Everything is joined by one run of
networking cable; right-click every modem so it turns red.

### Chest wall

The smallest setup. A wall of chests two high, with a **full-block wired
modem** after every two chests (one full-block modem touching two chests
connects both). Cable runs along the front of the wall to the computer.
The input and output chests each have a full-block modem between them and
the cable. An advanced monitor next to the computer, and a wireless modem
on top of it for turtles, are optional.

### Barrels with stack upgrades

[Sophisticated Storage](#stack-upgrades) barrels instead of chests. Barrels
are full blocks, so each takes a small wired modem on its side. Give some
barrels more stack upgrades than others: the storage computer fills the
most-upgraded ones with what there's most of, and keeps small amounts in
the plain ones.

### Full base

The chest wall plus everything that works with it, on the same cable:

- the [crafting turtle](../crafter-turtle/README.md) facing its crafter chest
- the [smelter](../smelter-computer/README.md): its computer and a row of
  furnaces, each furnace with a small wired modem
- a fuel chest, for the furnaces and turtles
- the delivery chest, with the [village builder](../village-turtle/README.md)
  taking its blocks from it

### AE2 with Advanced Peripherals

An ME system does the storing. The ME controller and drives sit on ME cable
as usual. Put an **ME Bridge** against the ME cable, with a wired modem on
the bridge, and run networking cable from it to the storage computer. The
input, output, fuel and **transfer** chests are ordinary chests on that
networking cable, and so are the smelter's furnaces. Run `storage setup`
and answer yes when it finds the bridge. A Refined Storage system with an
**RS Bridge** is laid out the same way.

## Files

- `storage.lua`: the program. Check intervals are at the top.
- `chests.lua`: storing in the chests on the network: which blocks count as storage, and what counts as bulk for stack upgrades
- `bridge.lua`: storing in an ME or RS system through its bridge
- `crafting.lua`: works out what to craft, ingredients first
- `recipes.lua`: the built-in recipes
- `pack_recipes.lua`: optional, every crafting recipe in your modpack (see [Modded recipes](#modded-recipes)); `packs/` has ready-made ones
- `startup.lua`: starts it on boot and restarts it if it stops
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional; it works without it.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.

## Setup

1. Place the computer and at least three chests (an input, an output, and one
   or more for storage). Double chests and barrels work. With an ME or RS
   system, you only need the input and output chests, plus a transfer chest
   for the smelter or crafting turtle.
2. Connect each chest to the network. A small wired modem only goes on a
   full block, so for a chest place a **full-block wired modem** (craft a
   small one on its own) touching it; one full-block modem between two chests
   connects both. **Barrels** are full blocks, so a small modem goes straight
   on them. Put a small wired modem on the computer.
3. For an ME or RS system: place the **ME Bridge** or **RS Bridge** touching
   the system (on a cable or next to the controller), put a wired modem on
   the bridge and join it to the same network.
4. Join all the modems with networking cable, and right-click each one so it
   turns red. Chat shows the name of each chest it connects.
5. Optional: put a monitor next to the computer (or on the network), and a
   wireless modem on it for turtles and the status server.
6. Run `storage`. The first time it asks whether to use the ME or RS system
   (if it found a bridge), then lists the chests it can see by name and asks
   which is the input, which is the output, and which (if any) are the
   delivery, crafter, fuel and transfer chests.

   ```
   storage                   -- start
   storage setup             -- choose the store and the chests again
   storage test              -- check deliveries (one item there and back), the fuel chest and the crafting turtle
   storage tidy              -- show slot sizes and sort bulk items into storage with stack upgrades now
   ```

   While `storage` is running, run these in a second tab (advanced
   computer: `bg storage tidy`) or stop it first with Ctrl+T.

Then reboot, and it starts on its own from then on. To move from chests to
an ME or RS system later, add the bridge, run `storage setup` and answer yes:
the turtles and the smelter carry on without being changed.

## Things to know

- Adding chests: connect them and wait up to a minute (it rescans every 60
  seconds), or reboot. An ME or RS system is re-read every 5 seconds.
- Items you take out of the storage chests by hand are noticed at the next
  rescan.
- If the storage is full, items stay in the input chest and the footer says so.
- Furnaces, hoppers, droppers and turtles on the network are never used as
  storage.
- If the delivery, crafter, fuel or transfer chest can't be found when it
  starts (a modem not red, say), it carries on without that feature and the
  footer says which chest is missing. A missing input or output chest, or a
  missing bridge in ME or RS mode, stops it.
- The ME or RS system's own patterns are trusted: a turtle is told an item
  can be made as soon as there's a pattern for it, even if the system turns
  out to lack the ingredients. The footer says when the system is done.
- With an ME or RS system, items with extra data (enchanted, named) may be
  counted with the plain ones, and the bridge may send either. If such an
  item stays in the input chest, the system wouldn't take it: take it out by
  hand.
- The [smelter](../smelter-computer/README.md) asks for things over the
  wired network's cable, so it works without a wireless modem.
- Turtles' requests are handled one at a time, in the order they arrive; none
  are lost while it's busy with another.
