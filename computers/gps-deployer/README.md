# gps-deployer

- **Type:** mining turtle (a wireless or ender modem as well lets it test the GPS at the end)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Builds a working GPS system for you. It flies up and places 4 computers, each
with a modem on top, then installs `gps host` on each one with its own
coordinates and switches them on. Afterwards any turtle or computer with a
wireless modem can call `gps.locate()`, and the mining turtles find their own
position.

By default it builds as high as possible, because wireless modems reach further
the higher they are. It climbs straight up until the world stops it, then builds
the hosts 9 blocks below that, so it works whatever the build limit is in your
world or modpack.

Layout near where the turtle starts (+x is east, +z is south), with H the height:

| Host | Position |
|---|---|
| GPS-1 | start +2, H, start +2 |
| GPS-2 | start +10, H, start +2 |
| GPS-3 | start +2, H, start +10 |
| GPS-4 | start +6, H + 6, start +6 (higher, so they're not all in one plane) |

Each host is labelled (so it keeps its program if broken) and restarts
`gps host` on its own after a reboot or chunk reload. If `lib/report.lua` is on
the turtle, it's copied to each host, and the hosts appear on the
[status server](../status-server/README.md) as "gps host".

### Satellites

`gps-deploy satellite` builds the same 4 hosts, then builds a satellite
around each one, so your GPS looks like something floating in orbit instead of
four bare computers in the sky:

- a 3×3×3 hull with the computer at its heart and the modem set in its top
- an antenna (2 end rods) on the modem, in a ring of slabs like a dish
- a solar wing to the east and west: an iron-bar spine with daylight
  detectors along both sides, and a light at the tip
- a light underneath

Each satellite is 17 blocks across (east to west) and 3 deep, so the hosts sit
further apart than plain ones (which also makes GPS a little more accurate):

| Host | Position |
|---|---|
| GPS-1 | start +9, H, start +4 |
| GPS-2 | start +28, H, start +4 |
| GPS-3 | start +9, H, start +22 |
| GPS-4 | start +18, H + 9, start +13 |

The hull doesn't block the signal: wireless and ender modems reach through
blocks.

## Example layouts

- **Plain hosts:** `gps-deploy`, four computers with modems on top, one raised.
- **Satellite:** one satellite close up, from `gps-deploy satellite`.
- **Satellite constellation:** all four satellites, the fourth 9 blocks higher.

## Files

- `gps-deploy.lua`: the program
- `startup.lua`: fetches any newer version from the website on boot (the deployer itself is started by hand)
- [`lib/nav.lua`](../../lib/nav.lua): movement (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): optional, passed on to the hosts (copy to `/lib/report.lua`)
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

## Use

1. Put these in the turtle, any slots:
   - 4 computers (normal or advanced)
   - 4 wireless modems, or ender modems
   - 1 disk drive and 1 floppy disk (both come back to the turtle)
   - fuel: about 750 from sea level (`refuel all`), about 3000 for satellites
   - for satellites, also (any of the listed kinds; one kind each looks tidiest):
     - 100 hull blocks: iron blocks, white or light gray concrete, smooth quartz or quartz blocks
     - 64 solar panels: daylight detectors, or blue, light blue or black stained glass
     - 48 iron bars
     - 32 slabs: smooth quartz, quartz, smooth stone or polished andesite
     - 12 lights: sea lanterns, glowstone, shroomlights or froglights
     - 8 end rods or lightning rods

     That's 11 slots with the computers and modems, so it all fits.
2. Place it somewhere with **open sky above it**. It flies straight up, and
   it will dig through anything in the way that isn't a chest or a computer.
3. Run `gps-deploy` to build at the top, or `gps-deploy 200` for a lower height.
   Add `satellite` for satellites: `gps-deploy satellite` or
   `gps-deploy satellite 200`. It lists any satellite blocks it's short of
   before it starts.
4. Enter the turtle's X, Y (height) and Z, and which way it's facing, from F3.
   It can't get them from GPS, since there isn't one yet. If it already knows
   its position from an earlier run, it shows it and asks you to confirm instead.

When it's done it lands on the ground below where it started. If it has a
modem, it also tests the new GPS and prints the position it got.

**If something goes wrong** (it runs out of items, a modem won't attach, and so
on) it stops, says why, and flies back down to the ground. Fix the problem and
run the same command again (with `satellite` if you used it): it remembers where
it is, skips hosts that are already running and satellite blocks already in
place, and finishes the rest. It asks before continuing if you have fewer than
4 computers or modems (or satellite blocks), which is expected when some are
already built.

## Things to know

- **Range:** wireless modems reach further the higher they are. Near the top of
  the world that is close to the 384-block maximum. Turtles mining deep underground or far away can still
  be out of range. **Ender modems on the hosts give unlimited range** and are
  the best choice if you have them.
- **Chunk loading:** GPS only answers while the hosts' chunk is loaded, so build
  it near where you spend your time (your base). Far from it, positions come
  from the turtles' saved positions instead.
- **Build limit:** if you ask for a height the turtle can't reach (it needs 9
  blocks of room above the hosts, 14 with satellites), it builds as high as it
  can instead.
- **Satellites over plain hosts:** the satellite layout puts its hosts in
  different places, so running `gps-deploy satellite` where plain hosts already
  stand builds 4 new ones beside them. Break the old ones (they keep their
  program, being labelled) or leave them: extra hosts do no harm.
- **Mixing it up:** the turtle uses whichever accepted block it finds first for
  each part, so if you load two kinds of hull block you'll get a patchy hull.
