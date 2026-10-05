------------------------------------------------------------------------
-- Night's Farmtracker - Fishing Lure Bar (optional)
-- Small movable bar of manually-assigned lure slots: drag a lure from
-- your bags onto the bar to add it, click to use it, right-click to
-- remove it (same drag-to-add / right-click-to-remove pattern as the
-- Vendor-Only Filter and Blacklist). Slots persist in NightsFarmtrackerDB
-- per character.
-- Off by default; toggled via Settings -> Fishing or "/nft bait".
------------------------------------------------------------------------
local _, ns = ...

-- Since profession equipment slots (Dragonflight+), the fishing rod sits
-- in its own dedicated tool slot instead of Main Hand.
local FISHING_POLE_SLOT = GetInventorySlotInfo("FISHINGTOOLSLOT")

-- Rough "does this look like a fishing lure" tooltip gate, so dragging in
-- an unrelated item gets rejected instead of silently accepted. Covers
-- the two known tooltip shapes: applied-to-pole lures (mention the pole
-- or fishing skill) and direct-use "chance to catch" baits (need all
-- three words on one line since "chance"/"catch" alone are common). Only
-- DE/EN for now (current localization scope) -- Shift-drag bypasses this
-- entirely for lures it doesn't recognize.
local BAIT_POLE_PHRASES = {
    deDE = { "angelrute", "angelfertigkeit" },
    enUS = { "fishing pole", "fishing skill" },
}
local BAIT_CHANCE_WORDS = {
    deDE = { "chance", "fangen", "min" },
    enUS = { "chance", "catch", "min" },
}
local function LooksLikeLure(link)
    local tooltipData = C_TooltipInfo.GetHyperlink(link)
    if not tooltipData then return false end
    local poleWords   = BAIT_POLE_PHRASES[GetLocale()] or BAIT_POLE_PHRASES.enUS
    local chanceWords = BAIT_CHANCE_WORDS[GetLocale()] or BAIT_CHANCE_WORDS.enUS
    for _, line in ipairs(tooltipData.lines) do
        if line.leftText then
            local text = line.leftText:lower()
            for _, phrase in ipairs(poleWords) do
                if text:find(phrase, 1, true) then return true end
            end
            if text:find(chanceWords[1], 1, true) and text:find(chanceWords[2], 1, true)
                and text:find(chanceWords[3], 1, true) then
                return true
            end
        end
    end
    return false
end

local BaitFrame
local buttonPool = {}
local BTN_SIZE = 30
local BTN_GAP = 4
local BUFF_ROW_H = 16
local RefreshBaitFrame -- forward declaration; defined below, used by drop/remove handlers

-- Small helper to avoid repeating the "if it exists, call it" guard at
-- every call site below (Venom Tracker loads before this file, but stay
-- defensive in case load order ever changes).
local function RepositionVenom()
    if ns.RepositionVenomTracker then ns.RepositionVenomTracker() end
end

------------------------------------------------------------------------
-- Fishing pole check
------------------------------------------------------------------------
-- Anything sitting in the Fishing Rod tool slot is, by definition, the
-- equipped fishing pole (profession equipment slot, see FISHINGTOOLSLOT).
local function HasFishingPoleEquipped()
    if not FISHING_POLE_SLOT then return false end
    return GetInventoryItemLink("player", FISHING_POLE_SLOT) ~= nil
end

