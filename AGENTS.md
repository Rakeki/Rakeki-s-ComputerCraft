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
    startup.lua             Runs on boot: install boot (update from the site), then resume a job or keep a service running
    <helper>.lua            Optional modules loaded with require("<helper>"), e.g. ui.lua
    config.lua              Optional player settings; list it under "keep" in programs.json
    preview/*.svg           Optional renders, linked from the README and the website
    packs/*.lua             Optional extra files the installer skips (only top-level .lua is installed);
                            published on the site for wget, e.g. storage-computer's modpack recipes
lib/                        Shared modules, copied to /lib/ in-game, loaded with require("lib.<module>")
  README.md                 One line per module: what it does and which programs use it
  nav.lua                   Turtle position tracking + safe movement (saved across reboots, optional GPS)
  report.lua                Sends status to the status server; no-op without a modem
  errlog.lua                Saves errors to /errors.log in one format for every program
  screen.lua                Flicker-free drawing on monitors and terminals (hidden frame, shown in one go); finds and scales monitors
  claim.lua                 Tells the storage computer which of its chests is next to this turtle (delivery / crafter chest)
  mekfeed.lua               Mekanism machines fed through a hopper or barrel (CC can't reach their slots): reads them, sets their output side, registers barrel feeders; enricher, smelter
  workchest.lua             A computer's work chest: the storage computer fills it in one request a round, the program loads its machines from it (smelter, enricher), on the cable or far away through ender chests
  net.lua                   Rednet: opening modems, requests with ids and deadlines, answers, cached lookups
  files.lua                 Crash-safe save files (temp file, then move); nav.writeFile etc. are these
  inv.lua                   Turtle inventory and fuel: count, select, empty slots, refuel
  plan.lua                  Building plans: loads /plans/<name>.json or .lua, places them in the world (turn, corner, world blocks); projector, build-control, instabuild
  crew.lua                  Hands a building to the builder turtles in strips and follows them (projector and build-control)
  setupui.lua               Setup screens on the monitor and terminal at once: settings pages, paged chest lists with contents (storage, enricher, smelter, cooker, essence)
plans/                      Building plans (JSON, or Lua for plans made by code), listed under "plans" in programs.json;
                            'install plan <name>' puts one in /plans, a program's "plans" field installs some with it;
                            underground ones (cellar, hideout, workshop, sanctum, atrium) also carry "hole" (the size
                            'excavate <plan>' digs) and "home" (the builder's clear spot); programs.json's entry has "hole" too
tools/                      PC-side helpers (Node, no dependencies), published on the site
  recipes.mjs               Pulls a modpack's crafting recipes out of its jars into a pack_recipes.lua
site/                       The website and in-game installer
  programs.json             Website + installer data for every program and lib (schema below)
  build.mjs                 Builds _site/ (Node, no dependencies)
  serve.mjs                 Local preview of _site/ on http://localhost:8080
  install.lua               The in-game installer; {{SITE_URL}} is filled in by the build
  src/index.html            Home page template
  src/page.html             Template for every program and library page
  src/404.html              Not-found page
  src/assets/app.js         Builds the pages from programs.json
  src/assets/cc.js          CC terminal mock-ups (typing demo, AutoMine map, dashboard, projector panel, storage terminal, monitor and setup screen, smelter, cooker, colony, Mekanism fission, power, fusion, digital miners, enricher, essence, build control, instabuild, remote terminal)
  src/assets/voxel.js       Isometric block renders of each program's build
  src/assets/plans.js       Plan viewer: loads a JSON plan (or a Lua one, run with fengari-web) like lib/plan.lua and draws it;
                            each plan gets a page at plans/<name>/, and viewer/ shows a dropped or pasted plan
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
| `group` | Which section of the home page it's in: an `id` from `groups` (mining, building, farming, storage, mekanism, network); the build stops if it's missing |
| `title`, `tagline` | Card title and one-sentence summary |
| `command` | The program file (`<command>.lua`) and what the player types |
| `device`, `deviceLabel` | `"turtle"` or `"computer"`, and the label shown on the card |
| `color` | CC colour name for its accent (`orange`, `lime`, `lightBlue`, ...) |
| `libs` | Modules from `lib/` the installer adds |
| `plans` | Plans (names from the `plans` list) installed into `/plans` with it |
| `keep` | Files the installer never overwrites (player settings) |
| `autostart` | `true` if `startup.lua` runs it, so the installer says "reboot" |
| `stats` | Four `[label, value]` pairs for the stat boxes |
| `features`, `setup` | Short bullet points and numbered setup steps |
| `commands` | `[command, what it does]` pairs |
| `integrates` | `[program or lib name, how they work together]` pairs |
| `render` | `voxel` (a scene in `voxel.js`), `screen` (a scene in `cc.js`; `more: [{ scene, caption }]` adds more screens below it, e.g. a monitor) or `gallery` (SVGs from `preview/`) |
| `layouts` | Optional `[{ title, scene, caption }]`: example builds shown as tabs under "Example layouts" (scenes in `voxel.js`); describe each in the README's "Example layouts" too |
| `terminal` | A scripted session for the typing demo, or `null`. Use the program's real `print` text |

`libraries` has one entry per `lib/` module (`usage` snippet, `api` table,
`notes`). `plans` has one entry per file in `plans/` (`name`, `file`,
`title`, `tagline`, `size`, `blocks`): the website lists them and
`install plan <name>` installs them. The installer takes every `.lua` in the program folder plus its
`libs`. Keep `programs.json` text consistent with the README; the README is
the source of truth.

### Adding or changing a program

1. New program: copy `computers/_template/` to `computers/<name>/` and write
   the program, `startup.lua` and the README in the format above (the
   `new-computer` skill has the checklist).
2. Add or update its line in the root `README.md` under "Computers" and the
   table below, and the protocol table if it talks over rednet.
3. If it uses a lib, add it to that lib's "Used by" line in `lib/README.md`.
4. Add or update its entry in `site/programs.json`. If its sizes or printed
   text changed, update its scene in `voxel.js` or `cc.js` too.
5. Run `node site/build.mjs`, then `node site/serve.mjs`, and check its page.
   Pushing to `main` publishes it to
   https://rakeki.github.io/Rakeki-s-ComputerCraft/.

## Website

`site/build.mjs` builds `_site/`: pages from `site/src/`, data from
`site/programs.json`, a copy of `computers/` (minus `_template`), `lib/` and
`tools/` for wget, `manifest.json` + `install.lua` for the installer, and a ZIP per
program. The site address comes from `GITHUB_REPOSITORY` on Actions, or
`SITE_URL`, and defaults to http://localhost:8080. In-game,
`wget run <site>/install.lua <program>` installs a program with its libs, and
`install update` reinstalls everything installed on that computer, and
`install remove <program>` uninstalls one (files from `/.installed_files`, or
the manifest for older installs; files another installed program lists stay,
`keep` files only if the player says so). Every
`startup.lua` begins with `install boot`: it fetches `manifest.json` (5 s
deadline, carries on without it) and reinstalls only programs whose
`version` (a hash of their files, made by the build) differs from the one
saved in `/.installed_versions`. `set install.autoupdate false` turns it off.
`/.installed_files` records the files each program put there, so an update
removes ones the new version dropped (never a file another installed program
still lists).
Plans from `plans/` are in the manifest as `plan:<name>` (not in `order`, so
not in the program list): `install plan <name>` installs one into `/plans`
and it updates on boot like a program.
The installer downloads a version's files from `v/<version>/...` (the build
copies them there), because GitHub Pages serves a cached copy of a file for
up to 10 minutes after it changes (a `?query` doesn't get round it); the
manifest itself can lag that long, so a reboot just after a push may still
say "up to date".

Existing computers:

| Folder | What | Libs |
|---|---|---|
| `mine-server` | AutoMine server: hands out chunks, planning map | report, errlog, screen, net, files |
| `mine-turtle` | AutoMine miner, talks to mine-server over rednet | nav, report, errlog, inv, net, files |
| `status-server` | Monitor dashboard of every computer's status | errlog, screen, net, files |
| `gps-deployer` | Turtle that builds a 4-computer GPS constellation | nav, inv, files, report, errlog (if present) |
| `excavate-turtle` | Standalone turtle: digs a hole of any size and seals its walls, floor and ceiling (no water or lava inside); builds nothing in it, builder turtles do. `excavate <plan>` digs the `hole` a plan names (cellar, hideout, workshop, sanctum, atrium) and prints its `home` for the builder | nav, report, errlog, inv, files |
| `strip-mine-turtle` | Standalone turtle: 3x3 main tunnel with 3x3 branches | nav, report, errlog, inv, files |
| `nether-tunnel-turtle` | Standalone turtle: sealed 3x3 Nether tunnel; patches holes, walls off lava, burns lava from a bucket | nav, report, errlog, inv, files |
| `village-turtle` | Turtle that builds themed villages | nav, report, errlog, claim, inv, net, files |
| `mob-farm-turtle` | Standalone turtle: drop-tower mob farm with water channels | nav, report, errlog, inv, files |
| `blueprint-projector` | Projects building plans from /plans with CC: Spatial Projector, monitor controls; Build sends the plan to the builder turtles (lib/crew.lua) | screen, net, files, plan, crew, report, errlog (if present) |
| `build-control` | Sends a plan from /plans to the builder turtles at typed coordinates (north-west bottom corner, facing), no projector; follows them | plan, crew, net, files, report, errlog (if present) |
| `instabuild` | Command computer (creative): places a plan from /plans with setblock/fill runs at typed coordinates, or (`serve`) the projector's plan where it's shown when Build is tapped; only places into air, never replaces a block; undo | plan, files, net, errlog (if present) |
| `builder-turtle` | Builds the projector's plan where it's projected: clears the box, builds bottom-up from above, restocks from home chests or the storage system | nav, report, errlog, claim, inv, net, files |
| `tree-farm-turtle` | Standalone turtle: plants, chops and replants a grid of trees | nav, report, errlog, inv, files |
| `crop-farm-turtle` | Standalone turtle: harvests and replants a crop field | nav, report, errlog, inv, files |
| `storage-computer` | Wired chest network (or AE2 / RS via an Advanced Peripherals bridge) as one searchable store; serves item requests from turtles over rednet and plans crafting; `storage dump` empties it into an ender chest whose twin is another storage system's input chest; setup screen on the monitor (lib/setupui.lua) | screen, files, net, setupui, report, errlog (if present) |
| `remote-terminal` | Far-away storage terminal: searches the storage computer's items (`list`) and pulls them into a linked ender chest (its twin claimed as this computer's delivery chest through `lib/claim.lua`); items dropped in go home with the delivery sweep | screen, net, files, claim, report, errlog (if present) |
| `crafter-turtle` | Crafty turtle that crafts for the storage system (recipes and planning live in storage-computer) | claim, net, report, errlog (if present) |
| `craft-overseer` | Takes the storage computer's crafting queue and shares it between every crafting turtle; monitor shows the queue and what's missing | screen, net, files, report, errlog (if present) |
| `smelter-computer` | Fills, fuels and empties the furnaces on the storage network, and feeds Mekanism Energized Smelters through a hopper or barrel (`lib/mekfeed.lua`); charcoal orders feed the fuel chest, stone orders smelt cobblestone, glass orders sand; smelts Mekanism dust, and leaves the ores the enricher takes to it; optional work chest (one `fill` a round), or far away through ender chests | screen, net, files, workchest, claim, mekfeed, setupui, report, errlog (if present) |
| `cooker-computer` | Runs Cobblemon cooking pots through a feed and an output hopper each (CC can't reach into a pot): exp candy, compressed up to XL; a comparator read through a redstone relay says how full each pot is, so it's fed only what fits and a hopper never overfills a slot (nothing is counted) | screen, net, files, setupui, report, errlog (if present) |
| `colony-dashboard` | MineColonies monitor dashboard via Advanced Peripherals Colony Integrator | screen, report, errlog (if present) |
| `fission-guard` | Mekanism fission reactor guard: SCRAMs on heat, damage, coolant, heated coolant or waste and latches until Reset; pauses while the Induction Matrix is full; monitor gauges and buttons | screen, files, report, errlog (if present) |
| `power-dashboard` | Mekanism Induction Matrix monitor: stored, in/out, full/empty forecast, graph, turbines and energy cubes, low-power redstone signal | screen, report, errlog (if present) |
| `fusion-control` | Mekanism fusion reactor panel: temperatures, fuel, water/steam, injection-rate buttons, warnings | screen, report, errlog (if present) |
| `digital-miner-manager` | Every Mekanism Digital Miner on the wired network from one monitor (start/stop/reset, radius, Y, silk, filters); auto eject into the storage input chest | screen, report, errlog (if present) |
| `essence-computer` | Empties Hopper Botany Pots (Mystical Agriculture) into the storage input chest; Recipes tab looks up what the stored essence crafts into (recipes from the storage computer, `recipes` request) and orders it with `prepare` | screen, net, setupui, report, errlog (if present) |
| `crate-turtle` | Pulls endless items from a Create Creative Crate into a chest: keeps it full, sends n, keeps n in the chest, or keeps n in the storage system (`count`, chest = its input chest); resumable job, no fuel | files, net, report, errlog (if present) |
| `enricher-computer` | Feeds ores from storage into Mekanism Enrichment Chambers (or Enriching Factories) through a feeder on each: a hopper on top, or a barrel a pipe pulls from (CC can't reach a Mekanism machine's slots); sets the bottom to Output with Auto-eject into its output chest, which it empties into storage (or a storage input chest); dust goes on to the smelter; optional work chest (one `fill` a round), or far away through ender chests | screen, net, files, workchest, claim, mekfeed, setupui, report, errlog (if present) |

`excavate-turtle/excavate.lua` is the reference for a **standalone,
resumable turtle job** (job file, local coordinates, chest behind the
start, refuel from chest, resume after reboot). Copy its patterns rather than
inventing new ones.

## How the programs talk

All over rednet on a wireless or ender modem, except chest-to-chest moves,
which go over the storage system's wired network. The storage computer,
smelter, cooker, enricher, crafter and craft overseer open every modem they have, so they
can also talk to each other over that network's cable. Requests carry an `id` that
the reply repeats (and `re` = the request type), so a late reply is never
taken for a newer one: `lib/net.lua` (`net.ask`, `net.answer`, `net.peer`)
does this for every program. The `storage-system` skill has every message and
reply field.

| Protocol | From → to | Messages |
|---|---|---|
| `cc_status` | everything → status-server, storage-computer | `lib/report.lua` broadcasts state, detail, position, fuel; the storage computer shows the services working with it (anyone that sent a `storage` request, or a service role) on its monitor |
| `automine` | mine-turtle ↔ mine-server | jobs, progress; `hello` and `status` carry the miner's `home` (where it was placed, its own chest behind it: it unloads, refuels and idles there; the server never mines a home chunk); the turtle retries until answered |
| `village_plan` | village-turtle → blueprint-projector | `plan` (every block, world coords if GPS), `progress` (stage, layer); the projector sends `request` on start |
| `projector_build` | blueprint-projector or build-control (both through `lib/crew.lua`) ↔ builder-turtle | `build` (key, name, `mats`, `blocks` = { x, y, z, m } in world coords; with several turtles also `area` = the whole building's box, `part` = this turtle's strip x0/x1/z0/z1, `lane` = extra cruise height; `clear = false` for a plan built in the air: don't dig out the box) → `accepted` / `busy` / `refused`; `stop`, `status` (an idle turtle answers `idle`); the turtle sends `progress` (stage clear/build/restocking/waiting/done/stopped, done, total, y, skipped, `need` = items it's waiting for or fetching while restocking/waiting; the projector's Now tab). One key per strip |
| `village_crew` | village-turtle (helper) ↔ village-turtle (lead) | `join` → theme, origin, radius, seed, map, `lane`; `plot` → `i`, `j` (or `none`, `more`); `done` (plot, built entry, paved segments, topY); `alive` every 5 min. GPS on both |
| `storage` | village-turtle, builder-turtle, crafter-turtle, smelter-computer, cooker-computer, enricher-computer, essence-computer, crate-turtle, remote-terminal → storage-computer | `list` (every plain item with its display name: remote-terminal), `count` (+ `need`), `prepare` (start crafting), `recipes` (every recipe using an item matching a pattern), `deliver` (top up the turtle's own chest, else the shared delivery chest), `claim` (this chest next to me is mine: `lib/claim.lua`), `learn` (a recipe), from the overseer `crafters` / `load` / `clear` / `jobdone` / `problem`, `stock` (every count, the input and fuel chests, `work` = the asker's work chest, `workRemote` = it's an ender chest, so a far-away asker takes it as its twin without a probe), `send` (load a furnace's input or fuel slot, or a hopper: furnaces, hoppers and the asker's feeders only), `feeders` (these barrels feed my machines: not storage; the enricher and smelter), `work` (this empty chest is my work chest, or with `items` / `seen` find it through an ender chest like `claim`; none: stop, put its contents away: `lib/workchest.lua`), `fill` (top my work chest up to these items and fuel for n smelts, in one go) |
| `instabuild` | blueprint-projector → instabuild (`instabuild serve`) | `build` (name, `mats`, `blocks` = { x, y, z, m } in world coords, `area`) → `ok` / `why`; then `done` (`text`, `placed`) once it's in. Build goes here when an instabuild computer hosts the protocol (`set projector.instabuild false` skips it) |
| `craft_overseer` | storage-computer → craft-overseer | `jobs` (each { id, plan, name, steps, count, grid, top }) → ack; the overseer then asks the storage computer (`storage` protocol) for `crafters`, `load`, `clear`, `stock`, and reports `jobdone` and `problem` |
| `smelter` | storage-computer → smelter-computer | hosted only: `storage config remote` finds smelters (and enrichers, which host `enricher`) by `rednet.lookup` to pick their ender chest |
| `enricher` | smelter-computer → enricher-computer | `takes` → `takes` (Lua patterns of the item ids it puts in its chambers; empty while no chamber is set up), so the smelter leaves those ores alone and waits for the dust; it keeps the last answer through missed ones. No enricher (or none heard for 10 min): the smelter smelts them |
| `storage_crafter` | storage-computer or craft-overseer → crafter-turtle | `craft` (ingredients are in the crafter chest; `grid` = cell → item, and the turtle sorts by name, since barrels ignore slots), `ping`; replies `crafted` (`made`, `item` it made, `error`), `pong` |

Rules that keep it from stalling:

- The storage computer files incoming requests in an inbox (`netReceive`)
  and a separate loop (`netLoop`) answers them, so a request that arrives
  while another is being handled is never lost.
- Anything that waits for a reply has a deadline and says on screen what
  it's waiting for; nothing waits forever without saying why.
- Crafting is planned all at once (`crafting.lua`), queued, and run one
  batch at a time; `pendingCraft` stops the same order being queued twice.
  With a craft overseer, the storage computer still plans but hands the queue
  over (`handOver`); the overseer runs a job per crafting turtle, steps of
  one plan in order, and reports each job done (`jobFinished`).
  When the whole amount can't be made, it makes as many as it can.
- Long computations yield now and then (`crafting.lua`'s and `chests.lua`'s
  `breathe`) so CC never stops the program for running too long without
  yielding.
- With a modpack's recipes (`pack_recipes.lua`, thousands of them), plans
  only try items that can be made at all from what's stored
  (`crafting.reachable`, worked out once per request and passed in as
  `reach`). Anything that would plan every recipe, like the Craftable tab,
  is off by default.
- The crafter never relies on chest slot order (barrels with stack upgrades
  ignore it): craft jobs carry the grid by item name, and the turtle reports
  what it made so a wrong craft is caught.
- Only the storage computer takes items out of storage (it caches chest
  contents); the smelter asks it to fill furnaces (the cooker, its pots'
  feed hoppers; the enricher, its chambers' hoppers or barrel feeders) and only empties them (their output hoppers)
  into the input chest itself.
- A computer on the cable (smelter, enricher) may name a **work chest**
  (`work`, `lib/workchest.lua`; `setup.works[computer id]`, never storage):
  each round it plans every load, asks for all of it with one `fill`,
  moves it into its machines with `pushItems`, and sends whatever is left
  back through the input chest, so nothing waits there unseen. A missing or
  refused work chest falls back to per-machine `send`. Only an empty chest
  can become one, so a full storage chest is never taken. Far away the
  work chest is an ender chest whose twin at home is found by probe
  (`work` with `items` / `seen`, `lib/claim.lua` role `work`), and
  there's no `send` fallback. Things go home through the same chest:
  each `fill` carries `sweep` and the storage computer first puts away
  everything in it that wasn't asked for. Or a second ender pair (`back`,
  its twin an extra input chest) takes the place of the input chest.
- **Ender chests** (any peripheral type with `ender` in it) are never
  storage in `chests.lua`: they share their items with a chest elsewhere.
  The remote terminal claims one as its delivery chest, so `deliver` and
  the delivery sweep (unreserved items go back within `SWEEP_EVERY`) do the
  pulling and pushing.
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
- Optional chests (delivery, crafter, fuel, transfer) that go missing turn
  their feature off with a message instead of stopping the storage system.
- Turtles find their own chest (`claim`, `lib/claim.lua`): the turtle sends
  its chest's `list()`, the storage computer drops one item into each chest
  that could be it until the turtle sees it arrive, then records it in
  `setup.deliveries[turtle id]` (or `setup.crafter`). Never ask the player
  to pick a turtle's chest in `storage setup`.

## Skills

Detailed guides live in `.claude/skills/`:

- `new-computer`: adding a computer folder, README format, startup, getting it in-game
- `lib-nav`: the `lib/nav.lua` API, heading convention and gotchas
- `lib-report`: the `lib/report.lua` API and status states
- `lib-errlog`: the `lib/errlog.lua` API and the error log format
- `lib-screen`: the `lib/screen.lua` API for flicker-free monitors and terminals
- `lib-net`: `lib/net.lua` (rednet requests, answers, peers), `lib/files.lua` (crash-safe save files) and `lib/inv.lua` (turtle inventory and fuel)
- `turtle-job`: the standalone resumable turtle job pattern (from excavate-turtle), and jobs in world coordinates (builder-turtle)
- `storage-system`: asking the storage computer for items (messages, replies, crafting on request) and how it works inside

## Conventions

- **Lua style:** 2-space indent, `local` everything, functions and locals in
  `camelCase` (no snake_case), tunables are `UPPER_CASE` constants at
  the top of the file with a comment each. Sections are separated with
  `---------------------------------------------------------------- name`.
- **Strings:** `("Need %d fuel"):format(n)`. User-facing `print` text is plain,
  friendly English ("Chest is full. Waiting...").
- **Comments** explain why, not what. Header comment on each program gives
  what it does and its usage lines.
- **Items:** programs that need items or fuel ask the storage computer
  (`storage` protocol) and put things away through its input chest; they
  never read or empty storage chests (or an ME / RS system) themselves.
- **Movement:** turtles use `lib/nav.lua` (never raw `turtle.forward` for moves
  that change position) so position is saved and protected blocks are never dug.
  Counting, selecting and burning items go through `lib/inv.lua`; GPS checks
  through `nav.locate` and `nav.confirmResume`.
- **Rednet:** requests and answers go through `lib/net.lua` (`net.peer(...):ask`,
  `net.ask` with a deadline, `net.answer`), never a hand-rolled receive loop.
- **Screens:** every monitor and terminal UI draws through `lib/screen.lua`:
  `local win, w, h = s:frame()`, draw, `s:show()`. Never clear a monitor (or
  the terminal) and redraw it in place: it flashes. A screen redrawn on every
  event skips unchanged frames with `s:same(key)`. Monitors come from
  `screen.find` (it picks and scales them, and `s:refresh()` on `peripheral` /
  `peripheral_detach` follows them): never find, wrap or `setTextScale` a
  monitor yourself. Pass `setting = "<command>.monitor"` so the player can
  name the monitor (`set storage.monitor monitor_3`): every computer on a
  cable sees every monitor on it. Add `screen` to the program's `libs` in programs.json.
- **Status:** long-running programs call `report.init(role)`, `report.set(state, detail)`
  as they work, and run `parallel.waitForAny(main, report.loop)`; wrap `main` in
  `errlog.pcall` and report `"error"` on failure.
- **Errors:** every program logs errors through `lib/errlog.lua` (`errlog.init(name,
  context)`, `errlog.pcall` around the main loop and per-event handlers), never
  its own log file, so `/errors.log` reads the same on every computer.
- **Persistence:** save state with `lib/files.lua` (`files.write` / `read` /
  `delete`; temp-file writes, crash safe), which turtles also have as
  `nav.writeFile` etc. Never `fs.open` a state file directly. Job files are `/.<name>_job`.
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
- Mekanism (written for 10.7 on 1.21.1): every method name, argument and
  return is in Mekanism's generated list for that version,
  `src/datagen/generated/mekanism/data/mekanism/computer_help/methods.csv`
  at the release tag (e.g. `v1.21.1-10.7.19.85`). Methods run on the game's
  main thread, a tick per call, so the Mekanism programs start all their
  reads at once with `parallel.waitForAll`. Energy comes in joules (FE =
  J / 2.5 by default) and fill levels as 0-1; setters throw Mekanism's
  reason, which the programs show as is.
- In-game files: `saves/<world>/computercraft/computer/<id>/`. `lib/` is copied
  to `/lib/` on the computer.
