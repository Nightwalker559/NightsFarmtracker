------------------------------------------------------------------------
-- Night's Farmtracker - UI
-- Main window: button bar (always visible), the item list and the footer
-- (total gold | timer | gold/rate), plus the Gold Overview window below it.
------------------------------------------------------------------------
local _, ns = ...

local PAD         = ns.PAD
local FRAME_W     = ns.FRAME_W
local FOOTER_H    = ns.FOOTER_H
local ROW_H       = ns.ROW_H
local CAT_ROW_H   = ns.CAT_ROW_H
local CAT_GAP     = ns.CAT_GAP
local ICON_X      = ns.ICON_X
local ICON_SIZE   = ns.ICON_SIZE
local CONTENT_W   = ns.CONTENT_W
local SCROLL_STEP = ns.SCROLL_STEP

-- Value bar of an item row: starts where the item name starts (NAME_GAP right
-- of the icon), its bottom edge flush with the icon border's bottom edge
-- (the border sticks out 1 px on every side of the icon, see ns.AddRowIcon),
-- running to the row's right edge (the category header's right edge).
local NAME_GAP   = ns.NAME_GAP
local BAR_H      = 2
local BAR_LEFT   = ICON_X + ICON_SIZE + NAME_GAP
local BAR_BOTTOM = (ROW_H - ICON_SIZE) / 2 - 1
local BAR_FULL_W = CONTENT_W - BAR_LEFT
local GOAL_COL   = {0.2, 0.85, 0.2}

local ART     = ns.ART
local MakeBtn = ns.MakeBtn

local HDR_PAD    = 6
local BTN_BAR_H  = 26
local HDR_TOTAL  = ns.WINDOW_HDR_H  -- same header height as every other window
local SCROLL_TOP = HDR_TOTAL + 1
local COLLAPSED_H = HDR_TOTAL + 1 + FOOTER_H
ns.COLLAPSED_H = COLLAPSED_H   -- the Loot Log docked below the collapsed window shares the height cap with it

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local itemRows  = {}
local itemOrder = {}
local cachedGold = 0
local totalH     = 0

------------------------------------------------------------------------
-- Main frame
------------------------------------------------------------------------
local MainFrame = CreateFrame("Frame","NightsFarmtrackerMain",UIParent,"BackdropTemplate")
MainFrame:SetSize(FRAME_W, COLLAPSED_H)
MainFrame:SetPoint("TOP", UIParent, "TOP", 0, -150)
MainFrame:Hide()
MainFrame:HookScript("OnHide", function(self) ns.HideTooltipOf(self) end)
-- Same strata as every other window of the addon.
MainFrame:SetFrameStrata("MEDIUM")
MainFrame:SetMovable(true); MainFrame:EnableMouse(true); MainFrame:SetClampedToScreen(true)
MainFrame:EnableMouseWheel(true)   -- the wheel must not scroll whatever lies behind the window
ns.ApplyFrameStyle(MainFrame)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", function(self)
    if not NightsFarmtrackerDB.mainLocked then self:StartMoving() end
end)
MainFrame:SetScript("OnDragStop", function(self)
    if NightsFarmtrackerDB.mainLocked then return end
    self:StopMovingOrSizing()
    local x, y = ns.AnchorToTop(self)
    if x then NightsFarmtrackerDB.pos = {"TOP", "TOP", x, y} end
end)
ns.MainFrame = MainFrame

------------------------------------------------------------------------
-- Button bar — always visible
-- Left:  [▶] [↺] [history/log] [filter/blacklist]
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

-- "NFT" watermark between the two button groups: readable, but dimmed
-- far enough not to compete with the buttons. Tinted like the icons
-- (gray by default, theme accent with the themed-buttons option).
local watermark = BtnBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
watermark:SetPoint("CENTER", BtnBar, "CENTER", 0, 0)
-- SetFont instead of SetFontHeight: the size change did not show up with
-- SetFontHeight on this template font. Same font file, explicit size.
watermark:SetFont((GameFontNormal:GetFont()), 16, "")
watermark:SetText("NFT")
watermark:SetAlpha(0.6)
ns.RegisterTintTex(watermark)

-- Theme decoration: a pumpkin on each side of the watermark (Hallow's End
-- theme). White artwork (same pumpkin as in Aureole Cursor), tinted with the
-- theme accent. Built hidden, shown by ns.ApplyThemeDecor once the saved
-- theme is known.
local decorLeft  = BtnBar:CreateTexture(nil, "OVERLAY")
local decorRight = BtnBar:CreateTexture(nil, "OVERLAY")
for _, tex in ipairs({ decorLeft, decorRight }) do
    tex:SetSize(20, 20)
    tex:SetTexture(ART .. "pumpkin.png")
    tex:SetAlpha(0.95)
    tex:Hide()
end
decorLeft:SetPoint("RIGHT", watermark, "LEFT", -6, 0)
decorRight:SetPoint("LEFT", watermark, "RIGHT", 6, 0)

function ns.ApplyThemeDecor()
    local shown = ns.THEME_DECOR == "pumpkin"
    for _, tex in ipairs({ decorLeft, decorRight }) do
        tex:SetVertexColor(unpack(ns.COL_ACCENT))
        tex:SetShown(shown)
    end
end

