------------------------------------------------------------------------
-- Night's Farmtracker - UI
-- BtnBar always visible: [▶][↺][⏱] left · [⚙][?][▼/▲][✕] right
-- Footer always visible: total gold | timer | gold/rate
------------------------------------------------------------------------
local _, ns = ...

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
local HDR_TOTAL  = ns.WINDOW_HDR_H  -- same header height as every other window
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
MainFrame:SetPoint("TOP", UIParent, "TOP", 0, -150)
MainFrame:Hide()
-- Explicit (was relying on the "MEDIUM" default before): every other
-- window (History/Settings/Filter/Blacklist/Log via ns.CreateWindowFrame,
-- Detail, Gold Overview, Venom Tracker, Fishing Lure Bar) now matches
-- this same strata - see their own SetFrameStrata("MEDIUM") calls.
MainFrame:SetFrameStrata("MEDIUM")
MainFrame:SetMovable(true); MainFrame:EnableMouse(true); MainFrame:SetClampedToScreen(true)
ns.ApplyFrameStyle(MainFrame)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
MainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- WoW's drag mechanism does not preserve the original anchor point type -
    -- StopMovingOrSizing()/GetPoint() can return a different point (e.g.
    -- "RIGHT", which is vertically centered) depending on where the frame
    -- ends up. A "RIGHT" anchor would make height changes grow symmetrically
    -- up/down again, so always normalize back to a "TOP" anchor here.
    local top      = self:GetTop()
    local left     = self:GetLeft()
    local right    = self:GetRight()
    local uiTop    = UIParent:GetTop()
    local uiWidth  = UIParent:GetWidth()
    local offsetY  = top - uiTop
    local offsetX  = (left + right) / 2 - uiWidth / 2
    NightsFarmtrackerDB.pos = {"TOP", "TOP", offsetX, offsetY}
    self:ClearAllPoints()
    self:SetPoint("TOP", UIParent, "TOP", offsetX, offsetY)
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

local btnPause    = MakeBtn(BtnBar, 18, "btn_play.png")
btnPause:SetPoint("LEFT", BtnBar, "LEFT", 0, 0)

local btnReset    = MakeBtn(BtnBar, 18, "btn_reset.png")
btnReset:SetPoint("LEFT", btnPause, "RIGHT", 6, 0)

local btnHistory  = MakeBtn(BtnBar, 18, "btn_history.png")
btnHistory:SetPoint("LEFT", btnReset, "RIGHT", 10, 0)

local btnFilter   = MakeBtn(BtnBar, 18, "btn_filter.png")
btnFilter:SetPoint("LEFT", btnHistory, "RIGHT", 6, 0)

-- Right side (anchored from right): close → collapse → help → settings
local btnClose = MakeBtn(BtnBar, 18, "btn_close.png")
btnClose:SetPoint("RIGHT", BtnBar, "RIGHT", 0, 0)

local btnToggle = MakeBtn(BtnBar, 18, "btn_expand.png")
btnToggle:SetPoint("RIGHT", btnClose, "LEFT", -6, 0)

local btnHelp = MakeBtn(BtnBar, 18, "btn_help.png")
btnHelp:SetPoint("RIGHT", btnToggle, "LEFT", -6, 0)

local btnSettings = MakeBtn(BtnBar, 18, "btn_settings.png")
btnSettings:SetPoint("RIGHT", btnHelp, "LEFT", -6, 0)

-- Separator below BtnBar
local hdrSep = MainFrame:CreateTexture(nil, "ARTWORK")
hdrSep:SetHeight(1)
hdrSep:SetColorTexture(unpack(ns.COL_BORDER))
hdrSep:SetPoint("TOPLEFT",  PAD,  -HDR_TOTAL)
hdrSep:SetPoint("TOPRIGHT", -PAD, -HDR_TOTAL)
table.insert(MainFrame.nftEdges, hdrSep)

------------------------------------------------------------------------
-- Empty hint (expanded, no items yet)
------------------------------------------------------------------------
local emptyHint = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
emptyHint:SetPoint("TOP", MainFrame, "TOP", 0, -(SCROLL_TOP + 28))
emptyHint:SetTextColor(unpack(ns.COL_ACCENT))
emptyHint:SetFontHeight(ns.FONT_NORMAL)
emptyHint:SetText(ns.L["gathering_active"])
emptyHint:Hide()
MainFrame.nftAccentTexts = MainFrame.nftAccentTexts or {}
table.insert(MainFrame.nftAccentTexts, emptyHint)

------------------------------------------------------------------------
-- Footer — always visible: [total gold] [timer] [gold/rate]
------------------------------------------------------------------------
local footerSep = MainFrame:CreateTexture(nil, "ARTWORK")
footerSep:SetHeight(1)
footerSep:SetColorTexture(unpack(ns.COL_BORDER))
footerSep:SetPoint("BOTTOMLEFT",  PAD,  FOOTER_H - 2)
footerSep:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H - 2)
table.insert(MainFrame.nftEdges, footerSep)

