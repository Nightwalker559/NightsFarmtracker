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

-- Localized self-loot prefix derived from WoW's own global string.
-- EN: "You receive loot: "  /  DE: "Ihr erhaltet Beute: "
-- Only messages starting with this prefix belong to the player.
-- "Ihr " (DE) / "You " (EN) — erstes Wort aus LOOT_ITEM_SELF.
-- Deckt alle eigenen Loot-Varianten ab: Beute, Gegenstände, einen Gegenstand, etc.
-- Andere Spieler beginnen mit ihrem Charakternamen → werden gefiltert.
local SELF_LOOT_PREFIX    = LOOT_ITEM_SELF and LOOT_ITEM_SELF:match("^(%S+%s)") or nil

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

            if db.excludedNames[name] then
                -- name explicitly excluded
            elseif db.trackedNames and db.trackedNames[name] then
                shouldTrack = true
            elseif quality == 0 then
                -- grey: vendorbar (bekannt oder unbekannt=Cache-Miss, später auflösen) + Junk-Kategorie nicht excluded
                if sellPrice ~= nil then
                    shouldTrack = (sellPrice > 0) and not db.excludedNames[ns.CAT_VENDOR]
                else
                    shouldTrack = not db.excludedNames[ns.CAT_VENDOR]
                end
            else
                -- quality > 0: tracken sofern nicht definitiv unverkäuflich.
                -- sellPrice == nil = Cache-Miss = unbekannt → tracken und Preis später auflösen.
                -- Nur überspringen wenn sellPrice explizit 0 UND BoP UND kein Trade Good.
                local definitelyUnsellable = (sellPrice == 0)
                                          and (bindType == BIND_ON_PICKUP)
                                          and (classID ~= TRADE_GOODS)
                shouldTrack = not definitelyUnsellable
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
                -- canAH: nur BoE und ungebundene Items (0/nil) sowie Trade Goods dürfen auf dem AH.
                -- BoP (1), Kriegsmeute-/Account-gebunden und alles andere → nur Vendor.
                if entry.canAH == nil then
                    entry.canAH = (bindType == BIND_ON_EQUIP)
                               or (bindType == 0 or bindType == nil)
                               or (classID == TRADE_GOODS)
                end

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
                            else
                                data.noSell = true
                            end
                            -- classID / Bind-Flags nachladen wenn beim Looten nicht aufgelöst
                            if not data.classID then
                                local _, _, _, _, cID, _, bType = C_Item.GetItemInfoInstant(bagLink)
                                if cID then data.classID = cID end
                                if bType then
                                    if bType == BIND_ON_EQUIP  then data.isBoE = true end
                                    if bType == BIND_ON_PICKUP then data.isBoP = true end
                                    if data.canAH == nil then
                                        data.canAH = (bType == BIND_ON_EQUIP)
                                                  or (bType == 0)
                                                  or (data.classID == TRADE_GOODS)
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
    elseif cmd == "filter" then
        ns.ToggleFilterWindow()
    elseif cmd == "test" then
        local db = NightsFarmtrackerDB
        local n = 0; for _ in pairs(db.count) do n = n + 1 end
        print("|cff30b0c0NFT:|r paused=" .. tostring(db.paused) .. " items=" .. n)
        for name, data in pairs(db.count) do
            print("  " .. name .. " x" .. data.amount .. " classID=" .. tostring(data.classID) .. " sell=" .. tostring(data.sellPrice))
        end
    else
        print("|cff30b0c0Night's Farmtracker:|r /nft · /nft debug · /nft filter · /nft test")
    end
end

------------------------------------------------------------------------
-- Event frame
------------------------------------------------------------------------
EventFrame = CreateFrame("Frame")

-- Within-CHAT_MSG_LOOT dedup: verhindert dass dasselbe Event doppelt feuert
local recentLoot   = {}
local DEDUP_WINDOW = 0.1  -- seconds

