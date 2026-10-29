------------------------------------------------------------------------
-- Night's Farmtracker - Repairs
-- One-time data repairs and migrations of saved sessions and of the live
-- session, run once per account/character from the numbered registry at the
-- end of this file (see ns.ACCOUNT_REPAIRS / ns.CHARACTER_REPAIRS).
------------------------------------------------------------------------
local _, ns = ...

-- Migrates the old flat sessions array (sessions[1], sessions[2], ...) to
-- day-keyed storage (sessions["YYYY-MM-DD"] = that day's sessions). The old
-- shape is recognized by sessions[1] having a timestamp; an empty or already
-- migrated table is left alone. Mutates in place so existing references to
-- NightsFarmtrackerAccountDB.sessions stay valid. Returns how many sessions
-- were migrated.
function ns.MigrateSessionsToDateKeyed(sessions)
    if not sessions then return 0 end
    if sessions[1] == nil or type(sessions[1]) ~= "table" or sessions[1].timestamp == nil then
        return 0 -- empty, or already on the new format
    end

    local byDay, count = {}, 0
    for _, session in ipairs(sessions) do
        local dayKey = date("%Y-%m-%d", session.timestamp)
        byDay[dayKey] = byDay[dayKey] or {}
        table.insert(byDay[dayKey], session)
        count = count + 1
    end
    -- Preserve newest-first order within each day, matching the old
    -- array's own invariant (a new same-day entry was always inserted at
    -- position 1).
    for _, list in pairs(byDay) do
        table.sort(list, function(a, b) return a.timestamp > b.timestamp end)
    end

    for k in pairs(sessions) do sessions[k] = nil end
    for dayKey, list in pairs(byDay) do sessions[dayKey] = list end
    return count
end

-- Calls fn(d, itemID, session) for every saved item of every session and adds
-- up what it returns (a number, or true for 1). Returns the total.
local function ForEachSavedItem(sessions, fn)
    if not sessions then return 0 end
    local total = 0
    ns.ForEachSession(sessions, function(session)
        for itemID, d in pairs(session.items or {}) do
            local r = fn(d, itemID, session)
            if r == true then total = total + 1 elseif type(r) == "number" then total = total + r end
        end
    end)
    return total
end

------------------------------------------------------------------------
-- Clears per-item breakdowns that do not add up to the item's own amount
-- (reagent tiers q/qIDs/qAHTotal, gearVariants) and recomputes vendorTotal
-- where it disagreed with sellPrice * amount. Returns how many items changed.
function ns.RepairCorruptedTierBreakdowns(sessions)
    return ForEachSavedItem(sessions, function(d)
        local fixed = 0
        local amount = d.amount or 0
        if d.q then
            local qSum = (d.q[1] or 0) + (d.q[2] or 0) + (d.q[3] or 0)
            if qSum ~= amount then
                d.q, d.qIDs, d.qAHTotal = nil, nil, nil
                fixed = fixed + 1
            end
        end
        if d.gearVariants then
            local gvSum = 0
            for _, gv in pairs(d.gearVariants) do gvSum = gvSum + (gv.amount or 0) end
            if gvSum ~= amount then
                d.gearVariants = nil
                if d.sellPrice and d.sellPrice > 0 then d.vendorTotal = d.sellPrice * amount end
                fixed = fixed + 1
            end
        elseif d.sellPrice and d.sellPrice > 0 then
            local expect = d.sellPrice * amount
            if d.vendorTotal ~= expect then
                d.vendorTotal = expect
                fixed = fixed + 1
            end
        end
        return fixed
    end)
end

-- One-time repair for the Bind-on-Use canAH fix (see CanAH in Main.lua):
-- items saved before the fix with canAH=false purely because of their
-- bind type (not BoP/BoA, which stay vendor-only) get canAH re-enabled so
-- they price via AH again. Returns how many items were touched.
local function FixBindOnUseCanAH(d)
    if d.canAH == false and not d.isBoP and not d.isBoA then
        d.canAH = true
        return true
    end
end

function ns.RepairBindOnUseCanAH(sessions)
    return ForEachSavedItem(sessions, FixBindOnUseCanAH)
end

