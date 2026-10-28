------------------------------------------------------------------------
-- Night's Farmtracker - Widgets
-- Shared UI building blocks: window docking, windows, buttons, list rows,
-- scroll helpers, and the copy-text window.
------------------------------------------------------------------------
local _, ns = ...

------------------------------------------------------------------------
-- After a drag WoW may report any anchor point of the frame ("RIGHT", ...),
-- which would make height changes grow it in both directions. Re-anchors it
-- to the TOP of the screen at the same spot and returns the offsets
-- (nothing while the frame has no position yet).
function ns.AnchorToTop(frame)
    local top, left, right = frame:GetTop(), frame:GetLeft(), frame:GetRight()
    local uiTop, uiWidth = UIParent:GetTop(), UIParent:GetWidth()
    if not (top and left and right and uiTop and uiWidth) then return end
    local x, y = (left + right) / 2 - uiWidth / 2, top - uiTop
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", x, y)
    return x, y
end

local function DockStacked(frame, anchor, edge)
    local height       = frame:GetHeight() or 0
    local screenTop    = UIParent:GetTop()
    local anchorBottom = anchor:GetBottom()
    local anchorTop    = anchor:GetTop()
    local noRoomBelow  = anchorBottom and UIParent:GetBottom() and (anchorBottom - 1 - height) < UIParent:GetBottom()
    local roomAbove    = anchorTop and screenTop and (anchorTop + 1 + height) <= screenTop
    if noRoomBelow and roomAbove then
        frame:SetPoint("BOTTOM" .. edge, anchor, "TOP" .. edge, 0, 1)
    else
        frame:SetPoint("TOP" .. edge, anchor, "BOTTOM" .. edge, 0, -1)
    end
end

-- Docks `frame` to the left or right of `anchor`. Without room on screen in
-- that direction it docks below the anchor, or above it when the screen bottom
-- is too close (windows are clamped to the screen, so a "below" without room
-- would slide up over the anchor). Call it after the frame has its final
-- height.
function ns.DockFrame(frame, anchor, side)
    frame:ClearAllPoints()
    local width       = frame:GetWidth() or ns.FRAME_W
    local screenLeft  = UIParent:GetLeft()
    local screenRight = UIParent:GetRight()
    if side == "left" then
        local anchorLeft = anchor:GetLeft()
        if anchorLeft and screenLeft and (anchorLeft - 1 - width) < screenLeft then
            DockStacked(frame, anchor, "RIGHT")
        else
            frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -1, 0)
        end
    else
        local anchorRight = anchor:GetRight()
        if anchorRight and screenRight and (anchorRight + 1 + width) > screenRight then
            DockStacked(frame, anchor, "LEFT")
        else
            frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 1, 0)
        end
    end
end

------------------------------------------------------------------------
-- Docking chains: every window that docks next to MainFrame is registered here
-- by name. ns.RefreshWindowChain walks a chain and re-docks each shown window
-- behind the previous one (MainFrame -> first shown -> next shown ...), so the
-- layout never overlaps whatever the opening order, and no circular anchors
-- can arise. Session Detail anchors to HistFrame directly instead of joining
-- a chain.
--
-- To add a window: expose ns.<Key>Frame, add "<Key>Frame" to a chain below and
-- call ns.RefreshWindowChain(side) after showing or hiding it.
------------------------------------------------------------------------
ns.WINDOW_CHAINS = {
    right = { "LogFrame", "FilterFrame", "BlacklistFrame", "GoalsFrame" },
    left  = { "HistFrame", "SettingsFrame", "ExportPickFrame", "ExportFrame", "DebugFrame" },
}

function ns.RefreshWindowChain(side)
    local order = ns.WINDOW_CHAINS[side]
    if not order then return end
    local prev = ns.MainFrame
    for _, key in ipairs(order) do
        local f = ns[key]
        -- Log docks BELOW MainFrame while collapsed - it sits outside the
        -- horizontal chain in that state, so it is skipped as a link.
        local collapsedLog = key == "LogFrame" and NightsFarmtrackerDB and NightsFarmtrackerDB.expanded == false
        if f and f:IsShown() and not collapsedLog then
            ns.DockFrame(f, prev, side)
            prev = f
        end
    end