------------------------------------------------------------------------
-- Active lure buff (reads it straight off the pole's tooltip, same
-- approach as the Venom Tracker). The line has the shape
-- "Angelköder (+20 Angelfertigkeit) (10 Min.)" -- a label followed by
-- two parenthesised groups (bonus, then duration) -- distinct enough to
-- match locale-independently without needing the exact label text.
------------------------------------------------------------------------
local function ScanActiveLureBuff()
    if not FISHING_POLE_SLOT or not HasFishingPoleEquipped() then return nil end
    local tooltipData = C_TooltipInfo.GetInventoryItem("player", FISHING_POLE_SLOT)
    if not tooltipData then return nil end
    for _, line in ipairs(tooltipData.lines) do
        if line.leftText and line.leftText:match("%(%+%d+.-%)%s*%(.-%)%s*$") then
            return line.leftText
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Manually-assigned slots (persisted per character)
------------------------------------------------------------------------
local function GetBaitSlots()
    NightsFarmtrackerDB.baitSlots = NightsFarmtrackerDB.baitSlots or {}
    return NightsFarmtrackerDB.baitSlots
end

local function AddBaitSlot(itemID, link, icon)
    local slots = GetBaitSlots()
    for _, e in ipairs(slots) do
        if e.itemID == itemID then return end -- already on the bar
    end
    slots[#slots + 1] = {
        itemID = itemID,
        link   = link,
        icon   = icon,
    }
    RefreshBaitFrame()
end

local function RemoveBaitSlot(index)
    table.remove(GetBaitSlots(), index)
    RefreshBaitFrame()
end

------------------------------------------------------------------------
-- Drag & drop receiving (item from bags via cursor)
------------------------------------------------------------------------
local function HandleDrop()
    ns.HandleItemDrop(function(itemID, itemLink)
        if not IsShiftKeyDown() and not LooksLikeLure(itemLink) then
            print("|cff30b0c0Night's Farmtracker:|r " .. ns.L["bait_frame_rejected"])
            return
        end
        AddBaitSlot(itemID, itemLink, C_Item.GetItemIconByID(itemID))
    end)
end

------------------------------------------------------------------------
-- Apply a lure via secure click (left click only, see ConfigureButtonAction
-- below). Applying a lure calls protected functions (item use / macro
-- action) -- Blizzard forbids calling those from a plain Button's OnClick
-- in ways that can taint unpredictably. Fix: build the buttons on
-- SecureActionButtonTemplate and drive the left click purely via secure
-- attributes -- the click itself performs the protected action securely,
-- no Lua call needed. Right click stays a non-secure PostClick used only
-- to remove the slot (never SetScript("OnClick", ...) on a secure button --
-- that replaces its own internal click handler and silently disables the
-- attribute-driven action).
------------------------------------------------------------------------
local function ConfigureButtonAction(btn, entry)
    btn:SetAttribute("type2", nil) -- right click never performs a secure action
    -- Always the same "/use <item>" + "/use <pole slot>" macro for every
    -- lure. Some baits need the second click to actually land the buff on
    -- the pole (old-style "apply to weapon" cursor step); self-buff baits
    -- that don't need it just ignore the harmless extra pole click.
    --
    -- Uses "item:<id>" rather than the raw item hyperlink: the hyperlink's
    -- "[Item Name]" display text is wrapped in square brackets, which the
    -- macro engine's conditional parser (used by /use, /cast, etc.) tries
    -- to read as a "[condition]" like [nomod]/[combat] -- causing "Unknown
    -- macro option: <item name>". item:<id> has no brackets, so it can't
    -- collide with that syntax, and is the standard way to reference a
    -- specific item in a macro/secure attribute.
    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("macrotext1", "/use item:" .. entry.itemID .. "\n/use " .. FISHING_POLE_SLOT)
end

------------------------------------------------------------------------
-- Build (lazy)
------------------------------------------------------------------------
local function ApplyBaitPosition()
    local pos = NightsFarmtrackerDB.baitPos
    BaitFrame:ClearAllPoints()
    if pos then
        BaitFrame:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else
        BaitFrame:SetPoint("BOTTOMRIGHT", ns.MainFrame, "TOPRIGHT", 0, 1)
    end
end