-- Repairs gear-variant price data. Found in saved data:
--  1. A variant with the legacy per-unit field `ahPrice` instead of `ahTotal`.
--  2. A variant with no price field at all.
--  3. Variant ahTotals that do not sum to the item's own ahTotal (two
--     independent live AH lookups at save time drifted apart).
-- For 1-2 the live lookup would target one long-gone bonus-ID roll and usually
-- return nil, so the row fell back to vendor price. The item-level ahTotal is
-- frozen at save time and trusted instead: `ahPrice` becomes `ahTotal`, and
-- what the item total does not already account for is split across the
-- priceless variants by amount. For 3 every variant is rescaled to sum to the
-- item total. Reads d.variants, falling back to the pre-migration
-- d.gearVariants. Returns how many variants changed.
function ns.RepairGearVariantPricing(sessions)
    return ForEachSavedItem(sessions, function(d)
        local variants = d.variants or d.gearVariants
        if not variants then return 0 end
        local fixed = 0
        local knownTotal, missingAmount = 0, 0
        for _, gv in pairs(variants) do
            if gv.ahPrice then
                gv.ahTotal = (gv.ahPrice or 0) * (gv.amount or 0)
                gv.ahPrice = nil
                fixed = fixed + 1
            end
            if (gv.ahTotal or 0) > 0 then
                knownTotal = knownTotal + gv.ahTotal
            else
                missingAmount = missingAmount + (gv.amount or 0)
            end
        end
        local remaining = (d.ahTotal or 0) - knownTotal
        if missingAmount > 0 and remaining > 0 then
            local perUnit = remaining / missingAmount
            for _, gv in pairs(variants) do
                if (gv.ahTotal or 0) <= 0 and (gv.amount or 0) > 0 then
                    gv.ahTotal = perUnit * gv.amount
                    fixed = fixed + 1
                end
            end
        elseif missingAmount == 0 and knownTotal > 0 and (d.ahTotal or 0) > 0
        and math.abs(knownTotal - d.ahTotal) > 1 then
            -- Every variant has a price but they do not add up to the item's
            -- frozen total: treat the item total as the truth (every other
            -- total is built from it) and rescale each variant's share.
            local scale = d.ahTotal / knownTotal
            for _, gv in pairs(variants) do
                if (gv.ahTotal or 0) > 0 then
                    gv.ahTotal = gv.ahTotal * scale
                end
            end
            fixed = fixed + 1
        end
        return fixed
    end)
end

-- Fills a missing itemLevel on a gear variant (the __novariant__ placeholder,
-- or old data) from the same item's full saved history: scaling gear ties item
-- level to quality, so if quality 3 only ever dropped at level 266, a quality-3
-- bucket without a level was 266 too. A quality seen at several levels is
-- ambiguous and left alone. Returns how many variants changed.
function ns.RepairGearVariantItemLevels(sessions)
    -- Pass 1: itemID -> quality -> itemLevel over every session. A quality
    -- seen at more than one level is marked ambiguous (false) and never used
    -- to fill anything in. Reads d.variants, falling back to d.gearVariants.
    local ilvlByItemQuality = {}
    ForEachSavedItem(sessions, function(d, itemID)
        local variants = d.variants or d.gearVariants
        if variants then
            local byQuality = ilvlByItemQuality[itemID]
            if not byQuality then
                byQuality = {}
                ilvlByItemQuality[itemID] = byQuality
            end
            for _, gv in pairs(variants) do
                if gv.itemLevel and gv.quality then
                    local existing = byQuality[gv.quality]
                    if existing == nil then
                        byQuality[gv.quality] = gv.itemLevel
                    elseif existing ~= false and existing ~= gv.itemLevel then
                        byQuality[gv.quality] = false -- ambiguous, don't guess
                    end
                end
            end
        end
    end)

    -- Pass 2: fill in whatever pass 1 resolved unambiguously.
    return ForEachSavedItem(sessions, function(d, itemID)
        local variants = d.variants or d.gearVariants
        local byQuality = variants and ilvlByItemQuality[itemID]
        if not byQuality then return 0 end
        local fixed = 0
        for _, gv in pairs(variants) do
            if not gv.itemLevel and gv.quality then
                local ilvl = byQuality[gv.quality]
                if ilvl and ilvl ~= false then
                    gv.itemLevel = ilvl
                    fixed = fixed + 1
                end
            end
        end
        return fixed
    end)
end

