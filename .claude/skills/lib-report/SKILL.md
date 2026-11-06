---
name: lib-report
description: Reference for lib/report.lua, which sends a computer's or turtle's status to the status-server dashboard. Use when adding status reporting to a program or changing what a program shows on the dashboard.
---

# lib/report.lua

```lua
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log
```

Broadcasts this computer's status over rednet (protocol `cc_status`) to the
[status server](../../../computers/status-server/README.md). Without a
wireless/ender modem it silently does nothing, so it is always safe to include.

## API

| Call | Does |
|---|---|
| `report.init(role)` | Role is a short "what this is for", e.g. `"excavator"`, `"auto miner"`. Call once before the main loop. |
| `report.set(state, detail, extra)` | Current state and what it's doing. Cheap: only sends when something changed (at most every 2 s) or as a 10 s heartbeat. Call it as often as you like, e.g. every cell/step. |
| `report.log(text)` | One-off line for the computer's activity list. |
| `report.loop()` | Heartbeat loop; run it beside the program. It also answers the update watcher. |
| `report.handle(ev)` | For a program with its own event loop and no `report.loop` (mine-server): pass every event; `true` when it was an update request (it may reboot the computer). |
| `report.updateNow()` | Runs `install boot` with its text hidden and reboots if anything changed; else `false, why`. The update watcher uses it on itself. |

Every report carries `versions` (the installer's `/.installed_versions`,
program -> version, re-read every minute). On `cc_update` the update watcher
sends `update`; the computer answers `ok` (or `why`: `install.remote` /
`install.autoupdate` off, no http, no `/install.lua`), sets state `updating`,
and reboots if `install boot` changed anything, else carries on and logs
why. A reboot mid-job is fine: programs here resume after one anyway.

`extra` is a table of extra fields. `{ pos = nav.getPos() }` sends a tracked
position; add `posFrom = "fixed"` for a computer that never moves. Only pass
`pos` when the coordinates are real world coordinates (GPS-based). Otherwise
leave it out and report.lua uses GPS itself if available.

Turtles also send fuel and fuel limit automatically.

## States

One lowercase word. The dashboard colours them: green working, grey idle,
yellow/orange waiting or paused, blue travelling, red error. Words used so far:
`starting`, `digging`, `mining`, `building`, `sealing`, `farming`, `crafting`,
`clearing`, `paving`, `surveying`, `serving`, `running`, `unloading`, `restocking`,
`checking`, `travelling`, `returning`, `waiting`, `paused`, `idle`, `stuck`, `done`,
`alert`, `error`. A word the dashboard doesn't know shows in white; add new
ones to `STATE_COLOR` in `computers/status-server/dashboard.lua`.
A state change is also logged as an activity event.

## Standard wiring

```lua
report.init("excavator")
errlog.init("excavate", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
```

Inside the work loop:

```lua
report.set("digging", progressText(), job.gps and { pos = nav.getPos() } or nil)
```

When waiting on the player, report why: `report.set("waiting", "chest full or missing")`.