-- Cross-event dedup: verhindert Doppelzählung zwischen CHAT_MSG_LOOT und ENCOUNTER_LOOT_RECEIVED
local recentChatLoot      = {}  -- gesehen von CHAT_MSG_LOOT
local recentEncounterLoot = {}  -- gesehen von ENCOUNTER_LOOT_RECEIVED
local CROSS_DEDUP_TTL     = 2   -- seconds

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
        ns.InitSettings()

        local p = NightsFarmtrackerDB.pos
        MainFrame:ClearAllPoints()
        MainFrame:SetPoint(p[1], UIParent, p[2], p[3], p[4])

        ns.UpdateTimerDisplay(ns.FormatTime(NightsFarmtrackerDB.totalTime))
        ns.ApplyPauseVisuals()
        ns.InitMinimapButton()
        if NightsFarmtrackerDB.visible then MainFrame:Show() end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        if not NightsFarmtrackerDB.paused then ns.StartTimer() end
        ns.SetMinimapVisible(not (NightsFarmtrackerDB.minimap and NightsFarmtrackerDB.minimap.hide))
        ns.SetExpanded(NightsFarmtrackerDB.expanded)
        ns.UpdateHistoryBtn()
        ns.RefreshHUD()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- ElvUI repositioniert die Minimap; Refresh korrigiert die Button-Position.
        local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        if DBIcon then
            C_Timer.After(0, function() DBIcon:Refresh("NightsFarmtracker") end)
        end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    elseif event == "BAG_UPDATE_DELAYED" and ns.pendingPriceUpdate then
        FlushPendingLoot()
        ns.UpdatePricesFromBags()

    elseif event == "CHAT_MSG_MONEY" and not NightsFarmtrackerDB.paused then
        local msg = ...
        local copper = 0
        local g = msg:match("(%d+)%s*[Gg]old")
        local s = msg:match("(%d+)%s*[Ss]il")                                    -- Silber / Silver
        local c = msg:match("(%d+)%s*[Kk]upfer") or msg:match("(%d+)%s*[Cc]opper") -- Kupfer / Copper
        if g then copper = copper + tonumber(g) * 10000 end
        if s then copper = copper + tonumber(s) * 100   end
        if c then copper = copper + tonumber(c)         end
        if copper > 0 then
            NightsFarmtrackerDB.lootedGold = (NightsFarmtrackerDB.lootedGold or 0) + copper
            ns.RefreshHUD()
        end

    elseif event == "CHAT_MSG_LOOT" and not NightsFarmtrackerDB.paused then
        local msg, _, _, _, sender = ...

        -- isMe: Prefix-Check ("Ihr "/"You ") ODER Sender = eigener Spielername
        local prefixMatch = SELF_LOOT_PREFIX and msg:find(SELF_LOOT_PREFIX, 1, true)
        local senderShort = sender and sender:match("^([^%-]+)") or ""
        local senderMatch = senderShort ~= "" and senderShort == UnitName("player")
        if not prefixMatch and not senderMatch then return end

        local color, linkData, itemName =
            msg:match("|cff(%x%x%x%x%x%x)|H(item:[^|]+)|h%[([^%]]+)%]|h")
        if not linkData then
            linkData, itemName = msg:match("|H(item:[^|]+)|h%[([^%]]+)%]|h")
        end
        if not linkData then return end

        local itemID = tonumber(linkData:match("^item:(%d+)"))
        if not itemID then return end

        local qty      = tonumber(msg:match("x(%d+)")) or 1
        local fullLink = "|H" .. linkData .. "|h[" .. itemName .. "]|h"

        -- Within-event dedup (itemID:qty Key, 0.1s Fenster)
        local now      = GetTime()
        local dedupKey = itemID .. ":" .. qty
        for k, t in pairs(recentLoot) do
            if (now - t) > DEDUP_WINDOW * 10 then recentLoot[k] = nil end
        end
        if recentLoot[dedupKey] and (now - recentLoot[dedupKey]) < DEDUP_WINDOW then return end
        recentLoot[dedupKey] = now

        -- Cross-event dedup: ENCOUNTER_LOOT_RECEIVED war schneller → überspringen
        if recentEncounterLoot[itemID] and recentEncounterLoot[itemID] > 0 then
            recentEncounterLoot[itemID] = recentEncounterLoot[itemID] - 1
            return
        end
        -- Markieren damit ENCOUNTER_LOOT_RECEIVED es überspringt falls es danach kommt
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
        -- Feuert für Encounter-Loot (Boss-Drops etc.) locale-unabhängig
        -- Args: encounterID, encounterName, difficultyID, groupSize, itemLink, quantity, playerName
        local _, _, _, _, link, qty, playerName = ...
        if not link or link == "" then return end
        if playerName ~= UnitName("player") then return end

        local itemID = tonumber(link:match("item:(%d+)"))
        if not itemID then return end

        -- Cross-event dedup: CHAT_MSG_LOOT war schneller → überspringen
        if recentChatLoot[itemID] and recentChatLoot[itemID] > 0 then
            recentChatLoot[itemID] = recentChatLoot[itemID] - 1
            return
        end
        -- Markieren damit CHAT_MSG_LOOT es überspringt falls es danach kommt
        recentEncounterLoot[itemID] = (recentEncounterLoot[itemID] or 0) + 1
        C_Timer.After(CROSS_DEDUP_TTL, function()
            if recentEncounterLoot[itemID] and recentEncounterLoot[itemID] > 0 then
                recentEncounterLoot[itemID] = recentEncounterLoot[itemID] - 1
            end
        end)

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
    end
end)