------------------------------------------------------------------------
-- Night's Farmtracker - Sessions
-- Saved-session data model: saving the live session, merging and compacting
-- sessions, deleting, and the category builder behind the Detail window.
-- (Repairs of saved sessions live in Repairs.lua.) The windows themselves live in Modules/History.lua.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Session save
------------------------------------------------------------------------

-- Placeholder variant key for the part of an item's amount that has no
-- per-variant breakdown (one side of a merge lacked it), so the variant sum
-- always equals the item's own amount. Keyed per quality: two sessions that
-- dropped different qualities must not collapse into one bucket that can
-- only remember one of them.
local function NoVariantKey(quality)
    return "__novariant__" .. tostring(quality or "?")
end

-- Calls fn(session) for every saved session (sessions["YYYY-MM-DD"] = a list
-- of that day's sessions). Order is not defined: callers that need
-- newest-first (RebuildHistory) sort the day keys themselves.
function ns.ForEachSession(sessions, fn)
    if not sessions then return end
    for _, dayList in pairs(sessions) do
        for _, session in ipairs(dayList) do fn(session) end
    end
end

local function CopyVariant(gv, ahTotal, ahAmount)
    return { amount = gv.amount, quality = gv.quality, itemLevel = gv.itemLevel,
             itemLink = gv.itemLink, sellPrice = gv.sellPrice, ahTotal = ahTotal,
             priceItemID = gv.priceItemID, ahAmount = ahAmount }
end

-- Copies an item's variants into a saved session. With snapshotAH (copying
-- from the live session) each variant's AH value is looked up once and frozen
-- into gv.ahTotal (a gold total, not a unit price). Copying from an already
-- saved entry (merge) carries the frozen total through, so two sessions
-- priced differently add up instead of being re-priced as one.
local function CopyVariants(variants, itemID, snapshotAH)
    if not variants then return nil end
    local hasAH = snapshotAH and NightsFarmtrackerDB.ahSource ~= "none"
    local copy = {}
    for key, gv in pairs(variants) do
        local ahTotal = gv.ahTotal
        if ahTotal == nil then
            ahTotal = 0
            if hasAH then
                local ap = ns.GetAHPriceForID(gv.priceItemID or itemID, gv.itemLink)
                if ap then ahTotal = ap * gv.amount end
            end
        end
        -- Units of this variant that carry an AH value (the rest are
        -- vendor-priced) - frozen like ahTotal, for the History tooltip.
        local ahAmount = gv.ahAmount
        if ahAmount == nil and snapshotAH then
            ahAmount = (ahTotal > 0) and gv.amount or 0
        end
        copy[key] = CopyVariant(gv, ahTotal, ahAmount)
    end
    return copy
end

-- Fields every saved item shares, whether it was just saved from the live
-- session or copied from another saved session; the caller adds the rest
-- (totals, variants, frozen values).
local function CopyItemFields(d)
    return {
        amount=d.amount, icon=d.icon, quality=d.quality, itemSubType=d.itemSubType, sellPrice=d.sellPrice,
        isVendorTrash=d.isVendorTrash, isBoE=d.isBoE, isBoP=d.isBoP, isBoA=d.isBoA, isWarbound=d.isWarbound, canAH=d.canAH,
        isCosmetic=d.isCosmetic, name=d.name,
        classID=d.classID, subClassID=d.subClassID, itemID=d.itemID, itemLink=d.itemLink,
    }
end

-- Sum of every variant's amount, for the reagent-tier consistency gate
-- below (mirrors the self-heal check in ProcessLoot).
local function VariantsSum(variants)
    local s = 0
    for _, gv in pairs(variants) do s = s + (gv.amount or 0) end
    return s
end

