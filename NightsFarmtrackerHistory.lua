------------------------------------------------------------------------
-- Night's Farmtracker - History
-- Narrower windows. Detail matches main frame width & single-line rows.
------------------------------------------------------------------------
local _, ns = ...
local ART = ns.ART

------------------------------------------------------------------------
-- Layout — history list
------------------------------------------------------------------------
local H_W      = ns.FRAME_W
local H_PAD    = 10
local H_HDR_H  = ns.WINDOW_HDR_H
local H_FTR_H  = 28
local DAY_H    = ns.CAT_ROW_H
local MONTH_H  = ns.CAT_ROW_H
local SESS_H   = 38
local MAX_VIS_H = 10 * SESS_H

------------------------------------------------------------------------
-- Layout — detail window (matches main frame width)
------------------------------------------------------------------------
local DET_W      = ns.FRAME_W          -- same as main frame
local DET_PAD    = ns.PAD
local DET_HDR_H  = ns.WINDOW_HDR_H
local DET_FTR_H  = 30
local DET_CONT_W = ns.CONTENT_W
local DET_CAT_H  = ns.CAT_ROW_H
local DET_ROW_H  = ns.ROW_H
local DET_MAX_H  = ns.MAX_ROWS * DET_ROW_H

------------------------------------------------------------------------
-- Session save
------------------------------------------------------------------------

-- itemID/snapshotAH are only passed when copying straight from the LIVE
-- session (fresh SaveCurrentSession); the AH value for this session's
-- amount of this variant is looked up ONCE and frozen into gv.ahTotal
-- (a gold total, not a unit price). When copying from an already-saved
-- history entry (merge), no lookup is done - the existing ahTotal is
-- carried through as-is, so later AH scans/price changes can't
-- retroactively alter it, AND merging two sessions with different
-- market prices for the same item correctly ADDS the two frozen totals
-- instead of re-pricing the combined amount at either session's price.
-- Synthetic gearVariants key used by MergeSessionInto below to absorb an
-- item's amount/value when one side of a merge has no per-variant
-- breakdown at all, so the variant-sum never drifts from the item's own
-- amount (which RepairCorruptedTierBreakdowns would otherwise mistake for
-- corruption and wipe the whole, otherwise-fine, breakdown).
-- Keyed per quality (not a single shared key) so two sessions that both
-- lack a full itemLevel breakdown, but dropped at DIFFERENT qualities
-- (e.g. a q2/ilvl253 and a q3/ilvl266 roll of the same scaling item),
-- don't collapse into one bucket that can only remember ONE quality.
-- Before this fix "quality = egv.quality or gv.quality" kept whichever
-- session was merged FIRST and silently mis-attributed every later
-- session's amount to that quality - i.e. the split between item-level
-- rows depended on session order instead of each session's own logged
-- quality (see BuildMonthAggregate, which rebuilds this merge fresh from
-- session order every time the month view opens).
local function NoVariantKey(quality)
    return "__novariant__" .. tostring(quality or "?")
end

-- Iterates every individual session in NightsFarmtrackerAccountDB.sessions,
-- regardless of whether it's still the old flat array (pre-1.6.x, sessions[1],
-- sessions[2], ...) or the current day-keyed table of per-day arrays
-- (sessions["YYYY-MM-DD"] = { session1, session2, ... }) - so every repair
-- can iterate sessions without caring which storage shape it finds. Order is
-- NOT guaranteed for the day-keyed shape (table iteration order is
-- undefined) - callers that need newest-first order (RebuildHistory) build
-- their own sorted day-key list instead of using this.
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

-- Freezes a live entry.variants table (gear-keyed or reagent-tier-keyed -
-- see GetVariants in PriceHelper.lua) into a saved-session copy, same
-- reasoning as the old per-type freeze: each variant's AH value is looked
-- up ONCE here and frozen into gv.ahTotal (a gold total, not a unit
-- price), so a later AH scan/price change can't retroactively alter it.
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
                -- Reagent-tier variants (item is not Equipment) only merge
                -- when their own amounts are internally consistent with d's
                -- own amount - never sum a corrupted breakdown into the
                -- target, or the corruption compounds with every future
                -- same-day merge instead of staying contained to its source.
                -- Gear variants have no such gate. Classified via ns.IsGear(d),
                -- never by a variant key's type (mixed-type keys have an
                -- undefined pairs() order).
                local isTier   = not ns.IsGear(d)
                local consistent = (not isTier) or (VariantsSum(d.variants) == (d.amount or 0))
                if consistent then
                    if not isTier and not ei.variants and priorAmount > 0 then
                        -- ei already accumulated amount/value from an earlier
                        -- source that had no variant breakdown at all (see
                        -- the elseif below) - seed a placeholder bucket for
                        -- that portion FIRST, so the variant-sum keeps
                        -- matching ei.amount once d's real variants are
                        -- merged in below, instead of quietly under-
                        -- accounting for it (which the next repair pass
                        -- would then read as corruption and wipe the whole,
                        -- otherwise fine, breakdown). Reagent tiers never get
                        -- this placeholder (matches pre-unified behavior) -
                        -- an inconsistent tier breakdown is left to drift and
                        -- gets wiped by RepairCorruptedTierBreakdowns instead.
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