-- Recomputes every saved session's totalGold/totalVendor/totalAH from its own
-- items via BuildSessionCategories, so the session row cannot disagree with the
-- Detail window (needed for sessions whose frozen totals were inflated by
-- mis-tagged reagent tiers). It deliberately avoids ns.VendorTotal/AHTotal/
-- ItemValue, which price gear from a live AH lookup and would replace an old
-- session's frozen gear value with today's price. Sessions without filterFrozen
-- are valued with the current Vendor-Only filters.
function ns.RepairSessionTotals(sessions)
    if not sessions then return 0 end
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        local cats = ns.BuildSessionCategories(session)
        local totalGold = 0
        for _, cat in pairs(cats) do totalGold = totalGold + cat.gold end

        local totalVendor, totalAH = 0, 0
        for _, d in pairs(session.items or {}) do
            totalVendor = totalVendor + (d.vendorTotal or 0)
            local ah = d.ahTotal
            if d.q and d.qIDs
            and ((d.q[1] or 0) + (d.q[2] or 0) + (d.q[3] or 0)) ~= (d.amount or 0) then
                local p = ns.GetAHPriceForID(d.itemID, d.itemLink)
                ah = p and (p * (d.amount or 0)) or nil
            end
            totalAH = totalAH + (ah or 0)
        end

        if totalGold   ~= (session.totalGold or 0)
        or totalVendor ~= (session.totalVendor or 0)
        or totalAH     ~= (session.totalAH or 0) then
            session.totalGold   = totalGold
            session.totalVendor = totalVendor
            session.totalAH     = totalAH
            fixed = fixed + 1
        end
    end)
    return fixed
end

