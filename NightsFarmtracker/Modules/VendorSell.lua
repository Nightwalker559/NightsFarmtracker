------------------------------------------------------------------------
-- Night's Farmtracker - Vendor Sell List
-- Opens next to the merchant window and lists the bag items the Vendor-Only
-- Filter and the Gear AH Threshold treat as vendor goods; one button sells
-- them. With the protection on, one click sells at most PROTECT_MAX items,
-- as many as the merchant's buyback list holds, so a wrong click can still be
-- undone. Off, one click sells the whole list. Warband items stay in the bags
-- unless that option is switched off. Both options sit in the window itself.
------------------------------------------------------------------------
local _, ns = ...

ns.VENDOR_SELL_PROTECT_MAX = 12   -- the buyback list keeps the last 12 sold items
local PROTECT_MAX   = ns.VENDOR_SELL_PROTECT_MAX
local SELL_INTERVAL = 0.1    -- seconds between two sales, so the server keeps up
local LAST_BAG      = 5      -- backpack (0), four bags, reagent bag

local pad, hdrH = ns.PAD, ns.WINDOW_HDR_H
local MIN_VIS_H = ns.DROPLIST_MIN_VIS_H
local BTN_H     = 22
local FTR_H     = 8 + BTN_H + 8
local VALUE_W   = 96         -- value column on the right of each row

local FRAME_NAME = "NightsFarmtrackerVendorSellWnd"
local frame, scrollFrame, listFrame
local items, rows = {}, {}   -- bag items to sell (most gold first) and their active rows
local selling                -- ticker of the running sale

-- Both options (Settings, Windows & Buttons) are on until switched off.
local function IsOn(dbKey)
    return NightsFarmtrackerDB[dbKey] ~= false
end

------------------------------------------------------------------------
-- What is for sale: the item data NFT's own rules need (the filter and the
-- threshold look at class, quality and binding), built from the bag link.
------------------------------------------------------------------------
local function BagItemData(itemID, link)
    local name, _, quality, _, _, _, itemSubType, _, _, _, sellPrice, classID, subClassID, bindType = C_Item.GetItemInfo(link)
    if not (classID and sellPrice and sellPrice > 0) then return nil end
    return {
        name = name, itemID = itemID, itemLink = link, classID = classID, subClassID = subClassID,
        quality = quality, itemSubType = itemSubType, isVendorTrash = (quality == 0),
        isBoE = (bindType == ns.BIND_ON_EQUIP), isBoP = (bindType == ns.BIND_ON_PICKUP),
        isBoA = ns.BIND_TO_ACCOUNT[bindType] or nil,
        isCosmetic = ns.IsGearClass(classID) and C_Item.IsCosmeticItem(link) or nil,
    }, sellPrice
end

-- Vendor-Only Filter (items, categories, AH-by-expansion), or Equipment under
-- the Gear AH Threshold. Only real weapons/armor take the threshold path:
-- ns.IsGear also counts every soulbound item, which must not be sold on a
-- missing AH price.
local function IsVendorGood(data, count)
    if ns.IsForceVendor(data.itemID) or ns.IsForceVendorCategory(data) or ns.IsForceVendorExpansion(data) then
        return true
    end
    if not ns.IsGearClass(data.classID) then return false end
    local ahPrice = ns.GetAHPriceForID(data.itemID, data.itemLink)
    return ns.IsGearThresholdVendorOnly(data, ahPrice and ahPrice * count)
end

-- Bound to the Warband, or until equipped (older clients report the latter as
-- plain BoE, so the bag slot is asked as well, like ApplyBagItemInfo does).
local function IsWarband(data, bag, slot)
    if data.isBoA then return true end
    if not C_Item.IsBoundToAccountUntilEquip then return false end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    return loc ~= nil and loc:IsValid() and C_Item.IsBoundToAccountUntilEquip(loc) == true
end

