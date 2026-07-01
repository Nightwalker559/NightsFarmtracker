------------------------------------------------------------------------
-- Night's Farmtracker - Core
------------------------------------------------------------------------
local ADDON_NAME, ns = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
ns.ADDON_NAME     = ADDON_NAME
ns.TRADE_GOODS    = Enum.ItemClass.Tradegoods
ns.QUEST_CLASS    = Enum.ItemClass.Questitem
ns.BIND_ON_EQUIP  = 2
ns.BIND_ON_PICKUP = 1
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
-- Legacy aliases (used in History fallback)
ns.CAT_VENDOR = "Vendor Trash"
ns.CAT_MATS   = "Tradeskill"

-- UI layout
ns.FRAME_W     = 310
ns.PAD         = 10
ns.ROW_H       = 34
ns.CAT_ROW_H   = 22
ns.CAT_INDENT  = 8
ns.FOOTER_H    = 32
ns.ICON_SIZE   = 22
ns.RANK_ICON_W = 14   -- width of the R1/R2/R3 atlas markup (CreateAtlasMarkup)
ns.RANK_ICON_H = 16   -- height of the R1/R2/R3 atlas markup
ns.CONTENT_W   = ns.FRAME_W - ns.PAD * 2
ns.MAX_ROWS    = 8
ns.SCROLL_STEP = ns.ROW_H

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
}
-- Display order for the Settings dropdown
ns.COLOR_THEME_ORDER = {"default", "void", "silvermoon", "fel", "frost", "bloodmoon"}
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
-- Utility
------------------------------------------------------------------------
function ns.FormatTime(s)
    s = math.floor(s or 0)
    return string.format("%02d:%02d:%02d",
        math.floor(s/3600), math.floor((s%3600)/60), s%60)
end

local function FormatGoldClassic(copper)
    if copper >= 10000 then
        -- Gold + Silber (auf nächste Silbermünze runden)
        return GetCoinTextureString(math.floor(copper / 100) * 100)
    end
    -- Unter 1g: Silber + Kupfer
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
        parts[#parts+1] = MONEY_GOLD_CC .. gold .. ns.L["coin_gold"] .. MONEY_CC_CLOSE
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
local NAME_MAX = 20
function ns.TruncateName(name)
    if not name then return "" end
    if #name > NAME_MAX then
        return name:sub(1, NAME_MAX - 2) .. ".."
    end
    return name
end

------------------------------------------------------------------------
-- Price source detection
------------------------------------------------------------------------
function ns.HasAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1 and true or false
end

function ns.HasTSM()
    return TSM_API ~= nil
end

function ns.HasAnyAH()
    return ns.HasAuctionator() or ns.HasTSM()
end

function ns.GetAuctionatorPrice(itemID)
    if not ns.HasAuctionator() or not itemID then return nil end
    local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON_NAME, itemID)
    return ok and p and p > 0 and p or nil
end

ns.TSM_SOURCES = {"DBMarket","DBRegionMarketAvg","DBMinBuyout","VendorSell"}

function ns.GetTSMPrice(itemID)
    if not ns.HasTSM() or not itemID then return nil end
    local db     = NightsFarmtrackerDB
    local custom = db.tsmCustomSource and db.tsmCustomSource ~= "" and db.tsmCustomSource
    local source = custom or db.tsmPriceSource or "DBMarket"
    local ok, p  = pcall(TSM_API.GetCustomPriceValue, source, "i:"..itemID)
    return ok and type(p)=="number" and p > 0 and p or nil
end

function ns.GetAHPriceForID(itemID)
    if not itemID then return nil end
    local src = NightsFarmtrackerDB.ahSource or "auto"
    if src == "auctionator" then return ns.GetAuctionatorPrice(itemID) end
    if src == "tsm"         then return ns.GetTSMPrice(itemID) end
    -- auto: prefer Auctionator, fallback TSM
    return ns.GetAuctionatorPrice(itemID) or ns.GetTSMPrice(itemID)
end

