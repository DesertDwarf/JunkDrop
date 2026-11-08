# JunkDrop

## v1.0.0

Updated for current World of Warcraft, with many new features.

- Works on retail (12.1), Classic Era (1.15) and World of Warcraft: Forever (1.60).
- `/jd 3` deletes the next 3 stacks in line, for example. `/jd all` deletes everything that qualifies.
- `/jd list` shows the next stack in line without deleting anything, so you can decide whether a new item is worth looting. `/jd list 3` and `/jd list all` show more.
- `/jd debug` lists every stack in drop order and marks the ones that are dropped.
- `/jd help` describes every option. An unknown option is now refused instead of falling through to a delete.
- Item values are shown as gold, silver and copper icons.
- Choose which item qualities can be dropped: Poor (the default), Common, Uncommon, Rare and Epic. Drop order is either lowest quality first, or cheapest price first regardless of quality.
- Quest items (items you need for a quest, or that start one) are never dropped, at any quality. Anything better than Poor also needs a vendor price, so things like the Hearthstone are never picked. A confirmation lists exactly what will be deleted, unless you turn it off.
- A "Never drop" filter: type words separated by commas, such as `knife, fishing pole, bag`, and any item whose name contains one is never dropped. A Test button lists what the words match in your bags.
- The bar item shows the next stack in line beside its name, with colored dots for the selected qualities, and lists the next few stacks in its tooltip. Left-click deletes the first stack listed; right-click opens settings.
- A settings window (`/jd options`): label, value-only display, stack size, quality dots, coin style, tooltip rows, confirmations, and chat reports of deleted items. It follows your EllesmereUI theme when that addon is installed.
- With EllesmereUI Bags installed, the next stack to be dropped pulses with a red glow while your bags are open (optional).
- When your bags are full and the loot window is open, a note beside it says whether each item that won't fit is worth taking, and which of your items to drop for it. A button drops the suggested stacks, with the same confirmation as everything else (optional). The note follows your EllesmereUI theme when that addon is installed.
- The first time you delete with a click on the bar item, and the first time you use `/jd all`, a one-time warning shows what would go and asks you to confirm. Accepting it once is enough; "Reset to defaults" brings the warnings back.
- Fixed: the reagent bag is now scanned on retail.

## v0.8

- Verified with WoW 5.0.4 and updated the TOC.
