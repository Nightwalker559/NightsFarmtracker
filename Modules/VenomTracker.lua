------------------------------------------------------------------------
-- Night's Farmtracker - Coiled Huntress Venom Tracker (optional)
-- Small movable overlay showing the Venom/Toxin stack on the equipped
-- "The Coiled Huntress" fishing rod (item 244790) and the Coiled
-- Filament currency (id 3546). Blizzard only exposes the venom value
-- inside the item tooltip, so it's scanned and mirrored here.
-- Off by default; toggled via Settings -> Fishing.
------------------------------------------------------------------------
local _, ns = ...

local ITEM_ID     = 244790 -- The Coiled Huntress
local CURRENCY_ID = 3546   -- Coiled Filament

-- Tooltip keyword used to find the venom line; depends on client locale.
local LOCALE_KEYWORDS = { deDE = "Toxin", enUS = "Venom", enGB = "Venom" }
local LABEL = LOCALE_KEYWORDS[GetLocale()] or "Venom"

local VenomFrame
local MIN_WIDTH = 150
local WIDTH_PADDING = 24

------------------------------------------------------------------------
-- Build (lazy)
------------------------------------------------------------------------
local function ApplyVenomPosition()
    local pos = NightsFarmtrackerDB.venomPos
    VenomFrame:ClearAllPoints()
    if pos then
        VenomFrame:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    elseif ns.BaitFrame and ns.BaitFrame:IsShown() then
        -- Dock above the Fishing Lure Bar when it's visible, so the two
        -- fishing-related frames don't overlap.
        VenomFrame:SetPoint("BOTTOMLEFT", ns.BaitFrame, "TOPLEFT", 0, 1)
    else
        -- Default: docked above the main frame.
        VenomFrame:SetPoint("BOTTOMLEFT", ns.MainFrame, "TOPLEFT", 0, 1)
    end
end

-- Re-applies the default (non-custom) anchor. Called by the Bait Frame
-- whenever its own visibility/size changes, so the Venom Tracker follows
-- it instead of overlapping.
function ns.RepositionVenomTracker()
    if VenomFrame and VenomFrame:IsShown() then
        ApplyVenomPosition()
    end
end

