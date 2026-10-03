# Changelog

## 1.7.0

### New

- Data Export: pick which month to export (or all months) before the export text opens

### Changed

- Rank icons (R1/R2/R3) now sit on the bottom-right corner of the item icon instead of beside it
- Item names start 4 px from the icon, giving names and amounts more room

## 1.6.9

### New

- Session History: hover an item's gold amount to see how many items were valued at AH vs. vendor price (new sessions)

### Changed

- Item icons 22 -> 30 px, 2 px gap between rows
- Main window rows show the same value as the category total
- Instance Lockout checkbox moved to Settings -> Display
- Code cleanup

### Fixed

- History keeps the Vendor-Only filters as they were when the session was saved (new sessions)
- History: merged sessions with mixed AH/vendor pricing now add up correctly
- Blacklist: category blacklisting at loot time now respects binding/cosmetic
- Turning off the Vendor-Only filter also turns off AH Price by Expansion
- Active filter/blacklist categories stay listed after a Reset
- `/nft filter` respects the Vendor-Only filter switch

## 1.6.8

### New

- Instance lockout counter (Settings -> Display, off by default): small frame below the main window showing resets in the last hour as x/9, the time until the oldest one expires, and a button that resets instances. Tooltip lists each reset with its expiry time. Resets are tracked account-wide
- Gear AH Threshold: config icon next to the threshold field (Settings -> AH Price Source) lets you choose which Equipment categories (Equipment, BoE, BoA, Cosmetic) the threshold applies to. Unchecked categories use the higher of AH and vendor price. All categories stay enabled by default, so existing behavior is unchanged

### Changed

- Items of obsolete classes (WoW Token, obsolete Money/Permanent) are no longer tracked
- Loot parsing is safe against Midnight "secret values": CHAT_MSG_LOOT, CHAT_MSG_MONEY and ENCOUNTER_LOOT_RECEIVED skip secret payloads instead of erroring
- Looted gold is parsed with the client's own coin strings (works in every language, not just EN/DE); own loot is additionally recognized by sender GUID

## 1.6.7

### New

- Oribos Exchange support as a third AH price source (Settings -> AH Price Source), alongside Auctionator and TSM - no desktop app required; Auto mode now tries Auctionator, then Oribos Exchange, then TSM; falls back to the region price when the realm has no recent data

### Fixed

- Session History: a session farmed before midnight and reset after was filed under the reset day instead of the day it was actually farmed - sessions are now dated by when tracking started, not when Reset was clicked
- `.toc` IconTexture pointed at a non-existent `Icon.png` (only `Icon.tga` is shipped) - addon list icon now loads correctly

## 1.6.6

### New

- Session length (Settings -> Display): set e.g. 60 min and the timer counts down and pauses the session automatically at 0 (0 = off); Gold/hour then equals total gold / session length

### Changed

- Gold/hour is back to the plain session average (totalGold/totalTime) - reverts the EMA smoothing from 1.6.5

## 1.6.5

### Changed

- Gold/hour (footer rate button) is now EMA-smoothed instead of a plain lifetime average (totalGold/totalTime) - reflects recent farming pace instead of staying skewed by one early big drop for the rest of the session
- AH price lookups (Auctionator/TSM) are now cached for 1 hour per item, cutting repeated API calls on every HUD refresh; cache clears automatically when the AH source, TSM price source or custom TSM string is changed

### Fixed

- Gear AH Threshold sound only ever fired once per item group per session - looting a 2nd/3rd copy of an already-notified valuable item stayed silent; now re-checks and alerts again on each new copy whose own AH price reaches the threshold

## 1.6.4

### Fixed

- Combat lockdown: opening/closing/toggling any window (Main, Gold, Log, Filter, Blacklist, Settings, History/Detail, Venom Tracker, Export) via its X button, minimap icon, or `/nft` could throw ADDON_ACTION_BLOCKED - all Show()/Hide() calls now deferred to right after combat via a shared `ns.DeferInCombat` helper
- Venom Tracker overlay: scan now bails out cleanly in combat instead of risking a blocked Show/Hide, and re-syncs automatically once combat ends

## 1.6.3

### Changed

