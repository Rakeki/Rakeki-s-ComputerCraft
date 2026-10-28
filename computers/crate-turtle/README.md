# crate-turtle

- **Type:** any turtle (it doesn't move, so no tool or fuel), plus a wireless or ender modem for `crate stock` and the [status server](../status-server/README.md)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Turns a **Creative Crate** from Create into a tap. A Creative Crate gives
endless amounts of one item, whichever you right-click it with. The turtle
sits between the crate and a chest and moves that item into the chest a
stack at a time. It can:

- **keep the chest full** (`crate`): fills it, then tops it up whenever you
  take something out;
- **send a set amount** (`crate 500`), then stop;
- **keep a set amount in the chest** (`crate keep 256`), so the chest never
  overflows with it;
- **keep a set amount in the [storage system](../storage-computer/README.md)**
  (`crate stock 1000`): the chest is the storage computer's input chest, and
  the turtle asks the storage computer how many it holds every 15 seconds and
  sends more when it drops below. Turtles, crafting and the smelter then
  never run out of it.

When the chest is full it waits and tries again every 5 seconds. If the
crate has no item set it says so and waits until you set one. Change the
crate's item at any time: the turtle notices and carries on with the new one.

It saves its job, so after a reboot or chunk reload it carries on by itself.

## Files

- `crate.lua`: the program. Tunables are at the top (how often it checks, and `CRATE_SIDE` if it can't find the crate by itself).
- `startup.lua`: carries on with the saved job after a reboot or chunk reload, and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/files.lua`](../../lib/files.lua): saves the job without losing it in a crash (copy to `/lib/files.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): asks the storage computer for counts (copy to `/lib/net.lua`). Only `crate stock` needs it.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Use

1. Place the **Creative Crate** and right-click it with the item you want.
2. Place the turtle so the crate is **in front of it, above it or below
   it**.
3. Put a **chest** on another of those sides: below the turtle is checked
   first, then above, then in front. For `crate stock`, that chest is the
   storage computer's input chest (or one of its extra input chests).
4. For `crate stock`, give the turtle a **wireless or ender modem** on its
   left or right side.
5. Run one of these:

   ```
   crate                    -- fill the chest, then keep it full
   crate 500                -- send 500, then stop
   crate keep 256           -- keep 256 of the item in the chest
   crate stock 1000         -- keep 1000 in the storage system
   crate stop               -- forget the job (it won't start again on boot)
   ```

To stop it, hold Ctrl+T, then hold it again while it says "Restarting in 5s",
and run `crate stop`.

## Things to know

- Anything put into a Creative Crate is destroyed. The turtle never drops
  into the crate, but don't let a hopper or pipe feed into it either.
- It finds the crate by its name. If a Create version names it differently
  and the turtle says it can't see one, set `CRATE_SIDE` at the top of
  `crate.lua` to `"front"`, `"top"` or `"bottom"`.
- It moves one stack at a time. For more at once, run more turtles off
  more crates.
- `crate keep` and `crate stock` send one item first to learn what the crate
  gives, so they never overshoot. `crate stock` also counts what's still
  sitting in the input chest, so it doesn't send the same items twice while
  the storage computer is putting them away.
- Creative Crates only exist in creative mode or by commands; in survival
  you can't craft one.
