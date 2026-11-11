---
name: labels
description: How every computer and turtle here names itself with lib/label.lua ("<Name>-<id>", e.g. Storage-4, Excavator-12, Factory-Smelt-Enrich-7), the name each program uses, labels that change with what a computer runs (the factory's parts), and never replacing a label the player typed. Use when writing a new program, changing what a computer runs, or anywhere a program reads or sets os.getComputerLabel.
---

# Labels (lib/label.lua)

Every program labels the computer or turtle it runs on, once at start, so the
status server, the turtle finder, the overseer map and `/errors.log` all show
the same readable names, and a broken turtle keeps its files (a labelled
turtle keeps its disk).

```lua
require("lib.label").set("Storage")                 -- Storage-4
local label = require("lib.label")
label.set("Factory", { "Smelt", "Enrich" })        -- Factory-Smelt-Enrich-7
```

## Rules

- **Format:** `<Name>-<id>`, or `<Name>-<extra>-<extra>-<id>`. Name is
  CamelCase, no spaces (`CropFarm`, `CraftOverseer`). The id is always last.
  CC labels are at most 32 characters: extras that don't fit are left off.
- **Never replace a player's label.** `label.set` only names a computer that
  has no label, or still wears the label it last set (`/.auto_label`), or the
  old `<Name>-<id>` one turtles always gave themselves. So `label set Base
  furnaces` sticks, and a computer's label still follows what it runs.
- **Call it at start**, before `report.init` / `errlog.init` and before any
  `rednet.host(..., os.getComputerLabel())`, so the first status report and
  the hosted name carry it. Never call `os.setComputerLabel` yourself.
- **A label that depends on what runs** (the factory) calls `label.set` again
  whenever that changes: it's cheap (nothing happens when it's already right),
  so the factory calls it every round from `reportStatus`.
- **Libs:** add `"label"` and `"files"` (label.lua saves `/.auto_label` with
  `lib/files.lua`) to the program's `libs` in `site/programs.json`, and the
  program to `label.lua`'s line in `lib/README.md`.
- GPS hosts built by the gps-deployer are named by its floppy installer
  (`GPS-<n>` style); they don't run a program of this repo, so they're the
  one exception.

## Names in use

| Program | Name | | Program | Name |
|---|---|---|---|---|
| blueprint-projector | Projector | | excavate-turtle | Excavator |
| build-control | BuildControl | | level-turtle | Leveller |
| instabuild | Instabuild | | strip-mine-turtle | StripMiner |
| cannon-feeder | CannonFeeder | | nether-tunnel-turtle | NetherTunnel |
| cobble-breeder | Breeder | | mine-turtle | Miner |
| colony-dashboard | Colony | | mine-server | MineServer |
| craft-overseer | CraftOverseer | | village-turtle | Villager |
| craft-terminal | CraftTerminal | | mob-farm-turtle | MobFarm |
| remote-terminal | RemoteTerminal | | tree-farm-turtle | TreeFarm |
| storage-computer | Storage | | crop-farm-turtle | CropFarm |
| factory | Factory-<parts> | | builder-turtle | Builder |
| digital-miner-manager | DigitalMiners | | crafter-turtle | Crafter |
| fission-guard | FissionGuard | | crate-turtle | Crate |
| fusion-control | Fusion | | furnace-turtle | Smelter |
| power-dashboard | Power | | gps-deployer | GpsDeployer |
| display-monitor | Display | | turtle-finder | Finder |
| status-server | Status | | overseer-bridge | Bridge |
| update-watcher | Updater | | | |

The factory's extras are each running part's `short` (else its `title`), in
the chain's order: `Enrich`, `Smelt`, `Infuse`, `Saw`, `Cook`, `Essence`. A
factory with nothing running yet is just `Factory-<id>`.

A new program picks a name not in this table and adds it here.
