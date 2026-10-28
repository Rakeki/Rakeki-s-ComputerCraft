# blueprint-projector

- **Type:** advanced computer with a Spatial Projector from [CC: Spatial Projector](https://modrinth.com/mod/cc-spatial-projector), plus an advanced monitor for the controls
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** Spatial Projector (next to the computer or on a wired modem), advanced monitor (2×2 or bigger), optional wireless or ender modem for the [status server](../status-server/README.md), for following a [village turtle](#following-a-village-turtle) and for [having a turtle build it](#having-a-turtle-build-it)

## What it does

Loads a building plan and projects it into the world as glowing outlines, so
you can see what a building would look like before placing a single block.
Anyone wearing Spatial Goggles bound to the projector sees it; to everyone
else nothing is there, and the outlines never get in the way.

The monitor is the control panel. Tap the buttons to move the building
around, raise or lower it, and turn it to face another way, until it sits
where you want it. Then use it to build:

- **Whole** view shows the building, each material in its own colour.
- **Layer** view shows one layer at a time, block by block, with a white
  guide around that layer. Build it, tap **+**, and the next layer appears.
- **Outline** view shows only the box the building takes up: handy for
  checking it fits before looking at the details.
- **Build** hands it to a [builder turtle](../builder-turtle/README.md),
  which builds it right where it's shown. See
  [Having a turtle build it](#having-a-turtle-build-it).

Under the buttons, the monitor shows a top-down map of the current layer
(north is up) and how many of each block it needs, so you know what to bring.
In Whole view, the layer buttons choose how high to show the building (the
count covers every layer up to there).

The first time it runs, the building appears 2 blocks south of the
projector, sitting on the projector's level. Where it is, which way it faces,
the plan and the view are saved, so a reboot puts it straight back.

It comes with four plans, in the `/plans` folder: a **cottage** (7×7, 8
high), a **watchtower** (7×7, 11 high), a five-storey **pagoda** (31×32, 59
high, over 9,000 blocks) with balconies, upturned eaves and a gold spire,
and a **sky station** (63×63, 98 high, about 21,200 blocks) to hang in the
sky: four hollow rings round a core with a glass dome and a spire on top
and a spike below, with floors to walk round inside (see
[Building in the sky](#building-in-the-sky)). `install plans` lists the
plans on the website and `install plan <name>` adds one; your own go in
`/plans` too (see [Plans](#plans)). The same plans work with
[build control](../build-control/README.md), which sends a plan to the
builder turtles without a projector.

## Files

- `projector.lua`: the program: loads plans, works out the shapes and draws them. Tunables are at the top.
- `ui.lua`: the monitor control panel
- `plans/`: the plans it comes with (`cottage.json`, `watchtower.json`, `pagoda.lua`, `skystation.lua`); `install plan <name>` adds more
- `startup.lua`: starts the projector on boot and restarts it if it ever stops (first it fetches any newer version from the website)
- [`lib/report.lua`](../../lib/report.lua): optional, reports what it's showing to the status server (copy to `/lib/report.lua`)
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed.
- [`lib/plan.lua`](../../lib/plan.lua): loads plans and places them in the world (copy to `/lib/plan.lua`). Needed.
- [`lib/crew.lua`](../../lib/crew.lua): hands the plan to the builder turtles and follows them (copy to `/lib/crew.lua`). Needed.

## Setup

1. Place an advanced computer with a Spatial Projector next to it (or connect
   the projector with a wired modem), and an advanced monitor touching the
   computer.
2. Right-click the projector with Spatial Goggles to bind them, and wear them.
3. Install and reboot. The cottage appears south of the projector.
4. Tap **▶** on the monitor to switch plans, then move it into place.

```
projector                  -- show the last plan (startup does this)
projector pagoda           -- show a plan: /plans/<name>.json or .lua
projector disk/house.lua   -- show a plan file from anywhere
projector village          -- follow what a village turtle is building
projector build            -- have the free builder turtles build the plan where it's shown
projector list             -- every plan, with its size
projector check house      -- load a plan and list its size and blocks
projector clear            -- remove the projection (Ctrl+T first to stop it)
```

### The control panel

| Button | What it does |
|---|---|
| **◀ ▶** (top) | previous / next plan |
| **N S W E** | move the building north, south, west or east |
| **Step** | how far each tap moves it: 1, 5 or 16 blocks |
| **Up Down** | raise or lower it |
| **Turn ← →** | turn it a quarter turn about its middle |
| **View** | Whole, Layer or Outline |
| **Layer − +** | the layer to build (Layer view) or how high to show it (Whole view) |
| **Here** | put it back next to the projector |
| **Hide / Show** | take the projection down or put it back |
| **Build / Stop** | have a [builder turtle](../builder-turtle/README.md) build it here, or stop it |

Without a monitor, the panel shows on the computer's screen: click instead of
tap. A monitor added (or removed) while it runs is picked up straight away. The keyboard works too: arrows move, PgUp/PgDn raise and lower, Q/E
turn, `[` `]` change layer, V view, S step, N/P plan, H hide, Home here,
B build.

## Having a turtle build it

With a [builder turtle](../builder-turtle/README.md) set up nearby, tap
**Build** and it builds the building exactly where the projection is. Both
need a wireless or ender modem.

- The projector asks every builder turtle in range whether it's free, and
  shares the building between the free ones (up to 4): each gets a strip of
  it, side by side across the longer side, at least 3 blocks wide. With one
  free turtle it builds the whole thing. The panel says who took it, or why
  none did (none in range, or all busy).
- A strip nobody could take waits for the first turtle to come free (one
  finishing its own strip, or a new one: the projector looks every 30
  seconds).
- While they build, the panel shows how far they've got ("Builder #7:
  building, 340 of 1200 (28%)", or with a few, "3 builders: 900 of 2400
  (37%)"), and in **Layer** view the projection follows the lowest layer
  being built, so you can watch the next layer appear.
- The building can't be moved, turned or swapped for another plan while it's
  being built. Tap **Stop** to call the turtles off; they go home. If one
  never answers (broken, or its chunk unloaded), tap Stop again to give up
  on it.
- When it's done the panel says so, with how many blocks they couldn't place,
  if any. A restart of the projector keeps track: it asks each turtle where
  it's got to.

### Building in the sky

The **sky station** (`projector skystation`) is meant to float. Set **Step**
to 16 and tap **Up** until it's as high as you want it (Outline view shows
its box), then tap **Build**. The builders fly over the top of it, so keep
its bottom no higher than about Y 215 (the station is 98 high, and the
build limit is Y 319).

- Plans built in the air say so (`clear = false`, see [Plans](#plans)), so
  the builders don't dig out the box first: that would mean flying through
  every empty block of it. They go straight to building, bottom layer
  first, placing each block from the one above it, so nothing needs
  holding up.
- It's about 21,200 blocks, mostly concrete (white, gray, light gray, black
  and red), smooth stone for the floors, glass, light blue stained glass,
  sea lanterns and a little iron. `projector check skystation` lists them.
  A [Creative Crate turtle](../crate-turtle/README.md) with `crate stock`
  keeps the storage system supplied.
- Use four builders: with one, it's a long job. The whole thing is too big
  for the projector to outline every block in its colours, so Whole view
  shows it in one colour or only part of it; Layer view shows each layer in
  full.
- Turtles stop when their chunk unloads, so stay nearby while they work.

## Following a village turtle

`projector village` shows the building a [village turtle](../village-turtle/README.md#seeing-it-with-a-projector)
is working on, right where it's building it. Both need a wireless or ender
modem, and they must be in range of each other.

- The projection appears as soon as the turtle picks a building, so you can
  see it on its plot while the turtle is still gathering materials or
  clearing the ground. When the turtle moves on, so does the projection.
- In **Layer** view it shows the layer the turtle is building and keeps up as
  it climbs. **Whole** and **Outline** work as usual.
- With GPS on the turtle, the building goes exactly where it's being built
  and the move and turn buttons are switched off. Without GPS it appears next
  to the projector and you can move it into place yourself.
- The monitor says what the turtle is doing: getting materials, clearing,
  building (with how far along), or paving the street.
- Once heard, the village shows up among the plans (**◀ ▶**) and is
  remembered after a reboot. If no turtle has been heard yet,
  `projector village` waits for one.

## Plans

A plan is a file in `/plans/` named after it: `/plans/house.json` (or
`house.lua`) is `projector house`. Every plan there appears on the monitor.

### Getting plans

`install plans` lists the plans on the website, and `install plan <name>`
puts one in `/plans` (they update on boot like programs). Your own: write
it on your PC and drag the file onto the computer's screen, or
`wget <url> plans/house.json`, or `edit plans/house.json`. Run
`projector check house` to see that it loads and what it needs. Give your
own plans names of their own: `install update` puts the plans that came
with the projector back as they were.

### Writing one (JSON)

Draw each layer from above, bottom layer first, one character per block:

```json
{
  "name": "Gatehouse",
  "legend": {
    "C": "minecraft:cobblestone",
    "P": "minecraft:oak_planks",
    "G": ["minecraft:glass", "#99ddff"]
  },
  "layers": [
    ["CCCCC",
     "C...C",
     "CCCCC"],
    ["PPGPP",
     "P...P",
     "PPPPP"]
  ]
}
```

- `.` and spaces are air. Every other character needs a legend entry.
- The first row of a layer is the front: it faces north until you turn it.
  Each row runs west to east, and later rows are further south.
- `name` is what the monitor shows. A colour after a block (`"#99ddff"`)
  is only for the projection, and is picked from the block name (oak,
  spruce, stone, glass, white wool...) when left out.
- Instead of `legend` and `layers`, a plan can list its blocks:
  `"blocks": [[0, 0, 0, "minecraft:stone"], [1, 0, 0, "minecraft:glass"]]`
  (x east, y up, z south), which suits plans made by a tool.
- `"clear": false` says the plan is built in the air, so builder turtles
  don't dig out its box first (the sky station has it). Leave it out for
  anything built on the ground.

`plans/cottage.json` and `plans/watchtower.json` are examples.

### Plans made by code (Lua)

A `.lua` plan returns the same table, so a loop can make one: handy for
big or round buildings that would be huge as JSON. `plans/pagoda.lua` and
`plans/skystation.lua` are made that way:

```lua
local plan = { name = "Pillar", blocks = {} }
for y = 0, 9 do
  plan.blocks[#plan.blocks + 1] = { 0, y, 0, "minecraft:quartz_pillar" }
end
return plan
```

## Things to know

- Plans are shown as outlines, not solid blocks. Neighbouring blocks of the
  same material are joined into one bigger box, so a wall shows as one
  outline in Whole view; Layer view outlines every block on its own.
- A projector holds up to 1,024 shapes. A building too big for that is shown
  in a single colour, and if it still doesn't fit, only part of it is shown;
  the monitor says so in orange. Layer view almost always fits.
- After you tap a button, the outline moves at once and the rest of the
  building follows a moment after you stop tapping. A big building takes a
  few seconds to redraw.
- The projection disappears when its chunk unloads and comes back when the
  computer starts again. Wearing the goggles is the only way to see it.
- Every plan in `/plans/` appears on the monitor. One that has a mistake is
  skipped; `projector list` shows what's wrong with it.
