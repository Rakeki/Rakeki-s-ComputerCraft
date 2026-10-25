---
name: lib-net
description: Reference for lib/net.lua (rednet requests with ids and deadlines, answers, cached peer lookups, opening modems), lib/files.lua (crash-safe save files) and lib/inv.lua (turtle inventory and fuel). Use when writing or changing anything that talks over rednet, saves state to a file, or counts, selects or burns items in a turtle.
---

# lib/net.lua, lib/files.lua, lib/inv.lua

The shared plumbing every program uses instead of its own copy. Add each
one you require to the program's `libs` in `site/programs.json` (the
installer copies only what's listed), and to its README's Files list.

## lib/net.lua: talking over rednet

```lua
local net = require("lib.net")
```

| Call | Does |
|---|---|
| `net.open(kind)` | Opens modems: wireless and ender ones (default), or every modem with `"any"` (wired too). True if rednet is open on any. |
| `net.hasWireless()` | A wireless or ender modem is attached (so turtles can reach this computer). |
| `net.ask(to, protocol, msg, opts)` | Gives `msg` a fresh `id`, sends it, and waits for the answer from `to`. Returns it, or nil when none came in time. `opts.wait` (seconds, default 10); `opts.match(reply, from)` to accept a different answer (default: `reply.re == msg.type and reply.id == msg.id`); `opts.other(from, msg)` gets anything else that arrives on the protocol meanwhile. |
| `net.answer(to, protocol, request, reply)` | Sets `reply.re = request.type`, `reply.id = request.id` and sends it. |
| `net.peer(protocol, opts)` | A computer found by `rednet.lookup`, remembered until it goes quiet. `opts.open` (`"wireless"` / `"any"`), `opts.retry` (seconds before looking again after nobody was found), `opts.wait`, `opts.host`. |
| `peer:ask(msg, wait)` | `net.ask` to the peer. Returns the answer, or nil and why: `"no modem"`, `"none"` (nobody hosts it) or `"no answer"` (then it's looked up again next time). |
| `peer.id`, `peer:forget()` | Its id (set it when a message tells you who it is); forget it. |

The rules it keeps for you (AGENTS.md, "How the programs talk"):

- Every request has an id and every answer repeats it with `re`, so a late
  answer to an earlier request is never taken for a newer one. Ids come from
  one counter per computer, so several coroutines can ask at once.
- Nothing waits forever: every ask has a deadline, and the caller says on
  screen what it's waiting for.
- A protocol whose answers aren't `re`/`id` (the builder's `accepted` /
  `busy`, the crafter's `crafted`) passes `match`.

```lua
local storage = net.peer("storage", { retry = 60 })
local reply, why = storage:ask({ type = "count", items = { "minecraft:torch" } })
if not reply then print("No storage system: " .. why) end

-- answering, on the server side
local from, msg = rednet.receive("storage")
net.answer(from, "storage", msg, { counts = counts })
```

Broadcasts (`lib/report.lua`, the village turtle's plans) and hosting
(`rednet.host`) stay plain rednet. `lib/report.lua` opens its own modem so
it has no dependencies.

## lib/files.lua: crash-safe save files

```lua
local files = require("lib.files")
files.write("/.myjob_job", job)        -- temp file, then moved into place
local job = files.read("/.myjob_job")  -- falls back to the .tmp copy; nil if none
files.delete("/.myjob_job")            -- both copies
```

`nav.writeFile` / `nav.readFile` / `nav.deleteFile` are these same
functions (lib/nav.lua requires lib/files.lua, so every nav program lists
`files` in its libs). Never write state with `fs.open` directly.

## lib/inv.lua: a turtle's inventory and fuel

```lua
local inv = require("lib.inv")
```

| Call | Does |
|---|---|
| `inv.count(match)` | How many matching items are on board. |
| `inv.select(match)` | Selects the first matching slot; false if none. |
| `inv.emptySlots()` | Empty slots. |
| `inv.fuelLevel()` | Fuel level, `"unlimited"` as `math.huge`. |
| `inv.refuel(target, fuels)` | Burns items until the level reaches target: only `fuels` if given, else anything that burns (miners burn the coal they dig). |
| `inv.matcher(match)` | The test `match` stands for. |

`match` is an item name, a list of names, a set (`{ [name] = true }`, like a
`FUEL` table) or a function of the name.

Programs keep their old local names as aliases (`local fuelLevel =
inv.fuelLevel`), so the code reads as before.

Related: [[lib-nav]] (`nav.locate`, `nav.confirmResume`), [[turtle-job]],
[[storage-system]].
