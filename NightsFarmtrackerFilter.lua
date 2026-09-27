------------------------------------------------------------------------
-- Night's Farmtracker - Filter
-- Vendor-only filter: drag items from bags here, they will always be
-- valued at vendor price (never AH), account-wide and persistent.
-- Category checkboxes above the drop zone let whole categories be
-- forced to vendor price too - the list mirrors whatever categories are
-- currently shown in the main HUD (ns.CategoryName), so it automatically
-- follows the "split trade goods by subtype" setting: turn that on and
-- e.g. "Metal & Stone"/"Herb" appear here individually instead of one
-- combined "Trade Goods" entry. "Junk" is always shown and defaults to
-- enabled (previously hardcoded; now a normal toggle like any other).
--
-- Structurally a near-mirror of Blacklist.lua; the shared row-rendering
-- logic (category/AH-expansion checkbox sections, drop-list item rows)
-- lives in ns.RebuildCheckboxSection/ns.RebuildDropItemList (Core.lua) so
-- both files only keep their own window layout and data-source wiring.
------------------------------------------------------------------------
local _, ns = ...

local F_W       = ns.FRAME_W
local F_PAD     = ns.PAD
local F_HDR_H   = ns.WINDOW_HDR_H
local ROW_H     = ns.ROW_H
local MAX_VIS_H = 8 * ROW_H
local MIN_VIS_H = 30
local DZ_H      = 34            -- permanent drop-zone height
local F_FTR_H   = 26            -- footer strip height (Clear All button)

-- Category/AH-expansion checkbox sections - row count varies (depends on
-- which categories are currently tracked, the splitTradeGoods setting, and
-- collapse state), so heights below are recomputed on every rebuild.
local CAT_SEC_TOP = F_HDR_H  -- flush against the window's title separator (1px below it, like History/Main HUD)

local FilterFrame, FScrollFrame, FListFrame

