---
name: lib-screen
description: Reference for lib/screen.lua, flicker-free drawing on monitors and terminals (each frame drawn into a hidden window and shown in one go, unchanged frames skipped) and finding, scaling and following monitors as they come and go. Use when writing or changing any program that draws a UI on a monitor or the computer's screen.
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
| `screen.find(opts)` | A screen on a monitor it finds and scales itself (see below). Use this for every monitor. |
| `s:refresh()` | Call on `peripheral` / `peripheral_detach`. Keeps a monitor that is still there; otherwise moves to another (scaling it once) or to the fallback. `true` when it moved. |
| `s:clicked(ev)` | `x, y, drag` when `ev` (`{ os.pullEvent() }`) is a tap on its monitor, or a `mouse_click` / `mouse_drag` while it's the terminal; else `nil`. |
| `s.target`, `s.name` | What it draws on now (`nil` with no monitor and no fallback: don't draw), and the monitor's name (`nil` on the terminal). |
| `screen.new(target)` | Wrap `term.current()` (or a fixed target). Never `term.native()`: it breaks multishell tabs. |
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
local display = screen.find({ fallback = term.current() })
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

A monitor redrawn on every event (storage.lua's `drawMonitor`, the status
server's dashboard): build `key` from what it shows (title, counts, the
rows' text, "5s ago" times) and return early when `display:same(key)`;
each real change is sent to every player who can see the monitor.

### Monitors

Never find, wrap or scale a monitor yourself: `screen.find` does it, so
every program handles monitors coming and going the same way.

```lua
local display = screen.find({
  scales = { 1, 0.5 },        -- tried in order; the first that fits minW x minH wins (default { 1 })
  minW = 53, minH = 12,       -- optional
  filter = function(name, m) return m.isColor() end, -- optional: which monitors will do
  name = config.monitor,      -- optional: only this one (then filter is ignored)
  fallback = term.current(),  -- optional: drawn on while there's no monitor
})

-- in the event loop
local x, y, drag = display:clicked(ev)
if x then ... -- a tap on its monitor, or a click while it's the terminal
elseif ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
  if display:refresh() then announce() end -- moved: say where on the terminal
end
-- monitor_resize / term_resize: just draw; frame() is made at the new size
```

Why it's built this way (each of these made monitors flash):

- `peripheral` / `peripheral_detach` fire whenever anything attaches, a
  turtle driving past or a modem being placed, so `refresh()` leaves a
  monitor that is still there alone. Rebuilding the UI on them rescaled the
  monitor every time a turtle went by.
- The text scale is set once, when a monitor is picked, never per frame.
  `setTextScale` itself fires `monitor_resize`, so rescaling on that
  event loops.
- Keep one screen for the program's life (in the UI module: `self.display`)
  and keep UI state (page, selection) on that module, so a monitor moving
  doesn't mean making a new UI.

A prompt that uses `read()` (smelter.lua's charcoal order) writes to the real
terminal; the next `frame()` / `show()` draws over it cleanly.

Related: [[new-computer]].
