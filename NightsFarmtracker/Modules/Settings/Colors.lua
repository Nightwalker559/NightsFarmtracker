------------------------------------------------------------------------
-- Night's Farmtracker - Settings: colors
-- Color theme dropdown with hover preview, custom accent color row and the
-- Colors section.
------------------------------------------------------------------------
local _, ns = ...
local K = ns.SettingsKit

local S_W, S_PAD, TITLE_STEP = K.S_W, K.S_PAD, K.TITLE_STEP
local MakeDropdownBox, MakePopupList, ToggleMenu = K.MakeDropdownBox, K.MakePopupList, K.ToggleMenu

local themeDropdown

-- Rows of the theme list (MakeThemeDropdown): an expandable list, unlike the TSM
-- cycle-button - there are enough themes that jumping straight to one beats
-- clicking through them one by one.
local THEME_ROW_H = 20

-- Miniature window (frame colors, header strip - flat or gradient depending
-- on the Header gradient option - accent text) used by the theme list's
-- hover preview and by the custom color row. :SetTheme() takes a theme
-- table (bg/border/catBg/accent).
local function MakeThemePreview(parent)
    local pv = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pv:SetSize(150, 40)
    pv:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Buttons/WHITE8x8", tile = true, tileSize = 8, edgeSize = 1,
        insets = {left = 1, right = 1, top = 1, bottom = 1}})
    pv.strip = pv:CreateTexture(nil, "BACKGROUND", nil, 1)
    pv.strip:SetPoint("TOPLEFT", 1, -1); pv.strip:SetPoint("TOPRIGHT", -1, -1)
    pv.strip:SetHeight(18)
    pv.head = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pv.head:SetPoint("LEFT", pv.strip, "LEFT", 5, 0)
    pv.head:SetText(ns.L["custom_preview_header"])
    pv.body = pv:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pv.body:SetPoint("BOTTOMLEFT", 5, 5)
    pv.body:SetTextColor(0.85, 0.85, 0.85)
    pv.body:SetText(ns.L["custom_preview_text"])

    function pv:SetTheme(t)
        self:SetBackdropColor(unpack(t.bg))
        self:SetBackdropBorderColor(unpack(t.border))
        self.head:SetTextColor(unpack(t.accent))
        if NightsFarmtrackerDB.headerGradient then
            local l, r = ns.CatGradient(t)
            self.strip:SetColorTexture(1, 1, 1, 1)
            self.strip:SetGradient("HORIZONTAL", CreateColor(unpack(l)), CreateColor(unpack(r)))
        else
            self.strip:SetColorTexture(unpack(t.catBg))
        end
    end
    return pv
end

-- Theme table for a key; "custom" reflects the saved custom color.
local function ThemeForKey(key)
    local c = NightsFarmtrackerDB.customAccent
    if key == "custom" and type(c) == "table" and c[1] and c[2] and c[3] then
        return ns.DeriveCustomTheme(c[1], c[2], c[3])
    end
    return ns.COLOR_THEMES[key] or ns.COLOR_THEMES.default
end

