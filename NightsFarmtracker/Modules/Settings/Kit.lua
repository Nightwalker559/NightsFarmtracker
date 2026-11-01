------------------------------------------------------------------------
-- Night's Farmtracker - Settings kit
-- What the settings files share: layout constants, pooled checkbox / radio /
-- label rows, the popup lists of the dropdowns, number boxes and the registry
-- the section files add their sections to (Window.lua builds the page from it).
------------------------------------------------------------------------
local _, ns = ...

local K = {}
ns.SettingsKit = K

ns.RegisterConfirmDialog("NFT_RELOAD", ns.L["reload_required"], function() ReloadUI() end)

local S_W   = 320
local S_PAD = 14

-- Checkboxes and radio dots are CTRL_SIZE squares with CTRL_GAP between the
-- rows of a group. CHECK_RUN_TAIL is the extra space after the last checkbox of
-- a run (before a section title or a block of other widgets).
local CTRL_SIZE, CTRL_GAP = 14, ns.CTRL_GAP
local CHECK_RUN_TAIL = 18
-- Distance from a section title to its first row: checkboxes and radio dots sit
-- 4 px inside their row, so a section that starts with one uses the smaller step.
local TITLE_STEP, TITLE_STEP_CTRL = 26, 22

------------------------------------------------------------------------
-- Radio button row — pooled (built once, reconfigured on reuse) so
-- RebuildSettingsContent doesn't leak new Frame/FontString objects on
-- every settings interaction (see ns.NewPool).
------------------------------------------------------------------------
local function CreateRadio(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2, CTRL_SIZE + CTRL_GAP)

    local dot, fill = ns.CreateMarkBox(row, CTRL_SIZE)
    dot:SetPoint("TOPLEFT", 0, -4)
    fill:Hide()
    dot.fill = fill

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    lbl:SetTextColor(0.85,0.85,0.85)
    row.label = lbl

    local grayLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    grayLbl:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
    grayLbl:SetTextColor(0.4,0.4,0.4)
    grayLbl:SetText(ns.L["not_installed"])
    grayLbl:Hide()
    row.notInstalled = grayLbl

    row.dot = dot

    function row:SetSelected(sel)
        if sel then
            fill:Show()
            lbl:SetTextColor(1, 0.82, 0)
        else
            fill:Hide()
            lbl:SetTextColor(0.85,0.85,0.85)
        end
    end

    function row:SetEnabled(en)
        row:EnableMouse(en)
        if not en then
            lbl:SetTextColor(0.4,0.4,0.4)
            dot:SetBackdropBorderColor(0.2,0.2,0.2,0.5)
            grayLbl:Show()
        else
            dot:SetBackdropBorderColor(unpack(ns.COL_BORDER))
            grayLbl:Hide()
        end
    end

    return row
end

local radioPool = ns.NewPool(CreateRadio, function(row) row:SetScript("OnMouseUp", nil) end)

-- (Re-)configures a pooled radio row for its current position/label/value/
-- callback. Called every time regardless of whether the row is freshly
-- built or reused from the pool.
local function ConfigureRadio(row, label, yOff, value, setGroup)
    row:SetPoint("TOPLEFT", S_PAD, yOff)
    row.label:SetText(label)
    row.value = value
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function()
        setGroup(value)
        ns.RebuildSettingsContent()
    end)
    return row
end

local function MenuTextColor(row)
    if row.isActive then row.txt:SetTextColor(1, 0.82, 0) else row.txt:SetTextColor(0.85, 0.85, 0.85) end
end