- Settings sidebar consolidated from 11 to 8 sections: TSM Price Source merged into AH Price Source (it's a detail of that choice); Color Theme and the Log Window toggle moved into Display
- Internal: gear-variant vendor sell-price fallback (recorded price, else live item link/ID lookup) was duplicated in History.lua, ItemHelper.lua and UI.lua; now a single shared `ns.VariantSellPrice` in PriceHelper.lua - no behavior change

### Fixed

- Gear AH Threshold sound could stay silent for Adventurer's/scaling gear: it checked each raw bonus-ID roll on its own instead of the combined value shown in the item's row, so a second pickup that looked identical but landed in its own bucket never individually reached the threshold even though the displayed total did
- Settings sidebar: alphabetical sort could place Profiles above other sections (e.g. Session History) depending on locale; Profiles now always sorts last

## 1.6.2

### New

- Data Export: Settings -> Data Export opens a copyable window with the full saved session history as JSON (every month, same category/item gold values as Session History), for further processing outside the addon
- Data Export includes each item's quality (for text color) and reagent rank (R1/R2/R3) where applicable
- `/nft export` slash command as a shortcut for the above
- Info tooltip (main window "?" button) now mentions Data Export

### Changed

- `/nft test`, `/nft itemdb`, `/nft monthdump`, `/nft sessionsdump` now open a copyable window instead of spamming chat
- Internal: all debug dump commands and their shared UI helper moved into a new `NightsFarmtrackerDebug.lua`; Data Export's window code is now a shared, reusable helper too

### Fixed

- Gold Overview frame's title and row text now use the addon's standard font sizes instead of unscaled Blizzard defaults, matching the main window's text

## 1.6.1

### Changed

- Internal: scaling/Adventurer's gear and reagent quality tiers now share one unified `variants` storage schema instead of three separate shapes - no behavior change
- All windows (History, Settings, Filter, Blacklist, Log, Detail, Gold Overview, Venom Tracker, Fishing Lure Bar) now use the same frame strata as the main window

### Fixed

- Scaling/Adventurer's BoE gear could show vendor price instead of AH price, or drift out of sync with the item's total
- Main window could throw `ADDON_ACTION_BLOCKED` when resizing (e.g. after looting) during combat; resize is now deferred to combat end instead
- Session History: a stray legacy variant key could misclassify a gear item as a reagent-tier, showing stale, un-recomputed month-summary totals
- Session History: an item's displayed gold value could disagree with how the row was sorted when its vendor price exceeded its AH price
- Scaling/Adventurer's gear could split into two variant buckets for the exact same roll instead of one summed bucket, fragmenting its AH value, if the item's link resolved differently once fully cached
- Gear items no longer store a redundant, easily stale duplicate of their item link outside their variant data
- One-time login repair applies all of the above fixes to saved session history and the live session

## 1.6.0

### Fixed

- Bind-on-Use items always showed vendor price, ignoring Filter/category settings - now priced via AH again like BoE
- One-time repair on login fixes already-affected items in the live session and all saved session history

## 1.5.9

### Fixed

- Fishing Lure Bar: refreshing while in combat could touch the SecureActionButtonTemplate lure buttons and throw `ADDON_ACTION_BLOCKED`; refresh now skips entirely during combat and re-runs on leaving combat
- Reagent quality-tier tracking (R1/R2/R3) could drift far above an item's own tracked amount and stay corrupted indefinitely once it happened; tracking now self-heals on the next loot of that item instead of freezing the bad numbers
- Same-day session merging and the old item-key migration could sum an already-corrupted tier breakdown into the target instead of ignoring it, compounding the corruption further with every merge
- One-time cleanup on login for already-saved sessions and the current running session: clears corrupted reagent-tier breakdowns and gearVariants/vendorTotal mismatches left over from before the above fixes existed

## 1.5.8

### New

- Session History: Shift+Click a month row to open a month-wide summary in the Detail window (all sessions of that month merged, same view as single sessions)
- Gold values now show a thousands separator (e.g. `1.056.859`) in every window
- Hovering a gold total (session row, month row, Detail window header) shows an Items / Direct / Total breakdown tooltip
- Detail window header now shows only the date/month (was wrapping to 2 lines for month summaries); hovering it shows duration + gold breakdown

### Fixed

- Session History: month row totals now include Direct (looted) gold, matching the Detail window's total
- Item name/quality-color resolution (`ns.DisplayName`, `ns.ApplyQualityColor` - used by every item row in every window) called the non-namespaced `GetItemInfo`/`GetItemQualityColor` globals, which are removed on current 12.x clients; switched to `C_Item.GetItemInfo`/`C_Item.GetItemQualityColor`
- Trade Goods/Reagent subtype splitting used the deprecated global `GetItemSubClassInfo`; switched to `C_Item.GetItemSubClassInfo` for consistency with the rest of the item API calls
- Detail window: the new header gold-breakdown hover tooltip overlapped the close button, swallowing clicks meant to close the window after hovering the header
- Crafting-reagent quality-tier rows (e.g. per-rank ore) could show wildly inflated item counts: `GetReagentQualityInfo` occasionally mis-tagged an item's rank, corrupting the internal per-tier breakdown while the item's real tracked amount stayed correct; tier tracking now rejects updates that would push the breakdown above the item's own amount, and History/HUD fall back to the correct total for any already-corrupted entries instead of displaying the bad count
- Entries falling back to the correct total (see above) now still show their R1/R2/R3 rank badge, read directly from the item's own saved link instead of the unreliable live tracking
- The same mis-tagged reagent tier could also inflate an item's tracked AH gold value (not just its count), since the per-tier price total was computed from the same corrupted breakdown; `ns.AHTotal` now applies the same consistency guard, and History's category/item gold totals recompute live for any already-saved entry whose breakdown fails it
- Session/month gold totals (session row, month row, Detail window header) froze the same inflated numbers at save time; a one-time repair on login recomputes every saved session's totals from its own items - fixed to reuse the same frozen per-item values the Detail window itself displays, after an earlier version of this repair briefly re-priced gear off today's live AH price instead and made totals disagree with the category breakdown

### Changed

- Font sizes standardized on even values via shared `ns.FONT_SMALL/NORMAL/HEADER` constants (was a mix of 10/11/12 literals); default row text now 12 instead of 11
- Window titles (Session History, Vendor-Only Filter, Blacklist, Loot Log, Settings) now use the same header font size as the Detail window
- All window titles (incl. Detail window and Gold Overview) are now center-aligned instead of a left/center mix
- Settings title sat 2px lower than every other window's title; now aligned
- Header height unified across all secondary windows (History, Detail, Vendor-Only Filter, Blacklist, Loot Log) to match Settings' 34px (was 40px, borrowed from the main frame's taller icon-toolbar header)
- Main frame header reduced to the same 34px (was 40px) — icon toolbar still fits
- Settings header separator was still hardcoded at a fixed offset and sat 3px higher than the other windows'; now tied to the shared header height like everywhere else

