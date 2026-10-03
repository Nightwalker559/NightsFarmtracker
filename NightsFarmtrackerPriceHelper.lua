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
-- Canonical item link for a given link/ID. Passing the raw stored link straight
-- to an external addon's API can mismatch its own internal lookup if the link
-- isn't in the exact form that addon expects; GetItemInfo returns the
-- canonical link Auctionator (and others) key their price data on.
function ns.CleanItemLink(itemLink)
    if not itemLink then return nil end
    return select(2, C_Item.GetItemInfo(itemLink)) or itemLink
end

-- Expansion ID (expacID) an item belongs to, per Enum.ExpansionLevel.
-- itemLink carries bonus IDs so this stays consistent with CleanItemLink's
-- other callers; falls back to itemID. Returns nil if uncached/unknown.
function ns.GetItemExpansionID(data)
    local src = ns.CleanItemLink(data.itemLink) or data.itemID
    if not src then return nil end
    return select(15, C_Item.GetItemInfo(src))
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
-- OEMarketInfo(item, tbl) fills tbl with (among others) ['market'] (this
-- realm's median price over the past 4 days) and ['region'] (median across
-- the region) in copper - see OribosExchange.lua's header comment. Mirrors
-- the addon's own GetAuctionBuyout override: prefer the realm price, fall
-- back to the region price when this realm has no recent data.
--
-- OribosExchange.lua explicitly nils out region when it's 0, but NOT
-- market (OEMarketInfo just assigns the raw decoded byte there) - so an
-- item with no recent realm data comes back as market=0, not market=nil.
-- In Lua, 0 is truthy, so a plain `r["market"] or r["region"]` never falls
-- through to region for those items; it has to be checked explicitly.
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
-- Price cache (session-only, 1h TTL)
-- Auctionator/TSM price data changes rarely mid-session, so re-querying
-- their APIs on every RefreshHUD (called on every loot event, and for
-- every gear-variant group in the threshold-sound check) is wasted work
-- once an item's price is already known. Only successful lookups are
-- cached - a miss (nil, e.g. AH scan not loaded yet right after a fresh
-- drop) is never cached, so the delayed-refresh self-heal in Main.lua
-- keeps retrying on the next RefreshHUD until a real price resolves.
-- Cleared on logout/reload (plain Lua table, not a SavedVariable) and
-- explicitly whenever a setting that changes the computed price itself
-- (AH source, TSM source/custom string) is changed - see Settings.lua.
------------------------------------------------------------------------
ns.priceCache = ns.priceCache or {}
local PRICE_CACHE_TTL = 3600

function ns.ClearPriceCache()
    wipe(ns.priceCache)
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

    local src = NightsFarmtrackerDB.ahSource or "auto"
    local p
    if src == "auctionator" then p = ns.GetAuctionatorPrice(itemID, itemLink)
    elseif src == "tsm"     then p = ns.GetTSMPrice(itemID)
    elseif src == "oribos"  then p = ns.GetOribosPrice(itemID, itemLink)
    else
        p = ns.GetAuctionatorPrice(itemID, itemLink) or ns.GetOribosPrice(itemID, itemLink) or ns.GetTSMPrice(itemID)
    end

    if p then ns.priceCache[key] = { price = p, time = GetTime() } end
    return p
end

-- Stable per-drop key for scaling/Adventurer's gear (same item ID, different
-- item level/quality per roll). itemLevel and quality from GetItemInfo are
-- NOT reliable at loot time: a cache miss leaves itemLevel nil, and some
-- scaling gear reports a uniform loot-toast quality regardless of the true
-- rolled rarity - either way two different rolls can end up with the same
-- fallback key and get merged into one bucket (wrong shared price). The
-- bonus-ID string baked into the item link is fixed the moment the item
-- drops and always differs between rolls, cache state or not.
--
-- Cleaned via CleanItemLink first: the raw loot-message/bag link carries
-- incidental fields (uniqueID, linkLevel) that can differ between two
-- drops of the exact same item/roll, which fragmented identical loot into
-- separate variant rows instead of merging their amounts. The canonical
-- link from GetItemInfo keeps the bonus IDs (the actual stat/ilvl roll)
-- but normalizes that incidental noise.
function ns.GearVariantKey(link)
    if not link then return "unknown" end
    local clean = ns.CleanItemLink(link) or link
    return clean:match("item[%-%d:]+") or clean
end

-- Display-only grouping of raw gearVariants (keyed by full bonus-ID string)
-- into buckets keyed by (itemLevel, quality). Two drops can carry different
-- bonus-ID strings yet show the IDENTICAL item level/quality/stats - e.g.
-- Adventurer's/scaling gear bakes a hidden per-drop scaling component into
-- the bonus IDs that doesn't affect the displayed result. Those are visually
-- indistinguishable to the player and should sum into one row; only bonus-ID
-- rolls that actually produce a different item level or quality stay split.
-- Backend storage (db.count/session data) keeps the raw per-bonus-ID keys
-- untouched, so per-roll AH pricing accuracy is unaffected - this only
-- changes what UI.lua/History.lua iterate over when building display rows.
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
-- Unified variant view (read-only)
-- Every tracked item is stored in one of three legacy shapes: plain
-- (single sellPrice/itemLink), gear (data.gearVariants, keyed by bonus-ID
-- string - scaling/Adventurer's gear), or reagent (data.q/qIDs/qAHTotal,
-- three parallel arrays for crafting-reagent quality tiers). This builds
-- a single normalized view over whichever shape a given item actually
-- uses, so price/value code has ONE loop instead of three near-duplicate
-- ones. It does NOT change how data is written/merged/repaired (see
-- ProcessLoot in Main.lua and SaveCurrentSession/MergeSessionInto in
-- History.lua) - purely a read-side view, rebuilt fresh on every call.
--
-- Each returned variant: { amount, quality, itemLevel, itemLink,
-- sellPrice, ahTotal, priceItemID }.
--   - ahTotal is nil unless already frozen (saved session data); a live
--     db.count entry never has this set, so callers always do a live
--     AH lookup for it.
--   - priceItemID is the itemID to price this variant against. Only set
--     explicitly for reagent tiers, which are a genuinely different
--     itemID per tier; gear/plain variants fall back to data.itemID.
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

-- DEPRECATED - do not use for classification. A variants table can end up
-- with a stray numeric key from legacy data (e.g. an old itemLevel-keyed
-- bucket predating the bonus-ID key scheme) mixed in with normal string
-- keys; since pairs()/next() order over mixed key types is undefined in
-- Lua, checking only the first key is unreliable - it can misclassify a
-- real gear item as reagent-tier depending on hash order. Callers should
-- use ns.IsGear(data) instead (classID/bind-flag based, unambiguous).
function ns.IsTierVariants(variants)
    return type(next(variants)) == "number"
end

-- Vendor sell price for one variant: trust its own recorded sellPrice,
-- else look one up live via its item link (bonus IDs → correct scaled
-- price) or, failing that, its price-lookup itemID. Exposed on ns since
-- History.lua, ItemHelper.lua and UI.lua all need this same fallback for
-- their own per-variant row/total math (was duplicated inline in all three).
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
