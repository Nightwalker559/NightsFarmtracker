------------------------------------------------------------------------
-- Night's Farmtracker - History
-- Narrower windows. Detail matches main frame width & single-line rows.
------------------------------------------------------------------------
local _, ns = ...
local ART = "Interface\\AddOns\\NightsFarmtracker\\Media\\"

------------------------------------------------------------------------
-- Layout — history list
------------------------------------------------------------------------
local H_W      = ns.FRAME_W
local H_PAD    = 10
local H_HDR_H  = ns.HDR_TOTAL     -- same as main frame header
local H_FTR_H  = 28
local H_CONT_W = H_W - H_PAD * 2
local DAY_H    = ns.CAT_ROW_H     -- same height as category headers in main/detail frame
local SESS_H   = 38
local MAX_VIS_H = 10 * SESS_H

------------------------------------------------------------------------
-- Layout — detail window (matches main frame width)
------------------------------------------------------------------------
local DET_W      = ns.FRAME_W          -- same as main frame
local DET_PAD    = ns.PAD
local DET_HDR_H  = ns.HDR_TOTAL   -- same as main frame header
local DET_FTR_H  = 30
local DET_CONT_W = ns.CONTENT_W
local DET_CAT_H  = ns.CAT_ROW_H
local DET_ROW_H  = ns.ROW_H
local DET_MAX_H  = ns.MAX_ROWS * DET_ROW_H

------------------------------------------------------------------------
-- Session save
------------------------------------------------------------------------
local MAX_SESSIONS = 50

function ns.SaveCurrentSession()
    local db = NightsFarmtrackerDB
    if not db or not next(db.count or {}) then return end
    if (db.totalTime or 0) < 10 then return end
    if not NightsFarmtrackerAccountDB then NightsFarmtrackerAccountDB = {} end
    if not NightsFarmtrackerAccountDB.sessions then NightsFarmtrackerAccountDB.sessions = {} end
    local sessions = NightsFarmtrackerAccountDB.sessions
    local newEntry = {
        timestamp=time(), duration=math.floor(db.totalTime),
        totalGold=0, totalVendor=0, totalAH=0, items={},
        qAtlas=db.qAtlas or {},
    }
    for name, data in pairs(db.count) do
        local vendor = ns.VendorTotal(data)
        local ah     = ns.AHTotal(data)
        local val    = (ah and vendor) and math.max(ah,vendor) or ah or vendor or 0
        newEntry.totalGold   = newEntry.totalGold   + val
        newEntry.totalVendor = newEntry.totalVendor + (vendor or 0)
        newEntry.totalAH     = newEntry.totalAH     + (ah or 0)
        newEntry.items[name] = {
            amount=data.amount, icon=data.icon, quality=data.quality,
            itemSubType=data.itemSubType, sellPrice=data.sellPrice,
            vendorTotal=vendor, ahTotal=ah,
            isVendorTrash=data.isVendorTrash, isBoE=data.isBoE, isBoP=data.isBoP,
            classID=data.classID, itemID=data.itemID, q=data.q, qIDs=data.qIDs,
        }
    end
    local today = date("%d.%m.%Y")
    if #sessions > 0 and date("%d.%m.%Y", sessions[1].timestamp) == today then
        local ex = sessions[1]
        ex.timestamp=newEntry.timestamp
        ex.duration    = ex.duration    + newEntry.duration
        ex.totalGold   = ex.totalGold   + newEntry.totalGold
        ex.totalVendor = ex.totalVendor + newEntry.totalVendor
        ex.totalAH     = ex.totalAH     + newEntry.totalAH
        -- merge qAtlas: keep any tier atlas already known, add new ones
        if newEntry.qAtlas then
            ex.qAtlas = ex.qAtlas or {}
            for tier, atlas in pairs(newEntry.qAtlas) do
                ex.qAtlas[tier] = ex.qAtlas[tier] or atlas
            end
        end
        for name, d in pairs(newEntry.items) do
            if not ex.items[name] then
                ex.items[name]={amount=0,icon=d.icon,quality=d.quality,itemSubType=d.itemSubType,
                    sellPrice=d.sellPrice,vendorTotal=0,ahTotal=0,
                    isVendorTrash=d.isVendorTrash,isBoE=d.isBoE,isBoP=d.isBoP,
                    classID=d.classID,itemID=d.itemID,q=d.q,qIDs=d.qIDs}
            end
            local ei=ex.items[name]
            ei.amount      = ei.amount      + d.amount
            ei.vendorTotal = (ei.vendorTotal or 0) + (d.vendorTotal or 0)
            ei.ahTotal     = (ei.ahTotal     or 0) + (d.ahTotal     or 0)
            if d.q then
                if not ei.q then ei.q={}; ei.qIDs={} end
                for tier=1,3 do
                    if d.q[tier] then ei.q[tier]=(ei.q[tier] or 0)+d.q[tier] end
                    if d.qIDs and d.qIDs[tier] and not ei.qIDs[tier] then ei.qIDs[tier]=d.qIDs[tier] end
                end
            end
        end
    else
        table.insert(sessions,1,newEntry)
        while #sessions > MAX_SESSIONS do table.remove(sessions) end
    end
