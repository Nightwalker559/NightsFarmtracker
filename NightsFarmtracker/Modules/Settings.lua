------------------------------------------------------------------------
-- Night's Farmtracker - Settings
-- Custom settings window (no WoW Settings API dependency).
-- Price source: Auctionator / TSM4 / None + TSM price source selector.
------------------------------------------------------------------------
local _, ns = ...


StaticPopupDialogs["NFT_RELOAD"] = {
    text        = ns.L["reload_required"],
    button1     = OKAY,
    button2     = CANCEL,
    OnAccept    = function() ReloadUI() end,
    timeout     = 0,
    whileDead   = true,
    hideOnEscape = true,
}
StaticPopupDialogs["NFT_CONFIRM_HISTORY_COMPACT"] = {
    text        = ns.L["compact_history_confirm"],
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
    text        = ns.L["reset_addon_confirm"],
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
local S_FTR_H       = 26   -- footer strip height (Reset to Default button)
local S_SCROLL_STEP = 22

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
    fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
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
local function ConfigureRadio(row, label, yOff, value, setGroup)
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

-- Text prompt for a profile name; onShow fills the box, onAccept gets the dialog.
local function ProfilePrompt(textKey, onShow, onAccept)
    return {
        text         = ns.L[textKey],
        button1      = OKAY,
        button2      = CANCEL,
        hasEditBox   = true,
        OnShow       = onShow,
        OnAccept     = onAccept,
        EditBoxOnEnterPressed  = function(editBox) editBox:GetParent():GetButton1():Click() end,
        EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
    }
end

local function ClearProfilePrompt(dialog)
    local eb = dialog:GetEditBox()
    eb:SetText(""); eb:SetFocus()
end

-- New / Copy: create the profile under the typed name, switch to it, reload.
local function SwitchToNewProfile(dialog, create)
    local name = dialog:GetEditBox():GetText()
    if name and name ~= "" and create(name) then
        ns.SetActiveProfile(name)
        ns.RebuildSettingsContent()
        StaticPopup_Show("NFT_RELOAD")
    end
end

StaticPopupDialogs["NFT_PROFILE_NEW"] = ProfilePrompt("profile_new_prompt", ClearProfilePrompt,
    function(dialog) SwitchToNewProfile(dialog, ns.CreateProfile) end)
StaticPopupDialogs["NFT_PROFILE_COPY"] = ProfilePrompt("profile_copy_prompt", ClearProfilePrompt,
    function(dialog)
        SwitchToNewProfile(dialog, function(name) return ns.CopyProfile(name, ns.GetActiveProfileName()) end)
    end)
StaticPopupDialogs["NFT_PROFILE_RENAME"] = ProfilePrompt("profile_rename_prompt",
    function(dialog)
        local eb = dialog:GetEditBox()
        eb:SetText(ns.GetActiveProfileName())
        eb:HighlightText()
    end,
    function(dialog)
        local name = dialog:GetEditBox():GetText()
        if name and name ~= "" and ns.RenameProfile(ns.GetActiveProfileName(), name) then
            ns.RebuildSettingsContent()
        end
    end)
StaticPopupDialogs["NFT_PROFILE_DELETE_CONFIRM"] = {
    text         = ns.L["profile_delete_confirm"],
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function(_, name)
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
local maxHeightEB
local profileDropdown
local profileButtons
local deleteProfileRow

-- Single-instance widgets are built on first use, then only moved and shown.
local function PlaceWidget(widget, make, y)
    if not widget then widget = make(SListFrame, y) end
    widget:SetParent(SListFrame)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", S_PAD, y)
    widget:Show()
    return widget
end

local function MenuTextColor(row)
    if row.isActive then row.txt:SetTextColor(1, 0.82, 0) else row.txt:SetTextColor(0.85, 0.85, 0.85) end
end

-- Fills a popup list with one clickable row per name (rows are reused).
-- The row matching activeName is highlighted; onPick(name) runs on click.
local function FillMenu(list, rows, names, rowH, activeName, onPick)
    for _, row in ipairs(rows) do row:Hide() end
    for i, name in ipairs(names) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, list)
            row:SetHeight(rowH)
            row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.txt:SetPoint("LEFT", 6, 0)
            row:SetScript("OnEnter", function() row.txt:SetTextColor(1, 1, 1) end)
            row:SetScript("OnLeave", function() MenuTextColor(row) end)
            rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
        row:SetPoint("RIGHT", -2, 0)
        row.txt:SetText(name)
        row.isActive = (name == activeName)
        MenuTextColor(row)
        row:SetScript("OnClick", function() onPick(name) end)
        row:Show()
    end
    list:SetHeight(2 + rowH * math.max(#names, 1) + 2)
end

-- Boxed dropdown header (label + expand arrow) shared by every dropdown below.
local function MakeDropdownBox(parent, width)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, 24)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    frame.lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.lbl:SetPoint("LEFT",6,0)
    frame.lbl:SetTextColor(0.85,0.85,0.85)

    local arrow = frame:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(10, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(unpack(ns.COL_ACCENT))

    return frame
end

-- Popup list shown under a dropdown; its own frame on UIParent so it can
-- overlap the settings window, and it swallows clicks meant for whatever
-- sits behind it.
local function MakePopupList()
    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetFrameStrata("TOOLTIP")
    list:EnableMouse(true)
    ns.StyleBackdropBox(list, {0.05,0.08,0.09,1})
    list:Hide()
    return list
end

local function MakeDropdown(parent, yOff)
    local frame = MakeDropdownBox(parent, S_W - S_PAD*2 - 40)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)

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
        ns.RefreshHUD()
    end)

    function frame:Refresh()
        local db     = NightsFarmtrackerDB
        local custom = db.tsmCustomSource and db.tsmCustomSource ~= ""
        self.lbl:SetText(db.tsmPriceSource or "DBMarket")
        self.lbl:SetTextColor(custom and 0.40 or 0.85, custom and 0.40 or 0.85, custom and 0.40 or 0.85)
    end

    return frame
end

-- Enter/Escape release focus; the boxed frame around the EditBox is
-- highlighted while it has focus.
local function HookEditBoxFocus(frame, eb)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_ACCENT))
    end)
    eb:SetScript("OnEditFocusLost", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))
    end)
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
    -- userInput is false when RebuildSettingsContent fills the box with
    -- SetText; only react to what the player actually typed (otherwise every
    -- click in Settings would wipe the price cache).
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        NightsFarmtrackerDB.tsmCustomSource = self:GetText()
        if tsmDropdown then tsmDropdown:Refresh() end
        ns.ClearPriceCache()
        ns.RefreshHUD()
    end)
    HookEditBoxFocus(frame, eb)
    frame.eb = eb
    return frame
