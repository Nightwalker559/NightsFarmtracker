------------------------------------------------------------------------
-- Night's Farmtracker - Core
------------------------------------------------------------------------
local ADDON_NAME, ns = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
ns.ADDON_NAME     = ADDON_NAME
ns.ART            = "Interface\\AddOns\\NightsFarmtracker\\Media\\"

------------------------------------------------------------------------
-- Combat-safe deferral for popup windows. Frame:Show/Hide/SetPoint calls
-- can throw ADDON_ACTION_BLOCKED in combat lockdown (BaitFrame's
-- SecureActionButtonTemplate lure button taints the shared execution
-- path). ns.DeferInCombat(fn) queues fn to run right after combat ends
-- instead of letting the call fail; returns true if it was queued.
------------------------------------------------------------------------
local pendingCombatCalls = {}
local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
    local queued = pendingCombatCalls
    pendingCombatCalls = {}
    for _, fn in ipairs(queued) do fn() end
end)

function ns.DeferInCombat(fn)
    if InCombatLockdown() then
        pendingCombatCalls[#pendingCombatCalls + 1] = fn
        return true
    end
    return false
end

ns.TRADE_GOODS    = Enum.ItemClass.Tradegoods
ns.QUEST_CLASS    = Enum.ItemClass.Questitem
ns.BIND_ON_EQUIP  = 2
ns.BIND_ON_PICKUP = 1
ns.BIND_ON_USE    = 3
ns.FALLBACK_ICON  = 134400
-- Housing classID: Enum.ItemClass.Housing if defined (12.0.0+), else runtime-detected
ns.HOUSING = Enum.ItemClass and Enum.ItemClass.Housing or nil

-- Item class priority for display order (by WoW classID)
ns.CLASS_PRIORITY = {
    [7]  = 1,   -- Tradeskill / Tradegoods
    [5]  = 2,   -- Reagent
    [2]  = 3,   -- Weapon
    [4]  = 4,   -- Armor
    [3]  = 5,   -- Gem
    [0]  = 6,   -- Consumable
    [9]  = 7,   -- Recipe
    [8]  = 8,   -- Item Enhancement
    [1]  = 9,   -- Container
    [12] = 10,  -- Quest
    [14] = 11,  -- Miscellaneous
}
-- Housing classID is not hardcoded above (varies by patch); ns.InitDB()
-- registers it at runtime via ns.HOUSING so it always gets the correct
-- priority instead of silently falling through to the default (50).

-- UI layout
ns.FRAME_W     = 310
ns.PAD         = 10
ns.ROW_H       = 34
ns.CAT_ROW_H   = 22
ns.CHECKBOX_ROW_H = 16  -- row height for checkbox-list sections (category filters, AH-by-expansion)
ns.CAT_INDENT  = 8
ns.FOOTER_H    = 32
ns.ICON_SIZE   = 30
ns.RANK_ICON_W = 12   -- width of the R1/R2/R3 atlas markup (CreateAtlasMarkup)
ns.RANK_ICON_H = 14   -- height of the R1/R2/R3 atlas markup
ns.CONTENT_W   = ns.FRAME_W - ns.PAD * 2
ns.MAX_ROWS    = 8
ns.SCROLL_STEP = ns.ROW_H

-- Font sizes (odd values render blurry at some UI scales, so we stick to
-- even numbers). Used via SetFontHeight() everywhere instead of scattered
-- literals, so the whole addon can be resized from one place.
ns.FONT_SMALL  = 10  -- secondary/info text (day-row info, merge button)
ns.FONT_NORMAL = 12  -- default row/item text
ns.FONT_HEADER = 14  -- emphasized headers/titles

-- Header height for title-only secondary windows (History, Detail, Filter,
-- Blacklist, Log, Settings). MainFrame keeps its own taller header (it has
-- to fit the icon toolbar) and isn't affected by this constant.
ns.WINDOW_HDR_H = 34

-- Colors — theme-based. ns.COL_GOLD always stays the same regardless of
-- theme (gold amounts should stay visually consistent/recognizable).
ns.COLOR_THEMES = {
    default = {
        name     = "Default",
        labelKey = "theme_default",
        descKey  = "theme_default_desc",
        bg     = {0.06, 0.09, 0.10, 0.92},
        border = {0.20, 0.38, 0.42, 0.85},
        catBg  = {0.10, 0.16, 0.18, 0.80},
        accent = {0.30, 0.75, 0.85},
    },
    void = {
        name     = "Void",
        labelKey = "theme_void",
        descKey  = "theme_void_desc",
        bg     = {0.07, 0.05, 0.10, 0.92},
        border = {0.32, 0.18, 0.42, 0.85},
        catBg  = {0.12, 0.08, 0.16, 0.80},
        accent = {0.62, 0.35, 0.90},
    },
    silvermoon = {
        name     = "Silvermoon",
        labelKey = "theme_silvermoon",
        descKey  = "theme_silvermoon_desc",
        bg     = {0.09, 0.06, 0.04, 0.92},
        border = {0.45, 0.30, 0.10, 0.85},
        catBg  = {0.16, 0.10, 0.06, 0.80},
        accent = {1.00, 0.75, 0.25},
    },
    fel = {
        name     = "Fel",
        labelKey = "theme_fel",
        descKey  = "theme_fel_desc",
        bg     = {0.05, 0.08, 0.04, 0.92},
        border = {0.18, 0.38, 0.14, 0.85},
        catBg  = {0.08, 0.14, 0.06, 0.80},
        accent = {0.55, 0.95, 0.20},
    },
    frost = {
        name     = "Frost",
        labelKey = "theme_frost",
        descKey  = "theme_frost_desc",
        bg     = {0.05, 0.07, 0.10, 0.92},
        border = {0.20, 0.32, 0.48, 0.85},
        catBg  = {0.08, 0.12, 0.18, 0.80},
        accent = {0.55, 0.80, 1.00},
    },
    bloodmoon = {
        name     = "Bloodmoon",
        labelKey = "theme_bloodmoon",
        descKey  = "theme_bloodmoon_desc",
        bg     = {0.08, 0.04, 0.05, 0.92},
        border = {0.42, 0.14, 0.16, 0.85},
        catBg  = {0.14, 0.06, 0.07, 0.80},
        accent = {0.95, 0.30, 0.30},
    },
    molten = {
        name     = "Molten",
        labelKey = "theme_molten",
        descKey  = "theme_molten_desc",
        bg     = {0.10, 0.06, 0.03, 0.92},
        border = {0.55, 0.28, 0.08, 0.85},
        catBg  = {0.16, 0.09, 0.04, 0.80},
        accent = {1.00, 0.55, 0.10},
    },
    emerald = {
        name     = "Emerald",
        labelKey = "theme_emerald",
        descKey  = "theme_emerald_desc",
        bg     = {0.04, 0.09, 0.06, 0.92},
        border = {0.14, 0.42, 0.26, 0.85},
        catBg  = {0.07, 0.15, 0.10, 0.80},
        accent = {0.15, 0.85, 0.48},
    },
    arcane = {
        name     = "Arcane",
        labelKey = "theme_arcane",
        descKey  = "theme_arcane_desc",
        bg     = {0.08, 0.05, 0.10, 0.92},
        border = {0.40, 0.16, 0.46, 0.85},
        catBg  = {0.13, 0.08, 0.16, 0.80},
        accent = {0.78, 0.29, 0.86},
    },
    bronze = {
        name     = "Bronze",
        labelKey = "theme_bronze",
        descKey  = "theme_bronze_desc",
        bg     = {0.09, 0.07, 0.04, 0.92},
        border = {0.42, 0.28, 0.12, 0.85},
        catBg  = {0.15, 0.11, 0.06, 0.80},
        accent = {0.72, 0.47, 0.18},
    },
    plague = {
        name     = "Plague",
        labelKey = "theme_plague",
        descKey  = "theme_plague_desc",
        bg     = {0.06, 0.08, 0.03, 0.92},
        border = {0.28, 0.36, 0.10, 0.85},
        catBg  = {0.10, 0.13, 0.05, 0.80},
        accent = {0.60, 0.80, 0.20},
    },
    nether = {
        name     = "Nether",
        labelKey = "theme_nether",
        descKey  = "theme_nether_desc",
        bg     = {0.03, 0.08, 0.09, 0.92},
        border = {0.10, 0.34, 0.38, 0.85},
        catBg  = {0.05, 0.14, 0.16, 0.80},
        accent = {0.10, 0.72, 0.77},
    },
    argent = {
        name     = "Argent",
        labelKey = "theme_argent",
        descKey  = "theme_argent_desc",
        bg     = {0.09, 0.08, 0.06, 0.92},
        border = {0.55, 0.50, 0.35, 0.85},
        catBg  = {0.15, 0.13, 0.09, 0.80},
        accent = {0.95, 0.90, 0.70},
    },
}
-- Display order for the Settings dropdown
ns.COLOR_THEME_ORDER = {
    "default", "void", "silvermoon", "fel", "frost", "bloodmoon",
    "molten", "emerald", "arcane", "bronze", "plague", "nether", "argent",
}
ns.COL_GOLD = {1.00, 0.82, 0.00}

-- Applies a theme's colors to ns.COL_BG/BORDER/CAT_BG/ACCENT. Elements
-- already drawn with the old colors are not retroactively recolored -
-- a UI reload is required for a theme change to fully apply everywhere.
function ns.ApplyColorTheme(themeKey)
    local theme = ns.COLOR_THEMES[themeKey] or ns.COLOR_THEMES.default
    ns.COL_BG     = theme.bg
    ns.COL_BORDER = theme.border
    ns.COL_CAT_BG = theme.catBg
    ns.COL_ACCENT = theme.accent
end

-- Shared tooltip-style backdrop used throughout Settings/Blacklist/Filter
-- for small boxed widgets (checkboxes, radio dots, dropdowns, edit boxes).
-- bgColor defaults to {0.06,0.09,0.10,1} (the checkbox/radio shade); pass
-- {0.05,0.08,0.09,1} for the slightly darker dropdown/edit-box shade.
function ns.StyleBackdropBox(frame, bgColor)
    frame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Tooltips/UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
    frame:SetBackdropColor(unpack(bgColor or {0.06,0.09,0.10,1}))
    frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))