local function EnsureVenomFrame()
    if VenomFrame then return end

    VenomFrame = CreateFrame("Frame", "NightsFarmtrackerVenomFrame", UIParent, "BackdropTemplate")
    VenomFrame:SetSize(150, 44)
    VenomFrame:SetFrameStrata("MEDIUM")
    VenomFrame:SetClampedToScreen(true)
    VenomFrame:SetMovable(true)
    VenomFrame:EnableMouse(true)
    VenomFrame:RegisterForDrag("LeftButton")
    ns.ApplyFrameStyle(VenomFrame)
    VenomFrame:Hide()
    ns.VenomFrame = VenomFrame

    -- Give it a valid anchor immediately, same rationale as the Bait
    -- Frame: don't rely solely on the hidden->shown transition in
    -- ScanVenom for the frame's very first anchor point.
    ApplyVenomPosition()

    VenomFrame.venomText = VenomFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    VenomFrame.venomText:SetPoint("TOP", 0, -8)
    VenomFrame.venomText:SetFontHeight(ns.FONT_NORMAL)
    VenomFrame.venomText:SetTextColor(unpack(ns.COL_ACCENT))
    VenomFrame.venomText:SetText(LABEL .. ": n/a")

    VenomFrame.currencyText = VenomFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    VenomFrame.currencyText:SetPoint("BOTTOM", 0, 8)
    VenomFrame.currencyText:SetFontHeight(ns.FONT_NORMAL)
    VenomFrame.currencyText:SetTextColor(unpack(ns.COL_GOLD))
    VenomFrame.currencyText:SetText("...")

    VenomFrame.closeButton = ns.MakeBtn(VenomFrame, 14, "btn_close.png")
    VenomFrame.closeButton:SetPoint("TOPRIGHT", -4, -4)
    VenomFrame.closeButton:SetScript("OnClick", function()
        -- Closing via X fully disables the bar, keeping the Settings
        -- checkbox in sync instead of just hiding it for the session.
        ns.SetVenomTrackerEnabled(false)
    end)

    VenomFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    VenomFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Normalize to a "TOP"/UIParent anchor (same approach as MainFrame)
        -- so the saved position stays independent of MainFrame afterwards.
        local top, left, right = self:GetTop(), self:GetLeft(), self:GetRight()
        local uiTop, uiWidth    = UIParent:GetTop(), UIParent:GetWidth()
        if top and left and right and uiTop and uiWidth then
            local offsetY = top - uiTop
            local offsetX = (left + right) / 2 - uiWidth / 2
            NightsFarmtrackerDB.venomPos = { "TOP", offsetX, offsetY }
            self:ClearAllPoints()
            self:SetPoint("TOP", UIParent, "TOP", offsetX, offsetY)
        end
    end)

    VenomFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            NightsFarmtrackerDB.venomPos = nil
            ApplyVenomPosition()
        end
    end)

    VenomFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.L["venom_tracker_title"])
        GameTooltip:AddLine(ns.L["venom_tracker_hint"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    VenomFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Scan
------------------------------------------------------------------------
local function FindItemSlot()
    for slot = 1, 40 do
        if GetInventoryItemID("player", slot) == ITEM_ID then
            return slot
        end
    end
    return nil
end

local function ExtractVenomFromLine(line)
    if line:find(LABEL) then
        local number = line:match("(%d+)")
        if number then return tonumber(number) end
    end
    return nil
end

local function UpdateVenomFrameWidth()
    local needed = math.max(VenomFrame.venomText:GetStringWidth(), VenomFrame.currencyText:GetStringWidth()) + WIDTH_PADDING
    VenomFrame:SetWidth(math.max(MIN_WIDTH, needed))
end

local function ScanCurrency()
    if not VenomFrame or NightsFarmtrackerDB.venomTrackerEnabled ~= true then return end
    local info = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_ID)
    if info then
        VenomFrame.currencyText:SetText(info.name .. ": " .. info.quantity)
        UpdateVenomFrameWidth()
    end
end

local function ScanVenom()
    if NightsFarmtrackerDB.venomTrackerEnabled ~= true then return end
    -- Bail out entirely in combat: VenomFrame:Show()/Hide() can throw
    -- ADDON_ACTION_BLOCKED during combat lockdown (same shared-execution
    -- taint as BaitFrame, see Modules/BaitFrame.lua). The
    -- PLAYER_REGEN_ENABLED watcher below re-scans right after combat ends.
    if InCombatLockdown() then return end
    if not ns.MainFrame or not ns.MainFrame:IsShown() then
        if VenomFrame then VenomFrame:Hide() end
        return
    end
    EnsureVenomFrame()

    local slot = FindItemSlot()
    if not slot then
        VenomFrame:Hide()
        return
    end

    if NightsFarmtrackerDB.venomUserHidden then
        VenomFrame:Hide()
        return
    end

    if not VenomFrame:IsShown() then
        ApplyVenomPosition()
        VenomFrame:Show()
    end

    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot)
    if not tooltipData then return end

    for _, line in ipairs(tooltipData.lines) do
        if line.leftText then
            local value = ExtractVenomFromLine(line.leftText)
            if value then
                VenomFrame.venomText:SetText(LABEL .. ": " .. value)
                UpdateVenomFrameWidth()
                return
            end
        end
    end
    -- No line matched the locale keyword: this is NOT the same as "0
    -- venom" (that only happens if the keyword line exists but has no
    -- number). Showing "0" here would be misleading if the keyword is
    -- wrong, so surface it as unknown and warn once per session.
    VenomFrame.venomText:SetText(LABEL .. ": n/a")
    UpdateVenomFrameWidth()
    if not NightsFarmtrackerDB.venomWarnedLocaleMismatch then
        NightsFarmtrackerDB.venomWarnedLocaleMismatch = true
        print("|cff30b0c0Night's Farmtracker:|r couldn't find '" .. LABEL ..
            "' in the tooltip for locale " .. GetLocale() ..
            ". Use /nft venomdump to inspect the raw tooltip lines.")
    end