------------------------------------------------------------------------
-- Item helpers
------------------------------------------------------------------------
function ns.IsMat(data)
    if data.classID then
        return data.classID == 7 or data.classID == 5
    end
    return not data.isVendorTrash and not data.isBoE and not data.isBoP
end

function ns.CategoryName(data)
    if data.isVendorTrash or (data.quality == 0) then
        return ns.L and ns.L["cat_junk"] or "Junk"
    end
    if data.classID then
        if data.classID == 2 or data.classID == 4 then
            return ns.L and ns.L["cat_gear"] or "Equipment"
        end
        -- Mounts / Companion Pets always get their own category (classID 15, Miscellaneous)
        if data.classID == Enum.ItemClass.Miscellaneous and data.subClassID then
            if data.subClassID == Enum.ItemMiscellaneousSubclass.Mount then
                return ns.L and ns.L["cat_mounts"] or "Mounts"
            end
            if data.subClassID == Enum.ItemMiscellaneousSubclass.CompanionPet then
                return ns.L and ns.L["cat_pets"] or "Pets"
            end
        end
        -- Split trade goods (7) and reagents (5) by WoW subtype when enabled
        if (data.classID == 7 or data.classID == 5)
        and NightsFarmtrackerDB and NightsFarmtrackerDB.splitTradeGoods
        and data.itemSubType and data.itemSubType ~= "" then
            return data.itemSubType
        end
        local name = C_Item.GetItemClassInfo(data.classID)
        if name and name ~= "" then return name end
    end
    if data.isBoE or data.isBoP then
        return C_Item.GetItemClassInfo(Enum.ItemClass.Armor) or "Equipment"
    end
    return C_Item.GetItemClassInfo(Enum.ItemClass.Tradegoods) or "Tradeskill"
end

function ns.VendorTotal(data)
    local sp = data.sellPrice
    if not sp then
        -- itemLink hat die vollen Bonus-IDs (Skalierung, ilvl) → korrekter Vendorpreis
        -- itemID allein gibt nur den Basispreis ohne Skalierung zurück
        local src = data.itemLink or data.itemID
        if src then sp = select(11, C_Item.GetItemInfo(src)) end
    end
    return (sp and sp > 0) and (sp * data.amount) or nil
end

function ns.AHTotal(data)
    if NightsFarmtrackerDB.ahSource == "none" then return nil end
    local total = 0
    if data.q and data.qIDs then
        for i = 1, 3 do
            if (data.q[i] or 0) > 0 and data.qIDs[i] then
                local p = ns.GetAHPriceForID(data.qIDs[i])
                if p then total = total + p * data.q[i] end
            end
        end
    end
    if total == 0 and data.itemID then
        local p = ns.GetAHPriceForID(data.itemID)
        if p then total = p * data.amount end
    end
    return total > 0 and total or nil
end

-- vendor/ah are optional precomputed values (avoids recalculating
-- VendorTotal/AHTotal when the caller already has them, e.g. RefreshHUD).
-- True if an item must always be valued at vendor price, never AH
-- (junk, BoP, force-vendor filtered, or explicitly AH-ineligible).
function ns.IsVendorOnly(data)
    return data.isVendorTrash or (data.quality == 0) or data.isBoP
        or data.canAH == false or ns.IsForceVendor(data.itemID)
end

function ns.ItemValue(data, vendor, ah)
    if data.isVendorTrash or (data.quality == 0) then return vendor or ns.VendorTotal(data) end
    if data.itemID and ns.IsForceVendor(data.itemID) then return vendor or ns.VendorTotal(data) end
    if data.isBoP or data.canAH == false then return vendor or ns.VendorTotal(data) end
    local v = vendor or ns.VendorTotal(data)
    local a = ah     or ns.AHTotal(data)
    if a and v then return math.max(a, v) end
    return a or v
end

