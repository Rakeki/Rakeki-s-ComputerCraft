---
name: performance
description: Keeping ComputerCraft programs fast and alive - yielding in long work (breathe with tickets, "too long without yielding"), peripheral calls that cost a game tick (read everything at once with parallel), caching per round instead of per item, files and big data on a 1 MB disk, rednet message size, inboxes so requests aren't lost, redrawing only on change, expensive views that rest, and plans that cost the recipe tree not the stock. Use when writing a loop over many items, recipes, chests or machines, when something stalls, lags or freezes, or before adding a big data file.
---

# Performance on CC computers

A CC computer runs Lua on the server, a slice at a time, and stops a
program that runs **~7 s without yielding** ("Too long without yielding").
Most peripheral methods run on the **game's main thread**: each call waits
for the next tick (50 ms). Both shape everything below.

## Yield in long work

Any loop that can run thousands of times (planning, scanning chests,
listing recipes) calls `breathe()` now and then:

```lua
local YIELD_AFTER = 0.05 -- seconds of work before letting the screens and requests have a turn
local calls, tickets, yieldedAt = 0, 0, os.clock()
local function breathe()
  calls = calls + 1
  if calls % 10 == 0 and (calls % 1000 == 0 or os.clock() - yieldedAt >= YIELD_AFTER) then
    tickets = tickets + 1
    local mine = tickets
    os.queueEvent("crafting_yield", mine) -- its own event name per module
    repeat local _, ticket = os.pullEvent("crafting_yield") until ticket == mine
    yieldedAt = os.clock()
  end
end
```

The **ticket** matters: with one shared event, every loop waiting on a
yield woke on each one and ran another slice, so a tap waited rounds of
all of them. Only `pullEvent` your own ticket. (Copies: `crafting.lua`,
`chests.lua`.)

## Peripheral calls: all at once

Inventory methods (`list`, `pushItems`, `getItemDetail`), Mekanism methods
and most mod peripherals cost a tick each. Reading 40 chests one by one is
2 s; in parallel it's one tick:

```lua
local jobs = {}
for _, name in ipairs(names) do
  jobs[#jobs + 1] = function() out[name] = peripheral.call(name, "list") end
end
parallel.waitForAll(table.unpack(jobs))
```

`mekfeed`'s `read`, `setupui.contents`, the storage computer's `links.scan`
and the Mekanism programs all do this. Don't call a peripheral inside a
loop over recipes or items; read once, then work on the tables.

`peripheral.getNames()` / `getType` on every name is cheap but not free:
the factory keeps "has this part got machines" for `ACTIVE_EVERY` (2 s)
and forgets it on `peripheral` / `peripheral_detach`.

## Cache per round, not per item

A function called per recipe must not read a file or the network. The
saw's first `anyLine(rc)` called `set:entries()` (a file read) for each of
12,000 recipes every round; now `refreshLines()` reads the lines once per
round (and per command) into `lineList`. Same idea: one `stock` per factory
round for every part; `crafting.reachable` worked out once per request and
passed in as `reach`, never per item; `fits(key)` cached.

## Plans cost the recipe tree, never the stock

A modpack base stores 1000s of item types. Look each ingredient up by name
(`avail[name]`); scan all of `avail` only for a `*` key; undo changes with a
journal instead of copying the stock per recipe tried; prune with `reach`.
Measured with crafting.lua alone under Fengari (trekt-mons pack): the craft
terminal's 400 counts went from 200 s to 3 s with the same answers.

## Big data: disk, memory, messages

- A computer has **1 MB of disk** by default. Data files number their
  item names (`names = { ... }`, rows of numbers): `pack_recipes.lua`
  (700 KB), `atmons-saw.lua` (280 KB for 12,000 recipes). Load with
  `loadfile(path, "t", {})` (no globals) inside `pcall`, once at start.
- Build lookups once (`byFrom`, `byKey`, `byMake`), and compute display
  strings lazily (`titleOf(rc)`), not for every row at load.
- **Rednet messages are serialized whole**: send what the other side can
  use, not everything. The saw offers the overseer only recipes a line can
  make now (~250), not its 12,000. Send a list again only when its key
  changed (`makesKey`), with a slow refresh (`MAKES_EVERY`).
- Save request files only when something changed (`dirty`), not every round.

## Never lose a request

A server that does slow work answers from an **inbox**: one loop
(`netReceive`) files every message, another (`netLoop`) answers them one at
a time. A request arriving mid-plan is then queued, not dropped (the
storage computer, the overseer). Everything that waits for a reply has a
deadline (`net.ask` / `peer:ask` with `wait`) and says on screen what it's
waiting for.

## Screens

Draw through `lib/screen.lua` and skip unchanged frames (`s:same(key)`;
the key is every value the frame shows). Redraw at once on input events,
`REDRAW_GAP` (0.2 s) after change events (a burst draws once), and every
`REDRAW_EVERY` (2 s) otherwise; **not** on every event: on a busy network,
redrawing on each rednet message kept the factory busy. See [[lib-screen]].

## Expensive views rest

Work that only a screen needs runs only while it's shown and rests in
proportion to its cost: the craft terminal's counts (`viewLoop`) run while
a terminal keeps asking (`VIEW_KEEP`) and rest `VIEW_REST` × the last
run; the storage computer's network view scans only while a monitor shows
it.

## Turtles and chunks

Turtles freeze when their chunk unloads and restart from `startup.lua`:
anything long is a resumable job ([[turtle-job]]). Don't rely on a timer
outliving a chunk unload.

## Finding what's slow

- `os.clock()` around a suspect section, printed or logged (`f.log`).
- Headless: run the module under Fengari with stubs and time it
  ([[testing]]): planning, recipe loading and parsing are pure Lua.
- In the sim, a frozen simulated clock means some computer is stuck in
  heavy Lua without yielding (see the sim memory / sim/README.md).

Related: [[storage-system]], [[factory]], [[lib-net]], [[lib-screen]].
