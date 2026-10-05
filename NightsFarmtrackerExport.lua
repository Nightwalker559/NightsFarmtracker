------------------------------------------------------------------------
-- Night's Farmtracker - Data Export
-- Builds a JSON export of the saved session history (every calendar
-- month or one chosen month, aggregated and categorized exactly like
-- Session History itself) and shows it in a copyable text window after a
-- month picker. Opened via Settings -> Data Export or "/nft export".
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
-- Any other control character must be \u-escaped, or the JSON is invalid.
local function JSONEscape(c)
    return JSON_ESCAPES[c] or string.format("\\u%04x", c:byte())
end
local function JSONString(s)
    return "\"" .. tostring(s):gsub('[%c"\\]', JSONEscape) .. "\""
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
-- then runs each month through BuildCategoriesList. `onlyMonth` ("YYYY-MM")
-- limits the export to that one month; nil exports every month.
function ns.BuildFullExportJSON(onlyMonth)
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    local months, monthOrder = {}, {}
    if sessions then
        ns.ForEachSession(sessions, function(session)
            local mKey = date("%Y-%m", session.timestamp)
            if onlyMonth and mKey ~= onlyMonth then return end
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
-- Export windows. Step 1: a month picker ("All months" + every month with
-- saved sessions, newest first). Step 2: the copy-text window (shared
-- helper, see ns.CreateCopyTextWindow/ns.ShowCopyText in
-- NightsFarmtrackerCore.lua) with the JSON for the chosen selection.
------------------------------------------------------------------------
local PICK_W, PICK_ROW_H, PICK_MAX_ROWS = 260, 22, 10

local ExportFrame, PickFrame
local pickRows = {}

-- "YYYY-MM" keys of every month that has at least one saved session,
-- newest first.
local function GetExportMonths()
    local keys, seen = {}, {}
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    if sessions then
        ns.ForEachSession(sessions, function(session)
            local k = date("%Y-%m", session.timestamp)
            if not seen[k] then seen[k] = true; keys[#keys + 1] = k end
        end)
    end
    table.sort(keys, function(a, b) return a > b end)
    return keys
end

local function MonthLabel(key)
    local y, m = key:match("^(%d+)-(%d+)$")
    return (ns.L.MONTH_NAMES[tonumber(m)] or m) .. " " .. y
end

local ShowPicker

-- monthKey nil = all months.
local function ShowExport(monthKey)
    if not ExportFrame then
        ExportFrame = ns.CreateCopyTextWindow("NightsFarmtrackerExportWnd", ns.L["export_title"])
        ns.ExportFrame = ExportFrame

        local back = CreateFrame("Button", nil, ExportFrame)
        back:SetSize(90, 16)
        back:SetPoint("TOPRIGHT", -ns.PAD - 100, -(ns.WINDOW_HDR_H + 6))
        local backText = back:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        backText:SetAllPoints(); backText:SetJustifyH("RIGHT")
        backText:SetTextColor(unpack(ns.COL_ACCENT))
        backText:SetText(ns.L["export_back"])
        back:SetScript("OnEnter", function() backText:SetTextColor(1, 1, 1) end)
        back:SetScript("OnLeave", function() backText:SetTextColor(unpack(ns.COL_ACCENT)) end)
        back:SetScript("OnClick", function() ExportFrame:Hide(); ShowPicker() end)
    end
    ExportFrame.titleFS:SetText(ns.L["export_title_fmt"]:format(monthKey and MonthLabel(monthKey) or ns.L["export_all"]))
    ns.ShowCopyText(ExportFrame, ns.BuildFullExportJSON(monthKey))
end

local function CreatePickRow(content)
    local row = CreateFrame("Button", nil, content)
    row:SetSize(PICK_W - ns.PAD * 2 - 4, PICK_ROW_H)

    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(unpack(ns.COL_CAT_BG)); hl:Hide()
    row.hl = hl

    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(0.12, 0.22, 0.25, 0.5)
    sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT")

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetFontHeight(ns.FONT_NORMAL)

    row:SetScript("OnEnter", function(self) self.hl:Show() end)
    row:SetScript("OnLeave", function(self) self.hl:Hide() end)
    row:SetScript("OnClick", function(self)
        PickFrame:Hide()
        ShowExport(self.monthKey)
    end)
    return row
end

local function EnsurePickFrame()
    if PickFrame then return end
    PickFrame = ns.CreateWindowFrame("NightsFarmtrackerExportPickWnd", ns.L["export_pick_title"],
        {width = PICK_W, pad = ns.PAD, titleColor = ns.COL_ACCENT})
    ns.ExportPickFrame = PickFrame
    PickFrame:SetScript("OnHide", function() ns.RefreshWindowChain("left") end)

    local sep = PickFrame:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(unpack(ns.COL_BORDER))
    sep:SetPoint("TOPLEFT", ns.PAD, -(ns.WINDOW_HDR_H - 1)); sep:SetPoint("TOPRIGHT", -ns.PAD, -(ns.WINDOW_HDR_H - 1))

    local scroll = CreateFrame("ScrollFrame", nil, PickFrame)
    scroll:SetPoint("TOPLEFT", ns.PAD, -(ns.WINDOW_HDR_H + 4))
    scroll:SetPoint("BOTTOMRIGHT", -ns.PAD, 10)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(PICK_W - ns.PAD * 2 - 4)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnMouseWheel", ns.MakeWheelHandler(scroll, content, PICK_ROW_H))
    PickFrame.scroll, PickFrame.content = scroll, content
end

ShowPicker = function()
    EnsurePickFrame()
    local entries = { { key = nil, label = ns.L["export_all"] } }
    for _, k in ipairs(GetExportMonths()) do
        entries[#entries + 1] = { key = k, label = MonthLabel(k) }
    end

    for i, e in ipairs(entries) do
        local row = pickRows[i]
        if not row then
            row = CreatePickRow(PickFrame.content)
            pickRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * PICK_ROW_H)
        row.monthKey = e.key
        row.text:SetText(e.label)
        row.text:SetTextColor(unpack(e.key and {1, 1, 1} or ns.COL_ACCENT))
        row:Show()
    end
    for i = #entries + 1, #pickRows do pickRows[i]:Hide() end

    PickFrame.content:SetHeight(#entries * PICK_ROW_H)
    PickFrame:SetHeight(ns.WINDOW_HDR_H + 14 + math.min(#entries, PICK_MAX_ROWS) * PICK_ROW_H)
    PickFrame.scroll:SetVerticalScroll(0)

    PickFrame:ClearAllPoints()
    PickFrame:SetPoint("CENTER")
    PickFrame:Show()
    ns.RefreshWindowChain("left")
end

function ns.ToggleExportWindow()
    if ns.DeferInCombat(ns.ToggleExportWindow) then return end
    if (ExportFrame and ExportFrame:IsShown()) or (PickFrame and PickFrame:IsShown()) then
        if ExportFrame then ExportFrame:Hide() end
        if PickFrame then PickFrame:Hide() end
    else
        ShowPicker()
    end
end
