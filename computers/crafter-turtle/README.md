# crafter-turtle

- **Type:** crafty turtle (a turtle with a crafting table), plus a wireless or ender modem
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

The crafting arm of the [storage system](../storage-computer/README.md). When
a turtle asks the storage computer for something it doesn't have (say the
[village builder](../village-turtle/README.md) wants 40 jungle fences), but it
could be made from what is stored, the storage computer works out the crafts
and has this turtle make them, ingredients first: jungle logs into planks,
planks into sticks, then the fences.

For each batch the storage computer puts the ingredients in this turtle's
chest and tells it which item goes in which cell of the crafting grid. The
turtle takes them out a stack at a time and sorts them into its grid by
name, so any chest or barrel works, even a Sophisticated barrel that stacks
matching items together. It crafts, puts everything back in the chest, and
tells the storage computer what it made; the storage computer puts the
results away. If it ever makes the wrong thing, the storage computer says
so instead of counting it as done. The turtle that asked gets them on its next request:
the village builder asks again every 10 seconds while it waits.

One turtle is enough to start with. For more crafting at once, set up more
crafting turtles, each with its own chest, and a
[crafting overseer](../craft-overseer/README.md): it shares the jobs out
between them and shows the queue on a monitor. Without an overseer, the
storage computer uses one of them.

It knows the recipes for everything the village themes use that can be
crafted (planks, slabs, stairs, fences, doors, beds, dyed wool, lanterns,
torches, deepslate tiles, sandstone, glass panes and more; the list is in
[`recipes.lua`](../storage-computer/recipes.lua) on the storage computer).
Smelted blocks like smooth sandstone can't be crafted. Teach it anything else
with `crafter learn`.

## Files

- `crafter.lua`: the program
- `startup.lua`: starts it on boot and restarts it if it stops
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.
- [`lib/claim.lua`](../../lib/claim.lua): tells the storage computer which chest is its crafter chest (copy to `/lib/claim.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.

The recipes and the planning live on the storage computer (`recipes.lua` and
`crafting.lua` there), not on this turtle.

## Setup

1. Craft a **crafty turtle** (a turtle with a crafting table) and put a
   **wireless or ender modem** on its other side.
2. Place it near the storage network with a **chest directly in front of
   it**.
3. Connect that chest to the storage network: a **full-block wired modem**
   touching the chest (not between the chest and the turtle), networking cable
   back to the storage, and right-click the modem so it turns red.
4. The storage computer needs a wireless modem too: the two talk by
   wireless. Or, instead of wireless modems on both, put a **full-block
   wired modem** against the back of the turtle, joined to the storage
   cable, and they talk over the cable.
5. Install this program on the turtle and reboot it. It tells the storage
   computer that the chest in front of it is the **crafter chest** (the
   storage computer drops one item into each chest that could be it until
   the turtle sees it arrive), and says "The storage system uses my chest
   (...)". There's nothing to pick in `storage setup`. It checks again
   every 5 minutes, and if the storage computer isn't running yet it keeps
   trying until it is.

   ```
   crafter                   -- start (startup.lua does this on boot)
   crafter learn             -- teach the storage system a recipe (see below)
   ```

### Teaching it a recipe

1. Stop the crafter: hold Ctrl+T, then hold it again while it says
   "Restarting in 5s" so it doesn't start back up. Put one set of the recipe in its
   crafting grid: slots 1-3 are the top row, 5-7 the middle and 9-11 the
   bottom. Leave every other slot empty.
2. Run `crafter learn`. It crafts it once to see what it makes and sends the
   recipe to the storage computer, which saves it (updating the programs never
   loses it). A new recipe for an item replaces an old learnt one.
3. Take the items back out, or just start the crafter again: it puts
   anything left in itself into its chest, and the storage computer puts it
   away.

## Things to know

- With an [ME or RS system](../storage-computer/README.md#me-and-rs-systems)
  behind the storage computer, the system crafts from its own patterns first;
  this turtle only makes what it has no pattern for. Its ingredients pass
  through the storage computer's transfer chest, so that needs to be set.

- One craft job at a time, up to 64 crafts per batch (fewer for things that
  don't stack to 64, and never more than 6 stacks of output). Big orders are
  split into batches.
- If there isn't enough to make a whole order, the storage computer has it
  make as many as it can. If something runs out half way, that order stops
  and the storage computer's footer says what was missing; the turtle that
  asked will ask again, and it starts again once there's enough.
- If this turtle is off or out of range, turtles waiting on a craft are told
  crafting is stuck, and it all carries on once it's back.
- It uses whichever matching item there's most of where a recipe takes any
  planks or any coal.
- Items with extra data (enchanted or named) are never used as ingredients.
