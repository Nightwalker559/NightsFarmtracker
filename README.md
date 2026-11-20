# Night's Farmtracker

Track what you farm. See what it's worth.

Counts everything you loot while you grind, groups it by category, sorts it by value and prices it against your AH addon or the vendor. Reset to save the session to the history and start fresh.

For World of Warcraft: Midnight (12.1 and 12.1.5). English and German. Optional: Auctionator, Oribos Exchange or TradeSkillMaster for AH prices.

**Author:** Nightwalker559 · **License:** MIT with AI restriction

---

## Features

- **No setup.** Loot is detected automatically. `/nft` or the minimap button opens one compact window with the total, session timer and gold rate.
- **Real values.** Every item is worth the higher of its AH and vendor price. Bind-on-Pickup, Warbound and filtered items always use the vendor price.
- **Clear lists.** Categories you can collapse, sorted by value, with reagent quality tiers, scaling gear per item level and directly looted gold shown separately. Optional split of trade goods and equipment, or all junk merged into one row.
- **Session limit or item goals.** Count down a fixed time, or set goals per item; the bars show progress and the session pauses when a goal is reached.
- **History and export.** Sessions are saved per day and month, account-wide, and can be exported as JSON (`/nft export`). *Compact mode* folds old months to keep the saved data small.
- **Profiles and themes.** Switchable profiles, 16 color themes plus your own color.

## Window

| Button | Action |
| --- | --- |
| Play / pause | Start and pause tracking and the timer |
| Reset | Save the session to the history and clear it. **Shift+click** resets without saving |
| History | **Left-click** Sessions & History, **right-click** Loot Log (if enabled) |
| Filter | **Left-click** Vendor-Only tab, **right-click** Blacklist tab |
| Settings, Help, Collapse, Close | The Help button lists all shortcuts and commands |

## Pricing

- **Sources:** Auctionator, Oribos Exchange or TradeSkillMaster (*Auto* prefers them in that order; TSM can use a price source or a custom expression). Without an AH addon the vendor price is used.
- **AH Price by Expansion:** use AH prices only for the expansions you pick.
- **Gear AH Threshold:** equipment uses its AH price only once one item reaches a gold amount you set, with an optional sound.

## Filters

One Filter window, three account-wide lists:

- **Vendor-Only:** items and categories valued at vendor price.
- **Blacklist:** never tracked; wins over everything else.
- **Delete List:** items that cannot be sold or auctioned; the Sell List offers them for deletion at a vendor, one per click.

**Sell List:** at a vendor, one button sells everything the Vendor-Only Filter and the Gear AH Threshold mark as vendor goods (equipment-set items are left out, one click sells at most 12 items).

Shortcuts on an item: **Ctrl+left-click** Vendor-Only, **Ctrl+right-click** Blacklist, **Shift+right-click** stop tracking (also on category headers).

## Optional modules

All off by default.

- **Loot Log:** the last 100 drops, per character.
- **Minimap HUD:** stretches the minimap over the screen so gathering nodes are readable all around you. Enable it in Settings → Minimap HUD, bind a key under Options → Keybindings → Night's Farmtracker (or use `/nft hud`). It cannot be opened in combat. Pins of HereBeDragons addons (GatherMate2, HandyNotes) and Routes move along.
- **Venom Tracker:** Venom/Toxin stack and Coiled Filament currency while [The Coiled Huntress](https://www.curseforge.com/wow/addons/the-coiled-huntress-venom-tracker) rod is equipped.
- **Fishing Lure Bar:** drag lures onto the bar, click to apply, right-click to remove, with the active buff and its time. Pairs well with [Better Fishing](https://www.curseforge.com/wow/addons/better-fishing).
- **Lockout counter:** instance resets in the last hour (x/9) and the time until the oldest expires.

## Settings

One window (Settings button or right-click on the minimap button) with a sidebar. Most settings belong to a **profile** you can create, copy, rename and switch. Window positions and the current session are stored per character.

## Commands

| Command | What it does |
| --- | --- |
| `/nft` | Open or close the window |
| `/nft filter` | Filter window |
| `/nft export` | Data export (JSON) |
| `/nft hud` | Toggle the Minimap HUD |
| `/nft hud size\|scale\|alpha <n>` | Adjust the HUD (size 20-100, scale 1-2.5, alpha 0-100) |
| `/nft hud rotate` | Toggle minimap rotation of the HUD |
| `/nft venom`, `/nft bait` | Show or hide the Venom Tracker / Lure Bar |

For bug reports: `/nft debug` opens a copyable debug log window.

---

See the [changelog](https://github.com/Nightwalker559/NightsFarmtracker/blob/main/CHANGELOG.md) for the version history.

## Feedback

Found a bug or have an idea? [Open an issue on GitHub](https://github.com/Nightwalker559/NightsFarmtracker/issues).

## License

MIT with AI restriction (no use for AI or machine learning), see [LICENSE.md](https://github.com/Nightwalker559/NightsFarmtracker/blob/main/LICENSE.md).
