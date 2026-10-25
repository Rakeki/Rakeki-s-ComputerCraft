# builder-turtle

- **Type:** turtle with a pickaxe (a mining turtle), plus a wireless or ender modem
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Builds whatever a [blueprint projector](../blueprint-projector/README.md) is
showing, exactly where it's shown. Move and turn the projection until the
building sits where you want it, tap **Build** on the projector's panel, and
the projector sends the plan (every block, in real world coordinates) to
this turtle over rednet.

The turtle then:

1. **Clears the plot:** everything inside the building's box is dug out
   (grass, trees, a hill in the way). Chests, computers and turtles are never
   dug.
2. **Builds it from the bottom up,** one layer at a time, back and forth
   along the rows, placing each block from the block above it. Doors go in
   last on their layer, from the side.
3. **Comes home** when it runs low on blocks or fuel or its inventory is
   full: what it dug up goes in the spoil chest, unused blocks go back in the
   supply chest, and it loads up the next stretch of blocks (13 stacks at a
   time) before heading back.
4. **Reports to the projector** as it goes. The projector's panel shows
   what it's doing ("Builder #7: building, 340 of 1200 (28%)"), and in Layer
   view the projection follows the layer it's on. Tap **Stop** on the panel to
   call it off.

If it runs out of a block, it asks a [storage system](../storage-computer/README.md)
for more (if there's one in range), and otherwise waits for you to put some
in the supply chest, saying what it needs on its screen, on the projector
and on the [status server](../status-server/README.md).

## Files

- `builder.lua`: the program
- `startup.lua`: starts it on boot: it carries on with an unfinished building, or waits for one
- [`lib/nav.lua`](../../lib/nav.lua): position tracking and movement (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`)
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).

## Setup

1. Put the turtle on its **home** block, near where you'll build (up to 256
   blocks away). Give it a wireless or ender modem and some coal.
2. Put the **supply chest** directly behind it and a **spoil chest** directly
   to its left. Fill the supply chest with the blocks the building needs and
   some coal: `projector check <plan>` on the projector lists them.
3. Install the program and run `builder`. It needs its real position: with
   [GPS](../gps-deployer/README.md) it finds it by itself; without GPS it asks
   for its X, Y and Z (look at its block with F3 open) and which way it faces.
   That block is now its home.
4. Reboot it. It waits for a building.
5. On the projector, put the building where you want it and tap **Build**
   (or press B, or run `projector build`).

```
builder              -- wait for a building (startup.lua does this)
builder setup        -- make this block home (asks where it is without GPS)
builder here         -- no GPS: you put it back on its home block, carry on
builder status       -- what it's building and how far along
builder cancel       -- forget the building it's working on
```

### Getting blocks from the storage system

With a [storage computer](../storage-computer/README.md) in range and this
turtle's supply chest set as its **delivery chest**, the builder orders each
load of blocks (and coal) from it before taking them from the chest. With
crafting set up there, things like stairs and slabs get crafted as needed.

## Staying on track

- It saves its progress after every block, so after a reboot or a chunk
  reload it carries on where it stopped.
- With GPS it checks its position every 50 blocks and fixes it if it's been
  moved.
- Without GPS it trusts its own count. When it starts back up mid-building
  it gives you 10 seconds to press a key if you moved it; then put it back on
  its home block, facing the way it faced, and run `builder here`.

## Things to know

- Clearing digs out the whole box the building fills, so check where the
  projection is first: the outline (Outline view) is the box. Keep chests
  and the projector out of it.
- Plans say which block goes where but not which way it faces, so stairs,
  logs and the like face whichever way the turtle happens to be facing.
  Beds and other two-block things may need placing by hand.
- A block it can't place (a protected block in the way, nothing under a
  torch) is skipped and counted; the projector says how many when it's done.
- It builds one building at a time. Another projector asking while it's busy
  is told what it's working on.
- Buildings the [village builder](../village-turtle/README.md) is working on
  can't be sent to it: the village builder builds those itself.
