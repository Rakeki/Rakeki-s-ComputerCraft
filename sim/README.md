# sim

A headless CC: Tweaked world on your PC: every program in this repo,
installed with the real installer and run together, so you can see them work
with each other before trying it in-game. It also makes the website's
[network map](https://rakeki.github.io/Rakeki-s-ComputerCraft/network/).

```
cd sim
npm install                 -- Fengari (Lua in JS), patched; then CC's own ROM from GitHub
node ../site/build.mjs      -- the computers install from _site/, built for http://localhost:8080
npm test                    -- each scenario on its own, with its checks
node run.mjs storage 400    -- one scenario: every computer's screen at the end (--monitors too)
node map.mjs 1800           -- the whole base for 30 game minutes -> site/network.json
```

## Watching a run

```
node replay.mjs bootstrap 3200   -- record a scenario: sim/out/replays/bootstrap.json
node viewer/serve.mjs            -- then open http://localhost:8081/?replay=bootstrap
```

The viewer plays the recording back in voxels: the turtles move, dig and
build, each rednet message flashes between sender and receiver (rings for
broadcasts), and the list shows every turtle's status and fuel. Tap one to
see its screen at that moment. Play, pause and drag the timeline; 1× to 200×;
drag to move, scroll or pinch to zoom, ⟳ to turn the view, and the cut menu hides
everything above a height so you can watch the mines underground. Any scenario
records (`node replay.mjs storage 400`); one with an exported `VIEW` box
draws that area, the others a box round their computers.

## How it works

- **Lua.** Each computer is its own [Fengari](https://fengari.io) Lua state,
  patched (`patch-fengari.mjs`) to act like CC's Cobalt: no 32-bit integer
  wraparound, `tostring(2.0)` is `"2"`, and Lua 5.2's lenient `%` escapes in
  `gsub`. `core/prelude.lua` adds the rest of Lua 5.2 (`bit32`, `loadstring`,
  `unpack`, `string.format` truncating `%d`) and turns the JS natives into
  CC's globals.
- **CraftOS.** `fetch-rom.mjs` downloads CC: Tweaked's own `bios.lua` and
  `rom/` at a fixed release, so rednet, parallel, settings, textutils, gps,
  the shell and `wget` are the real ones.
- **Time.** Everything runs on a simulated clock: a computer waiting on a
  timer costs nothing until the clock gets there. Timers fire on 50 ms ticks,
  turtle moves take 0.4 s, inventory and Mekanism calls take a tick and yield
  like CC's main-thread calls do. A computer that runs 7 s without yielding is
  stopped, as in CC.
- **The world** (`core/world.mjs`): blocks (lazily generated terrain below
  the base: `core/terrain.mjs`, with a Nether past X 2500), computers,
  turtles (movement, digging, placing, inventory, fuel, upgrades, crafting
  with the storage computer's own `recipes.lua`), wireless and ender modems
  (range by height, like CC), wired networks with named peripherals,
  inventories (`pushItems` / `pullItems` between them), monitors and touches,
  `http` (the site from `_site/`, and any route a scenario adds), command
  computers (`setblock`, `fill`).
- **Blocks that do things** (`core/machines.mjs`, `core/placing.mjs`,
  `core/mods.mjs`): furnaces, hoppers, ender chests, a creative crate,
  saplings and crops that grow, leaves that decay (dropping saplings), items
  lying on the ground (dropped, sucked up, gone after 5 minutes), disk drives
  and floppies, computers and
  modems a turtle places, a Spatial Projector, and stand-ins for Mekanism's
  Induction Matrix, fission and fusion reactors and Digital Miners, Advanced
  Peripherals' Colony Integrator and Block Reader, and Create's
  Schematicannon. Method names follow the mods (Mekanism 10.7's methods.csv).
- **The player** (`core/script.mjs`): types commands, waits for the screen to
  say something, clicks the terminal and taps monitors.

## Scenarios

Each builds part of a base the way the programs' READMEs say, and `check`s
what a player would notice.

| Scenario | What's in it | Checked |
|---|---|---|
| `mining` | GPS, the status server, AutoMine and two miners (chunks queued by clicking the map) | ore in the miners' chests |
| `storage` | Storage computer set up from its monitor, crafting turtle, factory with furnaces, a far-away remote terminal | 30 raw iron smelted into storage, the remote terminal's pull |
| `machines` | Power dashboard, fission guard, fusion control, digital miners, colony dashboard | the reactor started, then SCRAMmed when its coolant ran out |
| `gps` | No GPS: the GPS deployer builds the hosts | 4 hosts on, a probe gets a fix |
| `extras` | Tree and crop farms, mob farm, village, Nether tunnel, projector + instabuild, cobble breeder | instabuild placed blocks, the farms harvested |
| `bootstrap` | Four turtles placed together in one chunk, each with an ender modem and a chest: GPS deployer then strip miner (`set nav.range 64`), leveller, excavator, tree farm; and a crafty furnace turtle behind the strip miner's chest | what today's programs get done alone (ore mined at Y -54, furnaces crafted, the ore smelted), and that each turtle stays within its range; prints every step of a whole base, done or what's missing |
| `base` | All the above together, plus builders + build control, excavator, leveller, strip miner, crate turtle, turtle finder, overseer bridge, craft overseer | via `map.mjs` |

## Things to know

- It's a model of CC and the mods, not the real thing: it shows the programs
  talking to each other and finds mistakes in them, but timings and mod
  behaviour are approximate. Things still have to be tried in-game.
- Not modelled: mobs, redstone between blocks, chunk loading, other
  dimensions (the Nether is a region of the one world), Cobblemon (the cobble
  breeder starts but has no pasture to find).
- Each run's computers' files are in `out/run-*/computer/<id>/`, the way CC
  keeps them in a world save; runs older than a day are cleared.
