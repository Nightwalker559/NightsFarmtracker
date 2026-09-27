------------------------------------------------------------------------
-- Night's Farmtracker - Settings
-- Custom settings window (no WoW Settings API dependency).
-- Price source: Auctionator / TSM4 / None + TSM price source selector.
------------------------------------------------------------------------
local _, ns = ...


StaticPopupDialogs["NFT_RELOAD"] = {
    text        = ns.L and ns.L["reload_required"] or "Reload required.",
    button1     = OKAY,
    button2     = CANCEL,
    OnAccept    = function() ReloadUI() end,
    timeout     = 0,
    whileDead   = true,
    hideOnEscape = true,
}
StaticPopupDialogs["NFT_CONFIRM_HISTORY_COMPACT"] = {
    text        = ns.L and ns.L["compact_history_confirm"] or "Merge all past months into one entry each? This cannot be undone.",
    button1     = OKAY,
    button2     = CANCEL,
    OnAccept    = function()
        NightsFarmtrackerDB.sessionHistoryMode = "compact"
        ns.CompactOldMonths()
        ns.RebuildHistory()
        ns.RebuildSettingsContent()
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}
-- Wipes both SavedVariables tables and reloads - InitDB()/InitAccountDB()
-- (called again on the reload) then rebuild everything from scratch, same
-- as a fresh install. Deletes settings, session history, Vendor-Only
-- filter, Blacklist, AH-by-expansion selection - everything.
function ns.ResetAddonToDefault()
    NightsFarmtrackerDB = nil
    NightsFarmtrackerAccountDB = nil
    ReloadUI()
end

StaticPopupDialogs["NFT_CONFIRM_RESET_ADDON"] = {
    text        = ns.L and ns.L["reset_addon_confirm"] or "Reset the entire addon to default? This deletes ALL saved data (settings, session history, Vendor-Only filter, Blacklist) and cannot be undone. The UI will reload.",
    button1     = OKAY,
    button2     = CANCEL,
    OnAccept    = function() ns.ResetAddonToDefault() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
local SF           -- settings frame (lazy built)
local SScrollFrame -- scroll container for content
local SListFrame   -- scroll child (all widgets live here)
local SSidebar     -- category nav sidebar (doesn't scroll)

local S_W          = 320
local S_PAD        = 14
local S_HDR_H      = ns.WINDOW_HDR_H
local S_MAX_VIS    = 380   -- max visible scroll area height
local S_SCROLL_STEP = 22
local S_FTR_H       = 26   -- footer strip height (Reset to Default button)

------------------------------------------------------------------------
-- Radio button row — pooled (built once, reconfigured on reuse) so
-- RebuildSettingsContent doesn't leak new Frame/FontString objects on
-- every settings interaction. Mirrors the AcquireRow/ReleaseRow pattern
-- used throughout the rest of the addon (UI.lua, History.lua, etc.).
------------------------------------------------------------------------
local radioPool = {}

local function AcquireRadio(parent)
    local row = table.remove(radioPool)
    if row then
        row:SetParent(parent)
        row:Show()
        return row
    end

    row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2, 22)

    local dot = CreateFrame("Frame", nil, row, "BackdropTemplate")
    dot:SetSize(14, 14)
    dot:SetPoint("LEFT", 0, 0)
    ns.StyleBackdropBox(dot)

    local fill = dot:CreateTexture(nil,"ARTWORK")
    fill:SetSize(7,7); fill:SetPoint("CENTER")
    fill:SetColorTexture(unpack(ns.COL_ACCENT)); fill:Hide()
    dot.fill = fill

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    lbl:SetTextColor(0.85,0.85,0.85)
    row.label = lbl

    local grayLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    grayLbl:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
    grayLbl:SetTextColor(0.4,0.4,0.4)
    grayLbl:SetText(ns.L["not_installed"])
    grayLbl:Hide()
    row.notInstalled = grayLbl

    row.dot = dot

    function row:SetSelected(sel)
        if sel then
            fill:Show()
            lbl:SetTextColor(1, 0.82, 0)
        else
            fill:Hide()
            lbl:SetTextColor(0.85,0.85,0.85)
        end
    end

    function row:SetEnabled(en)
        row:EnableMouse(en)
        if not en then
            lbl:SetTextColor(0.4,0.4,0.4)
            dot:SetBackdropBorderColor(0.2,0.2,0.2,0.5)
            grayLbl:Show()
        else
            dot:SetBackdropBorderColor(unpack(ns.COL_BORDER))
            grayLbl:Hide()
        end
    end

    return row
end

-- (Re-)configures a pooled radio row for its current position/label/value/
-- callback. Called every time regardless of whether the row is freshly
-- built or reused from the pool.
local function ConfigureRadio(row, label, yOff, value, getGroup, setGroup)
    row:SetPoint("TOPLEFT", S_PAD, yOff)
    row.label:SetText(label)
    row.value = value
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function()
        setGroup(value)
        ns.RebuildSettingsContent()
    end)
    return row
end

StaticPopupDialogs["NFT_PROFILE_NEW"] = {
    text         = ns.L and ns.L["profile_new_prompt"] or "New profile name:",
    button1      = OKAY,
    button2      = CANCEL,
    hasEditBox   = true,
    OnShow       = function(dialog)
        local eb = dialog:GetEditBox()
        eb:SetText(""); eb:SetFocus()
    end,
    OnAccept     = function(dialog)
        local name = dialog:GetEditBox():GetText()
        if name and name ~= "" and ns.CreateProfile(name) then
            ns.SetActiveProfile(name)
            ns.RebuildSettingsContent()
            StaticPopup_Show("NFT_RELOAD")
        end
    end,
    EditBoxOnEnterPressed  = function(editBox) editBox:GetParent():GetButton1():Click() end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}
StaticPopupDialogs["NFT_PROFILE_COPY"] = {
    text         = ns.L and ns.L["profile_copy_prompt"] or "Name for the copy:",
    button1      = OKAY,
    button2      = CANCEL,
    hasEditBox   = true,
    OnShow       = function(dialog)
        local eb = dialog:GetEditBox()
        eb:SetText(""); eb:SetFocus()
    end,
    OnAccept     = function(dialog)
        local name = dialog:GetEditBox():GetText()
        if name and name ~= "" and ns.CopyProfile(name, ns.GetActiveProfileName()) then
            ns.SetActiveProfile(name)
            ns.RebuildSettingsContent()
            StaticPopup_Show("NFT_RELOAD")
        end
    end,
    EditBoxOnEnterPressed  = function(editBox) editBox:GetParent():GetButton1():Click() end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}
