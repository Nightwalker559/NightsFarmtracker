------------------------------------------------------------------------
-- Night's Farmtracker - Settings
-- Custom settings window (no WoW Settings API dependency).
-- Price source: Auctionator / TSM4 / None + TSM price source selector.
------------------------------------------------------------------------
local _, ns = ...

local ART = "Interface\\AddOns\\NightsFarmtracker\\Artwork\\"
local SF   -- settings frame (lazy built)

local S_W   = 320
local S_PAD = 14

------------------------------------------------------------------------
-- Helper: radio button row
------------------------------------------------------------------------
local function MakeRadio(parent, label, yOff, value, getGroup, setGroup)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2, 22)
    row:SetPoint("TOPLEFT", S_PAD, yOff)

    -- Circle
    local dot = CreateFrame("Frame", nil, row, "BackdropTemplate")
    dot:SetSize(14, 14)
    dot:SetPoint("LEFT", 0, 0)
    dot:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    dot:SetBackdropColor(0.06,0.09,0.10,1)
    dot:SetBackdropBorderColor(unpack(ns.COL_BORDER))

    local fill = dot:CreateTexture(nil,"ARTWORK")
    fill:SetSize(6,6); fill:SetPoint("CENTER")
    fill:SetColorTexture(unpack(ns.COL_ACCENT)); fill:Hide()
    dot.fill = fill

    local lbl = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lbl:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    lbl:SetTextColor(0.85,0.85,0.85)
    lbl:SetText(label)
    row.label = lbl

    -- Disabled overlay
    local grayLbl = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    grayLbl:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
    grayLbl:SetTextColor(0.4,0.4,0.4)
    grayLbl:SetText(ns.L["not_installed"])
    grayLbl:Hide()
    row.notInstalled = grayLbl

    row.dot   = dot
    row.value = value

    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function()
        setGroup(value)
        ns.RebuildSettingsContent()
    end)

    function row:SetSelected(sel)
        if sel then
            fill:Show()
            lbl:SetTextColor(1, 0.82, 0)
        else
            fill:Hide()
            lbl:SetTextColor(0.85,0.85,0.85)
        end
    end

    function row:SetEnabled(en)
        row:EnableMouse(en)
        if not en then
            lbl:SetTextColor(0.4,0.4,0.4)
            dot:SetBackdropBorderColor(0.2,0.2,0.2,0.5)
            grayLbl:Show()
        else
            dot:SetBackdropBorderColor(unpack(ns.COL_BORDER))
            grayLbl:Hide()
        end
    end

    return row
end

------------------------------------------------------------------------
-- Helper: dropdown for TSM price source
------------------------------------------------------------------------
local function MakeDropdown(parent, yOff)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(180, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    frame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    frame:SetBackdropColor(0.05,0.08,0.09,1)
    frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))

    frame.lbl = frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    frame.lbl:SetPoint("LEFT",6,0)
    frame.lbl:SetTextColor(0.85,0.85,0.85)

    local arrow = frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    arrow:SetPoint("RIGHT",-6,0); arrow:SetText("▾")
    arrow:SetTextColor(unpack(ns.COL_ACCENT))

    local sources = ns.TSM_SOURCES
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        -- Simple cycle through options
        local cur = NightsFarmtrackerDB.tsmPriceSource or "DBMarket"
        local idx = 1
        for i,v in ipairs(sources) do if v==cur then idx=i; break end end
        idx = (idx % #sources) + 1
        NightsFarmtrackerDB.tsmPriceSource = sources[idx]
        frame.lbl:SetText(sources[idx])
    end)

    function frame:Refresh()
        self.lbl:SetText(NightsFarmtrackerDB.tsmPriceSource or "DBMarket")
    end

    return frame
end