-- Separator below BtnBar
table.insert(MainFrame.nftEdges, ns.AddHLine(MainFrame, "TOP", PAD, -HDR_TOTAL))

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
local footerSep = ns.AddHLine(MainFrame, "BOTTOM", PAD, FOOTER_H - 2)
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
local ScrollFrame, ListFrame, OnWheel = ns.CreateScrollList(MainFrame, CONTENT_W, SCROLL_STEP)
ScrollFrame:SetPoint("TOPLEFT",     PAD,  -SCROLL_TOP)
ScrollFrame:SetPoint("BOTTOMRIGHT", -PAD,  FOOTER_H)
ScrollFrame:Hide()

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

    table.insert(GoldFrame.nftEdges, ns.AddHLine(GoldFrame, "TOP", gp, -26))

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

    table.insert(GoldFrame.nftEdges, ns.AddHLine(GoldFrame, "TOP", gp, -63))

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

-- Gold Overview, Lockout frame and (collapsed) Loot Log hang below the main
-- window. Near the bottom of the screen they would be clamped on top of it, so the window moves up by
-- the missing space instead (only on screen, the saved position stays).
function ns.KeepStackOnScreen()
    local bottom = MainFrame:GetBottom()
    if not bottom or not MainFrame:IsShown() then return end
    if InCombatLockdown() and ns.BaitDependsOnMainFrame and ns.BaitDependsOnMainFrame() then return end
    local below = 0
    if GoldFrame:IsShown() then below = below + GoldFrame:GetHeight() + 2 end
    local lockout = ns.LockoutFrame
    if lockout and lockout:IsShown() then below = below + lockout:GetHeight() + 2 end
    local log = ns.LogFrame   -- docked below the stack while the main window is collapsed
    if log and log:IsShown() and NightsFarmtrackerDB.expanded == false then below = below + ns.STACK_GAP + log:GetHeight() end
    local missing = below - bottom
    if missing <= 0 then return end
    local x, y = ns.AnchorToTop(MainFrame)
    if x then MainFrame:SetPoint("TOP", UIParent, "TOP", x, y + missing) end
end

function ns.ToggleGoldFrame()
    if ns.DeferInCombat(ns.ToggleGoldFrame) then return end
    if GoldFrame:IsShown() then GoldFrame:Hide()
    else GoldFrame:Show(); ns.UpdateGoldFrame() end
    -- GoldFrame always sits directly below MainFrame; when MainFrame is
    -- collapsed, LogFrame also wants that spot, so it chains below GoldFrame
    -- instead (avoids overlap) and gets less height.
    ns.RefreshLogDock()
    if GoldFrame:IsShown() then ns.KeepStackOnScreen() end
end

-- Closing the main window closes every popout that docks off it, so the
-- user doesn't end up with orphaned windows floating on screen.
local POPOUT_FRAMES = { "LogFrame", "FilterFrame", "SettingsFrame", "BlacklistFrame", "GoalsFrame",
                         "HistFrame", "DetailFrame", "VenomFrame" }

MainFrame:HookScript("OnHide", function()
    GoldFrame:Hide()
    for _, key in ipairs(POPOUT_FRAMES) do
        local f = ns[key]
        if f and f:IsShown() then f:Hide() end
    end
    if ns.BaitFrame and ns.BaitFrame:IsShown() then ns.SafeHideBaitFrame() end
end)

------------------------------------------------------------------------
-- Timer / rate
------------------------------------------------------------------------
-- Item goals and session length are mutually exclusive: db.limitMode picks
-- which one is active ("goal" | "session" | "off"), the other keeps its value.
-- The goal of one item (pieces) or nil: its own amount from db.itemGoals (only
-- while db.itemGoalsEnabled, so the list can stay without being emptied), else
-- the general db.itemGoal that covers every other item (0 = none), except
-- items in the Vendor-Only Filter: they only get a goal of their own. See
-- ApplyValueBars. Goals run the normal count-up timer.
function ns.GetItemGoal(itemID)
    local db = NightsFarmtrackerDB
    if db.limitMode ~= "goal" or not itemID then return nil end
    local entry = db.itemGoalsEnabled ~= false and db.itemGoals and db.itemGoals[itemID]
    local amount = entry and tonumber(entry.amount) or 0
    if amount <= 0 and not ns.IsForceVendor(itemID) then amount = tonumber(db.itemGoal) or 0 end
    return amount > 0 and amount or nil
end

-- Optional fixed session length (db.sessionLength minutes): the timer then
-- counts down and the session pauses itself at 0.
function ns.GetSessionLimit()
    if NightsFarmtrackerDB.limitMode ~= "session" then return nil end
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
    return SCROLL_TOP + 1 + ns.VisibleListHeight(totalH, SCROLL_TOP + 1, FOOTER_H) + FOOTER_H
end

------------------------------------------------------------------------
-- Combat-safe frame height. MainFrame:SetHeight() throws
-- ADDON_ACTION_BLOCKED during combat lockdown, but only while a protected
-- frame is anchored to it - that is the case while the Fishing Lure Bar's
-- secure lure buttons sit at the bar's default spot above this window
-- (ns.BaitDependsOnMainFrame). Only then is the change deferred to
-- PLAYER_REGEN_ENABLED (same pattern as SafeHideBaitFrame in
-- Modules/BaitFrame.lua). Otherwise the window must follow the item list at
-- once: deferring it always left new items cut off until combat ended.
------------------------------------------------------------------------
local pendingHeightUpdate = false

