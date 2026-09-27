------------------------------------------------------------------------
-- Night's Farmtracker - Item Helper
-- Item classification (category names) and gold-value resolution.
-- Split out of Core.lua so item-domain logic lives together with
-- PriceHelper.lua instead of alongside the generic UI/frame utilities.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Category names
------------------------------------------------------------------------
function ns.CategoryName(data)
    if data.isVendorTrash or (data.quality == 0) then
        return ns.L and ns.L["cat_junk"] or "Junk"
    end
    if data.classID then
        if data.classID == 2 or data.classID == 4 then
            if data.isCosmetic then
                return ns.L and ns.L["cat_gear_cosmetic"] or "Equipment (Cosmetic)"
            end
            return ns.GearCategoryName(data)
        end
        -- Mounts / Companion Pets always get their own category (classID 15, Miscellaneous)
        if data.classID == Enum.ItemClass.Miscellaneous and data.subClassID then
            if data.subClassID == Enum.ItemMiscellaneousSubclass.Mount then
                return ns.L and ns.L["cat_mounts"] or "Mounts"
            end
            if data.subClassID == Enum.ItemMiscellaneousSubclass.CompanionPet then
                return ns.L and ns.L["cat_pets"] or "Pets"
            end
        end
        -- Split trade goods (7) and reagents (5) by WoW subtype when enabled.
        -- Resolved fresh from subClassID (not the cached itemSubType string)
        -- so it always reflects the CURRENT client language, even if the
        -- item was first looted under a different one. Falls back to
        -- resolving subClassID from itemID for older saved data that
        -- predates the subClassID field, so already-archived sessions
        -- self-heal too instead of staying stuck on old text forever.
        if (data.classID == 7 or data.classID == 5)
        and NightsFarmtrackerDB and NightsFarmtrackerDB.splitTradeGoods then
            local subClassID = data.subClassID
            if not subClassID and data.itemID then
                local _, _, _, _, _, _, resolvedSub = C_Item.GetItemInfoInstant(data.itemID)
                subClassID = resolvedSub
            end
            if subClassID then
                local subName = C_Item.GetItemSubClassInfo(data.classID, subClassID)
                if subName and subName ~= "" then return subName end
            end
            if data.itemSubType and data.itemSubType ~= "" then return data.itemSubType end
        end
        local name = C_Item.GetItemClassInfo(data.classID)
        if name and name ~= "" then return name end
    end
    if data.isBoE or data.isBoP or data.isBoA or data.isWarbound then
        if data.isCosmetic then
            return ns.L and ns.L["cat_gear_cosmetic"] or "Equipment (Cosmetic)"
        end
        return ns.GearCategoryName(data)
    end
    return C_Item.GetItemClassInfo(Enum.ItemClass.Tradegoods) or "Tradeskill"
end

-- Equipment category name, optionally split into BoE / BoA / Soulbound
-- (data.isBoP = Soulbound) sub-categories via the "splitGearByBinding"
-- setting. Falls back to the single combined "Equipment" category when
-- the setting is off or an item's binding isn't known yet.
-- data.isWarbound is a legacy field name (pre-1.3) for the same BoA/
-- Warband flag - checked as a fallback so old saved session data keeps
-- categorizing correctly after the isBoA rename.
function ns.GearCategoryName(data)
    if NightsFarmtrackerDB and NightsFarmtrackerDB.splitGearByBinding then
        if data.isBoA or data.isWarbound then return ns.L and ns.L["cat_gear_boa"]  or "Equipment (BoA)" end
        if data.isBoP then return ns.L and ns.L["cat_gear_soul"] or "Equipment (Soulbound)" end
        if data.isBoE then return ns.L and ns.L["cat_gear_boe"]  or "Equipment (BoE)" end
    end
    return ns.L and ns.L["cat_gear"] or "Equipment"
end

------------------------------------------------------------------------
-- Gear / vendor-only / value resolution
-- VendorTotal/AHTotal live in NightsFarmtrackerPriceHelper.lua
------------------------------------------------------------------------

