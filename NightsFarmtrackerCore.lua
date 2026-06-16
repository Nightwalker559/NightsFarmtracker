------------------------------------------------------------------------
-- Night's Farmtracker - Core
------------------------------------------------------------------------
local ADDON_NAME, ns = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
ns.ADDON_NAME     = ADDON_NAME
ns.TRADE_GOODS    = Enum.ItemClass.Tradegoods
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
    [20] = 12,  -- Housing (fallback; actual classID confirmed at load)
}
-- Legacy aliases (used in History fallback)
ns.CAT_VENDOR = "Vendor Trash"
ns.CAT_BOE    = "Equipment"
ns.CAT_BOP    = "Equipment"
ns.CAT_MATS   = "Tradeskill"

-- UI layout
ns.FRAME_W     = 310
ns.PAD         = 10
ns.ROW_H       = 34
ns.CAT_ROW_H   = 22
ns.CAT_INDENT  = 8
ns.FOOTER_H    = 32
ns.ICON_SIZE   = 22
ns.CONTENT_W   = ns.FRAME_W - ns.PAD * 2
ns.MAX_ROWS    = 8
ns.SCROLL_STEP = ns.ROW_H

-- Colors
ns.COL_BG     = {0.06, 0.09, 0.10, 0.92}
ns.COL_BORDER = {0.20, 0.38, 0.42, 0.85}
ns.COL_CAT_BG = {0.10, 0.16, 0.18, 0.80}
ns.COL_ACCENT = {0.30, 0.75, 0.85}
ns.COL_GOLD   = {1.00, 0.82, 0.00}

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

function ns.FormatGold(copper)
    if not copper or copper <= 0 then return "" end
    if copper >= 10000 then
        -- Gold + Silber (auf nächste Silbermünze runden)
        return GetCoinTextureString(math.floor(copper / 100) * 100)
    end
    -- Unter 1g: Silber + Kupfer
    return GetCoinTextureString(copper)
end

local Q_FALLBACK = {"Q1:","Q2:","Q3:"}

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

function ns.ItemValue(data)
    if data.isBoP or data.canAH == false then return ns.VendorTotal(data) end
    local v = ns.VendorTotal(data)
    local a = ns.AHTotal(data)
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
    if db.pos           == nil then db.pos           = {"CENTER","CENTER",0,0} end
    if db.qAtlas        == nil then db.qAtlas        = {}                      end
    if db.trackedNames  == nil then db.trackedNames  = {}                      end
    if db.collapsed     == nil then db.collapsed     = {}                      end
    if db.excludedNames == nil then db.excludedNames = {}                      end
    if db.goldRateMode  == nil then db.goldRateMode  = "hour"                  end
    if db.minimapPos    == nil then db.minimapPos    = 225                     end
    if db.minimapHidden == nil then db.minimapHidden = false                   end
    if db.lootedGold    == nil then db.lootedGold    = 0                      end
    if db.sessionHistoryEnabled == nil then db.sessionHistoryEnabled = true  end
    if db.mergeDaily            == nil then db.mergeDaily            = true  end
    if db.splitTradeGoods       == nil then db.splitTradeGoods       = false end
    if db.ahSource        == nil then db.ahSource        = "auto"     end
    if db.tsmPriceSource  == nil then db.tsmPriceSource  = "DBMarket" end
    if db.tsmCustomSource == nil then db.tsmCustomSource = ""         end
end

function ns.InitAccountDB()
    if not NightsFarmtrackerAccountDB then NightsFarmtrackerAccountDB = {} end
    if not NightsFarmtrackerAccountDB.sessions then
        NightsFarmtrackerAccountDB.sessions = {}
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
    -- Draw 1px square border as four colored textures
    local r, g, b, a = unpack(ns.COL_BORDER)
    local function Edge(p1, p2, horiz)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        if horiz then t:SetHeight(1) else t:SetWidth(1) end
        t:SetPoint(p1); t:SetPoint(p2)
    end
    Edge("TOPLEFT",    "TOPRIGHT",    true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT",    "BOTTOMLEFT",  false)
    Edge("TOPRIGHT",   "BOTTOMRIGHT", false)
end
