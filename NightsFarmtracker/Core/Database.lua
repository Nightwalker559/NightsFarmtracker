------------------------------------------------------------------------
-- Night's Farmtracker - Database
-- SavedVariables setup: profiles, per-character and account-wide defaults,
-- item-key migrations, and the Vendor-Only / Blacklist stores.
------------------------------------------------------------------------
local _, ns = ...

local DEFAULT_MAIN_POS = {"TOP", "TOP", 0, -150}

------------------------------------------------------------------------
-- Item key migration (name-keyed -> itemID-keyed)
------------------------------------------------------------------------
-- Merges numeric/table fields of `src` into `target` in place. Handles
-- both db.count records (just `amount`) and saved session records
-- (`amount` + precomputed `vendorTotal`/`ahTotal` + reagent quality tiers).
local function MergeItemRecords(target, src)
    target.amount = (target.amount or 0) + (src.amount or 0)
    if src.vendorTotal then target.vendorTotal = (target.vendorTotal or 0) + src.vendorTotal end
    if src.ahTotal     then target.ahTotal     = (target.ahTotal or 0)     + src.ahTotal     end
    if src.q then
        -- Only merge a tier breakdown that's internally consistent with its
        -- own amount - a corrupted breakdown (see ProcessLoot's self-heal)
        -- must never be summed into target.q, or the corruption compounds
        -- with every future migration/merge instead of staying contained.
        local srcSum = (src.q[1] or 0) + (src.q[2] or 0) + (src.q[3] or 0)
        if srcSum == (src.amount or 0) then
            target.q    = target.q    or {}
            target.qIDs = target.qIDs or {}
            for tier = 1, 3 do
                if src.q[tier] then target.q[tier] = (target.q[tier] or 0) + src.q[tier] end
                if src.qIDs and src.qIDs[tier] and not target.qIDs[tier] then target.qIDs[tier] = src.qIDs[tier] end
            end
        end
    end
end

-- Re-keys name-keyed item tables (db.count, session.items) by itemID, merging
-- entries that turn out to be the same item (the same item looted in two client
-- languages used to create duplicates). An entry with no itemID keeps a
-- synthetic string key, so nothing is lost.
local function MigrateItemKeys(items)
    if not items then return end
    local hasOldKeys = false
    for key in pairs(items) do
        if type(key) == "string" then hasOldKeys = true; break end
    end
    if not hasOldKeys then return end

    local migrated = {}
    for key, d in pairs(items) do
        if type(key) == "string" then
            d.name = d.name or key
            local newKey = d.itemID or ("name:" .. key)
            local existing = migrated[newKey]
            if existing then
                MergeItemRecords(existing, d)
            else
                migrated[newKey] = d
            end
        else
            migrated[key] = d
        end
    end
    for k in pairs(items) do items[k] = nil end
    for k, v in pairs(migrated) do items[k] = v end
end

------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------
-- These keys live in the active profile (NightsFarmtrackerAccountDB.
-- profiles[key]) instead of directly on NightsFarmtrackerDB, so switching
-- profile switches all of them at once (the main window position included).
-- Everything else (session/tracking state, other window positions, UI
-- collapse flags, minimap) stays character-local, unchanged. A metatable
-- installed in InitDB() transparently redirects reads/writes of these keys -
-- no other file needs to change.
ns.PROFILE_KEYS = {
    goldRateMode=true, sessionLength=true, sessionHistoryEnabled=true, logWindowEnabled=true,
    vendorFilterEnabled=true, blacklistEnabled=true, mergeDaily=true,
    splitTradeGoods=true, splitGearByBinding=true, ahSource=true,
    gearAHThreshold=true, gearThresholdOff=true, goldDisplayMode=true, tsmPriceSource=true,
    tsmCustomSource=true, colorTheme=true, customAccent=true, headerGradient=true, themedButtons=true,
    maxWindowHeight=true,
    venomTrackerEnabled=true,
    baitFrameEnabled=true, mergeJunkEntries=true, instanceLockoutEnabled=true,
    hudEnabled=true, hudSize=true, hudScale=true, hudAlpha=true, hudRotate=true,
    showPriceSource=true, showValueBar=true, itemGoal=true, itemGoals=true, itemGoalsEnabled=true, limitMode=true,
    pos=true, mainLocked=true, gearAHThresholdSound=true, sessionHistoryMode=true, sessionHistoryAvg=true,
}

ns.DEFAULT_PROFILE = "Default"

local function NewProfileDefaults()
    return {
        goldRateMode          = "hour",
        sessionLength         = 0,
        sessionHistoryEnabled = true,
        logWindowEnabled      = false,
        vendorFilterEnabled   = true,
        blacklistEnabled      = true,
        mergeDaily            = true,
        splitTradeGoods       = false,
        splitGearByBinding    = false,
        ahSource              = "auto",
        gearAHThreshold       = 0,
        gearThresholdOff      = {},
        goldDisplayMode       = "classic",
        tsmPriceSource        = "DBMarket",
        tsmCustomSource       = "",
        colorTheme            = "default",
        headerGradient        = false,
        themedButtons         = false,
        maxWindowHeight       = ns.DEFAULT_MAX_WINDOW_H,
        venomTrackerEnabled   = false,
        baitFrameEnabled      = false,
        mergeJunkEntries      = false,
        instanceLockoutEnabled = false,
        hudEnabled            = false,
        showPriceSource       = false,
        showValueBar          = true,
        itemGoal              = 0,
        itemGoals             = {},
        itemGoalsEnabled      = true,
        limitMode             = "off",
        pos                   = { unpack(DEFAULT_MAIN_POS) },
        mainLocked            = false,
        gearAHThresholdSound  = false,
        sessionHistoryMode    = "full",
        sessionHistoryAvg     = false,
    }
end

-- Ensures NightsFarmtrackerAccountDB.profiles exists with at least the
-- "Default" profile. Safe to call any time, from any file.
local function EnsureProfileStore()
    if not NightsFarmtrackerAccountDB then NightsFarmtrackerAccountDB = {} end
    local acc = NightsFarmtrackerAccountDB
    if not acc.profiles then acc.profiles = {} end
    if not acc.profiles[ns.DEFAULT_PROFILE] then
        acc.profiles[ns.DEFAULT_PROFILE] = NewProfileDefaults()
    end
    return acc.profiles
end

function ns.GetProfileList()
    local list = {}
    for name in pairs(EnsureProfileStore()) do list[#list+1] = name end
    table.sort(list, function(a,b) return a:lower() < b:lower() end)
    return list
end

-- Falls back (and repairs the pointer) to "Default" if this character's
-- profile was deleted from another character.
function ns.GetActiveProfileName()
    local key = rawget(NightsFarmtrackerDB, "profileKey")
    if not key or not EnsureProfileStore()[key] then
        key = ns.DEFAULT_PROFILE
        rawset(NightsFarmtrackerDB, "profileKey", key)
    end
    return key
end

local function ActiveProfileTable()
    return EnsureProfileStore()[ns.GetActiveProfileName()]
end

function ns.CreateProfile(name)
    local profiles = EnsureProfileStore()
    if not name or name == "" or profiles[name] then return false end
    profiles[name] = NewProfileDefaults()
    return true
end

function ns.CopyProfile(name, sourceName)
    local profiles = EnsureProfileStore()
    if not name or name == "" or profiles[name] then return false end
    local src = profiles[sourceName] or ActiveProfileTable()
    local copy = {}
    for k, v in pairs(src) do copy[k] = v end
    -- gearThresholdOff and pos are tables - copy them so the two profiles don't share them
    for _, key in ipairs({ "gearThresholdOff", "pos" }) do
        if type(src[key]) == "table" then
            copy[key] = {}
            for k, v in pairs(src[key]) do copy[key][k] = v end
        end
    end
    -- itemGoals holds one table per item
    if type(src.itemGoals) == "table" then
        copy.itemGoals = {}
        for itemID, goal in pairs(src.itemGoals) do
            copy.itemGoals[itemID] = { name = goal.name, icon = goal.icon, quality = goal.quality, amount = goal.amount }
        end
    end
    profiles[name] = copy
    return true
end

function ns.RenameProfile(oldName, newName)
    local profiles = EnsureProfileStore()
    if not profiles[oldName] or not newName or newName == "" or profiles[newName] then return false end
    profiles[newName] = profiles[oldName]
    profiles[oldName] = nil
    if ns.GetActiveProfileName() == oldName then
        rawset(NightsFarmtrackerDB, "profileKey", newName)
    end
    return true
end

-- "Default" can't be deleted (always kept as the guaranteed fallback).
-- Deleting the active profile is repaired by ns.GetActiveProfileName() on
-- next access, for this character and any other character using it.
function ns.DeleteProfile(name)
    local profiles = EnsureProfileStore()
    if name == ns.DEFAULT_PROFILE or not profiles[name] then return false end
    profiles[name] = nil
    return true
end

function ns.SetActiveProfile(name)
    if not EnsureProfileStore()[name] then return false end
    rawset(NightsFarmtrackerDB, "profileKey", name)
    return true
end

------------------------------------------------------------------------
-- DB init
------------------------------------------------------------------------
function ns.InitDB()
    if not NightsFarmtrackerDB then NightsFarmtrackerDB = {} end
    EnsureProfileStore()

    -- One-time migration: pre-1.6.0 saves keep profile-scope settings as
    -- plain keys directly on NightsFarmtrackerDB. Move them into the
    -- "Default" profile before the metatable below starts shadowing them.
    if not rawget(NightsFarmtrackerDB, "profileKey") then
        local default = NightsFarmtrackerAccountDB.profiles[ns.DEFAULT_PROFILE]
        for key in pairs(ns.PROFILE_KEYS) do
            local old = rawget(NightsFarmtrackerDB, key)
            if old ~= nil then
                default[key] = old
                rawset(NightsFarmtrackerDB, key, nil)
            end
        end
        rawset(NightsFarmtrackerDB, "profileKey", ns.DEFAULT_PROFILE)
    end

    -- limitMode ("session" | "goal" | "off") picks which of sessionLength /
    -- itemGoal / itemGoals is active. Profiles saved before it existed keep
    -- whichever value was set (an item goal used to win over a session length).
    for _, profile in pairs(NightsFarmtrackerAccountDB.profiles) do
        if profile.limitMode == nil then
            if (tonumber(profile.itemGoal) or 0) > 0 then profile.limitMode = "goal"
            elseif (tonumber(profile.sessionLength) or 0) > 0 then profile.limitMode = "session"
            else profile.limitMode = "off" end
        end
    end

    if not getmetatable(NightsFarmtrackerDB) then
        setmetatable(NightsFarmtrackerDB, {
            __index = function(_, k)
                if ns.PROFILE_KEYS[k] then return ActiveProfileTable()[k] end
                return nil
            end,
            __newindex = function(t, k, v)
                if ns.PROFILE_KEYS[k] then
                    ActiveProfileTable()[k] = v
                else
                    rawset(t, k, v)
                end
            end,
        })
    end

    -- Register housing classID at runtime (may vary by patch)
    if ns.HOUSING and not ns.CLASS_PRIORITY[ns.HOUSING] then
        ns.CLASS_PRIORITY[ns.HOUSING] = 3  -- show after gems, before consumables
    end
    local db = NightsFarmtrackerDB
    if db.count == nil then db.count = {} end
    if not db.itemKeysMigrated then
        MigrateItemKeys(db.count)
        db.itemKeysMigrated = true
    end
    -- One-time repairs for the LIVE (unsaved) session - see
    -- ns.RunCharacterRepairs / ns.CHARACTER_REPAIRS in Repairs.lua.
    ns.RunCharacterRepairs()

    -- Keys that became profile settings after a character had saved them as
    -- plain fields (e.g. the main window position): hand the value to the
    -- active profile unless that already has one, then drop the plain copy -
    -- it would shadow the profile value, the metatable only sees absent keys.
    local profile = ActiveProfileTable()
    for key in pairs(ns.PROFILE_KEYS) do
        local old = rawget(db, key)
        if old ~= nil then
            if profile[key] == nil then profile[key] = old end
            rawset(db, key, nil)
        end
    end

    -- Profile settings: fill in whatever the active profile lacks (keys added
    -- by an update, profiles created before them).
    for key, default in pairs(NewProfileDefaults()) do
        if db[key] == nil then db[key] = default end
    end

    -- Character-local state
    for key, default in pairs({
        paused = true, visible = true, expanded = false, totalTime = 0, lootedGold = 0,
        logWindowShown = false, blacklistCategoriesCollapsed = false,
        filterCategoriesCollapsed = false, ahExpansionsCollapsed = false,
    }) do
        if db[key] == nil then db[key] = default end
    end
    for _, key in ipairs({ "qAtlas", "collapsed", "excludedNames", "excludedItemIDs", "logEntries" }) do
        if db[key] == nil then db[key] = {} end
    end
    -- Minimap button: minimapPos, hide, showInCompartment. The first two used
    -- to be plain keys on db (pre-LibDBIcon saves).
    if db.minimap == nil then
        db.minimap = { minimapPos = db.minimapPos or 225, hide = db.minimapHidden or false }
    end
    db.minimapPos, db.minimapHidden = nil, nil
    ns.ApplyColorTheme(db.colorTheme)
end

-- Catalog of every distinct item seen while tracking (one entry per itemID,
-- see ns.RecordItemDBEntry). Audit data only; it is persisted by the
-- optional NightsFarmtrackerItemDB companion addon and works without it.
function ns.InitItemDB()
    if not NightsFarmtrackerItemDB then NightsFarmtrackerItemDB = {} end
end

-- Tables every account needs (all start empty).
local ACCOUNT_TABLES = { "forceVendor", "forceVendorCategories", "ahExpansions", "blacklist", "blacklistCategories" }

function ns.InitAccountDB()
    if not NightsFarmtrackerAccountDB then NightsFarmtrackerAccountDB = {} end
    local acc = NightsFarmtrackerAccountDB
    acc.sessions = acc.sessions or {}
    -- Day-keyed storage before anything iterates the sessions (an old flat
    -- array is converted here; already converted data is left alone)
    ns.MigrateSessionsToDateKeyed(acc.sessions)
    if not acc.itemKeysMigrated then
        ns.ForEachSession(acc.sessions, function(session) MigrateItemKeys(session.items) end)
        acc.itemKeysMigrated = true
    end
    -- One-time repairs for the saved session history (Repairs.lua).
    ns.RunAccountRepairs()
    if acc.itemLinkMigrationPrompted == nil then acc.itemLinkMigrationPrompted = false end
    for _, key in ipairs(ACCOUNT_TABLES) do acc[key] = acc[key] or {} end

    -- Every expansion starts with AH pricing, once: unchecking boxes later
    -- must persist instead of resetting to "all on" at every login.
    if acc.ahExpansionsDefaulted == nil then
        if not next(acc.ahExpansions) then
            for _, expID in ipairs(ns.EXPANSION_ORDER) do acc.ahExpansions[expID] = true end
        end
        acc.ahExpansionsDefaulted = true
    end

    -- Junk starts as vendor-only unless the player already made a choice
    -- (SetForceVendorCategory always stores a real true/false).
    local junkName = ns.L["cat_junk"]
    if junkName and acc.forceVendorCategories[junkName] == nil then
        acc.forceVendorCategories[junkName] = true
    end
end

------------------------------------------------------------------------
-- Filter stores (account-wide, persistent). The Vendor-Only filter and the
-- Blacklist share one shape: itemID -> { name, icon, quality, expansionID }
-- plus a name-keyed set of categories (the exact string ns.CategoryName()
-- returns, so it follows the grouping the HUD shows, e.g. the trade-goods
-- split). `enabledKey` is the setting that switches the whole feature off.
------------------------------------------------------------------------
local function CreateFilterStore(itemsKey, catsKey, enabledKey)
    local function active()
        local db = NightsFarmtrackerDB
        return not (db and db[enabledKey] == false)
    end
    local function account(key) return NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB[key] end

    local store = {}
    function store.has(itemID)
        local list = account(itemsKey)
        return active() and itemID ~= nil and list ~= nil and list[itemID] ~= nil
    end
    function store.add(itemID, name, icon, quality)
        if not itemID then return end
        NightsFarmtrackerAccountDB[itemsKey][itemID] = {
            name = name, icon = icon, quality = quality, expansionID = select(15, C_Item.GetItemInfo(itemID)),
        }
    end
    function store.remove(itemID)
        if itemID then NightsFarmtrackerAccountDB[itemsKey][itemID] = nil end
    end
    function store.clear()
        local list = account(itemsKey)
        if list then wipe(list) end
    end
    function store.categoryEnabled(name)
        local cats = account(catsKey)
        return cats ~= nil and cats[name] == true
    end
    function store.setCategory(name, enabled)
        local cats = account(catsKey)
        if cats then cats[name] = enabled and true or false end
    end
    -- True if this item's current category is switched on.
    function store.hasCategory(data)
        local cats = account(catsKey)
        if not active() or not cats then return false end
        local name = ns.CategoryName(data)
        return name ~= nil and cats[name] == true
    end
    return store
end

-- Vendor-Only: these items always use the vendor price, never the AH price.
local vendorStore = CreateFilterStore("forceVendor", "forceVendorCategories", "vendorFilterEnabled")
ns.IsForceVendor                = vendorStore.has
ns.AddForceVendor               = vendorStore.add
ns.RemoveForceVendor            = vendorStore.remove
ns.ClearForceVendor             = vendorStore.clear
ns.IsForceVendorCategoryEnabled = vendorStore.categoryEnabled
ns.SetForceVendorCategory       = vendorStore.setCategory
ns.IsForceVendorCategory        = vendorStore.hasCategory

-- Blacklist: these items/categories are never tracked at all. It wins over
-- everything else, Vendor-Only included.
local blacklistStore = CreateFilterStore("blacklist", "blacklistCategories", "blacklistEnabled")
ns.IsBlacklisted                = blacklistStore.has
ns.AddBlacklist                 = blacklistStore.add
ns.RemoveBlacklist              = blacklistStore.remove
ns.ClearBlacklist               = blacklistStore.clear
ns.IsBlacklistCategoryEnabled   = blacklistStore.categoryEnabled
ns.SetBlacklistCategory         = blacklistStore.setCategory
ns.IsBlacklistCategory          = blacklistStore.hasCategory

------------------------------------------------------------------------
-- Item goals (profile scope): itemID -> { name, icon, quality, amount }, on
-- top of db.itemGoal (the amount for every item without an entry). Only
-- active while db.limitMode == "goal" (see ns.GetItemGoal).
------------------------------------------------------------------------
function ns.GetItemGoals()
    local db = NightsFarmtrackerDB
    if type(db.itemGoals) ~= "table" then db.itemGoals = {} end
    return db.itemGoals
end

function ns.SetItemGoal(itemID, name, icon, quality, amount)
    if not itemID then return end
    ns.GetItemGoals()[itemID] = { name = name, icon = icon, quality = quality, amount = amount }
end

function ns.RemoveItemGoal(itemID)
    if itemID then ns.GetItemGoals()[itemID] = nil end
end

function ns.ClearItemGoals()
    wipe(ns.GetItemGoals())
end

------------------------------------------------------------------------
-- AH price by expansion: an opt-in whitelist. With nothing selected the
-- filter is inactive; once an expansion is checked, items from any OTHER
-- expansion are priced at vendor value (e.g. "AH only for Midnight gear").
------------------------------------------------------------------------
function ns.IsAHExpansionEnabled(expID)
    return NightsFarmtrackerAccountDB ~= nil
       and NightsFarmtrackerAccountDB.ahExpansions ~= nil
       and NightsFarmtrackerAccountDB.ahExpansions[expID] == true
end

function ns.SetAHExpansionEnabled(expID, enabled)
    if not NightsFarmtrackerAccountDB or not NightsFarmtrackerAccountDB.ahExpansions then return end
    NightsFarmtrackerAccountDB.ahExpansions[expID] = enabled and true or nil
end

-- True if any expansion is selected (the filter is active).
function ns.HasAHExpansionSelection()
    local sel = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.ahExpansions
    return sel ~= nil and next(sel) ~= nil
end

-- True if the filter forces this item's expansion to vendor price.
function ns.IsForceVendorExpansion(data)
    if NightsFarmtrackerDB and NightsFarmtrackerDB.vendorFilterEnabled == false then return false end
    if not ns.HasAHExpansionSelection() then return false end
    local expID = ns.GetItemExpansionID(data)
    if expID == nil then return false end
    return not ns.IsAHExpansionEnabled(expID)
end
