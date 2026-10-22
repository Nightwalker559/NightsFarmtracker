------------------------------------------------------------------------
-- Night's Farmtracker - History
-- Session History window (months, days, sessions) and the Detail window for
-- one session or month. The data model is in Core/Sessions.lua.
------------------------------------------------------------------------
local _, ns = ...
local ART = ns.ART

------------------------------------------------------------------------
-- Layout — history list
------------------------------------------------------------------------
local H_W      = ns.FRAME_W
local H_PAD    = 10
local H_HDR_H  = ns.WINDOW_HDR_H
local H_FTR_H  = 28
local DAY_H    = ns.CAT_ROW_H
local MONTH_H  = ns.CAT_ROW_H
local SESS_H   = 38

------------------------------------------------------------------------
-- Layout — detail window (matches main frame width)
------------------------------------------------------------------------
local DET_W      = ns.FRAME_W          -- same as main frame
local DET_PAD    = ns.PAD
local DET_HDR_H  = ns.WINDOW_HDR_H
local DET_FTR_H  = 10   -- just padding: the item counts live in the header hover
local DET_CONT_W = ns.CONTENT_W
local DET_CAT_H  = ns.CAT_ROW_H
local DET_ROW_H  = ns.ROW_H

------------------------------------------------------------------------
-- Frame references
------------------------------------------------------------------------
local HistFrame, HScrollFrame, HListFrame
local DetailFrame, DScrollFrame, DListFrame

------------------------------------------------------------------------
-- History list row pools
------------------------------------------------------------------------
local activeSessRows={} local activeDayRows={} local sessPool={} local dayPool={}

