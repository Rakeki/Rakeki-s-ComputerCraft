# excavate-turtle

- **Type:** mining turtle, plus a wireless or ender modem for GPS and the [status server](../status-server/README.md)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Digs out an underground hall with two floors of rooms around it, then builds a
walkway ledge at the upper floor with stairs up to it. It works on its own; no
server needed. Or it digs one big empty box for the builder turtles to fill
with a pillared [atrium](#atrium) between two wings. GPS is optional but strongly recommended (see
[Staying on track](#staying-on-track)).

Default layout (`excavate` with no arguments), the same on all four sides:

- **Hall:** 21 wide × 21 long × 16 high
- **Lower rooms:** 12 rooms, 3 per wall, at floor level. Each is 5 wide × 10 deep × 6 high.
  Neighbouring rooms share a single-block wall, and the row is centred on the
  wall (2 blocks from each corner), so the middle room's door is in the exact
  centre. A 1-block wall separates each room from the hall, with a 1×3 doorway
  through it.
- **Upper rooms:** another 12 rooms directly above, floor 7 blocks up.
- **Ledge:** a 3-wide walkway around the hall walls at the upper floor. The
  upper rooms open onto it, and there are 6 blocks of headroom underneath.
- **Stairs:** a split staircase on every wall, 2 wide, just inside the ledge.
  From a landing at floor level in the middle of the wall, two flights of
  7 steps rise towards the corners. Where two flights meet in a corner, the
  steps merge so you can walk up from either side.

**You choose what the ledge and stairs are built from.** When the digging is
done, the turtle goes back to the start, empties into the chest, and asks:

```
Ready to build the ledge and stairs. What should I build them with?
  Slots 1-4: ledge blocks, 224 needed (have 0)
  Slots 5-8: stair blocks, 88 needed (have 0)
  Real stair blocks work: I'll face them up the stairs.
Fill the slots, then press Enter.
```

The slot numbers count across the turtle's inventory from the top left
(1–4 are the top row, 5–8 the second). Any full block works for the ledge.
Stair blocks are placed facing up each flight. The few steps that act as
landings (the top steps and the inside corners where flights meet) use the
ledge block. If your stairs come out facing backwards, set `STAIR_FLIP = true`
at the top of `excavate.lua`. To use different slots, change `LEDGE_SLOTS` /
`STAIR_SLOTS`.

**Solid walls.** After digging, the turtle walks the edge of the hall, every
room and every doorway. Wherever a cave, ravine, water or lava has left a gap in
a wall, floor or ceiling, it fills it with cobblestone. That includes the walls
between the hall and the rooms and between neighbouring rooms. It carries 3
stacks of cobblestone for this from what it digs. If a big cave needs more, it
goes back to the start and asks for some. While digging it also turns any water or lava source blocks
it finds above or below it into cobblestone and digs them out, so the space
ends up dry. To skip all this, set `SEAL_WALLS = false` at the top of
`excavate.lua`; it saves several thousand fuel.

It's only perfectly symmetric when the width and length are odd and the rooms
fit evenly. The default 21 does. The turtle warns you before starting if a
size you choose can't be.

## Files

- `excavate.lua`: the program. Room size, ledge width, floor height etc. are at the top.
- `startup.lua`: resumes an unfinished job after a reboot or chunk reload (first it fetches any newer version from the website)
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too, just without reporting.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

## Use

1. Place the turtle at floor level in one corner of the hall-to-be, facing
   along one edge. The hall extends **forward** and to the **right** of it.
2. Put a chest **directly behind** the turtle, with some coal in it. Loot goes
   in there too, and the junk (cobblestone, dirt and so on) gets dropped on the
   ground in front of the start.
3. **Fuel comes from the chest.** The turtle tops itself up to 5000 from the
   chest when it starts and whenever it's back to unload. That includes any
   coal it mined and dropped off itself, which goes back in the chest
   afterwards. A full job takes about 16,000. If the chest runs dry, it waits
   at the start for you to add fuel to the chest or to the turtle.
4. Run:

   ```
   excavate                      -- 21x21x16, digging up from the turtle
   excavate 21 21 16 down        -- dig downwards instead (turtle at the top corner)
   excavate deep                 -- shaft down from the surface, hall floor 10 above bedrock
   excavate atrium               -- an empty 60x60x30 box for the atrium plan (see Atrium)
   excavate atrium deep          -- the same, 10 above bedrock (down works too)
   excavate resume               -- carry on after stopping it
   excavate here                 -- no GPS: "I've put you back on your start block", then carry on
   excavate cancel               -- forget the current job
   ```

It digs the hall top-down, then each room (lower floor, then upper), then
patches any gaps in the walls, then builds the ledge and stairs, and finally
returns to the start. Height must be
at least 13 to fit both floors.

If the chest fills up, or it runs out of fuel or cobblestone, it waits at the
start until you fix it. Before building it also makes sure it has enough fuel
for the whole ledge and stairs, so it never has to fly home across a
half-built ledge.

## Atrium

`excavate atrium` digs one empty box, 60 wide, 60 long and 30 high: no
rooms, ledge or stairs, just the hall with its walls, floor and ceiling
sealed. The [atrium plan](../../plans/atrium.lua) fills it, using a
[builder turtle](../builder-turtle/README.md) sent by
[build control](../build-control/README.md). It's three rooms side by side
on two floors, mirror-symmetric both ways:

- **The atrium** in the middle, 24 wide and open to the ceiling. A spruce
  gallery runs round it at the second floor, on stripped spruce log
  pillars. Arches span the pillars under the gallery and under the ceiling
  beams, and shroomlights light the spans. A fence railing with lanterns
  runs along the gallery. Split stairs on both long sides rise from a
  landing in the middle to the gallery at each end. On the floor in the
  middle there's a moss garden of azaleas, bamboo and flowers round a pond
  with sugar cane.
- **Two wings**, 17 wide, one on each side, each with a full second floor
  on a row of log posts. Shroomlights are set into the floor, with lanterns
  on them.
- **Stone brick walls** between the wings and the atrium, with three
  doorways on each floor. The second-floor doorways open onto the gallery.

It needs 7,736 blocks: 3,384 stone bricks, 2,984 spruce planks, 748
stripped spruce logs, 112 spruce stairs, 112 spruce fences, 160 moss
blocks, 60 shroomlights, 28 lanterns, 16 water buckets and about 130
plants. `build check atrium` lists them all. To light it with something
other than shroomlights, change `LIGHT` at the top of `atrium.lua`.

1. Run `excavate atrium` (or `excavate atrium deep`) and let it finish.
   It's a big dig: it prints the fuel it needs before it starts (around
   65,000). With GPS it finishes by printing where to put the builder and
   the exact `build` command.
2. Put a builder turtle on the floor 29 blocks east and 7 south of the
   box's north-west corner, facing south (into the atrium). Its supply
   chest goes behind it and its spoil chest to its left. Run
   `builder setup` on it. The plan never builds above that spot, so the
   turtle can always get home without digging through anything.
3. On build control, run `build atrium <x> <y> <z>`. The coordinates are
   the box's north-west corner, on its floor.

Things to know:

- Use **one** builder (build control shares a plan between every free
  builder in range). The plan leaves a clear spot for only one home, and
  a builder with its home anywhere else digs its way there through the
  rock or the building.
- The plan only fits the 60×60×30 box, so `excavate atrium` doesn't take
  sizes.
- The plan stops one block below the ceiling, because the builder stands
  on top of what it places. The walls and pillars end there too.
- Wheat needs farmland, which turtles can't place, so the garden has none.
  Swap some moss for dirt and till it by hand if you want crops.
- The stairs float, as the excavator's do: there's nothing under the
  steps, so you can walk under the high end.

## Staying on track

**With GPS** (a GPS constellation in range when the job starts, and a modem on
the turtle), the turtle works in real world coordinates:

- **On start or resume:** every time it starts or resumes, including after a
  reboot, a chunk reload, or being picked up and put down, it checks its
  position and facing with GPS.
- **While working:** every 20 steps it compares where it thinks it is with what
  GPS says. If they differ, it re-checks and corrects itself.
- **Off its route:** if it finds itself somewhere it shouldn't be, for example
  carried up to the surface, it goes back to its start block and carries on
  with the job from there.

GPS has to be working when you **start** the job. A job started without GPS
keeps counting its own moves even if GPS appears later, because its
coordinates aren't real world coordinates. Underground, GPS may be out of range
(an ender modem helps). The turtle then keeps going on its own count and checks
again when GPS is back.

**Without GPS**, the turtle can't tell if it has been moved. When it resumes, it
waits 10 seconds first:

- **If you didn't move it,** do nothing and it carries on.
- **If you moved it,** press any key. Then put it back on its start block, facing
  the same way it faced when the job began, and run `excavate here`.

**If its route is blocked** (for example by a chest, spawner or other protected
block in the shaft), it stops and shows where it's stuck and why. It keeps
retrying until the way is clear. It no longer skips ahead, which used to make it
look stuck and then dig in the wrong place. The only spots it skips are ones that
can't be dug themselves, such as a spawner in the middle of the hall.

### Deep mode

`excavate deep` digs a 1×1 shaft straight down from the turtle. The hall is
built **centred under the turtle**, so the shaft comes down through the exact
middle of the ceiling. Its floor is at Y −50, which is 10 above the top bedrock
layer (−60 in 1.18+). Change `BEDROCK_TOP` / `ABOVE_BEDROCK` at the top of
`excavate.lua` to adjust. The turtle gets its Y level from GPS, or asks you for it.
If you carry it up out of the shaft mid-job, with GPS it finds its way back to
the top of the shaft and continues.

The turtle's facing still sets which way the hall's walls run. The chest stays
at the surface behind the turtle, and every unload trip goes up and down the
shaft. Starting from Y 64, plan on roughly 24,000 fuel (it takes it from the chest as it goes).

**Cover the shaft when you're not using it.** It's a straight drop of over
100 blocks into the middle of the hall.
