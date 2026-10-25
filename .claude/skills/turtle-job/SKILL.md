---
name: turtle-job
description: The standard pattern for a standalone, resumable turtle job in this repo (job file, local coordinates relative to the start, chest behind the start, junk dropping, refuel from chest, resume/cancel/here commands, GPS checks), modelled on computers/excavate-turtle/excavate.lua. Use when writing a turtle that mines, digs or builds on its own.
---

# Standalone resumable turtle job

Reference implementation: `computers/excavate-turtle/excavate.lua`. Read the
relevant section there before writing; reuse its functions and wording.
Uses [[lib-nav]], [[lib-report]] and [[lib-errlog]]; folder setup is in [[new-computer]].

## Shape of the program

```lua
-- <What it does, one paragraph.>
--
--   prog [args]
--   prog resume
--   prog cancel
local nav = require("lib.nav")
local report = require("lib.report") -- status server; does nothing without a modem
local errlog = require("lib.errlog") -- saves errors to /errors.log

local JOB_FILE = "/.prog_job"
-- tunables (UPPER_CASE, commented)
local JUNK = {} -- built from a name list, see excavate.lua

local job -- everything needed to resume: args, origin, gps flag, progress counters
```

Sections, in order: coordinates, plan, inventory and fuel, main, then the
argument handling at the bottom.

## Job state and progress

- `job` holds the arguments, `origin`, `gps` (bool), and progress counters
  (excavate uses `phase` + `cell`). Everything derived (the plan) is rebuilt from
  `job` on resume, never saved.
- Work is split into small numbered units. After each unit:
  `job.cell = job.cell + 1; save()` with `local function save() nav.writeFile(JOB_FILE, job) end`.
  Units must be safe to redo, since a reboot can land mid-unit.
- Finished: `nav.deleteFile(JOB_FILE)`, `report.set("done", ...)`.

## Local coordinates

Jobs work in their own frame: `x` to the right, `z` forward, `y` up,
relative to `job.origin = { x, y, z, heading }` (the turtle's nav position and
heading at the start).

```lua
local DIRS = { [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 }, [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 } }

local function toWorld(p)
  local o = job.origin
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  return o.x + p.x * r.x + p.z * f.x, o.y + p.y, o.z + p.x * r.z + p.z * f.z
end

local function here() -- inverse of toWorld for the current nav position
  local o, w = job.origin, nav.getPos()
  local f, r = DIRS[o.heading], DIRS[(o.heading + 1) % 4]
  local dx, dz = w.x - o.x, w.z - o.z
  return { x = dx * r.x + dz * r.z, y = w.y - o.y, z = dx * f.x + dz * f.z }
end
```

Facing in the local frame: forward is `job.origin.heading`, right is
`(heading + 1) % 4`, back (the chest) is `(heading + 2) % 4`, left `(heading + 3) % 4`.

Trips home must follow paths the job has already cleared (excavate's
`travel`/`reach`), not a straight `nav.goTo` through solid rock.

## Chest, junk and fuel (copy from excavate.lua)

- **Chest directly behind the start.** `faceChest()` = `nav.face((job.origin.heading + 2) % 4)`.
- `fuelLevel` is `inv.fuelLevel` ([[lib-net]]: lib/inv.lua), which maps `"unlimited"` to `math.huge`;
  `emptySlots` and `refuelFromInventory` come from lib/inv.lua too.
- `dropJunk()` drops `JUNK` items; `unload()` goes to the start, drops junk in
  front, empties the rest into the chest, waits (`report.set("waiting", "chest full or missing")`,
  `sleep(5)` retry) if `turtle.drop()` fails, then tops up with `refuelFromChest(REFUEL_TO)`.
- `refuelFromChest(target)` sucks from the chest, burns fuel, puts non-fuel back.
- `waitForFuel(target)` goes home, refuels from the chest, otherwise waits on
  `turtle_inventory` or a 10 s timer re-checking the chest.
- `housekeeping()` after every unit:
  ```lua
  if emptySlots() <= 1 then
    dropJunk()
    if emptySlots() <= 2 then unload() end
  end
  local needed = homeDistance() -- distance home + margin
  if fuelLevel() < needed then
    refuelFromInventory(needed + 1000)
    if fuelLevel() < needed then waitForFuel(needed + 1000) end
  end
  ```
  Each unit starts with `reach(p)` (travel to its spot), so after an
  unload/refuel trip the next unit takes the turtle back on its own.

## GPS

- `local hasGps = gpsPos() ~= nil` (`gpsPos` is `nav.locate`), `useGps = hasGps and (not job or job.gps)`,
  `nav.init(useGps)`. A job started without GPS stays in counted coordinates.
- With `job.gps`, every 20 units `checkPosition()` compares nav with GPS and
  calls `nav.init()` + `rejoin()` (go back to start if off the plan).
- Without GPS, on resume `confirmResume()` (`nav.confirmResume(putBack)`) gives
  10 s to press a key if the turtle was moved; the player then puts it back on the start block and runs
  `prog here`, which does `nav.setPosition(toWorld(start)..., job.origin.heading)`.

## Commands

| Arg | Does |
|---|---|
| (sizes) | New job. Refuses if a job exists ("Run 'prog resume' or 'prog cancel'."). Prints sizes and a fuel estimate, "Press Enter to start", `save()`, refuel from chest. |
| `resume` | Rebuild plan from the job file and continue. `startup.lua` runs this. |
| `here` | No GPS: player has put it back on the start block. |
| `cancel` | `nav.deleteFile(JOB_FILE)`. |

Label on start: `if not os.getComputerLabel() then os.setComputerLabel("Prog-" .. os.getComputerID()) end`.

End of file:

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

## Jobs given in world coordinates

A job that comes from another computer (the projector's plan for
`builder-turtle`) is in **real world coordinates**, so the turtle must know
its own real position. Copy `computers/builder-turtle/builder.lua`:

- `builder setup` makes the current block home and saves `/.builder_home`
  `{ x, y, z, heading, gps }`: from GPS if there is one, otherwise the player
  types the position and facing shown on F3.
- Save the job (big: every block) once to its own file, and the progress
  (stage + step) to a small file rewritten after every block.
- Refuse a job too far from home (`MAX_DISTANCE`), and with GPS check the
  counted position every `CHECK_EVERY` blocks.
- Inside the work area, travel one block above the layer being worked on,
  where nothing is built yet; anywhere else, fly above it.
- Report progress back to the computer that sent the job (`projector_build`
  `progress`) as well as to the status server.
- Sharing a job between turtles: give each its own part of the area to
  clear and build, have every turtle stay out of the others' parts, and give
  each a cruise height of its own (`lane`) so they never meet in the air
  (builder.lua's strips, village.lua's crew).

## Materials from the storage system

A job that places blocks can restock from the storage system as well as its
home chest: at home, facing the supply chest, `supply:check(askStorage,
"front")` (a `claim.tracker` from `lib/claim.lua`) so the storage computer
sends to that chest, then `deliver` what the next trip needs and pass the
reply to `supply:seen` (see [[storage-system]]; builder.lua's
`orderFromStorage` and village.lua's `restock`). Without a storage computer
in range it just uses the chest.

## Blocked moves

nav refuses to dig protected blocks and can't dig bedrock. Don't skip ahead
silently: print where it's stuck and why, `report.set("stuck", msg)`, and
retry until clear (see excavate's `reach`). Skip only units that are themselves
undiggable.
