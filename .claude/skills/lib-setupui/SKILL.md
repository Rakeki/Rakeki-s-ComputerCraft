---
name: lib-setupui
description: Reference for lib/setupui.lua, the setup screens shown on the monitor and the terminal at once (pages of rows, chest lists a page at a time with contents, an Empty filter and typed search, opening the screen in the running program from another tab). Use when writing or changing a setup screen (storage-computer, factory, mekfeed and workchest pages) or any page where the player picks a chest or machine.
---

# lib/setupui.lua

```lua
local setupui = require("lib.setupui")
local ui = setupui.new({ screens = { termScreen, monScreen }, name = "factory" }) -- lib/screen.lua screens;
                                     -- the first is the terminal (keyboard); one without a target is skipped
local result = ui:run(page)          -- shows page until ui:finish(result)
```

Everything works on the monitor (taps), the terminal (clicks) and the
keyboard alone (arrows + Enter, Backspace = back, a button's first letter
presses it): a basic computer has no mouse.

## Pages

```lua
{ title = "Saws", hint = "a line under it",
  rows = function(ui) return { { label, value, colour, labelColour, dim, keep, act = function() end }, ... } end,
  buttons = function(ui) return { { " Save ", "black", "lime", function() end } } end, -- else Back / Done
  filter = true,                     -- typing on the terminal narrows the rows (label or value)
  empty = function(row) end,         -- an Empty button shows only rows this passes
  enter = function() end,            -- called when the page opens (read contents here, once)
  tick = function(ui) end }          -- every second while open
```

`rows` is called on every draw: keep it cheap (no peripheral calls; read
in `enter` or before opening). Build a long list once and close over it,
as the saw's filter picker does (thousands of outputs, `filter = true`).

| Call | What |
|---|---|
| `ui:open(page)` / `ui:back()` | go to a page / back |
| `ui:say(text, colour)` | the message line (say why a tap did nothing) |
| `ui:draw()` | draw now: before a slow call, after `say` |
| `ui:finish(result)` | close; `run` returns result |
| `ui:pickChest({ title, hint, names, current, none, nothing, roleOf, only, pick })` | a page of chests with their contents (`setupui.contents`, read at once); `roleOf(n)` marks one ("another machine's"), `only(n, info)` hides; `pick(nil)` = the `none` row |
| `ui:pickByDrop(o)` | the player drops an item into the chest they mean (empty ones watched each tick). Nothing uses it now: listing every chest was clearer |
| `ui:monitorPage(setting, event)` | pick the monitor for a lib/screen.lua setting |
| `setupui.contents(names)` | name → `{ ok, stacks, top }`, every chest read in parallel |
| `setupui.onNetwork(test)` | names on the wired network (not touching this computer) whose type passes |
| `setupui.monitorText(setting)` | the monitor setting as a row value |

## Picking chests

List **every** candidate on the cable with what's in it, and mark rather
than hide ones in use; refuse a bad pick with `ui:say` (a full chest near
storage: "empty it first"). A filtered "free chests only" list hid players'
barrels. See [[factory-io]] (Picking chests) and [[item-rules]].

## Opening from another tab

`<program> setup` typed in a second tab opens the screen in the running
program (which owns the monitor):

```lua
if setupui.openInRunning("factory") then return end   -- the command: true when one answered
if setupui.wanted("factory", ev) then setupScreen() end -- the running program's event loop
```

Libraries add their own pages: `set:setupParts(ui)` / `set:setupPage(ui)`
(lib/mekfeed.lua, with `opts.lineRows` for a line's own rows),
`work:setupPage(ui)` (lib/workchest.lua).

Related: [[lib-screen]], [[factory]], [[storage-system]].