local function AcquireButton(index)
    local btn = buttonPool[index]
    if btn then return btn end

    btn = CreateFrame("Button", nil, BaitFrame, "SecureActionButtonTemplate")
    btn:SetSize(BTN_SIZE, BTN_SIZE)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.countText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.countText:SetPoint("BOTTOMRIGHT", -2, 2)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:AddLine(ns.L["bait_frame_hint"], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- IMPORTANT: never SetScript("OnClick", ...) on a SecureActionButtonTemplate --
    -- that replaces the template's own secure click handler and silently
    -- disables the attribute-driven action (button appears to do nothing).
    -- PreClick/PostClick are separate hooks and don't have this problem.
    btn:SetScript("PostClick", function(self, button)
        if button == "RightButton" then
            -- type2 is nil (see ConfigureButtonAction), so right click never
            -- ran a secure action -- safe to remove the slot here.
            RemoveBaitSlot(self.slotIndex)
        else
            C_Timer.After(0.5, RefreshBaitFrame)
            C_Timer.After(1.5, RefreshBaitFrame)
        end
    end)
    -- Accept item drops directly on a button too (not just empty frame
    -- background), both drag-hold-release and click-to-place methods.
    btn:SetScript("OnReceiveDrag", HandleDrop)
    btn:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then HandleDrop() end
    end)

    buttonPool[index] = btn
    return btn
end

local function EnsureBaitFrame()
    if BaitFrame then return end

    BaitFrame = CreateFrame("Frame", "NightsFarmtrackerBaitFrame", UIParent, "BackdropTemplate")
    BaitFrame:SetSize(ns.FRAME_W, BUFF_ROW_H + BTN_SIZE + 24)
    BaitFrame:SetFrameStrata("MEDIUM")
    BaitFrame:SetClampedToScreen(true)
    BaitFrame:SetMovable(true)
    BaitFrame:EnableMouse(true)
    BaitFrame:RegisterForDrag("LeftButton")
    ns.ApplyFrameStyle(BaitFrame)
    BaitFrame:Hide()
    ns.BaitFrame = BaitFrame

    -- Give it a valid anchor immediately, don't rely solely on the
    -- hidden->shown transition in RefreshBaitFrame (e.g. if that guard
    -- is ever bypassed, the frame would otherwise have zero anchor
    -- points and render detached from MainFrame).
    ApplyBaitPosition()

    -- Accept item drops anywhere on the frame (fallback), same pattern
    -- as the Vendor-Only Filter / Blacklist drop zones -- both the real
    -- drag-hold-release gesture and the click-to-pick-up/click-to-place one.
    BaitFrame:SetScript("OnReceiveDrag", HandleDrop)

    BaitFrame.emptyText = BaitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    BaitFrame.emptyText:SetPoint("CENTER")
    BaitFrame.emptyText:SetTextColor(0.6, 0.6, 0.6)
    BaitFrame.emptyText:SetWidth(ns.FRAME_W - 24)
    BaitFrame.emptyText:SetWordWrap(true)
    BaitFrame.emptyText:SetJustifyH("CENTER")
    BaitFrame.emptyText:SetText(ns.L["bait_frame_empty"])

    BaitFrame.buffText = BaitFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    BaitFrame.buffText:SetPoint("TOP", 0, -8)
    BaitFrame.buffText:SetFontHeight(ns.FONT_NORMAL)
    BaitFrame.buffText:SetTextColor(unpack(ns.COL_ACCENT))
    BaitFrame.buffText:SetWidth(ns.FRAME_W - 40)
    BaitFrame.buffText:SetWordWrap(true)
    BaitFrame.buffText:SetJustifyH("CENTER")

    BaitFrame.closeButton = ns.MakeBtn(BaitFrame, 14, "btn_close.png")
    BaitFrame.closeButton:SetPoint("TOPRIGHT", -4, -4)
    BaitFrame.closeButton:SetScript("OnClick", function()
        -- Closing via X fully disables the bar, keeping the Settings
        -- checkbox in sync instead of just hiding it for the session.
        ns.SetBaitFrameEnabled(false)
    end)

    BaitFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    BaitFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local top, left, right = self:GetTop(), self:GetLeft(), self:GetRight()
        local uiTop, uiWidth    = UIParent:GetTop(), UIParent:GetWidth()
        if top and left and right and uiTop and uiWidth then
            local offsetY = top - uiTop
            local offsetX = (left + right) / 2 - uiWidth / 2
            NightsFarmtrackerDB.baitPos = { "TOP", offsetX, offsetY }
            self:ClearAllPoints()
            self:SetPoint("TOP", UIParent, "TOP", offsetX, offsetY)
        end
    end)

    BaitFrame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            NightsFarmtrackerDB.baitPos = nil
            ApplyBaitPosition()
        elseif button == "LeftButton" then
            HandleDrop()
        end
    end)