## 1.5.7

### Changed

- Gap between docked windows (Log/Filter/Blacklist, History/Settings, Venom Tracker, Fishing Lure Bar) reduced from 4px to 1px

### Fixed

- Hiding the Fishing Lure Bar (closing the main window, disabling it in Settings, or toggling it) could throw "ADDON_ACTION_BLOCKED" while in combat, since it parents a secure lure-apply button; hide is now deferred to combat end instead of failing

## 1.5.6

### New

- Profiles: settings (color theme, AH source, TSM, filters, windows, gold display, etc.) now live in switchable profiles instead of being tied to one character - create, copy, rename and delete profiles from Settings → Profiles; "Default" always exists and can't be deleted; deleting an unused (non-active) profile applies instantly, switching your active one still reloads the UI

### Changed

- Fishing Lure Bar: lures now sorted by current bag quantity (most first) and grayed out when no longer owned

### Fixed

- Fishing Lure Bar and Venom Tracker: closing via the X button left the corresponding Settings checkbox showing as enabled; it now disables the bar properly, keeping the checkbox in sync
- Item tooltips in History, Log, Filter and Blacklist rows no longer show Blizzard's "currently equipped" comparison tooltip, which was confusing for past loot entries
- `ns.SmartAnchor` (edge-aware tooltip anchoring used by History, Log, Filter and Blacklist row tooltips) was called throughout the addon but never defined, causing an error on hover; now implemented
- Closing the main window left the Fishing Lure Bar open (Loot Log, Filter, Blacklist, History, Settings and Venom Tracker already closed with it)