------------------------------------------------------------------------
-- DB init
------------------------------------------------------------------------
function ns.InitDB()
    if not NightsFarmtrackerDB then NightsFarmtrackerDB = {} end
    -- Register housing classID at runtime (may vary by patch)
    if ns.HOUSING and not ns.CLASS_PRIORITY[ns.HOUSING] then
        ns.CLASS_PRIORITY[ns.HOUSING] = 3  -- show after gems, before consumables
    end
    local db = NightsFarmtrackerDB
    if db.count         == nil then db.count         = {}                      end
    if db.paused        == nil then db.paused        = true                    end
    if db.visible       == nil then db.visible       = true                    end
    if db.expanded      == nil then db.expanded      = false                   end
    if db.totalTime     == nil then db.totalTime     = 0                       end
    if db.pos           == nil then db.pos           = {"TOP","TOP",0,-150} end
    if db.qAtlas        == nil then db.qAtlas        = {}                      end
    if db.trackedNames  == nil then db.trackedNames  = {}                      end
    if db.collapsed     == nil then db.collapsed     = {}                      end
    if db.excludedNames == nil then db.excludedNames = {}                      end
    if db.goldRateMode  == nil then db.goldRateMode  = "hour"                  end
    if db.minimapPos    == nil then db.minimapPos    = 225                     end
    if db.minimapHidden == nil then db.minimapHidden = false                   end
    -- LibDBIcon sub-table (migriert legacy keys beim ersten Load)
    if db.minimap == nil then
        db.minimap = { minimapPos = db.minimapPos, hide = db.minimapHidden }
    end
    if db.lootedGold    == nil then db.lootedGold    = 0                      end
    if db.sessionHistoryEnabled == nil then db.sessionHistoryEnabled = true  end
    if db.logWindowEnabled      == nil then db.logWindowEnabled      = false end
    if db.logWindowShown        == nil then db.logWindowShown        = false end
    if db.logEntries            == nil then db.logEntries            = {}    end
    if db.vendorFilterEnabled   == nil then db.vendorFilterEnabled   = true  end
    if db.mergeDaily            == nil then db.mergeDaily            = true  end
    if db.splitTradeGoods       == nil then db.splitTradeGoods       = false end
    if db.ahSource        == nil then db.ahSource        = "auto"     end
    if db.goldDisplayMode == nil then db.goldDisplayMode = "classic"  end
    if db.tsmPriceSource  == nil then db.tsmPriceSource  = "DBMarket" end
    if db.tsmCustomSource == nil then db.tsmCustomSource = ""         end
    if db.colorTheme      == nil then db.colorTheme      = "default"  end
    ns.ApplyColorTheme(db.colorTheme)
end

function ns.InitAccountDB()
    if not NightsFarmtrackerAccountDB then NightsFarmtrackerAccountDB = {} end
    if not NightsFarmtrackerAccountDB.sessions then
        NightsFarmtrackerAccountDB.sessions = {}
    end
    if not NightsFarmtrackerAccountDB.forceVendor then
        NightsFarmtrackerAccountDB.forceVendor = {}
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

------------------------------------------------------------------------
-- Icon badge helper — small slot between the item icon and item name
-- (used for crafting-reagent rank icons R1/R2/R3). Shared by every frame
-- that shows item icons, so the badge position/size stays identical.
-- Anchor item names to this badge's RIGHT (not the icon's), so the column
-- stays consistent whether or not a given row actually has a rank icon.
------------------------------------------------------------------------
local ICON_BADGE_W = 16  -- reserved width of the badge column

function ns.CreateIconBadge(parent, icon)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", icon, "RIGHT", 2, 0)
    fs:SetWidth(ICON_BADGE_W)
    fs:SetFontHeight(10)
    fs:SetJustifyH("CENTER")
    return fs
end

------------------------------------------------------------------------
-- Row appearance helper — icon border + name color by item quality.
-- Shared by all item rows (main HUD, history detail, filter list, log)
-- so the "look" lives in one place instead of being duplicated per file.
------------------------------------------------------------------------
function ns.ApplyQualityColor(nameText, iconBorder, quality, fallbackColor)
    if quality then
        local r, g, b = GetItemQualityColor(quality)
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
