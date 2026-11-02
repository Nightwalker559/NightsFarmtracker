------------------------------------------------------------------------
-- Night's Farmtracker - Help
-- The "?" button: a short hover tooltip and the full help window.
------------------------------------------------------------------------
local _, ns = ...

-- Hover shows only the essentials; clicking the button opens the full
-- info window (all sections, what Ctrl-click does, slash commands).
-- Built once at load time (static content) instead of on every hover.
local categoriesSection = { title = ns.L["help_categories"], lines = { ns.L["help_cat_click"], ns.L["help_cat_rclick"] } }

local helpTipSections = {
    categoriesSection,
    { title = ns.L["help_items"],      lines = { ns.L["help_item_ctrl_lclick"], ns.L["help_item_ctrl_rclick"], ns.L["help_item_rclick"] } },
}

local helpSections = {
    categoriesSection,
    { title = ns.L["help_items"],      lines = { ns.L["help_item_hover"], ns.L["help_item_ctrl_lclick"], ns.L["help_item_ctrl_rclick"], ns.L["help_item_rclick"],
                                                 ns.L["help_detail_vendor"], ns.L["help_detail_blacklist"], ns.L["help_detail_lists"] } },
    { title = ns.L["help_gold"],       lines = { ns.L["help_gold_click"] } },
    { title = ns.L["help_reset"],      lines = { ns.L["help_reset_shift"] } },
    { title = ns.L["help_histlog"],    lines = { ns.L["help_histlog_left"], ns.L["help_histlog_right"] } },
    { title = ns.L["help_filter"],     lines = { ns.L["help_filter_left"], ns.L["help_filter_right"], ns.L["help_filter_sell"] } },
    { title = ns.L["help_fishing"],    lines = { ns.L["help_fishing_hint"] } },
    { title = ns.L["help_export"],     lines = { ns.L["help_export_hint"] } },
    { title = ns.L["help_commands"],   lines = { ns.L["help_cmd_nft"], ns.L["help_cmd_filter"], ns.L["help_cmd_hud"], ns.L["help_cmd_export"], ns.L["help_cmd_fishing"] } },
    -- Explanations the settings window leaves out; its "?" buttons open them (ns.OpenHelpTopic)
    { key = "limit",  title = ns.L["help_set_limit"], lines = { ns.L["help_set_limit_length"], ns.L["help_set_limit_goals"],
                                                                ns.L["help_set_limit_general"], ns.L["help_set_limit_vendor"] } },
    { key = "gearah", title = ns.L["help_set_gear"],  lines = { ns.L["help_set_gear_text"] } },
}
table.sort(helpSections, function(a,b) return a.title < b.title end)

local function SectionText(section)
    local out = { "|cffffffff" .. section.title .. "|r" }
    for _, line in ipairs(section.lines) do out[#out+1] = "|cffb3b3b3" .. line .. "|r" end
    out[#out+1] = " "
    return table.concat(out, "\n")
end

local HelpFrame, helpScroll
local topicY = {}   -- section key -> offset of the section in the scrolled text

local function EnsureHelpFrame()
    if HelpFrame then return end
    local W = 420
    HelpFrame = ns.CreateWindowFrame("NightsFarmtrackerHelpWnd", ns.L["help_detail_title"], {width = W})
    HelpFrame:SetPoint("CENTER")
    -- Above the main window, Venom Tracker and Lure Bar (all MEDIUM) which it can overlap.
    HelpFrame:SetFrameStrata("HIGH")
    HelpFrame:SetToplevel(true)
    local hdrH = ns.WINDOW_HDR_H
    ns.AddHLine(HelpFrame, "TOP", ns.PAD, -(hdrH - 1))
    -- The text scrolls once the window reaches ns.GetMaxHelpH()
    local textW  = W - 2 * ns.PAD
    local scroll, child = ns.CreateScrollList(HelpFrame, textW, 24)
    helpScroll = scroll
    scroll:SetPoint("TOPLEFT", ns.PAD, -(hdrH + 8))
    scroll:SetWidth(textW)
    -- One text per section, stacked, so a topic's offset is known
    local textH = 0
    for _, section in ipairs(helpSections) do
        local fs = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", 0, -textH)
        fs:SetWidth(textW)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
        fs:SetSpacing(2)
        fs:SetText(SectionText(section))
        if section.key then topicY[section.key] = textH end
        textH = textH + math.ceil(fs:GetStringHeight()) + 2
    end
    HelpFrame.fit = function()
        ns.FitScrollWindow({
            window = HelpFrame, scroll = scroll, list = child,
            hdrH = hdrH + 8, ftrH = 8, contentH = textH,
            maxTotal = ns.GetMaxHelpH(),
        })
    end
    HelpFrame.fit()
end

function ns.ToggleHelpWindow()
    if ns.DeferInCombat(ns.ToggleHelpWindow) then return end
    EnsureHelpFrame()
    HelpFrame:SetShown(not HelpFrame:IsShown())
end

-- Opens the window scrolled to one section (the "?" buttons of the settings).
function ns.OpenHelpTopic(key)
    if ns.DeferInCombat(function() ns.OpenHelpTopic(key) end) then return end
    EnsureHelpFrame()
    HelpFrame:Show()
    -- the scroll range is only known once the window has been laid out
    RunNextFrame(function()
        helpScroll:SetVerticalScroll(math.min(topicY[key] or 0, helpScroll:GetVerticalScrollRange()))
    end)
end

-- Re-fit the (already built) Help window after the max window height changed
function ns.RefitHelpWindow()
    if HelpFrame and HelpFrame.fit then HelpFrame.fit() end
end

-- Tooltip lines for the "?" button (see SetBtnTooltip in Core/UI.lua).
function ns.FillHelpTooltip(tip)
    tip:AddLine(ns.L["help_title"], unpack(ns.COL_ACCENT))
    tip:AddLine(" ")
    for _, section in ipairs(helpTipSections) do
        tip:AddLine(section.title, 1, 1, 1)
        for _, line in ipairs(section.lines) do
            tip:AddLine(line, 0.7, 0.7, 0.7)
        end
    end
    tip:AddLine(" ")
    tip:AddLine(ns.L["help_more"], unpack(ns.COL_ACCENT))
end
