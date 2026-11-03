# lib

Shared Lua modules. Copy the `lib/` folder onto a computer and load with
`require("lib.<module>")`.

- `nav.lua`: turtle position tracking (saved across reboots, checked with GPS, which
  every moving turtle but the gps-deployer waits for: `nav.waitForGps`) and
  movement that digs through anything except protected blocks. Used by
  `excavate-turtle`, `level-turtle`, `strip-mine-turtle`, `nether-tunnel-turtle`, `village-turtle`, `mob-farm-turtle`,
  `tree-farm-turtle`, `crop-farm-turtle`, `mine-turtle`, `gps-deployer` and
  `builder-turtle`.
- `report.lua`: sends this computer's status to the [status
  server](../computers/status-server/README.md). Used by `excavate-turtle`, `level-turtle`,
  `strip-mine-turtle`, `nether-tunnel-turtle`, `village-turtle`, `mob-farm-turtle`,
  `tree-farm-turtle`, `crop-farm-turtle`, `mine-server`, `mine-turtle`,
  `gps-deployer` (if present), `blueprint-projector` (if present),
  `builder-turtle`, `storage-computer` (if present), `crafter-turtle` (if
  present), `craft-overseer` (if present), `factory` (if present), `colony-dashboard` (if present), `fission-guard` (if present),
  `power-dashboard` (if present), `fusion-control` (if present),
  `digital-miner-manager` (if present), `crate-turtle` (if present),
  `build-control` (if present), `remote-terminal` (if present), `cannon-feeder` (if present), `cobble-breeder` (if present) and the computer template.
- `errlog.lua`: saves errors to `/errors.log` on the computer in one format
  (time, program, computer, message, context such as position and fuel, stack
  trace), skipping repeats and trimming old entries. Used by
  `excavate-turtle`, `level-turtle`, `strip-mine-turtle`, `nether-tunnel-turtle`, `village-turtle`, `mob-farm-turtle`,
  `tree-farm-turtle`, `crop-farm-turtle`, `mine-server`, `mine-turtle`,
  `status-server`, `gps-deployer`, `blueprint-projector` (if present),
  `builder-turtle`, `storage-computer` (if present), `crafter-turtle` (if
  present), `craft-overseer` (if present), `factory` (if present), `colony-dashboard` (if present), `fission-guard` (if present),
  `power-dashboard` (if present), `fusion-control` (if present),
  `digital-miner-manager` (if present), `crate-turtle` (if present),
  `build-control` (if present), `instabuild` (if present), `remote-terminal` (if present), `cannon-feeder` (if present), `cobble-breeder` (if present), `turtle-finder` (if present) and the computer template.
