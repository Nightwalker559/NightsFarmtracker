------------------------------------------------------------------------
-- Night's Farmtracker - Settings: Sell List options
-- The Sell List options window (gear icon next to "Show the sell list at
-- vendors" in Settings and in the Sell List window) and its check box dropdowns.
------------------------------------------------------------------------
local _, ns = ...
local K = ns.SettingsKit

local S_W, S_PAD, S_HDR_H, CTRL_SIZE, CTRL_GAP = K.S_W, K.S_PAD, K.S_HDR_H, K.CTRL_SIZE, K.CTRL_GAP
local MakeDropdownBox, MakePopupList, ToggleMenu = K.MakeDropdownBox, K.MakePopupList, K.ToggleMenu
local MenuTextColor, checkboxPool, ConfigureCheckbox = K.MenuTextColor, K.checkboxPool, K.ConfigureCheckbox

local dropdownMenus = {}   -- the popup lists of this window's dropdowns, closed with it
local sellCfgPop           -- the options window (see ns.ToggleVendorSellConfig)

local function SellListOff()
    return NightsFarmtrackerDB.vendorSellEnabled == false
end

-- Warband or soulbound items are kept, so the upgrade track exception has something to apply to.
local function KeepsBoundItems()
    local db = NightsFarmtrackerDB
    return db.vendorSellKeepWarband ~= false or db.vendorSellKeepSoulbound == true
end

------------------------------------------------------------------------
-- Dropdown whose rows are check boxes; the list stays open while several are
-- ticked. The ticked keys are stored as db[cfg.dbKey][key] = true.
-- cfg: entries ({ key, label } in display order), dbKey, tip, isOff() (greyed
-- out and inert).
------------------------------------------------------------------------
local ROW_H = 20

local function MakeCheckDropdown(parent, cfg)
    local frame = MakeDropdownBox(parent, S_W - S_PAD*2 - 40 - (CTRL_SIZE + 8))
    frame.lbl:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    frame.lbl:SetJustifyH("LEFT")
    frame.lbl:SetWordWrap(false)

    local list = MakePopupList()
    list:SetFrameLevel(50)   -- above the options window that hosts this dropdown
    dropdownMenus[#dropdownMenus + 1] = list

    local function Ticked(key)
        local ticked = NightsFarmtrackerDB[cfg.dbKey]
        return ticked ~= nil and ticked[key] == true
    end

    list.rows = {}
    for i, entry in ipairs(cfg.entries) do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i-1)*ROW_H)
        row:SetPoint("RIGHT", -2, 0)
        local box, mark = ns.CreateMarkBox(row, 12)
        box:SetPoint("LEFT", 6, 0)
        row.mark = mark
        row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.txt:SetPoint("LEFT", box, "RIGHT", 6, 0)
        row.txt:SetText(entry.label)
        row:SetScript("OnEnter", function() row.txt:SetTextColor(1, 1, 1) end)
        row:SetScript("OnLeave", function() MenuTextColor(row) end)
        row:SetScript("OnClick", function()
            local db = NightsFarmtrackerDB
            db[cfg.dbKey] = db[cfg.dbKey] or {}
            db[cfg.dbKey][entry.key] = (not Ticked(entry.key)) or nil
            row.isActive = Ticked(entry.key)
            row.mark:SetShown(row.isActive)
            MenuTextColor(row)
            frame:Refresh()
            ns.RefreshVendorSell()
        end)
        list.rows[i] = row
    end
    list:SetHeight(2 + ROW_H * #cfg.entries + 2)

    frame:SetScript("OnMouseUp", function()
        ToggleMenu(list, frame, function()
            for i, entry in ipairs(cfg.entries) do
                local row = list.rows[i]
                row.isActive = Ticked(entry.key)
                row.mark:SetShown(row.isActive)
                MenuTextColor(row)
            end
        end)
    end)
    frame:SetScript("OnEnter", function(self)
        if not self:IsMouseEnabled() then return end
        ns.ShowGrayTip(self, cfg.tip)
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Label = the ticked entries; greyed out and inert while off
    function frame:Refresh()
        local names = {}
        for _, entry in ipairs(cfg.entries) do
            if Ticked(entry.key) then names[#names + 1] = entry.label end
        end
        local off = cfg.isOff()
        self.lbl:SetText(#names > 0 and table.concat(names, ", ") or ns.L["vendor_sell_tracks_none"])
        self.lbl:SetTextColor(off and 0.4 or 0.85, off and 0.4 or 0.85, off and 0.4 or 0.85)
        self:EnableMouse(not off)
        if off then list:Hide() end
    end

    return frame
end

-- Sell anyway, by upgrade track: Warband or soulbound gear on a ticked track is
-- offered. Retail only (Forever has no tracks).
local function MakeTrackDropdown(parent)
    local entries = {}
    for i, t in ipairs(ns.WARBAND_SELL_TRACKS) do entries[i] = { key = t.key, label = ns.L[t.locKey] } end
    return MakeCheckDropdown(parent, {
        entries = entries, dbKey = "vendorSellWarbandTracks", tip = ns.L["vendor_sell_track_tip"],
        isOff = function() return SellListOff() or not KeepsBoundItems() end,
    })
end

-- Keep unbound Bind on Equip items of the ticked qualities.
local function MakeBoEQualityDropdown(parent)
    local entries = {}
    for i, quality in ipairs(ns.BOE_KEEP_QUALITIES) do
        entries[i] = { key = quality, label = _G["ITEM_QUALITY" .. quality .. "_DESC"] }
    end
    return MakeCheckDropdown(parent, {
        entries = entries, dbKey = "vendorSellKeepBoEQualities", tip = ns.L["vendor_sell_boe_tip"],
        isOff = SellListOff,
    })
end

------------------------------------------------------------------------
-- Sell List config window: the gear icon next to "Show the sell list at
-- vendors" (Settings) and the one in the Sell List window open it. Warband
-- items (not in Forever), soulbound items, upgrade tracks (not in Forever), BoE
-- qualities and the sale protection; rebuilt on open and after every change,
-- so it always shows the active profile. New Sell List options belong here.
-- Opened from Settings it joins the left docking chain behind Settings, opened
-- from the Sell List window it docks to that window.
------------------------------------------------------------------------
local sellCfgRows = {}

local function BuildSellConfig()
    local pop = sellCfgPop
    checkboxPool.releaseAll(sellCfgRows)
    local db = NightsFarmtrackerDB
    local off = SellListOff()

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

    -- Hint line, then its dropdown; dimmed while the dropdown is inert
    local function dropdownRow(y, hint, dropdown, dimmed)
        local gray = dimmed and 0.3 or 0.5
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", S_PAD, y)
        hint:SetTextColor(gray, gray, gray)
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPLEFT", S_PAD, y - 18)
        dropdown:Refresh()
        return y - 18 - 32
    end

    local y = -(S_HDR_H + 6)
    if not ns.IS_FOREVER then
        y = option(y, ns.L["vendor_sell_warband"], "vendorSellKeepWarband", ns.L["vendor_sell_warband_tip"])
    end
    y = option(y, ns.L["vendor_sell_soulbound"], "vendorSellKeepSoulbound", ns.L["vendor_sell_soulbound_tip"])
    if not ns.IS_FOREVER then
        y = dropdownRow(y, pop.hint, pop.trackDropdown, off or not KeepsBoundItems())
    end
    y = dropdownRow(y, pop.boeHint, pop.boeDropdown, off)

    y = option(y, string.format(ns.L["vendor_sell_protect"], ns.VENDOR_SELL_PROTECT_MAX), "vendorSellProtect",
        string.format(ns.L["vendor_sell_protect_tip"], ns.VENDOR_SELL_PROTECT_MAX))
    pop:SetHeight(-y + 4)
end

function ns.ToggleVendorSellConfig(owner)
    if sellCfgPop and sellCfgPop:IsShown() then sellCfgPop:Hide(); return end

    if not sellCfgPop then
        local pop = ns.CreateWindowFrame("NightsFarmtrackerSellConfigWnd", ns.L["vendor_sell_config"],
            { width = S_W, pad = S_PAD, dockChain = "left", noEsc = true })
        sellCfgPop = pop
        K.RegisterPopup(pop)
        ns.AddHLine(pop, "TOP", S_PAD, -(S_HDR_H - 1))

        if not ns.IS_FOREVER then
            pop.hint = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            pop.hint:SetText(ns.L["vendor_sell_tracks"])
            pop.trackDropdown = MakeTrackDropdown(pop)
        end
        pop.boeHint = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pop.boeHint:SetText(ns.L["vendor_sell_boe"])
        pop.boeDropdown = MakeBoEQualityDropdown(pop)
        pop:HookScript("OnHide", function()
            for _, menu in ipairs(dropdownMenus) do menu:Hide() end
        end)
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
