# instabuild

- **Type:** command computer (creative only), plus a modem to take buildings from the blueprint projector
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Places a whole plan from `/plans` in one go, for creative worlds: the sky
station's 21,166 blocks go in within seconds, with no turtles and no
materials. It uses the same plans as the
[blueprint projector](../blueprint-projector/README.md) and
[build control](../build-control/README.md), and the same coordinates as
build control: the building's north-west bottom corner, and which way it
faces. Or let the projector do the placing: run `instabuild serve`, move
the projection where you want it, and tap **Build** on the projector's
panel.

- It **never replaces a block**: a plan block only goes in where there's
  air. Where something's already there (ground, a tree, water, your own
  build) that block is left out, and it tells you how many it left out.
  Clear the spot first if you want the whole building.
- It keeps a list of every block it placed, so `instabuild undo` takes them
  out again (back to air), and only those.
- Typed in, it prints the box it will fill and asks before building.

It reads what's there and places the blocks a row at a time: a run of the
same block along a row goes in with one `fill`.

## Files

- `instabuild.lua`: the program
- `startup.lua`: fetches any newer version from the website on boot, and goes back to serving the projector if it was
- `plans/`: the plans it comes with (`cottage.json`, `watchtower.json`, `pagoda.lua`, `skystation.lua`, `atrium.lua`, `factory.lua`)
- [`lib/plan.lua`](../../lib/plan.lua): loads plans and places them in the world (copy to `/lib/plan.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files, for the undo list (copy to `/lib/files.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers, for `instabuild serve` (copy to `/lib/net.lua`). Needed.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Use

1. In a creative world, get a command computer:
   `/give @s computercraft:computer_command`. Place it anywhere: it can
   build anywhere that's loaded.
2. Install this on it. It comes with the cottage, watchtower, pagoda,
   sky station, atrium and factory; `install plan <name>` adds more.
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
instabuild serve                         -- place what the blueprint projector shows when Build is tapped on it
instabuild undo                          -- remove what the last build placed
```

## With the blueprint projector

The projector shows where a building will go; instabuild can place it
there for you.

1. Give the command computer a modem the projector can reach: a wireless
   or ender modem, or a wired modem on the same cable as the projector's
   computer. The projector needs one too.
2. Run `instabuild serve`. It waits, and keeps waiting after a reboot until
   you stop it.
3. On the projector, pick the plan and move and turn it into place, then
   tap **Build** (or press B). The plan goes in straight away, exactly
   where it's shown, with no question asked: tapping Build is the go-ahead.
   The projector's panel says what was placed.

While it serves, press **U** on the command computer to undo the last
build, or **Q** to stop serving. The plan doesn't need to be on the command
computer: the projector sends the whole building. With an instabuild
computer serving, the projector's Build goes to it instead of the builder
turtles; `set projector.instabuild false` on the projector sends it to the
turtles again.

## Things to know

- Command computers only work in creative, and need command blocks
  enabled (`enable-command-block=true` in `server.properties` on a server;
  always on in single player).
- The whole box must be loaded: stay within render distance of it. Blocks
  in unloaded chunks can't be read or placed; it says so.
- Since nothing is replaced, a building set into the ground (or into
  water) comes out with gaps where the ground was. Dig it out, or move it
  up a block.
- Plans say which block goes where but not which way it faces, so stairs,
  logs and doors go in facing their default way. A JSON plan can give a
  block's state in the legend, e.g. `"minecraft:oak_stairs[facing=east]"`;
  builder turtles can't use those, though.
- Undo only remembers the last build. Building again replaces it. Undo
  turns every block it placed back into air, even one you've changed since.
