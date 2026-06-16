------------------------------------------------------------------------
-- Night's Farmtracker - UI
-- BtnBar always visible: [▶][↺][⏱] left · [⚙][?][▼/▲][✕] right
-- Footer always visible: total gold | timer | gold/rate
------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAD         = ns.PAD
local FRAME_W     = ns.FRAME_W
local FOOTER_H    = ns.FOOTER_H
local ROW_H       = ns.ROW_H
local CAT_ROW_H   = ns.CAT_ROW_H
local CAT_INDENT  = ns.CAT_INDENT
local ICON_SIZE   = ns.ICON_SIZE
local CONTENT_W   = ns.CONTENT_W
local MAX_ROWS    = ns.MAX_ROWS
local SCROLL_STEP = ns.SCROLL_STEP

local ART = "Interface\\AddOns\\NightsFarmtracker\\Media\\"

local HDR_PAD    = 6
local BTN_BAR_H  = 26
local HDR_TOTAL  = HDR_PAD + BTN_BAR_H + 8
ns.HDR_TOTAL = HDR_TOTAL
local SCROLL_TOP = HDR_TOTAL + 1
local COLLAPSED_H = HDR_TOTAL + 1 + FOOTER_H

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local rowPool   = {}
local itemRows  = {}
local itemOrder = {}
local cachedGold = 0
local totalH     = 0

------------------------------------------------------------------------
-- Custom TGA button
------------------------------------------------------------------------
local function MakeBtn(parent, size, artFile)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(ART .. artFile)
    btn.tex:SetAlpha(0.75)
    btn:SetScript("OnMouseDown", function(self)
        self.tex:ClearAllPoints()
        self.tex:SetSize(size-3, size-3)
        self.tex:SetPoint("CENTER", 1, -1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.tex:ClearAllPoints(); self.tex:SetAllPoints()
    end)
    btn:SetScript("OnEnter", function(self) self.tex:SetAlpha(1.0) end)
    btn:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75) end)
    return btn
end

------------------------------------------------------------------------
-- Main frame
------------------------------------------------------------------------
local MainFrame = CreateFrame("Frame","NightsFarmtrackerMain",UIParent,"BackdropTemplate")
MainFrame:SetSize(FRAME_W, COLLAPSED_H)
MainFrame:SetPoint("CENTER")
MainFrame:Hide()
MainFrame:SetMovable(true); MainFrame:EnableMouse(true); MainFrame:SetClampedToScreen(true)
ns.ApplyFrameStyle(MainFrame)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
MainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point,_,rel,x,y = self:GetPoint()
    NightsFarmtrackerDB.pos = {point,rel,x,y}
end)
ns.MainFrame = MainFrame

------------------------------------------------------------------------
-- Button bar — always visible
-- Left:  [▶] [↺] [⏱]
-- Right: [⚙] [?] [▼/▲] [✕]
------------------------------------------------------------------------
local BtnBar = CreateFrame("Frame", nil, MainFrame)
BtnBar:SetSize(CONTENT_W, BTN_BAR_H)
BtnBar:SetPoint("TOPLEFT", PAD, -HDR_PAD)

local btnPause    = MakeBtn(BtnBar, 18, "btn_play.tga")
btnPause:SetPoint("LEFT", BtnBar, "LEFT", 0, 0)

local btnReset    = MakeBtn(BtnBar, 18, "btn_reset.tga")
btnReset:SetPoint("LEFT", btnPause, "RIGHT", 6, 0)

local btnHistory  = MakeBtn(BtnBar, 16, "btn_history.tga")
btnHistory:SetPoint("LEFT", btnReset, "RIGHT", 10, 0)

-- Right side (anchored from right): close → collapse → help → settings
local btnClose = MakeBtn(BtnBar, 16, "btn_close.tga")
btnClose:SetPoint("RIGHT", BtnBar, "RIGHT", 0, 0)

local btnToggle = MakeBtn(BtnBar, 16, "btn_expand.tga")
btnToggle:SetPoint("RIGHT", btnClose, "LEFT", -6, 0)

local btnHelp = MakeBtn(BtnBar, 16, "btn_help.tga")
btnHelp:SetPoint("RIGHT", btnToggle, "LEFT", -6, 0)

local btnSettings = MakeBtn(BtnBar, 16, "btn_settings.tga")
btnSettings:SetPoint("RIGHT", btnHelp, "LEFT", -6, 0)

-- Separator below BtnBar
local hdrSep = MainFrame:CreateTexture(nil, "ARTWORK")
hdrSep:SetHeight(1)
hdrSep:SetColorTexture(unpack(ns.COL_BORDER))
hdrSep:SetPoint("TOPLEFT",  PAD,  -HDR_TOTAL)
hdrSep:SetPoint("TOPRIGHT", -PAD, -HDR_TOTAL)