local goldBtn = CreateFrame("Button", nil, MainFrame)
goldBtn:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", PAD, 4)
goldBtn:SetSize(140, 22)
MainFrame.totalGoldText = goldBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
MainFrame.totalGoldText:SetPoint("LEFT")
MainFrame.totalGoldText:SetTextColor(unpack(ns.COL_GOLD))
MainFrame.totalGoldText:SetFontHeight(ns.FONT_NORMAL)
goldBtn:SetScript("OnClick", function() ns.ToggleGoldFrame() end)
goldBtn:SetScript("OnEnter", function() MainFrame.totalGoldText:SetTextColor(1, 1, 0.6) end)
goldBtn:SetScript("OnLeave", function() MainFrame.totalGoldText:SetTextColor(unpack(ns.COL_GOLD)) end)

MainFrame.TimerText = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
MainFrame.TimerText:SetPoint("BOTTOM", MainFrame, "BOTTOM", 0, 9)
MainFrame.TimerText:SetJustifyH("CENTER")
MainFrame.TimerText:SetTextColor(0.65, 0.70, 0.72)
MainFrame.TimerText:SetFontHeight(ns.FONT_NORMAL)
MainFrame.TimerText:SetText("00:00:00")

local btnRate = CreateFrame("Frame", nil, MainFrame)
btnRate:SetPoint("BOTTOMRIGHT", -PAD, 4)
btnRate:SetSize(130, 20)
btnRate.text = btnRate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
btnRate.text:SetPoint("RIGHT")
btnRate.text:SetTextColor(0.55, 0.55, 0.55)
btnRate.text:SetFontHeight(ns.FONT_NORMAL)

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
GoldFrame:SetFrameStrata("MEDIUM")
GoldFrame:SetClampedToScreen(true)
ns.ApplyFrameStyle(GoldFrame)
GoldFrame:Hide()
ns.GoldFrame = GoldFrame

do
    local gp = PAD
    local titleFS = GoldFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("TOPLEFT", gp, -10)
    titleFS:SetPoint("TOPRIGHT", -gp, -10)
    titleFS:SetJustifyH("CENTER")
    titleFS:SetTextColor(unpack(ns.COL_ACCENT))
    titleFS:SetText(ns.L["gold_overview"])
    titleFS:SetFontHeight(ns.FONT_HEADER)
    GoldFrame.nftAccentTexts = { titleFS }

    local sep1 = GoldFrame:CreateTexture(nil,"ARTWORK"); sep1:SetHeight(1)
    sep1:SetColorTexture(unpack(ns.COL_BORDER))
    sep1:SetPoint("TOPLEFT", gp, -26); sep1:SetPoint("TOPRIGHT", -gp, -26)
    table.insert(GoldFrame.nftEdges, sep1)

    local function MakeRow(yOff, labelKey, bold)
        local font = bold and "GameFontNormal" or "GameFontNormalSmall"
        local lbl = GoldFrame:CreateFontString(nil, "OVERLAY", font)
        lbl:SetPoint("TOPLEFT", gp, yOff)
        lbl:SetTextColor(0.75, 0.75, 0.75)
        lbl:SetText(ns.L[labelKey] or labelKey)
        lbl:SetFontHeight(ns.FONT_NORMAL)
        local val = GoldFrame:CreateFontString(nil, "OVERLAY", font)
        val:SetPoint("TOPRIGHT", -gp, yOff)
        val:SetJustifyH("RIGHT")
        val:SetTextColor(unpack(ns.COL_GOLD))
        val:SetFontHeight(ns.FONT_NORMAL)
        return val
    end

    local itemsVal  = MakeRow(-33, "gold_items")
    local direktVal = MakeRow(-49, "looted_gold")

    local sep2 = GoldFrame:CreateTexture(nil,"ARTWORK"); sep2:SetHeight(1)
    sep2:SetColorTexture(unpack(ns.COL_BORDER))
    sep2:SetPoint("TOPLEFT", gp, -63); sep2:SetPoint("TOPRIGHT", -gp, -63)
    table.insert(GoldFrame.nftEdges, sep2)

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
    if ns.DeferInCombat(ns.ToggleGoldFrame) then return end
    if GoldFrame:IsShown() then GoldFrame:Hide()
    else GoldFrame:Show(); ns.UpdateGoldFrame() end
    -- GoldFrame always sits directly below MainFrame; when MainFrame is
    -- collapsed, LogFrame also wants that spot, so it needs to know
    -- whether to chain below GoldFrame instead (avoids overlap).
    if ns.ReanchorLogFrame and ns.LogFrame and ns.LogFrame:IsShown() then
        ns.ReanchorLogFrame()
    end
end

-- Closing the main window closes every popout that docks off it, so the
-- user doesn't end up with orphaned windows floating on screen.
MainFrame:HookScript("OnHide", function()
    GoldFrame:Hide()
    if ns.LogFrame      and ns.LogFrame:IsShown()      then ns.LogFrame:Hide()      end
    if ns.FilterFrame   and ns.FilterFrame:IsShown()   then ns.FilterFrame:Hide()   end
    if ns.SettingsFrame and ns.SettingsFrame:IsShown() then ns.SettingsFrame:Hide() end
    if ns.BlacklistFrame and ns.BlacklistFrame:IsShown() then ns.BlacklistFrame:Hide() end
    if ns.HistFrame      and ns.HistFrame:IsShown()      then ns.HistFrame:Hide()      end
    if ns.DetailFrame    and ns.DetailFrame:IsShown()    then ns.DetailFrame:Hide()    end
    if ns.VenomFrame     and ns.VenomFrame:IsShown()     then ns.VenomFrame:Hide()     end
    if ns.BaitFrame      and ns.BaitFrame:IsShown()      then ns.SafeHideBaitFrame()   end
end)

