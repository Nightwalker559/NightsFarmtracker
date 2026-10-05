# Night's Farmtracker

Track what you farm. See what it's worth.

Night's Farmtracker sits in your HUD while you grind and counts everything you loot — trade goods, crafting reagents, equipment, vendor trash. Items are grouped by class, sorted by value, and priced against your AH addon or vendor fallback. When the session ends, reset to save it to history and start fresh.

---

## Features

- Automatic loot detection — no setup, just farm
- Items grouped by WoW item class with collapsible categories; optionally split trade goods by subtype, split equipment by binding (BoE / BoA / Soulbound), or merge all Junk into one "Plunder" entry
- Cosmetic weapons/armor (transmog-only) tracked in their own "Equipment (Cosmetic)" category
- Every item is valued at the higher of its AH and vendor price; Vendor-Only items (Bind-on-Pickup, filtered items/categories) always use the vendor price
- AH Price by Expansion filter: limit AH pricing to selected expansions, everything else falls back to vendor price
- Gear AH Threshold: Equipment only uses its AH price once it reaches a configurable gold amount, below it (or with no AH price) vendor price is shown; a config icon lets you choose which Equipment categories (Equipment, BoE, BoA, Cosmetic) it applies to; optional alert sound for valuable drops
- Crafting reagent quality tier breakdown (R1/R2/R3) with per-tier AH pricing
- Session timer with pause/resume; optional fixed session length (timer counts down, session pauses itself at 0)
- Gold per hour / gold per minute rate display; classic (coin icons) or modern (colored text) gold format
- Direct gold from mob drops tracked separately
- Loot Log window: chronological, quality-colored entry list, persists per-character across reload
- Vendor-Only Filter window: force individual items or whole categories to vendor pricing
- Blacklist window: drop items or whole categories in to never track them, account-wide
- Account-wide session history, unlimited sessions, day-level merging, past months collapsed into a monthly group (current month stays expanded); optional Compact mode folds past months into one entry to keep saved-variables size bounded
- Data Export: copy the saved history (all months or a single month) as JSON for use outside the game
- Ctrl+Left-click an item to add it to the Vendor-Only Filter, Ctrl+Right-click to blacklist it
- Shift+Right-click to exclude items or categories from tracking
- Info button: short hover tooltip, click for the full help window (shortcuts and commands)
- Minimap button, draggable and repositionable
- 13 selectable color themes
- Profiles (Settings → Profiles): settings live in switchable profiles instead of being tied to one character — create, copy, rename and delete profiles, switch anytime
- English and German localization

### Optional modules (all off by default)

- **Minimap HUD** (Settings → Minimap HUD): see below
- **Coiled Huntress Venom Tracker** (Settings → Fishing): shows Venom/Toxin stacks and Coiled Filament currency while [The Coiled Huntress](https://www.curseforge.com/wow/addons/the-coiled-huntress-venom-tracker) fishing rod is equipped, docked above the main frame, movable, close button and `/nft venom` to hide/show
- **Fishing Lure Bar** (Settings → Fishing): drag lures from your bags onto the bar, click to apply one directly to your equipped fishing pole, right-click removes it; shows the active lure buff and its remaining duration, `/nft bait` to hide/show
- **Instance lockout counter** (Settings → Display): small frame below the main window showing resets in the last hour (x/9), the time until the oldest expires, and a button to reset instances

Tip: pair with [Better Fishing](https://www.curseforge.com/wow/addons/better-fishing) for double-click/keybind casting while you farm.

---

## Minimap HUD

Stretches the minimap over the screen so gathering nodes and tracking blips are readable all around your character. The feature is off by default; while it is disabled, the addon does not touch the minimap and the key binding does nothing.

1. Enable it under **Settings → Minimap HUD**.
2. Set your own key under **Options → Keybindings → Night's Farmtracker** (there is no default key), or use `/nft hud`.
3. Press the key to open and close the HUD.

Notes:

- Pins of HereBeDragons-based addons (GatherMate2, HandyNotes) and Routes move along with the minimap. Minimap buttons and UI panels attached to the minimap (made with ElvUI in mind) stay in the old spot on a placeholder and return when you close the HUD.
- Mouse clicks pass through to the 3D world; the HUD cannot be opened in combat (a close request in combat is carried out after it).
- Minimap rotation follows the HUD setting (on by default) while the HUD is open and is restored to your own setting afterwards.
- Tuning: `/nft hud size <20-100>` (percent of the screen height), `/nft hud scale <1-2.5>` (size of the symbols), `/nft hud alpha <0-100>` (opacity of the map background — 0 hides the map and keeps pins and blips), `/nft hud rotate` (toggle rotation).

---

## Price Sources

Works with [Auctionator](https://www.curseforge.com/wow/addons/auctionator), Oribos Exchange or [TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master). Without any of them, vendor prices are used where available. With several installed, "Auto" prefers Auctionator, then Oribos Exchange, then TSM.

---

## Slash Commands

| Command | Description |
|---|---|
| `/nft` | Toggle window |
| `/nft filter` | Toggle Vendor-Only Filter window |
| `/nft export` | Open the data export (JSON) |
| `/nft hud` | Toggle the Minimap HUD (if enabled) |
| `/nft hud size\|scale\|alpha <n>` | Adjust the Minimap HUD |
| `/nft hud rotate` | Toggle minimap rotation of the HUD |
| `/nft venom` | Toggle Venom Tracker overlay (if enabled) |
| `/nft bait` | Toggle Fishing Lure Bar (if enabled) |
| `/nft debug` | Toggle debug output |
| `/nft venomdump` | Print Venom Tracker's raw tooltip lines to chat (debug) |
| `/nft test` | Show the current session's tracked items (debug) |
| `/nft itemdb` | Show the item-audit catalog status (debug) |
| `/nft monthdump [itemID]` | Dump the current month's aggregate, optionally one item's variants (debug) |
| `/nft sessionsdump` | Dump the raw session storage structure (debug) |

---

## Project Layout

```
NightsFarmtracker.toc    load order
Bindings.xml             key bindings (must stay in the addon root)
Locales/                 enUS.lua (base), deDE.lua (overrides)
Core/                    Core, PriceHelper, ItemHelper, Repairs, UI, Main
Modules/                 History, Export, Debug, Log, Settings, Filter, Blacklist,
                         VenomTracker, BaitFrame, Lockout, Hud
Media/                   icons and sounds
```

To add a language, create `Locales/<locale>.lua` like `deDE.lua` and list it in the TOC after `enUS.lua`.

---

## Author

Nightwalker559
