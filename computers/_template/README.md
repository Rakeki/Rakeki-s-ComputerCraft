# <Computer name>

- **Type:** computer / advanced computer / turtle / pocket
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** (e.g. modem on top, monitor on left)

## What it does

## Files

- `startup.lua`: runs on boot: fetches any newer version from the website, then reports to the [status server](../status-server/README.md)
  through [`lib/report.lua`](../../lib/report.lua) and saves errors to `/errors.log`
  through [`lib/errlog.lua`](../../lib/errlog.lua); copy both to `/lib/`.