------------------------------------------------------------------------
-- Timer / rate
------------------------------------------------------------------------
-- Optional fixed session length (db.sessionLength minutes, 0 = off): the
-- timer then counts down and the session pauses itself at 0.
function ns.GetSessionLimit()
    local minutes = tonumber(NightsFarmtrackerDB.sessionLength) or 0
    return minutes > 0 and minutes * 60 or nil
end

function ns.SessionLimitReached()
    local limit = ns.GetSessionLimit()
    return limit ~= nil and (NightsFarmtrackerDB.totalTime or 0) >= limit
end

function ns.UpdateTimerDisplay()
    local elapsed = NightsFarmtrackerDB.totalTime or 0
    local limit   = ns.GetSessionLimit()
    if limit then
        MainFrame.TimerText:SetText(ns.FormatTime(math.ceil(math.max(limit - elapsed, 0))))
    else
        MainFrame.TimerText:SetText(ns.FormatTime(elapsed))
    end
end

-- Gold/hour is the plain session average (totalGold / totalTime).
function ns.UpdateGoldRate()
    local db = NightsFarmtrackerDB
    if cachedGold <= 0 or db.totalTime <= 0 then
        btnRate.text:SetText("")
        return
    end

    local rate = cachedGold / (db.totalTime / 3600)
    if db.goldRateMode == "min" then
        btnRate.text:SetText(ns.FormatGold(math.floor(rate / 60)) ..ns.L["rate_min"])
    else
        btnRate.text:SetText(ns.FormatGold(math.floor(rate))      ..ns.L["rate_hr"])
    end
end

------------------------------------------------------------------------
-- Expand / Collapse
------------------------------------------------------------------------
local function ExpandedHeight()
    return SCROLL_TOP + 1 + math.min(totalH, MAX_ROWS * ROW_H) + FOOTER_H
end

------------------------------------------------------------------------
-- Combat-safe frame height. MainFrame:SetHeight() can throw
-- ADDON_ACTION_BLOCKED when called during combat lockdown; defer to
-- PLAYER_REGEN_ENABLED instead of failing silently (same pattern as
-- SafeHideBaitFrame in NightsFarmtrackerBaitFrame.lua).
------------------------------------------------------------------------
local pendingHeightUpdate = false

local function SafeSetMainHeight(height)
    if InCombatLockdown() then
        pendingHeightUpdate = true
        return
    end
    MainFrame:SetHeight(height)
end

function ns.SetExpanded(expand)
    NightsFarmtrackerDB.expanded = expand
    if expand then
        btnToggle.tex:SetTexture(ART.."btn_collapse.png")
        if #itemOrder == 0 then
            emptyHint:Show(); ScrollFrame:Hide()
            SafeSetMainHeight(SCROLL_TOP + 60 + FOOTER_H)
        else
            emptyHint:Hide(); ScrollFrame:Show()
            SafeSetMainHeight(ExpandedHeight())
        end
    else
        emptyHint:Hide(); ScrollFrame:Hide()
        btnToggle.tex:SetTexture(ART.."btn_expand.png")
        SafeSetMainHeight(COLLAPSED_H)
    end
    if ns.ReanchorLogFrame and ns.LogFrame and ns.LogFrame:IsShown() then
        ns.ReanchorLogFrame()
    end
end

local function UpdateFrameHeight()
    if not NightsFarmtrackerDB.expanded then return end
    if #itemOrder == 0 then
        emptyHint:Show(); ScrollFrame:Hide()
        SafeSetMainHeight(SCROLL_TOP + 60 + FOOTER_H)
    else
        emptyHint:Hide(); ScrollFrame:Show()
        ListFrame:SetSize(CONTENT_W, totalH)
        SafeSetMainHeight(ExpandedHeight())
    end
end

------------------------------------------------------------------------
-- Combat-safe hide for MainFrame. Hiding it can throw ADDON_ACTION_BLOCKED
-- during combat lockdown (its OnHide chain touches BaitFrame, which can
-- hold a SecureActionButtonTemplate lure button); defer to
-- PLAYER_REGEN_ENABLED instead of failing silently.
------------------------------------------------------------------------
local pendingMainHide = false

local function SafeHideMainFrame()
    if InCombatLockdown() then
        pendingMainHide = true
        return
    end
    NightsFarmtrackerDB.visible = false
    MainFrame:Hide()
end
ns.SafeHideMainFrame = SafeHideMainFrame

-- Symmetric guard for Show(): SlashCmdList and the minimap icon can also
-- call this while in combat, and Show() is just as much on the
-- ADDON_ACTION_BLOCKED list as Hide() (see comment above).
local function SafeShowMainFrame()
    if ns.DeferInCombat(function()
        NightsFarmtrackerDB.visible = true
        MainFrame:Show()
    end) then return end
    NightsFarmtrackerDB.visible = true
    MainFrame:Show()
end
ns.SafeShowMainFrame = SafeShowMainFrame

