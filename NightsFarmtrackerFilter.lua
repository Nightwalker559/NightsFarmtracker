------------------------------------------------------------------------
-- Night's Farmtracker - Filter
-- Vendor-only filter: drag items from bags here, they will always be
-- valued at vendor price (never AH), account-wide and persistent.
------------------------------------------------------------------------
local _, ns = ...
local ART = "Interface\\AddOns\\NightsFarmtracker\\Media\\"

local F_W       = ns.FRAME_W
local F_PAD     = ns.PAD
local F_HDR_H   = ns.HDR_TOTAL
local ROW_H     = ns.ROW_H
local MAX_VIS_H = 8 * ROW_H
local MIN_VIS_H = 30
local DZ_H      = 34            -- permanent drop-zone height
local LIST_TOP  = F_HDR_H + 4 + DZ_H + 4 + 1 + 4   -- header gap, dropzone, gap, sep, gap

local FilterFrame, FScrollFrame, FListFrame

------------------------------------------------------------------------
-- Row pool
------------------------------------------------------------------------
local activeRows = {}
local rowPool    = {}

local function AcquireRow()
    local r = table.remove(rowPool)
    if r then r:SetParent(FListFrame); r:Show(); return r end

    r = CreateFrame("Frame", nil, FListFrame)
    r:SetSize(ns.CONTENT_W, ROW_H)
    r:EnableMouse(true)

    r.sep = r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1)
    r.sep:SetColorTexture(0.12,0.22,0.25,0.5)
    r.sep:SetPoint("BOTTOMLEFT",0,0); r.sep:SetPoint("BOTTOMRIGHT",0,0)

    r.icon = r:CreateTexture(nil,"ARTWORK")
    r.icon:SetSize(ns.ICON_SIZE, ns.ICON_SIZE)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.iconBorder = r:CreateTexture(nil,"BACKGROUND")
    r.iconBorder:SetPoint("TOPLEFT",     r.icon,"TOPLEFT",     -1,  1)
    r.iconBorder:SetPoint("BOTTOMRIGHT", r.icon,"BOTTOMRIGHT",  1, -1)
    r.iconBorder:Hide()

    r.nameText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",  r.icon, "RIGHT", 8, 0)
    r.nameText:SetPoint("RIGHT", r,      "RIGHT", -4, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(11)
    r.nameText:SetTextColor(0.85,0.85,0.85)

    r:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["filter_tip_shift_rclick"],0.5,0.5,0.5)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" and IsShiftKeyDown() and self.itemID then
            ns.RemoveForceVendor(self.itemID)
            ns.RebuildFilterList()
            ns.RefreshHUD()
        end
    end)
    return r
end