------------------------------------------------------------------------
-- Collapses the legacy per-item shapes (gearVariants for scaling gear, q/qIDs/
-- qAHTotal for reagent tiers) into one d.variants field: bonus-ID string keys
-- for gear, tier number 1-3 for reagents. It runs after the repairs that wipe
-- corrupted breakdowns, so it only reshapes consistent data. GetVariants in
-- PriceHelper.lua reads the result. Returns how many items were converted.
------------------------------------------------------------------------
function ns.MigrateItemToUnifiedVariants(d)
    if d.variants then return false end
    if d.gearVariants then
        d.variants, d.gearVariants = d.gearVariants, nil
        return true
    end
    if d.q then
        local variants
        for tier = 1, 3 do
            local tc = d.q[tier] or 0
            if tc > 0 then
                variants = variants or {}
                variants[tier] = {
                    amount = tc, sellPrice = d.sellPrice,
                    ahTotal = d.qAHTotal and d.qAHTotal[tier],
                    priceItemID = (d.qIDs and d.qIDs[tier]) or d.itemID,
                }
            end
        end
        if variants then d.variants = variants end
        d.q, d.qIDs, d.qAHTotal = nil, nil, nil
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Normalizes numeric keys in gear variants to strings (an old remainder bucket
-- was keyed by quality number), so a gear variants table is uniformly
-- string-keyed. Reagent tiers (keys 1/2/3) stay numeric, other code looks them
-- up by number. Returns how many keys changed.
------------------------------------------------------------------------
function ns.NormalizeVariantKeys(d)
    if not d.variants or not ns.IsGear(d) then return 0 end
    local numericKeys
    for key in pairs(d.variants) do
        if type(key) == "number" then
            numericKeys = numericKeys or {}
            numericKeys[#numericKeys+1] = key
        end
    end
    if not numericKeys then return 0 end
    for _, key in ipairs(numericKeys) do
        local gv = d.variants[key]
        d.variants[key] = nil
        local newKey = "legacy_" .. tostring(key)
        local existing = d.variants[newKey]
        if not existing then
            d.variants[newKey] = gv
        else
            -- Extremely unlikely collision (a real bonus-ID link string
            -- can never equal this) - merge instead of overwriting.
            existing.amount    = (existing.amount or 0) + (gv.amount or 0)
            existing.ahTotal   = (existing.ahTotal or 0) + (gv.ahTotal or 0)
            existing.sellPrice = existing.sellPrice or gv.sellPrice
            existing.itemLink  = existing.itemLink or gv.itemLink
            existing.itemLevel = existing.itemLevel or gv.itemLevel
            existing.quality   = existing.quality or gv.quality
        end
    end
    return #numericKeys
end

------------------------------------------------------------------------
-- Merges gear variants of the same item that describe the identical roll (same
-- itemLevel and quality) but got different keys because the bonus-ID tail of
-- the link came back in a different position between an early and a later
-- (fully cached) lookup, which split amount and ahTotal across two buckets.
-- Keyed by (itemLevel, quality), the pairing GroupGearVariantsForDisplay
-- already uses, instead of re-parsing the link. Reagent tiers and genuinely
-- different rolls are untouched. Returns how many variant keys were merged.
------------------------------------------------------------------------
function ns.MergeDuplicateGearVariants(d)
    if not d.variants or not ns.IsGear(d) then return 0 end

    local buckets, toMerge = {}, nil
    for key, gv in pairs(d.variants) do
        if gv.itemLevel and gv.quality then
            local bucketKey = gv.itemLevel .. "_" .. gv.quality
            local existingKey = buckets[bucketKey]
            if existingKey then
                toMerge = toMerge or {}
                toMerge[#toMerge+1] = { from = key, into = existingKey }
            else
                buckets[bucketKey] = key
            end
        end
    end
    if not toMerge then return 0 end

    for _, m in ipairs(toMerge) do
        local src, dst = d.variants[m.from], d.variants[m.into]
        if src and dst then
            dst.amount    = (dst.amount or 0)  + (src.amount or 0)
            dst.ahTotal   = (dst.ahTotal or 0) + (src.ahTotal or 0)
            dst.sellPrice = dst.sellPrice or src.sellPrice
            dst.itemLink  = dst.itemLink  or src.itemLink
        end
        d.variants[m.from] = nil
    end

    -- Resync the top-level mirror fields from the surviving variant with
    -- the largest amount, so d.itemLink/quality/sellPrice reflect an
    -- actually-existing bucket instead of a stale copy from whichever
    -- variant last happened to write them (see the Main.lua ProcessLoot/
    -- UpdatePricesFromBags comments on why this mirror exists at all).
    local best, bestAmount
    for _, gv in pairs(d.variants) do
        if not bestAmount or (gv.amount or 0) > bestAmount then
            best, bestAmount = gv, gv.amount or 0
        end
    end
    if best then
        d.itemLink  = best.itemLink  or d.itemLink
        d.quality   = best.quality   or d.quality
        d.sellPrice = best.sellPrice or d.sellPrice
    end

    return #toMerge
end

------------------------------------------------------------------------
-- Clears the top-level itemLink of gear items that have variants: it only
-- copied whichever variant was written last and goes stale with the next
-- different roll (display code reads gv.itemLink). New loot no longer writes
-- it. Non-gear items and gear without variants keep it as their only copy.
-- Returns how many items were cleared.
------------------------------------------------------------------------
function ns.StripRedundantGearItemLink(d)
    if d.itemLink and d.variants and ns.IsGear(d) then
        d.itemLink = nil
        return true
    end
    return false
end

------------------------------------------------------------------------
-- One-time repair for gear looted this session before variants existed: it was
-- merged into one db.count entry per item ID, mixing item levels and qualities.
-- Rebuilds the variant buckets from the items still in the bags; whatever was
-- already sold, mailed or banked stays in one fallback bucket (last known
-- quality and link) instead of being lost.
function ns.MigrateGearVariantsFromBags(items)
    if not items then return end
    local targets = {}
    for itemID, d in pairs(items) do
        if ns.IsGearClass(d.classID) and not d.variants then
            targets[itemID] = d
        end
    end
    if not next(targets) then return end

    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local ci = C_Container.GetContainerItemInfo(bag, slot)
            if ci and targets[ci.itemID] then
                local d    = targets[ci.itemID]
                local link = C_Container.GetContainerItemLink(bag, slot)
                if link then
                    local _, _, iQuality, iLevel, _, _, _, _, _, _, sp = C_Item.GetItemInfo(link)
                    local vKey = ns.GearVariantKey(link)
                    d.variants  = d.variants or {}
                    local gv    = d.variants[vKey]
                    if not gv then
                        gv = { amount = 0 }
                        d.variants[vKey] = gv
                    end
                    gv.amount    = gv.amount + (ci.stackCount or 1)
                    gv.quality   = iQuality
                    gv.itemLevel = iLevel
                    gv.itemLink  = link
                    if sp and sp > 0 then gv.sellPrice = sp end
                end
            end
        end
    end

    for _, d in pairs(targets) do
        local found = 0
        if d.variants then
            for _, gv in pairs(d.variants) do found = found + gv.amount end
        end
        local remainder = (d.amount or 0) - found
        if remainder > 0 then
            d.variants = d.variants or {}
            -- String key, never a bare number: a numeric key mixed into an
            -- otherwise bonus-ID-string-keyed variants table would make
            -- key-type checks depend on Lua's undefined pairs() order.
            local key = "legacy_q" .. tostring(d.quality or 0)
            local gv  = d.variants[key]
            if not gv then
                gv = { amount = 0, quality = d.quality, itemLink = d.itemLink, sellPrice = d.sellPrice }
                d.variants[key] = gv
            end
            gv.amount = gv.amount + remainder
        end
    end
end

-- Same repair as above, applied to the most recently saved session (rather
-- than the live/current one) - for when a session was already closed before
-- this fix was installed, but the items are still sitting in bags.
function ns.RepairLastSessionGearVariants()
    local session = ns.GetNewestSession()
    if session then ns.MigrateGearVariantsFromBags(session.items) end
end

------------------------------------------------------------------------
-- Central one-time repair registry. Account-wide (NightsFarmtrackerAccountDB)
-- and per-character (NightsFarmtrackerDB) repairs each run once, tracked by an
-- incrementing "repairVersion" per scope: ns.RunAccountRepairs and
-- ns.RunCharacterRepairs run every entry newer than the stored version, in
-- order.
--
-- To add a repair, append an entry with the next number and a short name. Never
-- reuse, skip or renumber an entry: already repaired accounts key off the
-- numbers.
------------------------------------------------------------------------

-- Account-wide repairs, applied to NightsFarmtrackerAccountDB.sessions.
-- InitAccountDB converts an old flat sessions array to day-keyed storage
-- before any of these run, so they all iterate with ns.ForEachSession
-- (Sessions.lua); entry 6 stays registered for the numbering.
ns.ACCOUNT_REPAIRS = {
    { 1, "qTotals",               function() return ns.RepairSessionTotals(NightsFarmtrackerAccountDB.sessions) end },
    { 2, "tierBreakdowns",        function() return ns.RepairCorruptedTierBreakdowns(NightsFarmtrackerAccountDB.sessions) end },
    { 3, "bindOnUseCanAH",        function() return ns.RepairBindOnUseCanAH(NightsFarmtrackerAccountDB.sessions) end },
    { 4, "gearVariantPricing",    function() return ns.RepairGearVariantPricing(NightsFarmtrackerAccountDB.sessions) end },
    { 5, "gearVariantItemLevels", function() return ns.RepairGearVariantItemLevels(NightsFarmtrackerAccountDB.sessions) end },
    { 6, "sessionsDateKeyed",     function() return ns.MigrateSessionsToDateKeyed(NightsFarmtrackerAccountDB.sessions) end },
    { 7, "unifiedVariants",      function() return ForEachSavedItem(NightsFarmtrackerAccountDB.sessions, ns.MigrateItemToUnifiedVariants) end },
    { 8, "normalizeVariantKeys", function() return ForEachSavedItem(NightsFarmtrackerAccountDB.sessions, ns.NormalizeVariantKeys) end },
    { 9, "mergeDuplicateGearVariants", function() return ForEachSavedItem(NightsFarmtrackerAccountDB.sessions, ns.MergeDuplicateGearVariants) end },
    { 10, "stripRedundantGearItemLink", function() return ForEachSavedItem(NightsFarmtrackerAccountDB.sessions, ns.StripRedundantGearItemLink) end },
    -- Re-run of #5 with the field-name bug fixed (it checked the legacy
    -- d.gearVariants field and had been a no-op since #7 renamed it to
    -- d.variants) - registered as a new number so it actually runs again
    -- for accounts whose repairVersion is already >= 5.
    { 11, "gearVariantItemLevelsV2", function() return ns.RepairGearVariantItemLevels(NightsFarmtrackerAccountDB.sessions) end },
    -- Re-run of #4 with the same field-name bug fixed.
    { 12, "gearVariantPricingV2", function() return ns.RepairGearVariantPricing(NightsFarmtrackerAccountDB.sessions) end },
    { 13, "timestampsToDayKey", function() return ns.RepairSessionTimestampsToDayKey(NightsFarmtrackerAccountDB.sessions) end },
}

-- Per-character repairs, applied directly to the LIVE (unsaved) session in
-- NightsFarmtrackerDB.count, so an already-open session self-heals
-- immediately instead of waiting for its next loot event (see ProcessLoot
-- in Main.lua, which guards against the same issues going forward).
local function ForEachLiveItem(fn)
    for _, d in pairs(NightsFarmtrackerDB.count) do fn(d) end
end

ns.CHARACTER_REPAIRS = {
    { 1, "tierBreakdowns", function()
        local db = NightsFarmtrackerDB
        for _, d in pairs(db.count) do
            local amount = d.amount or 0
            if d.q and ((d.q[1] or 0) + (d.q[2] or 0) + (d.q[3] or 0)) ~= amount then
                d.q, d.qIDs = nil, nil
            end
            if d.gearVariants then
                local gvSum = 0
                for _, gv in pairs(d.gearVariants) do gvSum = gvSum + (gv.amount or 0) end
                if gvSum ~= amount then d.gearVariants = nil end
            end
        end
    end },
    { 2, "bindOnUseCanAH", function() ForEachLiveItem(FixBindOnUseCanAH) end },
    -- Live-count counterpart of account repair #7 - collapses
    -- gearVariants/q+qIDs+qAHTotal into the unified d.variants field on the
    -- current (unsaved) session too, so it self-heals immediately.
    { 3, "unifiedVariants", function() ForEachLiveItem(ns.MigrateItemToUnifiedVariants) end },
    { 4, "normalizeVariantKeys", function() ForEachLiveItem(ns.NormalizeVariantKeys) end },
    -- Live-count counterpart of account repair #9.
    { 5, "mergeDuplicateGearVariants", function() ForEachLiveItem(ns.MergeDuplicateGearVariants) end },
    -- Live-count counterpart of account repair #10.
    { 6, "stripRedundantGearItemLink", function() ForEachLiveItem(ns.StripRedundantGearItemLink) end },
}

-- Legacy per-flag names this replaces, oldest first - used ONLY once, to
-- migrate an account/character already on the old system straight to the
-- matching repairVersion instead of re-running everything it already did.
-- Never extended for new repairs; anything added after this file exists
-- only ever lives under the numbered system above.
local LEGACY_ACCOUNT_FLAGS = {
    "qTotalsRepairedV2", "tierBreakdownsRepaired", "bindOnUseCanAHRepaired", "gearVariantPricingRepairedV2",
}
local LEGACY_CHARACTER_FLAGS = {
    "tierBreakdownsRepaired", "bindOnUseCanAHRepaired",
}

-- A flag only counts if every flag before it in the list is also set -
-- an old account should never end up on a HIGHER migrated version than
-- one it earned by actually completing every step in order.
local function MigratedVersion(db, legacyFlags)
    local version = 0
    for _, flagName in ipairs(legacyFlags) do
        if db[flagName] then
            version = version + 1
        else
            break
        end
    end
    return version
end

local function RunRepairs(db, registry, legacyFlags)
    if not db then return false end
    if db.repairVersion == nil then
        db.repairVersion = MigratedVersion(db, legacyFlags)
    end
    local ranAny = false
    for _, repair in ipairs(registry) do
        local num, name, fn = repair[1], repair[2], repair[3]
        if num > db.repairVersion then
            local ok, err = pcall(fn)
            if not ok then
                ns.Log("Repair '" .. name .. "' failed: " .. tostring(err))
            end
            ranAny = true
        end
    end
    if registry[#registry] then
        db.repairVersion = math.max(db.repairVersion, registry[#registry][1])
    end
    return ranAny
end

-- Called once from InitAccountDB, after NightsFarmtrackerAccountDB.sessions
-- exists. Session rollup totals (totalGold/totalVendor/totalAH) are always
-- refreshed once at the end if anything ran, since several of the repairs
-- above change per-item values those totals are built from.
function ns.RunAccountRepairs()
    if RunRepairs(NightsFarmtrackerAccountDB, ns.ACCOUNT_REPAIRS, LEGACY_ACCOUNT_FLAGS) then
        ns.RepairSessionTotals(NightsFarmtrackerAccountDB.sessions)
        if ns.RebuildHistory then ns.RebuildHistory() end
    end
end

-- Called once from InitDB, after NightsFarmtrackerDB.count exists.
function ns.RunCharacterRepairs()
    RunRepairs(NightsFarmtrackerDB, ns.CHARACTER_REPAIRS, LEGACY_CHARACTER_FLAGS)
end
