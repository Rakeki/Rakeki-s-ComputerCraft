# factory

- **Type:** computer (advanced is nicer: colour and mouse), plus a wired modem on the storage network
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem joined to the [storage system's](../storage-computer/README.md) network; whichever machines it runs, on that network (furnaces, Mekanism machines with their feeders and output chests, Create lines' feeder and output chests, cooking pots' hoppers and relays, botany pots on wired modems or the barrel they empty into); optional monitor, touching it or on the cable (picked with `factory monitor`)

## What it does

One program for every machine that turns what's in the
[storage system](../storage-computer/README.md) into something else, whatever
mods you have. It runs whichever of these it finds on its cable or you add:

| Machines | Mod | What happens |
|---|---|---|
| Furnaces, blast furnaces, smokers | vanilla | ores, dust and food [smelted and cooked](#smelting), with fuel from the fuel chest; charcoal, stone and glass on order |
| Energized Smelters | [Mekanism](https://www.curseforge.com/minecraft/mc-mods/mekanism) | [smelt](#mekanism-smelters) like furnaces, faster and with no fuel |
| Enrichment Chambers | Mekanism | [ores into dust](#enriching): 2 dust per ore block, 4 per 3 raw ores |
| Metallurgic Infusers | Mekanism | [on request](#infusing): steel, alloys, circuits, bronze, mossy blocks; the storage computer orders them for its crafts too |
| Crushing wheels, washing fans | [Create](https://www.curseforge.com/minecraft/mc-mods/create) | ores [crushed](#create-crushing-wheels), crushed ores [washed](#create-washing-fans) into nuggets and a byproduct |
| Blasting and smoking fans | Create | [smelt ores, cook food](#create-fans), no fuel |
| Campfire cooking pots | [Cobblemon](https://www.curseforge.com/minecraft/mc-mods/cobblemon) | [exp candy](#cooking-pots), compressed up to XL |
| Hopper Botany Pots | [Mystical Agriculture](https://www.curseforge.com/minecraft/mc-mods/mystical-agriculture) | [essence](#essence) emptied into storage, and the recipes it crafts into, ready to order |

What it makes goes back into storage through the storage computer's input
chest. Furnaces and botany pots are found by themselves; everything else is
added on the [setup screen](#the-setup-screen), in a few taps. With none of
a kind, that part simply doesn't run: a Create-only world, a furnaces-only
one and one with everything all use the same program.

The computer's screen has a tab per part that's running (**Smelter**,
**Enricher**, **Infuser**, **Pots**, **Essence**): tap one, or press **Tab**. A
**monitor** is a status board you can read from across the room, a tile per
machine:

| Colour | Means |
|---|---|
| Lime | ready and idle |
| Yellow | working |
| Orange | flat out: a full stack in, or every slot busy |
| Red | needs you: no fuel or power, output stuck, a Create line not moving, a pot not cooking, something missing (it says which) |

With cooking pots, the monitor has a **Candy** page too (tap it at the top),
and with infusers an **Infuse** page to request from.
With a wireless modem it also reports to the
[status server](../status-server/README.md).

### Several factory computers

Put the factory on as many computers as you like, near the machines each
one runs, all on the storage cable (or [far away](#far-from-the-storage-system)).
They sort themselves out:

- **Furnaces and botany pots** belong to whichever factory computer saw them
  first; the others leave them alone. Hand some to another computer on the
  setup screen (**Machines**: tap one), or with `factory give`.
- **Machines you add** belong to the computer you added them on, and other
  factory computers won't offer them.
- **The chain.** Each one tells the others which items its machines take.
  Ores an enricher takes (on any factory computer) are left to it by every
  smelter, which smelts their dust or crushed ores instead; with a washer,
  crushed ores go to it, and the storage computer crafts the nuggets into
  ingots. A factory computer that hasn't been heard from for 10 minutes is
  forgotten, and its ores are smelted as they are.

The **Chain** page on the setup screen shows what happens where. Every
combination (furnaces only, Mekanism, Create, near or far away) is in
[Smelter and enricher](../storage-computer/README.md#smelter-and-enricher).

## Smelting

Every 10 seconds the factory looks at each of its furnaces, blast furnaces
and smokers and:

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
factory loads each furnace from it. Without one, it asks the storage
computer for each furnace's load in turn, which is slower with a lot of
furnaces.

Ores that drop more when mined with Fortune (coal, diamond, emerald, lapis,
redstone, quartz) are left alone, and so are blocks of raw metal. 64
potatoes are always kept back for planting. Change what gets smelted and
cooked, and how much is kept back, under `smelter` in `config.lua`: add sand
for glass, say, or a modded food.

With Mekanism, it also smelts **dust** (iron, gold, copper, osmium, tin,
lead, uranium) into ingots, and Create's **crushed ores**. Ores that an
[enricher](#enriching) takes are left for it (see [the chain](#several-factory-computers)).

The Smelter tab lists each furnace (blast furnaces in orange, smokers in
pink), what's in it and its fuel, how much smelting the stored fuel is good
for, the orders and what it did last.

### Mekanism smelters

Mekanism **Energized Smelters** and **Smelting Factories** work too. CC
can't put items into a Mekanism machine, so each one has a **feeder**, like
the [chambers](#enriching): a hopper on top pointing down, or a barrel a
pipe pulls from into the machine (see [Barrel feeders](#barrel-feeders)).
The factory fills the feeders, and the machine pushes what it makes out of
its bottom into its **output chest** under it, which the factory empties
into storage each round (or into a storage input chest under it, if you
pick no output chest).

- They get first pick of what there is to smelt or cook (they're faster and
  need no fuel); the furnaces take what's left.
- With an output chest, they work on charcoal, stone and glass orders too,
  ahead of the furnaces: the factory counts what it empties out of that
  chest. One that pushes straight into a storage input chest takes no
  orders, since what it makes can't be counted. Orders need a plain furnace
  or a Mekanism smelter with an output chest (blast furnaces and smokers
  can't take them); without one the footer says so.
- With only Mekanism smelters and no furnaces, it works the same, minus the
  fuel.
- The factory sets each one's bottom to **Output** with **Auto-eject** on,
  when its security is **Public**. Otherwise do it by hand, or set
  `setSides = false` under `smelter` in `config.lua`.
- On the Smelter tab they're listed under the furnaces in light blue, with
  their power instead of fuel, and in red when they have no power, no
  feeder, or nowhere to put what they make.
- Something that doesn't go in within a minute is put back into storage and
  not tried in them again until the factory restarts.

### Create fans

Create fans smelt too, with no fuel at all: an **encased fan blowing
through lava** smelts what passes it on a belt (bulk blasting), and one
**blowing through fire** cooks food (bulk smoking). The computer can't see
a fan, so a **fan line** is two chests on the storage network:

- a **feeder**: an empty chest or barrel with a funnel that puts its items
  on the belt running past the fan.
- an **output chest**: where the belt ends, through a funnel. The factory
  empties it into storage each round. Or end the belt at a storage input
  chest and pick none.

Add one on the [setup screen](#the-setup-screen) under **Machines** (**+ Add
a Create blasting fan** or **smoking fan**), or with `factory add fan` or
`factory add smokefan`. Each round its feeder is topped up to a stack.

- A **blasting fan** takes what blast furnaces take: raw ores, ore blocks,
  ancient debris, Mekanism dust and Create's crushed ores (from the
  [crushers](#create-crushing-wheels)). A **smoking fan** takes only food.
- They're loaded along with the Mekanism smelters, before the furnaces, and
  like them take no part in charcoal, stone or glass orders.
- On the Smelter tab they're listed in yellow with "Create" where the fuel
  would be. Since the computer can't see the fan, it goes by the feeder:
  red **not moving: is the fan on?** when the feeder hasn't gone down for a
  minute (the fan isn't turning, there's no lava or fire in front of it, or
  the funnel isn't taking from the feeder). Nothing is put back: it just
  waits.

### Making charcoal

When there's far more of one kind of log than you want, burn it into
charcoal. On the Smelter tab press **C**, pick the logs from the list (the
kind there's most of is first), and say how much charcoal to make. Plain
furnaces and [Mekanism smelters](#mekanism-smelters) with an output chest
work on the order before ores and food (blast furnaces and smokers can't
burn logs), and the charcoal goes into the fuel chest, where it fuels the
furnaces and [turtles](../storage-computer/README.md#fuel). The tab shows
how far the order has got; it carries on after a reboot, and stops early if
those logs run out.

### Making stone

Press **S** and say how much stone to make from the cobblestone in
storage. It works like a charcoal order (plain furnaces and Mekanism
smelters, carries on after a reboot, stops early if the cobblestone runs
out), and the stone goes into storage.

### Making glass

Press **G** and say how much glass to make. It smelts sand and red sand,
whichever there's more of, and carries on with the other when one runs out
(`factory glass <n> red` sticks to red sand). Like stone, it uses plain
furnaces and Mekanism smelters (blast furnaces and smokers can't smelt
sand), carries on after a reboot, and the glass goes into storage.

All three orders can run at once: Mekanism smelters (with an output chest)
and plain furnaces start on the charcoal first, then the stone, then the
glass, and all of them come before ores and food. **X** cancels one (it
asks which when more than one is running). The `factory charcoal`,
`factory stone` and `factory glass` commands do the same from another tab;
the running factory picks them up within 10 seconds.

## Enriching

More ingots out of your ores, with Mekanism Enrichment Chambers, Create
crushing wheels and washing fans, or both. **No Mekanism?** Create works on
its own: see [Create crushing wheels](#create-crushing-wheels),
[Create washing fans](#create-washing-fans) and [Create only](#create-only).

Every 5 seconds the factory fills each chamber's feeder with ores from
storage. The chamber turns them into dust and pushes the dust out of its
bottom into its **output chest**, which the factory empties into storage
each round (or straight into a storage input chest under it). The
[smelter](#smelting) then smelts the dust into ingots, like any other ore.

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

While a chamber is set up, smelters never smelt those ores (raw iron, iron
ore, ...): they wait for the dust, which gives more ingots. That holds even
while a chamber can't be loaded for a while (no power, storage not
answering: the Enricher tab says why in red), so fix that and the ores move
on. Without a smelter anywhere the dust stays in storage.

The Enricher tab lists each chamber, crusher and washer with the ore it's
on, how many are queued in it and its feeder, its power and what it's
doing: **enriching**, **starting**, **idle**, **needs N more** (raw ores
waiting for a third), or in red **no power**, **output full** (the dust has
nowhere to go), **no output chest** or **no feeder**; a crusher or washer
shows **crushing** / **washing**, **idle**, or in red **not moving** (see
below). Under the list it shows how much ore is waiting in storage.

### Barrel feeders

A Mekanism machine doesn't have to be fed by a hopper. A barrel or chest
works too, as long as something moves its items into the machine: a
Mekanism logistical transporter from the barrel to the machine, with the
barrel end set to **pull** with the Configurator, or a Create funnel. A
barrel holds more than a hopper, and a fast transporter keeps up with an
upgraded factory.

- The barrel has to be **empty** when you add it. Only empty barrels and
  chests are offered, since every storage chest is one too.
- Once the factory is running, it tells the storage computer which barrels
  are feeders, and the storage computer stops using them as storage. Until
  it has said yes, those barrels aren't filled and the footer says why.
  Update the storage computer too (`install update`).
- The work chest fills a barrel feeder the same way as a hopper.

### Create crushing wheels

A pair of Create crushing wheels can do the chambers' job, or help them.
The computer can't see crushing wheels at all, so a **crushing line** is
two chests on the storage network:

- a **feeder**: an empty chest or barrel with a funnel (or a chute) that
  drops its items onto the wheels.
- an **output chest**: where the crushed ores end up, through a chute or
  funnel under the wheels. The factory empties it into storage each round.
  Or let them fall into a storage input chest and pick none.

Add one on the [setup screen](#the-setup-screen) under **Machines**,
**+ Add a Create crushing line**, or with `factory add crusher`. Each round
its feeder is topped up to a stack of ore. The crushed ores (and the XP
nuggets and odd bits of cobblestone) go into storage, and the
[smelter](#smelting) smelts the crushed ores into ingots, in furnaces or a
[blasting fan](#create-fans).

| Goes in | Crushed | Chamber instead |
|---|---|---|
| 1 ore block | 1.75 crushed ores on average → 1.75 ingots | 2 dust |
| 1 raw iron (gold, copper, ...) | 1 crushed ore (and XP nuggets) → 1 ingot | 1.33 dust |
| 1 block of raw iron | 9 crushed ores | 12 dust |
| 1 diamond or emerald ore | 1.75 on average | 2 |
| 1 redstone ore | 6.5 redstone on average | 12 |

Coal, lapis and quartz ores crush with a bonus too. Crushers also take ores
no chamber does: Create's **zinc**, and silver, nickel, aluminum, platinum
and quicksilver from other mods (`crushMetals` under `enricher` in
`config.lua`). Fluorite doesn't crush.

With both, the chambers always get first pick, since they give more per
ore, and the crushers take what's left over in storage, so more gets
through. Set `share = false` and, while there are chambers, the crushers
only take the ores the chambers can't (zinc and so on).

Since it can't see the wheels, the factory works out how a line is doing
from its feeder: **crushing** while ore is waiting in it, **idle** when
it's empty, and in red **not moving** when the feeder hasn't gone down for
a minute. Then check the wheels are turning (enough stress) and that the
funnel is taking from the feeder. Nothing is put back: it just waits.

Crushing raw ores (what a Fortune pickaxe gives you) gives no more ingots
on its own: 1 crushed ore is 1 ingot, plus XP nuggets. Add a **washing
fan** and each crushed ore also gives a byproduct, like redstone from iron.

### Create washing fans

An encased fan **blowing through water** washes the crushed ores going past
it on a belt into **9 nuggets and a byproduct**: that's Create's real bonus
for raw ores. Like a crusher, a **washer** is two chests on the storage
network: a **feeder** with a funnel that puts its items on the belt past
the fan, and an **output chest** at the end of the belt (or a storage input
chest, and pick none).

Add one on the [setup screen](#the-setup-screen) under **Machines**, **+ Add
a Create washing fan**, or with `factory add washer`. While there's a
washer, every crushed ore goes to it, and smelters leave crushed ores alone.

| Crushed ore | Washed |
|---|---|
| crushed raw iron | 9 iron nuggets, 75% chance of a redstone |
| crushed raw gold | 9 gold nuggets, 50% chance of a quartz |
| others (copper, zinc, mods' metals) | 9 nuggets and their own byproduct |

**Nuggets back into ingots.** Once a minute the factory asks the storage
computer to craft every 9 nuggets into an ingot, so you need its crafting
set up: a [crafting turtle](../crafter-turtle/README.md), or the patterns in
your ME or RS system. Iron, gold, Create copper and zinc nuggets are in the
storage computer's built-in recipes (`install update` it); other mods'
nuggets need their recipe (`crafter learn`, or a modpack's recipes) and a
line in `nuggets` under `enricher` in `config.lua`. If the storage computer
can't craft them, the footer says why. Keep some nuggets back with `keep`,
e.g. `["minecraft:iron_nugget"] = 18`, or turn this off with
`compact = false`.

A washer shows **washing**, **idle** or in red **not moving**, the same as
a crusher.

## Infusing

Runs Mekanism **Metallurgic Infusers** (and Infusing Factories), but only
when something is asked for: unlike smelting and enriching, nothing in
storage is infused by itself. Out of the box it knows Mekanism's recipes:

| Request | Made from | Infused with |
|---|---|---|
| Steel dust | enriched iron | carbon (coal or charcoal) |
| Enriched iron | iron ingot or iron dust | carbon |
| Infused alloy | copper ingot | redstone |
| Reinforced alloy | infused alloy | diamond (diamond dust) |
| Atomic alloy | reinforced alloy | refined obsidian (its dust) |
| Basic circuit | osmium ingot | redstone (2 a go) |
| Bronze ingot / dust | 3 copper ingots / dust, makes 4 | tin (tin dust) |
| Gilded blackstone | blackstone | gold (10 gold dust) |
| Slime balls, podzol, dirt, mossy cobblestone and stone bricks (slabs, stairs, walls) | clay, dirt, sand, cobblestone, stone bricks | bio fuel |
| Mycelium, crimson and warped nylium | dirt, netherrack, crimson nylium | mushrooms |

Plain diamonds, gold ingots and obsidian don't go in: Mekanism only takes
their dust (enrich them first) or enriched form. Carbon comes from coal,
charcoal, their dust or blocks; the factory sends whichever wastes least.

There are three ways to ask:

- **Its page.** The **Infuser** tab (and the monitor's **Infuse** page)
  lists every recipe with how many you can make from what's stored, and
  **+1**, **+8** and **+64** buttons: tap one to ask for that many more.
  What's asked for is listed underneath with how it's doing; tap **x** to
  cancel one. Up / Down or the mouse wheel scroll the list.
- **`factory infuse`** lists the recipes; `factory infuse steel 64` asks
  for 64 steel dust, `factory infuse cancel` cancels.
- **The storage computer.** It's told what this computer can infuse, so
  when a craft needs steel dust or an alloy (a turtle's `prepare`, an
  order, a recipe several steps deep) it plans the infusing as one of the
  steps and asks the infuser for it. Its crafting turtle carries on with
  the later steps once the infused items are in storage. Turn this off with
  `offer = false` under `infuser` in `config.lua`.

When what you ask for needs something that's infused too and none is
stored (steel dust needs enriched iron), it asks for that first, by itself:
64 steel dust from iron ingots is one request. The count shown already
takes that into account.

Each round it gives each idle infuser the oldest request it can work on,
sends its feeder the input and its **infusion feeder** just enough coal,
redstone and so on for it, and counts what comes out in its output chest
towards the request before it goes into storage. An infuser holds one
infusion type at a time; switching (carbon to redstone, say) empties what's
left of the old one, a few points at most. The items a request is waiting
on are left alone by the smelter, so your iron dust isn't smelted away
underneath it.

The tab shows each request (**on 1 infuser**, **waiting for** an item,
**queued**), and the status board a tile per infuser, red when it has no
power or feeder, or its output is stuck.

## Cooking pots

Puts Cobblemon's **campfire cooking pots** to work. Out of the box they make
exp candy and compress it:

| Pot | Takes, per cook | Makes |
|---|---|---|
| `exp_candy_xs` | 1 sculk + 1 honeycomb | 1 exp candy XS |
| `exp_candy_s` | 6 exp candy XS | 1 exp candy S |
| `exp_candy_m` | 3 exp candy S | 1 exp candy M |
| `exp_candy_l` | 3 exp candy M | 1 exp candy L |
| `exp_candy_xl` | 3 exp candy L | 1 exp candy XL |

Each pot makes one of these. Set up the ones you want, so a pot for each
size compresses everything up to XL, and pots up to M stop at M. Every 10
seconds the factory:

- **Looks at each pot.** A comparator next to the pot reads how full it
  is, and a redstone relay passes that to the computer.
- **Fills the pots.** It asks the storage computer for whatever the pot
  has room for, out of what's in storage, and the storage computer puts it
  in the pot's **feed hopper**, which passes it into the pot.
- **Empties them.** The **output hopper** under each pot takes out what's
  cooked, and the factory sends it to the storage computer's input chest,
  and from there into storage, ready for the next pot up.

A pot cooks one thing every 5 seconds, as long as its lid is shut, and
redstone power is what shuts it.

A hopper can't choose which pot slot an item goes in: it fills the first
slot it can, and a pot given one item too many starts another slot and
jams. That's what the comparator is for: the factory sends only what the
pot has room for, judged from what the pot really holds, so nothing has to
be counted and you can open a pot without upsetting it.

- **Sculk and honeycomb** go in in pairs, up to a stack between them in
  the pot. When one of them runs out in storage, the other waits too.
- **Keeping them coming.** Once a minute the factory asks the storage
  computer to craft more sculk and honeycomb, up to 128 of each in storage
  (on top of any `keep`), so the pots are never left waiting. This only
  does anything when the storage computer has a recipe for them (a
  modpack's, or one taught with `crafter learn`); without one it's left
  alone and tried again every 10 minutes. Change the amount with `craft`
  under `cooker` in `config.lua` (a number, or per item), or `craft = false`
  to turn it off.
- **Compressing** needs a slot per candy (6 for S, 3 for the rest), and a
  hopper only starts the next slot once one is full. So a compressing pot
  starts cooking once it holds 5 stacks and 1 (321 XS candy) for an S pot,
  or 2 stacks and 1 (129) for the others, and keeps a little more than
  that in it as it works. Those candies are in the pot, not in storage.

The Pots tab lists each pot, what it makes, how many it has made since the
factory started, and what it's doing: **cooking**, **filling** (about how
many it holds / how many it needs to start), **needs** an item that's run
out in storage, or **not cooking!** when it should be.

### Candy monitor

With cooking pots, the monitor gets a **Candy** page (tap it at the top of
the monitor) that shows how much candy you have:

- each size, XS to XL, and rare candy: how many are in storage, about how
  many are in the compressing pots, and the exp they're worth (XS 100, S
  800, M 3,000, L 10,000, XL 30,000, as in Cobblemon);
- the exp of all the candy in storage together;
- how much sculk and honeycomb is left for making more XS.

It needs room for 36 characters across: a monitor 4 blocks wide, or 2 or 3
wide (it then uses smaller text), and at least 2 blocks tall. To change what
it lists, see `candy` under `cooker` in `config.lua`.

## Essence

Turns a farm of Mystical Agriculture crops growing in
[Botany Pots](https://www.curseforge.com/minecraft/mc-mods/botany-pots) into
whatever their essence crafts into: iron ingots, dirt, diamonds and so on.

Every 10 seconds it empties each of its Hopper Botany Pots into the storage
system's input chest, so the essence (and any spare seeds) ends up in
storage. A pot whose harvest slots fill up stops growing, so this keeps
them all going. The seed and soil are never touched: a pot doesn't even
show them to a computer. If your pots push their harvest into a **barrel**
instead (under them, or at the end of a pipe), add that barrel as a **pot
barrel** and it's the barrel that gets emptied (see
[Botany pots](#botany-pots)).

The Essence tab's **Recipes** view is the lookup. It lists every recipe
that uses essence with what it makes, what it takes, how many you can make
from what's stored and how many are stored now. With nothing typed it shows
only what you have enough essence for; type part of a name (`iron`, `dirt`,
`ingot`) to find any recipe, even ones you can't make yet. Pick a recipe,
set how many crafts you want and press **Order**: the storage system's
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

On the Recipes view: type to search, **Backspace** to delete, **Up** /
**Down** (or the mouse wheel, or a click) to pick, **Left** / **Right** for
one craft fewer or more, **Page Up** / **Page Down** for ten, **End** for as
many as you can make, **Enter** to order.

The **Pots** view (top right of the tab) lists each pot with its crop
(named from what it last gave), what's left in it and what it's doing:
**harvested**, **growing**, **waiting** (nothing harvested yet), or in red
**can't see inside** (no modem under it), **not a hopper pot** or **input
chest full?**, and how much has come out of the pots and how much an hour.

## Example layouts

The website shows each of these in 3D.

### One pot

The pot on its campfire, raised one block so the output hopper fits under
it. The feed hopper points into the pot's side, and a redstone block behind
the pot shuts its lid without touching either hopper. A comparator on the
pot's other side reads it into the redstone relay beyond it. A wired modem on
each hopper and on the relay joins the storage network's cable, which also
reaches the storage input chest and this computer.

### Candy chain

Five pots in a row, one for each size from XS to XL, each set up like the
single pot, all on one cable. XS candy goes back into storage through the
input chest, then into the S pot, and so on up to XL.

## Files

- `factory.lua`: the program: the screens, the setup screen, the commands and the rounds
- `smelt.lua`, `enrich.lua`, `infuse.lua`, `cook.lua`, `botany.lua`: its parts (furnaces and smelters, chambers and Create lines, infusers, cooking pots, botany pots)
- `smelter.lua`, `enricher.lua`, `cooker.lua`, `essence.lua`: the old programs' commands, which now run `factory` (`smelter charcoal 64` still works)
- `config.lua`: each part's settings (kept when you update)
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screens without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed.
- [`lib/mekfeed.lua`](../../lib/mekfeed.lua): Mekanism machines, Create lines and their feeders (copy to `/lib/mekfeed.lua`). Needed.
- [`lib/workchest.lua`](../../lib/workchest.lua): the work chest (copy to `/lib/workchest.lua`). Needed.
- [`lib/claim.lua`](../../lib/claim.lua): finds a far-away work chest's twin at home (copy to `/lib/claim.lua`). Needed.
- [`lib/setupui.lua`](../../lib/setupui.lua): the setup screen (copy to `/lib/setupui.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Set up the [storage system](../storage-computer/README.md) first, and
   update it (`install update`) if it was installed before the factory.
2. Place your machines near the storage cable (see below for each kind),
   each with a **wired modem** joined to the cable. Right-click each modem
   so it turns red; it says the block's name.
3. Place this computer with a wired modem on it, joined to the same network
   (a wireless modem as well is only needed for the status server), and a
   monitor if you like.
4. Optional, but worth it with more than a few machines: put an **empty
   chest** on the cable as the [work chest](#work-chest).
5. Install and reboot. Then tap **Setup** at the top right of its monitor
   or screen, press **F1**, or run `factory setup` in a second tab: the
   [setup screen](#the-setup-screen). Check **Machines**, add what isn't
   found by itself, and pick the work chest. Everything is saved as you go.

### Furnaces

Furnaces, blast furnaces and smokers need nothing but a **wired modem** each
(they're full blocks, so a small modem goes straight on): they're found by
themselves. For a fuel chest, connect one more chest to the network, run
`storage setup` on the storage computer and pick it as the **fuel chest**,
and put some coal or charcoal in it, or in the input chest. Without a fuel
chest, furnaces burn coal and charcoal from anywhere in storage.

### Mekanism machines

For each **Enrichment Chamber** or **Energized Smelter** (or their
factories):

1. Place and power it. Open its security tab and set it to **Public**, so
   the factory can set its sides for you. Put a **wired modem** on it.
2. Give it a **feeder** with a wired modem on it: either a **hopper on
   top**, pointing down into it, or an **empty barrel** (or chest) with
   something that moves its items into the machine (see
   [Barrel feeders](#barrel-feeders)).
3. Put an **empty chest** (or barrel) **under** it with a wired modem on
   it: its **output chest**, which the factory empties into storage each
   round. (Or make the chest under it an **extra input chest** in
   `storage setup` and pick no output chest: then what it makes goes
   straight in, and several machines can share one through a pipe.)
4. On the setup screen, **Machines**, tap **+ Add an enrichment chamber**
   (or **energized smelter**): tap the machine, then its feeder, then put
   any item in its output chest (or tap **List** to pick it from a list).

### Infusers

For each **Metallurgic Infuser** (or Infusing Factory):

1. Place and power it, set its security to **Public** and put a **wired
   modem** on it. The factory then sets its sides: top **Input**, bottom
   **Output**, every other side **Extra** (where infusion items go in), and
   Auto-eject on. (Not Public: set them yourself in its side config.)
2. Its **feeder**, on top: a **hopper** pointing down into it, or an empty
   barrel with a pipe into its top.
3. Its **infusion feeder**, on any side: a **hopper** pointing sideways into
   it, or an empty barrel with a pipe into a side.
4. An **empty chest** (or barrel) **under** it: its **output chest**. It
   needs one: what's made is counted there.
5. Put a **wired modem** on each of them, joined to the storage network.
6. On the setup screen, **Machines**, tap **+ Add an infuser**: tap the
   infuser, its feeder, its infusion feeder, then put any item in its output
   chest. Or type `factory add infuser`.

### Create only

No Mekanism needed. For each crushing line, washing fan or blasting /
smoking fan:

1. Build the machine and power it. Put an **empty chest** (or barrel) by it
   with a **funnel** or chute that drops its items onto the wheels or the
   belt: the **feeder**.
2. Catch what comes out with a chute or funnel into another **empty
   chest**: the **output chest**. (Or into a storage input chest, and pick
   no output chest.)
3. Put a **wired modem** on both chests, joined to the storage network.
4. On the setup screen, **Machines**, tap **+ Add a Create crushing line**
   (or washing fan, blasting fan, smoking fan): tap its feeder, then put any
   item in its output chest. Or type `factory add crusher` (washer, fan,
   smokefan).

Several lines are fine; each gets a stack at a time. With no chambers, the
crushers take every ore in the list in `config.lua`, and smelters wait for
the crushed ores instead of smelting the raw ones.

### Cooking pots

For each pot:

1. Put a **campfire** down, light it, and put a **campfire pot** on it.
2. Put a **feed hopper** next to the pot, **pointing into its side** (sneak
   and place it against the pot). Not on top: a hopper above puts
   seasonings in the seasoning slots.
3. Put an **output hopper** under the pot, pointing sideways into a block
   that isn't a chest, so it keeps what it takes out.
4. On another side of the pot, put a **comparator** facing away from it
   (its back against the pot), and a **redstone relay** (CC: Tweaked) in
   front of the comparator. Leave the comparator in its normal mode (front
   torch off). Nothing else should power the relay.
5. Put a **wired modem** on each hopper and on the relay, join them to the
   storage network and right-click each modem: note which is which.
6. **Power the pot with redstone**, which shuts its lid: place a redstone
   block touching it, last, after the pot is on the campfire (the lid moves
   when the power changes). Keep it away from the hoppers (a powered hopper
   stops moving items) and from the comparator's sides and the relay (they
   would read it instead of the pot).
7. On the setup screen, **Machines**, tap **+ Add a cooking pot**: pick what
   it makes, its feed hopper, its output hopper and its relay. Or type
   `factory add pot`.

The storage computer has to be up to date (`install update`): older ones
only load furnaces, not hoppers.

Without a [work chest](#work-chest) the storage computer fills each feed
hopper itself, so the hoppers must be on **its** cable. If the footer says a
hopper "isn't a furnace, hopper or your feeder on my network", the storage
computer can't see it: join the hopper's modem to the storage cable (and
right-click it), or give the factory a work chest, which loads the hoppers
from the factory's own cable.

### Botany pots

Use **Hopper Botany Pots**: a plain pot doesn't let its harvest be taken
out. Stand each one on a **full-block wired modem** (craft a wired modem on
its own), join the modems with cable to the storage network and right-click
each so it turns red. A computer only sees a pot from below; a row of pots
on a row of modems works well. They're found by themselves.

Or let the pots empty themselves into a **barrel** (or chest): a Hopper
Botany Pot pushes its harvest into the block under it, so put a barrel
there, or pipe several pots into one. Put a wired modem on the barrel, join
it to the cable and right-click it, then add it on the setup screen
(**Machines**, **+ Add a botany pot barrel**) or with
`factory add potbarrel`. The pots then don't need modems. Without this the
storage computer takes the barrel for one of its storage chests and fills
it with other things, until the pots have nowhere to put their harvest. The
barrel must be empty for the storage computer to let it go: the factory
empties it first, and the Pots view shows **still storage** until it has.

For the
recipes, the storage computer needs a [crafting turtle](../crafter-turtle/README.md)
and your modpack's recipes, which include Mystical Agriculture's (see
[Modded recipes](../storage-computer/README.md#modded-recipes)); a
`pack_recipes.lua` made before the essence recipes were added has none of
them, so get it again.

### Commands

```
factory                        -- start (startup.lua does this on boot)
factory setup                  -- the setup screen (in the running factory, on its monitor)
factory add chamber            -- a Mekanism Enrichment Chamber: pick it, its feeder and output chest
factory add chamber enrichmentChamber_0 minecraft:hopper_3 minecraft:chest_4   -- or name them: machine, feeder, output
factory add smelter            -- a Mekanism Energized Smelter, the same way
factory add infuser            -- a Metallurgic Infuser: pick it, its feeder, its infusion feeder and output chest
factory add infuser metallurgicInfuser_0 minecraft:hopper_3 minecraft:hopper_4 minecraft:chest_6   -- or name them
factory add crusher            -- a Create crushing line: pick its feeder and output chest
factory add crusher minecraft:barrel_5 minecraft:chest_9   -- or name them: feeder, output
factory add washer             -- a Create washing fan (water)
factory add fan                -- a Create blasting fan (lava)
factory add smokefan           -- a Create smoking fan (fire): food only
factory add pot                -- a cooking pot: what it makes, its hoppers and its relay
factory add pot exp_candy_s minecraft:hopper_3 minecraft:hopper_4 redstone_relay_0   -- the same in one go
factory add potbarrel          -- the barrel your Hopper Botany Pots empty into: pick it
factory add potbarrel minecraft:barrel_7   -- or name it
factory relay 2                -- give cooking pot 2 its relay
factory list                   -- every machine added here, and the furnaces and pots found (and whose they are)
factory remove 2               -- forget machine 2 (no number: list them)
factory give all 14            -- hand every furnace and botany pot this computer has to factory computer 14
factory give minecraft:furnace_3 14   -- or just one
factory charcoal 256 spruce    -- make 256 charcoal from spruce logs
factory charcoal 64            -- make 64 from the logs there are most of
factory stone 512              -- make 512 stone from cobblestone
factory glass 256              -- make 256 glass from sand (or red sand)
factory glass 64 red           -- make 64 glass from red sand only
factory cancel stone           -- stop making stone ('factory cancel': every order)
factory infuse                 -- the infusing recipes, how many you can make, and what's asked for
factory infuse steel 64        -- ask for 64 steel dust (by name, or the number 'factory infuse' lists)
factory infuse cancel 2        -- cancel request 2 ('factory infuse cancel': all of them)
factory find iron              -- essence recipes for anything with "iron" in its name, and how many you can make
factory make 64 iron ingot     -- order 64 iron ingots made from essence
factory chest                  -- pick the work chest from the empty chests on the network
factory chest none             -- stop using one (what's in it goes back into storage)
factory chest remote           -- far from home: work through an ender chest (see below)
factory monitor                -- pick the monitor for the status board ('none': no board)
edit config.lua                -- what each part smelts, enriches, cooks, keeps back, names
```

On the running factory, **Tab** goes to the next tab and **F1** opens the
setup screen; the Smelter tab's **C**, **S**, **G** and **X** start and
cancel orders. `factory add`, `remove`, `relay` and the orders work from
another tab while it runs; it picks up the change straight away.

## Work chest

A chest on the storage network that the storage computer fills for the
factory in one go: each round the factory works out what every furnace and
feeder needs, asks for all of it at once, and loads them from the chest
itself. That's one request a round (one for the furnaces and smelters, one
for the chambers and crushers, one for the infusers) instead of one or two for every machine, so
the storage computer has more time for turtles, and with an ME or RS system
the items don't go through the transfer chest. The cooking pots use it too
(their feed hoppers are filled from it, so the storage computer doesn't need
to see them); the botany pots don't.

- It has to be **empty** when you pick it, and it can't be the input,
  output, fuel or transfer chest, a turtle's chest or another computer's
  work chest. With chests as storage, an empty storage chest works: it
  stops being storage.
- Anything left in it at the end of a round goes back through the input
  chest, so nothing waits there unseen. Don't put things in it by hand.
- If the chest goes missing or the storage computer won't take it, the
  footer says why and the factory loads each machine the old way until
  it's back. It asks again once a minute.
- The storage computer needs to be updated too (`install update`); an older
  one doesn't know work chests, and the factory carries on without.

### Far from the storage system

With ender chests that are shared by colour (EnderStorage or a mod like
it), the machines can be at another base. You need one ender chest pair:
one ender chest on the storage cable at home (wired modem, not picked as
any chest in `storage setup`) and its twin on the factory's own wired
network. The storage computer fills it each round, and what's made,
leftovers and anything put back go home through it too: each round the
storage computer takes out everything it didn't just send.

Put an **ender modem** on the factory and one on the storage computer, then
pick **Work chest**, **Far away** on the [setup screen](#the-setup-screen)
(or run `factory chest remote`) and pick the chest. The storage computer
finds its twin at home by dropping an item into each chest it could be
until it turns up at your end, so it needs something stored. Or pick the
twin on the storage computer first under
[Far-away workers](../storage-computer/README.md#far-away-workers) on its
setup screen (it finds the factory over the wireless or ender modem): then
there's no search.

- The ender chest needs a **wired modem on it**, joined to the factory's
  cable (one only touching the computer can't be reached from the machines).
- Put a barrel or chest under each Mekanism machine and pick it as its
  **output chest**: each round the factory moves what it made into the
  ender chest, and from there it goes home. Far away an output chest can
  already have something in it when you pick it. Or put the ender chest
  itself under a machine and pick no output chest.
- If the twin isn't found yet, Far away still sticks: what's made goes into
  the ender chest anyway, the footer says so, and it looks again every
  minute. The output chests empty into the ender chest every round even
  while the storage computer isn't answering.
- Far away the factory can only load machines through the work chest: while
  it's not in use (storage not answering, a chest gone), nothing is loaded
  and the footer says why. Both bases need to be loaded.
- The factory computers tell each other what they take over rednet, so a
  far-away one needs an ender modem for the others to hear it (or a smelter
  at home smelts the ores it would take).
- Cooking pots can be far away too: their feed hoppers are filled from the
  ender chest, and what's cooked goes home through it. Botany pots can't:
  they go through the storage input chest.

If you'd rather send things home separately, `factory chest remote` also
lets you pick a second, **return** ender chest, whose twin at home is an
**extra input chest** in `storage setup`.

## The setup screen

**Setup** at the top right of the monitor or the computer's screen, **F1**
on the computer, or `factory setup` (in a second tab, or after Ctrl+T)
opens it on the monitor and the computer at once, in the running factory
if there is one. It works like the
[storage computer's](../storage-computer/README.md#the-setup-screen):

- **Machines**: everything this factory runs, in one list.
  - **Found** furnaces, blast furnaces, smokers and botany pots, with whose
    they are: **mine**, **free**, **given away** or another computer's
    (`#14's`). Tap one of yours to give it up (another factory computer
    takes it), or someone else's to take it.
  - **Added** machines: Mekanism chambers and smelters, Create lines and
    cooking pots. Tap one to change its feeder, output chest, hoppers or
    relay, or remove it.
  - **+ Add** rows for each kind: a Mekanism machine (pick it, then its
    feeder, then its output chest), a Create line (its feeder, then its
    output chest), a cooking pot (what it makes, its hoppers, its relay).
    Mekanism's come first while there's a Mekanism machine around, else
    Create's.
  - **Picking an output chest:** put any item in it, and the factory sees
    which chest it went into (it goes into storage with the next round).
    **List** picks it from a list instead. Far away, set the work chest
    first: chests are listed, and ones that already have something in them
    are offered too.
- **Chain**: each step (ores into dust, crushed ores and nuggets; smelting
  and cooking; cooking pots; essence) and where it happens: here, on which
  other factory computers, or nowhere yet. Tap one to switch it off on this
  computer (its machines are left alone) or on again.
- **Work chest**: a chest on this cable, **Far away**, or **None**. Far away
  there's nothing to pick: work comes in through the ender chest on its
  network and what it makes goes home through the same chest (it only asks
  which when there are several). A separate return chest:
  `factory chest remote`.
- **Monitor**: which monitor shows the status board.

Chest lists show what's in each chest and go a page at a time (**<** **>**);
**Empty** shows only the empty ones, and on the computer you can type to
narrow the list. On the computer the arrow keys and Enter pick, Page Up and
Page Down turn the page, Backspace goes back, and a button's first letter
presses it (D for **Done**, B for **Back**; not on chest lists, where
typing narrows the list). Each change is saved as you make it, and the
factory uses it straight away.

## Moving from the old programs

The factory replaces the smelter, enricher, cooker and essence computers.
They update to it by themselves: on the next boot after the website has it
(or `install update`), each one installs the factory in its place and
carries on with everything it had: furnaces, chambers, Create lines, pots,
the work chest, orders in progress, the monitor and `config.lua`. The old
commands still work (`smelter charcoal 64`, `enricher add crusher`,
`cooker add`, `essence find iron`) and run the factory's; only `remove`
lists the machines first, as they're numbered across the whole factory now.
An old `config.lua`, with its settings at the top instead of under
`smelter`, `enricher` and so on, keeps working.

If two of the old programs ran on separate computers on the same cable,
they stay separate factory computers and share the work as above. To run
everything from one, `factory give all <id>` on one hands its furnaces and
botany pots over, and machines added there can be added again on the other.

## Things to know

- Machines must be on the network through a modem, not just touching this
  computer: the storage computer moves the items, and it can only reach
  what's on the cable.
- It works the same whether the storage computer keeps things in chests or
  in an [ME or RS system](../storage-computer/README.md#me-and-rs-systems).
  With an ME or RS system and no work chest, the storage computer needs a
  **transfer chest** (chosen in `storage setup`) to load the furnaces' slots
  and the pots' hopper slots.
- It asks the storage computer for everything over the cable, so both must
  be on the same wired network (far away: over ender modems). If the
  storage computer doesn't answer, the footer says so and it tries again.
- If one part fails (an error in its round), the others carry on; the tab
  of the one that failed shows the error, and it's saved in `/errors.log`.
- **Sides.** Mekanism takes items in on every side of a chamber except its
  right (output) and back (power), so the hopper on top works as it is. The
  factory sets the **bottom to Output** and turns **Auto-eject** on, but
  only when the machine's security is Public. Otherwise do it by hand in
  its side config (the wrench tab, Items), or set `setSides = false` and
  put the chest at whichever side is Output. An infuser gets more: top
  Input, bottom Output and every other side Extra, so its infusion feeder
  can go on any side but the top.
- **Speed.** A chamber on its own enriches one ore every 10 seconds; speed
  upgrades make it much faster. A hopper keeps up with a fully upgraded
  chamber; for a fast Enriching Factory use a barrel and a transporter.
- An ore that doesn't go into a chamber within a minute is put back into
  storage and not tried again until the factory restarts. If that happens
  to every ore, the hopper probably isn't pointing into the chamber, or
  nothing is moving items out of the barrel.
- In an Enriching Factory a few raw ores can be left waiting in a slot for
  the next batch; they go in once there are three.
- Coal, diamond, emerald and quartz ores give about as much with a Fortune
  III pickaxe. Take them out of `gems` under `enricher` to keep those ores
  for that.
- Making charcoal needs some fuel to start with: one coal or charcoal burns
  8 logs into 8 charcoal. A stone order only makes plain stone from
  cobblestone, not smooth stone or deepslate.
- If a furnace has fuel but doesn't smelt what's in it for 2 minutes (an
  item that doesn't smelt there, like a modded ore in a blast furnace), the
  item goes back into storage and isn't put in that kind of furnace again
  until the factory restarts.
- If the storage input chest (far away, the ender chest) is full, what's
  made waits in the furnaces, output chests and output hoppers, and the
  footer says so. Furnaces and smokers you load by hand get fuelled and
  emptied too.
- **Pots.** You can open a pot, take things out or put things in: the
  factory sees the change on its next round. Put in only what the pot's
  recipe takes, though: anything else jams it. If a pot that should be
  cooking makes nothing for 2 minutes, the tab says **not cooking!**: its
  lid is probably open (no redstone power), it's jammed, or the output
  hopper passes candy on to a chest or another hopper, so it's never seen
  coming out. Everything with a pot to go into gets used: keep some back
  with `keep` under `cooker`. Other pot recipes can be added there, as long
  as they take either different items (one each, at most 5) or one item
  several times; with Create, a recipe for XS candy from experience nuggets
  is there, commented out.
- **Essence.** No recipes? The storage computer has to know Mystical
  Agriculture's: they come from `pack_recipes.lua`, or teach one by hand
  with `crafter learn` on the crafting turtle. The list is fetched again
  every 5 minutes. The storage system picks its own recipe for an item: if
  you have iron blocks stored, an order for iron ingots may break those up
  instead of using essence. Spare seeds go to storage too; add `"_seeds$"`
  to `leave` under `essence` to leave them in the pots (a pot barrel is
  always emptied completely: nothing goes back into a pot). Pots of any kind
  work as long as they're Hopper pots whose names have `botany_pot` in
  them (`pots`).
- **Which monitor.** It uses a monitor touching it first, else the first
  one on its wired network. When several computers share a cable, they can
  take each other's: give this one its own with `factory monitor` (or
  **Monitor** on the setup screen), which lists every monitor it can see
  (the name shows when you right-click the monitor's modem); the running
  factory moves to it at once. `factory monitor none` keeps it off
  monitors. The board takes the largest text that fits.
