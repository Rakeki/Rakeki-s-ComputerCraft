# fusion-control

- **Type:** advanced computer
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** Fusion Reactor Logic Adapter (or Reactor Port) touching it or on a wired modem; advanced monitor (3 × 2 or bigger); optional speaker and wireless modem

## What it does

A control panel for a [Mekanism](https://www.curseforge.com/minecraft/mc-mods/mekanism)
Fusion Reactor (from Mekanism Generators), read once a second:

- **Plasma** and **case** temperature, each against its maximum (the bar
  turns orange past 75% and red past 90%).
- **Deuterium**, **tritium** and **D-T fuel** tanks.
- **Water** and **steam** when the reactor is water-cooled (it works this out
  from whether there's water in it).
- The **injection rate** with the minimum needed to keep the reaction going,
  and the power it's **making** per tick.

Along the bottom, **-10 -2 +2 +10** change the injection rate (it's always
even, 0 to 98 mB/t) and **Stop** sets it to 0. After a stop, **Resume**
puts back the rate it had.

Under the gauges it says what needs doing: fire the laser at the Hohlraum to
ignite, low deuterium, tritium or water, steam backing up, the case running
hot, or an injection rate too low to keep the reaction going. If the
reaction goes out on its own, a speaker beeps and the
[status server](../status-server/README.md) shows an alert.

Mekanism counts energy in joules; the panel shows FE (2.5 J each, as
Mekanism's default config has it), or joules if you prefer.

## Files

- `fusion.lua`: the program. Refresh rate and text size are at the top.
- `config.lua`: units and the warning levels. `install update` never replaces it.
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional; it works without it.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Put a **Fusion Reactor Logic Adapter** in the reactor's casing (a Reactor
   Port works too).
2. Place an advanced computer touching it, or connect them with wired modems
   and networking cable (right-click each modem so it turns red).
3. Put an advanced monitor next to the computer (3 wide × 2 high or bigger).
   Optional: a speaker and a wireless modem.
4. Install and reboot:

   ```
   fusion                    -- start the panel (startup.lua does this on boot)
   edit config.lua           -- units and warning levels
   ```

## Things to know

- The panel doesn't ignite the reactor: that still takes a Hohlraum filled
  with D-T fuel in the reactor and a laser burst. It tells you when it's
  ready for the laser.
- **Stop** (rate 0) lets the reaction burn what's already injected and then
  go out. A reaction that has gone out needs a new filled Hohlraum to start
  again. While the plasma is still hot enough you don't need the laser; once
  it has cooled, you do.
- Without a monitor it draws on the computer's own screen; click the buttons
  instead of tapping them.
