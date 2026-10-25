# AGENTS.md

Lua programs for ComputerCraft (CC: Tweaked) computers and turtles. There is no
build, test or lint tooling: code runs in-game only, so read it carefully
before calling it done and say that it hasn't been run in-game.

## Layout

```
computers/                  In-game programs, one folder each (never in the repo root)
  _template/                Copy this to start a new computer; not published
  <name>/                   One in-game computer or turtle program
    README.md               The player's manual (format below); shown on the website
    <program>.lua           The program; its file name is the command typed in-game
    startup.lua             Runs on boot (resume an unfinished job, or keep a service running)
    <helper>.lua            Optional modules loaded with require("<helper>"), e.g. ui.lua
    config.lua              Optional player settings; list it under "keep" in programs.json
    preview/*.svg           Optional renders, linked from the README and the website
lib/                        Shared modules, copied to /lib/ in-game, loaded with require("lib.<module>")
  README.md                 One line per module: what it does and which programs use it
  nav.lua                   Turtle position tracking + safe movement (saved across reboots, optional GPS)
  report.lua                Sends status to the status server; no-op without a modem
site/                       The website and in-game installer
  programs.json             Website + installer data for every program and lib (schema below)
  build.mjs                 Builds _site/ (Node, no dependencies)
  serve.mjs                 Local preview of _site/ on http://localhost:8080
  install.lua               The in-game installer; {{SITE_URL}} is filled in by the build
  src/index.html            Home page template
  src/page.html             Template for every program and library page
  src/404.html              Not-found page
  src/assets/app.js         Builds the pages from programs.json
  src/assets/cc.js          CC terminal mock-ups (typing demo, AutoMine map, dashboard)
  src/assets/voxel.js       Isometric block renders of each program's build
  src/assets/style.css      Site styles (CC palette, Minecraft GUI panels)
.claude/skills/             Detailed guides for agents (see Skills)
.claude/launch.json         Preview server config ("site")
.github/workflows/pages.yml Builds and publishes the website on every push to main
_site/                      Build output; git-ignored, never edit by hand
README.md                   Project overview, website link, list of computers, how to install
AGENTS.md                   This file (CLAUDE.md just includes it)
```

## Documentation

Every piece of documentation has one home. When behaviour changes, update
each place that describes it in the same change.

| Where | Audience | What goes in it |
|---|---|---|
| `computers/<name>/README.md` | Player | The full manual for that program (format below) |
| Program header comment | Player + agent | What it does and its usage lines |
| `README.md` (root) | Visitor | Overview, website link, one line per computer, how to install |
| `lib/README.md` | Programmer | One line per module and the programs that use it |
| `site/programs.json` | Website + installer | Card text, stats, setup steps, commands, renders |
| `.claude/skills/*/SKILL.md` | Agent | APIs, patterns and checklists for writing code here |
| `AGENTS.md` | Agent | Layout, documentation rules, conventions |

### Program README format

The website shows each README as the program's "full manual", so its shape
matters:

```markdown
# <name>                         -- folder name; the website drops this heading

- **Type:** mining turtle, plus a wireless or ender modem for ...
- **Computer ID:**               -- left blank in the repo: the website hides
- **Label:**                     -- empty ID / Label / Location lines,
- **Location:**                  -- the player fills them in for their world
- **Peripherals:** (computers only)

## What it does                 -- plain English, default sizes/layout, what
                                 -- happens when the chest fills or fuel runs out
## Files                        -- each file, one line: what it is
## Use  (or "Setup")            -- numbered steps, then a code block of
                                 -- commands with `--` comments
## Staying on track             -- optional: GPS, resume, moved turtles
## Things to know               -- optional: gotchas, limits, tips
```

- Write for the player: what it does, what to place where, what to type.
  No code internals; those belong in comments and skills.
- Use `##` for sections and `###` below them. Headings become link anchors
  (`#staying-on-track`), so renaming one breaks links to it.
