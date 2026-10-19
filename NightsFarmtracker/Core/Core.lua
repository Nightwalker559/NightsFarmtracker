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

-- Weapon (2) and Armor (4) are the item classes that count as Equipment.
function ns.IsGearClass(classID)
    return classID == 2 or classID == 4
end

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
ns.FRAME_W     = 330
ns.PAD         = 10
ns.ROW_H       = 34
ns.CAT_ROW_H   = 22
ns.CHECKBOX_ROW_H = 16  -- row height for checkbox-list sections (category filters, AH-by-expansion)
ns.CAT_INDENT  = 8
ns.FOOTER_H    = 32
ns.ICON_SIZE   = 30
ns.RANK_ICON_W = 20   -- width of the R1/R2/R3 atlas markup (CreateAtlasMarkup)
ns.RANK_ICON_H = 20   -- height of the R1/R2/R3 atlas markup
ns.CONTENT_W   = ns.FRAME_W - ns.PAD * 2
ns.SCROLL_STEP = ns.ROW_H
-- Maximum total window height (header + list + footer) of the main window and
-- every list window; longer content scrolls. User setting db.maxWindowHeight
-- (Settings -> Display), read through ns.GetMaxWindowH(). The Help window is
-- a bit taller (see ns.GetMaxHelpH).
ns.DEFAULT_MAX_WINDOW_H = 360
ns.MIN_MAX_WINDOW_H     = 200
ns.MAX_MAX_WINDOW_H     = 1000
ns.HELP_EXTRA_H         = 40

function ns.GetMaxWindowH()
    local v = tonumber(NightsFarmtrackerDB and NightsFarmtrackerDB.maxWindowHeight)
    if not v or v <= 0 then return ns.DEFAULT_MAX_WINDOW_H end
    return math.max(ns.MIN_MAX_WINDOW_H, math.min(ns.MAX_MAX_WINDOW_H, v))
end

function ns.GetMaxHelpH()
    return ns.GetMaxWindowH() + ns.HELP_EXTRA_H
end

-- Re-lays out every window that is currently open after the setting
-- changed. (The Detail window picks the new height up the next time it opens.)
function ns.ApplyWindowHeightSetting()
    if ns.RefreshHUD then ns.RefreshHUD() end
    if ns.HistFrame and ns.HistFrame:IsShown() and ns.RebuildHistory then ns.RebuildHistory() end
    if ns.FilterFrame and ns.FilterFrame:IsShown() and ns.RebuildFilterList then ns.RebuildFilterList() end
    if ns.BlacklistFrame and ns.BlacklistFrame:IsShown() and ns.RebuildBlacklistList then ns.RebuildBlacklistList() end
    if ns.LogFrame and ns.LogFrame:IsShown() and ns.RebuildLogList then ns.RebuildLogList() end
    if ns.RefitHelpWindow then ns.RefitHelpWindow() end
    if ns.SettingsFrame and ns.SettingsFrame:IsShown() and ns.RebuildSettingsContent then ns.RebuildSettingsContent() end
end

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
    "custom",
}
ns.COL_GOLD = {1.00, 0.82, 0.00}

-- Custom theme: the user picks one accent color, the other three are derived
-- from it. The built-in themes all follow the same recipe (one hue, fixed
-- saturation/brightness ramp), so the derived set looks like the presets.
local function RGBtoHSV(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then     h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else                h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx == 0) and 0 or d / mx, mx
end

local function HSVtoRGB(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

-- Accent brightness floor: it is used as text color on dark panels.
local CUSTOM_MIN_VALUE = 0.55

function ns.DeriveCustomTheme(r, g, b)
    local h, s, v = RGBtoHSV(r, g, b)
    if v < CUSTOM_MIN_VALUE then v = CUSTOM_MIN_VALUE end
    -- Saturation follows the accent's (pale accent -> pale panels), scaled
    -- per element to match the presets.
    local function shade(satFactor, val, alpha)
        local rr, gg, bb = HSVtoRGB(h, math.min(1, s * satFactor), val)
        return {rr, gg, bb, alpha}
    end
    local ar, ag, ab = HSVtoRGB(h, s, v)
    return {
        bg     = shade(0.70, 0.10, 0.92),
        border = shade(0.85, 0.42, 0.85),
        catBg  = shade(0.78, 0.17, 0.80),
        accent = {ar, ag, ab},
    }
end

do
    local t = ns.DeriveCustomTheme(0.30, 0.75, 0.85)
    t.name, t.labelKey, t.descKey = "Custom", "theme_custom", "theme_custom_desc"
    ns.COLOR_THEMES.custom = t
end

-- Header gradient colors (optional, see ns.PaintCatBg): left edge tinted
-- towards the accent, fading out to the right.
function ns.CatGradient(theme)
    local cb, ac = theme.catBg, theme.accent
    return {cb[1] + (ac[1] - cb[1]) * 0.22, cb[2] + (ac[2] - cb[2]) * 0.22,
            cb[3] + (ac[3] - cb[3]) * 0.22, 0.90},
           {cb[1], cb[2], cb[3], 0.25}
end

-- Applies a theme's colors to ns.COL_BG/BORDER/CAT_BG/ACCENT. Elements
-- already drawn with the old colors are not retroactively recolored -
-- a UI reload is required for a theme change to fully apply everywhere.
function ns.ApplyColorTheme(themeKey)
    local theme = ns.COLOR_THEMES[themeKey] or ns.COLOR_THEMES.default
    local acc = NightsFarmtrackerDB and NightsFarmtrackerDB.customAccent
    if themeKey == "custom" and type(acc) == "table" and acc[1] and acc[2] and acc[3] then
        theme = ns.DeriveCustomTheme(acc[1], acc[2], acc[3])
    end
    ns.COL_BG     = theme.bg
    ns.COL_BORDER = theme.border
    ns.COL_CAT_BG = theme.catBg
    ns.COL_ACCENT = theme.accent
    ns.COL_CAT_GRAD_L, ns.COL_CAT_GRAD_R = ns.CatGradient(theme)
end

-- Paints a header/category background texture: flat COL_CAT_BG, or a
-- left-to-right gradient when the "Header gradient" option is on.
function ns.PaintCatBg(tex)
    local db = NightsFarmtrackerDB
    if db and db.headerGradient then
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL",
            CreateColor(unpack(ns.COL_CAT_GRAD_L)), CreateColor(unpack(ns.COL_CAT_GRAD_R)))
    else
        tex:SetColorTexture(unpack(ns.COL_CAT_BG))
    end