function ns.SaveCurrentSession()
    local db = NightsFarmtrackerDB
    if not db or not next(db.count or {}) then return end
    if (db.totalTime or 0) < 10 then return end
    if db.sessionHistoryEnabled == false then return end
    if not NightsFarmtrackerAccountDB then NightsFarmtrackerAccountDB = {} end
    if not NightsFarmtrackerAccountDB.sessions then NightsFarmtrackerAccountDB.sessions = {} end
    local sessions = NightsFarmtrackerAccountDB.sessions
    local newEntry = {
        timestamp=time(), duration=math.floor(db.totalTime),
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
    -- Sessions are stored one array per calendar day
    -- (sessions["YYYY-MM-DD"] = { session1, session2, ... }, newest first
    -- within the day) so the raw SavedVariables file reads day-by-day
    -- instead of one long undated array. Keyed by when the session actually
    -- started (db.sessionStartTime, stamped in ns.StartTimer), not by
    -- "today" - otherwise a session farmed before midnight lands under the
    -- day it happens to be reset on instead of the day it ran. mergeDaily
    -- folds into that day's existing entry if there is one; otherwise a new
    -- one is added.
    local todayKey = date("%Y-%m-%d", db.sessionStartTime or newEntry.timestamp)
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
    text         = ns.L and ns.L["clear_all_history_confirm"] or "Delete all saved session history? This cannot be undone.",
    button1      = OKAY,
    button2      = CANCEL,
    OnAccept     = function() ns.ClearAllSessionHistory() end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

------------------------------------------------------------------------
-- One-time, account-wide prompt (see ns.MaybePromptSessionResetMigration
-- in Main.lua) offering to clear session history saved before the 1.3.0
-- itemLink fix, since those old sessions can't show an accurate tooltip
-- for scaling gear and never will be able to.
------------------------------------------------------------------------
StaticPopupDialogs["NFT_CONFIRM_SESSION_RESET_MIGRATION"] = {
    text         = ns.L and ns.L["session_reset_migration_text"] or "Clear all saved session history?",
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

------------------------------------------------------------------------
-- Frame references
------------------------------------------------------------------------
local HistFrame, HScrollFrame, HListFrame
local DetailFrame, DScrollFrame, DListFrame

------------------------------------------------------------------------
-- History list row pools
------------------------------------------------------------------------
local activeSessRows={} local activeDayRows={} local sessPool={} local dayPool={}

local function AcquireSessRow()
    local r=table.remove(sessPool)
    if r then r:SetParent(HListFrame); r:Show(); return r end
    r=CreateFrame("Frame",nil,HListFrame); r:SetHeight(SESS_H); r:EnableMouse(true)
    r.bg=r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1,1,1,0.05); r.bg:Hide()
    r.sep=r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1)
    r.sep:SetColorTexture(0.18,0.28,0.30,0.55); r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT")
    -- Single-line: [Dauer] [Gold] [X]
    r.dateText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.dateText:SetPoint("LEFT",6,0); r.dateText:SetTextColor(0.9,0.9,0.9); r.dateText:SetFontHeight(ns.FONT_NORMAL)
    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",-22,0); r.goldText:SetJustifyH("RIGHT"); r.goldText:SetFontHeight(ns.FONT_NORMAL)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    r.delBtn=CreateFrame("Button",nil,r); r.delBtn:SetSize(18,18); r.delBtn:SetPoint("RIGHT",-2,0)
    local delTex=r.delBtn:CreateTexture(nil,"ARTWORK"); delTex:SetAllPoints()
    delTex:SetTexture(ART.."btn_close.png"); delTex:SetAlpha(0.5)
    r.delBtn:SetScript("OnEnter",function() delTex:SetAlpha(1)
        GameTooltip:SetOwner(r.delBtn,"ANCHOR_TOP"); GameTooltip:SetText(ns.L["delete_session"]); GameTooltip:Show() end)
    r.delBtn:SetScript("OnLeave",function() delTex:SetAlpha(0.5); GameTooltip:Hide() end)
    r:SetScript("OnEnter",function(self)
        self.bg:Show(); self.dateText:SetTextColor(unpack(ns.COL_GOLD))
        local sess = self.session
        local lg = sess and (sess.lootedGold or 0) or 0
        if lg > 0 then
            local itemGold = sess.totalGold or 0
            GameTooltip:SetOwner(self,"ANCHOR_LEFT")
            GameTooltip:AddLine(ns.L["gold_overview"], unpack(ns.COL_ACCENT))
            GameTooltip:AddDoubleLine(ns.L["gold_items"], ns.FormatGold(itemGold), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["looted_gold"], ns.FormatGold(lg), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["gold_total"], ns.FormatGold(itemGold+lg), 0.75,0.75,0.75, unpack(ns.COL_GOLD))
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave",function(self) self.bg:Hide(); self.dateText:SetTextColor(0.9,0.9,0.9); GameTooltip:Hide() end)
    return r
end
local function ReleaseSessRow(r)
    r:Hide(); r:ClearAllPoints(); r.sessionIdx=nil; r.session=nil; r:SetScript("OnMouseUp",nil); sessPool[#sessPool+1]=r
end

local function AcquireDayRow()
    local r=table.remove(dayPool)
    if r then r:SetParent(HListFrame); r:Show(); return r end
    r=CreateFrame("Frame",nil,HListFrame); r:SetHeight(DAY_H); r:EnableMouse(true)
    r.bg=r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(unpack(ns.COL_CAT_BG))
    r.topSep=r:CreateTexture(nil,"ARTWORK"); r.topSep:SetHeight(1); r.topSep:SetColorTexture(unpack(ns.COL_BORDER))
    r.topSep:SetPoint("TOPLEFT"); r.topSep:SetPoint("TOPRIGHT")
    r.sep=r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1); r.sep:SetColorTexture(unpack(ns.COL_BORDER))
    r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT")
    r.dateText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.dateText:SetPoint("LEFT",4,0); r.dateText:SetFontHeight(ns.FONT_NORMAL); r.dateText:SetTextColor(unpack(ns.COL_ACCENT))
    r.infoText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.infoText:SetPoint("LEFT",r.dateText,"RIGHT",10,0); r.infoText:SetFontHeight(ns.FONT_SMALL); r.infoText:SetTextColor(0.45,0.45,0.45)
    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",0,0); r.goldText:SetJustifyH("RIGHT"); r.goldText:SetFontHeight(ns.FONT_NORMAL)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))

    r.mergeBtn = CreateFrame("Button", nil, r)
    r.mergeBtn:SetSize(40, DAY_H - 4)
    r.mergeBtn:SetPoint("RIGHT", r.goldText, "LEFT", -8, 0)
    r.mergeBtn.text = r.mergeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.mergeBtn.text:SetAllPoints(); r.mergeBtn.text:SetJustifyH("RIGHT")
    r.mergeBtn.text:SetFontHeight(ns.FONT_SMALL); r.mergeBtn.text:SetTextColor(unpack(ns.COL_ACCENT))
    r.mergeBtn.text:SetText(ns.L["merge_day_btn"])
    r.mergeBtn:SetScript("OnEnter", function()
        r.mergeBtn.text:SetTextColor(1,1,1)
        GameTooltip:SetOwner(r.mergeBtn,"ANCHOR_TOP"); GameTooltip:SetText(ns.L["merge_day_tooltip"]); GameTooltip:Show()
    end)
    r.mergeBtn:SetScript("OnLeave", function()
        r.mergeBtn.text:SetTextColor(unpack(ns.COL_ACCENT)); GameTooltip:Hide()
    end)
    r.mergeBtn:Hide()
    return r
end
local function ReleaseDayRow(r)
    r:Hide(); r:ClearAllPoints()
    r:SetScript("OnMouseUp",nil); r:SetScript("OnEnter",nil); r:SetScript("OnLeave",nil)
    r.dateText:SetTextColor(unpack(ns.COL_ACCENT))
    r.mergeBtn:Hide(); r.mergeBtn:SetScript("OnClick", nil)
    dayPool[#dayPool+1]=r
end

------------------------------------------------------------------------
-- Month header row pool (collapsible grouping for past months)
------------------------------------------------------------------------
local activeMonthRows={} local monthPool={}

local function AcquireMonthRow()
    local r=table.remove(monthPool)
    if r then r:SetParent(HListFrame); r:Show(); return r end
    r=CreateFrame("Frame",nil,HListFrame); r:SetHeight(MONTH_H); r:EnableMouse(true)
    r.bg=r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(unpack(ns.COL_CAT_BG))
    r.topSep=r:CreateTexture(nil,"ARTWORK"); r.topSep:SetHeight(1); r.topSep:SetColorTexture(unpack(ns.COL_BORDER))
    r.topSep:SetPoint("TOPLEFT"); r.topSep:SetPoint("TOPRIGHT")
    r.sep=r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1); r.sep:SetColorTexture(unpack(ns.COL_BORDER))
    r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT")
    r.arrow = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.arrow:SetPoint("LEFT",4,0); r.arrow:SetFontHeight(ns.FONT_NORMAL); r.arrow:SetTextColor(unpack(ns.COL_ACCENT))
    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",r.arrow,"RIGHT",4,0); r.nameText:SetFontHeight(ns.FONT_NORMAL)
    r.nameText:SetTextColor(unpack(ns.COL_ACCENT))
    r.delBtn=CreateFrame("Button",nil,r); r.delBtn:SetSize(18,18); r.delBtn:SetPoint("RIGHT",-2,0)
    local mDelTex=r.delBtn:CreateTexture(nil,"ARTWORK"); mDelTex:SetAllPoints()
    mDelTex:SetTexture(ART.."btn_close.png"); mDelTex:SetAlpha(0.5)
    r.delBtn:SetScript("OnEnter",function() mDelTex:SetAlpha(1)
        GameTooltip:SetOwner(r.delBtn,"ANCHOR_TOP"); GameTooltip:SetText(ns.L["delete_month"]); GameTooltip:Show() end)
    r.delBtn:SetScript("OnLeave",function() mDelTex:SetAlpha(0.5); GameTooltip:Hide() end)
    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",r.delBtn,"LEFT",-6,0); r.goldText:SetJustifyH("RIGHT"); r.goldText:SetFontHeight(ns.FONT_NORMAL)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    r:SetScript("OnEnter",function(self) self.nameText:SetTextColor(1,1,1) end)
    r:SetScript("OnLeave",function(self) self.nameText:SetTextColor(unpack(ns.COL_ACCENT)); GameTooltip:Hide() end)
    return r
end
local function ReleaseMonthRow(r)
    r:Hide(); r:ClearAllPoints(); r:SetScript("OnMouseUp",nil)
    r:SetScript("OnEnter",nil); r:SetScript("OnLeave",nil)
    r.delBtn:SetScript("OnClick",nil)
    r.nameText:SetTextColor(unpack(ns.COL_ACCENT))
    monthPool[#monthPool+1]=r
end

------------------------------------------------------------------------
-- Detail row pools — single-line, same as main frame
------------------------------------------------------------------------
local activeDetRows = {}
local activeDetCats = {}
local detRowPool    = {}
local detCatPool    = {}
local detCollapsed  = {}
local currentDetailSession = nil

local function AcquireDetRow()
    local r = table.remove(detRowPool)
    if r then r:SetParent(DListFrame); r:Show(); return r end
    r = CreateFrame("Frame", nil, DListFrame)
    r:SetSize(DET_CONT_W, DET_ROW_H)
    r:EnableMouse(true)

    r.sep = r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1)
    r.sep:SetColorTexture(0.12,0.22,0.25,0.5)
    r.sep:SetPoint("BOTTOMLEFT",0,0); r.sep:SetPoint("BOTTOMRIGHT",0,0)

    r.icon = r:CreateTexture(nil,"ARTWORK")
    r.icon:SetSize(ns.ICON_SIZE, ns.ICON_SIZE)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.iconBorder = r:CreateTexture(nil,"BACKGROUND")
    r.iconBorder:SetPoint("TOPLEFT",     r.icon,"TOPLEFT",     -1,  1)
    r.iconBorder:SetPoint("BOTTOMRIGHT", r.icon,"BOTTOMRIGHT",  1, -1)
    r.iconBorder:Hide()

    r.rankBadge = ns.CreateIconBadge(r, r.icon)

    -- Single-line: icon | name | count | gold (y=0 = centered with icon)
    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",  r.rankBadge, "RIGHT", 4,    0)
    r.nameText:SetPoint("RIGHT", r,           "RIGHT", -128, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(ns.FONT_NORMAL); r.nameText:SetWordWrap(false)

    r.countText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.countText:SetPoint("RIGHT", r, "RIGHT", -90, 0)
    r.countText:SetJustifyH("RIGHT"); r.countText:SetTextColor(0.78,0.78,0.78); r.countText:SetFontHeight(ns.FONT_NORMAL)

    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.goldText:SetJustifyH("RIGHT"); r.goldText:SetTextColor(unpack(ns.COL_GOLD)); r.goldText:SetFontHeight(ns.FONT_NORMAL)

    r:SetScript("OnEnter", function(self)
        -- DetailFrame docks LEFT of HistFrame, so its right side is
        -- structurally occupied - prefer LEFT here (see ns.SmartAnchor).
        local anchor = ns.SmartAnchor(self, "LEFT")
        if self.itemLink then
            ns.ShowItemTooltipNoCompare(self, anchor, self.itemLink)
        elseif self.itemID then
            -- Old session saved before the itemLink fix - for equipment,
            -- SetItemByID would show the generic base item (wrong item
            -- level/stats for scaling gear), so show just the name instead
            -- of a tooltip that looks precise but could be misleading.
            local isGear = self.classID == 2 or self.classID == 4
            if isGear then
                GameTooltip:SetOwner(self, anchor)
                GameTooltip:AddLine(self.itemName or "", 1,1,1)
                GameTooltip:AddLine(ns.L["tooltip_scaling_unknown"], 0.6,0.6,0.6, true)
                GameTooltip:Show()
            else
                ns.ShowItemTooltipNoCompare(self, anchor, nil, self.itemID)
            end
        elseif self.itemName then
            GameTooltip:SetOwner(self, anchor)
            GameTooltip:AddLine(self.itemName, 1,1,1)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Hover area over the gold amount: shows how many of the items were
    -- valued at AH price and how many at vendor price (see BuildSessionCategories).
    r.goldHit = CreateFrame("Frame", nil, r)
    r.goldHit:SetPoint("TOPLEFT",     r.goldText, "TOPLEFT",     -4,  2)
    r.goldHit:SetPoint("BOTTOMRIGHT", r.goldText, "BOTTOMRIGHT",  4, -2)
    r.goldHit:EnableMouse(true)
    r.goldHit:Hide()
    r.goldHit:SetScript("OnEnter", function(self)
        local b = r.breakdown
        if not b then return end
        GameTooltip:SetOwner(self, ns.SmartAnchor(r, "LEFT"))
        GameTooltip:AddLine(r.itemName or "", 1, 1, 1)
        if b.ahN > 0 then
            GameTooltip:AddDoubleLine(string.format(ns.L["tip_priced_ah"], b.ahN),
                ns.FormatGold(b.ahV), 0.75,0.75,0.75, 1,1,1)
        end
        if b.vN > 0 then
            GameTooltip:AddDoubleLine(string.format(ns.L["tip_priced_vendor"], b.vN),
                ns.FormatGold(b.vV), 0.75,0.75,0.75, 1,1,1)
        end
        GameTooltip:Show()
    end)
    r.goldHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function ReleaseDetRow(r)
    r:Hide(); r:ClearAllPoints(); r.itemID=nil; r.itemLink=nil; r.classID=nil; r.itemName=nil; r.iconBorder:Hide()
    r.breakdown=nil; r.goldHit:Hide()
    r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", 4, 0)
    r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    r.rankBadge:SetText("")
    detRowPool[#detRowPool+1]=r
end

local function AcquireDetCat()
    local r = table.remove(detCatPool)
    if r then r:SetParent(DListFrame); r:Show(); return r end
    r = CreateFrame("Frame", nil, DListFrame); r:SetHeight(DET_CAT_H)
    r:EnableMouse(true)
    r.bg = r:CreateTexture(nil,"BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(unpack(ns.COL_CAT_BG))
    r.topSep = r:CreateTexture(nil,"ARTWORK"); r.topSep:SetHeight(1); r.topSep:SetColorTexture(unpack(ns.COL_BORDER))
    r.topSep:SetPoint("TOPLEFT"); r.topSep:SetPoint("TOPRIGHT")
    r.sep = r:CreateTexture(nil,"ARTWORK"); r.sep:SetHeight(1); r.sep:SetColorTexture(unpack(ns.COL_BORDER))
    r.sep:SetPoint("BOTTOMLEFT"); r.sep:SetPoint("BOTTOMRIGHT")
    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",4,0); r.nameText:SetPoint("RIGHT",r,"RIGHT",-100,0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(ns.FONT_NORMAL); r.nameText:SetTextColor(unpack(ns.COL_ACCENT))
    r.goldText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.goldText:SetPoint("RIGHT",r,"RIGHT",-4,0); r.goldText:SetJustifyH("RIGHT")
    r.goldText:SetFontHeight(ns.FONT_NORMAL); r.goldText:SetTextColor(unpack(ns.COL_GOLD))
    return r
end
local function ReleaseDetCat(r)
    r:Hide(); r:ClearAllPoints(); r:SetHeight(DET_CAT_H); detCatPool[#detCatPool+1]=r
end

------------------------------------------------------------------------
-- Session detail window
------------------------------------------------------------------------
local function EnsureDetailFrame()
    if DListFrame then return end
    DetailFrame = CreateFrame("Frame","NightsFarmtrackerDetailWnd",UIParent,"BackdropTemplate")
    DetailFrame:SetWidth(DET_W)
    DetailFrame:SetFrameStrata("MEDIUM"); DetailFrame:SetClampedToScreen(true)
    DetailFrame:SetMovable(true); DetailFrame:EnableMouse(true)
    DetailFrame:RegisterForDrag("LeftButton")
    DetailFrame:SetScript("OnDragStart",function(s) s:StartMoving() end)
    DetailFrame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    ns.ApplyFrameStyle(DetailFrame); DetailFrame:Hide()
    ns.DetailFrame = DetailFrame  -- exposed so Settings can close it when it opens
    table.insert(UISpecialFrames,"NightsFarmtrackerDetailWnd")

    -- Header: single line "Date  ·  Duration  ·  Total Gold"
    DetailFrame.dateText = DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    DetailFrame.dateText:SetPoint("TOPLEFT",  DET_PAD, -12)
    DetailFrame.dateText:SetPoint("TOPRIGHT", -DET_PAD, -12)
    DetailFrame.dateText:SetJustifyH("CENTER")
    DetailFrame.dateText:SetTextColor(unpack(ns.COL_GOLD)); DetailFrame.dateText:SetFontHeight(ns.FONT_HEADER)

    -- Invisible hitbox over the header line: hovering the combined total
    -- shows the Items/Direct/Total breakdown instead of a permanent
    -- second line, so the header number and the History list agree.
    -- Right edge stops short of the close button (18px + gap) instead of
    -- matching dateText's full width - otherwise this hitbox sits on top
    -- of the close button and swallows the click meant for it.
    local headerHit = CreateFrame("Frame", nil, DetailFrame)
    headerHit:SetPoint("TOPLEFT", DetailFrame.dateText, "TOPLEFT", 0, 4)
    headerHit:SetPoint("BOTTOMRIGHT", DetailFrame.dateText, "BOTTOMRIGHT", -24, -4)
    headerHit:EnableMouse(true)
    headerHit:SetScript("OnEnter", function(self)
        local session = currentDetailSession
        if not session then return end
        local itemGold = session.totalGold or 0
        local lg       = session.lootedGold or 0
        local total    = itemGold + lg
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L["gold_overview"], unpack(ns.COL_ACCENT))
        GameTooltip:AddDoubleLine(ns.L["detail_duration"], ns.FormatTime(session.duration), 0.75,0.75,0.75, 1,1,1)
        if total > 0 then
            GameTooltip:AddDoubleLine(ns.L["gold_items"], ns.FormatGold(itemGold), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["looted_gold"], ns.FormatGold(lg), 0.75,0.75,0.75, 1,1,1)
            GameTooltip:AddDoubleLine(ns.L["gold_total"], ns.FormatGold(total), 0.75,0.75,0.75, unpack(ns.COL_GOLD))
        end
        GameTooltip:Show()
    end)
    headerHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local hSep = DetailFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT",DET_PAD,-(DET_HDR_H-1)); hSep:SetPoint("TOPRIGHT",-DET_PAD,-(DET_HDR_H-1))

    local xBtn = CreateFrame("Button",nil,DetailFrame); xBtn:SetSize(18,18); xBtn:SetPoint("TOPRIGHT",-DET_PAD,-10)
    local xTex = xBtn:CreateTexture(nil,"ARTWORK"); xTex:SetAllPoints()
    xTex:SetTexture(ART.."btn_close.png"); xTex:SetAlpha(0.8)
    xBtn:SetScript("OnClick",function()
        if not ns.DeferInCombat(function() DetailFrame:Hide() end) then DetailFrame:Hide() end
    end)
    xBtn:SetScript("OnEnter",function() xTex:SetAlpha(1) end)
    xBtn:SetScript("OnLeave",function() xTex:SetAlpha(0.8) end)

    DScrollFrame = CreateFrame("ScrollFrame",nil,DetailFrame)
    DScrollFrame:SetPoint("TOPLEFT",DET_PAD,-DET_HDR_H); DScrollFrame:SetWidth(DET_CONT_W)
    DScrollFrame:EnableMouseWheel(true)
    DListFrame = CreateFrame("Frame",nil,DScrollFrame)
    DListFrame:SetWidth(DET_CONT_W); DListFrame:SetHeight(1)
    DScrollFrame:SetScrollChild(DListFrame)
    local function OnWheel(_,delta)
        local cur=DScrollFrame:GetVerticalScroll()
        local maxS=math.max(0,DListFrame:GetHeight()-DScrollFrame:GetHeight())
        DScrollFrame:SetVerticalScroll(math.max(0,math.min(cur-delta*DET_ROW_H,maxS)))
    end
    DScrollFrame:SetScript("OnMouseWheel",OnWheel)
    DListFrame:EnableMouseWheel(true); DListFrame:SetScript("OnMouseWheel",OnWheel)

    local fSep = DetailFrame:CreateTexture(nil,"ARTWORK"); fSep:SetHeight(1)
    fSep:SetColorTexture(unpack(ns.COL_BORDER))
    fSep:SetPoint("BOTTOMLEFT",DET_PAD,DET_FTR_H-2); fSep:SetPoint("BOTTOMRIGHT",-DET_PAD,DET_FTR_H-2)

    DetailFrame.footLabel = DetailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    DetailFrame.footLabel:SetPoint("BOTTOMLEFT",DET_PAD,10); DetailFrame.footLabel:SetTextColor(0.38,0.38,0.38)
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

------------------------------------------------------------------------
-- One-time cleanup for saved sessions whose per-item breakdown fields got
-- corrupted before the merge-time guards above existed: a reagent-tier
-- breakdown (q/qIDs/qAHTotal) that doesn't sum to the item's own amount, or
-- gearVariants amounts that don't sum to the item's own amount. ns.AHTotal
-- already falls back correctly for a mismatched q at DISPLAY time, but the
-- raw stored numbers (shown on the R1/R2/R3 rows themselves, and re-summed
-- by every future merge) stayed wrong until now - this clears them so nothing
-- inconsistent is left to display or propagate. vendorTotal is recomputed
-- from sellPrice*amount wherever it disagreed. Returns how many items were
-- touched.
function ns.RepairCorruptedTierBreakdowns(sessions)
    if not sessions then return 0 end
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        for _, d in pairs(session.items or {}) do
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
        end
    end)
    return fixed
end

-- One-time repair for the Bind-on-Use canAH fix (see CanAH in Main.lua):
-- items saved before the fix with canAH=false purely because of their
-- bind type (not BoP/BoA, which stay vendor-only) get canAH re-enabled so
-- they price via AH again. Returns how many items were touched.
function ns.RepairBindOnUseCanAH(sessions)
    if not sessions then return 0 end
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        for _, d in pairs(session.items or {}) do
            if d.canAH == false and not d.isBoP and not d.isBoA then
                d.canAH = true
                fixed = fixed + 1
            end
        end
    end)
    return fixed
end

-- One-time repair for gearVariant per-price data. Three schema bugs found
-- in the wild:
--  1. A variant carrying a legacy field `ahPrice` (a PER-UNIT price) instead
--     of the current `ahTotal` (a per-variant TOTAL). Nothing in the current
--     code reads `ahPrice`, so that variant's row had no usable stored
--     price and fell through to a live AH lookup.
--  2. Variants saved with no price field at all (even older saves).
--  3. Every variant DOES have an ahTotal, but they don't sum to the item's
--     own d.ahTotal - SaveCurrentSession used to compute the item-level
--     total and the per-variant totals via two independent live AH
--     lookups, which could drift apart (see the fix there).
-- Cases 1-2: the live lookup targets one exact, often long-gone bonus-ID
-- roll and typically returns nil, so the row silently fell back to vendor
-- price even though the item's overall value was priced correctly via AH.
-- The item-level d.ahTotal is always frozen at save time regardless of how
-- old the entry is, so the true total is known - this converts ahPrice to
-- ahTotal, then splits whatever the item's own ahTotal doesn't already
-- account for across the remaining priceless variants, proportional to
-- their amount, instead of ever re-querying today's price for a stale
-- historical roll.
-- Case 3: rescales every variant's existing price proportionally so they
-- sum back to the item's own ahTotal (treated as ground truth, since
-- that's what every other total in the addon is built from).
-- Returns how many variants were touched.
-- Checks d.variants (current field) with a d.gearVariants fallback for
-- pre-migration data - this used to check ONLY d.gearVariants and had been
-- a no-op for any account already on the unified variants schema since #7
-- renamed the field (see the matching fix in RepairGearVariantItemLevels).
function ns.RepairGearVariantPricing(sessions)
    if not sessions then return 0 end
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        for _, d in pairs(session.items or {}) do
            local variants = d.variants or d.gearVariants
            if variants then
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
                    -- Every variant already carries a price, but they don't sum
                    -- to the item's own frozen total - the item-level total and
                    -- the per-variant prices were computed via two independent
                    -- live AH lookups at save time (see SaveCurrentSession) and
                    -- drifted apart. The item-level total is what every other
                    -- total in the addon is built from, so treat it as ground
                    -- truth and rescale each variant's share to match it.
                    local scale = d.ahTotal / knownTotal
                    for _, gv in pairs(variants) do
                        if (gv.ahTotal or 0) > 0 then
                            gv.ahTotal = gv.ahTotal * scale
                        end
                    end
                    fixed = fixed + 1
                end
            end
        end
    end)
    return fixed
end

-- Fills in a missing itemLevel on a gearVariants bucket (the __novariant__
-- placeholder MergeSessionInto creates for a merge-side with no breakdown
-- at all, or genuinely old data missing the field) from a sibling variant
-- of the SAME quality, using this itemID's full saved history as the
-- source of truth rather than just whatever one session happens to show.
-- Adventurer's/scaling gear ties item level to quality within one source,
-- so if quality 3 has only ever dropped at item level 266 anywhere in the
-- account's history, a quality-3 bucket missing its item level almost
-- certainly was 266 too. A quality that has dropped at more than one item
-- level (a genuinely ambiguous case, e.g. a different source later in the
-- account's history) is left alone rather than guessed. Returns how many
-- variants were touched.
function ns.RepairGearVariantItemLevels(sessions)
    if not sessions then return 0 end

    -- Pass 1: build itemID -> quality -> itemLevel across every session.
    -- A quality mapping to more than one itemLevel is marked ambiguous
    -- (false) and never used to fill anything in.
    -- Checks d.variants (current unified field, see MigrateItemsToUnified-
    -- Variants) with a d.gearVariants fallback for any account whose data
    -- hasn't been through that migration yet - not the other way round,
    -- since this repair used to check ONLY d.gearVariants and silently
    -- did nothing for any account already on the unified schema.
    local ilvlByItemQuality = {}
    ns.ForEachSession(sessions, function(session)
        for itemID, d in pairs(session.items or {}) do
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
        end
    end)

    -- Pass 2: fill in whatever pass 1 could resolve unambiguously.
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        for itemID, d in pairs(session.items or {}) do
            local variants = d.variants or d.gearVariants
            if variants then
                local byQuality = ilvlByItemQuality[itemID]
                if byQuality then
                    for _, gv in pairs(variants) do
                        if not gv.itemLevel and gv.quality then
                            local ilvl = byQuality[gv.quality]
                            if ilvl and ilvl ~= false then
                                gv.itemLevel = ilvl
                                fixed = fixed + 1
                            end
                        end
                    end
                end
            end
        end
    end)
    return fixed
end

-- One-time repair: recomputes every saved session's totalGold/totalVendor/
-- totalAH from its own items via BuildSessionCategories, so the session-row
-- total can't disagree with what the Detail window shows (needed for
-- sessions saved before the reagent-tier consistency guard existed, whose
-- frozen totals were inflated by mis-tagged tiers). Deliberately does NOT
-- go through ns.VendorTotal/ns.AHTotal/ns.ItemValue: those price gear off
-- a live AH lookup, which would replace an old session's frozen gear value
-- with today's price. Note: sessions without filterFrozen are valued with
-- the CURRENT Vendor-Only filters here.
function ns.RepairSessionTotals(sessions)
    if not sessions then return 0 end
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        local cats = BuildSessionCategories(session)
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
-- One-time migration (v1.7.0): the three legacy per-item shapes -
-- gearVariants (scaling/Adventurer's gear) and q+qIDs+qAHTotal (crafting-
-- reagent quality tiers) - collapse into one d.variants field, keyed by
-- bonus-ID string (gear) or tier number 1/2/3 (reagent). Runs AFTER every
-- other numbered repair above, so only already-consistent data (repairs
-- 1-5 already wiped anything corrupted) ever reaches this conversion -
-- it never needs to re-validate a breakdown, just rename/reshape it. See
-- GetVariants in PriceHelper.lua, which every price/value calculation
-- reads through instead of branching on which of the three shapes an
-- item happens to use. Returns how many items were converted.
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

function ns.MigrateItemsToUnifiedVariants(sessions)
    if not sessions then return 0 end
    local migrated = 0
    ns.ForEachSession(sessions, function(session)
        for _, d in pairs(session.items or {}) do
            if ns.MigrateItemToUnifiedVariants(d) then migrated = migrated + 1 end
        end
    end)
    return migrated
end

------------------------------------------------------------------------
-- One-time cleanup: a gear item's variants table can carry a stray
-- NUMERIC key from older code (e.g. the old ns.MigrateGearVariantsFromBags
-- remainder bucket, keyed by quality - now fixed to use a string) mixed
-- in with normal bonus-ID string keys. Classification (ns.IsGear-based)
-- doesn't care about key types, but a mixed-type table is still fragile -
-- normalize every numeric key to a string here so every GEAR item's
-- variants table ends up uniformly string-keyed. Reagent-tier variants
-- (numeric keys 1/2/3) are untouched - those are looked up by that exact
-- number elsewhere (ProcessLoot, BuildSessionCategories) and must stay
-- numeric. Returns how many keys were touched.
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

function ns.NormalizeVariantKeysInSessions(sessions)
    if not sessions then return 0 end
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        for _, d in pairs(session.items or {}) do
            fixed = fixed + ns.NormalizeVariantKeys(d)
        end
    end)
    return fixed
