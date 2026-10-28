# power-dashboard

- **Type:** advanced computer
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** Induction Port (or energy cubes) touching it or on a wired modem; advanced monitor (3 × 2 or bigger); optional turbine valves, wireless modem

## What it does

A live monitor for your [Mekanism](https://www.curseforge.com/minecraft/mc-mods/mekanism)
power, read once a second:

- **Stored:** energy in the Induction Matrix out of its capacity, with a
  bar that turns yellow below half, orange when low and red when nearly
  empty.
- **In / Out:** what went into and out of the matrix last tick.
- **Full in / Empty in:** how long until the matrix is full or empty at the
  rate of the last 30 seconds (or "Steady").
- The matrix's cells, providers and how much it can move per tick.
- A **graph** of how full it was over the last hour.
- One line per **Industrial Turbine** (what it's making, how full its steam
  is and how hard it's running) and per **energy cube** (stored and how full).

Mekanism counts energy in joules; the dashboard shows FE (2.5 J each, as
Mekanism's default config has it), or joules if you prefer.

Without an Induction Matrix, energy cubes count as the store instead.
Several matrices are added together. A matrix with more than one port
(or a turbine with more than one valve) is only counted once.

It can also switch a **redstone signal** on when power is low and off once
it's nearly full again, to start and stop generators. The
[status server](../status-server/README.md) shows what's stored and turns
red when it's almost empty.

## Files

- `power.lua`: the program. Refresh rate and text size are at the top.
- `config.lua`: units, graph length, the redstone signal and device names. `install update` never replaces it.
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional; it works without it.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Place an advanced computer touching an **Induction Port** of your matrix,
   or connect them with wired modems and networking cable (right-click each
   modem so it turns red). Add turbine valves and energy cubes to the same
   cable to see them too.
2. Put an advanced monitor next to the computer (3 wide × 2 high or bigger).
3. Optional: set `signalSide` in `config.lua` and run a redstone line from
   that side to your generators.
4. Install and reboot:

   ```
   power                     -- start the dashboard (startup.lua does this on boot)
   edit config.lua           -- units, redstone signal, names
   ```

## Things to know

- The graph starts empty and fills from the right as time goes by. It
  isn't saved, so a reboot starts it again.
- "Full in" needs a few seconds of readings before it shows.
- Without a monitor it draws on the computer's own screen.
- The [fission guard](../fission-guard/README.md) can pause a reactor while
  the matrix is full; this dashboard only watches.