local function InEquipmentSet(bag, slot)
    return C_Container.GetContainerItemEquipmentSetInfo(bag, slot) == true
end

local function CollectItems()
    local list = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isLocked and not info.hasNoValue then
                local data, sellPrice = BagItemData(info.itemID, info.hyperlink)
                if data and IsVendorGood(data, info.stackCount) and not InEquipmentSet(bag, slot)
                   and not (IsOn("vendorSellKeepWarband") and IsWarband(data, bag, slot)) then
                    list[#list + 1] = {
                        bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, name = data.name,
                        count = info.stackCount, value = sellPrice * info.stackCount,
                        quality = info.quality, icon = info.iconFileID,
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    return list
end

-- How many items one click sells, and what they bring.
local function BatchInfo()
    local n = #items
    if IsOn("vendorSellProtect") then n = math.min(n, PROTECT_MAX) end
    local total = 0
    for i = 1, n do total = total + items[i].value end
    return n, total
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------
local rowPool = ns.NewPool(function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(ns.CONTENT_W, ns.ROW_H)

    ns.AddRowIcon(r):SetPoint("LEFT", ns.ICON_X, 0)

    r.valueText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.valueText:SetPoint("RIGHT", -4, 0)
    r.valueText:SetWidth(VALUE_W)
    r.valueText:SetJustifyH("RIGHT"); r.valueText:SetFontHeight(ns.FONT_NORMAL)

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",  r.icon,      "RIGHT", 8, 0)
    r.nameText:SetPoint("RIGHT", r.valueText, "LEFT",  -4, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(ns.FONT_NORMAL)

    ns.HookRowLinkTooltip(r)
    return r
end, function(r)
    r.itemLink = nil
    r.iconBorder:Hide()
end)

------------------------------------------------------------------------
-- Selling: one item per tick, each checked against its slot first (the bags
-- can change in between); the merchant closing stops the run.
------------------------------------------------------------------------
local function StopSelling()
    if selling then selling:Cancel(); selling = nil end
end

local function UpdateSellButton()
    local n, total = BatchInfo()
    local btn = frame.sellBtn
    local canSell = n > 0 and not selling
    local text
    if n < #items then
        text = string.format(ns.L["vendor_sell_btn_part"], n, #items)
    else
        text = string.format(ns.L["vendor_sell_btn"], n)
    end
    if n > 0 then text = text .. "  " .. ns.FormatGold(total) end
    btn.lbl:SetText(text)
    btn:SetEnabled(canSell)
    btn.lbl:SetTextColor(canSell and 0.85 or 0.4, canSell and 0.85 or 0.4, canSell and 0.85 or 0.4)
end

local function SellClick()
    if selling or not MerchantFrame:IsShown() then return end
    local n = BatchInfo()
    if n == 0 then return end
    local queue = {}
    for i = 1, n do queue[i] = items[i] end

    local i = 0
    selling = C_Timer.NewTicker(SELL_INTERVAL, function()
        i = i + 1
        local e = queue[i]
        local info = C_Container.GetContainerItemInfo(e.bag, e.slot)
        if info and info.itemID == e.itemID and not info.isLocked then
            C_Container.UseContainerItem(e.bag, e.slot)
        end
        if i >= n then
            selling = nil
            UpdateSellButton()
        end
    end, n)
    UpdateSellButton()
end

------------------------------------------------------------------------
-- List rebuild
------------------------------------------------------------------------
local function Rebuild()
    rowPool.releaseAll(rows)
    items = CollectItems()

    local yOff = 0
    for _, e in ipairs(items) do
        local r = rowPool.acquire(listFrame)
        r:SetPoint("TOPLEFT", 0, -yOff)
        r.itemLink = e.link
        r.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
        local name = ns.TruncateName(e.name)
        r.nameText:SetText(e.count > 1 and (name .. " |cffffd100x" .. e.count .. "|r") or name)
        ns.ApplyQualityColor(r.nameText, r.iconBorder, e.quality, {0.85, 0.85, 0.85})
        r.valueText:SetText(ns.FormatGold(e.value))
        rows[#rows + 1] = r
        yOff = yOff + ns.ROW_H
    end

    ns.FitScrollWindow({
        window = frame, scroll = scrollFrame, list = listFrame,
        hdrH = hdrH, ftrH = FTR_H, contentH = yOff, minH = MIN_VIS_H,
    })
    frame.emptyLabel:SetShown(#items == 0)
    UpdateSellButton()
    ns.DockFrame(frame, MerchantFrame, "right")
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function CreateSellButton(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(BTN_H)
    ns.StyleBackdropBox(btn, {0.05, 0.08, 0.09, 1})
    btn.lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.lbl:SetPoint("CENTER")
    btn.lbl:SetFontHeight(ns.FONT_NORMAL)
    btn:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetBackdropBorderColor(unpack(ns.COL_ACCENT)) end
    end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(ns.COL_BORDER)) end)
    btn:SetScript("OnClick", SellClick)
    return btn
end

-- Gear icon left of the close button: opens Settings at the sell list options
local function CreateConfigButton(parent)
    local btn = ns.MakeBtn(parent, 16, "btn_settings.png")
    btn:SetPoint("RIGHT", parent.closeBtn, "LEFT", -6, 0)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:SetText(ns.L["vendor_sell_config"])
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function() ns.OpenSettingsAt("sellList") end)
    return btn
end

local function EnsureFrame()
    if frame then return end
    frame = ns.CreateWindowFrame(FRAME_NAME, ns.L["vendor_sell_title"], { width = ns.FRAME_W })
    -- It belongs to the merchant window, not to the docking chains: Esc must
    -- close the merchant in one press, which takes this window with it.
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == FRAME_NAME then table.remove(UISpecialFrames, i) end
    end
    ns.VendorSellFrame = frame

    ns.AddHLine(frame, "TOP", pad, -(hdrH - 1))
    ns.AddHLine(frame, "BOTTOM", pad, FTR_H - 2)

    scrollFrame, listFrame = ns.CreateScrollList(frame, ns.CONTENT_W, ns.ROW_H)
    scrollFrame:SetPoint("TOPLEFT", pad, -hdrH)
    scrollFrame:SetWidth(ns.CONTENT_W)

    frame.emptyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.emptyLabel:SetPoint("TOP", frame, "TOP", 0, -(hdrH + 14))
    frame.emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    frame.emptyLabel:SetText(ns.L["vendor_sell_empty"])

    CreateConfigButton(frame)

    frame.sellBtn = CreateSellButton(frame)
    frame.sellBtn:SetPoint("BOTTOMLEFT", pad, 8)
    frame.sellBtn:SetPoint("BOTTOMRIGHT", -pad, 8)

    -- Registered only while the window is open
    frame:SetScript("OnEvent", Rebuild)
    frame:HookScript("OnShow", function(self) self:RegisterEvent("BAG_UPDATE_DELAYED") end)
    frame:HookScript("OnHide", function(self) self:UnregisterEvent("BAG_UPDATE_DELAYED") end)
end

local function OnMerchantShow()
    if NightsFarmtrackerDB.vendorSellEnabled == false then return end
    EnsureFrame()
    Rebuild()
    if #items > 0 then frame:Show() end
end

local function OnMerchantHide()
    StopSelling()
    if frame then frame:Hide() end
end

-- Called from Settings when one of the window options changed
function ns.RefreshVendorSell()
    if frame and frame:IsShown() then Rebuild() end
end

-- Called from Settings when the feature is switched off
function ns.OnVendorSellDisabled()
    OnMerchantHide()
end

MerchantFrame:HookScript("OnShow", OnMerchantShow)
MerchantFrame:HookScript("OnHide", OnMerchantHide)