end

------------------------------------------------------------------------
-- Combat-safe hide. BaitFrame can parent a SecureActionButtonTemplate
-- lure button (see AcquireButton above), so hiding it directly during
-- combat throws ADDON_ACTION_BLOCKED. Defer to PLAYER_REGEN_ENABLED
-- instead of failing silently.
------------------------------------------------------------------------
local pendingHide = false

local function SafeHideBaitFrame()
    if not BaitFrame then return end
    if InCombatLockdown() then
        pendingHide = true
        return
    end
    BaitFrame:Hide()
end
ns.SafeHideBaitFrame = SafeHideBaitFrame

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function RefreshBaitFrame()
    if NightsFarmtrackerDB.baitFrameEnabled ~= true then return end
    -- Bail out entirely in combat: this function calls Hide()/Show()/
    -- SetPoint() on the SecureActionButtonTemplate lure buttons (see
    -- AcquireButton), which throws ADDON_ACTION_BLOCKED if touched during
    -- combat lockdown. PLAYER_REGEN_ENABLED (watcher below) re-runs a full
    -- refresh right after combat ends, so nothing is missed.
    if InCombatLockdown() then return end
    EnsureBaitFrame()
    if not ns.MainFrame or not ns.MainFrame:IsShown() then
        SafeHideBaitFrame()
        RepositionVenom()
        return
    end
    if NightsFarmtrackerDB.baitUserHidden then
        SafeHideBaitFrame()
        RepositionVenom()
        return
    end

    local slots = GetBaitSlots()

    local buffLine = ScanActiveLureBuff()
    BaitFrame.buffText:SetText(buffLine or ns.L["bait_no_active_buff"])
    local buffHeight = math.max(BUFF_ROW_H, BaitFrame.buffText:GetStringHeight() + 4)

    for _, btn in pairs(buttonPool) do btn:Hide() end

    BaitFrame:SetWidth(ns.FRAME_W)
    local rowTop = -(8 + buffHeight)

    if #slots == 0 then
        BaitFrame.emptyText:ClearAllPoints()
        BaitFrame.emptyText:SetPoint("TOP", 0, rowTop - 4)
        BaitFrame.emptyText:Show()
        BaitFrame:SetHeight(buffHeight + 16 + 28)
    else
        BaitFrame.emptyText:Hide()
        -- Fixed frame width -> wrap icons into rows, growing upward
        -- (the frame is bottom-anchored so SetHeight extends the top).
        local usableW  = ns.FRAME_W - 16
        local perRow   = math.max(1, math.floor((usableW + BTN_GAP) / (BTN_SIZE + BTN_GAP)))
        local numRows  = math.ceil(#slots / perRow)

        -- Display order only (sorted by current bag count, most first);
        -- the underlying slots table keeps its original order so
        -- RemoveBaitSlot's index-based removal is unaffected.
        local order = {}
        for i = 1, #slots do order[i] = i end
        table.sort(order, function(a, b)
            local ca = C_Item.GetItemCount(slots[a].itemID) or 0
            local cb = C_Item.GetItemCount(slots[b].itemID) or 0
            if ca ~= cb then return ca > cb end
            return a < b -- stable tie-break
        end)

        for pos, idx in ipairs(order) do
            local entry = slots[idx]
            local row = math.floor((pos - 1) / perRow)
            local col = (pos - 1) % perRow
            local btn = AcquireButton(idx)
            btn.slotIndex = idx
            btn.link = entry.link
            ConfigureButtonAction(btn, entry)
            btn.icon:SetTexture(entry.icon or ns.FALLBACK_ICON)
            local count = C_Item.GetItemCount(entry.itemID) or 0
            btn.countText:SetText(count > 1 and count or "")
            -- Gray out lures no longer in the bags (owned count is 0).
            btn.icon:SetDesaturated(count == 0)
            if count == 0 then
                btn.icon:SetVertexColor(0.5, 0.5, 0.5)
            else
                btn.icon:SetVertexColor(1, 1, 1)
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 8 + col * (BTN_SIZE + BTN_GAP), rowTop - row * (BTN_SIZE + BTN_GAP))
            btn:Show()
        end
        BaitFrame:SetHeight(buffHeight + numRows * BTN_SIZE + (numRows - 1) * BTN_GAP + 24)
    end

    if not BaitFrame:IsShown() then
        ApplyBaitPosition()
        BaitFrame:Show()
    end

    -- Bait Frame's shown state or height may have changed; let the Venom
    -- Tracker re-dock above it (or back to MainFrame) if needed.
    RepositionVenom()

    -- Keep the countdown/counts roughly current while the bar is visible.
    if not BaitFrame.ticker then
        BaitFrame.ticker = C_Timer.NewTicker(20, function()
            if BaitFrame:IsShown() then RefreshBaitFrame() end
        end)
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")   -- always: completes a hide deferred during combat