end

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
    r.sep:SetColorTexture(0.18,0.28,0.30,0.55); r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT")
    -- Single-line: [Dauer] [Items] [Gold] [X]
    r.dateText=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.dateText:SetPoint("LEFT",6,0); r.dateText:SetTextColor(0.9,0.9,0.9); r.dateText:SetFontHeight(11)
    r.infoText=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.infoText:SetPoint("CENTER",0,0); r.infoText:SetTextColor(0.55,0.55,0.55); r.infoText:SetFontHeight(11)
    r.goldText=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",-22,0); r.goldText:SetJustifyH("RIGHT"); r.goldText:SetFontHeight(11)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    r.delBtn=CreateFrame("Button",nil,r); r.delBtn:SetSize(16,16); r.delBtn:SetPoint("RIGHT",-2,0)
    local delTex=r.delBtn:CreateTexture(nil,"ARTWORK"); delTex:SetAllPoints()
    delTex:SetTexture(ART.."btn_close.tga"); delTex:SetAlpha(0.5)
    r.delBtn:SetScript("OnEnter",function() delTex:SetAlpha(1)
        GameTooltip:SetOwner(r.delBtn,"ANCHOR_TOP"); GameTooltip:SetText(ns.L["delete_session"]); GameTooltip:Show() end)
    r.delBtn:SetScript("OnLeave",function() delTex:SetAlpha(0.5); GameTooltip:Hide() end)
    r:SetScript("OnEnter",function(self) self.bg:Show(); self.dateText:SetTextColor(unpack(ns.COL_GOLD)) end)
    r:SetScript("OnLeave",function(self) self.bg:Hide(); self.dateText:SetTextColor(0.9,0.9,0.9) end)
    return r
end
local function ReleaseSessRow(r)
    r:Hide(); r:ClearAllPoints(); r.sessionIdx=nil; r:SetScript("OnMouseUp",nil); sessPool[#sessPool+1]=r
end

local function AcquireDayRow()
    local r=table.remove(dayPool)
    if r then r:SetParent(HListFrame); r:Show(); return r end
    r=CreateFrame("Frame",nil,HListFrame); r:SetHeight(DAY_H); r:EnableMouse(true)
    r.bg=r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(unpack(ns.COL_CAT_BG))
    r.sep=r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1); r.sep:SetColorTexture(unpack(ns.COL_BORDER))
    r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT")
    r.dateText=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.dateText:SetPoint("LEFT",4,0); r.dateText:SetFontHeight(11); r.dateText:SetTextColor(unpack(ns.COL_ACCENT))
    r.infoText=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.infoText:SetPoint("LEFT",r.dateText,"RIGHT",10,0); r.infoText:SetFontHeight(10); r.infoText:SetTextColor(0.45,0.45,0.45)
    r.goldText=r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",0,0); r.goldText:SetJustifyH("RIGHT"); r.goldText:SetFontHeight(11)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    return r
