------------------------------------------------------------------------
-- Night's Farmtracker - Minimap HUD (optional)
-- Stretches the minimap over the screen while farming, so gathering nodes
-- and tracking blips can be read around the character. Off by default;
-- toggled via Settings -> Minimap HUD, and opened/closed with a key binding
-- the player sets under Options -> Keybindings -> AddOns (no default key)
-- or with /nft hud.
--
-- How it works (same idea as the FarmHud addon, much smaller):
--   * The real Minimap frame is moved into a screen-sized HUD frame.
--   * Everything that belongs to the old minimap spot (children, textures
--     and any frame anchored to the Minimap - ElvUI panels, minimap buttons)
--     is moved to a placeholder frame that sits where the minimap was.
--   * Minimap pins (HereBeDragons / GatherMate2 / HandyNotes / Routes) are
--     handed to a separate "cluster" frame, so the map background can be made
--     transparent without hiding the pins.
--   * Closing the HUD puts everything back. Nothing is touched while the
--     feature is disabled or the HUD was never opened.
------------------------------------------------------------------------
local _, ns = ...
local L = ns.L

local PREFIX = "|cff30b0c0Night's Farmtracker:|r "
local STRATA = "BACKGROUND"

local Hud, Cluster, Dummy       -- frames, created on first open
local active       = false      -- HUD currently open
local busy         = false      -- ignore our own SetPoint/SetZoom calls in hooks
local pendingClose = false      -- close was requested in combat
local saved                     -- snapshot of the Minimap taken on open
local moved        = {}         -- { {obj=, parent=, strata=, level=, layer=, sub=}, ... }
local redirected   = {}         -- obj -> true while its Minimap anchors point at Dummy
local hooked       = {}         -- obj -> true once the SetPoint hook is installed
local hooksReady   = false

local function Msg(text)
    print(PREFIX .. text)
end

local function Enabled()
    return NightsFarmtrackerDB and NightsFarmtrackerDB.hudEnabled == true
end

------------------------------------------------------------------------
-- Settings (defaults mirror the FarmHud defaults)
------------------------------------------------------------------------
local function Num(key, default, lo, hi)
    local v = tonumber(NightsFarmtrackerDB and NightsFarmtrackerDB[key])
    if not v then return default end
    return math.min(hi, math.max(lo, v))
end

local function HudSize()   return Num("hudSize",  1,   0.2, 1)   end  -- share of the screen height
local function HudScale()  return Num("hudScale", 1.4, 1,   2.5) end  -- symbol scale of blips
local function HudAlpha()  return Num("hudAlpha", 0,   0,   1)   end  -- map background (0 = hidden)
local function HudRotate() return not NightsFarmtrackerDB or NightsFarmtrackerDB.hudRotate ~= false end

------------------------------------------------------------------------
-- Anchor helpers
------------------------------------------------------------------------
-- Re-points every anchor of obj that targets `from` to `to`.
-- Returns true if anything was changed.
local function SwapAnchors(obj, from, to)
    local n = obj:GetNumPoints()
    if type(n) ~= "number" or n == 0 then return false end
    local pts, hit = {}, false
    for i = 1, n do
        local point, rel, relPoint, x, y = obj:GetPoint(i)
        if rel == from then rel = to; hit = true end
        pts[i] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end
    if not hit then return false end
    obj:ClearAllPoints()
    for i = 1, n do
        local p = pts[i]
        obj:SetPoint(p.point, p.rel, p.relPoint, p.x, p.y)
    end
    return true
end

-- Foreign addons (ElvUI, LibDBIcon, ...) re-anchor their frames to the
-- Minimap from time to time. While the HUD is open, send those anchors
-- straight on to the placeholder again.
local function OnForeignSetPoint(obj)
    if not active or busy or not redirected[obj] then return end
    busy = true
    pcall(SwapAnchors, obj, Minimap, Dummy)
    busy = false
end

local function HookObject(obj)
    if hooked[obj] then return end
    hooked[obj] = true
    pcall(hooksecurefunc, obj, "SetPoint", OnForeignSetPoint)
end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local function Layout()
    local w, h = WorldFrame:GetSize()
    local size  = math.min(w, h) / UIParent:GetEffectiveScale() * HudSize()
    local scale = HudScale()
    local inner = size / scale

    Hud:SetSize(size, size)
    Minimap:SetScale(scale)
    Minimap:SetSize(inner, inner)
    Cluster:SetScale(scale)
    Cluster:SetSize(inner, inner)
end

