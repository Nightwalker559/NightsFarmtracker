------------------------------------------------------------------------
-- Night's Farmtracker - Data Export
-- Builds a JSON export of the ENTIRE saved session history (every
-- calendar month, aggregated and categorized exactly like Session
-- History itself) and shows it in a copyable text window. Opened via
-- Settings -> Data Export or "/nft export".
--
-- Feeds Nightwalker559's WoW Goldtracker web tool ("Beute" tab import) -
-- already-computed month/category/item gold values, no client-side
-- re-implementation of the addon's pricing/categorization logic needed.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Minimal JSON encoder - export data is always a plain tree of
-- strings/numbers/booleans/arrays/objects, so a full JSON library isn't
-- needed. Arrays are tables built with consecutive integer keys only
-- (never mixed with string keys) so the array-vs-object check below is
-- unambiguous.
------------------------------------------------------------------------
local JSON_ESCAPES = {
    ["\""] = "\\\"", ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}
local function JSONString(s)
    return "\"" .. tostring(s):gsub('[%c"\\]', JSON_ESCAPES) .. "\""
end

local function JSONValue(v)
    local t = type(v)
    if t == "string" then return JSONString(v) end
    if t == "number" then
        -- string.format("%d", v) overflows WoW's Lua 5.1 32-bit integer
        -- formatting for large sums (totalGold across many sessions can
        -- easily exceed 2^31). "%.0f" formats via the double itself, so it
        -- has no such limit.
        return (v == math.floor(v)) and string.format("%.0f", v) or tostring(v)
    end
    if t == "boolean" then return v and "true" or "false" end
    if t == "table" then
        if v[1] ~= nil or next(v) == nil then
            local parts = {}
            for i, item in ipairs(v) do parts[i] = JSONValue(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, val in pairs(v) do
            parts[#parts + 1] = JSONString(k) .. ":" .. JSONValue(val)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

------------------------------------------------------------------------
-- Build export data
------------------------------------------------------------------------
-- Same per-item/category gold values Session History shows (see
-- BuildSessionCategories in NightsFarmtrackerHistory.lua) - only rows
-- with a non-zero gold value are ever added there, so no extra filtering
-- needed here.
local function BuildCategoriesList(agg)
    local cats, catOrder = ns.BuildSessionCategories(agg)
    local list = {}
    for _, catName in ipairs(catOrder) do
        local cat = cats[catName]
        if cat and #cat.items > 0 then
            local items = {}
            for _, entry in ipairs(cat.items) do
                local item = {
                    itemID  = (entry.d and entry.d.itemID) or 0,
                    name    = entry.name or "",
                    amount  = (entry.gv and entry.gv.amount) or (entry.d and entry.d.amount) or 0,
                    gold    = entry.gold or 0,
                    -- Item quality/rarity (0=Poor/grey ... 5=Legendary/orange,
                    -- Blizzard's ITEM_QUALITY_COLORS index) so the HTML tool
                    -- can color the name the same as in-game. Gear variants
                    -- (scaling/Adventurer's items) can have a quality that
                    -- differs from the base item's, so prefer gv.quality.
                    quality = (entry.gv and entry.gv.quality) or (entry.d and entry.d.quality) or 1,
                }
                -- Reagent quality tier (R1/R2/R3 - ore, herbs, cloth, leather
                -- and other tiered trade goods split into per-tier rows by
                -- BuildSessionCategories, see entry.isRank there). Distinct
                -- from item "quality" above - this is the tier badge shown
                -- next to the item, not its rarity color.
                if entry.isRank and entry.tier then
                    item.rank = entry.tier
                end
                items[#items + 1] = item
            end
            list[#list + 1] = { name = catName, gold = cat.gold or 0, items = items }
        end
    end
    return list
end

-- Aggregates every saved session into one virtual, non-persisted session
-- per calendar month (same merge BuildMonthAggregate/the "/nft monthdump"
-- diagnostic use - see NightsFarmtrackerHistory.lua / NightsFarmtracker_Main.lua),
-- then runs each month through BuildCategoriesList.
function ns.BuildFullExportJSON()
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    local months, monthOrder = {}, {}
    if sessions then
        ns.ForEachSession(sessions, function(session)
            local mKey = date("%Y-%m", session.timestamp)
            if not months[mKey] then
                months[mKey] = { items = {} }
                monthOrder[#monthOrder + 1] = mKey
            end
            ns.MergeSessionInto(months[mKey], session, false)
        end)
    end
    table.sort(monthOrder)

    local monthList = {}
    for _, mKey in ipairs(monthOrder) do
        local agg = months[mKey]
        monthList[#monthList + 1] = {
            month      = mKey,
            totalGold  = agg.totalGold or 0,
            lootedGold = agg.lootedGold or 0,
            categories = BuildCategoriesList(agg),
        }
    end

    return JSONValue({
        addon       = "NightsFarmtracker",
        generatedAt = time(),
        months      = monthList,
    })
end

------------------------------------------------------------------------
-- Export window - built from the shared copy-text-window helper (see
-- ns.CreateCopyTextWindow/ns.ShowCopyText in NightsFarmtrackerCore.lua).
------------------------------------------------------------------------
local ExportFrame

local function EnsureExportFrame()
    if ExportFrame then return end
    ExportFrame = ns.CreateCopyTextWindow("NightsFarmtrackerExportWnd", ns.L["export_title"])
    ns.ExportFrame = ExportFrame
end

function ns.ToggleExportWindow()
    if ns.DeferInCombat(ns.ToggleExportWindow) then return end
    EnsureExportFrame()
    if ExportFrame:IsShown() then
        ExportFrame:Hide()
    else
        ns.ShowCopyText(ExportFrame, ns.BuildFullExportJSON())
    end
end