end
-- Best-effort early apply in case SavedVariables already happen to be
-- available (e.g. on repeated /reload during dev). On a normal login this
-- runs before SavedVariables are loaded and falls back to "default"; the
-- real apply happens in InitDB(), with MainFrame/GoldFrame explicitly
-- re-skinned afterwards since they're built before that point.
ns.ApplyColorTheme(NightsFarmtrackerDB and NightsFarmtrackerDB.colorTheme)

------------------------------------------------------------------------
-- Debug
------------------------------------------------------------------------
ns.debugMode = false
function ns.Log(...) if ns.debugMode then print("|cff44aaaa[NFT]:|r", ...) end end

------------------------------------------------------------------------
-- Item tooltips for looted items shown in our own history/log frames.
-- Blizzard auto-attaches a "currently equipped" comparison tooltip
-- (ShoppingTooltip1/2) to any equippable item tooltip. That's confusing
-- here since it's a *past* loot entry, not something being considered
-- for equip - so we hide the comparison tooltips right after showing
-- ours. Only affects our own rows; normal in-game item tooltips
-- elsewhere are untouched.
------------------------------------------------------------------------
function ns.ShowItemTooltipNoCompare(owner, anchor, hyperlink, itemID)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if hyperlink then
        GameTooltip:SetHyperlink(hyperlink)
    else
        GameTooltip:SetItemByID(itemID)
    end
    if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
    if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
    GameTooltip:Show()
end

-- Picks a GameTooltip anchor constant for `frame`, preferring `side`
-- ("LEFT" or "RIGHT") but flipping to the other side if the frame sits
-- too close to that edge of the screen for the tooltip to fit.
function ns.SmartAnchor(frame, side)
    local screenW = UIParent:GetWidth()
    local x = frame:GetCenter()
    if not x then
        return side == "LEFT" and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
    end
    x = x * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()

    if side == "LEFT" then
        if x < screenW * 0.28 then return "ANCHOR_RIGHT" end
        return "ANCHOR_LEFT"
    else
        if x > screenW * 0.72 then return "ANCHOR_LEFT" end
        return "ANCHOR_RIGHT"
    end
end