local function MergeSessionInto(target, src, keepTimestamp)
    if keepTimestamp then target.timestamp = src.timestamp end
    target.duration    = (target.duration or 0)    + (src.duration or 0)
    target.totalGold   = (target.totalGold or 0)   + (src.totalGold or 0)
    target.totalVendor = (target.totalVendor or 0) + (src.totalVendor or 0)
    target.totalAH     = (target.totalAH or 0)     + (src.totalAH or 0)
    target.lootedGold  = (target.lootedGold or 0)  + (src.lootedGold or 0)
    if src.qAtlas then
        target.qAtlas = target.qAtlas or {}
        for tier, atlas in pairs(src.qAtlas) do
            target.qAtlas[tier] = target.qAtlas[tier] or atlas
        end
    end
    target.items = target.items or {}
    for itemID, d in pairs(src.items or {}) do
        local ei = target.items[itemID]
        if not ei then
            ei = CopyItemFields(d)
            ei.vendorTotal, ei.ahTotal = d.vendorTotal or 0, d.ahTotal or 0
            ei.variants = CopyVariants(d.variants, d.itemID, false)
            ei.filterFrozen, ei.histValue = d.filterFrozen, d.histValue
            ei.ahAmount, ei.ahValue = d.ahAmount, d.ahValue
            target.items[itemID] = ei
        else
            -- Only stays frozen if BOTH sides were frozen at save time; a
            -- legacy (unfrozen) side falls back to the live vendor filters.
            ei.filterFrozen = ei.filterFrozen and d.filterFrozen or nil
            -- Frozen per-session values just add up, so a merge of one
            -- AH-priced and one vendor-priced session stays exact.
            if ei.histValue ~= nil and d.histValue ~= nil then
                ei.histValue = ei.histValue + d.histValue
            else
                ei.histValue = nil
            end
            if ei.ahAmount ~= nil and d.ahAmount ~= nil then
                ei.ahAmount = ei.ahAmount + d.ahAmount
                ei.ahValue  = (ei.ahValue or 0) + (d.ahValue or 0)
            else
                ei.ahAmount, ei.ahValue = nil, nil
            end
            local priorAmount      = ei.amount or 0
            local priorAhTotal     = ei.ahTotal or 0

            ei.amount      = priorAmount + (d.amount or 0)
            ei.vendorTotal = (ei.vendorTotal or 0) + (d.vendorTotal or 0)
            ei.ahTotal     = priorAhTotal + (d.ahTotal or 0)
            if d.variants then
                -- Reagent-tier variants merge only when their amounts add up to the entry's
                -- own amount, so a corrupted breakdown cannot spread through merges. Gear
                -- variants have no such gate. Tier or gear is decided by ns.IsGear(d), never
                -- by key type (mixed key types iterate in undefined order).
                local isTier   = not ns.IsGear(d)
                local consistent = (not isTier) or (VariantsSum(d.variants) == (d.amount or 0))
                if consistent then
                    if not isTier and not ei.variants and priorAmount > 0 then
                        -- ei already holds amount/value from an earlier source without a breakdown:
                        -- seed a placeholder bucket for that part first, so the variant sum keeps
                        -- matching ei.amount (a mismatch would be read as corruption and wiped).
                        -- Reagent tiers get no placeholder; an inconsistent tier breakdown is left
                        -- to RepairCorruptedTierBreakdowns.
                        ei.variants = { [NoVariantKey(ei.quality)] = {
                            amount = priorAmount, sellPrice = ei.sellPrice, ahTotal = priorAhTotal,
                            quality = ei.quality,
                        } }
                    end
                    ei.variants = ei.variants or {}
                    for key, gv in pairs(d.variants) do
                        local egv = ei.variants[key]
                        if not egv then
                            ei.variants[key] = CopyVariant(gv, gv.ahTotal or 0, gv.ahAmount)
                        else
                            if egv.ahAmount ~= nil and gv.ahAmount ~= nil then
                                egv.ahAmount = egv.ahAmount + gv.ahAmount
                            else
                                egv.ahAmount = nil
                            end
                            egv.amount      = (egv.amount or 0) + (gv.amount or 0)
                            egv.itemLink    = gv.itemLink or egv.itemLink
                            egv.quality     = gv.quality  or egv.quality
                            egv.sellPrice   = gv.sellPrice or egv.sellPrice
                            egv.priceItemID = gv.priceItemID or egv.priceItemID
                            -- Add the two sessions' frozen AH totals for this variant -
                            -- never re-price the combined amount at either price.
                            egv.ahTotal = (egv.ahTotal or 0) + (gv.ahTotal or 0)
                        end
                    end
                end
            elseif ei.variants and ns.IsGear(ei) then
                -- ei has a gear breakdown but this source's entry doesn't
                -- (older data, or an earlier repair wiped it) - fold its
                -- contribution into a placeholder bucket instead of just
                -- ei.amount, for the same reason as above: keeps the
                -- variant-sum from ever drifting away from ei.amount.
                -- Reagent tiers never get this treatment (see above).
                local nvKey = NoVariantKey(d.quality)
                local egv = ei.variants[nvKey]
                if not egv then
                    ei.variants[nvKey] = { amount = d.amount or 0, sellPrice = d.sellPrice, ahTotal = d.ahTotal or 0, quality = d.quality }
                else
                    egv.amount    = (egv.amount or 0) + (d.amount or 0)
                    egv.ahTotal   = (egv.ahTotal or 0) + (d.ahTotal or 0)
                    egv.sellPrice = egv.sellPrice or d.sellPrice
                    egv.quality   = egv.quality or d.quality
                end
            end
        end
    end
