------------------------------------------------------------------------
-- Night's Farmtracker - Settings: profiles
-- Profile dropdown, New / Copy / Rename buttons, Delete row and their dialogs.
------------------------------------------------------------------------
local _, ns = ...
local K = ns.SettingsKit

local S_W, S_PAD, TITLE_STEP = K.S_W, K.S_PAD, K.TITLE_STEP
local MakeDropdownBox, MakePopupList = K.MakeDropdownBox, K.MakePopupList
local FillMenu, ToggleMenu = K.FillMenu, K.ToggleMenu

local profileDropdown, profileButtons, deleteProfileRow

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
ns.RegisterConfirmDialog("NFT_PROFILE_DELETE_CONFIRM", ns.L["profile_delete_confirm"], function(_, name)
    local wasActive = (name == ns.GetActiveProfileName())
    if ns.DeleteProfile(name) then
        if wasActive then ns.SetActiveProfile(ns.DEFAULT_PROFILE) end
        ns.RebuildSettingsContent()
        if wasActive then StaticPopup_Show("NFT_RELOAD") end
    end
end)

------------------------------------------------------------------------
-- Helper: dropdown for Profile selection. Rebuilt every time it's opened
-- (unlike the Color Theme list) since profiles can be created, renamed or
-- deleted at any time.
------------------------------------------------------------------------
local profileMenuRows = {}
local PROFILE_ROW_H = 20

local function MakeProfileDropdown(parent)
    local frame = MakeDropdownBox(parent, S_W - S_PAD*2 - 40)

    local list = MakePopupList()

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
    frame:SetScript("OnMouseUp", function() ToggleMenu(list, frame, RebuildList) end)

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
local deleteMenuRows = {}
local DELETE_ROW_H = 20

local function MakeDeleteProfileRow(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(S_W - S_PAD*2, 24)

    local dd = MakeDropdownBox(frame, S_W - S_PAD*2 - 70)
    dd:SetPoint("LEFT", 0, 0)
    dd.lbl:SetPoint("RIGHT", -6, 0)
    dd.lbl:SetJustifyH("LEFT")

    local list = MakePopupList()

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
        ToggleMenu(list, dd, RebuildList)
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
-- Section: Profiles
------------------------------------------------------------------------
K.AddSection("sec_profiles", function(y, ui)
    local track, sectionTitle, hintLabel, place = ui.track, ui.sectionTitle, ui.hintLabel, ui.place
    y = sectionTitle(y, "sec_profiles", TITLE_STEP)

    profileDropdown = place(profileDropdown, MakeProfileDropdown, y)
    profileDropdown:Refresh()
    track(profileDropdown, "other")
    y = y - 30

    profileButtons = place(profileButtons, MakeProfileButtons, y)
    track(profileButtons, "other")
    y = y - 30

    hintLabel(S_PAD, y, ns.L["profile_delete_hint"], 0.50)
    y = y - 18

    deleteProfileRow = place(deleteProfileRow, MakeDeleteProfileRow, y)
    deleteProfileRow:Refresh()
    track(deleteProfileRow, "other")
    y = y - 30

    return y
end)
