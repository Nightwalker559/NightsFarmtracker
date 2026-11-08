------------------------------------------------------------------------
-- Night's Farmtracker - Settings: sections
-- The sections made of checkboxes, radio groups and number boxes (display,
-- session limit, windows, history, categories, filters, fishing, HUD, export).
------------------------------------------------------------------------
local _, ns = ...
local K = ns.SettingsKit

local CHECK_RUN_TAIL, TITLE_STEP, TITLE_STEP_CTRL, CTRL_SIZE = K.CHECK_RUN_TAIL, K.TITLE_STEP, K.TITLE_STEP_CTRL, K.CTRL_SIZE
local S_PAD, MakeNumberBox = K.S_PAD, K.MakeNumberBox

local sessionLengthEB, itemGoalEB, maxHeightEB
local goalsBtn, goalsCheck, exportBtn, sellConfigBtn, limitHelpBtn

ns.RegisterConfirmDialog("NFT_CONFIRM_HISTORY_COMPACT", ns.L["compact_history_confirm"], function()
    NightsFarmtrackerDB.sessionHistoryMode = "compact"
    ns.CompactOldMonths()
    ns.RebuildHistory()
    ns.RebuildSettingsContent()
end)

-- Fixed session length in minutes. Applied when the field loses focus / Enter
-- is pressed, not per keystroke - typing "6" on the way to "60" would otherwise
-- end a session that ran longer than 6 minutes on the first digit.
local function MakeSessionLengthEB(parent, yOff)
    local frame, eb = MakeNumberBox(parent, yOff, 4, ns.L["minutes_suffix"])
    eb:HookScript("OnEditFocusLost", function(self)
        NightsFarmtrackerDB.sessionLength = tonumber(self:GetText()) or 0
        ns.UpdateTimerDisplay()
        ns.ApplyPauseVisuals()
    end)
    return frame
end

-- General item goal (pieces for every item without an own goal in the Item
-- Goals window, 0 = none). Applied when the field loses focus / Enter is
-- pressed, not per keystroke - typing "5" on the way to "500" would otherwise
-- reach the goal and pause the session on the first digit.
local function MakeItemGoalEB(parent, yOff)
    local frame, eb = MakeNumberBox(parent, yOff, 6, ns.L["pieces_suffix"])
    eb:HookScript("OnEditFocusLost", function(self)
        local v = tonumber(self:GetText()) or 0
        self:SetText(v > 0 and tostring(v) or "")
        NightsFarmtrackerDB.itemGoal = v
        ns.RefreshHUD()
    end)
    return frame
end

-- Maximum window height (px). Applied when the field loses focus / Enter is
-- pressed, not per keystroke - typing "5" on the way to "500" must not resize
-- every open window to the minimum. Empty or 0 falls back to the default;
-- values are clamped to the allowed range.
local function MakeMaxHeightEB(parent, yOff)
    local frame, eb = MakeNumberBox(parent, yOff, 4, ns.L["px_suffix"])
    eb:HookScript("OnEditFocusLost", function(self)
        local v = tonumber(self:GetText())
        if not v or v <= 0 then v = ns.DEFAULT_MAX_WINDOW_H end
        v = math.max(ns.MIN_MAX_WINDOW_H, math.min(ns.MAX_MAX_WINDOW_H, v))
        self:SetText(tostring(v))
        if NightsFarmtrackerDB.maxWindowHeight ~= v then
            NightsFarmtrackerDB.maxWindowHeight = v
            ns.ApplyWindowHeightSetting()
        end
    end)
    return frame
end

------------------------------------------------------------------------
-- Helper: button that opens a window ("Open Export Window", "Edit Item Goals") -
-- single persistent instance, reused across rebuilds like the number boxes.
-- btn:SetActive(false) greys it out and makes it inert.
------------------------------------------------------------------------
local function MakeWindowButton(labelKey, onClick)
    return function(parent)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        ns.StyleBackdropBox(btn)
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetTextColor(unpack(ns.COL_ACCENT))
        text:SetText(ns.L[labelKey])
        btn:SetSize(text:GetStringWidth() + 20, 20)
        btn:SetScript("OnEnter", function(self) if self:IsEnabled() then text:SetTextColor(1,1,1) end end)
        btn:SetScript("OnLeave", function(self) if self:IsEnabled() then text:SetTextColor(unpack(ns.COL_ACCENT)) end end)
        btn:SetScript("OnClick", onClick)
        function btn:SetActive(on)
            self:SetEnabled(on)
            if on then text:SetTextColor(unpack(ns.COL_ACCENT)) else text:SetTextColor(0.4, 0.4, 0.4) end
        end
        return btn
    end