- `claim.lua`: tells the [storage
  computer](../computers/storage-computer/README.md) which chest on its
  network is the one next to this turtle (its delivery chest, or the crafter
  chest), so nothing has to be picked in `storage setup`. Used by
  `village-turtle`, `builder-turtle`, `crafter-turtle`, `remote-terminal`, `cannon-feeder`, `craft-overseer`
  (role `hub`: its ender chest's twin, for crafting turtles far away) and `workchest.lua`
  (role `work`: a far-away work chest, through an ender chest).
- `mekfeed.lua`: Mekanism machines fed through a hopper or barrel (CC can't
  reach their slots): reads them and their feeders at once, sets their bottom
  to Output with Auto-eject, empties their output chests into storage, tells
  the storage computer which barrels are feeders and output chests, puts back what doesn't go in, and the `add` / `remove` commands.
  Also Create lines (crushing wheels, washing, blasting and smoking fans), which CC can't see at all: just a feeder
  chest and an output chest, kept topped up and shown red when the feeder stops going down.
  A set can give each machine a second feeder for its extra slot (`opts.extra`), its own side config
  (`opts.sides`), more reads (`opts.read`) and a required output chest (`opts.needOutput`): the infuser's.
  Used by `factory` (its enricher's chambers, crushers and washers, its smelter's Mekanism smelters and fans, and its
  infuser's Metallurgic Infusers; `mekfeed.register` sends every set's feeders at once).
- `workchest.lua`: a computer's work chest: names an empty chest on the
  storage network to the [storage
  computer](../computers/storage-computer/README.md), has it filled in one
  request a round, moves items from it into furnaces or feeders and sends the
  rest back through the input chest. Far away it's an ender chest, and things
  go home through it too (or a return ender chest). Used by `factory` (one
  work chest for its smelter and enricher).
- `setupui.lua`: setup screens on the monitor and the terminal at once: pages of
  settings, and chest lists a page at a time with what's in each chest, an Empty
  filter and typed search. Used by `storage-computer` and `factory`
  (with `mekfeed.lua`'s and `workchest.lua`'s setup pages); `ui:pickByDrop` picks a chest by
  the item the player drops in it (the factory's output chests).
- `screen.lua`: flicker-free monitors and terminals: each frame is drawn into
  a hidden window and shown in one go, and frames that haven't changed can be
  skipped. `screen.find` picks the monitor (next to it or on the cable; the
  player can name one with `set <program>.monitor <name>`), sets its text
  scale once and follows monitors as they're added or removed. `screen.tiles`
  draws a status board (a coloured tile per machine). Used by `mine-server`,
  `status-server`, `blueprint-projector`, `storage-computer`,
  `craft-overseer`, `factory`, `colony-dashboard`,
  `fission-guard`, `power-dashboard`, `fusion-control`,
  `digital-miner-manager`, `remote-terminal`, `cannon-feeder`, `cobble-breeder` and `turtle-finder`.
- `net.lua`: rednet the same way everywhere: opening wireless or every modem,
  asking another computer something with an id the answer repeats and a
  deadline (`net.ask`), answering (`net.answer`), and a cached lookup of the
  computer hosting a protocol (`net.peer`). Copes with a server restart, when
  everything boots at once: a missing peer is looked for every 5 s for the first
  5 minutes, `net.open` waits briefly for a modem, `net.keepOpen` opens late ones. Used by `village-turtle`,
  `mine-server`, `mine-turtle`, `status-server`, `blueprint-projector`,
  `builder-turtle`, `storage-computer`, `crafter-turtle`, `craft-overseer`,
  `factory`,
  `crate-turtle` (for `crate stock`), `build-control`, `instabuild`, `remote-terminal`, `cannon-feeder` and `turtle-finder`.
- `files.lua`: crash-safe save files: a table written to a temp file and moved
  into place, so a crash mid-save never leaves a broken file. `lib/nav.lua`'s
  `writeFile` / `readFile` / `deleteFile` are these. Used by
  `excavate-turtle`, `level-turtle`, `strip-mine-turtle`, `nether-tunnel-turtle`, `village-turtle`, `mob-farm-turtle`,
  `tree-farm-turtle`, `crop-farm-turtle`, `mine-server`, `mine-turtle`,
  `status-server`, `gps-deployer`, `blueprint-projector`, `builder-turtle`,
  `storage-computer`, `craft-overseer`, `factory`,
  `fission-guard`, `crate-turtle`, `build-control`, `instabuild`,
  `remote-terminal`, `cannon-feeder`, `cobble-breeder`, `turtle-finder` and `workchest.lua`.
- `inv.lua`: a turtle's inventory and fuel: count or select an item (by name,
  list, set or function), empty slots, fuel level, refuel from what's on
  board. Used by `excavate-turtle`, `level-turtle`, `strip-mine-turtle`, `nether-tunnel-turtle`, `village-turtle`,
  `mob-farm-turtle`, `tree-farm-turtle`, `crop-farm-turtle`, `mine-turtle`,
  `gps-deployer` and `builder-turtle`.
- `plan.lua`: building plans: loads a `.json` or `.lua` plan from `/plans`
  (legend + layers, or a block list) and places it in the world, turned to
  face any way (blocks with a `[facing=...]` state turn with it, and the sides of walls and fences), takes options typed after the command for a Lua plan (`plan.options`: a size like `31x25x8`, `key=value`), and copies a plan so a building keeps the plan it started with. Used by `blueprint-projector`, `build-control`, `instabuild` and `cannon-feeder` (`cannon plan`: the blocks a plan uses).
- `crew.lua`: hands a building to the [builder
  turtles](../computers/builder-turtle/README.md) in strips (one per builder in range, up to 4), follows
  their progress, gives waiting strips to the next free one, and stops them.
  Used by `blueprint-projector` and `build-control`.