end
local function ReleaseDayRow(r)
    r:Hide(); r:ClearAllPoints()
    r:SetScript("OnMouseUp",nil); r:SetScript("OnEnter",nil); r:SetScript("OnLeave",nil)
    r.dateText:SetTextColor(unpack(ns.COL_ACCENT))
    dayPool[#dayPool+1]=r
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

local function AcquireDetRow()
    local r = table.remove(detRowPool)
    if r then r:SetParent(DListFrame); r:Show(); return r end
    r = CreateFrame("Frame", nil, DListFrame)
    r:SetSize(DET_CONT_W, DET_ROW_H)
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

    -- Single-line: icon | name | count | gold (y=0 = centered with icon)
    r.nameText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",  r.icon, "RIGHT", 8,    0)
    r.nameText:SetPoint("RIGHT", r,      "RIGHT", -128, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(11); r.nameText:SetWordWrap(false)

    r.countText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.countText:SetPoint("RIGHT", r, "RIGHT", -90, 0)
    r.countText:SetJustifyH("RIGHT"); r.countText:SetTextColor(0.78,0.78,0.78); r.countText:SetFontHeight(11)

    r.goldText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.goldText:SetJustifyH("RIGHT"); r.goldText:SetTextColor(unpack(ns.COL_GOLD)); r.goldText:SetFontHeight(11)

    r:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function ReleaseDetRow(r)
    r:Hide(); r:ClearAllPoints(); r.itemID=nil; r.iconBorder:Hide()
    r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", 4, 0)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    detRowPool[#detRowPool+1]=r
end

local function AcquireDetCat()
    local r = table.remove(detCatPool)
    if r then r:SetParent(DListFrame); r:Show(); return r end
    r = CreateFrame("Frame", nil, DListFrame); r:SetHeight(DET_CAT_H)
    r:EnableMouse(true)
    r.bg = r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(unpack(ns.COL_CAT_BG))
    r.sep = r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1); r.sep:SetColorTexture(unpack(ns.COL_BORDER))
    r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT")
    r.nameText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",4,0); r.nameText:SetPoint("RIGHT",r,"RIGHT",-100,0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(11); r.nameText:SetTextColor(unpack(ns.COL_ACCENT))
    r.goldText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",r,"RIGHT",-4,0); r.goldText:SetJustifyH("RIGHT")
    r.goldText:SetFontHeight(11); r.goldText:SetTextColor(unpack(ns.COL_GOLD))
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
    DetailFrame:SetFrameStrata("HIGH"); DetailFrame:SetClampedToScreen(true)
    DetailFrame:SetMovable(true); DetailFrame:EnableMouse(true)
    DetailFrame:RegisterForDrag("LeftButton")
    DetailFrame:SetScript("OnDragStart",function(s) s:StartMoving() end)
    DetailFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    ns.ApplyFrameStyle(DetailFrame); DetailFrame:Hide()
    table.insert(UISpecialFrames,"NightsFarmtrackerDetailWnd")

    -- Header: single line "Date  ·  Duration  ·  Total Gold"
    DetailFrame.dateText = DetailFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    DetailFrame.dateText:SetPoint("TOPLEFT",  DET_PAD, -12)
    DetailFrame.dateText:SetPoint("TOPRIGHT", -(DET_PAD+20), -12)
    DetailFrame.dateText:SetTextColor(unpack(ns.COL_GOLD)); DetailFrame.dateText:SetFontHeight(12)

    -- kept but unused (content set to "" in ShowDetail)
    DetailFrame.durationText = DetailFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    DetailFrame.durationText:SetPoint("TOPLEFT",DET_PAD,-12)
    DetailFrame.durationText:SetTextColor(0,0,0,0)  -- transparent, unused

    DetailFrame.summaryText = DetailFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    DetailFrame.summaryText:SetPoint("TOPLEFT",DET_PAD,-12)
    DetailFrame.summaryText:SetTextColor(0,0,0,0)  -- transparent, unused

    local hSep = DetailFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT",DET_PAD,-(DET_HDR_H-1)); hSep:SetPoint("TOPRIGHT",-DET_PAD,-(DET_HDR_H-1))

    local xBtn = CreateFrame("Button",nil,DetailFrame); xBtn:SetSize(14,14); xBtn:SetPoint("TOPRIGHT",-DET_PAD,-10)
    local xTex = xBtn:CreateTexture(nil,"ARTWORK"); xTex:SetAllPoints()
    xTex:SetTexture(ART.."btn_close.tga"); xTex:SetAlpha(0.8)
    xBtn:SetScript("OnClick",function() DetailFrame:Hide() end)
    xBtn:SetScript("OnEnter",function() xTex:SetAlpha(1) end)
    xBtn:SetScript("OnLeave",function() xTex:SetAlpha(0.8) end)

    DScrollFrame = CreateFrame("ScrollFrame",nil,DetailFrame)
    DScrollFrame:SetPoint("TOPLEFT",DET_PAD,-DET_HDR_H); DScrollFrame:SetWidth(DET_CONT_W)
    DScrollFrame:EnableMouseWheel(true)
    DListFrame = CreateFrame("Frame",nil,DScrollFrame)
    DListFrame:SetWidth(DET_CONT_W); DListFrame:SetHeight(1)
    DScrollFrame:SetScrollChild(DListFrame)
    local function OnWheel(_,delta)
        local cur=DScrollFrame:GetVerticalScroll()
        local maxS=math.max(0,DListFrame:GetHeight()-DScrollFrame:GetHeight())
        DScrollFrame:SetVerticalScroll(math.max(0,math.min(cur-delta*DET_ROW_H,maxS)))
    end
    DScrollFrame:SetScript("OnMouseWheel",OnWheel)
    DListFrame:EnableMouseWheel(true); DListFrame:SetScript("OnMouseWheel",OnWheel)

    local fSep = DetailFrame:CreateTexture(nil,"ARTWORK"); fSep:SetHeight(1)
    fSep:SetColorTexture(unpack(ns.COL_BORDER))
    fSep:SetPoint("BOTTOMLEFT",DET_PAD,DET_FTR_H-2); fSep:SetPoint("BOTTOMRIGHT",-DET_PAD,DET_FTR_H-2)

    DetailFrame.footLabel = DetailFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    DetailFrame.footLabel:SetPoint("BOTTOMLEFT",DET_PAD,10); DetailFrame.footLabel:SetTextColor(0.38,0.38,0.38)

    DetailFrame.totalText = DetailFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    DetailFrame.totalText:SetPoint("BOTTOMRIGHT",-DET_PAD,8); DetailFrame.totalText:SetJustifyH("RIGHT")
    DetailFrame.totalText:SetFontHeight(12); DetailFrame.totalText:SetTextColor(unpack(ns.COL_GOLD))
end

local function RebuildDetailContent(session)
    currentDetailSession = session
    for _,r in ipairs(activeDetRows) do ReleaseDetRow(r) end
    for _,r in ipairs(activeDetCats) do ReleaseDetCat(r)  end
    activeDetRows={}; activeDetCats={}

    -- Use AH if available, else vendor (same logic as main frame)
    local hasAH = ns.HasAnyAH() and NightsFarmtrackerDB.ahSource ~= "none"

    -- Build categories
    local cats, catOrder = {}, {}
    for name, d in pairs(session.items) do
        local cat = ns.CategoryName(d) or ns.CAT_MATS
        if not cats[cat] then
            cats[cat]={gold=0,items={},classID=d.classID}
            catOrder[#catOrder+1]=cat
        end
        local isJunk = d.isVendorTrash or (d.quality == 0)
        local qAtlas = session.qAtlas or NightsFarmtrackerDB.qAtlas or {}

        if not isJunk and d.q and d.qIDs then
            -- Split crafting reagents into per-tier rows
            for tier = 1, 3 do
                local tc  = d.q[tier] or 0
                local tid = d.qIDs[tier]
                if tc > 0 then
                    local tAH, tV
                    if tid and hasAH then
                        local p = ns.GetAHPriceForID(tid)
                        if p then tAH = p * tc end
                    end
                    if d.sellPrice and d.sellPrice > 0 then tV = d.sellPrice * tc end
                    local tGold = (tAH and tAH > 0) and tAH or tV or 0
                    if tGold > 0 then
                        local rankIcon = qAtlas[tier] and CreateAtlasMarkup(qAtlas[tier],12,11) or ("|cffaaaaaa R"..tier.."|r")
                        cats[cat].gold = cats[cat].gold + tGold
                        cats[cat].items[#cats[cat].items+1] = {
                            name=name, d=d, gold=tGold, isRank=true,
                            tier=tier, tc=tc, tid=tid, tAH=tAH, tV=tV, rankIcon=rankIcon,
                        }
                    end
                end
            end
        else
            local gold = (not isJunk and hasAH and (d.ahTotal or 0) > 0) and d.ahTotal or d.vendorTotal or 0
            if gold > 0 then
                cats[cat].gold = cats[cat].gold + gold
                cats[cat].items[#cats[cat].items+1] = {name=name, d=d, gold=gold, isRank=false}
            end
        end
    end
    table.sort(catOrder, function(a,b)
        if cats[a].gold ~= cats[b].gold then return cats[a].gold > cats[b].gold end
        local oa = (cats[a].classID and ns.CLASS_PRIORITY[cats[a].classID]) or 50
        local ob = (cats[b].classID and ns.CLASS_PRIORITY[cats[b].classID]) or 50
        return oa < ob
    end)

    local yOff = 0; local totalItems = 0
    for _, catName in ipairs(catOrder) do
        local cat = cats[catName]
        if #cat.items > 0 then
        table.sort(cat.items, function(a,b)
            if a.gold ~= b.gold then return a.gold > b.gold end
            return a.name < b.name
        end)

        local ch = AcquireDetCat(); ch:SetSize(DET_CONT_W, DET_CAT_H); ch:SetPoint("TOPLEFT",0,-yOff)
        local isCollapsed = detCollapsed[catName]
        ch.nameText:SetText((isCollapsed and "+ " or "- ")..catName)
        ch.goldText:SetText(cat.gold > 0 and ns.FormatGold(cat.gold) or "")
        ch:SetScript("OnMouseUp", function()
            detCollapsed[catName] = not detCollapsed[catName]
            RebuildDetailContent(currentDetailSession)
        end)
        activeDetCats[#activeDetCats+1]=ch; yOff = yOff + DET_CAT_H

        if not isCollapsed then
        for _, entry in ipairs(cat.items) do
            totalItems = totalItems + 1
            local ir = AcquireDetRow(); ir:SetWidth(DET_CONT_W); ir:SetPoint("TOPLEFT",0,-yOff)
            ir.sep:SetShown(yOff > 0)
            -- Icon einrücken wie im Hauptframe
            ir.icon:ClearAllPoints(); ir.icon:SetPoint("LEFT", 4 + ns.CAT_INDENT, 0)
            ir.nameText:ClearAllPoints()
            ir.nameText:SetPoint("LEFT",  ir.icon, "RIGHT", 8,    0)
            ir.nameText:SetPoint("RIGHT", ir,      "RIGHT", -128, 0)
            ir.icon:SetTexture(entry.d.icon or ns.FALLBACK_ICON)
            local q = entry.d.quality
            if q then
                local r_,g_,b_ = GetItemQualityColor(q)
                ir.nameText:SetTextColor(r_,g_,b_)
                ir.iconBorder:SetColorTexture(r_,g_,b_,0.9); ir.iconBorder:Show()
            else
                ir.nameText:SetTextColor(1,1,1); ir.iconBorder:Hide()
            end
            ir.goldText:SetTextColor(unpack(ns.COL_GOLD))  -- immer gold, wie Hauptframe
            if entry.isRank then
                ir.itemID = entry.tid
                ir.nameText:SetText(entry.name .. " " .. entry.rankIcon)
                ir.countText:SetText(tostring(entry.tc))
                if entry.tAH and entry.tAH > 0 then
                    ir.goldText:SetText(ns.FormatGold(entry.tAH))
                elseif entry.tV and entry.tV > 0 then
                    ir.goldText:SetText(ns.FormatGold(entry.tV))
                else
                    ir.goldText:SetText("")
                end
            else
                ir.itemID = entry.d.itemID
                ir.nameText:SetText(entry.name)
                ir.countText:SetText(tostring(entry.d.amount))
                local isJunk = entry.d.isVendorTrash or (entry.d.quality == 0)
                if not isJunk and hasAH and (entry.d.ahTotal or 0) > 0 then
                    ir.goldText:SetText(ns.FormatGold(entry.d.ahTotal))
                elseif (entry.d.vendorTotal or 0) > 0 then
                    ir.goldText:SetText(ns.FormatGold(entry.d.vendorTotal))
                else
                    ir.goldText:SetText("")
                end
            end
            activeDetRows[#activeDetRows+1]=ir; yOff = yOff + DET_ROW_H
        end
        yOff = yOff + 2
        end  -- not isCollapsed
        end  -- if #cat.items > 0
    end

    local contentH = math.max(1, yOff)
    DListFrame:SetHeight(contentH); DScrollFrame:SetVerticalScroll(0)
    local visH = math.min(contentH, DET_MAX_H)
    DScrollFrame:SetHeight(visH)
    DetailFrame:SetHeight(DET_HDR_H + visH + DET_FTR_H)
    DetailFrame.footLabel:SetText((totalItems==1 and string.format(ns.L["item_singular"],totalItems) or string.format(ns.L["item_plural"],totalItems)))
    DetailFrame.totalText:SetText("")  -- gold shown in header
end

local function ShowDetail(session)
    EnsureDetailFrame()
    detCollapsed = {}
    DetailFrame:ClearAllPoints()
    DetailFrame:SetPoint("TOPRIGHT", HistFrame, "TOPLEFT", -4, 0)
    local goldStr = session.totalGold > 0 and ("  ·  "..ns.FormatGold(session.totalGold)) or ""
    DetailFrame.dateText:SetText(
        date("%d.%m.%Y", session.timestamp) ..
        "  ·  " .. ns.FormatTime(session.duration) .. goldStr
    )
    DetailFrame.durationText:SetText("")
    DetailFrame.summaryText:SetText("")
    RebuildDetailContent(session)
    DetailFrame:Show()
end

------------------------------------------------------------------------
-- Merge sessions
------------------------------------------------------------------------
local function MergeDaySessions(day)
    if #day.sessions<=1 then return end
    local merged={timestamp=day.sessions[1].session.timestamp,duration=0,totalGold=0,totalVendor=0,totalAH=0,items={},qAtlas={}}
    for _,entry in ipairs(day.sessions) do
        local s=entry.session
        merged.duration    = merged.duration    + s.duration
        merged.totalGold   = merged.totalGold   + s.totalGold
        merged.totalVendor = merged.totalVendor + (s.totalVendor or 0)
        merged.totalAH     = merged.totalAH     + (s.totalAH     or 0)
        if s.qAtlas then
            for tier, atlas in pairs(s.qAtlas) do
                merged.qAtlas[tier] = merged.qAtlas[tier] or atlas
            end
        end
        for name,d in pairs(s.items) do
            if not merged.items[name] then
                merged.items[name]={amount=0,icon=d.icon,quality=d.quality,itemSubType=d.itemSubType,
                    sellPrice=d.sellPrice,vendorTotal=0,ahTotal=0,
                    isVendorTrash=d.isVendorTrash,isBoE=d.isBoE,isBoP=d.isBoP,
                    classID=d.classID,itemID=d.itemID}
            end
            local mi=merged.items[name]
            mi.amount      = mi.amount      + d.amount
            mi.vendorTotal = (mi.vendorTotal or 0) + (d.vendorTotal or 0)
            mi.ahTotal     = (mi.ahTotal     or 0) + (d.ahTotal     or 0)
        end
    end
    local indices={}
    for _,e in ipairs(day.sessions) do indices[#indices+1]=e.idx end
    table.sort(indices,function(a,b) return a>b end)
    for _,idx in ipairs(indices) do table.remove(NightsFarmtrackerAccountDB.sessions,idx) end
    table.insert(NightsFarmtrackerAccountDB.sessions,indices[#indices],merged)
    ns.RebuildHistory()
end

------------------------------------------------------------------------
-- RebuildHistory
------------------------------------------------------------------------
function ns.RebuildHistory()
    if not HListFrame then return end
    for _,r in ipairs(activeSessRows) do ReleaseSessRow(r) end
    for _,r in ipairs(activeDayRows)  do ReleaseDayRow(r)  end
    activeSessRows={}; activeDayRows={}
    local sessions=(NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions) or {}
    local days,dayOrder={},{}
    for i,session in ipairs(sessions) do
        local dStr=date("%d.%m.%Y",session.timestamp)
        if not days[dStr] then days[dStr]={totalGold=0,sessions={}}; dayOrder[#dayOrder+1]=dStr end
        days[dStr].totalGold=days[dStr].totalGold+session.totalGold
        days[dStr].sessions[#days[dStr].sessions+1]={session=session,idx=i}
    end
    local yOffset=0
    for _,dStr in ipairs(dayOrder) do
        local day=days[dStr]; local nSess=#day.sessions
        local drow=AcquireDayRow(); drow:SetSize(H_CONT_W, DAY_H); drow:SetPoint("TOPLEFT",0,-yOffset)
        drow.dateText:SetText(dStr)
        drow.infoText:SetText("")
        drow.goldText:SetText("")
        if nSess>1 then
            local d=day
            drow:SetScript("OnMouseUp",function(_,btn) if btn=="LeftButton" then MergeDaySessions(d) end end)
            drow:SetScript("OnEnter",function(self)
                self.bg:SetColorTexture(0.16,0.24,0.27,0.95); self.dateText:SetTextColor(1,1,1)
                GameTooltip:SetOwner(self,"ANCHOR_BOTTOMLEFT")
                GameTooltip:SetText(string.format(ns.L["merge_sessions"], nSess))
                GameTooltip:AddLine(ns.L["merge_desc"],0.7,0.7,0.7,true)
                GameTooltip:Show()
            end)
            drow:SetScript("OnLeave",function(self)
                self.bg:SetColorTexture(unpack(ns.COL_CAT_BG)); self.dateText:SetTextColor(unpack(ns.COL_ACCENT))
                GameTooltip:Hide()
            end)
        end
        activeDayRows[#activeDayRows+1]=drow; yOffset=yOffset+DAY_H
        for _,entry in ipairs(day.sessions) do
            local session=entry.session; local idx=entry.idx
            local row=AcquireSessRow(); row:SetWidth(H_CONT_W); row:SetPoint("TOPLEFT",0,-yOffset)
            row.sessionIdx=idx
            local hasAH = ns.HasAnyAH() and NightsFarmtrackerDB.ahSource ~= "none"
            local n=0
            for _,d in pairs(session.items) do
                local isJunk = d.isVendorTrash or (d.quality == 0)
                if not isJunk and d.q and d.qIDs then
                    for tier=1,3 do
                        local tc=d.q[tier] or 0; local tid=d.qIDs[tier]
                        if tc>0 then
                            local tAH,tV
                            if tid and hasAH then local p=ns.GetAHPriceForID(tid); if p then tAH=p*tc end end
                            if d.sellPrice and d.sellPrice>0 then tV=d.sellPrice*tc end
                            if ((tAH and tAH>0) and tAH or tV or 0) > 0 then n=n+1 end
                        end
                    end
                else
                    local gold=(not isJunk and hasAH and (d.ahTotal or 0)>0) and d.ahTotal or d.vendorTotal or 0
                    if gold>0 then n=n+1 end
                end
            end
            row.dateText:SetText(ns.FormatTime(session.duration))
            row.infoText:SetText(n==1 and string.format(ns.L["item_singular"],n) or string.format(ns.L["item_plural"],n))
            row.goldText:SetText(session.totalGold>0 and ns.FormatGold(session.totalGold) or "")
            local sess=session
            row:SetScript("OnMouseUp",function(self,btn)
                if btn=="LeftButton" and not self.delBtn:IsMouseOver() then ShowDetail(sess) end
            end)
            row.delBtn:SetScript("OnClick",function()
                table.remove(NightsFarmtrackerAccountDB.sessions,idx); ns.RebuildHistory()
            end)
            activeSessRows[#activeSessRows+1]=row; yOffset=yOffset+SESS_H
        end
        yOffset=yOffset+3
    end
    local contentH=math.max(1,yOffset)
    HListFrame:SetHeight(contentH)
    local maxS=math.max(0,contentH-HScrollFrame:GetHeight())
    HScrollFrame:SetVerticalScroll(math.min(HScrollFrame:GetVerticalScroll(),maxS))
    local visH=yOffset==0 and 44 or math.min(contentH,MAX_VIS_H)
    HistFrame:SetHeight(H_HDR_H+visH+H_FTR_H)
    local nDays=#dayOrder; local nTotal=#sessions
    if nTotal==0 then
        HistFrame.countLabel:SetText(ns.L["no_sessions"])
        if HistFrame.clrBtn then HistFrame.clrBtn:Hide() end
    else
        if HistFrame.clrBtn then HistFrame.clrBtn:Show() end
        local key = (nTotal == 1) and ns.L["sessions_summary"] or ns.L["sessions_summary_pl"]
        HistFrame.countLabel:SetText(string.format(key, nTotal, nDays, MAX_SESSIONS))
    end
end

------------------------------------------------------------------------
-- Build history list window (lazy)
------------------------------------------------------------------------
local function EnsureHistFrame()
    if HListFrame then return end
    HistFrame=CreateFrame("Frame","NightsFarmtrackerHistoryWnd",UIParent,"BackdropTemplate")
    HistFrame:SetWidth(H_W); HistFrame:SetPoint("TOPRIGHT", ns.MainFrame, "TOPLEFT", -4, 0)
    HistFrame:SetFrameStrata("HIGH"); HistFrame:SetClampedToScreen(true)
    HistFrame:SetMovable(true); HistFrame:EnableMouse(true)
    HistFrame:RegisterForDrag("LeftButton")
    HistFrame:SetScript("OnDragStart",function(s) s:StartMoving() end)
    HistFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    ns.ApplyFrameStyle(HistFrame); HistFrame:Hide()
    table.insert(UISpecialFrames,"NightsFarmtrackerHistoryWnd")
    HistFrame:SetScript("OnHide",function() if DetailFrame then DetailFrame:Hide() end end)

    local titleFS=HistFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    titleFS:SetPoint("TOPLEFT",H_PAD,-10); titleFS:SetText(ns.L["session_history"])
    titleFS:SetTextColor(unpack(ns.COL_GOLD))

    local hSep=HistFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT",H_PAD,-(H_HDR_H-1)); hSep:SetPoint("TOPRIGHT",-H_PAD,-(H_HDR_H-1))

    local xBtn=CreateFrame("Button",nil,HistFrame); xBtn:SetSize(14,14); xBtn:SetPoint("TOPRIGHT",-H_PAD,-10)
    local xTex=xBtn:CreateTexture(nil,"ARTWORK"); xTex:SetAllPoints()
    xTex:SetTexture(ART.."btn_close.tga"); xTex:SetAlpha(0.8)
    xBtn:SetScript("OnClick",function() HistFrame:Hide() end)
    xBtn:SetScript("OnEnter",function() xTex:SetAlpha(1) end)
    xBtn:SetScript("OnLeave",function() xTex:SetAlpha(0.8) end)

    HScrollFrame=CreateFrame("ScrollFrame",nil,HistFrame)
    HScrollFrame:SetPoint("TOPLEFT",H_PAD,-H_HDR_H); HScrollFrame:SetPoint("BOTTOMRIGHT",-H_PAD,H_FTR_H)
    HScrollFrame:EnableMouseWheel(true)
    HListFrame=CreateFrame("Frame",nil,HScrollFrame)
    HListFrame:SetWidth(H_CONT_W); HListFrame:SetHeight(1)
    HScrollFrame:SetScrollChild(HListFrame)
    local function OnWheel(_,delta)
        local cur=HScrollFrame:GetVerticalScroll()
        local maxS=math.max(0,HListFrame:GetHeight()-HScrollFrame:GetHeight())
        HScrollFrame:SetVerticalScroll(math.max(0,math.min(cur-delta*SESS_H,maxS)))
    end
    HScrollFrame:SetScript("OnMouseWheel",OnWheel)
    HListFrame:EnableMouseWheel(true); HListFrame:SetScript("OnMouseWheel",OnWheel)

    local fSep=HistFrame:CreateTexture(nil,"ARTWORK"); fSep:SetHeight(1)
    fSep:SetColorTexture(unpack(ns.COL_BORDER))
    fSep:SetPoint("BOTTOMLEFT",H_PAD,H_FTR_H-2); fSep:SetPoint("BOTTOMRIGHT",-H_PAD,H_FTR_H-2)

    HistFrame.countLabel=HistFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    HistFrame.countLabel:SetPoint("BOTTOMLEFT",H_PAD,8); HistFrame.countLabel:SetTextColor(0.40,0.40,0.40)

    HistFrame.clrBtn=CreateFrame("Button",nil,HistFrame); HistFrame.clrBtn:SetSize(70,18); HistFrame.clrBtn:SetPoint("BOTTOMRIGHT",-H_PAD,6)
    local clrLabel=HistFrame.clrBtn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    clrLabel:SetAllPoints(); clrLabel:SetJustifyH("RIGHT"); clrLabel:SetText(ns.L["clear_all"])
    clrLabel:SetTextColor(0.50,0.22,0.22)
    HistFrame.clrBtn:SetScript("OnClick",function()
        if not NightsFarmtrackerAccountDB.sessions or #NightsFarmtrackerAccountDB.sessions==0 then return end
        NightsFarmtrackerAccountDB.sessions={}; ns.RebuildHistory()
    end)
    HistFrame.clrBtn:SetScript("OnEnter",function()
        clrLabel:SetTextColor(1,0.4,0.4)
        GameTooltip:SetOwner(HistFrame.clrBtn,"ANCHOR_TOP"); GameTooltip:SetText(ns.L["delete_all"]); GameTooltip:Show()
    end)
    HistFrame.clrBtn:SetScript("OnLeave",function() clrLabel:SetTextColor(0.50,0.22,0.22); GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleHistory()
    EnsureHistFrame()
    if HistFrame:IsShown() then
        HistFrame:Hide()
        if DetailFrame then DetailFrame:Hide() end
    else
        ns.RebuildHistory()
        HistFrame:Show()
    end
end