local heightWatcher = CreateFrame("Frame")
heightWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
heightWatcher:SetScript("OnEvent", function()
    if pendingHeightUpdate then
        pendingHeightUpdate = false
        UpdateFrameHeight()
    end
    if pendingMainHide then
        pendingMainHide = false
        SafeHideMainFrame()
    end
end)

local function UpdateSummary(itemGoldTotal)
    cachedGold = (itemGoldTotal or 0) + (NightsFarmtrackerDB.lootedGold or 0)
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
            if btn == "RightButton" and IsShiftKeyDown() and not self.isJunkMerged then
                ns.ExcludeItemByID(self.baseItemID, self.itemName)
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        local anchor = ns.SmartAnchor(self, "RIGHT")
        if self.isCategoryHeader then
            GameTooltip:SetOwner(self, anchor)
            GameTooltip:AddLine(self.categoryName, 1,1,1)
            GameTooltip:AddLine(ns.L["cat_tip_click"],      0.5,0.5,0.5)
            GameTooltip:AddLine(ns.L["cat_tip_shift_rclick"],0.5,0.5,0.5)
            GameTooltip:Show()
        elseif self.itemName then
            if self.itemLink then
                ns.ShowItemTooltipNoCompare(self, anchor, self.itemLink)
            elseif self.itemID then
                ns.ShowItemTooltipNoCompare(self, anchor, nil, self.itemID)
            else
                GameTooltip:SetOwner(self, anchor)
                GameTooltip:AddLine(self.itemName,1,1,1)
            end
            if not self.isJunkMerged then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns.L["item_tip_shift_rclick"],0.5,0.5,0.5)
            end
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

    -- Category header only: proper top+bottom border (matches the
    -- Filter/Blacklist/History header style) instead of relying on the
    -- faint item-list divider above, so each header reads as a clean
    -- "line - background - line" block.
    row.catTopSep = row:CreateTexture(nil,"ARTWORK")
    row.catTopSep:SetHeight(1)
    row.catTopSep:SetColorTexture(unpack(ns.COL_BORDER))
    row.catTopSep:SetPoint("TOPLEFT"); row.catTopSep:SetPoint("TOPRIGHT")
    row.catTopSep:Hide()

    row.catBottomSep = row:CreateTexture(nil,"ARTWORK")
    row.catBottomSep:SetHeight(1)
    row.catBottomSep:SetColorTexture(unpack(ns.COL_BORDER))
    row.catBottomSep:SetPoint("BOTTOMLEFT"); row.catBottomSep:SetPoint("BOTTOMRIGHT")
    row.catBottomSep:Hide()

    row.icon = row:CreateTexture(nil,"ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconBorder = row:CreateTexture(nil,"BACKGROUND")
    row.iconBorder:SetPoint("TOPLEFT",     row.icon,"TOPLEFT",     -1,  1)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon,"BOTTOMRIGHT",  1, -1)
    row.iconBorder:Hide()

    row.rankBadge = ns.CreateIconBadge(row, row.icon)

    -- Single-line layout: all y=0 → vertically centered with icon
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("LEFT",  row.rankBadge, "RIGHT", 4,    0)
    row.nameText:SetPoint("RIGHT", row,           "RIGHT", -128, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetFontHeight(ns.FONT_NORMAL)
    row.nameText:SetWordWrap(false)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.countText:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    row.countText:SetJustifyH("RIGHT")
    row.countText:SetTextColor(0.78, 0.78, 0.78)
    row.countText:SetFontHeight(ns.FONT_NORMAL)

    row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.goldText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.goldText:SetJustifyH("RIGHT")
    row.goldText:SetTextColor(unpack(ns.COL_GOLD))
    row.goldText:SetFontHeight(ns.FONT_NORMAL)

    return row
end

local function ReleaseRow(row)
    row:Hide(); row:ClearAllPoints()
    row.itemName=nil; row.itemLink=nil; row.itemID=nil; row.baseItemID=nil
    row.isCategoryHeader=nil; row.categoryName=nil; row.isJunkMerged=nil
    row.catBg:SetAlpha(0)
    row.catTopSep:Hide(); row.catBottomSep:Hide()
    row.sep:Show()
    row:SetSize(CONTENT_W, ROW_H)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:Show()
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("LEFT",  row.rankBadge, "RIGHT", 4,    0)
    row.nameText:SetPoint("RIGHT", row,           "RIGHT", -128, 0)
    row.nameText:SetFontHeight(ns.FONT_NORMAL)
    row.countText:ClearAllPoints()
    row.countText:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    row.goldText:ClearAllPoints()
    row.goldText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.goldText:SetFontHeight(ns.FONT_NORMAL)
    row.rankBadge:SetText("")
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
    else
        ns.ApplyQualityColor(row.nameText, row.iconBorder, quality, {1,1,1})
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
    local cats   = {}
    local grandTotal = 0

    for itemID, data in pairs(db.count) do
        if data.classID == ns.QUEST_CLASS then
            -- Quest items are never sellable - drop any entry tracked before this fix existed
            db.count[itemID] = nil
        elseif ns.IsBlacklisted(data.itemID) or ns.IsBlacklistCategory(data) then
            -- Blacklisted after being looted this session - drop it from the live count too,
            -- not just from future loot (RefreshHUD runs right after Add/RemoveBlacklist).
            db.count[itemID] = nil
        else
            local cat = ns.CategoryName(data)
            if not cats[cat] then cats[cat]={items={},totalGold=0,classID=data.classID} end
            local c         = cats[cat]
            local vendorRaw = ns.VendorTotal(data)
            local ahRaw     = ns.AHTotal(data)
            local vendor    = vendorRaw or 0
            local ah        = ahRaw     or 0
            local gold      = ns.ItemValue(data, vendorRaw, ahRaw) or 0
            c.items[#c.items+1] = {name=data.name,itemID=itemID,data=data,gold=gold,vendor=vendor,ah=ah}
            c.totalGold   = c.totalGold   + gold
            grandTotal    = grandTotal    + gold
        end
    end

    -- Merge Junk into a single "Plunder" row (display-only - db.count
    -- itself is untouched, so turning the setting back off restores the
    -- normal per-item list immediately without any reload).
    -- Applies from the very first Junk item, not just once a 2nd distinct
    -- item shows up - otherwise the first item stays shown with its real
    -- name/icon until something else drops.
    if NightsFarmtrackerDB.mergeJunkEntries then
        for catName, cat in pairs(cats) do
            if ns.IsJunkCategory(catName) and #cat.items >= 1 then
                local totalAmount = 0
                for _, it in ipairs(cat.items) do
                    totalAmount = totalAmount + (it.data.amount or 0)
                end
                local merged = ns.JunkMergedRecord(totalAmount, cat.totalGold)
                cat.items = { {
                    name = merged.name, itemID = "NFT_JUNK_MERGED",
                    data = merged, gold = cat.totalGold,
                    vendor = cat.totalGold, ah = 0,
                } }
            end
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

    -- hasAH is needed below for fv
    local hasAH = ns.HasAnyAH() and db.ahSource ~= "none"

    -- Valuable-gear sound alert: runs independently of category collapse
    -- state (a collapsed "Equipment" category must not silently suppress
    -- it) and independently of Junk-merge display grouping. Checked via
    -- ns.GroupGearVariantsForDisplay, same grouping the item's row itself
    -- uses (see the flat-list build below). Checking raw per-bonus-ID
    -- variants instead (as before) under-notified: Adventurer's/scaling
    -- gear can bake a hidden per-drop bonus-ID component into otherwise
    -- identical rolls, so a second pickup of what looks like the same item
    -- landed in its own raw bucket that alone never reached the threshold,
    -- even though the combined, displayed value did.
    --
    -- Fires once per NEW copy added to a DISPLAYED (itemLevel, quality)
    -- group whose per-unit AH price alone reaches the Gear AH Threshold -
    -- tracked via thresholdNotifiedCounts (last amount already checked per
    -- group), so a 2nd/3rd drop of the same valuable item re-alerts instead
    -- of staying silent after the group's first drop already notified once.
    if db.gearAHThresholdSound and hasAH then
        local threshold = db.gearAHThreshold or 0
        if threshold > 0 then
            for _, data in pairs(db.count) do
                if data.variants and ns.IsGear(data) and not ns.IsVendorOnly(data) then
                    data.thresholdNotifiedCounts = data.thresholdNotifiedCounts or {}
                    for gKey, gv in pairs(ns.GroupGearVariantsForDisplay(data.variants)) do
                        local prevCount = data.thresholdNotifiedCounts[gKey] or 0
                        if gv.amount > prevCount then
                            local ap = ns.GetAHPriceForID(data.itemID, gv.itemLink)
                            if ap and ap >= threshold then
                                ns.PlayThresholdAlertSound()
                            end
                            data.thresholdNotifiedCounts[gKey] = gv.amount
                        end
                    end
                end
            end
        end
    end

    -- displayGold per category: cat.totalGold is the sum of ns.ItemValue
    -- (max(AH,Vendor) per item), matching the overall total gold logic.
    for _, entry in ipairs(sorted) do
        entry.cat.displayGold = entry.cat.totalGold
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
        hdr.catTopSep:Show(); hdr.catBottomSep:Show()
        hdr.sep:Hide()
        hdr.nameText:ClearAllPoints()
        hdr.nameText:SetPoint("LEFT",  4, 0)
        hdr.nameText:SetPoint("RIGHT", hdr, "RIGHT", -100, 0)
        hdr.nameText:SetText((isCollapsed and "+ " or "- ")..catName)
        hdr.nameText:SetFontHeight(ns.FONT_NORMAL)
        hdr.goldText:ClearAllPoints()
        hdr.goldText:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)
        hdr.goldText:SetFontHeight(ns.FONT_NORMAL)

        hdr.goldText:SetText(cat.totalGold > 0 and ns.FormatGold(cat.totalGold) or "")
        yOffset = yOffset + CAT_ROW_H

        if not isCollapsed then
            local qAtlas = NightsFarmtrackerDB.qAtlas or {}

            -- Build flat display list: each quality rank as separate entry
            local flat = {}
            for _, item in ipairs(cat.items) do
                local d = item.data
                local fv = not hasAH or ns.IsVendorOnly(d) or ns.IsGearThresholdVendorOnly(d, item.ah)
                if d.variants and not ns.IsGear(d) then
                    for tier = 1, 3 do
                        local gv = d.variants[tier]
                        local tc = gv and gv.amount or 0
                        local tid = gv and gv.priceItemID
                        if tc > 0 then
                            local tAH, tV
                            if tid then
                                local ap = ns.GetAHPriceForID(tid)
                                if ap then tAH = ap * tc end
                            end
                            if gv.sellPrice and gv.sellPrice > 0 then tV = gv.sellPrice * tc end
                            local tGold = fv and (tV or 0) or (tAH or tV or 0)
                            if tGold > 0 then
                                local rankIcon = qAtlas[tier]
                                              and CreateAtlasMarkup(qAtlas[tier],ns.RANK_ICON_W,ns.RANK_ICON_H)
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
                elseif d.variants then
                    -- Scaling/Adventurer's gear: same item ID, different item level
                    -- and quality per drop - split into one row per variant so
                    -- amounts and prices don't mix (see ProcessLoot). Grouped by
                    -- displayed (itemLevel, quality) first so two drops that only
                    -- differ in a hidden bonus-ID component still show as one
                    -- summed row (see GroupGearVariantsForDisplay).
                    for ilvl, gv in pairs(ns.GroupGearVariantsForDisplay(d.variants)) do
                        if gv.amount > 0 then
                            local sp  = ns.VariantSellPrice(gv, d)
                            local tV  = (sp and sp > 0) and (sp * gv.amount) or nil
                            local ap  = hasAH and ns.GetAHPriceForID(d.itemID, gv.itemLink) or nil
                            local tAH = ap and (ap * gv.amount) or nil
                            -- Decided per variant, not from the item's combined AH
                            -- total (item.ah) - a scaling item's variants can have
                            -- very different AH prices, so one variant crossing the
                            -- Gear AH Threshold must not force AH pricing onto a
                            -- cheaper sibling variant that's still below it.
                            local vfv   = not hasAH or ns.IsVendorOnly(d) or ns.IsGearThresholdVendorOnly(d, tAH)
                            local tGold = vfv and (tV or 0) or (tAH or tV or 0)

                            if tGold > 0 then
                                flat[#flat+1] = {
                                    isGearVariant=true, name=item.name, d=d,
                                    ilvl=ilvl, gv=gv, tV=tV, tAH=tAH, tGold=tGold, fv=vfv,
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
                local ga = (a.isRank or a.isGearVariant) and a.tGold or a.gold
                local gb = (b.isRank or b.isGearVariant) and b.tGold or b.gold
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
                ns.ApplyQualityColor(row.nameText, row.iconBorder, fi.isGearVariant and fi.gv.quality or d.quality, {1,1,1})
                row.nameText:ClearAllPoints()
                row.nameText:SetPoint("LEFT",  row.rankBadge,"RIGHT", 4,    0)
                row.nameText:SetPoint("RIGHT", row,          "RIGHT", -108, 0)

                if fi.isRank then
                    local key = tostring(d.itemID).."_q"..fi.tier
                    row.itemName = fi.name; row.itemID = fi.tid; row.itemLink = nil; row.baseItemID = d.itemID
                    row.nameText:SetText(ns.TruncateName(ns.DisplayName(fi.name, fi.tid)))
                    row.rankBadge:SetText(fi.rankIcon or "")
                    row.countText:SetText(tostring(fi.tc))
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
                elseif fi.isGearVariant then
                    local gv  = fi.gv
                    local key = tostring(d.itemID).."_g"..tostring(fi.ilvl)
                    row.itemName = fi.name; row.itemID = d.itemID; row.itemLink = gv.itemLink; row.baseItemID = d.itemID
                    row.nameText:SetText(ns.TruncateName(ns.DisplayName(fi.name, gv.itemLink or d.itemID)))
                    row.rankBadge:SetText("")
                    row.countText:SetText(tostring(gv.amount))
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
                    row.isJunkMerged = d.isJunkMerged
                    row.itemName = fi.name
                    if d.isJunkMerged then
                        row.itemID, row.itemLink, row.baseItemID = nil, nil, nil
                    else
                        row.itemID, row.itemLink, row.baseItemID = d.itemID, d.itemLink, d.itemID
                    end
                    row.nameText:SetText(d.isJunkMerged and ns.TruncateName(fi.name) or ns.TruncateName(ns.DisplayName(fi.name, d.itemID)))
                    row.rankBadge:SetText(ns.RankIconFromLink(d.itemLink) or "")
                    row.countText:SetText(tostring(d.amount))
                    if fi.fv then ShowGold(row,nil,it.vendor,true)
                    else ShowGold(row,it.ah,it.vendor,false) end
                    itemOrder[#itemOrder+1] = fi.item.itemID; itemRows[fi.item.itemID] = row
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
    UpdateSummary(grandTotal)

    if ns.FilterFrame and ns.FilterFrame:IsShown() then
        ns.RebuildFilterList()
    end
end

------------------------------------------------------------------------
-- Session controls
------------------------------------------------------------------------
function ns.Reset(skipSave)
    if not skipSave then
        ns.SaveCurrentSession()
    end
    local db = NightsFarmtrackerDB
    db.count={}; db.collapsed={}; db.excludedNames={}; db.excludedItemIDs={}
    db.totalTime=0; db.qAtlas={}; db.paused=true; db.lootedGold=0
    db.sessionStartTime=nil
    ns.ClearLog()
    if ns.LogFrame then ns.LogFrame:Hide() end
    NightsFarmtrackerDB.logWindowShown = false
    ns.StopTimer(); ns.CleanupPriceUpdate()
    GoldFrame:Hide()
    for _, row in pairs(itemRows) do ReleaseRow(row) end
    itemRows, itemOrder = {}, {}
    cachedGold = 0
    ns.UpdateTimerDisplay()
    MainFrame.totalGoldText:SetText("")
    btnRate.text:SetText("")
    ScrollFrame:SetVerticalScroll(0)
    UpdateFrameHeight()
    ns.ApplyPauseVisuals()
end

function ns.ApplyPauseVisuals()
    if NightsFarmtrackerDB.paused then
        btnPause.tex:SetTexture(ART.."btn_play.png")
        if ns.SessionLimitReached() then
            MainFrame.TimerText:SetTextColor(0.85, 0.3, 0.3)   -- session length used up
        else
            MainFrame.TimerText:SetTextColor(0.65, 0.70, 0.72)
        end
    else
        btnPause.tex:SetTexture(ART.."btn_pause.png")
        MainFrame.TimerText:SetTextColor(0.2, 0.85, 0.2)
    end
end

-- Category exclusion (Shift+Right-click on a category header). Categories
-- aren't individual items, so this still matches by name.
function ns.ExcludeItem(categoryName)
    NightsFarmtrackerDB.excludedNames[categoryName] = true
    for itemID, data in pairs(NightsFarmtrackerDB.count) do
        if ns.CategoryName(data) == categoryName then
            NightsFarmtrackerDB.count[itemID] = nil
        end
    end
    ns.RefreshHUD()
end

-- Item exclusion (Shift+Right-click on an item row). Keyed by itemID so it
-- survives a client-language switch, unlike the old name-based check.
-- Falls back to name if an itemID somehow isn't available.
function ns.ExcludeItemByID(itemID, name)
    if itemID then
        NightsFarmtrackerDB.excludedItemIDs[itemID] = true
        NightsFarmtrackerDB.count[itemID] = nil
    elseif name then
        NightsFarmtrackerDB.excludedNames[name] = true
        for id, data in pairs(NightsFarmtrackerDB.count) do
            if data.name == name then NightsFarmtrackerDB.count[id] = nil end
        end
    end
    ns.RefreshHUD()
end

------------------------------------------------------------------------
-- Button scripts
------------------------------------------------------------------------
btnClose:SetScript("OnClick", function()
    SafeHideMainFrame()
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
    -- A finished fixed-length session can't be resumed (it would just
    -- pause again on the next tick) - point to Reset / the setting instead.
    if NightsFarmtrackerDB.paused and ns.SessionLimitReached() then
        print("|cff30b0c0Night's Farmtracker:|r " .. ns.L["session_length_reached_resume"])
        return
    end
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

btnReset:SetScript("OnClick", function() ns.Reset(IsShiftKeyDown()) end)
btnReset:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText(ns.L["reset_session"])
    GameTooltip:AddLine(ns.L["reset_desc"],0.7,0.7,0.7,true)
    GameTooltip:AddLine(ns.L["reset_shift_hint"],0.5,0.5,0.5,true)
    GameTooltip:Show()
end)
btnReset:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

-- Left-click: Session History · Right-click: Loot Log
btnHistory:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btnHistory:SetScript("OnClick", function(self, button)
    local db = NightsFarmtrackerDB
    if button == "RightButton" then
        if db.logWindowEnabled == true then ns.ToggleLogWindow() end
    else
        if db.sessionHistoryEnabled ~= false then ns.ToggleHistory() end
    end
end)
btnHistory:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    local db          = NightsFarmtrackerDB
    local historyShown = db.sessionHistoryEnabled ~= false
    local logShown      = db.logWindowEnabled      == true
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    if historyShown and logShown then
        GameTooltip:SetText(ns.L["session_history"].." / "..ns.L["log_title"])
        GameTooltip:AddLine(ns.L["hist_log_left_hint"], 0.7,0.7,0.7)
        GameTooltip:AddLine(ns.L["hist_log_right_hint"], 0.7,0.7,0.7)
    elseif logShown then
        GameTooltip:SetText(ns.L["log_title"])
    else
        GameTooltip:SetText(ns.L["session_history"])
    end
    GameTooltip:Show()
end)
btnHistory:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

-- Left-click: Vendor-Only Filter · Right-click: Blacklist
btnFilter:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btnFilter:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        if NightsFarmtrackerDB.blacklistEnabled ~= false then ns.ToggleBlacklistWindow() end
    else
        if NightsFarmtrackerDB.vendorFilterEnabled ~= false then ns.ToggleFilterWindow() end
    end
end)
btnFilter:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    local db          = NightsFarmtrackerDB
    local vendorShown  = db.vendorFilterEnabled ~= false
    local blackShown   = db.blacklistEnabled    ~= false
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    if vendorShown and blackShown then
        GameTooltip:SetText(ns.L["filter_button"])
        GameTooltip:AddLine(ns.L["filter_left_hint"], 0.7,0.7,0.7)
        GameTooltip:AddLine(ns.L["filter_right_hint"], 0.7,0.7,0.7)
    elseif blackShown then
        GameTooltip:SetText(ns.L["blacklist_title"])
    else
        GameTooltip:SetText(ns.L["filter_title"])
    end
    GameTooltip:Show()
