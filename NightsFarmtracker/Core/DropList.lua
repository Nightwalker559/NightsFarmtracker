------------------------------------------------------------------------
-- Night's Farmtracker - Drop list windows
-- Building blocks and the pane factory shared by the tabs of the Filter
-- window (Vendor-Only, Blacklist, Delete List) and Item Goals: collapsible
-- checkbox sections, a drop zone for items dragged from the bags, and an item
-- list grouped by expansion.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Shared collapsible section header (category/expansion-style headers).
-- One recipe for the frame + header band (ns.AddHeaderBand) + accent-colored
-- label used by the Filter window (and matching History's month header), so
-- all of them share one height/font setup instead of slightly different
-- versions that can drift out of sync and render the header text off-center.
-- Caller still positions it (SetPoint) and wires OnMouseUp/OnEnter/OnLeave
-- for its own collapse/tooltip behavior.
------------------------------------------------------------------------
function ns.CreateSectionHeader(parent, width)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(width, ns.CAT_ROW_H)
    header:EnableMouse(true)

    ns.AddHeaderBand(header)

    local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", ns.HEADER_TEXT_X, 0)
    text:SetFontHeight(ns.FONT_NORMAL)
    text:SetTextColor(unpack(ns.COL_ACCENT))
    header.text = text

    return header
end

-- Click-to-collapse plus hover tooltip for a header from CreateSectionHeader:
-- title (locale key), optional extra hint line (locale key), then the
-- "click to collapse" line. onToggle runs on mouse-up.
function ns.WireSectionHeader(header, titleKey, onToggle, hintKey)
    header:SetScript("OnMouseUp", onToggle)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(ns.L[titleKey], 1, 1, 1)
        if hintKey then GameTooltip:AddLine(ns.L[hintKey], 0.5, 0.5, 0.5, true) end
        GameTooltip:AddLine(ns.L["cat_tip_click"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Checkbox row: box, accent-colored mark and label, shared by the category and
-- AH-expansion lists. The caller positions it, sets the label and wires its own
-- OnMouseUp/OnEnter/OnLeave.
------------------------------------------------------------------------
function ns.CreateCheckboxRow(parent, width, height)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(width, height)
    r:EnableMouse(true)

    local box, mark = ns.CreateMarkBox(r, 12)
    box:SetPoint("LEFT", 0, 0)
    r.mark = mark

    local lbl = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
    lbl:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    r.lbl = lbl

    return r
end

------------------------------------------------------------------------
-- Shared "drop-list" item row — icon + name, item
-- tooltip on hover, Shift+Right-click removes it via the given callback.
-- Used by the Filter window's item lists and Item Goals (same row shape; only
-- the removal/rebuild behavior differs).
------------------------------------------------------------------------
function ns.CreateDropListItemRow(parent, onShiftRemove)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(ns.CONTENT_W, ns.ROW_H)
    r:EnableMouse(true)

    ns.AddRowIcon(r):SetPoint("LEFT", ns.ICON_X, 0)

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",  r.icon, "RIGHT", 8, 0)
    r.nameText:SetPoint("RIGHT", r,      "RIGHT", -4, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(ns.FONT_NORMAL)
    r.nameText:SetWordWrap(false)   -- the name gets the whole row width, one line
    r.nameText:SetTextColor(0.85,0.85,0.85)

    r:SetScript("OnEnter", function(self)
        if self.itemID then
            ns.ShowItemTooltipNoCompare(self, "ANCHOR_RIGHT", nil, self.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["filter_tip_shift_rclick"],0.5,0.5,0.5)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" and IsShiftKeyDown() and self.itemID then
            onShiftRemove(self.itemID)
        end
    end)
    return r
end

------------------------------------------------------------------------
-- Shared permanent drop-target zone (dashed accent border, centered hint
-- label) used by the Filter window and Item Goals to accept item drags from
-- bags. onDrop is called for both the real drag-hold-
-- release gesture (OnReceiveDrag) and a left-click while holding an item
-- (OnMouseUp), matching ns.HandleItemDrop's two-script pattern.
------------------------------------------------------------------------
function ns.CreateDropZone(parent, height, onDrop)
    local dz = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dz:SetHeight(height)
    dz:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile     = true, tileSize = 8, edgeSize = 1,
        insets   = {left=1, right=1, top=1, bottom=1},
    })
    dz:SetBackdropColor(unpack(ns.COL_CAT_BG))
    dz:SetBackdropBorderColor(unpack(ns.COL_ACCENT))
    dz:EnableMouse(true)
    ns.EnableItemDrop(dz, onDrop)
    dz:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0) end)
    dz:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(ns.COL_ACCENT)) end)

    dz.label = dz:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dz.label:SetPoint("CENTER")
    dz.label:SetTextColor(unpack(ns.COL_ACCENT))
    dz.label:SetText(ns.L["filter_drop_hint"])

    return dz
