------------------------------------------------------------------------
-- Night's Farmtracker - Theme
-- Color themes (window, border, header and accent colors), the custom theme
-- derived from one picked color, and the shared box/header paint helpers.
------------------------------------------------------------------------
local _, ns = ...

-- Colors — theme-based. ns.COL_GOLD always stays the same regardless of
-- theme (gold amounts should stay visually consistent/recognizable).
ns.COLOR_THEMES = {
    default = {
        name     = "Default",
        labelKey = "theme_default",
        descKey  = "theme_default_desc",
        bg     = {0.06, 0.09, 0.10, 0.92},
        border = {0.20, 0.38, 0.42, 0.85},
        catBg  = {0.10, 0.16, 0.18, 0.80},
        accent = {0.30, 0.75, 0.85},
    },
    void = {
        name     = "Void",
        labelKey = "theme_void",
        descKey  = "theme_void_desc",
        bg     = {0.07, 0.05, 0.10, 0.92},
        border = {0.32, 0.18, 0.42, 0.85},
        catBg  = {0.12, 0.08, 0.16, 0.80},
        accent = {0.62, 0.35, 0.90},
    },
    silvermoon = {
        name     = "Silvermoon",
        labelKey = "theme_silvermoon",
        descKey  = "theme_silvermoon_desc",
        bg     = {0.09, 0.06, 0.04, 0.92},
        border = {0.45, 0.30, 0.10, 0.85},
        catBg  = {0.16, 0.10, 0.06, 0.80},
        accent = {1.00, 0.75, 0.25},
    },
    fel = {
        name     = "Fel",
        labelKey = "theme_fel",
        descKey  = "theme_fel_desc",
        bg     = {0.05, 0.08, 0.04, 0.92},
        border = {0.18, 0.38, 0.14, 0.85},
        catBg  = {0.08, 0.14, 0.06, 0.80},
        accent = {0.55, 0.95, 0.20},
    },
    frost = {
        name     = "Frost",
        labelKey = "theme_frost",
        descKey  = "theme_frost_desc",
        bg     = {0.05, 0.07, 0.10, 0.92},
        border = {0.20, 0.32, 0.48, 0.85},
        catBg  = {0.08, 0.12, 0.18, 0.80},
        accent = {0.55, 0.80, 1.00},
    },
    bloodmoon = {
        name     = "Bloodmoon",
        labelKey = "theme_bloodmoon",
        descKey  = "theme_bloodmoon_desc",
        bg     = {0.08, 0.04, 0.05, 0.92},
        border = {0.42, 0.14, 0.16, 0.85},
        catBg  = {0.14, 0.06, 0.07, 0.80},
        accent = {0.95, 0.30, 0.30},
    },
    molten = {
        name     = "Molten",
        labelKey = "theme_molten",
        descKey  = "theme_molten_desc",
        bg     = {0.10, 0.06, 0.03, 0.92},
        border = {0.55, 0.28, 0.08, 0.85},
        catBg  = {0.16, 0.09, 0.04, 0.80},
        accent = {1.00, 0.55, 0.10},
    },
    emerald = {
        name     = "Emerald",
        labelKey = "theme_emerald",
        descKey  = "theme_emerald_desc",
        bg     = {0.04, 0.09, 0.06, 0.92},
        border = {0.14, 0.42, 0.26, 0.85},
        catBg  = {0.07, 0.15, 0.10, 0.80},
        accent = {0.15, 0.85, 0.48},
    },
    arcane = {
        name     = "Arcane",
        labelKey = "theme_arcane",
        descKey  = "theme_arcane_desc",
        bg     = {0.08, 0.05, 0.10, 0.92},
        border = {0.40, 0.16, 0.46, 0.85},
        catBg  = {0.13, 0.08, 0.16, 0.80},
        accent = {0.78, 0.29, 0.86},
    },
    bronze = {
        name     = "Bronze",
        labelKey = "theme_bronze",
        descKey  = "theme_bronze_desc",
        bg     = {0.09, 0.07, 0.04, 0.92},
        border = {0.42, 0.28, 0.12, 0.85},
        catBg  = {0.15, 0.11, 0.06, 0.80},
        accent = {0.72, 0.47, 0.18},
    },
    plague = {
        name     = "Plague",
        labelKey = "theme_plague",
        descKey  = "theme_plague_desc",
        bg     = {0.06, 0.08, 0.03, 0.92},
        border = {0.28, 0.36, 0.10, 0.85},
        catBg  = {0.10, 0.13, 0.05, 0.80},
        accent = {0.60, 0.80, 0.20},
    },
    nether = {
        name     = "Nether",
        labelKey = "theme_nether",
        descKey  = "theme_nether_desc",
        bg     = {0.03, 0.08, 0.09, 0.92},
        border = {0.10, 0.34, 0.38, 0.85},
        catBg  = {0.05, 0.14, 0.16, 0.80},
        accent = {0.10, 0.72, 0.77},
    },
    argent = {
        name     = "Argent",
        labelKey = "theme_argent",
        descKey  = "theme_argent_desc",
        bg     = {0.09, 0.08, 0.06, 0.92},
        border = {0.55, 0.50, 0.35, 0.85},
        catBg  = {0.15, 0.13, 0.09, 0.80},
        accent = {0.95, 0.90, 0.70},
    },
    -- Hallow's End: `decor` also puts a pumpkin left and right of the "NFT"
    -- watermark (ns.ApplyThemeDecor).
    halloween = {
        name     = "Hallow's End",
        labelKey = "theme_halloween",
        descKey  = "theme_halloween_desc",
        bg     = {0.07, 0.04, 0.09, 0.92},
        border = {0.50, 0.26, 0.08, 0.85},
        catBg  = {0.14, 0.08, 0.13, 0.80},
        accent = {1.00, 0.50, 0.08},
        decor  = "pumpkin",
    },
}
-- Display order for the Settings dropdown
ns.COLOR_THEME_ORDER = {
    "default", "void", "silvermoon", "fel", "frost", "bloodmoon",
    "molten", "emerald", "arcane", "bronze", "plague", "nether", "argent",
    "halloween", "custom",
}
ns.COL_GOLD = {1.00, 0.82, 0.00}