------------------------------------------------------------------------
-- Empty hint (expanded, no items yet)
------------------------------------------------------------------------
local emptyHint = MainFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
emptyHint:SetPoint("TOP", MainFrame, "TOP", 0, -(SCROLL_TOP + 28))
emptyHint:SetTextColor(0.30, 0.55, 0.60)
emptyHint:SetFontHeight(11)
emptyHint:SetText(ns.L["gathering_active"])
emptyHint:Hide()

------------------------------------------------------------------------
-- Footer — always visible: [total gold] [timer] [gold/rate]
------------------------------------------------------------------------
local footerSep = MainFrame:CreateTexture(nil, "ARTWORK")
footerSep:SetHeight(1)
footerSep:SetColorTexture(unpack(ns.COL_BORDER))
footerSep:SetPoint("BOTTOMLEFT",  PAD,  FOOTER_H - 2)
footerSep:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H - 2)

local goldBtn = CreateFrame("Button", nil, MainFrame)
goldBtn:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", PAD, 4)
goldBtn:SetSize(140, 22)
MainFrame.totalGoldText = goldBtn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
MainFrame.totalGoldText:SetPoint("LEFT")
MainFrame.totalGoldText:SetTextColor(unpack(ns.COL_GOLD))
MainFrame.totalGoldText:SetFontHeight(11)
goldBtn:SetScript("OnClick", function() ns.ToggleGoldFrame() end)
goldBtn:SetScript("OnEnter", function() MainFrame.totalGoldText:SetTextColor(1, 1, 0.6) end)
goldBtn:SetScript("OnLeave", function() MainFrame.totalGoldText:SetTextColor(unpack(ns.COL_GOLD)) end)

MainFrame.TimerText = MainFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
MainFrame.TimerText:SetPoint("BOTTOM", MainFrame, "BOTTOM", 0, 9)
MainFrame.TimerText:SetJustifyH("CENTER")
MainFrame.TimerText:SetTextColor(0.65, 0.70, 0.72)
MainFrame.TimerText:SetFontHeight(11)
MainFrame.TimerText:SetText("00:00:00")

local btnRate = CreateFrame("Frame", nil, MainFrame)
btnRate:SetPoint("BOTTOMRIGHT", -PAD, 4)
btnRate:SetSize(130, 20)
btnRate.text = btnRate:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
btnRate.text:SetPoint("RIGHT")
btnRate.text:SetTextColor(0.55, 0.55, 0.55)
btnRate.text:SetFontHeight(11)

------------------------------------------------------------------------
-- Scroll frame (visible only when expanded)
------------------------------------------------------------------------
local ScrollFrame = CreateFrame("ScrollFrame", nil, MainFrame)
ScrollFrame:SetPoint("TOPLEFT",     PAD,  -SCROLL_TOP)
ScrollFrame:SetPoint("BOTTOMRIGHT", -PAD,  FOOTER_H)
ScrollFrame:Hide()

local ListFrame = CreateFrame("Frame", nil, ScrollFrame)
ListFrame:SetSize(CONTENT_W, 1)
ScrollFrame:SetScrollChild(ListFrame)

local function OnWheel(_, delta)
    local cur  = ScrollFrame:GetVerticalScroll()
    local maxS = math.max(0, ListFrame:GetHeight() - ScrollFrame:GetHeight())
    ScrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta * SCROLL_STEP, maxS)))
end
ScrollFrame:EnableMouseWheel(true)
ScrollFrame:SetScript("OnMouseWheel", OnWheel)
ListFrame:EnableMouseWheel(true)
ListFrame:SetScript("OnMouseWheel", OnWheel)

------------------------------------------------------------------------
-- Gold Overview Frame
------------------------------------------------------------------------
local GoldFrame = CreateFrame("Frame","NightsFarmtrackerGoldFrame",UIParent,"BackdropTemplate")
GoldFrame:SetWidth(FRAME_W)
GoldFrame:SetPoint("TOPLEFT", MainFrame, "BOTTOMLEFT", 0, -2)
GoldFrame:SetFrameStrata("HIGH")
GoldFrame:SetClampedToScreen(true)
ns.ApplyFrameStyle(GoldFrame)
GoldFrame:Hide()

