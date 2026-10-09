------------------------------------------------------------------------
-- Night's Farmtracker - Main
-- Events, loot processing, timer.
------------------------------------------------------------------------
local _, ns = ...

local ADDON_NAME     = ns.ADDON_NAME
local TRADE_GOODS    = ns.TRADE_GOODS
local QUEST_CLASS    = ns.QUEST_CLASS
local BIND_ON_EQUIP  = ns.BIND_ON_EQUIP
local BIND_ON_USE    = ns.BIND_ON_USE
local BIND_ON_PICKUP = ns.BIND_ON_PICKUP
local MainFrame      = ns.MainFrame
local EventFrame

-- Real account-bound ("Warband"/BoA) bindTypes per current Enum.ItemBind:
-- 7 = ToWoWAccount, 8 = ToBnetAccount, 9 = ToBnetAccountUntilEquipped.
-- (Some items still report bindType 7 despite showing "Binds to Warband"
-- in the tooltip - all three are treated the same here.)
local BIND_TO_ACCOUNT = { [7] = true, [8] = true, [9] = true }

------------------------------------------------------------------------
-- Loot processing
------------------------------------------------------------------------
local PRICE_MAX_RETRIES = 3
local priceRetryCount   = 0

-- Localized self-loot prefix derived from WoW's own global string.
-- EN: "You receive loot: "  /  DE: "Ihr erhaltet Beute: "
-- Only messages starting with this prefix belong to the player.
-- First word extracted from LOOT_ITEM_SELF ("You "/"Ihr " etc.), covers all
-- self-loot variants (loot, item, an item, ...). Other players' loot lines
-- start with their character name and are filtered out this way.
local SELF_LOOT_PREFIX    = LOOT_ITEM_SELF and LOOT_ITEM_SELF:match("^(%S+%s)") or nil

-- Midnight (12.x) can hand addons "secret values" (e.g. chat/event payloads
-- while restricted): any string operation on one throws. Event handlers
-- below bail out on them instead of erroring. No-op on clients without it.
local issecretvalue = issecretvalue or function() return false end

-- Coin patterns from WoW's own global strings ("%d Gold" etc.), so the
-- CHAT_MSG_MONEY parse works in every client language instead of only
-- matching hardcoded EN/DE words.
local function AmountPattern(fmt)
    if not fmt then return nil end
    local pattern = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%d", "(%%d+)")
    return pattern
end
local GOLD_PATTERN   = AmountPattern(GOLD_AMOUNT)
local SILVER_PATTERN = AmountPattern(SILVER_AMOUNT)
local COPPER_PATTERN = AmountPattern(COPPER_AMOUNT)

-- Cache reagent quality API at load time; nil if unavailable
local GetReagentQualityInfo = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo or nil

-- Item link color → quality (avoids GetItemInfo cache dependency for quality)
local LINK_QUALITY = {
    ["9d9d9d"] = 0,  -- Poor
    ["ffffff"] = 1,  -- Common
    ["1eff00"] = 2,  -- Uncommon
    ["0070dd"] = 3,  -- Rare
    ["a335ee"] = 4,  -- Epic
    ["ff8000"] = 5,  -- Legendary
    ["e6cc80"] = 6,  -- Artifact
    ["00ccff"] = 7,  -- Heirloom
}

local pendingLoot = {}
local delayedRefreshTicket = 0   -- see the delayed re-check at the end of ProcessLoot

-- canAH: BoE, Bind-on-Use and unbound items (0/nil), plus Trade Goods, may
-- go on the AH (all still tradeable before the bind actually triggers).
-- BoP (1), Warbound/account-bound and everything else → vendor only.
local function CanAH(bindType, classID)
    return (bindType == BIND_ON_EQUIP)
        or (bindType == BIND_ON_USE)
        or (bindType == 0 or bindType == nil)
        or (classID == TRADE_GOODS)
end