StaticPopupDialogs["NFT_CONFIRM_CLEAR_ALL_FILTER"] = {
    text         = ns.L and ns.L["filter_clear_all_confirm"] or "Remove all items from the Vendor-Only Filter? This cannot be undone.",
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function()
        ns.ClearForceVendor()
        ns.RebuildFilterList()
        ns.RefreshHUD()
    end,
    timeout      = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

------------------------------------------------------------------------
-- Category checkbox section (own row pool - see ns.RebuildCheckboxSection)
------------------------------------------------------------------------
local activeCatRows = {}
local catRowPool    = {}

local function RebuildCategorySection()
    local names   = ns.GetTrackedCategoryNames()
    local entries = {}
    for i, name in ipairs(names) do entries[i] = { key = name, label = name } end

    return ns.RebuildCheckboxSection(
        FilterFrame, FilterFrame.catHeader, catRowPool, activeCatRows,
        F_PAD, CAT_SEC_TOP, ns.L["filter_categories_title"],
        NightsFarmtrackerDB.filterCategoriesCollapsed, entries,
        ns.IsForceVendorCategoryEnabled, ns.SetForceVendorCategory, ns.RefreshHUD)
end

------------------------------------------------------------------------
-- AH-by-expansion checkbox section (own row pool). Checked expansions get
-- AH price; if nothing is checked, the filter is inactive and AH works as
-- always (see ns.IsForceVendorExpansion).
------------------------------------------------------------------------
local activeExpRows = {}
local expRowPool    = {}

local function RebuildExpansionSection(secTop)
    local entries = {}
    for i, expID in ipairs(ns.EXPANSION_ORDER) do
        entries[i] = { key = expID, label = ns.EXPANSION_NAMES[expID] or ("Expansion " .. expID) }
    end

    local secEnd = ns.RebuildCheckboxSection(
        FilterFrame, FilterFrame.expHeader, expRowPool, activeExpRows,
        F_PAD, secTop, ns.L["filter_ah_expansions_title"],
        NightsFarmtrackerDB.ahExpansionsCollapsed, entries,
        ns.IsAHExpansionEnabled, ns.SetAHExpansionEnabled, ns.RefreshHUD)

    -- Boundary separator before the drop zone (CreateDropZone has no top
    -- separator of its own, unlike CreateSectionHeader) - same 4+1+4 gap
    -- as Blacklist's catSep.
    FilterFrame.expSep:ClearAllPoints()
    FilterFrame.expSep:SetPoint("TOPLEFT",  F_PAD, -secEnd)
    FilterFrame.expSep:SetPoint("TOPRIGHT", -F_PAD, -secEnd)

    return secEnd + 4 + 1 + 4  -- dzTop
end

------------------------------------------------------------------------
-- Item row pool (Vendor-Only item drop list - see ns.RebuildDropItemList)
------------------------------------------------------------------------
local activeRows = {}
local rowPool    = {}

------------------------------------------------------------------------
-- List rebuild — category section, then AH-by-expansion section, then
-- the drop zone and item list below both.
------------------------------------------------------------------------
function ns.RebuildFilterList()
    if not FListFrame then return end

    local expSecTop = RebuildCategorySection()
    local dzTop     = RebuildExpansionSection(expSecTop)

    FilterFrame.DropZone:ClearAllPoints()
    FilterFrame.DropZone:SetPoint("TOPLEFT",  F_PAD, -dzTop)
    FilterFrame.DropZone:SetPoint("TOPRIGHT", -F_PAD, -dzTop)

    local dzSepTop = dzTop + DZ_H + 4
    FilterFrame.dzSep:ClearAllPoints()
    FilterFrame.dzSep:SetPoint("TOPLEFT",  F_PAD, -dzSepTop)
    FilterFrame.dzSep:SetPoint("TOPRIGHT", -F_PAD, -dzSepTop)

    local listTop = dzSepTop + 1 + 4

    ns.RebuildDropItemList({
        window = FilterFrame, listFrame = FListFrame, scrollFrame = FScrollFrame,
        emptyLabel = FilterFrame.emptyLabel,
        pool = rowPool, rows = activeRows,
        padX = F_PAD, listTop = listTop, ftrH = F_FTR_H,
        minVisH = MIN_VIS_H, maxVisH = MAX_VIS_H,
        items = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.forceVendor,
        onShiftRemove = function(itemID)
            ns.RemoveForceVendor(itemID)
            ns.RebuildFilterList()
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
        ns.AddForceVendor(itemID, name, icon, quality)
        ns.RebuildFilterList()
        ns.RefreshHUD()
    end)
end

------------------------------------------------------------------------
-- Build window (lazy) — only the parts whose position never changes are
-- built here (title, close button, category section title, the drop
-- zone, its separators, and the scroll frame). Actual positioning of
-- everything from the category separator downward happens dynamically
-- in RebuildCategorySection/RebuildFilterList since it depends on how
-- many category checkboxes are currently shown.
------------------------------------------------------------------------
local function EnsureFilterFrame()
    if FilterFrame then return end

    FilterFrame = ns.CreateWindowFrame("NightsFarmtrackerFilterWnd", ns.L["filter_title"], {width = F_W})
    FilterFrame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 4, 0)
    ns.FilterFrame = FilterFrame  -- exposed so other windows (e.g. Log) can anchor next to it

    local hSep = FilterFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT", F_PAD, -(F_HDR_H-1)); hSep:SetPoint("TOPRIGHT", -F_PAD, -(F_HDR_H-1))

    -- accept item drops anywhere on the frame (fallback)
    FilterFrame:SetScript("OnReceiveDrag", HandleDrop)
    FilterFrame:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then HandleDrop() end end)

    -- Category checkbox section header - clickable to collapse/expand,
    -- same interaction pattern AND visual style as the HUD's own category
    -- headers / History's month headers (full-width COL_CAT_BG background,
    -- bottom separator, accent-colored text).
    local catHeader = ns.CreateSectionHeader(FilterFrame, ns.CONTENT_W)
    catHeader:SetPoint("TOPLEFT", F_PAD, -CAT_SEC_TOP)
    catHeader:SetScript("OnMouseUp", function()
        NightsFarmtrackerDB.filterCategoriesCollapsed = not NightsFarmtrackerDB.filterCategoriesCollapsed
        ns.RebuildFilterList()
    end)
    catHeader:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(ns.L["filter_categories_title"],1,1,1)
        GameTooltip:AddLine(ns.L["cat_tip_click"],0.5,0.5,0.5)
        GameTooltip:Show()
    end)
    catHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    FilterFrame.catHeader = catHeader

    -- AH-by-expansion section header - same collapsible pattern as the
    -- category section above (see catHeader for the full comment).
    local expHeader = ns.CreateSectionHeader(FilterFrame, ns.CONTENT_W)
    expHeader:SetScript("OnMouseUp", function()
        NightsFarmtrackerDB.ahExpansionsCollapsed = not NightsFarmtrackerDB.ahExpansionsCollapsed
        ns.RebuildFilterList()
    end)
    expHeader:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(ns.L["filter_ah_expansions_title"],1,1,1)
        GameTooltip:AddLine(ns.L["filter_ah_expansions_hint"],0.5,0.5,0.5,true)
        GameTooltip:AddLine(ns.L["cat_tip_click"],0.5,0.5,0.5)
        GameTooltip:Show()
    end)
    expHeader:SetScript("OnLeave", function() GameTooltip:Hide() end)
    FilterFrame.expHeader = expHeader

    -- Boundary separator between the AH-expansion section and the drop
    -- zone (see RebuildExpansionSection).
    local expSep = FilterFrame:CreateTexture(nil,"ARTWORK"); expSep:SetHeight(1)
    expSep:SetColorTexture(unpack(ns.COL_BORDER))
    FilterFrame.expSep = expSep

    -- Permanent drop zone: always visible target, dashed border, drop here
    local DropZone = ns.CreateDropZone(FilterFrame, DZ_H, HandleDrop)
    FilterFrame.DropZone = DropZone

    -- Separator below drop zone
    local dzSep = FilterFrame:CreateTexture(nil,"ARTWORK"); dzSep:SetHeight(1)
    dzSep:SetColorTexture(unpack(ns.COL_BORDER))
    FilterFrame.dzSep = dzSep

    FScrollFrame = CreateFrame("ScrollFrame", nil, FilterFrame)
    FScrollFrame:SetWidth(ns.CONTENT_W)
    FScrollFrame:EnableMouseWheel(true)

    FListFrame = CreateFrame("Frame", nil, FScrollFrame)
    FListFrame:SetWidth(ns.CONTENT_W); FListFrame:SetHeight(1)
    FListFrame:EnableMouse(true)
    FScrollFrame:SetScrollChild(FListFrame)

    -- list area also accepts drops (convenience)
    FListFrame:SetScript("OnReceiveDrag", HandleDrop)
    FListFrame:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then HandleDrop() end end)

    local function OnWheel(_, delta)
        local cur  = FScrollFrame:GetVerticalScroll()
        local maxS = math.max(0, FListFrame:GetHeight() - FScrollFrame:GetHeight())
        FScrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta*ROW_H, maxS)))
    end
    FScrollFrame:SetScript("OnMouseWheel", OnWheel)
    FListFrame:SetScript("OnMouseWheel", OnWheel)

    FilterFrame.emptyLabel = FilterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    FilterFrame.emptyLabel:SetJustifyH("CENTER")
    FilterFrame.emptyLabel:SetTextColor(0.55,0.55,0.55)
    FilterFrame.emptyLabel:SetText(ns.L["filter_list_empty"])

    FilterFrame.clrBtn = ns.CreateClearAllButton(FilterFrame, F_PAD, function()
        local fv = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.forceVendor
        return fv and next(fv) ~= nil
    end, "NFT_CONFIRM_CLEAR_ALL_FILTER")
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleFilterWindow()
    if ns.DeferInCombat(ns.ToggleFilterWindow) then return end
    EnsureFilterFrame()
    if FilterFrame:IsShown() then
        FilterFrame:Hide()
    else
        ns.RebuildFilterList()
        FilterFrame:Show()
    end
    ns.RefreshWindowChain("right")
end
