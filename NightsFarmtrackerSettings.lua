------------------------------------------------------------------------
-- Night's Farmtracker - Settings
-- Custom settings window (no WoW Settings API dependency).
-- Price source: Auctionator / TSM4 / None + TSM price source selector.
------------------------------------------------------------------------
local _, ns = ...

local ART = "Interface\\AddOns\\NightsFarmtracker\\Media\\"

StaticPopupDialogs["NFT_MINIMAP_RELOAD"] = {
    text        = ns.L and ns.L["reload_required"] or "Reload required.",
    button1     = OKAY,
    button2     = CANCEL,
    OnAccept    = function() ReloadUI() end,
    timeout     = 0,
    whileDead   = true,
    hideOnEscape = true,
}
local SF           -- settings frame (lazy built)
local SScrollFrame -- scroll container for content
local SListFrame   -- scroll child (all widgets live here)

local S_W          = 320
local S_PAD        = 14
local S_HDR_H      = 34    -- header (title + sep)
local S_MAX_VIS    = 380   -- max visible scroll area height
local S_SCROLL_STEP = 22

------------------------------------------------------------------------
-- Helper: radio button row
------------------------------------------------------------------------
local function MakeRadio(parent, label, yOff, value, getGroup, setGroup)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2, 22)
    row:SetPoint("TOPLEFT", S_PAD, yOff)

    local dot = CreateFrame("Frame", nil, row, "BackdropTemplate")
    dot:SetSize(14, 14)
    dot:SetPoint("LEFT", 0, 0)
    dot:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    dot:SetBackdropColor(0.06,0.09,0.10,1)
    dot:SetBackdropBorderColor(unpack(ns.COL_BORDER))

    local fill = dot:CreateTexture(nil,"ARTWORK")
    fill:SetSize(7,7); fill:SetPoint("CENTER")
    fill:SetColorTexture(unpack(ns.COL_ACCENT)); fill:Hide()
    dot.fill = fill

    local lbl = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lbl:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    lbl:SetTextColor(0.85,0.85,0.85)
    lbl:SetText(label)
    row.label = lbl

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
local tsmDropdown
local tsmCustomEB

local function MakeDropdown(parent, yOff)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(S_W - S_PAD*2 - 40, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    frame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    frame:SetBackdropColor(0.05,0.08,0.09,1)
    frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))

    frame.lbl = frame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    frame.lbl:SetPoint("LEFT",6,0)
    frame.lbl:SetTextColor(0.85,0.85,0.85)

    local arrow = frame:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(10, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(unpack(ns.COL_ACCENT))

    local sources = ns.TSM_SOURCES
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        local cur = NightsFarmtrackerDB.tsmPriceSource or "DBMarket"
        local idx = 1
        for i,v in ipairs(sources) do if v==cur then idx=i; break end end
        idx = (idx % #sources) + 1
        NightsFarmtrackerDB.tsmPriceSource = sources[idx]
        frame.lbl:SetText(sources[idx])
    end)

    function frame:Refresh()
        local db     = NightsFarmtrackerDB
        local custom = db.tsmCustomSource and db.tsmCustomSource ~= ""
        self.lbl:SetText(db.tsmPriceSource or "DBMarket")
        self.lbl:SetTextColor(custom and 0.40 or 0.85, custom and 0.40 or 0.85, custom and 0.40 or 0.85)
    end

    return frame
end

------------------------------------------------------------------------
-- Helper: EditBox for custom TSM price source
------------------------------------------------------------------------
local function MakeCustomSourceEB(parent, yOff)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(S_W - S_PAD*2 - 40, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    frame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    frame:SetBackdropColor(0.05,0.08,0.09,1)
    frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))

    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetSize(S_W - S_PAD*2 - 56, 18)
    eb:SetPoint("LEFT", 6, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(64)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetTextColor(0.85, 0.85, 0.85)
    eb:SetScript("OnTextChanged", function(self)
        NightsFarmtrackerDB.tsmCustomSource = self:GetText()
        if tsmDropdown then tsmDropdown:Refresh() end
    end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_ACCENT))
    end)
    eb:SetScript("OnEditFocusLost", function()
        frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))
    end)
    frame.eb = eb
    return frame
