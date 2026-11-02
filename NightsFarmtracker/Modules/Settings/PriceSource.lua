------------------------------------------------------------------------
-- Night's Farmtracker - Settings: AH price source
-- AH source radio group, Gear AH threshold (with its per-group popup) and the
-- TSM price source widgets.
------------------------------------------------------------------------
local _, ns = ...
local K = ns.SettingsKit

local CHECK_RUN_TAIL, TITLE_STEP_CTRL, CTRL_SIZE, CTRL_GAP = K.CHECK_RUN_TAIL, K.TITLE_STEP_CTRL, K.CTRL_SIZE, K.CTRL_GAP
local S_W, S_PAD, S_HDR_H = K.S_W, K.S_PAD, K.S_HDR_H
local MakeDropdownBox, MakeNumberBox = K.MakeDropdownBox, K.MakeNumberBox
local checkboxPool, ConfigureCheckbox = K.checkboxPool, K.ConfigureCheckbox

local tsmDropdown, tsmCustomEB, gearThresholdEB

local function MakeTsmDropdown(parent, yOff)
    local frame = MakeDropdownBox(parent, S_W - S_PAD*2 - 40)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)

    local sources = ns.TSM_SOURCES
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        local cur = NightsFarmtrackerDB.tsmPriceSource or "DBMarket"
        local idx = 1
        for i,v in ipairs(sources) do if v==cur then idx=i; break end end
        idx = (idx % #sources) + 1
        NightsFarmtrackerDB.tsmPriceSource = sources[idx]
        frame.lbl:SetText(sources[idx])
        ns.ClearPriceCache()
        ns.RefreshHUD()
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
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetSize(S_W - S_PAD*2 - 56, 18)
    eb:SetPoint("LEFT", 6, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(64)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetTextColor(0.85, 0.85, 0.85)
    -- userInput is false when RebuildSettingsContent fills the box with
    -- SetText; only react to what the player actually typed (otherwise every
    -- click in Settings would wipe the price cache).
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        NightsFarmtrackerDB.tsmCustomSource = self:GetText()
        if tsmDropdown then tsmDropdown:Refresh() end
        ns.ClearPriceCache()
        ns.RefreshHUD()
    end)
    ns.HookEditBoxFocus(frame, eb)
    frame.eb = eb
    return frame
end

------------------------------------------------------------------------
-- Gear AH threshold window: one checkbox per Equipment group
-- (ns.GEAR_THRESHOLD_GROUPS); checked = the threshold applies to it. The gear
-- icon next to the threshold field opens it. It joins the left docking chain
-- behind Settings and the Sell List options, so it never covers Settings.
------------------------------------------------------------------------
local gearCfgPop
local gearCfgRows = {}

local function BuildGearThresholdConfig()
    checkboxPool.releaseAll(gearCfgRows)
    local y = -(S_HDR_H + 6)
    for _, g in ipairs(ns.GEAR_THRESHOLD_GROUPS) do
        local row = checkboxPool.acquire(gearCfgPop)
        gearCfgRows[#gearCfgRows + 1] = row
        ConfigureCheckbox(row, ns.L[g.locKey], y,
            function() return ns.IsGearThresholdGroupEnabled(g.key) end,
            function(v) ns.SetGearThresholdGroupEnabled(g.key, v); ns.RefreshHUD() end)
        y = y - math.max(CTRL_SIZE, math.ceil(row.label:GetStringHeight())) - CTRL_GAP
    end
    gearCfgPop:SetHeight(-y + 4)
end

function ns.ToggleGearThresholdConfig()
    if gearCfgPop and gearCfgPop:IsShown() then gearCfgPop:Hide(); return end

    if not gearCfgPop then
        gearCfgPop = ns.CreateWindowFrame("NightsFarmtrackerGearThresholdWnd", ns.L["gear_ah_threshold_config_title"],
            { width = S_W, pad = S_PAD, dockChain = "left", noEsc = true })
        ns.GearThresholdFrame = gearCfgPop
        K.RegisterPopup(gearCfgPop)   -- closes with Settings and on every rebuild of its content
        ns.AddHLine(gearCfgPop, "TOP", S_PAD, -(S_HDR_H - 1))
    end

    BuildGearThresholdConfig()
    gearCfgPop:Show()
    ns.RefreshWindowChain("left")
end

------------------------------------------------------------------------
-- Helper: gear AH threshold (gold) plus the config icon that opens the
-- per-group window (see ns.ToggleGearThresholdConfig)
------------------------------------------------------------------------
local function MakeGearThresholdEB(parent, yOff)
    local frame, eb = MakeNumberBox(parent, yOff, 7, ns.L["gold_suffix"])
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local gold = tonumber(self:GetText()) or 0
        NightsFarmtrackerDB.gearAHThreshold = gold * 10000
        ns.RefreshHUD()
    end)

    -- Config icon: opens a small window to pick which Equipment categories
    -- the threshold applies to (see ns.GEAR_THRESHOLD_GROUPS).
    local cfgBtn = ns.CreateConfigButton(parent, ns.L["gear_ah_threshold_config_title"], ns.L["gear_ah_threshold_config_tip"])
    cfgBtn:SetPoint("LEFT", frame.unitLbl, "RIGHT", 8, 0)
    cfgBtn:SetScript("OnClick", function() ns.ToggleGearThresholdConfig() end)

    local helpBtn = ns.CreateHelpButton(parent, "gearah")
    helpBtn:SetPoint("LEFT", cfgBtn, "RIGHT", 6, 0)

    -- Same sync as the unit label (see MakeNumberBox)
    local baseShow, baseHide = frame.Show, frame.Hide
    frame.Show = function(self) baseShow(self); cfgBtn:Show(); helpBtn:Show() end
    frame.Hide = function(self) baseHide(self); cfgBtn:Hide(); helpBtn:Hide() end
    return frame
end

------------------------------------------------------------------------
-- Section: AH Price Source (includes the Gear AH Threshold sub-block,
-- which has no header of its own and always follows this section)
------------------------------------------------------------------------
K.AddSection("ah_source", function(y, ui)
    local track, sectionTitle, wrappedHint, hintLabel, radio, flag, place, db =
        ui.track, ui.sectionTitle, ui.wrappedHint, ui.hintLabel, ui.radio, ui.flag, ui.place, ui.db
    y = sectionTitle(y, "ah_source", TITLE_STEP_CTRL)

    local ahOptions = {
        {label=ns.L["ah_auctionator"], value="auctionator", avail=ns.HasAuctionator()},
        {label=ns.L["ah_oribos"],      value="oribos",      avail=ns.HasOribos()},
        {label=ns.L["ah_tsm"],         value="tsm",         avail=ns.HasTSM()},
        {label=ns.L["ah_none"],        value="none",        avail=true},
    }
    local availableCount = (ns.HasAuctionator() and 1 or 0) + (ns.HasOribos() and 1 or 0) + (ns.HasTSM() and 1 or 0)
    if availableCount > 0 then
        table.insert(ahOptions, 1, {label=ns.L["ah_auto"], value="auto", avail=true})
    end

    local function getAH()  return db.ahSource or "auto" end
    local function setAH(v) db.ahSource = v; ns.ClearPriceCache(); ns.RefreshHUD() end

    for _, opt in ipairs(ahOptions) do
        local row = radio(y, opt.label, opt.value, setAH)
        row:SetSelected(getAH() == opt.value)
        row:SetEnabled(opt.avail)
        y = y - CTRL_SIZE - CTRL_GAP
        if opt.value == "auto" and availableCount > 1 then
            hintLabel(S_PAD + 22, y, ns.L["ah_auto_info"], 0.38)
            y = y - 16
        end
    end

    -- Gear AH Threshold: below this price Equipment skips the AH lookup
    -- and uses its vendor price (0 = off).
    y = y - 8
    local threshHint = wrappedHint(y, ns.L["gear_ah_threshold_hint"])
    y = y - math.max(28, math.ceil(threshHint:GetStringHeight()) + 6)

    gearThresholdEB = place(gearThresholdEB, MakeGearThresholdEB, y)
    local threshGold = math.floor((db.gearAHThreshold or 0) / 10000)
    gearThresholdEB.eb:SetText(threshGold > 0 and tostring(threshGold) or "")
    track(gearThresholdEB, "other")
    y = y - 32

    y = flag(y, "gear_ah_threshold_sound", "gearAHThresholdSound", false)

    -- TSM source block, only if TSM is installed.
    if ns.HasTSM() then
        y = y - CHECK_RUN_TAIL - 4
        wrappedHint(y, ns.L["tsm_hint"])
        y = y - 28

        tsmDropdown = place(tsmDropdown, MakeTsmDropdown, y)
        tsmDropdown:Refresh()
        track(tsmDropdown, "other")
        y = y - 32

        hintLabel(S_PAD, y, ns.L["tsm_custom"], 0.50)
        y = y - 18

        tsmCustomEB = place(tsmCustomEB, MakeCustomSourceEB, y)
        tsmCustomEB.eb:SetText(db.tsmCustomSource or "")
        track(tsmCustomEB, "other")
        y = y - 32
    end

    return y
end)