------------------------------------------------------------------------
-- Helper: checkbox
------------------------------------------------------------------------
local function MakeCheckbox(parent, label, yOff, getValue, setValue)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2, 22)
    row:SetPoint("TOPLEFT", S_PAD, yOff)

    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetSize(14, 14); box:SetPoint("LEFT", 0, 0)
    box:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    box:SetBackdropColor(0.06,0.09,0.10,1)
    box:SetBackdropBorderColor(unpack(ns.COL_BORDER))

    local check = box:CreateTexture(nil,"ARTWORK")
    check:SetSize(7,7); check:SetPoint("CENTER")
    check:SetColorTexture(unpack(ns.COL_ACCENT))

    local lbl = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
    lbl:SetTextColor(0.85,0.85,0.85); lbl:SetText(label)

    local function Refresh()
        if getValue() then check:Show(); lbl:SetTextColor(1,0.82,0)
        else               check:Hide(); lbl:SetTextColor(0.85,0.85,0.85) end
    end
    Refresh()
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function() setValue(not getValue()); Refresh() end)
    return row
end

------------------------------------------------------------------------
-- Settings content (rebuilt on open / change)
------------------------------------------------------------------------
local settingsContent = {}
local tsmDropdown

function ns.RebuildSettingsContent()
    if not SF then return end
    for _, w in ipairs(settingsContent) do w:Hide() end
    settingsContent = {}

    local db  = NightsFarmtrackerDB
    local pad = S_PAD
    local y   = -40   -- start below header

    -- Section: AH Price Source
    local secLbl = SF:CreateFontString(nil,"OVERLAY","GameFontNormal")
    secLbl:SetPoint("TOPLEFT", pad, y)
    secLbl:SetTextColor(unpack(ns.COL_ACCENT))
    secLbl:SetText(ns.L["ah_source"])
    settingsContent[#settingsContent+1] = secLbl
    y = y - 22

    local ahOptions = {
        {label=ns.L["ah_auctionator"], value="auctionator", avail=ns.HasAuctionator()},
        {label=ns.L["ah_tsm"], value="tsm",          avail=ns.HasTSM()},
        {label=ns.L["ah_none"],     value="none",         avail=true},
    }

    -- Also add auto if at least one is available
    if ns.HasAuctionator() or ns.HasTSM() then
        table.insert(ahOptions, 1, {label=ns.L["ah_auto"], value="auto", avail=true})
    end

    local function getAH()  return db.ahSource or "auto" end
    local function setAH(v) db.ahSource = v end

    for _, opt in ipairs(ahOptions) do
        local row = MakeRadio(SF, opt.label, y, opt.value, getAH, setAH)
        row:SetSelected(getAH() == opt.value)
        row:SetEnabled(opt.avail)
        settingsContent[#settingsContent+1] = row
        y = y - 24
    end

    y = y - 8
    -- Section: TSM Price Source (only if TSM available)
    if ns.HasTSM() then
        local tsmLbl = SF:CreateFontString(nil,"OVERLAY","GameFontNormal")
        tsmLbl:SetPoint("TOPLEFT", pad, y)
        tsmLbl:SetTextColor(unpack(ns.COL_ACCENT))
        tsmLbl:SetText(ns.L["tsm_source"])
        settingsContent[#settingsContent+1] = tsmLbl
        y = y - 26

        local hint = SF:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", pad, y)
        hint:SetTextColor(0.5,0.5,0.5)
        hint:SetText(ns.L["tsm_hint"])
        hint:SetWidth(S_W - pad*2)
        hint:SetJustifyH("LEFT")
        settingsContent[#settingsContent+1] = hint
        y = y - 28

        if not tsmDropdown then
            tsmDropdown = MakeDropdown(SF, y)
        else
            tsmDropdown:SetPoint("TOPLEFT", S_PAD, y)
            tsmDropdown:Show()
        end
        tsmDropdown:Refresh()
        settingsContent[#settingsContent+1] = tsmDropdown
        y = y - 32
    end

    y = y - 8
    -- Section: Display
    local dispLbl = SF:CreateFontString(nil,"OVERLAY","GameFontNormal")
    dispLbl:SetPoint("TOPLEFT", pad, y)
    dispLbl:SetTextColor(unpack(ns.COL_ACCENT))
    dispLbl:SetText(ns.L["display"])
    settingsContent[#settingsContent+1] = dispLbl
    y = y - 26

    -- Gold rate toggle
    local function getRateMode() return db.goldRateMode=="min" and "min" or "hour" end
    local rateRow1 = MakeRadio(SF,ns.L["gold_per_hour"], y, "hour", getRateMode,
        function(v) db.goldRateMode=v; ns.UpdateGoldRate() end)
    rateRow1:SetSelected(getRateMode()=="hour"); rateRow1:SetEnabled(true)
    settingsContent[#settingsContent+1] = rateRow1
    y = y - 24

    local rateRow2 = MakeRadio(SF,ns.L["gold_per_min"], y, "min", getRateMode,
        function(v) db.goldRateMode=v; ns.UpdateGoldRate() end)
    rateRow2:SetSelected(getRateMode()=="min"); rateRow2:SetEnabled(true)
    settingsContent[#settingsContent+1] = rateRow2
    y = y - 24

    -- Minimap button toggle
    local mmRow = MakeCheckbox(SF, ns.L["minimap_button"], y,
        function() return not db.minimapHidden end,
        function(v)
            db.minimapHidden = not v
            ns.SetMinimapVisible(v)
        end)
    settingsContent[#settingsContent+1] = mmRow
    y = y - 26

    -- Resize frame to content
    SF:SetHeight(math.abs(y) + 30)

    -- Show all
    for _, w in ipairs(settingsContent) do w:Show() end
end

------------------------------------------------------------------------
-- Build settings frame (lazy)
------------------------------------------------------------------------
local function EnsureSettingsFrame()
    if SF then return end

    SF = CreateFrame("Frame","NightsFarmtrackerSettingsWnd",UIParent,"BackdropTemplate")
    SF:SetWidth(S_W)
    SF:SetHeight(280)
    SF:SetPoint("CENTER",UIParent,"CENTER",180,0)
    SF:SetFrameStrata("HIGH")
    SF:SetClampedToScreen(true)
    SF:SetMovable(true); SF:EnableMouse(true)
    SF:RegisterForDrag("LeftButton")
    SF:SetScript("OnDragStart",function(s)s:StartMoving()end)
    SF:SetScript("OnDragStop", function(s)s:StopMovingOrSizing()end)
    ns.ApplyFrameStyle(SF)
    table.insert(UISpecialFrames,"NightsFarmtrackerSettingsWnd")
    SF:Hide()

    local title = SF:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    title:SetPoint("TOPLEFT",S_PAD,-12)
    title:SetText(ns.L["settings_title"])
    title:SetTextColor(unpack(ns.COL_ACCENT))

    local sep = SF:CreateTexture(nil,"ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(unpack(ns.COL_BORDER))
    sep:SetPoint("TOPLEFT",S_PAD,-30); sep:SetPoint("TOPRIGHT",-S_PAD,-30)

    -- Close button (custom TGA)
    local xBtn = CreateFrame("Button",nil,SF)
    xBtn:SetSize(16,16); xBtn:SetPoint("TOPRIGHT",-S_PAD,-10)
    local xTex = xBtn:CreateTexture(nil,"ARTWORK")
    xTex:SetAllPoints(); xTex:SetTexture(ART.."btn_close.tga")
    xTex:SetAlpha(0.7)
    xBtn:SetScript("OnClick", function() SF:Hide() end)
    xBtn:SetScript("OnEnter",function()xTex:SetAlpha(1)end)
    xBtn:SetScript("OnLeave",function()xTex:SetAlpha(0.7)end)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleSettings()
    EnsureSettingsFrame()
    if SF:IsShown() then
        SF:Hide()
    else
        ns.RebuildSettingsContent()
        SF:Show()
    end
end

-- Legacy: called from Main for ADDON_LOADED compatibility
function ns.InitSettings()
    -- nothing to register — our settings are self-contained
end
