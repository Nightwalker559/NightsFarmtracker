------------------------------------------------------------------------
-- Night's Farmtracker - Main
-- Events, loot processing, timer, slash commands.
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

-- First word of WoW's own self-loot string ("You " / "Ihr "): only chat lines
-- starting with it belong to the player; other players' lines start with
-- their name.
local SELF_LOOT_PREFIX = LOOT_ITEM_SELF and LOOT_ITEM_SELF:match("^(%S+%s)") or nil

-- Midnight (12.x) can hand addons "secret values": any string operation on
-- one throws, so the event handlers bail out on them.
local issecretvalue = ns.IsSecret

-- Coin patterns from WoW's own global strings, so CHAT_MSG_MONEY parses in
-- every client language.
local GOLD_PATTERN   = ns.FormatToPattern(GOLD_AMOUNT)
local SILVER_PATTERN = ns.FormatToPattern(SILVER_AMOUNT)
local COPPER_PATTERN = ns.FormatToPattern(COPPER_AMOUNT)

local GetReagentQualityInfo = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo or nil

-- Item link color -> quality (spares the GetItemInfo cache for the quality)
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

-- BoE, Bind-on-Use, unbound items (0/nil) and Trade Goods may go on the AH;
-- BoP, Warbound and everything else is vendor-only.
local function CanAH(bindType, classID)
    return (bindType == BIND_ON_EQUIP)
        or (bindType == BIND_ON_USE)
        or (bindType == 0 or bindType == nil)
        or (classID == TRADE_GOODS)
end

-- Starts watching the bags (BAG_UPDATE_DELAYED) so sell prices that were not
-- cached at loot time can be filled in, see UpdatePricesFromBags.
local function RequestPriceUpdate()
    if ns.pendingPriceUpdate then return end
    ns.pendingPriceUpdate = true
    priceRetryCount       = 0
    EventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
end

-- Whether a looted item enters the session count: not ignored, blacklisted
-- or excluded, and not unsellable. Unknown prices (cache miss) are tracked
-- and resolved later.
local function ShouldTrack(db, itemID, name, classID, quality, sellPrice, bindType, catData)
    if ns.IsIgnoredItemClass(classID) or ns.IsBlacklisted(itemID) or ns.IsBlacklistCategory(catData)
       or db.excludedItemIDs[itemID] or db.excludedNames[name]
       or db.excludedNames[ns.CategoryName(catData)] then
        return false
    end
    if quality == 0 then
        return sellPrice == nil or sellPrice > 0   -- grey: vendor junk
    end
    -- Quest items report sellPrice 0 but are not necessarily BoP; anything
    -- else is skipped only when it is explicitly unsellable.
    if classID == QUEST_CLASS then return false end
    return not (sellPrice == 0 and bindType == BIND_ON_PICKUP and classID ~= TRADE_GOODS)
end

local function NewVariant(variants, key)
    local gv = variants[key]
    if not gv then
        gv = { amount = 0 }
        variants[key] = gv
    end
    return gv
end

-- Scaling gear (same item ID, different item level/quality per drop) gets one
-- variant per roll, keyed by bonus-ID string, so amounts and prices don't mix.
-- The threshold sound is checked in BuildHUD, not here: the AH price of an
-- exact roll can take a moment to become queryable.
local function RecordGearVariant(entry, link, qty, quality, itemLevel, sellPrice)
    entry.variants = entry.variants or {}
    local gv = NewVariant(entry.variants, ns.GearVariantKey(link))
    gv.amount    = gv.amount + qty
    gv.quality   = quality   or gv.quality
    gv.itemLevel = itemLevel or gv.itemLevel
    gv.itemLink  = link
    if sellPrice and sellPrice > 0 then gv.sellPrice = sellPrice end
end

local function TierSum(v)
    return (v[1] and v[1].amount or 0) + (v[2] and v[2].amount or 0) + (v[3] and v[3].amount or 0)
end

