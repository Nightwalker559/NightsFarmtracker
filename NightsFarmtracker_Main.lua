------------------------------------------------------------------------
-- Night's Farmtracker - Main
-- Events, loot processing, timer.
------------------------------------------------------------------------
local _, ns = ...

local ADDON_NAME     = ns.ADDON_NAME
local TRADE_GOODS    = ns.TRADE_GOODS
local BIND_ON_EQUIP  = ns.BIND_ON_EQUIP
local BIND_ON_PICKUP = ns.BIND_ON_PICKUP
local MainFrame      = ns.MainFrame
local EventFrame

------------------------------------------------------------------------
-- Loot processing
------------------------------------------------------------------------
local PRICE_MAX_RETRIES = 3
local priceRetryCount   = 0

-- Cache reagent quality API at load time; nil if unavailable
local GetReagentQualityInfo = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo or nil

local pendingLoot = {}

local function ProcessLoot(items)
    local changed          = false
    local needsPriceUpdate = false

    for _, pending in ipairs(items) do
        local itemID = pending.itemID
        local qty    = pending.qty
        local link   = pending.link

        local name, _, quality, _, _, _, itemSubType, _, _, icon, sellPrice, classID, _, bindType =
            C_Item.GetItemInfo(link)

        -- Cache miss: defer until BAG_UPDATE_DELAYED when item info is available
        if not name then
            pendingLoot[#pendingLoot+1] = pending
            if not ns.pendingPriceUpdate then
                ns.pendingPriceUpdate = true
                priceRetryCount       = 0
                EventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
            end
        elseif classID then
            local db          = NightsFarmtrackerDB
            local shouldTrack = false

            if quality == 0 and sellPrice and sellPrice > 0 then
                -- Junk with vendor value
                shouldTrack = not db.excludedNames[ns.CAT_VENDOR] and not db.excludedNames[name]
            elseif classID == TRADE_GOODS
                or db.trackedNames[name]
                or (bindType == BIND_ON_EQUIP  and not db.excludedNames[ns.CAT_BOE])
                or (bindType == BIND_ON_PICKUP and quality and quality > 0
                    and not db.excludedNames[ns.CAT_BOP])
                or (quality and quality >= 2 and (not sellPrice or sellPrice == 0))
                or (quality and quality > 0 and sellPrice and sellPrice > 0) then
                -- Last two conditions: no-sell quality items (profession knowledge, crafting tokens)
                -- and any white+ sellable item (housing dyes/decor, consumables, etc.)
                shouldTrack = not db.excludedNames[name]
            end

            -- Apply filter mode
            if shouldTrack then
                local filter = db.filterMode or "all"
                if filter ~= "all" then
                    local isMat = (classID == TRADE_GOODS)
                    if filter == "mats"  and not isMat then shouldTrack = false end
                    if filter == "other" and isMat      then shouldTrack = false end
                end
            end

            if shouldTrack then
                local entry = db.count[name]
                if not entry then
                    entry          = { icon = icon, amount = 0 }
                    db.count[name] = entry
                end
                entry.amount      = entry.amount + qty
                entry.quality     = quality     or entry.quality
                entry.itemSubType = itemSubType or entry.itemSubType
                entry.classID     = entry.classID or classID
                entry.itemID      = entry.itemID or itemID
                entry.itemLink    = link

                if quality == 0               then entry.isVendorTrash = true end
                if bindType == BIND_ON_EQUIP  then entry.isBoE         = true end
                if bindType == BIND_ON_PICKUP then entry.isBoP         = true end

                -- Trust loot-link sell price for trade goods only;
                -- equipment prices resolved via bag scan; no-sell items skipped.
                if sellPrice and sellPrice > 0 and classID == TRADE_GOODS then
                    entry.sellPrice = sellPrice
                elseif not entry.noSell then
                    needsPriceUpdate = true
                end

                -- Quality tier tracking (crafting reagents Q1/Q2/Q3)
                if GetReagentQualityInfo then
                    local ok, qi = pcall(GetReagentQualityInfo, link)
                    if ok and qi then
                        local tier       = qi.quality
                        entry.q          = entry.q    or { 0, 0, 0 }
                        entry.qIDs       = entry.qIDs or {}
                        entry.q[tier]    = (entry.q[tier] or 0) + qty
                        entry.qIDs[tier] = itemID
                        db.qAtlas        = db.qAtlas or {}
                        db.qAtlas[tier]  = qi.iconChat
                    end
                end

                changed = true
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

    -- Build reverse map: itemID → entry (avoids O(items × bags × slots))
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
                            local sp = select(11, C_Item.GetItemInfo(bagLink))
                            if sp and sp > 0 then
                                data.sellPrice = sp
                                data.itemLink  = bagLink
                                updated        = true
                            else
                                data.noSell = true  -- no vendor price; skip future scans
                            end
                        end
                        byID[ci.itemID] = nil  -- matched, remove from map
                    end
                end
            end
        end
        -- Any entries still in byID were not found in bags
        if next(byID) then stillMissing = true end
    end

    if not stillMissing or priceRetryCount >= PRICE_MAX_RETRIES then
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
    local now = GetTime()
    NightsFarmtrackerDB.totalTime = (NightsFarmtrackerDB.totalTime or 0) + (now - lastTick)
    lastTick = now
    ns.UpdateTimerDisplay(ns.FormatTime(NightsFarmtrackerDB.totalTime))
    ns.UpdateGoldRate()
end

function ns.StartTimer()
    if timerTicker then return end
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
-- Event frame
------------------------------------------------------------------------
EventFrame = CreateFrame("Frame")

-- Dedup table: prevents double-counting the same item within a short window
local recentLoot   = {}
local DEDUP_WINDOW = 0.1  -- seconds

EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:RegisterEvent("CHAT_MSG_LOOT")

EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        ns.InitDB()
        ns.InitAccountDB()
        ns.InitSettings()

        -- Restore frame position
        MainFrame:ClearAllPoints()
        local p = NightsFarmtrackerDB.pos
        if #p == 4 then
            MainFrame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else
            MainFrame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
        end

        ns.UpdateTimerDisplay(ns.FormatTime(NightsFarmtrackerDB.totalTime))
        ns.ApplyPauseVisuals()
        ns.UpdateMinimapPosition(NightsFarmtrackerDB.minimapPos)
        if NightsFarmtrackerDB.visible then MainFrame:Show() end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if not NightsFarmtrackerDB.paused then ns.StartTimer() end
        ns.RefreshHUD()

    elseif event == "BAG_UPDATE_DELAYED" and ns.pendingPriceUpdate then
        FlushPendingLoot()
        ns.UpdatePricesFromBags()

    elseif event == "CHAT_MSG_LOOT" and not NightsFarmtrackerDB.paused then
        -- Fires for every item entering the bag regardless of loot method:
        -- normal, auto-loot, fast-loot addons, bonus drops, etc.
        local msg = ...
        local linkData, itemName = msg:match("|H(item:[^|]+)|h%[([^%]]+)%]|h")
        if not linkData then return end

        local itemID = tonumber(linkData:match("^item:(%d+)"))
        if not itemID then return end

        -- Prune and check dedup table
        local now = GetTime()
        for id, t in pairs(recentLoot) do
            if (now - t) > DEDUP_WINDOW * 10 then recentLoot[id] = nil end
        end
        if recentLoot[itemID] and (now - recentLoot[itemID]) < DEDUP_WINDOW then return end
        recentLoot[itemID] = now

        local qty      = tonumber(msg:match("x(%d+)")) or 1
        local fullLink = "|H" .. linkData .. "|h[" .. itemName .. "]|h"
        ProcessLoot({{ itemID = itemID, qty = qty, link = fullLink }})
    end
end)
