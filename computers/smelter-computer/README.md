# smelter-computer

- **Type:** computer (advanced is nicer: colour), plus a wired modem on the storage network
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem joined to the [storage system's](../storage-computer/README.md) network; furnaces and blast furnaces on that network

## What it does

The furnace arm of the [storage system](../storage-computer/README.md). Every
10 seconds it looks at each furnace and blast furnace on the storage
network and:

- **Empties them.** What's smelted goes into the storage computer's input
  chest, and from there into storage. Charcoal goes on to the fuel chest.
- **Fills them.** Raw iron, gold and copper, ore blocks and ancient debris
  in storage are shared out between the furnaces that are free, blast
  furnaces first (they're twice as fast). A furnace already smelting
  something is topped up with more of it, up to a stack.
- **Fuels them** from the storage computer's **fuel chest**, with enough
  for what's in each furnace. Charcoal is used first, then coal, then coal
  blocks; when the fuel chest is empty it uses coal kept anywhere else in
  storage.

Ores that drop more when mined with Fortune (coal, diamond, emerald, lapis,
redstone, quartz) are left alone, and so are blocks of raw metal. Change
what gets smelted in `config.lua`: add sand for glass, say.

### Making charcoal

When there's far more of one kind of log than you want, burn it into
charcoal. Press **C**, pick the logs from the list (the kind there's most of
is first), and say how much charcoal to make. Plain furnaces work on the
order before ores (blast furnaces can't smelt logs), and the charcoal goes
into the fuel chest, where it fuels the furnaces and
[turtles](../storage-computer/README.md#fuel). The screen shows how far the
order has got; it carries on after a reboot, and stops early if those logs
run out.

The screen lists each furnace, what's in it and its fuel, how much
smelting the stored fuel is good for, and what it did last. With a
wireless modem it also reports to the [status server](../status-server/README.md).

## Files

- `smelter.lua`: the program
- `config.lua`: which items get smelted (kept when you update)
- `startup.lua`: starts it on boot and restarts it if it stops
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed.

## Setup

1. Set up the [storage system](../storage-computer/README.md) first, and
   update it (`install update`) if it was installed before the smelter
   existed.
2. Place the furnaces and blast furnaces near the storage. Each one needs a
   **wired modem** on it (furnaces are full blocks, so a small modem goes
   straight on), joined to the storage network with networking cable.
   Right-click each modem so it turns red.
3. Place this computer with a wired modem on it, joined to the same network
   (a wireless modem as well is only needed for the status server).
4. For a fuel chest: connect one more chest to the network, run
   `storage setup` on the storage computer and pick it as the **fuel chest**.
   Put some coal or charcoal in it, or in the input chest. Without a fuel
   chest, furnaces burn coal and charcoal from anywhere in storage.
5. Install this program and reboot.

   ```
   smelter                        -- start (startup.lua does this on boot)
   smelter charcoal 256 spruce    -- make 256 charcoal from spruce logs
   smelter charcoal 64            -- make 64 from the logs there are most of
   smelter cancel                 -- stop making charcoal
   ```

On the running smelter, **C** starts a charcoal order and **X** cancels it.
The `smelter charcoal` command does the same from another tab (or after
stopping it with Ctrl+T); the running smelter picks it up within 10 seconds.

## Things to know

- Furnaces must be on the network through a modem, not just touching this
  computer: the storage computer moves the items, and it can only reach
  what's on the cable.
- It works the same whether the storage computer keeps things in chests or
  in an [ME or RS system](../storage-computer/README.md#me-and-rs-systems).
  With an ME or RS system, the storage computer needs a **transfer chest**
  (chosen in `storage setup`) to load the furnaces' slots.
- It asks the storage computer for everything over the cable, so both must
  be on the same wired network. If the storage computer doesn't answer, the
  footer says so and it tries again every 10 seconds.
- Making charcoal needs some fuel to start with: one coal or charcoal
  burns 8 logs into 8 charcoal.
- If a furnace has fuel but doesn't smelt what's in it for 2 minutes (an
  item that doesn't smelt there, like a modded ore in a blast furnace), the
  item goes back into storage and isn't put in that kind of furnace again
  until the smelter restarts.
- If the storage input chest is full, smelted items wait in the furnaces
  and the footer says so.
- Furnaces you load by hand get fuelled and emptied too. Smokers are left
  alone.
