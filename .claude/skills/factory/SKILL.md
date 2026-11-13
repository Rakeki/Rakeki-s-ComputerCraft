---
name: factory
description: How computers/factory is built (one program, a part per kind of machine, a round every 5 s, the chain of ranks, claims shared between factory computers, requests on demand with jobs from the craft overseer, makes/via offers) and the checklist for adding a part, a machine kind or a Create line. Use when changing anything in computers/factory, adding a machine the factory runs, or a program that orders from a factory part. For getting items into machines and results out, see factory-io.
---

# The factory

`computers/factory/factory.lua` is one program that runs every machine
turning stored items into other items. Each kind of machine is a **part**
(a module returning `M.new(f)`), and a computer runs whichever parts have
machines on its cable, so one program covers a furnaces-only world, a
Create-only one, or everything.

| Part | File | id / rank | Machines | Works |
|---|---|---|---|---|
| Enricher | `enrich.lua` | `enrich` / 1 | Mekanism Enrichment Chambers, Create crushers and washers | by itself (ores in storage) |
| Smelter | `smelt.lua` | `smelt` / 2 | furnaces, blast furnaces, smokers (found), Mekanism smelters, Create fans | ores/dust/food by itself, the rest on request |
| Infuser | `infuse.lua` | `infuse` / 0 | Metallurgic Infusers (two feeders) | on request only |
| Saw | `saw.lua` | `saw` / 0 | Create Mechanical Saw lines | on request only |
| AE2 | `ae2.lua` | `ae2` / 0 | AE2 inscribers, chargers, vibration chambers (found) | on request (inscribers, chargers); chambers kept fuelled |
| Brewer | `brew.lua` | `brew` / 0 | brewing stands (found), the potion chest, a dispenser bottle filler | on request only (no `makes`: potions carry data, so the overseer can't plan them) |
| Cooking | `cook.lua` | `cook` | Cobblemon cooking pots (comparator → redstone relay) | by itself |
| Essence | `botany.lua` (+ `farm.lua` far away) | `essence` | Hopper Botany Pots (found), pot barrels | by itself; far away a farm that crafts |

The old `smelter.lua` / `enricher.lua` / `cooker.lua` / `essence.lua` are
stubs that run `factory` (`replaces` in programs.json).

## The part interface

`f` (built in factory.lua) gives every part: `f.ask(msg, wait)` (the
storage computer, `storage` protocol), `f.craft(msg, wait)` (the craft
overseer, `lib/crafts.lua`), `f.work` (the work chest, `lib/workchest.lua`),
`f.config(section)` (its table in `config.lua`), `f.wake()` (a round now),
`f.changed()` (redraw soon), `f.event` (queued when machines change),
`f.taken(name)` (another factory computer's: don't offer it), `f.mine(name)`,
`f.leave(rank, name)` (an earlier part takes it), `f.log(text)`.

A part is a table with:

| Field | What |
|---|---|
| `id`, `title`, `short`, `rank`, `every`, `what` | identity; `rank` orders the chain (lower first); `every` = seconds between its rounds |
| `found()` | machines found by themselves (furnaces, botany pots): `{ { name, kind } }`, claimed in `/.factory_claims` |
| `uses()` | every peripheral its added machines use (always this computer's) |
| `active()` | has machines here; kept `ACTIVE_EVERY` s by `running(p)` |
| `takes()` | Lua patterns of item ids it takes: higher ranks leave them (here and on other factory computers, via `hello`) |
| `summary()` | one line for the Chain page and `hello` |
| `read(remote, remoteInput)` | read its machines (before `stock`); far away, empty output chests into the ender chest here |
| `round(r)` | the work, with `r = { stock, useWork, input, unsure, feedProblem }` |
| `key()`, `draw(win, w, h)` | its terminal tab (row 1 is the tab bar); `key` is what `s:same` compares |
| `tiles()` | `{ title, text, colour }` per machine for the monitor board |
| `event(ev, x, y)`, `command(args)` | keys/taps on its tab; `factory <word> ...` (return true if it was yours) |
| `request(from, msg)` | optional: `factory` protocol messages (the overseer's `<via>` jobs, `cancel`); nil if not yours |
| `monitorPage` | optional `{ title, key, draw, touch }`: a page on the monitor (Infuse, Saw, Candy) |
| `loop` | optional extra parallel loop (the farm answers its turtles) |
| `set` | its `lib/mekfeed.lua` set, if it has added machines |

Each part keeps `self.message = { text, colour }` (the footer; red = needs
you, orange = warning) and `self.status = { state, detail }` (for
`lib/report.lua`). A short-lived note: `tell(text, colour)` keeps it for a
minute over the round's own message.

## A round

`workLoop` runs `round()` every `EVERY` (5 s), or at once on `factory_added`:

1. `askPeers()` (every 30 s: other factory computers' `stages` and `owns`),
   `settle()` (claim free found machines; drop ones another computer had first).
2. Pick the parts that are running and due.
3. `work:reload()`; far away `remoteInput = work:input(nil)`; every due
   part's `read` (errors caught per part).
4. One `stock` request for all parts. No answer: every part says so, no work.
5. `work:check(reply)` (use the work chest?), the essence part's
   `beforeRegister`, then **one** `mekfeed.register` for every set's feeders
   (the storage computer keeps one list per computer, each `feeders`
   replaces it).
6. Each part's `round(r)` **in chain order**, so a smelter sees what the
   enricher takes this round. Errors are caught per part and shown red.

`uiLoop` draws; `netLoop` answers `hello` / `give` / `take` and hands every
other message to `p.request` (a `cancel` goes to every part); `report.loop`.

## Several factory computers

Found machines (furnaces, botany pots) belong to the earliest claim
(`/.factory_claims`: `mine` name → when, `released`, `off` = parts switched
off here); added machines count from time 0, so they always win. `hello` →
`{ stages, owns, label }`; `give` (let go) / `take` (they're yours). A
computer unheard for `PEER_FORGET` (10 min) is forgotten. The chain works
across computers: `f.leave(rank, name)` checks peers' `takes` too.

## Requests on demand

The smelter (other than ores and food), the infuser and the saw only make
what's asked for. The pattern (copy `saw.lua`, the simplest):

- **A file per request** in `/.factory_<part>/<epoch ms>`: `{ key, count,
  made, sent, at, job, done, ok, why }`, saved with `lib/files.lua`, so a
  request survives a reboot and one typed in another tab (`factory saw ...`)
  is never lost. `saveRequest` writes only while its file exists (a cancel
  in another tab stays cancelled), and only when something changed (`dirty`).
- **Sources:** its page's +1/+8/+64 buttons (terminal keys too: a basic
  computer has no mouse), `factory <part> <name> <count>`, and the craft
  overseer's job (`{ type = via, job, make, count, grid }` on `factory` →
  `{ ok }` or `{ ok = false, why }`).
- **Offering (`makes`):** each part tells the overseer what it can make
  (`f.craft({ type = "makes", via, recipes }, 5)`), when that changes
  (a key over the list) and every `MAKES_EVERY` (it forgets after
  `MACHINE_FORGET`). Recipes are ordinary grids. Offer only what the
  machines here can make **now** (the saw offers ~250 of 12,000 recipes:
  the rest need a filter no line has), which also keeps the message small.
- **Finishing:** a request is done when `made >= count`; a job reports
  `{ type = "jobdone", job, ok, why }` and its file goes once the overseer
  heard. A job with no progress for `GIVE_UP` (10 min) is handed back with
  `ok = false` and the reason (`q.state`). A request whose recipe vanished
  ends too.
- **Short inputs:** a request made on the part's own page (no `job`) whose
  input is short asks the overseer to `prepare` it, every `ORDER_EVERY`
  (the saw's `orderInputs`: glass for framed glass; `prepare` tops up to
  a total, so asking again never doubles it). The overseer's own jobs
  don't: its plan already makes their inputs first.
- **The chain:** `takes()` returns the inputs of open requests (escaped
  `^name$` patterns), so the smelter (rank 2) doesn't smelt them away.

## The parts in detail

The factory (`computers/factory`: one program, a part per kind of machine:
`smelt.lua`, `enrich.lua`, `infuse.lua`, `saw.lua`, `cook.lua`, `botany.lua`; one `stock` a round for
all of them) only ever `stock`, `send` / `fill` and empties into the input
chest. Its essence part empties Hopper Botany Pots into the input chest
itself (`pushItems` from the pot: a pot shows only its 12 harvest slots, only
through its bottom face, and only a hopper pot lets them be taken, so each pot
stands on a full-block wired modem), or empties a "pot barrel" the pots push into
(`/.factory_pot_barrels`, named to the storage computer with `feeders` so it isn't
storage; emptied just before each `feeders` request, since only an empty one is taken); far away (work chest an ender chest)
it's an essence farm instead (see Machine jobs in [[storage-system]]: it keeps its essence and crafts it itself), and orders crafts from the overseer (`f.craft`) with `prepare` set to
stored + already crafting + wanted (`prepare` tops up to a total). The smelter part's orders (`ORDERS` in smelt.lua: charcoal from logs into
the fuel chest, stone from cobblestone) each have their own save file and go
into plain furnaces ahead of ores, in that order, and into Mekanism smelters
with an output chest (`forOrders`; `made` counts what `collect` empties out
of it, before the orders are checked). The cooking pots part can't see inside
a pot: a comparator into a redstone relay says how full it is, and it sends
the feed hopper only what still fits.

The enricher part fills a feeder for each Mekanism Enrichment Chamber (CC
can't reach a Mekanism machine's slots: its own peripheral hides them): a
hopper on top, or a barrel a pipe pulls from into the chamber, which it
registers with `feeders` so it isn't storage (`mekfeed.register` sends the
smelter's and enricher's feeders in one list: each `feeders` replaces the
computer's whole list); and
the chamber auto-ejects dust into its output chest under it, which the factory
empties into storage each round (`set:collect`), or an extra input chest. The
smelter part leaves alone the ores a lower-rank part takes (`f.leave`): the
enricher here, or on another factory computer (`factory` protocol, `hello` →
`stages` with `takes` = Lua patterns), and smelts the dust.
The infuser part (rank 0) runs Metallurgic Infusers only on request: a file
per request in `/.factory_infuse/` (its page's buttons, `factory infuse`, or
the craft overseer's `infuse` on the `factory` protocol, carrying `job`).
Each infuser has two feeders (`opts.extra` in mekfeed: the infusion feeder
goes in its Extra side) and needs an output chest, where what comes out is
counted (`credit`). Its `takes` are the inputs and infusion items of open
requests, so the smelter leaves them alone. A request whose input isn't
stored but is infused here too gets a child request (`parent`).
The smelter part smelts ores, dust and food by itself, and everything else
(RECIPES in `smelt.lua` plus `config.recipes`: stone, glass, charcoal,
smooth stone, ingots, cooked food...) on request: a file per request in
`/.factory_smelt/` (C / S / G, `factory smelt`, or the overseer's `smelt`
with `job`; the old `/.smelter_*` orders are turned into requests on
start). It offers them with `makes` (`via = "smelt"`, only kinds its
furnaces can take: plain furnaces and Mekanism smelters with an output chest
everything, blast furnaces `kind = "ore"`, smokers `kind = "food"`).
Furnace and output-chest output is `credit`ed to requests by item, oldest
first; loads go through `addLoaded`. A request whose inputs were all loaded
but not all made loads the rest again; a job with nothing to smelt from
waits `GIVE_UP` then reports `jobdone` with `ok = false`.

## Config

`config.lua` has a table per part (`smelter`, `enricher`, `infuser`, `saw`,
`brewer`, `ae2`, `cooker`, `essence`; listed in `SECTIONS`). It's a `keep` file, so a player's
copy never gets new sections: **every setting needs a default in code**.
A config.lua from before the factory has its settings at the top; `section`
hands those to every part.

## Adding something

**A new Create line kind** (a machine CC can't see: feeder + output chest):

1. `LINES` in `lib/mekfeed.lua`: `word` (after `add`), `title`, `what`,
   `feeds`, `out`, `needOutput` if what comes out is counted.
2. Put the kind in the part's `lines = { ... }` (mekfeed opts).
3. `KINDS` in factory.lua (`<word> = { part, line = true }`), the `add`
   usage lines, and the header comment.
4. README: the machines table, a section, a Setup subsection, commands.

**A new part:**

1. `computers/factory/<part>.lua` with the interface above. Machines that
   are added go through a mekfeed set (`mekfeed.new({ name, cmd = "factory",
   event = f.event, ... })`); a set of lines only has no `single`.
2. factory.lua: `require` it in `parts` (chain order), add its set to
   `mekfeed.register({...})`, to `setParts` in `setupScreen`, to `listed()`'s
   ids, its kind to `KINDS`, its section to `SECTIONS`, header usage lines,
   the help line in `draw()` and the usage `print`s.
3. `config.lua` section with comments (and defaults in code).
4. On demand? Offer with `makes` and a new `via`: document it in AGENTS.md's
   protocol table (`craft_overseer` `makes` and `factory` messages) and the
   storage-system skill's `makes` row. The overseer needs no change: `via`
   is generic.
5. Docs: README (table, section, setup, commands, files), programs.json
   (tagline, stats, features, commands), AGENTS.md's factory row, root
   README line, lib/README.md "Used by", this skill.

## The brewer

Potions are items with components, which the storage computer never counts
or sends, so `brew.lua` keeps them out of storage: one potion chest
(`/.factory_brew_setup`, registered with `feeders` through `feedSet`)
holds the water bottles and every result; the part moves bottles between
it and the stands itself (its own chests). Only ingredients and blaze
powder come from storage (`send` to slots 4 / 5, which the storage computer
allows for brewing stands and dispensers, or the work chest). Each request
is a target key `<form>:<contents>`; `paths` is the shortest mix chain from
`potion:water` (contents mixes before gunpowder / dragon's breath). Each
round, a free stand takes the latest step of the oldest request that has
bottles at that step's input (`stepNeeds`: bottles still to pass each step,
less those past it in the chest or stands). A brew is done when slot 4 no
longer holds its ingredient; the changed bottles' `name#nbt` are learnt as
the mix's result (`/.factory_brew_names`), since CC can't read potion
contents and long / strong share a name. Jobs persist in
`/.factory_brew_stands`. The bottle filler runs in the part's own `loop`:
empty water out of the dispenser, then pulse once per bottle wanted while
it has glass and free slots (a full dispenser drops what it fills).

## The AE2 part

`ae2.lua` finds `ae2:inscriber`, `ae2:charger` and `ae2:vibration_chamber`
(exact peripheral types) and claims them like furnaces. An inscriber is read
through its combined inventory (`size() == 4`: 1 top, 2 bottom, 3 middle, 4
result; anything else means Separate Sides is on, a red tile). A recipe is
`{ make, middle, top, bottom, keep, machine, count }`; `keep` = top / bottom
stay (presses). Each round: results out (slot 4, a charger's slot once it
holds no chargeable item) credited by name, then each request, oldest first,
takes inscribers whose contents `fits` it, loading top / bottom level with
the middle (one each per craft; `getItemLimit` read once per inscriber), a
request's planned loads counted by `want` so two inscribers never both get
the whole amount. A press request with no inscriber holding the press puts
one from storage into an empty inscriber, always leaving one without a
press. Everything sent, nothing left in a machine, no progress for
`RESEND_AFTER`: `sent` drops back to what was made. Vibration chambers get
`send` `fuel` (the storage computer allows `ae2:*` machines). Offers via
`ae2`; jobs come back as `{ type = "ae2", make, grid }` and are matched by
`make` and the middle item in the grid.

Related: [[factory-io]] (feeders, work chest, output chests, cables),
[[storage-system]] (the messages), [[performance]], [[mod-recipes]],
[[lib-setupui]], [[lib-screen]], [[testing]].
