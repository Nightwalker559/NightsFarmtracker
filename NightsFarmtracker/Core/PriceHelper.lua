------------------------------------------------------------------------
-- Night's Farmtracker - Price Helper
-- AH price sources (Auctionator / TSM) and vendor sell price lookups.
------------------------------------------------------------------------
local ADDON_NAME, ns = ...

------------------------------------------------------------------------
-- Price source detection
------------------------------------------------------------------------
function ns.HasAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1 and true or false
end

function ns.HasTSM()
    return TSM_API ~= nil
end

-- Oribos Exchange: standalone AH price addon, no desktop app required.
-- Exposes a global OEMarketInfo(item, tbl) function - see GetOribosPrice.
function ns.HasOribos()
    return type(OEMarketInfo) == "function"
end

function ns.HasAnyAH()
    return ns.HasAuctionator() or ns.HasTSM() or ns.HasOribos()
end

------------------------------------------------------------------------
-- Expansion lookup (for the AH Price by Expansion filter)
-- Enum.ExpansionLevel values, per Blizzard's C_Item.GetItemInfo expacID.
------------------------------------------------------------------------
ns.EXPANSION_NAMES = {
    [0]  = "Classic",
    [1]  = "The Burning Crusade",
    [2]  = "Wrath of the Lich King",
    [3]  = "Cataclysm",
    [4]  = "Mists of Pandaria",
    [5]  = "Warlords of Draenor",
    [6]  = "Legion",
    [7]  = "Battle for Azeroth",
    [8]  = "Shadowlands",
    [9]  = "Dragonflight",
    [10] = "The War Within",
    [11] = "Midnight",
}
ns.EXPANSION_ORDER = {0,1,2,3,4,5,6,7,8,9,10,11}

------------------------------------------------------------------------
-- Item link normalization
------------------------------------------------------------------------
-- Canonical link for a link/ID: external price addons key their data on the
-- link GetItemInfo returns, so a raw stored link can miss. Memoized, since the
-- canonical form never changes and this runs several times per list rebuild;
-- only real lookups are cached (an uncached item returns the raw link and is
-- retried), and the cache is reset when it passes MEMO_LIMIT.
local MEMO_LIMIT = 2000
local cleanLinkMemo, cleanLinkCount = {}, 0

function ns.CleanItemLink(itemLink)
    if not itemLink then return nil end
    local clean = cleanLinkMemo[itemLink]
    if clean then return clean end
    clean = select(2, C_Item.GetItemInfo(itemLink))
    if not clean then return itemLink end
    if cleanLinkCount >= MEMO_LIMIT then
        wipe(cleanLinkMemo); cleanLinkCount = 0
    end
    cleanLinkMemo[itemLink] = clean
    cleanLinkCount = cleanLinkCount + 1
    return clean
end

-- Expansion ID (expacID) an item belongs to, per Enum.ExpansionLevel.
-- itemLink carries bonus IDs so this stays consistent with CleanItemLink's
-- other callers; falls back to itemID. Returns nil if uncached/unknown.
-- Memoized like CleanItemLink (an item's expansion never changes; the AH-by-
-- expansion filter asks for it for every item on every list rebuild).
local expansionMemo, expansionCount = {}, 0

function ns.GetItemExpansionID(data)
    local src = ns.CleanItemLink(data.itemLink) or data.itemID
    if not src then return nil end
    local expID = expansionMemo[src]
    if expID ~= nil then return expID end
    expID = select(15, C_Item.GetItemInfo(src))
    if expID ~= nil then
        if expansionCount >= MEMO_LIMIT then
            wipe(expansionMemo); expansionCount = 0
        end
        expansionMemo[src] = expID
        expansionCount = expansionCount + 1
    end
    return expID
end

------------------------------------------------------------------------
-- Auctionator
------------------------------------------------------------------------
function ns.GetAuctionatorPrice(itemID, itemLink)
    if not ns.HasAuctionator() then return nil end
    -- itemLink respects bonus IDs (random-stat gear); itemID alone can average
    -- across all stat rolls and mismatch Auctionator's own tooltip price.
    if itemLink then
        local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, ADDON_NAME, ns.CleanItemLink(itemLink))
        if ok and p and p > 0 then return p end
    end
    if not itemID then return nil end
    local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON_NAME, itemID)
    return ok and p and p > 0 and p or nil