do
    local gp = PAD
    local titleFS = GoldFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    titleFS:SetPoint("TOPLEFT", gp, -10)
    titleFS:SetTextColor(unpack(ns.COL_ACCENT))
    titleFS:SetText(ns.L["gold_overview"])

    local sep1 = GoldFrame:CreateTexture(nil,"ARTWORK"); sep1:SetHeight(1)
    sep1:SetColorTexture(unpack(ns.COL_BORDER))
    sep1:SetPoint("TOPLEFT", gp, -26); sep1:SetPoint("TOPRIGHT", -gp, -26)

    local function MakeRow(yOff, labelKey, bold)
        local font = bold and "GameFontNormal" or "GameFontNormalSmall"
        local lbl = GoldFrame:CreateFontString(nil,"OVERLAY",font)
        lbl:SetPoint("TOPLEFT", gp, yOff)
        lbl:SetTextColor(0.75, 0.75, 0.75)
        lbl:SetText(ns.L[labelKey] or labelKey)
        local val = GoldFrame:CreateFontString(nil,"OVERLAY",font)
        val:SetPoint("TOPRIGHT", -gp, yOff)
        val:SetJustifyH("RIGHT")
        val:SetTextColor(unpack(ns.COL_GOLD))
        return val
    end

    local itemsVal  = MakeRow(-33, "gold_items")
    local direktVal = MakeRow(-49, "looted_gold")

    local sep2 = GoldFrame:CreateTexture(nil,"ARTWORK"); sep2:SetHeight(1)
    sep2:SetColorTexture(unpack(ns.COL_BORDER))
    sep2:SetPoint("TOPLEFT", gp, -63); sep2:SetPoint("TOPRIGHT", -gp, -63)

    local totalVal = MakeRow(-72, "gold_total", true)

    GoldFrame:SetHeight(88)
    GoldFrame.itemsVal  = itemsVal
    GoldFrame.direktVal = direktVal
    GoldFrame.totalVal  = totalVal
end

function ns.UpdateGoldFrame()
    if not GoldFrame:IsShown() then return end
    local db         = NightsFarmtrackerDB
    local lootedGold = db.lootedGold or 0
    local itemGold   = cachedGold - lootedGold
    GoldFrame.itemsVal:SetText( itemGold   > 0 and ns.FormatGold(itemGold)   or "0")
    GoldFrame.direktVal:SetText(lootedGold > 0 and ns.FormatGold(lootedGold) or "0")
    GoldFrame.totalVal:SetText( cachedGold > 0 and ns.FormatGold(cachedGold) or "0")
end

function ns.ToggleGoldFrame()
    if GoldFrame:IsShown() then GoldFrame:Hide()
    else GoldFrame:Show(); ns.UpdateGoldFrame() end
end

MainFrame:HookScript("OnHide", function() GoldFrame:Hide() end)

------------------------------------------------------------------------
-- Timer / rate
------------------------------------------------------------------------
function ns.UpdateTimerDisplay(timeStr)
    MainFrame.TimerText:SetText(timeStr)
end

function ns.UpdateGoldRate()
    local db = NightsFarmtrackerDB
    if cachedGold <= 0 or db.totalTime <= 0 then
        btnRate.text:SetText(""); return
    end
    local secs = db.totalTime
    if db.goldRateMode == "min" then
        btnRate.text:SetText(ns.FormatGold(math.floor(cachedGold/(secs/60)))   ..ns.L["rate_min"])
    else
        btnRate.text:SetText(ns.FormatGold(math.floor(cachedGold/(secs/3600))) ..ns.L["rate_hr"])
    end
end

------------------------------------------------------------------------
-- Expand / Collapse
------------------------------------------------------------------------
local function ExpandedHeight()
    return SCROLL_TOP + 1 + math.min(totalH, MAX_ROWS * ROW_H) + FOOTER_H
end

function ns.SetExpanded(expand)
    NightsFarmtrackerDB.expanded = expand
    if expand then
        btnToggle.tex:SetTexture(ART.."btn_collapse.tga")
        if #itemOrder == 0 then
            emptyHint:Show(); ScrollFrame:Hide()
            MainFrame:SetHeight(SCROLL_TOP + 60 + FOOTER_H)
        else
            emptyHint:Hide(); ScrollFrame:Show()
            MainFrame:SetHeight(ExpandedHeight())
        end
    else
        emptyHint:Hide(); ScrollFrame:Hide()
        btnToggle.tex:SetTexture(ART.."btn_expand.tga")
        MainFrame:SetHeight(COLLAPSED_H)
    end
end

local function UpdateFrameHeight()
    if not NightsFarmtrackerDB.expanded then return end
    if #itemOrder == 0 then
        emptyHint:Show(); ScrollFrame:Hide()
        MainFrame:SetHeight(SCROLL_TOP + 60 + FOOTER_H)
    else
        emptyHint:Hide(); ScrollFrame:Show()
        ListFrame:SetSize(CONTENT_W, totalH)
        MainFrame:SetHeight(ExpandedHeight())
    end
end