local function MakeThemeDropdown(parent, yOff)
    local frame = MakeDropdownBox(parent, S_W - S_PAD*2 - 40)
    frame:SetPoint("TOPLEFT", S_PAD, yOff)

    local list = MakePopupList()

    -- The rows sit in a scroll area: with 17 themes the list is taller than
    -- the space below the dropdown on many screens.
    local listW = S_W - S_PAD*2 - 40 - 4
    local scroll, content, onWheel = ns.CreateScrollList(list, listW, THEME_ROW_H)
    scroll:SetPoint("TOPLEFT", 2, -2); scroll:SetPoint("BOTTOMRIGHT", -2, 2)
    content:SetSize(listW, THEME_ROW_H * #ns.COLOR_THEME_ORDER)

    -- Hover preview: floats beside the list next to the hovered entry
    local popup = MakeThemePreview(UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:Hide()
    list:SetScript("OnHide", function() popup:Hide() end)

    local function ThemeLabel(theme)
        local name = ns.L[theme.labelKey] or theme.name
        local desc = theme.descKey and ns.L[theme.descKey]
        return desc and (name.." ("..desc..")") or name
    end

    list.rows = {}
    for i, key in ipairs(ns.COLOR_THEME_ORDER) do
        local theme = ns.COLOR_THEMES[key]
        local row = CreateFrame("Button", nil, content)
        row:SetSize(listW, THEME_ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i-1)*THEME_ROW_H)
        row:EnableMouseWheel(true)   -- the wheel scrolls the list also over a row
        row:SetScript("OnMouseWheel", onWheel)
        -- Color chips (frame border, header, accent) as a quick glance
        row.chips = {}
        for ci = 1, 3 do
            local chip = row:CreateTexture(nil, "ARTWORK")
            chip:SetSize(8, 12)
            chip:SetPoint("LEFT", 6 + (ci-1)*9, 0)
            row.chips[ci] = chip
        end
        function row:PaintChips()
            local t = ThemeForKey(key)
            self.chips[1]:SetColorTexture(t.border[1], t.border[2], t.border[3], 1)
            self.chips[2]:SetColorTexture(t.catBg[1], t.catBg[2], t.catBg[3], 1)
            self.chips[3]:SetColorTexture(t.accent[1], t.accent[2], t.accent[3], 1)
        end
        row:PaintChips()
        row.txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.txt:SetPoint("LEFT", 6 + 3*9 + 4, 0)
        row.txt:SetText(ThemeLabel(theme))
        row.txt:SetTextColor(0.85,0.85,0.85)
        row:SetScript("OnEnter", function()
            row.txt:SetTextColor(1,1,1)
            popup:SetTheme(ThemeForKey(key))
            popup:ClearAllPoints()
            if (list:GetRight() or 0) + 170 > UIParent:GetWidth() then
                popup:SetPoint("RIGHT", row, "LEFT", -8, 0)
            else
                popup:SetPoint("LEFT", row, "RIGHT", 8, 0)
            end
            popup:Show()
        end)
        row:SetScript("OnLeave", function() row.txt:SetTextColor(0.85,0.85,0.85); popup:Hide() end)
        row:SetScript("OnClick", function()
            local db = NightsFarmtrackerDB
            db.colorTheme = key
            -- First pick of "Custom": start from the current accent color
            if key == "custom" and type(db.customAccent) ~= "table" then
                local a = ns.COL_ACCENT
                db.customAccent = {a[1], a[2], a[3]}
            end
            list:Hide()
            frame:Refresh()
            StaticPopup_Show("NFT_RELOAD")
        end)
        list.rows[i] = row
    end
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function()
        ToggleMenu(list, frame, function()
            for _, r in ipairs(list.rows) do r:PaintChips() end  -- custom color may have changed
            -- as many rows as fit between the dropdown and the screen bottom (at least 5)
            local bottom = (tonumber(frame:GetBottom()) or 0) * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local fit = math.floor((bottom - 16 - 4) / THEME_ROW_H)
            list:SetHeight(4 + THEME_ROW_H * math.max(5, math.min(#ns.COLOR_THEME_ORDER, fit)))
            scroll:SetVerticalScroll(0)
        end)
    end)

    function frame:Refresh()
        local key   = NightsFarmtrackerDB.colorTheme or "default"
        local theme = ns.COLOR_THEMES[key] or ns.COLOR_THEMES.default
        self.lbl:SetText(ThemeLabel(theme))
    end

    return frame
end

------------------------------------------------------------------------
-- Helper: custom accent color row (Colors section). A swatch opens the
-- Blizzard color picker; the other theme colors are derived from the pick
-- (ns.DeriveCustomTheme). Next to it a small preview frame shows the
-- resulting window/header colors - it updates live while dragging in the
-- picker, but the choice is only saved when the picker is confirmed (OK),
-- followed by the usual reload prompt.
------------------------------------------------------------------------
local customColorRow
local pickerCommit
local pickerHooked

local function MakeCustomColorRow(parent, themeDropdownRef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(S_W - S_PAD*2 - 40, 44)

    row.lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.lbl:SetPoint("LEFT", 0, 0)
    row.lbl:SetTextColor(0.85, 0.85, 0.85)
    row.lbl:SetText(ns.L["custom_color_label"])

    local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
    swatch:SetSize(24, 24)
    swatch:SetPoint("LEFT", row.lbl, "RIGHT", 8, 0)
    ns.StyleBackdropBox(swatch)
    swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
    swatch.tex:SetPoint("TOPLEFT", 2, -2); swatch.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    row.swatch = swatch

    local pv = MakeThemePreview(row)
    pv:SetPoint("LEFT", swatch, "RIGHT", 14, 0)
    row.preview = pv

    function row:SetPreview(r, g, b)
        swatch.tex:SetColorTexture(r, g, b, 1)
        pv:SetTheme(ns.DeriveCustomTheme(r, g, b))
    end

    local function SavedColor()
        local c = NightsFarmtrackerDB.customAccent
        if type(c) == "table" and c[1] and c[2] and c[3] then return c[1], c[2], c[3] end
        local a = ns.COL_ACCENT
        return a[1], a[2], a[3]
    end

    function row:Refresh()
        self:SetPreview(SavedColor())
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = SavedColor()
        local pending
        local function onChange()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            pending = {nr, ng, nb}
            row:SetPreview(nr, ng, nb)
        end
        pickerCommit = function()
            -- Another addon may have reused the picker in the meantime
            if ColorPickerFrame.swatchFunc ~= onChange or not pending then return end
            local db = NightsFarmtrackerDB
            local old = db.customAccent
            local same = db.colorTheme == "custom" and type(old) == "table"
                and math.abs(old[1] - pending[1]) < 0.002
                and math.abs(old[2] - pending[2]) < 0.002
                and math.abs(old[3] - pending[3]) < 0.002
            db.customAccent = pending
            db.colorTheme   = "custom"
            if themeDropdownRef then themeDropdownRef:Refresh() end
            row:Refresh()
            if not same then StaticPopup_Show("NFT_RELOAD") end
        end
        if not pickerHooked then
            pickerHooked = true
            ColorPickerFrame:HookScript("OnHide", function()
                local fn = pickerCommit
                pickerCommit = nil
                if fn then fn() end
            end)
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = onChange,
            cancelFunc = function() pending = nil; row:Refresh() end,
        })
    end)

    return row
end

------------------------------------------------------------------------
-- Section: Colors (theme, custom color, header gradient, button tint)
------------------------------------------------------------------------
K.AddSection("sec_colors", function(y, ui)
    local track, sectionTitle, flag, place = ui.track, ui.sectionTitle, ui.flag, ui.place
    y = sectionTitle(y, "sec_colors", TITLE_STEP)

    themeDropdown = place(themeDropdown, MakeThemeDropdown, y)
    themeDropdown:Refresh()
    track(themeDropdown, "other")
    y = y - 32

    customColorRow = place(customColorRow, function(parent) return MakeCustomColorRow(parent, themeDropdown) end, y)
    customColorRow:Refresh()
    track(customColorRow, "other")
    y = y - 52

    y = flag(y, "header_gradient", "headerGradient", false, function()
        customColorRow:Refresh()
        StaticPopup_Show("NFT_RELOAD")
    end)
    y = flag(y, "themed_buttons", "themedButtons", false, function() ns.RefreshButtonTint() end)

    return y
end)
