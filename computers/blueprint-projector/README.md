# blueprint-projector

- **Type:** advanced computer with a Spatial Projector from [CC: Spatial Projector](https://modrinth.com/mod/cc-spatial-projector), plus an advanced monitor for the controls
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** Spatial Projector (next to the computer or on a wired modem), advanced monitor (2×2 or bigger), optional wireless or ender modem for the [status server](../status-server/README.md)

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

Under the buttons, the monitor shows a top-down map of the current layer
(north is up) and how many of each block it needs, so you know what to bring.
In Whole view, the layer buttons choose how high to show the building (the
count covers every layer up to there).

The first time it runs, the building appears 2 blocks south of the
projector, sitting on the projector's level. Where it is, which way it faces,
the plan and the view are saved, so a reboot puts it straight back.

Two plans come built in: a **cottage** (7×7, 8 high) and a **watchtower**
(7×7, 11 high). Your own plans go in the `/plans` folder (see
[Plans](#plans)).

## Files

- `projector.lua`: the program: loads plans, works out the shapes and draws them. Tunables are at the top.
- `ui.lua`: the monitor control panel
- `sample_plans.lua`: the built-in plans, and examples of the plan format
- `startup.lua`: starts the projector on boot and restarts it if it ever stops
- [`lib/report.lua`](../../lib/report.lua): optional, reports what it's showing to the status server (copy to `/lib/report.lua`)

## Setup

1. Place an advanced computer with a Spatial Projector next to it (or connect
   the projector with a wired modem), and an advanced monitor touching the
   computer.
2. Right-click the projector with Spatial Goggles to bind them, and wear them.
3. Install and reboot. The cottage appears south of the projector.
4. Tap **▶** on the monitor to switch plans, then move it into place.

```
projector                  -- show the last plan (startup does this)
projector watchtower       -- show a plan: built in, or /plans/<name>.lua
projector disk/house.lua   -- show a plan file from anywhere
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

Without a monitor, the panel shows on the computer's screen: click instead of
tap. The keyboard works too: arrows move, PgUp/PgDn raise and lower, Q/E
turn, `[` `]` change layer, V view, S step, N/P plan, H hide, Home here.

## Plans

A plan is a Lua file in `/plans/` named after the plan (`/plans/house.lua` is
`projector house`). Draw each layer from above, bottom layer first, one
character per block:

```lua
return {
  name = "Gatehouse",                    -- shown on the monitor
  legend = {
    C = "minecraft:cobblestone",
    P = "minecraft:oak_planks",
    G = { "minecraft:glass", 0x99ddff },  -- optional colour for the projection
  },
  layers = {
    { "CCCCC",                           -- layer 1, the ground floor
      "C...C",                           -- the first row is the front:
      "CCCCC" },                         -- it faces north until you turn it
    { "PPGPP",
      "P...P",
      "PPPPP" },
  },
}
```

- `.` and spaces are air. Every other character needs a legend entry.
- Each row runs west to east, and later rows are further south.
- Colours are picked from the block name (oak, spruce, stone, glass, white
  wool...), so most plans don't need any.
- Instead of `layers`, a plan can list blocks:
  `blocks = { { x, y, z, "minecraft:stone" }, ... }`. A plan is a Lua
  program, so a loop can make one: the watchtower in `sample_plans.lua` is
  built that way.

Getting a plan onto the computer: `edit plans/house.lua` and type it in, or
write it on your PC and use `wget <url> plans/house.lua`,
`pastebin get <code> plans/house.lua`, or drag the file onto the computer's
screen. Run `projector check house` to see that it loads and what it needs.

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