------------------------------------------------------------------------
-- Shared "drop an item from your bags onto a frame" handler. Wire it to
-- both OnReceiveDrag (real drag-hold-release) and OnMouseUp with a
-- CursorHasItem() check (the "click to pick up, click again to place"
-- method, which doesn't reliably fire OnReceiveDrag on custom frames) --
-- see the Vendor-Only Filter / Blacklist / Fishing Lure Bar drop targets
-- for the two-script pattern. Always clears the cursor; calls
-- callback(itemID, itemLink) only if the cursor was holding an item.
------------------------------------------------------------------------
function ns.HandleItemDrop(callback)
    if not CursorHasItem() then return end
    local infoType, itemID, itemLink = GetCursorInfo()
    ClearCursor()
    if infoType == "item" and itemID then
        callback(itemID, itemLink)
    end
end

-- Wires both drop gestures (see above) on `frame` to onDrop().
function ns.EnableItemDrop(frame, onDrop)
    frame:SetScript("OnReceiveDrag", onDrop)
    frame:SetScript("OnMouseUp", function(_, btn) if btn == "LeftButton" then onDrop() end end)
end


------------------------------------------------------------------------
-- Utility
------------------------------------------------------------------------
function ns.FormatTime(s)
    s = math.floor(s or 0)
    return string.format("%02d:%02d:%02d",
        math.floor(s/3600), math.floor((s%3600)/60), s%60)
end

-- Inserts "." as a thousands separator (e.g. 1056859 -> "1.056.859"),
-- matching how Baganator/most gold addons display large amounts
-- regardless of client locale.
local function AddThousandsSep(n)
    local s = tostring(n)
    local rev = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
    if rev:sub(1,1) == "." then rev = rev:sub(2) end
    return rev
end

local function FormatGoldClassic(copper)
    if copper >= 10000 then
        -- Gold + silver (rounded to the nearest silver coin). Post-process
        -- Blizzard's own icon string to add the separator to the leading
        -- gold digits only — silver/copper stay 2-digit, never need one.
        local str = GetCoinTextureString(math.floor(copper / 100) * 100)
        local goldDigits, rest = str:match("^(%d+)(.*)$")
        if goldDigits then
            str = AddThousandsSep(goldDigits) .. rest
        end
        return str
    end
    -- Under 1g: silver + copper
    return GetCoinTextureString(copper)
end

-- GOLD_COLOR_CODE / SILVER_COLOR_CODE / COPPER_COLOR_CODE are not always
-- defined as globals depending on client version — fall back to the same
-- hex values Blizzard uses if they're missing.
local MONEY_GOLD_CC   = GOLD_COLOR_CODE   or "|cffffd700"
local MONEY_SILVER_CC = SILVER_COLOR_CODE or "|cffc7c7cf"
local MONEY_COPPER_CC = COPPER_COLOR_CODE or "|cffeda55f"
local MONEY_CC_CLOSE  = FONT_COLOR_CODE_CLOSE or "|r"

local function FormatGoldModern(copper)
    -- same threshold as classic: from 1g (10000 copper) onward, copper is not shown
    local showCopper = copper < 10000
    if not showCopper then
        copper = math.floor(copper / 100) * 100
    end
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop    = copper % 100

    local parts = {}
    if gold > 0 then
        parts[#parts+1] = MONEY_GOLD_CC .. AddThousandsSep(gold) .. ns.L["coin_gold"] .. MONEY_CC_CLOSE
    end
    parts[#parts+1] = MONEY_SILVER_CC .. string.format("%02d", silver) .. ns.L["coin_silver"] .. MONEY_CC_CLOSE
    if showCopper then
        parts[#parts+1] = MONEY_COPPER_CC .. string.format("%02d", cop) .. ns.L["coin_copper"] .. MONEY_CC_CLOSE
    end
    return table.concat(parts, " ")
end

function ns.FormatGold(copper)
    if not copper or copper <= 0 then return "" end
    if NightsFarmtrackerDB and NightsFarmtrackerDB.goldDisplayMode == "modern" then
        return FormatGoldModern(copper)
    end
    return FormatGoldClassic(copper)
end

-- Truncate item names to a fixed max length so columns stay aligned.
-- "Quasischweinefleisch" (20 chars) is the reference maximum.
-- Truncation is UTF-8 aware so multi-byte characters (e.g. German umlauts)
-- are never cut in the middle, which would render as a broken glyph.
local NAME_MAX = 20

-- Byte length of the UTF-8 character starting with lead byte `b`
-- (a stray continuation byte counts as 1).
local function Utf8CharBytes(b)
    if b >= 0xF0 then return 4 end
    if b >= 0xE0 then return 3 end
    if b >= 0xC0 then return 2 end
    return 1
end

local function Utf8Len(s)
    local len, i, n = 0, 1, #s
    while i <= n do
        i = i + Utf8CharBytes(s:byte(i))
        len = len + 1
    end
    return len
end

-- Byte offset (exclusive end) of the first `charCount` UTF-8 characters.
local function Utf8ByteOffset(s, charCount)
    local i, n, count = 1, #s, 0
    while i <= n and count < charCount do
        i = i + Utf8CharBytes(s:byte(i))
        count = count + 1
    end
    return i - 1
end

function ns.TruncateName(name)
    if not name then return "" end
    if Utf8Len(name) > NAME_MAX then
        local offset = Utf8ByteOffset(name, NAME_MAX - 2)
        return name:sub(1, offset) .. ".."
    end
    return name
end

-- Resolves an item's CURRENT-locale display name from its itemID (or
-- itemLink - GetItemInfo accepts either), falling back to the stored name
-- if unavailable (e.g. no identifier stored, or the rare case the client
-- hasn't cached that item at all). The stored name itself stays untouched
-- since it's used as a stable dictionary key for counting/exclusion/etc. -
-- this only affects what gets shown.
function ns.DisplayName(storedName, itemIdentifier)
    if itemIdentifier then
        local liveName = C_Item.GetItemInfo(itemIdentifier)
        if liveName and liveName ~= "" then return liveName end
    end
    return storedName
end

-- Item classification/value helpers (CategoryName, GearCategoryName, IsGear,
-- IsGearThresholdVendorOnly, IsVendorOnly, ItemValue) and the Junk-merge
-- display helpers now live in NightsFarmtrackerItemHelper.lua.

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

-- One-time migration: db.count / session.items used to be keyed by the
-- item's localized name, so looting the same item in two different client
-- languages (or after a locale change) created duplicate entries instead
-- of merging. Re-keys any old string-keyed entries by itemID, merging
-- duplicates that turn out to be the same item. An entry with no itemID
-- on record (very old cache-miss data) keeps a synthetic string key so
-- nothing is lost, just left unmerged - should be rare to nonexistent.
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
-- One-time, per-character migration: gear looted THIS session before the
-- gearVariants split (v1.5.0) was merged into a single db.count entry per
-- item ID, mixing amounts/prices across different item levels/qualities
-- (e.g. Adventurer's/scaling gear). Best-effort repair by re-scanning bags
-- right now and rebuilding the variant buckets from what's still there.
-- Anything already sold/mailed/banked this session can't be recovered from
-- bags, so its amount is kept under a single fallback bucket (using the
-- last known quality/link) instead of being lost.
function ns.MigrateGearVariantsFromBags(items)
    if not items then return end
    local targets = {}
    for itemID, d in pairs(items) do
        if (d.classID == 2 or d.classID == 4) and not d.variants then
            targets[itemID] = d
        end
    end
    if not next(targets) then return end

    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local ci = C_Container.GetContainerItemInfo(bag, slot)
            if ci and targets[ci.itemID] then
                local d    = targets[ci.itemID]
                local link = C_Container.GetContainerItemLink(bag, slot)
                if link then
                    local _, _, iQuality, iLevel, _, _, _, _, _, _, sp = C_Item.GetItemInfo(link)
                    local vKey = ns.GearVariantKey(link)
                    d.variants  = d.variants or {}
                    local gv    = d.variants[vKey]
                    if not gv then
                        gv = { amount = 0 }
                        d.variants[vKey] = gv
                    end
                    gv.amount    = gv.amount + (ci.stackCount or 1)
                    gv.quality   = iQuality
                    gv.itemLevel = iLevel
                    gv.itemLink  = link
                    if sp and sp > 0 then gv.sellPrice = sp end
                end
            end
        end
    end

    for _, d in pairs(targets) do
        local found = 0
        if d.variants then
            for _, gv in pairs(d.variants) do found = found + gv.amount end
        end
        local remainder = (d.amount or 0) - found
        if remainder > 0 then
            d.variants = d.variants or {}
            -- String key, never a bare number: a numeric key mixed into an
            -- otherwise bonus-ID-string-keyed variants table would make
            -- key-type checks depend on Lua's undefined pairs() order.
            local key = "legacy_q" .. tostring(d.quality or 0)
            local gv  = d.variants[key]
            if not gv then
                gv = { amount = 0, quality = d.quality, itemLink = d.itemLink, sellPrice = d.sellPrice }
                d.variants[key] = gv
            end
            gv.amount = gv.amount + remainder
        end
    end
end

-- Same repair as above, applied to the most recently saved session (rather
-- than the live/current one) - for when a session was already closed before
-- this fix was installed, but the items are still sitting in bags.
function ns.RepairLastSessionGearVariants()
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    if not sessions then return end
    -- "Most recent session" = the newest day key's first (newest) entry.
    -- ISO-format day keys ("YYYY-MM-DD") sort correctly as plain strings.
    local latestKey
    for k in pairs(sessions) do
        if not latestKey or k > latestKey then latestKey = k end
    end
    local dayList = latestKey and sessions[latestKey]
    if not dayList or not dayList[1] then return end
    ns.MigrateGearVariantsFromBags(dayList[1].items)
end

------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------
-- These keys live in the active profile (NightsFarmtrackerAccountDB.
-- profiles[key]) instead of directly on NightsFarmtrackerDB, so switching
-- profile switches all of them at once. Everything else (session/tracking
-- state, window positions, UI collapse flags, minimap) stays character-
-- local, unchanged. A metatable installed in InitDB() transparently
-- redirects reads/writes of these keys - no other file needs to change.
ns.PROFILE_KEYS = {
    goldRateMode=true, sessionLength=true, sessionHistoryEnabled=true, logWindowEnabled=true,
    vendorFilterEnabled=true, blacklistEnabled=true, mergeDaily=true,
    splitTradeGoods=true, splitGearByBinding=true, ahSource=true,
    gearAHThreshold=true, gearThresholdOff=true, goldDisplayMode=true, tsmPriceSource=true,
    tsmCustomSource=true, colorTheme=true, venomTrackerEnabled=true,
    baitFrameEnabled=true, mergeJunkEntries=true, instanceLockoutEnabled=true,
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
        venomTrackerEnabled   = false,
        baitFrameEnabled      = false,
        mergeJunkEntries      = false,
        instanceLockoutEnabled = false,
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
    -- gearThresholdOff is a table - copy it so the two profiles don't share it
    if type(src.gearThresholdOff) == "table" then
        copy.gearThresholdOff = {}
        for k, v in pairs(src.gearThresholdOff) do copy.gearThresholdOff[k] = v end
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
    if db.count         == nil then db.count         = {}                      end
    if not db.itemKeysMigrated then
        MigrateItemKeys(db.count)
        db.itemKeysMigrated = true
    end
    -- One-time repairs for the LIVE (unsaved) session - see
    -- ns.RunCharacterRepairs / ns.CHARACTER_REPAIRS in Repairs.lua.
    ns.RunCharacterRepairs()
    if db.paused        == nil then db.paused        = true                    end
    if db.visible       == nil then db.visible       = true                    end
    if db.expanded      == nil then db.expanded      = false                   end
    if db.totalTime     == nil then db.totalTime     = 0                       end
    if db.pos           == nil then db.pos           = {"TOP","TOP",0,-150} end
    if db.qAtlas        == nil then db.qAtlas        = {}                      end
    if db.collapsed     == nil then db.collapsed     = {}                      end
    if db.excludedNames == nil then db.excludedNames = {}                      end
    if db.excludedItemIDs == nil then db.excludedItemIDs = {}                  end
    if db.goldRateMode  == nil then db.goldRateMode  = "hour"                  end
    if db.sessionLength == nil then db.sessionLength = 0                       end
    if db.minimapPos    == nil then db.minimapPos    = 225                     end
    if db.minimapHidden == nil then db.minimapHidden = false                   end
    -- LibDBIcon sub-table (migrates legacy keys on first load)
    if db.minimap == nil then
        db.minimap = { minimapPos = db.minimapPos, hide = db.minimapHidden }
    end
    if db.lootedGold    == nil then db.lootedGold    = 0                      end
    if db.sessionHistoryEnabled == nil then db.sessionHistoryEnabled = true  end
    if db.logWindowEnabled      == nil then db.logWindowEnabled      = false end
    if db.logWindowShown        == nil then db.logWindowShown        = false end
    if db.logEntries            == nil then db.logEntries            = {}    end
    if db.vendorFilterEnabled   == nil then db.vendorFilterEnabled   = true  end
    if db.blacklistEnabled      == nil then db.blacklistEnabled      = true  end
    if db.blacklistCategoriesCollapsed == nil then db.blacklistCategoriesCollapsed = false end
    if db.filterCategoriesCollapsed == nil then db.filterCategoriesCollapsed = false end
    if db.ahExpansionsCollapsed == nil then db.ahExpansionsCollapsed = false end
    if db.mergeDaily            == nil then db.mergeDaily            = true  end
    if db.splitTradeGoods       == nil then db.splitTradeGoods       = false end
    if db.splitGearByBinding    == nil then db.splitGearByBinding    = false end
    if db.ahSource        == nil then db.ahSource        = "auto"     end
    if db.gearAHThreshold == nil then db.gearAHThreshold = 0          end
    if db.goldDisplayMode == nil then db.goldDisplayMode = "classic"  end
    if db.tsmPriceSource  == nil then db.tsmPriceSource  = "DBMarket" end
    if db.tsmCustomSource == nil then db.tsmCustomSource = ""         end
    if db.colorTheme      == nil then db.colorTheme      = "default"  end
    if db.venomTrackerEnabled == nil then db.venomTrackerEnabled = false end
    ns.ApplyColorTheme(db.colorTheme)
end

-- Account-wide, standalone SavedVariable - own file, not nested under
-- NightsFarmtrackerAccountDB. Persisted via the separate, optional
-- "NightsFarmtrackerItemDB" companion addon (own .toc/SavedVariables
-- declaration) so it doesn't share a file with the main addon's data;
-- only needs to be enabled for Nightwalker559's classification audits -
-- other players can leave it disabled/uninstalled without any effect.
-- A one-entry-per-itemID catalog of every distinct item seen while
-- tracking is active. Debug/audit data only - lets Nightwalker559
-- verify category/subcategory classification is correct across a play
-- session. Populated in ProcessLoot (Main.lua) via ns.RecordItemDBEntry
-- (ItemHelper.lua).
function ns.InitItemDB()
    if not NightsFarmtrackerItemDB then NightsFarmtrackerItemDB = {} end
end

function ns.InitAccountDB()
    if not NightsFarmtrackerAccountDB then NightsFarmtrackerAccountDB = {} end
    if not NightsFarmtrackerAccountDB.sessions then
        NightsFarmtrackerAccountDB.sessions = {}
    end
    if not NightsFarmtrackerAccountDB.itemKeysMigrated then
        for _, session in ipairs(NightsFarmtrackerAccountDB.sessions) do
            MigrateItemKeys(session.items)
        end
        NightsFarmtrackerAccountDB.itemKeysMigrated = true
    end
    -- One-time repairs for saved session history - see
    -- ns.RunAccountRepairs / ns.ACCOUNT_REPAIRS in Repairs.lua.
    ns.RunAccountRepairs()
    if NightsFarmtrackerAccountDB.itemLinkMigrationPrompted == nil then
        NightsFarmtrackerAccountDB.itemLinkMigrationPrompted = false
    end
    if not NightsFarmtrackerAccountDB.forceVendor then
        NightsFarmtrackerAccountDB.forceVendor = {}
    end
    if not NightsFarmtrackerAccountDB.forceVendorCategories then
        NightsFarmtrackerAccountDB.forceVendorCategories = {}
    end
    if not NightsFarmtrackerAccountDB.ahExpansions then
        NightsFarmtrackerAccountDB.ahExpansions = {}
    end
    -- Default: every expansion shows AH price (matches pre-filter behavior),
    -- but only once - so unchecking boxes later persists across sessions
    -- instead of resetting back to "all on" every login.
    if NightsFarmtrackerAccountDB.ahExpansionsDefaulted == nil then
        if not next(NightsFarmtrackerAccountDB.ahExpansions) then
            for _, expID in ipairs(ns.EXPANSION_ORDER) do
                NightsFarmtrackerAccountDB.ahExpansions[expID] = true
            end
        end
        NightsFarmtrackerAccountDB.ahExpansionsDefaulted = true
    end
    if not NightsFarmtrackerAccountDB.blacklist then
        NightsFarmtrackerAccountDB.blacklist = {}
    end
    if not NightsFarmtrackerAccountDB.blacklistCategories then
        NightsFarmtrackerAccountDB.blacklistCategories = {}
    end
    -- Junk defaults to vendor-only (matches the previous hardcoded behavior),
    -- but only if the player hasn't already made an explicit choice here -
    -- SetForceVendorCategory always stores a real true/false, so this only
    -- ever fires once, on a fresh install or for characters that pre-date
    -- this setting.
    local junkName = ns.L and ns.L["cat_junk"]
    if junkName and NightsFarmtrackerAccountDB.forceVendorCategories[junkName] == nil then
        NightsFarmtrackerAccountDB.forceVendorCategories[junkName] = true
    end
end

------------------------------------------------------------------------
-- Forced-vendor filter (account-wide, persistent)
-- Items in this list always use VendorTotal, never AH price.
------------------------------------------------------------------------
function ns.IsForceVendor(itemID)
    if NightsFarmtrackerDB and NightsFarmtrackerDB.vendorFilterEnabled == false then return false end
    return itemID ~= nil
       and NightsFarmtrackerAccountDB ~= nil
       and NightsFarmtrackerAccountDB.forceVendor ~= nil
       and NightsFarmtrackerAccountDB.forceVendor[itemID] ~= nil
end

function ns.AddForceVendor(itemID, name, icon, quality)
    if not itemID then return end
    NightsFarmtrackerAccountDB.forceVendor[itemID] = { name = name, icon = icon, quality = quality }
end

function ns.RemoveForceVendor(itemID)
    if not itemID then return end
    NightsFarmtrackerAccountDB.forceVendor[itemID] = nil
end

function ns.ClearForceVendor()
    if not NightsFarmtrackerAccountDB then return end
    wipe(NightsFarmtrackerAccountDB.forceVendor)
end

------------------------------------------------------------------------
-- Forced-vendor filter by item category (account-wide, persistent)
-- Keyed by category NAME (the exact string ns.CategoryName() returns),
-- not by classID. This means it automatically follows whatever grouping
-- is currently shown in the HUD - including the splitTradeGoods subtype
-- split (e.g. "Metal & Stone", "Herb" become individually toggleable once
-- that setting is on, instead of one combined "Trade Goods" entry).
-- Same name-as-key pattern already used by ns.ExcludeItem/excludedNames.
------------------------------------------------------------------------
function ns.IsForceVendorCategoryEnabled(name)
    return NightsFarmtrackerAccountDB ~= nil
       and NightsFarmtrackerAccountDB.forceVendorCategories ~= nil
       and NightsFarmtrackerAccountDB.forceVendorCategories[name] == true
end

function ns.SetForceVendorCategory(name, enabled)
    if not NightsFarmtrackerAccountDB or not NightsFarmtrackerAccountDB.forceVendorCategories then return end
    NightsFarmtrackerAccountDB.forceVendorCategories[name] = enabled and true or false
end

-- True if this item's current category is forced to vendor price.
function ns.IsForceVendorCategory(data)
    if NightsFarmtrackerDB and NightsFarmtrackerDB.vendorFilterEnabled == false then return false end
    if NightsFarmtrackerAccountDB == nil or NightsFarmtrackerAccountDB.forceVendorCategories == nil then return false end
    local name = ns.CategoryName(data)
    return name ~= nil and NightsFarmtrackerAccountDB.forceVendorCategories[name] == true
end

------------------------------------------------------------------------
-- AH Price by Expansion (account-wide, persistent) — an opt-in whitelist:
-- with nothing selected the filter is inactive (AH works as always). Once
-- at least one expansion is checked, items from any OTHER expansion are
-- forced to vendor price, matching e.g. "only show AH for Midnight gear".
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

-- True if any expansion is currently selected (i.e. the filter is active).
function ns.HasAHExpansionSelection()
    local sel = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.ahExpansions
    return sel ~= nil and next(sel) ~= nil
end

-- True if this item's expansion is forced to vendor price by the filter.
function ns.IsForceVendorExpansion(data)
    if NightsFarmtrackerDB and NightsFarmtrackerDB.vendorFilterEnabled == false then return false end
    if not ns.HasAHExpansionSelection() then return false end
    local expID = ns.GetItemExpansionID(data)
    if expID == nil then return false end
    return not ns.IsAHExpansionEnabled(expID)
end

------------------------------------------------------------------------
-- Blacklist (account-wide, persistent) — items/categories in here are
-- never tracked at all. Same storage pattern as the Vendor-Only filter
-- (itemID-keyed items, name-keyed categories). Takes priority over
-- everything else, including Vendor-Only: a blacklisted item is skipped
-- before any price logic runs.
------------------------------------------------------------------------
function ns.IsBlacklisted(itemID)
    if NightsFarmtrackerDB and NightsFarmtrackerDB.blacklistEnabled == false then return false end
    return itemID ~= nil
       and NightsFarmtrackerAccountDB ~= nil
       and NightsFarmtrackerAccountDB.blacklist ~= nil
       and NightsFarmtrackerAccountDB.blacklist[itemID] ~= nil
end

function ns.AddBlacklist(itemID, name, icon, quality)
    if not itemID then return end
    NightsFarmtrackerAccountDB.blacklist[itemID] = { name = name, icon = icon, quality = quality }
end

function ns.RemoveBlacklist(itemID)
    if not itemID then return end
    NightsFarmtrackerAccountDB.blacklist[itemID] = nil
end

function ns.ClearBlacklist()
    if not NightsFarmtrackerAccountDB then return end
    wipe(NightsFarmtrackerAccountDB.blacklist)
end

function ns.IsBlacklistCategoryEnabled(name)
    return NightsFarmtrackerAccountDB ~= nil
       and NightsFarmtrackerAccountDB.blacklistCategories ~= nil
       and NightsFarmtrackerAccountDB.blacklistCategories[name] == true
end

function ns.SetBlacklistCategory(name, enabled)
    if not NightsFarmtrackerAccountDB or not NightsFarmtrackerAccountDB.blacklistCategories then return end
    NightsFarmtrackerAccountDB.blacklistCategories[name] = enabled and true or false
end

-- True if this item's current category is blacklisted.
function ns.IsBlacklistCategory(data)
    if NightsFarmtrackerDB and NightsFarmtrackerDB.blacklistEnabled == false then return false end
    if NightsFarmtrackerAccountDB == nil or NightsFarmtrackerAccountDB.blacklistCategories == nil then return false end
    local name = ns.CategoryName(data)
    return name ~= nil and NightsFarmtrackerAccountDB.blacklistCategories[name] == true
end

------------------------------------------------------------------------
-- Generic frame docking — anchors `frame` to a side of `anchor`
-- ("right" or "left" of it), falling back to docking BELOW the anchor
-- instead if there isn't enough room left on screen in that direction.
-- Used by every window that docks next to another one (Log/Filter/
-- Blacklist to the right of MainFrame, Session History to the left of
-- MainFrame, Session Detail to the left of History) so none of them can
-- overlap another frame or run off the screen edge.
------------------------------------------------------------------------
function ns.DockFrame(frame, anchor, side)
    frame:ClearAllPoints()
    local width       = frame:GetWidth() or ns.FRAME_W
    local screenLeft  = UIParent:GetLeft()
    local screenRight = UIParent:GetRight()
    if side == "left" then
        local anchorLeft = anchor:GetLeft()
        if anchorLeft and screenLeft and (anchorLeft - 1 - width) < screenLeft then
            frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -1)
        else
            frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -1, 0)
        end
    else
        local anchorRight = anchor:GetRight()
        if anchorRight and screenRight and (anchorRight + 1 + width) > screenRight then
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -1)
        else
            frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 1, 0)
        end
    end
end

------------------------------------------------------------------------
-- Unified window-docking chains — every window that docks next to
-- MainFrame (in a chain to its left or right) is registered here by
-- name instead of each window hardcoding its neighbors. One generic
-- function (ns.RefreshWindowChain) walks a chain and re-docks every
-- currently shown window in that fixed order: MainFrame -> first shown
-- -> next shown -> ... This guarantees a consistent, non-overlapping
-- layout no matter which window was opened first, and can never create
-- a circular SetPoint dependency (each window only ever anchors to one
-- earlier in its own chain). Session Detail is a child of History (only
-- ever open together with it) so it anchors directly to HistFrame
-- elsewhere instead of joining the left chain as a peer.
--
-- To add a new docked window: expose it as ns.<Key>Frame, add "<Key>Frame"
-- to the relevant chain below, and call ns.RefreshWindowChain(side) after
-- showing/hiding it (see Log/Filter/Blacklist/History/Settings for the
-- pattern - toggle function shows/hides, then refreshes its chain).
------------------------------------------------------------------------
ns.WINDOW_CHAINS = {
    right = { "LogFrame", "FilterFrame", "BlacklistFrame" },
    left  = { "HistFrame", "SettingsFrame", "ExportFrame", "DebugFrame" },
}

function ns.RefreshWindowChain(side)
    local order = ns.WINDOW_CHAINS[side]
    if not order then return end
    local prev = ns.MainFrame
    for _, key in ipairs(order) do
        local f = ns[key]
        -- Log docks BELOW MainFrame while collapsed - it sits outside the
        -- horizontal chain in that state, so it is skipped as a link.
        local collapsedLog = key == "LogFrame" and NightsFarmtrackerDB and NightsFarmtrackerDB.expanded == false
        if f and f:IsShown() and not collapsedLog then
            ns.DockFrame(f, prev, side)
            prev = f
        end
    end
end

------------------------------------------------------------------------
-- Icon badge helper — overlay on the bottom-right corner of the item icon
-- (used for crafting-reagent rank icons R1/R2/R3). Shared by every frame
-- that shows item icons, so the badge position/size stays identical.
-- It sits on the icon itself, so item names anchor to the icon's RIGHT and
-- no horizontal space is reserved for it.
------------------------------------------------------------------------
function ns.CreateIconBadge(parent, icon)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    fs:SetFontHeight(ns.FONT_SMALL)
    fs:SetJustifyH("RIGHT")
    return fs
end

------------------------------------------------------------------------
-- Row appearance helper — icon border + name color by item quality.
-- Shared by all item rows (main HUD, history detail, filter list, log)
-- so the "look" lives in one place instead of being duplicated per file.
------------------------------------------------------------------------
function ns.ApplyQualityColor(nameText, iconBorder, quality, fallbackColor)
    if quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        nameText:SetTextColor(r, g, b)
        iconBorder:SetColorTexture(r, g, b, 0.9)
        iconBorder:Show()
    else
        local fr, fg, fb = unpack(fallbackColor or {1, 1, 1})
        nameText:SetTextColor(fr, fg, fb)
        iconBorder:Hide()
    end
end

------------------------------------------------------------------------
-- Rank badge straight from a saved item link — some crafting reagents
-- (e.g. per-rank ore) bake their quality tier directly into the item's
-- own display name as an atlas markup (".../Tier1", ".../Tier2", ...),
-- e.g. "|A:Professions-ChatIcon-Quality-12-Tier1:17:15::1|a". That's fixed
-- by the item itself at link time, so it works from any saved itemLink
-- regardless of whether that entry's live q[]/qIDs tracking (from
-- GetReagentQualityInfo, see ProcessLoot) is trustworthy - used as the
-- fallback rank badge for entries whose q[] breakdown didn't pass the
-- consistency check in BuildSessionCategories/RefreshHUD.
------------------------------------------------------------------------
function ns.RankIconFromLink(link)
    if not link then return nil end
    local atlasName = link:match("|A:(.-):")
    if not atlasName or not atlasName:find("Tier%d") then return nil end
    return CreateAtlasMarkup(atlasName, ns.RANK_ICON_W, ns.RANK_ICON_H)
end

------------------------------------------------------------------------
-- Shared collapsible section header (category/expansion-style headers).
-- One recipe for the frame + full-width background + bottom separator +
-- accent-colored label used by the Filter and Blacklist windows (and
-- matching History's month header), so all of them share one height/font
-- setup instead of each file rebuilding slightly different versions that
-- can drift out of sync (that mismatch is what caused the header text to
-- render off-center in 1.4.x). Caller still positions it (SetPoint) and
-- wires OnMouseUp/OnEnter/OnLeave for its own collapse/tooltip behavior.
------------------------------------------------------------------------
function ns.CreateSectionHeader(parent, width)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(width, ns.CAT_ROW_H)
    header:EnableMouse(true)

    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(ns.COL_CAT_BG))
    header.bg = bg

    local topSep = header:CreateTexture(nil, "ARTWORK"); topSep:SetHeight(1)
    topSep:SetColorTexture(unpack(ns.COL_BORDER))
    topSep:SetPoint("TOPLEFT"); topSep:SetPoint("TOPRIGHT")
    header.topSep = topSep

    local sep = header:CreateTexture(nil, "ARTWORK"); sep:SetHeight(1)
    sep:SetColorTexture(unpack(ns.COL_BORDER))
    sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT")
    header.sep = sep

    local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 4, 0)
    text:SetFontHeight(ns.FONT_NORMAL)
    text:SetTextColor(unpack(ns.COL_ACCENT))
    header.text = text

    return header
