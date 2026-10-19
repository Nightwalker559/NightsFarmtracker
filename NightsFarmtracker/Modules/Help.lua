------------------------------------------------------------------------
-- Night's Farmtracker - Help
-- The "?" button: a short hover tooltip and the full help window.
------------------------------------------------------------------------
local _, ns = ...

-- Hover shows only the essentials; clicking the button opens the full
-- info window (all sections, what Ctrl-click does, slash commands).
-- Built once at load time (static content) instead of on every hover.
local helpTipSections = {
    { title = ns.L["help_categories"], lines = { ns.L["help_cat_click"], ns.L["help_cat_rclick"] } },
    { title = ns.L["help_items"],      lines = { ns.L["help_item_ctrl_lclick"], ns.L["help_item_ctrl_rclick"], ns.L["help_item_rclick"] } },
}

local helpSections = {
    { title = ns.L["help_categories"], lines = { ns.L["help_cat_click"], ns.L["help_cat_rclick"] } },
    { title = ns.L["help_items"],      lines = { ns.L["help_item_hover"], ns.L["help_item_ctrl_lclick"], ns.L["help_item_ctrl_rclick"], ns.L["help_item_rclick"],
                                                 ns.L["help_detail_vendor"], ns.L["help_detail_blacklist"], ns.L["help_detail_undo"] } },
    { title = ns.L["help_gold"],       lines = { ns.L["help_gold_click"] } },
    { title = ns.L["help_reset"],      lines = { ns.L["help_reset_shift"] } },
    { title = ns.L["help_histlog"],    lines = { ns.L["help_histlog_left"], ns.L["help_histlog_right"] } },
    { title = ns.L["help_filter"],     lines = { ns.L["help_filter_left"], ns.L["help_filter_right"] } },
    { title = ns.L["help_fishing"],    lines = { ns.L["help_fishing_hint"] } },
    { title = ns.L["help_export"],     lines = { ns.L["help_export_hint"] } },
    { title = ns.L["help_commands"],   lines = { ns.L["help_cmd_nft"], ns.L["help_cmd_filter"], ns.L["help_cmd_hud"], ns.L["help_cmd_export"], ns.L["help_cmd_fishing"] } },
}
table.sort(helpSections, function(a,b) return a.title < b.title end)

local HelpFrame
local function BuildHelpText()
    local out = {}
    for _, section in ipairs(helpSections) do
        out[#out+1] = "|cffffffff" .. section.title .. "|r"
        for _, line in ipairs(section.lines) do out[#out+1] = "|cffb3b3b3" .. line .. "|r" end
        out[#out+1] = " "
    end
    return table.concat(out, "\n")
end

function ns.ToggleHelpWindow()
    if not HelpFrame then
        local W = 420
        HelpFrame = ns.CreateWindowFrame("NightsFarmtrackerHelpWnd", ns.L["help_detail_title"], {width = W, titleColor = ns.COL_ACCENT})
        HelpFrame:SetPoint("CENTER")
        -- Above the main window, Venom Tracker and Lure Bar (all MEDIUM) which it can overlap.
        HelpFrame:SetFrameStrata("HIGH")
        HelpFrame:SetToplevel(true)
        local hdrH = ns.WINDOW_HDR_H
        local sep = HelpFrame:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1); sep:SetColorTexture(unpack(ns.COL_BORDER))
        sep:SetPoint("TOPLEFT", ns.PAD, -(hdrH - 1)); sep:SetPoint("TOPRIGHT", -ns.PAD, -(hdrH - 1))
        -- The text scrolls once the window reaches ns.GetMaxHelpH()
        local textW  = W - 2 * ns.PAD
        local scroll = CreateFrame("ScrollFrame", nil, HelpFrame)
        scroll:SetPoint("TOPLEFT", ns.PAD, -(hdrH + 8))
        scroll:SetWidth(textW)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(textW)
        scroll:SetScrollChild(child)
        local fs = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT")
        fs:SetWidth(textW)
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
        fs:SetSpacing(2)
        fs:SetText(BuildHelpText())
        local textH = math.ceil(fs:GetStringHeight())
        HelpFrame.fit = function()
            ns.FitScrollWindow({
                window = HelpFrame, scroll = scroll, list = child,
                hdrH = hdrH + 8, ftrH = 8, contentH = textH,
                maxTotal = ns.GetMaxHelpH(),
            })
        end
        HelpFrame.fit()
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", ns.MakeWheelHandler(scroll, child, 24))
    end
    HelpFrame:SetShown(not HelpFrame:IsShown())
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
