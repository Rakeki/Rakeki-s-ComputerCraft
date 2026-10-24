# AGENTS.md

Lua programs for ComputerCraft (CC: Tweaked) computers and turtles. There is no
build, test or lint tooling: code runs in-game only, so read it carefully
before calling it done and say that it hasn't been run in-game.

## Layout

```
computers/
  _template/        Copy this to start a new computer
  <name>/           One folder per in-game computer or turtle program
    README.md       Type, ID, label, location, peripherals, what it does, files, use
    startup.lua     Runs on boot (often: resume an unfinished job)
    <program>.lua   The program itself
lib/                Shared modules, loaded with require("lib.<module>")
  nav.lua           Turtle position tracking + safe movement (saved across reboots, optional GPS)
  report.lua        Sends status to the status server; no-op without a modem
site/               The GitHub Pages website and in-game installer (see below)
README.md           Project overview, list of computers, how to get code in-game
```

**New programs never go in the repo root.** Every program lives in its own
`computers/<name>/` folder made from `_template`, and gets a line in the
root `README.md` under "Computers". If it uses a lib, add it to that lib's
"Used by" list in `lib/README.md`. It also needs an entry in
`site/programs.json` to show up on the website and in the installer.

## Website

`site/build.mjs` (Node, no dependencies) builds `_site/`: pages from
`site/src/`, data from `site/programs.json`, a copy of `computers/` and
`lib/` for wget, `manifest.json` + `install.lua` for the in-game installer,
and a ZIP per program. GitHub Actions (`.github/workflows/pages.yml`) builds
and publishes it on every push to `main`. Preview locally with
`node site/build.mjs && node site/serve.mjs` (http://localhost:8080).
The installer copies every `.lua` in a program's folder plus its `libs`;
files listed under `keep` (like `config.lua`) are never overwritten.
The 3D renders (`site/src/assets/voxel.js`) and terminal mock-ups
(`cc.js`) use the programs' real dimensions and output text, so update them
when those change.

Existing computers:

| Folder | What | Libs |
|---|---|---|
| `mine-server` | AutoMine server: hands out chunks, planning map | report |
| `mine-turtle` | AutoMine miner, talks to mine-server over rednet | nav, report |
| `status-server` | Monitor dashboard of every computer's status | — |
| `gps-deployer` | Turtle that builds a 4-computer GPS constellation | nav, report (if present) |
| `excavate-turtle` | Standalone turtle: hall + rooms + ledge + stairs | nav, report |
| `strip-mine-turtle` | Standalone turtle: 3x3 main tunnel with 3x3 branches | nav, report |
| `village-turtle` | Turtle that builds themed villages | nav, report |
| `mob-farm-turtle` | Standalone turtle: drop-tower mob farm with water channels | nav, report |

`excavate-turtle/excavate.lua` is the reference for a **standalone,
resumable turtle job** (job file, local coordinates, chest behind the
start, refuel from chest, resume after reboot). Copy its patterns rather than
inventing new ones.

## Skills

Detailed guides live in `.claude/skills/`:

- `new-computer`: adding a computer folder, README format, startup, getting it in-game
- `lib-nav`: the `lib/nav.lua` API, heading convention and gotchas
- `lib-report`: the `lib/report.lua` API and status states
- `turtle-job`: the standalone resumable turtle job pattern (from excavate-turtle)

## Conventions

- **Lua style:** 2-space indent, `local` everything, functions and locals in
  `camelCase` (no snake_case), tunables are `UPPER_CASE` constants at
  the top of the file with a comment each. Sections are separated with
  `---------------------------------------------------------------- name`.
- **Strings:** `("Need %d fuel"):format(n)`. User-facing `print` text is plain,
  friendly English ("Chest is full. Waiting...").
- **Comments** explain why, not what. Header comment on each program gives
  what it does and its usage lines.
- **Movement:** turtles use `lib/nav.lua` (never raw `turtle.forward` for moves
  that change position) so position is saved and protected blocks are never dug.
- **Status:** long-running programs call `report.init(role)`, `report.set(state, detail)`
  as they work, and run `parallel.waitForAny(main, report.loop)`; wrap `main` in
  `pcall` and report `"error"` on failure.
- **Persistence:** save state with `nav.writeFile` / `nav.readFile` /
  `nav.deleteFile` (temp-file writes, crash safe). Job files are `/.<name>_job`.
- **Labels:** turtles label themselves (`os.setComputerLabel("Excavator-" .. id)`)
  so they keep their files when broken.
- **Junk list**: cobblestone, cobbled_deepslate, stone, deepslate, dirt, gravel,
  andesite, diorite, granite, tuff, calcite, netherrack.
- **READMEs** are written for the player: what it does, setup steps, commands,
  things to know. Keep them in sync when behaviour changes.

## CC: Tweaked notes

- Lua 5.2-ish (Cobalt). `sleep`, `os.pullEvent`, `parallel`, `textutils`, `fs`,
  `peripheral`, `rednet`, `gps` are globals.
- `turtle.getFuelLevel()` may return `"unlimited"`; treat it as `math.huge`.
- Turtles freeze when their chunk unloads and the program restarts from
  `startup.lua` when it reloads, hence resumable jobs.
- In-game files: `saves/<world>/computercraft/computer/<id>/`. `lib/` is copied
  to `/lib/` on the computer.