local function ProcessLoot(items)
    local changed          = false
    local needsPriceUpdate = false

    for _, pending in ipairs(items) do
        local itemID = pending.itemID
        local qty    = pending.qty
        local link   = pending.link

        local name, _, quality, itemLevel, _, _, itemSubType, _, _, icon, sellPrice, classID, subClassID, bindType =
            C_Item.GetItemInfo(link)

        -- Cache miss: recover from link color (quality) + GetItemInfoInstant (classID/icon)
        -- C_Item.GetItemInfoInstant returns: itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID
        -- (no bindType — that gets resolved later via bag scan in ns.UpdatePricesFromBags)
        if not name then
            local _, _, _, _, icon2, classID2, subClassID2 = C_Item.GetItemInfoInstant(itemID)
            ns.Log("CacheMiss", itemID, "classID2=", classID2, "itemName=", pending.itemName)
            if classID2 and pending.itemName then
                name        = pending.itemName
                quality     = pending.linkQuality
                icon        = icon2
                classID     = classID2
                subClassID  = subClassID2
            else
                pendingLoot[#pendingLoot+1] = pending
                if not ns.pendingPriceUpdate then
                    ns.pendingPriceUpdate = true
                    priceRetryCount       = 0
                    EventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
                end
            end
        end

        ns.Log("ProcessLoot", name, "classID=", classID, "quality=", quality, "shouldTrack check")

        if name and classID then
            local db          = NightsFarmtrackerDB
            local shouldTrack = false

            -- Cosmetic weapons/armor (transmog-only, e.g. fishing rod skins) get
            -- their own category instead of being lumped into regular Equipment.
            local isCosmetic = (classID == 2 or classID == 4) and C_Item.IsCosmeticItem(link) or nil

            -- Category name for this pending item, using whatever bind/quality
            -- info is already available from GetItemInfo at loot time - lets
            -- category-level exclusion (Shift+Right-click on a category header)
            -- catch items before they're ever added to db.count, not just clear
            -- already-tracked ones.
            local catData = {
                classID = classID, subClassID = subClassID, quality = quality,
                itemSubType = itemSubType, isVendorTrash = (quality == 0),
                isBoE = (bindType == BIND_ON_EQUIP), isBoP = (bindType == BIND_ON_PICKUP),
                isBoA = BIND_TO_ACCOUNT[bindType] or nil, isCosmetic = isCosmetic,
            }

            ns.RecordItemDBEntry(itemID, name, link, quality, classID, subClassID, catData)

            if ns.IsIgnoredItemClass(classID) then
                -- obsolete/irrelevant item class (WoW Token, obsolete money/permanent) - never tracked
            elseif ns.IsBlacklisted(itemID) then
                -- itemID explicitly blacklisted — never tracked, wins over everything else
            elseif ns.IsBlacklistCategory(catData) then
                -- category blacklisted
            elseif db.excludedItemIDs[itemID] then
                -- itemID explicitly excluded — survives a client-language switch
            elseif db.excludedNames[name] then
                -- name explicitly excluded (legacy, pre-itemID-based exclusion)
            elseif db.excludedNames[ns.CategoryName(catData)] then
                -- category explicitly excluded (Shift+Right-click on category header)
            elseif quality == 0 then
                -- grey: vendor junk (known or unknown=cache miss, resolve later)
                if sellPrice ~= nil then
                    shouldTrack = sellPrice > 0
                else
                    shouldTrack = true
                end
            else
                -- quality > 0: track unless definitely unsellable.
                -- sellPrice == nil = cache miss = unknown → track and resolve price later.
                -- Quest items (classID 12) are always unsellable per the Blizzard API
                -- (sellPrice always 0) but not necessarily BIND_ON_PICKUP - hence its own check.
                -- Otherwise: only skip when sellPrice is explicitly 0 AND BoP AND not a trade good.
                local definitelyUnsellable
                if classID == QUEST_CLASS then
                    definitelyUnsellable = true
                else
                    definitelyUnsellable = (sellPrice == 0)
                                        and (bindType == BIND_ON_PICKUP)
                                        and (classID ~= TRADE_GOODS)
                end
                shouldTrack = not definitelyUnsellable
            end

            ns.Log("shouldTrack=", shouldTrack, "for", name)

            if shouldTrack then
                local entry = db.count[itemID]
                if not entry then
                    entry            = { icon = icon, amount = 0, name = name }
                    db.count[itemID] = entry
                end
                entry.amount      = entry.amount + qty
                entry.name        = entry.name or name
                entry.quality     = quality     or entry.quality
                entry.itemSubType = itemSubType or entry.itemSubType
                entry.classID     = entry.classID or classID
                entry.subClassID  = entry.subClassID or subClassID
                entry.itemID      = entry.itemID or itemID
                -- Gear (classID 2/4) tracks its link per-variant instead
                -- (see gv.itemLink below) - every display/tooltip path for
                -- a gear item with variants reads that, never this field,
                -- so writing it here would just be an unused duplicate
                -- that goes stale the moment a second, differently-rolled
                -- variant is looted. Non-gear items have no per-variant
                -- link, so this stays their only copy.
                if not (classID == 2 or classID == 4) then
                    entry.itemLink = link
                end

                if quality == 0               then entry.isVendorTrash = true end
                if bindType == BIND_ON_EQUIP  then entry.isBoE         = true end
                if bindType == BIND_ON_PICKUP then entry.isBoP         = true end
                if BIND_TO_ACCOUNT[bindType]  then entry.isBoA         = true end
                if isCosmetic                 then entry.isCosmetic   = true end
                if entry.canAH == nil then
                    entry.canAH = CanAH(bindType, classID)
                end

                -- Sell price: trust directly for trade goods and junk (no scaling)
                if sellPrice and sellPrice > 0 and (classID == TRADE_GOODS or quality == 0) then
                    entry.sellPrice = sellPrice
                elseif not entry.noSell then
                    needsPriceUpdate = true
                end

                -- Gear quality/ilvl variant tracking: scaling gear (e.g. Adventurer's
                -- gear) can drop under the SAME item ID at different item levels and
                -- qualities. Track each item level as its own bucket so amounts and
                -- prices don't mix between variants (mirrors the reagent tier split
                -- below); the merged entry.quality/itemLink above stay as a fallback
                -- for old saved data that predates this field.
                -- Unified variant tracking (v1.7.0): scaling/Adventurer's
                -- gear (same item ID, different item level/quality per drop)
                -- and crafting-reagent quality tiers (Q1/Q2/Q3) both need
                -- per-bucket amounts/prices instead of one shared
                -- sellPrice*amount - they now share ONE entry.variants
                -- table, keyed by bonus-ID string for gear or tier number
                -- (1/2/3) for reagents. See GetVariants in PriceHelper.lua,
                -- which every price/value calculation reads through.
                if classID == 2 or classID == 4 then
                    local vKey = ns.GearVariantKey(link)
                    entry.variants = entry.variants or {}
                    local gv = entry.variants[vKey]
                    if not gv then
                        gv = { amount = 0 }
                        entry.variants[vKey] = gv
                    end
                    gv.amount    = gv.amount + qty
                    gv.quality   = quality    or gv.quality
                    gv.itemLevel = itemLevel  or gv.itemLevel
                    gv.itemLink  = link
                    if sellPrice and sellPrice > 0 then gv.sellPrice = sellPrice end
                    -- Threshold-sound check happens in RefreshHUD (UI.lua),
                    -- not here: the AH price for this exact bonus-ID roll can
                    -- take a moment to become queryable, and RefreshHUD is
                    -- what re-checks it (see the delayed refresh below).
                end

                -- Quality tier tracking (crafting reagents Q1/Q2/Q3)
                local rankIcon
                if GetReagentQualityInfo then
                    local ok, qi = pcall(GetReagentQualityInfo, link)
                    if ok and qi then
                        local tier = qi.quality
                        local v = entry.variants
                        local hasTiers = v and (v[1] or v[2] or v[3])
                        local qSum = hasTiers and ((v[1] and v[1].amount or 0) + (v[2] and v[2].amount or 0) + (v[3] and v[3].amount or 0)) or 0
                        -- Self-heal: the breakdown was ALREADY inconsistent with
                        -- this item's own amount before this loot event (e.g. an
                        -- older corrupted save that got merged in) - wipe it
                        -- instead of permanently freezing the bad numbers in
                        -- place, so tier tracking can recover cleanly from here.
                        if hasTiers and qSum ~= (entry.amount - qty) then
                            entry.variants[1], entry.variants[2], entry.variants[3] = nil, nil, nil
                            qSum = 0
                        end
                        -- Sanity guard: GetReagentQualityInfo can occasionally
                        -- report a tier that doesn't match this item (seen with
                        -- some reagents whose quality is already fixed by their
                        -- itemID, e.g. per-rank ore). Accepting it would push
                        -- the tier total above the item's own tracked amount -
                        -- skip the update instead of corrupting entry.variants.
                        if tier and qSum + qty > entry.amount then
                            tier = nil
                        end
                        if tier then
                            entry.variants = entry.variants or {}
                            local gv = entry.variants[tier]
                            if not gv then gv = { amount = 0 }; entry.variants[tier] = gv end
                            gv.amount      = gv.amount + qty
                            gv.priceItemID = itemID
                            if sellPrice and sellPrice > 0 then gv.sellPrice = sellPrice end
                            db.qAtlas        = db.qAtlas or {}
                            db.qAtlas[tier]  = qi.iconChat
                            rankIcon = qi.iconChat and CreateAtlasMarkup(qi.iconChat, ns.RANK_ICON_W, ns.RANK_ICON_H)
                                    or ("|cffaaaaaa R" .. tier .. "|r")
                        end
                    end
                end

                changed = true
                ns.AddLogEntry(icon, name, qty, link, quality, rankIcon or ns.RankIconFromLink(link))
            end
        end
    end

    if changed then
        ns.RefreshHUD()
        if needsPriceUpdate and not ns.pendingPriceUpdate then
            ns.pendingPriceUpdate = true
            priceRetryCount       = 0
            EventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        end
        -- Auctionator/TSM can take a moment after looting before an AH price
        -- for a specific bonus-ID roll is queryable. RefreshHUD only reruns
        -- on the next loot event otherwise, so an item that priced as
        -- vendor-only on this pass (AH price not yet available) would stay
        -- stuck showing vendor price/never trigger the threshold sound.
        -- One delayed re-check self-corrects that. Only the timer of the
        -- LAST loot of a burst fires (ticket check), so N drops in quick
        -- succession cost one delayed rebuild instead of N.
        delayedRefreshTicket = delayedRefreshTicket + 1
        local ticket = delayedRefreshTicket
        C_Timer.After(2, function()
            if ticket == delayedRefreshTicket then ns.RefreshHUD() end
        end)
    end
