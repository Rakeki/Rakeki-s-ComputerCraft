# lib

Shared Lua modules. Copy the `lib/` folder onto a computer and load with
`require("lib.<module>")`.

- `nav.lua`: turtle position tracking (saved across reboots, optional GPS) and
  movement that digs through anything except protected blocks. Used by
  `mine-turtle`, `excavate-turtle`, `strip-mine-turtle`, `mob-farm-turtle`, `village-turtle` and `gps-deployer`.
- `report.lua`: sends this computer's status to the
  [status server](../computers/status-server/README.md). Used by `mine-turtle`,
  `mine-server`, `excavate-turtle`, `strip-mine-turtle`, `mob-farm-turtle`, `village-turtle` and the computer template.