end

------------------------------------------------------------------------
-- One-time cleanup: two gear-variant keys for the SAME item can end up
-- describing the identical roll (same itemLevel + quality) when the
-- bonus-ID/modifier tail of the item link comes back in a different
-- position between an early (not-yet-fully-cached) lookup and a later
-- one - see ns.GearVariantKey. The two resulting keys are byte-different
-- even though the roll is identical, so two variant buckets get created
-- instead of one, splitting amount/ahTotal that belong together and
-- leaving the item's top-level itemLink/quality/sellPrice mirroring
-- whichever bucket happened to be written last.
--
-- Deliberately keyed by (itemLevel, quality) rather than re-parsing the
-- item link itself - the exact byte layout of the bonus-ID/modifier tail
-- isn't safe to reorder or reinterpret without live in-game verification
-- (some of those fields are type:value pairs, not a freely-reorderable
-- set), whereas itemLevel+quality is the same trusted pairing
-- GroupGearVariantsForDisplay has used for DISPLAY grouping since v1.5.5
-- - this applies that same, already-proven pairing to STORAGE instead.
-- Never touches reagent-tier variants (numeric 1/2/3 keys, no itemLevel
-- field) or gear variants that genuinely differ in ilvl or quality.
-- Returns how many variant keys were merged away.
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

