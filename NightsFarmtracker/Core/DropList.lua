------------------------------------------------------------------------
-- Night's Farmtracker - Drop list windows
-- Building blocks and the window factory shared by the Vendor-Only Filter
-- and the Blacklist: collapsible checkbox sections, a drop zone for items
-- dragged from the bags, and an item list grouped by expansion.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Shared collapsible section header (category/expansion-style headers).
-- One recipe for the frame + header band (ns.AddHeaderBand) + accent-colored
-- label used by the Filter and Blacklist windows (and matching History's month
-- header), so all of them share one height/font setup instead of each file
-- rebuilding slightly different versions that can drift out of sync (that
-- mismatch is what caused the header text to render off-center in 1.4.x).
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
-- Used by the Vendor-Only Filter and Blacklist item lists (identical row
-- shape; only the removal/rebuild behavior differs between the two).
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
-- label) used by the Vendor-Only Filter and Blacklist windows to accept
-- item drags from bags. onDrop is called for both the real drag-hold-
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
-- Scroll frame + list frame pair for the Vendor-Only Filter / Blacklist
-- item lists: mouse-wheel scrolling in row steps, item drops accepted on
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
-- window's list (Filter, Blacklist, Item Goals). CreateDropZoneRow builds them
-- once (frame.DropZone, frame.dzSep); PlaceDropZoneRow puts them at `top` (Y
-- inside listFrame) and returns the Y where the item rows start.
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
-- window's item row pool, see ns.NewPool, and its active rows); headers (active
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
                r.nameText:SetText(ns.TruncateName(ns.DisplayName(e.name, e.itemID) or ("Item " .. e.itemID)))
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
        hdrH = cfg.bodyTop, ftrH = cfg.ftrH,
        contentH = yOff + (count == 0 and cfg.minVisH or 0),
    })

    cfg.emptyLabel:ClearAllPoints()
    cfg.emptyLabel:SetPoint("TOP", cfg.listFrame, "TOP", 0, -(yOff + 14))
    cfg.emptyLabel:SetShown(count == 0)
end

------------------------------------------------------------------------
-- Window factory. The Vendor-Only Filter and the Blacklist are the same
-- window with different data behind it; Modules/Filter.lua and
-- Modules/Blacklist.lua only describe that data here.
--
-- cfg:
--   frameName, frameKey      global frame name / ns.<frameKey>
--   rebuildKey, toggleKey    names of the ns functions this call defines
--   enabledKey               setting that switches the feature off
--   itemsKey                 account table: itemID -> { name, icon, quality, expansionID }
--   categoriesKey            account table of per-category switches
--   titleKey, categoriesTitleKey, emptyKey, clearConfirmKey, removeGroupKey   locale keys
--   clearPopup, removeGroupPopup                  StaticPopup names
--   categoriesCollapsedKey, groupsCollapsedKey    collapse state in the character DB
--   isCategoryEnabled, setCategory                category switch accessors
--   add(itemID, name, icon, quality), remove(itemID), clear()
--   expansions (optional)    { titleKey, hintKey, collapsedKey }: AH-by-expansion section
------------------------------------------------------------------------
local MIN_VIS_H = ns.DROPLIST_MIN_VIS_H
local FTR_H     = ns.DROPLIST_FTR_H
local SEC_GAP   = 4 + 1 + 4  -- space, separator, space between sections