local function UpdateSummary()
    cachedGold = 0
    local filter = NightsFarmtrackerDB.filterMode or "all"
    for _, data in pairs(NightsFarmtrackerDB.count) do
        local vis = filter=="all"
               or (filter=="mats"  and ns.IsMat(data))
               or (filter=="other" and not ns.IsMat(data))
        if vis then
            local val = ns.ItemValue(data)
            if val then cachedGold = cachedGold + val end
        end
    end
    cachedGold = cachedGold + (NightsFarmtrackerDB.lootedGold or 0)
    MainFrame.totalGoldText:SetText(cachedGold > 0 and ns.FormatGold(cachedGold) or "")
    ns.UpdateGoldRate()
    ns.UpdateGoldFrame()
end

------------------------------------------------------------------------
-- Row pool
------------------------------------------------------------------------
local function AcquireRow()
    local row = table.remove(rowPool)
    if row then row:Show(); return row end

    row = CreateFrame("Frame", nil, ListFrame)
    row:SetSize(CONTENT_W, ROW_H)

    row.catBg = row:CreateTexture(nil,"BACKGROUND")
    row.catBg:SetAllPoints()
    row.catBg:SetColorTexture(unpack(ns.COL_CAT_BG))
    row.catBg:SetAlpha(0)

    row:EnableMouse(true); row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", OnWheel)

    row:SetScript("OnMouseUp", function(self, btn)
        if self.isCategoryHeader then
            if btn == "LeftButton" then
                NightsFarmtrackerDB.collapsed[self.categoryName] = not NightsFarmtrackerDB.collapsed[self.categoryName]
                ns.RefreshHUD()
            elseif btn == "RightButton" and IsShiftKeyDown() then
                ns.ExcludeItem(self.categoryName)
            end
        elseif self.itemName then
            if btn == "RightButton" and IsShiftKeyDown() then
                ns.ExcludeItem(self.itemName)
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        if self.isCategoryHeader then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:AddLine(self.categoryName, 1,1,1)
            GameTooltip:AddLine(ns.L["cat_tip_click"],      0.5,0.5,0.5)
            GameTooltip:AddLine(ns.L["cat_tip_shift_rclick"],0.5,0.5,0.5)
            GameTooltip:Show()
        elseif self.itemName then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            if self.itemLink then
                GameTooltip:SetHyperlink(self.itemLink)
            elseif self.itemID then
                GameTooltip:SetItemByID(self.itemID)
            else
                GameTooltip:AddLine(self.itemName,1,1,1)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["item_tip_shift_rclick"],0.5,0.5,0.5)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner()==self then GameTooltip:Hide() end
    end)

    row.sep = row:CreateTexture(nil,"ARTWORK")
    row.sep:SetHeight(1)
    row.sep:SetColorTexture(0.12,0.22,0.25,0.5)
    row.sep:SetPoint("BOTTOMLEFT",  row,"BOTTOMLEFT",  0, 0)
    row.sep:SetPoint("BOTTOMRIGHT", row,"BOTTOMRIGHT", 0, 0)

    row.icon = row:CreateTexture(nil,"ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconBorder = row:CreateTexture(nil,"BACKGROUND")
    row.iconBorder:SetPoint("TOPLEFT",     row.icon,"TOPLEFT",     -1,  1)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon,"BOTTOMRIGHT",  1, -1)
    row.iconBorder:Hide()

    -- Single-line layout: all y=0 → vertically centered with icon
    row.nameText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.nameText:SetPoint("LEFT",  row.icon, "RIGHT", 8,    0)
    row.nameText:SetPoint("RIGHT", row,      "RIGHT", -128, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetFontHeight(11)
    row.nameText:SetWordWrap(false)

    row.countText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.countText:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    row.countText:SetJustifyH("RIGHT")
    row.countText:SetTextColor(0.78, 0.78, 0.78)
    row.countText:SetFontHeight(11)

    row.goldText = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.goldText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.goldText:SetJustifyH("RIGHT")
    row.goldText:SetTextColor(unpack(ns.COL_GOLD))
    row.goldText:SetFontHeight(11)

    return row
end

local function ReleaseRow(row)
    row:Hide(); row:ClearAllPoints()
    row.itemName=nil; row.itemLink=nil; row.itemID=nil
    row.isCategoryHeader=nil; row.categoryName=nil
    row.catBg:SetAlpha(0)
    row:SetSize(CONTENT_W, ROW_H)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:Show()
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("LEFT",  row.icon, "RIGHT", 8,    0)
    row.nameText:SetPoint("RIGHT", row,      "RIGHT", -128, 0)
    row.nameText:SetFontHeight(11)
    row.countText:ClearAllPoints()
    row.countText:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    row.goldText:ClearAllPoints()
    row.goldText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.goldText:SetFontHeight(11)
    rowPool[#rowPool+1] = row
end

local function PlaceRow(row, yOff, name, icon, nameColor, quality)
    row:SetPoint("TOPLEFT", 0, -yOff)
    row.itemName = name
    row.icon:SetTexture(icon or ns.FALLBACK_ICON)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); row.icon:Show()
    row.nameText:SetText(name)
    row.sep:SetShown(yOff > 0)
    if nameColor then
        row.nameText:SetTextColor(unpack(nameColor)); row.iconBorder:Hide()
    elseif quality then
        local r,g,b = GetItemQualityColor(quality)
        row.nameText:SetTextColor(r,g,b)
        row.iconBorder:SetColorTexture(r,g,b,0.9); row.iconBorder:Show()
    else
        row.nameText:SetTextColor(1,1,1); row.iconBorder:Hide()
    end
    itemOrder[#itemOrder+1] = name
    itemRows[name] = row
end

local function ShowGold(row, ah, vendor, forceVendor)
    if not forceVendor and ah and ah > 0 then
        row.goldText:SetText(ns.FormatGold(ah))
    elseif vendor and vendor > 0 then
        row.goldText:SetText(ns.FormatGold(vendor))
    else
        row.goldText:SetText("")
    end
end

------------------------------------------------------------------------
-- RefreshHUD
------------------------------------------------------------------------
ns.RefreshHUD = function()
    local savedScroll = ScrollFrame:GetVerticalScroll()
    for _, row in pairs(itemRows) do ReleaseRow(row) end
    itemRows, itemOrder = {}, {}

    local db     = NightsFarmtrackerDB
    local filter = db.filterMode or "all"
    local cats   = {}

    for name, data in pairs(db.count) do
        local vis = filter=="all"
               or (filter=="mats"  and ns.IsMat(data))
               or (filter=="other" and not ns.IsMat(data))
        if vis then
            local cat = ns.CategoryName(data) or ns.CAT_MATS
            if not cats[cat] then cats[cat]={items={},totalGold=0,totalVendor=0,totalAH=0,classID=data.classID} end
            local c      = cats[cat]
            local vendor = ns.VendorTotal(data) or 0
            local ah     = ns.AHTotal(data)     or 0
            local gold   = ns.ItemValue(data)   or 0
            c.items[#c.items+1] = {name=name,data=data,gold=gold,vendor=vendor,ah=ah}
            c.totalGold   = c.totalGold   + gold
            c.totalVendor = c.totalVendor + vendor
            c.totalAH     = c.totalAH     + ah
        end
    end

    for _, cat in pairs(cats) do
        table.sort(cat.items, function(a,b)
            if a.gold ~= b.gold then return a.gold > b.gold end
            if a.data.amount ~= b.data.amount then return a.data.amount > b.data.amount end
            return a.name < b.name
        end)
    end

    local sorted = {}
    for catName, cat in pairs(cats) do sorted[#sorted+1]={name=catName,cat=cat} end

    -- hasAH muss vor dem Sort bekannt sein
    local hasAH = ns.HasAnyAH() and db.ahSource ~= "none"

    -- displayGold pro Kategorie: gleiche Logik wie der Header-Text
    local junkLabel = ns.L["cat_junk"] or "Junk"
    for _, entry in ipairs(sorted) do
        local catName   = entry.name
        local cat       = entry.cat
        local isJunkCat = (catName == junkLabel)
        if not hasAH or isJunkCat then
            cat.displayGold = cat.totalVendor
        elseif cat.totalAH > 0 then
            cat.displayGold = cat.totalAH
        else
            cat.displayGold = cat.totalGold
        end
    end

    table.sort(sorted, function(a,b)
        if a.cat.displayGold ~= b.cat.displayGold then return a.cat.displayGold > b.cat.displayGold end
        local oa = (a.cat.classID and ns.CLASS_PRIORITY[a.cat.classID]) or 50
        local ob = (b.cat.classID and ns.CLASS_PRIORITY[b.cat.classID]) or 50
        return oa < ob
    end)
    local yOffset = 0

    for _, entry in ipairs(sorted) do
        local catName     = entry.name
        local cat         = entry.cat
        local isCollapsed = db.collapsed[catName]

        local hdr = AcquireRow()
        hdr:SetSize(CONTENT_W, CAT_ROW_H)
        PlaceRow(hdr, yOffset, catName, nil, ns.COL_ACCENT)
        hdr.icon:Hide(); hdr.iconBorder:Hide()
        hdr.countText:SetText("")
        hdr.isCategoryHeader=true; hdr.categoryName=catName
        hdr.catBg:SetAlpha(1)
        hdr.nameText:ClearAllPoints()
        hdr.nameText:SetPoint("LEFT",  4, 0)
        hdr.nameText:SetPoint("RIGHT", hdr, "RIGHT", -100, 0)
        hdr.nameText:SetText((isCollapsed and "+ " or "- ")..catName)
        hdr.nameText:SetFontHeight(11)
        hdr.goldText:ClearAllPoints()
        hdr.goldText:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)
        hdr.goldText:SetFontHeight(11)

        local isJunkCat = (catName == (ns.L["cat_junk"] or "Junk"))
        if not hasAH or isJunkCat then
            hdr.goldText:SetText(cat.totalVendor > 0 and ns.FormatGold(cat.totalVendor) or "")
        elseif cat.totalAH > 0 then
            hdr.goldText:SetText(ns.FormatGold(cat.totalAH))
        else
            hdr.goldText:SetText(cat.totalGold > 0 and ns.FormatGold(cat.totalGold) or "")
        end
        yOffset = yOffset + CAT_ROW_H

        if not isCollapsed then
            local qAtlas = NightsFarmtrackerDB.qAtlas or {}

            -- Build flat display list: each quality rank as separate entry
            local flat = {}
            for _, item in ipairs(cat.items) do
                local d = item.data
                local fv = not hasAH or (d.quality==0) or d.isVendorTrash or d.isBoP
                if d.q and d.qIDs then
                    for tier = 1, 3 do
                        local tc = d.q[tier] or 0
                        local tid = d.qIDs[tier]
                        if tc > 0 then
                            local tAH, tV
                            if tid then
                                local ap = ns.GetAHPriceForID(tid)
                                if ap then tAH = ap * tc end
                            end
                            if d.sellPrice and d.sellPrice > 0 then tV = d.sellPrice * tc end
                            local tGold = fv and (tV or 0) or (tAH or tV or 0)
                            if tGold > 0 then
                                local rankIcon = qAtlas[tier]
                                              and CreateAtlasMarkup(qAtlas[tier],12,11)
                                              or ("|cffaaaaaa R"..tier.."|r")
                                flat[#flat+1] = {
                                    isRank=true, name=item.name, d=d,
                                    tier=tier, tid=tid, tc=tc,
                                    tAH=tAH, tV=tV, tGold=tGold,
                                    rankIcon=rankIcon, fv=fv,
                                }
                            end
                        end
                    end
                else
                    local gold = fv and (item.vendor or 0) or (item.ah or item.vendor or 0)
                    flat[#flat+1] = {
                        isRank=false, name=item.name, d=d,
                        item=item, gold=gold, fv=fv,
                    }
                end
            end

            -- Skip category entirely if no displayable items
            if #flat == 0 and not isCollapsed then
                ReleaseRow(hdr)
                itemRows[catName] = nil
                yOffset = yOffset - CAT_ROW_H
            else

            -- Sort flat list by gold descending
            table.sort(flat, function(a,b)
                local ga = a.isRank and a.tGold or a.gold
                local gb = b.isRank and b.tGold or b.gold
                if ga ~= gb then return ga > gb end
                return a.name < b.name
            end)

            -- Render
            for _, fi in ipairs(flat) do
                local row = AcquireRow()
                local d = fi.d
                row.sep:SetShown(yOffset > 0)
                row.icon:SetTexture(d.icon or ns.FALLBACK_ICON)
                row.icon:SetTexCoord(0.08,0.92,0.08,0.92); row.icon:Show()
                row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", 4+CAT_INDENT, 0)
                row:SetPoint("TOPLEFT", 0, -yOffset)
                if d.quality then
                    local r,g,b = GetItemQualityColor(d.quality)
                    row.nameText:SetTextColor(r,g,b)
                    row.iconBorder:SetColorTexture(r,g,b,0.9); row.iconBorder:Show()
                else
                    row.nameText:SetTextColor(1,1,1); row.iconBorder:Hide()
                end
                row.nameText:ClearAllPoints()
                row.nameText:SetPoint("LEFT",  row.icon,"RIGHT", 8,    0)
                row.nameText:SetPoint("RIGHT", row,     "RIGHT", -108, 0)

                if fi.isRank then
                    local key = fi.name.."_q"..fi.tier
                    row.itemName = fi.name; row.itemID = fi.tid; row.itemLink = nil
                    row.nameText:SetText(ns.TruncateName(fi.name))
                    row.countText:SetText(fi.rankIcon.." "..tostring(fi.tc))
                    if fi.fv then
                        row.goldText:SetText(fi.tV and ns.FormatGold(fi.tV) or "")
                    elseif fi.tAH and fi.tAH > 0 then
                        row.goldText:SetText(ns.FormatGold(fi.tAH))
                    elseif fi.tV and fi.tV > 0 then
                        row.goldText:SetText(ns.FormatGold(fi.tV))
                    else
                        row.goldText:SetText("")
                    end
                    itemOrder[#itemOrder+1] = key; itemRows[key] = row
                else
                    local it = fi.item
                    row.itemName = fi.name; row.itemID = d.itemID; row.itemLink = d.itemLink
                    row.nameText:SetText(ns.TruncateName(fi.name))
                    row.countText:SetText(tostring(d.amount))
                    if fi.fv then ShowGold(row,nil,it.vendor,true)
                    else ShowGold(row,it.ah,it.vendor,false) end
                    itemOrder[#itemOrder+1] = fi.name; itemRows[fi.name] = row
                end
                yOffset = yOffset + ROW_H
            end
            end  -- else (flat not empty)
        end
    end

    totalH = yOffset
    local maxScroll = math.max(0, totalH - ScrollFrame:GetHeight())
    ScrollFrame:SetVerticalScroll(math.min(savedScroll, maxScroll))
    UpdateFrameHeight()
    UpdateSummary()
end

------------------------------------------------------------------------
-- Session controls
------------------------------------------------------------------------
function ns.Reset()
    ns.SaveCurrentSession()
    local db = NightsFarmtrackerDB
    db.count={}; db.collapsed={}; db.excludedNames={}
    db.totalTime=0; db.qAtlas={}; db.paused=true; db.lootedGold=0
    ns.StopTimer(); ns.CleanupPriceUpdate()
    GoldFrame:Hide()
    for _, row in pairs(itemRows) do ReleaseRow(row) end
    itemRows, itemOrder = {}, {}
    cachedGold = 0
    ns.UpdateTimerDisplay("00:00:00")
    MainFrame.totalGoldText:SetText("")
    btnRate.text:SetText("")
    ScrollFrame:SetVerticalScroll(0)
    UpdateFrameHeight()
    ns.ApplyPauseVisuals()
end

function ns.ApplyPauseVisuals()
    if NightsFarmtrackerDB.paused then
        btnPause.tex:SetTexture(ART.."btn_play.tga")
        MainFrame.TimerText:SetTextColor(0.65, 0.70, 0.72)
    else
        btnPause.tex:SetTexture(ART.."btn_pause.tga")
        MainFrame.TimerText:SetTextColor(0.2, 0.85, 0.2)
    end
    ns.UpdateMinimapIcon()
end

function ns.ExcludeItem(name)
    NightsFarmtrackerDB.excludedNames[name] = true
    for itemName, data in pairs(NightsFarmtrackerDB.count) do
        if itemName==name or ns.CategoryName(data)==name then
            NightsFarmtrackerDB.count[itemName] = nil
        end
    end
    ns.RefreshHUD()
end

------------------------------------------------------------------------
-- Button scripts
------------------------------------------------------------------------
btnClose:SetScript("OnClick", function()
    NightsFarmtrackerDB.visible = false
    MainFrame:Hide()
    GoldFrame:Hide()
end)
btnClose:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.L["close"])
    GameTooltip:Show()
end)
btnClose:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

btnToggle:SetScript("OnClick", function()
    ns.SetExpanded(not NightsFarmtrackerDB.expanded)
end)
btnToggle:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT")
    GameTooltip:SetText(NightsFarmtrackerDB.expanded and ns.L["collapse"] or ns.L["expand"])
    GameTooltip:Show()
end)
btnToggle:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

btnPause:SetScript("OnClick", function()
    NightsFarmtrackerDB.paused = not NightsFarmtrackerDB.paused
    if NightsFarmtrackerDB.paused then ns.StopTimer() else ns.StartTimer() end
    ns.ApplyPauseVisuals()
end)
btnPause:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText(NightsFarmtrackerDB.paused and ns.L["start_tracking"] or ns.L["pause_tracking"])
    GameTooltip:Show()
end)
btnPause:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

btnReset:SetScript("OnClick", ns.Reset)
btnReset:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText(ns.L["reset_session"])
    GameTooltip:AddLine(ns.L["reset_desc"],0.7,0.7,0.7,true)
    GameTooltip:Show()
end)
btnReset:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

