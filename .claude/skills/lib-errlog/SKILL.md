---
name: lib-errlog
description: Reference for lib/errlog.lua, which saves every program's errors to /errors.log in one shared format. Use when adding error handling to a program, wrapping a main loop or event handler in pcall, or changing how errors are recorded.
---

# lib/errlog.lua

```lua
local errlog = require("lib.errlog") -- saves errors to /errors.log
```

Appends errors to `/errors.log` on the computer, in one format for every
program. Programs never write their own error files; use this. The player
reads the log with `edit /errors.log`.

Programs whose `report` is optional (`fs.exists("lib/report.lua") and require(...)`)
load errlog the same way and call `(errlog and errlog.pcall or pcall)(...)`.

## API

| Call | Does |
|---|---|
| `errlog.init(name, context)` | `name`: what entries are filed under (use the command, e.g. `"excavate"`; defaults to the running program's file name). `context`: optional function returning a table of fields added to every entry, e.g. `function() return { pos = nav.getPos() } end`. Errors inside it are ignored. |
| `errlog.pcall(fn, ...)` | Drop-in `pcall`: same arguments and returns, but logs the error with a stack trace first. |
| `errlog.error(msg, fields)` / `errlog.warn(msg, fields)` | Log an error you caught yourself, or a non-fatal warning. `fields` is an optional table. |
| `errlog.write(level, msg, fields)` | The general form; `fields.trace` is written as the stack trace. |
| `errlog.recent(n)` | The newest `n` entries (default 5), oldest first, one string each. |
| `errlog.clear()` | Delete the log. |

## Format

```
[2026-10-25 14:05:12 | day 12 06:30] ERROR excavate (Excavator-7 #7)
  excavate.lua:312: Out of fuel
  pos: x=10 y=64 z=-3
  fuel: 0
  stack traceback:
    excavate.lua:312: in function 'refuel'

```

- Header: real time (`os.date`) and game day/time, level, program name, label and ID.
- Then every line indented: the message, fields sorted by name (tables as
  `k=v`), `fuel` on turtles, then the stack trace (cut at 12 lines).
- A blank line ends each entry, and no entry contains one, so entries split
  on `\n\n` and headers are the only lines starting with `[`.
- The same level + program + message within 60 s is counted, not written;
  the next entry starts with `(the entry above happened N more times)`.
- `"Terminated"` (Ctrl+T) is never logged.
- Past 16 KB the file is cut to its newest ~8 KB at an entry boundary (temp
  file, then move).
- Writing never throws: a full disk loses the entry, not the program.

## Standard wiring

```lua
report.init("excavator")
errlog.init("excavate", function() return { pos = nav.getPos() } end)
parallel.waitForAny(function()
  local ok, err = errlog.pcall(run)
  if not ok then
    report.set("error", tostring(err))
    error(err, 0)
  end
end, report.loop)
```

Event loops that survive a bad event (servers) wrap each handler:
`local ok, err = errlog.pcall(handle, ev)`; repeats are collapsed, so a
handler failing every tick doesn't fill the disk.

Wrap the function that does the work, not `parallel.waitForAny`: an error in
a parallel coroutine is re-raised by `parallel`, so the stack trace would
point there instead of at the real line (the message still has file:line).
