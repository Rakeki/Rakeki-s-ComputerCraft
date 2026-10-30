---
name: storage-system
description: How programs get items from the storage system (the storage protocol, deliveries, crafting on request, fuel) and how storage-computer works inside (chest / ME / RS backends, fuel chest, crafter, smelter, modpack recipes). Use when writing a program that needs items or fuel, or changing storage-computer, crafter-turtle, craft-overseer, smelter-computer or cooker-computer.
---

# The storage system

`computers/storage-computer` is the **gateway** to all items. Programs never
read or empty storage chests (or an AE2 / RS system) themselves: they ask the
storage computer over rednet, protocol `storage`, and it moves items into a
chest they can reach. That's what lets every program work with chests, AE2 or
Refined Storage without changes.

## Asking for items (client side)

A turtle that needs blocks has a **supply chest** next to its home, with a
wired modem on the storage cable. Facing it, the turtle calls
`claim.chest(askStorage, "delivery", "front")` (`lib/claim.lua`) once, and
from then on its deliveries go there (each turtle has its own; nothing is
picked in `storage setup`). Claim again when a `deliver` reply's `to`
isn't `"own"` (the storage computer was set up again): `claim.tracker`
does all of that (see builder.lua's `orderFromStorage`). Ask through a
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
- A program on the storage cable (smelter, cooker, overseer, crafter) uses
  `{ open = "any" }`: the storage computer answers on all of its modems, so
  it needs no wireless.
- nil means "no storage system" (the second value says why): carry on with
  the home chests and tell the player, never wait forever.

| Request | Reply fields | Use |
|---|---|---|
| `{ type = "count", items = { name, ... }, need = { [name] = n } }` | `counts`, `craftable` (how many more could be crafted, up to `need`) | before starting: is there enough? Add `craftable` to `counts`. |
| `{ type = "deliver", items = { [name] = n } }` | `sent`, `ready` (now in the chest), `stock` (left), `crafting`, `cantCraft` (name → why), `craftProblem`, `to` (`"own"`, `"delivery"` or `"output"`), `error` | tops the turtle's chest **up to** n of each (what's already there counts) and **starts crafting** what's missing. Ask again every ~10 s while waiting. |
| `{ type = "prepare", items = { [name] = n } }` | `crafting`, `cantCraft`, `craftProblem` | start crafting what a coming job lacks, before it's needed |
| `{ type = "stock" }` | `counts` (every plain item), `input`, `fuelChest`, `fuel` (items the stored fuel smelts), `work` (the asker's work chest, if any) | the smelter, cooker and enricher |
| `{ type = "list" }` | `items` (each `{ name, label, count }`, plain items) | the remote terminal's search |
| `{ type = "work", chest = name }` / `{ type = "work" }` | `ok`, `chest`, `error` | name this computer's work chest (empty chests only), or stop using it (its contents are put away); use `lib/workchest.lua` |
| `{ type = "work", items = list() }`, then `{ type = "work", seen }` | as `claim` | a far-away work chest's twin, found by probe (`claim.chest(ask, "work", side)`) |
| `{ type = "fill", items = { [name] = n }, fuel = n, sweep = true or nil }` | `sent`, `ready`, `fuel`, `error`, `nochest`, `swept` | top the asker's work chest up to n of each and fuel for n smelts (what's in it counts), in one go; no crafting; `sweep` first puts away everything else in it (one ender chest both ways) |
| `{ type = "send", to = furnace, slot = 1, items = {...} }` / `slot = 2, fuel = n, item` | `sent`, `fuel`, `error` | load a furnace (only furnaces are accepted) |
| `{ type = "send", to = hopper, slot = n or nil, items = {...} }` | `sent`, `fuel`, `error` | fill a hopper (the cooker's pot feed hoppers, the enricher's chamber hoppers), or one of the asker's `feeders`; no slot = any slot |
| `{ type = "feeders", chests = { name, ... } }` | `ok`, `error` | the enricher's and smelter's barrel and chest feeders (`lib/mekfeed.lua`; the whole list each time it changes): kept out of storage (`setup.feeders[id]`) and open to `send`; a new one must be empty |
| `{ type = "learn", recipe = { make, count, rows, keys } }` | `ok`, `error` | `crafter learn` |
| `{ type = "recipes", uses = pattern }` | `recipes` (each `{ make, count, grid }`, grid cell → item name, a name with `*`, or a list; tags come as lists), `error` | the essence computer (`uses` = its essence pattern); `crafting.using` |
| `{ type = "claim", role = "delivery" or "crafter", items = list() }`, then `{ type = "claim", role, seen }` | `ok` + `chest`, or `probe` (an item just put in a chest it could be), or `ok = false` + `error` | use `lib/claim.lua`, never by hand |

The craft overseer's own requests (same protocol; only it sends these):

