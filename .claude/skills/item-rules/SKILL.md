---
name: item-rules
description: The rules every program here follows with items and chests - only the storage computer takes items out of storage, everything goes back through an input chest, chests are found by probing (claim) never picked by hand for turtles, only empty chests change role, ender chests are never storage, items are matched by name never by slot, NBT items are left alone, keep amounts and the chain decide who takes what. Use before writing anything that moves, counts, reserves or picks chests or items, or when items go missing, double up or end up in the wrong chest.
---

# Item and chest rules

These hold across the storage computer, the craft overseer, the factory
and every turtle. Breaking one is how items went missing or doubled before.

## Who moves what

1. **Only the storage computer takes items out of storage** (chests or an
   ME / RS system). It caches chest contents; anyone else reading or
   emptying a storage chest makes that cache wrong. Programs ask over
   `storage` (`deliver`, `send`, `fill`, `load`) — see [[storage-system]].
2. **Everything goes back through an input chest**: the storage computer's
   `stock.input` (or an extra input chest from `storage setup`), far away
   the ender chest twin. Programs may `pushItems` their **own** chests
   (output chests, furnace output, a turtle's inventory) into it; never
   into a storage chest directly.
3. **Programs never talk to a store directly** (`chests.lua` / `bridge.lua`
   are the storage computer's): new programs use `storage` messages, so they
   work with chests, AE2 and RS alike.
4. **Recipes live on the craft overseer only.** Ask for crafting through
   `lib/crafts.lua`; the storage computer knows none.

## Which chest is whose

- A chest is **storage** unless the storage computer was told otherwise:
  setup chests (input, output, delivery, crafter, fuel, transfer),
  `deliveries` / `crafters` (turtles' chests, from `claim`), `works` (work
  chests), `feeders` (a computer's machine barrels), `inputs`.
- **A chest only changes role while empty.** The storage computer only
  takes a new feeder, work chest or claimed chest when it's empty, so a
  full storage chest is never taken by a slip of the finger. Programs that
  pick chests list every chest with its contents and refuse a full one
  (near storage) with a message to empty it; far away (nothing there is
  storage) anything goes.
- **Turtles find their own chest by probe** (`lib/claim.lua`): the turtle
  sends its chest's `list()`, the storage computer drops one item into
  each chest that could be it until the turtle sees it arrive. Never ask
  the player to pick a turtle's chest in `storage setup`. Concurrent
  searches never share a probe item (`markersInUse`).
- **Ender chests are never storage** (any peripheral type containing
  `ender`): their items are shared with a twin somewhere else. They're
  links: a far-away work chest (one chest both ways, swept each `fill`), a
  remote terminal's delivery chest, a hub, a dump. Never an output that
  "goes home by itself" when what's made must be counted.
- Optional chests that go missing turn their feature off with a message;
  only input and output are required.

## Matching items

- **By name, never by slot.** Barrels with stack upgrades (and many mod
  inventories) ignore slot order. Craft jobs carry the grid as cell → item
  name and the crafter sorts by name; the crafter reports what it made, so
  a wrong craft is caught.
- **Items with NBT / components** (enchanted, named, damaged tools) are
  never counted or sent as plain items.
- Recipes key items by id, `*` globs, `#tags` or lists; tags come from the
  pack's data ([[mod-recipes]]).

## Counting and reserving

- `deliver` tops a chest **up to** n (what's there counts); `most` caps one
  move for a chest something else empties meanwhile.
- `prepare` tops up to a **total** (stored + being made count), so asking
  again never doubles an order. `pending` stops the overseer queueing the
  same thing twice.
- A request counts what came out by name (`credit`: oldest first, up to
  what it still needs) from the chests it empties itself; what it can't
  see arrive can't be counted.
- **Keep amounts** (`config.keep`): what a part leaves in storage (seed
  potatoes, a stack of logs).
- **The chain** (the factory's ranks): a part leaves items an earlier part
  takes (`takes()` patterns, shared between factory computers), so the
  smelter doesn't smelt what the enricher or a request is waiting on.

## Fuel

Order `minecraft:coal`, then `charcoal`, then `coal_block`; the fuel chest
is filled first on `putAway` and taken from first. `turtle.getFuelLevel()`
may be `"unlimited"`: treat it as `math.huge` (`lib/inv.lua`).

## Junk

Turtles drop cobblestone, cobbled_deepslate, stone, deepslate, dirt,
gravel, andesite, diorite, granite, tuff, calcite, netherrack (the junk
list in AGENTS.md); everything else goes home.

Related: [[storage-system]], [[factory-io]], [[lib-net]] (inv), [[turtle-job]].