end

------------------------------------------------------------------------
-- Gear AH threshold config popup: one checkbox per Equipment group
-- (ns.GEAR_THRESHOLD_GROUPS); checked = the threshold applies to it.
-- Lazily built, anchored under the config icon, child of the settings
-- window so it closes with it.
------------------------------------------------------------------------
local TC_ROW_H = 20

function ns.ToggleGearThresholdConfig(anchor)
    local pop = ns.GearThresholdConfigFrame
    if pop and pop:IsShown() then pop:Hide(); return end

    if not pop then
        pop = CreateFrame("Frame", nil, ns.SettingsFrame, "BackdropTemplate")
        pop:SetFrameStrata("TOOLTIP")
        pop:EnableMouse(true)
        ns.ApplyFrameStyle(pop)
        ns.GearThresholdConfigFrame = pop

        local title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetTextColor(unpack(ns.COL_ACCENT))
        title:SetText(ns.L["gear_ah_threshold_config_title"])

        pop.rows = {}
        local width = title:GetStringWidth() + 20
        for i, g in ipairs(ns.GEAR_THRESHOLD_GROUPS) do
            local row = CreateFrame("Frame", nil, pop)
            row:SetHeight(TC_ROW_H)
            row:SetPoint("TOPLEFT", 10, -(26 + (i - 1) * TC_ROW_H))
            row:SetPoint("TOPRIGHT", -10, -(26 + (i - 1) * TC_ROW_H))

            local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
            box:SetSize(14, 14); box:SetPoint("LEFT", 0, 0)
            ns.StyleBackdropBox(box)
            local check = box:CreateTexture(nil, "ARTWORK")
            check:SetPoint("TOPLEFT", 1, -1); check:SetPoint("BOTTOMRIGHT", -1, 1)
            check:SetColorTexture(unpack(ns.COL_ACCENT))

            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
            lbl:SetText(ns.L[g.locKey])
            width = math.max(width, lbl:GetStringWidth() + 14 + 8 + 20)

            local function Refresh()
                if ns.IsGearThresholdGroupEnabled(g.key) then
                    check:Show(); lbl:SetTextColor(1, 0.82, 0)
                else
                    check:Hide(); lbl:SetTextColor(0.85, 0.85, 0.85)
                end
            end
            row.Refresh = Refresh
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function()
                ns.SetGearThresholdGroupEnabled(g.key, not ns.IsGearThresholdGroupEnabled(g.key))
                Refresh()
                ns.RefreshHUD()
            end)
            pop.rows[i] = row
        end
        pop:SetSize(width, 26 + #ns.GEAR_THRESHOLD_GROUPS * TC_ROW_H + 8)
    end

    for _, row in ipairs(pop.rows) do row.Refresh() end
    pop:ClearAllPoints()
    pop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    pop:Show()
end

------------------------------------------------------------------------
-- Helper: boxed numeric input (60 px) with a unit label ("g", "min", "px")
-- next to it. The label lives on the outer list, not inside the bordered box,
-- so it has to be shown/hidden together with the (reused) frame explicitly.
------------------------------------------------------------------------
local function MakeNumberBox(parent, yOff, maxLetters, unitText)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(60, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetSize(48, 18)
    eb:SetPoint("LEFT", 6, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(maxLetters)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetTextColor(0.85, 0.85, 0.85)
    HookEditBoxFocus(frame, eb)

    local unitLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unitLbl:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    unitLbl:SetText(unitText)
    unitLbl:SetTextColor(0.6,0.6,0.6)
    frame.unitLbl = unitLbl
    local baseShow, baseHide = frame.Show, frame.Hide
    frame.Show = function(self) baseShow(self); unitLbl:Show() end
    frame.Hide = function(self) baseHide(self); unitLbl:Hide() end

    frame.eb = eb
    return frame, eb
end

------------------------------------------------------------------------
-- Helper: gear AH threshold (gold) plus the config icon that opens the
-- per-group popup (see ns.ToggleGearThresholdConfig)
------------------------------------------------------------------------
local function MakeGearThresholdEB(parent, yOff)
    local frame, eb = MakeNumberBox(parent, yOff, 7, ns.L["gold_suffix"])
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local gold = tonumber(self:GetText()) or 0
        NightsFarmtrackerDB.gearAHThreshold = gold * 10000
        ns.RefreshHUD()
    end)

    -- Config icon: opens a small popup to pick which Equipment categories
    -- the threshold applies to (see ns.GEAR_THRESHOLD_GROUPS).
    local cfgBtn = CreateFrame("Button", nil, parent)
    cfgBtn:SetSize(16, 16)
    cfgBtn:SetPoint("LEFT", frame.unitLbl, "RIGHT", 8, 0)
    local cfgTex = cfgBtn:CreateTexture(nil, "ARTWORK")
    cfgTex:SetAllPoints()
    cfgTex:SetTexture(ns.ART.."btn_settings.png")
    cfgTex:SetAlpha(0.75)
    ns.RegisterTintTex(cfgTex)
    cfgBtn:SetScript("OnEnter", function(self)
        cfgTex:SetAlpha(1)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(ns.L["gear_ah_threshold_config_title"], 1, 1, 1)
        GameTooltip:AddLine(ns.L["gear_ah_threshold_config_tip"], 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    cfgBtn:SetScript("OnLeave", function() cfgTex:SetAlpha(0.75); GameTooltip:Hide() end)
    cfgBtn:SetScript("OnClick", function(self) ns.ToggleGearThresholdConfig(self) end)

    -- Same sync as the unit label (see MakeNumberBox); hiding also closes the popup.
    local baseShow, baseHide = frame.Show, frame.Hide
    frame.Show = function(self) baseShow(self); cfgBtn:Show() end
    frame.Hide = function(self)
        baseHide(self); cfgBtn:Hide()
        if ns.GearThresholdConfigFrame then ns.GearThresholdConfigFrame:Hide() end
    end
    return frame
end

-- Fixed session length in minutes (0 = off)
local function MakeSessionLengthEB(parent, yOff)
    local frame, eb = MakeNumberBox(parent, yOff, 4, ns.L["minutes_suffix"])
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        NightsFarmtrackerDB.sessionLength = tonumber(self:GetText()) or 0
        ns.UpdateTimerDisplay()
        ns.ApplyPauseVisuals()
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
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    ns.StyleBackdropBox(btn)
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetTextColor(unpack(ns.COL_ACCENT))
    text:SetText(ns.L["export_open_btn"])
    btn:SetSize(text:GetStringWidth() + 20, 20)
    btn:SetScript("OnEnter", function() text:SetTextColor(1,1,1) end)
    btn:SetScript("OnLeave", function() text:SetTextColor(unpack(ns.COL_ACCENT)) end)
    btn:SetScript("OnClick", function() ns.ToggleExportWindow() end)
    return btn
end

local function CloseThemeMenu()
    if themeMenuList then themeMenuList:Hide() end
end

-- Miniature window (frame colors, header strip - flat or gradient depending
-- on the Header gradient option - accent text) used by the theme list's
-- hover preview and by the custom color row. :SetTheme() takes a theme
-- table (bg/border/catBg/accent).
local function MakeThemePreview(parent)
    local pv = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pv:SetSize(150, 40)
    pv:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8x8", tile = true, tileSize = 8, edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1}})
    pv.strip = pv:CreateTexture(nil, "BACKGROUND", nil, 1)
    pv.strip:SetPoint("TOPLEFT", 1, -1); pv.strip:SetPoint("TOPRIGHT", -1, -1)
    pv.strip:SetHeight(18)
    pv.head = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pv.head:SetPoint("LEFT", pv.strip, "LEFT", 5, 0)
    pv.head:SetText(ns.L["custom_preview_header"])
    pv.body = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pv.body:SetPoint("BOTTOMLEFT", 5, 5)
    pv.body:SetTextColor(0.85, 0.85, 0.85)
    pv.body:SetText(ns.L["custom_preview_text"])

    function pv:SetTheme(t)
        self:SetBackdropColor(unpack(t.bg))
        self:SetBackdropBorderColor(unpack(t.border))
        self.head:SetTextColor(unpack(t.accent))
        if NightsFarmtrackerDB.headerGradient then
            local l, r = ns.CatGradient(t)
            self.strip:SetColorTexture(1, 1, 1, 1)
            self.strip:SetGradient("HORIZONTAL", CreateColor(unpack(l)), CreateColor(unpack(r)))
        else
            self.strip:SetColorTexture(unpack(t.catBg))
        end
    end
    return pv
end

-- Theme table for a key; "custom" reflects the saved custom color.
local function ThemeForKey(key)
    local c = NightsFarmtrackerDB.customAccent
    if key == "custom" and type(c) == "table" and c[1] and c[2] and c[3] then
        return ns.DeriveCustomTheme(c[1], c[2], c[3])
    end
    return ns.COLOR_THEMES[key] or ns.COLOR_THEMES.default
end

local function MakeThemeDropdown(parent, yOff)
    local frame = MakeDropdownBox(parent, S_W - S_PAD*2 - 40)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)

    local list = MakePopupList()
    themeMenuList = list

    -- Hover preview: floats beside the list next to the hovered entry
    local popup = MakeThemePreview(UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:Hide()
    list:SetScript("OnHide", function() popup:Hide() end)

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
        -- Color chips (frame border, header, accent) as a quick glance
        row.chips = {}
        for ci = 1, 3 do
            local chip = row:CreateTexture(nil, "ARTWORK")
            chip:SetSize(8, 12)
            chip:SetPoint("LEFT", 6 + (ci-1)*9, 0)
            row.chips[ci] = chip
        end
        function row:PaintChips()
            local t = ThemeForKey(key)
            self.chips[1]:SetColorTexture(t.border[1], t.border[2], t.border[3], 1)
            self.chips[2]:SetColorTexture(t.catBg[1], t.catBg[2], t.catBg[3], 1)
            self.chips[3]:SetColorTexture(t.accent[1], t.accent[2], t.accent[3], 1)
        end
        row:PaintChips()
        row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.txt:SetPoint("LEFT", 6 + 3*9 + 4, 0)
        row.txt:SetText(ThemeLabel(theme))
        row.txt:SetTextColor(0.85,0.85,0.85)
        row:SetScript("OnEnter", function()
            row.txt:SetTextColor(1,1,1)
            popup:SetTheme(ThemeForKey(key))
            popup:ClearAllPoints()
            if (list:GetRight() or 0) + 170 > UIParent:GetWidth() then
                popup:SetPoint("RIGHT", row, "LEFT", -8, 0)
            else
                popup:SetPoint("LEFT", row, "RIGHT", 8, 0)
            end
            popup:Show()
        end)
        row:SetScript("OnLeave", function() row.txt:SetTextColor(0.85,0.85,0.85); popup:Hide() end)
        row:SetScript("OnClick", function()
            local db = NightsFarmtrackerDB
            db.colorTheme = key
            -- First pick of "Custom": start from the current accent color
            if key == "custom" and type(db.customAccent) ~= "table" then
                local a = ns.COL_ACCENT
                db.customAccent = {a[1], a[2], a[3]}
            end
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
        for _, r in ipairs(list.rows) do r:PaintChips() end  -- custom color may have changed
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
-- Helper: custom accent color row (Display section). A swatch opens the
-- Blizzard color picker; the other theme colors are derived from the pick
-- (ns.DeriveCustomTheme). Next to it a small preview frame shows the
-- resulting window/header colors - it updates live while dragging in the
-- picker, but the choice is only saved when the picker is confirmed (OK),
-- followed by the usual reload prompt.
------------------------------------------------------------------------
local customColorRow
local pickerCommit
local pickerHooked

local function MakeCustomColorRow(parent, themeDropdownRef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2 - 40, 44)

    row.lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.lbl:SetPoint("LEFT", 0, 0)
    row.lbl:SetTextColor(0.85, 0.85, 0.85)
    row.lbl:SetText(ns.L["custom_color_label"])

    local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
    swatch:SetSize(24, 24)
    swatch:SetPoint("LEFT", row.lbl, "RIGHT", 8, 0)
    ns.StyleBackdropBox(swatch)
    swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
    swatch.tex:SetPoint("TOPLEFT", 2, -2); swatch.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    row.swatch = swatch

    local pv = MakeThemePreview(row)
    pv:SetPoint("LEFT", swatch, "RIGHT", 14, 0)
    row.preview = pv

    function row:SetPreview(r, g, b)
        swatch.tex:SetColorTexture(r, g, b, 1)
        pv:SetTheme(ns.DeriveCustomTheme(r, g, b))
    end

    local function SavedColor()
        local c = NightsFarmtrackerDB.customAccent
        if type(c) == "table" and c[1] and c[2] and c[3] then return c[1], c[2], c[3] end
        local a = ns.COL_ACCENT
        return a[1], a[2], a[3]
    end

    function row:Refresh()
        self:SetPreview(SavedColor())
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = SavedColor()
        local pending
        local function onChange()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            pending = {nr, ng, nb}
            row:SetPreview(nr, ng, nb)
        end
        pickerCommit = function()
            -- Another addon may have reused the picker in the meantime
            if ColorPickerFrame.swatchFunc ~= onChange or not pending then return end
            local db = NightsFarmtrackerDB
            local old = db.customAccent
            local same = db.colorTheme == "custom" and type(old) == "table"
                and math.abs(old[1] - pending[1]) < 0.002
                and math.abs(old[2] - pending[2]) < 0.002
                and math.abs(old[3] - pending[3]) < 0.002
            db.customAccent = pending
            db.colorTheme   = "custom"
            if themeDropdownRef then themeDropdownRef:Refresh() end
            row:Refresh()
            if not same then StaticPopup_Show("NFT_RELOAD") end
        end
        if not pickerHooked then
            pickerHooked = true
            ColorPickerFrame:HookScript("OnHide", function()
                local fn = pickerCommit
                pickerCommit = nil
                if fn then fn() end
            end)
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = onChange,
            cancelFunc = function() pending = nil; row:Refresh() end,
        })
    end)

    return row
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
    local frame = MakeDropdownBox(parent, S_W - S_PAD*2 - 40)

    local list = MakePopupList()
    profileMenuList = list

    local function RebuildList()
        FillMenu(list, profileMenuRows, ns.GetProfileList(), PROFILE_ROW_H, ns.GetActiveProfileName(), function(name)
            if name ~= ns.GetActiveProfileName() then
                ns.SetActiveProfile(name)
                ns.RebuildSettingsContent()
                StaticPopup_Show("NFT_RELOAD")
            end
            list:Hide()
        end)
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

    local dd = MakeDropdownBox(frame, S_W - S_PAD*2 - 70)
    dd:SetPoint("LEFT", 0, 0)
    dd.lbl:SetPoint("RIGHT", -6, 0)
    dd.lbl:SetJustifyH("LEFT")

    local list = MakePopupList()
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
        FillMenu(list, deleteMenuRows, Candidates(), DELETE_ROW_H, nil, function(name)
            frame.selected = name
            UpdateLabel()
            list:Hide()
        end)
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
    check:SetPoint("TOPLEFT", 1, -1); check:SetPoint("BOTTOMRIGHT", -1, 1)
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
-- Settings content, rebuilt on open and on every change. All widgets are
-- parented to SListFrame (the scroll child) and tracked with their "kind", so
-- the next rebuild releases each one back to its pool instead of leaking
-- frames. Single-instance widgets (tsmDropdown, tsmCustomEB, themeDropdown)
-- are created once and only repositioned.
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

    -- Section title label at y; returns the y below it.
    local function sectionTitle(y, key, step)
        local lbl = track(AcquireSectionLabel(SListFrame), "section")
        lbl:SetPoint("TOPLEFT", S_PAD, y)
        lbl:SetText(ns.L[key])
        return y - step
    end

    -- Grey wrapped hint text at y (full width); returns the FontString so the
    -- caller can size the space below it.
    local function wrappedHint(y, text)
        local fs = track(AcquireWrappedHint(SListFrame), "wrappedHint")
        fs:SetPoint("TOPLEFT", S_PAD, y)
        fs:SetTextColor(0.5,0.5,0.5)
        fs:SetText(text)
        return fs
    end

    local sections = {}
    local function addSection(titleKey, builder)
        sections[#sections + 1] = {titleKey = titleKey, title = ns.L[titleKey], builder = builder}
    end

    -- Grey single-line hint label; the caller moves y down.
    local function hintLabel(x, y, text, gray)
        local fs = track(AcquireHintLabel(SListFrame), "hint")
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetTextColor(gray, gray, gray)
        fs:SetText(text)
    end

    -- Checkbox row at y; returns the y below it.
    local function checkbox(y, labelKey, get, set)
        ConfigureCheckbox(track(AcquireCheckbox(SListFrame), "checkbox"), ns.L[labelKey], y, get, set)
        return y - 38
    end

    -- Checkbox bound to db[key]. With defaultOn an unset value counts as
    -- checked. after(v) runs once the value is stored.
    local function flag(y, labelKey, key, defaultOn, after)
        return checkbox(y, labelKey,
            function()
                if defaultOn then return db[key] ~= false end
                return db[key] == true
            end,
            function(v)
                db[key] = v
                if after then after(v) end
            end)
    end

    -- Radio group, one row per { labelKey, value }; `after` is the space below
    -- the last row. Returns the new y and the rows.
    local function radioGroup(y, options, current, set, after)
        local rows = {}
        for i, opt in ipairs(options) do
            local row = track(AcquireRadio(SListFrame), "radio")
            ConfigureRadio(row, ns.L[opt[1]], y, opt[2], set)
            row:SetSelected(current == opt[2]); row:SetEnabled(true)
            rows[i] = row
            y = y - (i < #options and 24 or after)
        end
        return y, rows
    end

    -- ----------------------------------------------------------------
    -- Section: AH Price Source (includes the Gear AH Threshold sub-block,
    -- which has no header of its own and always follows this section)
    -- ----------------------------------------------------------------
    addSection("ah_source", function(y)
        y = sectionTitle(y, "ah_source", 22)

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
        local function setAH(v) db.ahSource = v; ns.ClearPriceCache(); ns.RefreshHUD() end

        for _, opt in ipairs(ahOptions) do
            local row = track(AcquireRadio(SListFrame), "radio")
            ConfigureRadio(row, opt.label, y, opt.value, setAH)
            row:SetSelected(getAH() == opt.value)
            row:SetEnabled(opt.avail)
            y = y - 24
            if opt.value == "auto" and availableCount > 1 then
                hintLabel(S_PAD + 22, y, ns.L["ah_auto_info"], 0.38)
                y = y - 16
            end
        end

        -- Gear AH Threshold: below this price Equipment skips the AH lookup
        -- and uses its vendor price (0 = off).
        y = y - 4
        local threshHint = wrappedHint(y, ns.L["gear_ah_threshold_hint"])
        y = y - math.max(28, math.ceil(threshHint:GetStringHeight()) + 6)

        gearThresholdEB = PlaceWidget(gearThresholdEB, MakeGearThresholdEB, y)
        local threshGold = math.floor((db.gearAHThreshold or 0) / 10000)
        gearThresholdEB.eb:SetText(threshGold > 0 and tostring(threshGold) or "")
        track(gearThresholdEB, "other")
        y = y - 32

        y = flag(y, "gear_ah_threshold_sound", "gearAHThresholdSound", false)

        -- TSM source block, only if TSM is installed.
        if ns.HasTSM() then
            y = y - 4
            wrappedHint(y, ns.L["tsm_hint"])
            y = y - 28

            tsmDropdown = PlaceWidget(tsmDropdown, MakeDropdown, y)
            tsmDropdown:Refresh()
            track(tsmDropdown, "other")
            y = y - 32

            hintLabel(S_PAD, y, ns.L["tsm_custom"], 0.50)
            y = y - 18

            tsmCustomEB = PlaceWidget(tsmCustomEB, MakeCustomSourceEB, y)
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
        y = sectionTitle(y, "display", 26)

        y = radioGroup(y, { {"gold_per_hour", "hour"}, {"gold_per_min", "min"} },
            db.goldRateMode == "min" and "min" or "hour",
            function(v) db.goldRateMode = v; ns.UpdateGoldRate() end, 32)

        -- Fixed session length (0 = off): the timer counts down and the
        -- session pauses at 0.
        wrappedHint(y, ns.L["session_length_hint"])
        y = y - 28

        sessionLengthEB = PlaceWidget(sessionLengthEB, MakeSessionLengthEB, y)
        local lenMin = tonumber(db.sessionLength) or 0
        sessionLengthEB.eb:SetText(lenMin > 0 and tostring(lenMin) or "")
        track(sessionLengthEB, "other")
        y = y - 40

        -- Max window height: windows grow up to this, then their lists scroll.
        local heightHint = wrappedHint(y, string.format(ns.L["max_window_height_hint"],
            ns.DEFAULT_MAX_WINDOW_H, ns.MIN_MAX_WINDOW_H, ns.MAX_MAX_WINDOW_H))
        y = y - math.ceil(heightHint:GetStringHeight()) - 6

        maxHeightEB = PlaceWidget(maxHeightEB, MakeMaxHeightEB, y)
        maxHeightEB.eb:SetText(tostring(ns.GetMaxWindowH()))
        track(maxHeightEB, "other")
        y = y - 40

        y = radioGroup(y, { {"gold_display_classic", "classic"}, {"gold_display_modern", "modern"} },
            db.goldDisplayMode == "modern" and "modern" or "classic",
            function(v) db.goldDisplayMode = v; ns.RefreshHUD() end, 28)

        y = flag(y, "show_price_source", "showPriceSource", false, function() ns.RefreshHUD() end)
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

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Colors (theme, custom color, header gradient, button tint)
    -- ----------------------------------------------------------------
    addSection("sec_colors", function(y)
        y = sectionTitle(y, "sec_colors", 26)

        themeDropdown = PlaceWidget(themeDropdown, MakeThemeDropdown, y)
        themeDropdown:Refresh()
        track(themeDropdown, "other")
        y = y - 32

        customColorRow = PlaceWidget(customColorRow, function(parent) return MakeCustomColorRow(parent, themeDropdown) end, y)
        customColorRow:Refresh()
        track(customColorRow, "other")
        y = y - 52

        y = flag(y, "header_gradient", "headerGradient", false, function()
            customColorRow:Refresh()
            StaticPopup_Show("NFT_RELOAD")
        end)
        y = flag(y, "themed_buttons", "themedButtons", false, function() ns.RefreshButtonTint() end)

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Profiles
    -- ----------------------------------------------------------------
    addSection("sec_profiles", function(y)
        y = sectionTitle(y, "sec_profiles", 26)

        profileDropdown = PlaceWidget(profileDropdown, MakeProfileDropdown, y)
        profileDropdown:Refresh()
        track(profileDropdown, "other")
        y = y - 30

        profileButtons = PlaceWidget(profileButtons, MakeProfileButtons, y)
        track(profileButtons, "other")
        y = y - 30

        hintLabel(S_PAD, y, ns.L["profile_delete_hint"], 0.50)
        y = y - 18

        deleteProfileRow = PlaceWidget(deleteProfileRow, MakeDeleteProfileRow, y)
        deleteProfileRow:Refresh()
        track(deleteProfileRow, "other")
        y = y - 30

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Session History
    -- ----------------------------------------------------------------
    addSection("session_history", function(y)
        y = sectionTitle(y, "session_history", 26)

        y = flag(y, "session_history_enabled", "sessionHistoryEnabled", true, function() ns.RefreshLeftButtons() end)

        hintLabel(S_PAD, y, ns.L["session_history_mode"], 0.6)
        y = y - 18

        local function getHistMode() return db.sessionHistoryMode == "compact" and "compact" or "full" end
        local rows
        y, rows = radioGroup(y,
            { {"session_history_mode_full", "full"}, {"session_history_mode_compact", "compact"} },
            getHistMode(), function(v) db.sessionHistoryMode = v end, 30)
        -- "compact" folds past months irreversibly: ask first instead of
        -- switching on click.
        rows[2]:SetScript("OnMouseUp", function()
            if getHistMode() ~= "compact" then
                StaticPopup_Show("NFT_CONFIRM_HISTORY_COMPACT")
            end
        end)

        y = flag(y, "merge_daily_sessions", "mergeDaily", true)

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Categories & Grouping
    -- ----------------------------------------------------------------
    addSection("sec_categories", function(y)
        y = sectionTitle(y, "sec_categories", 26)

        y = flag(y, "split_trade_goods", "splitTradeGoods", false, function() ns.RefreshHUD() end)
        y = flag(y, "split_gear_by_binding", "splitGearByBinding", false, function() ns.RefreshHUD() end)
        y = flag(y, "merge_junk_entries", "mergeJunkEntries", false, function() StaticPopup_Show("NFT_RELOAD") end)

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Filters
    -- ----------------------------------------------------------------
    addSection("sec_filters", function(y)
        y = sectionTitle(y, "sec_filters", 26)

        local function filterChanged() ns.RefreshLeftButtons(); ns.RefreshHUD() end
        y = flag(y, "vendor_filter_enabled", "vendorFilterEnabled", true, filterChanged)
        y = flag(y, "blacklist_enabled", "blacklistEnabled", true, filterChanged)

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Fishing
    -- ----------------------------------------------------------------
    addSection("sec_fishing", function(y)
        y = sectionTitle(y, "sec_fishing", 26)

        y = checkbox(y, "venom_tracker_enabled",
            function() return db.venomTrackerEnabled == true end,
            function(v) ns.SetVenomTrackerEnabled(v) end)
        y = checkbox(y, "bait_frame_enabled",
            function() return db.baitFrameEnabled == true end,
            function(v) ns.SetBaitFrameEnabled(v) end)

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Minimap HUD
    -- ----------------------------------------------------------------
    addSection("sec_hud", function(y)
        y = sectionTitle(y, "sec_hud", 26)

        y = checkbox(y, "hud_enabled",
            function() return db.hudEnabled == true end,
            function(v) ns.SetHudEnabled(v) end)

        local hudHint = wrappedHint(y, ns.L["hud_keybind_hint"])
        y = y - math.ceil(hudHint:GetStringHeight()) - 10

        return y
    end)

    -- ----------------------------------------------------------------
    -- Section: Data Export
    -- ----------------------------------------------------------------
    addSection("sec_export", function(y)
        y = sectionTitle(y, "sec_export", 26)

        local exportHint = wrappedHint(y, ns.L["export_hint"])
        -- Button sits 2 px below the (wrapped) hint, however many lines it takes.
        y = y - math.ceil(exportHint:GetStringHeight()) - 2

        exportBtn = PlaceWidget(exportBtn, MakeExportButton, y)
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
    local visH = ns.FitScrollWindow({
        window = SF, scroll = SScrollFrame, list = SListFrame,
        hdrH = S_HDR_H, ftrH = S_FTR_H, contentH = contentH,
    })
    SSidebar:SetHeight(visH)
    SScrollFrame:SetVerticalScroll(math.min(prevScroll, math.max(0, contentH - visH)))
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

    local OnWheel = ns.MakeWheelHandler(SScrollFrame, SListFrame, S_SCROLL_STEP)
    SScrollFrame:SetScript("OnMouseWheel", OnWheel)
    SListFrame:EnableMouseWheel(true)
    SListFrame:SetScript("OnMouseWheel", OnWheel)

    ns.CreateDangerLink(SF, S_PAD, ns.L["reset_addon"], function() StaticPopup_Show("NFT_CONFIRM_RESET_ADDON") end)
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
