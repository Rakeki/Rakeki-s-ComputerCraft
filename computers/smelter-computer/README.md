# smelter-computer

- **Type:** computer (advanced is nicer: colour), plus a wired modem on the storage network
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem joined to the [storage system's](../storage-computer/README.md) network; furnaces, blast furnaces and smokers on that network; optionally Mekanism Energized Smelters, each with a hopper or barrel feeding it and an output chest under it; optional monitor, touching it or on the cable (picked with `smelter monitor`)

## What it does

The furnace arm of the [storage system](../storage-computer/README.md). Every
10 seconds it looks at each furnace, blast furnace and smoker on the
storage network and:

- **Empties them.** What's smelted goes into the storage computer's input
  chest, and from there into storage. Charcoal goes on to the fuel chest.
- **Fills them.** Raw iron, gold and copper, ore blocks and ancient debris
  in storage are shared out between the furnaces that are free, blast
  furnaces first (they're twice as fast). Raw meat, fish, potatoes and kelp
  are cooked the same way, smokers first. Blast furnaces only take ores and
  smokers only take food; plain furnaces take either. A furnace already
  smelting something is topped up with more of it, up to a stack.
- **Fuels them** from the storage computer's **fuel chest**, with enough
  for what's in each furnace. Charcoal is used first, then coal, then coal
  blocks; when the fuel chest is empty it uses coal kept anywhere else in
  storage.

With a [work chest](#work-chest), the storage computer fills that chest once
a round with everything the furnaces need, ores and fuel together, and the
smelter loads each furnace from it. Without one, it asks the storage
computer for each furnace's load in turn, which is slower with a lot of
furnaces.

Ores that drop more when mined with Fortune (coal, diamond, emerald, lapis,
redstone, quartz) are left alone, and so are blocks of raw metal. 64
potatoes are always kept back for planting. Change what gets smelted and
cooked, and how much is kept back, in `config.lua`: add sand for glass, say,
or a modded food.

With Mekanism, it also smelts **dust** (iron, gold, copper, osmium, tin,
lead, uranium) into ingots. While the [enricher](../enricher-computer/README.md)
is running with a chamber set up, the smelter never smelts the ores it puts
into its Enrichment Chambers (raw iron, iron ore, ...): it waits for them to
come back as dust, which gives more ingots, even while a chamber is stuck
for a while. Without an enricher, or once it's been gone for 10 minutes, the
smelter smelts those ores itself, as before. Every combination (furnaces only, Mekanism
smelters, with or without the enricher, near or far away) is in
[Smelter and enricher](../storage-computer/README.md#smelter-and-enricher).

### Mekanism smelters

Mekanism **Energized Smelters** and **Smelting Factories** work too. CC
can't put items into a Mekanism machine, so each one has a **feeder**, just
like the [enricher's chambers](../enricher-computer/README.md): a hopper on
top pointing down, or a barrel a pipe pulls from into the machine (see
[Barrel feeders](../enricher-computer/README.md#barrel-feeders)). The
smelter fills the feeders, and the machine pushes what it makes out of its
bottom into its **output chest** under it, which the smelter empties into
storage each round (or into a storage input chest under it, if you pick no
output chest).

- They get first pick of what there is to smelt or cook (they're faster and
  need no fuel); the furnaces take what's left.
- They don't work on charcoal, stone or glass orders: what they make goes
  straight into storage, so the smelter can't count it. Orders need at
  least one plain furnace (blast furnaces and smokers can't take them
  either); without one the footer says so.
- With only Mekanism smelters and no furnaces, it works the same, minus the
  orders and the fuel.
- The smelter sets each one's bottom to **Output** with **Auto-eject** on,
  when its security is **Public**. Otherwise do it by hand, or set
  `setSides = false` in `config.lua`.
- On the screen they're listed under the furnaces in light blue, with their
  power instead of fuel, and in red when they have no power, no feeder, or
  nowhere to put what they make. On the status board they're tiles like the
  furnaces.
- Something that doesn't go in within a minute is put back into storage and
  not tried in them again until the smelter restarts.

### Making charcoal

When there's far more of one kind of log than you want, burn it into
charcoal. Press **C**, pick the logs from the list (the kind there's most of
is first), and say how much charcoal to make. Plain furnaces work on the
order before ores and food (blast furnaces and smokers can't burn logs), and the charcoal goes
into the fuel chest, where it fuels the furnaces and
[turtles](../storage-computer/README.md#fuel). The screen shows how far the
order has got; it carries on after a reboot, and stops early if those logs
run out.

### Making stone

Press **S** and say how much stone to make from the cobblestone in
storage. It works like a charcoal order (plain furnaces only, carries on
after a reboot, stops early if the cobblestone runs out), and the stone
goes into storage.

### Making glass

Press **G** and say how much glass to make. It smelts sand and red sand,
whichever there's more of, and carries on with the other when one runs
out (`smelter glass <n> red` sticks to red sand). Like stone, it uses
plain furnaces only (blast furnaces and smokers can't smelt sand), carries
on after a reboot, and the glass goes into storage.

All three orders can run at once: plain furnaces start on the charcoal
first, then the stone, then the glass, and all of them come before ores and
food.

The screen lists each furnace (blast furnaces in orange, smokers in pink), what's in it and its fuel, how much
smelting the stored fuel is good for, and what it did last. With a
wireless modem it also reports to the [status server](../status-server/README.md).

## Files

- `smelter.lua`: the program
- `config.lua`: which items get smelted (kept when you update)
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed.
- [`lib/workchest.lua`](../../lib/workchest.lua): the work chest (copy to `/lib/workchest.lua`). Needed.
- [`lib/claim.lua`](../../lib/claim.lua): finds a far-away work chest's twin at home (copy to `/lib/claim.lua`). Needed.
- [`lib/mekfeed.lua`](../../lib/mekfeed.lua): Mekanism smelters and their feeders (copy to `/lib/mekfeed.lua`). Needed.

## Setup

1. Set up the [storage system](../storage-computer/README.md) first, and
   update it (`install update`) if it was installed before the smelter
   existed.
2. Place the furnaces, blast furnaces and smokers near the storage. Each one needs a
   **wired modem** on it (furnaces are full blocks, so a small modem goes
   straight on), joined to the storage network with networking cable.
   Right-click each modem so it turns red.
3. Place this computer with a wired modem on it, joined to the same network
   (a wireless modem as well is only needed for the status server).
4. For a fuel chest: connect one more chest to the network, run
   `storage setup` on the storage computer and pick it as the **fuel chest**.
   Put some coal or charcoal in it, or in the input chest. Without a fuel
   chest, furnaces burn coal and charcoal from anywhere in storage.
5. Optional: for each Mekanism **Energized Smelter** (or Smelting
   Factory), set its security to **Public**, put a wired modem on it, a
   **feeder** with a wired modem (a hopper on top, or an empty barrel a pipe
   pulls from into it) and an empty **output chest** under it, all on the
   network, then add each one on the setup screen (step 7). See
   [Mekanism smelters](#mekanism-smelters).
6. Optional, but worth it with more than a few furnaces: put an **empty
   chest** next to the furnaces with a wired modem on it, on the same
   network, as the [work chest](#work-chest).
7. Install this program and reboot. Then tap **Setup** at the top right of
   its monitor or screen, press **F1**, or run `smelter setup` in a second tab: the
   [setup screen](#the-setup-screen). Pick the work chest (if you placed one)
   and add any Mekanism smelters there. Everything is saved as you go.

   ```
   smelter                        -- start (startup.lua does this on boot)
   smelter setup                  -- the setup screen (in the running smelter, on its monitor)
   smelter add                    -- or by typing: add a Mekanism smelter, its feeder (hopper or barrel) and output chest
   smelter add energizedSmelter_0 minecraft:hopper_4 minecraft:chest_9   -- or name them: smelter, input, output
   smelter remove 1               -- forget Mekanism smelter 1 (no number: list them)
   smelter chest                  -- pick the work chest from the empty chests on the network
   smelter chest minecraft:chest_7  -- or name it straight away
   smelter chest none             -- stop using one (what's in it goes back into storage)
   smelter chest remote           -- far from home: work through an ender chest (see below)
   smelter charcoal 256 spruce    -- make 256 charcoal from spruce logs
   smelter charcoal 64            -- make 64 from the logs there are most of
   smelter stone 512              -- make 512 stone from cobblestone
   smelter glass 256              -- make 256 glass from sand (or red sand)
   smelter glass 64 red           -- make 64 glass from red sand only
   smelter cancel stone           -- stop making stone
   smelter cancel                 -- stop every order
   smelter monitor                -- pick the monitor for the status board from every one on the network
   smelter monitor monitor_3      -- or name it straight away ('none': no status board)
   ```

On the running smelter, **C** starts a charcoal order, **S** a stone order,
**G** a glass order, **X** cancels one (it asks which when more than one
is running), and **F1** opens the setup screen. The `smelter charcoal`, `smelter stone` and `smelter glass`
commands do the same from another tab (or
after stopping it with Ctrl+T); the running smelter picks them up within
10 seconds.

## Work chest

A chest on the storage network that the storage computer fills for the
smelter in one go: each round the smelter works out what every furnace
needs, asks for all of it at once, and loads the furnaces from the chest
itself. That's one request a round instead of two for every furnace, so
the storage computer has more time for turtles, and with an ME or RS system
the items don't go through the transfer chest.

- It has to be **empty** when you pick it, and it can't be the input,
  output, fuel or transfer chest, a turtle's chest or the
  [enricher's](../enricher-computer/README.md#work-chest) work chest. With
  chests as storage, an empty storage chest works: it stops being storage.
- Anything left in it at the end of a round goes back through the input
  chest, so nothing waits there unseen. Don't put things in it by hand.
- If the chest goes missing or the storage computer won't take it, the
  footer says why and the smelter loads each furnace the old way until it's
  back. It asks again once a minute.
- The storage computer needs to be updated too (`install update`); an older
  one doesn't know work chests, and the smelter carries on without.

### Far from the storage system

With ender chests that are shared by colour (EnderStorage or a mod like
it), the furnaces can be at another base. You need one ender chest pair:
one ender chest on the storage cable at home (wired modem, not picked as
any chest in `storage setup`) and its twin on the smelter's own wired
network. The storage computer fills it each round, and smelted items,
leftovers and anything put back go home through it too: each round the
storage computer takes out everything it didn't just send.

Put an **ender modem** on the smelter and one on the storage computer, then
pick **Work chest**, **Far away** on the [setup screen](#the-setup-screen)
(or run `smelter chest remote`) and pick the chest. The storage computer
finds its twin at home by dropping an item into each chest
it could be until it turns up at your end, so it needs something stored.
Or pick the twin on the storage computer first under
[Far-away workers](../storage-computer/README.md#far-away-workers) on its setup screen
(it finds the smelter over the wireless or ender modem): then there's no
search.
The ender chest needs a **wired modem on it**, joined to the smelter's cable
(one only touching the computer can't be reached from the furnaces). If the
twin isn't found yet, Far away still sticks: smelted items go into the ender
chest anyway, the footer says so, and it looks again every minute.
Far away the smelter can only load furnaces through the work chest: while
it's not in use (storage not answering, a chest gone), nothing is loaded
and the footer says why. Both bases need to be loaded. Update the
storage computer too (`install update`). With an
[enricher](../enricher-computer/README.md), the smelter asks it which ores to
leave over rednet: with either of them far away, both need an ender modem,
or the smelter smelts those ores itself.

If you'd rather send things home separately, `smelter chest remote` also
lets you pick a second, **return** ender chest, whose twin at home is an
**extra input chest** in `storage setup`.

```
smelter chest remote           -- pick the ender chest (and, if you like, a return one)
```

## The setup screen

**Setup** at the top right of the monitor or the computer's screen, **F1**
on the computer, or `smelter setup` (in a second tab, or after Ctrl+T)
opens it on the monitor and the computer at once, in the running smelter
if there is one. It works like the
[storage computer's](../storage-computer/README.md#the-setup-screen) and the
[enricher's](../enricher-computer/README.md#the-setup-screen):

- **Furnaces**: how many it found on the network (nothing to pick: every
  furnace, blast furnace and smoker on the cable is used).
- **Mekanism smelters**: each with its feeder and output chest. Tap one to
  change them or remove it; **+ Add an energized smelter** picks the
  smelter, then its feeder (a hopper, or an empty barrel), then its output
  chest (or none). Far away, set the work chest first: then chests that
  already have something in them are offered too, and the output chest is
  emptied into the ender chest, which takes the ingots home.
- **Work chest**: a chest on this cable, **Far away**, or **None**. Far away
  there's nothing to pick: work comes in through the ender chest on its
  network and what it makes goes home through the same chest (it only asks
  which when there are several). Its twin at home is the one picked under
  Far-away workers on the storage computer, or found by itself. An ender
  chest is always far away, however it's picked. A separate return chest:
  `smelter chest remote`.
- **Monitor**: which monitor shows the status board.

Chest lists show what's in each chest and go a page at a time (**<** **>**);
**Empty** shows only the empty ones, and on the computer you can type to
narrow the list. On the computer the arrow keys and Enter pick, Page Up and
Page Down turn the page, Backspace goes back, and a button's first letter
presses it (D for **Done**, B for **Back**; not on chest lists, where
typing narrows the list). Each change is saved as you make it, and the
smelter uses it straight away.

## Things to know

- Furnaces must be on the network through a modem, not just touching this
  computer: the storage computer moves the items, and it can only reach
  what's on the cable.
- It works the same whether the storage computer keeps things in chests or
  in an [ME or RS system](../storage-computer/README.md#me-and-rs-systems).
  With an ME or RS system and no work chest, the storage computer needs a
  **transfer chest** (chosen in `storage setup`) to load the furnaces' slots.
- It asks the storage computer for everything over the cable, so both must
  be on the same wired network (far away: over ender modems, see
  [Far from the storage system](#far-from-the-storage-system)). If the
  storage computer doesn't answer, the footer says so and it tries again
  every 10 seconds.
- Making charcoal needs some fuel to start with: one coal or charcoal
  burns 8 logs into 8 charcoal.
- A stone order only makes plain stone from cobblestone, not smooth stone
  or deepslate.
- If a furnace has fuel but doesn't smelt what's in it for 2 minutes (an
  item that doesn't smelt there, like a modded ore in a blast furnace), the
  item goes back into storage and isn't put in that kind of furnace again
  until the smelter restarts.
- If the storage input chest (far away, the ender chest) is full, smelted
  items wait in the furnaces and the footer says so.
- Furnaces and smokers you load by hand get fuelled and emptied too.
- After `install update`, an older `config.lua` (kept as it was) has no
  cook list: the smelter then cooks the food listed above and keeps 64
  potatoes. Copy the `cook` and `keep` lists from the new one to change them.
- **A status board.** A monitor is the smelter's status board straight away: one touching it first, else the first one on the cable (put a wired modem on it and join it to the network). If it picks the wrong one (another program's on the same cable), `smelter monitor` (or **Monitor** on the setup screen) lists every monitor it can see (right-click a monitor's modem to see its name) and the running smelter moves to the one you pick at once, no reboot (`smelter monitor none` for no board). The board has a tile per furnace and Mekanism smelter: **lime** idle, **yellow** smelting, **orange** a full stack in, **red** when it needs you (items waiting with no fuel or power, or its output stuck). The full table, the orders and the C, S, G, X and F1 keys stay on the computer's screen.