end
local MakeExportButton = MakeWindowButton("export_open_btn", function() ns.ToggleExportWindow() end)
local MakeGoalsButton  = MakeWindowButton("goals_open_btn",  function() ns.ToggleGoalsWindow() end)

local function MakeLimitHelpButton(parent) return ns.CreateHelpButton(parent, "limit") end

-- Label-less checkbox for db.itemGoalsEnabled; it also greys out the Item
-- Goals button next to it. Single persistent instance like the button.
local function MakeGoalsCheck(parent)
    local box, check = ns.CreateMarkBox(parent, CTRL_SIZE)

    function box:Sync()
        local on = NightsFarmtrackerDB.itemGoalsEnabled ~= false
        check:SetShown(on)
        if goalsBtn then goalsBtn:SetActive(on) end
    end
    box:EnableMouse(true)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L["goals_use_own"])
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    box:SetScript("OnMouseUp", function(self)
        NightsFarmtrackerDB.itemGoalsEnabled = NightsFarmtrackerDB.itemGoalsEnabled == false
        self:Sync()
        if ns.RebuildGoalsList then ns.RebuildGoalsList() end
        ns.RefreshHUD()
    end)
    return box
end

------------------------------------------------------------------------
-- Section: Display (what the main window shows and how)
------------------------------------------------------------------------
K.AddSection("display", function(y, ui)
    local sectionTitle, flag, radioGroup, db = ui.sectionTitle, ui.flag, ui.radioGroup, ui.db
    y = sectionTitle(y, "display", TITLE_STEP_CTRL)

    y = radioGroup(y, { {"gold_per_hour", "hour"}, {"gold_per_min", "min"} },
        db.goldRateMode == "min" and "min" or "hour",
        function(v) db.goldRateMode = v; ns.UpdateGoldRate() end, 32)

    y = radioGroup(y, { {"gold_display_classic", "classic"}, {"gold_display_modern", "modern"} },
        db.goldDisplayMode == "modern" and "modern" or "classic",
        function(v) db.goldDisplayMode = v; ns.RefreshHUD() end)

    y = flag(y, "show_price_source", "showPriceSource", false, function() ns.RefreshHUD() end)
    y = flag(y, "show_value_bar", "showValueBar", true, function() ns.RefreshHUD() end)

    return y
end)

------------------------------------------------------------------------
-- Section: Session limit (session length or item goals)
------------------------------------------------------------------------
K.AddSection("sec_session_limit", function(y, ui)
    local track, sectionTitle, wrappedHint, checkbox, place, db = ui.track, ui.sectionTitle, ui.wrappedHint, ui.checkbox, ui.place, ui.db
    local title
    y, title = sectionTitle(y, "sec_session_limit", TITLE_STEP_CTRL)

    -- "?" behind the title: what session length and item goals do
    limitHelpBtn = place(limitHelpBtn, MakeLimitHelpButton, y)
    limitHelpBtn:ClearAllPoints()
    limitHelpBtn:SetPoint("LEFT", title, "RIGHT", 6, 0)
    track(limitHelpBtn, "other")

    -- Session length and item goal exclude each other (db.limitMode);
    -- the checkbox picks the active one, the other keeps its value.
    -- Rebuilt next frame: the click handler still refreshes its own
    -- (pooled) row after the setter returns.
    local function limitCheckbox(y, labelKey, mode)
        return checkbox(y, labelKey,
            function() return db.limitMode == mode end,
            function(v)
                db.limitMode = v and mode or "off"
                ns.UpdateTimerDisplay()
                ns.ApplyPauseVisuals()
                ns.RefreshHUD()
                if ns.RebuildGoalsList then ns.RebuildGoalsList() end
                RunNextFrame(ns.RebuildSettingsContent)
            end)
    end

    -- Fixed session length: the timer counts down and the session pauses at 0.
    y = limitCheckbox(y, "session_length_hint", "session")

    sessionLengthEB = place(sessionLengthEB, MakeSessionLengthEB, y)
    local lenMin = tonumber(db.sessionLength) or 0
    sessionLengthEB.eb:SetText(lenMin > 0 and tostring(lenMin) or "")
    track(sessionLengthEB, "other")
    y = y - 40

    -- Item goals: per-item progress bar, green and timer stop at the goal.
    y = limitCheckbox(y, "item_goal_hint", "goal")

    -- General goal for every item without an own one (see GetItemGoal)
    local goalHint = wrappedHint(y, ns.L["item_goal_general_hint"])
    y = y - math.ceil(goalHint:GetStringHeight()) - 6

    itemGoalEB = place(itemGoalEB, MakeItemGoalEB, y)
    local goal = tonumber(db.itemGoal) or 0
    itemGoalEB.eb:SetText(goal > 0 and tostring(goal) or "")
    track(itemGoalEB, "other")

    -- Right of the amount box: checkbox for the own goals (the list stays
    -- when off), then the Item Goals window button, greyed out while off
    goalsCheck = place(goalsCheck, MakeGoalsCheck, y)
    goalsCheck:ClearAllPoints()
    goalsCheck:SetPoint("LEFT", itemGoalEB.unitLbl, "RIGHT", 14, 0)
    track(goalsCheck, "other")

    goalsBtn = place(goalsBtn, MakeGoalsButton, y)
    goalsBtn:ClearAllPoints()
    goalsBtn:SetPoint("LEFT", goalsCheck, "RIGHT", 8, 0)
    track(goalsBtn, "other")
    goalsCheck:Sync()
    y = y - 40

    return y
end)

