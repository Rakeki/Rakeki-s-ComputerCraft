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
site/             The website and in-game installer (built by GitHub Actions)
```

## Computers

- [mine-server](computers/mine-server/README.md): AutoMine server; assigns chunks to miners and shows a chunk-planning map
- [mine-turtle](computers/mine-turtle/README.md): AutoMine mining turtle (same code on every miner)
- [status-server](computers/status-server/README.md): monitor dashboard showing every computer's status and what it's doing
- [gps-deployer](computers/gps-deployer/README.md): turtle that builds and starts a 4-computer GPS system
- [excavate-turtle](computers/excavate-turtle/README.md): standalone turtle that digs a hall with two floors of rooms, a ledge and stairs
- [strip-mine-turtle](computers/strip-mine-turtle/README.md): standalone turtle that digs a 3x3 main tunnel with 3x3 branches off both sides
- [village-turtle](computers/village-turtle/README.md): turtle that builds a themed village and keeps expanding it, picking buildings to suit the terrain
- [mob-farm-turtle](computers/mob-farm-turtle/README.md): standalone turtle that builds a mob farm: a dark spawning room with water channels, a drop shaft and a collection chest

## Adding a computer

1. Copy `computers/_template` to `computers/<name>` (e.g. `computers/mining-turtle`).
2. Fill in its `README.md` (computer ID, label, location, peripherals).
3. Write its programs; `startup.lua` runs on boot.

## Getting code onto a computer

**Installer (easiest):** `wget run https://rakeki.github.io/Rakeki-s-ComputerCraft/install.lua <program>`
downloads a program and the `lib/` files it needs. Afterwards `install update`
fetches newer versions (your `config.lua` is kept).

In-game files live in your world save at
`saves/<world>/computercraft/computer/<id>/` (turtles too, keyed by ID — run `id` in-game to see it).
Options:

- **Copy files** directly into that folder (single-player).
- **Pastebin**: `pastebin get <code> startup.lua`.
- **wget**: host the raw file (e.g. on GitHub) and run `wget <url> startup.lua`.

Shared modules from `lib/` should be copied alongside the program and loaded with `require("lib.<module>")`.
