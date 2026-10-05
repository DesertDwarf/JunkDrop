# JunkDrop

## v1.0.0

Updated for current World of Warcraft, with new features.

- Works on retail (12.1), Classic Era (1.15.9) and World of Warcraft: Forever (1.60.1).
- `/jd <number>` deletes that many of the cheapest junk stacks, for example `/jd 3`.
- `/jd list` shows the cheapest junk stack without deleting anything, so you can decide whether a new grey is worth looting. `/jd list <number>` and `/jd list all` show more.
- `/jd debug` lists every junk stack, cheapest first, and marks the ones that are dropped.
- `/jd help` describes every option. Unknown options are now refused instead of falling through to a delete.
- Values are shown as gold, silver and copper.
- The LDB item now shows the cheapest junk stack beside its name and lists the cheapest few stacks in its tooltip.
- New settings window (`/jd options`, or right-click the LDB item): label, value-only display, stack size, coin style, tooltip rows, confirmation before deleting, and chat reports of deleted items. It follows your EllesmereUI theme when that addon is installed.
- Fixed: the reagent bag is now scanned on retail.

## v0.8

- Verified with WoW 5.0.4 and updated the TOC.