end

------------------------------------------------------------------------
-- Scroll frame + list frame pair for the item lists of the Filter window and
-- Item Goals: mouse-wheel scrolling in row steps, item drops accepted on
-- the list area too. Caller sizes/positions the scroll frame (see
-- ns.RebuildDropItemList). Returns scrollFrame, listFrame.
------------------------------------------------------------------------
function ns.CreateDropListScroll(window, onDrop)
    local scrollFrame, listFrame = ns.CreateScrollList(window, ns.CONTENT_W, ns.ROW_H)
    scrollFrame:SetWidth(ns.CONTENT_W)
    listFrame:EnableMouse(true)
    ns.EnableItemDrop(listFrame, onDrop)
    return scrollFrame, listFrame
end

------------------------------------------------------------------------
-- Drop zone plus the separator line below it, at the top of a drop-list
-- window's list (Filter window panes, Item Goals). CreateDropZoneRow
-- builds them once (owner.DropZone, owner.dzSep, owner = the pane or the
-- window); PlaceDropZoneRow puts them at `top` (Y inside listFrame) and
-- returns the Y where the item rows start.
------------------------------------------------------------------------
local DZ_H = 34   -- drop zone height
ns.DROPLIST_MIN_VIS_H = 30   -- room for the "list empty" label
ns.DROPLIST_FTR_H     = 26   -- footer strip (Clear All)

function ns.CreateDropZoneRow(frame, listFrame, onDrop)
    frame.DropZone = ns.CreateDropZone(listFrame, DZ_H, onDrop)
    frame.dzSep = ns.AddHLine(listFrame, "TOP", 0, 0)
end

function ns.PlaceDropZoneRow(frame, top)
    frame.DropZone:ClearAllPoints()
    frame.DropZone:SetPoint("TOPLEFT", 0, -top)
    frame.DropZone:SetPoint("TOPRIGHT", 0, -top)
    local sepTop = top + DZ_H + 4
    frame.dzSep:ClearAllPoints()
    frame.dzSep:SetPoint("TOPLEFT", 0, -sepTop)
    frame.dzSep:SetPoint("TOPRIGHT", 0, -sepTop)
    return sepTop + 1 + 4
end

------------------------------------------------------------------------
-- Collapsible checkbox section: a header above one pooled checkbox row per
-- entry. Arguments: frame (parent of the rows), header (from
-- CreateSectionHeader), rows (this section's active rows), padX, secTop (Y
-- where the section starts), titleText, collapsed, entries ({ key, label }
-- list), isEnabled(key) and setEnabled(key, value), onChanged() (optional).
-- Returns the Y where the next section starts.
------------------------------------------------------------------------
local checkboxRowPool = ns.NewPool(
    function(parent) return ns.CreateCheckboxRow(parent, ns.CONTENT_W, ns.CHECKBOX_ROW_H) end,
    function(r) r:SetScript("OnMouseUp", nil) end)