StaticPopupDialogs["NFT_PROFILE_RENAME"] = {
    text         = ns.L and ns.L["profile_rename_prompt"] or "Rename profile to:",
    button1      = OKAY,
    button2      = CANCEL,
    hasEditBox   = true,
    OnShow       = function(dialog)
        local eb = dialog:GetEditBox()
        eb:SetText(ns.GetActiveProfileName())
        eb:HighlightText()
    end,
    OnAccept     = function(dialog)
        local name = dialog:GetEditBox():GetText()
        if name and name ~= "" and ns.RenameProfile(ns.GetActiveProfileName(), name) then
            ns.RebuildSettingsContent()
        end
    end,
    EditBoxOnEnterPressed  = function(editBox) editBox:GetParent():GetButton1():Click() end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}
StaticPopupDialogs["NFT_PROFILE_DELETE_CONFIRM"] = {
    text         = ns.L and ns.L["profile_delete_confirm"] or "Delete profile \"%s\"? This cannot be undone.",
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function(dialog, name)
        local wasActive = (name == ns.GetActiveProfileName())
        if ns.DeleteProfile(name) then
            if wasActive then ns.SetActiveProfile(ns.DEFAULT_PROFILE) end
            ns.RebuildSettingsContent()
            if wasActive then StaticPopup_Show("NFT_RELOAD") end
        end
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

local function ReleaseRadio(row)
    row:Hide(); row:ClearAllPoints()
    row:SetScript("OnMouseUp", nil)
    radioPool[#radioPool+1] = row
end

------------------------------------------------------------------------
-- Helper: dropdown for TSM price source
------------------------------------------------------------------------
local tsmDropdown
local tsmCustomEB
local themeDropdown
local gearThresholdEB
local sessionLengthEB
local profileDropdown
local profileButtons
local deleteProfileRow

local function MakeDropdown(parent, yOff)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(S_W - S_PAD*2 - 40, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    frame.lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.lbl:SetPoint("LEFT",6,0)
    frame.lbl:SetTextColor(0.85,0.85,0.85)

    local arrow = frame:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(10, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(unpack(ns.COL_ACCENT))

    local sources = ns.TSM_SOURCES
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        local cur = NightsFarmtrackerDB.tsmPriceSource or "DBMarket"
        local idx = 1
        for i,v in ipairs(sources) do if v==cur then idx=i; break end end
        idx = (idx % #sources) + 1
        NightsFarmtrackerDB.tsmPriceSource = sources[idx]
        frame.lbl:SetText(sources[idx])
        ns.ClearPriceCache()
    end)

    function frame:Refresh()
        local db     = NightsFarmtrackerDB
        local custom = db.tsmCustomSource and db.tsmCustomSource ~= ""
        self.lbl:SetText(db.tsmPriceSource or "DBMarket")
        self.lbl:SetTextColor(custom and 0.40 or 0.85, custom and 0.40 or 0.85, custom and 0.40 or 0.85)
    end

    return frame
end

------------------------------------------------------------------------
-- Helper: EditBox for custom TSM price source
------------------------------------------------------------------------
local function MakeCustomSourceEB(parent, yOff)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(S_W - S_PAD*2 - 40, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetSize(S_W - S_PAD*2 - 56, 18)
    eb:SetPoint("LEFT", 6, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(64)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetTextColor(0.85, 0.85, 0.85)
    eb:SetScript("OnTextChanged", function(self)
        NightsFarmtrackerDB.tsmCustomSource = self:GetText()
        if tsmDropdown then tsmDropdown:Refresh() end
        ns.ClearPriceCache()
    end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_ACCENT))
    end)
    eb:SetScript("OnEditFocusLost", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))
    end)
    frame.eb = eb
    return frame
end

------------------------------------------------------------------------
-- Helper: EditBox for gear AH threshold (gold, numeric only)
------------------------------------------------------------------------
local function MakeGearThresholdEB(parent, yOff)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(60, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetSize(48, 18)
    eb:SetPoint("LEFT", 6, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(7)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetTextColor(0.85, 0.85, 0.85)
    eb:SetScript("OnTextChanged", function(self)
        local gold = tonumber(self:GetText()) or 0
        NightsFarmtrackerDB.gearAHThreshold = gold * 10000
    end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_ACCENT))
    end)
    eb:SetScript("OnEditFocusLost", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))
    end)

    -- Parented to the outer settings list, not the bordered box, so it
    -- renders clearly outside the input field instead of hugging the edge.
    local goldLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldLbl:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    goldLbl:SetText(ns.L["gold_suffix"])
    goldLbl:SetTextColor(0.6,0.6,0.6)
    frame.goldLbl = goldLbl

    -- goldLbl isn't a child of frame (it needs to sit outside frame's
    -- bordered box), so it won't auto-hide/show with frame - keep it in
    -- sync explicitly since this widget is reused across settings rebuilds.
    local baseShow, baseHide = frame.Show, frame.Hide
    frame.Show = function(self) baseShow(self); goldLbl:Show() end
    frame.Hide = function(self) baseHide(self); goldLbl:Hide() end

    frame.eb = eb
    return frame
end

------------------------------------------------------------------------
-- Helper: EditBox for the fixed session length (minutes, numeric only)
------------------------------------------------------------------------
local function MakeSessionLengthEB(parent, yOff)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(60, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetSize(48, 18)
    eb:SetPoint("LEFT", 6, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(4)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetTextColor(0.85, 0.85, 0.85)
    eb:SetScript("OnTextChanged", function(self)
        NightsFarmtrackerDB.sessionLength = tonumber(self:GetText()) or 0
        ns.UpdateTimerDisplay()
        ns.ApplyPauseVisuals()
    end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_ACCENT))
    end)
    eb:SetScript("OnEditFocusLost", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))
    end)

    -- Suffix label lives on the outer list (see MakeGearThresholdEB), so
    -- keep its visibility in sync with the reused frame explicitly.
    local unitLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unitLbl:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    unitLbl:SetText(ns.L["minutes_suffix"])
    unitLbl:SetTextColor(0.6,0.6,0.6)
    local baseShow, baseHide = frame.Show, frame.Hide
    frame.Show = function(self) baseShow(self); unitLbl:Show() end
    frame.Hide = function(self) baseHide(self); unitLbl:Hide() end

    frame.eb = eb
    return frame
end

------------------------------------------------------------------------
-- Helper: dropdown for Color Theme (expandable list, unlike the TSM
-- cycle-button - there are enough themes that jumping straight to one
-- beats clicking through them one by one)
------------------------------------------------------------------------
local themeMenuList
local THEME_ROW_H = 20

------------------------------------------------------------------------
-- Helper: "Open Export Window" button (Data Export section) - single
-- persistent instance, reused across rebuilds like gearThresholdEB above.
------------------------------------------------------------------------
local exportBtn
local function MakeExportButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(S_W - S_PAD*2, 18)
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetAllPoints(); text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(ns.COL_ACCENT))
    text:SetText(ns.L["export_open_btn"])
    btn:SetScript("OnEnter", function() text:SetTextColor(1,1,1) end)
    btn:SetScript("OnLeave", function() text:SetTextColor(unpack(ns.COL_ACCENT)) end)
    btn:SetScript("OnClick", function() ns.ToggleExportWindow() end)
    return btn