function ns.MergeDuplicateGearVariantsInSessions(sessions)
    if not sessions then return 0 end
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        for _, d in pairs(session.items or {}) do
            fixed = fixed + ns.MergeDuplicateGearVariants(d)
        end
    end)
    return fixed
end

------------------------------------------------------------------------
-- One-time cleanup: a gear item's top-level itemLink is a byte-for-byte
-- copy of whichever variant was looted/refreshed last (see ProcessLoot/
-- UpdatePricesFromBags in Main.lua) - every display/tooltip path for a
-- gear item with variants reads gv.itemLink instead (History.lua/UI.lua
-- gear-variant rows), so once variants exist the top-level copy is pure,
-- unused duplication that also goes stale the moment a second, different
-- roll is looted. New loot no longer writes it (see ProcessLoot/
-- UpdatePricesFromBags); this clears it from already-saved data. Never
-- touches non-gear items or gear items with no variants yet - those
-- still rely on the top-level link as their only copy. Returns how many
-- items were cleared.
------------------------------------------------------------------------
function ns.StripRedundantGearItemLink(d)
    if d.itemLink and d.variants and ns.IsGear(d) then
        d.itemLink = nil
        return true
    end
    return false
end

function ns.StripRedundantGearItemLinkInSessions(sessions)
    if not sessions then return 0 end
    local fixed = 0
    ns.ForEachSession(sessions, function(session)
        for _, d in pairs(session.items or {}) do
            if ns.StripRedundantGearItemLink(d) then fixed = fixed + 1 end
        end
    end)
    return fixed
