------------------------------------------------------------------------
-- Night's Farmtracker - Loot Log
-- Optional feed window: one line per loot event (icon, name, amount).
-- Survives /reload and relogs (SavedVariablesPerCharacter); only cleared
-- when the session itself is reset.
------------------------------------------------------------------------
local _, ns = ...
local ART = "Interface\\AddOns\\NightsFarmtracker\\Media\\"

local LOG_W       = ns.FRAME_W
local LOG_PAD     = ns.PAD
local LOG_HDR_H   = ns.HDR_TOTAL
local ROW_H       = ns.ROW_H
local MAX_VIS_H   = 8 * ROW_H
local MIN_VIS_H   = 30
local MAX_ENTRIES = 100  -- in-memory cap, oldest entries drop off

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

    r.timeText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.timeText:SetPoint("LEFT", 4, 0)
    r.timeText:SetWidth(38)
    r.timeText:SetJustifyH("LEFT"); r.timeText:SetFontHeight(11)
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

    r.nameText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",  r.rankBadge, "RIGHT", 4, 0)
    r.nameText:SetPoint("RIGHT", r,           "RIGHT", -40, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(11)
    r.nameText:SetTextColor(0.85,0.85,0.85)

    r.countText = r:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    r.countText:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.countText:SetJustifyH("RIGHT"); r.countText:SetFontHeight(11)
    r.countText:SetTextColor(unpack(ns.COL_GOLD))

    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
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

    local yOff = 0
    for _, e in ipairs(NightsFarmtrackerDB.logEntries or {}) do
        local r = AcquireRow()
        r:SetPoint("TOPLEFT", 0, -yOff)
        r.sep:SetShown(yOff > 0)
        r.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
        r.timeText:SetText(date("%H:%M", e.timestamp or time()))
        r.nameText:SetText(ns.TruncateName(e.name))
        r.rankBadge:SetText(e.rankIcon or "")
        r.countText:SetText("x" .. e.amount)
        r.itemLink = e.itemLink
        ns.ApplyQualityColor(r.nameText, r.iconBorder, e.quality, {0.85, 0.85, 0.85})
        activeRows[#activeRows+1] = r
        yOff = yOff + ROW_H
    end

    local contentH = math.max(1, yOff)
    LListFrame:SetHeight(contentH)
    local visH = math.max(MIN_VIS_H, math.min(contentH, MAX_VIS_H))
    LScrollFrame:SetHeight(visH)
    LogFrame:SetHeight(LOG_HDR_H + visH + 10)

    LogFrame.emptyLabel:SetShown(#(NightsFarmtrackerDB.logEntries or {}) == 0)
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

------------------------------------------------------------------------
-- Build window (lazy)
------------------------------------------------------------------------
local function EnsureLogFrame()
    if LogFrame then return end

    LogFrame = CreateFrame("Frame","NightsFarmtrackerLogWnd",UIParent,"BackdropTemplate")
    LogFrame:SetWidth(LOG_W)
    LogFrame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 4, 0)
    LogFrame:SetFrameStrata("HIGH"); LogFrame:SetClampedToScreen(true)
    LogFrame:SetMovable(true); LogFrame:EnableMouse(true)
    LogFrame:RegisterForDrag("LeftButton")
    LogFrame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    LogFrame:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    ns.ApplyFrameStyle(LogFrame)
    LogFrame:Hide()
    ns.LogFrame = LogFrame  -- exposed so other windows (e.g. Filter) can anchor next to it

    local titleFS = LogFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    titleFS:SetPoint("TOPLEFT", LOG_PAD, -10)
    titleFS:SetText(ns.L["log_title"])
    titleFS:SetTextColor(unpack(ns.COL_GOLD))

    local hSep = LogFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT", LOG_PAD, -(LOG_HDR_H-1)); hSep:SetPoint("TOPRIGHT", -LOG_PAD, -(LOG_HDR_H-1))

    local xBtn = CreateFrame("Button", nil, LogFrame); xBtn:SetSize(18,18); xBtn:SetPoint("TOPRIGHT",-LOG_PAD,-10)
    local xTex = xBtn:CreateTexture(nil,"ARTWORK"); xTex:SetAllPoints()
    xTex:SetTexture(ART.."btn_close.png"); xTex:SetAlpha(0.8)
    xBtn:SetScript("OnClick", function()
        LogFrame:Hide()
        NightsFarmtrackerDB.logWindowShown = false
    end)
    xBtn:SetScript("OnEnter", function() xTex:SetAlpha(1) end)
    xBtn:SetScript("OnLeave", function() xTex:SetAlpha(0.8) end)

    LScrollFrame = CreateFrame("ScrollFrame", nil, LogFrame)
    LScrollFrame:SetPoint("TOPLEFT", LOG_PAD, -LOG_HDR_H)
    LScrollFrame:SetWidth(ns.CONTENT_W)
    LScrollFrame:EnableMouseWheel(true)

    LListFrame = CreateFrame("Frame", nil, LScrollFrame)
    LListFrame:SetWidth(ns.CONTENT_W); LListFrame:SetHeight(1)
    LScrollFrame:SetScrollChild(LListFrame)

    local function OnWheel(_, delta)
        local cur  = LScrollFrame:GetVerticalScroll()
        local maxS = math.max(0, LListFrame:GetHeight() - LScrollFrame:GetHeight())
        LScrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta*ROW_H, maxS)))
    end
    LScrollFrame:SetScript("OnMouseWheel", OnWheel)
    LListFrame:SetScript("OnMouseWheel", OnWheel)

    LogFrame.emptyLabel = LogFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    LogFrame.emptyLabel:SetPoint("TOP", LogFrame, "TOP", 0, -(LOG_HDR_H+14))
    LogFrame.emptyLabel:SetJustifyH("CENTER")
    LogFrame.emptyLabel:SetTextColor(0.55,0.55,0.55)
    LogFrame.emptyLabel:SetText(ns.L["log_empty"])