end

-- Retry items whose GetItemInfo was not yet cached at loot time
local function FlushPendingLoot()
    if #pendingLoot == 0 then return end
    local items = pendingLoot
    pendingLoot = {}
    ProcessLoot(items)
end

------------------------------------------------------------------------
-- Deferred price update — scans bags for correct equipment sell prices
------------------------------------------------------------------------
function ns.CleanupPriceUpdate()
    if ns.pendingPriceUpdate then
        EventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        ns.pendingPriceUpdate = false
    end
    priceRetryCount = 0
end

function ns.UpdatePricesFromBags()
    local updated      = false
    local stillMissing = false

    local byID = {}
    for _, data in pairs(NightsFarmtrackerDB.count) do
        if data.itemID and not data.sellPrice and not data.noSell then
            byID[data.itemID] = data
        end
    end

    if next(byID) then
        for bag = 0, 5 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local ci = C_Container.GetContainerItemInfo(bag, slot)
                if ci then
                    local data = byID[ci.itemID]
                    if data then
                        local bagLink = C_Container.GetContainerItemLink(bag, slot)
                        if bagLink then
                            local _, _, iQuality, iLevel, _, _, _, _, _, _, sp, cID, subID, bType = C_Item.GetItemInfo(bagLink)
                            if sp and sp > 0 then
                                data.sellPrice = sp
                                -- Gear (classID 2/4) mirrors its link into
                                -- the matching variant bucket below instead -
                                -- writing it here too would recreate the
                                -- same unused top-level duplicate ProcessLoot
                                -- no longer writes at loot time.
                                if not (cID == 2 or cID == 4) then
                                    data.itemLink = bagLink
                                end
                            else
                                data.noSell = true
                            end
                            -- Quality: authoritative now, same reasoning as classID/bind below.
                            -- At loot time this can be a rough guess (chat-message link color,
                            -- or a cache-miss fallback) that's wrong for items whose real
                            -- quality only resolves once the client fully caches them (seen
                            -- with scaling/track gear) - correct it here, and propagate the
                            -- correction to any already-written Loot Log entries for this item,
                            -- since those are otherwise never revisited after being written.
                            if iQuality and iQuality ~= data.quality then
                                data.quality = iQuality
                                if iQuality == 0 then data.isVendorTrash = true end
                                if ns.UpdateLogEntryQuality then
                                    ns.UpdateLogEntryQuality(ci.itemID, iQuality)
                                end
                            end
                            -- classID / subclass / bind flags: authoritative now that the
                            -- item is cached via the bag link — overwrites any approximate
                            -- values set during a loot-time cache miss (no bindType there)
                            if cID then
                                data.classID    = cID
                                data.subClassID = subID
                                if bType == BIND_ON_EQUIP  then data.isBoE = true end
                                if bType == BIND_ON_PICKUP then data.isBoP = true end
                                if BIND_TO_ACCOUNT[bType]  then data.isBoA = true end
                                data.canAH = CanAH(bType, cID)
                                if cID == 2 or cID == 4 then
                                    data.isCosmetic = C_Item.IsCosmeticItem(bagLink) or nil
                                    -- Correct the matching gear variant bucket (see ProcessLoot)
                                    -- with the bag-cached quality/link, same reasoning as the
                                    -- top-level quality fix above but per item-level bucket.
                                    if data.variants then
                                        local gv = data.variants[ns.GearVariantKey(bagLink)]
                                        if not gv and iLevel and iQuality then
                                            -- The exact key can differ once the item is fully
                                            -- cached (bonus-ID/modifier tail can shift position
                                            -- between an early and a later lookup of the same
                                            -- roll - see ns.MergeDuplicateGearVariants). Fall
                                            -- back to the bucket matching this roll's own
                                            -- itemLevel+quality instead of leaving it stale.
                                            for _, candidate in pairs(data.variants) do
                                                if candidate.itemLevel == iLevel and candidate.quality == iQuality then
                                                    gv = candidate
                                                    break
                                                end
                                            end
                                        end
                                        if gv then
                                            gv.itemLink = bagLink
                                            if sp and sp > 0 then gv.sellPrice = sp end
                                            if iQuality then gv.quality = iQuality end
                                            if iLevel then gv.itemLevel = iLevel end
                                        end
                                    end
                                end
                                -- Older/compat-mode clients can still report Warbound-until-
                                -- equipped gear as plain bindType 2 (BoE) instead of 9 - detect
                                -- that case explicitly via the item location so it's still
                                -- flagged BoA and forced to vendor-only pricing.
                                if data.canAH and not data.isBoA and C_Item.IsBoundToAccountUntilEquip then
                                    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                                    if loc and loc:IsValid() and C_Item.IsBoundToAccountUntilEquip(loc) then
                                        data.canAH = false
                                        data.isBoA = true
                                    end
                                end
                            end
                            updated            = true
                            byID[ci.itemID]    = nil
                        end
                        -- bagLink nil: keep in byID, try other slots / next retry
                    end
                end
            end
        end
        if next(byID) then stillMissing = true end
    end

    if not stillMissing or priceRetryCount >= PRICE_MAX_RETRIES then
        -- Items still in byID were never found in any bag slot.
        -- After max retries, mark them noSell so they only show if they have an AH price.
        if stillMissing then
            for _, data in pairs(byID) do
                data.noSell = true
            end
            updated = true
        end
        EventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        ns.pendingPriceUpdate = false
        priceRetryCount       = 0
    else
        priceRetryCount = priceRetryCount + 1
    end

    if updated then ns.RefreshHUD() end