## 1.5.5

### Fixed

- Two drops of the same scaling/Adventurer's gear piece with identical displayed item level and quality could still show as separate, unsummed rows instead of one combined row (their underlying bonus-ID rolls differed even though nothing visible did); gear-variant rows are now grouped by displayed item level + quality instead of the raw bonus-ID key

## 1.5.4

### Changed

- Gear AH Threshold alert now uses a custom sound file (`Media\ThresholdAlert.ogg` or `.mp3`) instead of a fixed built-in SoundKit; falls back to the built-in sound if no custom file is present

### Fixed

- Two drops of the exact same weapon/armor piece could be listed as separate rows instead of adding up: the gear-variant key was built from the raw loot/bag item link, which can carry incidental noise (uniqueID, linkLevel) that differs between drops of an otherwise identical item; now built from the cleaned/canonical item link instead
- Gear AH Threshold decision for scaling/Adventurer's gear variants was based on the combined AH value of all variants of an item instead of each variant's own AH value, so a cheap variant could wrongly show its (below-threshold) AH price while an expensive sibling variant stayed on vendor price
- Settings sidebar: category labels (e.g. "Categories & Grouping") could render unwrapped on the very first open instead of wrapping onto multiple lines

## 1.5.3

### New

- Optional sound alert when an Equipment item's AH value reaches the Gear AH Threshold

### Fixed

- Session History: AH value for split reagent/gear rows was recalculated live instead of frozen per session, causing incorrect totals after AH scans or session merges
- Session History: legacy entries without a frozen AH value now fall back to a live lookup instead of always showing vendor price
- "Merge Junk entries" now applies from the first item, not just once a 2nd item drops
- Main frame could get stuck on vendor price (and skip the threshold sound) when the AH price wasn't cached yet at loot time; now self-corrects via delayed refresh
- Threshold sound now fires even while its Equipment category is collapsed

## 1.5.2

### Changed

- Full pre-release audit (syntax check, dead-code scan, locale-key cross-check across EN/DE) - no functional bugs found
- Consolidated 4 identical button-refresh wrappers (`UpdateHistoryBtn`/`UpdateFilterBtn`/`UpdateBlacklistBtn`/`UpdateLogBtn`) into one `ns.RefreshLeftButtons()` (no behavior change)
- Item classification/value logic (`CategoryName`, `GearCategoryName`, `IsGear`, `IsVendorOnly`, `ItemValue`, Junk-merge helpers) moved out of Core.lua into a new `NightsFarmtrackerItemHelper.lua` (no behavior change)
- Deduplicated Vendor-Only Filter and Blacklist window code: the category-checkbox section, the AH-by-expansion section, and the item drop-list are now one shared implementation each (`ns.RebuildCheckboxSection`, `ns.RebuildDropItemList` in Core.lua; `ns.GetTrackedCategoryNames` in ItemHelper.lua) instead of two near-identical copies. Filter.lua shrank from 411 to 269 lines, Blacklist.lua from 307 to 214 - no behavior or layout change, verified against the original pixel-position formulas

### Fixed

- Scaling/Adventurer's gear variants (same item ID, different item level) could merge into one bucket and show the same price on first loot, since itemLevel/quality aren't reliable at loot time; now keyed by the item link's bonus IDs instead
- Bag-scan price correction and the login bag-repair migration updated to match the new key
- Session History detail view collapsed scaling-gear variants and reagent quality tiers back into one row for vendor-only items (e.g. BoP), instead of splitting per item level/tier like the main HUD already did; total gold was correct either way, only the row breakdown was missing

## 1.5.1

### New

- Settings: "Merge Junk into one entry" - collapses the whole Junk category into a single "Trash" row (main frame + Session History detail), display-only so existing sessions apply retroactively and the setting is reversible at any time

## 1.5.0

### Fixed

