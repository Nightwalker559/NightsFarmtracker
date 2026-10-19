# Night's Farmtracker

Track what you farm. See what it's worth.

Night's Farmtracker counts everything you loot while you grind (trade goods, reagents, equipment, vendor trash), groups it by class, sorts it by value and prices it against your AH addon or the vendor. When the session ends, reset to save it to the history and start fresh.

For World of Warcraft: Midnight (game versions 12.0.7, 12.1 and 12.1.5). English and German. Optional: Auctionator, Oribos Exchange or TradeSkillMaster for prices.

**Author:** Nightwalker559 · **License:** MIT

---

## At a glance

- **No setup.** Loot is detected automatically, just farm.
- **`/nft`** opens the window. The info button shows a short hover tooltip, a click opens the full help (shortcuts and commands).
- **Profiles.** Settings live in switchable profiles (Settings → Profiles): create, copy, rename and delete them, switch anytime.
- **Optional modules** (Minimap HUD, fishing helpers, lockout counter) are all off by default.

---

## Tracking

- Items grouped by WoW item class with collapsible categories. Optionally split trade goods by subtype, split equipment by binding (BoE / BoA / Soulbound), or merge all junk into one "Plunder" entry.
- Transmog-only weapons and armor get their own "Equipment (Cosmetic)" category.
- Crafting reagents show a quality tier breakdown (R1/R2/R3) with per-tier AH prices.
- Direct gold from mob drops is tracked separately.
- **Loot Log**: chronological, quality-colored list of what dropped, kept per character across reloads.
- Session timer with pause and resume. Optionally a fixed session length: the timer counts down and the session pauses itself at 0.
- `/reload` pauses the session, a relog saves it to the history and starts fresh.
- Gold per hour or per minute, in classic (coin icons) or modern (colored text) format.

## Pricing

Every item is valued at the higher of its AH and vendor price. Vendor-only items (Bind-on-Pickup, filtered items or categories) always use the vendor price.

- **AH Price by Expansion**: limit AH pricing to the expansions you pick, everything else falls back to the vendor price.
- **Gear AH Threshold**: equipment only uses its AH price once it reaches a gold amount you set; below it, or without an AH price, the vendor price is shown. A config icon lets you choose which categories it applies to (Equipment, BoE, BoA, Cosmetic). An optional alert sound plays for valuable drops.
- **Price sources**: Auctionator, Oribos Exchange or TradeSkillMaster. Without any of them the vendor price is used where available. With several installed, "Auto" prefers Auctionator, then Oribos Exchange, then TSM.

## Filter and blacklist

- **Vendor-Only Filter** (`/nft filter`): force single items or whole categories to the vendor price.
- **Blacklist**: drop items or categories onto it to never track them, account-wide.
- **Ctrl+Left-click** an item adds it to the Vendor-Only Filter, **Ctrl+Right-click** blacklists it, **Shift+Right-click** excludes it (or a category) from tracking.

## History and export

- Account-wide session history without a session limit. Sessions of one day are merged, past months fold into a monthly group (the current month stays expanded).
- **Compact mode** folds past months into a single entry to keep the saved data small.
- **Data export** (`/nft export`): copy the saved history, all months or a single one, as JSON for use outside the game.

## Look

- 13 color themes plus a custom color (Settings → Colors), with preview and an optional header gradient.
- Draggable, repositionable minimap button.

---

## Optional modules

All off by default.

### Minimap HUD

Stretches the minimap over the screen so gathering nodes and tracking blips are readable all around your character. While it is disabled, the addon does not touch the minimap and the key binding does nothing.

1. Enable it under **Settings → Minimap HUD**.
2. Set your own key under **Options → Keybindings → Night's Farmtracker** (there is no default key), or use `/nft hud`.
3. Press the key to open and close the HUD.

Notes:

- Pins of HereBeDragons-based addons (GatherMate2, HandyNotes) and Routes move along with the minimap. Minimap buttons and UI panels attached to the minimap (made with ElvUI in mind) stay in the old spot on a placeholder and return when you close the HUD.
- Mouse clicks pass through to the 3D world. The HUD cannot be opened in combat; a close request in combat is carried out after it.
- Minimap rotation follows the HUD setting (on by default) while the HUD is open and is restored to your own setting afterwards.
- Tuning: `/nft hud size <20-100>` (percent of the screen height), `/nft hud scale <1-2.5>` (size of the symbols), `/nft hud alpha <0-100>` (opacity of the map background, 0 hides the map and keeps pins and blips), `/nft hud rotate` (toggle rotation).

### Fishing (Settings → Fishing)

- **Coiled Huntress Venom Tracker**: shows Venom/Toxin stacks and Coiled Filament currency while the [The Coiled Huntress](https://www.curseforge.com/wow/addons/the-coiled-huntress-venom-tracker) fishing rod is equipped. Docked above the main frame, movable, with a close button. `/nft venom` hides or shows it.
- **Fishing Lure Bar**: drag lures from your bags onto the bar, click one to apply it to your equipped fishing pole, right-click removes it. Shows the active lure buff and its remaining time. `/nft bait` hides or shows it.

Tip: pair with [Better Fishing](https://www.curseforge.com/wow/addons/better-fishing) for double-click or keybind casting while you farm.

### Instance lockout counter (Settings → Display)

A small frame below the main window with the resets in the last hour (x/9), the time until the oldest one expires, and a button to reset instances.

---

## Commands

| Command | What it does |
| --- | --- |
| `/nft` | Open or close the window |
| `/nft filter` | Open or close the Vendor-Only Filter |
| `/nft export` | Open the data export (JSON) |
| `/nft hud` | Toggle the Minimap HUD (if enabled) |
| `/nft hud size\|scale\|alpha <n>` | Adjust the Minimap HUD |
| `/nft hud rotate` | Toggle minimap rotation of the HUD |
| `/nft venom` | Show or hide the Venom Tracker (if enabled) |
| `/nft bait` | Show or hide the Fishing Lure Bar (if enabled) |

Debug commands for bug reports: `/nft debug` opens a live debug log window (copyable, no chat output). `/nft venomdump`, `/nft test`, `/nft itemdb`, `/nft monthdump [itemID]` and `/nft sessionsdump` write their output into the same window.

---

The full version history is in the [changelog](https://github.com/Nightwalker559/NightsFarmtracker/blob/main/CHANGELOG.md). Bugs and suggestions: [GitHub Issues](https://github.com/Nightwalker559/NightsFarmtracker/issues), CurseForge or Wago.