- Link with relative paths only: `../<other>/README.md` (becomes that
  program's page), `../../lib/<module>.lua` (becomes the library page),
  `preview/<file>.svg` (opens the image). No absolute GitHub URLs.
- Renders go in `preview/` as SVG and get linked from "What it does".

### `site/programs.json`

One entry per program under `programs`, in the order they appear on the site:

| Field | Meaning |
|---|---|
| `name` | Folder name under `computers/` |
| `title`, `tagline` | Card title and one-sentence summary |
| `command` | The program file (`<command>.lua`) and what the player types |
| `device`, `deviceLabel` | `"turtle"` or `"computer"`, and the label shown on the card |
| `color` | CC colour name for its accent (`orange`, `lime`, `lightBlue`, ...) |
| `libs` | Modules from `lib/` the installer adds |
| `keep` | Files the installer never overwrites (player settings) |
| `autostart` | `true` if `startup.lua` runs it, so the installer says "reboot" |
| `stats` | Four `[label, value]` pairs for the stat boxes |
| `features`, `setup` | Short bullet points and numbered setup steps |
| `commands` | `[command, what it does]` pairs |
| `integrates` | `[program or lib name, how they work together]` pairs |
| `render` | `voxel` (a scene in `voxel.js`), `screen` (a scene in `cc.js`) or `gallery` (SVGs from `preview/`) |
| `terminal` | A scripted session for the typing demo, or `null`. Use the program's real `print` text |

`libraries` has one entry per `lib/` module (`usage` snippet, `api` table,
`notes`). The installer takes every `.lua` in the program folder plus its
`libs`. Keep `programs.json` text consistent with the README; the README is
the source of truth.

### Adding or changing a program

1. New program: copy `computers/_template/` to `computers/<name>/` and write
   the program, `startup.lua` and the README in the format above.
2. Add or update its line in the root `README.md` under "Computers" and the
   table below.
3. If it uses a lib, add it to that lib's "Used by" line in `lib/README.md`.
4. Add or update its entry in `site/programs.json`. If its sizes or printed
   text changed, update its scene in `voxel.js` or `cc.js` too.
5. Run `node site/build.mjs`, then `node site/serve.mjs`, and check its page.
   Pushing to `main` publishes it to
   https://rakeki.github.io/Rakeki-s-ComputerCraft/.

## Website

`site/build.mjs` builds `_site/`: pages from `site/src/`, data from
`site/programs.json`, a copy of `computers/` (minus `_template`) and `lib/`
for wget, `manifest.json` + `install.lua` for the installer, and a ZIP per
program. The site address comes from `GITHUB_REPOSITORY` on Actions, or
`SITE_URL`, and defaults to http://localhost:8080. In-game,
`wget run <site>/install.lua <program>` installs a program with its libs, and
`install update` reinstalls everything installed on that computer.

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
| `blueprint-projector` | Projects building plans with CC: Spatial Projector, monitor controls | report (if present) |
| `tree-farm-turtle` | Standalone turtle: plants, chops and replants a grid of trees | nav, report |
| `crop-farm-turtle` | Standalone turtle: harvests and replants a crop field | nav, report |
| `storage-computer` | Wired chest network (or AE2 / RS via an Advanced Peripherals bridge) as one searchable store; serves item requests from turtles over rednet and plans crafting | report (if present) |
| `crafter-turtle` | Crafty turtle that crafts for the storage system (recipes and planning live in storage-computer) | report (if present) |
| `smelter-computer` | Fills, fuels and empties the furnaces on the storage network; charcoal orders feed the fuel chest | report (if present) |
| `colony-dashboard` | MineColonies monitor dashboard via Advanced Peripherals Colony Integrator | report (if present) |

`excavate-turtle/excavate.lua` is the reference for a **standalone,
resumable turtle job** (job file, local coordinates, chest behind the
start, refuel from chest, resume after reboot). Copy its patterns rather than
inventing new ones.

## How the programs talk

All over rednet on a wireless or ender modem, except chest-to-chest moves,
which go over the storage system's wired network, and the smelter, which
sends rednet over that network's cable (the storage computer opens every
modem it has). Requests carry an `id` that the reply repeats, so a late
reply is never taken for a newer one.

| Protocol | From → to | Messages |
|---|---|---|
| `cc_status` | everything → status-server | `lib/report.lua` broadcasts state, detail, position, fuel |
| `automine` | mine-turtle ↔ mine-server | jobs, progress, docking; the turtle retries until answered |
| `village_plan` | village-turtle → blueprint-projector | `plan` (every block, world coords if GPS), `progress` (stage, layer); the projector sends `request` on start |
| `storage` | village-turtle, crafter-turtle, smelter-computer → storage-computer | `count` (+ `need`), `prepare` (start crafting), `deliver` (top up the delivery chest), `learn` (a recipe), `stock` (every count, the input and fuel chests), `send` (load a furnace's input or fuel slot; furnaces only) |
| `storage_crafter` | storage-computer → crafter-turtle | `craft` (ingredients are in the crafter chest, slot k = grid cell k), `ping`; replies `crafted`, `pong` |

Rules that keep it from stalling:

- The storage computer files incoming requests in an inbox (`netReceive`)
  and a separate loop (`netLoop`) answers them, so a request that arrives
  while another is being handled is never lost.
- Anything that waits for a reply has a deadline and says on screen what
  it's waiting for; nothing waits forever without saying why.
- Crafting is planned all at once (`crafting.lua`), queued, and run one
  batch at a time; `pendingCraft` stops the same order being queued twice.
  When the whole amount can't be made, it makes as many as it can.
- Long computations yield now and then (`crafting.lua`'s `breathe`) so CC
  never stops the program for running too long without yielding.
- Only the storage computer takes items out of storage (it caches chest
  contents); the smelter asks it to fill furnaces and only empties them
  into the input chest itself.
- **Programs never talk to a store directly.** The storage computer is the
  gateway: its `chests.lua` and `bridge.lua` backends (same functions:
  `scan`, `items`, `space`, `putAway`, `fetch`; chests add `tidy` and
  `roomInfo` for stack-upgraded storage, the bridge adds `canCraft`,
  `craft`, `isCrafting`) hide whether items live in chests or an AE2 / RS
  system. New programs that need items use the `storage` protocol and the
  input chest, so they work with either. The fuel chest sits above the
  backend in `storage.lua`. The bridge handles both Advanced Peripherals
  APIs (0.7 `listItems` / `exportItemToPeripheral`, 0.8 / 1.21 `getItems`
  / `exportItem`) and can't target a slot, so slot moves go through the
  transfer chest.
- Optional chests (delivery, crafter, fuel) that go missing turn their feature
  off with a message instead of stopping the storage system.

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
- **READMEs** follow the format in [Documentation](#documentation) and are
  kept in sync with behaviour, along with `site/programs.json`.

## CC: Tweaked notes

- Lua 5.2-ish (Cobalt). `sleep`, `os.pullEvent`, `parallel`, `textutils`, `fs`,
  `peripheral`, `rednet`, `gps` are globals.
- `turtle.getFuelLevel()` may return `"unlimited"`; treat it as `math.huge`.
- Turtles freeze when their chunk unloads and the program restarts from
  `startup.lua` when it reloads, hence resumable jobs.
- In-game files: `saves/<world>/computercraft/computer/<id>/`. `lib/` is copied
  to `/lib/` on the computer.
