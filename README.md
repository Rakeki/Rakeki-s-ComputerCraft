# Rakeki's ComputerCraft

Lua programs for ComputerCraft (CC: Tweaked) computers and turtles.

**Website: https://rakeki.github.io/Rakeki-s-ComputerCraft/** — every program
with 3D renders, setup guides and one-line installs. In-game, run:

```
wget run https://rakeki.github.io/Rakeki-s-ComputerCraft/install.lua
```

## Layout

```
computers/
  _template/      Copy this to start a new computer
  <name>/         One folder per in-game computer
    README.md     What it does, where it is, its computer ID, peripherals
    startup.lua   Runs automatically when the computer boots
lib/              Shared modules usable by any computer
tools/            PC-side helpers, e.g. recipes.mjs: a modpack's crafting recipes for the storage system
site/             The website and in-game installer (built by GitHub Actions)
```

## Computers

- [mine-server](computers/mine-server/README.md): AutoMine server; assigns chunks to miners and shows a chunk-planning map
- [mine-turtle](computers/mine-turtle/README.md): AutoMine mining turtle (same code on every miner)
- [status-server](computers/status-server/README.md): monitor dashboard showing every computer's status and what it's doing
- [gps-deployer](computers/gps-deployer/README.md): turtle that builds and starts a 4-computer GPS system
- [excavate-turtle](computers/excavate-turtle/README.md): standalone turtle that digs a hall with two floors of rooms, a ledge and stairs, or a garden pit for the atrium plan
- [strip-mine-turtle](computers/strip-mine-turtle/README.md): standalone turtle that digs a 3x3 main tunnel with 3x3 branches off both sides
- [nether-tunnel-turtle](computers/nether-tunnel-turtle/README.md): standalone turtle that digs a sealed 3x3 tunnel through the Nether, patching holes and walling off lava
- [village-turtle](computers/village-turtle/README.md): turtle that builds a themed village and keeps expanding it, picking buildings to suit the terrain
- [mob-farm-turtle](computers/mob-farm-turtle/README.md): standalone turtle that builds a mob farm: a dark spawning room with water channels, a drop shaft and a collection chest
- [blueprint-projector](computers/blueprint-projector/README.md): projects a building plan into the world with CC: Spatial Projector; move and turn it from a monitor, then build it layer by layer, or tap Build and a builder turtle builds it
- [builder-turtle](computers/builder-turtle/README.md): turtle that builds whatever the blueprint projector is showing, right where it's shown
- [build-control](computers/build-control/README.md): sends a plan to the builder turtles at coordinates you type, from any computer or pocket computer, no projector needed
- [instabuild](computers/instabuild/README.md): creative only: places a whole plan in seconds from a command computer, and undoes it again
- [tree-farm-turtle](computers/tree-farm-turtle/README.md): turtle that plants a grid of trees, chops them as they grow, replants and brings the logs to a chest
- [crop-farm-turtle](computers/crop-farm-turtle/README.md): turtle that flies over a field, harvests ripe wheat, carrots, potatoes and beetroot, and replants them
- [storage-computer](computers/storage-computer/README.md): turns a network of chests, or an AE2 / Refined Storage system, into one searchable store with an input and an output chest and a touch monitor to take items from, and serves items to every turtle
- [remote-terminal](computers/remote-terminal/README.md): the storage system from anywhere, through a linked ender chest: search and pull items, or drop them in to send them home
- [crafter-turtle](computers/crafter-turtle/README.md): crafty turtle that makes what the storage system is asked for but doesn't have, from what it does
- [craft-overseer](computers/craft-overseer/README.md): shares the storage system's crafting between any number of crafting turtles, with the queue and what each job is missing on a monitor
- [smelter-computer](computers/smelter-computer/README.md): keeps the storage system's furnaces busy smelting ores (and Mekanism dust) and cooking raw food, fuels them from its fuel chest, and burns spare logs into charcoal, cobblestone into stone or sand into glass on request
- [cooker-computer](computers/cooker-computer/README.md): runs Cobblemon cooking pots for the storage system: makes exp candy from sculk and honeycomb and compresses it up to XL
- [colony-dashboard](computers/colony-dashboard/README.md): monitor dashboard for a MineColonies colony: citizens, happiness, buildings, requests, work orders and attack alarm
- [fission-guard](computers/fission-guard/README.md): watches a Mekanism fission reactor and SCRAMs it before it overheats, takes damage, runs short of coolant or backs up on steam or waste; monitor gauges with start, SCRAM and burn-rate buttons
- [power-dashboard](computers/power-dashboard/README.md): Mekanism Induction Matrix on a monitor: stored power, in and out, time until full or empty, an hour's graph, turbines and energy cubes, and a redstone signal when power runs low
- [fusion-control](computers/fusion-control/README.md): Mekanism fusion reactor panel: plasma and case temperature, fuel, water and steam, power made, injection-rate buttons and warnings
- [digital-miner-manager](computers/digital-miner-manager/README.md): every Mekanism Digital Miner on one monitor: start, stop, reset, radius, Y range, silk touch and filters; mined items go to the storage system's input chest
- [enricher-computer](computers/enricher-computer/README.md): feeds the storage system's ores into Mekanism Enrichment Chambers for 2 dust per ore (4 per 3 raw), which the smelter turns into ingots
- [essence-computer](computers/essence-computer/README.md): empties Botany Pots of Mystical Agriculture essence into the storage system, and looks up and orders what the essence crafts into
- [crate-turtle](computers/crate-turtle/README.md): turtle that pulls endless items out of a Create Creative Crate into a chest: keeps it full, sends a set amount, or keeps the storage system stocked

