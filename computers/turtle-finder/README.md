# turtle-finder

- **Type:** pocket computer (advanced for colour) with a wireless or ender modem, inside [GPS](../gps-deployer/README.md) range
- **Computer ID:** 
- **Label:** 

## What it does

Finds a turtle you've lost. Every program here sends its status every 10
seconds through [`lib/report.lua`](../../lib/report.lua), with its GPS
position when it has one. The finder listens for those messages and lists
every turtle it hears, nearest first. Pick one and a big arrow points the way
to it, with how far it is, which direction (north-east, say), how far above
or below you, its coordinates and what it's doing ("stuck", "waiting",
"clearing").

The arrow points **relative to the way you last walked**: walk a few blocks
in the direction you're looking, then open the pocket computer. If you
haven't walked yet, it shows a compass instead, with north at the top
(press `C` to keep it that way). Pocket computers can't tell which way you
are looking, so they use the direction you walked.

The arrow is green when the position is fresh, yellow when it's a few
minutes old and red when it's older than that. It remembers the last place
it heard each turtle, even after you close it, so you can head for a turtle's
last known spot while it's out of range.

## Files

- `finder.lua`: the program. Settings (how far to walk before the arrow turns, when a position counts as old) are at the top.
- `startup.lua`: fetches any newer version from the website on boot. The finder only runs when you type `finder`.
- [`lib/screen.lua`](../../lib/screen.lua): draws the screen without flashing (copy to `/lib/screen.lua`)
- [`lib/net.lua`](../../lib/net.lua): opens the modem (copy to `/lib/net.lua`)
- [`lib/files.lua`](../../lib/files.lua): remembers where it last heard each turtle (copy to `/lib/files.lua`)
- [`lib/errlog.lua`](../../lib/errlog.lua): optional; saves any error to `/errors.log`

## Use

1. Put a wireless or ender modem on a pocket computer (craft them together).
   An ender modem reaches any distance and dimension; a wireless one reaches a
   few hundred blocks.
2. Install it on the pocket computer and run it:

   ```
   finder                -- every turtle heard, nearest first: arrow keys and Enter to follow one
   finder Leveller       -- follow the one whose label has "Leveller" in it (or type its ID)
   finder all            -- list every computer, not just turtles
   ```

3. While following: `Backspace` or `←` goes back to the list, `C` switches between
   the walking arrow and the compass, `Q` quits. In the list, `Tab` switches
   between turtles and everything, and you can tap a row.

## Things to know

- **The turtle needs a modem and GPS.** Without a modem it can't send
  anything. Without GPS where it is, it says what it's doing but not where.
- **Its chunk has to be loaded.** A turtle in an unloaded chunk is frozen and
  silent. Head for its last known position: once you're close enough for
  its chunk to load, it starts sending again.
- **You need GPS too.** With no GPS signal where you're standing, it shows the
  turtle's coordinates but can't point.
- **Straight up or down.** When you're standing over it or under it, the
  arrow turns blue and points up or down, and says how many blocks.