end

-- Prints all tooltip lines of the equipped item to chat, used to debug a
-- locale keyword mismatch.
function ns.DumpVenomTooltip()
    local slot = FindItemSlot()
    if not slot then
        print("|cff30b0c0Night's Farmtracker:|r Coiled Huntress not equipped.")
        return
    end
    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slot)
    if not tooltipData then return end
    print("|cff30b0c0Night's Farmtracker|r venom tooltip dump:")
    for i, line in ipairs(tooltipData.lines) do
        print(i .. ": " .. (line.leftText or ""))
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")

-- The tracker's events are only registered while the feature is enabled, so
-- a disabled tracker costs nothing at all (UNIT_SPELLCAST_SUCCEEDED and
-- CURRENCY_DISPLAY_UPDATE fire constantly). The cast event is limited to
-- the player: the unfiltered event also fires for every nameplate/party
-- unit.
local function UpdateWatcher()
    if NightsFarmtrackerDB and NightsFarmtrackerDB.venomTrackerEnabled == true then
        watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        watcher:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        watcher:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
        watcher:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        watcher:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
        watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

-- Tooltip data (C_TooltipInfo) can briefly lag behind the actual value
-- right after an event fires (e.g. right after a catch), so a scan
-- triggered immediately can still show the previous number. Re-scan a
-- couple of times shortly after to catch the updated value.
local function ScanVenomDelayed()
    ScanVenom()
    C_Timer.After(0.5, ScanVenom)
    C_Timer.After(1.5, ScanVenom)
end

watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then UpdateWatcher() end
    if not NightsFarmtrackerDB or NightsFarmtrackerDB.venomTrackerEnabled ~= true then return end
    if event == "PLAYER_REGEN_ENABLED" then
        ScanVenom()
        ScanCurrency()
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- every spell the player casts lands here; only a catch with the
        -- rod equipped can change the venom value
        if unit ~= "player" or not FindItemSlot() then return end
    end
    if event == "CURRENCY_DISPLAY_UPDATE" then
        ScanCurrency()
        return
    end
    ScanVenomDelayed()
    ScanCurrency()
end)

-- Re-show the overlay when the main window reopens (it's force-hidden
-- together with MainFrame, see MainFrame:HookScript("OnHide", ...) in
-- Core/UI.lua).
if ns.MainFrame then
    ns.MainFrame:HookScript("OnShow", function()
        ScanVenom()
        ScanCurrency()
    end)
end

------------------------------------------------------------------------
-- Public API (called from Settings)
------------------------------------------------------------------------
function ns.SetVenomTrackerEnabled(enabled)
    NightsFarmtrackerDB.venomTrackerEnabled = enabled and true or false
    UpdateWatcher()
    if enabled then
        NightsFarmtrackerDB.venomUserHidden = false
        EnsureVenomFrame()
        ScanVenom()
        ScanCurrency()
    elseif VenomFrame then
        if not ns.DeferInCombat(function() VenomFrame:Hide() end) then VenomFrame:Hide() end
    end
end

-- Toggle overlay visibility without touching the Settings checkbox,
-- used by "/nft venom".
function ns.ToggleVenomTracker()
    if NightsFarmtrackerDB.venomTrackerEnabled ~= true then
        print("|cff30b0c0Night's Farmtracker:|r Venom Tracker is disabled in Settings -> Fishing.")
        return
    end
    if ns.DeferInCombat(ns.ToggleVenomTracker) then return end
    NightsFarmtrackerDB.venomUserHidden = not NightsFarmtrackerDB.venomUserHidden
    if NightsFarmtrackerDB.venomUserHidden then
        if VenomFrame then VenomFrame:Hide() end
    else
        ScanVenom()
        ScanCurrency()
    end
end
