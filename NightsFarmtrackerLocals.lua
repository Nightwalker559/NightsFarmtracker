------------------------------------------------------------------------
-- Night's Farmtracker - Localization
-- Default: English. Override per locale below.
------------------------------------------------------------------------
local _, ns = ...
local L = {}
ns.L = L

------------------------------------------------------------------------
-- English (default)
------------------------------------------------------------------------
-- Main frame
L["start_tracking"]    = "Start tracking"
L["pause_tracking"]    = "Pause tracking"
L["reset_session"]     = "Reset session"
L["reset_desc"]        = "Save to history, clear items & timer"
L["session_history"]   = "Session History"
L["settings"]          = "Settings"
L["collapse"]          = "Collapse"
L["expand"]            = "Expand"
L["close"]             = "Close"
L["gathering_start"]   = "Hit start and begin gathering"
L["gathering_active"]  = "Gathering... loot will appear here"
-- Help tooltip
L["help_categories"]   = "Categories:"
L["help_cat_click"]    = "  Click to expand/collapse"
L["help_cat_rclick"]   = "  Shift+Right-click to exclude"
L["help_items"]        = "Items:"
L["help_item_hover"]   = "  Hover for item tooltip"
L["help_item_rclick"]  = "  Shift+Right-click to stop tracking"
-- History
L["delete_session"]    = "Delete this session"
L["delete_all"]        = "Delete all saved sessions"
L["clear_all"]         = "Clear All"
L["no_sessions"]       = "No sessions saved yet  —  sessions are saved on reset"
L["merge_sessions"]    = "Merge %d sessions"
L["merge_desc"]        = "Combines all items and durations from this day."
L["item_singular"]     = "%d item"
L["item_plural"]       = "%d items"
L["sessions_summary"]  = "%d session across %d day (max %d)"
L["sessions_summary_pl"] = "%d sessions across %d days (max %d)"
L["looted_gold"]       = "Direct"
-- Settings
L["settings_title"]    = "Night's Farmtracker — Settings"
L["ah_source"]         = "AH Price Source"
L["ah_auto"]           = "Auto (best available)"
L["ah_auctionator"]    = "Auctionator"
L["ah_tsm"]            = "TradeSkillMaster (TSM)"
L["ah_none"]           = "None (vendor only)"
L["not_installed"]     = "(not installed)"
L["tsm_source"]        = "TSM Price Source"
L["tsm_hint"]          = "Click to cycle: DBMarket · DBRegionMarketAvg · DBMinBuyout"
L["display"]           = "Display"
L["gold_per_hour"]     = "Gold / hour"
L["gold_per_min"]      = "Gold / min"
L["minimap_button"]    = "Show minimap button"
-- Categories
L["cat_junk"]       = "Junk"
L["cat_gear"]       = "Equipment"
-- Category price cycle
L["price_ah_vendor"]   = "AH + Vendor"
L["price_ah_only"]     = "AH only"
L["price_vendor_only"] = "Vendor only"

-- Category row tooltips
L["cat_tip_click"]         = "Click to expand/collapse"
L["cat_tip_shift_click"]   = "Shift+Click to cycle price (%s)"
L["cat_tip_shift_rclick"]  = "Shift+Right-click to exclude"
L["item_tip_shift_rclick"] = "Shift+Right-click to stop tracking"
-- Minimap
L["mm_toggle"]   = "Click to toggle window"
L["mm_settings"] = "Right-click for settings"
L["mm_drag"]     = "Drag to reposition"
-- Gold rate suffix
L["rate_hr"]  = "/hr"
L["rate_min"] = "/min"
-- Gold overview tooltip
L["gold_overview"] = "Gold Overview"
L["gold_items"]    = "Items"
L["gold_total"]    = "Total"
-- Settings
L["tracking"]                 = "Tracking"
L["session_history_enabled"]  = "Save session history"
L["ah_auto_info"]             = "Prefers Auctionator, falls back to TSM"
L["tsm_custom"]               = "Custom TSM expression (overrides above)"