end)
btnFilter:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

btnSettings:SetScript("OnClick", function() ns.ToggleSettings() end)
btnSettings:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText(ns.L["settings"])
    GameTooltip:Show()
end)
btnSettings:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

-- Built once at load time (static content) instead of on every hover.
local helpSections = {
    { title = ns.L["help_categories"], lines = { ns.L["help_cat_click"], ns.L["help_cat_rclick"] } },
    { title = ns.L["help_items"],      lines = { ns.L["help_item_hover"], ns.L["help_item_rclick"] } },
    { title = ns.L["help_gold"],       lines = { ns.L["help_gold_click"] } },
    { title = ns.L["help_reset"],      lines = { ns.L["help_reset_shift"] } },
    { title = ns.L["help_histlog"],    lines = { ns.L["help_histlog_left"], ns.L["help_histlog_right"] } },
    { title = ns.L["help_filter"],     lines = { ns.L["help_filter_left"], ns.L["help_filter_right"] } },
    { title = ns.L["help_fishing"],    lines = { ns.L["help_fishing_hint"] } },
    { title = ns.L["help_export"],     lines = { ns.L["help_export_hint"] } },
}
table.sort(helpSections, function(a,b) return a.title < b.title end)

btnHelp:SetScript("OnEnter", function(self)
    self.tex:SetAlpha(1)
    GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(ns.L["help_title"],unpack(ns.COL_ACCENT))
    GameTooltip:AddLine(" ")
    for _,section in ipairs(helpSections) do
        GameTooltip:AddLine(section.title, 1,1,1)
        for _,line in ipairs(section.lines) do
            GameTooltip:AddLine(line, 0.7,0.7,0.7)
        end
    end
    GameTooltip:Show()
end)
btnHelp:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)

