------------------------------------------------------------------------
-- Night's Farmtracker - Minimap button
-- Minimap button and Addon Compartment entry, without libraries.
------------------------------------------------------------------------
local _, ns = ...
local ART = ns.ART

------------------------------------------------------------------------
-- Minimap button without a library: left click toggles the main window, right
-- click the settings, drag moves it (angle in db.minimap.minimapPos). Named
-- like a LibDBIcon button ("LibDBIcon10_<name>" with .icon / .border /
-- .background) so button collectors (LuckyoneUI, MinimapButtonButton ...) pick
-- it up.
------------------------------------------------------------------------
local mmButton

-- Places the button on the minimap edge at `angle` degrees (0 = right,
-- counterclockwise); square minimaps (ElvUI) get it on the square edge.
local function PlaceMinimapButton(angle)
    if not mmButton then return end
    -- A collector moved the button into its own bar: leave the layout to it.
    if mmButton:GetParent() ~= Minimap then return end
    local rad = math.rad(angle)
    local dx, dy = math.cos(rad), math.sin(rad)
    local half = Minimap:GetWidth() / 2 + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape ~= "ROUND" then
        local m = math.max(math.abs(dx), math.abs(dy))
        dx, dy = dx / m, dy / m
    end
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", dx * half, dy * half)
end

local function UpdateMinimapAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    NightsFarmtrackerDB.minimap.minimapPos = angle
    PlaceMinimapButton(angle)
end

local function ShowMinimapTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("Night's Farmtracker", unpack(ns.COL_ACCENT))
    GameTooltip:AddLine(ns.L["mm_toggle"],   1, 1, 1)
    GameTooltip:AddLine(ns.L["mm_settings"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(ns.L["mm_drag"],     0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function OnMinimapClick(mouseButton)
    if mouseButton == "RightButton" then
        ns.ToggleSettings()
    else
        ns.ToggleMainFrame()
    end
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "LibDBIcon10_NightsFarmtracker", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ART.."Icon")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.icon, b.border, b.background = icon, border, bg

    b:SetScript("OnClick", function(_, mouseButton) OnMinimapClick(mouseButton) end)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", UpdateMinimapAngleFromCursor)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", ShowMinimapTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Shows or hides the button according to the setting (creates it on first need).
local function ApplyMinimapButton()
    local mm = NightsFarmtrackerDB.minimap
    if mm.hide then
        if mmButton then mmButton:Hide() end
        return
    end
    if not mmButton then mmButton = CreateMinimapButton() end
    PlaceMinimapButton(mm.minimapPos or 225)
    mmButton:Show()
end

-- Button bars (LuckyoneUI) re-collect on ElvUI's minimap update; LibDBIcon
-- buttons triggered that through the library's Show/Hide, a plain button has
-- to ask. Without this the gap of a hidden button stays until the next reload.
local function NotifyButtonBars()
    local E = ElvUI and ElvUI[1]
    local minimap = E and E.GetModule and E:GetModule("Minimap", true)
    if minimap and minimap.UpdateSettings then pcall(minimap.UpdateSettings, minimap) end
end

-- Entry in Blizzard's Addon Compartment (the minimap addon menu). The
-- compartment has no unregister call, so removing means taking our entry
-- out of its list again.
local compartmentData

local function SetCompartmentEntry(show)
    local frame = AddonCompartmentFrame
    if not (frame and frame.registeredAddons) then return end
    if show and not compartmentData then
        compartmentData = {
            text = "Night's Farmtracker",
            icon = ART.."Icon",
            func = function(_, menuInputData) OnMinimapClick(menuInputData and menuInputData.buttonName) end,
            funcOnEnter = function(btn) ShowMinimapTooltip(btn) end,
            funcOnLeave = function() GameTooltip:Hide() end,
        }
        frame:RegisterAddon(compartmentData)
    elseif not show and compartmentData then
        for i, data in ipairs(frame.registeredAddons) do
            if data == compartmentData then table.remove(frame.registeredAddons, i) break end
        end
        compartmentData = nil
        frame:UpdateDisplay()
    end
end

function ns.InitMinimapButton()
    ApplyMinimapButton()
    SetCompartmentEntry(NightsFarmtrackerDB.minimap.showInCompartment)
end

-- Re-applies the saved position (ElvUI repositions the minimap after login).
function ns.RefreshMinimapButton()
    PlaceMinimapButton(NightsFarmtrackerDB.minimap.minimapPos or 225)
end

function ns.SetMinimapVisible(show)
    NightsFarmtrackerDB.minimap.hide  = not show
    ApplyMinimapButton()
    NotifyButtonBars()
end

function ns.IsInCompartment()
    return compartmentData ~= nil
end

function ns.SetInCompartment(show)
    NightsFarmtrackerDB.minimap.showInCompartment = show and true or false
    SetCompartmentEntry(show)
end