end

------------------------------------------------------------------------
-- Shared checkbox row — box + accent-colored mark + label. Used by every
-- collapsible checkbox list (Vendor-Only Filter categories, AH-by-
-- expansion list, Blacklist categories) so the three no longer each build
-- a slightly different copy. Caller positions the row, sets the label
-- text, and wires its own OnMouseUp/OnEnter/OnLeave.
------------------------------------------------------------------------
function ns.CreateCheckboxRow(parent, width, height)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(width, height)
    r:EnableMouse(true)

    local box = CreateFrame("Frame", nil, r, "BackdropTemplate")
    box:SetSize(12, 12); box:SetPoint("LEFT", 0, 0)
    ns.StyleBackdropBox(box)

    local mark = box:CreateTexture(nil,"ARTWORK")
    mark:SetSize(6,6); mark:SetPoint("CENTER")
    mark:SetColorTexture(unpack(ns.COL_ACCENT))
    r.mark = mark

    local lbl = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
    lbl:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    r.lbl = lbl

    return r
end

------------------------------------------------------------------------
-- Shared "drop-list" item row — icon + name + bottom separator, item
-- tooltip on hover, Shift+Right-click removes it via the given callback.
-- Used by the Vendor-Only Filter and Blacklist item lists (identical row
-- shape; only the removal/rebuild behavior differs between the two).
------------------------------------------------------------------------
function ns.CreateDropListItemRow(parent, onShiftRemove)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(ns.CONTENT_W, ns.ROW_H)
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

    r.nameText = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.nameText:SetPoint("LEFT",  r.icon, "RIGHT", 8, 0)
    r.nameText:SetPoint("RIGHT", r,      "RIGHT", -4, 0)
    r.nameText:SetJustifyH("LEFT"); r.nameText:SetFontHeight(ns.FONT_NORMAL)
    r.nameText:SetTextColor(0.85,0.85,0.85)

    r:SetScript("OnEnter", function(self)
        if self.itemID then
            ns.ShowItemTooltipNoCompare(self, "ANCHOR_RIGHT", nil, self.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.L["filter_tip_shift_rclick"],0.5,0.5,0.5)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" and IsShiftKeyDown() and self.itemID then
            onShiftRemove(self.itemID)
        end
    end)
    return r
