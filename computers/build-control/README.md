# build-control

- **Type:** any computer or pocket computer, with a wireless or ender modem
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Sends a building plan to the [builder turtles](../builder-turtle/README.md)
at coordinates you type, no [blueprint projector](../blueprint-projector/README.md)
needed. From a pocket computer, `build skystation 100 150 -40` puts the
sky station's north-west bottom corner at 100, 150, -40 and the builders get
to work.

It works the same way as the projector's **Build** button: the builder
turtles that are free (up to 4) each take a strip of the building, side by
side across its longer side, and build it bottom layer up. A strip nobody
could take waits for the next builder that comes free. While they work it
shows how far they've got, one line whenever it changes:

```
4 builders: 5210 of 21548 (24%)
```

Before anything is sent it prints the box the building will fill and asks
you to say yes, because builders dig out everything in that box first
(unless the plan is built in the air, like the sky station).

Plans are files in `/plans`: the [same plans](../blueprint-projector/README.md#plans)
the projector uses. It comes with the cottage, watchtower, pagoda and sky
station; `install plans` lists the rest on the website, `install plan <name>`
adds one, and your own JSON or Lua plans go in `/plans` too.

## Files

- `build.lua`: the program
- `startup.lua`: after a reboot, carries on following a building that's still going up, so waiting strips still get handed out (first it fetches any newer version from the website)
- `plans/`: the plans it comes with (`cottage.json`, `watchtower.json`, `pagoda.lua`, `skystation.lua`)
- [`lib/plan.lua`](../../lib/plan.lua): loads plans and places them in the world (copy to `/lib/plan.lua`). Needed.
- [`lib/crew.lua`](../../lib/crew.lua): hands the building to the builder turtles and follows them (copy to `/lib/crew.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Use

1. Set up the builder turtles first, each on its home block with its supply
   and spoil chests ([builder setup](../builder-turtle/README.md#setup)).
2. Install this on a computer or pocket computer with a wireless or ender
   modem, within range of the builders.
3. Pick the spot: the coordinates are the building's **north-west bottom
   corner** (its smallest X and Z, and the Y of its bottom layer). Press F3
   and look at the block to read them. `build check <plan>` says how big it
   is.
4. Run `build <plan> <x> <y> <z>`, check the box it prints, and type `y`.

```
build list                          -- the plans here, with their sizes
build check skystation              -- size, and every block it needs
build skystation 100 150 -40        -- north-west bottom corner at 100 150 -40, front facing north
build cottage 20 64 -8 east         -- front facing east (north, east, south or west)
build cottage here                  -- at this computer's position (needs GPS)
build watch                         -- follow the builders again (after Ctrl+T)
build stop                          -- call them off; again to give up on ones that don't answer
```

"Facing" is the way the plan's front (its first row) faces. Turning it
keeps the north-west corner where you said, so the building grows south and
east from there whichever way it faces.

## Things to know

- Ctrl+T stops following, not building: the turtles carry on. `build
  watch`, or a reboot, picks it up again; it needs to be running for strips
  that are still waiting to be handed out.
- Only one building at a time from one computer. `build stop` first to send
  another.
- The builders report how far they've got to whoever sent the building, so
  follow it from the computer that started it.
- Builders take strips only when they're free: to have four share a
  building, set them all up before you run `build`.
- In creative, [instabuild](../instabuild/README.md) places a plan at the
  same coordinates in seconds from a command computer, and undoes it: handy
  for trying a spot before the turtles build it.