local function SafeSetMainHeight(height)
    if InCombatLockdown() and ns.BaitDependsOnMainFrame and ns.BaitDependsOnMainFrame() then
        pendingHeightUpdate = true
        return
    end
    MainFrame:SetHeight(height)
    ns.KeepStackOnScreen()
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

-- The footer line is dropped while the list ends in a collapsed header and
-- nothing scrolls (see ns.SetFooterLine); BuildHUD feeds the list state.
local listFlow, listScrolls = ns.NewHeaderFlow(), false
local function UpdateFooterLine()
    local expanded = NightsFarmtrackerDB.expanded
    ns.SetFooterLine(footerSep, listFlow,
        listScrolls or #itemOrder == 0 or not expanded,
        listScrolls and expanded and ns.ScrolledToEnd(ScrollFrame, ListFrame))
end
ScrollFrame:SetScript("OnVerticalScroll", UpdateFooterLine)

function ns.SetExpanded(expand)
    NightsFarmtrackerDB.expanded = expand
    if expand then
        btnToggle.tex:SetTexture(ART.."btn_collapse.png")
        UpdateFrameHeight()
    else
        emptyHint:Hide(); ScrollFrame:Hide()
        btnToggle.tex:SetTexture(ART.."btn_expand.png")
        SafeSetMainHeight(COLLAPSED_H)
    end
    UpdateFooterLine()
    ns.RefreshLogDock()   -- the log's size and place depend on the state
    ns.KeepStackOnScreen()
end

------------------------------------------------------------------------
-- Combat-safe hide for MainFrame. Hiding it can throw ADDON_ACTION_BLOCKED
-- during combat lockdown (its OnHide chain touches BaitFrame, which can
-- hold a SecureActionButtonTemplate lure button); defer until combat ends
-- instead of failing silently.
------------------------------------------------------------------------
local function SafeHideMainFrame()
    if ns.DeferInCombat(SafeHideMainFrame) then return end
    NightsFarmtrackerDB.visible = false
    MainFrame:Hide()
end

-- Symmetric guard for Show(): SlashCmdList and the minimap icon can also
-- call this while in combat, and Show() is just as much on the
-- ADDON_ACTION_BLOCKED list as Hide() (see comment above).
local function SafeShowMainFrame()
    local function show()
        NightsFarmtrackerDB.visible = true
        MainFrame:Show()
    end
    if not ns.DeferInCombat(show) then show() end
end

function ns.ToggleMainFrame()
    if MainFrame:IsShown() then SafeHideMainFrame() else SafeShowMainFrame() end
end

local heightWatcher = CreateFrame("Frame")
heightWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
heightWatcher:SetScript("OnEvent", function()
    if pendingHeightUpdate then
        pendingHeightUpdate = false
        UpdateFrameHeight()
    end
end)

local function UpdateSummary(itemGoldTotal)
    cachedGold = (itemGoldTotal or 0) + (NightsFarmtrackerDB.lootedGold or 0)
    MainFrame.totalGoldText:SetText(cachedGold > 0 and ns.FormatGold(cachedGold) or "")
    ns.UpdateGoldRate()
    ns.UpdateGoldFrame()
end

------------------------------------------------------------------------
-- Ctrl+Left-click: item -> Vendor-Only Filter, Ctrl+Right-click -> Blacklist.
-- Name/icon/quality come from the session data (db.count) so the entry
-- looks right in the Filter/Blacklist windows without an item-info lookup.
------------------------------------------------------------------------
local function AddItemToList(itemID, itemName, toBlacklist)
    local d = NightsFarmtrackerDB.count[itemID]
    local name, icon, quality = (d and d.name) or itemName, d and d.icon, d and d.quality
    if toBlacklist then
        ns.AddBlacklist(itemID, name, icon, quality)
        ns.Print(ns.L["msg_added_blacklist"]:format(name))
        ns.RebuildBlacklistList()
    elseif ns.IsForceVendor(itemID) then
        ns.Print(ns.L["msg_already_vendor"]:format(name))
        return
    else
        ns.AddForceVendor(itemID, name, icon, quality)
        ns.Print(ns.L["msg_added_vendor"]:format(name))
        ns.RebuildFilterList()
    end
    ns.RefreshHUD()  -- also drops a just-blacklisted item from the live count
end

------------------------------------------------------------------------
-- Row pool
------------------------------------------------------------------------
-- Default column layout of an item row: icon | name ... count | gold. Applied
-- to a new row and again when a pooled row is released (headers and the
-- price-source tag move these anchors).
local function ResetRowLayout(row)
    row:SetSize(CONTENT_W, ROW_H)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", ICON_X, 0)
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("LEFT",  row.icon, "RIGHT", NAME_GAP, 0)
    row.nameText:SetPoint("RIGHT", row,      "RIGHT", -128, 0)
    row.nameText:SetFontHeight(ns.FONT_NORMAL)
    row.nameText:SetMaxLines(2)
    row.countText:ClearAllPoints()
    row.countText:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    row.goldText:ClearAllPoints()
    row.goldText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.goldText:SetFontHeight(ns.FONT_NORMAL)
end

