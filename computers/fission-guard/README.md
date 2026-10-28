# fission-guard

- **Type:** advanced computer
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** Fission Reactor Logic Adapter (or Reactor Port) touching it or on a wired modem; advanced monitor (3 × 2 or bigger); optional Induction Port, speaker and wireless modem

## What it does

Keeps a [Mekanism](https://www.curseforge.com/minecraft/mc-mods/mekanism)
Fission Reactor (from Mekanism Generators) out of trouble. Twice a second
it reads the reactor and **SCRAMs** it (an emergency stop) as soon as any of
these is reached:

- temperature 1000 K (Mekanism starts damaging the reactor above 1200 K)
- any damage (1%)
- coolant down to 10%
- heated coolant (steam) up to 90%: the boilers or turbines can't keep up
- waste up to 80%: nothing is taking the waste away

A safety SCRAM **latches**: the reactor stays off, the monitor shows why in
red, a speaker rings, and the [status server](../status-server/README.md)
shows an alert until you fix the cause and tap **Reset**. If anything starts
the reactor while it's latched, from its own screen or with redstone, the guard
SCRAMs it again. The latch is saved, so it survives a reboot.

The monitor shows each gauge as a coloured bar (green, orange near the limit,
red past it): temperature, damage, coolant, heated coolant, fuel and waste,
plus the burn rate (set, actual and maximum) and heating rate. Along the
bottom:

- **Start** starts the reactor, unless it's latched or a gauge is past its limit
- **SCRAM** stops it by hand (this doesn't latch)
- **Reset** clears a latched SCRAM once every gauge is back under its limit (it doesn't start the reactor)
- **-1 -.1 +.1 +1** change the burn rate in mB/t

With an **Induction Port** on the same network it also shows how full the
matrix is, and pauses the reactor at 98% so it isn't burning fuel for power
that has nowhere to go. It starts the reactor again once the matrix is below
80%. A pause isn't a safety SCRAM, so it doesn't latch.

Low fuel only shows a warning: an empty reactor just stops.

## Files

- `fission.lua`: the program. How often it checks and the text size are at the top.
- `config.lua`: the limits, the power pause and the alarm. `install update` never replaces it.
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): saves the latch so a reboot doesn't clear it (copy to `/lib/files.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional; it works without it.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Build the reactor and put a **Fission Reactor Logic Adapter** in its
   casing (a Reactor Port works too). Leave the adapter's redstone mode on
   Disabled, so only the guard and you start the reactor.
2. Place an advanced computer touching the adapter, or connect them with
   wired modems and networking cable (right-click each modem so it turns red).
3. Put an advanced monitor next to the computer (3 wide × 2 high or bigger).
   Optional: a speaker for the alarm, an Induction Port of your matrix on the
   same wired network, and a wireless modem for the status server.
4. Check the limits in `config.lua`, then install and reboot:

   ```
   fission                   -- start the guard (startup.lua does this on boot)
   edit config.lua           -- change the limits, power pause or alarm
   ```

## Things to know

- Keep the computer in the **same chunk** as the reactor (or chunk-load
  both). When the computer's chunk unloads, nothing is watching.
- While it's latched, the bottom of the screen says what tripped it and
  when. Fix the cause (more coolant, a bigger turbine, empty the waste),
  wait for the gauges to drop, tap **Reset**, then **Start**.
- "Mekanism has force-disabled the reactor" means Mekanism itself stopped
  it after damage. The reactor has to cool down and repair before it can
  start again.
- Without a monitor it draws on the computer's own screen; click the
  buttons instead of tapping them.
- Holding Ctrl+T stops the guard and the reactor carries on unguarded.
  startup.lua starts the guard again 5 seconds after it crashes.
- `alarmSide` in `config.lua` turns a redstone side on while a SCRAM is
  latched, for lamps or Mekanism's Industrial Alarm.
