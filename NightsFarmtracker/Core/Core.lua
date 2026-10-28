------------------------------------------------------------------------
-- Night's Farmtracker - Core
------------------------------------------------------------------------
local ADDON_NAME, ns = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
ns.ADDON_NAME     = ADDON_NAME
ns.ART            = "Interface\\AddOns\\NightsFarmtracker\\Media\\"

------------------------------------------------------------------------
-- Combat-safe deferral for popup windows. Frame:Show/Hide/SetPoint calls
-- can throw ADDON_ACTION_BLOCKED in combat lockdown (BaitFrame's
-- SecureActionButtonTemplate lure button taints the shared execution
-- path). ns.DeferInCombat(fn) queues fn to run right after combat ends
-- instead of letting the call fail; returns true if it was queued.
------------------------------------------------------------------------
local pendingCombatCalls = {}
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
    local queued = pendingCombatCalls
    pendingCombatCalls = {}
    for _, fn in ipairs(queued) do fn() end
end)

function ns.DeferInCombat(fn)
    if InCombatLockdown() then
        pendingCombatCalls[#pendingCombatCalls + 1] = fn
        return true
    end
    return false
end

ns.TRADE_GOODS    = Enum.ItemClass.Tradegoods
ns.QUEST_CLASS    = Enum.ItemClass.Questitem
ns.BIND_ON_EQUIP  = 2
ns.BIND_ON_PICKUP = 1
ns.BIND_ON_USE    = 3
ns.FALLBACK_ICON  = 134400
-- Housing classID: Enum.ItemClass.Housing if defined (12.0.0+), else runtime-detected
ns.HOUSING = Enum.ItemClass and Enum.ItemClass.Housing or nil

-- Weapon (2) and Armor (4) are the item classes that count as Equipment.
function ns.IsGearClass(classID)
    return classID == 2 or classID == 4
end

-- Item class priority for display order (by WoW classID)
ns.CLASS_PRIORITY = {
    [7]  = 1,   -- Tradeskill / Tradegoods
    [5]  = 2,   -- Reagent
    [2]  = 3,   -- Weapon
    [4]  = 4,   -- Armor
    [3]  = 5,   -- Gem
    [0]  = 6,   -- Consumable
    [9]  = 7,   -- Recipe
    [8]  = 8,   -- Item Enhancement
    [1]  = 9,   -- Container
    [12] = 10,  -- Quest
    [14] = 11,  -- Miscellaneous
}
-- Housing classID is not hardcoded above (varies by patch); ns.InitDB()
-- registers it at runtime via ns.HOUSING so it always gets the correct
-- priority instead of silently falling through to the default (50).

-- UI layout
ns.FRAME_W     = 330
ns.STACK_GAP   = 4    -- space between the windows stacked below the collapsed main window (the Loot Log)
ns.PAD         = 4    -- side gap between a window's border and its content
ns.ROW_H       = 34   -- 30 px icon + 1 px border each side: 2 px between the borders of adjacent rows
ns.CAT_GAP     = 5    -- extra space above/below a category's rows: 6 px between header and icon border
ns.CAT_ROW_H   = 22
ns.CTRL_GAP    = 6    -- gap between neighbouring checkboxes / radio buttons (Settings and the list windows)
ns.CHECKBOX_ROW_H = 12 + ns.CTRL_GAP  -- row height for checkbox-list sections (12 px box + gap): category filters, AH-by-expansion
ns.ICON_X      = 1    -- row icon offset: its 1 px border then sits flush with the row/header edge
ns.FOOTER_H    = 32
ns.ICON_SIZE   = 30
ns.RANK_ICON_W = 20   -- width of the R1/R2/R3 atlas markup (CreateAtlasMarkup)
ns.RANK_ICON_H = 20   -- height of the R1/R2/R3 atlas markup
ns.CONTENT_W   = ns.FRAME_W - ns.PAD * 2
ns.SCROLL_STEP = ns.ROW_H
-- Maximum total window height (header + list + footer) of the main window and
-- every list window; longer content scrolls. User setting db.maxWindowHeight
-- (Settings -> Windows & Buttons), read through ns.GetMaxWindowH(). The Help window is
-- a bit taller (see ns.GetMaxHelpH).
ns.DEFAULT_MAX_WINDOW_H = 360
ns.MIN_MAX_WINDOW_H     = 200
ns.MAX_MAX_WINDOW_H     = 1000
ns.HELP_EXTRA_H         = 40

function ns.GetMaxWindowH()
    local v = tonumber(NightsFarmtrackerDB and NightsFarmtrackerDB.maxWindowHeight)
    if not v or v <= 0 then return ns.DEFAULT_MAX_WINDOW_H end
    return math.max(ns.MIN_MAX_WINDOW_H, math.min(ns.MAX_MAX_WINDOW_H, v))
end

function ns.GetMaxHelpH()
    return ns.GetMaxWindowH() + ns.HELP_EXTRA_H
end

-- Re-lays out every window that is currently open after the setting
-- changed. (The Detail window picks the new height up the next time it opens.)
function ns.ApplyWindowHeightSetting()
    if ns.RefreshHUD then ns.RefreshHUD() end
    if ns.HistFrame and ns.HistFrame:IsShown() and ns.RebuildHistory then ns.RebuildHistory() end
    if ns.FilterFrame and ns.FilterFrame:IsShown() and ns.RebuildFilterList then ns.RebuildFilterList() end
    if ns.BlacklistFrame and ns.BlacklistFrame:IsShown() and ns.RebuildBlacklistList then ns.RebuildBlacklistList() end
    if ns.GoalsFrame and ns.GoalsFrame:IsShown() and ns.RebuildGoalsList then ns.RebuildGoalsList() end
    if ns.LogFrame and ns.LogFrame:IsShown() and ns.RebuildLogList then ns.RebuildLogList() end
    if ns.RefitHelpWindow then ns.RefitHelpWindow() end
    if ns.SettingsFrame and ns.SettingsFrame:IsShown() and ns.RebuildSettingsContent then ns.RebuildSettingsContent() end
end

-- Font sizes (odd values render blurry at some UI scales, so we stick to
-- even numbers). Used via SetFontHeight() everywhere instead of scattered
-- literals, so the whole addon can be resized from one place.
ns.FONT_SMALL  = 10  -- secondary/info text (day-row info, merge button)
ns.FONT_NORMAL = 12  -- default row/item text
ns.FONT_HEADER = 14  -- emphasized headers/titles

-- Header height for title-only secondary windows (History, Detail, Filter,
-- Blacklist, Log, Settings). MainFrame keeps its own taller header (it has
-- to fit the icon toolbar) and isn't affected by this constant.
ns.WINDOW_HDR_H = 34
