---
name: new-computer
description: How to add a new ComputerCraft computer or turtle program to this repo (folder layout, README format, startup.lua, root README entry, getting it in-game). Use whenever writing a new program, turtle script or computer.
---

# Adding a computer or program

Every program gets its own folder under `computers/`. Never put programs in the
repo root.

## Steps

1. Copy `computers/_template/` to `computers/<name>/`. Name it after what it is,
   e.g. `excavate-turtle`, `mine-server`, `wheat-farm`.
2. Write the program as `computers/<name>/<program>.lua`. The program name is
   what the player types in-game (`excavate`, `miner`, `village`).
3. Replace `startup.lua`. Typical shapes:
   - **Resumable job** (standalone turtles):
     ```lua
     -- Pick an unfinished excavation back up after a reboot or chunk reload.
     if fs.exists("/.excavate_job") or fs.exists("/.excavate_job.tmp") then
       shell.run("excavate", "resume")
     end
     ```
   - **Always-on service** (servers, networked miners):
     ```lua
     -- Keep the miner running: if it ever stops or crashes, start it again.
     while true do
       shell.run("miner")
       print("Miner stopped. Restarting in 5s (Ctrl+T to cancel)")
       sleep(5)
     end
     ```
4. Fill in `README.md` (format below).
5. Add a line to the root `README.md` under **Computers**:
   `- [<name>](computers/<name>/README.md): <one-line what it does>`
6. If it uses `lib/` modules, add it to that module's "Used by" text in
   `lib/README.md`.
7. Add an entry to `site/programs.json` so it appears on the website and in
   the installer (title, command, device, libs, stats, setup, commands, render).
   Run `node site/build.mjs` to check it builds.

## README format

```markdown
# <name>

- **Type:** mining turtle, plus a wireless or ender modem for GPS and the [status server](../status-server/README.md)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does
Plain-English description for the player. Default sizes/layout, what happens
when the chest fills or fuel runs out.

## Files
- `<program>.lua`: the program. Tunables are at the top.
- `startup.lua`: resumes an unfinished job after a reboot or chunk reload
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too.

## Use
1. Numbered setup steps (where to place the turtle, chest, fuel).
2. A code block of commands with `--` comments:
   ```
   program                  -- defaults
   program 64 32            -- custom size
   program resume           -- carry on after stopping it
   program cancel           -- forget the current job
   ```

## Things to know (optional)
```

## Getting it in-game

Once pushed, `wget run https://rakeki.github.io/Rakeki-s-ComputerCraft/install.lua <name>`
installs it with its libs. Or by hand:
files go in `saves/<world>/computercraft/computer/<id>/` (run `id` in-game).
Copy the program, `startup.lua`, and any used `lib/*.lua` to `/lib/`.
Modules load with `require("lib.nav")`.

Related: [[lib-nav]], [[lib-report]], [[turtle-job]].
