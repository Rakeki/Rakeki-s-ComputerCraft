# cooker-computer

- **Type:** computer (advanced is nicer: colour), plus a wired modem on the storage network
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem joined to the [storage system's](../storage-computer/README.md) network; two hoppers per cooking pot on that network

## What it does

Puts Cobblemon's **campfire cooking pots** to work for the
[storage system](../storage-computer/README.md). Out of the box it makes
exp candy and compresses it:

| Pot | Takes, per cook | Makes |
|---|---|---|
| `exp_candy_xs` | 1 sculk + 1 honeycomb | 1 exp candy XS |
| `exp_candy_s` | 6 exp candy XS | 1 exp candy S |
| `exp_candy_m` | 3 exp candy S | 1 exp candy M |
| `exp_candy_l` | 3 exp candy M | 1 exp candy L |
| `exp_candy_xl` | 3 exp candy L | 1 exp candy XL |

Each pot makes one of these. Set up the ones you want, so a pot for each
size compresses everything up to XL, and pots up to M stop at M. Every 10
seconds the cooker:

- **Fills the pots.** It asks the storage computer for what each pot needs,
  and the storage computer puts it in the pot's **feed hopper**, which
  passes it into the pot.
- **Empties them.** The **output hopper** under each pot takes out what's
  cooked, and the cooker sends it to the storage computer's input chest,
  and from there into storage, ready for the next pot up.

A pot cooks one thing every 5 seconds, as long as its lid is shut, and
redstone power is what shuts it.

A hopper can't choose which pot slot an item goes in: it fills the first
slot it can. So the cooker counts everything that goes in and comes out,
and sends no more than the pot can take:

- **Sculk and honeycomb** go in in pairs, at most a stack of each in the
  pot. When one of them runs out in storage, the other waits too.
- **Compressing** needs a slot per candy (6 for S, 3 for the rest), and a
  hopper only starts the next slot once one is full. So a compressing pot
  starts cooking once it holds 5 stacks and 1 (321 XS candy) for an S pot,
  or 2 stacks and 1 (129) for the others, and keeps up to 6 or 3 stacks in
  it as it works. Those candies are in the pot, not in storage.

The screen lists each pot, what it makes, how many it has made, and what
it's doing: **cooking**, **filling** (how many it holds / how many it
needs to start), **needs** an item that's run out in storage, or **not
cooking!** when it should be. With a wireless modem it also reports to the
[status server](../status-server/README.md).

## Example layouts

The website shows each of these in 3D.

### One pot

The pot on its campfire, raised one block so the output hopper fits under
it. The feed hopper points into the pot's side, and a redstone block behind
the pot shuts its lid without touching either hopper. A wired modem on each
hopper joins the storage network's cable, which also reaches the storage
input chest and this computer.

### Candy chain

Five pots in a row, one for each size from XS to XL, each set up like the
single pot, all on one cable. XS candy goes back into storage through the
input chest, then into the S pot, and so on up to XL.

## Files

- `cooker.lua`: the program
- `config.lua`: what the pots can make, and what to leave in storage (kept when you update)
- `startup.lua`: starts it on boot and restarts it if it stops
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): crash-safe save files (copy to `/lib/files.lua`). Needed.

## Setup

1. Set up the [storage system](../storage-computer/README.md) first, and
   update it (`install update`): older storage computers only load
   furnaces, not hoppers.
2. For each pot: put a **campfire** down, light it, and put a **campfire
   pot** on it.
3. Put a **feed hopper** next to the pot, **pointing into its side** (sneak
   and place it against the pot). Not on top: a hopper above puts
   seasonings in the seasoning slots.
4. Put an **output hopper** under the pot, pointing sideways into a block
   that isn't a chest, so it keeps what it takes out.
5. Put a **wired modem** on each hopper, join them to the storage network
   with networking cable, and right-click each modem so it turns red. It
   says the hopper's name, like `minecraft:hopper_3`: note which is which.
6. **Power the pot with redstone**, which shuts its lid: place a redstone
   block touching it, last, after the pot is on the campfire (the lid moves
   when the power changes). Keep it away from the hoppers: a powered hopper
   stops moving items.
7. Place this computer with a wired modem on it, joined to the same network
   (a wireless modem as well is only needed for the status server). Install
   this program, then add each pot and reboot.

   ```
   cooker add                         -- add a pot: asks what it makes and which hoppers are its
   cooker add exp_candy_s minecraft:hopper_3 minecraft:hopper_4   -- the same in one go (feed, then output)
   cooker                             -- start (startup.lua does this on boot)
   cooker remove 2                    -- forget pot 2 (no number: list the pots)
   cooker reset 2                     -- after emptying pot 2 by hand
   ```

`cooker add`, `remove` and `reset` work from another tab while the cooker
runs (Ctrl+T to stop it, or open a tab on an advanced computer); it picks
up the change straight away.

## Things to know

- **Leave the pots alone.** The cooker knows what's in a pot only by
  counting. If you take things out of a pot or put things in by hand,
  empty it completely (its slots, not the hoppers) and run
  `cooker reset <n>`.
- If a pot that should be cooking hasn't made anything for 2 minutes, the
  screen says **not cooking!** Its lid is probably open (no redstone power),
  or it's jammed: empty it by hand and run `cooker reset <n>`.
- If the storage computer doesn't answer while loading a pot, the cooker
  takes it that the items were sent, so it never overfills the pot. If
  they weren't, the pot just waits longer to start.
- Everything with a pot to go into gets used: to keep some sculk,
  honeycomb or smaller candy in storage, add it to `keep` in `config.lua`.
- With Create installed, Cobblemon also makes XS candy from experience
  nuggets and honeycomb. That recipe is in `config.lua`, commented out.
- Other pot recipes can be added to `config.lua`, as long as they take
  either different items (one each, at most 5) or one item several times.
  Recipes that need, say, two of one item and one of another can't be fed
  by hoppers.
- The storage computer can't ask the pots to make something on request:
  candy is compressed as it comes in, not when a turtle asks for it.
- If the storage input chest is full, cooked candy waits in the output
  hoppers and the footer says so.
- It works the same whether the storage computer keeps things in chests or
  in an [ME or RS system](../storage-computer/README.md#me-and-rs-systems).
  With an ME or RS system, the storage computer needs a **transfer chest**
  to load the sculk and honeycomb into the right hopper slots.
