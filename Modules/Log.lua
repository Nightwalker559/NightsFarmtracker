------------------------------------------------------------------------
-- Night's Farmtracker - Loot Log
-- Optional feed window: one line per loot event (icon, name, amount).
-- Survives /reload and relogs (SavedVariablesPerCharacter); only cleared
-- when the session itself is reset.
------------------------------------------------------------------------
local _, ns = ...

local LOG_W       = ns.FRAME_W
local LOG_PAD     = ns.PAD
local LOG_HDR_H   = ns.WINDOW_HDR_H
local ROW_H       = ns.ROW_H
local MAX_VIS_H   = 8 * ROW_H
local MIN_VIS_H   = 30
local MAX_ENTRIES = 100  -- in-memory cap, oldest entries drop off

-- Row layout (the window is as wide as its widest row, see RebuildLogList)
local TIME_W         = 38
local ROW_GAP        = 4   -- time|icon|name
local ROW_EDGE       = 4   -- left/right row padding
local NAME_COUNT_GAP = 6   -- name|amount
local EMPTY_PAD      = 20  -- room around the "no entries" label

local LogFrame, LScrollFrame, LListFrame

-- Backed by NightsFarmtrackerDB.logEntries (SavedVariablesPerCharacter), so
-- it survives /reload and relogs. Only ns.ClearLog() (called on session
-- reset) empties it - never written anywhere else, never account-wide.

------------------------------------------------------------------------
-- Row pool
------------------------------------------------------------------------
local activeRows = {}
local rowPool    = {}