------------------------------------------------------------------------
-- Section: Windows and buttons (height, lock, optional windows, launchers)
------------------------------------------------------------------------
K.AddSection("sec_windows", function(y, ui)
    local track, sectionTitle, wrappedHint, hintLabel, checkbox, flag, place, db = ui.track, ui.sectionTitle, ui.wrappedHint, ui.hintLabel, ui.checkbox, ui.flag, ui.place, ui.db
    y = sectionTitle(y, "sec_windows", TITLE_STEP)

    -- Max window height: windows grow up to this, then their lists scroll.
    local heightHint = wrappedHint(y, string.format(ns.L["max_window_height_hint"],
        ns.DEFAULT_MAX_WINDOW_H, ns.MIN_MAX_WINDOW_H, ns.MAX_MAX_WINDOW_H))
    y = y - math.ceil(heightHint:GetStringHeight()) - 6

    maxHeightEB = place(maxHeightEB, MakeMaxHeightEB, y)
    maxHeightEB.eb:SetText(tostring(ns.GetMaxWindowH()))
    track(maxHeightEB, "other")
    y = y - 40

    y = flag(y, "lock_main_frame", "mainLocked", false)
    y = checkbox(y, "minimap_button",
        function() return not db.minimap.hide end,
        function(v) ns.SetMinimapVisible(v) end)
    y = checkbox(y, "compartment_button",
        function() return ns.IsInCompartment() end,
        function(v) ns.SetInCompartment(v) end)
    y = flag(y, "log_window_enabled", "logWindowEnabled", false, function(v)
        if not v then ns.OnLogWindowDisabled() end
        ns.RefreshLeftButtons()
    end)
    y = checkbox(y, "lockout_enabled",
        function() return db.instanceLockoutEnabled == true end,
        function(v) ns.SetInstanceLockoutEnabled(v) end)

    -- Sell list at vendors; its options sit behind the gear icon (own window)
    y = y - CHECK_RUN_TAIL
    hintLabel(S_PAD, y, ns.L["vendor_sell_group"], 0.6)
    y = y - 18
    local rowY, row = y
    y, row = flag(y, "vendor_sell_enabled", "vendorSellEnabled", true, function(v)
        if not v then ns.OnVendorSellDisabled() end
        RunNextFrame(ns.RebuildSettingsContent)   -- the pooled row still refreshes itself after this returns
    end)
    sellConfigBtn = place(sellConfigBtn, K.MakeSellConfigButton, rowY)
    sellConfigBtn:ClearAllPoints()
    sellConfigBtn:SetPoint("LEFT", row.label, "LEFT", row.label:GetStringWidth() + 8, 0)
    sellConfigBtn:SetFrameLevel(row:GetFrameLevel() + 5)   -- pooled rows keep their level, the checkbox row must not catch the click
    track(sellConfigBtn, "other")

    return y - CHECK_RUN_TAIL   -- the gear icon is the last tracked widget, so the section loop adds no tail
end)

