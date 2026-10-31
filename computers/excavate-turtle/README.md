# excavate-turtle

- **Type:** mining turtle, plus a wireless or ender modem for GPS and the [status server](../status-server/README.md)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Digs out a box-shaped hole and makes sure it's walled in and dry. It works on
its own; no server needed. GPS is optional but strongly recommended (see
[Staying on track](#staying-on-track)).

That's all it does: it builds nothing inside the hole. The inner walls, the
decorative walls and every detail inside are for a
[builder turtle](../builder-turtle/README.md) to build from a plan. The
[atrium](#atrium) is one such plan, made for a 60×60×30 hole.

Default size (`excavate` with no arguments): **21 wide × 21 long × 16 high**.
You can give any size.

**Walled in and dry.** After digging, the turtle walks the whole edge of the
hole: every block of the floor and ceiling and every block along the four
walls (and the deep shaft, if there is one). Wherever a cave, ravine, water or
lava has left a gap, it fills it with cobblestone, so the hole ends up with
solid walls, floor and ceiling all the way round. Standing in each edge block
clears any water in it too, and the floor goes last, so water that ran down
while the walls were still open is gone once the hole is shut in. While
digging it also turns any water or lava source blocks it finds above or below
it into cobblestone and digs them out.

It carries 3 stacks of cobblestone for patching from what it digs. If a big
cave needs more, it goes back to the start and asks for some. To skip sealing,
set `SEAL_WALLS = false` at the top of `excavate.lua`; it saves a few thousand
fuel, but then water and lava can get in.

## Files

- `excavate.lua`: the program. Settings (sealing, deep-mode depth, refuel level) are at the top.
- `startup.lua`: resumes an unfinished job after a reboot or chunk reload (first it fetches any newer version from the website)
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): reports progress to the status server (copy to `/lib/report.lua`). It works without a modem too, just without reporting.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed by lib/nav.lua.
- [`lib/inv.lua`](../../lib/inv.lua): inventory and fuel helpers (copy to `/lib/inv.lua`). Needed.

## Use

1. Place the turtle at floor level in one corner of the hole-to-be, facing
   along one edge. The hole extends **forward** and to the **right** of it.
2. Put a chest **directly behind** the turtle, with some coal in it. Loot goes
   in there too, and the junk (cobblestone, dirt and so on) gets dropped on the
   ground in front of the start.
3. **Fuel comes from the chest.** The turtle tops itself up to 5000 from the
   chest when it starts and whenever it's back to unload. That includes any
   coal it mined and dropped off itself, which goes back in the chest
   afterwards. The default hole takes about 6,000. If the chest runs dry, it
   waits at the start for you to add fuel to the chest or to the turtle.
4. Run:

   ```
   excavate                      -- 21x21x16 hole, digging up from the turtle
   excavate 30 40 12             -- 30 wide, 40 long, 12 high
   excavate 21 21 16 down        -- dig downwards instead (turtle at the top corner)
   excavate deep                 -- shaft down from the surface, hole floor 10 above bedrock
   excavate atrium               -- a 60x60x30 hole for the atrium plan (see Atrium)
   excavate atrium deep          -- the same, 10 above bedrock (down works too)
   excavate resume               -- carry on after stopping it
   excavate here                 -- no GPS: "I've put you back on your start block", then carry on
   excavate cancel               -- forget the current job
   ```

It digs the hole from the top down in 3-high layers, then seals it from the
top down, and finally returns to the start. If the chest fills up, or it runs
out of fuel or cobblestone, it waits at the start until you fix it.

A job started by an older version (the one with rooms, a ledge and stairs)
carries on as just the hole: if it was already past the hall, it goes straight
to sealing.

## Atrium

`excavate atrium` digs a hole 60 wide, 60 long and 30 high, with its walls,
floor and ceiling sealed. The [atrium plan](../../plans/atrium.lua) fills it,
using a [builder turtle](../builder-turtle/README.md) sent by
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
   It's a big dig: it prints the fuel it needs before it starts. With GPS
   it finishes by printing where to put the builder and the exact `build`
   command.
2. Put a builder turtle on the floor 29 blocks east and 7 south of the
   hole's north-west corner, facing south (into the atrium). Its supply
   chest goes behind it and its spoil chest to its left. Run
   `builder setup` on it. The plan never builds above that spot, so the
   turtle can always get home without digging through anything.
3. On build control, run `build atrium <x> <y> <z>`. The coordinates are
   the hole's north-west corner, on its floor.

Things to know:

- Use **one** builder (build control shares a plan between every free
  builder in range). The plan leaves a clear spot for only one home, and
  a builder with its home anywhere else digs its way there through the
  rock or the building.
- The plan only fits the 60×60×30 hole, so `excavate atrium` doesn't take
  sizes.
- The plan stops one block below the ceiling, because the builder stands
  on top of what it places. The walls and pillars end there too.
- Wheat needs farmland, which turtles can't place, so the garden has none.
  Swap some moss for dirt and till it by hand if you want crops.
- The stairs float: there's nothing under the steps, so you can walk under
  the high end.

## Example layouts

- **Default hole** (`excavate`): the empty 21×21×16 hole, walled in and
  ready for a builder turtle.
- **Atrium** (`excavate atrium`, then the atrium plan): the 60×60×30 hole,
  filled with a 24-wide atrium between two 17-wide wings on two floors (see
  [Atrium](#atrium)). The builder turtle sits on its clear spot at the north
  end, with its two chests.

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
can't be dug themselves, such as a spawner in the middle of the hole.

### Deep mode

`excavate deep` digs a 1×1 shaft straight down from the turtle. The hole is
dug **centred under the turtle**, so the shaft comes down through the exact
middle of the ceiling. Its floor is at Y −50, which is 10 above the top bedrock
layer (−60 in 1.18+). Change `BEDROCK_TOP` / `ABOVE_BEDROCK` at the top of
`excavate.lua` to adjust. The turtle gets its Y level from GPS, or asks you for it.
If you carry it up out of the shaft mid-job, with GPS it finds its way back to
the top of the shaft and continues. The shaft's walls are sealed too, so no
water runs down it into the hole.

The turtle's facing still sets which way the hole's walls run. The chest stays
at the surface behind the turtle, and every unload trip goes up and down the
shaft. Starting from Y 64, plan on roughly 10,000 fuel for the default size
(it takes it from the chest as it goes).

**Cover the shaft when you're not using it.** It's a straight drop of over
100 blocks into the middle of the hole.
