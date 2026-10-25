# lib

Shared Lua modules. Copy the `lib/` folder onto a computer and load with
`require("lib.<module>")`.

- `nav.lua`: turtle position tracking (saved across reboots, optional GPS) and
  movement that digs through anything except protected blocks. Used by
  `excavate-turtle`, `strip-mine-turtle`, `village-turtle`, `mob-farm-turtle`,
  `tree-farm-turtle`, `crop-farm-turtle`, `mine-turtle`, `gps-deployer` and
  `builder-turtle`.
- `report.lua`: sends this computer's status to the [status
  server](../computers/status-server/README.md). Used by `excavate-turtle`,
  `strip-mine-turtle`, `village-turtle`, `mob-farm-turtle`,
  `tree-farm-turtle`, `crop-farm-turtle`, `mine-server`, `mine-turtle`,
  `gps-deployer` (if present), `blueprint-projector` (if present),
  `builder-turtle`, `storage-computer` (if present), `crafter-turtle` (if
  present), `craft-overseer` (if present), `smelter-computer` (if present),
  `colony-dashboard` (if present) and the computer template.
- `errlog.lua`: saves errors to `/errors.log` on the computer in one format
  (time, program, computer, message, context such as position and fuel, stack
  trace), skipping repeats and trimming old entries. Used by
  `excavate-turtle`, `strip-mine-turtle`, `village-turtle`, `mob-farm-turtle`,
  `tree-farm-turtle`, `crop-farm-turtle`, `mine-server`, `mine-turtle`,
  `status-server`, `gps-deployer`, `blueprint-projector` (if present),
  `builder-turtle`, `storage-computer` (if present), `crafter-turtle` (if
  present), `craft-overseer` (if present), `smelter-computer` (if present),
  `colony-dashboard` (if present) and the computer template.
- `claim.lua`: tells the [storage
  computer](../computers/storage-computer/README.md) which chest on its
  network is the one next to this turtle (its delivery chest, or the crafter
  chest), so nothing has to be picked in `storage setup`. Used by
  `village-turtle`, `builder-turtle` and `crafter-turtle`.
- `screen.lua`: flicker-free monitors and terminals: each frame is drawn into
  a hidden window and shown in one go, and frames that haven't changed can be
  skipped. `screen.find` picks the monitor, sets its text scale once and
  follows monitors as they're added or removed. Used by `mine-server`,
  `status-server`, `blueprint-projector`, `storage-computer`,
  `craft-overseer`, `smelter-computer` and `colony-dashboard`.
- `net.lua`: rednet the same way everywhere: opening wireless or every modem,
  asking another computer something with an id the answer repeats and a
  deadline (`net.ask`), answering (`net.answer`), and a cached lookup of the
  computer hosting a protocol (`net.peer`). Used by `village-turtle`,
  `mine-server`, `mine-turtle`, `status-server`, `blueprint-projector`,
  `builder-turtle`, `storage-computer`, `crafter-turtle`, `craft-overseer` and
  `smelter-computer`.
- `files.lua`: crash-safe save files: a table written to a temp file and moved
  into place, so a crash mid-save never leaves a broken file. `lib/nav.lua`'s
  `writeFile` / `readFile` / `deleteFile` are these. Used by
  `excavate-turtle`, `strip-mine-turtle`, `village-turtle`, `mob-farm-turtle`,
  `tree-farm-turtle`, `crop-farm-turtle`, `mine-server`, `mine-turtle`,
  `status-server`, `gps-deployer`, `blueprint-projector`, `builder-turtle`,
  `storage-computer`, `craft-overseer` and `smelter-computer`.
- `inv.lua`: a turtle's inventory and fuel: count or select an item (by name,
  list, set or function), empty slots, fuel level, refuel from what's on
  board. Used by `excavate-turtle`, `strip-mine-turtle`, `village-turtle`,
  `mob-farm-turtle`, `tree-farm-turtle`, `crop-farm-turtle`, `mine-turtle`,
  `gps-deployer` and `builder-turtle`.
