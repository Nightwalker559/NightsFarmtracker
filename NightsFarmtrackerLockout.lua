------------------------------------------------------------------------
-- Night's Farmtracker - Instance Lockout Counter (optional)
-- WoW limits how many instances you can enter per hour, but exposes no API
-- for it. Every successful instance reset ("<Zone> has been reset.") is
-- recorded here and expires again after one hour, so the counter shows how
-- many resets are currently "in the budget". A small frame below the main
-- window shows x/9 plus the time until the oldest one drops off, with a
-- button that calls ResetInstances().
-- The limit is per account, so the list lives in the account-wide DB.
-- Off by default; toggled via Settings -> Display.
------------------------------------------------------------------------
local _, ns = ...

local ART = "Interface\\AddOns\\NightsFarmtracker\\Media\\"

local MAX_RESETS = 9
local LOCK_TIME  = 3600  -- seconds a reset counts against the limit
local FRAME_H    = 28

local issecretvalue = issecretvalue or function() return false end

-- "%s has been reset." -> pattern capturing the zone name.
local RESET_PATTERN
do
    local fmt = INSTANCE_RESET_SUCCESS
    if fmt then
        local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)")
        RESET_PATTERN = p
    end
end

local LockoutFrame

------------------------------------------------------------------------
-- Data (account-wide list of { time = serverTime, zone = name })
------------------------------------------------------------------------
local function GetResets()
    if not NightsFarmtrackerAccountDB then return {} end
    local list = NightsFarmtrackerAccountDB.instanceResets
    if not list then
        list = {}
        NightsFarmtrackerAccountDB.instanceResets = list
    end
    return list
end

-- Drops entries older than LOCK_TIME; returns the (pruned) list.
local function PrunedResets()
    local list = GetResets()
    local now = GetServerTime()
    for i = #list, 1, -1 do
        if now - list[i].time >= LOCK_TIME then table.remove(list, i) end
    end
    return list
end