end

------------------------------------------------------------------------
-- Icon badge helper — overlay on the bottom-right corner of the item icon
-- (used for crafting-reagent rank icons R1/R2/R3). Shared by every frame
-- that shows item icons, so the badge position/size stays identical.
-- It sits on the icon itself, so item names anchor to the icon's RIGHT and
-- no horizontal space is reserved for it.
------------------------------------------------------------------------
function ns.CreateIconBadge(parent, icon)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    fs:SetFontHeight(ns.FONT_SMALL)
    fs:SetJustifyH("RIGHT")
    return fs
end

------------------------------------------------------------------------
-- Row appearance helper — icon border + name color by item quality.
-- Shared by all item rows (main HUD, history detail, filter list, log)
-- so the "look" lives in one place instead of being duplicated per file.
------------------------------------------------------------------------
function ns.ApplyQualityColor(nameText, iconBorder, quality, fallbackColor)
    if quality then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        nameText:SetTextColor(r, g, b)
        iconBorder:SetColorTexture(r, g, b, 0.9)
        iconBorder:Show()
    else
        local fr, fg, fb = unpack(fallbackColor or {1, 1, 1})
        nameText:SetTextColor(fr, fg, fb)
        iconBorder:Hide()
    end
end

------------------------------------------------------------------------
-- 1 px line in the theme border color across the frame, `pad` in from both
-- sides and `offset` down (negative) or up (positive) from its top/bottom
-- edge: window title and footer separators. edge is "TOP" or "BOTTOM".
------------------------------------------------------------------------
function ns.AddHLine(frame, edge, pad, offset)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(unpack(ns.COL_BORDER))
    line:SetPoint(edge .. "LEFT",  pad,  offset)
    line:SetPoint(edge .. "RIGHT", -pad, offset)
    return line
end

------------------------------------------------------------------------
-- Row furniture: a bottom separator line (Export picker rows) and the item
-- icon plus its quality border shared by the HUD, History, Log and the drop
-- lists (the caller anchors the icon).
------------------------------------------------------------------------
function ns.AddRowSeparator(row, r, g, b, a)
    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(r or 0.12, g or 0.22, b or 0.25, a or 0.5)
    sep:SetPoint("BOTTOMLEFT"); sep:SetPoint("BOTTOMRIGHT")
    row.sep = sep
    return sep
end

function ns.AddRowIcon(row)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ns.ICON_SIZE, ns.ICON_SIZE)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon
    local border = row:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    border:Hide()
    row.iconBorder = border
    return icon
end

