# CurseForge page text for JunkDrop

Not part of the addon package (`art` is in `.pkgmeta`'s ignore list). Paste these into the project's page at authors.curseforge.com.

## Project name and slug

- Project name: `JunkDrop`
- Slug: `junkdrop`

## Summary (256 characters at most)

Delete your lowest-value items with one command or click, so you can keep looting with full bags. Choose which qualities count, protect items by name, and see what's next on your bar and in your bags.

## Logo

`art/curseforge-icon-400.png`, exactly 400x400. Regenerate or tweak it with `art/make-logo.py` (needs Pillow).

## Categories

- Main category: Bags & Inventory
- Additional categories: Plugins, Data Broker

## License tab

GNU General Public License version 3 (GPLv3). This matches the `LICENSE` file and the TOC.

## Source and issues

- Source: https://github.com/DesertDwarf/JunkDrop
- Issues: https://github.com/DesertDwarf/JunkDrop/issues

## Description

**JunkDrop deletes items. It does not sell them, and deleted items cannot be recovered.** By default it only considers Poor (grey) items.

JunkDrop clears bag space with one command or one click, so you can keep looting when your bags are full. It works on retail, Classic Era and World of Warcraft: Forever.

### How it ranks items

A stack is one bag slot, and its value is the vendor price of the whole stack. A slot of six 2-copper items is worth 12 copper, so it ranks above a single 10-copper item. The lowest-value stack goes first.

You can choose which item qualities may be dropped (Poor, Common, Uncommon, Rare, Epic), and whether to drop the lowest quality first or simply the cheapest price first.

Quest items (ones you need for a quest, or that start one) are never picked, at any quality. Safeguards for anything better than Poor: an item must have a vendor price (so the Hearthstone is never picked), and a confirmation window lists exactly what will be deleted.

### Never drop

Type words separated by commas, such as `knife, fishing pole, bag`. An item whose name contains any of them is never dropped. A Test button lists what your words match in your bags right now.

### Commands

Type `/jd` or `/junkdrop`:

- `/jd` deletes the next stack in line. `/jd 3` deletes the next 3. `/jd all` deletes everything that qualifies.
- `/jd list` shows the next stack without deleting anything, so you can decide whether a new item is worth looting. `/jd list 3` and `/jd list all` show more.
- `/jd debug` shows every stack in drop order.
- `/jd options` opens the settings window. `/jd reset` resets every setting (it asks first). `/jd help` lists the commands.

### On your bar

JunkDrop adds an item to data-broker bars (EllesmereUI, ElvUI DataTexts, Titan Panel and others). It shows the next stack and its value, with colored dots for the qualities you've chosen. Hover to see the next few stacks, left-click to delete the first one, right-click for settings. The first time you delete with a click or with `/jd`, and the first time you use `/jd all`, a one-time warning asks you to confirm.

### Glow in your bags

With EllesmereUI Bags installed, the next stack to be dropped pulses red while your bags are open. You can turn it off in settings.

### At the loot window

When the loot window is open and your bags are full, JunkDrop shows a note beside it. For each item that won't fit, it says whether the item is worth more than the next stack JunkDrop would drop with a short checklist (drop this, then take that) or a "Skip". A button drops the suggested stacks, asking first for anything better than Poor. It works with any loot window, and follows your EllesmereUI theme.

### Settings

`/jd options` or right-click the bar item. Label, value-only display, stack size, quality dots, coin style, tooltip rows, confirmations, chat reports, and the bag glow. It follows your EllesmereUI theme when that addon is installed.

---

Source and bug reports: https://github.com/DesertDwarf/JunkDrop
