------------------------------------------------------------------------
-- Night's Farmtracker - Settings: Sell List options
-- The Sell List options window (gear icon next to "Show the sell list at
-- vendors" in Settings and in the Sell List window) and its Warband track dropdown.
------------------------------------------------------------------------
local _, ns = ...
local K = ns.SettingsKit

local S_W, S_PAD, S_HDR_H, CTRL_SIZE, CTRL_GAP = K.S_W, K.S_PAD, K.S_HDR_H, K.CTRL_SIZE, K.CTRL_GAP
local MakeDropdownBox, MakePopupList, ToggleMenu = K.MakeDropdownBox, K.MakePopupList, K.ToggleMenu
local MenuTextColor, checkboxPool, ConfigureCheckbox = K.MenuTextColor, K.checkboxPool, K.ConfigureCheckbox

local trackMenuList
local sellCfgPop   -- the options window (see ns.ToggleVendorSellConfig)

------------------------------------------------------------------------
-- Sell List: upgrade tracks of Warband gear that is sold anyway. A dropdown
-- whose rows are check boxes; the list stays open while several are ticked.
-- Greyed out while Warband items are not kept or the Sell List is off.
------------------------------------------------------------------------
local TRACK_ROW_H = 20

local function MakeWarbandTrackDropdown(parent)
    local frame = MakeDropdownBox(parent, S_W - S_PAD*2 - 40 - (CTRL_SIZE + 8))
    frame.lbl:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    frame.lbl:SetJustifyH("LEFT")
    frame.lbl:SetWordWrap(false)

    local list = MakePopupList()
    list:SetFrameLevel(50)   -- above the options window that hosts this dropdown
    trackMenuList = list

    local function Ticked(key)
        local tracks = NightsFarmtrackerDB.vendorSellWarbandTracks
        return tracks ~= nil and tracks[key] == true
    end

    list.rows = {}
    for i, t in ipairs(ns.WARBAND_SELL_TRACKS) do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(TRACK_ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i-1)*TRACK_ROW_H)
        row:SetPoint("RIGHT", -2, 0)
        local box, mark = ns.CreateMarkBox(row, 12)
        box:SetPoint("LEFT", 6, 0)
        row.mark = mark
        row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.txt:SetPoint("LEFT", box, "RIGHT", 6, 0)
        row.txt:SetText(ns.L[t.locKey])
        row:SetScript("OnEnter", function() row.txt:SetTextColor(1, 1, 1) end)
        row:SetScript("OnLeave", function() MenuTextColor(row) end)
        row:SetScript("OnClick", function()
            local db = NightsFarmtrackerDB
            db.vendorSellWarbandTracks = db.vendorSellWarbandTracks or {}
            db.vendorSellWarbandTracks[t.key] = (not Ticked(t.key)) or nil
            row.isActive = Ticked(t.key)
            row.mark:SetShown(row.isActive)
            MenuTextColor(row)
            frame:Refresh()
            ns.RefreshVendorSell()
        end)
        list.rows[i] = row
    end
    list:SetHeight(2 + TRACK_ROW_H * #ns.WARBAND_SELL_TRACKS + 2)

    frame:SetScript("OnMouseUp", function()
        ToggleMenu(list, frame, function()
            for i, t in ipairs(ns.WARBAND_SELL_TRACKS) do
                local row = list.rows[i]
                row.isActive = Ticked(t.key)
                row.mark:SetShown(row.isActive)
                MenuTextColor(row)
            end
        end)
    end)
    frame:SetScript("OnEnter", function(self)
        if not self:IsMouseEnabled() then return end
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(ns.L["vendor_sell_track_tip"], 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Label = the ticked tracks; greyed out and inert while off
    function frame:Refresh()
        local db = NightsFarmtrackerDB
        local names = {}
        for _, t in ipairs(ns.WARBAND_SELL_TRACKS) do
            if Ticked(t.key) then names[#names + 1] = ns.L[t.locKey] end
        end
        local off = db.vendorSellEnabled == false or db.vendorSellKeepWarband == false
        self.lbl:SetText(#names > 0 and table.concat(names, ", ") or ns.L["vendor_sell_tracks_none"])
        self.lbl:SetTextColor(off and 0.4 or 0.85, off and 0.4 or 0.85, off and 0.4 or 0.85)
        self:EnableMouse(not off)
        if off then list:Hide() end
    end

    return frame
end

------------------------------------------------------------------------
-- Sell List config window: the gear icon next to "Show the sell list at
-- vendors" (Settings) and the one in the Sell List window open it. Warband
-- items, upgrade tracks and the sale protection, the same widgets as the
-- settings page; rebuilt on open and after every change, so it always shows
-- the active profile. New Sell List options belong here. Opened from Settings
-- it joins the left docking chain behind Settings, opened from the Sell List
-- window it docks to that window.
------------------------------------------------------------------------
local sellCfgRows = {}

local function BuildSellConfig()
    local pop = sellCfgPop
    checkboxPool.releaseAll(sellCfgRows)
    local db = NightsFarmtrackerDB
    local off = db.vendorSellEnabled == false

    -- Checkbox on db[key] (on unless switched off), then the next row's y
    local function option(y, label, key, tip)
        local row = checkboxPool.acquire(pop)
        sellCfgRows[#sellCfgRows + 1] = row
        ConfigureCheckbox(row, label, y,
            function() return db[key] ~= false end,
            function(v)
                db[key] = v
                ns.RefreshVendorSell()
                RunNextFrame(BuildSellConfig)   -- the pooled row still refreshes itself after this returns
            end, { disabled = off, tip = tip })
        return y - math.max(CTRL_SIZE, math.ceil(row.label:GetStringHeight())) - CTRL_GAP
    end

    local y = -(S_HDR_H + 6)
    y = option(y, ns.L["vendor_sell_warband"], "vendorSellKeepWarband", ns.L["vendor_sell_warband_tip"])

    local indent = CTRL_SIZE + 8
    local gray = (off or db.vendorSellKeepWarband == false) and 0.3 or 0.5
    pop.hint:ClearAllPoints()
    pop.hint:SetPoint("TOPLEFT", S_PAD + indent, y)
    pop.hint:SetTextColor(gray, gray, gray)
    y = y - 18
    pop.trackDropdown:ClearAllPoints()
    pop.trackDropdown:SetPoint("TOPLEFT", S_PAD + indent, y)
    pop.trackDropdown:Refresh()
    y = y - 32

    y = option(y, string.format(ns.L["vendor_sell_protect"], ns.VENDOR_SELL_PROTECT_MAX), "vendorSellProtect",
        string.format(ns.L["vendor_sell_protect_tip"], ns.VENDOR_SELL_PROTECT_MAX))
    pop:SetHeight(-y + 4)
end

function ns.ToggleVendorSellConfig(owner)
    if sellCfgPop and sellCfgPop:IsShown() then sellCfgPop:Hide(); return end

    if not sellCfgPop then
        local pop = ns.CreateWindowFrame("NightsFarmtrackerSellConfigWnd", ns.L["vendor_sell_config"],
            { width = S_W, pad = S_PAD, titleColor = ns.COL_ACCENT, dockChain = "left", noEsc = true })
        sellCfgPop = pop
        K.RegisterPopup(pop)
        ns.AddHLine(pop, "TOP", S_PAD, -(S_HDR_H - 1))

        pop.hint = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pop.hint:SetText(ns.L["vendor_sell_tracks"])
        pop.trackDropdown = MakeWarbandTrackDropdown(pop)
        pop:HookScript("OnHide", function() trackMenuList:Hide() end)
    end

    BuildSellConfig()
    -- Only a window opened from Settings belongs to the chain (it re-docks
    -- there whenever another window opens or closes)
    local fromSettings = owner == ns.SettingsFrame
    ns.SellConfigFrame = fromSettings and sellCfgPop or nil
    sellCfgPop:Show()
    if fromSettings then ns.RefreshWindowChain("left") else ns.DockFrame(sellCfgPop, owner, "right") end
end

-- The merchant window closing takes the options window with it
function ns.CloseVendorSellConfig()
    if sellCfgPop then sellCfgPop:Hide() end
end

function K.MakeSellConfigButton(parent)
    local btn = ns.CreateConfigButton(parent, ns.L["vendor_sell_config"])
    btn:SetScript("OnClick", function() ns.ToggleVendorSellConfig(ns.SettingsFrame) end)
    return btn
end
