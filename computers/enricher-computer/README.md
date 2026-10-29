# enricher-computer

- **Type:** computer (advanced is nicer: colour), plus a wired modem on the storage network
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem joined to the [storage system's](../storage-computer/README.md) network; for each Enrichment Chamber, a hopper on top and an input chest under it, all on that network; optional monitor

## What it does

Gets more ingots out of your ores with [Mekanism](https://www.curseforge.com/minecraft/mc-mods/mekanism)
Enrichment Chambers. Every 5 seconds it fills each chamber's hopper with
ores from the [storage system](../storage-computer/README.md). The chamber
turns them into dust and pushes the dust out of its bottom into a storage
input chest. The [smelter](../smelter-computer/README.md) then smelts the
dust into ingots, like any other ore.

| Goes in | Comes out | Smelted straight away, you'd get |
|---|---|---|
| 1 ore block (iron, gold, copper, osmium, tin, lead, uranium) | 2 dust → 2 ingots | 1 ingot |
| 3 raw iron (gold, copper, ...) | 4 dust → 4 ingots | 3 ingots |
| 1 block of raw iron (gold, copper, ...) | 12 dust → 12 ingots | can't be smelted |
| 1 coal, diamond, emerald or quartz ore | 2 coal, diamonds, emeralds or quartz | |
| 1 redstone or lapis ore | 12 redstone or lapis | |
| 1 fluorite ore | 6 fluorite | |

Ore blocks come from silk touch, like a [Digital Miner](../digital-miner-manager/README.md)
with **Silk** on. Deepslate and nether ores count too.

Each chamber works on one kind of ore at a time, the one there's most of in
storage, and its hopper is kept topped up to a stack. Raw ores always go in
threes, so none are left over in the chamber. An Enriching Factory works
too and takes a different ore in each of its slots.

With a [work chest](#work-chest), the storage computer fills that chest once
a round with the ores for every hopper, and the enricher fills the hoppers
from it, instead of asking for each hopper in turn.

While the enricher has a chamber with power, the smelter leaves those ores
alone and smelts the dust instead. When the enricher stops, the smelter
goes back to smelting the ores itself.

The screen lists each chamber with the ore it's on, how many are queued in
it and its hopper, its power and what it's doing: **enriching**,
**starting**, **idle**, **needs N more** (raw ores waiting for a third),
or in red **no power**, **output full** (the dust has nowhere to go) or
**no hopper**. Under the list it shows how much ore is waiting in storage.
With a wireless modem it also reports to the
[status server](../status-server/README.md).

## Files

- `enricher.lua`: the program
- `config.lua`: which ores go in, how many to keep back, chamber names (kept when you update)
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): remembers which hopper feeds which chamber (copy to `/lib/files.lua`). Needed.
- [`lib/workchest.lua`](../../lib/workchest.lua): the work chest (copy to `/lib/workchest.lua`). Needed.
- [`lib/claim.lua`](../../lib/claim.lua): finds a far-away work chest's twin at home (copy to `/lib/claim.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Set up the [storage system](../storage-computer/README.md) and the
   [smelter](../smelter-computer/README.md) first, and `install update` both
   if they were installed before the enricher existed.
2. Place each **Enrichment Chamber** next to the storage network and power
   it. Open its security tab and set it to **Public**, so the enricher can
   set its sides for you. Put a **wired modem** on it, joined to the
   network with cable, and right-click the modem so it turns red.
3. Put a **hopper on top** of the chamber, pointing down into it, with a
   wired modem on it on the same network.
4. Put a **chest under** the chamber with a wired modem on it, and run
   `storage setup` on the storage computer to add it as an **extra input
   chest**. Several chambers can share one through a pipe.
5. Place this computer with a wired modem on it, joined to the same network.
6. Optional: put an **empty chest** with a wired modem on it on the same
   network as the [work chest](#work-chest).
7. Install and reboot. To add the chambers, hold **Ctrl+T** to stop the
   program, and hold it again during the 5-second wait to get the prompt.
   Add each chamber (and pick the work chest), then `reboot`:

   ```
   enricher add                     -- pick a chamber and the hopper on top of it
   enricher add enrichmentChamber_0 minecraft:hopper_3   -- or name them straight away
   enricher remove                  -- list the chambers
   enricher remove 2                -- forget chamber 2
   enricher chest                   -- pick the work chest from the empty chests on the network
   enricher chest none              -- stop using one (what's in it goes back into storage)
   enricher chest remote            -- far from home: two ender chest pairs (see below)
   edit config.lua                  -- which ores, how many to keep, names
   ```

## Work chest

A chest on the storage network that the storage computer fills for the
enricher in one go: each round the enricher works out what every hopper
needs, asks for all of it at once, and fills the hoppers from the chest
itself. That's one request a round instead of one per hopper.

- It has to be **empty** when you pick it, and it can't be the input,
  output, fuel or transfer chest, a turtle's chest or the
  [smelter's](../smelter-computer/README.md#work-chest) work chest. It's
  not the chest under a chamber either: that one is an input chest.
- Anything left in it at the end of a round goes back through the input
  chest. Don't put things in it by hand.
- If the chest goes missing or the storage computer won't take it, the
  footer says why and the enricher fills each hopper the old way until it's
  back. Update the storage computer too (`install update`).

### Far from the storage system

The chambers can be at another base, fed through two pairs of ender chests
shared by colour (EnderStorage or a mod like it), just like the
[smelter far away](../smelter-computer/README.md#far-from-the-storage-system):
a **supply** pair (home end on the storage cable, not picked in `storage
setup`) and a **return** pair (home end an **extra input chest**). Put the
return chest's far end under the chambers instead of a storage input chest,
or pipe the chests under them into it, so the dust goes home. Put an
**ender modem** on the enricher and the storage computer and run `enricher
chest remote`. Far away nothing is loaded while the work chest isn't in
use, and the footer says why.

## Things to know

- **Sides.** Mekanism takes items in on every side of a chamber except its
  right (output) and back (power), so the hopper on top works as it is. The
  enricher sets the **bottom to Output** and turns **Auto-eject** on, but
  only when the chamber's security is Public. Otherwise do it by hand in
  the chamber's side config (the wrench tab, Items), or set `setSides =
  false` in `config.lua` and put the chest at whichever side is Output.
- **Speed.** A chamber on its own enriches one ore every 10 seconds; speed
  upgrades make it much faster. The hopper keeps up with a fully upgraded
  chamber.
- An ore that doesn't go into the chamber within a minute is put back into
  storage and not tried again until the enricher restarts. If that happens
  to every ore, the hopper probably isn't pointing into the chamber.
- In an Enriching Factory a few raw ores can be left waiting in a slot for
  the next batch; they go in once there are three.
- Coal, diamond, emerald and quartz ores give about as much with a Fortune
  III pickaxe. Take them out of `gems` in `config.lua` to keep those ores
  for that.
- Without a monitor it draws on the computer's own screen.
