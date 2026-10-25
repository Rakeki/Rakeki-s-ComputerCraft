---
name: storage-system
description: How programs get items from the storage system (the storage protocol, deliveries, crafting on request, fuel) and how storage-computer works inside (chest / ME / RS backends, fuel chest, crafter, smelter, modpack recipes). Use when writing a program that needs items or fuel, or changing storage-computer, crafter-turtle or smelter-computer.
---

# The storage system

`computers/storage-computer` is the **gateway** to all items. Programs never
read or empty storage chests (or an AE2 / RS system) themselves: they ask the
storage computer over rednet, protocol `storage`, and it moves items into a
chest they can reach. That's what lets every program work with chests, AE2 or
Refined Storage without changes.

## Asking for items (client side)

A turtle that needs blocks has a **supply chest** next to its home, and that
chest is the storage computer's **delivery chest** (`storage setup`). Copy
`askStorage` from `computers/builder-turtle/builder.lua` (or village.lua):

```lua
local STORAGE_PROTOCOL = "storage"
local STORAGE_WAIT = 10 -- seconds to wait for an answer
local storageId, noStorageUntil, requestId = nil, 0, 0

local function askStorage(msg)
  if os.clock() < noStorageUntil or not openModem() then return nil end
  storageId = storageId or rednet.lookup(STORAGE_PROTOCOL)
  if not storageId then noStorageUntil = os.clock() + 60 return nil end -- don't look again for a minute
  requestId = requestId + 1
  msg.id = requestId
  rednet.send(storageId, msg, STORAGE_PROTOCOL)
  local deadline = os.clock() + STORAGE_WAIT
  while os.clock() < deadline do
    local from, reply = rednet.receive(STORAGE_PROTOCOL, math.max(0.1, deadline - os.clock()))
    if from == storageId and type(reply) == "table" and reply.re == msg.type and reply.id == msg.id then return reply end
  end
  storageId = nil -- gone quiet: look it up again next time
  return nil
end
```

- Check `re` **and** `id`: a late reply to an earlier request must never be
  taken for this one.
- `openModem()` opens every modem (wireless or wired): the storage computer
  answers on all of its modems, so a program on its cable needs no wireless.
- nil means "no storage system": carry on with the home chests and tell the
  player, never wait forever.

| Request | Reply fields | Use |
|---|---|---|
| `{ type = "count", items = { name, ... }, need = { [name] = n } }` | `counts`, `craftable` (how many more could be crafted, up to `need`) | before starting: is there enough? Add `craftable` to `counts`. |
| `{ type = "deliver", items = { [name] = n } }` | `sent`, `ready` (now in the chest), `stock` (left), `crafting`, `cantCraft` (name → why), `craftProblem`, `to` (`"delivery"` or `"output"`), `error` | tops the delivery chest **up to** n of each (what's already there counts) and **starts crafting** what's missing. Ask again every ~10 s while waiting. |
| `{ type = "prepare", items = { [name] = n } }` | `crafting`, `cantCraft`, `craftProblem` | start crafting what a coming job lacks, before it's needed |
| `{ type = "stock" }` | `counts` (every plain item), `input`, `fuelChest`, `fuel` (items the stored fuel smelts) | the smelter |
| `{ type = "send", to = furnace, slot = 1, items = {...} }` / `slot = 2, fuel = n, item` | `sent`, `fuel`, `error` | load a furnace (only furnaces are accepted) |
| `{ type = "learn", recipe = { make, count, rows, keys } }` | `ok`, `error` | `crafter learn` |

Fuel: order `minecraft:coal`, then `charcoal`, then `coal_block` (first one
with `ready > 0` wins; see `STORAGE_FUEL` in builder.lua). Items with NBT
(enchanted, named) are never counted or sent. Things to report to the player:
`to == "output"` (no delivery chest set), `error`, `cantCraft[name]` unless it
is `"no recipe for it"`, `craftProblem` while `crafting` is non-empty.

Putting things away: drop them in the storage computer's **input chest**
(the smelter pushes furnace output there; farms use it as their chest).

## Crafting on request

Crafting is never a separate step for clients: `deliver` and `prepare` plan
and queue crafts for anything missing. Inside storage.lua `orderCraft` uses
the ME/RS system's patterns first (bridge mode), then the crafting turtle
(`crafting.lua` plans, `storage_crafter` protocol carries one batch at a
time; the job's `grid` names each cell's item and the crafter sorts its chest
by name, since barrels ignore slots; it replies with the `item` it made).
`pendingCraft` stops an order being queued twice.

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
- **Special chests** (`setup`): input, output, delivery, crafter, fuel,
  transfer. Only input and output are required; a missing optional one
  turns its feature off with a footer message.
- **Loops** run in `parallel`: UI, input, rescan, `netReceive` (files requests
  in `inbox`) + `netLoop` (answers them one at a time), sweep (keeps the
  delivery chest to what turtles reserved), craft, tidy, output, craft view.
  Anything that waits has a deadline and a footer message.
- **Screens** draw into hidden windows (`frameFor`); the monitor skips
  unchanged frames.
- `storage test` / `storage tidy` are the diagnostics to point players at.

Related: [[new-computer]], [[lib-report]], [[lib-errlog]].