btnHistory:SetScript("OnClick", function() ns.ToggleHistory() end)
btnHistory:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText(ns.L["session_history"])
    GameTooltip:Show()
end)
btnHistory:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

btnSettings:SetScript("OnClick", function() ns.ToggleSettings() end)
btnSettings:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText(ns.L["settings"])
    GameTooltip:Show()
end)
btnSettings:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

btnHelp:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("Night's Farmtracker",unpack(ns.COL_ACCENT))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.L["help_categories"], 1,1,1)
    GameTooltip:AddLine(ns.L["help_cat_click"],             0.7,0.7,0.7)
    GameTooltip:AddLine(ns.L["help_cat_rclick"],    0.7,0.7,0.7)
    GameTooltip:AddLine(ns.L["help_items"], 1,1,1)
    GameTooltip:AddLine(ns.L["help_item_hover"],                0.7,0.7,0.7)
    GameTooltip:AddLine(ns.L["help_item_rclick"],   0.7,0.7,0.7)
    GameTooltip:Show()
end)
btnHelp:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local rad,deg,cos,sin,sqrt = math.rad,math.deg,math.cos,math.sin,math.sqrt
local atan2,mmax,mmin      = math.atan2,math.max,math.min
local mmShapes = {
    ["ROUND"]={true,true,true,true},["SQUARE"]={false,false,false,false},
    ["CORNER-TOPLEFT"]={false,false,false,true},["CORNER-TOPRIGHT"]={false,false,true,false},
    ["CORNER-BOTTOMLEFT"]={false,true,false,false},["CORNER-BOTTOMRIGHT"]={true,false,false,false},
    ["SIDE-LEFT"]={false,true,false,true},["SIDE-RIGHT"]={true,false,true,false},
    ["SIDE-TOP"]={false,false,true,true},["SIDE-BOTTOM"]={true,true,false,false},
    ["TRICORNER-TOPLEFT"]={false,true,true,true},["TRICORNER-TOPRIGHT"]={true,false,true,true},
    ["TRICORNER-BOTTOMLEFT"]={true,true,false,true},["TRICORNER-BOTTOMRIGHT"]={true,true,true,false},
}
local mmBtn = CreateFrame("Button","NightsFarmtrackerMinimapBtn",Minimap)
mmBtn:SetSize(31,31); mmBtn:SetFrameStrata("MEDIUM"); mmBtn:SetFixedFrameStrata(true)
mmBtn:SetFrameLevel(8); mmBtn:SetFixedFrameLevel(true)
mmBtn:RegisterForClicks("anyUp"); mmBtn:RegisterForDrag("LeftButton")
mmBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-Tracking-Highlight")
mmBtn.icon=mmBtn:CreateTexture(nil,"BACKGROUND"); mmBtn.icon:SetSize(20,20)
mmBtn.icon:SetPoint("CENTER"); mmBtn.icon:SetTexture(ART.."Icon")
mmBtn.icon:SetTexCoord(0.05,0.95,0.05,0.95)
mmBtn.border=mmBtn:CreateTexture(nil,"OVERLAY"); mmBtn.border:SetSize(54,54)
mmBtn.border:SetPoint("TOPLEFT",mmBtn,"TOPLEFT",-1,1)
mmBtn.border:SetTexture("Interface\\Minimap\\UI-Minimap-Border")
local function PlaceMinimapBtn(pos)
    local angle=rad(pos or 225); local x,y=cos(angle),sin(angle)
    local q=1; if x<0 then q=q+1 end; if y>0 then q=q+2 end
    local quad=mmShapes[GetMinimapShape and GetMinimapShape() or "ROUND"] or mmShapes["ROUND"]
    local w=Minimap:GetWidth()/2+5; local h=Minimap:GetHeight()/2+5
    if quad[q] then x,y=x*w,y*h
    else
        local dw=sqrt(2*w^2)-10; local dh=sqrt(2*h^2)-10
        x=mmax(-w,mmin(x*dw,w)); y=mmax(-h,mmin(y*dh,h))
    end
    mmBtn:ClearAllPoints(); mmBtn:SetPoint("CENTER",Minimap,"CENTER",x,y)
