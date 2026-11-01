------------------------------------------------------------------------
-- Night's Farmtracker - Settings window
-- Custom settings window (no WoW Settings API dependency): one scrolling page
-- with a section sidebar. The sections themselves live in the other files of
-- this folder and register with ns.SettingsKit.AddSection; this file builds
-- the page from them, owns the sidebar and the window.
------------------------------------------------------------------------
local _, ns = ...
local K = ns.SettingsKit

local S_W, S_PAD, S_HDR_H = K.S_W, K.S_PAD, K.S_HDR_H
local CTRL_SIZE, CTRL_GAP, CHECK_RUN_TAIL = K.CTRL_SIZE, K.CTRL_GAP, K.CHECK_RUN_TAIL
local radioPool, checkboxPool = K.radioPool, K.checkboxPool
local sectionLabelPool, hintLabelPool, wrappedHintPool = K.sectionLabelPool, K.hintLabelPool, K.wrappedHintPool

local SF           -- settings frame (lazy built)
local SScrollFrame -- scroll container for content
local SListFrame   -- scroll child (all widgets live here)
local SSidebar     -- category nav sidebar (doesn't scroll)

local S_SIDEBAR_W   = 92
local S_FTR_H       = 26   -- footer strip height (Reset to Default button)
local S_SCROLL_STEP = 22
local TOP_PAD       = 8    -- small top padding within the scroll area

-- Wipes both SavedVariables tables and reloads - InitDB()/InitAccountDB()
-- (called again on the reload) then rebuild everything from scratch, same
-- as a fresh install. Deletes settings, session history, Vendor-Only
-- filter, Blacklist, Delete List, AH-by-expansion selection - everything.
function ns.ResetAddonToDefault()
    NightsFarmtrackerDB = nil
    NightsFarmtrackerAccountDB = nil
    ReloadUI()
end

ns.RegisterConfirmDialog("NFT_CONFIRM_RESET_ADDON", ns.L["reset_addon_confirm"],
    function() ns.ResetAddonToDefault() end, { preferredIndex = 3 })

------------------------------------------------------------------------
-- Sidebar navigation — pooled category buttons on the left, rebuilt to
-- match whatever sections actually exist this rebuild (TSM section is
-- conditional). Clicking a row scrolls the content so that section's
-- header lands at the top of the visible area.
------------------------------------------------------------------------
local sidebarRows = {}
local contentWheel   -- mouse-wheel handler of the content scroll area; the sidebar forwards to it
local function SidebarWheel(_, delta) contentWheel(nil, delta) end

local sidebarPool = ns.NewPool(function(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(S_SIDEBAR_W - 12)
    row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.txt:SetPoint("TOPLEFT", 0, 0)
    -- Fixed explicit width (not anchor-stretched) so word wrap is resolved
    -- immediately on the same frame. Anchor-based width (TOPLEFT+TOPRIGHT)
    -- isn't guaranteed to resolve before GetStringHeight() is read below,
    -- which caused the label to render unwrapped on the very first build.
    row.txt:SetWidth(S_SIDEBAR_W - 12)
    row.txt:SetJustifyH("LEFT")
    row.txt:SetWordWrap(true)
    row:SetScript("OnEnter", function(self) self.txt:SetTextColor(1, 0.82, 0) end)
    row:SetScript("OnLeave", function(self) self.txt:SetTextColor(0.7, 0.7, 0.7) end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", SidebarWheel)
    return row
end, function(row) row:SetScript("OnClick", nil) end)

local function RebuildSidebar(jumpTargets)
    sidebarPool.releaseAll(sidebarRows)

    local rowY = -4
    for _, target in ipairs(jumpTargets) do
        local row = sidebarPool.acquire(SSidebar)
        row.txt:SetText(target.title)
        row.txt:SetTextColor(0.7, 0.7, 0.7)
        row:SetPoint("TOPLEFT", 6, rowY)
        row:SetHeight(math.max(16, row.txt:GetStringHeight()))
        row:EnableMouse(true)
        row:SetScript("OnClick", function()
            local maxS = math.max(0, SListFrame:GetHeight() - SScrollFrame:GetHeight())
            SScrollFrame:SetVerticalScroll(math.max(0, math.min(target.y, maxS)))
        end)
        sidebarRows[#sidebarRows + 1] = row
        rowY = rowY - row:GetHeight() - 10
    end
end

------------------------------------------------------------------------
-- Settings content, rebuilt on open and on every change. All widgets are
-- parented to SListFrame (the scroll child) and tracked with their "kind", so
-- the next rebuild releases each one back to its pool instead of leaking
-- frames. Single-instance widgets (the dropdowns, number boxes, ...) are
-- created once by the section file and only repositioned (ui.place).
------------------------------------------------------------------------
local settingsContent = {}

local RELEASE_FN = {
    radio       = radioPool.release,
    checkbox    = checkboxPool.release,
    section     = sectionLabelPool.release,
    hint        = hintLabelPool.release,
    wrappedHint = wrappedHintPool.release,
}

-- Single-instance widgets are built on first use, then only moved and shown.
local function PlaceWidget(widget, make, y)
    if not widget then widget = make(SListFrame, y) end
    widget:SetParent(SListFrame)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", S_PAD, y)
    widget:Show()
    return widget
end

-- The helpers a section builder(y, ui) works with. Each returns the y below
-- what it placed, and registers the widget it took from a pool in
-- settingsContent for the next rebuild to release.
local function NewBuildContext(db)
    local ui = {db = db, place = PlaceWidget}

    function ui.track(widget, kind)
        settingsContent[#settingsContent + 1] = {widget = widget, kind = kind}
        return widget
    end
    local track = ui.track

    -- Section title label at y; returns the y below it.
    function ui.sectionTitle(y, key, step)
        local lbl = track(sectionLabelPool.acquire(SListFrame), "section")
        lbl:SetPoint("TOPLEFT", S_PAD, y)
        lbl:SetText(ns.L[key])
        return y - step
    end

    -- Grey wrapped hint text at y (full width); returns the FontString so the
    -- caller can size the space below it.
    function ui.wrappedHint(y, text)
        local fs = track(wrappedHintPool.acquire(SListFrame), "wrappedHint")
        fs:SetPoint("TOPLEFT", S_PAD, y)
        fs:SetTextColor(0.5,0.5,0.5)
        fs:SetText(text)
        return fs
    end

    -- Grey single-line hint label; the caller moves y down.
    function ui.hintLabel(x, y, text, gray)
        local fs = track(hintLabelPool.acquire(SListFrame), "hint")
        fs:SetPoint("TOPLEFT", x, y)
        fs:SetTextColor(gray, gray, gray)
        fs:SetText(text)
    end

    -- Checkbox row at y; returns the y below it: CTRL_GAP below the box or
    -- the (possibly wrapped) label, whichever is taller.
    -- opts (optional): indent, disabled (see K.ConfigureCheckbox), tip (locale key
    -- of the tooltip), arg (fills the %d of the label and the tooltip).
    function ui.checkbox(y, labelKey, get, set, opts)
        opts = opts or {}
        local label = opts.arg and string.format(ns.L[labelKey], opts.arg) or ns.L[labelKey]
        local tip = opts.tip and string.format(ns.L[opts.tip], opts.arg)
        local row = K.ConfigureCheckbox(track(checkboxPool.acquire(SListFrame), "checkbox"), label, y, get, set,
            { indent = opts.indent, disabled = opts.disabled, tip = tip })
        return y - math.max(CTRL_SIZE, math.ceil(row.label:GetStringHeight())) - CTRL_GAP, row
    end

    -- Checkbox bound to db[key]. With defaultOn an unset value counts as
    -- checked. after(v) runs once the value is stored.
    function ui.flag(y, labelKey, key, defaultOn, after, opts)
        return ui.checkbox(y, labelKey,
            function()
                if defaultOn then return db[key] ~= false end
                return db[key] == true
            end,
            function(v)
                db[key] = v
                if after then after(v) end
            end, opts)
    end

    -- One radio row at y; the caller sets its selected / enabled state.
    function ui.radio(y, label, value, set)
        local row = track(radioPool.acquire(SListFrame), "radio")
        K.ConfigureRadio(row, label, y, value, set)
        return row
    end

    -- Radio group, one row per { labelKey, value }; `after` is the distance from
    -- the last row to whatever follows (default: the usual row step, for a
    -- checkbox or radio below). Returns the new y and the rows.
    function ui.radioGroup(y, options, current, set, after)
        local rows = {}
        for i, opt in ipairs(options) do
            local row = ui.radio(y, ns.L[opt[1]], opt[2], set)
            row:SetSelected(current == opt[2]); row:SetEnabled(true)
            rows[i] = row
            y = y - (i < #options and CTRL_SIZE + CTRL_GAP or after or CTRL_SIZE + CTRL_GAP)
        end
        return y, rows
    end

    return ui
end

-- Sections are sorted alphabetically by the CURRENT locale's title text, so the
-- list reads alphabetically in every language without hardcoding per-locale
-- order. Profiles is the one exception: it's account/character management, not
-- a content setting, so it always sorts last regardless of where its localized
-- title would alphabetically land.
local function SortedSections()
    local sections = {}
    for i, sec in ipairs(K.sections) do
        sections[i] = {titleKey = sec.titleKey, title = ns.L[sec.titleKey], builder = sec.builder}
    end
    table.sort(sections, function(a, b)
        if a.titleKey == "sec_profiles" then return false end
        if b.titleKey == "sec_profiles" then return true end
        return a.title:lower() < b.title:lower()
    end)
    return sections
end

------------------------------------------------------------------------
-- Settings content (rebuilt on open / change). Each builder receives the
-- running y-offset and returns the new one; a sidebar entry is recorded for
-- each section's starting position so the nav list can jump to it.
------------------------------------------------------------------------
function ns.RebuildSettingsContent()
    if not SListFrame then return end
    K.CloseMenus()
    local prevScroll = SScrollFrame:GetVerticalScroll()
    for _, entry in ipairs(settingsContent) do
        local release = RELEASE_FN[entry.kind]
        if release then release(entry.widget) else entry.widget:Hide() end
    end
    settingsContent = {}

    local ui = NewBuildContext(NightsFarmtrackerDB)

    local y = -TOP_PAD
    local jumpTargets = {}
    for _, sec in ipairs(SortedSections()) do
        -- keeps the same gap above the title as at the very top, so jumping to
        -- the first section doesn't scroll at all
        jumpTargets[#jumpTargets + 1] = {title = sec.title, y = -y - TOP_PAD}
        y = sec.builder(y, ui)
        local last = settingsContent[#settingsContent]
        if last and last.kind == "checkbox" then y = y - CHECK_RUN_TAIL end   -- air before the next section title
    end
    RebuildSidebar(jumpTargets)

    -- ----------------------------------------------------------------
    -- Resize scroll area and outer frame
    -- ----------------------------------------------------------------
    local contentH = math.abs(y) + 8
    local visH = ns.FitScrollWindow({
        window = SF, scroll = SScrollFrame, list = SListFrame,
        hdrH = S_HDR_H, ftrH = S_FTR_H, contentH = contentH,
    })
    SSidebar:SetHeight(visH)
    SScrollFrame:SetVerticalScroll(math.min(prevScroll, math.max(0, contentH - visH)))
end

------------------------------------------------------------------------
-- Build settings frame (lazy)
------------------------------------------------------------------------
local function EnsureSettingsFrame()
    if SF then return end

    SF = ns.CreateWindowFrame("NightsFarmtrackerSettingsWnd", ns.L["settings_title"],
        {width = S_W + S_SIDEBAR_W, pad = S_PAD, titleColor = ns.COL_ACCENT, dockChain = "left"})
    SF:SetHeight(280)
    ns.SettingsFrame = SF  -- exposed so Session History can dock next to it in the left-side chain
    -- Closes the floating dropdown lists and the option windows whenever
    -- Settings hides for ANY reason (X button, ESC via UISpecialFrames, /reload,
    -- etc.) - they are separate frames parented to UIParent, so they don't
    -- auto-close with SF on their own.
    SF:HookScript("OnHide", K.CloseMenus)

    ns.AddHLine(SF, "TOP", S_PAD, -(S_HDR_H-1))

    -- Sidebar — fixed-width category nav, doesn't scroll with the content.
    SSidebar = CreateFrame("Frame", nil, SF)
    SSidebar:SetPoint("TOPLEFT", 0, -S_HDR_H)
    SSidebar:SetWidth(S_SIDEBAR_W)
    SSidebar:EnableMouse(true)   -- with the wheel it keeps the sidebar's gaps from passing scrolls to the chat
    SSidebar:EnableMouseWheel(true)
    SSidebar:SetScript("OnMouseWheel", SidebarWheel)

    local sidebarSep = SF:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetWidth(1); sidebarSep:SetColorTexture(unpack(ns.COL_BORDER))
    sidebarSep:SetPoint("TOPLEFT", S_SIDEBAR_W, -S_HDR_H)
    sidebarSep:SetPoint("BOTTOMLEFT", S_SIDEBAR_W, S_FTR_H)

    -- Scroll container — right of the sidebar, below header sep
    SScrollFrame, SListFrame, contentWheel = ns.CreateScrollList(SF, S_W, S_SCROLL_STEP)
    SScrollFrame:SetPoint("TOPLEFT",  S_SIDEBAR_W, -S_HDR_H)
    SScrollFrame:SetPoint("TOPRIGHT", 0, -S_HDR_H)

    ns.CreateDangerLink(SF, S_PAD, ns.L["reset_addon"], function() StaticPopup_Show("NFT_CONFIRM_RESET_ADDON") end)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
function ns.ToggleSettings()
    if ns.DeferInCombat(ns.ToggleSettings) then return end
    EnsureSettingsFrame()
    if SF:IsShown() then
        SF:Hide()
    else
        -- History and its Detail child dock off the same anchor point as
        -- Settings, so close them first to avoid overlap.
        if ns.HistFrame and ns.HistFrame:IsShown() then ns.HistFrame:Hide() end
        if ns.DetailFrame and ns.DetailFrame:IsShown() then ns.DetailFrame:Hide() end
        ns.RebuildSettingsContent()
        SF:Show()
        ns.RefreshWindowChain("left")
    end
end