-- Fills a popup list with one clickable row per name (rows are reused).
-- The row matching activeName is highlighted; onPick(name) runs on click.
local function FillMenu(list, rows, names, rowH, activeName, onPick)
    for _, row in ipairs(rows) do row:Hide() end
    for i, name in ipairs(names) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, list)
            row:SetHeight(rowH)
            row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.txt:SetPoint("LEFT", 6, 0)
            row:SetScript("OnEnter", function() row.txt:SetTextColor(1, 1, 1) end)
            row:SetScript("OnLeave", function() MenuTextColor(row) end)
            rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
        row:SetPoint("RIGHT", -2, 0)
        row.txt:SetText(name)
        row.isActive = (name == activeName)
        MenuTextColor(row)
        row:SetScript("OnClick", function() onPick(name) end)
        row:Show()
    end
    list:SetHeight(2 + rowH * math.max(#names, 1) + 2)
end

-- Boxed dropdown header (label + expand arrow) shared by every dropdown below.
local function MakeDropdownBox(parent, width)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, 24)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    frame.lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.lbl:SetPoint("LEFT",6,0)
    frame.lbl:SetTextColor(0.85,0.85,0.85)

    local arrow = frame:CreateTexture(nil,"ARTWORK")
    arrow:SetSize(10, 8)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetVertexColor(unpack(ns.COL_ACCENT))

    return frame
end

-- Popup lists and the option windows (Sell List, Gear AH threshold) are frames
-- of their own (not children of Settings), so CloseMenus has to hide them
-- explicitly.
local popups = {}
local function RegisterPopup(frame) popups[#popups + 1] = frame end

-- Popup list shown under a dropdown; its own frame on UIParent so it can
-- overlap the settings window, and it swallows clicks meant for whatever
-- sits behind it.
local function MakePopupList()
    local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    list:SetFrameStrata("TOOLTIP")
    list:EnableMouse(true)
    list:EnableMouseWheel(true)   -- see ns.CreateWindowFrame
    ns.StyleBackdropBox(list, {0.05,0.08,0.09,1})
    list:Hide()
    RegisterPopup(list)
    return list
end

-- Opens `list` under `anchor` (prepare() fills it first), or closes it again
-- when it is already open.
local function ToggleMenu(list, anchor, prepare)
    if list:IsShown() then list:Hide(); return end
    if prepare then prepare() end
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    list:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    list:Show()
end

local function CloseMenus()
    for _, frame in ipairs(popups) do frame:Hide() end
end

------------------------------------------------------------------------
-- Helper: boxed numeric input (60 px) with a unit label ("g", "min", "px")
-- next to it. The label lives on the outer list, not inside the bordered box,
-- so it has to be shown/hidden together with the (reused) frame explicitly.
------------------------------------------------------------------------
local function MakeNumberBox(parent, yOff, maxLetters, unitText)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(60, 24)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)
    ns.StyleBackdropBox(frame, {0.05,0.08,0.09,1})

    local eb = CreateFrame("EditBox", nil, frame)
    eb:SetSize(48, 18)
    eb:SetPoint("LEFT", 6, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(maxLetters)
    eb:SetFontObject(GameFontNormalSmall)
    eb:SetTextColor(0.85, 0.85, 0.85)
    ns.HookEditBoxFocus(frame, eb)

    local unitLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unitLbl:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    unitLbl:SetText(unitText)
    unitLbl:SetTextColor(0.6,0.6,0.6)
    frame.unitLbl = unitLbl
    local baseShow, baseHide = frame.Show, frame.Hide
    frame.Show = function(self) baseShow(self); unitLbl:Show() end
    frame.Hide = function(self) baseHide(self); unitLbl:Hide() end

    frame.eb = eb
    return frame, eb
end

------------------------------------------------------------------------
-- Checkbox row — pooled, same rationale as radio rows above.
------------------------------------------------------------------------
local function CreateCheckbox(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2, CTRL_SIZE + CTRL_GAP)

    local box, check = ns.CreateMarkBox(row, CTRL_SIZE)
    box:SetPoint("TOPLEFT", 0, -4)
    row.box   = box
    row.check = check

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 0)
    lbl:SetWidth(S_W - S_PAD*2 - CTRL_SIZE - 8)   -- fixed width: GetStringHeight of a wrapped label is exact
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(true)
    row.label = lbl

    return row
end

local checkboxPool = ns.NewPool(CreateCheckbox, function(row)
    row:SetScript("OnMouseUp", nil); row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil)
end)

