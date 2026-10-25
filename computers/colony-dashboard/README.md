# colony-dashboard

- **Type:** advanced computer
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** Colony Integrator (Advanced Peripherals) next to it; advanced monitor (3 × 2 or bigger); optional speaker and wireless modem

## What it does

A live dashboard for a [MineColonies](https://www.curseforge.com/minecraft/mc-mods/minecolonies)
colony on a monitor. It reads the colony every 5 seconds through an
Advanced Peripherals Colony Integrator. Tap the tabs along the top to switch
pages:

- **Overview:** colony name, citizens out of the maximum, happiness out of 10
  (green, yellow or red), and how many citizens are idle, asleep, hungry or
  hurt. Also graves, buildings, building sites, work orders, and a list of
  what the colony is waiting for.
- **Citizens:** everyone's name, job and what they're doing. Idle citizens are
  yellow, sleeping ones grey, and anyone under half health red.
- **Buildings:** every hut with its level out of its maximum (green when
  maxed, grey if not built yet) and who works there.
- **Requests:** every open request: the item, how many, and which building
  wants it.
- **Builds:** builder work orders, highest priority first, and whether a
  builder has taken each one.

Long lists scroll with the **v** and **^** buttons under the tabs.

When the colony is under attack the title bar turns red, a speaker (if
attached) rings an alarm, and the [status server](../status-server/README.md)
shows it as an alert.

## Files

- `colony.lua`: the program. Refresh rate, text size, the hungry level and the alarm are at the top.
- `startup.lua`: starts it on boot and restarts it if it stops
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional; it works without it.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. You need the **Advanced Peripherals** mod alongside MineColonies.
2. Place an advanced computer **inside your colony's borders**, with a
   Colony Integrator touching it.
3. Put an advanced monitor next to it (3 wide × 2 high or bigger works well).
   Optional: a speaker for the attack alarm and a wireless modem for the
   status server.
4. Install and reboot:

   ```
   colony                    -- start the dashboard (startup.lua does this on boot)
   ```

## Things to know

- Without a monitor it draws on the computer's own screen; click the tabs
  instead of tapping them. Narrow screens get shorter tab names.
- "Not inside a colony" means the computer is outside the colony's borders:
  move it closer to the town hall.
- It only reads the colony; it never changes anything.
