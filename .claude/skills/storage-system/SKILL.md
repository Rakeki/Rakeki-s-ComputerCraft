---
name: storage-system
description: How programs get items from the storage system (the storage protocol, deliveries, fuel) and have things crafted (the craft overseer, lib/crafts.lua), and how storage-computer and craft-overseer work inside (chest / ME / RS backends, fuel chest, the monitor's network view, planning, crafters, machines, modpack recipes). Use when writing a program that needs items or fuel, or changing storage-computer, crafter-turtle or craft-overseer (the factory's own workings are in the factory and factory-io skills).
---

# The storage system

`computers/storage-computer` is the **gateway** to all items. Programs never
read or empty storage chests (or an AE2 / RS system) themselves: they ask the
storage computer over rednet, protocol `storage`, and it moves items into a
chest they can reach. That's what lets every program work with chests, AE2 or
Refined Storage without changes.

It keeps items only and **knows no recipes**. Crafting is the **craft
overseer's** (`computers/craft-overseer`, protocol `craft_overseer`): the
recipe server. A program asks the storage computer for what's stored and the
overseer for the rest, through `lib/crafts.lua`, which adds the overseer's
answers to a storage reply. Keep it that way: planning in the storage
computer's single request loop made every item request wait behind it.

## Asking for items (client side)