| Request | Reply fields | Use |
|---|---|---|
| `{ type = "crafters" }` | `crafters` (turtle id → its chest, present ones only), `shared` (`setup.crafter`) | which turtles can take a job |
| `{ type = "load", crafter = id, grid, steps }` | `steps` (batches loaded, 0 when short), `missing`, `error` | one batch into that turtle's chest |
| `{ type = "clear", crafter = id }` | `ok` | empty its chest back into storage |
| `{ type = "jobdone", job = id, ok, why }` | `ok` | → `jobFinished` (fixes `pendingCraft`, drops the rest of a failed plan) |
| `{ type = "problem", text }` | `ok` | why crafting is stuck (nil: it isn't); shown to turtles as `craftProblem` |

Protocol `storage_crafter` (storage computer or overseer → crafter-turtle):
`{ type = "craft", steps, grid }` → `{ re = "crafted", made, item, error }`,
and `{ type = "ping" }` → `pong`.

Fuel: order `minecraft:coal`, then `charcoal`, then `coal_block` (first one
with `ready > 0` wins; see `STORAGE_FUEL` in builder.lua). Items with NBT
(enchanted, named) are never counted or sent. Things to report to the player:
`to == "output"` (it has no chest for you), `error`, `cantCraft[name]` unless it
is `"no recipe for it"`, `craftProblem` while `crafting` is non-empty.

Putting things away: drop them in the storage computer's **input chest**
(the smelter pushes furnace output there, the cooker its pots' output
hoppers; farms use it as their chest).

The smelter and cooker only ever `stock`, `send` and empty into the input
chest. The essence computer empties Hopper Botany Pots into the input chest
itself (`pushItems` from the pot: a pot shows only its 12 harvest slots, only
through its bottom face, and only a hopper pot lets them be taken, so each pot
stands on a full-block wired modem), and orders crafts with `prepare` set to
stored + already crafting + wanted (`prepare` tops up to a total). The smelter's orders (`ORDERS` in smelter.lua: charcoal from logs into
the fuel chest, stone from cobblestone) each have their own save file and go
into plain furnaces ahead of ores, in that order. The cooker can't see inside
a pot: a comparator into a redstone relay says how full it is, and it sends
the feed hopper only what still fits.
**Work chests** (`lib/workchest.lua`): the smelter and enricher can each name
an empty chest on the cable (`smelter chest`, `enricher chest` → `work`,
recorded in `setup.works[id]` and left out of storage). Each round they plan
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
The enricher fills a feeder for each Mekanism Enrichment Chamber (CC
can't reach a Mekanism machine's slots: its own peripheral hides them): a
hopper on top, or a barrel a pipe pulls from into the chamber, which it
registers with `feeders` so it isn't storage; and
the chamber auto-ejects dust into an extra input chest under it. The smelter
asks the enricher (`enricher` protocol, `takes` → Lua patterns) which ores to
leave alone, and smelts the dust.

## Crafting on request

Crafting is never a separate step for clients: `deliver` and `prepare` plan
and queue crafts for anything missing. Inside storage.lua `orderCraft` uses
the ME/RS system's patterns first (bridge mode), then the crafting turtle
(`crafting.lua` plans, `storage_crafter` protocol carries one batch at a
time; the job's `grid` names each cell's item and the crafter sorts its chest
by name, since barrels ignore slots; it replies with the `item` it made).
`pendingCraft` stops an order being queued twice.

Crafting turtles each claim a chest (`claim` role `crafter` →
`setup.crafters[id]`; `setup.crafter` is the shared one picked in setup).
With a **craft overseer** (`computers/craft-overseer`, protocol
`craft_overseer`) the storage computer still plans, then `handOver` sends
the unsent jobs (`id` unique across restarts, `plan`, `grid`, `steps`,
`count`, `top`). The overseer picks a free turtle per job (one plan's jobs
in order), asks the storage computer to `load` that turtle's chest one batch
at a time (`steps` back, or 0 with `missing`), crafts over `storage_crafter`,
asks it to `clear` the chest, and sends `jobdone` (→ `jobFinished`, which
fixes `pendingCraft` and drops the rest of a failed plan). Without an
overseer, `craftLoop` runs jobs on one turtle itself. Never clear crafter
chests from the storage computer while an overseer is about: a batch may be
loaded.

Recipes: `recipes.lua` (built in), `/.storage_recipes` (taught with
`crafter learn`), and `pack_recipes.lua` (a modpack's crafting recipes from
`tools/recipes.mjs`, published in `computers/storage-computer/packs/`, not
installed by the installer). Keys are item names, `*` globs, `#tags` or lists.
With thousands of recipes, plans must pass `reach` (`crafting.reachable(avail)`,
cached by `reachNow()` for 10 s): it prunes everything that can't be made
from what's stored. Work it out once per request, never per item. The
Craftable tab (`CRAFTABLE_TAB`) is off by default because listing every
craftable item takes too long.

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
  in `inbox`) + `netLoop` (answers them one at a time), sweep (keeps the
  delivery chest to what turtles reserved), craft, tidy, output, craft view.
  Anything that waits has a deadline and a footer message.
- **Screens** draw through `lib/screen.lua` (`termScreen`, `monScreen`); the
  monitor skips unchanged frames with `same()` ([[lib-screen]]).
- `storage test` / `storage tidy` are the diagnostics to point players at.
- `storage dump [chest|stop]` saves `/.storage_dump` ({ chest, at, moved });
  `dumpLoop` in the running program `fetch`es everything (biggest piles
  first, fuel chest included) into that ender chest whenever it has room,
  until storage is empty or a pass with room moves nothing. Only an ender
  chest that isn't a setup, turtle or work chest can be one (`dumpProblem`);
  its twin is another storage system's input chest. `claimable` skips it,
  so probes never fall through to the other side.

Related: [[new-computer]], [[lib-report]], [[lib-errlog]].
