# mine-server

- **Type:** advanced computer (colour + mouse/touch)
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** ender modem (or wireless modem), optional advanced monitor(s) for the status board and/or map

## What it does

Runs AutoMine. Hands chunks out to the [mining turtles](../mine-turtle/README.md),
keeps track of their progress, and shows a chunk map for planning.

## Files

- `startup.lua`: starts the server on boot and restarts it if it ever stops (first it fetches any newer version from the website)
- `server.lua`: assigns jobs, tracks turtles and their homes
- `ui.lua`: chunk map and turtle panel
- `status.lua`: status board for a monitor
- `config.lua`: cruise height, mining depth, monitors, fuel targets, junk list
- [`lib/report.lua`](../../lib/report.lua): reports to the [status server](../status-server/README.md) (copy it to `/lib/report.lua`)
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed.

## Restarts

The server can be rebooted, crash, or get chunk-unloaded without losing anything:

- The plan, turtle list (with each miner's home), pause state and recent
  events are saved to `/.automine_state`. Saves go through a temp file, so a
  crash mid-save can't corrupt it.
- Turtles keep mining while the server is down, unloading at their own homes.
  Asking for a new job waits and retries until it's back. If the server comes
  back with a different computer ID, turtles find it again within about a minute.
- A bad message or a display error is logged and skipped rather than stopping
  the server.

## Monitors

Both are optional:

- **Status board**: with no settings, any attached monitor shows job totals,
  every turtle's state, chunk, progress bar and fuel, and recent events
  (connections, chunks taken and finished, errors). Set `statusMonitor` in
  `config.lua` to pick a monitor, or `false` to turn it off.
- **Touch map**: shows on the computer's screen unless you set `mapMonitor`
  to a monitor. With the map on a monitor, the computer's screen shows the event log.

Monitors can be added or removed while the server is running.

## Setup

1. Place the computer and attach a modem and any monitors.
2. Copy the files on and reboot.
3. Place your [miners](../mine-turtle/README.md). Each one lives where you
   place it (open sky above it) with its own chest **directly behind it**:
   that spot is its home, where it unloads, refuels and waits when there's
   nothing to do. A second chest on its left or right holds its fuel. Each
   miner tells the server its home, and the server never mines a chunk with
   a home in it.

```
miner home      -- on a miner with a chest behind it: move its home here
server clear    -- on the server (Ctrl+T first): drop every queued and in-progress chunk, then reboot
```

## Using the map

Each cell is one chunk, with north at the top.

| Cell | Meaning |
|---|---|
| blue `HQ` | a miner's home chunk (never mined) |
| yellow `1`, `2`… | queued for turtles, in that order |
| orange `##` | being mined by turtle `##` |
| green | mined out |
| purple `Me` | reserved for you to mine yourself; turtles skip it |
| `T#` | a turtle is currently here |

Pick a tool on the bottom bar, then tap chunks (or drag on the computer screen):

- **Look**: select a chunk to see its block coordinates and status
- **Queue**: add the chunk to the turtles' job queue
- **Me**: mark the chunk as yours. These are listed under *Your chunks* with
  block coordinates so you know where to go.
- **Clear**: unplan the chunk. A turtle working on it stops and takes the next job.
- **Done**: mark the chunk as mined

Header arrows (or the arrow keys/WASD) pan the map; **HQ** recentres it on the first miner's home.
**Pause** sends every turtle home to unload and wait; **Resume** sends them back.

Turtles mining with nothing queued on the map are working on chunks off the
edge of it. Press Ctrl+T on the
server, run `server clear` and reboot: queued and in-progress chunks are
dropped (mined and *Me* chunks stay) and the turtles stop.