end
ns.MergeSessionInto = MergeSessionInto

-- Folds a list of sessions (oldest first after sorting) into its first entry,
-- which ends up with the most recent timestamp, and returns it.
local function MergeSessionList(list)
    table.sort(list, function(a, b) return a.timestamp < b.timestamp end)
    local merged = list[1]
    for i = 2, #list do
        MergeSessionInto(merged, list[i], true)
    end
    return merged
end

-- True for a saved item that always counts at vendor price. Entries saved with
-- filterFrozen already had the Vendor-Only filters applied (forced-vendor items
-- carry no AH value), so only the item's own flags count; older entries still
-- follow the live filters.
function ns.IsSavedVendorOnly(d)
    if d.filterFrozen then return d.isBoP or d.canAH == false end
    return ns.IsVendorOnly(d)
end

-- Freezes what the list showed into the AH value of each variant of scaling
-- gear: a variant the list priced at vendor - below the Gear AH Threshold (per
-- item) or worth more at vendor - keeps no AH value, so History shows the same
-- value as the list. useLive: a missing vendor price may be looked up from the
-- item (when saving); otherwise only the stored one counts. Returns true if a
-- variant changed.
function ns.FreezeVariantPrices(d, variants, useLive)
    if not ns.IsGear(d) then return false end
    local changed = false
    for _, gv in pairs(variants) do
        local ah = gv.ahTotal or 0
        if ah > 0 then
            local sp = useLive and ns.VariantSellPrice(gv, d) or gv.sellPrice
            local atVendor = sp and sp > 0 and sp * (gv.amount or 0) > ah
            if atVendor or ns.IsGearThresholdVendorOnly(d, ah, gv.amount) then
                gv.ahTotal, gv.ahAmount = 0, 0
                changed = true
            end
        end
    end
    return changed
end