-- (Re-)configures a pooled checkbox row: label text, position, and the
-- getValue/setValue accessors driving its checked state and click handler.
-- opts (optional): indent shifts the row right (an option under another
-- checkbox); disabled greys it out and ignores clicks, the checked state
-- stays visible; tip is a tooltip text shown on hover.
local function ConfigureCheckbox(row, label, yOff, getValue, setValue, opts)
    opts = opts or {}
    local indent, disabled, tip = opts.indent or 0, opts.disabled, opts.tip
    row:SetPoint("TOPLEFT", S_PAD + indent, yOff)
    row:SetWidth(S_W - S_PAD*2 - indent)
    row.label:SetWidth(S_W - S_PAD*2 - indent - CTRL_SIZE - 8)
    row.label:SetText(label)
    row:SetHeight(4 + math.max(CTRL_SIZE, math.ceil(row.label:GetStringHeight())))   -- hit area follows a wrapped label

    row.check:SetAlpha(disabled and 0.35 or 1)
    row.box:SetBackdropBorderColor(unpack(disabled and {0.2, 0.2, 0.2, 0.5} or ns.COL_BORDER))
    local function Refresh()
        if disabled then row.label:SetTextColor(0.4,0.4,0.4)
        elseif getValue() then row.label:SetTextColor(1,0.82,0)
        else row.label:SetTextColor(0.85,0.85,0.85) end
        row.check:SetShown(getValue() and true or false)
    end
    Refresh()
    row:EnableMouse(not disabled)
    row:SetScript("OnMouseUp", not disabled and function() setValue(not getValue()); Refresh() end or nil)
    row:SetScript("OnEnter", tip and not disabled and function(self)
        GameTooltip:SetOwner(self, ns.SmartAnchor(self, "RIGHT"))
        GameTooltip:AddLine(tip, 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end or nil)
    row:SetScript("OnLeave", tip and not disabled and function() GameTooltip:Hide() end or nil)
    return row
end

------------------------------------------------------------------------
-- Section title / hint text — pooled FontStrings. Text color is set once
-- at creation (ns.COL_ACCENT/gray) since a theme change always requires
-- a UI reload (see ApplyColorTheme), so it never goes stale while pooled.
------------------------------------------------------------------------
local sectionLabelPool = ns.NewPool(function(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetTextColor(unpack(ns.COL_ACCENT))
    return fs
end)

local hintLabelPool = ns.NewPool(function(parent)
    return parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
end)

-- Separate pool for the hints that use a fixed width + word wrap - kept apart
-- from the auto-sized hints above so reuse never has to un-set a manually
-- fixed width.
local wrappedHintPool = ns.NewPool(function(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetWidth(S_W - S_PAD*2)
    fs:SetJustifyH("LEFT")
    return fs
end)

K.S_W, K.S_PAD = S_W, S_PAD
K.S_HDR_H = ns.WINDOW_HDR_H
K.CTRL_SIZE, K.CTRL_GAP, K.CHECK_RUN_TAIL = CTRL_SIZE, CTRL_GAP, CHECK_RUN_TAIL
K.TITLE_STEP, K.TITLE_STEP_CTRL = TITLE_STEP, TITLE_STEP_CTRL
K.radioPool, K.checkboxPool = radioPool, checkboxPool
K.sectionLabelPool, K.hintLabelPool, K.wrappedHintPool = sectionLabelPool, hintLabelPool, wrappedHintPool
K.ConfigureRadio, K.ConfigureCheckbox = ConfigureRadio, ConfigureCheckbox
K.MenuTextColor, K.FillMenu, K.ToggleMenu, K.CloseMenus = MenuTextColor, FillMenu, ToggleMenu, CloseMenus
K.MakeDropdownBox, K.MakePopupList, K.RegisterPopup = MakeDropdownBox, MakePopupList, RegisterPopup
K.MakeNumberBox = MakeNumberBox

-- Section files register a builder(y, ui) that returns the y below its widgets;
-- Window.lua sorts them by their localized title.
K.sections = {}
function K.AddSection(titleKey, builder)
    K.sections[#K.sections + 1] = {titleKey = titleKey, builder = builder}
end