function ns.CreateDropListWindow(cfg)
    local pad, hdrH = ns.PAD, ns.WINDOW_HDR_H
    local frame, scrollFrame, listFrame, Rebuild
    local catRows, expRows, itemRows, headers = {}, {}, {}, {}

    local function RefreshAll()
        Rebuild()
        ns.RefreshHUD()
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
        local names = ns.GetTrackedCategoryNames(NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB[cfg.categoriesKey])
        local entries = {}
        for i, name in ipairs(names) do entries[i] = { key = name, label = name } end
        local y = ns.RebuildCheckboxSection(
            listFrame, frame.catHeader, catRows, 0, 0, ns.L[cfg.categoriesTitleKey],
            NightsFarmtrackerDB[cfg.categoriesCollapsedKey], entries,
            cfg.isCategoryEnabled, cfg.setCategory, ns.RefreshHUD)

        if cfg.expansions then
            local exps = {}
            for i, expID in ipairs(ns.EXPANSION_ORDER) do
                exps[i] = { key = expID, label = ns.EXPANSION_NAMES[expID] or ("Expansion " .. expID) }
            end
            y = ns.RebuildCheckboxSection(
                listFrame, frame.expHeader, expRows, 0, y, ns.L[cfg.expansions.titleKey],
                NightsFarmtrackerDB[cfg.expansions.collapsedKey], exps,
                ns.IsAHExpansionEnabled, ns.SetAHExpansionEnabled, ns.RefreshHUD)
        end

        frame.sectionSep:ClearAllPoints()
        frame.sectionSep:SetPoint("TOPLEFT", 0, -y)
        frame.sectionSep:SetPoint("TOPRIGHT", 0, -y)
        return y + SEC_GAP
    end

    function Rebuild()
        if not listFrame then return end
        local dzTop = RebuildSections()

        local itemsTop = ns.PlaceDropZoneRow(frame, dzTop)

        ns.RebuildDropItemList({
            window = frame, listFrame = listFrame, scrollFrame = scrollFrame, emptyLabel = frame.emptyLabel,
            itemPool = itemPool, rows = itemRows, padX = pad, bodyTop = hdrH, itemsTop = itemsTop,
            ftrH = FTR_H, minVisH = MIN_VIS_H, items = Items(),
            headers = headers,
            collapsed = ns.GetCollapsedTable(cfg.groupsCollapsedKey),
            rebuild = Rebuild,
            onRemoveGroup = function(groupName, itemIDs)
                StaticPopup_Show(cfg.removeGroupPopup, #itemIDs, groupName, { ids = itemIDs })
            end,
        })
    end
    ns[cfg.rebuildKey] = Rebuild

    local function CollapsibleHeader(titleKey, collapsedKey, hintKey)
        local header = ns.CreateSectionHeader(listFrame, ns.CONTENT_W)
        ns.WireSectionHeader(header, titleKey, function()
            NightsFarmtrackerDB[collapsedKey] = not NightsFarmtrackerDB[collapsedKey]
            Rebuild()
        end, hintKey)
        return header
    end

    -- Built once, on first open. Only parts whose position never changes are
    -- placed here; Rebuild positions everything below the first section.
    local function EnsureFrame()
        if frame then return end
        frame = ns.CreateWindowFrame(cfg.frameName, ns.L[cfg.titleKey], { width = ns.FRAME_W, dockChain = "right" })
        frame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 4, 0)
        ns[cfg.frameKey] = frame  -- other windows anchor to it

        ns.AddHLine(frame, "TOP", pad, -(hdrH - 1))

        ns.EnableItemDrop(frame, HandleDrop)

        -- The scroll area holds the whole body, flush below the title line.
        scrollFrame, listFrame = ns.CreateDropListScroll(frame, HandleDrop)
        scrollFrame:SetPoint("TOPLEFT", pad, -hdrH)

        frame.catHeader = CollapsibleHeader(cfg.categoriesTitleKey, cfg.categoriesCollapsedKey)
        frame.catHeader:SetPoint("TOPLEFT", 0, 0)
        if cfg.expansions then
            frame.expHeader = CollapsibleHeader(cfg.expansions.titleKey, cfg.expansions.collapsedKey, cfg.expansions.hintKey)
        end
        frame.sectionSep = ns.AddHLine(listFrame, "TOP", 0, 0)   -- separator lines: Rebuild positions them

        ns.CreateDropZoneRow(frame, listFrame, HandleDrop)

        frame.emptyLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.emptyLabel:SetJustifyH("CENTER")
        frame.emptyLabel:SetTextColor(0.55, 0.55, 0.55)
        frame.emptyLabel:SetText(ns.L[cfg.emptyKey])

        frame.clrBtn = ns.CreateClearAllButton(frame, pad, function()
            local list = Items()
            return list and next(list) ~= nil
        end, cfg.clearPopup)
    end

    local function Toggle()
        if NightsFarmtrackerDB[cfg.enabledKey] == false then return end
        if ns.DeferInCombat(Toggle) then return end
        EnsureFrame()
        if frame:IsShown() then
            frame:Hide()
        else
            Rebuild()
            frame:Show()
        end
        ns.RefreshWindowChain("right")
    end
    ns[cfg.toggleKey] = Toggle
end
