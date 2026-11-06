# furnace-turtle

- **Type:** crafty mining turtle (crafting table and pickaxe: it crafts its own furnaces), or a mining turtle with a wireless or ender modem for GPS and the [status server](../status-server/README.md) (then give it furnaces)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Places a row of furnaces straight ahead of itself and keeps them smelting
whatever turns up in the chest behind it, fuelled with the coal or charcoal in
that chest. Everything smelted comes out in the chest on its left. It needs no
modems, cables or storage system: it works the furnaces the way hoppers do,
from a lane above the row (what to smelt goes in the top) and a lane below it
(fuel goes in the bottom, results come out of it).

```
   side view                      from above
   . . . . . .   top lane         O
   T F F F F .                    T F F F F
   . . . . . .   bottom lane      C
                                  (C = chest behind, O = output chest on its left)
```

- **Furnaces:** 4 by default, up to 16. Furnaces already standing where the
  row goes are used as they are. A crafty turtle crafts the rest from
  cobblestone (8 each, cobbled deepslate or blackstone too) in its inventory or
  the chest; otherwise put furnaces in the chest or the turtle.
- **What it smelts:** raw ore and ore blocks, sand, logs (into charcoal), clay,
  cactus, kelp and raw meat, fish and potatoes. Each furnace gets one kind at a
  time and the load is shared between the furnaces.
- **Fuel:** coal, charcoal, blaze rods, dried kelp blocks or coal blocks from
  the chest, just enough for what each furnace has to smelt. It burns some
  for itself too: about 4 fuel per furnace each round. It takes only
  the fuel the smelting on hand needs, so a chest it shares with another
  turtle keeps the rest. Charcoal it makes is used the same way; the rest goes out.
- **Everything else** that's in the chest behind it (diamonds, cobblestone it
  doesn't need) goes into the output chest too, so you only have one chest to
  empty.
- **Rounds:** every 20 seconds while anything is smelting; with nothing to do
  it looks in the chest every 30 seconds (and straight away when you put
  something in the turtle).
- If the output chest is full it waits, saying so, until there's room.

The chest behind it can be another turtle's chest: put it behind a
[strip miner](../strip-mine-turtle/README.md) or [tree farm](../tree-farm-turtle/README.md),
on the other side of the chest, and it smelts what they bring home.

## Files

- `furnace.lua`: the program. Furnace count, round times, fuel kept and what it smelts are at the top.
- `startup.lua`: carries on with the job after a reboot or chunk reload (first it fetches any newer version from the website)
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers
- [`lib/files.lua`](../../lib/files.lua): crash-safe job file
- [`lib/report.lua`](../../lib/report.lua): status server reports (does nothing without a modem)
- [`lib/errlog.lua`](../../lib/errlog.lua): saves errors to `/errors.log`

## Use

1. Place the turtle where the row should start, facing along it. The row and
   the lanes need a strip 1 wide and 3 high (from one below the turtle to one
   above), as long as the row plus 2; it digs whatever is there.
2. Put a chest directly behind it (what to smelt, and fuel) and one on its
   left (what comes out).
3. Put some coal in the chest, and cobblestone (crafty turtle) or furnaces.
4. Run the command and press Enter.

```
furnace          -- a row of 4 furnaces, then keeps them going
furnace 8        -- a row of 8
furnace resume   -- carry on (startup.lua does this)
furnace here     -- no GPS and it was moved: you put it back on its start block
furnace cancel   -- forget the job; the furnaces stay
```

## Staying on track

A crafty turtle has no room for a modem, so it counts its moves from the start
block (it never goes more than a block from its row). If it starts up and you
might have moved it, it gives you 10 seconds to press a key; then put it back
on its start block, facing the row, and run `furnace here`. With a modem it
waits for GPS and checks its position with it every time it starts.

## Things to know

- A different count later: `furnace cancel`, then `furnace <count>`. The
  furnaces already there are used again.
- Smelting only: blast furnaces and smokers standing in the row work too,
  but it only places plain furnaces.
- Not yet tried in-game. It relies on vanilla furnaces' faces: the top takes
  what to smelt, the bottom takes fuel and gives the results.