function ns.SaveCurrentSession()
    local db = NightsFarmtrackerDB
    if not db or not next(db.count or {}) then return end
    if (db.totalTime or 0) < 10 then return end
    if db.sessionHistoryEnabled == false then return end
    if not NightsFarmtrackerAccountDB then NightsFarmtrackerAccountDB = {} end
    if not NightsFarmtrackerAccountDB.sessions then NightsFarmtrackerAccountDB.sessions = {} end
    local sessions = NightsFarmtrackerAccountDB.sessions
    -- Stamped with when the session started (not when it is saved), so the
    -- date History shows and groups by matches the storage day key below.
    local startedAt = db.sessionStartTime or time()
    local newEntry = {
        timestamp=startedAt, duration=math.floor(db.totalTime),
        totalGold=0, totalVendor=0, totalAH=0, items={},
        qAtlas=db.qAtlas or {},
        lootedGold=db.lootedGold or 0,
    }
    for itemID, data in pairs(db.count) do
        local vendor = ns.VendorTotal(data)
        -- For variant items (scaling gear OR reagent quality tiers - see
        -- GetVariants in PriceHelper.lua), freeze every variant's price ONCE
        -- here and derive the item-level AH total as their exact sum, rather
        -- than also calling ns.AHTotal(data) (a second, independent live
        -- price lookup for the same item). Two separate lookups can drift
        -- apart (stale AH-addon cache, a source hiccup between the two
        -- calls) and silently desync the item's header total from its own
        -- variant rows.
        local variantsCopy = CopyVariants(data.variants, data.itemID, true)
        -- Vendor-Only filters (item / category / AH-by-expansion) are frozen
        -- into the entry here: a forced-vendor item is saved without any AH
        -- value, so changing the filters later can't retroactively re-price
        -- this session in History (see BuildSessionCategories).
        local forceVendor = ns.IsForceVendor(data.itemID) or ns.IsForceVendorCategory(data)
            or ns.IsForceVendorExpansion(data)   -- not ns.IsVendorOnly: BoP/canAH are decided separately below
        if forceVendor and variantsCopy then
            for _, gv in pairs(variantsCopy) do gv.ahTotal = 0; gv.ahAmount = 0 end
        elseif variantsCopy then
            ns.FreezeVariantPrices(data, variantsCopy, true)
        end
        local ah
        if forceVendor then
            ah = nil
        elseif variantsCopy then
            local sum, any = 0, false
            for _, gv in pairs(variantsCopy) do
                if (gv.ahTotal or 0) > 0 then sum = sum + gv.ahTotal; any = true end
            end
            ah = any and sum or nil
        else
            ah = ns.AHTotal(data)
            if ah and ns.IsGearThresholdVendorOnly(data, ah, data.amount) then ah = nil end
        end
        local val    = ns.ItemValue(data, vendor, ah) or 0
        -- Item value as History shows it, frozen per item, so merging sessions
        -- priced differently (e.g. filters changed in between) adds up instead of
        -- re-pricing the combined amount at one price. It is the value the list
        -- showed while farming: vendor-only items vendor, below the Gear AH
        -- Threshold vendor, else max(AH, vendor) - for scaling gear per variant
        -- (the variants above were frozen the same way).
        local histAH = (not (forceVendor or data.isBoP or data.canAH == false))
            and ns.HasAnyAH() and db.ahSource ~= "none" and (ah or 0) > 0 and ah or nil
        local histVendor = (vendor or 0) > 0 and vendor or nil
        local histValue  = (histAH and histVendor) and math.max(histAH, histVendor) or histAH or histVendor or 0
        if variantsCopy and ns.IsGear(data) then histValue = val end
        -- Which part of histValue came from the AH price (the whole item
        -- when AH wins, nothing otherwise) - shown in the Detail tooltip.
        local histAHWins = histAH ~= nil and (histVendor == nil or histAH >= histVendor)
        local ahAmount   = histAHWins and (data.amount or 0) or 0
        local ahValue    = histAHWins and histAH or 0
        newEntry.totalGold   = newEntry.totalGold   + val
        newEntry.totalVendor = newEntry.totalVendor + (vendor or 0)
        newEntry.totalAH     = newEntry.totalAH     + (ah or 0)

        local saved = CopyItemFields(data)
        saved.vendorTotal, saved.ahTotal = vendor, ah
        saved.variants, saved.filterFrozen, saved.histValue = variantsCopy, true, histValue
        saved.ahAmount, saved.ahValue = ahAmount, ahValue
        newEntry.items[itemID] = saved
    end
    -- Sessions are stored per calendar day, newest first, keyed by when the
    -- session started (db.sessionStartTime), not when it is reset, so farming past
    -- midnight files under the right day. mergeDaily folds into that day's
    -- existing entry, otherwise a new one is added.
    local todayKey = date("%Y-%m-%d", startedAt)
    local todayList = sessions[todayKey]
    if db.mergeDaily ~= false and todayList and todayList[1] then
        MergeSessionInto(todayList[1], newEntry, true)
    else
        todayList = todayList or {}
        table.insert(todayList, 1, newEntry)
        sessions[todayKey] = todayList
    end

    -- Default mode is "full" (keep every session forever). Only in "compact"
    -- mode does everything outside the current calendar month get folded into
    -- one entry per month right after saving, keeping the list bounded.
    if db.sessionHistoryMode == "compact" then
        ns.CompactOldMonths()
    end
