# Night's Farmtracker

Track what you farm. See what it's worth.

Night's Farmtracker sits in your HUD while you grind and counts everything you loot — trade goods, crafting reagents, equipment, vendor trash. Items are grouped by class, sorted by value, and priced against your AH addon or vendor fallback. When the session ends, reset to save it to history and start fresh.

---

## Features

- Automatic loot detection — no setup, just farm
- Items grouped by WoW item class with collapsible categories
- Cosmetic weapons/armor (transmog-only) tracked in their own "Equipment (Cosmetic)" category
- Per-category price mode: AH + Vendor, AH only, or Vendor only (Shift+Click to cycle)
- AH Price by Expansion filter: limit AH pricing to selected expansions, everything else falls back to vendor price
- Gear AH Threshold: Equipment only uses its AH price once it reaches a configurable gold amount, below it (or with no AH price) vendor price is shown; a config icon lets you choose which Equipment categories (Equipment, BoE, BoA, Cosmetic) it applies to
- Crafting reagent quality tier breakdown (Q1/Q2/Q3) with per-tier AH pricing
- Session timer with pause/resume; optional fixed session length (timer counts down, session pauses itself at 0)
- Gold per hour / gold per minute rate display
- Direct gold from mob drops tracked separately
- Loot Log window: chronological, quality-colored entry list, persists per-character across reload
- Vendor-Only Filter window: force individual items or whole categories to vendor pricing
- Blacklist window: drop items or whole categories in to never track them, account-wide
- Account-wide session history, unlimited sessions, day-level merging, past months collapsed into a monthly group (current month stays expanded); optional Compact mode folds past months into one entry to keep saved-variables size bounded
- Shift+Right-click to exclude items or categories from tracking
- Minimap button, draggable and repositionable
- 13 selectable color themes
- English and German localization
- Optional Coiled Huntress Venom Tracker overlay (Settings → Fishing): shows Venom/Toxin stacks and Coiled Filament currency while [The Coiled Huntress](https://www.curseforge.com/wow/addons/the-coiled-huntress-venom-tracker) fishing rod is equipped, docked above the main frame, movable, close button and `/nft venom` to hide/show
- Optional Fishing Lure Bar (Settings → Fishing): drag lures from your bags onto the bar, click to apply one directly to your equipped fishing pole, right-click removes it; shows the active lure buff and its remaining duration, `/nft bait` to hide/show
- Optional instance lockout counter (Settings → Display): small frame below the main window showing resets in the last hour (x/9), the time until the oldest expires, and a button to reset instances
- Profiles (Settings → Profiles): settings live in switchable profiles instead of being tied to one character - create, copy, rename and delete profiles, switch anytime
- Tip: pair with [Better Fishing](https://www.curseforge.com/wow/addons/better-fishing) for double-click/keybind casting while you farm

---

## Price Sources

Works with [Auctionator](https://www.curseforge.com/wow/addons/auctionator), Oribos Exchange or [TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master). Without any of them, vendor prices are used where available.

---

## Slash Commands

| Command | Description |
|---|---|
| `/nft` | Toggle window |
| `/nft debug` | Toggle debug output |
| `/nft filter` | Toggle Vendor-Only Filter window |
| `/nft venom` | Toggle Venom Tracker overlay (if enabled) |
| `/nft venomdump` | Print Venom Tracker's raw tooltip lines to chat (debug) |
| `/nft bait` | Toggle Fishing Lure Bar (if enabled) |
| `/nft test` | Print current session to chat |

---

## Author

Nightwalker559