end

------------------------------------------------------------------------
-- Anchoring — below MainFrame when collapsed, otherwise right side of
-- MainFrame (or right of Vendor-Only Filter window if that's open, to
-- avoid overlapping it).
------------------------------------------------------------------------
local function ReanchorLogFrame()
    LogFrame:ClearAllPoints()
    if NightsFarmtrackerDB.expanded == false then
        LogFrame:SetPoint("TOPLEFT", ns.MainFrame, "BOTTOMLEFT", 0, -4)
    elseif ns.FilterFrame and ns.FilterFrame:IsShown() then
        LogFrame:SetPoint("TOPLEFT", ns.FilterFrame, "TOPRIGHT", 4, 0)
    else
        LogFrame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 4, 0)
    end
end
ns.ReanchorLogFrame = ReanchorLogFrame

------------------------------------------------------------------------
-- Public API - window
------------------------------------------------------------------------
function ns.ToggleLogWindow()
    if NightsFarmtrackerDB.logWindowEnabled ~= true then return end
    EnsureLogFrame()
    if LogFrame:IsShown() then
        LogFrame:Hide()
        NightsFarmtrackerDB.logWindowShown = false
    else
        ReanchorLogFrame()
        RebuildLogList()
        LogFrame:Show()
        NightsFarmtrackerDB.logWindowShown = true
    end
end

-- Called at PLAYER_LOGIN to restore the window across /reload and relogs,
-- mirroring how the main frame's own visibility is restored.
function ns.RestoreLogWindow()
    if NightsFarmtrackerDB.logWindowEnabled == true and NightsFarmtrackerDB.logWindowShown == true then
        EnsureLogFrame()
        ReanchorLogFrame()
        RebuildLogList()
        LogFrame:Show()
    end
end

-- Called from Settings when the feature is toggled off: hides the window
-- and clears the in-memory feed (kept disabled state = empty next time).
function ns.OnLogWindowDisabled()
    NightsFarmtrackerDB.logWindowShown = false
    if LogFrame then LogFrame:Hide() end
end
