---
name: lib-screen
description: Reference for lib/screen.lua, flicker-free drawing on monitors and terminals (each frame drawn into a hidden window and shown in one go, unchanged frames skipped). Use when writing or changing any program that draws a UI on a monitor or the computer's screen.
---

# lib/screen.lua

```lua
local screen = require("lib.screen") -- flicker-free drawing
```

Clearing a monitor and redrawing it in place makes it flash, so every
program with a screen draws through this. Each frame goes into a hidden
window over the screen, then appears all at once. Add `screen` to the
program's `libs` in `site/programs.json` (it is required, not optional), and
list `lib/screen.lua` in its README's Files.

## API

| Call | Does |
|---|---|
| `screen.new(target)` | Wrap a monitor (`peripheral.find("monitor")`) or `term.current()`. Never `term.native()`: it breaks multishell tabs. |
| `s:frame(bg)` | Returns `win, w, h`: a hidden, cleared window the size of the screen. Made again when the screen's size changes (monitor resized or rescaled). |
| `s:show()` | Shows the frame. Set the cursor on `win` first if it should blink (a search box): showing puts it there. |
| `s:same(key)` | `true` when `key` (a string describing everything the frame shows) matches the last one at this size: skip drawing. |
| `s:setTarget(t)` | Draw on another monitor from now on. |
| `s:size()` | The screen's size now (for layout before the first frame). |
| `screen.put(t, x, y, text, fg, bg)` | Write text. Colours are names (`"lime"`) or numbers (`colors.lime`); `bg` defaults to black, `fg` to white. |
| `screen.fit(text, w)` | Cut or pad to exactly `w` characters (`""` when `w <= 0`). |

## Patterns

A UI drawn on demand (a panel, a dashboard):

```lua
local display = screen.new(target)
local function draw()
  local win, w, h = display:frame()
  screen.put(win, 1, 1, (" "):rep(w), "white", "gray")
  -- ...
  display:show()
end
```

UI modules keep the window being drawn in `self.win` for helpers like
`self:button()` (see `computers/blueprint-projector/ui.lua`), and use
`self.display:size()` for layout outside `draw`.

A monitor redrawn on every event (storage.lua's `drawMonitor`): build `key`
from what it shows (title, counts, the rows' text) and return early when
`display:same(key)`; each real change is sent to every player who can see
the monitor. Set the monitor's text scale before the first frame (or when
the monitor changes), not every frame.

A prompt that uses `read()` (smelter.lua's charcoal order) writes to the real
terminal; the next `frame()` / `show()` draws over it cleanly.

Related: [[new-computer]].