-- Crafting-reagent quality tiers (Q1/Q2/Q3) are variants keyed 1/2/3. Returns
-- the rank badge markup for the loot log, or nil.
local function RecordReagentTier(db, entry, itemID, link, qty, sellPrice)
    if not GetReagentQualityInfo then return end
    local ok, qi = pcall(GetReagentQualityInfo, link)
    if not (ok and qi) then return end
    local tier = qi.quality
    local v = entry.variants
    local hasTiers = v and (v[1] or v[2] or v[3])
    local qSum = hasTiers and TierSum(v) or 0
    -- Self-heal: the breakdown was already inconsistent with the item's own
    -- amount before this loot (e.g. a corrupted save merged in): drop it so
    -- tracking can recover instead of freezing the bad numbers.
    if hasTiers and qSum ~= (entry.amount - qty) then
        v[1], v[2], v[3] = nil, nil, nil
        qSum = 0
    end
    -- GetReagentQualityInfo can report a tier that does not fit the item
    -- (seen with reagents whose quality is fixed by their itemID, e.g.
    -- per-rank ore); accepting it would push the tier total above the amount.
    if not tier or qSum + qty > entry.amount then return end
    entry.variants = entry.variants or {}
    local gv = NewVariant(entry.variants, tier)
    gv.amount      = gv.amount + qty
    gv.priceItemID = itemID
    if sellPrice and sellPrice > 0 then gv.sellPrice = sellPrice end
    db.qAtlas       = db.qAtlas or {}
    db.qAtlas[tier] = qi.iconChat
    return ns.RankBadgeMarkup(qi.iconChat, tier)
end

-- Adds one looted stack to the session count. Returns true if the item still
-- needs a price lookup from the bags.
local function AddToCount(db, pending, info)
    local itemID, qty, link = pending.itemID, pending.qty, pending.link
    local entry = db.count[itemID]
    if not entry then
        entry = { icon = info.icon, amount = 0, name = info.name }
        db.count[itemID] = entry
    end
    entry.amount      = entry.amount + qty
    entry.name        = entry.name or info.name
    entry.quality     = info.quality     or entry.quality
    entry.itemSubType = info.itemSubType or entry.itemSubType
    entry.classID     = entry.classID    or info.classID
    entry.subClassID  = entry.subClassID or info.subClassID
    entry.itemID      = entry.itemID     or itemID
    -- Gear keeps its link per variant; a top-level copy would only go stale.
    if not ns.IsGearClass(info.classID) then entry.itemLink = link end

    if info.quality == 0                   then entry.isVendorTrash = true end
    if info.bindType == BIND_ON_EQUIP      then entry.isBoE         = true end
    if info.bindType == BIND_ON_PICKUP     then entry.isBoP         = true end
    if BIND_TO_ACCOUNT[info.bindType]      then entry.isBoA         = true end
    if info.isCosmetic                     then entry.isCosmetic    = true end
    if entry.canAH == nil then entry.canAH = CanAH(info.bindType, info.classID) end

    local needsPrice = false
    -- Trade goods and junk don't scale: the loot-time price is trusted.
    if info.sellPrice and info.sellPrice > 0 and (info.classID == TRADE_GOODS or info.quality == 0) then
        entry.sellPrice = info.sellPrice
    elseif not entry.noSell then
        needsPrice = true
    end

    if ns.IsGearClass(info.classID) then
        RecordGearVariant(entry, link, qty, info.quality, info.itemLevel, info.sellPrice)
    end
    info.rankIcon = RecordReagentTier(db, entry, itemID, link, qty, info.sellPrice)
    return needsPrice
end