local rowPool = ns.NewPool(function(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(CONTENT_W, ROW_H)

    -- Header band (background + top/bottom line), only shown on category
    -- headers. Show/Hide rather than SetAlpha: a gradient texture doesn't
    -- reliably honor region alpha, so item rows would still draw the header
    -- gradient.
    ns.AddHeaderBand(row)
    ns.ShowHeaderBand(row, false)

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
        elseif self.itemName and not self.isJunkMerged then
            local db = NightsFarmtrackerDB
            if btn == "RightButton" and IsShiftKeyDown() then
                ns.ExcludeItemByID(self.baseItemID, self.itemName)
            elseif IsControlKeyDown() and self.baseItemID then
                if btn == "LeftButton" and db.vendorFilterEnabled ~= false then
                    AddItemToList(self.baseItemID, self.itemName, false)
                elseif btn == "RightButton" and db.blacklistEnabled ~= false then
                    AddItemToList(self.baseItemID, self.itemName, true)
                end
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
                local db = NightsFarmtrackerDB
                GameTooltip:AddLine(" ")
                if db.vendorFilterEnabled ~= false then
                    GameTooltip:AddLine(ns.L["item_tip_ctrl_lclick"],0.5,0.5,0.5)
                end
                if db.blacklistEnabled ~= false then
                    GameTooltip:AddLine(ns.L["item_tip_ctrl_rclick"],0.5,0.5,0.5)
                end
                GameTooltip:AddLine(ns.L["item_tip_shift_rclick"],0.5,0.5,0.5)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner()==self then GameTooltip:Hide() end
    end)

    ns.AddRowIcon(row)
    row.rankBadge = ns.CreateIconBadge(row, row.icon)

    -- All y=0 → vertically centered with the icon; long names wrap onto a
    -- second line (see ns.SetItemRowName)
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.SetupRowNameText(row.nameText)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.countText:SetJustifyH("RIGHT")
    row.countText:SetTextColor(0.78, 0.78, 0.78)
    row.countText:SetFontHeight(ns.FONT_NORMAL)

    row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.goldText:SetJustifyH("RIGHT")
    row.goldText:SetTextColor(unpack(ns.COL_GOLD))

    -- Price source tag ("AH" / "V") in its own fixed column at the right
    -- edge, after the gold amount; only filled in by ShowGold when the
    -- setting is on.
    row.srcText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.srcText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.srcText:SetWidth(20)
    row.srcText:SetJustifyH("LEFT")
    row.srcText:SetFontHeight(ns.FONT_SMALL)

    -- Value bar: track plus fill; only the fill's width and color change (DrawBar).
    row.barBg = row:CreateTexture(nil, "ARTWORK")
    row.barBg:SetHeight(BAR_H)
    row.barBg:SetColorTexture(1, 1, 1, 0.08)
    row.barBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", BAR_LEFT, BAR_BOTTOM)
    row.barBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, BAR_BOTTOM)
    row.bar = row:CreateTexture(nil, "OVERLAY")
    row.bar:SetHeight(BAR_H)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", BAR_LEFT, BAR_BOTTOM)
    row.barBg:Hide(); row.bar:Hide()
    row.barValue, row.barCount = false, false

    ResetRowLayout(row)
    return row
end, function(row)
    row.barBg:Hide(); row.bar:Hide(); row.barValue = false; row.barCount = false; row.barGoal = nil
    row.itemName=nil; row.itemLink=nil; row.itemID=nil; row.baseItemID=nil
    row.isCategoryHeader=nil; row.categoryName=nil; row.isJunkMerged=nil
    ns.ShowHeaderBand(row, false)
    ResetRowLayout(row)
    row.icon:Show()
    row.srcText:SetText("")
    row.rankBadge:SetText("")
end)

-- Releases every row of the current list.
local function ClearRows()
    for _, row in pairs(itemRows) do rowPool.release(row) end
    itemRows, itemOrder = {}, {}
end

