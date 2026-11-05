# JunkDrop

Deletes the lowest-value items in your bags with one command or one click, so you can keep looting when your bags are full. For World of Warcraft retail, Classic Era and World of Warcraft: Forever.

**JunkDrop deletes items. It does not sell them, and deleted items cannot be recovered.** By default it only considers Poor (grey) items.

## Install

1. Close WoW.
2. Copy the `JunkDrop` folder into your client's `Interface/AddOns` folder.
3. Start WoW and make sure JunkDrop is enabled in the AddOns list on the character select screen.

## Commands

Type `/jd` or `/junkdrop`, followed by any of these options:

| Command | What it does |
| --- | --- |
| `/jd` | Delete the next stack in line |
| `/jd 3` | Delete the next 3 stacks |
| `/jd all` | Delete every stack that qualifies (cannot be combined with a number) |
| `/jd list` | Delete nothing; show the next stack in line. Handy for deciding whether a new item is worth looting |
| `/jd list 3` or `/jd list all` | Show the next 3 stacks, or every stack, in drop order |
| `/jd debug` | Show every stack found, in drop order, and mark the ones that are (or would be) dropped |
| `/jd options` | Open the settings window (right-clicking the bar item does the same) |
| `/jd help` | List the commands |

Options can be combined, for example `/jd list 3` or `/jd 3 debug`. An option JunkDrop doesn't recognize is refused, and nothing is deleted.

A stack is one bag slot, and its value is the vendor price of the whole stack. A slot holding six 2-copper items is worth 12 copper, so it ranks above a single 10-copper item.

## What gets dropped

Items are ranked, and the first in line is dropped first. In **Settings**:

- **What can be dropped:** choose any of Poor, Common, Uncommon, Rare and Epic. Only Poor is on by default.
- **Drop order:** either *lowest quality first* (then cheapest), or *cheapest price first* regardless of quality.

Safeguards for anything better than Poor:

- An item must have a vendor price, and quest items are never picked. So the Hearthstone, which sells for nothing, can never look like the cheapest item in your bags.
- A confirmation window lists exactly what will be deleted, and deletes only that. You can turn it off in Settings.

### Never drop

Type words separated by commas, for example `knife, fishing pole, bag`. An item whose name contains any of them is never dropped, at any quality. Matching ignores capitals. **Test** lists what your words match in your bags right now, and says whether each match is actually being kept safe.

## The bar item

JunkDrop adds an item to any bar that supports data-broker (LibDataBroker) plugins, such as EllesmereUI's data bars, ElvUI's DataTexts, or Titan Panel.

- It shows the next stack in line, with its value, next to the name. A colored dot after the name shows which qualities are selected.
- Hovering lists the next few stacks. **Left-click** deletes the first stack listed. **Right-click** opens Settings.

## Glow in your bags

With [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui) Bags installed, the next stack to be dropped pulses with a red glow while your bags are open. It's on by default and can be turned off in Settings. Other bag addons are not affected.

## Settings

`/jd options` or right-click the bar item. It follows your EllesmereUI theme when that addon is installed.

- What can be dropped, drop order, and the never-drop words.
- Bar text: the label (`JunkDrop`, `JD` or none), name and value or value only, stack size, quality dots, coin icons or letters, and how many stacks the tooltip lists.
- Behavior: confirm before deleting from the bar, always confirm for items better than Poor, print each deleted item in chat, and the bag glow.

Settings are shared by every character on your account.

## Building and testing

You only need this section to work on the addon.

### Tests

The tests run the addon's real Lua files against a stand-in for the WoW API, using Lua 5.1 like the game does. They check ranking, safeguards, confirmations, the bar text, the options window and the bag glow.

```
py -m pip install -r tests/requirements.txt
py -m unittest discover -s tests
```

Stand-ins prove the logic and catch typos, not how things look or behave in the real client, so always check in game too.

### Installing a build into your own client

Put the AddOns folders to update in `tools/deploy-targets.txt` (one per line, not in git), then run `tools/deploy.bat`. It copies the same files the release package contains, never deletes anything, and lists any stale files. `tools/deploy.bat -WhatIf` only shows what would happen. Then type `/reload` in game, or restart if files were added or removed.

### Releasing

1. Add a section for the new version at the top of `CHANGELOG.md`, written for players. CurseForge shows it as the release notes.
2. Run the tests, then commit and push `main`.
3. Tag the release and push the tag: `git tag -a v1.0.1 -m "Short description"` then `git push origin v1.0.1`.

The packager (`.github/workflows/release.yml`) builds the zip and uploads it. It only runs for tags starting with `v`. A tag containing `alpha` or `beta` is uploaded as that release type, and **will publish to CurseForge** once the `CF_API_TOKEN` secret and the project ID in the TOC exist, so only push one when you want a public beta file.

## License

GNU General Public License v3. See `LICENSE`.