end
ns.UpdateMinimapPosition = PlaceMinimapBtn
function ns.UpdateMinimapIcon() end
function ns.SetMinimapVisible(show)
    if show then mmBtn:Show() else mmBtn:Hide() end
end

function ns.UpdateHistoryBtn()
    local enabled = NightsFarmtrackerDB.sessionHistoryEnabled ~= false
    if enabled then
        btnHistory:Show(); btnHistory:EnableMouse(true)
    else
        btnHistory:Hide(); btnHistory:EnableMouse(false)
    end
end
mmBtn:SetScript("OnMouseDown",function(self)self.icon:SetSize(17,17)end)
mmBtn:SetScript("OnMouseUp",  function(self)self.icon:SetSize(20,20)end)
mmBtn:SetScript("OnDragStart",function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate",function()
        local mx,my=Minimap:GetCenter(); local cx,cy=GetCursorPosition()
        local sc=Minimap:GetEffectiveScale(); cx,cy=cx/sc,cy/sc
        local p=deg(atan2(cy-my,cx-mx))%360
        NightsFarmtrackerDB.minimapPos=p; PlaceMinimapBtn(p)
    end)
end)
mmBtn:SetScript("OnDragStop",function(self)
    self:SetScript("OnUpdate",nil); self:UnlockHighlight(); self.icon:SetSize(20,20)
end)
mmBtn:SetScript("OnClick",function(_,btn)
    if btn=="RightButton" then ns.ToggleSettings()
    else
        if MainFrame:IsShown() then
            NightsFarmtrackerDB.visible=false; MainFrame:Hide()
        else
            NightsFarmtrackerDB.visible=true; MainFrame:Show()
        end
    end
end)
mmBtn:SetScript("OnEnter", nil)
mmBtn:SetScript("OnLeave", nil)