end

------------------------------------------------------------------------
-- TSM
------------------------------------------------------------------------
ns.TSM_SOURCES = {"DBMarket","DBRegionMarketAvg","DBMinBuyout","VendorSell"}

function ns.GetTSMPrice(itemID)
    if not ns.HasTSM() or not itemID then return nil end
    local db     = NightsFarmtrackerDB
    local custom = db.tsmCustomSource and db.tsmCustomSource ~= "" and db.tsmCustomSource
    local source = custom or db.tsmPriceSource or "DBMarket"
    local ok, p  = pcall(TSM_API.GetCustomPriceValue, source, "i:"..itemID)
    return ok and type(p)=="number" and p > 0 and p or nil
end

------------------------------------------------------------------------
-- Oribos Exchange
------------------------------------------------------------------------
-- OEMarketInfo(item, tbl) fills tbl with ['market'] (this realm's median over
-- four days) and ['region'] (region median) in copper. Prefer the realm
-- price, else the region price. An item without realm data comes back as
-- market = 0, not nil, and 0 is truthy in Lua, so the fallback must check
-- for it explicitly.
local oribosResult = {}
function ns.GetOribosPrice(itemID, itemLink)
    if not ns.HasOribos() then return nil end
    local item = itemLink or itemID
    if not item then return nil end
    local ok, r = pcall(OEMarketInfo, item, oribosResult)
    if not ok or not r or r["input"] ~= item then return nil end
    local m = r["market"]
    local p = (type(m) == "number" and m > 0 and m) or r["region"]
    return type(p) == "number" and p > 0 and p or nil
end

------------------------------------------------------------------------
-- Price cache (session only, 1 h TTL). AH prices rarely change mid-session, so
-- RefreshHUD should not query the AH addon again for every item. Only hits are
-- cached: a miss (e.g. AH scan not ready after a fresh drop) is retried on the
-- next refresh. Cleared on logout and whenever a setting that changes the
-- price itself (AH source, TSM source) changes.
------------------------------------------------------------------------
ns.priceCache = ns.priceCache or {}
local PRICE_CACHE_TTL = 3600

function ns.ClearPriceCache()
    wipe(ns.priceCache)
    -- The last-known prices came from the old source/settings too
    if NightsFarmtrackerDB then NightsFarmtrackerDB.ahLast = nil end
end

