------------------------------------------------------------------------
-- Night's Farmtracker - Filter window
-- One window for the drop lists (Vendor-Only Filter, Blacklist, ...): a tab
-- strip under the title and one pane per tab (ns.CreateDropListPane). A list
-- module describes its data with ns.RegisterFilterTab, in load order, and gets
-- its tab; the window, the strip, docking and opening live here. A tab whose
-- feature is switched off in Settings is not shown. Items dropped on the
-- window land in the active tab.
--
-- ns.RegisterFilterTab(cfg): cfg.key (tab id), cfg.titleKey (tab label),
-- cfg.enabledKey (setting that switches the tab off), and the pane fields
-- described at ns.CreateDropListPane.
------------------------------------------------------------------------
local _, ns = ...

local pad, hdrH = ns.PAD, ns.WINDOW_HDR_H
local TAB_H     = 22
local BODY_TOP  = hdrH + TAB_H   -- window Y where a pane starts

local tabs, byKey = {}, {}       -- registered tabs in order, and by key
local frame, active              -- the window (built on first open) and the shown tab

function ns.RegisterFilterTab(cfg)
    local tab = { key = cfg.key, cfg = cfg }
    tabs[#tabs + 1] = tab
    byKey[cfg.key] = tab
end

local function IsEnabled(tab)
    return NightsFarmtrackerDB[tab.cfg.enabledKey] ~= false
end

local function FirstEnabled()
    for _, tab in ipairs(tabs) do
        if IsEnabled(tab) then return tab end
    end
end

------------------------------------------------------------------------
-- Tab strip
------------------------------------------------------------------------
local function PaintTabs()
    for _, tab in ipairs(tabs) do
        local on = tab == active
        tab.button.text:SetTextColor(unpack(on and ns.COL_ACCENT or {0.6, 0.6, 0.6}))
        tab.button.underline:SetShown(on)
    end
end

-- Enabled tabs share the width of the strip equally
local function LayoutTabs()
    local shown = {}
    for _, tab in ipairs(tabs) do
        if IsEnabled(tab) then shown[#shown + 1] = tab else tab.button:Hide() end
    end
    local w = ns.CONTENT_W / math.max(#shown, 1)
    for i, tab in ipairs(shown) do
        tab.button:ClearAllPoints()
        tab.button:SetPoint("TOPLEFT", frame, "TOPLEFT", pad + (i - 1) * w, -hdrH)
        tab.button:SetSize(w, TAB_H)
        tab.button:Show()
    end
end

local function CreateTabButton(tab, onClick)
    local btn = CreateFrame("Button", nil, frame)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetAllPoints()   -- as wide as the tab, centered: the label cannot drift with its own width
    btn.text:SetJustifyH("CENTER")
    btn.text:SetFontHeight(ns.FONT_NORMAL)
    btn.text:SetText(ns.L[tab.cfg.titleKey])
    btn.underline = btn:CreateTexture(nil, "ARTWORK")
    btn.underline:SetHeight(2)
    btn.underline:SetPoint("BOTTOMLEFT", 0, 0)
    btn.underline:SetPoint("BOTTOMRIGHT", 0, 0)
    btn.underline:SetColorTexture(unpack(ns.COL_ACCENT))
    btn:SetScript("OnEnter", function(self) if tab ~= active then self.text:SetTextColor(1, 1, 1) end end)
    btn:SetScript("OnLeave", function() PaintTabs() end)
    btn:SetScript("OnClick", function() onClick(tab) end)
    return btn
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function SelectTab(tab)
    if active and active ~= tab and active.pane then active.pane.Hide() end
    active = tab
    NightsFarmtrackerDB.filterTab = tab.key
    if not tab.pane then
        tab.pane = ns.CreateDropListPane(frame, tab.cfg, BODY_TOP)
        ns.RoundWindowLayout(frame)
    end
    tab.pane.Show()
    PaintTabs()
    tab.pane.Rebuild()
end

local function EnsureFrame()
    if frame then return end
    frame = ns.CreateWindowFrame("NightsFarmtrackerFilterWnd", ns.L["filter_button"], { width = ns.FRAME_W, dockChain = "right" })
    frame:SetPoint("TOPLEFT", ns.MainFrame, "TOPRIGHT", ns.WINDOW_GAP, 0)
    ns.FilterFrame = frame  -- other windows anchor to it

    ns.AddHLine(frame, "TOP", pad, -(hdrH - 1))
    ns.AddHLine(frame, "TOP", pad, -(BODY_TOP - 1))
    ns.EnableItemDrop(frame, function()
        if active and active.pane then active.pane.HandleDrop() end
    end)

    for _, tab in ipairs(tabs) do tab.button = CreateTabButton(tab, SelectTab) end
    ns.RoundWindowLayout(frame)   -- title and tab labels stay put while the list below changes height
end

-- Rebuilds the list of the shown tab (the others rebuild when opened)
function ns.RebuildFilterList()
    if frame and frame:IsShown() and active and active.pane then active.pane.Rebuild() end
end

-- After a tab's feature was switched on or off in Settings: the strip follows, and
-- a window on a tab that is gone moves to the next one or closes.
function ns.RefreshFilterTabs()
    if not frame then return end
    LayoutTabs()
    if not frame:IsShown() then return end
    local first = FirstEnabled()
    if not first then frame:Hide(); return end
    if active and IsEnabled(active) then PaintTabs() else SelectTab(first) end
end

-- Opens the window on a tab (by key; without one, or when that tab is switched
-- off, the tab used last), switches to it when the window is open on another
-- tab, closes it when it is already there. Without a key an open window closes.
function ns.ToggleFilterWindow(tabKey)
    local tab = byKey[tabKey or ""]
    if tab and not IsEnabled(tab) then tab, tabKey = nil, nil end
    if ns.DeferInCombat(function() ns.ToggleFilterWindow(tabKey) end) then return end
    if not tab then
        tab = byKey[NightsFarmtrackerDB.filterTab]
        if not (tab and IsEnabled(tab)) then tab = FirstEnabled() end
        if not tab then return end
    end
    EnsureFrame()
    if frame:IsShown() then
        if tabKey and active ~= tab then SelectTab(tab) else frame:Hide() end
    else
        LayoutTabs()
        SelectTab(tab)
        frame:Show()
    end
    ns.RefreshWindowChain("right")
end