local function ApplyRotation()
    local want = HudRotate() and "1" or "0"
    if C_CVar.GetCVar("rotateMinimap") ~= want then
        C_CVar.SetCVar("rotateMinimap", want)
        if Minimap_UpdateRotationSetting then Minimap_UpdateRotationSetting() end
    end
end

local function ReanchorMinimap()
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", Hud, "CENTER")
end

local function EnsureFrames()
    if Hud then return end

    Hud = CreateFrame("Frame", "NightsFarmtrackerHud", UIParent)
    Hud:SetFrameStrata(STRATA)
    Hud:SetFrameLevel(2)
    Hud:SetPoint("CENTER", WorldFrame, "CENTER")  -- follows the user's viewport
    Hud:Hide()

    -- Stand-in "minimap" for pins and Routes lines. Needs the zoom calls a
    -- Minimap object offers.
    Cluster = CreateFrame("Frame", nil, Hud)
    Cluster:SetPoint("CENTER")
    function Cluster:GetZoom() return Minimap:GetZoom() end
    function Cluster:SetZoom() end

    -- Placeholder where the minimap used to be.
    Dummy = CreateFrame("Frame", nil, UIParent)
    Dummy:Hide()
end

local function InstallHooks()
    if hooksReady then return end
    hooksReady = true

    hooksecurefunc(Minimap, "SetZoom", function(_, level)
        if active and level ~= 0 then Minimap:SetZoom(0) end
    end)

    hooksecurefunc(Minimap, "SetPoint", function()
        if not active or busy then return end
        busy = true
        pcall(ReanchorMinimap)
        busy = false
    end)
end

------------------------------------------------------------------------
-- Moving the old minimap surroundings to the placeholder
------------------------------------------------------------------------
local function IsIgnored(obj)
    if obj == Minimap or obj == Hud or obj == Cluster or obj == Dummy then return true end
    if obj.IsForbidden and obj:IsForbidden() then return true end
    if obj.GetObjectType and obj:GetObjectType() == "Line" then return true end
    local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if pins and pins.minimapPins and pins.minimapPins[obj] then return true end
    local name = obj.GetName and obj:GetName()
    if name and name:find("GatherMate", 1, true) then return true end
    return false
end

local function Redirect(obj, reparent)
    local rec = { obj = obj }
    local isFrame = obj.GetFrameStrata ~= nil

    if reparent and obj:GetParent() == Minimap then
        rec.parent = Minimap
        if isFrame then
            rec.strata, rec.level = obj:GetFrameStrata(), obj:GetFrameLevel()
        else
            rec.layer, rec.sub = obj:GetDrawLayer()
        end
        obj:SetParent(Dummy)
        -- SetParent can reset level/layer; put them back
        if isFrame then
            obj:SetFrameStrata(rec.strata)
            obj:SetFrameLevel(rec.level)
        else
            obj:SetDrawLayer(rec.layer, rec.sub)
        end
    end

    local anchored = SwapAnchors(obj, Minimap, Dummy)
    if anchored then redirected[obj] = true end
    if rec.parent or anchored then
        HookObject(obj)
        moved[#moved + 1] = rec
    end
end

-- true if one of the frame's anchors targets the Minimap. Called through
-- pcall: some frames hand back unusable values (GetNumPoints not a number,
-- restricted/secret anchor data), those are simply skipped.
local function AnchoredToMinimap(f)
    local n = f:GetNumPoints()
    if type(n) ~= "number" then return false end
    for i = 1, n do
        local _, rel = f:GetPoint(i)
        if rel == Minimap then return true end
    end
    return false
end

local function MoveSurroundings()
    local seen = {}

    local function consider(obj, reparent)
        if seen[obj] or IsIgnored(obj) then return end
        seen[obj] = true
        local ok, err = pcall(Redirect, obj, reparent)
        if not ok and ns.Log then ns.Log("Hud: redirect failed", err) end
    end

    -- 1) everything that is a child or texture of the Minimap itself
    for _, child in ipairs({ Minimap:GetChildren() }) do consider(child, true) end
    for _, region in ipairs({ Minimap:GetRegions() }) do consider(region, true) end

    -- 2) textures/fontstrings of neighbouring containers that are anchored to it
    local holders = { MinimapBackdrop, MinimapCluster, saved.parent }
    for i = 1, 3 do  -- fixed bound: entries may be nil (ipairs would stop there)
        local holder = holders[i]
        if holder and holder ~= Minimap then
            for _, region in ipairs({ holder:GetRegions() }) do consider(region, false) end
        end
    end

    -- 3) other frames anchored to the Minimap (ElvUI panels, tracking/mail/
    -- calendar icons, ...). Deliberately NOT a scan of every frame in the game
    -- (EnumerateFrames): with a big UI that is hundreds of thousands of
    -- frames and froze the client for seconds. Those frames live under
    -- UIParent, ElvUI's own UIParent or the minimap cluster, so only the
    -- children of those few roots are checked.
    local function scan(root, depth)
        if not root or not root.GetChildren then return end
        for _, child in ipairs({ root:GetChildren() }) do
            if not seen[child] and not (child.IsForbidden and child:IsForbidden()) then
                local ok, hit = pcall(AnchoredToMinimap, child)
                if ok and hit then consider(child, false) end
                if depth > 1 then scan(child, depth - 1) end
            end
        end
    end
    local ElvUIParent = _G.ElvUI and _G.ElvUI[1] and _G.ElvUI[1].UIParent
    -- pcall: a root with an enormous child count could exceed the Lua stack
    -- limit when its children are unpacked; skip that root instead of failing
    local started = debugprofilestop()
    pcall(scan, UIParent, 1)
    pcall(scan, ElvUIParent, 1)
    pcall(scan, MinimapCluster, 2)
    if ns.debugMode then
        Msg(string.format("HUD: frame scan took %.1f ms", debugprofilestop() - started))
    end