local function PlaceRow(row, yOff, name, icon, nameColor, quality)
    row:SetPoint("TOPLEFT", 0, -yOff)
    row.itemName = name
    row.icon:SetTexture(icon or ns.FALLBACK_ICON)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); row.icon:Show()
    row.nameText:SetText(name)
    if nameColor then
        row.nameText:SetTextColor(unpack(nameColor)); row.iconBorder:Hide()
    else
        ns.ApplyQualityColor(row.nameText, row.iconBorder, quality, {1,1,1})
    end
    itemOrder[#itemOrder+1] = name
    itemRows[name] = row
end

-- Hands back a category header row that turned out to have nothing to show.
local function DropLastHeader(row, name)
    rowPool.release(row)
    itemRows[name] = nil
    itemOrder[#itemOrder] = nil   -- PlaceRow appended it; keep #itemOrder = real rows
end

-- Same rule as ns.ItemValue: vendor price when forced (filters, BoP, no AH
-- source, Gear AH Threshold), otherwise the higher of AH and vendor price -
-- so a row always shows the value that goes into its category total.
-- With "Show price source" on, a small "AH" / "V" tag tells which of the two
-- it is; the name and count columns shift left to make room for it.
local SRC_SHIFT = 24
local function ShowGold(row, ah, vendor, forceVendor)
    local shown = forceVendor and (vendor or 0) or math.max(ah or 0, vendor or 0)
    row.barValue = shown
    row.goldText:SetText(shown > 0 and ns.FormatGold(shown) or "")
    if NightsFarmtrackerDB.showPriceSource and shown > 0 then
        local fromAH = not forceVendor and (ah or 0) >= (vendor or 0)
        row.srcText:SetText(fromAH and "AH" or "V")
        if fromAH then row.srcText:SetTextColor(0.4, 0.75, 1) else row.srcText:SetTextColor(0.6, 0.6, 0.6) end
        row.goldText:SetPoint("RIGHT", row, "RIGHT", -4 - SRC_SHIFT, 0)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -128 - SRC_SHIFT, 0)
        row.countText:SetPoint("RIGHT", row, "RIGHT", -90 - SRC_SHIFT, 0)
    else
        row.srcText:SetText("")
    end
end

-- Value bars: every item row's value relative to the most valuable row, in
-- the theme's accent color. The merged junk row is a category sum, so it is
-- left out of the scale (and capped at full length) unless it is all there is.
local goalReached = false
local barsShown   = true   -- db.showValueBar, read once per ApplyValueBars

local function DrawBar(row, frac, r, g, b)
    if not barsShown then return end
    row.bar:SetWidth(math.max(1, math.floor(BAR_FULL_W * math.min(1, frac))))
    row.bar:SetColorTexture(r, g, b, 0.85)
    row.barBg:Show(); row.bar:Show()
end

-- Rows of an item with a goal (db.itemGoals / db.itemGoal) show their count relative to the
-- goal instead, and turn green once it is reached; goalReached then tells
-- BuildHUD to pause the session (also with the bars switched off). The merged
-- junk row is a sum of many items, so it has no goal. Every other row keeps
-- the value bar, scaled among the rows without a goal.
local function ApplyValueBars()
    goalReached = false
    barsShown = NightsFarmtrackerDB.showValueBar ~= false

    local maxValue, maxMerged = 0, 0
    for _, row in pairs(itemRows) do
        local goal = not row.isJunkMerged and row.barCount and ns.GetItemGoal(row.itemID)
        if goal then
            local c = row.barCount
            row.barGoal = goal
            if c >= goal then
                goalReached = true
                DrawBar(row, 1, unpack(GOAL_COL))
            else
                DrawBar(row, c / goal, unpack(ns.COL_ACCENT))
            end
        else
            row.barGoal = nil
            local v = row.barValue
            if v then
                if row.isJunkMerged then maxMerged = math.max(maxMerged, v)
                else maxValue = math.max(maxValue, v) end
            end
        end
    end
    if not barsShown then return end

    if maxValue == 0 then maxValue = maxMerged end
    for _, row in pairs(itemRows) do
        local v = row.barValue
        if not row.barGoal and v and v > 0 and maxValue > 0 then
            DrawBar(row, v / maxValue, unpack(ns.COL_ACCENT))
        end
    end
end

function ns.GoalReached() return goalReached end

------------------------------------------------------------------------
-- RefreshHUD
-- BuildHUD rebuilds the whole item list (every row, price lookup and sort).
-- It is requested on every loot event, every settings click and again 2 s
-- after each drop, so ns.RefreshHUD only queues one rebuild for the next frame
-- and any number of requests within a frame collapse into it.
------------------------------------------------------------------------
local function ItemSort(a, b)
    if a.gold ~= b.gold then return a.gold > b.gold end
    if a.data.amount ~= b.data.amount then return a.data.amount > b.data.amount end
    return a.name < b.name
end

-- Groups db.count into categories ({ items, totalGold, classID }) and returns
-- them with the grand total. Quest items (never sellable) and items
-- blacklisted after they were looted are dropped from the live count too.
local function CollectCategories(db)
    local cats, grandTotal = {}, 0
    for itemID, data in pairs(db.count) do
        if data.classID == ns.QUEST_CLASS
           or ns.IsBlacklisted(data.itemID) or ns.IsBlacklistCategory(data) then
            db.count[itemID] = nil
        else
            local cat = ns.CategoryName(data)
            if not cats[cat] then cats[cat] = {items = {}, totalGold = 0, classID = data.classID} end
            local c         = cats[cat]
            local vendorRaw = ns.VendorTotal(data)
            local ahRaw     = ns.AHTotal(data)
            local gold      = ns.ItemValue(data, vendorRaw, ahRaw) or 0
            c.items[#c.items + 1] = {name = data.name, itemID = itemID, data = data, gold = gold,
                                     vendor = vendorRaw or 0, ah = ahRaw or 0}
            c.totalGold = c.totalGold + gold
            grandTotal  = grandTotal + gold
        end
    end
    return cats, grandTotal
end

-- Junk shows as one "Plunder" row from the very first junk item. Display
-- only: db.count is untouched, so switching the setting off restores the
-- per-item list at once.
local function MergeJunkCategories(cats)
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

-- Valuable-gear sound: independent of category collapse and Junk merging. It
-- checks the displayed (itemLevel, quality) groups (GroupGearVariantsForDisplay),
-- because identical-looking rolls can carry different hidden bonus IDs and no
-- single raw bucket would reach the threshold. It fires once per new copy of a
-- group whose per-unit AH price reaches the Gear AH Threshold;
-- thresholdNotifiedCounts remembers the last amount checked per group, so a
-- second drop alerts again.
local function PlayGearThresholdSound(db, hasAH)
    if not (db.gearAHThresholdSound and hasAH) then return end
    local threshold = db.gearAHThreshold or 0
    if threshold <= 0 then return end
    for _, data in pairs(db.count) do
        if data.variants and ns.IsGearThresholdApplicable(data) and not ns.IsVendorOnly(data) then
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

-- Category header row; returns it so an empty category can be dropped again.
-- flow (ns.NewHeaderFlow) decides whether the header draws its top line.
local function PlaceCategoryHeader(catName, cat, isCollapsed, yOffset, flow)
    local hdr = rowPool.acquire(ListFrame)
    hdr:SetSize(CONTENT_W, CAT_ROW_H)
    PlaceRow(hdr, yOffset, catName, nil, ns.COL_ACCENT)
    hdr.icon:Hide(); hdr.iconBorder:Hide()
    hdr.countText:SetText("")
    hdr.isCategoryHeader = true; hdr.categoryName = catName
    ns.ShowHeaderBand(hdr, true)
    flow.header(hdr)
    ns.SetHeaderArrow(hdr, isCollapsed)
    hdr.nameText:ClearAllPoints()
    hdr.nameText:SetPoint("LEFT",  ns.HEADER_TEXT_X, 0)
    hdr.nameText:SetPoint("RIGHT", hdr, "RIGHT", -100, 0)
    hdr.nameText:SetText(catName)
    hdr.nameText:SetFontHeight(ns.FONT_NORMAL)
    hdr.nameText:SetMaxLines(1)   -- a header is one line high; item rows may wrap onto two
    hdr.goldText:ClearAllPoints()
    -- same right edge as the item amounts below (they leave room for the AH/V tag)
    hdr.goldText:SetPoint("RIGHT", hdr, "RIGHT", NightsFarmtrackerDB.showPriceSource and (-4 - SRC_SHIFT) or -4, 0)
    hdr.goldText:SetFontHeight(ns.FONT_NORMAL)
    hdr.goldText:SetText(cat.totalGold > 0 and ns.FormatGold(cat.totalGold) or "")
    return hdr
end

-- Reagent items: one entry per quality tier that has a value.
local function AddTierEntries(flat, item, fv, qAtlas)
    local d = item.data
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
            local tGold = fv and (tV or 0) or math.max(tAH or 0, tV or 0)
            if tGold > 0 then
                flat[#flat + 1] = {
                    isRank = true, name = item.name, d = d,
                    tier = tier, tid = tid, tc = tc,
                    tAH = tAH, tV = tV, tGold = tGold,
                    rankIcon = ns.RankBadgeMarkup(qAtlas[tier], tier), fv = fv,
                }
            end
        end
    end
end

-- Scaling gear: one entry per displayed (itemLevel, quality) group, so
-- amounts and prices of different rolls don't mix.
local function AddGearEntries(flat, item, hasAH)
    local d = item.data
    for ilvl, gv in pairs(ns.GroupGearVariantsForDisplay(d.variants)) do
        if gv.amount > 0 then
            local sp  = ns.VariantSellPrice(gv, d)
            local tV  = (sp and sp > 0) and (sp * gv.amount) or nil
            local ap  = hasAH and ns.GetAHPriceForID(d.itemID, gv.itemLink) or nil
            local tAH = ap and (ap * gv.amount) or nil
            -- Decided per variant, not from the item's combined AH total: one
            -- variant crossing the Gear AH Threshold must not force AH pricing
            -- onto a cheaper sibling below it.
            local vfv   = not hasAH or ns.IsVendorOnly(d) or ns.IsGearThresholdVendorOnly(d, tAH)
            local tGold = vfv and (tV or 0) or math.max(tAH or 0, tV or 0)
            if tGold > 0 then
                flat[#flat + 1] = {
                    isGearVariant = true, name = item.name, d = d,
                    ilvl = ilvl, gv = gv, tV = tV, tAH = tAH, tGold = tGold, fv = vfv,
                }
            end
        end
    end
end

-- Display entries of one category, by gold descending.
local function BuildFlatList(cat, hasAH, qAtlas)
    local flat = {}
    for _, item in ipairs(cat.items) do
        local d = item.data
        local fv = not hasAH or ns.IsVendorOnly(d) or ns.IsGearThresholdVendorOnly(d, item.ah)
        if d.variants and not ns.IsGear(d) then
            AddTierEntries(flat, item, fv, qAtlas)
        elseif d.variants then
            AddGearEntries(flat, item, hasAH)
        else
            local gold = fv and (item.vendor or 0) or math.max(item.ah or 0, item.vendor or 0)
            flat[#flat + 1] = {isRank = false, name = item.name, d = d, item = item, gold = gold, fv = fv}
        end
    end
    table.sort(flat, function(a, b)
        local ga = (a.isRank or a.isGearVariant) and a.tGold or a.gold
        local gb = (b.isRank or b.isGearVariant) and b.tGold or b.gold
        if ga ~= gb then return ga > gb end
        return a.name < b.name
    end)
    return flat
end

local function RenderFlatRow(fi, yOffset)
    local row = rowPool.acquire(ListFrame)
    local d = fi.d
    row.icon:SetTexture(d.icon or ns.FALLBACK_ICON)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); row.icon:Show()
    row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", ICON_X, 0)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    ns.ApplyQualityColor(row.nameText, row.iconBorder, fi.isGearVariant and fi.gv.quality or d.quality, {1, 1, 1})
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("LEFT",  row.icon, "RIGHT", NAME_GAP, 0)
    row.nameText:SetPoint("RIGHT", row,      "RIGHT", -108, 0)

    if fi.isRank then
        local key = tostring(d.itemID) .. "_q" .. fi.tier
        row.itemName = fi.name; row.itemID = fi.tid; row.itemLink = nil; row.baseItemID = d.itemID
        row.rankBadge:SetText(fi.rankIcon or "")
        row.countText:SetText(tostring(fi.tc)); row.barCount = fi.tc
        ShowGold(row, fi.tAH, fi.tV, fi.fv)
        ns.SetItemRowName(row.nameText, ns.DisplayName(fi.name, fi.tid))
        itemOrder[#itemOrder + 1] = key; itemRows[key] = row
    elseif fi.isGearVariant then
        local gv  = fi.gv
        local key = tostring(d.itemID) .. "_g" .. tostring(fi.ilvl)
        row.itemName = fi.name; row.itemID = d.itemID; row.itemLink = gv.itemLink; row.baseItemID = d.itemID
        row.rankBadge:SetText("")
        row.countText:SetText(tostring(gv.amount)); row.barCount = gv.amount
        ShowGold(row, fi.tAH, fi.tV, fi.fv)
        ns.SetItemRowName(row.nameText, ns.DisplayName(fi.name, gv.itemLink or d.itemID))
        itemOrder[#itemOrder + 1] = key; itemRows[key] = row
    else
        local it = fi.item
        row.isJunkMerged = d.isJunkMerged
        row.itemName = fi.name
        if d.isJunkMerged then
            row.itemID, row.itemLink, row.baseItemID = nil, nil, nil
        else
            row.itemID, row.itemLink, row.baseItemID = d.itemID, d.itemLink, d.itemID
        end
        row.rankBadge:SetText(ns.RankIconFromLink(d.itemLink) or "")
        row.countText:SetText(tostring(d.amount)); row.barCount = d.amount
        ShowGold(row, it.ah, it.vendor, fi.fv)
        ns.SetItemRowName(row.nameText, d.isJunkMerged and fi.name or ns.DisplayName(fi.name, d.itemID))
        itemOrder[#itemOrder + 1] = it.itemID; itemRows[it.itemID] = row
    end
end

local function BuildHUD()
    local savedScroll = ScrollFrame:GetVerticalScroll()
    ClearRows()

    local db = NightsFarmtrackerDB
    local cats, grandTotal = CollectCategories(db)
    if db.mergeJunkEntries then MergeJunkCategories(cats) end
    for _, cat in pairs(cats) do table.sort(cat.items, ItemSort) end

    -- With no AH source (or "none" selected) every item is valued at vendor price
    local hasAH = ns.HasAnyAH() and db.ahSource ~= "none"
    PlayGearThresholdSound(db, hasAH)

    -- Categories by total gold (the sum of ns.ItemValue, matching the overall
    -- total), ties by item class priority.
    local sorted = {}
    for catName, cat in pairs(cats) do sorted[#sorted + 1] = {name = catName, cat = cat} end
    table.sort(sorted, function(a, b)
        return ns.CategoryBefore(a.cat.totalGold, a.cat.classID, b.cat.totalGold, b.cat.classID)
    end)

    local yOffset = 0
    local flow = ns.NewHeaderFlow()
    for _, entry in ipairs(sorted) do
        local catName, cat = entry.name, entry.cat
        local isCollapsed = db.collapsed[catName]
        local lineAbove = flow.after
        local hdr = PlaceCategoryHeader(catName, cat, isCollapsed, yOffset, flow)
        yOffset = yOffset + CAT_ROW_H

        if not isCollapsed then
            local flat = BuildFlatList(cat, hasAH, db.qAtlas or {})
            if #flat == 0 then
                -- nothing displayable: skip the category entirely
                DropLastHeader(hdr, catName)
                yOffset = yOffset - CAT_ROW_H
                flow.after = lineAbove
            else
                yOffset = yOffset + CAT_GAP
                for _, fi in ipairs(flat) do
                    RenderFlatRow(fi, yOffset)
                    yOffset = yOffset + ROW_H
                end
                yOffset = yOffset + CAT_GAP
                flow.rows()
            end
        end
    end

    local wasReached = goalReached
    ApplyValueBars()
    if goalReached and not db.paused then
        db.paused = true
        ns.StopTimer()
        ns.Print(ns.L["item_goal_reached"])
    end
    if goalReached ~= wasReached then ns.ApplyPauseVisuals() end

    totalH = yOffset
    local maxScroll = math.max(0, totalH - ScrollFrame:GetHeight())
    ScrollFrame:SetVerticalScroll(math.min(savedScroll, maxScroll))
    UpdateFrameHeight()
    listFlow = flow
    listScrolls = ns.VisibleListHeight(totalH, SCROLL_TOP + 1, FOOTER_H) < totalH
    UpdateFooterLine()
    UpdateSummary(grandTotal)

    if ns.FilterFrame and ns.FilterFrame:IsShown() then
        ns.RebuildFilterList()
    end
end

local refreshQueued = false

function ns.RefreshHUD()
    if refreshQueued then return end
    refreshQueued = true
    RunNextFrame(function()
        refreshQueued = false   -- reset first: a later request must still get through if BuildHUD errors
        BuildHUD()
    end)
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
    db.ahLast=nil   -- last-known AH prices belong to the filed session
    ns.ClearLog()
    if ns.LogFrame then ns.LogFrame:Hide() end
    db.logWindowShown = false
    ns.StopTimer(); ns.CleanupPriceUpdate()
    GoldFrame:Hide()
    ClearRows()
    cachedGold = 0
    goalReached = false
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
        if ns.SessionLimitReached() or ns.GoalReached() then
            MainFrame.TimerText:SetTextColor(0.85, 0.3, 0.3)   -- session length used up / goal reached
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
-- survives a client-language switch; falls back to the name when no itemID
-- is available.
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
-- MakeBtn already dims the icons and nudges them when pressed; this adds
-- the tooltip. fill(tooltip) writes the lines.
local function SetBtnTooltip(btn, anchor, fill)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor)
        fill(GameTooltip)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

btnClose:SetScript("OnClick", function()
    SafeHideMainFrame()
    GoldFrame:Hide()
end)
SetBtnTooltip(btnClose, "ANCHOR_LEFT", function(tip) tip:SetText(ns.L["close"]) end)

btnToggle:SetScript("OnClick", function()
    ns.SetExpanded(not NightsFarmtrackerDB.expanded)
end)
SetBtnTooltip(btnToggle, "ANCHOR_LEFT", function(tip)
    tip:SetText(NightsFarmtrackerDB.expanded and ns.L["collapse"] or ns.L["expand"])
end)

btnPause:SetScript("OnClick", function()
    -- A finished fixed-length session can't be resumed (it would just
    -- pause again on the next tick): point to Reset / the setting instead.
    if NightsFarmtrackerDB.paused and ns.SessionLimitReached() then
        ns.Print(ns.L["session_length_reached_resume"])
        return
    end
    if NightsFarmtrackerDB.paused and ns.GoalReached() then
        ns.Print(ns.L["item_goal_reached_resume"])
        return
    end
    NightsFarmtrackerDB.paused = not NightsFarmtrackerDB.paused
    if NightsFarmtrackerDB.paused then ns.StopTimer() else ns.StartTimer() end
    ns.ApplyPauseVisuals()
end)
SetBtnTooltip(btnPause, "ANCHOR_RIGHT", function(tip)
    tip:SetText(NightsFarmtrackerDB.paused and ns.L["start_tracking"] or ns.L["pause_tracking"])
end)

btnReset:SetScript("OnClick", function() ns.Reset(IsShiftKeyDown()) end)
SetBtnTooltip(btnReset, "ANCHOR_RIGHT", function(tip)
    tip:SetText(ns.L["reset_session"])
    tip:AddLine(ns.L["reset_desc"], 0.7, 0.7, 0.7, true)
    tip:AddLine(ns.L["reset_shift_hint"], 0.5, 0.5, 0.5, true)
end)

-- Left-click: Session History · Right-click: Loot Log
btnHistory:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btnHistory:SetScript("OnClick", function(_, button)
    local db = NightsFarmtrackerDB
    if button == "RightButton" then
        if db.logWindowEnabled == true then ns.ToggleLogWindow() end
    else
        if db.sessionHistoryEnabled ~= false then ns.ToggleHistory() end
    end
end)
SetBtnTooltip(btnHistory, "ANCHOR_RIGHT", function(tip)
    local db = NightsFarmtrackerDB
    local historyShown = db.sessionHistoryEnabled ~= false
    local logShown     = db.logWindowEnabled == true
    if historyShown and logShown then
        tip:SetText(ns.L["session_history"] .. " / " .. ns.L["log_title"])
        tip:AddLine(ns.L["hist_log_left_hint"], 0.7, 0.7, 0.7)
        tip:AddLine(ns.L["hist_log_right_hint"], 0.7, 0.7, 0.7)
    elseif logShown then
        tip:SetText(ns.L["log_title"])
    else
        tip:SetText(ns.L["session_history"])
    end
end)

-- Left-click: Vendor-Only Filter · Right-click: Blacklist
btnFilter:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btnFilter:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        if NightsFarmtrackerDB.blacklistEnabled ~= false then ns.ToggleBlacklistWindow() end
    else
        if NightsFarmtrackerDB.vendorFilterEnabled ~= false then ns.ToggleFilterWindow() end
    end
end)
SetBtnTooltip(btnFilter, "ANCHOR_RIGHT", function(tip)
    local db = NightsFarmtrackerDB
    local vendorShown = db.vendorFilterEnabled ~= false
    local blackShown  = db.blacklistEnabled ~= false
    if vendorShown and blackShown then
        tip:SetText(ns.L["filter_button"])
        tip:AddLine(ns.L["filter_left_hint"], 0.7, 0.7, 0.7)
        tip:AddLine(ns.L["filter_right_hint"], 0.7, 0.7, 0.7)
    elseif blackShown then
        tip:SetText(ns.L["blacklist_title"])
    else
        tip:SetText(ns.L["filter_title"])
    end
end)

btnSettings:SetScript("OnClick", function() ns.ToggleSettings() end)
SetBtnTooltip(btnSettings, "ANCHOR_RIGHT", function(tip) tip:SetText(ns.L["settings"]) end)

btnHelp:SetScript("OnClick", function() ns.ToggleHelpWindow() end)
SetBtnTooltip(btnHelp, "ANCHOR_BOTTOMRIGHT", function(tip) ns.FillHelpTooltip(tip) end)

-- Re-evaluates and re-lays-out the History/Log/Filter/Blacklist buttons.
-- Called whenever a setting affecting their visibility changes (session
-- history, loot log, vendor filter, or blacklist toggled on/off).
function ns.RefreshLeftButtons()
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