------------------------------------------------------------------------
-- German (deDE)
------------------------------------------------------------------------
if GetLocale() == "deDE" then
    L["start_tracking"]    = "Tracking starten"
    L["pause_tracking"]    = "Tracking pausieren"
    L["reset_session"]     = "Session zurücksetzen"
    L["reset_desc"]        = "In Verlauf speichern, Items & Timer leeren"
    L["session_history"]   = "Session-Verlauf"
    L["settings"]          = "Einstellungen"
    L["collapse"]          = "Einklappen"
    L["expand"]            = "Ausklappen"
    L["close"]             = "Schließen"
    L["gathering_start"]   = "Start drücken und farmen"
    L["gathering_active"]  = "Sammle... Beute erscheint hier"
    L["help_categories"]   = "Kategorien:"
    L["help_cat_click"]    = "  Klick → ein-/ausklappen"
    L["help_cat_rclick"]   = "  Shift+Rechtsklick → ausschließen"
    L["help_items"]        = "Items:"
    L["help_item_hover"]   = "  Hover → Item-Tooltip"
    L["help_item_rclick"]  = "  Shift+Rechtsklick → nicht tracken"
    L["delete_session"]    = "Session löschen"
    L["delete_all"]        = "Alle Sessions löschen"
    L["clear_all"]         = "Alles löschen"
    L["no_sessions"]       = "Keine Sessions gespeichert  —  Reset speichert eine Session"
    L["merge_sessions"]    = "%d Sessions zusammenführen"
    L["merge_desc"]        = "Kombiniert alle Items und Zeiten dieses Tages."
    L["item_singular"]     = "%d Item"
    L["item_plural"]       = "%d Items"
    L["sessions_summary"]    = "%d Session über %d Tag (max %d)"
    L["sessions_summary_pl"] = "%d Sessions über %d Tage (max %d)"
    L["looted_gold"]       = "Direkt"
    L["settings_title"]    = "Night's Farmtracker — Einstellungen"
    L["ah_source"]         = "AH-Preisquelle"
    L["ah_auto"]           = "Automatisch (beste verfügbare)"
    L["ah_auctionator"]    = "Auctionator"
    L["ah_tsm"]            = "TradeSkillMaster (TSM)"
    L["ah_none"]           = "Keine (nur Händlerpreis)"
    L["not_installed"]     = "(nicht installiert)"
    L["tsm_source"]        = "TSM-Preisquelle"
    L["tsm_hint"]          = "Klicken zum Wechseln: DBMarket · DBRegionMarketAvg · DBMinBuyout"
    L["display"]           = "Anzeige"
    L["gold_per_hour"]     = "Gold / Stunde"
    L["gold_per_min"]      = "Gold / Minute"
    L["minimap_button"]    = "Minimap-Button anzeigen"
    L["cat_junk"]          = "Müll"
    L["cat_gear"]          = "Ausrüstung"
    L["price_ah_vendor"]   = "AH + Händler"
    L["price_ah_only"]     = "Nur AH"
    L["price_vendor_only"] = "Nur Händler"
    -- Tooltips
    L["cat_tip_click"]         = "Klick zum Ein-/Ausklappen"
    L["cat_tip_shift_click"]   = "Shift+Klick: Preis wechseln (%s)"
    L["cat_tip_shift_rclick"]  = "Shift+Rechtsklick: Ausschließen"
    L["item_tip_shift_rclick"] = "Shift+Rechtsklick: Nicht mehr tracken"
    -- Minimap
    L["mm_toggle"]   = "Klick zum Ein-/Ausblenden"
    L["mm_settings"] = "Rechtsklick für Einstellungen"
    L["mm_drag"]     = "Ziehen zum Verschieben"
    -- Gold rate suffix
    L["rate_hr"]  = "/Std"
    L["rate_min"] = "/Min"
    -- Gold overview tooltip
    L["gold_overview"] = "Gold-Übersicht"
    L["gold_items"]    = "Items"
    L["gold_total"]    = "Gesamt"
    -- Settings
    L["tracking"]                = "Tracking"
    L["session_history_enabled"] = "Session-Verlauf speichern"
    L["ah_auto_info"]            = "Bevorzugt Auctionator, fällt auf TSM zurück"
    L["tsm_custom"]              = "Eigener TSM-Ausdruck (überschreibt oben)"
end