end

local function RestoreSurroundings()
    for i = #moved, 1, -1 do
        local rec = moved[i]
        local obj = rec.obj
        redirected[obj] = nil
        pcall(function()
            if rec.parent and obj:GetParent() == Dummy then
                obj:SetParent(rec.parent)
                if rec.strata then
                    obj:SetFrameStrata(rec.strata)
                    obj:SetFrameLevel(rec.level)
                else
                    obj:SetDrawLayer(rec.layer, rec.sub)
                end
            end
            SwapAnchors(obj, Dummy, Minimap)
        end)
    end
    wipe(moved)
end

------------------------------------------------------------------------
-- Pin addons: hand their pins to the cluster while the HUD is open
------------------------------------------------------------------------
local function SetPinParent(map)
    local target = map or Minimap

    local GM = _G.GatherMate2
    if GM and GM.GetModule then
        pcall(function()
            local display = GM:GetModule("Display", true)
            if display and display.ReparentMinimapPins then display:ReparentMinimapPins(target) end
        end)
    end

    local Routes = _G.Routes
    if Routes and Routes.ReparentMinimap then
        pcall(Routes.ReparentMinimap, Routes, target)
    end

    -- HereBeDragons (also drives HandyNotes); nil = back to the real minimap
    local pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    if pins and pins.SetMinimapObject then
        pcall(pins.SetMinimapObject, pins, map)
    end
end

------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------
local function OpenImpl()
    EnsureFrames()
    InstallHooks()

    local width, height = Minimap:GetSize()
    saved = {
        parent     = Minimap:GetParent(),
        scale      = Minimap:GetScale(),
        strata     = Minimap:GetFrameStrata(),
        level      = Minimap:GetFrameLevel(),
        alpha      = Minimap:GetAlpha(),
        mouse      = Minimap:IsMouseEnabled(),
        mousewheel = Minimap:IsMouseWheelEnabled(),
        zoom       = Minimap:GetZoom(),
        shown      = Minimap:IsShown(),
        rotate     = C_CVar.GetCVar("rotateMinimap"),
        width      = width,
        height     = height,
        points     = {},
    }
    for i = 1, Minimap:GetNumPoints() do
        local point, rel, relPoint, x, y = Minimap:GetPoint(i)
        saved.points[i] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end

    -- placeholder takes over the old minimap spot
    Dummy:SetParent(saved.parent)
    Dummy:SetScale(saved.scale)
    Dummy:SetSize(saved.width, saved.height)
    Dummy:SetFrameStrata(saved.strata)
    Dummy:SetFrameLevel(saved.level)
    Dummy:ClearAllPoints()
    for _, p in ipairs(saved.points) do
        Dummy:SetPoint(p.point, p.rel, p.relPoint, p.x, p.y)
    end
    Dummy:Show()

    -- the HUD must be visible before the minimap moves into it, so the
    -- minimap never changes its own shown state (no OnShow/OnHide for others)
    Hud:Show()

    busy = true
    MoveSurroundings()

    Minimap:SetParent(Hud)
    ReanchorMinimap()
    Minimap:SetFrameStrata(STRATA)
    Minimap:SetFrameLevel(1)
    Cluster:SetFrameStrata(STRATA)
    Cluster:SetFrameLevel(1)
    Layout()
    Minimap:SetZoom(0)
    Minimap:SetAlpha(HudAlpha())
    Minimap:EnableMouse(false)        -- clicks must reach the 3D world
    Minimap:EnableMouseWheel(false)
    if not Minimap:IsShown() then Minimap:Show() end
    busy = false

    ApplyRotation()
    SetPinParent(Cluster)
    active = true