A turtle that needs blocks has a **supply chest** next to its home, with a
wired modem on the storage cable. Facing it, the turtle calls
`claim.chest(askStorage, "delivery", "front")` (`lib/claim.lua`) once, and
from then on its deliveries go there (each turtle has its own; nothing is
picked in `storage setup`). Claim again when a `deliver` reply's `to`
isn't `"own"` (the storage computer was set up again): `claim.tracker`
does all of that (see builder.lua's `orderFromStorage`). A program whose chest
is an ender chest twin should also call `supply:arrived(r, contents)` after
each `deliver`: `ready` items that never show up in its chest, three times
running, mean the storage computer has the wrong chest, and it claims again
(the cannon feeder does). Concurrent searches never share a probe item
(`markersInUse`: the same marker in two searches once handed a cannon feeder
another program's ender chest), and `assign` puts away what waited in a
turtle's old chest unless another turtle has it. A delivery claim whose
probe arrived wins a chest a crafter holds (an empty wrong crafter chest
passes the crafter's `sameItems` check forever): the crafter record is
dropped and the crafter probes for its real one next time. Ask through a
[[lib-net]] peer:

```lua
local net = require("lib.net")
local claim = require("lib.claim")
local storage = net.peer("storage", { retry = 60 }) -- look again a minute after nobody answered
local supply = claim.tracker("delivery", 300)

local function askStorage(msg) return (storage:ask(msg)) end

-- at home, before ordering:
if supply:due() then faceSupply(); supply:check(askStorage, "front") end
local r = askStorage({ type = "deliver", items = order })
supply:seen(r)
```

- `peer:ask` matches `re` **and** `id`, so a late reply to an earlier
  request is never taken for this one.
- A program on the storage cable (factory, overseer, crafter) uses
  `{ open = "any" }`: the storage computer answers on all of its modems, so
  it needs no wireless.
- nil means "no storage system" (the second value says why): carry on with
  the home chests and tell the player, never wait forever.
- Crafting: right after the storage request, `crafts.deliver(r, order, most)`
  (has what's short and not stored made: `r.crafting`, `r.cantCraft`,
  `r.craftProblem`) or `crafts.count(r, names, need)` (`r.craftable`).
  Add `crafts` to the program's `libs`. With no overseer the replies say
  "no craft overseer answered".

| Request | Reply fields | Use |
|---|---|---|
| `{ type = "count", items = { name, ... } }` | `counts` | before starting: is there enough? (`crafts.count` adds `craftable`) |
| `{ type = "deliver", items = { [name] = n } }` | `sent`, `ready` (now in the chest), `stock` (left), `to` (`"own"`, `"delivery"` or `"output"`), `error` | tops the turtle's chest **up to** n of each (what's already there counts). Then `crafts.deliver` has what's missing made. Ask again every ~10 s while waiting. Optional `most = { [name] = n }` moves no more than n of that item this time: for a chest something else empties while the request is on its way (the cannon feeder sends what's left of each amount, so a top-up never goes past it). From the overseer, `for = id`: into that computer's own chest only (a craft terminal's order) |
| `{ type = "stock" }` | `counts` (every plain item), `input`, `fuelChest`, `fuel` (items the stored fuel smelts), `work` (the asker's work chest, if any), `workRemote` (it's an ender chest: `storage config remote` picked it, or a probe found it), `patterns` (what an ME/RS system can craft), `syscrafting` (what it's making) | the smelter, cooker and enricher; the overseer's planning stock |
| `{ type = "list" }` | `items` (each `{ name, label, count }`, plain items) | the remote terminal's search |
| `{ type = "work", chest = name }` / `{ type = "work" }` | `ok`, `chest`, `error` | name this computer's work chest (empty chests only), or stop using it (its contents are put away); use `lib/workchest.lua` |
| `{ type = "work", items = list() }`, then `{ type = "work", seen }` | as `claim` | a far-away work chest's twin, found by probe (`claim.chest(ask, "work", side)`) |
| `{ type = "fill", items = { [name] = n }, fuel = n, sweep = true or nil }` | `sent`, `ready`, `fuel`, `error`, `nochest`, `swept` | top the asker's work chest up to n of each and fuel for n smelts (what's in it counts), in one go; no crafting; `sweep` first puts away everything else in it (one ender chest both ways) |
| `{ type = "send", to = furnace, slot = 1, items = {...} }` / `slot = 2, fuel = n, item` | `sent`, `fuel`, `error` | load a furnace (only furnaces are accepted) |
| `{ type = "send", to = hopper, slot = n or nil, items = {...} }` | `sent`, `fuel`, `error` | fill a hopper (the factory's pot feed hoppers and chamber hoppers), or one of the asker's `feeders`; no slot = any slot |
| `{ type = "feeders", chests = { name, ... } }` | `ok`, `error` | the factory's barrel and chest feeders (`lib/mekfeed.lua`; the whole list each time it changes): kept out of storage (`setup.feeders[id]`) and open to `send`; a new one must be empty |
| `{ type = "claim", role = "delivery", "crafter" or "hub", items = list() }`, then `{ type = "claim", role, seen }` | `ok` + `chest`, or `probe` (an item just put in a chest it could be), or `ok = false` + `error` | use `lib/claim.lua`, never by hand; `hub` is a far-away overseer's ender chest twin, kept in `setup.crafters[overseer id]` |

The craft overseer's own requests (same protocol; only it sends these):

| Request | Reply fields | Use |
|---|---|---|
| `{ type = "crafters" }` | `crafters` (turtle id → its chest, present ones only), `shared` (`setup.crafter`) | which turtles can take a job |
| `{ type = "load", crafter = id, grid, steps }` | `steps` (batches loaded, 0 when short), `missing`, `error` | one batch into that turtle's chest; when short, the overseer orders what's `missing` (beyond `pending`), since a plan counts on stock a delivery can take before its step runs |
| `{ type = "clear", crafter = id }` | `ok` | empty its chest back into storage |
| `{ type = "syscraft", item, count }` | `ok`, `error` | the ME/RS system crafts it from its pattern (`store.craft`); counted in `stock.syscrafting` until `isCrafting` says it's done |

Protocol `craft_overseer` (everyone → craft-overseer, through `lib/crafts.lua`):

| Request | Reply fields | Use |
|---|---|---|
| `{ type = "canmake", items = { name, ... }, need = { [name] = n } }` | `counts` (how many more could be made, up to `need`, being made included), `problem` | `crafts.count` |
| `{ type = "prepare", items = { [name] = n } }` | `crafting`, `cantCraft` (name → why), `craftProblem` | start crafting so there'll be n in all (stored and being made count); `crafts.prepare`, `crafts.deliver` |
| `{ type = "craftable", have = key }` | `items` (each `{ name, label, count, stored }`: what can be made now; `count` nil = an ME/RS pattern), `ready` (false while the first count is still being worked out), `making` (each `{ name, label, count }` being crafted), `queue`, `problem`, `crafter`, `key` (which recipe list), `all` (every recipe `{ name, label, pattern }`, sorted; only when `have` isn't `key`), `wanted` (the asker's waiting orders `{ name, label, left, why }`) | the craft terminal. Asking keeps `viewLoop` running for `VIEW_KEEP` seconds |
| `{ type = "cancel", item }` | `ok` | stop waiting to make the asker's order of it |
| `{ type = "craft", item, count, to, wait }` | `making` (how many, 0 = none), `waiting` (with `wait`: how many more it's kept to make once there's enough, a standing order in `wants`), `why` (why not, or why fewer), `to` ("own": sent to the asker's chest as made, else "storage") | the craft terminal's order: `count` more, whatever is stored (`orderCraft`); with `to = "chest"` `orderLoop` has the storage computer `deliver` them `for` it (`most` = what's left of the order) |
| `{ type = "learn", recipe = { make, count, rows, keys } }` | `ok`, `error` | `crafter learn`; saved in `/.overseer_recipes` |
| `{ type = "makes", via, recipes = { { make, count, rows, keys, max } } }` | `ok` | a machine's recipes (the factory's smelter, `via = "smelt"`: one input cell each; its infuser, `via = "infuse"`; its Create saws, `via = "saw"`: one item in, `count` out, only what a sawing line can make (one-recipe items, or its filter's item); the essence farm, `via = "essence"`, with empty rows and keys and `max` goes), sent when they change and every minute; `crafting.setMachine` swaps them in, forgotten after `MACHINE_FORGET` |
| `{ type = "jobdone", job = id, ok, why }` | `ok` | from that machine, once it has made (or given up on) a job it was handed |
| `{ type = "recipes", uses = pattern }` | `recipes` (each `{ make, count, grid }`, grid cell → item name, a name with `*`, or a list; tags come as lists), `error` | the factory's essence part (`uses` = its essence pattern); `crafting.using` |
| `{ type = "claim", ... }` | as on `storage` | a crafting turtle finding its barrel on a far-away overseer's cable (hub) |

Protocol `storage_crafter` (overseer or an essence farm → crafter-turtle):
`{ type = "craft", steps, grid }` → `{ re = "crafted", made, item, error }`,
and `{ type = "ping" }` → `pong`.

Fuel: order `minecraft:coal`, then `charcoal`, then `coal_block` (first one
with `ready > 0` wins; see `STORAGE_FUEL` in builder.lua). Items with NBT
(enchanted, named) are never counted or sent. Things to report to the player:
`to == "output"` (it has no chest for you), `error`, `cantCraft[name]` unless it
is `"no recipe for it"`, `craftProblem` while `crafting` is non-empty.

Putting things away: drop them in the storage computer's **input chest**
(the factory pushes furnace output there, and its pots' output hoppers,
machines' output chests and botany pots; farms use it as their chest).

The factory (`computers/factory`) only ever asks `stock`, `send` / `fill`
and `feeders`, and empties its own chests into the input chest: its parts
are in [[factory]], how items get in and out in [[factory-io]].

**Work chests** (`lib/workchest.lua`): a factory computer can name one
empty chest on the cable (`factory chest` → `work`, recorded in
`setup.works[id]` and left out of storage; its smelter and enricher parts
share it, a `fill` each). Each round they plan
every load as before but only note it down, ask for the lot with one
`fill`, `work:move` it into each furnace slot or hopper, undo what didn't
arrive, and `work:empty(input)` the rest back. `work:check(stock)` (after
each `stock`) says whether to use it, re-claims a forgotten one once a
minute, and leaves `work.problem` for the footer; without one they fall
back to `send`. Work chests are kept in setup even while missing (a claim
needs an empty chest, and one coming back may still hold items).
Far away (`work:setRemote(supply, back)`, back optional; `<program> chest remote`) the work
chest is an ender chest: `claim.chest(ask, "work", supply)` sends `work`
with `items` / `seen`, the storage computer probes like `claim` and
`recordWork`s the twin, `stock.work` is compared with the saved `home`,
`work:input()` is where furnace output, put-backs and leftovers go: the
work chest itself with no `back` (every `fill` then carries `sweep = true`,
even with nothing to ask for, and the storage computer first puts away all
it holds beyond the items and fuel asked for; `swept` in the reply, else
the program says to update), or the return ender chest (twin = an extra
input chest). There's no `send` fallback.
Ender chests (type contains `ender`) are never storage in `chests.lua`.
The remote terminal (`computers/remote-terminal`) claims an ender chest as
its delivery chest before each `deliver` and reads `list` (`{ name, label,
count }` for every plain item); items dropped in go home with the sweep.

## Crafting (the craft overseer)

Clients never plan: `lib/crafts.lua` asks the overseer to `prepare` what a
storage reply came up short of. Inside overseer.lua `orderCraft` plans with
`freshStock()` (the storage computer's `stock`, at most `STOCK_FRESH` old)
minus what the queue uses and plus what it makes (`planningStock`), the
ME/RS system's `patterns` first (`syscraft` to the storage computer), then
`crafting.lua`. Jobs carry `id` (unique across restarts), `plan`, `grid`,
`steps`, `left`, `count`, `via` and on the last `top` (how many were asked
for); `pending(name)` (the queue's `top`s plus `syscrafting`) stops an order
being queued twice. A free turtle takes the first job whose earlier steps
are done (`nextJob`; one plan's jobs in order), has the storage computer
`load` its chest one batch at a time (`steps` back, or 0 with `missing`, which
it orders), crafts over `storage_crafter` (the job's `grid` names each cell's
item and the crafter sorts its chest by name, since barrels ignore slots; it
replies with the `item` it made), and has it `clear` the chest.

Requests go into an `inbox` (`netReceive`) and `netLoop` answers them one at
a time, like the storage computer, so none is missed while a plan runs. A
waiting request is taken before the `{ wants = true }` retry, and that retry
stops between orders when a request comes in (re-queued with `start`, `list`).
`freshStock` sends one `stock` ask at a time: others wanting it meanwhile wait
for that answer (`overseer_stock`).

Crafting turtles each claim a chest (`claim` role `crafter` →
`setup.crafters[id]` on the storage computer; `setup.crafter` is the shared
one picked in setup). Never clear crafter
chests from the storage computer: a batch may beloaded.

**Hub** (`overseer hub`, setting `overseer.hub`): an overseer far from the
storage system has an ender chest on its own cable, and each crafting
turtle's barrel on that cable. It claims the twin with role `hub` (the
storage computer keeps it as `setup.crafters[overseer id]`, but never takes
the overseer for a crafting turtle), then `load` / `clear` with
`crafter = its own id`, and moves each batch between the ender chest and
the turtle's barrel itself, one batch at a time (`withHub`). Turtles
`claim` on `craft_overseer` first (the overseer probes its own cable with
an item from the ender chest, borrowed from storage by a one-item `load`;
`/.overseer_barrels`), then on `storage`, always in that order: the storage
computer's quick check takes an empty chest it had for the turtle before as
still its own (two empty chests look alike), so asked first it would keep the
turtle off the overseer's barrel. The overseer links its ender chest before
answering a turtle's first claim, so turtles that start with it don't fall
through to the storage computer.

**Machine jobs.** A factory computer sends `makes` with its smelter's and
infuser's recipes as ordinary grids (input cells, plus enough infusion items
for one go for the infuser), tagged `via`. One factory computer per `via`:
another one's `makes` is ignored while the first was heard within
`MACHINE_FORGET`. Plans use them like any recipe, and their jobs have
`job.via`: `runMachineJobs` (`machineLoop`) sends each one that's first of its
plan to the maker (`factory` protocol, `{ type = via, job, make, count, grid }`
→ `ok` / `why`) and marks it `sent`; the factory answers with `jobdone` on
`craft_overseer`. `nextJob` never gives a turtle a machine job, and a later
step of its plan waits behind it. A failed plan
sends `cancel` for its machine jobs already handed out. A plan made only of
machine jobs needs no crafting turtle.
The essence farm (`computers/factory/farm.lua`, a far-away factory) sends
`makes` with `via = "essence"` and recipes with nothing in them (`rows = {}`,
`keys = {}`) plus `max` = goes its own essence covers: `normalize` takes an
empty grid only with `via` and `max`, and `planRecipe` keeps the goes left in
`avail` under `goesKey(r)` (a name starting with a 0 byte, which `isItem`
keeps out of the matching), so a dropped plan gives them back and no plan
asks for more. Its jobs come as `{ type = "essence", job, make, count }`; it
crafts with its own turtles (they claim their barrel on `factory_crafter`),
puts the result in its ender chest, sends an empty `fill` (sweep) and then
`jobdone`. A `cancel` on the `factory` protocol goes to every part.

Recipes (all on the overseer): `recipes.lua` (built in), `/.overseer_recipes` (taught with
`crafter learn`), and `pack_recipes.lua` (a modpack's crafting recipes from
`tools/recipes.mjs`, published in `computers/craft-overseer/packs/`, not
installed by the installer). Keys are item names, `*` globs, `#tags` or lists.
With thousands of recipes, plans must pass `reach` (`crafting.reachable(avail)`,
cached by `reachNow()` for 10 s): it prunes everything that can't be made
from what's stored. Work it out once per request, never per item
(`crafting.reachable` also keeps its last answer until the set of stored
item names or the recipes change, so asking again is cheap; a new answer is
one worklist pass over an index of which keys each item fits, built once per
`crafting.version()`). `makeable(key)` looks up a name or `#tag`'s own items
(`fits`), never every recipe; only `*` keys scan. `setMachine` with the same
recipes and only `max` changed (the essence farm) updates `max` in place and
keeps the version, so none of those caches is thrown away. The craft
terminal's list (`viewLoop`) runs only while a terminal keeps asking, and
rests `VIEW_REST` times as long as the last count took. The overseer's own
Craft tab never starts it: it lists every recipe (`allCraftable`, rebuilt when
`crafting.version()` changes) and shows `view.list`'s counts only if a
terminal has them going. Its orders go in the inbox as `{ order = ... }` (so
they plan in turn with requests) and become standing orders (`wants`, saved
in `/.overseer_wants`): `orderCraft` plans what it can, the rest is retried
every `WANT_EVERY` by `wantLoop` (`{ wants = true }` in the inbox), skipped
while some of that item is still pending.

Keep planning's cost to the recipe tree, never to how much is stored (a
modpack base stores 1000s of item types, and the craft terminal's counts run
~10 plans per craftable item): `planRecipe` finds an ingredient through
`fits(key)` (the names a key stands for, cached) and looks each up in
`avail`, and only scans all of `avail` for a `*` key; a plan works on the
caller's `avail` and undoes its own changes (`put` / `undo`, a journal)
instead of copying the stock for each recipe it tries; and it never
recolours inside a recolouring of the same group (`recolours(r)`: a recipe
whose make fits one of its own keys, black placard from any placard), which
otherwise went through all 16 colours six deep. Timed with crafting.lua
alone under Fengari (the trekt-mons pack, 1500 stored items), that took
`craftable` for 400 items from 200 s to 3 s, with the same counts.

## Inside storage-computer

- **Backends** (same functions): `chests.lua` (wired chests; `scan`, `items`,
  `space`, `putAway`, `fetch`, plus `tidy` / `roomInfo` for stack-upgraded
  storage, read with `getItemLimit`) and `bridge.lua` (Advanced Peripherals
  ME / RS Bridge; both the 0.7 `listItems` / `exportItemToPeripheral` and 0.8
  `getItems` / `exportItem` APIs, picked by which methods exist; adds
  `canCraft`, `craftables`, `craft`, `isCrafting`). The bridge can't target a
  slot, so slot moves go through the **transfer chest**.
- **Fuel chest** sits above the backend in storage.lua: fuel goes there
  first on `putAway`, `fetch(..., fuelFirst)` takes from it first, and its
  contents count as stock.
- **Special chests** (`setup`): input, output, delivery (shared), crafter,
  fuel, transfer, `works` (computer id → its work chest), `inputs` (extra input chests, emptied like `input`;
  `stock` only ever reports `input`, so returns go there), and `deliveries` (turtle id → its own chest, from
  `claim`; `claimChest` probes, `assign` records it in the setup file too,
  `storage setup` keeps them). `reserved` is per chest. Only input and output are required; a missing optional one
  turns its feature off with a footer message.
- **Loops** run in `parallel`: UI, input, rescan, `netReceive` (files requests
  in `inbox`) + `netLoop` (answers them one at a time, timing each), `quickLoop`
  (`count` / `stock` / `crafters` from their own `quick` inbox, beside it), sweep
  (keeps the delivery chest to what turtles reserved), links (the network
  view), tidy, ME/RS crafts done (`sysCraftLoop`), dump. Anything that waits
  has a deadline and a footer message.
- **Screens** draw through `lib/screen.lua` (`termScreen`, `monScreen`); the
  monitor skips unchanged frames with `same()` ([[lib-screen]]).
- **The network view** (`links`): `links.note(chest, name, n, dir)` in
  `fetch` ("out") and `putAway` ("in") keeps each served chest's moves for
  `links.WINDOW`; `links.list()` is every chest that isn't storage (setup's,
  turtles' and computers' from `setup.deliveries` / `crafters` / `works` /
  `feeders`, a dump, any ender chest), ender chests first; `linksLoop` reads
  them all at once (`links.scan`, a `list()` each) every `links.EVERY` s, only
  while a monitor shows the view; `netLoop` sets `links.busy` / `links.slow`.
  `links.draw` colours a row red (gone, full), orange (3/4 full: piling
  up), lime (moved in `ACTIVE` s). The Items view is the old item grid.
- `storage test` / `storage tidy` are the diagnostics to point players at.
- `storage dump [chest|stop]` saves `/.storage_dump` ({ chest, at, moved });
  `dumpLoop` in the running program `fetch`es everything (biggest piles
  first, fuel chest included) into that ender chest whenever it has room,
  until storage is empty or a pass with room moves nothing. Only an ender
  chest that isn't a setup, turtle or work chest can be one (`dumpProblem`);
  its twin is another storage system's input chest. `claimable` skips it,
  so probes never fall through to the other side.

Related: [[factory]], [[factory-io]], [[item-rules]], [[performance]], [[mod-recipes]], [[new-computer]], [[lib-report]], [[lib-errlog]].
