# lib

Shared Lua modules. Copy the `lib/` folder onto a computer and load with
`require("lib.<module>")`.

- `nav.lua`: turtle position tracking (saved across reboots, optional GPS) and
  movement that digs through anything except protected blocks. Used by
  `mine-turtle`, `excavate-turtle`, `strip-mine-turtle`, `mob-farm-turtle`, `village-turtle`, `builder-turtle`, `tree-farm-turtle`, `crop-farm-turtle` and `gps-deployer`.
- `report.lua`: sends this computer's status to the
  [status server](../computers/status-server/README.md). Used by `mine-turtle`,
  `mine-server`, `excavate-turtle`, `strip-mine-turtle`, `mob-farm-turtle`, `village-turtle`, `builder-turtle`, `tree-farm-turtle`, `crop-farm-turtle`, `blueprint-projector` (if present), `storage-computer` (if present), `colony-dashboard` (if present), `crafter-turtle` (if present), `smelter-computer` (if present) and the computer template.
- `errlog.lua`: saves errors to `/errors.log` on the computer in one format
  (time, program, computer, message, context such as position and fuel, stack
  trace), skipping repeats and trimming old entries. Used by `mine-turtle`,
  `mine-server`, `status-server`, `excavate-turtle`, `strip-mine-turtle`,
  `mob-farm-turtle`, `village-turtle`, `tree-farm-turtle`, `crop-farm-turtle`,
  `gps-deployer`, `storage-computer` (if present), `colony-dashboard` (if present),
  `crafter-turtle` (if present), `smelter-computer` (if present), `builder-turtle`,
  `blueprint-projector` (if present) and the computer template.
- `claim.lua`: tells the [storage computer](../computers/storage-computer/README.md)
  which chest on its network is the one next to this turtle (its delivery
  chest, or the crafter chest), so nothing has to be picked in
  `storage setup`. Used by `village-turtle`, `builder-turtle` and
  `crafter-turtle`.
- `screen.lua`: flicker-free monitors and terminals: each frame is drawn into a
  hidden window and shown in one go, and frames that haven't changed can be
  skipped. `screen.find` picks the monitor, sets its text scale once and
  follows monitors as they're added or removed. Used by `storage-computer`, `smelter-computer`, `colony-dashboard`,
  `blueprint-projector`, `mine-server` and `status-server`.