local function AddReset(zone)
    local list = PrunedResets()
    list[#list + 1] = { time = GetServerTime(), zone = zone }
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------
local function FormatRemaining(seconds)
    seconds = math.max(0, seconds)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function CountColor(count)
    if count >= MAX_RESETS     then return 1.0, 0.3, 0.3 end
    if count >= MAX_RESETS - 3 then return 1.0, 0.82, 0.0 end
    return 0.3, 0.9, 0.3
end

local function UpdateText()
    if not LockoutFrame or not LockoutFrame:IsShown() then return end
    local list = PrunedResets()
    local count = #list
    LockoutFrame.countText:SetText(string.format(ns.L["lockout_count"], count, MAX_RESETS))
    LockoutFrame.countText:SetTextColor(CountColor(count))
    if count > 0 then
        local oldest = list[1].time
        for i = 2, #list do oldest = math.min(oldest, list[i].time) end
        LockoutFrame.timeText:SetText(FormatRemaining(oldest + LOCK_TIME - GetServerTime()))
    else
        LockoutFrame.timeText:SetText("")
    end
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    local list = PrunedResets()
    GameTooltip:AddLine(string.format(ns.L["lockout_tooltip_title"], #list, MAX_RESETS), 1, 1, 1)
    for _, entry in ipairs(list) do
        GameTooltip:AddDoubleLine(date("%H:%M:%S", entry.time + LOCK_TIME), entry.zone or "?", 0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:AddLine(ns.L["lockout_reset_hint"], 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

-- Dock directly below the main window, or below the Gold Overview when
-- that is open (it sits in the same spot).
local function Reanchor()
    if not LockoutFrame then return end
    LockoutFrame:ClearAllPoints()
    if ns.GoldFrame and ns.GoldFrame:IsShown() then
        LockoutFrame:SetPoint("TOPLEFT", ns.GoldFrame, "BOTTOMLEFT", 0, -2)
    else
        LockoutFrame:SetPoint("TOPLEFT", ns.MainFrame, "BOTTOMLEFT", 0, -2)
    end
end

local function EnsureFrame()
    if LockoutFrame then return end

    LockoutFrame = CreateFrame("Frame", "NightsFarmtrackerLockoutFrame", UIParent, "BackdropTemplate")
    LockoutFrame:SetSize(ns.FRAME_W, FRAME_H)
    LockoutFrame:SetFrameStrata("MEDIUM")
    LockoutFrame:SetClampedToScreen(true)
    LockoutFrame:EnableMouse(true)
    ns.ApplyFrameStyle(LockoutFrame)
    LockoutFrame:Hide()
    ns.LockoutFrame = LockoutFrame

    local pad = ns.PAD

    local countText = LockoutFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("LEFT", pad, 0)
    countText:SetFontHeight(ns.FONT_NORMAL)
    LockoutFrame.countText = countText

    local btn = CreateFrame("Button", nil, LockoutFrame)
    btn:SetSize(16, 16)
    btn:SetPoint("RIGHT", -pad, 0)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(ART .. "btn_reset.png")
    btn.tex:SetAlpha(0.75)
    btn:SetScript("OnEnter", function(self)
        self.tex:SetAlpha(1)
        ShowTooltip(self)
    end)
    btn:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75); GameTooltip:Hide() end)
    btn:SetScript("OnClick", function() ResetInstances() end)
    LockoutFrame.resetBtn = btn

    local timeText = LockoutFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    timeText:SetFontHeight(ns.FONT_NORMAL)
    timeText:SetTextColor(0.75, 0.75, 0.75)
    LockoutFrame.timeText = timeText

    LockoutFrame:SetScript("OnEnter", function(self) ShowTooltip(self) end)
    LockoutFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 1s refresh of the countdown while visible.
    local elapsed = 0
    LockoutFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 1 then elapsed = 0; UpdateText() end
    end)

    -- Frames below the main window (Log while collapsed) chain below this
    -- one while it's visible; follow Gold Overview open/close too.
    LockoutFrame:HookScript("OnShow", function()
        Reanchor(); UpdateText()
        if ns.LogFrame and ns.LogFrame:IsShown() and ns.ReanchorLogFrame then ns.ReanchorLogFrame() end
    end)
    LockoutFrame:HookScript("OnHide", function()
        if ns.LogFrame and ns.LogFrame:IsShown() and ns.ReanchorLogFrame then ns.ReanchorLogFrame() end
    end)
    ns.GoldFrame:HookScript("OnShow", Reanchor)
    ns.GoldFrame:HookScript("OnHide", Reanchor)
end

-- Shown iff enabled and the main window is open.
function ns.UpdateLockoutFrame()
    if not NightsFarmtrackerDB then return end
    if NightsFarmtrackerDB.instanceLockoutEnabled ~= true or not ns.MainFrame:IsShown() then
        if LockoutFrame then LockoutFrame:Hide() end
        return
    end
    EnsureFrame()
    Reanchor()
    LockoutFrame:Show()
    UpdateText()
end

function ns.SetInstanceLockoutEnabled(enabled)
    NightsFarmtrackerDB.instanceLockoutEnabled = enabled and true or false
    ns.UpdateLockoutFrame()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
-- Resets are recorded even while the counter is disabled, so enabling it
-- later immediately shows the correct state.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("CHAT_MSG_SYSTEM")
watcher:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_LOGIN" then
        ns.UpdateLockoutFrame()
    elseif RESET_PATTERN and msg and not issecretvalue(msg) then
        local zone = msg:match(RESET_PATTERN)
        if zone then
            AddReset(zone)
            UpdateText()
        end
    end
end)

ns.MainFrame:HookScript("OnShow", ns.UpdateLockoutFrame)
ns.MainFrame:HookScript("OnHide", ns.UpdateLockoutFrame)