end

------------------------------------------------------------------------
-- Shared permanent drop-target zone (dashed accent border, centered hint
-- label) used by the Vendor-Only Filter and Blacklist windows to accept
-- item drags from bags. onDrop is called for both the real drag-hold-
-- release gesture (OnReceiveDrag) and a left-click while holding an item
-- (OnMouseUp), matching ns.HandleItemDrop's two-script pattern.
------------------------------------------------------------------------
function ns.CreateDropZone(parent, height, onDrop)
    local dz = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dz:SetHeight(height)
    dz:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8x8",
        tile     = true, tileSize = 8, edgeSize = 1,
        insets   = {left=1, right=1, top=1, bottom=1},
    })
    dz:SetBackdropColor(unpack(ns.COL_CAT_BG))
    dz:SetBackdropBorderColor(unpack(ns.COL_ACCENT))
    dz:EnableMouse(true)
    ns.EnableItemDrop(dz, onDrop)
    dz:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0) end)
    dz:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(ns.COL_ACCENT)) end)

    dz.label = dz:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dz.label:SetPoint("CENTER")
    dz.label:SetTextColor(unpack(ns.COL_ACCENT))
    dz.label:SetText(ns.L["filter_drop_hint"])

    return dz
end

------------------------------------------------------------------------
-- Shared "Clear All" footer button (bottom-right, dim red -> bright red
-- on hover) used by the Vendor-Only Filter and Blacklist windows.
-- hasDataFn guards against popping the confirm dialog on an empty list.
------------------------------------------------------------------------
function ns.CreateClearAllButton(parent, pad, hasDataFn, popupName)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(70, 18)
    btn:SetPoint("BOTTOMRIGHT", -pad, 6)
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetAllPoints(); lbl:SetJustifyH("RIGHT"); lbl:SetText(ns.L["clear_all"])
    lbl:SetTextColor(0.50,0.22,0.22)
    btn:SetScript("OnClick", function()
        if not hasDataFn() then return end
        StaticPopup_Show(popupName)
    end)
    btn:SetScript("OnEnter", function() lbl:SetTextColor(1,0.4,0.4) end)
    btn:SetScript("OnLeave", function() lbl:SetTextColor(0.50,0.22,0.22) end)
    return btn
