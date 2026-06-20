# Changelog

## [1.0.8] - 2026-06-19

### New

- Vendor-Only Filter: new window (button in BtnBar / `/nft filter`) — drag items from your bags into it to force vendor-only pricing for that item everywhere (HUD, category totals, session history), regardless of AH price
- Filter is account-wide and persistent until removed (Shift+Right-click on entry)
- Settings: Vendor-Only Filter can be disabled (Tracking section); when off, items in the list are priced normally again (list itself is kept)

### Fixed

- Filter button now shifts left to fill the gap when the History button is hidden (session history disabled), instead of leaving a blank space
- Session history (list, detail view, save) now correctly excludes BoP items and items flagged `canAH == false` from AH pricing, matching the live HUD — previously these could be overstated using the AH price in saved sessions
- Grey/junk items whose vendor price wasn't yet cached at loot time (cache miss) were silently dropped instead of being tracked and resolved via bag scan
- Settings: custom TSM price source field referenced an undeclared variable due to declaration order, so the dropdown's greyed-out state never updated live while typing (only after reopening Settings)
- Removed a stale hardcoded item-class priority entry that could block the correct (runtime-detected) Housing category sort order
- Removed dead minimap-icon stub code left over from the pre-LibDBIcon implementation
- HUD refresh (`RefreshHUD`) no longer recalculates each item's AH/vendor price up to three times per loot event; gold totals are now computed once and reused

---

## [1.0.7] - 2026-06-18

### Fixed

- Junk/Müll items were including AH prices (from Auctionator or TSM) in the category total, overall gold, and session history; vendor price is now always used for items with quality 0 or flagged as vendor trash

---

## [1.0.6] - 2026-06-18

### Fixed

- HUD category totals could show far less gold than the actual session total when a category mixed AH-priced and vendor-only items (e.g. "Metalle & Steine" 2997g vs. items only counted via AH falling out entirely); category gold now sums max(AH, Vendor) per item, matching the overall total
- Same fix applied to the Session History detail view, where category totals previously favored AH-only sums and could undercount vendor-only items
- Removed now-unused per-category `totalVendor`/`totalAH` accumulation in the HUD (dead code)

---

## [1.0.5] - 2026-06-17

### Changed

- Minimap button migrated to LibDBIcon-1.0 — button now integrates correctly with MinimapButtonButton, ElvUI, Bazooka, and other minimap managers
- Embedded libs added: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0
- ElvUI: minimap button position now correctly updated after UI load
- Re-enabling the minimap button via Settings now prompts for a UI reload so minimap bar managers (e.g. WindTools) pick it up immediately

---

## [1.0.4] - 2026-06-16

### Changed

- Session history: clicking the day header no longer merges sessions; merging is now handled automatically via the Settings option
- All icon buttons (main frame, history, detail, settings) standardized to 18×18 px
- Button icons replaced with new artwork
- Texture format switched from TGA to PNG across all media files

---

## [1.0.3] - 2026-06-16

### New

- Settings: option to disable automatic same-day session merging; when off, each session is saved individually

### Changed

- Per-category price mode (Shift+Click to cycle AH/Vendor) removed; price source is now controlled globally via Settings
- Settings frame width increased to 320; long labels now wrap instead of being cut off
- Radio buttons and checkboxes in Settings now use identical indicator size

---

## [1.0.2] - 2026-06-16

### New

- Main frame header now has a close button (X) to hide the window directly
- Session timer turns green while tracking is active
- Settings: option to split trade goods and reagents into WoW subtypes (Herb, Metal & Stone, Leather, etc.) instead of one combined category

### Changed

- Frame width reduced from 340 to 310
- Crafting reagent quality rank indicator (Q1/Q2/Q3) moved from item name to the count column, keeping item names readable
- Item names truncated to 20 characters to keep columns aligned
- "No sessions saved" message shortened

### Fixed

- English client: copper amounts from direct gold drops were not tracked
- Day-merge (history): crafting reagent quality tier data (Q1/Q2/Q3) was lost when merging sessions of the same day
- German help tooltip strings no longer show placeholder characters for unsupported Unicode symbols

---

## [1.0.1] - 2026-06-16

### New

- Settings: session history can now be disabled; when off, nothing is saved and the history button is hidden
- Settings: frame now scrolls when content exceeds the visible area
- Gold overview: click on total gold in the footer to toggle a panel anchored below the main frame
- Companion and hunter pet loot (pushed items) is now tracked alongside player loot
- Loot from encounters (ENCOUNTER_LOOT_RECEIVED) is now tracked as a secondary source, catching items that bypass chat parsing

### Changed

- Item tracking simplified: only items sellable at vendor or auction house are tracked
- Items with unknown sell price at loot time (cache miss) are now tracked and resolved later via bag scan
- BoP items without a vendor price are no longer tracked (truly unsellable)
- BoE items are now tracked without requiring a vendor price at loot time
- BoA and Warband-bound items now always use vendor price instead of AH price
- Categories are now sorted by their displayed gold value instead of an internal calculation
- Scaled equipment now shows the correct vendor price based on item level instead of the base item price
- Total gold in the footer now includes direct gold drops and updates immediately
- classID and bind flags are now resolved from the bag link when missing at loot time

### Fixed

- Gold overview panel was not updating when first opened
- BoP and BoA items were being dropped if vendor price was not yet cached at loot time
- Multiple loot events for the same item within the same session were being incorrectly deduplicated
- Companion loot (singular and plural message formats) now correctly tracked
- Encounter loot (boss drops, BoA gear) now tracked even when chat parsing fails
- History: "No sessions saved" message now appears centered in the frame

---

## [1.0.0] - 2026-06-15

Initial release.

- Automatic loot tracking via chat events
- Items grouped by WoW item class with collapsible categories
- Vendor and AH price display (Auctionator / TSM)
- Crafting reagent quality tier breakdown (Q1/Q2/Q3)
- Session timer with pause/resume
- Gold per hour / gold per minute rate
- Direct gold from mob drops tracked separately
- Account-wide session history (up to 50 sessions) with day-level merging
- Exclude items or categories from tracking
- Minimap button
- English and German localization