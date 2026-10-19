------------------------------------------------------------------------
-- Night's Farmtracker - Sessions
-- Saved-session data model: saving the live session, merging and compacting
-- sessions, re-pricing, deleting, and the category builder behind the
-- Detail window. The windows themselves live in Modules/History.lua.
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

-- Calls fn(session) for every saved session, whether the table is still the
-- old flat array or the current day-keyed one (sessions["YYYY-MM-DD"] = a
-- list of that day's sessions). Order is not defined: callers that need
-- newest-first (RebuildHistory) sort the day keys themselves.
function ns.ForEachSession(sessions, fn)
    if not sessions then return end
    if sessions[1] ~= nil and type(sessions[1]) == "table" and sessions[1].timestamp ~= nil then
        for _, session in ipairs(sessions) do fn(session) end
    else
        for _, dayList in pairs(sessions) do
            for _, session in ipairs(dayList) do fn(session) end
        end
    end
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
        copy[key] = { amount = gv.amount, quality = gv.quality, itemLevel = gv.itemLevel,
                      itemLink = gv.itemLink, sellPrice = gv.sellPrice, ahTotal = ahTotal,
                      priceItemID = gv.priceItemID, ahAmount = ahAmount }
    end
    return copy
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
            target.items[itemID] = {
                amount=d.amount, icon=d.icon, quality=d.quality, itemSubType=d.itemSubType,
                sellPrice=d.sellPrice, vendorTotal=d.vendorTotal or 0, ahTotal=d.ahTotal or 0,
                isVendorTrash=d.isVendorTrash, isBoE=d.isBoE, isBoP=d.isBoP, isBoA=d.isBoA, canAH=d.canAH,
                isCosmetic=d.isCosmetic, name=d.name,
                classID=d.classID, subClassID=d.subClassID, itemID=d.itemID, itemLink=d.itemLink,
                variants=CopyVariants(d.variants, d.itemID, false),
                filterFrozen=d.filterFrozen, histValue=d.histValue,
                ahAmount=d.ahAmount, ahValue=d.ahValue,
            }
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
                            ei.variants[key] = { amount = gv.amount, quality = gv.quality,
                                itemLevel = gv.itemLevel, itemLink = gv.itemLink, sellPrice = gv.sellPrice,
                                ahTotal = gv.ahTotal or 0, priceItemID = gv.priceItemID,
                                ahAmount = gv.ahAmount }
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

-- Sessions saved before the timestamp became the real start time carry the
-- save (Reset) time, so a session farmed on day A and reset on day B sits
-- under key A but shows up under day B in the History window, which groups
-- by timestamp. Pull such timestamps back onto their storage day (noon;
-- the time of day isn't known). Returns how many were fixed.
function ns.RepairSessionTimestampsToDayKey(sessions)
    if not sessions then return 0 end
    local fixed = 0
    for dayKey, list in pairs(sessions) do
        local y, m, d
        if type(dayKey) == "string" and type(list) == "table" then
            y, m, d = dayKey:match("^(%d+)-(%d+)-(%d+)$")
        end
        if y then
            local noon = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
            for _, session in ipairs(list) do
                if session.timestamp and date("%Y-%m-%d", session.timestamp) ~= dayKey then
                    session.timestamp = noon
                    fixed = fixed + 1
                end
            end
        end
    end
    return fixed
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
            or ns.IsForceVendorExpansion(data)
        if forceVendor and variantsCopy then
            for _, gv in pairs(variantsCopy) do gv.ahTotal = 0; gv.ahAmount = 0 end
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
        end
        local val    = ns.ItemValue(data, vendor, ah) or 0
        -- Item value as History shows it (same rule as BuildSessionCategories:
        -- vendor-only items vendor, else max(AH, vendor); no Gear AH
        -- Threshold) frozen per item, so merging sessions priced differently
        -- (e.g. filters changed in between) adds up instead of re-pricing
        -- the combined amount at one price.
        local histAH = (not (forceVendor or data.isBoP or data.canAH == false))
            and ns.HasAnyAH() and db.ahSource ~= "none" and (ah or 0) > 0 and ah or nil
        local histVendor = (vendor or 0) > 0 and vendor or nil
        local histValue  = (histAH and histVendor) and math.max(histAH, histVendor) or histAH or histVendor or 0
        -- Which part of histValue came from the AH price (the whole item
        -- when AH wins, nothing otherwise) - shown in the Detail tooltip.
        local histAHWins = histAH ~= nil and (histVendor == nil or histAH >= histVendor)
        local ahAmount   = histAHWins and (data.amount or 0) or 0
        local ahValue    = histAHWins and histAH or 0
        newEntry.totalGold   = newEntry.totalGold   + val
        newEntry.totalVendor = newEntry.totalVendor + (vendor or 0)
        newEntry.totalAH     = newEntry.totalAH     + (ah or 0)

        newEntry.items[itemID] = {
            amount=data.amount, icon=data.icon, quality=data.quality,
            itemSubType=data.itemSubType, sellPrice=data.sellPrice,
            vendorTotal=vendor, ahTotal=ah,
            isVendorTrash=data.isVendorTrash, isBoE=data.isBoE, isBoP=data.isBoP,
            isBoA=data.isBoA, canAH=data.canAH, isCosmetic=data.isCosmetic, name=data.name,
            classID=data.classID, subClassID=data.subClassID, itemID=data.itemID, itemLink=data.itemLink,
            variants=variantsCopy, filterFrozen=true, histValue=histValue,
            ahAmount=ahAmount, ahValue=ahValue,
        }
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

    -- No hard cap on session count anymore. Default is "full" (keep every
    -- session forever). Only in "compact" mode does everything outside the
    -- current calendar month get folded into one entry per month right
    -- after saving, keeping the list bounded.
    if db.sessionHistoryMode == "compact" then
        ns.CompactOldMonths()
    end
end

------------------------------------------------------------------------
-- Manual merge of all sessions belonging to one calendar day (identified
-- by its "YYYY-MM-DD" storage key). Used when "merge_daily_sessions" was
-- off and the user wants to combine already-saved separate entries
-- afterwards.
------------------------------------------------------------------------
function ns.MergeDaySessions(dayKey)
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    local dayList = sessions and sessions[dayKey]
    if not dayList or #dayList < 2 then return end

    table.sort(dayList, function(a,b) return a.timestamp < b.timestamp end)
    local merged = dayList[1]
    for i = 2, #dayList do
        MergeSessionInto(merged, dayList[i], true) -- keep most recent timestamp
    end
    sessions[dayKey] = { merged }
    ns.RebuildHistory()
end

------------------------------------------------------------------------
-- Re-prices a saved session whose AH prices are wrong or missing (the relog
-- save can run before the AH addon answers or the item cache is warm). Every
-- AH-priced item/variant gets the current price for its exact link. Vendor-only
-- items and items whose data is not loaded yet are skipped; a second run picks
-- those up. Idempotent while the AH data stays the same. Returns: re-priced
-- items, items still without AH price, skipped items, gold change.
------------------------------------------------------------------------
local function LinkCached(link)
    return link == nil or C_Item.GetItemInfo(link) ~= nil
end

-- Session-total value of one saved item, the way SaveCurrentSession's
-- ns.ItemValue call saw it: vendor-only items at vendor price, gear per
-- variant with the Gear AH Threshold (below it = vendor price), the rest
-- max(AH, vendor). Same rules as ns.ItemValue, but on the frozen AH values
-- instead of live lookups. (The per-item histValue deliberately ignores
-- the threshold, see BuildSessionCategories - only session.totalGold uses it.)
local function FrozenItemValue(d)
    local vendor = (d.vendorTotal or 0) > 0 and d.vendorTotal or nil
    if d.isBoP or d.canAH == false or ns.IsForceVendor(d.itemID)
       or ns.IsForceVendorCategory(d) or ns.IsForceVendorExpansion(d) then
        return vendor or ns.VendorTotal(d) or 0
    end
    if d.variants and ns.IsGear(d) then
        local total = 0
        for _, gv in pairs(d.variants) do
            local sp = ns.VariantSellPrice(gv, d)
            local v  = (sp and sp > 0 and gv.amount) and sp * gv.amount or nil
            local a  = (gv.ahTotal or 0) > 0 and gv.ahTotal or nil
            if ns.IsGearThresholdVendorOnly(d, a) then total = total + (v or a or 0)
            elseif a and v then total = total + math.max(a, v)
            else total = total + (a or v or 0) end
        end
        return total
    end
    local a = (d.ahTotal or 0) > 0 and d.ahTotal or nil
    if ns.IsGearThresholdVendorOnly(d, a) then return vendor or a or 0 end
    if a and vendor then return math.max(a, vendor) end
    return a or vendor or 0
end

function ns.RepairSessionAHPrices(session)
    local db = NightsFarmtrackerDB
    if not session or not session.items or db.ahSource == "none" or not ns.HasAnyAH() then
        return 0, 0, 0, 0
    end
    local fixed, missing, skipped = 0, 0, 0
    for _, d in pairs(session.items) do
        if not (d.isBoP or d.canAH == false or ns.IsForceVendor(d.itemID)
                or ns.IsForceVendorCategory(d) or ns.IsForceVendorExpansion(d)) then
            local oldAH, newAH, changed, skip, cut = d.ahTotal or 0, 0, false, false, false
            local gear = ns.IsGearThresholdApplicable(d)
            if d.variants then
                for _, gv in pairs(d.variants) do
                    if (gv.amount or 0) > 0 then
                        if not LinkCached(gv.itemLink) then
                            skip = true
                        else
                            local ap = ns.GetAHPriceForID(gv.priceItemID or d.itemID, gv.itemLink)
                            local total = ap and ap * gv.amount or (gv.ahTotal or 0)
                            -- Gear AH Threshold: a variant below it is vendor-priced
                            -- (frozen like a Vendor-Only item), per variant as in ns.GearVariantItemValue
                            if gear and total > 0 and ns.IsGearThresholdVendorOnly(d, total) then
                                total, cut = 0, true
                            end
                            if total ~= (gv.ahTotal or 0) then changed = true end
                            gv.ahTotal  = total
                            gv.ahAmount = total > 0 and gv.amount or 0
                        end
                    end
                    newAH = newAH + (gv.ahTotal or 0)
                end
            elseif (d.amount or 0) > 0 then
                if not LinkCached(d.itemLink) then
                    skip = true
                else
                    local ap = ns.GetAHPriceForID(d.itemID, d.itemLink)
                    newAH = ap and ap * d.amount or oldAH
                    if gear and newAH > 0 and ns.IsGearThresholdVendorOnly(d, newAH) then
                        newAH, cut = 0, true
                    end
                end
            end
            if skip then skipped = skipped + 1 end
            if newAH ~= oldAH then changed = true end
            if changed then
                d.ahTotal = newAH > 0 and newAH or nil
                if d.variants then
                    local n, v = 0, 0
                    for _, gv in pairs(d.variants) do
                        n = n + (gv.ahAmount or 0)
                        v = v + (gv.ahTotal or 0)
                    end
                    if d.ahAmount ~= nil then d.ahAmount = n end
                    if d.ahValue  ~= nil then d.ahValue  = v end
                else
                    local vendor = (d.vendorTotal or 0) > 0 and d.vendorTotal or nil
                    local ahWins = newAH > 0 and (vendor == nil or newAH >= vendor)
                    if d.ahAmount ~= nil then d.ahAmount = ahWins and (d.amount or 0) or 0 end
                    if d.ahValue  ~= nil then d.ahValue  = ahWins and newAH or 0 end
                end
                -- History value rule: max(AH, vendor), vendor where the threshold cut the AH price
                if d.histValue ~= nil then d.histValue = FrozenItemValue(d) end
                fixed = fixed + 1
            elseif newAH == 0 and not skip and not cut then
                missing = missing + 1
            end
        end
    end
    -- Session totals from the (now corrected) items. Done as a full sum, not
    -- as deltas, so the Gear AH Threshold stays in (see FrozenItemValue) and
    -- an earlier partial repair can't leave the total out of step.
    local oldTotal = session.totalGold or 0
    local totalGold, totalAH = 0, 0
    for _, d in pairs(session.items) do
        totalGold = totalGold + FrozenItemValue(d)
        totalAH   = totalAH + ((d.ahTotal or 0) > 0 and d.ahTotal or 0)
    end
    session.totalGold, session.totalAH = totalGold, totalAH
    return fixed, missing, skipped, totalGold - oldTotal
end

-- Re-prices the newest saved session (ns.GetNewestSession). Run via /nft repairprices.
function ns.RepairLastSessionPrices()
    local L = ns.L
    local session, dayKey = ns.GetNewestSession()
    if not session then
        ns.Print(L["repair_prices_nosession"])
        return
    end
    if not ns.HasAnyAH() or NightsFarmtrackerDB.ahSource == "none" then
        ns.Print(L["repair_prices_noah"])
        return
    end
    local fixed, missing, skipped, gained = ns.RepairSessionAHPrices(session)
    ns.Print(L["repair_prices_done"]:format(
        dayKey, fixed, (gained < 0 and "-" or "+") .. ns.FormatGold(math.abs(gained)), missing, skipped))
    if ns.RebuildHistory then ns.RebuildHistory() end
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
    local byMonth = {}
    for dayKey, dayList in pairs(sessions) do
        local sample = dayList[1]
        if sample and date("%Y-%m", sample.timestamp) ~= currentKey then
            local mKey = date("%Y-%m", sample.timestamp)
            byMonth[mKey] = byMonth[mKey] or {}
            for _, session in ipairs(dayList) do
                table.insert(byMonth[mKey], session)
            end
            sessions[dayKey] = nil
        end
    end
    if not next(byMonth) then return end

    for mKey, list in pairs(byMonth) do
        table.sort(list, function(a,b) return a.timestamp < b.timestamp end)
        local merged = list[1]
        for i = 2, #list do
            MergeSessionInto(merged, list[i], true) -- keep most recent timestamp
        end
        merged.timestamp = ns.EndOfMonthTimestamp(mKey)
        merged.isMonthCompact = true
        sessions[date("%Y-%m-%d", merged.timestamp)] = { merged }
    end
end

StaticPopupDialogs["NFT_CONFIRM_MERGE_DAY"] = {
    text         = "%s",
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function(_, data) ns.MergeDaySessions(data) end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

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

StaticPopupDialogs["NFT_CONFIRM_DELETE_MONTH"] = {
    text         = "%s",
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function(_, data) ns.DeleteMonthSessions(data) end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

------------------------------------------------------------------------
-- Clear all saved session history — shared by the History window's
-- "Clear All" button and the one-time post-update migration prompt below.
------------------------------------------------------------------------
function ns.ClearAllSessionHistory()
    if not NightsFarmtrackerAccountDB then return end
    NightsFarmtrackerAccountDB.sessions = {}
    ns.RebuildHistory()
end

StaticPopupDialogs["NFT_CONFIRM_CLEAR_ALL_HISTORY"] = {
    text         = ns.L["clear_all_history_confirm"],
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function() ns.ClearAllSessionHistory() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

------------------------------------------------------------------------
-- One-time, account-wide prompt (see ns.MaybePromptSessionResetMigration
-- in Main.lua) offering to clear session history saved before the itemLink fix
-- itemLink fix, since those old sessions can't show an accurate tooltip
-- for scaling gear and never will be able to.
------------------------------------------------------------------------
StaticPopupDialogs["NFT_CONFIRM_SESSION_RESET_MIGRATION"] = {
    text         = ns.L["session_reset_migration_text"],
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function() ns.ClearAllSessionHistory() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = false,  -- explicit choice only, avoid it silently vanishing on login
}

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

-- Category/item builder used by the Detail window.
local function BuildSessionCategories(session)
    -- Use AH if available, else vendor (same logic as main frame)
    local hasAH = ns.HasAnyAH() and NightsFarmtrackerDB.ahSource ~= "none"

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
        local isVendorOnly
        if d.filterFrozen then
            isVendorOnly = d.isBoP or d.canAH == false
        else
            isVendorOnly = ns.IsVendorOnly(d)
        end
        local qAtlas = session.qAtlas or NightsFarmtrackerDB.qAtlas or {}

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
        -- Note: the Gear AH Threshold setting is deliberately NOT applied here.
        -- It's a live-session decision aid ("is this worth listing on the AH
        -- right now") for the main frame only (see ItemHelper.lua/UI.lua) -
        -- History is a record of what was actually tracked, so it always
        -- shows the item's real AH/vendor value regardless of that setting.
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
                    local tAH, tV
                    -- gv.ahTotal is already the frozen, session-added AH
                    -- value for this tier - never recompute unit price × qty,
                    -- so merged sessions with different AH prices sum correctly.
                    -- Legacy entries saved before this field existed have no
                    -- ahTotal at all - fall back to a live lookup for those
                    -- instead of silently dropping to vendor-only.
                    if tid and not isVendorOnly then
                        if (gv.ahTotal or 0) > 0 then
                            tAH = gv.ahTotal
                        elseif gv.ahTotal == nil and hasAH then
                            local p = ns.GetAHPriceForID(tid)
                            if p then tAH = p * tc end
                        end
                    end
                    if gv.sellPrice and gv.sellPrice > 0 then tV = gv.sellPrice * tc end
                    local tGold = (tAH and tAH > 0) and tAH or tV or 0
                    local breakdown
                    if gv.ahAmount ~= nil then
                        -- Amount split is known: AH-priced units at their frozen AH
                        -- total, the rest at vendor price (mixed sessions).
                        local vN = math.max(0, tc - gv.ahAmount)
                        local vV = (gv.sellPrice or 0) * vN
                        tGold = (tAH or 0) + vV
                        breakdown = { ahN = gv.ahAmount, ahV = tAH or 0, vN = vN, vV = vV }
                    end
                    if tGold > 0 then
                        local rankIcon = qAtlas[tier] and CreateAtlasMarkup(qAtlas[tier],ns.RANK_ICON_W,ns.RANK_ICON_H) or ("|cffaaaaaa R"..tier.."|r")
                        cats[cat].items[#cats[cat].items+1] = {
                            name=d.name, d=d, gold=tGold, isRank=true,
                            tier=tier, tc=tc, tid=tid, tAH=tAH, tV=tV, rankIcon=rankIcon,
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
            for ilvl, gv in pairs(ns.GroupGearVariantsForDisplay(d.variants)) do
                if gv.amount > 0 then
                    local tAH, tV
                    -- gv.ahTotal is already the frozen, session-added AH value
                    -- for this variant - never recompute unit price × amount,
                    -- so merged sessions with different AH prices sum correctly.
                    -- Legacy entries saved before this field existed have no
                    -- ahTotal at all - fall back to a live lookup for those
                    -- instead of silently dropping to vendor-only.
                    if not isVendorOnly then
                        if (gv.ahTotal or 0) > 0 then
                            tAH = gv.ahTotal
                        elseif gv.ahTotal == nil and hasAH then
                            local p = ns.GetAHPriceForID(d.itemID, gv.itemLink)
                            if p then tAH = p * gv.amount end
                        end
                    end
                    local sp = ns.VariantSellPrice(gv, d)
                    if sp and sp > 0 then tV = sp * gv.amount end
                    local tGold = (tAH and tAH > 0) and tAH or tV or 0
                    local breakdown
                    if gv.ahAmount ~= nil then
                        local vN = math.max(0, gv.amount - gv.ahAmount)
                        local vV = ((sp and sp > 0) and sp or 0) * vN
                        tGold = (tAH or 0) + vV
                        breakdown = { ahN = gv.ahAmount, ahV = tAH or 0, vN = vN, vV = vV }
                    end
                    if tGold > 0 then
                        cats[cat].items[#cats[cat].items+1] = {
                            name=d.name, d=d, gold=tGold, isGearVariant=true,
                            ilvl=ilvl, gv=gv, tAH=tAH, tV=tV, breakdown=breakdown,
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
                    local ed = entry.d
                    totalAmount = totalAmount + (ed.amount or (entry.gv and entry.gv.amount) or 0)
                end
                local merged = ns.JunkMergedRecord(totalAmount, cat.gold)
                cat.items = { { name = merged.name, d = merged, gold = cat.gold, isRank = false } }
            end
        end
    end

    table.sort(catOrder, function(a,b)
        if cats[a].gold ~= cats[b].gold then return cats[a].gold > cats[b].gold end
        local oa = (cats[a].classID and ns.CLASS_PRIORITY[cats[a].classID]) or 50
        local ob = (cats[b].classID and ns.CLASS_PRIORITY[cats[b].classID]) or 50
        return oa < ob
    end)

    for _, catName in ipairs(catOrder) do
        table.sort(cats[catName].items, function(a,b)
            if a.gold ~= b.gold then return a.gold > b.gold end
            return a.name < b.name
        end)
    end

    return cats, catOrder, hasAH
end
ns.BuildSessionCategories = BuildSessionCategories
