------------------------------------------------------------------------
-- Night's Farmtracker - Debug
-- The debug log and its live window, plus all diagnostic "/nft ..." dump
-- commands (test, itemdb, monthdump, sessionsdump, venomdump). Everything
-- goes into the log window (see ns.CreateCopyTextWindow/ns.ShowCopyText
-- in Core/Core.lua) instead of chat - easier to read and to paste into a
-- bug report than a wall of chat messages.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- Debug log - one in-memory ring buffer for everything diagnostic: the
-- live ns.Log() trace (while /nft debug is on) and the output of the dump
-- commands. Nothing goes to chat; the window below shows the log live.
------------------------------------------------------------------------
local LOG_MAX      = 2000   -- lines kept, oldest drop off
local REFRESH_STEP = 0.2    -- seconds between window refreshes while lines arrive

local logLines = {}
local logFirst, logLast = 1, 0
local DebugFrame
local dirty, stickPending = false, false

local function Stamp()
    return string.format("%s.%03d", date("%H:%M:%S"), (GetTime() % 1) * 1000)
end

-- Appends one line (any number of values, joined by spaces).
function ns.DebugLogAdd(...)
    local n = select("#", ...)
    local line
    if n == 1 then
        line = tostring((...))
    else
        local parts = {}
        for i = 1, n do parts[i] = tostring((select(i, ...))) end
        line = table.concat(parts, " ")
    end
    logLast = logLast + 1
    logLines[logLast] = Stamp() .. "  " .. line
    if logLast - logFirst + 1 > LOG_MAX then
        logLines[logFirst] = nil
        logFirst = logFirst + 1
    end
    dirty = true
end

local function LogText()
    return table.concat(logLines, "\n", logFirst, logLast)
end

local function ClearLog()
    logLines = {}
    logFirst, logLast = 1, 0
    dirty = true
end

-- Window refresh: only while shown and while the EditBox has no focus, so
-- selecting text for Ctrl+C is never wiped by an incoming line. Follows the
-- newest line when the view was already scrolled to the end.
local function RefreshWindow(frame)
    local sf = frame.scrollFrame
    local wasAtEnd = sf:GetVerticalScroll() >= sf:GetVerticalScrollRange() - 2
    frame.box:SetText(LogText())
    sf:UpdateScrollChildRect()
    dirty = false
    stickPending = wasAtEnd
end

local function CreateDebugWindow()
    local frame = ns.CreateCopyTextWindow("NightsFarmtrackerDebugWnd", ns.L["debug_title"])

    local clearBtn = CreateFrame("Button", nil, frame)
    clearBtn:SetSize(60, 16)
    clearBtn:SetPoint("TOPRIGHT", -ns.PAD - 100, -(ns.WINDOW_HDR_H + 6))
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearText:SetAllPoints(); clearText:SetJustifyH("RIGHT")
    clearText:SetTextColor(unpack(ns.COL_ACCENT))
    clearText:SetText(ns.L["debug_clear"])
    clearBtn:SetScript("OnEnter", function() clearText:SetTextColor(1, 1, 1) end)
    clearBtn:SetScript("OnLeave", function() clearText:SetTextColor(unpack(ns.COL_ACCENT)) end)
    clearBtn:SetScript("OnClick", function()
        ClearLog()
        frame.box:ClearFocus()
    end)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        if stickPending then
            stickPending = false
            self.scrollFrame:UpdateScrollChildRect()
            self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange())
        end
        if not dirty or self.box:HasFocus() then return end
        elapsed = elapsed + dt
        if elapsed < REFRESH_STEP then return end
        elapsed = 0
        RefreshWindow(self)
    end)
    return frame
end

-- Opens (or refreshes) the live debug window.
function ns.ShowDebugLog()
    if not DebugFrame then
        DebugFrame = CreateDebugWindow()
        ns.DebugFrame = DebugFrame
    end
    ns.ShowCopyText(DebugFrame, LogText(), true)
    dirty = false
    stickPending = true
end

------------------------------------------------------------------------
-- Dump commands collect lines in a Buffer, then log them as one block and
-- open the window. :Add(fmt, ...) works like print()/string.format (a
-- plain string is added as-is, extra args run it through string.format).
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

local function ShowDebug(buf)
    for _, line in ipairs(buf.lines) do ns.DebugLogAdd(line) end
    ns.ShowDebugLog()
end

-- /nft debug - ON opens the live window, OFF closes it (the log keeps the
-- "OFF" line and everything before it for the next time it is opened).
function ns.ToggleDebugMode()
    ns.debugMode = not ns.debugMode
    ns.DebugLogAdd("-- debug trace " .. (ns.debugMode and "ON" or "OFF") .. " --")
    if ns.debugMode then
        ns.ShowDebugLog()
    elseif DebugFrame then
        DebugFrame:Hide()
    end
end

-- /nft venomdump - tooltip lines of the equipped venom item (nil = none).
function ns.DebugVenomTooltip(lines)
    local buf = NewBuffer()
    if not lines then
        buf:Add("venomdump: Coiled Huntress not equipped / no tooltip data.")
    else
        buf:Add("venom tooltip dump:")
        for i, text in ipairs(lines) do buf:Add("  %d: %s", i, text) end
    end
    ShowDebug(buf)
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
