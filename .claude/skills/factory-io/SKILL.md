---
name: factory-io
description: How the factory gets items into its machines and results back into storage - send vs the work chest (fill, move, empty), feeders (hoppers, barrels, registering them so they aren't storage), output chests and collect, crediting requests, Create lines CC can't see, far-away factories through ender chests, and the cable mistakes behind "I can't see ...". Also lib/mekfeed.lua and lib/workchest.lua. Use when a machine isn't being fed or its output isn't counted, or when adding a machine, line kind or chest role.
---

# Items in and out of the factory

Two rules shape everything:

1. **Only the storage computer takes items out of storage.** The factory
   never reads or empties a storage chest: it asks (`send`, or `fill` into
   its work chest) and the storage computer moves the items.
2. **Results go back through an input chest** (the storage computer's
   `stock.input`, far away `work:input()`), which the storage computer
   sweeps. The factory may `pushItems` from its own output chests into it.

So every chest a machine uses is either storage (the storage computer's),
or a chest the storage computer has been told **isn't** storage.

## Getting items in

**CC can't reach most machines' slots**: Mekanism hides them behind its
computer port; Create machines aren't peripherals at all; a cooking pot
shows nothing. So each machine has a **feeder** that the program can fill
and that empties into the machine by itself:

| Machine | Feeder |
|---|---|
| furnace / blast furnace / smoker | none: `send` targets the furnace's slot 1 (input) or 2 (fuel) |
| AE2 inscriber / charger / vibration chamber | none: `send` targets the inscriber's slot 1 top, 2 bottom, 3 middle (4 is the result, taken out with `pushItems`), the charger's one slot, or the chamber's fuel (`fuel = n`) |
| Mekanism machine | a hopper on top (pointing down), or a barrel/chest a pipe (logistical transporter set to pull, a funnel) empties into it |
| infuser | the above for its input, plus an **extra** feeder into a side (infusion items) |
| Create line (crusher, washer, fans, saw) | a chest a funnel or chute empties onto the wheels/belt |
| cooking pot | a feed hopper into its side (never more than the pot can take: see cook.lua) |

**Feeders must be registered.** A barrel or chest on the storage cable is
storage to the storage computer (it would fill it with other things), so
`mekfeed.register(sets, remote, storageId)` sends one `feeders` list with
every barrel and chest feeder and output chest of every set on this
computer (hoppers and ender chests are left out: never storage). The
storage computer only takes a chest it didn't have before when it's
**empty**, which is what keeps a full storage barrel from being taken by
mistake. Until it says yes, those feeders are `unsure` and aren't filled;
`feedProblem` explains why (now with which cable, see below).

**Two ways to fill feeders**, chosen each round by `work:check(stock)`:

- **`send`** (no work chest): `f.ask({ type = "send", to = feeder, items = { [name] = n } })`
  per machine. Simple, one request per machine per round.
- **The work chest** (`lib/workchest.lua`): one empty chest on the cable,
  `setup.works[id]` on the storage computer. Each part **plans** every load
  (`plan[#plan+1] = { m, name, n }`), asks for the lot with one
  `work:fill(items, fuel)`, then `work:move(name, feeder, slot, n)` into each
  machine, **undoes what didn't arrive** (`mekfeed.added(m, name, got - n)`,
  request `sent` too), and `work:empty(input)` sends the rest back. Far
  away there's no `send` fallback.

What a feeder holds is tracked through the round: `mekfeed.added(m, name, n)`
after each load, `mekfeed.space(m, name)` for how much more, `mekfeed.current(m)`
for what it's on. A Create line's feeder is kept at `m.fill` (a stack).

**Stuck items** (`set:unstick`): an item sitting in a feeder over an empty,
powered machine for a minute goes back to input (wrong item, missing pipe).
Create lines show red **not moving** instead (`m.stalled`: feeder hasn't
gone down in `LINE_STUCK` s).

## Getting results out

- **Furnaces:** the factory pushes the output slot into input.
- **An output chest** (under a Mekanism machine, at the end of a Create
  belt): `set:collect(machines, input)` pushes everything into input each
  round and returns `moved, stuck, why, byName`. `byName` (item → count) is
  what requests are **credited** from (`credit`: oldest request first, up to
  what it still needs). `needOutput` (the infuser, a saw line) makes one
  required, because without it nothing can be counted.
- **No output chest:** the machine ejects straight into a storage input
  chest (an extra one from `storage setup`). Fine for by-itself parts
  (ores into dust); can't count.
- **Not an ender chest per machine.** Machines away from the storage cable
  use the one-ender-chest layout below, never a separate ender chest as an
  output: what goes home by itself can't be counted (an ender-output saw
  line was tried, counting from stored counts going up, and dropped for
  this). One pattern everywhere: the far-away factory, the craft overseer's
  hub, the remote terminal.