-- Equipment and bag events are only needed while the bar is enabled
-- (BAG_UPDATE_DELAYED fires on every loot/vendor/bank action).
local function UpdateWatcher()
    if NightsFarmtrackerDB and NightsFarmtrackerDB.baitFrameEnabled == true then
        watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    else
        watcher:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
        watcher:UnregisterEvent("BAG_UPDATE_DELAYED")
    end
end

watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then UpdateWatcher() end
    if event == "PLAYER_REGEN_ENABLED" and pendingHide then
        pendingHide = false
        SafeHideBaitFrame()
    end
    if not NightsFarmtrackerDB or NightsFarmtrackerDB.baitFrameEnabled ~= true then return end
    RefreshBaitFrame()
end)

if ns.MainFrame then
    ns.MainFrame:HookScript("OnShow", RefreshBaitFrame)
end

------------------------------------------------------------------------
-- Public API (called from Settings / slash command)
------------------------------------------------------------------------
function ns.SetBaitFrameEnabled(enabled)
    NightsFarmtrackerDB.baitFrameEnabled = enabled and true or false
    UpdateWatcher()
    if enabled then
        NightsFarmtrackerDB.baitUserHidden = false
        EnsureBaitFrame()
        RefreshBaitFrame()
    elseif BaitFrame then
        SafeHideBaitFrame()
        if BaitFrame.ticker then
            BaitFrame.ticker:Cancel()
            BaitFrame.ticker = nil
        end
        RepositionVenom()
    end
end

function ns.ToggleBaitFrame()
    if NightsFarmtrackerDB.baitFrameEnabled ~= true then
        print("|cff30b0c0Night's Farmtracker:|r Fishing Lure Bar is disabled in Settings -> Fishing.")
        return
    end
    NightsFarmtrackerDB.baitUserHidden = not NightsFarmtrackerDB.baitUserHidden
    if NightsFarmtrackerDB.baitUserHidden then
        SafeHideBaitFrame()
        RepositionVenom()
    else
        EnsureBaitFrame()
        RefreshBaitFrame()
    end
end
