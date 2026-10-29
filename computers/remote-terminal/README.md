# remote-terminal

- **Type:** computer (advanced is nicer: colour), plus an ender modem
- **Computer ID:** 
- **Label:** 
- **Location:** 
- **Peripherals:** ender modem; an ender chest (EnderStorage or a mod like it) next to it, whose twin is on the [storage system's](../storage-computer/README.md) cable

## What it does

Your [storage system](../storage-computer/README.md), anywhere. Put this
computer at an outpost, a farm or in another dimension, next to an ender
chest whose twin (same colours) sits on the storage system's cable at home.

- **Pull items.** Type to search everything that's stored, pick one and
  press **Enter** for a stack or **Right** for one. The storage computer
  puts it in its ender chest, so it turns up in yours. Anything that isn't
  stored but can be crafted gets crafted, like a turtle's order.
- **Send items home.** Drop anything in the ender chest and it goes into
  storage within about 5 seconds.

What you pulled waits in the chest for 10 minutes; anything still there
after that goes back into storage. The screen shows each item and how many
are stored, refreshed every 15 seconds.

It only works with ender chests that CC can see and that are shared by
colour, like [EnderStorage](https://www.curseforge.com/minecraft/mc-mods/ender-storage-1-8)'s.
Vanilla ender chests are each player's own, and CC can't reach into them.

## Files

- `remote.lua`: the program
- `startup.lua`: starts it on boot and restarts it if it stops (first it fetches any newer version from the website)
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`). Needed.
- [`lib/net.lua`](../../lib/net.lua): rednet requests and answers (copy to `/lib/net.lua`). Needed.
- [`lib/files.lua`](../../lib/files.lua): remembers which ender chest to use (copy to `/lib/files.lua`). Needed.
- [`lib/claim.lua`](../../lib/claim.lua): tells the storage computer which chest is this terminal's (copy to `/lib/claim.lua`). Needed.
- [`lib/report.lua`](../../lib/report.lua): reports to the status server (copy to `/lib/report.lua`). Optional.
- [`lib/errlog.lua`](../../lib/errlog.lua): saves any error to `/errors.log` so you can read it later with `edit /errors.log` (copy to `/lib/errlog.lua`). Optional.

## Setup

1. Update the [storage system](../storage-computer/README.md) (`install
   update`): older ones can't list their items for the terminal. Give the
   storage computer an **ender modem** too, so it hears the terminal from
   any distance.
2. At home, put one ender chest next to the storage, with a **wired modem**
   on it joined to the storage cable. Right-click the modem so it turns red.
   Don't pick it as any chest in `storage setup`: the storage computer finds
   it by itself.
3. At the far end, put its twin (the same three colours) next to this
   computer, or on a wired modem network with it.
4. Put an **ender modem** on this computer, install the program and reboot.

   ```
   remote                     -- start (startup.lua does this on boot)
   remote get 64 iron ingot   -- pull 64 of the first item matching "iron ingot"
   remote chest               -- pick the ender chest, if it can see more than one
   ```

The first time you pull something, the storage computer drops one item into
each chest that could be the twin until it turns up in yours (it takes them
back), so it needs something stored.

## Things to know

- Use a **colour code of its own** for each terminal: two terminals on the
  same colours share one chest, and so see each other's items.
- Both ends need to be loaded: the home base for the storage system, and
  the outpost while you use it.
- The ender chests at home are never used as storage, even with chests as
  storage, so nothing stored turns up at the other end by itself.
- Items you pulled and didn't take go home after 10 minutes. Things you
  drop in that match something you just pulled wait as long, too.
- A smelter or enricher far from home can be fed through ender chests as
  well: see the [smelter's work chest](../smelter-computer/README.md#work-chest).