end

------------------------------------------------------------------------
-- Manual merge of all sessions belonging to one calendar day (identified
-- by its "YYYY-MM-DD" storage key). Used when db.mergeDaily was off and the
-- user wants to combine already-saved separate entries afterwards.
------------------------------------------------------------------------
function ns.MergeDaySessions(dayKey)
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    local dayList = sessions and sessions[dayKey]
    if not dayList or #dayList < 2 then return end

    sessions[dayKey] = { MergeSessionList(dayList) }
    ns.RebuildHistory()
end

-- Most recently saved session = the first (newest) entry of the newest day
-- key. ISO-format day keys ("YYYY-MM-DD") sort correctly as plain strings.
-- Returns session, dayKey (nothing if there is no saved session).
function ns.GetNewestSession()
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    local latestKey
    for k in pairs(sessions or {}) do
        if type(k) == "string" and (not latestKey or k > latestKey) then latestKey = k end
    end
    local session = latestKey and sessions[latestKey] and sessions[latestKey][1]
    if session then return session, latestKey end
end

------------------------------------------------------------------------
-- Returns a timestamp for the last calendar day of month "YYYY-MM" (noon,
-- to stay clear of any DST edge cases). Uses the day=0 trick: day 0 of
-- month m+1 normalizes to the last day of month m.
------------------------------------------------------------------------
function ns.EndOfMonthTimestamp(monthKey)
    local y, m = monthKey:match("(%d+)-(%d+)")
    y, m = tonumber(y), tonumber(m)
    return time({year=y, month=m+1, day=0, hour=12})
end