------------------------------------------------------------------------
-- Pool of reusable frames / font strings, so list rebuilds don't leak new
-- widgets. create(parent) builds a fresh one; reset(obj) (optional) clears
-- per-use state (scripts, texts, stored data) when it goes back.
--   pool.acquire(parent)  reuse (re-parented, shown) or create
--   pool.release(obj)     hide, unanchor, reset, keep for reuse
--   pool.releaseAll(list) release every object of an active list and empty it
------------------------------------------------------------------------
function ns.NewPool(create, reset)
    local free, pool = {}, {}
    function pool.acquire(parent)
        local obj = table.remove(free)
        if not obj then return create(parent) end
        if obj:GetParent() ~= parent then obj:SetParent(parent) end
        obj:Show()
        return obj
    end
    function pool.release(obj)
        obj:Hide(); obj:ClearAllPoints()
        if reset then reset(obj) end
        free[#free + 1] = obj
    end
    function pool.releaseAll(list)
        for i = #list, 1, -1 do
            pool.release(list[i])
            list[i] = nil
        end
    end
    return pool
end

-- StaticPopup with OK/Cancel and the addon's usual settings; onAccept(dialog,
-- data) runs on OK. `extra` adds or overrides dialog fields (e.g. hideOnEscape).
function ns.RegisterConfirmDialog(name, text, onAccept, extra)
    local dialog = {
        text = text, button1 = OKAY, button2 = CANCEL, OnAccept = onAccept,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    for k, v in pairs(extra or {}) do dialog[k] = v end
    StaticPopupDialogs[name] = dialog
end

------------------------------------------------------------------------
-- Header band (category, month and day rows of every list): gradient/flat
-- background plus a top and a bottom line. Creates frame.bg, frame.topSep and
-- frame.bottomSep; the caller adds its own texts and sets the size.
------------------------------------------------------------------------
function ns.AddHeaderBand(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ns.PaintCatBg(bg)
    frame.bg = bg

    local top = frame:CreateTexture(nil, "ARTWORK")
    top:SetHeight(1)
    top:SetColorTexture(unpack(ns.COL_BORDER))
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    frame.topSep = top

    local bottom = frame:CreateTexture(nil, "ARTWORK")
    bottom:SetHeight(1)
    bottom:SetColorTexture(unpack(ns.COL_BORDER))
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    frame.bottomSep = bottom
    return frame
end

-- For pooled rows that are a header only some of the time.
function ns.ShowHeaderBand(frame, shown)
    frame.bg:SetShown(shown); frame.topSep:SetShown(shown); frame.bottomSep:SetShown(shown)
    if frame.headerArrow and not shown then frame.headerArrow:Hide() end
end

-- Collapse/expand arrow at the left of a collapsible header. Header texts
-- start at ns.HEADER_TEXT_X, right of it.
ns.HEADER_ARROW_SIZE = 10
ns.HEADER_TEXT_X     = 4 + ns.HEADER_ARROW_SIZE + 4
function ns.SetHeaderArrow(frame, collapsed)
    local arrow = frame.headerArrow
    if not arrow then
        arrow = frame:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(ns.HEADER_ARROW_SIZE, ns.HEADER_ARROW_SIZE)
        arrow:SetPoint("LEFT", 4, 0)
        frame.headerArrow = arrow
    end
    arrow:SetTexture(ns.ART .. (collapsed and "btn_arrow_right.png" or "btn_arrow_down.png"))
    arrow:SetVertexColor(unpack(ns.COL_ACCENT))
    arrow:Show()
end

-- Exactly one line between neighbouring headers: a header skips its top line
-- when a line already sits right above it (the window's title separator, or
-- the previous header's bottom line). Create one per list build, call
-- flow.header(frame) for every header in order and flow.rows() once rows were
-- placed below a header. afterLine (default true) says whether a line sits
-- above the first header. flow.after can be saved and restored when a header
-- is dropped again.
function ns.NewHeaderFlow(afterLine)
    local flow = { after = afterLine ~= false }
    function flow.header(frame)
        frame.topSep:SetShown(not flow.after)
        flow.after = true
    end
    function flow.rows() flow.after = false end
    return flow
end

-- Footer separator of a list window: not needed while the list ends in a
-- header (its bottom line already sits right above) and nothing scrolls out
-- behind it. showAnyway covers scrolling lists and empty/collapsed states.
-- atEnd (scroll position, see ns.ScrolledToEnd) drops it again once a
-- scrolling list sits flush on its last header.
function ns.SetFooterLine(sep, flow, showAnyway, atEnd)
    sep:SetShown(not flow.after or (showAnyway and not atEnd))
end

function ns.ScrolledToEnd(scroll, list)
    return scroll:GetVerticalScroll() >= list:GetHeight() - scroll:GetHeight() - 1.5
end

------------------------------------------------------------------------
-- Small red close "x": dimmed until hovered. With `tooltip` (text) it also
-- shows that on hover.
------------------------------------------------------------------------
function ns.CreateCloseButton(parent, size, idleAlpha, tooltip)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(ns.ART .. "btn_close.png")
    btn.tex:SetAlpha(idleAlpha)
    btn:SetScript("OnEnter", function(self)
        self.tex:SetAlpha(1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.tex:SetAlpha(idleAlpha)
        if tooltip then GameTooltip:Hide() end
    end)
    return btn
end

------------------------------------------------------------------------
-- Dim-red text link at the bottom right of a window ("Clear all", "Reset
-- all"), bright red on hover; its width follows the text so no language
-- cuts it off.
------------------------------------------------------------------------
function ns.CreateDangerLink(parent, pad, text, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("BOTTOMRIGHT", -pad, 6)
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetJustifyH("RIGHT"); lbl:SetText(text)
    lbl:SetTextColor(0.50, 0.22, 0.22)
    btn:SetSize(math.max(70, math.ceil(lbl:GetStringWidth()) + 4), 18)
    lbl:SetAllPoints()
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function() lbl:SetTextColor(1, 0.4, 0.4) end)
    btn:SetScript("OnLeave", function() lbl:SetTextColor(0.50, 0.22, 0.22) end)
    return btn
end

-- "Clear all" link: hasDataFn guards against asking about an empty list.
function ns.CreateClearAllButton(parent, pad, hasDataFn, popupName)
    return ns.CreateDangerLink(parent, pad, ns.L["clear_all"], function()
        if hasDataFn() then StaticPopup_Show(popupName) end
    end)
end

------------------------------------------------------------------------
-- Mouse-wheel handler for a ScrollFrame: scrolls `scroll` by `step` pixels
-- per wheel notch, clamped to the height of its scroll child. Shared by
-- every scrolling window so the clamp logic lives in one place; assign the
-- result to OnMouseWheel of the ScrollFrame (and of its child / rows, so
-- scrolling also works while hovering them).
------------------------------------------------------------------------
function ns.MakeWheelHandler(scroll, child, step)
    return function(_, delta)
        local maxS = math.max(0, child:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScroll() - delta * step, maxS)))
    end
end

------------------------------------------------------------------------
-- Window height rule shared by every list window: header + list + footer
-- grows with the content up to ns.GetMaxWindowH() in total, then the list
-- scrolls.
--
-- ns.VisibleListHeight(contentH, hdrH, ftrH [, maxTotal]) -> visible list
-- height (pure calculation, for windows that size themselves).
--
-- ns.FitScrollWindow(cfg) sizes a whole window and returns visH:
--   window, scroll    frames (scroll = the ScrollFrame inside the window)
--   list              scroll child, gets the content height (optional)
--   hdrH, ftrH        space above/below the list inside the window
--   contentH          full height of the list content
--   minH              minimum visible list height (optional)
--   maxTotal          total window cap, default ns.GetMaxWindowH() (optional)
--   anchored          true if the scroll frame is anchored top AND bottom
--                     to the window, so only the window height is set
-- The scroll offset is clamped so shrinking content never leaves it
-- scrolled past the end.
------------------------------------------------------------------------
function ns.VisibleListHeight(contentH, hdrH, ftrH, maxTotal)
    local maxVis = (maxTotal or ns.GetMaxWindowH()) - hdrH - ftrH
    return math.min(math.max(1, contentH), maxVis)
end

function ns.FitScrollWindow(cfg)
    local contentH = math.max(1, cfg.contentH)
    local visH = ns.VisibleListHeight(contentH, cfg.hdrH, cfg.ftrH, cfg.maxTotal)
    if cfg.minH then visH = math.max(cfg.minH, visH) end
    if cfg.list then cfg.list:SetHeight(contentH) end
    if not cfg.anchored then cfg.scroll:SetHeight(visH) end
    cfg.window:SetHeight(cfg.hdrH + visH + cfg.ftrH)
    cfg.scroll:SetVerticalScroll(math.min(cfg.scroll:GetVerticalScroll(), math.max(0, contentH - visH)))
    return visH
end

------------------------------------------------------------------------
-- Custom icon button (texture from the Media folder): dimmed until
-- hovered, nudged while pressed. Shared by the main window and the
-- Venom Tracker / Fishing Lure Bar overlays.
------------------------------------------------------------------------
-- Toolbar icon tint. The icon PNGs are white; they are tinted gray by
-- default, or with the active theme's accent color when the "themedButtons"
-- option is on.
ns.BTN_GRAY = {115/255, 115/255, 115/255}
local tintTextures = {}

function ns.ApplyButtonTint(tex)
    local db = NightsFarmtrackerDB
    local c = (db and db.themedButtons == true and ns.COL_ACCENT) or ns.BTN_GRAY
    if tex.SetVertexColor then tex:SetVertexColor(c[1], c[2], c[3])
    else tex:SetTextColor(c[1], c[2], c[3]) end  -- FontString (header watermark)
end

function ns.RegisterTintTex(tex)
    tintTextures[#tintTextures + 1] = tex
    ns.ApplyButtonTint(tex)
end

function ns.RefreshButtonTint()
    for _, tex in ipairs(tintTextures) do ns.ApplyButtonTint(tex) end
end

function ns.MakeBtn(parent, size, artFile)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetAllPoints()
    btn.tex:SetTexture(ns.ART .. artFile)
    btn.tex:SetAlpha(0.75)
    -- Close keeps its own red artwork; every other icon is white artwork
    -- tinted gray (default) or with the theme accent (see ns.ApplyButtonTint).
    if artFile ~= "btn_close.png" then ns.RegisterTintTex(btn.tex) end
    btn:SetScript("OnMouseDown", function(self)
        self.tex:ClearAllPoints()
        self.tex:SetSize(size - 3, size - 3)
        self.tex:SetPoint("CENTER", 1, -1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self.tex:ClearAllPoints(); self.tex:SetAllPoints()
    end)
    btn:SetScript("OnEnter", function(self) self.tex:SetAlpha(1.0) end)
    btn:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.75) end)
    return btn
end

------------------------------------------------------------------------
-- Hides GameTooltip if it belongs to `frame` or one of its children. A frame
-- that is hidden while the mouse is over one of its rows never gets that
-- row's OnLeave, so the tooltip would otherwise linger after closing.
------------------------------------------------------------------------
function ns.HideTooltipOf(frame)
    if not GameTooltip:IsShown() then return end
    local owner = GameTooltip:GetOwner()
    while owner do
        if owner == frame then GameTooltip:Hide(); return end
        owner = owner:GetParent()
    end
end

------------------------------------------------------------------------
-- Window shell shared by every top-level window: border and background,
-- movable, clamped to the screen, closable with ESC, title text and close
-- button. Callers add their content below the header and can hook extra close
-- behavior via frame:SetScript("OnHide", ...) or
-- frame.closeBtn:HookScript("OnClick", ...). opts (all optional): width, pad
-- (default ns.PAD), titleColor (default ns.COL_GOLD), titleY (default -10).
------------------------------------------------------------------------
function ns.CreateWindowFrame(name, title, opts)
    opts = opts or {}
    local pad = opts.pad or ns.PAD

    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:HookScript("OnHide", function(self) ns.HideTooltipOf(self) end)
    if opts.width then frame:SetWidth(opts.width) end
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:EnableMouseWheel(true)   -- the wheel must not scroll whatever lies behind the window (chat, ...)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    frame:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    ns.ApplyFrameStyle(frame)
    frame:Hide()
    table.insert(UISpecialFrames, name)

    local titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleFS:SetPoint("TOPLEFT", pad, opts.titleY or -10)
    titleFS:SetPoint("TOPRIGHT", -pad, opts.titleY or -10)
    titleFS:SetJustifyH("CENTER")
    titleFS:SetText(title)
    titleFS:SetTextColor(unpack(opts.titleColor or ns.COL_GOLD))
    titleFS:SetFontHeight(ns.FONT_HEADER)
    frame.titleFS = titleFS

    local xBtn = ns.CreateCloseButton(frame, 18, 0.8)
    xBtn:SetPoint("TOPRIGHT", -pad, opts.titleY or -10)
    xBtn:SetScript("OnClick", function()
        if not ns.DeferInCombat(function() frame:Hide() end) then frame:Hide() end
    end)
    frame.closeBtn = xBtn

    return frame
end

------------------------------------------------------------------------
-- Small movable overlay (Venom Tracker, Fishing Lure Bar): styled, clamped,
-- hidden at first. Dragging saves db[posKey] = { "TOP", x, y } (anchored to
-- the screen top, see ns.AnchorToTop); the X button calls onClose. The caller
-- sets size, position and content.
------------------------------------------------------------------------
function ns.CreateOverlayFrame(name, posKey, onClose)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)   -- see CreateWindowFrame
    frame:RegisterForDrag("LeftButton")
    ns.ApplyFrameStyle(frame)
    frame:Hide()
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = ns.AnchorToTop(self)
        if x then NightsFarmtrackerDB[posKey] = { "TOP", x, y } end
    end)

    frame.closeButton = ns.MakeBtn(frame, 14, "btn_close.png")
    frame.closeButton:SetPoint("TOPRIGHT", -4, -4)
    frame.closeButton:SetScript("OnClick", onClose)
    return frame
end

------------------------------------------------------------------------
-- Frame style helper — square 1px border, dark teal background.
-- Used by all windows (main, history, detail, settings).
------------------------------------------------------------------------
function ns.ApplyFrameStyle(frame)
    frame:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        tile     = true, tileSize = 16,
        insets   = {left=0, right=0, top=0, bottom=0},
    })
    frame:SetBackdropColor(unpack(ns.COL_BG))
    -- Draw 1px square border as four colored textures. Tracked on the frame
    -- so ns.RefreshFrameStyle() can recolor them later (needed for frames
    -- built before SavedVariables/theme are loaded, e.g. MainFrame).
    frame.nftEdges = frame.nftEdges or {}
    local function Edge(p1, p2, horiz)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(ns.COL_BORDER))
        if horiz then t:SetHeight(1) else t:SetWidth(1) end
        t:SetPoint(p1); t:SetPoint(p2)
        frame.nftEdges[#frame.nftEdges+1] = t
    end
    Edge("TOPLEFT",    "TOPRIGHT",    true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT",    "BOTTOMLEFT",  false)
    Edge("TOPRIGHT",   "BOTTOMRIGHT", false)
end

-- Re-applies the current theme colors to a frame already styled via
-- ApplyFrameStyle. Needed for MainFrame specifically: it's built while
-- UI.lua loads, which happens before SavedVariables/InitDB have set the
-- saved theme, so its border/background start out on the default colors.
-- Extra COL_BORDER-colored textures (e.g. header/footer separators) can be
-- added to frame.nftEdges by the caller so they get refreshed too.
function ns.RefreshFrameStyle(frame)
    if not frame or not frame.nftEdges then return end
    frame:SetBackdropColor(unpack(ns.COL_BG))
    for _, t in ipairs(frame.nftEdges) do
        t:SetColorTexture(unpack(ns.COL_BORDER))
    end
    if frame.nftAccentTexts then
        for _, fs in ipairs(frame.nftAccentTexts) do
            fs:SetTextColor(unpack(ns.COL_ACCENT))
        end
    end
end

------------------------------------------------------------------------
-- Gear AH Threshold alert sound. Looks for a user-supplied custom file
-- at Media\ThresholdAlert.ogg / .mp3 first; falls back to a built-in
-- SoundKit if neither is present in the addon folder.
------------------------------------------------------------------------
local THRESHOLD_SOUND_BASE = "Interface\\AddOns\\NightsFarmtracker\\Media\\ThresholdAlert"

function ns.PlayThresholdAlertSound()
    local willPlay = PlaySoundFile(THRESHOLD_SOUND_BASE .. ".ogg", "Master")
    if not willPlay then
        willPlay = PlaySoundFile(THRESHOLD_SOUND_BASE .. ".mp3", "Master")
    end
    if not willPlay then
        PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST, "Master")
    end
end

------------------------------------------------------------------------
-- Copyable text window: a scrolling, pre-selected EditBox (addons cannot write
-- the clipboard, so the player presses Ctrl+C). Shared by the data export and
-- the debug dumps. ns.CreateCopyTextWindow(name, title) builds it once;
-- ns.ShowCopyText(frame, text) fills and shows it, docked next to Settings if
-- that is open, else centered.
------------------------------------------------------------------------
function ns.CreateCopyTextWindow(name, title)
    local W, HDR_H, FTR_H = 460, ns.WINDOW_HDR_H, 12

    local frame = ns.CreateWindowFrame(name, title, {width = W, pad = ns.PAD, titleColor = ns.COL_ACCENT})
    frame:SetHeight(360)
    frame:SetScript("OnHide", function() ns.RefreshWindowChain("left") end)

    ns.AddHLine(frame, "TOP", ns.PAD, -(HDR_H - 1))

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", ns.PAD, -(HDR_H + 6))
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText(ns.L["copy_hint_window"])

    local selectBtn = CreateFrame("Button", nil, frame)
    selectBtn:SetSize(90, 16)
    selectBtn:SetPoint("TOPRIGHT", -ns.PAD, -(HDR_H + 6))
    local selectText = selectBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selectText:SetAllPoints(); selectText:SetJustifyH("RIGHT")
    selectText:SetTextColor(unpack(ns.COL_ACCENT))
    selectText:SetText(ns.L["export_select_all"])
    selectBtn:SetScript("OnEnter", function() selectText:SetTextColor(1, 1, 1) end)
    selectBtn:SetScript("OnLeave", function() selectText:SetTextColor(unpack(ns.COL_ACCENT)) end)
    selectBtn:SetScript("OnClick", function() frame.box:SetFocus(); frame.box:HighlightText() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", ns.PAD, -(HDR_H + 26))
    scrollFrame:SetPoint("BOTTOMRIGHT", -ns.PAD - 2, FTR_H)
    scrollFrame:EnableMouseWheel(true)

    local boxBG = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
    boxBG:SetAllPoints(scrollFrame)
    boxBG:SetFrameLevel(scrollFrame:GetFrameLevel())
    ns.StyleBackdropBox(boxBG, {0.05, 0.08, 0.09, 1})

    -- Multi-line EditBox left un-sized on height: with only its width set,
    -- it auto-grows to fit its text - exactly what a scroll child needs,
    -- no manual height bookkeeping on every SetText.
    local box = CreateFrame("EditBox", nil, scrollFrame)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextColor(0.85, 0.85, 0.85)
    box:SetWidth(W - ns.PAD * 2 - 24)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(box)

    scrollFrame:SetScript("OnMouseWheel", ns.MakeWheelHandler(scrollFrame, box, 22))

    frame.scrollFrame = scrollFrame
    frame.box = box
    return frame
end

-- Fills a window built by ns.CreateCopyTextWindow with `text` and shows
-- it (docked next to Settings if open, else centered), pre-selected for
-- an immediate Ctrl+C. `live` (the debug log): no focus/selection grab, so
-- the window can keep refreshing; the caller handles scrolling.
function ns.ShowCopyText(frame, text, live)
    frame.box:SetText(text)
    frame.scrollFrame:UpdateScrollChildRect()
    if not live then frame.scrollFrame:SetVerticalScroll(0) end
    frame:ClearAllPoints()
    if ns.SettingsFrame and ns.SettingsFrame:IsShown() then
        ns.DockFrame(frame, ns.SettingsFrame, "left")
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    if not live then
        frame.box:SetFocus()
        frame.box:HighlightText()
    end
    ns.RefreshWindowChain("left")
end
