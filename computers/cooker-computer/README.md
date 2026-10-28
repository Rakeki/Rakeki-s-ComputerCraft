# cooker-computer

- **Type:** computer (advanced is nicer: colour), plus a wired modem on the storage network
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** wired modem joined to the [storage system's](../storage-computer/README.md) network; for each cooking pot, two hoppers and a redstone relay on that network; optional monitor for the candy count

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

- **Looks at each pot.** A comparator next to the pot reads how full it
  is, and a redstone relay passes that to the cooker.
- **Fills the pots.** It asks the storage computer for whatever the pot
  has room for, out of what's in storage, and the storage computer puts it
  in the pot's **feed hopper**, which passes it into the pot.
- **Empties them.** The **output hopper** under each pot takes out what's
  cooked, and the cooker sends it to the storage computer's input chest,
  and from there into storage, ready for the next pot up.

A pot cooks one thing every 5 seconds, as long as its lid is shut, and
redstone power is what shuts it.

A hopper can't choose which pot slot an item goes in: it fills the first
slot it can, and a pot given one item too many starts another slot and
jams. That's what the comparator is for: the cooker sends only what the pot
has room for, judged from what the pot really holds, so nothing has to be
counted and you can open a pot without upsetting it.

- **Sculk and honeycomb** go in in pairs, up to a stack between them in
  the pot. When one of them runs out in storage, the other waits too.
- **Compressing** needs a slot per candy (6 for S, 3 for the rest), and a
  hopper only starts the next slot once one is full. So a compressing pot
  starts cooking once it holds 5 stacks and 1 (321 XS candy) for an S pot,
  or 2 stacks and 1 (129) for the others, and keeps a little more than
  that in it as it works. Those candies are in the pot, not in storage.

The screen lists each pot, what it makes, how many it has made since the
cooker started, and what it's doing: **cooking**, **filling** (about how
many it holds / how many it needs to start), **needs** an item that's run
out in storage, or **not cooking!** when it should be. With a wireless
modem it also reports to the [status server](../status-server/README.md).

### Candy monitor

Put a monitor on the computer (or on the network with a wired modem) and it
shows how much candy you have:

- each size, XS to XL, and rare candy: how many are in storage, about how
  many are in the compressing pots, and the exp they're worth (XS 100, S
  800, M 3,000, L 10,000, XL 30,000, as in Cobblemon);
- the exp of all the candy in storage together;
- how much sculk and honeycomb is left for making more XS.

It needs room for 36 characters across: a monitor 4 blocks wide, or 2 or 3
wide (it then uses smaller text), and at least 2 blocks tall. It updates
every 10 seconds, with the pots. To pick one monitor out of several, or
change what it lists, see `monitor` and `candy` in `config.lua`.

## Example layouts

The website shows each of these in 3D.

### One pot

The pot on its campfire, raised one block so the output hopper fits under
it. The feed hopper points into the pot's side, and a redstone block behind
the pot shuts its lid without touching either hopper. A comparator on the
pot's other side reads it into the redstone relay beyond it. A wired modem on
each hopper and on the relay joins the storage network's cable, which also
reaches the storage input chest and this computer.

### Candy chain

Five pots in a row, one for each size from XS to XL, each set up like the
single pot, all on one cable. XS candy goes back into storage through the
input chest, then into the S pot, and so on up to XL.

## Files

- `cooker.lua`: the program
- `config.lua`: what the pots can make, what to leave in storage, and the candy monitor (kept when you update)
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
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
5. On another side of the pot, put a **comparator** facing away from it
   (its back against the pot), and a **redstone relay** (CC: Tweaked) in
   front of the comparator. Leave the comparator in its normal mode (front
   torch off). Nothing else should power the relay.
6. Put a **wired modem** on each hopper and on the relay, join them to the
   storage network with networking cable, and right-click each modem so it
   turns red. It says the block's name, like `minecraft:hopper_3` or
   `redstone_relay_0`: note which is which.
7. **Power the pot with redstone**, which shuts its lid: place a redstone
   block touching it, last, after the pot is on the campfire (the lid moves
   when the power changes). Keep it away from the hoppers (a powered hopper
   stops moving items) and from the comparator's sides and the relay (they
   would read it instead of the pot).
8. Place this computer with a wired modem on it, joined to the same network
   (a wireless modem as well is only needed for the status server). For the
   [candy monitor](#candy-monitor), put a monitor on it too. Install this
   program, then add each pot and reboot.

   ```
   cooker add                         -- add a pot: asks what it makes, its hoppers and its relay
   cooker add exp_candy_s minecraft:hopper_3 minecraft:hopper_4 redstone_relay_0   -- the same in one go
   cooker                             -- start (startup.lua does this on boot)
   cooker relay 2                     -- give pot 2 its relay (pots added before relays were needed)
   cooker remove 2                    -- forget pot 2 (no number: list the pots)
   ```

`cooker add`, `relay` and `remove` work from another tab while the cooker
runs (Ctrl+T to stop it, or open a tab on an advanced computer); it picks
up the change straight away.

### Pots set up before the comparator

Older versions of the cooker counted what went into each pot instead of
reading a comparator, and could lose count. Add a comparator and a relay to
each pot (steps 5 and 6), then run `cooker relay <n>` for each one. Until it
has a relay, a pot isn't fed and the screen says **no relay**. Whatever is in
the pots already is fine: the comparator sees it.

## Things to know

- You can open a pot, take things out or put things in: the cooker sees the
  change on its next round. Put in only what the pot's recipe takes, though:
  anything else jams it.
- If a pot that should be cooking (it's full enough) makes nothing for 2
  minutes, the screen says **not cooking!** Its lid is probably open (no
  redstone power), or it's jammed with something it can't cook: empty it by
  hand. Check too that the output hopper points into a solid block: if it
  passes candy on to a chest or another hopper, the cooker never sees it
  come out.
- The comparator reads a pot in steps of about a stack, so the cooker sends
  candy in small amounts as a pot gets near full, and keeps the feed hopper
  nearly empty.
- If the storage computer doesn't answer while loading a pot, nothing is
  lost: the cooker sees what arrived in the feed hopper on its next round.
- After `install update`, an older `config.lua` (kept as it was) has no
  `monitor` or `candy` settings: the monitor then uses any monitor it finds
  and lists the candy above.
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