- Gear dropping under the same item ID at different item levels/qualities (e.g. Adventurer's/scaling gear) was merged into one tracked entry, mixing amounts and prices between variants; now split into separate rows per item level, on the main frame and in Session History detail, same as the existing reagent quality-tier split
- One-time bag rescan on login repairs gear already merged this way, both in the live session and the most recently closed one (items no longer in bags keep their total amount under a single fallback entry)

## 1.4.9

### New

- Fishing Lure Bar: lures are added manually by dragging from bags (like Vendor-Only Filter/Blacklist); right-click removes one; non-lure drops are rejected unless Shift is held

### Fixed

- Fishing Lure Bar failed to use lures (taint/macro errors) and didn't accept click-to-place drops; now uses a secure macro button with the same drop handling as Vendor-Only Filter/Blacklist
- Items tracked by localized name instead of item ID, causing duplicates across languages; also broke item exclusion (Shift+Right-click) after a language switch; both now keyed by item ID, existing history migrates automatically
- Removed unused `trackedNames` setting and dead `ns.RefreshAllWindowChains` code; translated remaining German code comments to English
- Deduplicated Vendor-Only Filter/Blacklist UI code into shared helpers (no behavior change)

## 1.4.8

### New

- Fishing Lure Bar: docks next to the main frame, lists fishing lures found in your bags, click applies one directly to your equipped fishing pole
- Fishing Lure Bar shows the active lure buff and its remaining duration, read straight off the pole's tooltip
- Settings: sections now sort alphabetically (per the client's current language) instead of a fixed order
- Settings: new left-side sidebar lists all categories — click one to jump straight to it
- Settings: Venom Tracker and Fishing Lure Bar grouped under a new "Fishing" section
- `/nft bait` command to toggle the Fishing Lure Bar

### Fixed

- Fishing pole detection updated for the Profession Tool equipment slot (the rod no longer sits in Main Hand)
- Coiled Huntress Venom Tracker now docks above the Fishing Lure Bar when it's shown, instead of overlapping it
- Trade Goods/Reagent subtype categories (when split by type) now resolve the display name fresh from the current client language instead of caching whatever language was active the first time an item was looted; falls back to resolving it from the item ID, so already-saved Session History entries self-heal too instead of staying stuck
- Item names (main frame, Session History, Loot Log, Vendor-Only Filter, Blacklist) now resolve fresh from the item ID/link at display time instead of the language they were first looted in - old entries self-heal the same way
- Fishing Lure Bar (and Venom Tracker) could lose their anchor to the main frame after certain reload timings, rendering detached; both now get a valid anchor immediately on creation instead of only on their first show

## 1.4.7

### Fixed

- Item names with multi-byte UTF-8 characters (e.g. German umlauts) no longer render broken glyphs when truncated for column display

## 1.4.6

### New

- Vendor-Only Filter: "AH Price by Expansion" section — check expansions to show AH price for; unchecked ones fall back to vendor price (all expansions on by default)
- Vendor-Only Filter and Blacklist: "Clear All" button to remove all individually-added items at once (with confirmation)
- Settings: "Reset to Default" button — wipes all saved data (settings, session history, Vendor-Only filter, Blacklist) and reloads the UI (with confirmation)

### Fixed

- Category/section headers (Filter, Blacklist, Session History, Session Details, main HUD) now render with a proper top and bottom border flush against the background, removing black gaps that appeared between headers and separator lines

## 1.4.5

### Fixed

- Gear AH Threshold now also applies to cosmetic Equipment (transmog-only items), which was previously skipped since it had no bind flags set yet

## 1.4.4

### New

- Gear AH Threshold setting: Equipment only uses its AH price once it reaches a configurable gold amount; below it, vendor price is shown (0 = disabled)
- Session History: "Clear All" now asks for confirmation before deleting

### Changed

- Deduplicated the repeated tooltip-style backdrop styling (9 occurrences across Settings/Blacklist/Filter) into one shared `ns.StyleBackdropBox()` helper

## 1.4.3

### New

- Venom Tracker: `/nft venomdump` prints raw tooltip lines for locale debugging

### Fixed

- Venom Tracker: fixed stale Venom/Toxin value shown right after a catch (tooltip data lagged behind the actual stat); rescan is now retried shortly after trigger events
- Venom Tracker: locale keyword mismatch now shows "n/a" instead of a misleading "0", with a one-time chat warning pointing to `/nft venomdump`

## 1.4.2

### New

- Venom Tracker: close button (X) to hide the overlay manually, hidden state persists across sessions — uses the addon's own `btn_close.png` skin instead of the default Blizzard button
- Venom Tracker: `/nft venom` toggles the overlay

### Fixed

- Venom Tracker: frame now widens automatically for long values (e.g. Filament > 9999) instead of clipping

### Changed

- Venom Tracker: removed a redundant, frequently-firing event that caused unnecessary scans

## 1.4.1

### New

- Cosmetic weapons/armor (transmog-only, `C_Item.IsCosmeticItem`) now get their own "Equipment (Cosmetic)" category instead of being grouped into regular Equipment

### Fixed

- Closing the main window now also closes Loot Log, Filter, Settings, Blacklist, Session History, and the Venom Tracker overlay instead of leaving them floating; Venom Tracker reappears automatically when the main window is reopened

## 1.4.0

### New

- Optional Coiled Huntress Venom Tracker overlay (Settings → Extras, off by default): shows Venom/Toxin stacks and Coiled Filament currency while the item is equipped; docked above the main frame by default, movable and independently repositionable (right-click resets position)

## 1.3.0

### New

- Split equipment into BoE / BoA / Soulbound sub-categories (Settings → Categories & Grouping), off by default
- Settings reorganized into clearer sections: Session History, Categories & Grouping, Filters, Windows
- One-time login prompt to clear old session history (needed for the tooltip fix below)

### Fixed

- Category exclusion (Shift+Right-click header) didn't actually stop future loot of that category, only cleared the current view
- Item quality/color could get stuck on a wrong loot-time guess for scaling gear; now corrected via bag rescan, including already-written Log entries
- Session History tooltips showed the wrong (generic) item instead of the one you looted; item link is now saved and used
- Old Session History entries without a saved link show the item name only instead of a misleading tooltip
- Warband/BoA items (bindType 7/8/9) now detected directly per current `Enum.ItemBind`

### Changed

- Checked against Patch 12.1 — no relevant API changes (12.1 only touches auras/combat log)

### Removed

- Dead legacy code (`CAT_VENDOR`/`CAT_MATS` aliases)

## 1.2.1

### Fixed

- Auctionator price for the main item now matches Auctionator's own tooltip: items with variable bonus IDs (e.g. random-stat gear) are priced by item link instead of item ID, which previously could average across all stat rolls and show the wrong price
- Item links passed to Auctionator/vendor pricing are now normalized to their canonical form first, avoiding lookup mismatches for items whose stored link wasn't already in that exact form

### Changed

- AH/vendor pricing logic (Auctionator, TSM, vendor sell price) moved out of Core into its own `NightsFarmtrackerPriceHelper.lua` file

## 1.2.0

### New

- Blacklist window: items/categories dropped here are never tracked at all (account-wide, persistent), same drag & drop / category-checkbox UI as the Vendor-Only Filter — takes priority over the Vendor-Only Filter and all other tracking rules
- Filter button: left-click opens Vendor-Only Filter, right-click opens Blacklist; tooltip shows both hints

### Fixed

- Items already looted this session now disappear from the live tracking list immediately when blacklisted (item or category), instead of only affecting future loot
- Loot Log window now closes on Escape like the other windows (was missing from the special-frames list)
- Color Theme dropdown list no longer stays open when Settings is closed via Escape
- Log, Filter, Blacklist, Session History and Session Detail windows now dock cleanly next to each other regardless of which is opened first, and drop to a row below instead of overlapping or running off-screen when there isn't enough horizontal room
- Clicking the same session entry again in Session History now closes its Detail window instead of doing nothing (previously only Escape or the X button closed it)
- Settings and Session History (with its Detail window) now close each other when either is opened, since both dock at the same anchor point and could otherwise overlap

### Changed

- Filter button tooltip title shortened from "Vendor-Only Filter" to "Filter" (left/right-click hints already explain what each does)
- Settings window now docks to the left of MainFrame (same side as Session History) instead of opening centered on screen, with the same non-overlapping chain behavior as the other docked windows
- Window docking unified into one system (`ns.WINDOW_CHAINS` + `ns.RefreshWindowChain`) instead of separate near-duplicate left/right implementations — Log/Filter/Blacklist and History/Settings both register into it the same way, making it straightforward to add another docked window later

## 1.1.5

### New

- 7 new color themes: Molten (lava orange), Emerald (emerald green), Arcane (magenta), Bronze, Plague (sickly green), Nether (deep teal), Argent (holy gold) — 13 themes total

- Session history mode setting: "Full" (default) keeps every session forever; "Compact" folds all sessions of past calendar months into one entry per month, keeping saved-variables size bounded no matter how long history is kept
- Switching to "Compact" merges past months immediately (with a confirmation popup, since it's irreversible); switching back to "Full" only stops future merging, already-merged months stay merged
- Compacted month entries are now dated to the last calendar day of that month instead of the date of the last actual session within it
- History window footer shortened to "N sessions" (day count removed)
- Session detail window shows the month name (e.g. "Juni 2026") instead of a date for compacted month entries; unaffected current-month sessions still show the exact date
- Hard cap of 50 saved sessions removed for both modes

### Changed

- Session merge logic (same-day auto-merge, manual day-merge, new month-compaction) now shares one internal helper instead of three duplicated implementations
- History window footer no longer shows a "(max N)" session count, since the cap was removed

### Fixed

- Warbound-until-equipped gear was priced using the AH price instead of vendor price — `GetItemInfo` reports the same bindType as regular Bind-on-Equip for these items, so it's no longer sufficient on its own; now double-checked via `C_Item.IsBoundToAccountUntilEquip`

## 1.1.4

### New

- Vendor-Only Filter: whole categories can be forced to vendor price, not just individual items
- Filter categories mirror the HUD, including subtype split when enabled
- Junk is now a toggle (default on) instead of hardcoded
- Filter category section is collapsible

### Changed

- Filter category header styled to match HUD/History headers
- German: "Item(s)" replaced with "Gegenstand(e)"
- Removed dead filter-mode code
- Help tooltip built once instead of on every hover
- Settings widgets pooled/reused instead of recreated

## 1.1.3

- Interface version bumped to 120100 (WoW 12.1)

## 1.1.2

### New

- Session History grouped by month, collapsible, bulk delete per month
- History/Log share one button (left/right click)
- Color Theme setting (6 themes, requires reload)

### Fixed

- German localization gaps
- Color Theme not applied after reload
- Settings scroll reset on every change

## 1.1.1

- "Merge" button for multi-session days
- Quest items no longer tracked
- Cleanup: duplicated logic consolidated into shared helpers

## 1.1.0

- New Loot Log window (per-character, persists across reload)
- Reagent rank indicator moved to icon badge
- Fixed: main frame anchor drift on collapse/expand and after entering world

## 1.0.9

- Pets/Mounts get own categories
- Shift+Click Reset skips saving to history
- Gold display: Classic vs Modern toggle
- Fixed: off-by-one bug in item info lookup

## 1.0.8

- New Vendor-Only Filter window
- Various fixes: filter button position, session history AH exclusion, junk cache-miss tracking, TSM field bug, redundant gold calc

## 1.0.7

- Fixed: junk items no longer use AH price

## 1.0.6

- Fixed: category totals undercounting mixed AH/vendor items

## 1.0.5

- Minimap button migrated to LibDBIcon-1.0

## 1.0.4

- Session merging automatic via Settings only
- Icon buttons standardized, new PNG artwork

## 1.0.3

- Option to disable automatic same-day merging
- Per-category price mode removed (global Settings control)

## 1.0.2

- Close button on main frame
- Timer turns green while tracking
- Option to split trade goods/reagents by subtype
- Various fixes: copper tracking, day-merge data loss, tooltip Unicode

## 1.0.1

- Session history can be disabled, Settings frame scrolls
- Gold overview panel, pet loot, encounter loot tracked
- Various tracking/pricing fixes (see git history for details)

## 1.0.0

Initial release: loot tracking, vendor/AH pricing, reagent quality tiers, session timer, session history, minimap button, EN/DE localization.