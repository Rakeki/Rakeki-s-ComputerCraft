---
name: lib-nav
description: Reference for lib/nav.lua, the shared turtle movement and position library (headings, safe digging, goTo, GPS calibration, crash-safe state files). Use when writing or changing any turtle code that moves, digs, or saves state.
---

# lib/nav.lua

```lua
local nav = require("lib.nav")
```

Tracks the turtle's position and heading and saves them to `/.nav_state`
after **every** move or turn, so a reboot or chunk reload never loses track.
All turtle movement should go through it.

## Coordinates and headings

World-style axes: `x` east, `y` up, `z` south.

| heading | name | step |
|---|---|---|
| 0 | north | z - 1 |
| 1 | east | x + 1 |
| 2 | south | z + 1 |
| 3 | west | x - 1 |

`nav.HEADINGS.north == 0` etc. `nav.face` accepts a number or a name.
`turnRight` adds 1, `turnLeft` subtracts 1 (mod 4).

Every turtle that moves needs GPS (all but the gps-deployer): call
`nav.waitForGps()` before the first move. Jobs from before that rule may still
be in counted coordinates: there the numbers are whatever was set with `nav.setPosition`
(commonly `0, 0, 0, "north"`), so treat them as relative. Programs that work
in their own frame (forward/right of the start) convert with an origin; see
[[turtle-job]].

## Setup

| Call | Does |
|---|---|
| `nav.init(useGps)` | Loads the saved position. Unless `useGps == false`, also calibrates with GPS (steps forward once and back to learn heading; if blocked it tries the other sides, then turns back, so it always ends facing the way it started). The step needs fuel: with none burnt it burns one fuel item it carries, or says so and waits for one, rather than guess north. Returns `true` if the position is known. |
| `nav.setPosition(x, y, z, h)` | Sets position/heading outright (h number or name) and saves. |
| `nav.locate()` | Where GPS says the turtle is, rounded to the block, or nil (no move, no calibration). |
| `nav.waitForGps()` | Waits until GPS answers (tries every 5 s; prints why, and `report.set("waiting", ...)` if the program loaded `lib.report`). Returns the position. After a server restart the GPS hosts may still be starting, so moving turtles wait here rather than trust a saved position. |
| `nav.confirmResume(putBack)` | Resuming an old job started without GPS: gives the player 10 s to press a key if the turtle was moved. True to carry on; on a key prints `putBack` (how to put it back and run `prog here`) and returns false. |

Typical start:

```lua
local knowsPosition = nav.init(useGps)
if not knowsPosition then nav.setPosition(0, 0, 0, "north") end
```

## Movement

All return `ok, err`. `err` is one of `"nofuel"`, `"protected"`, `"bedrock"`,
`"undiggable"`, `"blocked"`, or `nav.OUT_OF_BOUNDS` ("the edge of my area
(nav.bounds)", see Bounds below).

| Call | Notes |
|---|---|
| `nav.forward()` / `nav.up()` / `nav.down()` | Digs whatever is in the way (retries for falling gravel/sand), attacks mobs, waits for other turtles. Position only changes on success. |
| `nav.turnLeft()` / `nav.turnRight()` / `nav.face(h)` | `face` picks the shortest turn. |
| `nav.digUp()` / `nav.digDown()` | Clears the block above/below (keeps going while gravel falls). No forward dig: moving forward digs. |
| `nav.goTo(x, y, z)` | Rises to `y` first, then moves x then z, then descends. **If blocked it goes up a block and retries (up to 8 times)**, so it can dig new holes in a ceiling. Inside carefully shaped tunnels, prefer moving along known-clear paths (axis by axis) yourself. |
| `nav.getPos()` | Copy of `{ x, y, z }`. |
| `nav.getHeading()` | 0-3. |

Never dug (protected): anything whose name contains `chest`, `barrel`,
`shulker_box`, `hopper`, `furnace`, `computercraft:` (turtles, computers) or
`spawner`. Code must handle `ok == false` (stop and report, wait, or skip).

## Bounds

`set nav.bounds x1,z1,x2,z2` (world X and Z, both corners inside, commas: CC's
`set` keeps only one word) fences a turtle in: `nav.forward` refuses a step
onto a column outside it and returns `false, nav.OUT_OF_BOUNDS`, and
`nav.goTo` gives up on it at once instead of climbing round. Up and down
are never refused. A turtle placed outside may move only towards the area.

It only applies while the position is in world coordinates: after GPS
calibration (`nav.init`), or `nav.setPosition(x, y, z, h, true)`. A plain
`nav.setPosition` (a job counted from its own start, no GPS) turns it off, so
pass `job.gps` when re-anchoring a GPS job (`here`). `nav.bounds()` returns
`{ x1, z1, x2, z2 }` or nil and `nav.inBounds(x, z)` checks a column, for
checking a job's size before starting. Raw `turtle.*` moves (the calibration
step, programs moving without nav) aren't covered: keep turtles a block in
from the edge when placing them.

## State files

Crash-safe helpers for any program's own state (write to `.tmp`, then move).
They are lib/files.lua's `files.write` / `read` / `delete` ([[lib-net]]), so
nav needs `/lib/files.lua` too (list `files` in the program's libs):

```lua
nav.writeFile("/.myjob_job", job)   -- textutils.serialize
local job = nav.readFile("/.myjob_job") -- falls back to the .tmp copy, nil if none
nav.deleteFile("/.myjob_job")       -- removes both
```

`startup.lua` should check for both `path` and `path .. ".tmp"`.

## Gotchas

- Use nav for every move that changes position. A raw `turtle.forward()`
  desyncs the saved position.
- Fuel: nav fails with `"nofuel"` at 0; programs must keep enough fuel to get
  home themselves (see [[turtle-job]]).
- `turtle.getFuelLevel()` may be `"unlimited"`: use `inv.fuelLevel()` (lib/inv.lua).