end

-- Shared backdrop used throughout Settings/Blacklist/Filter for small
-- boxed widgets (checkboxes, radio dots, dropdowns, edit boxes, buttons).
-- Its 1px square border matches the window frames (see ApplyFrameStyle).
-- bgColor defaults to {0.06,0.09,0.10,1} (the checkbox/radio shade); pass
-- {0.05,0.08,0.09,1} for the slightly darker dropdown/edit-box shade.
function ns.StyleBackdropBox(frame, bgColor)
    frame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Buttons/WHITE8x8",
        tile=true,tileSize=8,edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
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
-- Live trace goes to the debug log window (Modules/Debug.lua), not chat.
function ns.Log(...) if ns.debugMode then ns.DebugLogAdd(...) end end

-- Midnight (12.x) can hand addons "secret values" that throw on any string
-- operation; this is a no-op on clients without the API.
ns.IsSecret = issecretvalue or function() return false end

-- Turns a WoW format string ("%d Gold", "%s has been reset.") into a Lua
-- pattern that captures its %d / %s placeholders.
function ns.FormatToPattern(fmt)
    if not fmt then return nil end
    local pattern = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
    pattern = pattern:gsub("%%%%d", "(%%d+)"):gsub("%%%%s", "(.+)")
    return pattern
end

-- Chat output with the addon's colored prefix.
ns.CHAT_PREFIX = "|cff30b0c0Night's Farmtracker:|r "
function ns.Print(text) print(ns.CHAT_PREFIX .. text) end

------------------------------------------------------------------------
-- Item tooltips for looted items shown in our own history/log frames.
-- Blizzard auto-attaches a "currently equipped" comparison tooltip
-- (ShoppingTooltip1/2) to any equippable item tooltip. That's confusing
-- here since it's a *past* loot entry, not something being considered
-- for equip - so we hide the comparison tooltips right after showing
-- ours. Only affects our own rows; normal in-game item tooltips
-- elsewhere are untouched.
------------------------------------------------------------------------
-- Auctionator adds its Vendor/Auction lines through hooks that fire reliably
-- for SetItemByID (as in the Vendor-Only Filter) but not for SetHyperlink.
-- So plain items are shown by ID - the link adds nothing for them (crafting
-- quality tiers are separate item IDs). Only items whose tooltip depends on
-- the link's own data keep SetHyperlink: gear (item level/stats of this
-- drop), battle pets and Mythic keystones.
local KEYSTONE_ITEM_ID = 180653
local function TooltipNeedsLink(id, classID)
    return ns.IsGearClass(classID) or classID == 17 or id == KEYSTONE_ITEM_ID
end

-- Safety net for the SetHyperlink path: if Auctionator is loaded but its
-- lines did not get added, add them ourselves (never twice).
local function EnsureAuctionatorLines(link)
    local A = Auctionator
    if not (A and A.Tooltip and A.Tooltip.ShowTipWithPricing and A.Locales and A.Locales.Apply) then return end
    local ok, label = pcall(A.Locales.Apply, "AUCTION")
    if not ok or not label then return end
    for i = 2, GameTooltip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text:find(label, 1, true) == 1 then return end
    end
    A.Tooltip.ShowTipWithPricing(GameTooltip, link, 1)
end

function ns.ShowItemTooltipNoCompare(owner, anchor, hyperlink, itemID)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local linkID, classID
    if hyperlink then
        local id, _, _, _, _, cls = C_Item.GetItemInfoInstant(hyperlink)
        linkID, classID = id, cls
    end
    if hyperlink and (not linkID or TooltipNeedsLink(linkID, classID)) then
        GameTooltip:SetHyperlink(hyperlink)
        EnsureAuctionatorLines(hyperlink)
    else
        GameTooltip:SetItemByID(linkID or itemID)
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
        local str = C_CurrencyInfo.GetCoinTextureString(math.floor(copper / 100) * 100)
        local goldDigits, rest = str:match("^(%d+)(.*)$")
        if goldDigits then
            str = AddThousandsSep(goldDigits) .. rest
        end
        return str
    end
    -- Under 1g: silver + copper
    return C_CurrencyInfo.GetCoinTextureString(copper)
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
