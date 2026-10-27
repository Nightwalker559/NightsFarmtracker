------------------------------------------------------------------------
-- Night's Farmtracker - Item Goals
-- Items dragged in here get a target amount; while Item goals is the active
-- limit (Settings, Display) their bars show the progress and the session
-- pauses as soon as one of them reaches its amount. Per profile; the goals
-- themselves live in db.itemGoals (see ns.SetItemGoal, ns.GetItemGoal).
------------------------------------------------------------------------
local _, ns = ...

local MIN_VIS_H = 30   -- room for the "list empty" label
local DZ_H      = 34   -- drop zone height
local FTR_H     = 26   -- footer strip (Clear All, inactive note)
local BOX_W     = 52   -- amount box on the right of each row

local pad, hdrH = ns.PAD, ns.WINDOW_HDR_H
local frame, scrollFrame, listFrame
local rows = {}

local function Rebuild() ns.RebuildGoalsList() end

local function RemoveGoal(itemID)
    ns.RemoveItemGoal(itemID)
    Rebuild()
    ns.RefreshHUD()
end

-- Row = the shared drop-list item row plus a boxed amount field. The amount
-- is applied when the field loses focus / Enter is pressed, not per keystroke
-- (typing "2" on the way to "20" would otherwise reach the goal on the first
-- digit and pause the session).
local function CreateGoalRow(parent)
    local r = ns.CreateDropListItemRow(parent, RemoveGoal)

    local box = CreateFrame("Frame", nil, r, "BackdropTemplate")
    box:SetSize(BOX_W, 20)
    box:SetPoint("RIGHT", -4, 0)
    ns.StyleBackdropBox(box, {0.05, 0.08, 0.09, 1})

    local eb = CreateFrame("EditBox", nil, box)
    eb:SetSize(BOX_W - 12, 18)
    eb:SetPoint("LEFT", 6, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(5)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetTextColor(0.85, 0.85, 0.85)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(unpack(ns.COL_ACCENT)) end)
    eb:SetScript("OnEditFocusLost", function(self)
        box:SetBackdropBorderColor(unpack(ns.COL_BORDER))
        local goal = r.itemID and ns.GetItemGoals()[r.itemID]
        if not goal then return end
        local v = tonumber(self:GetText()) or 0
        goal.amount = v
        self:SetText(v > 0 and tostring(v) or "")
        ns.RefreshHUD()
    end)
    r.amountBox = eb

    r.nameText:ClearAllPoints()
    r.nameText:SetPoint("LEFT",  r.icon, "RIGHT", 8, 0)
    r.nameText:SetPoint("RIGHT", box,    "LEFT", -6, 0)
    return r
end

local rowPool = ns.NewPool(CreateGoalRow, function(r)
    r.amountBox:ClearFocus()   -- commits a pending edit while the row still knows its item
    r.itemID = nil; r.iconBorder:Hide()
end)

function ns.RebuildGoalsList()
    if not frame then return end
    rowPool.releaseAll(rows)

    local list = {}
    for itemID, goal in pairs(ns.GetItemGoals()) do
        list[#list + 1] = { itemID = itemID, goal = goal }
    end
    table.sort(list, function(a, b) return (a.goal.name or "") < (b.goal.name or "") end)

    frame.DropZone:ClearAllPoints()
    frame.DropZone:SetPoint("TOPLEFT", 0, 0)
    frame.DropZone:SetPoint("TOPRIGHT", 0, 0)
    local sepTop = DZ_H + 4
    frame.dzSep:ClearAllPoints()
    frame.dzSep:SetPoint("TOPLEFT", 0, -sepTop)
    frame.dzSep:SetPoint("TOPRIGHT", 0, -sepTop)

    local yOff = sepTop + 1 + 4
    for _, e in ipairs(list) do
        local r = rowPool.acquire(listFrame)
        r:SetPoint("TOPLEFT", 0, -yOff)
        r.itemID = e.itemID
        r.icon:SetTexture(e.goal.icon or ns.FALLBACK_ICON)
        r.nameText:SetText(ns.TruncateName(ns.DisplayName(e.goal.name, e.itemID) or ("Item " .. e.itemID)))
        ns.ApplyQualityColor(r.nameText, r.iconBorder, e.goal.quality, {0.85, 0.85, 0.85})
        local amount = tonumber(e.goal.amount) or 0
        r.amountBox:SetText(amount > 0 and tostring(amount) or "")
        rows[#rows + 1] = r
        yOff = yOff + ns.ROW_H
    end

    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", pad, -hdrH)
    ns.FitScrollWindow({
        window = frame, scroll = scrollFrame, list = listFrame,
        hdrH = hdrH, ftrH = FTR_H,
        contentH = yOff + (#list == 0 and MIN_VIS_H or 0),
    })

    frame.emptyLabel:ClearAllPoints()
    frame.emptyLabel:SetPoint("TOP", listFrame, "TOP", 0, -(yOff + 14))
    frame.emptyLabel:SetShown(#list == 0)
    frame.inactiveNote:SetShown(NightsFarmtrackerDB.limitMode ~= "goal")
end

local function HandleDrop()
    ns.HandleItemDrop(function(itemID, itemLink)
        local goals = ns.GetItemGoals()
        if not goals[itemID] then
            local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink or itemID)
            ns.SetItemGoal(itemID, name or ("Item " .. itemID), icon, quality, 1)
        end
        Rebuild()
        ns.RefreshHUD()
    end)
end

local function EnsureFrame()
    if frame then return end
    frame = ns.CreateWindowFrame("NightsFarmtrackerGoalsWnd", ns.L["goals_title"], { width = ns.FRAME_W })
    frame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", 4, 0)
    ns.GoalsFrame = frame   -- docking chain, see ns.WINDOW_CHAINS

    ns.AddHLine(frame, "TOP", pad, -(hdrH - 1))
    ns.EnableItemDrop(frame, HandleDrop)

    scrollFrame, listFrame = ns.CreateDropListScroll(frame, HandleDrop)
    scrollFrame:SetPoint("TOPLEFT", pad, -hdrH)

    frame.DropZone = ns.CreateDropZone(listFrame, DZ_H, HandleDrop)
    frame.dzSep = ns.AddHLine(listFrame, "TOP", 0, 0)

    frame.emptyLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.emptyLabel:SetWidth(ns.CONTENT_W)
    frame.emptyLabel:SetJustifyH("CENTER")
    frame.emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    frame.emptyLabel:SetText(ns.L["goals_list_empty"])

    frame.inactiveNote = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.inactiveNote:SetPoint("BOTTOMLEFT", pad, 10)
    frame.inactiveNote:SetTextColor(0.85, 0.3, 0.3)
    frame.inactiveNote:SetText(ns.L["goals_inactive"])

    frame.clrBtn = ns.CreateClearAllButton(frame, pad, function()
        return next(ns.GetItemGoals()) ~= nil
    end, "NFT_CONFIRM_CLEAR_ALL_GOALS")
end

ns.RegisterConfirmDialog("NFT_CONFIRM_CLEAR_ALL_GOALS", ns.L["goals_clear_all_confirm"],
    function()
        ns.ClearItemGoals()
        Rebuild()
        ns.RefreshHUD()
    end, { preferredIndex = 3 })

function ns.ToggleGoalsWindow()
    if ns.DeferInCombat(ns.ToggleGoalsWindow) then return end
    EnsureFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        Rebuild()
        frame:Show()
    end
    ns.RefreshWindowChain("right")
end