end

local function CloseThemeMenu()
    if themeMenuList then themeMenuList:Hide() end
end

local function MakeThemeDropdown(parent, yOff)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(S_W - S_PAD*2 - 40, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    frame.lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.lbl:SetPoint("LEFT",6,0)
    frame.lbl:SetTextColor(0.85,0.85,0.85)

    local arrow = frame:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(10, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(unpack(ns.COL_ACCENT))

    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetFrameStrata("TOOLTIP")
    list:EnableMouse(true)  -- blocks clicks from falling through to whatever sits behind the open list
    ns.StyleBackdropBox(list, {0.05,0.08,0.09,1})
    list:Hide()
    themeMenuList = list

    local function ThemeLabel(theme)
        local name = ns.L[theme.labelKey] or theme.name
        local desc = theme.descKey and ns.L[theme.descKey]
        return desc and (name.." ("..desc..")") or name
    end

    list.rows = {}
    for i, key in ipairs(ns.COLOR_THEME_ORDER) do
        local theme = ns.COLOR_THEMES[key]
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(THEME_ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i-1)*THEME_ROW_H)
        row:SetPoint("RIGHT", -2, 0)
        row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.txt:SetPoint("LEFT", 6, 0)
        row.txt:SetText(ThemeLabel(theme))
        row.txt:SetTextColor(0.85,0.85,0.85)
        row:SetScript("OnEnter", function() row.txt:SetTextColor(1,1,1) end)
        row:SetScript("OnLeave", function() row.txt:SetTextColor(0.85,0.85,0.85) end)
        row:SetScript("OnClick", function()
            NightsFarmtrackerDB.colorTheme = key
            list:Hide()
            frame:Refresh()
            StaticPopup_Show("NFT_RELOAD")
        end)
        list.rows[i] = row
    end
    list:SetHeight(2 + THEME_ROW_H * #ns.COLOR_THEME_ORDER + 2)

    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        if list:IsShown() then list:Hide(); return end
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        list:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
        list:Show()
    end)

    function frame:Refresh()
        local key   = NightsFarmtrackerDB.colorTheme or "default"
        local theme = ns.COLOR_THEMES[key] or ns.COLOR_THEMES.default
        self.lbl:SetText(ThemeLabel(theme))
    end

    return frame
end

------------------------------------------------------------------------
-- Helper: dropdown for Profile selection. Rebuilt every time it's opened
-- (unlike the Color Theme list) since profiles can be created, renamed or
-- deleted at any time.
------------------------------------------------------------------------
local profileMenuList
local profileMenuRows = {}
local PROFILE_ROW_H = 20

local function CloseProfileMenu()
    if profileMenuList then profileMenuList:Hide() end
end

local function MakeProfileDropdown(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(S_W - S_PAD*2 - 40, 24)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    frame.lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.lbl:SetPoint("LEFT",6,0)
    frame.lbl:SetTextColor(0.85,0.85,0.85)

    local arrow = frame:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(10, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(unpack(ns.COL_ACCENT))

    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetFrameStrata("TOOLTIP")
    list:EnableMouse(true)  -- blocks clicks from falling through to whatever sits behind the open list
    ns.StyleBackdropBox(list, {0.05,0.08,0.09,1})
    list:Hide()
    profileMenuList = list

    local function RebuildList()
        local names = ns.GetProfileList()
        local active = ns.GetActiveProfileName()
        for i, row in ipairs(profileMenuRows) do row:Hide() end
        for i, name in ipairs(names) do
            local row = profileMenuRows[i]
            if not row then
                row = CreateFrame("Button", nil, list)
                row:SetHeight(PROFILE_ROW_H)
                row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.txt:SetPoint("LEFT", 6, 0)
                row:SetScript("OnEnter", function() row.txt:SetTextColor(1,1,1) end)
                row:SetScript("OnLeave", function()
                    row.txt:SetTextColor(row.isActive and 1 or 0.85, row.isActive and 0.82 or 0.85, row.isActive and 0 or 0.85)
                end)
                profileMenuRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 2, -2 - (i-1)*PROFILE_ROW_H)
            row:SetPoint("RIGHT", -2, 0)
            row.txt:SetText(name)
            row.isActive = (name == active)
            row.txt:SetTextColor(row.isActive and 1 or 0.85, row.isActive and 0.82 or 0.85, row.isActive and 0 or 0.85)
            row:SetScript("OnClick", function()
                if name ~= ns.GetActiveProfileName() then
                    ns.SetActiveProfile(name)
                    ns.RebuildSettingsContent()
                    StaticPopup_Show("NFT_RELOAD")
                end
                list:Hide()
            end)
            row:Show()
        end
        list:SetHeight(2 + PROFILE_ROW_H * #names + 2)
    end

    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        if list:IsShown() then list:Hide(); return end
        RebuildList()
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        list:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
        list:Show()
    end)

    function frame:Refresh()
        self.lbl:SetText(ns.GetActiveProfileName())
    end

    return frame
end

------------------------------------------------------------------------
-- Helper: New / Copy / Rename buttons for the Profiles section.
------------------------------------------------------------------------
local function MakeProfileButtons(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(S_W - S_PAD*2, 18)

    local btnW = (S_W - S_PAD*2 - 2*6) / 3
    local x = 0

    local function MakeBtn(labelKey, onClick)
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(btnW, 18)
        btn:SetPoint("LEFT", x, 0)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints(); lbl:SetJustifyH("CENTER")
        lbl:SetText(ns.L[labelKey])
        lbl:SetTextColor(0.75,0.75,0.75)
        btn.lbl = lbl
        btn:SetScript("OnEnter", function() if btn:IsEnabled() then lbl:SetTextColor(1,0.82,0) end end)
        btn:SetScript("OnLeave", function() lbl:SetTextColor(btn:IsEnabled() and 0.75 or 0.35, btn:IsEnabled() and 0.75 or 0.35, btn:IsEnabled() and 0.75 or 0.35) end)
        btn:SetScript("OnClick", onClick)
        x = x + btnW + 6
        return btn
    end

    MakeBtn("profile_new", function() StaticPopup_Show("NFT_PROFILE_NEW") end)
    MakeBtn("profile_copy", function() StaticPopup_Show("NFT_PROFILE_COPY") end)
    MakeBtn("profile_rename", function() StaticPopup_Show("NFT_PROFILE_RENAME") end)

    function frame:Refresh() end -- nothing dynamic here anymore

    return frame
end

------------------------------------------------------------------------
-- Helper: "Delete profile" row - its own dropdown (any profile except
-- "Default", which can never be deleted) plus a Delete button. Deleting a
-- profile that ISN'T the character's active one needs no reload at all;
-- only deleting the active one does (handled in NFT_PROFILE_DELETE_CONFIRM).
------------------------------------------------------------------------
local deleteMenuList
local deleteMenuRows = {}
local DELETE_ROW_H = 20

local function CloseDeleteMenu()
    if deleteMenuList then deleteMenuList:Hide() end
end

local function MakeDeleteProfileRow(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(S_W - S_PAD*2, 24)

    local dd = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    dd:SetSize(S_W - S_PAD*2 - 70, 24)
    dd:SetPoint("LEFT", 0, 0)
    ns.StyleBackdropBox(dd, {0.05,0.08,0.09,1})

    dd.lbl = dd:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dd.lbl:SetPoint("LEFT",6,0)
    dd.lbl:SetPoint("RIGHT",-6,0)
    dd.lbl:SetJustifyH("LEFT")
    dd.lbl:SetTextColor(0.85,0.85,0.85)

    local arrow = dd:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(10, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(unpack(ns.COL_ACCENT))

    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetFrameStrata("TOOLTIP")
    list:EnableMouse(true)  -- blocks clicks from falling through to whatever sits behind the open list
    ns.StyleBackdropBox(list, {0.05,0.08,0.09,1})
    list:Hide()
    deleteMenuList = list

    frame.selected = nil

    local function Candidates()
        local out = {}
        local active = ns.GetActiveProfileName()
        for _, name in ipairs(ns.GetProfileList()) do
            if name ~= ns.DEFAULT_PROFILE and name ~= active then out[#out+1] = name end
        end
        return out
    end

    local function UpdateLabel()
        dd.lbl:SetText(frame.selected or ns.L["profile_delete_none"])
    end

    local function RebuildList()
        local names = Candidates()
        for i, row in ipairs(deleteMenuRows) do row:Hide() end
        for i, name in ipairs(names) do
            local row = deleteMenuRows[i]
            if not row then
                row = CreateFrame("Button", nil, list)
                row:SetHeight(DELETE_ROW_H)
                row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.txt:SetPoint("LEFT", 6, 0)
                row.txt:SetTextColor(0.85,0.85,0.85)
                row:SetScript("OnEnter", function() row.txt:SetTextColor(1,1,1) end)
                row:SetScript("OnLeave", function() row.txt:SetTextColor(0.85,0.85,0.85) end)
                deleteMenuRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 2, -2 - (i-1)*DELETE_ROW_H)
            row:SetPoint("RIGHT", -2, 0)
            row.txt:SetText(name)
            row:SetScript("OnClick", function()
                frame.selected = name
                UpdateLabel()
                list:Hide()
            end)
            row:Show()
        end
        list:SetHeight(2 + DELETE_ROW_H * math.max(#names, 1) + 2)
    end

    dd:EnableMouse(true)
    dd:SetScript("OnMouseUp", function()
        if #Candidates() == 0 then return end
        if list:IsShown() then list:Hide(); return end
        RebuildList()
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
        list:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", 0, -2)
        list:Show()
    end)

    local delBtn = CreateFrame("Button", nil, frame)
    delBtn:SetSize(60, 24)
    delBtn:SetPoint("RIGHT", 0, 0)
    local delLbl = delBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    delLbl:SetAllPoints(); delLbl:SetJustifyH("CENTER")
    delLbl:SetText(ns.L["profile_delete"])
    delBtn.lbl = delLbl
    delBtn:SetScript("OnEnter", function() if delBtn:IsEnabled() then delLbl:SetTextColor(1,0.4,0.4) end end)
    delBtn:SetScript("OnLeave", function() delLbl:SetTextColor(delBtn:IsEnabled() and 0.50 or 0.30, delBtn:IsEnabled() and 0.22 or 0.30, delBtn:IsEnabled() and 0.22 or 0.30) end)
    delBtn:SetScript("OnClick", function()
        if frame.selected then
            StaticPopup_Show("NFT_PROFILE_DELETE_CONFIRM", frame.selected, nil, frame.selected)
        end
    end)
    frame.delBtn = delBtn

    function frame:Refresh()
        local candidates = Candidates()
        if frame.selected then
            local stillValid = false
            for _, name in ipairs(candidates) do if name == frame.selected then stillValid = true end end
            if not stillValid then frame.selected = nil end
        end
        if not frame.selected and candidates[1] then frame.selected = candidates[1] end
        UpdateLabel()
        local hasAny = #candidates > 0
        delBtn:SetEnabled(hasAny)
        delLbl:SetTextColor(hasAny and 0.50 or 0.30, hasAny and 0.22 or 0.30, hasAny and 0.22 or 0.30)
    end

    return frame
end

------------------------------------------------------------------------
-- Checkbox row — pooled, same rationale as radio rows above.
------------------------------------------------------------------------
local checkboxPool = {}

local function AcquireCheckbox(parent)
    local row = table.remove(checkboxPool)
    if row then
        row:SetParent(parent)
        row:Show()
        return row
    end

    row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2, 36)

    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetSize(14, 14); box:SetPoint("TOPLEFT", 0, -4)
    ns.StyleBackdropBox(box)

    local check = box:CreateTexture(nil,"ARTWORK")
    check:SetSize(7,7); check:SetPoint("CENTER")
    check:SetColorTexture(unpack(ns.COL_ACCENT))
    row.check = check

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 0)
    lbl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    row.label = lbl

    return row
end

-- (Re-)configures a pooled checkbox row: label text, position, and the
-- getValue/setValue accessors driving its checked state and click handler.
local function ConfigureCheckbox(row, label, yOff, getValue, setValue)
    row:SetPoint("TOPLEFT", S_PAD, yOff)
    row.label:SetText(label)

    local function Refresh()
        if getValue() then row.check:Show(); row.label:SetTextColor(1,0.82,0)
        else                row.check:Hide(); row.label:SetTextColor(0.85,0.85,0.85) end
    end
    Refresh()
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function() setValue(not getValue()); Refresh() end)
    return row
end

local function ReleaseCheckbox(row)
    row:Hide(); row:ClearAllPoints()
    row:SetScript("OnMouseUp", nil)
    checkboxPool[#checkboxPool+1] = row
end

------------------------------------------------------------------------
-- Section title / hint text — pooled FontStrings. Text color is set once
-- at creation (ns.COL_ACCENT/gray) since a theme change always requires
-- a UI reload (see ApplyColorTheme), so it never goes stale while pooled.
------------------------------------------------------------------------
local sectionLabelPool = {}
local hintLabelPool    = {}

local function AcquireSectionLabel(parent)
    local fs = table.remove(sectionLabelPool)
    if fs then fs:SetParent(parent); fs:Show(); return fs end
    fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetTextColor(unpack(ns.COL_ACCENT))
    return fs
end

local function ReleaseSectionLabel(fs)
    fs:Hide(); fs:ClearAllPoints()
    sectionLabelPool[#sectionLabelPool+1] = fs
end

local function AcquireHintLabel(parent)
    local fs = table.remove(hintLabelPool)
    if fs then fs:SetParent(parent); fs:Show(); return fs end
    fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    return fs
end

local function ReleaseHintLabel(fs)
    fs:Hide(); fs:ClearAllPoints()
    hintLabelPool[#hintLabelPool+1] = fs
end

-- Separate pool for the one hint that uses a fixed width + word wrap (the
-- TSM hint line) - kept apart from the auto-sized hints above so reuse
-- never has to un-set a manually fixed width.
local wrappedHintPool = {}

local function AcquireWrappedHint(parent)
    local fs = table.remove(wrappedHintPool)
    if fs then fs:SetParent(parent); fs:Show(); return fs end
    fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetWidth(S_W - S_PAD*2)
    fs:SetJustifyH("LEFT")
    return fs
end

local function ReleaseWrappedHint(fs)
    fs:Hide(); fs:ClearAllPoints()
    wrappedHintPool[#wrappedHintPool+1] = fs
end

------------------------------------------------------------------------
-- Settings content (rebuilt on open / change)
-- All widgets are parented to SListFrame (the scroll child). Entries are
-- tracked with their "kind" so the next rebuild can release each one back
-- to its pool instead of leaking a fresh Frame/FontString every time -
-- radios, checkboxes and labels are all reused (see AcquireRadio/
-- AcquireCheckbox/AcquireSectionLabel/AcquireHintLabel above). The
-- persistent single-instance widgets (tsmDropdown, tsmCustomEB,
-- themeDropdown) are not pooled here - they already manage their own
-- reuse (create-once, reposition-and-show on every rebuild) and are
-- simply hidden between rebuilds like before.
------------------------------------------------------------------------
local settingsContent = {}

local RELEASE_FN = {
    radio       = ReleaseRadio,
    checkbox    = ReleaseCheckbox,
    section     = ReleaseSectionLabel,
    hint        = ReleaseHintLabel,
    wrappedHint = ReleaseWrappedHint,
}

------------------------------------------------------------------------
-- Sidebar navigation — pooled category buttons on the left, rebuilt to
-- match whatever sections actually exist this rebuild (TSM section is
-- conditional). Clicking a row scrolls the content so that section's
-- header lands at the top of the visible area.
------------------------------------------------------------------------
local S_SIDEBAR_W = 92
local sidebarPool = {}
local sidebarRows = {}

local function AcquireSidebarRow(parent)
    local row = table.remove(sidebarPool)
    if row then row:SetParent(parent); row:Show(); return row end

    row = CreateFrame("Button", nil, parent)
    row:SetWidth(S_SIDEBAR_W - 12)
    row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.txt:SetPoint("TOPLEFT", 0, 0)
    -- Fixed explicit width (not anchor-stretched) so word wrap is resolved
    -- immediately on the same frame. Anchor-based width (TOPLEFT+TOPRIGHT)
    -- isn't guaranteed to resolve before GetStringHeight() is read below,
    -- which caused the label to render unwrapped on the very first build.
    row.txt:SetWidth(S_SIDEBAR_W - 12)
    row.txt:SetJustifyH("LEFT")
    row.txt:SetWordWrap(true)
    row:SetScript("OnEnter", function(self) self.txt:SetTextColor(1, 0.82, 0) end)
    row:SetScript("OnLeave", function(self) self.txt:SetTextColor(0.7, 0.7, 0.7) end)
    return row
end

local function ReleaseSidebarRow(row)
    row:Hide(); row:ClearAllPoints()
    row:SetScript("OnClick", nil)
    sidebarPool[#sidebarPool + 1] = row
end

local function RebuildSidebar(jumpTargets)
    for _, row in ipairs(sidebarRows) do ReleaseSidebarRow(row) end
    sidebarRows = {}

    local rowY = -4
    for _, target in ipairs(jumpTargets) do
        local row = AcquireSidebarRow(SSidebar)
        row.txt:SetText(target.title)
        row.txt:SetTextColor(0.7, 0.7, 0.7)
        row:SetPoint("TOPLEFT", 6, rowY)
        row:SetHeight(math.max(16, row.txt:GetStringHeight()))
        row:EnableMouse(true)
        row:SetScript("OnClick", function()
            local maxS = math.max(0, SListFrame:GetHeight() - SScrollFrame:GetHeight())
            SScrollFrame:SetVerticalScroll(math.max(0, math.min(target.y, maxS)))
        end)
        row:Show()
        sidebarRows[#sidebarRows + 1] = row
        rowY = rowY - row:GetHeight() - 10
    end
end

------------------------------------------------------------------------
-- Settings content (rebuilt on open / change). Sections are collected as
-- {titleKey, title, builder} entries, then alpha-sorted by the CURRENT
-- locale's title text so the list reads alphabetically in every language
-- without hardcoding per-locale order. Each builder receives the running
-- y-offset and returns the new one; a sidebar entry is recorded for each
-- section's starting position so the nav list can jump to it.
------------------------------------------------------------------------
function ns.RebuildSettingsContent()
    if not SListFrame then return end
    CloseThemeMenu()
    CloseProfileMenu()
    CloseDeleteMenu()
    local prevScroll = SScrollFrame:GetVerticalScroll()
    for _, entry in ipairs(settingsContent) do
        local release = RELEASE_FN[entry.kind]
        if release then release(entry.widget) else entry.widget:Hide() end
    end
    settingsContent = {}

    local db = NightsFarmtrackerDB

    local function track(widget, kind)
        settingsContent[#settingsContent + 1] = {widget = widget, kind = kind}
        return widget
    end

    local sections = {}
    local function addSection(titleKey, builder)
        sections[#sections + 1] = {titleKey = titleKey, title = ns.L[titleKey], builder = builder}
    end

    -- ----------------------------------------------------------------
    -- Section: AH Price Source (includes the Gear AH Threshold sub-block,
    -- which has no header of its own and always follows this section)
    -- ----------------------------------------------------------------
    addSection("ah_source", function(y)
        local secLbl = track(AcquireSectionLabel(SListFrame), "section")
        secLbl:SetPoint("TOPLEFT", S_PAD, y)
        secLbl:SetText(ns.L["ah_source"])
        y = y - 22

        local ahOptions = {
            {label=ns.L["ah_auctionator"], value="auctionator", avail=ns.HasAuctionator()},
            {label=ns.L["ah_oribos"],      value="oribos",      avail=ns.HasOribos()},
            {label=ns.L["ah_tsm"],         value="tsm",         avail=ns.HasTSM()},
            {label=ns.L["ah_none"],        value="none",        avail=true},
        }
        local availableCount = (ns.HasAuctionator() and 1 or 0) + (ns.HasOribos() and 1 or 0) + (ns.HasTSM() and 1 or 0)
        if availableCount > 0 then
            table.insert(ahOptions, 1, {label=ns.L["ah_auto"], value="auto", avail=true})
        end

        local function getAH()  return db.ahSource or "auto" end
        local function setAH(v) db.ahSource = v; ns.ClearPriceCache() end

        for _, opt in ipairs(ahOptions) do
            local row = track(AcquireRadio(SListFrame), "radio")
            ConfigureRadio(row, opt.label, y, opt.value, getAH, setAH)
            row:SetSelected(getAH() == opt.value)
            row:SetEnabled(opt.avail)
            y = y - 24
            if opt.value == "auto" and availableCount > 1 then
                local infoLbl = track(AcquireHintLabel(SListFrame), "hint")
                infoLbl:SetPoint("TOPLEFT", S_PAD + 22, y)
                infoLbl:SetTextColor(0.38, 0.38, 0.38)
                infoLbl:SetText(ns.L["ah_auto_info"])
                y = y - 16
            end
        end

        -- Gear AH Threshold (below this vendor price, Equipment skips the
        -- AH lookup and always uses vendor price; 0 = disabled)
        y = y - 4
        local threshHint = track(AcquireWrappedHint(SListFrame), "wrappedHint")
        threshHint:SetPoint("TOPLEFT", S_PAD, y)
        threshHint:SetTextColor(0.5,0.5,0.5)
        threshHint:SetText(ns.L["gear_ah_threshold_hint"])
        y = y - 28

        if not gearThresholdEB then
            gearThresholdEB = MakeGearThresholdEB(SListFrame, y)
        else
            gearThresholdEB:SetPoint("TOPLEFT", S_PAD, y)
            gearThresholdEB:Show()
        end
        local threshGold = math.floor((db.gearAHThreshold or 0) / 10000)
        gearThresholdEB.eb:SetText(threshGold > 0 and tostring(threshGold) or "")
        track(gearThresholdEB, "other")
        y = y - 32

        local threshSoundRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(threshSoundRow, ns.L["gear_ah_threshold_sound"], y,
            function() return db.gearAHThresholdSound == true end,
            function(v) db.gearAHThresholdSound = v end)
        y = y - 38

        -- TSM source sub-block (only if TSM is installed) - a detail of the
        -- AH source choice above, not a separate concern of its own.
        if ns.HasTSM() then
            y = y - 4
            local hint = track(AcquireWrappedHint(SListFrame), "wrappedHint")
            hint:SetPoint("TOPLEFT", S_PAD, y)
            hint:SetTextColor(0.5,0.5,0.5)
            hint:SetText(ns.L["tsm_hint"])
            y = y - 28

            if not tsmDropdown then
                tsmDropdown = MakeDropdown(SListFrame, y)
            else
                tsmDropdown:SetPoint("TOPLEFT", S_PAD, y)
                tsmDropdown:Show()
            end
            tsmDropdown:Refresh()
            track(tsmDropdown, "other")
            y = y - 32

            local customLbl = track(AcquireHintLabel(SListFrame), "hint")
            customLbl:SetPoint("TOPLEFT", S_PAD, y)
            customLbl:SetTextColor(0.50, 0.50, 0.50)
            customLbl:SetText(ns.L["tsm_custom"])
            y = y - 18

            if not tsmCustomEB then
                tsmCustomEB = MakeCustomSourceEB(SListFrame, y)
            else
                tsmCustomEB:SetPoint("TOPLEFT", S_PAD, y)
                tsmCustomEB:Show()
            end
            tsmCustomEB.eb:SetText(db.tsmCustomSource or "")
            track(tsmCustomEB, "other")
            y = y - 32
        end

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Display
    -- ----------------------------------------------------------------
    addSection("display", function(y)
        local dispLbl = track(AcquireSectionLabel(SListFrame), "section")
        dispLbl:SetPoint("TOPLEFT", S_PAD, y)
        dispLbl:SetText(ns.L["display"])
        y = y - 26

        local function getRateMode() return db.goldRateMode=="min" and "min" or "hour" end
        local rateRow1 = track(AcquireRadio(SListFrame), "radio")
        ConfigureRadio(rateRow1, ns.L["gold_per_hour"], y, "hour", getRateMode,
            function(v) db.goldRateMode=v; ns.UpdateGoldRate() end)
        rateRow1:SetSelected(getRateMode()=="hour"); rateRow1:SetEnabled(true)
        y = y - 24

        local rateRow2 = track(AcquireRadio(SListFrame), "radio")
        ConfigureRadio(rateRow2, ns.L["gold_per_min"], y, "min", getRateMode,
            function(v) db.goldRateMode=v; ns.UpdateGoldRate() end)
        rateRow2:SetSelected(getRateMode()=="min"); rateRow2:SetEnabled(true)
        y = y - 32

        -- Fixed session length (0 = off): timer counts down, session pauses at 0
        local lenHint = track(AcquireWrappedHint(SListFrame), "wrappedHint")
        lenHint:SetPoint("TOPLEFT", S_PAD, y)
        lenHint:SetTextColor(0.5,0.5,0.5)
        lenHint:SetText(ns.L["session_length_hint"])
        y = y - 28

        if not sessionLengthEB then
            sessionLengthEB = MakeSessionLengthEB(SListFrame, y)
        else
            sessionLengthEB:SetPoint("TOPLEFT", S_PAD, y)
            sessionLengthEB:Show()
        end
        local lenMin = tonumber(db.sessionLength) or 0
        sessionLengthEB.eb:SetText(lenMin > 0 and tostring(lenMin) or "")
        track(sessionLengthEB, "other")
        y = y - 40

        local function getGoldDisplay() return db.goldDisplayMode=="modern" and "modern" or "classic" end
        local function setGoldDisplay(v) db.goldDisplayMode=v; ns.RefreshHUD() end

        local gdRow1 = track(AcquireRadio(SListFrame), "radio")
        ConfigureRadio(gdRow1, ns.L["gold_display_classic"], y, "classic", getGoldDisplay, setGoldDisplay)
        gdRow1:SetSelected(getGoldDisplay()=="classic"); gdRow1:SetEnabled(true)
        y = y - 24

        local gdRow2 = track(AcquireRadio(SListFrame), "radio")
        ConfigureRadio(gdRow2, ns.L["gold_display_modern"], y, "modern", getGoldDisplay, setGoldDisplay)
        gdRow2:SetSelected(getGoldDisplay()=="modern"); gdRow2:SetEnabled(true)
        y = y - 24

        local mmRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(mmRow, ns.L["minimap_button"], y,
            function() return not db.minimapHidden end,
            function(v)
                db.minimapHidden = not v
                db.minimap.hide  = not v
                if v then
                    StaticPopup_Show("NFT_RELOAD")
                else
                    ns.SetMinimapVisible(false)
                end
            end)
        y = y - 38

        local logRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(logRow, ns.L["log_window_enabled"], y,
            function() return db.logWindowEnabled == true end,
            function(v)
                db.logWindowEnabled = v
                if not v then ns.OnLogWindowDisabled() end
                ns.RefreshLeftButtons()
            end)
        y = y - 38

        if not themeDropdown then
            themeDropdown = MakeThemeDropdown(SListFrame, y)
        else
            themeDropdown:SetPoint("TOPLEFT", S_PAD, y)
            themeDropdown:Show()
        end
        themeDropdown:Refresh()
        track(themeDropdown, "other")
        y = y - 32

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Profiles
    -- ----------------------------------------------------------------
    addSection("sec_profiles", function(y)
        local profLbl = track(AcquireSectionLabel(SListFrame), "section")
        profLbl:SetPoint("TOPLEFT", S_PAD, y)
        profLbl:SetText(ns.L["sec_profiles"])
        y = y - 26

        if not profileDropdown then
            profileDropdown = MakeProfileDropdown(SListFrame)
        end
        profileDropdown:ClearAllPoints()
        profileDropdown:SetPoint("TOPLEFT", S_PAD, y)
        profileDropdown:Show()
        profileDropdown:Refresh()
        track(profileDropdown, "other")
        y = y - 30

        if not profileButtons then
            profileButtons = MakeProfileButtons(SListFrame)
        end
        profileButtons:ClearAllPoints()
        profileButtons:SetPoint("TOPLEFT", S_PAD, y)
        profileButtons:Show()
        profileButtons:Refresh()
        track(profileButtons, "other")
        y = y - 30

        local delHint = track(AcquireHintLabel(SListFrame), "hint")
        delHint:SetPoint("TOPLEFT", S_PAD, y)
        delHint:SetTextColor(0.50, 0.50, 0.50)
        delHint:SetText(ns.L["profile_delete_hint"])
        y = y - 18

        if not deleteProfileRow then
            deleteProfileRow = MakeDeleteProfileRow(SListFrame)
        end
        deleteProfileRow:ClearAllPoints()
        deleteProfileRow:SetPoint("TOPLEFT", S_PAD, y)
        deleteProfileRow:Show()
        deleteProfileRow:Refresh()
        track(deleteProfileRow, "other")
        y = y - 30

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Session History
    -- ----------------------------------------------------------------
    addSection("session_history", function(y)
        local trackLbl = track(AcquireSectionLabel(SListFrame), "section")
        trackLbl:SetPoint("TOPLEFT", S_PAD, y)
        trackLbl:SetText(ns.L["session_history"])
        y = y - 26

        local histRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(histRow, ns.L["session_history_enabled"], y,
            function() return db.sessionHistoryEnabled ~= false end,
            function(v)
                db.sessionHistoryEnabled = v
                ns.RefreshLeftButtons()
            end)
        y = y - 38

        local histModeLbl = track(AcquireHintLabel(SListFrame), "hint")
        histModeLbl:SetPoint("TOPLEFT", S_PAD, y)
        histModeLbl:SetTextColor(0.6, 0.6, 0.6)
        histModeLbl:SetText(ns.L["session_history_mode"])
        y = y - 18

        local function getHistMode() return db.sessionHistoryMode == "compact" and "compact" or "full" end

        local histModeRow1 = track(AcquireRadio(SListFrame), "radio")
        ConfigureRadio(histModeRow1, ns.L["session_history_mode_full"], y, "full", getHistMode,
            function(v) db.sessionHistoryMode = v end)
        histModeRow1:SetSelected(getHistMode()=="full"); histModeRow1:SetEnabled(true)
        y = y - 24

        -- "compact" folds past months irreversibly, so route it through a
        -- confirmation popup instead of ConfigureRadio's default instant-set
        -- OnMouseUp behavior.
        local histModeRow2 = track(AcquireRadio(SListFrame), "radio")
        ConfigureRadio(histModeRow2, ns.L["session_history_mode_compact"], y, "compact", getHistMode, function() end)
        histModeRow2:SetScript("OnMouseUp", function()
            if getHistMode() ~= "compact" then
                StaticPopup_Show("NFT_CONFIRM_HISTORY_COMPACT")
            end
        end)
        histModeRow2:SetSelected(getHistMode()=="compact"); histModeRow2:SetEnabled(true)
        y = y - 30

        local mergeRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(mergeRow, ns.L["merge_daily_sessions"], y,
            function() return db.mergeDaily ~= false end,
            function(v)
                db.mergeDaily = v
            end)
        y = y - 38

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Categories & Grouping
    -- ----------------------------------------------------------------
    addSection("sec_categories", function(y)
        local catLbl = track(AcquireSectionLabel(SListFrame), "section")
        catLbl:SetPoint("TOPLEFT", S_PAD, y)
        catLbl:SetText(ns.L["sec_categories"])
        y = y - 26

        local splitRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(splitRow, ns.L["split_trade_goods"], y,
            function() return db.splitTradeGoods == true end,
            function(v)
                db.splitTradeGoods = v
                ns.RefreshHUD()
            end)
        y = y - 38

        local splitGearRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(splitGearRow, ns.L["split_gear_by_binding"], y,
            function() return db.splitGearByBinding == true end,
            function(v)
                db.splitGearByBinding = v
                ns.RefreshHUD()
            end)
        y = y - 38

        local mergeJunkRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(mergeJunkRow, ns.L["merge_junk_entries"], y,
            function() return db.mergeJunkEntries == true end,
            function(v)
                db.mergeJunkEntries = v
                StaticPopup_Show("NFT_RELOAD")
            end)
        y = y - 38

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Filters
    -- ----------------------------------------------------------------
    addSection("sec_filters", function(y)
        local filterLbl = track(AcquireSectionLabel(SListFrame), "section")
        filterLbl:SetPoint("TOPLEFT", S_PAD, y)
        filterLbl:SetText(ns.L["sec_filters"])
        y = y - 26

        local filterRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(filterRow, ns.L["vendor_filter_enabled"], y,
            function() return db.vendorFilterEnabled ~= false end,
            function(v)
                db.vendorFilterEnabled = v
                ns.RefreshLeftButtons()
                ns.RefreshHUD()
            end)
        y = y - 38

        local blacklistRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(blacklistRow, ns.L["blacklist_enabled"], y,
            function() return db.blacklistEnabled ~= false end,
            function(v)
                db.blacklistEnabled = v
                ns.RefreshLeftButtons()
                ns.RefreshHUD()
            end)
        y = y - 38

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Fishing
    -- ----------------------------------------------------------------
    addSection("sec_fishing", function(y)
        local fishingLbl = track(AcquireSectionLabel(SListFrame), "section")
        fishingLbl:SetPoint("TOPLEFT", S_PAD, y)
        fishingLbl:SetText(ns.L["sec_fishing"])
        y = y - 26

        local venomRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(venomRow, ns.L["venom_tracker_enabled"], y,
            function() return db.venomTrackerEnabled == true end,
            function(v) ns.SetVenomTrackerEnabled(v) end)
        y = y - 38

        local baitRow = track(AcquireCheckbox(SListFrame), "checkbox")
        ConfigureCheckbox(baitRow, ns.L["bait_frame_enabled"], y,
            function() return db.baitFrameEnabled == true end,
            function(v) ns.SetBaitFrameEnabled(v) end)
        y = y - 38

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Data Export
    -- ----------------------------------------------------------------
    addSection("sec_export", function(y)
        local exportLbl = track(AcquireSectionLabel(SListFrame), "section")
        exportLbl:SetPoint("TOPLEFT", S_PAD, y)
        exportLbl:SetText(ns.L["sec_export"])
        y = y - 26

        local exportHint = track(AcquireWrappedHint(SListFrame), "wrappedHint")
        exportHint:SetPoint("TOPLEFT", S_PAD, y)
        exportHint:SetTextColor(0.5,0.5,0.5)
        exportHint:SetText(ns.L["export_hint"])
        y = y - 28

        if not exportBtn then
            exportBtn = MakeExportButton(SListFrame)
        else
            exportBtn:SetParent(SListFrame)
            exportBtn:Show()
        end
        exportBtn:SetPoint("TOPLEFT", S_PAD, y)
        track(exportBtn, "other")
        y = y - 30

        return y
    end)

    -- ----------------------------------------------------------------
    -- Sort alphabetically by the CURRENT locale's title text, then build
    -- in that order, recording each section's start position for the
    -- sidebar nav. Profiles is the one exception: it's account/character
    -- management, not a content setting, so it always sorts last
    -- regardless of where its localized title would alphabetically land.
    -- ----------------------------------------------------------------
    table.sort(sections, function(a, b)
        if a.titleKey == "sec_profiles" then return false end
        if b.titleKey == "sec_profiles" then return true end
        return a.title:lower() < b.title:lower()
    end)

    local y = -8   -- start with small top padding within scroll area
    local jumpTargets = {}
    for _, sec in ipairs(sections) do
        jumpTargets[#jumpTargets + 1] = {title = sec.title, y = -y}
        y = sec.builder(y)
    end
    RebuildSidebar(jumpTargets)

    -- ----------------------------------------------------------------
    -- Resize scroll area and outer frame
    -- ----------------------------------------------------------------
    local contentH = math.abs(y) + 8
    SListFrame:SetHeight(contentH)
    local visH = math.min(contentH, S_MAX_VIS)
    SScrollFrame:SetHeight(visH)
    SSidebar:SetHeight(visH)
    SF:SetHeight(S_HDR_H + visH + S_FTR_H)
    local maxS = math.max(0, contentH - visH)
    SScrollFrame:SetVerticalScroll(math.min(prevScroll, maxS))
end

------------------------------------------------------------------------
-- Build settings frame (lazy)
------------------------------------------------------------------------
local function EnsureSettingsFrame()
    if SF then return end

    SF = ns.CreateWindowFrame("NightsFarmtrackerSettingsWnd", ns.L["settings_title"],
        {width = S_W + S_SIDEBAR_W, pad = S_PAD, titleColor = ns.COL_ACCENT})
    SF:SetHeight(280)
    ns.SettingsFrame = SF  -- exposed so Session History can dock next to it in the left-side chain
    -- Closes the floating theme dropdown list whenever Settings hides for
    -- ANY reason (X button, ESC via UISpecialFrames, /reload, etc.) - the
    -- list is a separate TOOLTIP-strata frame parented to UIParent, so it
    -- doesn't auto-close with SF on its own.
    SF:SetScript("OnHide", function()
        CloseThemeMenu()
        CloseProfileMenu()
        CloseDeleteMenu()
        ns.RefreshWindowChain("left")
    end)

    local sep = SF:CreateTexture(nil,"ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(unpack(ns.COL_BORDER))
    sep:SetPoint("TOPLEFT",S_PAD,-(S_HDR_H-1)); sep:SetPoint("TOPRIGHT",-S_PAD,-(S_HDR_H-1))

    -- Sidebar — fixed-width category nav, doesn't scroll with the content.
    SSidebar = CreateFrame("Frame", nil, SF)
    SSidebar:SetPoint("TOPLEFT", 0, -S_HDR_H)
    SSidebar:SetWidth(S_SIDEBAR_W)

    local sidebarSep = SF:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetWidth(1); sidebarSep:SetColorTexture(unpack(ns.COL_BORDER))
    sidebarSep:SetPoint("TOPLEFT", S_SIDEBAR_W, -S_HDR_H)
    sidebarSep:SetPoint("BOTTOMLEFT", S_SIDEBAR_W, S_FTR_H)

    -- Scroll container — right of the sidebar, below header sep
    SScrollFrame = CreateFrame("ScrollFrame", nil, SF)
    SScrollFrame:SetPoint("TOPLEFT",  S_SIDEBAR_W, -S_HDR_H)
    SScrollFrame:SetPoint("TOPRIGHT", 0, -S_HDR_H)
    SScrollFrame:EnableMouseWheel(true)

    SListFrame = CreateFrame("Frame", nil, SScrollFrame)
    SListFrame:SetWidth(S_W)
    SListFrame:SetHeight(1)
    SScrollFrame:SetScrollChild(SListFrame)

    local function OnWheel(_, delta)
        local cur  = SScrollFrame:GetVerticalScroll()
        local maxS = math.max(0, SListFrame:GetHeight() - SScrollFrame:GetHeight())
        SScrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta * S_SCROLL_STEP, maxS)))
    end
    SScrollFrame:SetScript("OnMouseWheel", OnWheel)
    SListFrame:EnableMouseWheel(true)
    SListFrame:SetScript("OnMouseWheel", OnWheel)

    local resetBtn = CreateFrame("Button", nil, SF)
    resetBtn:SetSize(110,18); resetBtn:SetPoint("BOTTOMRIGHT",-S_PAD,6)
    local resetLabel = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetLabel:SetAllPoints(); resetLabel:SetJustifyH("RIGHT"); resetLabel:SetText(ns.L["reset_addon"])
    resetLabel:SetTextColor(0.50,0.22,0.22)
    resetBtn:SetScript("OnClick", function() StaticPopup_Show("NFT_CONFIRM_RESET_ADDON") end)
    resetBtn:SetScript("OnEnter", function() resetLabel:SetTextColor(1,0.4,0.4) end)
    resetBtn:SetScript("OnLeave", function() resetLabel:SetTextColor(0.50,0.22,0.22) end)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleSettings()
    if ns.DeferInCombat(ns.ToggleSettings) then return end
    EnsureSettingsFrame()
    if SF:IsShown() then
        SF:Hide()
    else
        -- History and its Detail child dock off the same anchor point as
        -- Settings, so close them first to avoid overlap.
        if ns.HistFrame and ns.HistFrame:IsShown() then ns.HistFrame:Hide() end
        if ns.DetailFrame and ns.DetailFrame:IsShown() then ns.DetailFrame:Hide() end
        ns.RebuildSettingsContent()
        SF:Show()
        ns.RefreshWindowChain("left")
    end
end

function ns.InitSettings()
    -- nothing to register — our settings are self-contained
end