------------------------------------------------------------------------
-- Night's Farmtracker - Debug
-- All the diagnostic "/nft ..." dump commands (test, itemdb, monthdump,
-- sessionsdump) live here, building their output into a Buffer instead
-- of spamming individual print() lines, then showing it all at once in
-- a copyable window (see ns.CreateCopyTextWindow/ns.ShowCopyText in
-- Core/Core.lua) - easier to read and to paste into a bug
-- report than a wall of chat messages.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Buffer helper - :Add(fmt, ...) works like print()/string.format (a
-- plain string is added as-is, extra args run it through string.format),
-- :Text() joins everything with newlines for the copy window.
------------------------------------------------------------------------
local Buffer = {}
Buffer.__index = Buffer

local function NewBuffer()
    return setmetatable({lines = {}}, Buffer)
end

function Buffer:Add(fmt, ...)
    if select("#", ...) > 0 then
        self.lines[#self.lines + 1] = string.format(fmt, ...)
    else
        self.lines[#self.lines + 1] = tostring(fmt)
    end
end

function Buffer:Text()
    return table.concat(self.lines, "\n")
end

------------------------------------------------------------------------
-- Debug window - built from the shared copy-text-window helper.
------------------------------------------------------------------------
local DebugFrame

local function ShowDebug(buf)
    if not DebugFrame then
        DebugFrame = ns.CreateCopyTextWindow("NightsFarmtrackerDebugWnd", ns.L["debug_title"])
        ns.DebugFrame = DebugFrame
    end
    ns.ShowCopyText(DebugFrame, buf:Text())
end

------------------------------------------------------------------------
-- /nft test - live session's tracked item count table
------------------------------------------------------------------------
function ns.DebugTest()
    local buf = NewBuffer()
    local db = NightsFarmtrackerDB
    local n = 0; for _ in pairs(db.count) do n = n + 1 end
    buf:Add("NFT: paused=%s items=%d", tostring(db.paused), n)
    for itemID, data in pairs(db.count) do
        buf:Add("  %s (%s) x%s classID=%s sell=%s",
            tostring(data.name), tostring(itemID), tostring(data.amount),
            tostring(data.classID), tostring(data.sellPrice))
    end
    ShowDebug(buf)
end

------------------------------------------------------------------------
-- /nft itemdb - companion item-audit addon's SavedVariables status
------------------------------------------------------------------------
function ns.DebugItemDB()
    local buf = NewBuffer()
    if NightsFarmtrackerItemDB == nil then
        buf:Add("NightsFarmtrackerItemDB is nil - SavedVariables not registered (check .toc) or ns.InitItemDB never ran.")
    else
        local n = 0; for _ in pairs(NightsFarmtrackerItemDB) do n = n + 1 end
        buf:Add("NightsFarmtrackerItemDB exists, entries=%d", n)
    end
    ShowDebug(buf)
end

------------------------------------------------------------------------
-- /nft monthdump [itemID] - rebuilds the CURRENT calendar month's
-- aggregate (same merge Shift-Click on a month row uses) and lists every
-- category row with its sort-relevant gold value, plus the raw variant
-- buckets for a specific item if an ID follows the command.
------------------------------------------------------------------------
function ns.DebugMonthDump(targetID)
    local buf = NewBuffer()
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    if not sessions then buf:Add("no sessions"); ShowDebug(buf); return end

    local monthKey = date("%Y-%m")
    local agg = { items = {} }
    local n = 0
    ns.ForEachSession(sessions, function(session)
        if date("%Y-%m", session.timestamp) == monthKey then
            ns.MergeSessionInto(agg, session, false)
            n = n + 1
        end
    end)
    buf:Add("monthdump: merged %d sessions for %s", n, monthKey)

    local cats, catOrder = ns.BuildSessionCategories(agg)
    for _, catName in ipairs(catOrder) do
        buf:Add("Category %s total=%s", catName, tostring(cats[catName].gold))
        for i, entry in ipairs(cats[catName].items) do
            local rowAmount = entry.gv and entry.gv.amount or (entry.d and entry.d.amount)
            buf:Add("  #%d gold=%s amount=%s isGearVariant=%s isRank=%s id=%s name=%s",
                i, tostring(entry.gold), tostring(rowAmount), tostring(entry.isGearVariant),
                tostring(entry.isRank), tostring(entry.d and entry.d.itemID), tostring(entry.name))
        end
    end

    if targetID then
        local d = agg.items[targetID]
        if not d then
            buf:Add("itemID %s not in this month's aggregate", tostring(targetID))
        else
            buf:Add("item %s amount=%s ahTotal=%s vendorTotal=%s isBoP=%s canAH=%s",
                tostring(targetID), tostring(d.amount), tostring(d.ahTotal), tostring(d.vendorTotal),
                tostring(d.isBoP), tostring(d.canAH))
            if d.variants then
                for key, gv in pairs(d.variants) do
                    buf:Add("  variant key=%s amount=%s quality=%s ilvl=%s sellPrice=%s ahTotal=%s itemLink=%s",
                        tostring(key), tostring(gv.amount), tostring(gv.quality), tostring(gv.itemLevel),
                        tostring(gv.sellPrice), tostring(gv.ahTotal), tostring(gv.itemLink))
                end
            else
                buf:Add("  (no variants table)")
            end
        end
    end

    ShowDebug(buf)
end

------------------------------------------------------------------------
-- /nft sessionsdump - raw storage structure: every day-key, every
-- session in it, its timestamp/isMonthCompact flag. Finds a stray
-- already-compacted "same month" entry sitting alongside the live one.
------------------------------------------------------------------------
function ns.DebugSessionsDump()
    local buf = NewBuffer()
    local sessions = NightsFarmtrackerAccountDB and NightsFarmtrackerAccountDB.sessions
    if not sessions then buf:Add("no sessions"); ShowDebug(buf); return end

    local dayKeys = {}
    for k in pairs(sessions) do dayKeys[#dayKeys + 1] = k end
    table.sort(dayKeys)
    for _, dayKey in ipairs(dayKeys) do
        for i, session in ipairs(sessions[dayKey]) do
            local n = 0
            for _ in pairs(session.items or {}) do n = n + 1 end
            buf:Add("dayKey=%s [%d] ts=%s (%s) isMonthCompact=%s items=%d totalGold=%s",
                dayKey, i, tostring(session.timestamp), date("%Y-%m-%d %H:%M:%S", session.timestamp),
                tostring(session.isMonthCompact), n, tostring(session.totalGold))
        end
    end
    ShowDebug(buf)
end