------------------------------------------------------------------------
-- Minimap button (LibDBIcon-1.0)
------------------------------------------------------------------------
local nftLDB  -- lazily created in InitMinimapButton

function ns.InitMinimapButton()
    local LDB    = LibStub("LibDataBroker-1.1")
    local DBIcon = LibStub("LibDBIcon-1.0")

    if not nftLDB then
        nftLDB = LDB:NewDataObject("NightsFarmtracker", {
            type  = "launcher",
            label = "Night's Farmtracker",
            icon  = ART.."Icon",
            OnClick = function(_, btn)
                if btn == "RightButton" then
                    ns.ToggleSettings()
                else
                    if MainFrame:IsShown() then
                        SafeHideMainFrame()
                    else
                        SafeShowMainFrame()
                    end
                end
            end,
            OnTooltipShow = function(tt)
                tt:AddLine("Night's Farmtracker", unpack(ns.COL_ACCENT))
                tt:AddLine(ns.L["mm_toggle"],   1, 1, 1)
                tt:AddLine(ns.L["mm_settings"], 0.7, 0.7, 0.7)
                tt:AddLine(ns.L["mm_drag"],     0.5, 0.5, 0.5)
            end,
        })
    end

    local db = NightsFarmtrackerDB
    if not db.minimap then
        db.minimap = {
            minimapPos = db.minimapPos or 225,
            hide       = db.minimapHidden or false,
        }
    end
    if not DBIcon:IsRegistered("NightsFarmtracker") then
        DBIcon:Register("NightsFarmtracker", nftLDB, db.minimap)
    end
