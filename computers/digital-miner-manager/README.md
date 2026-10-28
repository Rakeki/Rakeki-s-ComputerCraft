# digital-miner-manager

- **Type:** advanced computer
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modems on each Digital Miner, joined to this computer with networking cable; advanced monitor (3 × 2 or bigger); optional wireless modem

## What it does

Runs every [Mekanism](https://www.curseforge.com/minecraft/mc-mods/mekanism)
**Digital Miner** on the computer's wired network from one monitor. The
list page shows each miner with what it's doing (searching, mining, stopped,
finished, idle, or "no power"), blocks left to mine, its radius, Y range and
how full its power buffer is. **Start all** and **Stop all** are at the top.

Tap a miner for its own page:

- **Start**, **Stop** (pause) and **Reset**
- **Silk** and **Eject** switch silk touch and auto eject on and off
- **Radius**, **Min Y** and **Max Y** with buttons to change them
- its **filters**: tap **x** to remove one, or a **+ tag** button (from
  `config.lua`, `c:ores` by default) to add it. A miner with no filters mines
  everything it finds.

Mekanism only lets you change the radius, Y range and filters after a
**Reset**. If the miner says no, the reason shows at the bottom of the
screen.

**Mined items** go wherever the miner ejects them. The manager turns
**Auto Eject** on for every miner when it starts. Put the
[storage computer](../storage-computer/README.md)'s **input chest** at each
miner's eject port, or run a pipe from there to the input chest, and
everything mined ends up in your storage.

The [status server](../status-server/README.md) shows how many are mining
and how many blocks are left.

## Files

- `dminer.lua`: the program. Refresh rate and text size are at the top.
- `config.lua`: units, auto eject, the "+ tag" filter buttons and miner names. `install update` never replaces it.
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional; it works without it.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Open each Digital Miner's security settings and set it to **Public**.
   Mekanism ignores a computer's orders otherwise. The manager can still
   read the miner, but every button fails with a security message.
2. Put a wired modem on each miner and join them to the computer with
   networking cable. Right-click each modem so it turns red.
3. The miner ejects from the port in the middle of its back, on the top row.
   Put the storage system's input chest right behind that port, or a pipe
   from it to the input chest.
4. Put an advanced monitor next to the computer (3 wide × 2 high or bigger).
5. Install and reboot:

   ```
   dminer                          -- start the monitor (startup.lua does this on boot)
   dminer list                     -- every miner with its number
   dminer start all                -- start every miner (or: dminer start 2)
   dminer stop all                 -- stop every miner (or: dminer stop 2)
   dminer reset 2                  -- reset miner 2 so its settings can change
   dminer filter 2                 -- list miner 2's filters
   dminer filter 2 add tag c:ores  -- also: add item minecraft:diamond_ore, add mod create
   dminer filter 2 remove 1        -- remove its first filter
   ```

## Things to know

- The commands are for when the monitor isn't running. Hold Ctrl+T to stop
  it, then hold Ctrl+T again during the 5-second wait to get the prompt.
  Run `dminer` (or reboot) when you're done.
- Miners are numbered in peripheral-name order. Give them names in
  `config.lua` so the list says "North quarry" instead of "Miner 1".
- A miner with an empty power buffer shows "no power" in red.
- Without a monitor it draws on the computer's own screen; click instead of
  tapping.
