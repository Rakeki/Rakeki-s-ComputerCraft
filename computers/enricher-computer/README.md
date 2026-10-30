# enricher-computer

- **Type:** computer (advanced is nicer: colour), plus a wired modem on the storage network
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem joined to the [storage system's](../storage-computer/README.md) network; for each Enrichment Chamber, an input (a hopper on top, or a barrel a pipe pulls from into it) and an output chest under it, all on that network; optional monitor

## What it does

Gets more ingots out of your ores with [Mekanism](https://www.curseforge.com/minecraft/mc-mods/mekanism)
Enrichment Chambers. Every 5 seconds it fills each chamber's feeder with
ores from the [storage system](../storage-computer/README.md). The chamber
turns them into dust and pushes the dust out of its bottom into its
**output chest**, which the enricher empties into storage each round (or
straight into a storage input chest under it). The [smelter](../smelter-computer/README.md) then smelts the
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
storage, and its feeder is kept topped up to a stack. Raw ores always go in
threes, so none are left over in the chamber. An Enriching Factory works
too and takes a different ore in each of its slots.

With a [work chest](#work-chest), the storage computer fills that chest once
a round with the ores for every feeder, and the enricher fills the feeders
from it, instead of asking for each feeder in turn.

While the enricher has a chamber with power, the smelter leaves those ores
alone and smelts the dust instead. When the enricher stops, or can't load
its chambers (its screen says why in red), the smelter goes back to
smelting the ores itself, so they never just sit in storage.

The computer's screen lists each chamber with the ore it's on, how many are queued in
it and its feeder, its power and what it's doing: **enriching**,
**starting**, **idle**, **needs N more** (raw ores waiting for a third),
or in red **no power**, **output full** (the dust has nowhere to go),
**no output chest** or
**no feeder**. Under the list it shows how much ore is waiting in storage.

A **monitor** is a status board you can read from across the room: a tile
per chamber with its name and the ore it's on, coloured by how it's doing:

| Colour | Means |
|---|---|
| Lime | ready and idle |
| Yellow | working |
| Orange | flat out: every slot busy and a stack waiting |
| Red | needs you: no power, output full, or its feeder or output chest missing (it says which) |

With a wireless modem it also reports to the
[status server](../status-server/README.md).

## Files

- `enricher.lua`: the program
- `config.lua`: which ores go in, how many to keep back, chamber names (kept when you update)
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): remembers what feeds which chamber (copy to `/lib/files.lua`). Needed.
- [`lib/mekfeed.lua`](../../lib/mekfeed.lua): reads the chambers and their feeders (copy to `/lib/mekfeed.lua`). Needed.
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
3. Give the chamber a **feeder** with a wired modem on it, on the same
   network: either a **hopper on top**, pointing down into it, or an
   **empty barrel** (or chest) with something that moves its items into the
   chamber, like a Mekanism logistical transporter whose barrel end is set
   to **pull** with the Configurator. See [Barrel feeders](#barrel-feeders).
4. Put an **empty chest** (or barrel) **under** the chamber with a wired
   modem on it, on the same network: its **output chest**. Pick it in
   `enricher add`, and the enricher empties it into storage each round.
   (Or make the chest under it an **extra input chest** in `storage setup`
   and skip it in `enricher add`: then the dust goes straight in, and
   several chambers can share one through a pipe.)
5. Place this computer with a wired modem on it, joined to the same network.
6. Optional: put an **empty chest** with a wired modem on it on the same
   network as the [work chest](#work-chest).
7. Install and reboot. Then tap **Setup** on its monitor, or run
   `enricher setup` in a second tab (`bg enricher setup` on an advanced
   computer): the [setup screen](#the-setup-screen). Under **Chambers**, add
   each chamber: tap it, then its feeder, then its output chest. Pick the
   work chest under **Work chest**. Everything is saved as you go.

   ```
   enricher setup                   -- the setup screen (in the running enricher, on its monitor)
   enricher add                     -- or by typing: pick a chamber, its feeder (hopper or barrel) and its output chest
   enricher add enrichmentChamber_0 minecraft:barrel_1 minecraft:chest_4   -- or name them: chamber, input, output
   enricher add enrichmentChamber_0 minecraft:hopper_3   -- no output chest: the chest under it is a storage input chest
   enricher add enrichmentChamber_1 minecraft:barrel_2   -- a barrel a pipe empties into the chamber
   enricher remove                  -- list the chambers
   enricher remove 2                -- forget chamber 2
   enricher chest                   -- pick the work chest from the empty chests on the network
   enricher chest none              -- stop using one (what's in it goes back into storage)
   enricher chest remote            -- far from home: one ender chest both ways (see below)
   edit config.lua                  -- which ores, how many to keep, names
   ```

## Barrel feeders

A chamber doesn't have to be fed by a hopper. A barrel or chest works too,
as long as something moves its items into the chamber: a Mekanism
logistical transporter from the barrel to the chamber, with the barrel end
set to **pull** with the Configurator, or a Create
funnel. A barrel holds more than a hopper, and a fast transporter keeps up
with an upgraded Enriching Factory.

- The barrel has to be **empty** when you add it. `enricher add` only
  lists empty barrels and chests, since every storage chest is one too.
- Once the enricher is running, it tells the storage computer which barrels
  are feeders, and the storage computer stops using them as storage. Until
  it has said yes, those barrels aren't filled and the footer says why.
  Update the storage computer too (`install update`).
- The work chest fills a barrel feeder the same way as a hopper.

## Work chest

A chest on the storage network that the storage computer fills for the
enricher in one go: each round the enricher works out what every feeder
needs, asks for all of it at once, and fills the feeders from the chest
itself. That's one request a round instead of one per feeder.

- It has to be **empty** when you pick it, and it can't be the input,
  output, fuel or transfer chest, a turtle's chest or the
  [smelter's](../smelter-computer/README.md#work-chest) work chest. It's
  not the chest under a chamber either: that one is an input chest.
- Anything left in it at the end of a round goes back through the input
  chest. Don't put things in it by hand.
- If the chest goes missing or the storage computer won't take it, the
  footer says why and the enricher fills each feeder the old way until it's
  back. Update the storage computer too (`install update`).

### Far from the storage system

The chambers can be at another base, fed through one pair of ender chests
shared by colour (EnderStorage or a mod like it), just like the
[smelter far away](../smelter-computer/README.md#far-from-the-storage-system):
the home end on the storage cable (not picked in `storage setup`), the far
end on the enricher's network. The storage computer fills it with ore each
round, and takes out everything it didn't just send: the dust, and ores put
back. So put the ender chest under a chamber instead of a storage input
chest, or pipe the chests under the chambers into it, so the dust goes
home. Put an **ender modem** on the enricher and the storage computer and
pick **Work chest**, **Far away** on the [setup screen](#the-setup-screen)
(or run `enricher chest remote`). The storage computer finds the twin by
dropping an item into each chest it could be, or pick it there first with
[Far-away workers](../storage-computer/README.md#far-away-workers) on its
setup screen and there's no search. Far away nothing is loaded while the work
chest isn't in use, and the footer says why. Update the storage computer
too (`install update`).

The command also lets you pick a second, **return** ender chest (home end
an **extra input chest**) if you'd rather the dust went home through that.

## The setup screen

`enricher setup` (or **Setup** on the monitor) opens it on the monitor and the
computer at once, in the running enricher if there is one:

- **Chambers**: every chamber with its feeder and output chest. Tap one to
  change its feeder or output chest, or remove it; **+ Add a chamber** picks
  a chamber, then its feeder (a hopper, or an empty barrel), then its output
  chest (or none, when a storage input chest is under it).
- **Work chest**: a chest on this cable, **Far away**, or **None**. Far away
  there's nothing to pick: work comes in through the ender chest on its
  network and what it makes goes home through the same chest (it only asks
  which when there are several). Its twin at home is the one picked under
  Far-away workers on the storage computer, or found by itself. An ender
  chest is always far away, however it's picked. A separate return chest:
  `enricher chest remote`.
- **Monitor**: which monitor shows the status board.

Chest lists show what's in each chest and go a page at a time (**<** **>**);
**Empty** shows only the empty ones, and on the computer you can type to
narrow the list. On the computer the arrow keys and Enter pick, Backspace
goes back, and a button's first letter presses it. Each change is saved as
you make it, and the enricher uses it on its next round.

## Things to know

- **Sides.** Mekanism takes items in on every side of a chamber except its
  right (output) and back (power), so the hopper on top works as it is. The
  enricher sets the **bottom to Output** and turns **Auto-eject** on, but
  only when the chamber's security is Public. Otherwise do it by hand in
  the chamber's side config (the wrench tab, Items), or set `setSides =
  false` in `config.lua` and put the chest at whichever side is Output.
- **Speed.** A chamber on its own enriches one ore every 10 seconds; speed
  upgrades make it much faster. A hopper keeps up with a fully upgraded
  chamber; for a fast Enriching Factory use a barrel and a transporter.
- An ore that doesn't go into the chamber within a minute is put back into
  storage and not tried again until the enricher restarts. If that happens
  to every ore, the hopper probably isn't pointing into the chamber, or
  nothing is moving items out of the barrel.
- In an Enriching Factory a few raw ores can be left waiting in a slot for
  the next batch; they go in once there are three.
- Coal, diamond, emerald and quartz ores give about as much with a Fortune
  III pickaxe. Take them out of `gems` in `config.lua` to keep those ores
  for that.
- Without a monitor it draws on the computer's own screen.
- The status board takes the largest text that fits. A monitor 2 blocks wide
  shows a column of tiles; wider ones fit two or more side by side.
- **Which monitor.** It uses the first free monitor it finds, next to it or on its wired network (a wired modem on the monitor, joined by cable). When several computers share a cable, they can take each other's: give this one its own with `set enricher.monitor monitor_3` (the name shows when you right-click the monitor's modem) and reboot. `set enricher.monitor none` keeps it off monitors.
