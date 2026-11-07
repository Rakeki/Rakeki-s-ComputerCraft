# AGENTS.md

Lua programs for ComputerCraft (CC: Tweaked) computers and turtles. There is no
build or lint tooling, and the only test is `sim/` (a simulated CC world, see
below): it shows programs working together, but it's a model, so read code
carefully before calling it done and say whether it has been run in the
simulator and that it hasn't been run in-game.

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
                            published on the site for wget, e.g. craft-overseer's modpack recipes
lib/                        Shared modules, copied to /lib/ in-game, loaded with require("lib.<module>")
  README.md                 One line per module: what it does and which programs use it
  nav.lua                   Turtle position tracking + safe movement (saved across reboots, GPS checks; nav.waitForGps;
                            never more than the nav.range setting, 256 unless set, from where it started)
  report.lua                Sends status (and installed versions) to the status server; answers the update watcher; no-op without a modem
  errlog.lua                Saves errors to /errors.log in one format for every program
  screen.lua                Flicker-free drawing on monitors and terminals (hidden frame, shown in one go); finds and scales monitors
  claim.lua                 Tells the storage computer which of its chests is next to this turtle (delivery / crafter chest)
  mekfeed.lua               Mekanism machines fed through a hopper or barrel (CC can't reach their slots): reads them, sets their sides, registers barrel feeders, a second feeder for an extra slot (infusers); also Create lines (crushing wheels, washing / blasting / smoking fans: a feeder and an output chest); the factory
  workchest.lua             A computer's work chest: the storage computer fills it in one request a round, the program loads its machines from it (the factory), on the cable or far away through ender chests
  net.lua                   Rednet: opening modems, requests with ids and deadlines, answers, cached lookups
  crafts.lua                Crafting questions for the craft overseer (the recipe server), added to storage replies: deliver, count, prepare
  files.lua                 Crash-safe save files (temp file, then move); nav.writeFile etc. are these
  inv.lua                   Turtle inventory and fuel: count, select, empty slots, refuel
  plan.lua                  Building plans: loads /plans/<name>.json or .lua, places them in the world (turn, corner, world blocks); projector, build-control, instabuild, cannon-feeder (a plan's blocks)
  crew.lua                  Hands a building to the builder turtles in strips and follows them (projector and build-control)
  setupui.lua               Setup screens on the monitor and terminal at once: settings pages, paged chest lists with contents, chests picked by dropping an item in (storage, factory)
plans/                      Building plans (JSON, or Lua for plans made by code), listed under "plans" in programs.json;
                            'install plan <name>' puts one in /plans (no program comes with any: install it, then the plans);
                            underground ones (bunker, cellar, hideout, workshop, burrow, cloister, greathall, crossroads,
                            sanctum, atrium, grandstair, fortress, cavern, deephold) also carry "hole" (the size 'excavate <plan>' digs)
                            and "home" (the builder's clear spot); programs.json's entry has "hole" too
tools/                      PC-side helpers (Node, no dependencies), published on the site
  recipes.mjs               Pulls a modpack's crafting recipes out of its jars into a pack_recipes.lua
  overseer/                 The overseer: server.mjs (takes posts from computers/overseer-bridge, streams them to the page
                            as server-sent events; config and saved state in data/, git-ignored) and public/ (the live
                            map page: app.js, demo.js = the made-up base it plays with no server, style.css)
sim/                        A headless CC world on the PC (Node + Fengari: `npm install` there): every program installed
                            with the real installer and run together on simulated time; sim/README.md has the details
  core/                     The VM bridge, CC's natives (prelude.lua), the world (blocks, turtles, modems, cables,
                            inventories, http), machines, mod stand-ins, the player's typing and taps (script.mjs)
  scenarios/                Parts of a base set up the way each README says, with checks; base.mjs is all of it
  run.mjs, test/all.mjs     Run one scenario (screens at the end) / every scenario's checks (`npm test`)
  map.mjs                   Runs the whole base and writes site/network.json for the website's network map
site/                       The website and in-game installer
  network.json              The network map's data, made by `node sim/map.mjs` (commit it after a run)
  programs.json             Website + installer data for every program and lib (schema below)
  build.mjs                 Builds _site/ (Node, no dependencies)
  serve.mjs                 Local preview of _site/ on http://localhost:8080
  install.lua               The in-game installer; {{SITE_URL}} is filled in by the build
  src/index.html            Home page template
  src/page.html             Template for every program and library page
  src/404.html              Not-found page
  src/assets/app.js         Builds the pages from programs.json
  src/assets/cc.js          CC terminal mock-ups (typing demo, AutoMine map, dashboard, projector panel, storage terminal, monitor (network and items views) and setup screen, the factory's tabs (smelter, enricher, infuser, pots, essence) and board, cooker candy, colony, Mekanism fission, power, fusion, digital miners, build control, turtle finder, instabuild, remote terminal, craft terminal, cannon feeder)
  src/assets/voxel.js       Isometric block renders of each program's build
  src/assets/plans.js       Plan viewer: loads a JSON plan (or a Lua one, run with fengari-web) like lib/plan.lua and draws it;
                            plans/ lists every plan (a 3D picture each, PlanView.thumb; above ground / underground, search, sort),
                            each plan gets a page at plans/<name>/, and viewer/ shows a dropped or pasted plan
  src/assets/netmap.js      The network map page (network/): network.json drawn with voxel.js, computers marked, what they
                            sent each other drawn on top by protocol, each computer's last screen
  src/assets/style.css      Site styles (CC palette, Minecraft GUI panels)
  diagrams/                 Setup diagrams: build.mjs has a scene per program (where each block goes, from its
                            README's Setup / Use) and writes computers/<name>/preview/setup.svg; render.mjs draws
                            them with voxel.js's blocks plus numbered markers and a legend. Rerun after a setup change
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
| `mods` | Mods it needs besides CC: Tweaked (`[]` for none). Any at all puts it in the home page's Modded part (`sections`); none, in Vanilla & ComputerCraft |
| `parts` | Optional: the home page parts it's shown in, overriding `mods` (the factory: `["vanilla", "modded"]`, as it runs plain furnaces and modded machines alike) |
| `worksWith` | Optional: mods it uses if they're there but doesn't need (shown on its page, doesn't move it) |
| `title`, `tagline` | Card title and one-sentence summary |
| `command` | The program file (`<command>.lua`) and what the player types |
| `device`, `deviceLabel` | `"turtle"` or `"computer"`, and the label shown on the card |
| `color` | CC colour name for its accent (`orange`, `lime`, `lightBlue`, ...) |
| `libs` | Modules from `lib/` the installer adds |
| `keep` | Files the installer never overwrites (player settings) |
| `autostart` | `true` if `startup.lua` runs it, so the installer says "reboot" |
| `replaces` | Optional: old program names this one took the place of. The build puts each in the manifest as an alias of it (`alias`), so a computer that has one installs this on its next update, and the installer records it under the new name |
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
   text changed, update its scene in `voxel.js` or `cc.js` too. If what goes
   where changed (or it's new), update its scene in `site/diagrams/build.mjs`
   and run `node site/diagrams/build.mjs <name>`; the README shows
   `preview/setup.svg` at the top of its Setup / Use section.
5. Run `node site/build.mjs`, then `node site/serve.mjs`, and check its page.
6. Add it to a scenario in `sim/scenarios/` (set up as its README says, with a
   check), run it (`node sim/run.mjs <scenario>`), and rerun `node sim/map.mjs`
   so the network map has it.
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
not in the program list): `install plan <name> ...` installs them into `/plans`
(the plans page writes that command for the ones picked; picks stay in localStorage),
and each updates on boot like a program.
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
| `turtle-finder` | Pocket computer: lists every turtle heard on `cc_status`, nearest first, and points a big arrow at the one picked (relative to the way you last walked, or a compass), with distance, height and what it is doing; remembers last known positions | screen, net, files, errlog (if present) |
| `overseer-bridge` | Listens on the rednet repeat channel (65533: rednet sends every message there too) on every modem, so it hears all traffic in range unchanged; posts a summary of each message (type, re, a few short fields, size; `cc_status` reports in full) with `http.post` about once a second to `tools/overseer/server.mjs` on the player's PC (`overseer.url`, `overseer.key` settings), which streams it to a browser map. Queues up to 2000 while the server is down | screen, report, errlog (if present) |
| `update-watcher` | Checks the website's `manifest.json` every `updates.every` minutes (address read from `/install.lua`); hears each computer's installed `versions` in its `cc_status` report; asks out-of-date ones in range (heard within 40 s) to `update` on `cc_update`, one every 5 s, again after 3 min, at most 5 times per new version; then updates itself with `report.updateNow`. `updates auto off`: only shows, U pushes. Terminal and optional monitor list | screen, net, report, errlog (if present) |
| `gps-deployer` | Turtle that builds a 4-computer GPS constellation; `gps-deploy satellite` spreads the hosts wider and builds a satellite round each (hull, antenna dish, solar wings, lights) | nav, inv, files, report, errlog (if present) |
| `excavate-turtle` | Standalone turtle: digs a hole of any size and seals its walls, floor and ceiling (no water or lava inside); builds nothing in it, builder turtles do. `excavate <plan>` digs the `hole` a plan names (the fourteen underground plans, bunker to deephold) and prints its `home` for the builder. With a storage computer its chest is claimed as its delivery chest (`lib/claim.lua`): loot goes home with the sweep, fuel and cobblestone come by `deliver` | nav, report, errlog, inv, files, net, claim |
| `level-turtle` | Standalone turtle: flattens an area into a solid building platform (clears everything above the ground it starts on in 3-high layers, up to open sky or a given height, then fills holes below with the dirt it dug, up to 8 deep) | nav, report, errlog, inv, files |
| `strip-mine-turtle` | Standalone turtle: 3x3 main tunnel with 3x3 branches; `at <y>` digs a 1x1 shaft down under the start first and hauls everything back up it | nav, report, errlog, inv, files |
| `nether-tunnel-turtle` | Standalone turtle: sealed 3x3 Nether tunnel; patches holes, walls off lava, burns lava from a bucket | nav, report, errlog, inv, files |
| `village-turtle` | Turtle that builds themed villages | nav, report, errlog, claim, inv, net, files |
| `mob-farm-turtle` | Standalone turtle: drop-tower mob farm with water channels | nav, report, errlog, inv, files |
| `blueprint-projector` | Projects building plans from /plans with CC: Spatial Projector, monitor controls; Build sends the plan to the builder turtles (lib/crew.lua) | screen, net, files, plan, crew, report, errlog (if present) |
| `build-control` | Sends a plan from /plans to the builder turtles at typed coordinates (north-west bottom corner, facing), no projector; follows them | plan, crew, net, files, report, errlog (if present) |
| `instabuild` | Command computer (creative): places a plan from /plans with setblock/fill runs at typed coordinates, or (`serve`) the projector's plan where it's shown when Build is tapped; only places into air, never replaces a block; undo | plan, files, net, errlog (if present) |
| `builder-turtle` | Builds the projector's plan where it's projected: clears the box, builds bottom-up from above, restocks from home chests or the storage system | nav, report, errlog, claim, inv, net, files |
| `tree-farm-turtle` | Standalone turtle: plants, chops and replants a grid of trees | nav, report, errlog, inv, files |
| `crop-farm-turtle` | Standalone turtle: harvests and replants a crop field | nav, report, errlog, inv, files |
| `cobble-breeder` | Command computer (creative / op): reads each Cobbreeding egg's IVs in the egg chest (`commands.getBlockInfo`: the `cobbreeding:pokemon_properties` component, so egg encryption must be off), sends an egg that beats the weakest non-Ditto breeder (of its gender without a Ditto) to the incubator's hopper with `item replace`, the rest to a reject chest; breeders are the pasture's tethers (`TetherPokemon` UUIDs), learned once by Scan (`data get entity` of Pokemon sent out nearby: pastured ones carry no data) or typed, and a kept egg is taken to be the unknown Pokemon that arrives after its breeder leaves; monitor IV cards and progress to 6x31 | screen, files, report, errlog (if present) |
| `storage-computer` | Wired chest network (or AE2 / RS via an Advanced Peripherals bridge) as one searchable store; serves item requests from turtles over rednet; knows no recipes (the craft overseer plans crafting); monitor network view (every ender / turtle / computer chest it serves, what's sent to each lately, how full, the request queue: `links`); `storage dump` empties it into an ender chest whose twin is another storage system's input chest; setup screen on the monitor (lib/setupui.lua) | screen, files, net, setupui, report, errlog (if present) |
| `craft-terminal` | Orders crafts from the craft overseer: lists everything it can craft (`craftable`: how many it could make, how many are stored, what's being made; worked out by the overseer while a terminal keeps asking) and orders an amount (`craft`), sent to a chest next to it (claimed with the storage computer as its delivery chest through `lib/claim.lua`; the overseer has the storage computer `deliver` `for` it) or kept in storage | screen, net, files, claim, crafts, report, errlog (if present) |
| `remote-terminal` | Far-away storage terminal: searches the storage computer's items (`list`) and pulls them into a linked ender chest (its twin claimed as this computer's delivery chest through `lib/claim.lua`); items dropped in go home with the delivery sweep | screen, net, files, claim, report, errlog (if present) |
| `cannon-feeder` | Keeps the chest touching a Create Schematicannon topped up (`deliver`, its own chest claimed through `lib/claim.lua`, or an ender chest twin) with a typed material list or a plan's blocks, until all of each is sent, and with an Advanced Peripherals Block Reader on the cannon (`getBlockData`: `MissingItem`, `State`, `Status`, `AmountPlaced` / `AmountToPlace`) the item it's waiting for, kept topped up until it says `finished`; gunpowder too; crafting comes with `deliver` | screen, net, files, claim, plan, report, errlog (if present) |
| `crafter-turtle` | Crafty turtle that crafts for the storage system (recipes and planning live in craft-overseer; `crafter learn` sends it there) | claim, net, crafts, report, errlog (if present) |
| `craft-overseer` | The recipe server: `crafting.lua`, `recipes.lua`, `pack_recipes.lua`, learnt recipes and the factory machines' (`makes`); plans every craft from the storage computer's `stock` (`orderCraft`), keeps the queue, answers `canmake` / `prepare` / `craftable` / `craft` / `recipes` / `learn` (an inbox like the storage computer's), runs machine jobs on the factory, has the storage computer load each turtle's chest and shares the jobs between every crafting turtle; monitor shows the queue and what's missing. Far away (`overseer hub`): one ender chest on its own cable (twin claimed on the storage cable, role `hub`) and the turtles' barrels on that cable; it moves each batch between them and finds each turtle's barrel (`claim` on `craft_overseer`) | screen, net, files, claim, report, errlog (if present) |
| `factory` | Every machine that turns stored items into others, on as many computers as you like: furnaces, blast furnaces, smokers and Mekanism Energized Smelters and Create blasting / smoking fans (`smelt.lua`: ores, dust, food; charcoal, stone and glass orders), Mekanism Enrichment Chambers and Create crushing wheels and washing fans (`enrich.lua`; washed nuggets crafted with `prepare`), Mekanism Metallurgic Infusers on request (`infuse.lua`: its tab or the monitor's Infuse page, `factory infuse`, or the storage computer, which gets its recipes with `makes` and hands it the infusing steps of its crafting plans; two feeders each), Cobblemon cooking pots (`cook.lua`: comparator through a redstone relay, so a pot never overfills; sculk and honeycomb ordered with `prepare` up to `craft`; Candy monitor page) and Hopper Botany Pots (`botany.lua`: essence into storage, a recipe finder that orders with `prepare`; far away an essence farm, `farm.lua`: every barrel and chest on its cable is its store, the essence stays there, it offers what it can make with `makes` via `essence` (empty recipes, `max` goes) and its own crafting turtles (claimed on `factory_crafter`) make the jobs, which go home through its ender chest). Furnaces and botany pots are found and claimed (`/.factory_claims`: the earliest claim wins between factory computers); Mekanism machines and Create lines go through `lib/mekfeed.lua`, one work chest for all (`lib/workchest.lua`), or far away through ender chests. Parts are ranked in a chain (infuser 0: what its requests wait on; enricher 1, smelter 2): a part leaves items a lower rank takes, here or on another factory computer (`factory` protocol). Replaces the smelter, enricher, cooker and essence computers (`replaces` in programs.json; their names install it, and stubs keep their commands) | screen, net, files, workchest, claim, mekfeed, setupui, report, errlog (if present) |
| `colony-dashboard` | MineColonies monitor dashboard via Advanced Peripherals Colony Integrator | screen, report, errlog (if present) |
| `fission-guard` | Mekanism fission reactor guard: SCRAMs on heat, damage, coolant, heated coolant or waste and latches until Reset; pauses while the Induction Matrix is full; monitor gauges and buttons | screen, files, report, errlog (if present) |
| `power-dashboard` | Mekanism Induction Matrix monitor: stored, in/out, full/empty forecast, graph, turbines and energy cubes, low-power redstone signal | screen, report, errlog (if present) |
| `fusion-control` | Mekanism fusion reactor panel: temperatures, fuel, water/steam, injection-rate buttons, warnings | screen, report, errlog (if present) |
| `digital-miner-manager` | Every Mekanism Digital Miner on the wired network from one monitor (start/stop/reset, radius, Y, silk, filters); auto eject into the storage input chest | screen, report, errlog (if present) |
| `furnace-turtle` | Places a row of furnaces ahead of itself (a crafty turtle crafts them from cobblestone) and runs them from the chest behind it: loads from a lane above, fuels and empties from a lane below (vanilla's furnace faces), results and anything it can't smelt into the chest on its left; takes only the fuel it needs, so it can share another turtle's chest. Crafty: no modem, so counted moves (`furnace here`) | nav, inv, files, report, errlog (if present) |
| `crate-turtle` | Pulls endless items from a Create Creative Crate into a chest: keeps it full, sends n, keeps n in the chest, or keeps n in the storage system (`count`, chest = its input chest); resumable job, no fuel | files, net, report, errlog (if present) |

`excavate-turtle/excavate.lua` is the reference for a **standalone,
resumable turtle job** (job file, local coordinates, chest behind the
start, refuel from chest, resume after reboot). Copy its patterns rather than
inventing new ones.

## How the programs talk

All over rednet on a wireless or ender modem, except chest-to-chest moves,
which go over the storage system's wired network. The storage computer,
factory, crafter and craft overseer open every modem they have, so they
can also talk to each other over that network's cable. Requests carry an `id` that
the reply repeats (and `re` = the request type), so a late reply is never
taken for a newer one: `lib/net.lua` (`net.ask`, `net.answer`, `net.peer`)
does this for every program. The `storage-system` skill has every message and
reply field.

| Protocol | From → to | Messages |
|---|---|---|
| `cc_status` | everything → status-server, storage-computer, turtle-finder, update-watcher | `lib/report.lua` broadcasts state, detail, position, fuel, `versions` (`/.installed_versions`); the storage computer shows the services working with it (anyone that sent a `storage` request, or a service role) on its monitor |
| `cc_update` | update-watcher → anything running `lib/report.lua` (`report.loop`, or `report.handle` in its own event loop: mine-server) | `update` → `ok` or `why` (`install.remote` / `install.autoupdate` off, no http, no installer); then it runs `install boot` with the screen hidden and reboots if anything changed, else logs why and carries on |
| `automine` | mine-turtle ↔ mine-server | jobs, progress; `hello` and `status` carry the miner's `home` (where it was placed, its own chest behind it: it unloads, refuels and idles there; the server never mines a home chunk); the turtle retries until answered |
| `village_plan` | village-turtle → blueprint-projector | `plan` (every block, world coords if GPS), `progress` (stage, layer); the projector sends `request` on start |
| `projector_build` | blueprint-projector or build-control (both through `lib/crew.lua`) ↔ builder-turtle | `build` (key, name, `mats`, `blocks` = { x, y, z, m } in world coords; with several turtles also `area` = the whole building's box, `part` = this turtle's strip x0/x1/z0/z1, `lane` = extra cruise height; `clear = false` for a plan built in the air: don't dig out the box) → `accepted` / `busy` / `refused`; `stop`, `status` (an idle turtle answers `idle`); the turtle sends `progress` (stage clear/build/restocking/waiting/done/stopped, done, total, y, skipped, `need` = items it's waiting for or fetching while restocking/waiting; the projector's Now tab). One key per strip |
| `village_crew` | village-turtle (helper) ↔ village-turtle (lead) | `join` → theme, origin, radius, seed, map, `lane`; `plot` → `i`, `j` (or `none`, `more`); `done` (plot, built entry, paved segments, topY); `alive` every 5 min. GPS on both |
| `storage` | village-turtle, builder-turtle, excavate-turtle, crafter-turtle, factory, crate-turtle, remote-terminal, craft-terminal, cannon-feeder, craft-overseer → storage-computer | Items only, no crafting: `list` (every plain item with its display name: remote-terminal), `count` (stored counts), `deliver` (top up the turtle's own chest, else the shared delivery chest; from the overseer `for` = a computer id: into that computer's own chest only), `claim` (this chest next to me is mine: `lib/claim.lua`; role `hub`: a far-away overseer's ender chest twin, its crafter chest), from the overseer `crafters` / `load` / `clear` / `syscraft` (the ME/RS system crafts it from its pattern), `stock` (every count, the input and fuel chests, `work` = the asker's work chest, `workRemote` = it's an ender chest, so a far-away asker takes it as its twin without a probe; `patterns` = what an ME/RS system can craft, `syscrafting` = what it's making), `send` (load a furnace's input or fuel slot, or a hopper: furnaces, hoppers and the asker's feeders only), `feeders` (these barrels feed my machines: not storage; the factory's enricher and smelter, sent together by `mekfeed.register`), `work` (this empty chest is my work chest, or with `items` / `seen` find it through an ender chest like `claim`; none: stop, put its contents away: `lib/workchest.lua`), `fill` (top my work chest up to these items and fuel for n smelts, in one go) |
| `instabuild` | blueprint-projector → instabuild (`instabuild serve`) | `build` (name, `mats`, `blocks` = { x, y, z, m } in world coords, `area`) → `ok` / `why`; then `done` (`text`, `placed`) once it's in. Build goes here when an instabuild computer hosts the protocol (`set projector.instabuild false` skips it) |
| `craft_overseer` | village-turtle, builder-turtle, cannon-feeder, remote-terminal, craft-terminal, crafter-turtle, factory (all through `lib/crafts.lua`) → craft-overseer | `canmake` (items, `need` → `counts` = how many more could be made, being made included), `prepare` (start crafting up to n in all → `crafting`, `cantCraft`, `craftProblem`), `craftable` (the craft terminal's list: everything that can be crafted, stored or not, with how many, `making`, `ready`), `craft` (make n more; `to` = "chest": sent to the asker's own chest as they're made, else into storage), `recipes` (every recipe using an item matching a pattern), `learn` (a recipe), `makes` (a machine's recipes, `via` = "infuse": the factory's infuser, or "essence": an essence farm, recipes with nothing in them and `max` goes; plans use them and their jobs go to it), `jobdone` (from that machine), `ping`; the overseer asks the storage computer (`storage` protocol) for `stock`, `crafters`, `load`, `clear`, `syscraft`, `deliver` `for`; crafter-turtle → craft-overseer `claim` (as on `storage`: which barrel on the overseer's cable is mine, with a hub), tried before the storage computer's |
| `factory` | factory ↔ factory; craft-overseer → factory | `hello` → `stages` (each running part: id, title, rank, `takes` = Lua patterns of the item ids its machines take, summary), `owns` (peripheral name → when it was claimed, 0 for machines added by hand: the earliest wins); `give` (let go of these names) and `take` (these are yours now) → `ok`; from the craft overseer `infuse` / `essence` (job, make, count, grid: a crafting plan's infusing step) → `ok` / `why`, and `cancel` (job). A part leaves items a lower-rank part takes (the enricher, rank 1, before the smelter, rank 2); a factory computer unheard for 10 min is forgotten. Hosted, so `storage config remote` finds factory computers (old `smelter` / `enricher` hosts too) by `rednet.lookup` to pick their ender chest |
| `factory_crafter` | crafter-turtle → factory (an essence farm, far away) | `claim` (as on `storage`: which barrel on the farm's cable is mine), tried first; the farm then sends its jobs on `storage_crafter` |
| `storage_crafter` | craft-overseer or an essence farm → crafter-turtle | `craft` (ingredients are in the crafter chest; `grid` = cell → item, and the turtle sorts by name, since barrels ignore slots), `ping`; replies `crafted` (`made`, `item` it made, `error`), `pong` |

Rules that keep it from stalling:

- The storage computer files incoming requests in an inbox (`netReceive`)
  and a separate loop (`netLoop`) answers them, so a request that arrives
  while another is being handled is never lost.
- Anything that waits for a reply has a deadline and says on screen what
  it's waiting for; nothing waits forever without saying why.
- **The storage computer knows no recipes.** Every crafting request goes to
  the craft overseer (`lib/crafts.lua` adds its answers to a storage reply),
  so planning never holds up item requests: with a modpack, counts and plans
  in the storage computer's request loop made every turtle wait.
- Crafting is planned all at once (`crafting.lua` on the overseer), queued,
  and run one batch at a time; a machine's recipes (`crafting.setMachine`,
  the infuser's) plan like any other, but their jobs go to that factory
  computer, and no later step of the plan starts until it reports `jobdone`;
  what's being made (`pending`: the queue's `top` jobs, plus the ME/RS
  system's `syscrafting`) stops the same order being queued twice. The
  overseer runs a job per crafting turtle, steps of one plan in order.
  When the whole amount can't be made, it makes as many as it can.
- Long computations yield now and then (`crafting.lua`'s and `chests.lua`'s
  `breathe`) so CC never stops the program for running too long without
  yielding.
- With a modpack's recipes (`pack_recipes.lua`, thousands of them), plans
  only try items that can be made at all from what's stored
  (`crafting.reachable`, worked out once per request and passed in as
  `reach`). Anything that would plan every recipe, like the craft
  terminal's list, runs only while it's wanted and rests three times as long
  as it took. Plans cost what the recipe tree costs, never how much is
  stored (see the `storage-system` skill).
- The crafter never relies on chest slot order (barrels with stack upgrades
  ignore it): craft jobs carry the grid by item name, and the turtle reports
  what it made so a wrong craft is caught.
- Only the storage computer takes items out of storage (it caches chest
  contents); the factory asks it to fill furnaces, pots' feed hoppers and
  Mekanism / Create feeders, and only empties them (output slots, output
  hoppers and chests, botany pots) into the input chest itself.
- A computer on the cable (the factory) may name a **work chest**
  (`work`, `lib/workchest.lua`; `setup.works[computer id]`, never storage):
  each round each part plans every load, asks for all of it with one `fill`,
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
  Every turtle that moves needs GPS (only the gps-deployer, which builds it, and
  a crafty furnace-turtle, which has no room for a modem and stays by its row, do
  without): `nav.waitForGps()` before the first move, so after a server restart
  it waits for the GPS hosts instead of trusting a saved position.
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