end

------------------------------------------------------------------------
-- Scroll frame + list frame pair for the Vendor-Only Filter / Blacklist
-- item lists: mouse-wheel scrolling in row steps, item drops accepted on
-- the list area too. Caller sizes/positions the scroll frame (see
-- ns.RebuildDropItemList). Returns scrollFrame, listFrame.
------------------------------------------------------------------------
function ns.CreateDropListScroll(window, onDrop)
    local scrollFrame = CreateFrame("ScrollFrame", nil, window)
    scrollFrame:SetWidth(ns.CONTENT_W)
    scrollFrame:EnableMouseWheel(true)

    local listFrame = CreateFrame("Frame", nil, scrollFrame)
    listFrame:SetWidth(ns.CONTENT_W); listFrame:SetHeight(1)
    listFrame:EnableMouse(true)
    scrollFrame:SetScrollChild(listFrame)
    ns.EnableItemDrop(listFrame, onDrop)

    local function OnWheel(_, delta)
        local cur  = scrollFrame:GetVerticalScroll()
        local maxS = math.max(0, listFrame:GetHeight() - scrollFrame:GetHeight())
        scrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta * ns.ROW_H, maxS)))
    end
    scrollFrame:SetScript("OnMouseWheel", OnWheel)
    listFrame:SetScript("OnMouseWheel", OnWheel)

    return scrollFrame, listFrame