local function AcquireRow()
    local r = table.remove(rowPool)
    if r then r:SetParent(LListFrame); r:Show(); return r end

    r = CreateFrame("Frame", nil, LListFrame)
    r:SetSize(ns.CONTENT_W, ROW_H)

    r.sep = r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1)
    r.sep:SetColorTexture(0.12,0.22,0.25,0.5)
    r.sep:SetPoint("BOTTOMLEFT",0,0); r.sep:SetPoint("BOTTOMRIGHT",0,0)

    r.timeText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.timeText:SetPoint("LEFT", 4, 0)
    r.timeText:SetWidth(38)
    r.timeText:SetJustifyH("LEFT"); r.timeText:SetFontHeight(ns.FONT_NORMAL)
    r.timeText:SetTextColor(0.45,0.45,0.45)

    r.icon = r:CreateTexture(nil,"ARTWORK")
    r.icon:SetSize(ns.ICON_SIZE, ns.ICON_SIZE)
    r.icon:SetPoint("LEFT", r.timeText, "RIGHT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.iconBorder = r:CreateTexture(nil,"BACKGROUND")
    r.iconBorder:SetPoint("TOPLEFT",     r.icon,"TOPLEFT",     -1,  1)
    r.iconBorder:SetPoint("BOTTOMRIGHT", r.icon,"BOTTOMRIGHT",  1, -1)
    r.iconBorder:Hide()

    r.rankBadge = ns.CreateIconBadge(r, r.icon)

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT", r.icon, "RIGHT", ROW_GAP, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(ns.FONT_NORMAL)
    r.nameText:SetTextColor(0.85,0.85,0.85)

    r.countText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.countText:SetPoint("LEFT", r.nameText, "RIGHT", NAME_COUNT_GAP, 0)
    r.countText:SetJustifyH("LEFT"); r.countText:SetFontHeight(ns.FONT_NORMAL)
    r.countText:SetTextColor(unpack(ns.COL_GOLD))

    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if self.itemLink then
            ns.ShowItemTooltipNoCompare(self, ns.SmartAnchor(self, "RIGHT"), self.itemLink)
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function ReleaseRow(r)
    r:Hide(); r:ClearAllPoints(); r.itemLink = nil
    r.iconBorder:Hide()
    r.rankBadge:SetText("")
    rowPool[#rowPool+1] = r
end

------------------------------------------------------------------------
-- List rebuild
------------------------------------------------------------------------
local function RebuildLogList()
    if not LListFrame then return end
    for _, r in ipairs(activeRows) do ReleaseRow(r) end
    activeRows = {}

    local yOff, widest = 0, 0
    for _, e in ipairs(NightsFarmtrackerDB.logEntries or {}) do
        local r = AcquireRow()
        r:SetPoint("TOPLEFT", 0, -yOff)
        r.sep:SetShown(yOff > 0)
        r.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
        r.timeText:SetText(date("%H:%M", e.timestamp or time()))
        r.nameText:SetText(ns.TruncateName(ns.DisplayName(e.name, e.itemLink)))
        r.rankBadge:SetText(e.rankIcon or "")
        r.countText:SetText("x" .. e.amount)
        r.itemLink = e.itemLink
        ns.ApplyQualityColor(r.nameText, r.iconBorder, e.quality, {0.85, 0.85, 0.85})
        activeRows[#activeRows+1] = r
        yOff = yOff + ROW_H
        widest = math.max(widest, ROW_EDGE + TIME_W + ROW_GAP + ns.ICON_SIZE + ROW_GAP
            + r.nameText:GetStringWidth() + NAME_COUNT_GAP + r.countText:GetStringWidth() + ROW_EDGE)
    end

    -- Window width follows the widest row; never narrower than the title
    -- (plus close button) or, with no entries, the "empty" label.
    local minW = LogFrame.titleFS:GetStringWidth() + 2 * (LOG_PAD + 22)
    if #activeRows == 0 then
        minW = math.max(minW, LogFrame.emptyLabel:GetStringWidth() + 2 * EMPTY_PAD)
    end
    local frameW   = math.ceil(math.max(minW, widest + 2 * LOG_PAD))
    local contentW = frameW - 2 * LOG_PAD
    for _, r in ipairs(activeRows) do r:SetWidth(contentW) end
    LScrollFrame:SetWidth(contentW); LListFrame:SetWidth(contentW)
    local widthChanged = math.abs(LogFrame:GetWidth() - frameW) > 0.5
    LogFrame:SetWidth(frameW)

    local contentH = math.max(1, yOff)
    LListFrame:SetHeight(contentH)
    local visH = math.max(MIN_VIS_H, math.min(contentH, MAX_VIS_H))
    LScrollFrame:SetHeight(visH)
    LogFrame:SetHeight(LOG_HDR_H + visH + 10)

    LogFrame.emptyLabel:SetShown(#(NightsFarmtrackerDB.logEntries or {}) == 0)

    -- Docking decides left/right (or below) by the frame's width: redo it
    if widthChanged and LogFrame:IsShown() and ns.ReanchorLogFrame then ns.ReanchorLogFrame() end
end

------------------------------------------------------------------------
-- Public API - logging
------------------------------------------------------------------------
function ns.AddLogEntry(icon, name, amount, itemLink, quality, rankIcon)
    if NightsFarmtrackerDB.logWindowEnabled ~= true then return end
    local entries = NightsFarmtrackerDB.logEntries
    if not entries then entries = {}; NightsFarmtrackerDB.logEntries = entries end
    table.insert(entries, 1, { icon = icon, name = name, amount = amount, itemLink = itemLink, quality = quality, rankIcon = rankIcon, timestamp = time() })
    while #entries > MAX_ENTRIES do table.remove(entries) end
    if LogFrame and LogFrame:IsShown() then RebuildLogList() end
end

function ns.ClearLog()
    NightsFarmtrackerDB.logEntries = {}
    if LogFrame and LogFrame:IsShown() then RebuildLogList() end
end

-- Corrects the stored quality (and thus display color) of any already-
-- written log entries for this itemID. Log entries are written once at
-- loot time and never otherwise revisited, so if the loot-time quality
-- guess was wrong (see ns.UpdatePricesFromBags), this is the only way
-- they get fixed up after the fact.
function ns.UpdateLogEntryQuality(itemID, quality)
    if not itemID or not quality then return end
    local entries = NightsFarmtrackerDB.logEntries
    if not entries then return end
    local changed = false
    for _, e in ipairs(entries) do
        if e.itemLink and e.quality ~= quality then
            local eID = tonumber(e.itemLink:match("item:(%d+)"))
            if eID == itemID then
                e.quality = quality
                changed = true
            end
        end
    end
    if changed and LogFrame and LogFrame:IsShown() then RebuildLogList() end
end

------------------------------------------------------------------------
-- Build window (lazy)
------------------------------------------------------------------------
local function EnsureLogFrame()
    if LogFrame then return end

    LogFrame = ns.CreateWindowFrame("NightsFarmtrackerLogWnd", ns.L["log_title"], {width = LOG_W})
    LogFrame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 4, 0)
    ns.LogFrame = LogFrame  -- exposed so other windows (e.g. Filter) can anchor next to it
    LogFrame.closeBtn:HookScript("OnClick", function()
        NightsFarmtrackerDB.logWindowShown = false
    end)

    local hSep = LogFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT", LOG_PAD, -(LOG_HDR_H-1)); hSep:SetPoint("TOPRIGHT", -LOG_PAD, -(LOG_HDR_H-1))

    LScrollFrame = CreateFrame("ScrollFrame", nil, LogFrame)
    LScrollFrame:SetPoint("TOPLEFT", LOG_PAD, -LOG_HDR_H)
    LScrollFrame:SetWidth(ns.CONTENT_W)
    LScrollFrame:EnableMouseWheel(true)

    LListFrame = CreateFrame("Frame", nil, LScrollFrame)
    LListFrame:SetWidth(ns.CONTENT_W); LListFrame:SetHeight(1)
    LScrollFrame:SetScrollChild(LListFrame)

    local OnWheel = ns.MakeWheelHandler(LScrollFrame, LListFrame, ROW_H)
    LScrollFrame:SetScript("OnMouseWheel", OnWheel)
    LListFrame:SetScript("OnMouseWheel", OnWheel)

    LogFrame.emptyLabel = LogFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    LogFrame.emptyLabel:SetPoint("TOP", LogFrame, "TOP", 0, -(LOG_HDR_H+14))
    LogFrame.emptyLabel:SetJustifyH("CENTER")
    LogFrame.emptyLabel:SetTextColor(0.55,0.55,0.55)
    LogFrame.emptyLabel:SetText(ns.L["log_empty"])
end

------------------------------------------------------------------------
-- Anchoring — below MainFrame when collapsed (or below the Gold Overview
-- window / Instance Lockout frame if those are also open there, to avoid
-- overlapping them), otherwise
-- part of the Log/Filter/Blacklist right-side chain (see
-- ns.RefreshWindowChain in Core.lua), which also re-flows Filter/
-- Blacklist if they're open.
------------------------------------------------------------------------
local function ReanchorLogFrame()
    if NightsFarmtrackerDB.expanded == false then
        LogFrame:ClearAllPoints()
        if ns.LockoutFrame and ns.LockoutFrame:IsShown() then
            LogFrame:SetPoint("TOPLEFT", ns.LockoutFrame, "BOTTOMLEFT", 0, -4)
        elseif ns.GoldFrame and ns.GoldFrame:IsShown() then
            LogFrame:SetPoint("TOPLEFT", ns.GoldFrame, "BOTTOMLEFT", 0, -4)
        else
            LogFrame:SetPoint("TOPLEFT", ns.MainFrame, "BOTTOMLEFT", 0, -4)
        end
    end
    ns.RefreshWindowChain("right")
end
ns.ReanchorLogFrame = ReanchorLogFrame

------------------------------------------------------------------------
-- Public API - window
------------------------------------------------------------------------
function ns.ToggleLogWindow()
    if NightsFarmtrackerDB.logWindowEnabled ~= true then return end
    if ns.DeferInCombat(ns.ToggleLogWindow) then return end
    EnsureLogFrame()
    if LogFrame:IsShown() then
        LogFrame:Hide()
        NightsFarmtrackerDB.logWindowShown = false
        ns.RefreshWindowChain("right")
    else
        RebuildLogList()
        LogFrame:Show()
        ReanchorLogFrame()
        NightsFarmtrackerDB.logWindowShown = true
    end
end

-- Called at PLAYER_LOGIN to restore the window across /reload and relogs,
-- mirroring how the main frame's own visibility is restored.
function ns.RestoreLogWindow()
    if NightsFarmtrackerDB.logWindowEnabled == true and NightsFarmtrackerDB.logWindowShown == true then
        EnsureLogFrame()
        RebuildLogList()
        LogFrame:Show()
        ReanchorLogFrame()
    end
end

-- Called from Settings when the feature is toggled off: hides the window
-- and clears the in-memory feed (kept disabled state = empty next time).
function ns.OnLogWindowDisabled()
    NightsFarmtrackerDB.logWindowShown = false
    if LogFrame then
        if not ns.DeferInCombat(function() LogFrame:Hide() end) then LogFrame:Hide() end
    end
end