-- GetItemInfo for a pending loot entry. On a cache miss it falls back to the
-- chat link (name, quality color) plus GetItemInfoInstant (class, icon); with
-- neither, the entry is queued for a retry and nil is returned.
local function ResolveItemInfo(pending)
    local name, _, quality, itemLevel, _, _, itemSubType, _, _, icon, sellPrice, classID, subClassID, bindType =
        C_Item.GetItemInfo(pending.link)
    if not name then
        local _, _, _, _, icon2, classID2, subClassID2 = C_Item.GetItemInfoInstant(pending.itemID)
        ns.Log("CacheMiss", pending.itemID, "classID2=", classID2, "itemName=", pending.itemName)
        if classID2 and pending.itemName then
            name, quality, icon, classID, subClassID = pending.itemName, pending.linkQuality, icon2, classID2, subClassID2
        else
            pendingLoot[#pendingLoot + 1] = pending
            RequestPriceUpdate()
        end
    end
    ns.Log("ProcessLoot", name, "classID=", classID, "quality=", quality)
    if not (name and classID) then return nil end
    return {
        name = name, quality = quality, itemLevel = itemLevel, itemSubType = itemSubType, icon = icon,
        sellPrice = sellPrice, classID = classID, subClassID = subClassID, bindType = bindType,
    }
end

-- One looted stack as ProcessLoot wants it. `color` is the link's color code
-- (hex), `itemName` the bracketed name; both may be nil.
local function NewPendingLoot(itemID, qty, link, itemName, color)
    return {
        itemID      = itemID,
        qty         = qty,
        link        = link,
        itemName    = itemName,
        linkQuality = LINK_QUALITY[color and color:lower()],
    }
end

local function ProcessLoot(items)
    local changed, needsPriceUpdate = false, false

    for _, pending in ipairs(items) do
        local info = ResolveItemInfo(pending)
        if info then
            local db = NightsFarmtrackerDB
            local classID, quality, bindType = info.classID, info.quality, info.bindType
            -- Cosmetic weapons/armor (transmog only) get their own category.
            info.isCosmetic = ns.IsGearClass(classID) and C_Item.IsCosmeticItem(pending.link) or nil

            -- Category data from what GetItemInfo knows right now, so a whole
            -- excluded/blacklisted category is caught before it is counted.
            local catData = {
                classID = classID, subClassID = info.subClassID, quality = quality,
                itemSubType = info.itemSubType, isVendorTrash = (quality == 0),
                isBoE = (bindType == BIND_ON_EQUIP), isBoP = (bindType == BIND_ON_PICKUP),
                isBoA = BIND_TO_ACCOUNT[bindType] or nil, isCosmetic = info.isCosmetic,
            }
            ns.RecordItemDBEntry(pending.itemID, info.name, pending.link, quality, classID, info.subClassID, catData)

            local shouldTrack = ShouldTrack(db, pending.itemID, info.name, classID, quality, info.sellPrice, bindType, catData)
            ns.Log("shouldTrack=", shouldTrack, "for", info.name)
            if shouldTrack then
                if AddToCount(db, pending, info) then needsPriceUpdate = true end
                changed = true
                ns.AddLogEntry(info.icon, info.name, pending.qty, pending.link, quality,
                    info.rankIcon or ns.RankIconFromLink(pending.link))
            end
        end
    end

    if changed then
        ns.RefreshHUD()
        if needsPriceUpdate then RequestPriceUpdate() end
        -- Auctionator/TSM can take a moment after looting before an AH price
        -- for an exact roll is queryable; without a re-check an item priced
        -- as vendor-only here would stay that way until the next loot. Only
        -- the last loot of a burst fires its timer (ticket), so N quick
        -- drops cost one delayed rebuild.
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
-- Deferred price update: scans the bags for correct sell prices
------------------------------------------------------------------------
function ns.CleanupPriceUpdate()
    if ns.pendingPriceUpdate then
        EventFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        ns.pendingPriceUpdate = false
    end
    priceRetryCount = 0
end

-- Gear variant bucket matching a bag link. The exact key can differ once the
-- item is fully cached (the bonus-ID tail can shift), so fall back to the
-- bucket with the same item level and quality.
local function FindGearVariant(data, bagLink, iLevel, iQuality)
    local gv = data.variants[ns.GearVariantKey(bagLink)]
    if gv or not (iLevel and iQuality) then return gv end
    for _, candidate in pairs(data.variants) do
        if candidate.itemLevel == iLevel and candidate.quality == iQuality then return candidate end
    end
end

-- Takes the authoritative item data from a cached bag link and overwrites the
-- loot-time guesses (quality from a chat link color, class/bind flags from a
-- cache miss). Quality corrections are passed on to the Loot Log, whose
-- entries are otherwise never revisited.
local function ApplyBagItemInfo(data, bag, slot, bagLink)
    local _, _, iQuality, iLevel, _, _, _, _, _, _, sp, cID, subID, bType = C_Item.GetItemInfo(bagLink)
    if sp and sp > 0 then
        data.sellPrice = sp
        if not ns.IsGearClass(cID) then data.itemLink = bagLink end
    else
        data.noSell = true
    end
    if iQuality and iQuality ~= data.quality then
        data.quality = iQuality
        if iQuality == 0 then data.isVendorTrash = true end
        ns.UpdateLogEntryQuality(data.itemID, iQuality)
    end
    if not cID then return end

    data.classID    = cID
    data.subClassID = subID
    if bType == BIND_ON_EQUIP  then data.isBoE = true end
    if bType == BIND_ON_PICKUP then data.isBoP = true end
    if BIND_TO_ACCOUNT[bType]  then data.isBoA = true end
    data.canAH = CanAH(bType, cID)
    if ns.IsGearClass(cID) then
        data.isCosmetic = C_Item.IsCosmeticItem(bagLink) or nil
        local gv = data.variants and FindGearVariant(data, bagLink, iLevel, iQuality)
        if gv then
            gv.itemLink = bagLink
            if sp and sp > 0 then gv.sellPrice = sp end
            if iQuality then gv.quality = iQuality end
            if iLevel then gv.itemLevel = iLevel end
        end
    end
    -- Older clients report Warbound-until-equipped gear as plain BoE: detect
    -- it through the item location so it is still flagged BoA (vendor-only).
    if data.canAH and not data.isBoA and C_Item.IsBoundToAccountUntilEquip then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if loc and loc:IsValid() and C_Item.IsBoundToAccountUntilEquip(loc) then
            data.canAH = false
            data.isBoA = true
        end
    end
end

function ns.UpdatePricesFromBags()
    local updated = false

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
                local data = ci and byID[ci.itemID]
                local bagLink = data and C_Container.GetContainerItemLink(bag, slot)
                -- no link yet: keep the item in byID for another slot or retry
                if bagLink then
                    ApplyBagItemInfo(data, bag, slot, bagLink)
                    updated = true
                    byID[ci.itemID] = nil
                end
            end
        end
    end

    local stillMissing = next(byID) ~= nil
    if not stillMissing or priceRetryCount >= PRICE_MAX_RETRIES then
        -- Items never found in any bag after the last retry are marked
        -- noSell, so they only show if they have an AH price.
        for _, data in pairs(byID) do
            data.noSell = true
            updated = true
        end
        ns.CleanupPriceUpdate()
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
        ns.Print(ns.L["session_length_reached"])
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
local SLASH_COMMANDS = {
    debug        = function() ns.ToggleDebugMode() end,
    filter       = function() ns.ToggleFilterWindow() end,
    venom        = function() ns.ToggleVenomTracker() end,
    venomdump    = function() ns.DumpVenomTooltip() end,
    bait         = function() ns.ToggleBaitFrame() end,
    hud          = function(args) ns.HudSlash(args) end,
    export       = function() ns.ToggleExportWindow() end,
    test         = function() ns.DebugTest() end,
    itemdb       = function() ns.DebugItemDB() end,
    monthdump    = function(args) ns.DebugMonthDump(tonumber(args)) end,
    sessionsdump = function() ns.DebugSessionsDump() end,
    repairprices = function() ns.RepairLastSessionPrices() end,
}

SLASH_FARMTRACK1 = "/nft"
SlashCmdList["FARMTRACK"] = function(msg)
    local cmd, args = (msg or ""):match("^%s*(%S*)%s*(.*)$")
    cmd = cmd:lower()
    if cmd == "" then
        ns.ToggleMainFrame()
    elseif SLASH_COMMANDS[cmd] then
        SLASH_COMMANDS[cmd](args)
    else
        ns.Print("/nft · /nft debug · /nft filter · /nft venom · /nft venomdump · /nft bait · /nft hud · /nft export · /nft test · /nft itemdb · /nft monthdump [itemID] · /nft sessionsdump · /nft repairprices")
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
local recentLootLine  = {}  -- itemID -> { text, at, lineID }
local recentLootCount = 0
local DUP_WINDOW      = 0.02  -- seconds, "this frame or the next"
local LOOT_LINE_PRUNE = 100   -- entries before the stale ones are dropped

local function PruneLootLines(now)
    for id, rec in pairs(recentLootLine) do
        if now - rec.at >= DUP_WINDOW then
            recentLootLine[id] = nil
            recentLootCount = recentLootCount - 1
        end
    end
end

local function IsDuplicateLootLine(itemID, msg, lineID)
    local now = GetTime()
    local rec = recentLootLine[itemID]
    local lastText, lastAt, lastLineID
    if rec then
        lastText, lastAt, lastLineID = rec.text, rec.at, rec.lineID
    else
        -- an entry older than the window can never match again, so the table
        -- only holds what was looted in the last moments
        if recentLootCount >= LOOT_LINE_PRUNE then PruneLootLines(now) end
        rec = {}
        recentLootLine[itemID] = rec
        recentLootCount = recentLootCount + 1
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
        ns.RefreshButtonTint()

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
            local x, y = ns.AnchorToTop(MainFrame)
            if x then NightsFarmtrackerDB.pos = {"TOP", "TOP", x, y} end
        end

        ns.UpdateTimerDisplay()
        ns.ApplyPauseVisuals()
        ns.InitMinimapButton()
        if NightsFarmtrackerDB.visible then MainFrame:Show() end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if not NightsFarmtrackerDB.paused then ns.StartTimer() end
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
        RunNextFrame(ns.RefreshMinimapButton)
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
            ns.ReapplyBaitPosition()
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

        ProcessLoot({ NewPendingLoot(itemID, qty, fullLink, itemName, color) })

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

            ProcessLoot({ NewPendingLoot(itemID, tonumber(qty) or 1, fullLink, itemName, color) })
        end)
    end
end)