end

function ns.SetMinimapVisible(show)
    local DBIcon = LibStub("LibDBIcon-1.0")
    NightsFarmtrackerDB.minimap.hide  = not show
    NightsFarmtrackerDB.minimapHidden = not show
    if show then DBIcon:Show("NightsFarmtracker")
    else         DBIcon:Hide("NightsFarmtracker") end
end

local function UpdateLeftButtons()
    local db           = NightsFarmtrackerDB
    local historyShown = db.sessionHistoryEnabled ~= false
    local logShown     = db.logWindowEnabled      == true
    local filterShown  = (db.vendorFilterEnabled ~= false) or (db.blacklistEnabled ~= false)
    local histLogShown = historyShown or logShown

    if histLogShown then btnHistory:Show(); btnHistory:EnableMouse(true)
    else                  btnHistory:Hide(); btnHistory:EnableMouse(false) end

    if filterShown then btnFilter:Show(); btnFilter:EnableMouse(true)
    else                  btnFilter:Hide(); btnFilter:EnableMouse(false) end

    -- Filter slides next to the Reset button when History/Log is hidden (no gap)
    btnFilter:ClearAllPoints()
    if histLogShown then
        btnFilter:SetPoint("LEFT", btnHistory, "RIGHT", 6, 0)
    else
        btnFilter:SetPoint("LEFT", btnReset, "RIGHT", 10, 0)
    end
end

-- Re-evaluates and re-lays-out the History/Log/Filter/Blacklist buttons.
-- Called whenever a setting affecting their visibility changes (session
-- history, loot log, vendor filter, or blacklist toggled on/off).
function ns.RefreshLeftButtons()
    UpdateLeftButtons()
end