------------------------------------------------------------------------
-- Section: Session History
------------------------------------------------------------------------
K.AddSection("session_history", function(y, ui)
    local sectionTitle, hintLabel, flag, radioGroup, db = ui.sectionTitle, ui.hintLabel, ui.flag, ui.radioGroup, ui.db
    y = sectionTitle(y, "session_history", TITLE_STEP_CTRL)

    y = flag(y, "session_history_enabled", "sessionHistoryEnabled", true, function() ns.RefreshLeftButtons() end)
    y = y - CHECK_RUN_TAIL

    hintLabel(S_PAD, y, ns.L["session_history_mode"], 0.6)
    y = y - 18

    local function getHistMode() return db.sessionHistoryMode == "compact" and "compact" or "full" end
    local rows
    y, rows = radioGroup(y,
        { {"session_history_mode_full", "full"}, {"session_history_mode_compact", "compact"} },
        getHistMode(), function(v) db.sessionHistoryMode = v; ns.RebuildHistory() end)
    -- "compact" folds past months irreversibly: ask first instead of
    -- switching on click.
    rows[2]:SetScript("OnMouseUp", function()
        if getHistMode() ~= "compact" then
            StaticPopup_Show("NFT_CONFIRM_HISTORY_COMPACT")
        end
    end)

    y = flag(y, "merge_daily_sessions", "mergeDaily", true)
    y = flag(y, "session_history_avg", "sessionHistoryAvg", false, function() ns.RebuildHistory() end)

    return y
end)

------------------------------------------------------------------------
-- Section: Categories & Grouping
------------------------------------------------------------------------
K.AddSection("sec_categories", function(y, ui)
    local sectionTitle, flag = ui.sectionTitle, ui.flag
    y = sectionTitle(y, "sec_categories", TITLE_STEP_CTRL)

    y = flag(y, "split_trade_goods", "splitTradeGoods", false, function() ns.RefreshHUD() end)
    y = flag(y, "split_gear_by_binding", "splitGearByBinding", false, function() ns.RefreshHUD() end)
    y = flag(y, "merge_junk_entries", "mergeJunkEntries", false, function() StaticPopup_Show("NFT_RELOAD") end)

    return y
end)

------------------------------------------------------------------------
-- Section: Filters
------------------------------------------------------------------------
K.AddSection("sec_filters", function(y, ui)
    local sectionTitle, flag = ui.sectionTitle, ui.flag
    y = sectionTitle(y, "sec_filters", TITLE_STEP_CTRL)

    local function filterChanged() ns.RefreshLeftButtons(); ns.RefreshHUD(); ns.RefreshVendorSell() end
    y = flag(y, "vendor_filter_enabled", "vendorFilterEnabled", true, filterChanged)
    y = flag(y, "blacklist_enabled", "blacklistEnabled", true, filterChanged)
    y = flag(y, "delete_list_enabled", "deleteListEnabled", true, filterChanged, { tip = "delete_list_tip" })

    return y
end)

------------------------------------------------------------------------
-- Section: Fishing
------------------------------------------------------------------------
K.AddSection("sec_fishing", function(y, ui)
    local sectionTitle, checkbox, db = ui.sectionTitle, ui.checkbox, ui.db
    y = sectionTitle(y, "sec_fishing", TITLE_STEP_CTRL)

    if not ns.IS_FOREVER then   -- the Coiled Huntress rod does not exist in Forever
        y = checkbox(y, "venom_tracker_enabled",
            function() return db.venomTrackerEnabled == true end,
            function(v) ns.SetVenomTrackerEnabled(v) end)
    end
    y = checkbox(y, "bait_frame_enabled",
        function() return db.baitFrameEnabled == true end,
        function(v) ns.SetBaitFrameEnabled(v) end)

    return y
end)

------------------------------------------------------------------------
-- Section: Minimap HUD
------------------------------------------------------------------------
K.AddSection("sec_hud", function(y, ui)
    local sectionTitle, wrappedHint, checkbox, db = ui.sectionTitle, ui.wrappedHint, ui.checkbox, ui.db
    y = sectionTitle(y, "sec_hud", TITLE_STEP_CTRL)

    y = checkbox(y, "hud_enabled",
        function() return db.hudEnabled == true end,
        function(v) ns.SetHudEnabled(v) end)

    local hudHint = wrappedHint(y, ns.L["hud_keybind_hint"])
    y = y - math.ceil(hudHint:GetStringHeight()) - 10

    return y
end)

------------------------------------------------------------------------
-- Section: Data Export
------------------------------------------------------------------------
K.AddSection("sec_export", function(y, ui)
    local track, sectionTitle, wrappedHint, place = ui.track, ui.sectionTitle, ui.wrappedHint, ui.place
    y = sectionTitle(y, "sec_export", TITLE_STEP)

    local exportHint = wrappedHint(y, ns.L["export_hint"])
    -- Button sits 2 px below the (wrapped) hint, however many lines it takes.
    y = y - math.ceil(exportHint:GetStringHeight()) - 2

    exportBtn = place(exportBtn, MakeExportButton, y)
    track(exportBtn, "other")
    y = y - 30

    return y
end)