-- True if this item counts as Equipment for GearAHThreshold purposes
-- (same binding flags used by GearCategoryName above, plus classID 2/4
-- as a fallback for cosmetic/unbound gear that has no bind flags yet -
-- keeps this in sync with CategoryName's cosmetic detection).
function ns.IsGear(data)
    return data.isBoE or data.isBoP or data.isBoA or data.isWarbound
        or data.classID == 2 or data.classID == 4
end

-- True if the Gear AH Threshold setting forces vendor-only pricing for
-- this item: Equipment whose AH price is below the configured gold
-- threshold (or has no AH price at all) always displays vendor price.
-- Shared by ItemValue() and the HUD row display so both stay in sync -
-- a display-side re-derivation of this rule previously caused item rows
-- to disagree with the category header (which goes through ItemValue).
function ns.IsGearThresholdVendorOnly(data, ahTotal)
    local threshold = NightsFarmtrackerDB.gearAHThreshold or 0
    if threshold <= 0 or not ns.IsGear(data) then return false end
    return not (ahTotal and ahTotal >= threshold)
end

-- vendor/ah are optional precomputed values (avoids recalculating
-- VendorTotal/AHTotal when the caller already has them, e.g. RefreshHUD).
-- True if an item must always be valued at vendor price, never AH
-- (BoP, force-vendor filtered item/category - which includes Junk by
-- default - or explicitly AH-ineligible).
function ns.IsVendorOnly(data)
    return data.isBoP or data.canAH == false or ns.IsForceVendor(data.itemID)
        or ns.IsForceVendorCategory(data) or ns.IsForceVendorExpansion(data)
end

-- Scaling/Adventurer's gear (see GearVariantKey) can drop the same item ID
-- at very different item levels, so each variant's own AH price can sit on
-- either side of the Gear AH Threshold independently. Deciding vendor-vs-AH
-- once from the combined AHTotal() of all variants (old behavior) meant one
-- expensive variant crossing the threshold forced AH pricing onto a much
-- cheaper sibling variant that was still below it, and vice versa. So this
-- picks vendor/AH per variant, then sums - kept in sync with the per-variant
-- row logic in UI.lua's flat-list build.
function ns.GearVariantItemValue(data)
    local total, any = 0, false
    for _, gv in pairs(ns.GetVariants(data)) do
        local sp = ns.VariantSellPrice(gv, data)
        local v = (sp and sp > 0) and (sp * gv.amount) or nil
        local ap = ns.GetAHPriceForID(data.itemID, gv.itemLink)
        local a = ap and (ap * gv.amount) or nil
        local value
        if ns.IsGearThresholdVendorOnly(data, a) then
            value = v or a
        elseif a and v then
            value = math.max(a, v)
        else
            value = a or v
        end
        if value then total = total + value; any = true end
    end
    return any and total or nil
end

function ns.ItemValue(data, vendor, ah)
    if data.itemID and ns.IsForceVendor(data.itemID) then return vendor or ns.VendorTotal(data) end
    if ns.IsForceVendorCategory(data) then return vendor or ns.VendorTotal(data) end
    if ns.IsForceVendorExpansion(data) then return vendor or ns.VendorTotal(data) end
    if data.isBoP or data.canAH == false then return vendor or ns.VendorTotal(data) end
    -- Per-variant vendor-vs-AH threshold decision only applies to scaling
    -- gear (see GearVariantItemValue) - reagent quality tiers also use
    -- data.variants (see GetVariants in PriceHelper.lua) but keep the
    -- combined item-level decision below, matching pre-unification behavior.
    if data.variants and ns.IsGear(data) then return ns.GearVariantItemValue(data) end
    local v = vendor or ns.VendorTotal(data)
    local a = ah     or ns.AHTotal(data)

    -- Gear AH threshold: Equipment only uses its AH price once that price
    -- reaches the configured gold threshold; below it (or with no AH price
    -- at all), vendor price is used instead.
    if ns.IsGearThresholdVendorOnly(data, a) then
        return v or a
    end

    if a and v then return math.max(a, v) end
    return a or v
end

------------------------------------------------------------------------
-- Item DB (audit/debug catalog) — one entry per itemID, written once and
-- never updated again. See ns.InitItemDB (Core.lua) for the SavedVariable
-- itself and why it exists. subcategory is the raw WoW item subclass name
-- (independent of the "splitTradeGoods" display setting), so the catalog
-- always shows the real classification regardless of addon settings.
------------------------------------------------------------------------
function ns.RecordItemDBEntry(itemID, name, link, quality, classID, subClassID, catData)
    if not itemID or not NightsFarmtrackerItemDB or NightsFarmtrackerItemDB[itemID] then return end
    local subName = subClassID and C_Item.GetItemSubClassInfo(classID, subClassID) or nil
    NightsFarmtrackerItemDB[itemID] = {
        name        = name,
        itemLink    = link,
        quality     = quality,
        itemID      = itemID,
        subID       = subClassID,
        category    = ns.CategoryName(catData),
        subcategory = subName,
    }
end

------------------------------------------------------------------------
-- Category discovery — every distinct category currently present among
-- tracked items (same grouping the HUD uses). "Junk" is always pinned in
-- the list even with nothing tracked yet, since both the Vendor-Only
-- Filter and Blacklist windows show it as an always-available toggle.
-- Shared by both windows' category checkbox sections.
------------------------------------------------------------------------
function ns.GetTrackedCategoryNames()
    local junkName = ns.L and ns.L["cat_junk"] or "Junk"
    local seen, names = { [junkName] = true }, { junkName }
    local db = NightsFarmtrackerDB
    if db and db.count then
        for _, data in pairs(db.count) do
            local name = ns.CategoryName(data)
            if name and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    return names
end

------------------------------------------------------------------------
-- Junk merge display ("mergeJunkEntries" setting) - display-only, does
-- NOT touch saved item data. When enabled, HUD/History/Log collapse the
-- whole Junk category into a single pseudo-item row ("Plunder") instead
-- of listing every junk item individually. Fixed generic icon, since the
-- row represents many different items at once.
------------------------------------------------------------------------
ns.JUNK_MERGED_ICON = "Interface\\Icons\\INV_Misc_Coin_02"

function ns.IsJunkCategory(catName)
    return catName == (ns.L and ns.L["cat_junk"] or "Junk")
end

-- Builds the pseudo-item record standing in for every Junk item once
-- merged. No real itemID/itemLink behind it, so tooltip/exclude code
-- paths must check `isJunkMerged` before touching those fields.
function ns.JunkMergedRecord(totalAmount, totalGold)
    return {
        amount        = totalAmount,
        icon          = ns.JUNK_MERGED_ICON,
        quality       = 0,
        itemID        = nil,
        itemLink      = nil,
        name          = ns.L and ns.L["junk_merged_name"] or "Plunder",
        isVendorTrash = true,
        isJunkMerged  = true,
        vendorTotal   = totalGold,
    }
end
