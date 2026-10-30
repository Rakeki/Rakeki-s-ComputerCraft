# essence-computer

- **Type:** advanced computer (colour and mouse; a plain one works with the keyboard), plus a wired modem on the storage network
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem joined to the [storage system's](../storage-computer/README.md) network; each Hopper Botany Pot standing on a full-block wired modem on that network

## What it does

Turns a farm of [Mystical Agriculture](https://www.curseforge.com/minecraft/mc-mods/mystical-agriculture)
crops growing in [Botany Pots](https://www.curseforge.com/minecraft/mc-mods/botany-pots)
into whatever their essence crafts into: iron ingots, dirt, diamonds and so on.

Every 10 seconds it empties each Hopper Botany Pot on the network into the
storage system's input chest, so the essence (and any spare seeds) ends up
in [storage](../storage-computer/README.md). A pot whose harvest slots fill
up stops growing, so this keeps them all going. The seed and soil are never
touched: a pot doesn't even show them to a computer.

The **Recipes** tab is the lookup. It lists every recipe that uses essence
with what it makes, what it takes, how many you can make from what's stored
and how many are stored now. With nothing typed it shows only what you have
enough essence for; type part of a name (`iron`, `dirt`, `ingot`) to find
any recipe, even ones you can't make yet. Pick a recipe, set how many crafts
you want and press **Order**: the storage system's
[crafting turtle](../crafter-turtle/README.md) makes them, and they land in
storage like anything else. Ordering more than the essence covers makes as
many as it can.

| Example | Takes | Makes |
|---|---|---|
| iron ingot | 8 iron essence | 6 |
| copper ingot | 8 copper essence | 6 |
| dirt | 8 dirt essence | 24 |
| tin ingot (Mekanism) | 8 tin essence | 4 |
| honey bottle | 1 honey essence + 1 glass bottle | 1 |

The **Pots** tab lists each pot with its crop (named from what it last gave),
what's left in it and what it's doing: **harvested**, **growing**,
**waiting** (nothing harvested yet), or in red **can't see inside** (no
modem under it), **not a hopper pot** or **input chest full?**. The header
shows how much essence is stored, and the Pots tab how much has come out of
the pots and how much an hour. With a wireless modem it also reports to the
[status server](../status-server/README.md).

## Files

- `essence.lua`: the program
- `config.lua`: which ingredients count as essence, what to leave in the pots, pot names (kept when you update)
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/setupui.lua`](../../lib/setupui.lua): the setup screen (copy to `/lib/setupui.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Set up the [storage system](../storage-computer/README.md) with a
   [crafting turtle](../crafter-turtle/README.md), and `install update` the
   storage computer if it was installed before the essence computer existed.
2. Give the storage computer your modpack's recipes, which include
   Mystical Agriculture's (see [Modded recipes](../storage-computer/README.md#modded-recipes)).
   For TRekt Mons that's one `wget`; a `pack_recipes.lua` made before the
   essence computer existed has none of the essence recipes, so get it again.
3. Use **Hopper Botany Pots**: a plain pot doesn't let its harvest be taken
   out. Stand each one on a **full-block wired modem** (craft a wired modem
   on its own), join the modems with cable to the storage network and
   right-click each so it turns red. A computer only sees a pot from below.
   A row of pots on a row of modems works well.
4. Place this computer with a wired modem on it, joined to the same network,
   install and reboot. There's nothing to pick: every Hopper Botany Pot on
   the cable is used. **Setup** at the top right of its screen, **F1**, or
   `essence setup` shows the [setup screen](#the-setup-screen): the pots it
   found and what each needs.

```
essence                          -- start (runs on boot)
essence setup                    -- the setup screen (in the running program)
essence find iron                -- recipes for anything with "iron" in its name, and how many you can make
essence make 64 iron ingot       -- order 64 iron ingots
edit config.lua                  -- what counts as essence, what to leave in the pots, pot names
```

On the Recipes tab: type to search, **Backspace** to delete, **Up** /
**Down** (or the mouse wheel, or a click) to pick, **Left** / **Right** for
one craft fewer or more, **Page Up** / **Page Down** for ten, **End** for as
many as you can make, **Enter** to order. **Tab** switches tabs, **F1**
opens the setup screen.

### The setup screen

Like the [storage computer's](../storage-computer/README.md#the-setup-screen),
[smelter's](../smelter-computer/README.md#the-setup-screen) and
[cooker's](../cooker-computer/README.md#the-setup-screen), opened the same
ways (**Setup**, **F1**, or `essence setup` in a second tab), with the same
keys. There's nothing to pick, so it's a check list:

- **Pots**: every pot on the cable, with its crop and what it's doing, in
  red when it needs you (not a Hopper Botany Pot, or the input chest full).
- **Recipes**: how many essence recipes came from the storage computer.
- **Storage computer**: whether it's answering.

**Done** (or D, or Backspace) goes back to the recipes.

## Things to know

- **No recipes?** The storage computer has to know Mystical Agriculture's
  recipes: they come from `pack_recipes.lua` (step 2), or teach one by hand
  with `crafter learn` on the crafting turtle. The list is fetched again
  every 5 minutes, so a new recipe shows up without a restart.
- The storage system picks its own recipe for an item: if you have iron
  blocks stored, an order for iron ingots may break those up instead of
  using essence.
- Some ingots (aluminum, brass, silver, ...) come out as whichever mod's
  ingot Mystical Agriculture prefers. `pack_recipes.lua` names vanilla's if
  there is one, else the first mod's; if the game picks a different one,
  the crafting turtle says so and the order stops.
- Pots of any kind work as long as they're Hopper pots, including other
  colours and Botany Pots Tiers, if their names have `botany_pot` in them
  (`pots` in `config.lua`).
- Spare seeds a crop drops go to storage too. Add `"_seeds$"` to `leave` in
  `config.lua` to leave them in the pots instead (they'll fill up over time).
- Turning essence into seeds, tools and armour is crafting too, so those
  recipes show up as well when the storage computer knows them.
