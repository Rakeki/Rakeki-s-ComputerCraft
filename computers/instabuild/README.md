# instabuild

- **Type:** command computer (creative only)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Places a whole plan from `/plans` in one go, for creative worlds: the sky
station's 21,548 blocks go in within seconds, with no turtles and no
materials. It uses the same plans as the
[blueprint projector](../blueprint-projector/README.md) and
[build control](../build-control/README.md), and the same coordinates as
build control: the building's north-west bottom corner, and which way it
faces.

- Plans built on the ground clear their box first (everything in it
  becomes air), as builder turtles do. Plans built in the air, like the sky
  station, only place their own blocks.
- Chests, barrels, computers, turtles and other blocks that hold things are
  never replaced; it says how many it kept.
- Before placing anything it keeps a copy of every block it's about to
  change, so `instabuild undo` puts back exactly what was there.
- It prints the box it will fill and asks before building.

It reads what's there and places the blocks a row at a time: a run of the
same block along a row goes in with one `fill`.

## Files

- `instabuild.lua`: the program
- `startup.lua`: fetches any newer version from the website on boot
- `plans/`: the plans it comes with (`cottage.json`, `watchtower.json`, `pagoda.lua`, `skystation.lua`)
- [`lib/plan.lua`](../../lib/plan.lua): loads plans and places them in the world (copy to `/lib/plan.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files, for the undo copy (copy to `/lib/files.lua`). Needed.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Use

1. In a creative world, get a command computer:
   `/give @s computercraft:computer_command`. Place it anywhere: it can
   build anywhere that's loaded.
2. Install this on it. It comes with the cottage, watchtower, pagoda and
   sky station; `install plan <name>` adds more.
3. Pick the spot: the coordinates are the building's **north-west bottom
   corner** (its smallest X and Z, and the Y of its bottom layer). Press F3
   and look at the block to read them.
4. Run `instabuild <plan> <x> <y> <z>`, check the box it prints, and type
   `y`.

```
instabuild list                          -- the plans here, with their sizes
instabuild check skystation              -- size, and every block it uses
instabuild skystation 100 150 -40        -- north-west bottom corner at 100 150 -40, front facing north
instabuild cottage 20 64 -8 east         -- front facing east (north, east, south or west)
instabuild cottage here                  -- 2 blocks south of this computer, on its level
instabuild undo                          -- put back what the last build replaced
```

## Things to know

- Command computers only work in creative, and need command blocks
  enabled (`enable-command-block=true` in `server.properties` on a server;
  always on in single player).
- The whole box must be loaded: stay within render distance of it. Blocks
  in unloaded chunks can't be read or placed; it says so.
- Plans say which block goes where but not which way it faces, so stairs,
  logs and doors go in facing their default way. A JSON plan can give a
  block's state in the legend, e.g. `"minecraft:oak_stairs[facing=east]"`;
  builder turtles can't use those, though.
- Undo only remembers the last build. Building again replaces it.
