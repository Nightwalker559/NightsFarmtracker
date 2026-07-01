# Changelog

## [1.1.2] - 2026-07-01

### New

- Session History: sessions are now grouped by month. Past months are collapsed by default (click the month header to expand/collapse); the current month starts expanded but can be collapsed too
- Month headers show a delete button to remove all sessions of that month at once (with confirmation), instead of deleting sessions one by one or clearing the whole history
- Session History and Loot Log now share a single button: left-click opens Session History, right-click opens Loot Log. Tooltip and the "?" help window reflect both actions
- New Settings section "Color Theme" to switch the addon's border/background/accent colors, picked from an expandable dropdown menu: Default, Void, Silvermoon, Fel, Frost, Bloodmoon. Gold text color stays the same across all themes. Requires a UI reload to fully apply

### Changed

- Session History rows no longer show the item count ("N items") - duration and gold are enough at a glance, the full item breakdown is still available in the session detail view
- The "?" help window now sorts its sections alphabetically by their (localized) title instead of a fixed order

### Fixed

- German localization: the help window's "Items" section title and hover hint were left untranslated (still showed the English words) - now properly localized
- Color Theme: the main frame's and Gold Overview's border/background/accent colors kept the default theme's colors even after switching to another theme and reloading. Both are built before SavedVariables are available, so they now get explicitly re-skinned once the saved theme is loaded
- Color Theme: the "Gathering... loot will appear here" empty-state hint was still hardcoded to the default teal instead of following the selected theme's accent color
- Gold Overview and Loot Log windows overlapped when both were open and the main frame was collapsed, since both anchored to the same spot directly below the main frame. Loot Log now chains below Gold Overview in that case, matching the existing chaining behavior between Vendor-Only Filter and Loot Log
- Settings window jumped back to the top every time a radio option (AH source, gold display, gold rate, color theme) was changed, since the content rebuild always reset the scroll position to 0. It now keeps the current scroll position (clamped to the new content height)

## [1.1.1] - 2026-06-23

### New

- Session History: days with more than one session now show a "Merge" button next to the date header - merges all sessions of that day into one (duration, gold, items combined). Useful for sessions saved before "Merge same-day sessions automatically" was enabled
- Loot Log window now anchors below the main frame when it's collapsed, and back to its right side (or right of the Vendor-Only Filter window) when expanded again

### Fixed

- Quest items were tracked despite never having a vendor or AH value. Quest-class items are now correctly detected and always treated as unsellable, regardless of bind type. Already-tracked quest items in the current session are cleaned up automatically on the next refresh - no reset required

### Cleanup

- Removed unused `CAT_BOE`/`CAT_BOP` legacy category aliases in Core.lua (never referenced)
- The vendor-only check (junk/quality0/BoP/canAH=false/forced-vendor) was duplicated three times in History.lua — consolidated into one shared `ns.IsVendorOnly()` helper in Core.lua; no visual or behavioral change
- The AH-eligibility (`canAH`) calculation was duplicated identically at loot-time and during the deferred bag-price scan in Main.lua — consolidated into one local `CanAH()` helper; no behavioral change
- Removed unused `ADDON_NAME` local in UI.lua

## [1.1.0] - 2026-06-23

### New

- Optional Loot Log window (button in BtnBar) - shows a feed of looted items (icon, name, amount, item quality), one line per loot event, most recent first
- Settings: Loot log window is disabled by default; enable it in the Tracking section
- Loot log entries are saved per-character (SavedVariablesPerCharacter) and survive `/reload` and relogs - only a session reset clears them
- Loot Log anchors right of the main frame and docks next to the Vendor-Only Filter when both are open (whichever opens second chains outward); does not close on Escape, only on session reset
- Loot Log window's open/closed state is also saved per-character and restored after `/reload` and relogs
- Loot Log rows show a timestamp (HH:MM) before the item icon

### Changed

- Crafting-reagent rank indicator (R1/R2/R3) moved from inline text next to the count to a small badge between the item icon and item name — consistent across the main HUD, history detail view, and the new loot log

### Fixed

- Main frame was anchored via "CENTER", so collapsing/expanding (and any height change) grew/shrank the frame symmetrically around its middle - the header visually drifted instead of staying put. Now anchored via "TOP": the header stays fixed in place and the frame only grows downward. Saved positions are normalized automatically on login (same screen spot, no jump)
- Root cause of the above persisting even after the anchor fix: WoW's drag mechanism does not preserve the original anchor point type after moving the frame - it can hand back e.g. "RIGHT" (vertically centered) instead of "TOP", silently reintroducing the symmetric-growth bug on every drag. The drag handler now always normalizes the anchor back to "TOP" after a move
- Some ElvUI/WindTools setups re-anchor unrelated addon frames after entering the world, silently swapping our "TOP" anchor for something else even with the above fixes in place and the saved position correct. The main frame's anchor is now defensively re-applied after `PLAYER_ENTERING_WORLD`, mirroring the existing minimap-button fix for the same kind of interference

### Cleanup

- Removed unused `Q_FALLBACK` local in Core.lua and an unused `gathering_start` locale string (EN+DE)
- Removed an orphaned empty comment header in History.lua
- Item-row quality coloring (icon border + name color) was duplicated identically in five places across UI.lua, History.lua, Filter.lua, and Log.lua — consolidated into one shared `ns.ApplyQualityColor()` helper in Core.lua; no visual or behavioral change
- Rank-icon size (`CreateAtlasMarkup` width/height) was hardcoded identically in three places — consolidated into `ns.RANK_ICON_W`/`ns.RANK_ICON_H` in Core.lua

## [1.0.9] - 2026-06-22

### New

- Pets and Mounts now get their own categories ("Pets"/"Haustiere", "Mounts"/"Reittiere") instead of being grouped under Miscellaneous
- Shift+Click on Reset button resets the session without saving it to history
- Help tooltip now also explains the Gold Overview (click footer total) and the Shift+Click reset behavior
- Settings: Gold display can be switched between Classic (coin icons) and Modern (colored text, e.g. `31g 60s`) — applies everywhere gold is shown (HUD, category totals, footer, history)
- Modern display matches Classic's existing behavior of hiding the copper value from 1g onward
- Modern display suffixes (g/s/c) are now localized — German uses "k" for Kupfer instead of "c"
- Modern display uses Blizzard's native `GOLD_COLOR_CODE`/`SILVER_COLOR_CODE`/`COPPER_COLOR_CODE` globals when available, with a hardcoded hex fallback for clients where they're not defined

### Fixed

- `GetItemInfoInstant` return values were off-by-one in two places (loot-time cache-miss recovery, bag-scan price resolution), causing wrong icon/classID and bogus bind-type checks for items not yet cached at loot time; bag-scan now reuses the existing full `GetItemInfo` call instead, which also correctly resolves bind flags afterwards

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