- **Uncut / unmade:** the input itself showing up in an output chest means
  the machine had no recipe (or a Create saw's filter is wrong): the request
  ends with a message.
- **Fewer than the recipe says:** when everything's sent, nothing's in a
  feeder and nothing came for `SHORT_AFTER`, send the shortfall again
  (saw.lua).

## Machines CC can't see (Create lines)

A line is `{ line = kind, feeder, output, filter? }` in the set's save file
(`/.<set>_machines`). All the computer knows is the feeder: it's **moving**
when its count went down since last round or something came out, **stalled**
after `LINE_STUCK` s without. No power, speed or recipe can be read, so:

- what it makes must come from data (the saw's recipe files, see
  [[mod-recipes]]), never from the machine;
- anything the player sets on the machine (a saw's **filter**) must be told
  to the program too (the line's page, `factory saw filter`), and the
  program must only send what that setting can make. An unfiltered saw
  cycles through an item's recipes (Create's `recipeIndex`), so a line with
  no filter only gets items with exactly one recipe.

## Far away: one ender chest both ways

A factory on its own cable (no wired path to the storage computer; it talks
over rednet, an ender modem if it's far) has **one ender chest** with a
wired modem on that cable, next to the machines, and the feeders and output
chests on the same cable. Nothing to set: each round `work:auto(stock)`
sees the factory can't see `stock.input` (`workchest.onStorageCable`),
and with exactly one ender chest on the cable calls `work:setRemote(it)`
by itself; with none or several the parts say so and nothing is loaded
(no `feeders` either, so no "I can't see" error). The setup screen leads
with **Items come and go** (orange until linked), `work:setupPage` offers
only the ender chest off the storage cable. It's
`work:setRemote(supply, back)`: an ender chest pair whose twin at home is
found by probe (`claim.chest(ask, "work", side)`, like a turtle's chest).
Everything comes in through it with `fill`, and goes home through it:
`work:input()` is the ender chest (every `fill` then carries `sweep = true`
so the storage computer puts away what wasn't asked for), or a second
return pair. Nothing on a far cable is storage, so any barrel can be picked
there, and nothing is registered (`remote`).

## Cables: "I can't see minecraft:barrel_93"

That's the **storage computer** answering `feeders`: the factory sees the
chest, the storage computer doesn't. Their wired networks differ. Usual
causes: the factory has a second wired modem whose cable holds the machines
and never joins the storage cable; or the factory reaches the storage
computer only wirelessly (then it should be Far away). `cableHint` in
mekfeed.register works out which: the wired modem that `isPresentRemote`s
the chest, and the one whose `getNamesRemote` includes a computer whose
`getID()` is the storage computer (only visible when that computer's modem
is switched on). Peripheral names (`barrel_93`) are per world, not per
network, so the same name on both doesn't mean the same network.

## Picking chests

Setup pages and `factory add` list **every** barrel, chest (and hopper,
for feeders) on the cable with what's in it
(`chestNote`, `setupui.contents`), never a filtered "free" list: players
couldn't find their barrel when empty-only lists hid it. Picking one with
items in it is refused near storage (`emptyEnough`: most likely a storage
chest, and the storage computer would refuse it anyway); far away anything
goes. Ones another machine uses are marked, not hidden.

## The libraries

- `lib/mekfeed.lua`: a **set** of machines and lines (`mekfeed.new(opts)`):
  `read` (all at once, `parallel.waitForAll`), `register`, `unstick`,
  `collect`, `add` / `command` (terminal), `setupParts(ui)` (setup rows;
  `opts.lineRows(ui, i, entry, change)` adds rows to a line's page),
  `ready`, `space`, `current`, `status` (board colour + words). Opts:
  `single`/`factory` (Mekanism peripheral types; omit for lines only),
  `lines`, `extra` (second feeder), `needOutput`, `sides`, `read`, `names`.
- `lib/workchest.lua`: `new(name, ask, older)`, `set`, `setRemote`,
  `check(stock)`, `input(stockInput)`, `fill`, `move`, `empty`, `setupPage`,
  `problem`, `remote`. Saved in `/.<name>_chest`.

Related: [[factory]], [[storage-system]] (`send`, `fill`, `feeders`, `work`),
[[item-rules]], [[performance]].
