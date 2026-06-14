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

local function ProcessLoot(items)
    local changed          = false
    local needsPriceUpdate = false

    for _, pending in ipairs(items) do
        local itemID = pending.itemID
        local qty    = pending.qty
        local link   = pending.link

        local name, _, quality, _, _, _, itemSubType, _, _, icon, sellPrice, classID, _, bindType =
            C_Item.GetItemInfo(link)

        -- Cache miss: recover from link color (quality) + GetItemInfoInstant (classID/icon)
        -- C_Item.GetItemInfoInstant returns: itemType,itemSubType,itemEquipLoc,icon,classID,subClassID,bindType
        if not name then
            local _t, _s, _e, icon2, classID2, _sc, bindType2 = C_Item.GetItemInfoInstant(itemID)
            ns.Log("CacheMiss", itemID, "classID2=", classID2, "itemName=", pending.itemName)
            if classID2 and pending.itemName then
                name      = pending.itemName
                quality   = pending.linkQuality
                icon      = icon2
                classID   = classID2
                bindType  = bindType2
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

            if quality == 0 and sellPrice and sellPrice > 0 then
                -- Junk with vendor value
                shouldTrack = not db.excludedNames[ns.CAT_VENDOR] and not db.excludedNames[name]
            elseif classID == TRADE_GOODS
                or db.trackedNames[name]
                or (bindType == BIND_ON_EQUIP  and not db.excludedNames[ns.CAT_BOE])
                or (bindType == BIND_ON_PICKUP and quality and quality > 0
                    and not db.excludedNames[ns.CAT_BOP])
                or (quality and quality >= 2 and (not sellPrice or sellPrice == 0))
                or (quality and quality > 0  and sellPrice and sellPrice > 0) then
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

            ns.Log("shouldTrack=", shouldTrack, "for", name)

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

                -- Sell price: trust directly for trade goods and junk (no scaling)
                if sellPrice and sellPrice > 0 and (classID == TRADE_GOODS or quality == 0) then
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
                                data.noSell = true
                            end
                        end
                        byID[ci.itemID] = nil
                    end
                end
            end
        end
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
-- Slash commands
------------------------------------------------------------------------
SLASH_FARMTRACK1 = "/nft"
SlashCmdList["FARMTRACK"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "" then
        -- Toggle main window
        if MainFrame:IsShown() then
            NightsFarmtrackerDB.visible = false; MainFrame:Hide()
        else
            NightsFarmtrackerDB.visible = true;  MainFrame:Show()
        end
    elseif cmd == "debug" then
        ns.debugMode = not ns.debugMode
        print("|cff30b0c0Night's Farmtracker:|r Debug " .. (ns.debugMode and "|cff00ff00AN|r" or "|cffff4444AUS|r"))
    elseif cmd == "test" then
        local db = NightsFarmtrackerDB
        local n = 0; for _ in pairs(db.count) do n = n + 1 end
        print("|cff30b0c0NFT:|r paused=" .. tostring(db.paused) .. " items=" .. n)
        for name, data in pairs(db.count) do
            print("  " .. name .. " x" .. data.amount .. " classID=" .. tostring(data.classID) .. " sell=" .. tostring(data.sellPrice))
        end
    else
        print("|cff30b0c0Night's Farmtracker:|r /nft · /nft debug · /nft test")
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

        local p = NightsFarmtrackerDB.pos
        MainFrame:ClearAllPoints()
        MainFrame:SetPoint(p[1], UIParent, p[2], p[3], p[4])

        ns.UpdateTimerDisplay(ns.FormatTime(NightsFarmtrackerDB.totalTime))
        ns.ApplyPauseVisuals()
        ns.UpdateMinimapPosition(NightsFarmtrackerDB.minimapPos)
        if NightsFarmtrackerDB.visible then MainFrame:Show() end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if not NightsFarmtrackerDB.paused then ns.StartTimer() end
        ns.SetMinimapVisible(not NightsFarmtrackerDB.minimapHidden)
        ns.SetExpanded(NightsFarmtrackerDB.expanded)
        ns.RefreshHUD()

    elseif event == "BAG_UPDATE_DELAYED" and ns.pendingPriceUpdate then
        FlushPendingLoot()
        ns.UpdatePricesFromBags()

    elseif event == "CHAT_MSG_LOOT" and not NightsFarmtrackerDB.paused then
        local msg = ...

        -- WoW loot messages may or may not include a color prefix before the item link.
        -- Try with color first (quality extraction), then without as fallback.
        local color, linkData, itemName =
            msg:match("|cff(%x%x%x%x%x%x)|H(item:[^|]+)|h%[([^%]]+)%]|h")
        if not linkData then
            linkData, itemName = msg:match("|H(item:[^|]+)|h%[([^%]]+)%]|h")
        end
        if not linkData then return end

        local itemID = tonumber(linkData:match("^item:(%d+)"))
        if not itemID then return end

        ns.Log("LOOT itemID=", itemID, "name=", itemName, "color=", color)

        -- Prune and check dedup table
        local now = GetTime()
        for id, t in pairs(recentLoot) do
            if (now - t) > DEDUP_WINDOW * 10 then recentLoot[id] = nil end
        end
        if recentLoot[itemID] and (now - recentLoot[itemID]) < DEDUP_WINDOW then return end
        recentLoot[itemID] = now

        local qty      = tonumber(msg:match("x(%d+)")) or 1
        local fullLink = "|H" .. linkData .. "|h[" .. itemName .. "]|h"
        ProcessLoot({{
            itemID      = itemID,
            qty         = qty,
            link        = fullLink,
            itemName    = itemName,
            linkQuality = LINK_QUALITY[color and color:lower()],
        }})
    end
end)
