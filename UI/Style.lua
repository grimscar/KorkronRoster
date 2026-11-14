-- The Kor'kron look, "Warband" (iron and blood): colours, fonts and the art in Media/ (drawn by tools/make_art.py).
-- It knows nothing about the mod it's in. Kor'kron Hub holds the original: change it there, then its
-- tools/copy_style.py gives every Kor'kron mod the same copy of this file, UI/StyleArt.lua and Media/.
-- Sizes are the game's units; the art is drawn at twice that.
local ADDON_NAME, ns = ...

local Style = {}
ns.Style = Style

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local ART = MEDIA .. "Art.tga"
local MASK = MEDIA .. "Mask.tga"
local WHITE = "Interface\\Buttons\\WHITE8x8"

Style.FONTS = {
    title = MEDIA .. "Fonts\\GrenzeGotisch-SemiBold.ttf",
    body = MEDIA .. "Fonts\\Barlow-Regular.ttf",
    bold = MEDIA .. "Fonts\\Barlow-SemiBold.ttf",
}

local function RGB(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end

Style.COLOR = {
    gold = RGB("e3c27a"),     -- titles
    pale = RGB("f3dfb0"),     -- the picked mod, text on red buttons
    text = RGB("e6dccb"),
    soft = RGB("cfc5b4"),     -- longer text
    muted = RGB("9a9086"),    -- what you don't have
    danger = RGB("e0604f"),   -- warnings
    iron = RGB("6b5f55"),
    ironDark = RGB("4a423c"),
    red = RGB("c0392b"),      -- the picked ring and its glow
    fill = RGB("171313"),     -- window inside: the same as the art's
    field = RGB("0d0b0b"),    -- text boxes
    button = RGB("2f2624"),
    primary = RGB("a52323"),
    emblem = RGB("4a1313"),
    nodeBack = RGB("2a2321"),
}
local C = Style.COLOR

-- the art's pieces are in UI/StyleArt.lua; a half-pixel inset keeps neighbouring pieces from bleeding in
local function Piece(tex, name, flipX, flipY)
    local A = ns.STYLE_ART
    local x, y, w, h = unpack(A[name])
    local left, right = (x + 0.5) / A.width, (x + w - 0.5) / A.width
    local top, bottom = (y + 0.5) / A.height, (y + h - 0.5) / A.height
    if flipX then left, right = right, left end
    if flipY then top, bottom = bottom, top end
    tex:SetTexture(ART)
    tex:SetTexCoord(left, right, top, bottom)
end

-- a piece at its own size (half its pixels), or stretched where w or h is nil
local function Tex(parent, layer, name, w, h)
    local tex = parent:CreateTexture(nil, layer)
    Piece(tex, name)
    local _, _, pw, ph = unpack(ns.STYLE_ART[name])
    if w ~= false then tex:SetWidth(w or pw / 2) end
    if h ~= false then tex:SetHeight(h or ph / 2) end
    return tex
end

local function Tint(parts, color, alpha)
    for _, tex in ipairs(parts) do
        tex:SetVertexColor(color[1], color[2], color[3], alpha or 1)
    end
end

-- fonts -----------------------------------------------------------------------------------------
-- New files in Media only load after the game restarts; until then the game's own fonts stand in, once said.
local fontsWarned = false

local function FontsMissing()
    if fontsWarned then return end
    fontsWarned = true
    ns:Print("its fonts didn't load. Restart the game: a /reload doesn't pick up new files.")
end

function Style.Font(fs, kind, size, color)
    if not fs:SetFont(Style.FONTS[kind], size, "") then
        fs:SetFontObject(kind == "title" and GameFontNormalLarge or GameFontHighlight)
        FontsMissing()
    end
    color = color or C.text
    fs:SetTextColor(color[1], color[2], color[3])
end

-- Font objects, for code that names one (CreateFontString's third argument, SetFontObject): <mod>Font<role>, e.g.
-- KorkronLootFontNormalSmall. The roles are the game's own font names: Normal gold, Highlight light, Disable dim;
-- Small a size down, Large a heading. Each stands in with the game's font of the same role until ours load.
local FONT_ROLES = {
    Normal = { "bold", 13, C.gold },
    NormalSmall = { "bold", 11, C.gold },
    NormalLarge = { "title", 18, C.gold },
    Highlight = { "body", 13, C.text },
    HighlightSmall = { "body", 11, C.text },
    HighlightLarge = { "bold", 16, C.text },
    Disable = { "body", 13, C.muted },
    DisableSmall = { "body", 11, C.muted },
    RedSmall = { "body", 11, C.danger },
}

for role, spec in pairs(FONT_ROLES) do
    local font = CreateFont(ADDON_NAME .. "Font" .. role)
    if not font:SetFont(Style.FONTS[spec[1]], spec[2], "") then
        font:CopyFontObject(_G["GameFont" .. role])
        FontsMissing()
    end
    font:SetTextColor(spec[3][1], spec[3][2], spec[3][3])
end

-- windows ---------------------------------------------------------------------------------------
-- the iron frame with cut corners, the blood-red title band, spikes on the corners, the title and a close button
Style.BAND = ns.STYLE_ART.win_t[4] / 2 -- the title band's height, red line included
Style.TOP = -(Style.BAND + 8)            -- where a window's content starts, under the band

function Style.Window(frame, title)
    local tl = Tex(frame, "BACKGROUND", "win_tl")
    tl:SetPoint("TOPLEFT")
    local tr = Tex(frame, "BACKGROUND", "win_tr")
    tr:SetPoint("TOPRIGHT")
    local top = Tex(frame, "BACKGROUND", "win_t", false)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", tr, "TOPLEFT")
    local bl = Tex(frame, "BACKGROUND", "win_bl")
    bl:SetPoint("BOTTOMLEFT")
    local br = Tex(frame, "BACKGROUND", "win_br")
    br:SetPoint("BOTTOMRIGHT")
    local bottom = Tex(frame, "BACKGROUND", "win_b", false)
    bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left = Tex(frame, "BACKGROUND", "win_l", nil, false)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
    local right = Tex(frame, "BACKGROUND", "win_r", nil, false)
    right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local inside = frame:CreateTexture(nil, "BACKGROUND")
    inside:SetColorTexture(C.fill[1], C.fill[2], C.fill[3])
    inside:SetPoint("TOPLEFT", left, "TOPRIGHT")
    inside:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")

    for _, corner in ipairs({ { "TOPLEFT", -7, 7 }, { "TOPRIGHT", 7, 7, true }, { "BOTTOMLEFT", -7, -7, false, true },
        { "BOTTOMRIGHT", 7, -7, true, true } }) do
        local spike = frame:CreateTexture(nil, "OVERLAY")
        Piece(spike, "spike", corner[4], corner[5])
        spike:SetSize(20, 20)
        spike:SetPoint(corner[1], corner[2], corner[3])
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    Style.Font(frame.title, "title", 18, C.gold)
    frame.title:SetPoint("CENTER", frame, "TOP", 0, -Style.BAND / 2)
    frame.title:SetText(title)

    frame.closeButton = Style.CloseButton(frame)
    frame.closeButton:SetPoint("TOPRIGHT", -9, -6)
end

-- an iron square with a bone cross that hides parent when clicked
function Style.CloseButton(parent)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(18, 18)
    Tex(close, "ARTWORK", "close", false, false):SetAllPoints()
    local lit = Tex(close, "HIGHLIGHT", "close", false, false)
    lit:SetAllPoints()
    lit:SetBlendMode("ADD")
    lit:SetAlpha(0.35)
    close:SetScript("OnClick", function() parent:Hide() end)
    return close
end

-- buttons ---------------------------------------------------------------------------------------
-- cut on two corners: a fill (red for the main action, dark for the rest), an iron outline, lighter on hover,
-- dimmed while it can't be clicked

local function ThreeSlice(button, layer, name)
    local l = Tex(button, layer, name .. "_l", nil, false)
    l:SetPoint("TOPLEFT")
    l:SetPoint("BOTTOMLEFT")
    local r = Tex(button, layer, name .. "_r", nil, false)
    r:SetPoint("TOPRIGHT")
    r:SetPoint("BOTTOMRIGHT")
    local m = Tex(button, layer, name .. "_m", false, false)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT")
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    return { l, m, r }
end

local function PaintButton(button)
    local on, primary = button:IsEnabled(), button.primary
    Tint(button.fill, primary and C.primary or C.button, on and 1 or 0.5)
    Tint(button.line, C.iron, primary and 0 or on and 1 or 0.5)
    local color = not on and C.muted or primary and C.pale or C.text
    button:GetFontString():SetTextColor(color[1], color[2], color[3])
end

function Style.Button(button)
    button.fill = ThreeSlice(button, "BACKGROUND", "button")
    button.line = ThreeSlice(button, "BORDER", "buttonline")
    local lit = ThreeSlice(button, "HIGHLIGHT", "button")
    for _, tex in ipairs(lit) do tex:SetBlendMode("ADD") end
    Tint(lit, C.text, 0.12)
    local fs = button:CreateFontString(nil, "OVERLAY")
    Style.Font(fs, "bold", 12)
    button:SetFontString(fs)
    button:SetPushedTextOffset(1, -1)
    button:HookScript("OnEnable", PaintButton)
    button:HookScript("OnDisable", PaintButton)
    Style.SetButtonKind(button, false)
end

-- primary: red, for the main action or the open tab
function Style.SetButtonKind(button, primary)
    button.primary = primary
    PaintButton(button)
end

-- check boxes -----------------------------------------------------------------------------------
-- an iron-edged dark square with a pale tick when it's on (the frame must be a CheckButton)
function Style.CheckBox(check)
    Tex(check, "BACKGROUND", "checkbox", 16, 16):SetPoint("CENTER")
    check:SetCheckedTexture(ART)
    local tick = check:GetCheckedTexture()
    Piece(tick, "tick")
    tick:ClearAllPoints()
    tick:SetSize(16, 16)
    tick:SetPoint("CENTER")
    Tint({ tick }, C.pale)
    local lit = Tex(check, "HIGHLIGHT", "checkbox", 16, 16)
    lit:SetPoint("CENTER")
    lit:SetBlendMode("ADD")
    Tint({ lit }, C.gold, 0.3)
end

-- a tick on its own, for a menu's chosen line
function Style.Tick(parent, size)
    local tick = Tex(parent, "ARTWORK", "tick", size, size)
    Tint({ tick }, C.gold)
    return tick
end

-- boxes and scroll bars -------------------------------------------------------------------------

-- a plain dark box with an iron edge, for menus, cards and text areas (the frame must be made with
-- "BackdropTemplate"); fill and edge are Style.COLOR entries
function Style.Panel(frame, fill, edge)
    fill, edge = fill or C.fill, edge or C.iron
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(fill[1], fill[2], fill[3], 1)
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
end

-- a text box: dark, with an iron edge (the box must be made with "BackdropTemplate")
function Style.EditBox(box)
    Style.Panel(box, C.field, C.ironDark)
    box:SetTextInsets(6, 6, 0, 0)
    Style.Font(box, "body", 12)
end

-- a scroll frame made with UIPanelScrollFrameTemplate: a thin iron bar in a dark groove instead of the game's
-- knob, and no arrow buttons (made see-through: the game shows them again whenever the length changes)
function Style.ScrollBar(scroll)
    local bar = scroll.ScrollBar
    for _, arrow in ipairs({ bar.ScrollUpButton, bar.ScrollDownButton }) do
        arrow:SetAlpha(0)
        arrow:EnableMouse(false)
    end
    local groove = bar:CreateTexture(nil, "BACKGROUND")
    groove:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
    groove:SetWidth(6)
    groove:SetPoint("TOP")
    groove:SetPoint("BOTTOM")
    local thumb = bar:GetThumbTexture()
    thumb:SetColorTexture(C.iron[1], C.iron[2], C.iron[3], 1)
    thumb:SetSize(6, 28)
end

-- round icons: the game's square icons cut round inside an iron ring ------------------------------

local function Masked(frame, icon)
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- the icons' own dark edge
end

-- returns the icon texture
function Style.Ring(button, size)
    button:SetSize(size, size)
    local glow = Tex(button, "BACKGROUND", "glow", size * 1.6, size * 1.6)
    glow:SetPoint("CENTER")
    Tint({ glow }, C.red)
    local back = Tex(button, "BORDER", "disc", size, size)
    back:SetPoint("CENTER")
    Tint({ back }, C.nodeBack)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size - 2, size - 2)
    icon:SetPoint("CENTER")
    Masked(button, icon)
    local ring = Tex(button, "OVERLAY", "ring", size, size)
    ring:SetPoint("CENTER")
    local lit = Tex(button, "HIGHLIGHT", "glow", size * 1.6, size * 1.6)
    lit:SetPoint("CENTER")
    lit:SetBlendMode("ADD")
    Tint({ lit }, C.gold, 0.45)
    button.icon, button.ring, button.glow = icon, ring, glow
    Style.SetRingState(button, false, false)
    return icon
end

-- picked: a red ring and glow; off (not installed or turned off): greyed
function Style.SetRingState(button, picked, off)
    Tint({ button.ring }, picked and C.red or off and C.ironDark or C.iron)
    button.glow:SetShown(picked)
    button.icon:SetDesaturated(off)
    button.icon:SetAlpha(off and 0.5 or 1)
end

-- the guild's emblem: a dark red disc in a red ring and an iron ring, glowing; returns the icon texture
function Style.Emblem(frame, size)
    frame:SetSize(size, size)
    local glow = Tex(frame, "BACKGROUND", "glow", size * 1.7, size * 1.7)
    glow:SetPoint("CENTER")
    Tint({ glow }, C.red, 0.6)
    local back = Tex(frame, "BORDER", "disc", size, size)
    back:SetPoint("CENTER")
    Tint({ back }, C.emblem)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size * 0.72, size * 0.72)
    icon:SetPoint("CENTER")
    Masked(frame, icon)
    local inner = Tex(frame, "OVERLAY", "ring", size, size)
    inner:SetPoint("CENTER")
    Tint({ inner }, C.primary)
    local outer = Tex(frame, "OVERLAY", "ring", size + 12, size + 12)
    outer:SetPoint("CENTER")
    Tint({ outer }, C.iron)
    return icon
end

-- a fading iron line with a red diamond in the middle
function Style.Divider(parent)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(8)
    local diamond = Tex(line, "ARTWORK", "diamond")
    diamond:SetPoint("CENTER")
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local fade = line:CreateTexture(nil, "ARTWORK")
        fade:SetColorTexture(1, 1, 1, 1)
        fade:SetHeight(1)
        local clear, solid = CreateColor(C.iron[1], C.iron[2], C.iron[3], 0), CreateColor(C.iron[1], C.iron[2], C.iron[3], 1)
        if side == "LEFT" then
            fade:SetPoint("LEFT")
            fade:SetPoint("RIGHT", diamond, "LEFT", -5, 0)
            fade:SetGradient("HORIZONTAL", clear, solid)
        else
            fade:SetPoint("RIGHT")
            fade:SetPoint("LEFT", diamond, "RIGHT", 5, 0)
            fade:SetGradient("HORIZONTAL", solid, clear)
        end
    end
    return line
end
