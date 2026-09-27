------------------------------------------------------------------------
-- Night's Farmtracker - Blacklist
-- Items/categories dropped here are never tracked at all (account-wide,
-- persistent). Structurally a mirror of the Vendor-Only filter, but
-- inverted: instead of forcing vendor price, it skips tracking entirely.
-- Takes priority over the Vendor-Only filter and everything else.
--
-- The shared row-rendering logic (category checkbox section, drop-list
-- item rows) lives in ns.RebuildCheckboxSection/ns.RebuildDropItemList
-- (Core.lua) so this file only keeps its own window layout and
-- data-source wiring; see Filter.lua for the sibling window (which adds
-- an AH-by-expansion section this one doesn't have).
------------------------------------------------------------------------
local _, ns = ...

local B_W       = ns.FRAME_W
local B_PAD     = ns.PAD
local B_HDR_H   = ns.WINDOW_HDR_H
local ROW_H     = ns.ROW_H
local MAX_VIS_H = 8 * ROW_H
local MIN_VIS_H = 30
local DZ_H      = 34            -- permanent drop-zone height
local B_FTR_H   = 26            -- footer strip height (Clear All button)

-- Category checkbox section - row count varies, recomputed on every rebuild.
local CAT_SEC_TOP = B_HDR_H  -- flush against the window's title separator (1px below it, like History/Main HUD)

local BlacklistFrame, BScrollFrame, BListFrame

StaticPopupDialogs["NFT_CONFIRM_CLEAR_ALL_BLACKLIST"] = {
    text         = ns.L and ns.L["blacklist_clear_all_confirm"] or "Remove all items from the Blacklist? This cannot be undone.",
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function()
        ns.ClearBlacklist()
        ns.RebuildBlacklistList()
        ns.RefreshHUD()
    end,
    timeout      = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

------------------------------------------------------------------------
-- Category checkbox section (own row pool - see ns.RebuildCheckboxSection).
-- Also positions the boundary separator right before the drop zone, since
-- (unlike Filter.lua) nothing else sits between this section and the
-- drop zone.
------------------------------------------------------------------------
local activeCatRows = {}
local catRowPool    = {}

local function RebuildCategorySection()
    local names   = ns.GetTrackedCategoryNames()
    local entries = {}
    for i, name in ipairs(names) do entries[i] = { key = name, label = name } end

    local secEnd = ns.RebuildCheckboxSection(
        BlacklistFrame, BlacklistFrame.catHeader, catRowPool, activeCatRows,
        B_PAD, CAT_SEC_TOP, ns.L["blacklist_categories_title"],
        NightsFarmtrackerDB.blacklistCategoriesCollapsed, entries,
        ns.IsBlacklistCategoryEnabled, ns.SetBlacklistCategory, ns.RefreshHUD)

    BlacklistFrame.catSep:ClearAllPoints()
    BlacklistFrame.catSep:SetPoint("TOPLEFT",  B_PAD, -secEnd)
    BlacklistFrame.catSep:SetPoint("TOPRIGHT", -B_PAD, -secEnd)

    return secEnd + 4 + 1 + 4  -- dzTop
end

------------------------------------------------------------------------
-- Item row pool (Blacklist item drop list - see ns.RebuildDropItemList)
------------------------------------------------------------------------
local activeRows = {}
local rowPool    = {}

------------------------------------------------------------------------
-- List rebuild — category section, then the drop zone and item list.
------------------------------------------------------------------------
function ns.RebuildBlacklistList()
    if not BListFrame then return end

    local dzTop = RebuildCategorySection()

    BlacklistFrame.DropZone:ClearAllPoints()
    BlacklistFrame.DropZone:SetPoint("TOPLEFT",  B_PAD, -dzTop)
    BlacklistFrame.DropZone:SetPoint("TOPRIGHT", -B_PAD, -dzTop)

    local dzSepTop = dzTop + DZ_H + 4
    BlacklistFrame.dzSep:ClearAllPoints()
    BlacklistFrame.dzSep:SetPoint("TOPLEFT",  B_PAD, -dzSepTop)
    BlacklistFrame.dzSep:SetPoint("TOPRIGHT", -B_PAD, -dzSepTop)

    local listTop = dzSepTop + 1 + 4

    ns.RebuildDropItemList({
        window = BlacklistFrame, listFrame = BListFrame, scrollFrame = BScrollFrame,
        emptyLabel = BlacklistFrame.emptyLabel,
        pool = rowPool, rows = activeRows,
        padX = B_PAD, listTop = listTop, ftrH = B_FTR_H,
        minVisH = MIN_VIS_H, maxVisH = MAX_VIS_H,
        items = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.blacklist,
        onShiftRemove = function(itemID)
            ns.RemoveBlacklist(itemID)
            ns.RebuildBlacklistList()
            ns.RefreshHUD()
        end,
    })
end

------------------------------------------------------------------------
-- Drag & drop receiving (item from bags via cursor)
------------------------------------------------------------------------
local function HandleDrop()
    ns.HandleItemDrop(function(itemID, itemLink)
        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink or itemID)
        name = name or ("Item " .. itemID)
        ns.AddBlacklist(itemID, name, icon, quality)
        ns.RebuildBlacklistList()
        ns.RefreshHUD()
    end)
end

------------------------------------------------------------------------
-- Build window (lazy)
------------------------------------------------------------------------
local function EnsureBlacklistFrame()
    if BlacklistFrame then return end

    BlacklistFrame = ns.CreateWindowFrame("NightsFarmtrackerBlacklistWnd", ns.L["blacklist_title"], {width = B_W})
    BlacklistFrame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 4, 0)
    ns.BlacklistFrame = BlacklistFrame  -- exposed so other windows can anchor next to it

    -- accept item drops anywhere on the frame (fallback)
    BlacklistFrame:SetScript("OnReceiveDrag", HandleDrop)
    BlacklistFrame:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then HandleDrop() end end)

    local hSep = BlacklistFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT", B_PAD, -(B_HDR_H-1)); hSep:SetPoint("TOPRIGHT", -B_PAD, -(B_HDR_H-1))

    -- Category checkbox section header - clickable to collapse/expand.
    local catHeader = ns.CreateSectionHeader(BlacklistFrame, ns.CONTENT_W)
    catHeader:SetPoint("TOPLEFT", B_PAD, -CAT_SEC_TOP)
    catHeader:SetScript("OnMouseUp", function()
        NightsFarmtrackerDB.blacklistCategoriesCollapsed = not NightsFarmtrackerDB.blacklistCategoriesCollapsed
        ns.RebuildBlacklistList()
    end)
    catHeader:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(ns.L["blacklist_categories_title"],1,1,1)
        GameTooltip:AddLine(ns.L["cat_tip_click"],0.5,0.5,0.5)
        GameTooltip:Show()
    end)
    catHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BlacklistFrame.catHeader = catHeader

    local catSep = BlacklistFrame:CreateTexture(nil,"ARTWORK"); catSep:SetHeight(1)
    catSep:SetColorTexture(unpack(ns.COL_BORDER))
    BlacklistFrame.catSep = catSep

    -- Permanent drop zone: always visible target, dashed border, drop here
    local DropZone = ns.CreateDropZone(BlacklistFrame, DZ_H, HandleDrop)
    BlacklistFrame.DropZone = DropZone

    -- Separator below drop zone
    local dzSep = BlacklistFrame:CreateTexture(nil,"ARTWORK"); dzSep:SetHeight(1)
    dzSep:SetColorTexture(unpack(ns.COL_BORDER))
    BlacklistFrame.dzSep = dzSep

    BScrollFrame = CreateFrame("ScrollFrame", nil, BlacklistFrame)
    BScrollFrame:SetWidth(ns.CONTENT_W)
    BScrollFrame:EnableMouseWheel(true)

    BListFrame = CreateFrame("Frame", nil, BScrollFrame)
    BListFrame:SetWidth(ns.CONTENT_W); BListFrame:SetHeight(1)
    BListFrame:EnableMouse(true)
    BScrollFrame:SetScrollChild(BListFrame)

    -- list area also accepts drops (convenience)
    BListFrame:SetScript("OnReceiveDrag", HandleDrop)
    BListFrame:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then HandleDrop() end end)

    local function OnWheel(_, delta)
        local cur  = BScrollFrame:GetVerticalScroll()
        local maxS = math.max(0, BListFrame:GetHeight() - BScrollFrame:GetHeight())
        BScrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta*ROW_H, maxS)))
    end
    BScrollFrame:SetScript("OnMouseWheel", OnWheel)
    BListFrame:SetScript("OnMouseWheel", OnWheel)

    BlacklistFrame.emptyLabel = BlacklistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    BlacklistFrame.emptyLabel:SetJustifyH("CENTER")
    BlacklistFrame.emptyLabel:SetTextColor(0.55,0.55,0.55)
    BlacklistFrame.emptyLabel:SetText(ns.L["blacklist_list_empty"])

    BlacklistFrame.clrBtn = ns.CreateClearAllButton(BlacklistFrame, B_PAD, function()
        local bl = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.blacklist
        return bl and next(bl) ~= nil
    end, "NFT_CONFIRM_CLEAR_ALL_BLACKLIST")
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleBlacklistWindow()
    if NightsFarmtrackerDB.blacklistEnabled == false then return end
    if ns.DeferInCombat(ns.ToggleBlacklistWindow) then return end
    EnsureBlacklistFrame()
    if BlacklistFrame:IsShown() then
        BlacklistFrame:Hide()
    else
        ns.RebuildBlacklistList()
        BlacklistFrame:Show()
    end
    ns.RefreshWindowChain("right")
end