local function AcquireSessRow()
    local r=table.remove(sessPool)
    if r then r:SetParent(HListFrame); r:Show(); return r end
    r=CreateFrame("Frame",nil,HListFrame); r:SetHeight(SESS_H); r:EnableMouse(true)
    r.bg=r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1,1,1,0.05); r.bg:Hide()
    r.sep=r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1)
    r.sep:SetColorTexture(ns.COL_BORDER[1],ns.COL_BORDER[2],ns.COL_BORDER[3],0.55); r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT")
    -- Single-line: [Dauer] [Gold] [X]
    r.dateText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.dateText:SetPoint("LEFT",6,0); r.dateText:SetTextColor(0.9,0.9,0.9); r.dateText:SetFontHeight(ns.FONT_NORMAL)
    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",-22,0); r.goldText:SetJustifyH("RIGHT"); r.goldText:SetFontHeight(ns.FONT_NORMAL)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    r.delBtn = ns.CreateCloseButton(r, 18, 0.5, ns.L["delete_session"]); r.delBtn:SetPoint("RIGHT",-2,0)
    r:SetScript("OnEnter",function(self)
        self.bg:Show(); self.dateText:SetTextColor(unpack(ns.COL_GOLD))
        local sess = self.session
        local lg = sess and (sess.lootedGold or 0) or 0
        if lg > 0 then
            local itemGold = sess.totalGold or 0
            GameTooltip:SetOwner(self,"ANCHOR_LEFT")
            GameTooltip:AddLine(ns.L["gold_overview"], unpack(ns.COL_ACCENT))
            GameTooltip:AddDoubleLine(ns.L["gold_items"], ns.FormatGold(itemGold), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["looted_gold"], ns.FormatGold(lg), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["gold_total"], ns.FormatGold(itemGold+lg), 0.75,0.75,0.75, unpack(ns.COL_GOLD))
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave",function(self) self.bg:Hide(); self.dateText:SetTextColor(0.9,0.9,0.9); GameTooltip:Hide() end)
    return r
end
local function ReleaseSessRow(r)
    r:Hide(); r:ClearAllPoints(); r.session=nil; r:SetScript("OnMouseUp",nil); sessPool[#sessPool+1]=r
end

local function AcquireDayRow()
    local r=table.remove(dayPool)
    if r then r:SetParent(HListFrame); r:Show(); return r end
    r=CreateFrame("Frame",nil,HListFrame); r:SetHeight(DAY_H); r:EnableMouse(true)
    ns.AddHeaderBand(r)
    r.dateText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.dateText:SetPoint("LEFT",4,0); r.dateText:SetFontHeight(ns.FONT_NORMAL); r.dateText:SetTextColor(unpack(ns.COL_ACCENT))
    r.infoText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.infoText:SetPoint("LEFT",r.dateText,"RIGHT",10,0); r.infoText:SetFontHeight(ns.FONT_SMALL); r.infoText:SetTextColor(0.45,0.45,0.45)
    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",0,0); r.goldText:SetJustifyH("RIGHT"); r.goldText:SetFontHeight(ns.FONT_NORMAL)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))

    r.mergeBtn = CreateFrame("Button", nil, r)
    r.mergeBtn:SetSize(40, DAY_H - 4)
    r.mergeBtn:SetPoint("RIGHT", r.goldText, "LEFT", -8, 0)
    r.mergeBtn.text = r.mergeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.mergeBtn.text:SetAllPoints(); r.mergeBtn.text:SetJustifyH("RIGHT")
    r.mergeBtn.text:SetFontHeight(ns.FONT_SMALL); r.mergeBtn.text:SetTextColor(unpack(ns.COL_ACCENT))
    r.mergeBtn.text:SetText(ns.L["merge_day_btn"])
    r.mergeBtn:SetScript("OnEnter", function()
        r.mergeBtn.text:SetTextColor(1,1,1)
        GameTooltip:SetOwner(r.mergeBtn,"ANCHOR_TOP"); GameTooltip:SetText(ns.L["merge_day_tooltip"]); GameTooltip:Show()
    end)
    r.mergeBtn:SetScript("OnLeave", function()
        r.mergeBtn.text:SetTextColor(unpack(ns.COL_ACCENT)); GameTooltip:Hide()
    end)
    r.mergeBtn:Hide()
    return r
end
local function ReleaseDayRow(r)
    r:Hide(); r:ClearAllPoints()
    r:SetScript("OnMouseUp",nil); r:SetScript("OnEnter",nil); r:SetScript("OnLeave",nil)
    r.dateText:SetTextColor(unpack(ns.COL_ACCENT))
    r.mergeBtn:Hide(); r.mergeBtn:SetScript("OnClick", nil)
    dayPool[#dayPool+1]=r
end

------------------------------------------------------------------------
-- Month header row pool (collapsible grouping for past months)
------------------------------------------------------------------------
local activeMonthRows={} local monthPool={}

local function AcquireMonthRow()
    local r=table.remove(monthPool)
    if r then r:SetParent(HListFrame); r:Show(); return r end
    r=CreateFrame("Frame",nil,HListFrame); r:SetHeight(MONTH_H); r:EnableMouse(true)
    ns.AddHeaderBand(r)
    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",ns.HEADER_TEXT_X,0); r.nameText:SetFontHeight(ns.FONT_NORMAL)
    r.nameText:SetTextColor(unpack(ns.COL_ACCENT))
    r.delBtn = ns.CreateCloseButton(r, 18, 0.5, ns.L["delete_month"]); r.delBtn:SetPoint("RIGHT",-2,0)
    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",r.delBtn,"LEFT",-6,0); r.goldText:SetJustifyH("RIGHT"); r.goldText:SetFontHeight(ns.FONT_NORMAL)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    r:SetScript("OnEnter",function(self) self.nameText:SetTextColor(1,1,1) end)
    r:SetScript("OnLeave",function(self) self.nameText:SetTextColor(unpack(ns.COL_ACCENT)); GameTooltip:Hide() end)
    return r
end
local function ReleaseMonthRow(r)
    -- OnEnter is replaced per rebuild, but OnLeave (reset color, hide
    -- tooltip) is only set once at creation, so it must survive pooling.
    r:Hide(); r:ClearAllPoints(); r:SetScript("OnMouseUp",nil)
    r.delBtn:SetScript("OnClick",nil)
    r.nameText:SetTextColor(unpack(ns.COL_ACCENT))
    monthPool[#monthPool+1]=r
end

------------------------------------------------------------------------
-- Detail row pools — single-line, same as main frame
------------------------------------------------------------------------
local activeDetRows = {}
local activeDetCats = {}
local detRowPool    = {}
local detCatPool    = {}
local detCollapsed  = {}
local currentDetailSession = nil
local historyTotals = nil -- {items, looted} gold over all saved months, shown in the History title hover
local detailStats = nil   -- {kinds = distinct item rows, qty = total amount} of currentDetailSession, shown in the header hover

local function AcquireDetRow()
    local r = table.remove(detRowPool)
    if r then r:SetParent(DListFrame); r:Show(); return r end
    r = CreateFrame("Frame", nil, DListFrame)
    r:SetSize(DET_CONT_W, DET_ROW_H)
    r:EnableMouse(true)

    ns.AddRowIcon(r):SetPoint("LEFT", ns.ICON_X, 0)
    r.rankBadge = ns.CreateIconBadge(r, r.icon)

    -- Single-line: icon | name | count | gold (y=0 = centered with icon)
    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",  r.icon, "RIGHT", 4, 0)
    r.nameText:SetPoint("RIGHT", r,           "RIGHT", -128, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(ns.FONT_NORMAL); r.nameText:SetWordWrap(false)

    r.countText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.countText:SetPoint("RIGHT", r, "RIGHT", -90, 0)
    r.countText:SetJustifyH("RIGHT"); r.countText:SetTextColor(0.78,0.78,0.78); r.countText:SetFontHeight(ns.FONT_NORMAL)

    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.goldText:SetJustifyH("RIGHT"); r.goldText:SetTextColor(unpack(ns.COL_GOLD)); r.goldText:SetFontHeight(ns.FONT_NORMAL)

    r:SetScript("OnEnter", function(self)
        -- DetailFrame docks LEFT of HistFrame, so its right side is
        -- structurally occupied - prefer LEFT here (see ns.SmartAnchor).
        local anchor = ns.SmartAnchor(self, "LEFT")
        if self.itemLink then
            ns.ShowItemTooltipNoCompare(self, anchor, self.itemLink)
        elseif self.itemID then
            -- Old session saved before the itemLink fix - for equipment,
            -- SetItemByID would show the generic base item (wrong item
            -- level/stats for scaling gear), so show just the name instead
            -- of a tooltip that looks precise but could be misleading.
            if ns.IsGearClass(self.classID) then
                GameTooltip:SetOwner(self, anchor)
                GameTooltip:AddLine(self.itemName or "", 1,1,1)
                GameTooltip:AddLine(ns.L["tooltip_scaling_unknown"], 0.6,0.6,0.6, true)
                GameTooltip:Show()
            else
                ns.ShowItemTooltipNoCompare(self, anchor, nil, self.itemID)
            end
        elseif self.itemName then
            GameTooltip:SetOwner(self, anchor)
            GameTooltip:AddLine(self.itemName, 1,1,1)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hover area over the gold amount: shows how many of the items were
    -- valued at AH price and how many at vendor price (see BuildSessionCategories).
    r.goldHit = CreateFrame("Frame", nil, r)
    r.goldHit:SetPoint("TOPLEFT",     r.goldText, "TOPLEFT",     -4,  2)
    r.goldHit:SetPoint("BOTTOMRIGHT", r.goldText, "BOTTOMRIGHT",  4, -2)
    r.goldHit:EnableMouse(true)
    r.goldHit:Hide()
    r.goldHit:SetScript("OnEnter", function(self)
        local b = r.breakdown
        if not b then return end
        GameTooltip:SetOwner(self, ns.SmartAnchor(r, "LEFT"))
        GameTooltip:AddLine(r.itemName or "", 1, 1, 1)
        if b.ahN > 0 then
            GameTooltip:AddDoubleLine(string.format(ns.L["tip_priced_ah"], b.ahN),
                ns.FormatGold(b.ahV), 0.75,0.75,0.75, 1,1,1)
        end
        if b.vN > 0 then
            GameTooltip:AddDoubleLine(string.format(ns.L["tip_priced_vendor"], b.vN),
                ns.FormatGold(b.vV), 0.75,0.75,0.75, 1,1,1)
        end
        GameTooltip:Show()
    end)
    r.goldHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function ReleaseDetRow(r)
    r:Hide(); r:ClearAllPoints(); r.itemID=nil; r.itemLink=nil; r.classID=nil; r.itemName=nil; r.iconBorder:Hide()
    r.breakdown=nil; r.goldHit:Hide()
    r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", ns.ICON_X, 0)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    r.rankBadge:SetText("")
    detRowPool[#detRowPool+1]=r
end

local function AcquireDetCat()
    local r = table.remove(detCatPool)
    if r then r:SetParent(DListFrame); r:Show(); return r end
    r = CreateFrame("Frame", nil, DListFrame); r:SetHeight(DET_CAT_H)
    r:EnableMouse(true)
    ns.AddHeaderBand(r)
    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",ns.HEADER_TEXT_X,0); r.nameText:SetPoint("RIGHT",r,"RIGHT",-100,0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(ns.FONT_NORMAL); r.nameText:SetTextColor(unpack(ns.COL_ACCENT))
    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",r,"RIGHT",-4,0); r.goldText:SetJustifyH("RIGHT")
    r.goldText:SetFontHeight(ns.FONT_NORMAL); r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    return r
end
local function ReleaseDetCat(r)
    r:Hide(); r:ClearAllPoints(); r:SetHeight(DET_CAT_H); detCatPool[#detCatPool+1]=r
end

------------------------------------------------------------------------
-- Session detail window
------------------------------------------------------------------------
local function EnsureDetailFrame()
    if DListFrame then return end
    DetailFrame = CreateFrame("Frame","NightsFarmtrackerDetailWnd",UIParent,"BackdropTemplate")
    DetailFrame:SetWidth(DET_W)
    DetailFrame:SetFrameStrata("MEDIUM"); DetailFrame:SetClampedToScreen(true)
    DetailFrame:SetMovable(true); DetailFrame:EnableMouse(true)
    DetailFrame:RegisterForDrag("LeftButton")
    DetailFrame:SetScript("OnDragStart",function(s) s:StartMoving() end)
    DetailFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    ns.ApplyFrameStyle(DetailFrame); DetailFrame:Hide()
    ns.DetailFrame = DetailFrame  -- exposed so Settings can close it when it opens
    DetailFrame:HookScript("OnHide", function(self) ns.HideTooltipOf(self) end)
    table.insert(UISpecialFrames,"NightsFarmtrackerDetailWnd")

    -- Header: single line "Date  ·  Duration  ·  Total Gold"
    DetailFrame.dateText = DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    DetailFrame.dateText:SetPoint("TOPLEFT",  DET_PAD, -12)
    DetailFrame.dateText:SetPoint("TOPRIGHT", -DET_PAD, -12)
    DetailFrame.dateText:SetJustifyH("CENTER")
    DetailFrame.dateText:SetTextColor(unpack(ns.COL_GOLD)); DetailFrame.dateText:SetFontHeight(ns.FONT_HEADER)

    -- Invisible hitbox over the header line: hovering the combined total
    -- shows the Items/Direct/Total breakdown instead of a permanent
    -- second line, so the header number and the History list agree.
    -- Right edge stops short of the close button (18px + gap) instead of
    -- matching dateText's full width - otherwise this hitbox sits on top
    -- of the close button and swallows the click meant for it.
    local headerHit = CreateFrame("Frame", nil, DetailFrame)
    headerHit:SetPoint("TOPLEFT", DetailFrame.dateText, "TOPLEFT", 0, 4)
    headerHit:SetPoint("BOTTOMRIGHT", DetailFrame.dateText, "BOTTOMRIGHT", -24, -4)
    headerHit:EnableMouse(true)
    headerHit:SetScript("OnEnter", function(self)
        local session = currentDetailSession
        if not session then return end
        local itemGold = session.totalGold or 0
        local lg       = session.lootedGold or 0
        local total    = itemGold + lg
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L["gold_overview"], unpack(ns.COL_ACCENT))
        GameTooltip:AddDoubleLine(ns.L["detail_duration"], ns.FormatTime(session.duration), 0.75,0.75,0.75, 1,1,1)
        if detailStats then
            GameTooltip:AddDoubleLine(ns.L["detail_item_kinds"], BreakUpLargeNumbers(detailStats.kinds), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["detail_item_qty"], BreakUpLargeNumbers(detailStats.qty), 0.75,0.75,0.75, 1,1,1)
        end
        if total > 0 then
            GameTooltip:AddDoubleLine(ns.L["gold_items"], ns.FormatGold(itemGold), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["looted_gold"], ns.FormatGold(lg), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["gold_total"], ns.FormatGold(total), 0.75,0.75,0.75, unpack(ns.COL_GOLD))
        end
        GameTooltip:Show()
    end)
    headerHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local hSep = DetailFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT",DET_PAD,-(DET_HDR_H-1)); hSep:SetPoint("TOPRIGHT",-DET_PAD,-(DET_HDR_H-1))

    local xBtn = ns.CreateCloseButton(DetailFrame, 18, 0.8); xBtn:SetPoint("TOPRIGHT",-DET_PAD,-10)
    xBtn:SetScript("OnClick",function()
        if not ns.DeferInCombat(function() DetailFrame:Hide() end) then DetailFrame:Hide() end
    end)

    DScrollFrame = CreateFrame("ScrollFrame",nil,DetailFrame)
    DScrollFrame:SetPoint("TOPLEFT",DET_PAD,-DET_HDR_H); DScrollFrame:SetWidth(DET_CONT_W)
    DScrollFrame:EnableMouseWheel(true)
    DListFrame = CreateFrame("Frame",nil,DScrollFrame)
    DListFrame:SetWidth(DET_CONT_W); DListFrame:SetHeight(1)
    DScrollFrame:SetScrollChild(DListFrame)
    local OnWheel = ns.MakeWheelHandler(DScrollFrame, DListFrame, DET_ROW_H)
    DScrollFrame:SetScript("OnMouseWheel",OnWheel)
    DListFrame:EnableMouseWheel(true); DListFrame:SetScript("OnMouseWheel",OnWheel)

end

-- Row gold text. Plain rows and rows with a frozen AH/vendor split show
-- entry.gold (the exact value the list was sorted by - BuildSessionCategories
-- takes the LARGER of AH and vendor); older variant/tier rows show their AH
-- total, else their vendor total.
local function SetDetailGold(ir, entry)
    local value = entry.gold
    if (entry.isRank or entry.isGearVariant) and not entry.breakdown then
        value = (entry.tAH and entry.tAH > 0) and entry.tAH or entry.tV
    end
    ir.goldText:SetText(value and value > 0 and ns.FormatGold(value) or "")
end

-- Item name, icon, count and tooltip fields of one Detail row.
local function FillDetailRow(ir, entry)
    local d = entry.d
    ir.icon:SetTexture(d.icon or ns.FALLBACK_ICON)
    ns.ApplyQualityColor(ir.nameText, ir.iconBorder, d.quality, {1,1,1})
    ir.goldText:SetTextColor(unpack(ns.COL_GOLD))  -- always gold, like the main window
    ir.classID = d.classID
    ir.itemName = entry.name
    if entry.isRank then
        ir.itemID = entry.tid
        ir.itemLink = nil
        ir.nameText:SetText(ns.TruncateName(ns.DisplayName(entry.name, entry.tid)))
        ir.rankBadge:SetText(entry.rankIcon or "")
        ir.countText:SetText(tostring(entry.tc))
    elseif entry.isGearVariant then
        local gv = entry.gv
        ns.ApplyQualityColor(ir.nameText, ir.iconBorder, gv.quality, {1,1,1})
        ir.itemID = d.itemID
        ir.itemLink = gv.itemLink
        ir.nameText:SetText(ns.TruncateName(ns.DisplayName(entry.name, gv.itemLink or d.itemID)))
        ir.rankBadge:SetText("")
        ir.countText:SetText(tostring(gv.amount))
    else
        ir.itemID = d.itemID
        ir.itemLink = d.itemLink
        ir.nameText:SetText(d.isJunkMerged and ns.TruncateName(entry.name) or ns.TruncateName(ns.DisplayName(entry.name, d.itemID)))
        ir.rankBadge:SetText(entry.rankIcon or "")
        ir.countText:SetText(tostring(d.amount))
    end
    SetDetailGold(ir, entry)
    -- AH/vendor split for the gold-hover tooltip (only known for sessions
    -- saved with the frozen split).
    ir.breakdown = entry.breakdown
    ir.goldHit:SetShown(entry.breakdown ~= nil)
end

local function RebuildDetailContent(session)
    currentDetailSession = session
    for _,r in ipairs(activeDetRows) do ReleaseDetRow(r) end
    for _,r in ipairs(activeDetCats) do ReleaseDetCat(r)  end
    activeDetRows={}; activeDetCats={}

    local cats, catOrder = ns.BuildSessionCategories(session)

    -- Item counts for the header hover; counted over all categories, so
    -- collapsing one doesn't change them.
    local kinds, qty = 0, 0
    for _, catName in ipairs(catOrder) do
        for _, entry in ipairs(cats[catName].items) do
            kinds = kinds + 1
            qty = qty + (tonumber(entry.isRank and entry.tc or entry.isGearVariant and entry.gv.amount or entry.d.amount) or 0)
        end
    end
    detailStats = { kinds = kinds, qty = qty }

    local yOff = 0
    local flow = ns.NewHeaderFlow()
    for _, catName in ipairs(catOrder) do
        local cat = cats[catName]
        if #cat.items > 0 then
            local ch = AcquireDetCat(); ch:SetSize(DET_CONT_W, DET_CAT_H); ch:SetPoint("TOPLEFT",0,-yOff)
            flow.header(ch)
            local isCollapsed = detCollapsed[catName]
            ns.SetHeaderArrow(ch, isCollapsed)
            ch.nameText:SetText(catName)
            ch.goldText:SetText(cat.gold > 0 and ns.FormatGold(cat.gold) or "")
            ch:SetScript("OnMouseUp", function()
                detCollapsed[catName] = not detCollapsed[catName]
                RebuildDetailContent(currentDetailSession)
            end)
            activeDetCats[#activeDetCats+1]=ch; yOff = yOff + DET_CAT_H

            if not isCollapsed then
                yOff = yOff + ns.CAT_GAP
                for _, entry in ipairs(cat.items) do
                    local ir = AcquireDetRow(); ir:SetWidth(DET_CONT_W); ir:SetPoint("TOPLEFT",0,-yOff)
                    FillDetailRow(ir, entry)
                    activeDetRows[#activeDetRows+1]=ir; yOff = yOff + DET_ROW_H
                end
                yOff = yOff + ns.CAT_GAP
                flow.rows()
            end
        end
    end

    DScrollFrame:SetVerticalScroll(0)
    ns.FitScrollWindow({
        window = DetailFrame, scroll = DScrollFrame, list = DListFrame,
        hdrH = DET_HDR_H, ftrH = DET_FTR_H, contentH = yOff,
    })
end

-- Builds a virtual, non-persisted session that merges every real session
-- belonging to one calendar month, so the existing Detail window (same
-- one used for isMonthCompact entries) can render a month-wide summary
-- on demand without touching saved data.
local function BuildMonthAggregate(mKey, month)
    local agg = {
        timestamp = ns.EndOfMonthTimestamp(mKey), isMonthCompact = true,
        duration = 0, totalGold = 0, totalVendor = 0, totalAH = 0,
        lootedGold = 0, items = {}, qAtlas = {},
    }
    for _, session in ipairs(month.sessionsList or {}) do
        ns.MergeSessionInto(agg, session, false)
    end
    return agg
end

local function ShowDetail(session)
    if ns.DeferInCombat(function() ShowDetail(session) end) then return end
    EnsureDetailFrame()
    detCollapsed = {}
    local dateStr
    if session.isMonthCompact then
        dateStr = (ns.L.MONTH_NAMES[tonumber(date("%m", session.timestamp))] or "")
            .." "..date("%Y", session.timestamp)
    else
        dateStr = date("%d.%m.%Y", session.timestamp)
    end
    DetailFrame.dateText:SetText(dateStr)
    RebuildDetailContent(session)
    ns.DockFrame(DetailFrame, HistFrame, "left")
    DetailFrame:Show()
end

------------------------------------------------------------------------
-- RebuildHistory
------------------------------------------------------------------------
function ns.RebuildHistory()
    if not HListFrame then return end
    for _,r in ipairs(activeSessRows)  do ReleaseSessRow(r)  end
    for _,r in ipairs(activeDayRows)   do ReleaseDayRow(r)   end
    for _,r in ipairs(activeMonthRows) do ReleaseMonthRow(r) end
    activeSessRows={}; activeDayRows={}; activeMonthRows={}
    local sessions=(NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions) or {}

    -- sessions is keyed by "YYYY-MM-DD" (each value an array of that day's
    -- sessions, newest first) - table iteration order is undefined, so
    -- build a sorted list of day keys ourselves. ISO-format strings sort
    -- lexicographically in the same order as chronologically, so a plain
    -- string sort works.
    local storageDayKeys = {}
    for k in pairs(sessions) do storageDayKeys[#storageDayKeys+1] = k end
    table.sort(storageDayKeys, function(a,b) return a > b end)

    -- Group sessions by calendar day (order follows the sorted day keys
    -- above, newest first; within a day, the stored array is already
    -- newest-first too).
    local nTotal = 0
    local days,dayOrder={},{}
    for _, dayKey in ipairs(storageDayKeys) do
        for sessIdx, session in ipairs(sessions[dayKey]) do
            nTotal = nTotal + 1
            local dStr=date("%d.%m.%Y",session.timestamp)
            if not days[dStr] then
                days[dStr]={
                    totalGold=0, sessions={}, dayKey=dayKey,
                    monthKey=date("%Y-%m",session.timestamp),
                    monthLabel=(ns.L.MONTH_NAMES[tonumber(date("%m",session.timestamp))] or "")
                        .." "..date("%Y",session.timestamp),
                }
                dayOrder[#dayOrder+1]=dStr
            end
            days[dStr].totalGold=days[dStr].totalGold+session.totalGold
            days[dStr].lootedGold=(days[dStr].lootedGold or 0)+(session.lootedGold or 0)
            days[dStr].sessions[#days[dStr].sessions+1]={session=session,dayKey=dayKey,sessIdx=sessIdx}
        end
    end

    -- Group days into months, preserving day order
    local months,monthOrder={},{}
    local currentMonthKey=date("%Y-%m")
    for _,dStr in ipairs(dayOrder) do
        local day=days[dStr]; local mKey=day.monthKey
        if not months[mKey] then
            months[mKey]={label=day.monthLabel,totalGold=0,sessionCount=0,dayList={},sessionsList={},isCurrent=(mKey==currentMonthKey)}
            monthOrder[#monthOrder+1]=mKey
        end
        months[mKey].totalGold=months[mKey].totalGold+day.totalGold
        months[mKey].lootedGold=(months[mKey].lootedGold or 0)+(day.lootedGold or 0)
        months[mKey].sessionCount=months[mKey].sessionCount+#day.sessions
        table.insert(months[mKey].dayList,dStr)
        for _,entry in ipairs(day.sessions) do
            months[mKey].sessionsList[#months[mKey].sessionsList+1]=entry.session
        end
    end

    -- Totals over all months for the title hover
    local tot = { items=0, looted=0 }
    for _,mKey in ipairs(monthOrder) do
        local m=months[mKey]
        tot.items=tot.items+m.totalGold
        tot.looted=tot.looted+(m.lootedGold or 0)
    end
    historyTotals = tot

    local accDB=NightsFarmtrackerAccountDB
    accDB.collapsedMonths=accDB.collapsedMonths or {}

    local yOffset=0
    local flow=ns.NewHeaderFlow()
    for _,mKey in ipairs(monthOrder) do
        local month=months[mKey]
        -- default: current month expanded, past months collapsed — user choice wins
        local collapsed=accDB.collapsedMonths[mKey]
        if collapsed==nil then collapsed=not month.isCurrent end
        local mrow=AcquireMonthRow(); mrow:SetSize(ns.CONTENT_W, MONTH_H); mrow:SetPoint("TOPLEFT",0,-yOffset)
        flow.header(mrow)
        ns.SetHeaderArrow(mrow, collapsed)
        mrow.nameText:SetText(month.label)
        local monthCombined = (month.totalGold or 0) + (month.lootedGold or 0)
        mrow.goldText:SetText(monthCombined>0 and ns.FormatGold(monthCombined) or "")
        mrow:SetScript("OnEnter",function(self)
            self.nameText:SetTextColor(1,1,1)
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:AddLine(ns.L["month_summary_tooltip"])
            if monthCombined>0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(ns.L["gold_items"], ns.FormatGold(month.totalGold or 0), 0.75,0.75,0.75, 1,1,1)
                GameTooltip:AddDoubleLine(ns.L["looted_gold"], ns.FormatGold(month.lootedGold or 0), 0.75,0.75,0.75, 1,1,1)
                GameTooltip:AddDoubleLine(ns.L["gold_total"], ns.FormatGold(monthCombined), 0.75,0.75,0.75, unpack(ns.COL_GOLD))
            end
            GameTooltip:Show()
        end)
        mrow:SetScript("OnMouseUp",function(self)
            if self.delBtn:IsMouseOver() then return end
            if IsShiftKeyDown() then
                if #month.sessionsList > 0 then
                    ShowDetail(BuildMonthAggregate(mKey, month))
                end
            else
                accDB.collapsedMonths[mKey]=not collapsed
                ns.RebuildHistory()
            end
        end)
        mrow.delBtn:SetScript("OnClick",function()
            StaticPopup_Show("NFT_CONFIRM_DELETE_MONTH",
                string.format(ns.L["delete_month_confirm"], month.sessionCount, month.label), nil, mKey)
        end)
        activeMonthRows[#activeMonthRows+1]=mrow; yOffset=yOffset+MONTH_H
        if not collapsed then
            -- flush: month row already draws its own bottom line, first day row starts right after it
            for _,dStr in ipairs(month.dayList) do
                local day=days[dStr]
                -- A past month with exactly one day/session (e.g. after
                -- compaction) doesn't need its own date subheader — the
                -- month header already says everything there is to say.
                local skipDayRow = (not month.isCurrent) and #month.dayList==1 and #day.sessions==1
                if not skipDayRow then
                    local drow=AcquireDayRow(); drow:SetSize(ns.CONTENT_W, DAY_H); drow:SetPoint("TOPLEFT",0,-yOffset)
                    flow.header(drow)
                    drow.dateText:SetText(dStr)
                    drow.goldText:SetText("")
                    if #day.sessions > 1 then
                        drow.mergeBtn:Show()
                        drow.mergeBtn:SetScript("OnClick", function()
                            StaticPopup_Show("NFT_CONFIRM_MERGE_DAY",
                                string.format(ns.L["merge_day_confirm"], #day.sessions, dStr), nil, day.dayKey)
                        end)
                    else
                        drow.mergeBtn:Hide()
                    end
                    activeDayRows[#activeDayRows+1]=drow; yOffset=yOffset+DAY_H
                end
                for si,entry in ipairs(day.sessions) do
                    local session=entry.session
                    local row=AcquireSessRow(); row:SetWidth(ns.CONTENT_W); row:SetPoint("TOPLEFT",0,-yOffset)
                    row.sep:SetShown(si < #day.sessions)   -- only between sessions; a header line follows the last one
                    row.session=session
                    local combinedGold = (session.totalGold or 0) + (session.lootedGold or 0)
                    row.dateText:SetText(ns.FormatTime(session.duration))
                    row.goldText:SetText(combinedGold>0 and ns.FormatGold(combinedGold) or "")
                    local sess=session
                    row:SetScript("OnMouseUp",function(self,btn)
                        if btn=="LeftButton" and not self.delBtn:IsMouseOver() then
                            if DetailFrame and DetailFrame:IsShown() and currentDetailSession == sess then
                                if not ns.DeferInCombat(function() DetailFrame:Hide() end) then DetailFrame:Hide() end
                            else
                                ShowDetail(sess)
                            end
                        end
                    end)
                    row.delBtn:SetScript("OnClick",function()
                        local dayList = NightsFarmtrackerAccountDB.sessions[entry.dayKey]
                        if dayList then
                            table.remove(dayList, entry.sessIdx)
                            if #dayList == 0 then NightsFarmtrackerAccountDB.sessions[entry.dayKey] = nil end
                        end
                        ns.RebuildHistory()
                    end)
                    activeSessRows[#activeSessRows+1]=row; yOffset=yOffset+SESS_H
                    flow.rows()
                end
            end
        end
    end
    local visH = ns.FitScrollWindow({
        window=HistFrame, scroll=HScrollFrame, list=HListFrame, anchored=true,
        hdrH=H_HDR_H, ftrH=H_FTR_H, contentH=yOffset,
        minH=yOffset==0 and 44 or nil,   -- empty: room for the "no sessions" label
    })
    if HistFrame.footerSep then
        ns.SetFooterLine(HistFrame.footerSep, flow, yOffset == 0 or visH < yOffset)
    end
    -- nTotal already counted above while grouping by day
    if nTotal==0 then
        HistFrame.countLabel:SetText("")
        HistFrame.emptyLabel:SetText(ns.L["no_sessions"])
        HistFrame.emptyLabel:Show()
        if HistFrame.clrBtn then HistFrame.clrBtn:Hide() end
    else
        HistFrame.emptyLabel:Hide()
        if HistFrame.clrBtn then HistFrame.clrBtn:Show() end
        local key = (nTotal == 1) and ns.L["sessions_summary"] or ns.L["sessions_summary_pl"]
        HistFrame.countLabel:SetText(string.format(key, nTotal))
    end
end

------------------------------------------------------------------------
-- Build history list window (lazy)
------------------------------------------------------------------------
local function EnsureHistFrame()
    if HListFrame then return end
    HistFrame = ns.CreateWindowFrame("NightsFarmtrackerHistoryWnd", ns.L["session_history"], {width = H_W})
    ns.HistFrame = HistFrame  -- exposed so Settings can dock next to it in the left-side chain
    HistFrame:SetScript("OnHide",function(self)
        ns.HideTooltipOf(self)  -- explicit: don't rely on the shell's hook surviving SetScript
        if DetailFrame then DetailFrame:Hide() end
        ns.RefreshWindowChain("left")
    end)

    local hSep=HistFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT",H_PAD,-(H_HDR_H-1)); hSep:SetPoint("TOPRIGHT",-H_PAD,-(H_HDR_H-1))

    -- Hover on the title: gold of all saved months added up. The right edge
    -- stops short of the close button so the hitbox doesn't swallow its click.
    local titleHit = CreateFrame("Frame", nil, HistFrame)
    titleHit:SetPoint("TOPLEFT", HistFrame.titleFS, "TOPLEFT", 0, 4)
    titleHit:SetPoint("BOTTOMRIGHT", HistFrame.titleFS, "BOTTOMRIGHT", -24, -4)
    titleHit:EnableMouse(true)
    -- The title is the window's drag handle: pass dragging through to the window
    titleHit:RegisterForDrag("LeftButton")
    titleHit:SetScript("OnDragStart", function() HistFrame:StartMoving() end)
    titleHit:SetScript("OnDragStop",  function() HistFrame:StopMovingOrSizing() end)
    titleHit:SetScript("OnEnter", function(self)
        local t = historyTotals
        if not t then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L["history_total_title"], unpack(ns.COL_ACCENT))
        GameTooltip:AddDoubleLine(ns.L["gold_items"], ns.FormatGold(t.items), 0.75,0.75,0.75, 1,1,1)
        GameTooltip:AddDoubleLine(ns.L["looted_gold"], ns.FormatGold(t.looted), 0.75,0.75,0.75, 1,1,1)
        GameTooltip:AddDoubleLine(ns.L["gold_total"], ns.FormatGold(t.items + t.looted), 0.75,0.75,0.75, unpack(ns.COL_GOLD))
        GameTooltip:Show()
    end)
    titleHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    HScrollFrame=CreateFrame("ScrollFrame",nil,HistFrame)
    HScrollFrame:SetPoint("TOPLEFT",H_PAD,-H_HDR_H); HScrollFrame:SetPoint("BOTTOMRIGHT",-H_PAD,H_FTR_H)
    HScrollFrame:EnableMouseWheel(true)
    HListFrame=CreateFrame("Frame",nil,HScrollFrame)
    HListFrame:SetWidth(ns.CONTENT_W); HListFrame:SetHeight(1)
    HScrollFrame:SetScrollChild(HListFrame)
    local OnWheel = ns.MakeWheelHandler(HScrollFrame, HListFrame, SESS_H)
    HScrollFrame:SetScript("OnMouseWheel",OnWheel)
    HListFrame:EnableMouseWheel(true); HListFrame:SetScript("OnMouseWheel",OnWheel)

    local fSep=HistFrame:CreateTexture(nil,"ARTWORK"); fSep:SetHeight(1)
    fSep:SetColorTexture(unpack(ns.COL_BORDER))
    fSep:SetPoint("BOTTOMLEFT",H_PAD,H_FTR_H-2); fSep:SetPoint("BOTTOMRIGHT",-H_PAD,H_FTR_H-2)
    HistFrame.footerSep = fSep

    HistFrame.countLabel = HistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    HistFrame.countLabel:SetPoint("BOTTOMLEFT",H_PAD,8); HistFrame.countLabel:SetTextColor(0.40,0.40,0.40)

    HistFrame.emptyLabel = HistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    HistFrame.emptyLabel:SetPoint("TOP",HistFrame,"TOP",0,-(H_HDR_H+22))
    HistFrame.emptyLabel:SetJustifyH("CENTER")
    HistFrame.emptyLabel:SetTextColor(0.55,0.55,0.55)
    HistFrame.emptyLabel:Hide()

    HistFrame.clrBtn = ns.CreateClearAllButton(HistFrame, H_PAD, function()
        return NightsFarmtrackerAccountDB.sessions and next(NightsFarmtrackerAccountDB.sessions) ~= nil
    end, "NFT_CONFIRM_CLEAR_ALL_HISTORY")
    HistFrame.clrBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(ns.L["delete_all"]); GameTooltip:Show()
    end)
    HistFrame.clrBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleHistory()
    if ns.DeferInCombat(ns.ToggleHistory) then return end
    EnsureHistFrame()
    if HistFrame:IsShown() then
        HistFrame:Hide()
        if DetailFrame then DetailFrame:Hide() end
    else
        -- Settings docks off the same anchor point as History, so close
        -- it first to avoid overlap.
        if ns.SettingsFrame and ns.SettingsFrame:IsShown() then ns.SettingsFrame:Hide() end
        ns.RebuildHistory()
        HistFrame:Show()
        ns.RefreshWindowChain("left")
    end
end