## How they connect

Every program works on its own. With a modem they work together: everything
reports to the status server, AutoMine turtles take jobs from the AutoMine
server, the GPS deployer's hosts keep turtles on course, the village builder
gets its blocks from the storage system (which has the crafter make what it
lacks, and the smelter smelt its ores) and shows its next building through the blueprint projector,
several builder turtles share one projected building a strip each, and village turtles with GPS can
join one village as a crew. The
website has a diagram of it all.

## Adding a computer

1. Copy `computers/_template` to `computers/<name>` (e.g. `computers/mining-turtle`).
2. Fill in its `README.md` (computer ID, label, location, peripherals).
3. Write its programs; `startup.lua` runs on boot.

## Getting code onto a computer

**Installer (easiest):** `wget run https://rakeki.github.io/Rakeki-s-ComputerCraft/install.lua <program>`
downloads a program and the `lib/` files it needs. Afterwards `install update`
fetches newer versions (your `config.lua` is kept), and `install remove <program>`
uninstalls one (files another program still uses stay). Building plans for the
projector and builder turtles live in [`plans/`](plans/): `install plans`
lists them and `install plan <name>` adds one to a computer's `/plans`.
Each has a page on the website with a 3D view, and the website's plan viewer
shows any plan file you drop on it.

### Updates

Installed programs update themselves: on every boot `startup.lua` asks the
website whether there's a newer version and, if so, downloads it before the
program starts (your `config.lua` is kept). Without internet it carries on
after a few seconds. After a push, the website takes a few minutes (up to
about 15) before computers see the new version. To turn it off on one computer, type
`set install.autoupdate false`. A turtle that reboots in the middle of a job
carries on with the new version.

In-game files live in your world save at
`saves/<world>/computercraft/computer/<id>/` (turtles too, keyed by ID — run `id` in-game to see it).
Options:

- **Copy files** directly into that folder (single-player).
- **Pastebin**: `pastebin get <code> startup.lua`.
- **wget**: host the raw file (e.g. on GitHub) and run `wget <url> startup.lua`.

Shared modules from `lib/` should be copied alongside the program and loaded with `require("lib.<module>")`.

Every program saves its errors to `/errors.log` on that computer through
`lib/errlog.lua`, all in one format. If something stopped, `edit /errors.log`
shows what went wrong, when, and where the turtle was.