------------------------------------------------------------------------
-- Fold every session outside the current calendar month into a single
-- entry per month. Runs automatically after each save when
-- sessionHistoryMode == "compact" (opt-in; default is "full"). Keeps the
-- saved-variables size bounded no matter how long history is kept, at
-- the cost of per-day detail for past months. The compacted entry is
-- stored under its own end-of-month day key like any other single-day
-- entry - nothing else needs to know it represents a whole month rather
-- than one day (see isMonthCompact for the one place that does).
------------------------------------------------------------------------
function ns.CompactOldMonths()
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    if not sessions or not next(sessions) then return end

    local currentKey = date("%Y-%m")
    local byMonth, oldDays = {}, {}
    for dayKey, dayList in pairs(sessions) do
        local sample = dayList[1]
        if sample and date("%Y-%m", sample.timestamp) ~= currentKey then
            local mKey = date("%Y-%m", sample.timestamp)
            byMonth[mKey] = byMonth[mKey] or {}
            for _, session in ipairs(dayList) do
                table.insert(byMonth[mKey], session)
            end
            oldDays[#oldDays + 1] = dayKey
        end
    end
    if not next(byMonth) then return end

    -- Merge first, drop the old days only when every month is merged: an error
    -- in a merge must not lose the sessions.
    local compacted = {}
    for mKey, list in pairs(byMonth) do
        local merged = MergeSessionList(list)
        merged.timestamp = ns.EndOfMonthTimestamp(mKey)
        merged.isMonthCompact = true
        compacted[date("%Y-%m-%d", merged.timestamp)] = { merged }
    end
    for _, dayKey in ipairs(oldDays) do sessions[dayKey] = nil end
    for dayKey, list in pairs(compacted) do sessions[dayKey] = list end
end

ns.RegisterConfirmDialog("NFT_CONFIRM_MERGE_DAY", "%s", function(_, data) ns.MergeDaySessions(data) end)

------------------------------------------------------------------------
-- Delete all sessions belonging to one calendar month ("YYYY-MM")
------------------------------------------------------------------------
function ns.DeleteMonthSessions(monthKey)
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    if not sessions then return end
    for dayKey, dayList in pairs(sessions) do
        local sample = dayList[1]
        if sample and date("%Y-%m", sample.timestamp) == monthKey then
            sessions[dayKey] = nil
        end
    end
    if NightsFarmtrackerAccountDB.collapsedMonths then
        NightsFarmtrackerAccountDB.collapsedMonths[monthKey] = nil
    end
    ns.RebuildHistory()
end

ns.RegisterConfirmDialog("NFT_CONFIRM_DELETE_MONTH", "%s", function(_, data) ns.DeleteMonthSessions(data) end)

------------------------------------------------------------------------
-- Clear all saved session history — shared by the History window's
-- "Clear All" button and the one-time post-update migration prompt below.
------------------------------------------------------------------------
function ns.ClearAllSessionHistory()
    if not NightsFarmtrackerAccountDB then return end
    NightsFarmtrackerAccountDB.sessions = {}
    ns.RebuildHistory()
end

ns.RegisterConfirmDialog("NFT_CONFIRM_CLEAR_ALL_HISTORY", ns.L["clear_all_history_confirm"],
    function() ns.ClearAllSessionHistory() end)

------------------------------------------------------------------------
-- One-time, account-wide prompt (shown by ns.MaybePromptSessionResetMigration
-- below, called from Main.lua) offering to clear session history saved before
-- the itemLink fix, since those old sessions can't show an accurate tooltip
-- for scaling gear and never will be able to.
------------------------------------------------------------------------
-- hideOnEscape off: explicit choice only, avoid it silently vanishing on login
ns.RegisterConfirmDialog("NFT_CONFIRM_SESSION_RESET_MIGRATION", ns.L["session_reset_migration_text"],
    function() ns.ClearAllSessionHistory() end, { hideOnEscape = false })

-- Called once at PLAYER_LOGIN (see Main.lua). Shows the migration prompt at
-- most once per account, and only if there's actually old session history
-- to reset - an account with no saved sessions has nothing to migrate, so
-- the flag is marked done without ever bothering the player with it.
function ns.MaybePromptSessionResetMigration()
    local accDB = NightsFarmtrackerAccountDB
    if not accDB or accDB.itemLinkMigrationPrompted ~= false then return end
    accDB.itemLinkMigrationPrompted = true
    if accDB.sessions and next(accDB.sessions) then
        StaticPopup_Show("NFT_CONFIRM_SESSION_RESET_MIGRATION")
    end
end

-- AH value, vendor value, row gold and AH/vendor split of one saved variant
-- row (a reagent tier or one item-level group of scaling gear). gv.ahTotal is
-- already the frozen, session-added AH value - never recompute unit price ×
-- amount, so merged sessions with different AH prices sum correctly. Legacy
-- entries saved before that field existed have no ahTotal at all: fall back
-- to a live lookup for those (priceID/link) instead of silently dropping to
-- vendor-only. useAH is false for vendor-only items (no AH lookup at all).
local function VariantRowValue(gv, amount, sellPrice, useAH, priceID, link, hasAH)
    local tAH, tV
    if useAH then
        if (gv.ahTotal or 0) > 0 then
            tAH = gv.ahTotal
        elseif gv.ahTotal == nil and hasAH then
            local p = ns.GetAHPriceForID(priceID, link)
            if p then tAH = p * amount end
        end
    end
    local sp = (sellPrice and sellPrice > 0) and sellPrice or nil
    if sp then tV = sp * amount end
    local tGold = (tAH and tAH > 0) and tAH or tV or 0
    local breakdown
    if useAH and gv.ahAmount ~= nil then
        -- Amount split is known: AH-priced units at their frozen AH total,
        -- the rest at vendor price (mixed sessions).
        local vN = math.max(0, amount - gv.ahAmount)
        local vV = (sp or 0) * vN
        tGold = (tAH or 0) + vV
        breakdown = { ahN = gv.ahAmount, ahV = tAH or 0, vN = vN, vV = vV }
    end
    return tAH, tV, tGold, breakdown
end

-- Amount one Detail row stands for: a reagent tier, an item-level group of
-- scaling gear, or the whole item.
function ns.EntryAmount(entry)
    if entry.isRank then return tonumber(entry.tc) or 0 end
    if entry.isGearVariant then return tonumber(entry.gv.amount) or 0 end
    return tonumber(entry.d.amount) or 0
end

-- Category/item builder used by the Detail window.
local function BuildSessionCategories(session)
    -- Use AH if available, else vendor (same logic as main frame)
    local hasAH = ns.HasAnyAH() and NightsFarmtrackerDB.ahSource ~= "none"

    local qAtlas = session.qAtlas or NightsFarmtrackerDB.qAtlas or {}

    -- Build categories
    local cats, catOrder = {}, {}
    for _, d in pairs(session.items) do
        local cat = ns.CategoryName(d)
        if not cats[cat] then
            cats[cat]={gold=0,items={},classID=d.classID}
            catOrder[#catOrder+1]=cat
        end
        -- Entries saved with filterFrozen already had the Vendor-Only
        -- filters applied at save time (forced-vendor items carry no AH
        -- value), so only the item's own flags count here. Older entries
        -- still follow the live filters.
        local isVendorOnly = ns.IsSavedVendorOnly(d)
        -- A reagent-tier breakdown (item is not Equipment - see ns.IsGear)
        -- that doesn't sum to the item's own amount means GetReagentQualityInfo
        -- mis-tagged a tier at tracking time (see ProcessLoot's guard) - this
        -- saved entry's frozen ahTotal was priced off that same inflated
        -- breakdown, so recompute it live off the item's real amount
        -- instead of trusting the stale, corrupted value. d.vendorTotal is
        -- unaffected (never derived from the tier breakdown).
        -- Classified via ns.IsGear(d), never by a variant key's type.
        local isTier      = d.variants and not ns.IsGear(d)
        local qConsistent = isTier and VariantsSum(d.variants) == d.amount
        local ahTotal = d.ahTotal
        if isTier and not qConsistent and not (d.filterFrozen and (d.ahTotal or 0) == 0) then
            local p = ns.GetAHPriceForID(d.itemID, d.itemLink)
            ahTotal = p and (p * d.amount) or nil
        end

        -- Category total: max(AH,Vendor) per item — vendor-only items (junk, BoP, forceVendor/category, canAH=false) always vendor only.
        -- The Gear AH Threshold is not applied here: SaveCurrentSession froze it
        -- into the saved AH values (variants below it carry no AH value), so
        -- History shows what the list showed while farming.
        local itemAH     = (not isVendorOnly) and hasAH and (ahTotal or 0) > 0 and ahTotal or nil
        local itemVendor = (d.vendorTotal or 0) > 0 and d.vendorTotal or nil
        local itemGold   = (itemAH and itemVendor) and math.max(itemAH, itemVendor) or itemAH or itemVendor or 0
        if d.filterFrozen and d.histValue ~= nil then itemGold = d.histValue end
        cats[cat].gold = cats[cat].gold + itemGold

        if isTier and qConsistent then
            -- Split crafting reagents into per-tier rows (display only).
            -- Split happens regardless of isVendorOnly (matches main HUD);
            -- only the AH lookup itself is skipped for vendor-only items.
            -- The consistency check above guards against stale saved data
            -- where GetReagentQualityInfo mis-tagged a tier and inflated
            -- the breakdown beyond the item's own tracked amount - such
            -- entries fall through to the plain row below instead of
            -- displaying a corrupted count.
            for tier = 1, 3 do
                local gv  = d.variants[tier]
                local tc  = gv and gv.amount or 0
                local tid = gv and gv.priceItemID
                if tc > 0 then
                    local _, _, tGold, breakdown = VariantRowValue(gv, tc, gv.sellPrice,
                        tid and not isVendorOnly, tid, nil, hasAH)
                    if tGold > 0 then
                        local rankIcon = ns.RankBadgeMarkup(qAtlas[tier], tier)
                        cats[cat].items[#cats[cat].items+1] = {
                            name=d.name, d=d, gold=tGold, isRank=true,
                            tier=tier, tc=tc, tid=tid, rankIcon=rankIcon,
                            breakdown=breakdown,
                        }
                    end
                end
            end
        elseif d.variants and not isTier then
            -- Split scaling/Adventurer's gear into per-item-level rows (display only).
            -- Split happens regardless of isVendorOnly (matches main HUD);
            -- only the AH lookup itself is skipped for vendor-only items.
            -- Grouped by displayed (itemLevel, quality) first so two drops that
            -- only differ in a hidden bonus-ID component still show as one
            -- summed row (see GroupGearVariantsForDisplay).
            for _, gv in pairs(ns.GroupGearVariantsForDisplay(d.variants)) do
                if gv.amount > 0 then
                    local _, _, tGold, breakdown = VariantRowValue(gv, gv.amount, ns.VariantSellPrice(gv, d),
                        not isVendorOnly, d.itemID, gv.itemLink, hasAH)
                    if tGold > 0 then
                        cats[cat].items[#cats[cat].items+1] = {
                            name=d.name, d=d, gold=tGold, isGearVariant=true,
                            gv=gv, breakdown=breakdown,
                        }
                    end
                end
            end
        else
            if itemGold > 0 then
                local breakdown
                if d.filterFrozen and d.ahAmount ~= nil and d.histValue ~= nil then
                    breakdown = { ahN = d.ahAmount, ahV = d.ahValue or 0,
                                  vN = math.max(0, (d.amount or 0) - d.ahAmount),
                                  vV = math.max(0, itemGold - (d.ahValue or 0)) }
                end
                cats[cat].items[#cats[cat].items+1] = {name=d.name, d=d, gold=itemGold, isRank=false, rankIcon=ns.RankIconFromLink(d.itemLink), breakdown=breakdown}
            end
        end
    end
    -- Merge Junk into a single "Plunder" row (display-only, see UI.lua).
    -- Applies from the very first Junk item, not just once a 2nd distinct
    -- item shows up.
    if NightsFarmtrackerDB.mergeJunkEntries then
        for _, catName in ipairs(catOrder) do
            local cat = cats[catName]
            if ns.IsJunkCategory(catName) and #cat.items >= 1 then
                local totalAmount = 0
                for _, entry in ipairs(cat.items) do
                    totalAmount = totalAmount + ns.EntryAmount(entry)
                end
                local merged = ns.JunkMergedRecord(totalAmount, cat.gold)
                cat.items = { { name = merged.name, d = merged, gold = cat.gold, isRank = false } }
            end
        end
    end

    table.sort(catOrder, function(a, b)
        return ns.CategoryBefore(cats[a].gold, cats[a].classID, cats[b].gold, cats[b].classID)
    end)

    for _, catName in ipairs(catOrder) do
        table.sort(cats[catName].items, function(a,b)
            if a.gold ~= b.gold then return a.gold > b.gold end
            return a.name < b.name
        end)
    end

    return cats, catOrder
end
ns.BuildSessionCategories = BuildSessionCategories