function ns.RebuildCheckboxSection(frame, header, rows, padX, secTop, titleText, collapsed, entries, isEnabled, setEnabled, onChanged)
    checkboxRowPool.releaseAll(rows)

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", padX, -secTop)
    ns.SetHeaderArrow(header, collapsed)
    header.text:SetText(titleText)

    local n = 0
    if not collapsed then
        n = #entries
        for i, entry in ipairs(entries) do
            local r = checkboxRowPool.acquire(frame)
            r:SetPoint("TOPLEFT", padX, -(secTop + ns.CAT_ROW_H + (i-1) * ns.CHECKBOX_ROW_H))
            r.lbl:SetText(entry.label)

            local function Refresh()
                if isEnabled(entry.key) then
                    r.mark:Show(); r.lbl:SetTextColor(1, 0.82, 0)
                else
                    r.mark:Hide(); r.lbl:SetTextColor(0.85, 0.85, 0.85)
                end
            end
            r:SetScript("OnMouseUp", function()
                setEnabled(entry.key, not isEnabled(entry.key))
                Refresh()
                if onChanged then onChanged() end
            end)
            Refresh()
            rows[#rows + 1] = r
        end
    end

    return secTop + ns.CAT_ROW_H + n * ns.CHECKBOX_ROW_H + 4
end

-- Per-profile table of collapsed item groups (expansionID -> true), created
-- on first use; read fresh on every rebuild so a profile switch is picked up.
function ns.GetCollapsedTable(key)
    local db = NightsFarmtrackerDB
    if type(db[key]) ~= "table" then db[key] = {} end
    return db[key]
end

local UNKNOWN_EXPANSION = -1

-- Header for one expansion group: ns.CreateSectionHeader + a small X button
-- on the right that removes the whole group.
local function CreateItemGroupHeader(parent)
    local h = ns.CreateSectionHeader(parent, ns.CONTENT_W)
    h:SetScript("OnMouseUp", function(self)
        self.collapsed[self.groupKey] = not self.collapsed[self.groupKey] or nil
        self.rebuild()
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(self.groupName, 1, 1, 1)
        GameTooltip:AddLine(ns.L["cat_tip_click"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local x = ns.CreateCloseButton(h, 12, 0.6)
    x:SetPoint("RIGHT", -4, 0)
    x:SetScript("OnClick", function() h.onRemove(h.groupName, h.groupIDs) end)
    x:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(ns.L["group_remove_tip"], 1, 1, 1)
        GameTooltip:Show()
    end)
    x:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return h
end

local groupHeaderPool = ns.NewPool(CreateItemGroupHeader)

------------------------------------------------------------------------
-- Rebuilds the item list below the drop zone: pooled icon + name rows, grouped
-- under one collapsible header per expansion (newest first, unknown last) and
-- sorted by name, plus the scroll area and the "list empty" label. The window
-- grows with its content up to ns.GetMaxWindowH(), then scrolls.
--
-- cfg: window, listFrame, scrollFrame, emptyLabel; itemPool, rows (the
-- window's item row pool, see ns.NewPool, and its active rows); fixedVisH
-- (optional: the list area never gets smaller than this); headers (active
-- group headers); padX; bodyTop (window Y where the scroll area starts);
-- itemsTop (Y inside listFrame where the rows start); ftrH; minVisH (room for
-- the "list empty" label); items (itemID -> { name, icon, quality,
-- expansionID }); collapsed (expansionID -> true, persisted by the caller);
-- rebuild() (re-runs the window rebuild after a collapse); onRemoveGroup(
-- groupName, itemIDs).
------------------------------------------------------------------------
function ns.RebuildDropItemList(cfg)
    local itemPool, rows, headers = cfg.itemPool, cfg.rows, cfg.headers
    itemPool.releaseAll(rows)
    groupHeaderPool.releaseAll(headers)

    -- Bucket by expansion. Older entries have no expansionID: resolve it now and
    -- store it; if the item is not cached yet it goes under "Unknown" and a load
    -- is requested for next time.
    local groups, count = {}, 0
    for itemID, entry in pairs(cfg.items or {}) do
        local exp = entry.expansionID
        if exp == nil then
            exp = select(15, C_Item.GetItemInfo(itemID))
            if exp ~= nil then entry.expansionID = exp
            else C_Item.RequestLoadItemDataByID(itemID) end
        end
        exp = exp or UNKNOWN_EXPANSION
        local g = groups[exp]
        if not g then g = {}; groups[exp] = g end
        g[#g + 1] = { itemID = itemID, name = entry.name, icon = entry.icon, quality = entry.quality }
        count = count + 1
    end

    local order = {}
    for exp in pairs(groups) do order[#order + 1] = exp end
    table.sort(order, function(a, b)
        if a == UNKNOWN_EXPANSION then return false end
        if b == UNKNOWN_EXPANSION then return true end
        return a > b
    end)

    local yOff = cfg.itemsTop
    local flow = ns.NewHeaderFlow(false)   -- the drop zone above has no line of its own
    for _, exp in ipairs(order) do
        local list = groups[exp]
        table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)

        local groupName = exp == UNKNOWN_EXPANSION and ns.L["group_unknown"]
                          or ns.EXPANSION_NAMES[exp] or ("Expansion " .. exp)
        local collapsed = cfg.collapsed[exp]

        local h = groupHeaderPool.acquire(cfg.listFrame)
        h:SetPoint("TOPLEFT", 0, -yOff)
        flow.header(h)
        ns.SetHeaderArrow(h, collapsed)
        h.text:SetText(groupName .. " (" .. #list .. ")")
        h.groupKey, h.groupName, h.collapsed, h.rebuild, h.onRemove = exp, groupName, cfg.collapsed, cfg.rebuild, cfg.onRemoveGroup
        local ids = {}
        for i, e in ipairs(list) do ids[i] = e.itemID end
        h.groupIDs = ids
        headers[#headers + 1] = h
        yOff = yOff + ns.CAT_ROW_H

        if not collapsed then
            yOff = yOff + ns.CAT_GAP
            for _, e in ipairs(list) do
                local r = itemPool.acquire(cfg.listFrame)
                r:SetPoint("TOPLEFT", 0, -yOff)
                r.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
                r.nameText:SetText(ns.DisplayName(e.name, e.itemID) or ("Item " .. e.itemID))
                r.itemID = e.itemID
                ns.ApplyQualityColor(r.nameText, r.iconBorder, e.quality, {0.85, 0.85, 0.85})
                rows[#rows + 1] = r
                yOff = yOff + ns.ROW_H
            end
            yOff = yOff + ns.CAT_GAP
            flow.rows()
        end
    end

    cfg.scrollFrame:ClearAllPoints()
    cfg.scrollFrame:SetPoint("TOPLEFT", cfg.padX, -cfg.bodyTop)

    ns.FitScrollWindow({
        window = cfg.window, scroll = cfg.scrollFrame, list = cfg.listFrame,
        hdrH = cfg.bodyTop, ftrH = cfg.ftrH, minH = cfg.fixedVisH,
        contentH = yOff + (count == 0 and cfg.minVisH or 0),
    })

    cfg.emptyLabel:ClearAllPoints()
    cfg.emptyLabel:SetPoint("TOP", cfg.listFrame, "TOP", 0, -(yOff + 14))
    cfg.emptyLabel:SetShown(count == 0)
end

------------------------------------------------------------------------
-- Pane factory: the content of one tab of the Filter window. The Vendor-Only
-- Filter, the Blacklist and the Delete List are the same pane with different
-- data behind it; Modules/Filter.lua, Blacklist.lua and DeleteList.lua only
-- describe that data (ns.RegisterFilterTab) and Modules/FilterWindow.lua hosts
-- the panes.
--
-- window: the shared window; bodyTop: window Y where the scroll area starts.
-- cfg:
--   itemsKey                 account table: itemID -> { name, icon, quality, expansionID }
--   categoriesKey (optional) account table of per-category switches; without it there are no
--                            category checkboxes (the Delete List)
--   categoriesTitleKey, emptyKey, clearConfirmKey, removeGroupKey   locale keys
--   clearPopup, removeGroupPopup                  StaticPopup names
--   categoriesCollapsedKey, groupsCollapsedKey    collapse state in the character DB
--   isCategoryEnabled, setCategory                category switch accessors (with categoriesKey)
--   add(itemID, name, icon, quality), remove(itemID), clear()
--   expansions (optional)    { titleKey, hintKey, collapsedKey }: AH-by-expansion section
-- Returns pane = { Rebuild(), Show(), Hide(), HandleDrop() }.
------------------------------------------------------------------------
local MIN_VIS_H = ns.DROPLIST_MIN_VIS_H
local FTR_H     = ns.DROPLIST_FTR_H
local SEC_GAP   = 4 + 1 + 4  -- space, separator, space between sections

function ns.CreateDropListPane(window, cfg, bodyTop)
    local pad = ns.PAD
    local pane = {}   -- also carries the drop zone row and the section parts (see ns.CreateDropZoneRow)
    local scrollFrame, listFrame, Rebuild
    local catRows, expRows, itemRows, headers = {}, {}, {}, {}

    local function RefreshAll()
        Rebuild()
        ns.RefreshHUD()
        if ns.RefreshVendorSell then ns.RefreshVendorSell() end   -- the Sell List at a vendor follows the lists
    end

    local function RemoveItem(itemID)
        cfg.remove(itemID)
        RefreshAll()
    end
    local itemPool = ns.NewPool(
        function(parent) return ns.CreateDropListItemRow(parent, RemoveItem) end,
        function(r) r.itemID = nil; r.iconBorder:Hide() end)

    ns.RegisterConfirmDialog(cfg.clearPopup, ns.L[cfg.clearConfirmKey],
        function() cfg.clear(); RefreshAll() end, { preferredIndex = 3 })
    ns.RegisterConfirmDialog(cfg.removeGroupPopup, ns.L[cfg.removeGroupKey],
        function(_, data)
            for _, itemID in ipairs(data.ids) do cfg.remove(itemID) end
            RefreshAll()
        end, { preferredIndex = 3 })

    local function Items()
        return NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB[cfg.itemsKey]
    end

    local function HandleDrop()
        ns.HandleItemDrop(function(itemID, itemLink)
            local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink or itemID)
            cfg.add(itemID, name or ("Item " .. itemID), icon, quality)
            RefreshAll()
        end)
    end

    -- Category checkboxes, then the optional AH-by-expansion list. Returns the
    -- Y where the drop zone starts; a separator closes the last section.
    local function RebuildSections()
        local y = 0
        if cfg.categoriesKey then
            local names = ns.GetTrackedCategoryNames(NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB[cfg.categoriesKey])
            local entries = {}
            for i, name in ipairs(names) do entries[i] = { key = name, label = name } end
            y = ns.RebuildCheckboxSection(
                listFrame, pane.catHeader, catRows, 0, 0, ns.L[cfg.categoriesTitleKey],
                NightsFarmtrackerDB[cfg.categoriesCollapsedKey], entries,
                cfg.isCategoryEnabled, cfg.setCategory, ns.RefreshHUD)
        end

        if cfg.expansions then
            local exps = {}
            for i, expID in ipairs(ns.EXPANSION_ORDER) do
                exps[i] = { key = expID, label = ns.EXPANSION_NAMES[expID] or ("Expansion " .. expID) }
            end
            y = ns.RebuildCheckboxSection(
                listFrame, pane.expHeader, expRows, 0, y, ns.L[cfg.expansions.titleKey],
                NightsFarmtrackerDB[cfg.expansions.collapsedKey], exps,
                ns.IsAHExpansionEnabled, ns.SetAHExpansionEnabled, ns.RefreshHUD)
        end

        if not pane.sectionSep then return 0 end   -- no sections: the drop zone starts at the top
        pane.sectionSep:ClearAllPoints()
        pane.sectionSep:SetPoint("TOPLEFT", 0, -y)
        pane.sectionSep:SetPoint("TOPRIGHT", 0, -y)
        return y + SEC_GAP
    end

    function Rebuild()
        local dzTop = RebuildSections()

        local itemsTop = ns.PlaceDropZoneRow(pane, dzTop)

        ns.RebuildDropItemList({
            window = window, listFrame = listFrame, scrollFrame = scrollFrame, emptyLabel = pane.emptyLabel,
            itemPool = itemPool, rows = itemRows, padX = pad, bodyTop = bodyTop, itemsTop = itemsTop,
            ftrH = FTR_H, minVisH = MIN_VIS_H, items = Items(),
            fixedVisH = ns.GetMaxWindowH() - bodyTop - FTR_H,   -- same window height in every tab
            headers = headers,
            collapsed = ns.GetCollapsedTable(cfg.groupsCollapsedKey),
            rebuild = Rebuild,
            onRemoveGroup = function(groupName, itemIDs)
                StaticPopup_Show(cfg.removeGroupPopup, #itemIDs, groupName, { ids = itemIDs })
            end,
        })
    end

    local function CollapsibleHeader(titleKey, collapsedKey, hintKey)
        local header = ns.CreateSectionHeader(listFrame, ns.CONTENT_W)
        ns.WireSectionHeader(header, titleKey, function()
            NightsFarmtrackerDB[collapsedKey] = not NightsFarmtrackerDB[collapsedKey]
            Rebuild()
        end, hintKey)
        return header
    end

    -- The scroll area holds the whole body, flush below the tab strip. Only
    -- parts whose position never changes are placed here; Rebuild positions
    -- everything below the first section.
    scrollFrame, listFrame = ns.CreateDropListScroll(window, HandleDrop)
    scrollFrame:SetPoint("TOPLEFT", pad, -bodyTop)

    if cfg.categoriesKey then
        pane.catHeader = CollapsibleHeader(cfg.categoriesTitleKey, cfg.categoriesCollapsedKey)
        pane.catHeader:SetPoint("TOPLEFT", 0, 0)
    end
    if cfg.expansions then
        pane.expHeader = CollapsibleHeader(cfg.expansions.titleKey, cfg.expansions.collapsedKey, cfg.expansions.hintKey)
    end
    if cfg.categoriesKey or cfg.expansions then
        pane.sectionSep = ns.AddHLine(listFrame, "TOP", 0, 0)   -- separator lines: Rebuild positions them
    end

    ns.CreateDropZoneRow(pane, listFrame, HandleDrop)

    pane.emptyLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pane.emptyLabel:SetJustifyH("CENTER")
    pane.emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    pane.emptyLabel:SetText(ns.L[cfg.emptyKey])

    pane.clrBtn = ns.CreateClearAllButton(window, pad, function()
        local list = Items()
        return list and next(list) ~= nil
    end, cfg.clearPopup)

    pane.Rebuild, pane.HandleDrop = Rebuild, HandleDrop
    function pane.Show() scrollFrame:Show(); pane.clrBtn:Show() end
    function pane.Hide() scrollFrame:Hide(); pane.clrBtn:Hide() end
    return pane
end
