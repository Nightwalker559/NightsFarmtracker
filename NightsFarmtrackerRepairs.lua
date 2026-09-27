local ADDON_NAME, ns = ...

-- One-time migration from the old flat sessions array (sessions[1],
-- sessions[2], ...) to the current day-keyed storage
-- (sessions["YYYY-MM-DD"] = { session1, session2, ... }) - makes the raw
-- SavedVariables file readable by calendar day instead of one long
-- undated list, instead of a numeric index per session. Detects the old
-- shape by checking whether sessions[1] looks like a session (has a
-- timestamp) rather than a day's array of sessions; an empty or
-- already-migrated table is left untouched. Mutates the table in place
-- (clears the old numeric keys, adds the new date keys) rather than
-- replacing it, so the change is visible through every existing
-- reference to NightsFarmtrackerAccountDB.sessions. Returns how many
-- sessions were migrated.
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

------------------------------------------------------------------------
-- Central one-time repair registry.
--
-- Account-wide (NightsFarmtrackerAccountDB) and per-character
-- (NightsFarmtrackerDB) one-time data repairs used to each track their
-- own boolean "somethingRepaired" flag, checked and run individually in
-- Core.lua. That grew unwieldy fast - this file replaces all of them
-- with a single incrementing "repairVersion" per scope: each repair is
-- registered below with the next sequential number, and ns.RunAccountRepairs
-- / ns.RunCharacterRepairs run every entry newer than what's already been
-- applied, in order, exactly once.
--
-- To add a new one-time repair: append an entry to the relevant list
-- below with the NEXT number after the current highest one and a short
-- name, and write the repair function itself wherever makes sense
-- (History.lua for anything touching saved sessions). Never reuse, skip,
-- or renumber an existing entry - already-repaired accounts key off these
-- numbers to know what they've already run.
------------------------------------------------------------------------

-- Account-wide repairs, applied to NightsFarmtrackerAccountDB.sessions.
-- Repairs 1-5 all use ns.ForEachSession (History.lua) so they work
-- unchanged on either the old flat array or the current day-keyed
-- storage - only the migration itself (6) cares which shape it finds.
ns.ACCOUNT_REPAIRS = {
    { 1, "qTotals",               function() return ns.RepairSessionTotals(NightsFarmtrackerAccountDB.sessions) end },
    { 2, "tierBreakdowns",        function() return ns.RepairCorruptedTierBreakdowns(NightsFarmtrackerAccountDB.sessions) end },
    { 3, "bindOnUseCanAH",        function() return ns.RepairBindOnUseCanAH(NightsFarmtrackerAccountDB.sessions) end },
    { 4, "gearVariantPricing",    function() return ns.RepairGearVariantPricing(NightsFarmtrackerAccountDB.sessions) end },
    { 5, "gearVariantItemLevels", function() return ns.RepairGearVariantItemLevels(NightsFarmtrackerAccountDB.sessions) end },
    { 6, "sessionsDateKeyed",     function() return ns.MigrateSessionsToDateKeyed(NightsFarmtrackerAccountDB.sessions) end },
    { 7, "unifiedVariants",      function() return ns.MigrateItemsToUnifiedVariants(NightsFarmtrackerAccountDB.sessions) end },
    { 8, "normalizeVariantKeys", function() return ns.NormalizeVariantKeysInSessions(NightsFarmtrackerAccountDB.sessions) end },
    { 9, "mergeDuplicateGearVariants", function() return ns.MergeDuplicateGearVariantsInSessions(NightsFarmtrackerAccountDB.sessions) end },
    { 10, "stripRedundantGearItemLink", function() return ns.StripRedundantGearItemLinkInSessions(NightsFarmtrackerAccountDB.sessions) end },
    -- Re-run of #5 with the field-name bug fixed (it checked the legacy
    -- d.gearVariants field and had been a no-op since #7 renamed it to
    -- d.variants) - registered as a new number so it actually runs again
    -- for accounts whose repairVersion is already >= 5.
    { 11, "gearVariantItemLevelsV2", function() return ns.RepairGearVariantItemLevels(NightsFarmtrackerAccountDB.sessions) end },
    -- Re-run of #4 with the same field-name bug fixed.
    { 12, "gearVariantPricingV2", function() return ns.RepairGearVariantPricing(NightsFarmtrackerAccountDB.sessions) end },
}

-- Per-character repairs, applied directly to the LIVE (unsaved) session in
-- NightsFarmtrackerDB.count, so an already-open session self-heals
-- immediately instead of waiting for its next loot event (see ProcessLoot
-- in Main.lua, which guards against the same issues going forward).
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
    { 2, "bindOnUseCanAH", function()
        local db = NightsFarmtrackerDB
        for _, d in pairs(db.count) do
            if d.canAH == false and not d.isBoP and not d.isBoA then
                d.canAH = true
            end
        end
    end },
    -- Live-count counterpart of account repair #7 (History.lua) - collapses
    -- gearVariants/q+qIDs+qAHTotal into the unified d.variants field on the
    -- current (unsaved) session too, so it self-heals immediately.
    { 3, "unifiedVariants", function()
        local db = NightsFarmtrackerDB
        for _, d in pairs(db.count) do
            ns.MigrateItemToUnifiedVariants(d)
        end
    end },
    { 4, "normalizeVariantKeys", function()
        local db = NightsFarmtrackerDB
        for _, d in pairs(db.count) do
            ns.NormalizeVariantKeys(d)
        end
    end },
    -- Live-count counterpart of account repair #9 (History.lua).
    { 5, "mergeDuplicateGearVariants", function()
        local db = NightsFarmtrackerDB
        for _, d in pairs(db.count) do
            ns.MergeDuplicateGearVariants(d)
        end
    end },
    -- Live-count counterpart of account repair #10 (History.lua).
    { 6, "stripRedundantGearItemLink", function()
        local db = NightsFarmtrackerDB
        for _, d in pairs(db.count) do
            ns.StripRedundantGearItemLink(d)
        end
    end },
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
