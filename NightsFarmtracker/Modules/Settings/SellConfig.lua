------------------------------------------------------------------------
-- Night's Farmtracker - Settings: Sell List options
-- The Sell List options window (gear icon next to "Show the sell list at
-- vendors" in Settings and in the Sell List window) and the pick window behind
-- the gear icon of its Warband, soulbound and BoE options.
------------------------------------------------------------------------
local _, ns = ...
local K = ns.SettingsKit

local S_W, S_PAD, S_HDR_H, CTRL_SIZE, CTRL_GAP = K.S_W, K.S_PAD, K.S_HDR_H, K.CTRL_SIZE, K.CTRL_GAP
local checkboxPool, ConfigureCheckbox = K.checkboxPool, K.ConfigureCheckbox

local sellCfgPop   -- the options window (see ns.ToggleVendorSellConfig)

local function SellListOff()
    return NightsFarmtrackerDB.vendorSellEnabled == false
end

local function TrackEntries()
    local entries = {}
    for i, t in ipairs(ns.SELL_TRACKS) do entries[i] = { key = t.key, label = ns.L[t.locKey] } end
    return entries
end

local function QualityEntries()
    local entries = {}
    for i, quality in ipairs(ns.BOE_KEEP_QUALITIES) do
        entries[i] = { key = quality, label = _G["ITEM_QUALITY" .. quality .. "_DESC"] }
    end
    return entries
end

-- The options that open a pick window: the option itself, the list its window
-- ticks (db[dbKey][key] = true), the rows of that list, whether the option is on
-- (the list only matters while it is) and the texts of the window and its gear
-- icon. Warband and soulbound gear is picked by upgrade track (sold anyway), BoE
-- items by quality (kept).
local PICK_KINDS = {
    warband = {
        optionKey = "vendorSellKeepWarband", dbKey = "vendorSellWarbandTracks", entries = TrackEntries,
        titleKey = "vendor_sell_pick_warband", tipKey = "vendor_sell_pick_warband_tip",
        isOn = function() return NightsFarmtrackerDB.vendorSellKeepWarband ~= false end,
    },
    soulbound = {
        optionKey = "vendorSellKeepSoulbound", dbKey = "vendorSellSoulboundTracks", entries = TrackEntries,
        titleKey = "vendor_sell_pick_soulbound", tipKey = "vendor_sell_pick_soulbound_tip",
        isOn = function() return NightsFarmtrackerDB.vendorSellKeepSoulbound == true end,
    },
    boe = {
        optionKey = "vendorSellKeepBoE", dbKey = "vendorSellKeepBoEQualities", entries = QualityEntries,
        titleKey = "vendor_sell_pick_boe", tipKey = "vendor_sell_pick_boe_tip",
        isOn = function() return NightsFarmtrackerDB.vendorSellKeepBoE == true end,
    },
}

------------------------------------------------------------------------
-- Pick window: the gear icon behind an option opens it, one window that shows
-- the list of the icon clicked last (clicking the same icon again closes it).
-- Warband and soulbound gear on a ticked upgrade track is offered although it is
-- kept (retail only, Forever has no tracks); BoE items of a ticked quality are
-- kept. Opened from the options window while that one sits in the left docking
-- chain it joins the chain behind it, otherwise it docks to the options window.
------------------------------------------------------------------------
local pickPop, pickKind
local pickRows = {}

local function BuildPick()
    local pop, kind = pickPop, PICK_KINDS[pickKind]
    checkboxPool.releaseAll(pickRows)
    local off = SellListOff() or not kind.isOn()

    pop.titleFS:SetText(ns.L[kind.titleKey])

    local y = -(S_HDR_H + 6)
    for _, entry in ipairs(kind.entries()) do
        local row = checkboxPool.acquire(pop)
        pickRows[#pickRows + 1] = row
        ConfigureCheckbox(row, entry.label, y,
            function()
                local ticked = NightsFarmtrackerDB[kind.dbKey]
                return ticked ~= nil and ticked[entry.key] == true
            end,
            function(v)
                local db = NightsFarmtrackerDB
                db[kind.dbKey] = db[kind.dbKey] or {}
                db[kind.dbKey][entry.key] = v or nil
                ns.RefreshVendorSell()
            end, { disabled = off })
        y = y - math.max(CTRL_SIZE, math.ceil(row.label:GetStringHeight())) - CTRL_GAP
    end
    pop:SetHeight(-y + 4)
end

local function TogglePick(kindKey)
    if pickPop and pickPop:IsShown() and pickKind == kindKey then pickPop:Hide(); return end

    if not pickPop then
        pickPop = ns.CreateWindowFrame("NightsFarmtrackerSellPickWnd", "", { width = S_W, pad = S_PAD, dockChain = "left", noEsc = true })
        K.RegisterPopup(pickPop)
        ns.AddHLine(pickPop, "TOP", S_PAD, -(S_HDR_H - 1))
    end

    pickKind = kindKey
    BuildPick()
    -- the options window is in the chain only when Settings opened it (see ns.ToggleVendorSellConfig)
    local inChain = ns.SellConfigFrame ~= nil
    ns.SellPickFrame = inChain and pickPop or nil
    pickPop:Show()
    if inChain then ns.RefreshWindowChain("left") else ns.DockFrame(pickPop, sellCfgPop, "right") end
end

------------------------------------------------------------------------
-- Sell List config window: the gear icon next to "Show the sell list at
-- vendors" (Settings) and the one in the Sell List window open it. Warband
-- items (not in Forever), soulbound items, BoE items (each with the gear icon of
-- its pick window; the Warband and soulbound ones not in Forever) and the sale
-- protection; rebuilt on open and after every change, so it always shows the
-- active profile. New Sell List options belong here.
-- Opened from Settings it joins the left docking chain behind Settings, opened
-- from the Sell List window it docks to that window.
------------------------------------------------------------------------
local sellCfgRows = {}

local function BuildSellConfig()
    local pop = sellCfgPop
    checkboxPool.releaseAll(sellCfgRows)
    local db = NightsFarmtrackerDB
    local off = SellListOff()

    -- Checkbox on db[key] (on unless switched off), then the next row's y and the row
    local function option(y, label, key, tip, onSet)
        local row = checkboxPool.acquire(pop)
        sellCfgRows[#sellCfgRows + 1] = row
        ConfigureCheckbox(row, label, y,
            function() return db[key] ~= false end,
            function(v)
                db[key] = v
                if onSet then onSet(v) end
                ns.RefreshVendorSell()
                RunNextFrame(BuildSellConfig)   -- the pooled row still refreshes itself after this returns
            end, { disabled = off, tip = tip })
        return y - math.max(CTRL_SIZE, math.ceil(row.label:GetStringHeight())) - CTRL_GAP, row
    end

    -- Option row with the gear icon of its pick window right behind the label
    local function pickOption(y, kindKey, label, tip, onSet)
        local row
        y, row = option(y, label, PICK_KINDS[kindKey].optionKey, tip, onSet)
        local btn = pop.pickBtns[kindKey]   -- none for soulbound in Forever (no tracks to pick)
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", row.label, "LEFT", row.label:GetStringWidth() + 8, 0)
            btn:SetFrameLevel(row:GetFrameLevel() + 5)   -- pooled rows keep their level, the checkbox row must not catch the click
        end
        return y
    end

    local y = -(S_HDR_H + 6)
    if not ns.IS_FOREVER then
        y = pickOption(y, "warband", ns.L["vendor_sell_warband"], ns.L["vendor_sell_warband_tip"])
    end
    y = pickOption(y, "soulbound", ns.L["vendor_sell_soulbound"], ns.L["vendor_sell_soulbound_tip"])
    -- switching it on with nothing ticked keeps every quality, not nothing
    y = pickOption(y, "boe", ns.L["vendor_sell_boe"], ns.L["vendor_sell_boe_tip"], function(v)
        if v and next(db.vendorSellKeepBoEQualities) == nil then
            for _, quality in ipairs(ns.BOE_KEEP_QUALITIES) do db.vendorSellKeepBoEQualities[quality] = true end
        end
    end)

    y = option(y, string.format(ns.L["vendor_sell_protect"], ns.VENDOR_SELL_PROTECT_MAX), "vendorSellProtect",
        string.format(ns.L["vendor_sell_protect_tip"], ns.VENDOR_SELL_PROTECT_MAX))
    pop:SetHeight(-y + 4)

    -- the pick window dims or lights up with the option it belongs to
    if pickPop and pickPop:IsShown() then BuildPick() end
end

function ns.ToggleVendorSellConfig(owner)
    if sellCfgPop and sellCfgPop:IsShown() then sellCfgPop:Hide(); return end

    if not sellCfgPop then
        local pop = ns.CreateWindowFrame("NightsFarmtrackerSellConfigWnd", ns.L["vendor_sell_config"],
            { width = S_W, pad = S_PAD, dockChain = "left", noEsc = true })
        sellCfgPop = pop
        K.RegisterPopup(pop)
        ns.AddHLine(pop, "TOP", S_PAD, -(S_HDR_H - 1))

        pop.pickBtns = {}
        for kindKey, kind in pairs(PICK_KINDS) do
            if not (ns.IS_FOREVER and kindKey ~= "boe") then   -- Forever has no tracks
                local btn = ns.CreateConfigButton(pop, ns.L[kind.titleKey], ns.L[kind.tipKey])
                btn:SetScript("OnClick", function() TogglePick(kindKey) end)
                pop.pickBtns[kindKey] = btn
            end
        end
        pop:HookScript("OnHide", function()
            if pickPop then pickPop:Hide() end
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