end

-- Row gold text. Plain rows and rows with a frozen AH/vendor split show
-- entry.gold (the exact value the list was sorted by - BuildSessionCategories
-- takes the LARGER of AH and vendor); older variant/tier rows show their AH
-- total, else their vendor total.
local function SetDetailGold(ir, entry)
    local value = entry.gold
    if (entry.isRank or entry.isGearVariant) and not entry.breakdown then
        value = (entry.tAH and entry.tAH > 0) and entry.tAH or entry.tV
    end
    ir.goldText:SetText(value and value > 0 and ns.FormatGold(value) or "")
end

local function RebuildDetailContent(session)
    currentDetailSession = session
    for _,r in ipairs(activeDetRows) do ReleaseDetRow(r) end
    for _,r in ipairs(activeDetCats) do ReleaseDetCat(r)  end
    activeDetRows={}; activeDetCats={}

    local cats, catOrder = BuildSessionCategories(session)

    local yOff = 0; local totalItems = 0
    for _, catName in ipairs(catOrder) do
        local cat = cats[catName]
        if #cat.items > 0 then

        local ch = AcquireDetCat(); ch:SetSize(DET_CONT_W, DET_CAT_H); ch:SetPoint("TOPLEFT",0,-yOff)
        local isCollapsed = detCollapsed[catName]
        ch.nameText:SetText((isCollapsed and "+ " or "- ")..catName)
        ch.goldText:SetText(cat.gold > 0 and ns.FormatGold(cat.gold) or "")
        ch:SetScript("OnMouseUp", function()
            detCollapsed[catName] = not detCollapsed[catName]
            RebuildDetailContent(currentDetailSession)
        end)
        activeDetCats[#activeDetCats+1]=ch; yOff = yOff + DET_CAT_H

        if not isCollapsed then
        for _, entry in ipairs(cat.items) do
            totalItems = totalItems + 1
            local ir = AcquireDetRow(); ir:SetWidth(DET_CONT_W); ir:SetPoint("TOPLEFT",0,-yOff)
            ir.sep:SetShown(yOff > 0)
            -- Indent icon like in the main frame
            ir.icon:ClearAllPoints(); ir.icon:SetPoint("LEFT", 4 + ns.CAT_INDENT, 0)
            ir.nameText:ClearAllPoints()
            ir.nameText:SetPoint("LEFT",  ir.rankBadge, "RIGHT", 4,    0)
            ir.nameText:SetPoint("RIGHT", ir,           "RIGHT", -128, 0)
            ir.icon:SetTexture(entry.d.icon or ns.FALLBACK_ICON)
            local q = entry.d.quality
            ns.ApplyQualityColor(ir.nameText, ir.iconBorder, q, {1,1,1})
            ir.goldText:SetTextColor(unpack(ns.COL_GOLD))  -- always gold, like the main window
            if entry.isRank then
                ir.itemID = entry.tid
                ir.itemLink = nil
                ir.classID = entry.d.classID
                ir.itemName = entry.name
                ir.nameText:SetText(ns.TruncateName(ns.DisplayName(entry.name, entry.tid)))
                ir.rankBadge:SetText(entry.rankIcon or "")
                ir.countText:SetText(tostring(entry.tc))
            elseif entry.isGearVariant then
                local gv = entry.gv
                ns.ApplyQualityColor(ir.nameText, ir.iconBorder, gv.quality, {1,1,1})
                ir.itemID = entry.d.itemID
                ir.itemLink = gv.itemLink
                ir.classID = entry.d.classID
                ir.itemName = entry.name
                ir.nameText:SetText(ns.TruncateName(ns.DisplayName(entry.name, gv.itemLink or entry.d.itemID)))
                ir.rankBadge:SetText("")
                ir.countText:SetText(tostring(gv.amount))
            else
                ir.itemID = entry.d.itemID
                ir.itemLink = entry.d.itemLink
                ir.classID = entry.d.classID
                ir.itemName = entry.name
                ir.nameText:SetText(entry.d.isJunkMerged and ns.TruncateName(entry.name) or ns.TruncateName(ns.DisplayName(entry.name, entry.d.itemID)))
                ir.rankBadge:SetText(entry.rankIcon or "")
                ir.countText:SetText(tostring(entry.d.amount))
            end
            SetDetailGold(ir, entry)
            -- AH/vendor split for the gold-hover tooltip (only known for
            -- sessions saved with the frozen split; older ones have none).
            ir.breakdown = entry.breakdown
            ir.goldHit:SetShown(entry.breakdown ~= nil)
            activeDetRows[#activeDetRows+1]=ir; yOff = yOff + DET_ROW_H
        end
        yOff = yOff + 2
        end  -- not isCollapsed
        end  -- if #cat.items > 0
    end

    local contentH = math.max(1, yOff)
    DListFrame:SetHeight(contentH); DScrollFrame:SetVerticalScroll(0)
    local visH = math.min(contentH, DET_MAX_H)
    DScrollFrame:SetHeight(visH)
    DetailFrame:SetHeight(DET_HDR_H + visH + DET_FTR_H)
    DetailFrame.footLabel:SetText((totalItems==1 and string.format(ns.L["item_singular"],totalItems) or string.format(ns.L["item_plural"],totalItems)))
end

-- Builds a virtual, non-persisted session that merges every real session
-- belonging to one calendar month, so the existing Detail window (same
-- one used for isMonthCompact entries) can render a month-wide summary
-- on demand without touching saved data.
local function BuildMonthAggregate(mKey, month)
    local agg = {
        timestamp = ns.EndOfMonthTimestamp(mKey), isMonthCompact = true,
        duration = 0, totalGold = 0, totalVendor = 0, totalAH = 0,
        lootedGold = 0, items = {}, qAtlas = {},
    }
    for _, session in ipairs(month.sessionsList or {}) do
        MergeSessionInto(agg, session, false)
    end
    return agg
end

local function ShowDetail(session)
    if ns.DeferInCombat(function() ShowDetail(session) end) then return end
    EnsureDetailFrame()
    detCollapsed = {}
    DetailFrame:ClearAllPoints()
    ns.DockFrame(DetailFrame, HistFrame, "left")
    local dateStr
    if session.isMonthCompact then
        dateStr = (ns.L.MONTH_NAMES[tonumber(date("%m", session.timestamp))] or "")
            .." "..date("%Y", session.timestamp)
    else
        dateStr = date("%d.%m.%Y", session.timestamp)
    end
    DetailFrame.dateText:SetText(dateStr)
    RebuildDetailContent(session)
    DetailFrame:Show()
end

------------------------------------------------------------------------
-- RebuildHistory
------------------------------------------------------------------------
function ns.RebuildHistory()
    if not HListFrame then return end
    for _,r in ipairs(activeSessRows)  do ReleaseSessRow(r)  end
    for _,r in ipairs(activeDayRows)   do ReleaseDayRow(r)   end
    for _,r in ipairs(activeMonthRows) do ReleaseMonthRow(r) end
    activeSessRows={}; activeDayRows={}; activeMonthRows={}
    local sessions=(NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions) or {}

    -- sessions is keyed by "YYYY-MM-DD" (each value an array of that day's
    -- sessions, newest first) - table iteration order is undefined, so
    -- build a sorted list of day keys ourselves. ISO-format strings sort
    -- lexicographically in the same order as chronologically, so a plain
    -- string sort works.
    local storageDayKeys = {}
    for k in pairs(sessions) do storageDayKeys[#storageDayKeys+1] = k end
    table.sort(storageDayKeys, function(a,b) return a > b end)

    -- Group sessions by calendar day (order follows the sorted day keys
    -- above, newest first; within a day, the stored array is already
    -- newest-first too).
    local nTotal = 0
    local days,dayOrder={},{}
    for _, dayKey in ipairs(storageDayKeys) do
        for sessIdx, session in ipairs(sessions[dayKey]) do
            nTotal = nTotal + 1
            local dStr=date("%d.%m.%Y",session.timestamp)
            if not days[dStr] then
                days[dStr]={
                    totalGold=0, sessions={}, dayKey=dayKey,
                    monthKey=date("%Y-%m",session.timestamp),
                    monthLabel=(ns.L.MONTH_NAMES[tonumber(date("%m",session.timestamp))] or "")
                        .." "..date("%Y",session.timestamp),
                }
                dayOrder[#dayOrder+1]=dStr
            end
            days[dStr].totalGold=days[dStr].totalGold+session.totalGold
            days[dStr].lootedGold=(days[dStr].lootedGold or 0)+(session.lootedGold or 0)
            days[dStr].sessions[#days[dStr].sessions+1]={session=session,dayKey=dayKey,sessIdx=sessIdx}
        end
    end

    -- Group days into months, preserving day order
    local months,monthOrder={},{}
    local currentMonthKey=date("%Y-%m")
    for _,dStr in ipairs(dayOrder) do
        local day=days[dStr]; local mKey=day.monthKey
        if not months[mKey] then
            months[mKey]={label=day.monthLabel,totalGold=0,sessionCount=0,dayList={},sessionsList={},isCurrent=(mKey==currentMonthKey)}
            monthOrder[#monthOrder+1]=mKey
        end
        months[mKey].totalGold=months[mKey].totalGold+day.totalGold
        months[mKey].lootedGold=(months[mKey].lootedGold or 0)+(day.lootedGold or 0)
        months[mKey].sessionCount=months[mKey].sessionCount+#day.sessions
        table.insert(months[mKey].dayList,dStr)
        for _,entry in ipairs(day.sessions) do
            months[mKey].sessionsList[#months[mKey].sessionsList+1]=entry.session
        end
    end

    local accDB=NightsFarmtrackerAccountDB
    accDB.collapsedMonths=accDB.collapsedMonths or {}

    local yOffset=0
    for _,mKey in ipairs(monthOrder) do
        local month=months[mKey]
        -- default: current month expanded, past months collapsed — user choice wins
        local collapsed=accDB.collapsedMonths[mKey]
        if collapsed==nil then collapsed=not month.isCurrent end
        local mrow=AcquireMonthRow(); mrow:SetSize(ns.CONTENT_W, MONTH_H); mrow:SetPoint("TOPLEFT",0,-yOffset)
        mrow.arrow:SetText(collapsed and "+" or "-")
        mrow.nameText:SetText(month.label)
        local monthCombined = (month.totalGold or 0) + (month.lootedGold or 0)
        mrow.goldText:SetText(monthCombined>0 and ns.FormatGold(monthCombined) or "")
        mrow:SetScript("OnEnter",function(self)
            self.nameText:SetTextColor(1,1,1)
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:AddLine(ns.L["month_summary_tooltip"])
            if monthCombined>0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(ns.L["gold_items"], ns.FormatGold(month.totalGold or 0), 0.75,0.75,0.75, 1,1,1)
                GameTooltip:AddDoubleLine(ns.L["looted_gold"], ns.FormatGold(month.lootedGold or 0), 0.75,0.75,0.75, 1,1,1)
                GameTooltip:AddDoubleLine(ns.L["gold_total"], ns.FormatGold(monthCombined), 0.75,0.75,0.75, unpack(ns.COL_GOLD))
            end
            GameTooltip:Show()
        end)
        mrow:SetScript("OnMouseUp",function(self)
            if self.delBtn:IsMouseOver() then return end
            if IsShiftKeyDown() then
                if #month.sessionsList > 0 then
                    ShowDetail(BuildMonthAggregate(mKey, month))
                end
            else
                accDB.collapsedMonths[mKey]=not collapsed
                ns.RebuildHistory()
            end
        end)
        mrow.delBtn:SetScript("OnClick",function()
            StaticPopup_Show("NFT_CONFIRM_DELETE_MONTH",
                string.format(ns.L["delete_month_confirm"], month.sessionCount, month.label), nil, mKey)
        end)
        activeMonthRows[#activeMonthRows+1]=mrow; yOffset=yOffset+MONTH_H
        if not collapsed then
            -- flush: month row already draws its own bottom line, first day row starts right after it
            for _,dStr in ipairs(month.dayList) do
                local day=days[dStr]
                -- A past month with exactly one day/session (e.g. after
                -- compaction) doesn't need its own date subheader — the
                -- month header already says everything there is to say.
                local skipDayRow = (not month.isCurrent) and #month.dayList==1 and #day.sessions==1
                if not skipDayRow then
                    local drow=AcquireDayRow(); drow:SetSize(ns.CONTENT_W, DAY_H); drow:SetPoint("TOPLEFT",0,-yOffset)
                    drow.dateText:SetText(dStr)
                    drow.goldText:SetText("")
                    if #day.sessions > 1 then
                        drow.mergeBtn:Show()
                        drow.mergeBtn:SetScript("OnClick", function()
                            StaticPopup_Show("NFT_CONFIRM_MERGE_DAY",
                                string.format(ns.L["merge_day_confirm"], #day.sessions, dStr), nil, day.dayKey)
                        end)
                    else
                        drow.mergeBtn:Hide()
                    end
                    activeDayRows[#activeDayRows+1]=drow; yOffset=yOffset+DAY_H
                end
                for _,entry in ipairs(day.sessions) do
                    local session=entry.session
                    local row=AcquireSessRow(); row:SetWidth(ns.CONTENT_W); row:SetPoint("TOPLEFT",0,-yOffset)
                    row.session=session
                    local combinedGold = (session.totalGold or 0) + (session.lootedGold or 0)
                    row.dateText:SetText(ns.FormatTime(session.duration))
                    row.goldText:SetText(combinedGold>0 and ns.FormatGold(combinedGold) or "")
                    local sess=session
                    row:SetScript("OnMouseUp",function(self,btn)
                        if btn=="LeftButton" and not self.delBtn:IsMouseOver() then
                            if DetailFrame and DetailFrame:IsShown() and currentDetailSession == sess then
                                if not ns.DeferInCombat(function() DetailFrame:Hide() end) then DetailFrame:Hide() end
                            else
                                ShowDetail(sess)
                            end
                        end
                    end)
                    row.delBtn:SetScript("OnClick",function()
                        local dayList = NightsFarmtrackerAccountDB.sessions[entry.dayKey]
                        if dayList then
                            table.remove(dayList, entry.sessIdx)
                            if #dayList == 0 then NightsFarmtrackerAccountDB.sessions[entry.dayKey] = nil end
                        end
                        ns.RebuildHistory()
                    end)
                    activeSessRows[#activeSessRows+1]=row; yOffset=yOffset+SESS_H
                end
            end
        end
    end
    local contentH=math.max(1,yOffset)
    HListFrame:SetHeight(contentH)
    local maxS=math.max(0,contentH-HScrollFrame:GetHeight())
    HScrollFrame:SetVerticalScroll(math.min(HScrollFrame:GetVerticalScroll(),maxS))
    local visH=yOffset==0 and 44 or math.min(contentH,MAX_VIS_H)
    HistFrame:SetHeight(H_HDR_H+visH+H_FTR_H)
    -- nTotal already counted above while grouping by day
    if nTotal==0 then
        HistFrame.countLabel:SetText("")
        HistFrame.emptyLabel:SetText(ns.L["no_sessions"])
        HistFrame.emptyLabel:Show()
        if HistFrame.clrBtn then HistFrame.clrBtn:Hide() end
    else
        HistFrame.emptyLabel:Hide()
        if HistFrame.clrBtn then HistFrame.clrBtn:Show() end
        local key = (nTotal == 1) and ns.L["sessions_summary"] or ns.L["sessions_summary_pl"]
        HistFrame.countLabel:SetText(string.format(key, nTotal))
    end
end

------------------------------------------------------------------------
-- Build history list window (lazy)
------------------------------------------------------------------------
local function EnsureHistFrame()
    if HListFrame then return end
    HistFrame = ns.CreateWindowFrame("NightsFarmtrackerHistoryWnd", ns.L["session_history"], {width = H_W})
    ns.HistFrame = HistFrame  -- exposed so Settings can dock next to it in the left-side chain
    HistFrame:SetScript("OnHide",function()
        if DetailFrame then DetailFrame:Hide() end
        ns.RefreshWindowChain("left")
    end)

    local hSep=HistFrame:CreateTexture(nil,"ARTWORK"); hSep:SetHeight(1)
    hSep:SetColorTexture(unpack(ns.COL_BORDER))
    hSep:SetPoint("TOPLEFT",H_PAD,-(H_HDR_H-1)); hSep:SetPoint("TOPRIGHT",-H_PAD,-(H_HDR_H-1))

    HScrollFrame=CreateFrame("ScrollFrame",nil,HistFrame)
    HScrollFrame:SetPoint("TOPLEFT",H_PAD,-H_HDR_H); HScrollFrame:SetPoint("BOTTOMRIGHT",-H_PAD,H_FTR_H)
    HScrollFrame:EnableMouseWheel(true)
    HListFrame=CreateFrame("Frame",nil,HScrollFrame)
    HListFrame:SetWidth(ns.CONTENT_W); HListFrame:SetHeight(1)
    HScrollFrame:SetScrollChild(HListFrame)
    local function OnWheel(_,delta)
        local cur=HScrollFrame:GetVerticalScroll()
        local maxS=math.max(0,HListFrame:GetHeight()-HScrollFrame:GetHeight())
        HScrollFrame:SetVerticalScroll(math.max(0,math.min(cur-delta*SESS_H,maxS)))
    end
    HScrollFrame:SetScript("OnMouseWheel",OnWheel)
    HListFrame:EnableMouseWheel(true); HListFrame:SetScript("OnMouseWheel",OnWheel)

    local fSep=HistFrame:CreateTexture(nil,"ARTWORK"); fSep:SetHeight(1)
    fSep:SetColorTexture(unpack(ns.COL_BORDER))
    fSep:SetPoint("BOTTOMLEFT",H_PAD,H_FTR_H-2); fSep:SetPoint("BOTTOMRIGHT",-H_PAD,H_FTR_H-2)

    HistFrame.countLabel = HistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    HistFrame.countLabel:SetPoint("BOTTOMLEFT",H_PAD,8); HistFrame.countLabel:SetTextColor(0.40,0.40,0.40)

    HistFrame.emptyLabel = HistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    HistFrame.emptyLabel:SetPoint("TOP",HistFrame,"TOP",0,-(H_HDR_H+22))
    HistFrame.emptyLabel:SetJustifyH("CENTER")
    HistFrame.emptyLabel:SetTextColor(0.55,0.55,0.55)
    HistFrame.emptyLabel:Hide()

    HistFrame.clrBtn=CreateFrame("Button",nil,HistFrame); HistFrame.clrBtn:SetSize(70,18); HistFrame.clrBtn:SetPoint("BOTTOMRIGHT",-H_PAD,6)
    local clrLabel = HistFrame.clrBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clrLabel:SetAllPoints(); clrLabel:SetJustifyH("RIGHT"); clrLabel:SetText(ns.L["clear_all"])
    clrLabel:SetTextColor(0.50,0.22,0.22)
    HistFrame.clrBtn:SetScript("OnClick",function()
        if not NightsFarmtrackerAccountDB.sessions or not next(NightsFarmtrackerAccountDB.sessions) then return end
        StaticPopup_Show("NFT_CONFIRM_CLEAR_ALL_HISTORY")
    end)
    HistFrame.clrBtn:SetScript("OnEnter",function()
        clrLabel:SetTextColor(1,0.4,0.4)
        GameTooltip:SetOwner(HistFrame.clrBtn,"ANCHOR_TOP"); GameTooltip:SetText(ns.L["delete_all"]); GameTooltip:Show()
    end)
    HistFrame.clrBtn:SetScript("OnLeave",function() clrLabel:SetTextColor(0.50,0.22,0.22); GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleHistory()
    if ns.DeferInCombat(ns.ToggleHistory) then return end
    EnsureHistFrame()
    if HistFrame:IsShown() then
        HistFrame:Hide()
        if DetailFrame then DetailFrame:Hide() end
    else
        -- Settings docks off the same anchor point as History, so close
        -- it first to avoid overlap.
        if ns.SettingsFrame and ns.SettingsFrame:IsShown() then ns.SettingsFrame:Hide() end
        ns.RebuildHistory()
        HistFrame:Show()
        ns.RefreshWindowChain("left")
    end
end