end

local function Close()
    if not saved then return end
    active = false
    busy = true

    local s = saved
    pcall(function()
        Minimap:SetParent(s.parent)
        Minimap:ClearAllPoints()
        for _, p in ipairs(s.points) do
            Minimap:SetPoint(p.point, p.rel, p.relPoint, p.x, p.y)
        end
        Minimap:SetScale(s.scale)
        Minimap:SetSize(s.width, s.height)
        Minimap:SetFrameStrata(s.strata)
        Minimap:SetFrameLevel(s.level)
        Minimap:SetAlpha(s.alpha)
        Minimap:EnableMouse(s.mouse)
        Minimap:EnableMouseWheel(s.mousewheel)
        local maxZoom = Minimap:GetZoomLevels()
        Minimap:SetZoom(maxZoom and math.min(s.zoom, maxZoom) or s.zoom)
        if not s.shown then Minimap:Hide() end
    end)

    RestoreSurroundings()
    SetPinParent(nil)

    if Dummy then Dummy:Hide() end
    if Hud then Hud:Hide() end

    if s.rotate and C_CVar.GetCVar("rotateMinimap") ~= s.rotate then
        C_CVar.SetCVar("rotateMinimap", s.rotate)
        if Minimap_UpdateRotationSetting then Minimap_UpdateRotationSetting() end
    end

    saved = nil
    pendingClose = false
    busy = false
end

local function Open()
    local ok, err = pcall(OpenImpl)
    if not ok then
        pcall(Close)
        Msg(string.format(L["hud_error"], tostring(err)))
    end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------
-- show: true = open, false = close, nil = toggle
function ns.SetHudVisible(show)
    if show == nil then show = not active end
    if show == active then return end

    if show and not Enabled() then return end   -- feature off: key binding and /nft hud do nothing
    if InCombatLockdown() then
        if show then
            Msg(L["hud_combat"])
        else
            pendingClose = true
            Msg(L["hud_combat_close"])
        end
        return
    end

    if show then Open() else Close() end
end

function ns.ToggleHud()
    ns.SetHudVisible(nil)
end

-- Called when the setting is switched; disabling closes an open HUD.
function ns.SetHudEnabled(enabled)
    NightsFarmtrackerDB.hudEnabled = enabled and true or false
    if not enabled and active then
        ns.SetHudVisible(false)
    end
end

-- /nft hud [size <20-100> | scale <1-2.5> | alpha <0-100> | rotate]
function ns.HudSlash(arg)
    local sub, val = (arg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    local num = tonumber(val)
    local db = NightsFarmtrackerDB

    if sub == "" then
        ns.ToggleHud()
        return
    elseif sub == "size" and num then
        db.hudSize = math.min(100, math.max(20, num)) / 100
    elseif sub == "scale" and num then
        db.hudScale = math.min(2.5, math.max(1, num))
    elseif sub == "alpha" and num then
        db.hudAlpha = math.min(100, math.max(0, num)) / 100
    elseif sub == "rotate" then
        db.hudRotate = not HudRotate()
    else
        Msg(L["hud_usage"])
        return
    end

    if active then
        local ok = pcall(function()
            Layout()
            Minimap:SetAlpha(HudAlpha())
            ApplyRotation()
        end)
        if not ok then Msg(L["hud_apply_failed"]) end
    end
    Msg(string.format(L["hud_values"],
        math.floor(HudSize() * 100 + 0.5), HudScale(), math.floor(HudAlpha() * 100 + 0.5),
        HudRotate() and L["on"] or L["off"]))
end

-- Global entry points for Bindings.xml
function NightsFarmtracker_ToggleHud()
    ns.ToggleHud()
end

BINDING_HEADER_NIGHTSFARMTRACKER = "Night's Farmtracker"
BINDING_NAME_NFT_TOGGLE_HUD      = L["hud_binding"]

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_LOGOUT")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingClose and active then Close() end
        pendingClose = false
    elseif event == "PLAYER_LOGOUT" then
        -- also fires on /reload: leave the minimap and the rotate CVar as found
        if active then pcall(Close) end
    elseif active then
        -- resolution / UI scale changed while the HUD is open
        pcall(Layout)
    end
end)