end

------------------------------------------------------------------------
-- Timer
------------------------------------------------------------------------
local lastTick    = GetTime()
local timerTicker = nil

local function OnTick()
    local db  = NightsFarmtrackerDB
    local now = GetTime()
    local dt  = now - lastTick
    lastTick  = now

    -- Fixed session length: clamp the last tick so totalTime ends exactly on
    -- the limit (gold/hour then equals total gold / session length).
    local limit    = ns.GetSessionLimit()
    local finished = false
    if limit and (db.totalTime or 0) + dt >= limit then
        dt       = math.max(limit - (db.totalTime or 0), 0)
        finished = true
    end

    db.totalTime = (db.totalTime or 0) + dt
    ns.UpdateTimerDisplay()
    ns.UpdateGoldRate()

    if finished then
        db.paused = true
        ns.StopTimer()
        ns.ApplyPauseVisuals()
        print("|cff30b0c0Night's Farmtracker:|r " .. ns.L["session_length_reached"])
    end
end

function ns.StartTimer()
    if timerTicker then return end
    -- Stamp the real-world start of this session the first time it actually
    -- starts running, so SaveCurrentSession can file it under the calendar
    -- day it was farmed on instead of the day it happens to be reset on
    -- (e.g. farming past midnight, then resetting after sleeping).
    if not NightsFarmtrackerDB.sessionStartTime then
        NightsFarmtrackerDB.sessionStartTime = time()
    end
    lastTick    = GetTime()
    timerTicker = C_Timer.NewTicker(1, OnTick)
