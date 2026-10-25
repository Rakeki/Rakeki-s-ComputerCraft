# status-server

- **Type:** advanced computer
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** ender modem (or wireless modem), advanced monitor (3×2 or bigger works well)

## What it does

Shows the status of every computer and turtle in the project on the monitor.
Each one broadcasts its status through [`lib/report.lua`](../../lib/report.lua),
and this server collects them. No setup is needed per computer: anything
running `report` appears on its own.

**Grid view:** one card per computer, with online ones first:

- label and ID
- what it's for (its role) and whether it's a turtle, computer or pocket computer
- its state, colour-coded: green working, grey idle, yellow/orange waiting or
  paused, blue travelling, red error
- what it's doing right now
- where it is (X, Y, Z), or "position unknown"
- a fuel bar for turtles, and how long ago it last reported

Positions come from GPS when there is one (see
[gps-deployer](../gps-deployer/README.md)). Turtles that keep track of their own
position (the auto miners, and the excavator when it has GPS) send that instead,
so their position stays up to date even out of GPS range; it's marked
"(tracked)". Offline computers keep their last known position.

A computer that stops reporting for 30 seconds turns grey and shows how long
it's been offline. With more computers than fit on screen, use the arrows in
the header to page through them.

**Detail view:** tap a card to see everything it reported (position, uptime,
fuel) and its recent activity: state changes, events it logged, and when it went
offline or came back. **Back** returns to the grid. **Forget** removes a
computer you've dismantled.

The list is saved to `/.status_state`, so a restart keeps it.

## Files

- `startup.lua`: starts the server on boot and restarts it if it ever stops
- `server.lua`: listens for status broadcasts and tracks each computer
- `dashboard.lua`: the monitor UI
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).

## Setup

1. Place an advanced computer with a modem and an advanced monitor.
2. Copy the files on and reboot.

Without a monitor, the dashboard shows on the computer's own screen (click
instead of tap).

## Reporting from a computer

Already built in: [mine-turtle](../mine-turtle/README.md) and
[mine-server](../mine-server/README.md). For anything else, copy
`lib/report.lua` to `/lib/report.lua` and:

```lua
local report = require("lib.report")
report.init("wheat farm")                 -- what this computer is for
report.set("harvesting", "row 3 of 8")    -- state + what it's doing
report.log("chest full")                  -- adds a line to its activity list
parallel.waitForAny(main, report.loop)    -- keeps it online while main runs
```

The position is filled in from GPS automatically. If the program knows its own
position, pass it: `report.set(state, detail, { pos = { x = 1, y = 2, z = 3 } })`.
For a computer that never moves, add `posFrom = "fixed"` and it won't ask GPS.

The computer needs a wireless or ender modem. Use ender modems for anything
far away or underground: a wireless modem only reaches about 64 blocks at
ground level.