-- Last successfully looked-up AH price per item/roll, kept in the character
-- SavedVariables (db.ahLast, wiped by ns.Reset once the session is filed).
-- The price cache above dies with the UI, but the relog save runs at the
-- very first PLAYER_ENTERING_WORLD, when Auctionator/TSM/Oribos may not
-- answer yet - without this the whole session was filed with no AH value.
-- Keyed by item ID + bonus IDs parsed straight from the link (no
-- GetItemInfo, so a raw and a canonical link of the same drop match, and
-- it works while the item cache is still cold at login).
local function StablePriceKey(itemID, itemLink)
    if type(itemLink) == "string" then
        local f = { strsplit(":", (itemLink:match("item:([%-%d:]*)") or "")) }
        local id = tonumber(f[1])
        if id then
            local n = tonumber(f[13]) or 0
            local parts = { id }
            for i = 1, n do parts[#parts + 1] = f[13 + i] or "" end
            return table.concat(parts, ":")
        end
    end
    return itemID and tostring(itemID) or nil
end

local function CachedPrice(key)
    local c = ns.priceCache[key]
    if c and (GetTime() - c.time) < PRICE_CACHE_TTL then return c.price end
    return nil
end

------------------------------------------------------------------------
-- Combined AH lookup / totals
------------------------------------------------------------------------
function ns.GetAHPriceForID(itemID, itemLink)
    if not itemID then return nil end
    local key = (itemLink and ns.CleanItemLink(itemLink)) or ("id:" .. itemID)
    local cached = CachedPrice(key)
    if cached then return cached end

    local db  = NightsFarmtrackerDB
    local src = db.ahSource or "auto"
    -- Item data not loaded yet (cold cache right after login): the link is
    -- not canonical and Auctionator can only answer with a rougher item-ID
    -- price. Prefer the exact price remembered from before, if there is one.
    local exact = not itemLink or C_Item.GetItemInfo(itemLink) ~= nil
    local pkey  = StablePriceKey(itemID, itemLink)
    if not exact and pkey and src ~= "none" and db.ahLast and db.ahLast[pkey] then
        return db.ahLast[pkey]
    end

    local p
    if src == "auctionator" then p = ns.GetAuctionatorPrice(itemID, itemLink)
    elseif src == "tsm"     then p = ns.GetTSMPrice(itemID)
    elseif src == "oribos"  then p = ns.GetOribosPrice(itemID, itemLink)
    else
        p = ns.GetAuctionatorPrice(itemID, itemLink) or ns.GetOribosPrice(itemID, itemLink) or ns.GetTSMPrice(itemID)
    end

    if p then
        -- An inexact answer is neither cached nor remembered
        if exact then
            ns.priceCache[key] = { price = p, time = GetTime() }
            if pkey and src ~= "none" then
                db.ahLast = db.ahLast or {}
                db.ahLast[pkey] = p
            end
        end
    elseif pkey and src ~= "none" and db.ahLast then
        -- Source has no answer right now (not loaded yet after login):
        -- use the last known price. Not cached, so live lookups keep retrying.
        p = db.ahLast[pkey]
    end
    return p
end

-- Stable key per roll of scaling gear (same item ID, different item level and
-- quality). itemLevel and quality are unreliable at loot time (cache miss, or
-- a uniform toast quality), so two rolls could share a fallback key; the
-- bonus-ID string in the link is fixed at drop and always differs. The link
-- goes through CleanItemLink first so incidental fields (uniqueID, linkLevel)
-- do not split identical drops into separate rows.
function ns.GearVariantKey(link)
    if not link then return "unknown" end
    local clean = ns.CleanItemLink(link) or link
    return clean:match("item[%-%d:]+") or clean
end

-- Display-only grouping of gear variants (stored per bonus-ID string) into
-- buckets per (itemLevel, quality). Scaling gear can carry a hidden per-drop
-- component in its bonus IDs that changes nothing the player sees, so such
-- drops sum into one row; only rolls with a different item level or quality
-- stay split. Storage keeps the raw keys, so per-roll AH pricing is unaffected.
function ns.GroupGearVariantsForDisplay(gearVariants)
    -- A variant can be missing its itemLevel (the __novariant__ placeholder
    -- MergeSessionInto creates for a merge-side with no breakdown at all, or
    -- genuinely old data) while still carrying its quality. Adventurer's/
    -- scaling gear ties item level to quality within one source, so another
    -- variant of the SAME item that quality already dropped at tells us
    -- which item level this one almost certainly was too - infer it instead
    -- of grouping it into its own separate "no ilvl" row.
    local ilvlByQuality = {}
    for _, gv in pairs(gearVariants) do
        if gv.itemLevel and gv.quality and not ilvlByQuality[gv.quality] then
            ilvlByQuality[gv.quality] = gv.itemLevel
        end
    end

    local groups = {}
    for _, gv in pairs(gearVariants) do
        if gv.amount > 0 then
            local itemLevel = gv.itemLevel or (gv.quality and ilvlByQuality[gv.quality])
            local gKey = tostring(itemLevel or "?") .. "|" .. tostring(gv.quality or "?")
            local g = groups[gKey]
            if not g then
                groups[gKey] = {
                    amount = gv.amount, quality = gv.quality, itemLevel = itemLevel,
                    itemLink = gv.itemLink, sellPrice = gv.sellPrice, ahTotal = gv.ahTotal,
                    ahAmount = gv.ahAmount,
                }
            else
                g.amount    = g.amount + gv.amount
                g.itemLink  = g.itemLink  or gv.itemLink
                g.sellPrice = g.sellPrice or gv.sellPrice
                if gv.ahTotal then g.ahTotal = (g.ahTotal or 0) + gv.ahTotal end
                g.ahAmount = (g.ahAmount ~= nil and gv.ahAmount ~= nil) and (g.ahAmount + gv.ahAmount) or nil
            end
        end
    end
    return groups
end

------------------------------------------------------------------------
-- Unified variant view (read-only). An item is stored in one of three shapes:
-- plain (one sellPrice/itemLink), gear (variants keyed by bonus-ID string) or
-- reagent (variants keyed by quality tier 1/2/3). This returns one normalized
-- list for any of them, so price code has a single loop. It only reads: writing
-- and merging stay in ProcessLoot and Sessions.lua.
--
-- Each variant: { amount, quality, itemLevel, itemLink, sellPrice, ahTotal,
-- priceItemID }.
--   - ahTotal is nil unless frozen in a saved session; live entries always
--     look the AH price up.
--   - priceItemID is the itemID to price against: set for reagent tiers (a
--     different itemID per tier), otherwise data.itemID.
------------------------------------------------------------------------
function ns.GetVariants(data)
    if data.variants then return data.variants end
    -- Legacy fallback: only reachable for the brief window before the
    -- one-time "unifiedVariants" repair (see Repairs.lua) has converted
    -- an item's old gearVariants/q+qIDs+qAHTotal fields into d.variants.
    if data.gearVariants then return data.gearVariants end
    if data.q and data.qIDs
    -- Only trust the per-tier breakdown when it actually adds up to the
    -- item's own tracked amount - GetReagentQualityInfo can occasionally
    -- mis-tag a tier (see ProcessLoot), inflating q[] far beyond amount.
    and ((data.q[1] or 0) + (data.q[2] or 0) + (data.q[3] or 0)) == data.amount then
        local variants
        for tier = 1, 3 do
            local tc = data.q[tier] or 0
            if tc > 0 and data.qIDs[tier] then
                variants = variants or {}
                variants[tier] = {
                    amount = tc, sellPrice = data.sellPrice,
                    ahTotal = data.qAHTotal and data.qAHTotal[tier],
                    priceItemID = data.qIDs[tier],
                }
            end
        end
        if variants then return variants end
    end
    return { default = {
        amount = data.amount, quality = data.quality, itemLink = data.itemLink,
        sellPrice = data.sellPrice, ahTotal = data.ahTotal, priceItemID = data.itemID,
    } }
end

-- Vendor sell price for one variant: trust its own recorded sellPrice,
-- else look one up live via its item link (bonus IDs → correct scaled
-- price) or, failing that, its price-lookup itemID. Shared by the per-variant
-- row/total math of Sessions.lua, ItemHelper.lua and UI.lua.
function ns.VariantSellPrice(gv, data)
    local sp = gv.sellPrice
    if not sp then
        local src = ns.CleanItemLink(gv.itemLink) or gv.priceItemID or data.itemID
        if src then sp = select(11, C_Item.GetItemInfo(src)) end
    end
    return sp
end

function ns.VendorTotal(data)
    local total, any = 0, false
    for _, gv in pairs(ns.GetVariants(data)) do
        local sp = ns.VariantSellPrice(gv, data)
        if sp and sp > 0 and gv.amount and gv.amount > 0 then
            total = total + sp * gv.amount; any = true
        end
    end
    return any and total or nil
end

function ns.AHTotal(data)
    if NightsFarmtrackerDB.ahSource == "none" then return nil end
    local total, any = 0, false
    for _, gv in pairs(ns.GetVariants(data)) do
        if gv.ahTotal ~= nil then
            -- Frozen (saved session) value - never re-priced live.
            total = total + gv.ahTotal
            if gv.ahTotal > 0 then any = true end
        else
            local p = ns.GetAHPriceForID(gv.priceItemID or data.itemID, gv.itemLink)
            if p then total = total + p * gv.amount; any = true end
        end
    end
    if not any and data.itemID and not (data.variants and ns.IsGear(data)) then
        -- Fallback for reagents whose tier IDs had no AH price at all:
        -- try the combined item once (matches the legacy per-tier path).
        local p = ns.GetAHPriceForID(data.itemID, data.itemLink)
        if p then total = p * data.amount; any = true end
    end
    return any and total or nil
end