end

function ns.StopTimer()
    if timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_FARMTRACK1 = "/nft"
SlashCmdList["FARMTRACK"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" then
        ns.ToggleMainFrame()
    elseif cmd == "debug" then
        ns.debugMode = not ns.debugMode
        print("|cff30b0c0Night's Farmtracker:|r Debug " .. (ns.debugMode and "|cff00ff00AN|r" or "|cffff4444AUS|r"))
    elseif cmd == "filter" then
        ns.ToggleFilterWindow()
    elseif cmd == "venom" then
        ns.ToggleVenomTracker()
    elseif cmd == "venomdump" then
        ns.DumpVenomTooltip()
    elseif cmd == "bait" then
        ns.ToggleBaitFrame()
    elseif cmd == "hud" then
        ns.HudSlash((msg or ""):match("^%s*%S*%s*(.*)$"))
    elseif cmd == "export" then
        ns.ToggleExportWindow()
    elseif cmd == "test" then
        ns.DebugTest()
    elseif cmd == "itemdb" then
        ns.DebugItemDB()
    elseif cmd == "monthdump" then
        local rest     = (msg or ""):match("^%s*%S*%s*(.*)$")
        local targetID = tonumber(rest)
        ns.DebugMonthDump(targetID)
    elseif cmd == "sessionsdump" then
        ns.DebugSessionsDump()
    else
        print("|cff30b0c0Night's Farmtracker:|r /nft · /nft debug · /nft filter · /nft venom · /nft venomdump · /nft bait · /nft hud · /nft export · /nft test · /nft itemdb · /nft monthdump [itemID] · /nft sessionsdump")
    end
end

------------------------------------------------------------------------
-- Event frame
------------------------------------------------------------------------
EventFrame = CreateFrame("Frame")

-- Blizzard sometimes dispatches the very same CHAT_MSG_LOOT line twice for one
-- pickup. That double has the same lineID (and byte-identical text, which
-- includes the full link, so differently rolled gear never matches). Two real
-- pickups - several corpses in one loot-all, herb procs - are separate chat
-- lines with their own lineID and must both count, so the window is tiny.
local recentLootLine = {}  -- itemID -> { text, at, lineID }
local DUP_WINDOW     = 0.02  -- seconds, "this frame or the next"

local function IsDuplicateLootLine(itemID, msg, lineID)
    local now = GetTime()
    local rec = recentLootLine[itemID]
    local lastText, lastAt, lastLineID
    if rec then
        lastText, lastAt, lastLineID = rec.text, rec.at, rec.lineID
    else
        rec = {}
        recentLootLine[itemID] = rec
    end
    rec.text, rec.at, rec.lineID = msg, now, lineID
    if lastAt and lineID and lastLineID and lineID ~= lastLineID then return false end
    return lastAt ~= nil and lastText == msg and (now - lastAt) < DUP_WINDOW
end

-- Cross-event dedup between CHAT_MSG_LOOT and ENCOUNTER_LOOT_RECEIVED. The
-- encounter event's quantity is unreliable (chests/caches), so only the chat
-- line counts; the encounter event just waits for it and is the fallback if
-- no chat line follows.
local recentChatLoot      = {}  -- counted via CHAT_MSG_LOOT, expires after CROSS_DEDUP_TTL
local recentEncounterLoot = {}  -- ENCOUNTER_LOOT_RECEIVED waiting for its chat line
local CROSS_DEDUP_TTL     = 2   -- seconds
local ENCOUNTER_WAIT      = 0.4 -- seconds to wait for the chat line

local function ConsumePending(t, itemID)
    if t[itemID] and t[itemID] > 0 then
        t[itemID] = t[itemID] - 1
        return true
    end
    return false
end

EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("CHAT_MSG_LOOT")
EventFrame:RegisterEvent("CHAT_MSG_MONEY")
EventFrame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")

EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        ns.InitDB()
        ns.InitAccountDB()
        ns.InitItemDB()

        -- MainFrame and GoldFrame were built while UI.lua loaded, before
        -- SavedVariables/the saved color theme were available, so their
        -- border/background still have the default theme's colors baked
        -- in - refresh them now.
        ns.RefreshFrameStyle(MainFrame)
        ns.RefreshFrameStyle(ns.GoldFrame)

        local p = NightsFarmtrackerDB.pos
        MainFrame:ClearAllPoints()
        MainFrame:SetPoint(p[1], UIParent, p[2], p[3], p[4])

        -- Normalize to a "TOP" anchor if it's anything else. Needed not just
        -- for old saved data, but also because WoW's drag mechanism itself
        -- can hand back a different anchor type after StopMovingOrSizing()
        -- (e.g. "RIGHT", which is vertically centered) - a non-"TOP" anchor
        -- makes height changes (collapse/expand) grow symmetrically up/down
        -- instead of just downward. Runs every login as a safety net; same
        -- screen spot, no visual jump.
        if p[1] ~= "TOP" then
            local top, left, right = MainFrame:GetTop(), MainFrame:GetLeft(), MainFrame:GetRight()
            if top and left and right then
                local offsetY = top - UIParent:GetTop()
                local offsetX = (left + right) / 2 - UIParent:GetWidth() / 2
                NightsFarmtrackerDB.pos = {"TOP", "TOP", offsetX, offsetY}
                MainFrame:ClearAllPoints()
                MainFrame:SetPoint("TOP", UIParent, "TOP", offsetX, offsetY)
            end
        end

        ns.UpdateTimerDisplay()
        ns.ApplyPauseVisuals()
        ns.InitMinimapButton()
        if NightsFarmtrackerDB.visible then MainFrame:Show() end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if not NightsFarmtrackerDB.paused then ns.StartTimer() end
        ns.SetMinimapVisible(not (NightsFarmtrackerDB.minimap and NightsFarmtrackerDB.minimap.hide))
        ns.SetExpanded(NightsFarmtrackerDB.expanded)
        ns.RefreshLeftButtons()
        ns.RestoreLogWindow()
        if not NightsFarmtrackerDB.gearVariantsMigrated then
            ns.MigrateGearVariantsFromBags(NightsFarmtrackerDB.count)
            NightsFarmtrackerDB.gearVariantsMigrated = true
        end
        if not NightsFarmtrackerAccountDB.lastSessionGearVariantsMigrated then
            ns.RepairLastSessionGearVariants()
            NightsFarmtrackerAccountDB.lastSessionGearVariantsMigrated = true
        end
        ns.RefreshHUD()
        ns.MaybePromptSessionResetMigration()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- First PEW after the addon loaded = login or /reload (never a plain
        -- load screen, we unregister below). PLAYER_LOGOUT can't tell logout
        -- from reload, so the relog reset is done here at the next login.
        local isInitialLogin, isReloadingUi = ...
        local db = NightsFarmtrackerDB
        if isReloadingUi then
            -- /reload: keep the session, but pause it
            if not db.paused then
                db.paused = true
                ns.StopTimer()
                ns.ApplyPauseVisuals()
            end
        elseif isInitialLogin then
            -- Relog: file the old session into History, start clean
            if (db.totalTime or 0) > 0 or next(db.count) or (db.lootedGold or 0) > 0 then
                -- Reset closes the Loot Log; a relog shouldn't, so put it back
                local logShown = db.logWindowShown
                ns.Reset()
                if logShown then
                    db.logWindowShown = true
                    ns.RestoreLogWindow()
                end
            end
        end

        -- ElvUI repositions the minimap; refresh corrects the button position.
        local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        if DBIcon then
            RunNextFrame(function() DBIcon:Refresh("NightsFarmtracker") end)
        end
        -- Some ElvUI/WindTools setups also re-anchor unrelated addon frames
        -- after entering the world (observed: our "TOP" anchor silently
        -- becomes "RIGHT", reintroducing the symmetric collapse/expand bug).
        -- Re-apply our saved TOP anchor here, after other addons had their turn.
        RunNextFrame(function()
            local pos = NightsFarmtrackerDB.pos
            if pos and pos[1] == "TOP" then
                MainFrame:ClearAllPoints()
                MainFrame:SetPoint("TOP", UIParent, "TOP", pos[3], pos[4])
            end
            if ns.ReapplyBaitPosition then ns.ReapplyBaitPosition() end
        end)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    elseif event == "BAG_UPDATE_DELAYED" and ns.pendingPriceUpdate then
        FlushPendingLoot()
        ns.UpdatePricesFromBags()

    elseif event == "CHAT_MSG_MONEY" and not NightsFarmtrackerDB.paused then
        local msg = ...
        if not msg or issecretvalue(msg) then return end
        local copper = 0
        local g = GOLD_PATTERN   and msg:match(GOLD_PATTERN)
        local s = SILVER_PATTERN and msg:match(SILVER_PATTERN)
        local c = COPPER_PATTERN and msg:match(COPPER_PATTERN)
        if g then copper = copper + tonumber(g) * 10000 end
        if s then copper = copper + tonumber(s) * 100   end
        if c then copper = copper + tonumber(c)         end
        if copper > 0 then
            NightsFarmtrackerDB.lootedGold = (NightsFarmtrackerDB.lootedGold or 0) + copper
            ns.RefreshHUD()
        end

    elseif event == "CHAT_MSG_LOOT" and not NightsFarmtrackerDB.paused then
        local msg, _, _, _, sender, _, _, _, _, _, lineID, guid = ...
        if type(lineID) ~= "number" or issecretvalue(lineID) then lineID = nil end
        if not msg or issecretvalue(msg) then return end

        -- isMe: sender GUID = own GUID (language-independent) OR prefix check
        -- ("Ihr "/"You ") OR sender = own player name
        local guidMatch   = guid and not issecretvalue(guid) and guid == UnitGUID("player")
        local prefixMatch = SELF_LOOT_PREFIX and msg:find(SELF_LOOT_PREFIX, 1, true)
        local senderShort = (sender and not issecretvalue(sender)) and sender:match("^([^%-]+)") or ""
        local senderMatch = senderShort ~= "" and senderShort == UnitName("player")
        if not guidMatch and not prefixMatch and not senderMatch then return end

        local color, linkData, itemName =
            msg:match("|cff(%x%x%x%x%x%x)|H(item:[^|]+)|h%[([^%]]+)%]|h")
        if not linkData then
            linkData, itemName = msg:match("|H(item:[^|]+)|h%[([^%]]+)%]|h")
        end
        if not linkData then return end

        local itemID = tonumber(linkData:match("^item:(%d+)"))
        if not itemID then return end

        -- Quantity sits at the very end ("...]|h|rx5."); strip the links first
        -- so an item name like "Box x2" can't pass for a quantity.
        local qty      = tonumber(msg:gsub("|H.-|h.-|h", ""):match("x(%d+)%D*$")) or 1
        local fullLink = "|H" .. linkData .. "|h[" .. itemName .. "]|h"

        -- Blizzard's double dispatch of one chat line (same lineID/text)
        if IsDuplicateLootLine(itemID, msg, lineID) then return end

        -- This chat line is the authoritative count. An ENCOUNTER_LOOT_RECEIVED
        -- that was waiting for it is now satisfied; either way remember it so
        -- a late encounter event for this item is skipped.
        ConsumePending(recentEncounterLoot, itemID)
        recentChatLoot[itemID] = (recentChatLoot[itemID] or 0) + 1
        C_Timer.After(CROSS_DEDUP_TTL, function()
            if recentChatLoot[itemID] and recentChatLoot[itemID] > 0 then
                recentChatLoot[itemID] = recentChatLoot[itemID] - 1
            end
        end)

        ProcessLoot({{
            itemID      = itemID,
            qty         = qty,
            link        = fullLink,
            itemName    = itemName,
            linkQuality = LINK_QUALITY[color and color:lower()],
        }})

    elseif event == "ENCOUNTER_LOOT_RECEIVED" and not NightsFarmtrackerDB.paused then
        -- Fires for encounter loot (boss drops etc.), locale-independent
        -- Args: encounterID, itemID, itemLink, quantity, playerName, className
        -- (Blizzard's API docs call the last two itemName/fileName, but
        -- BossBannerToast.lua reads them as player name and class file name)
        local _, itemID, link, qty, playerName = ...
        if issecretvalue(itemID) or issecretvalue(link) or issecretvalue(qty) or issecretvalue(playerName) then return end
        if not itemID or not link or link == "" then return end
        ns.Log("EncounterLoot", itemID, "qty=", qty, "player=", playerName)
        -- may arrive as "Name-Realm" for cross-realm players: compare the short name
        if type(playerName) ~= "string" or playerName:match("^([^%-]+)") ~= UnitName("player") then return end

        -- The chat line already counted it
        if ConsumePending(recentChatLoot, itemID) then return end

        -- The chat line is the authoritative count: wait for it. Only if none
        -- shows up count it from here so the item isn't lost.
        recentEncounterLoot[itemID] = 1
        C_Timer.After(ENCOUNTER_WAIT, function()
            if not ConsumePending(recentEncounterLoot, itemID) then return end
            if NightsFarmtrackerDB.paused then return end

            local color    = link:match("|cff(%x%x%x%x%x%x)|H")
            local itemName = link:match("%[(.-)%]")
            local fullLink = link:match("(|H.+|h%[.-%]|h)") or link

            ProcessLoot({{
                itemID      = itemID,
                qty         = tonumber(qty) or 1,
                link        = fullLink,
                itemName    = itemName,
                linkQuality = LINK_QUALITY[color and color:lower()],
            }})
        end)
    end
end)