end

------------------------------------------------------------------------
-- Helper: checkbox
------------------------------------------------------------------------
local function MakeCheckbox(parent, label, yOff, getValue, setValue)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2, 36)
    row:SetPoint("TOPLEFT", S_PAD, yOff)

    local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    box:SetSize(14, 14); box:SetPoint("TOPLEFT", 0, -4)
    box:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    box:SetBackdropColor(0.06,0.09,0.10,1)
    box:SetBackdropBorderColor(unpack(ns.COL_BORDER))

    local check = box:CreateTexture(nil,"ARTWORK")
    check:SetSize(7,7); check:SetPoint("CENTER")
    check:SetColorTexture(unpack(ns.COL_ACCENT))

    local lbl = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 0)
    lbl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
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
-- All widgets are parented to SListFrame (the scroll child).
------------------------------------------------------------------------
local settingsContent = {}

function ns.RebuildSettingsContent()
    if not SListFrame then return end
    for _, w in ipairs(settingsContent) do w:Hide() end
    settingsContent = {}

    local db  = NightsFarmtrackerDB
    local y   = -8   -- start with small top padding within scroll area

    -- ----------------------------------------------------------------
    -- Section: AH Price Source
    -- ----------------------------------------------------------------
    local secLbl = SListFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    secLbl:SetPoint("TOPLEFT", S_PAD, y)
    secLbl:SetTextColor(unpack(ns.COL_ACCENT))
    secLbl:SetText(ns.L["ah_source"])
    settingsContent[#settingsContent+1] = secLbl
    y = y - 22

    local ahOptions = {
        {label=ns.L["ah_auctionator"], value="auctionator", avail=ns.HasAuctionator()},
        {label=ns.L["ah_tsm"],         value="tsm",         avail=ns.HasTSM()},
        {label=ns.L["ah_none"],        value="none",        avail=true},
    }
    if ns.HasAuctionator() or ns.HasTSM() then
        table.insert(ahOptions, 1, {label=ns.L["ah_auto"], value="auto", avail=true})
    end

    local function getAH()  return db.ahSource or "auto" end
    local function setAH(v) db.ahSource = v end

    for _, opt in ipairs(ahOptions) do
        local row = MakeRadio(SListFrame, opt.label, y, opt.value, getAH, setAH)
        row:SetSelected(getAH() == opt.value)
        row:SetEnabled(opt.avail)
        settingsContent[#settingsContent+1] = row
        y = y - 24
        if opt.value == "auto" and ns.HasAuctionator() and ns.HasTSM() then
            local infoLbl = SListFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            infoLbl:SetPoint("TOPLEFT", S_PAD + 22, y)
            infoLbl:SetTextColor(0.38, 0.38, 0.38)
            infoLbl:SetText(ns.L["ah_auto_info"])
            settingsContent[#settingsContent+1] = infoLbl
            y = y - 16
        end
    end

    -- ----------------------------------------------------------------
    -- Section: TSM Price Source (only if TSM available)
    -- ----------------------------------------------------------------
    if ns.HasTSM() then
        y = y - 8
        local tsmLbl = SListFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
        tsmLbl:SetPoint("TOPLEFT", S_PAD, y)
        tsmLbl:SetTextColor(unpack(ns.COL_ACCENT))
        tsmLbl:SetText(ns.L["tsm_source"])
        settingsContent[#settingsContent+1] = tsmLbl
        y = y - 26

        local hint = SListFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", S_PAD, y)
        hint:SetTextColor(0.5,0.5,0.5)
        hint:SetText(ns.L["tsm_hint"])
        hint:SetWidth(S_W - S_PAD*2)
        hint:SetJustifyH("LEFT")
        settingsContent[#settingsContent+1] = hint
        y = y - 28

        if not tsmDropdown then
            tsmDropdown = MakeDropdown(SListFrame, y)
        else
            tsmDropdown:SetPoint("TOPLEFT", S_PAD, y)
            tsmDropdown:Show()
        end
        tsmDropdown:Refresh()
        settingsContent[#settingsContent+1] = tsmDropdown
        y = y - 32

        local customLbl = SListFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        customLbl:SetPoint("TOPLEFT", S_PAD, y)
        customLbl:SetTextColor(0.50, 0.50, 0.50)
        customLbl:SetText(ns.L["tsm_custom"])
        settingsContent[#settingsContent+1] = customLbl
        y = y - 18

        if not tsmCustomEB then
            tsmCustomEB = MakeCustomSourceEB(SListFrame, y)
        else
            tsmCustomEB:SetPoint("TOPLEFT", S_PAD, y)
            tsmCustomEB:Show()
        end
        tsmCustomEB.eb:SetText(db.tsmCustomSource or "")
        settingsContent[#settingsContent+1] = tsmCustomEB
        y = y - 32
    end

    -- ----------------------------------------------------------------
    -- Section: Display
    -- ----------------------------------------------------------------
    y = y - 8
    local dispLbl = SListFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    dispLbl:SetPoint("TOPLEFT", S_PAD, y)
    dispLbl:SetTextColor(unpack(ns.COL_ACCENT))
    dispLbl:SetText(ns.L["display"])
    settingsContent[#settingsContent+1] = dispLbl
    y = y - 26

    local function getRateMode() return db.goldRateMode=="min" and "min" or "hour" end
    local rateRow1 = MakeRadio(SListFrame, ns.L["gold_per_hour"], y, "hour", getRateMode,
        function(v) db.goldRateMode=v; ns.UpdateGoldRate() end)
    rateRow1:SetSelected(getRateMode()=="hour"); rateRow1:SetEnabled(true)
    settingsContent[#settingsContent+1] = rateRow1
    y = y - 24

    local rateRow2 = MakeRadio(SListFrame, ns.L["gold_per_min"], y, "min", getRateMode,
        function(v) db.goldRateMode=v; ns.UpdateGoldRate() end)
    rateRow2:SetSelected(getRateMode()=="min"); rateRow2:SetEnabled(true)
    settingsContent[#settingsContent+1] = rateRow2
    y = y - 24

    local function getGoldDisplay() return db.goldDisplayMode=="modern" and "modern" or "classic" end
    local function setGoldDisplay(v) db.goldDisplayMode=v; ns.RefreshHUD() end

    local gdRow1 = MakeRadio(SListFrame, ns.L["gold_display_classic"], y, "classic", getGoldDisplay, setGoldDisplay)
    gdRow1:SetSelected(getGoldDisplay()=="classic"); gdRow1:SetEnabled(true)
    settingsContent[#settingsContent+1] = gdRow1
    y = y - 24

    local gdRow2 = MakeRadio(SListFrame, ns.L["gold_display_modern"], y, "modern", getGoldDisplay, setGoldDisplay)
    gdRow2:SetSelected(getGoldDisplay()=="modern"); gdRow2:SetEnabled(true)
    settingsContent[#settingsContent+1] = gdRow2
    y = y - 24

    local mmRow = MakeCheckbox(SListFrame, ns.L["minimap_button"], y,
        function() return not db.minimapHidden end,
        function(v)
            db.minimapHidden = not v
            db.minimap.hide  = not v
            if v then
                StaticPopup_Show("NFT_MINIMAP_RELOAD")
            else
                ns.SetMinimapVisible(false)
            end
        end)
    settingsContent[#settingsContent+1] = mmRow
    y = y - 38

    -- ----------------------------------------------------------------
    -- Section: Tracking
    -- ----------------------------------------------------------------
    y = y - 8
    local trackLbl = SListFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    trackLbl:SetPoint("TOPLEFT", S_PAD, y)
    trackLbl:SetTextColor(unpack(ns.COL_ACCENT))
    trackLbl:SetText(ns.L["tracking"])
    settingsContent[#settingsContent+1] = trackLbl
    y = y - 26

    local histRow = MakeCheckbox(SListFrame, ns.L["session_history_enabled"], y,
        function() return db.sessionHistoryEnabled ~= false end,
        function(v)
            db.sessionHistoryEnabled = v
            ns.UpdateHistoryBtn()
        end)
    settingsContent[#settingsContent+1] = histRow
    y = y - 38

    local splitRow = MakeCheckbox(SListFrame, ns.L["split_trade_goods"], y,
        function() return db.splitTradeGoods == true end,
        function(v)
            db.splitTradeGoods = v
            ns.RefreshHUD()
        end)
    settingsContent[#settingsContent+1] = splitRow
    y = y - 38

    local mergeRow = MakeCheckbox(SListFrame, ns.L["merge_daily_sessions"], y,
        function() return db.mergeDaily ~= false end,
        function(v)
            db.mergeDaily = v
        end)
    settingsContent[#settingsContent+1] = mergeRow
    y = y - 38

    local filterRow = MakeCheckbox(SListFrame, ns.L["vendor_filter_enabled"], y,
        function() return db.vendorFilterEnabled ~= false end,
        function(v)
            db.vendorFilterEnabled = v
            ns.UpdateFilterBtn()
            ns.RefreshHUD()
        end)
    settingsContent[#settingsContent+1] = filterRow
    y = y - 38

    local logRow = MakeCheckbox(SListFrame, ns.L["log_window_enabled"], y,
        function() return db.logWindowEnabled == true end,
        function(v)
            db.logWindowEnabled = v
            if not v then ns.OnLogWindowDisabled() end
            ns.UpdateLogBtn()
        end)
    settingsContent[#settingsContent+1] = logRow
    y = y - 38

    -- ----------------------------------------------------------------
    -- Resize scroll area and outer frame
    -- ----------------------------------------------------------------
    local contentH = math.abs(y) + 8
    SListFrame:SetHeight(contentH)
    SScrollFrame:SetVerticalScroll(0)
    local visH = math.min(contentH, S_MAX_VIS)
    SScrollFrame:SetHeight(visH)
    SF:SetHeight(S_HDR_H + visH + 10)

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

    -- Close button
    local xBtn = CreateFrame("Button",nil,SF)
    xBtn:SetSize(18,18); xBtn:SetPoint("TOPRIGHT",-S_PAD,-10)
    local xTex = xBtn:CreateTexture(nil,"ARTWORK")
    xTex:SetAllPoints(); xTex:SetTexture(ART.."btn_close.png")
    xTex:SetAlpha(0.7)
    xBtn:SetScript("OnClick", function() SF:Hide() end)
    xBtn:SetScript("OnEnter",function()xTex:SetAlpha(1)end)
    xBtn:SetScript("OnLeave",function()xTex:SetAlpha(0.7)end)

    -- Scroll container — spans full width, below header sep
    SScrollFrame = CreateFrame("ScrollFrame", nil, SF)
    SScrollFrame:SetPoint("TOPLEFT",  0, -S_HDR_H)
    SScrollFrame:SetPoint("TOPRIGHT", 0, -S_HDR_H)
    SScrollFrame:EnableMouseWheel(true)

    SListFrame = CreateFrame("Frame", nil, SScrollFrame)
    SListFrame:SetWidth(S_W)
    SListFrame:SetHeight(1)
    SScrollFrame:SetScrollChild(SListFrame)

    local function OnWheel(_, delta)
        local cur  = SScrollFrame:GetVerticalScroll()
        local maxS = math.max(0, SListFrame:GetHeight() - SScrollFrame:GetHeight())
        SScrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta * S_SCROLL_STEP, maxS)))
    end
    SScrollFrame:SetScript("OnMouseWheel", OnWheel)
    SListFrame:EnableMouseWheel(true)
    SListFrame:SetScript("OnMouseWheel", OnWheel)
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

function ns.InitSettings()
    -- nothing to register — our settings are self-contained
end