local function ReleaseRow(r)
    r:Hide(); r:ClearAllPoints(); r.itemID=nil
    r.iconBorder:Hide()
    rowPool[#rowPool+1] = r
end

------------------------------------------------------------------------
-- List rebuild
------------------------------------------------------------------------
function ns.RebuildFilterList()
    if not FListFrame then return end
    for _, r in ipairs(activeRows) do ReleaseRow(r) end
    activeRows = {}

    local fv = (NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.forceVendor) or {}
    local list = {}
    for itemID, entry in pairs(fv) do
        list[#list+1] = { itemID = itemID, name = entry.name, icon = entry.icon, quality = entry.quality }
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)

    local yOff = 0
    for _, e in ipairs(list) do
        local r = AcquireRow()
        r:SetPoint("TOPLEFT", 0, -yOff)
        r.sep:SetShown(yOff > 0)
        r.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
        r.nameText:SetText(ns.TruncateName(e.name or ("Item " .. e.itemID)))
        r.itemID = e.itemID
        if e.quality then
            local rq, gq, bq = GetItemQualityColor(e.quality)
            r.nameText:SetTextColor(rq, gq, bq)
            r.iconBorder:SetColorTexture(rq, gq, bq, 0.9); r.iconBorder:Show()
        else
            r.nameText:SetTextColor(0.85, 0.85, 0.85); r.iconBorder:Hide()
        end
        activeRows[#activeRows+1] = r
        yOff = yOff + ROW_H
    end

    local contentH = math.max(1, yOff)
    FListFrame:SetHeight(contentH)
    local visH = math.max(MIN_VIS_H, math.min(contentH, MAX_VIS_H))
    FScrollFrame:SetHeight(visH)
    FilterFrame:SetHeight(LIST_TOP + visH + 14)

    FilterFrame.emptyLabel:SetShown(#list == 0)
end

------------------------------------------------------------------------
-- Drag & drop receiving (item from bags via cursor)
------------------------------------------------------------------------
local function HandleDrop()
    if not CursorHasItem() then return end
    local infoType, itemID, itemLink = GetCursorInfo()
    ClearCursor()
    if infoType ~= "item" or not itemID then return end

    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink or itemID)
    name = name or ("Item " .. itemID)
    ns.AddForceVendor(itemID, name, icon, quality)
    ns.RebuildFilterList()
    ns.RefreshHUD()
end

------------------------------------------------------------------------
-- Build window (lazy)
------------------------------------------------------------------------
local function EnsureFilterFrame()
    if FilterFrame then return end

    FilterFrame = CreateFrame("Frame","NightsFarmtrackerFilterWnd",UIParent,"BackdropTemplate")
    FilterFrame:SetWidth(F_W)
    FilterFrame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 4, 0)
    FilterFrame:SetFrameStrata("HIGH"); FilterFrame:SetClampedToScreen(true)
    FilterFrame:SetMovable(true); FilterFrame:EnableMouse(true)
    FilterFrame:RegisterForDrag("LeftButton")
    FilterFrame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    FilterFrame:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    ns.ApplyFrameStyle(FilterFrame)
    FilterFrame:Hide()
    table.insert(UISpecialFrames, "NightsFarmtrackerFilterWnd")

    -- accept item drops anywhere on the frame (fallback)
    FilterFrame:SetScript("OnReceiveDrag", HandleDrop)
    FilterFrame:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then HandleDrop() end end)

    local titleFS = FilterFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    titleFS:SetPoint("TOPLEFT", F_PAD, -10)
    titleFS:SetText(ns.L["filter_title"])
    titleFS:SetTextColor(unpack(ns.COL_GOLD))

    local hSep = FilterFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT", F_PAD, -(F_HDR_H-1)); hSep:SetPoint("TOPRIGHT", -F_PAD, -(F_HDR_H-1))

    local xBtn = CreateFrame("Button", nil, FilterFrame); xBtn:SetSize(18,18); xBtn:SetPoint("TOPRIGHT",-F_PAD,-10)
    local xTex = xBtn:CreateTexture(nil,"ARTWORK"); xTex:SetAllPoints()
    xTex:SetTexture(ART.."btn_close.png"); xTex:SetAlpha(0.8)
    xBtn:SetScript("OnClick", function() FilterFrame:Hide() end)
    xBtn:SetScript("OnEnter", function() xTex:SetAlpha(1) end)
    xBtn:SetScript("OnLeave", function() xTex:SetAlpha(0.8) end)

    -- Permanent drop zone: always visible target, dashed border, drop here
    local DropZone = CreateFrame("Frame", nil, FilterFrame, "BackdropTemplate")
    DropZone:SetHeight(DZ_H)
    DropZone:SetPoint("TOPLEFT",  F_PAD, -(F_HDR_H + 4))
    DropZone:SetPoint("TOPRIGHT", -F_PAD, -(F_HDR_H + 4))
    DropZone:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile     = true, tileSize = 8, edgeSize = 1,
        insets   = {left=1, right=1, top=1, bottom=1},
    })
    DropZone:SetBackdropColor(unpack(ns.COL_CAT_BG))
    DropZone:SetBackdropBorderColor(unpack(ns.COL_ACCENT))
    DropZone:EnableMouse(true)
    DropZone:SetScript("OnReceiveDrag", HandleDrop)
    DropZone:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then HandleDrop() end end)
    DropZone:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0) end)
    DropZone:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(ns.COL_ACCENT)) end)

    DropZone.label = DropZone:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    DropZone.label:SetPoint("CENTER")
    DropZone.label:SetTextColor(unpack(ns.COL_ACCENT))
    DropZone.label:SetText(ns.L["filter_drop_hint"])
    FilterFrame.DropZone = DropZone

    -- Separator below drop zone
    local dzSep = FilterFrame:CreateTexture(nil,"ARTWORK"); dzSep:SetHeight(1)
    dzSep:SetColorTexture(unpack(ns.COL_BORDER))
    dzSep:SetPoint("TOPLEFT",  F_PAD, -(F_HDR_H + 4 + DZ_H + 4))
    dzSep:SetPoint("TOPRIGHT", -F_PAD, -(F_HDR_H + 4 + DZ_H + 4))

    FScrollFrame = CreateFrame("ScrollFrame", nil, FilterFrame)
    FScrollFrame:SetPoint("TOPLEFT", F_PAD, -LIST_TOP)
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

    FilterFrame.emptyLabel = FilterFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    FilterFrame.emptyLabel:SetPoint("TOP", FilterFrame, "TOP", 0, -(LIST_TOP+14))
    FilterFrame.emptyLabel:SetJustifyH("CENTER")
    FilterFrame.emptyLabel:SetTextColor(0.55,0.55,0.55)
    FilterFrame.emptyLabel:SetText(ns.L["filter_list_empty"])
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleFilterWindow()
    EnsureFilterFrame()
    if FilterFrame:IsShown() then
        FilterFrame:Hide()
    else
        ns.RebuildFilterList()
        FilterFrame:Show()
    end
end
