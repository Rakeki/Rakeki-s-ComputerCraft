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
tools/            PC-side helpers, e.g. recipes.mjs: a modpack's crafting recipes for the storage system,
                  and overseer/: the server and page for the live network map
site/             The website and in-game installer (built by GitHub Actions)
sim/              A simulated CC world on your PC that runs every program together (tests, and the network map)
```

## Computers

- [mine-server](computers/mine-server/README.md): AutoMine server; assigns chunks to miners and shows a chunk-planning map
- [mine-turtle](computers/mine-turtle/README.md): AutoMine mining turtle (same code on every miner)
- [status-server](computers/status-server/README.md): monitor dashboard showing every computer's status and what it's doing
- [overseer-bridge](computers/overseer-bridge/README.md): listens to every rednet message and status report and posts them to the overseer server on your PC, a live browser map of every computer and turtle, what each is doing, and the messages flying between them
- [turtle-finder](computers/turtle-finder/README.md): pocket computer that finds a lost turtle: lists every turtle it hears, nearest first, and points an arrow to the one you pick
- [gps-deployer](computers/gps-deployer/README.md): turtle that builds and starts a 4-computer GPS system, optionally each host inside a satellite
- [excavate-turtle](computers/excavate-turtle/README.md): standalone turtle that digs a hole of any size and walls it in so it stays dry, ready for the builder turtles; `excavate <plan>` digs the hole an underground plan needs (fourteen of them, from a small bunker to a Create base and train station by bedrock)
- [level-turtle](computers/level-turtle/README.md): standalone turtle that flattens an area into a solid building platform: cuts down hills and trees, fills dips, ponds and holes with the dirt it dug
- [strip-mine-turtle](computers/strip-mine-turtle/README.md): standalone turtle that digs a 3x3 main tunnel with 3x3 branches off both sides
- [nether-tunnel-turtle](computers/nether-tunnel-turtle/README.md): standalone turtle that digs a sealed 3x3 tunnel through the Nether, patching holes and walling off lava
- [village-turtle](computers/village-turtle/README.md): turtle that builds a themed village and keeps expanding it, picking buildings to suit the terrain
- [mob-farm-turtle](computers/mob-farm-turtle/README.md): standalone turtle that builds a mob farm: a dark spawning room with water channels, a drop shaft and a collection chest
- [blueprint-projector](computers/blueprint-projector/README.md): projects a building plan into the world with CC: Spatial Projector; move and turn it from a monitor, then build it layer by layer, or tap Build and a builder turtle builds it
- [builder-turtle](computers/builder-turtle/README.md): turtle that builds whatever the blueprint projector is showing, right where it's shown
- [build-control](computers/build-control/README.md): sends a plan to the builder turtles at coordinates you type, from any computer or pocket computer, no projector needed
- [instabuild](computers/instabuild/README.md): creative only: places a whole plan in seconds from a command computer, typed in or where the blueprint projector shows it, never replacing a block, and undoes it again
- [tree-farm-turtle](computers/tree-farm-turtle/README.md): turtle that plants a grid of trees, chops them as they grow, replants and brings the logs to a chest
- [crop-farm-turtle](computers/crop-farm-turtle/README.md): turtle that flies over a field, harvests ripe wheat, carrots, potatoes and beetroot, and replants them
- [cobble-breeder](computers/cobble-breeder/README.md): breeds better and better Cobblemon from a Cobbreeding pasture (command computer): reads every egg's IVs before it hatches, sends the better ones to the incubator and tells you which breeder to swap; monitor shows each breeder's IVs and how close you are to 6x31
- [storage-computer](computers/storage-computer/README.md): turns a network of chests, or an AE2 / Refined Storage system, into one searchable store with an input and an output chest and a touch monitor to take items from, and serves items to every turtle
- [remote-terminal](computers/remote-terminal/README.md): the storage system from anywhere, through a linked ender chest: search and pull items, or drop them in to send them home
- [cannon-feeder](computers/cannon-feeder/README.md): keeps a Create Schematicannon stocked from the storage system: give it the material list and it tops up the chest by the cannon, crafting what's missing on the way
- [crafter-turtle](computers/crafter-turtle/README.md): crafty turtle that makes what the storage system is asked for but doesn't have, from what it does
- [craft-overseer](computers/craft-overseer/README.md): shares the storage system's crafting between any number of crafting turtles, with the queue and what each job is missing on a monitor
- [factory](computers/factory/README.md): every machine that turns stored items into something else, on as many computers as you like: furnaces, blast furnaces and smokers (ores, food, charcoal, stone and glass on order), Mekanism Enrichment Chambers and Energized Smelters, Metallurgic Infusers on request (steel, alloys, circuits; the storage computer orders them for its crafts too), Create crushing wheels, washing fans and blasting and smoking fans (no Mekanism needed), Cobblemon cooking pots (exp candy up to XL) and Mystical Agriculture botany pots (essence, and ordering what it crafts into; far away, an essence farm with its own crafting turtles that makes what the storage computer asks for)
- [colony-dashboard](computers/colony-dashboard/README.md): monitor dashboard for a MineColonies colony: citizens, happiness, buildings, requests, work orders and attack alarm
- [fission-guard](computers/fission-guard/README.md): watches a Mekanism fission reactor and SCRAMs it before it overheats, takes damage, runs short of coolant or backs up on steam or waste; monitor gauges with start, SCRAM and burn-rate buttons
- [power-dashboard](computers/power-dashboard/README.md): Mekanism Induction Matrix on a monitor: stored power, in and out, time until full or empty, an hour's graph, turbines and energy cubes, and a redstone signal when power runs low
- [fusion-control](computers/fusion-control/README.md): Mekanism fusion reactor panel: plasma and case temperature, fuel, water and steam, power made, injection-rate buttons and warnings
- [digital-miner-manager](computers/digital-miner-manager/README.md): every Mekanism Digital Miner on one monitor: start, stop, reset, radius, Y range, silk touch and filters; mined items go to the storage system's input chest
- [crate-turtle](computers/crate-turtle/README.md): turtle that pulls endless items out of a Create Creative Crate into a chest: keeps it full, sends a set amount, or keeps the storage system stocked

## How they connect

Every program works on its own. With a modem they work together: everything
reports to the status server (and, through the overseer bridge, to a live map in your browser), AutoMine turtles take jobs from the AutoMine
server, the GPS deployer's hosts keep turtles on course, the village builder
gets its blocks from the storage system (which has the crafter make what it
lacks, and the factory smelt its ores) and shows its next building through the blueprint projector,
several builder turtles share one projected building a strip each, and village turtles with GPS can
join one village as a crew. The
website has a diagram of it all, and a
[network map](https://rakeki.github.io/Rakeki-s-ComputerCraft/network/) of a
whole base run in the [simulator](sim/README.md): where each computer is and
what they actually send each other.

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
The website's [plans page](https://rakeki.github.io/Rakeki-s-ComputerCraft/plans/)
shows them all in 3D, above ground and underground; tap Pick on the ones you want for one
`install plan <name> <name> ...` command. Each has a page of its own, and the website's plan viewer
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
