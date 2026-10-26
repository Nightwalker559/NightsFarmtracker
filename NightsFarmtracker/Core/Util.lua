------------------------------------------------------------------------
-- Night's Farmtracker - Util
-- Debug log hook, chat output, item tooltips and bag drag-and-drop helpers,
-- and the time / gold / item-name formatting used by every window.
------------------------------------------------------------------------
local _, ns = ...

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

-- Item name field of a list row: long names wrap onto a second line (the row
-- is tall enough for two) instead of being cut off at NAME_MAX.
function ns.SetupRowNameText(fs)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(true); fs:SetMaxLines(2)
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