-- Custom theme: the user picks one accent color, the other three are derived
-- from it. The built-in themes all follow the same recipe (one hue, fixed
-- saturation/brightness ramp), so the derived set looks like the presets.
local function RGBtoHSV(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then     h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else                h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx == 0) and 0 or d / mx, mx
end

local function HSVtoRGB(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

-- Accent brightness floor: it is used as text color on dark panels.
local CUSTOM_MIN_VALUE = 0.55

function ns.DeriveCustomTheme(r, g, b)
    local h, s, v = RGBtoHSV(r, g, b)
    if v < CUSTOM_MIN_VALUE then v = CUSTOM_MIN_VALUE end
    -- Saturation follows the accent's (pale accent -> pale panels), scaled
    -- per element to match the presets.
    local function shade(satFactor, val, alpha)
        local rr, gg, bb = HSVtoRGB(h, math.min(1, s * satFactor), val)
        return {rr, gg, bb, alpha}
    end
    local ar, ag, ab = HSVtoRGB(h, s, v)
    return {
        bg     = shade(0.70, 0.10, 0.92),
        border = shade(0.85, 0.42, 0.85),
        catBg  = shade(0.78, 0.17, 0.80),
        accent = {ar, ag, ab},
    }
end

do
    local t = ns.DeriveCustomTheme(0.30, 0.75, 0.85)
    t.name, t.labelKey, t.descKey = "Custom", "theme_custom", "theme_custom_desc"
    ns.COLOR_THEMES.custom = t
end

-- Header gradient colors (optional, see ns.PaintCatBg): left edge tinted
-- towards the accent, fading out to the right.
function ns.CatGradient(theme)
    local cb, ac = theme.catBg, theme.accent
    return {cb[1] + (ac[1] - cb[1]) * 0.22, cb[2] + (ac[2] - cb[2]) * 0.22,
            cb[3] + (ac[3] - cb[3]) * 0.22, 0.90},
           {cb[1], cb[2], cb[3], 0.25}
end

-- Applies a theme's colors to ns.COL_BG/BORDER/CAT_BG/ACCENT. Elements
-- already drawn with the old colors are not retroactively recolored -
-- a UI reload is required for a theme change to fully apply everywhere.
function ns.ApplyColorTheme(themeKey)
    local theme = ns.COLOR_THEMES[themeKey] or ns.COLOR_THEMES.default
    local acc = NightsFarmtrackerDB and NightsFarmtrackerDB.customAccent
    if themeKey == "custom" and type(acc) == "table" and acc[1] and acc[2] and acc[3] then
        theme = ns.DeriveCustomTheme(acc[1], acc[2], acc[3])
    end
    ns.COL_BG     = theme.bg
    ns.COL_BORDER = theme.border
    ns.COL_CAT_BG = theme.catBg
    ns.COL_ACCENT = theme.accent
    ns.THEME_DECOR = theme.decor
    ns.COL_CAT_GRAD_L, ns.COL_CAT_GRAD_R = ns.CatGradient(theme)
    if ns.ApplyThemeDecor then ns.ApplyThemeDecor() end   -- not there yet during the early apply
end

-- Paints a header/category background texture: flat COL_CAT_BG, or a
-- left-to-right gradient when the "Header gradient" option is on.
function ns.PaintCatBg(tex)
    local db = NightsFarmtrackerDB
    if db and db.headerGradient then
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL",
            CreateColor(unpack(ns.COL_CAT_GRAD_L)), CreateColor(unpack(ns.COL_CAT_GRAD_R)))
    else
        tex:SetColorTexture(unpack(ns.COL_CAT_BG))
    end
end

-- Shared backdrop used throughout Settings/Blacklist/Filter for small
-- boxed widgets (checkboxes, radio dots, dropdowns, edit boxes, buttons).
-- Its 1px square border matches the window frames (see ApplyFrameStyle).
-- bgColor defaults to {0.06,0.09,0.10,1} (the checkbox/radio shade); pass
-- {0.05,0.08,0.09,1} for the slightly darker dropdown/edit-box shade.
function ns.StyleBackdropBox(frame, bgColor)
    frame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",
        edgeFile="Interface/Buttons/WHITE8x8",
        tile=true,tileSize=8,edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
    frame:SetBackdropColor(unpack(bgColor or {0.06,0.09,0.10,1}))
    frame:SetBackdropBorderColor(unpack(ns.COL_BORDER))
end

-- Best-effort early apply in case SavedVariables already happen to be
-- available (e.g. on repeated /reload during dev). On a normal login this
-- runs before SavedVariables are loaded and falls back to "default"; the
-- real apply happens in InitDB(), with MainFrame/GoldFrame explicitly
-- re-skinned afterwards since they're built before that point.
ns.ApplyColorTheme(NightsFarmtrackerDB and NightsFarmtrackerDB.colorTheme)