end

------------------------------------------------------------------------
-- Custom icon button (texture from the Media folder): dimmed until
-- hovered, nudged while pressed. Shared by the main window and the
-- Venom Tracker / Fishing Lure Bar overlays.
------------------------------------------------------------------------
function ns.MakeBtn(parent, size, artFile)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(ns.ART .. artFile)
    btn.tex:SetAlpha(0.75)
    btn:SetScript("OnMouseDown", function(self)
        self.tex:ClearAllPoints()
        self.tex:SetSize(size - 3, size - 3)
        self.tex:SetPoint("CENTER", 1, -1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.tex:ClearAllPoints(); self.tex:SetAllPoints()
    end)
    btn:SetScript("OnEnter", function(self) self.tex:SetAlpha(1.0) end)
    btn:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75) end)
    return btn
end

------------------------------------------------------------------------
-- Shared collapsible checkbox section — one CreateSectionHeader title
-- (click to collapse/expand) above N pooled checkbox rows. Used by the
-- Vendor-Only Filter and Blacklist windows for their category lists, and
-- by the Vendor-Only Filter for its AH-by-expansion list, so all three no
-- longer duplicate the same row-rendering loop.
--
-- frame:      the window frame the rows are parented to
-- header:     the section's CreateSectionHeader widget (frame.catHeader etc.)
-- pool/rows:  the row pool + currently-active-rows table this section owns
--             (each caller keeps its own, since sections don't share rows)
-- padX:       left padding (F_PAD/B_PAD)
-- secTop:     Y offset (from the window's top) where this section starts
-- titleText:  header label (without the "+"/"-" prefix, added here)
-- collapsed:  current collapsed state for this section
-- entries:    { {key=<opaque>, label=<string>}, ... } to render as rows
-- isEnabled(key) / setEnabled(key, val): checkbox state accessors
-- onChanged(): optional, called after a row is toggled (e.g. ns.RefreshHUD)
--
-- Returns the Y offset where the NEXT section should start.
------------------------------------------------------------------------
function ns.RebuildCheckboxSection(frame, header, pool, rows, padX, secTop, titleText, collapsed, entries, isEnabled, setEnabled, onChanged)
    for _, r in ipairs(rows) do
        r:Hide(); r:ClearAllPoints(); r:SetScript("OnMouseUp", nil)
        pool[#pool+1] = r
    end
    for i = #rows, 1, -1 do rows[i] = nil end

    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", padX, -secTop)
    header.text:SetText((collapsed and "+ " or "- ") .. titleText)

    local n = 0
    if not collapsed then
        n = #entries
        for i, entry in ipairs(entries) do
            local r = table.remove(pool)
            if r then r:SetParent(frame); r:Show()
            else r = ns.CreateCheckboxRow(frame, ns.CONTENT_W, ns.CHECKBOX_ROW_H) end
            r:SetPoint("TOPLEFT", padX, -(secTop + ns.CAT_ROW_H + (i-1) * ns.CHECKBOX_ROW_H))
            r.lbl:SetText(entry.label)

            local function Refresh()
                if isEnabled(entry.key) then
                    r.mark:Show(); r.lbl:SetTextColor(1, 0.82, 0)
                else
                    r.mark:Hide(); r.lbl:SetTextColor(0.85, 0.85, 0.85)
                end
            end
            r:SetScript("OnMouseUp", function()
                setEnabled(entry.key, not isEnabled(entry.key))
                Refresh()
                if onChanged then onChanged() end
            end)
            Refresh()
            rows[#rows + 1] = r
        end
    end

    return secTop + ns.CAT_ROW_H + n * ns.CHECKBOX_ROW_H + 4
end

------------------------------------------------------------------------
-- Shared drop-list item rebuild — used by the Vendor-Only Filter and
-- Blacklist windows for their bottom item list: pooled icon+name rows
-- (see ns.CreateDropListItemRow), sorted by name, sized/positioned scroll
-- area, and the "list empty" label. The two windows differ only in which
-- account-wide item table backs the list and what Shift+Right-click does
-- (both passed in via cfg).
--
-- cfg fields: window, listFrame, scrollFrame, emptyLabel (frames/widgets),
-- pool, rows (this list's own row pool + active-rows table), padX,
-- listTop, ftrH, minVisH, maxVisH (layout), items (itemID -> {name,icon,
-- quality} table), onShiftRemove(itemID) (passed straight to
-- ns.CreateDropListItemRow for newly-created rows).
------------------------------------------------------------------------
function ns.RebuildDropItemList(cfg)
    local pool, rows = cfg.pool, cfg.rows
    for _, r in ipairs(rows) do
        r:Hide(); r:ClearAllPoints(); r.itemID = nil; r.iconBorder:Hide()
        pool[#pool + 1] = r
    end
    for i = #rows, 1, -1 do rows[i] = nil end

    local list = {}
    for itemID, entry in pairs(cfg.items or {}) do
        list[#list + 1] = { itemID = itemID, name = entry.name, icon = entry.icon, quality = entry.quality }
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)

    local yOff = 0
    for _, e in ipairs(list) do
        local r = table.remove(pool)
        if r then r:SetParent(cfg.listFrame); r:Show()
        else r = ns.CreateDropListItemRow(cfg.listFrame, cfg.onShiftRemove) end
        r:SetPoint("TOPLEFT", 0, -yOff)
        r.sep:SetShown(yOff > 0)
        r.icon:SetTexture(e.icon or ns.FALLBACK_ICON)
        r.nameText:SetText(ns.TruncateName(ns.DisplayName(e.name, e.itemID) or ("Item " .. e.itemID)))
        r.itemID = e.itemID
        ns.ApplyQualityColor(r.nameText, r.iconBorder, e.quality, {0.85, 0.85, 0.85})
        rows[#rows + 1] = r
        yOff = yOff + ns.ROW_H
    end

    cfg.scrollFrame:ClearAllPoints()
    cfg.scrollFrame:SetPoint("TOPLEFT", cfg.padX, -cfg.listTop)

    local contentH = math.max(1, yOff)
    cfg.listFrame:SetHeight(contentH)
    local visH = math.max(cfg.minVisH, math.min(contentH, cfg.maxVisH))
    cfg.scrollFrame:SetHeight(visH)
    cfg.window:SetHeight(cfg.listTop + visH + cfg.ftrH)

    cfg.emptyLabel:ClearAllPoints()
    cfg.emptyLabel:SetPoint("TOP", cfg.window, "TOP", 0, -(cfg.listTop + 14))
    cfg.emptyLabel:SetShown(#list == 0)
end

------------------------------------------------------------------------
-- Shared window shell: border/background (ApplyFrameStyle), movable +
-- clamped, ESC-closable (UISpecialFrames), title text, close button.
-- Used by every top-level window (History, Log, Filter, Blacklist,
-- Settings) so they can't drift out of sync with each other. Callers add
-- their own content below the header (scroll frame, header separator at
-- their own HDR_H, etc.) and can hook extra close behavior via
-- frame:SetScript("OnHide", ...) or frame.closeBtn:HookScript("OnClick", ...).
--
-- opts (all optional): width, pad (default ns.PAD), titleColor (default
-- ns.COL_GOLD), titleY (default -10).
------------------------------------------------------------------------
function ns.CreateWindowFrame(name, title, opts)
    opts = opts or {}
    local pad = opts.pad or ns.PAD

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    if opts.width then frame:SetWidth(opts.width) end
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    frame:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    ns.ApplyFrameStyle(frame)
    frame:Hide()
    table.insert(UISpecialFrames, name)

    local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFS:SetPoint("TOPLEFT", pad, opts.titleY or -10)
    titleFS:SetPoint("TOPRIGHT", -pad, opts.titleY or -10)
    titleFS:SetJustifyH("CENTER")
    titleFS:SetText(title)
    titleFS:SetTextColor(unpack(opts.titleColor or ns.COL_GOLD))
    titleFS:SetFontHeight(ns.FONT_HEADER)
    frame.titleFS = titleFS

    local xBtn = CreateFrame("Button", nil, frame)
    xBtn:SetSize(18, 18)
    xBtn:SetPoint("TOPRIGHT", -pad, opts.titleY or -10)
    local xTex = xBtn:CreateTexture(nil, "ARTWORK")
    xTex:SetAllPoints()
    xTex:SetTexture(ns.ART.."btn_close.png")
    xTex:SetAlpha(0.8)
    xBtn:SetScript("OnClick", function()
        if not ns.DeferInCombat(function() frame:Hide() end) then frame:Hide() end
    end)
    xBtn:SetScript("OnEnter", function() xTex:SetAlpha(1) end)
    xBtn:SetScript("OnLeave", function() xTex:SetAlpha(0.8) end)
    frame.closeBtn = xBtn
    frame.closeTex = xTex

    return frame
end

------------------------------------------------------------------------
-- Frame style helper — square 1px border, dark teal background.
-- Used by all windows (main, history, detail, settings).
------------------------------------------------------------------------
function ns.ApplyFrameStyle(frame)
    frame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        tile     = true, tileSize = 16,
        insets   = {left=0, right=0, top=0, bottom=0},
    })
    frame:SetBackdropColor(unpack(ns.COL_BG))
    -- Draw 1px square border as four colored textures. Tracked on the frame
    -- so ns.RefreshFrameStyle() can recolor them later (needed for frames
    -- built before SavedVariables/theme are loaded, e.g. MainFrame).
    frame.nftEdges = frame.nftEdges or {}
    local function Edge(p1, p2, horiz)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(ns.COL_BORDER))
        if horiz then t:SetHeight(1) else t:SetWidth(1) end
        t:SetPoint(p1); t:SetPoint(p2)
        frame.nftEdges[#frame.nftEdges+1] = t
    end
    Edge("TOPLEFT",    "TOPRIGHT",    true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT",    "BOTTOMLEFT",  false)
    Edge("TOPRIGHT",   "BOTTOMRIGHT", false)
end

-- Re-applies the current theme colors to a frame already styled via
-- ApplyFrameStyle. Needed for MainFrame specifically: it's built while
-- UI.lua loads, which happens before SavedVariables/InitDB have set the
-- saved theme, so its border/background start out on the default colors.
-- Extra COL_BORDER-colored textures (e.g. header/footer separators) can be
-- added to frame.nftEdges by the caller so they get refreshed too.
function ns.RefreshFrameStyle(frame)
    if not frame or not frame.nftEdges then return end
    frame:SetBackdropColor(unpack(ns.COL_BG))
    for _, t in ipairs(frame.nftEdges) do
        t:SetColorTexture(unpack(ns.COL_BORDER))
    end
    if frame.nftAccentTexts then
        for _, fs in ipairs(frame.nftAccentTexts) do
            fs:SetTextColor(unpack(ns.COL_ACCENT))
        end
    end
end

------------------------------------------------------------------------
-- Gear AH Threshold alert sound. Looks for a user-supplied custom file
-- at Media\ThresholdAlert.ogg / .mp3 first; falls back to a built-in
-- SoundKit if neither is present in the addon folder.
------------------------------------------------------------------------
local THRESHOLD_SOUND_BASE = "Interface\\AddOns\\NightsFarmtracker\\Media\\ThresholdAlert"

function ns.PlayThresholdAlertSound()
    local willPlay = PlaySoundFile(THRESHOLD_SOUND_BASE .. ".ogg", "Master")
    if not willPlay then
        willPlay = PlaySoundFile(THRESHOLD_SOUND_BASE .. ".mp3", "Master")
    end
    if not willPlay then
        PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST, "Master")
    end
end

------------------------------------------------------------------------
-- Generic copyable text window - scrolling, pre-selected EditBox. WoW
-- addons can't write the OS clipboard directly, so the standard pattern
-- is: show the text, select it all, let the user Ctrl+C. Shared by Data
-- Export (NightsFarmtrackerExport.lua) and the Debug dump commands
-- (NightsFarmtrackerDebug.lua) so both get one copy of this UI code.
--
-- ns.CreateCopyTextWindow(name, title) builds one such window (call once,
-- keep the returned frame). ns.ShowCopyText(frame, text) fills it and
-- shows it, docked next to Settings if open, else centered.
------------------------------------------------------------------------
function ns.CreateCopyTextWindow(name, title)
    local W, HDR_H, FTR_H = 460, ns.WINDOW_HDR_H, 12

    local frame = ns.CreateWindowFrame(name, title, {width = W, pad = ns.PAD, titleColor = ns.COL_ACCENT})
    frame:SetHeight(360)
    frame:SetScript("OnHide", function() ns.RefreshWindowChain("left") end)

    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(unpack(ns.COL_BORDER))
    sep:SetPoint("TOPLEFT", ns.PAD, -(HDR_H - 1)); sep:SetPoint("TOPRIGHT", -ns.PAD, -(HDR_H - 1))

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", ns.PAD, -(HDR_H + 6))
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText(ns.L["copy_hint_window"])

    local selectBtn = CreateFrame("Button", nil, frame)
    selectBtn:SetSize(90, 16)
    selectBtn:SetPoint("TOPRIGHT", -ns.PAD, -(HDR_H + 6))
    local selectText = selectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selectText:SetAllPoints(); selectText:SetJustifyH("RIGHT")
    selectText:SetTextColor(unpack(ns.COL_ACCENT))
    selectText:SetText(ns.L["export_select_all"])
    selectBtn:SetScript("OnEnter", function() selectText:SetTextColor(1, 1, 1) end)
    selectBtn:SetScript("OnLeave", function() selectText:SetTextColor(unpack(ns.COL_ACCENT)) end)
    selectBtn:SetScript("OnClick", function() frame.box:SetFocus(); frame.box:HighlightText() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", ns.PAD, -(HDR_H + 26))
    scrollFrame:SetPoint("BOTTOMRIGHT", -ns.PAD - 2, FTR_H)
    scrollFrame:EnableMouseWheel(true)

    local boxBG = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
    boxBG:SetAllPoints(scrollFrame)
    boxBG:SetFrameLevel(scrollFrame:GetFrameLevel())
    ns.StyleBackdropBox(boxBG, {0.05, 0.08, 0.09, 1})

    -- Multi-line EditBox left un-sized on height: with only its width set,
    -- it auto-grows to fit its text - exactly what a scroll child needs,
    -- no manual height bookkeeping on every SetText.
    local box = CreateFrame("EditBox", nil, scrollFrame)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextColor(0.85, 0.85, 0.85)
    box:SetWidth(W - ns.PAD * 2 - 24)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(box)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur  = self:GetVerticalScroll()
        local maxS = math.max(0, box:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 22, maxS)))
    end)

    frame.scrollFrame = scrollFrame
    frame.box = box
    return frame
end

-- Fills a window built by ns.CreateCopyTextWindow with `text` and shows
-- it (docked next to Settings if open, else centered), pre-selected for
-- an immediate Ctrl+C.
function ns.ShowCopyText(frame, text)
    frame.box:SetText(text)
    frame.scrollFrame:UpdateScrollChildRect()
    frame.scrollFrame:SetVerticalScroll(0)
    frame:ClearAllPoints()
    if ns.SettingsFrame and ns.SettingsFrame:IsShown() then
        ns.DockFrame(frame, ns.SettingsFrame, "left")
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    frame.box:SetFocus()
    frame.box:HighlightText()
    ns.RefreshWindowChain("left")
end
