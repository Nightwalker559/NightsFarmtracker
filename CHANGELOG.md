# Changelog

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

- German help tooltip strings no longer show placeholder characters for unsupported Unicode symbols (arrows, plus signs replaced with ASCII equivalents)

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