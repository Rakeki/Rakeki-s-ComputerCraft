---
name: testing
description: How to check a change here before calling it done - compile every Lua file with Fengari (node sim/compile.mjs), run one module headless with CC stubbed out (a part's commands, a round, recipe loading), when to use the full simulator (sim/: scenarios, npm test, rebuild the site first) and what to tell the player about what was and wasn't run. Use after editing Lua, before committing, or when something misbehaves in-game.
---

# Checking changes

There's no build or lint, and nothing here can run the real game. Three
levels, cheapest first; say which ran, and always that it hasn't been run
in-game.

## 1. Compile (always)

```
node sim/compile.mjs                   -- every .lua under computers/, lib/, plans/, animations/
node sim/compile.mjs computers/factory lib/mekfeed.lua
```

Fengari's parser (Lua 5.3) is close to CC's Cobalt (5.2-ish): it catches
syntax errors and bad `local` placement, not misspelt globals or wrong
arguments. Needs `npm install` in `sim/` once. Also `node site/build.mjs`
after touching programs.json, a README or `computers/` (it stops on a
missing group or an animation not listed).

## 2. Headless module check (logic you can't eyeball)

Load the module under Fengari with just enough of CC stubbed to run the
code path, and print what it does. Good for: a factory part's commands and
a round, recipe loading and lookups, planning, parsing. The pattern (as
used for saw.lua):

- `package.path` = the repo root and the program folder, so `require("lib.x")`
  and `require("saw")` resolve.
- Stub the globals it touches: `fs` (exists / isDir / list / makeDir /
  delete), `peripheral` (`call` returning lists, `getType`, `isPresent`,
  `getNames`), `parallel.waitForAll` (call each in turn), `term.getSize`,
  `keys`, `colors`, `os.epoch`, `os.queueEvent`, `rs.getSides`,
  `textutils`. Fengari's node build has **no `io`**: read files with
  `loadfile`, not `io.open`.
- Replace `lib.files` with an in-memory table store
  (`package.loaded["lib.files"] = { read, write, delete }`) instead of
  faking `fs.open` and serialization.
- Give the part a fake `f` (`config`, `ask` answering `stock` / `send` /
  `feeders`, `craft`, `wake`, `changed`, `work` with `fill` / `move` /
  `empty` for far away), then call `command({...})`, `request(...)`,
  `read(...)` + `round(r)` and print `self.message` and what was asked.
- Run it: `lauxlib.luaL_loadfile` + `lua_pcall` from a small `node -e`
  using `sim/node_modules/fengari`. Keep the harness in the scratchpad, not
  the repo.
- Time heavy pure-Lua work the same way (`os.clock()`): see [[performance]].

## 3. The simulator (when there's a bug to chase)

`sim/` runs every program together on simulated time, installed with the
real installer from `_site/`:

```
node site/build.mjs        -- first: the sim installs from _site/, a stale build tests old code
cd sim && npm test         -- every scenario's checks
node run.mjs storage 400   -- one scenario, every screen at the end
```

Use it to investigate a bug, not as routine for every change (it's slow and
it's a model: mod machines are stand-ins). A frozen sim clock means a
computer is stuck in heavy Lua without yielding. Scenarios live in
`sim/scenarios/` (set up as each README says, with checks); a new program
gets one. `node sim/map.mjs` rebuilds `site/network.json` for the network map
(commit it).

## In-game facts the tests can't give

Mod behaviour (what a Create saw does with several recipes, what a mod
builds at start-up, which tags the loader fills) comes from reading the
mod's jars ([[mod-recipes]]), or from the player. When the player reports
something ("the saw can do framed glass"), find out why the data missed it
and fix the source, not just the one item.

Related: [[performance]], [[new-computer]], [[mod-recipes]].
