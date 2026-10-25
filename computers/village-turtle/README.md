# village-turtle

- **Type:** mining turtle (pickaxe), plus a wireless or ender modem for GPS, the [status server](../status-server/README.md) and the [projector](../blueprint-projector/README.md#following-a-village-turtle)
- **Computer ID:** 
- **Label:** 
- **Location:** 

## What it does

Builds a themed village and keeps growing it for as long as it runs. You pick
a theme when it starts. First it builds its **depot** round itself (see
[The depot](#the-depot)), then it works outward from where you placed it, one
plot at a time:

1. **Survey** the plot: drop onto 25 spots across it (a 5×5 grid, 3 blocks
   apart) and note the ground height, water, trees and anything already built.
2. **Choose** a building that suits the ground (see [Terrain](#terrain)).
3. **Clear** trees and high ground above floor level, then **build** layer by
   layer from the bottom up. Holes under the floor (dips, ponds) are filled
   with dirt or stone first.
4. **Pave** a path from the door to the street, and the street back to the
   plaza, with curbs, lamps and stairs on slopes (see [Roads](#roads)).
5. Move on to the next plot.

Previews of every building in each theme (rendered from the real blueprints):
[medieval](preview/medieval.svg), [desert](preview/desert.svg),
[nordic](preview/nordic.svg), [japanese](preview/japanese.svg), and
[the depot in each theme](preview/depot.svg).

A 12-building village it built in the simulator, on test terrain with a lake,
a hill and a cliff, in 3D for each theme:
[medieval](preview/example-medieval.svg), [desert](preview/example-desert.svg),
[nordic](preview/example-nordic.svg), [japanese](preview/example-japanese.svg),
and [as a plan](preview/village-plan.svg).

### Layout

The village is a grid of 13×13 plots with 5-wide streets between them (18
blocks from plot centre to plot centre). The middle plot is the **plaza**:
the depot round home (where the turtle starts, with the chests), a well in
front of it, and streets round all four sides. The turtle builds the depot
and then the rest of the plaza first, then the plots ring by ring outward, out to the radius you give it (default 48 blocks,
about 21 plots). Every building faces the plaza. Its street runs along the
plaza-facing side of its plot and joins up with the streets already built.

### The depot

The very first thing the turtle builds is a small hut round its home block
and both chests, so it isn't left standing half way into the plaza. It's
5×5 and 3 high in the theme's blocks, with windows, lanterns on the roof
corners and a door on the turtle's right for you to get to the chests
(desert depots have an open doorway). The roof has a one-block hole straight
above the home block: the turtle flies in and out through it, so its trips
home work just as before. It needs about 82 blocks, for example in medieval:
31 spruce planks, 27 cobblestone, 8 oak logs, 8 oak planks, 4 lanterns, 3
glass panes and an oak door. Like any building it waits for the blocks, and
you can press **S** to skip it.

Villages started before the depot existed carry on without one (their well
is a block closer to home, where the depot would go).

### Roads

- **Main roads:** the four streets along the sides of the plaza, and their
  continuations out to the edge of the village, are paved all 5 blocks wide
  in a finer block (stone bricks for medieval), with a lamp post on both
  sides every 6 blocks. Streets out to new buildings join them by the
  shortest way, so they become the village's high streets.
- **Side streets:** a 3-wide road with a curb on each side, and a lamp post
  on alternate curbs every 6 blocks. Crossroads are paved all the way across.
- **Door paths:** a 1-wide path from each door out to its street.
- **Slopes:** before paving each stretch, the turtle walks its centre line
  to measure the ground. It then picks heights for the whole width that never
  change by more than one block per block, and puts a stair on every step,
  so every street can be walked without jumping. Where the ground is steeper,
  it cuts into the high side and builds up the low side about equally, so a
  cliff becomes a ramp centred on its edge. Cuttings are dug open to the sky
  (up to 8 deep), and dips are filled with dirt and stone from the spoil
  chest (up to 8 deep). Water is bridged with deck planks.
- **Joins:** a new street matches the height of any street already at its
  crossroads, and never digs into existing roads, stairs or lamps.
- Road blocks don't fall (no sand or gravel), so a road over a cave stays put.

| Theme | Main road | Side street | Curb | Steps |
|---|---|---|---|---|
| Medieval | stone bricks | coarse dirt | cobblestone | cobblestone stairs |
| Desert | smooth sandstone | sandstone | cut sandstone | sandstone stairs |
| Nordic | stone bricks | cobblestone | mossy cobblestone | cobblestone stairs |
| Japanese | polished andesite | packed mud | stone bricks | stone brick stairs |

Lamps are two fence posts with a lantern on top.

When every plot within the radius is done (built or skipped), the turtle goes
home and stops. `village grow 80` lets it carry on further out.

### Themes

| Theme | Look | Buildings |
|---|---|---|
| Medieval | timber frame on cobble, spruce gable roofs, chimneys | cottage, town house, tavern, watchtower, farm, market stall, dock |
| Desert | sandstone, flat roofs with parapets and beams, open doorways | adobe house, courtyard house, caravanserai, lookout, oasis farm, bazaar stall, jetty |
| Nordic | spruce and cobble, steep dark-oak roofs | hut, longhouse, mead hall, watchtower, farm, trading post, boathouse pier |
| Japanese | dark wood frame, birch walls, deepslate-tile hip roofs with upturned corners | machiya, minka, tea house, pagoda, field, market stall, pier |

The blocks for each theme are listed in `village_themes.lua`. Change any of
them to suit what you have; set one to `false` to leave it out.

Buildings and their size (medieval block counts; other themes are similar):

| Building | Footprint | Blocks | Inside |
|---|---|---|---|
| cottage | 7×9 (9×11 with eaves) | 320 | bed, crafting table, barrel, 2 lanterns |
| town house | 9×11 | 489 | 2 beds, crafting table, barrel, lanterns |
| tavern | 11×11 | 588 | barrel counter, crafting tables, 6 lanterns |
| watchtower | 7×7, 13 high | 384 | spiral stair up to a lookout with battlements |
| farm | 11×11 | 166 | fenced 9×9 dirt field around one water block (keeps all of it hydrated) |
| market stall | 7×7 | 122 | counter, shelves, striped canopy |
| dock | 5×13 | 106 | pier on log posts, rails, lanterns |
| well (plaza) | 5×5 | 92 | |

The farm is left as dirt: till and plant it yourself (a turtle can't make
farmland without a hoe).

### Terrain

| Plot | What it gets |
|---|---|
| **Flat** (height range ≤ 2) | houses, town houses, tavern, farm, market stall |
| **Slope** (range 3–5) | watchtower (most likely) or cottage, levelled: high ground cut away, low ground filled |
| **Hilltop** (4+ blocks above home) | towers much more likely |
| **Wooded** (6+ tree spots) | trees are cleared; a cottage becomes more likely |
| **Shore** (30%+ water, some land) | dock, running from the land out over the water |
| **Steep** (range > 5), **open water**, lava, deep holes | skipped |
| **Already built on** (planks, bricks, glass, chests, other turtles…) | skipped, so your own builds are safe |

The range ignores the single highest and lowest spot, so one boulder doesn't
rule out a plot. Taverns, towers, farms and stalls are kept in proportion
(e.g. one tavern per 10 buildings, about one farm per two houses). The choice
is random beyond that.

## Files

Copy these to the turtle:

- `village.lua`: the program. Plot size, terrain limits etc. are at the top.
- `village_themes.lua`: the themes and their blocks
- `village_blueprints.lua`: the buildings
- `startup.lua`: resumes after a reboot or chunk reload
- [`lib/nav.lua`](../../lib/nav.lua): movement and position tracking (copy to `/lib/nav.lua`)
- [`lib/report.lua`](../../lib/report.lua): status server reporting (copy to `/lib/report.lua`); does nothing without a modem
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`).
- [`lib/claim.lua`](../../lib/claim.lua): tells the storage computer which chest is the supply chest (copy to `/lib/claim.lua`)

`preview/` is just the pictures; it doesn't go on the turtle.

## Setting up

1. Pick the village centre: fairly flat open ground. Stand the turtle on it,
   facing the way you want the village's "forward" to be.
2. Put the **supply chest** directly **behind** the turtle (a double chest is
   best) and the **spoil chest** directly to its **left**.
3. Fill the supply chest with the theme's blocks and some coal. Run
   `village list medieval` (or another theme) to see what each building needs.
   The first order is the depot (about 82 blocks), then the plaza, the
   biggest: the well (92 blocks) plus its four stretches of main road: about
   380 stone bricks, 32 fences and 16 lanterns for medieval, and some
   cobblestone stairs if the ground slopes.
4. Run `village`. Pick a theme, give a radius (Enter for 48), and press Enter.

### Materials

- Before each building, the turtle checks that the **supply and spoil
  chests together hold everything** for it and its street (plus the
  [storage system](#getting-blocks-from-the-storage-system), if it has one). If not, it waits
  at home showing what's missing (also on the status server, e.g. `needs 87
  oak_planks, 70 spruce_stairs, ...`). Top up the chest and it carries on by
  itself within 10 seconds. Press **S** to skip that building and pick
  another for the plot.
- It carries about 12 stacks at a time and comes home to reload as it goes.
- Everything it digs up goes into the **spoil chest**. Dirt and stone from
  there get used again to fill holes under floors. Logs from cleared trees
  end up there too. If the spoil chest is full, it throws the extra away, so
  empty it now and then.
- Water buckets come back empty and go back in the supply chest.

### Getting blocks from the storage system

Optional. With a [storage computer](../storage-computer/README.md) the turtle
doesn't need everything in its supply chest up front. It still needs the
supply and spoil chests at home: the storage sends its blocks to the supply
chest, and the turtle takes them from there.

1. Connect the village's **supply chest** to the storage system's wired
   network (a full-block wired modem touching the chest, and networking cable
   back to the storage; cable can run as far as you like). Right-click the
   modem so it turns red.
2. Give both the turtle and the storage computer a wireless modem.

There's nothing to pick on the storage computer: the first time the turtle
orders something, it tells the storage computer which chest is its supply
chest ("The storage system sends my blocks to the supply chest (...)").
Several villages can share one storage system, each with its own supply
chest.

Then, when it checks the materials for a building, whatever the storage
system holds counts as well. Each time the turtle loads up for the next
stretch, it asks the storage system to send what's missing to the supply
chest, then takes it. When it's low on fuel it asks for coal the same way
(or charcoal, or coal blocks, if that's what the storage has). If the storage
system runs short too, the turtle waits as usual and asks again every 10
seconds.

If nothing arrives, the turtle's screen says why: it has no wireless modem
itself, no storage system answered (check the storage computer's wireless
modem and that it's within about 64 blocks, or use ender modems), it can't
find the supply chest (no wired modem on it, or the modem isn't red;
it tries again 5 minutes later), it has
none of that item, or the supply chest is full. Running `storage test` on the
storage computer checks its side.

The storage system keeps the supply chest clear apart from what the turtle
has asked for: leftovers and empty buckets go back into storage. So put
blocks and coal into the storage system's input chest rather than the supply
chest (anything put in the supply chest just gets moved into storage, and
comes back when the turtle asks for it).

With a [crafting turtle](../crafter-turtle/README.md) on the storage system,
blocks that aren't stored but can be crafted from what is (fences from logs,
slabs from smooth sandstone, lanterns from iron and coal...) count as
available too. While it waits for a building's materials it asks the storage
system to start crafting what's short, and its screen says what's being made
(or why it can't be, such as no crafter chest set, or only enough to make
some). If the crafting turtle is off, it says crafting is stuck, and carries
on by itself once it's back.

To turn this off, set `USE_STORAGE = false` at the top of `village.lua`.

Example: a medieval cottage is 87 spruce_stairs, 66 oak_planks, 60
cobblestone, 35 spruce_planks, 24 oak_log, 22 stripped_oak_log, 11
spruce_slab, 9 glass_pane, 2 lantern, a crafting table, barrel, red bed and
oak door. Each new stretch of side street adds 69 coarse dirt, 26
cobblestone, 4 fences and 2 lanterns (`village list` shows these per theme).

### Fuel

About 1,900 fuel per building, including streets and trips home (about 24
coal). It takes coal, charcoal, coal blocks, blaze rods, dried kelp blocks or
lava buckets from the supply chest whenever it's home and running low. If
there's none, it waits.

## Staying on track

- **Reboots and chunk unloads:** progress (the village plan, the plot it's
  on, the stage and the exact block) is saved after every block, and
  `startup.lua` picks it up again. In the simulator it was rebooted 8 times at
  random points (mid-flight, mid-build, mid-street) and built exactly the
  same village as without reboots.
- **GPS:** with GPS available when the village starts, the turtle checks its
  position against GPS on every resume and every 25 blocks. If it's been
  moved, it recalibrates and heads home before carrying on. Without GPS it
  trusts its own count and gives you 10 seconds on resume to say it was moved
  (then put it back on its home block facing forward and run `village here`).
- **Never digs** chests, barrels, furnaces, hoppers, spawners or anything from
  ComputerCraft (via `lib/nav.lua`). Between plots it flies above everything
  it has built, and never digs sideways on the way: it goes over whatever's
  in front of it.

## Building with a crew

More village turtles can help build one village. Each helper builds whole
plots (building, door path and street) while the first turtle, the
**lead**, keeps the village's map and hands out the plots, so a village
goes up several plots at a time.

Every turtle in the crew needs **GPS** (they share the village's
coordinates through it; see the [GPS deployer](../gps-deployer/README.md))
and a wireless or ender modem. The lead must have had GPS when its village
started.

1. Start the village with one turtle as usual (`village`). That's the lead.
2. Put each helper somewhere near the village with **its own supply chest
   behind it and spoil chest on its left**, stocked like the lead's (or
   with a wired modem on the supply chest, on the
   [storage system's](../storage-computer/README.md) cable).
3. On each helper, run `village join`. It finds the lead, says "Joined
   turtle #7's Medieval village", and starts on the next free plot. With more
   than one village around, name the lead: `village join 7`.

What to expect:

- The lead builds the depot and plaza first, as always; helpers start on
  the plots around it straight away.
- Each turtle flies between plots at a height of its own, so they don't meet
  in the air.
- A helper tells the lead what it built when it finishes a plot, then asks
  for the next. If the lead can't be reached it keeps trying every 30
  seconds, and says so.
- A helper that goes quiet for 30 minutes (broken, or its chunk unloaded)
  loses its plot: the lead gives it to someone else.
- When no plots are left, the lead waits at home for the crew to finish
  theirs, then says the village is done. `village grow` on the lead gives
  everyone more plots.
- Reboots are fine: helpers resume their plot, and their reports wait until
  the lead is back.

## Seeing it with a projector

Optional. With a wireless or ender modem, the turtle shares the building it's
working on, so a [blueprint projector](../blueprint-projector/README.md#following-a-village-turtle)
running `projector village` can show it in the world as glowing outlines
(with a crew, it shows whichever turtle last picked a building):
you can see the whole building on its plot while the turtle is still
fetching materials or clearing the ground. In Layer view the projection
follows the layer the turtle is building. It moves on to the next building
as soon as the turtle picks one.

The turtle needs GPS for the projection to land exactly on the plot. Without
GPS the building shows next to the projector instead, and you can move it
into place by hand.

To turn sharing off, set `SHARE_PLAN = false` at the top of `village.lua`.

## Commands

- `village`: start a new village here
- `village resume`: carry on (`startup.lua` does this)
- `village here`: you put the turtle back on its home block, facing forward; reset its position
- `village grow <radius>`: let a finished village grow further out
- `village list [theme]`: blocks each building needs
- `village status`: what's built so far
- `village cancel`: forget the village (the buildings stay)
- `village join [lead id]`: help another village turtle build its village, from this turtle's own chests (needs GPS; see [Building with a crew](#building-with-a-crew))

## Things to know

- **Stairs facing:** roof and tower stairs are placed with the turtle facing
  the way they should climb. If they come out backwards on your server, set
  `STAIR_FLIP = true` at the top of `village.lua`.
- **Streets on very steep ground:** cuttings and fills stop at 8 blocks, so a
  street up a cliff higher than about 16 blocks still ends in a step. Where two
  sloping streets cross on a hillside, a corner of the crossroads can end up
  2 blocks off (4 cells out of about 1,250 in the simulator test).
- **Lamps** stand on the curbs. Where a curb cell has a lamp, the stair for a
  step goes on the road lanes only.
- **Doors** are placed from inside the building. Desert houses have open doorways.
- **Moving items out of the chest:** the turtle uses the chest's own
  inventory functions (`list`, `pushItems`) to bring what it needs to the
  front before taking it. That works with vanilla chests, barrels and most
  modded chests. If they're missing it falls back to taking stacks one by one,
  which only reaches the first dozen or so stacks.
- **Tested in a simulator only**, not yet in-game: all four themes, varied
  terrain, material shortages, reboots and GPS. Watch the first building or two.
