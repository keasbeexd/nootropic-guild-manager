--[[
    Nootropic Guild Manager - Theme (3.0)
    The addon's look, matching NGM Peon's dashboard (ngm-hub docs/DESIGN.md):
    the Gruvbox palette, JetBrains Mono for titles, labels, buttons and
    numbers, and Rubik for text. Font objects (NGMFont*) stand in for the
    game's own (GameFont*) everywhere; other alphabets (Cyrillic for Rubik,
    Korean and Chinese for both) use the game's fonts, so no name ever shows
    as boxes. If a font file can't be loaded, the game's font is used.

    ns.Theme.C.yellow          {r, g, b}
    ns.Theme.HEX.yellow        "fabd2f" (for |cff...|r)
    ns.Theme:Skin(frame)       a window as the dashboard's page (template art hidden;
                               tick boxes, fields, scroll bars and panels inside too)
    ns.Theme:SkinButton(b)     a button as the dashboard's
    ns.Theme:Box(frame)        a dashboard box: dark fill, notched pixel edge
    ns.Theme:Dashes(host)      the dashboard's dashed rule
    ns.Theme:Scanlines(region, alpha)   faint CRT lines over a frame (tiled)
    ns.Theme:Toast(title, text)        an arcade banner ("LEVEL UP!") that drops in
]]
local _, ns = ...
local T = {}
ns.Theme = T

-- Gruvbox (dark), as the dashboard
T.HEX = {
    bg = "1d2021", bg1 = "282828", line = "3c3836", edge = "504945",
    fg = "ebdbb2", dim = "a89984", faint = "7c6f64",
    yellow = "fabd2f", red = "fb4934", green = "b8bb26", blue = "83a598",
    aqua = "8ec07c", orange = "fe8019", purple = "d3869b", shade = "9d0006",
}
T.C = {}
for k, h in pairs(T.HEX) do
    T.C[k] = { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

local MEDIA = "Interface\\AddOns\\NootropicGuildManager\\Media\\"
T.SCANLINES = MEDIA .. "Scanlines"
T.DASH = MEDIA .. "Dash"
T.CRT = { mask = MEDIA .. "CRTMask", shade = MEDIA .. "CRTShade", glass = MEDIA .. "CRTGlass" }
local DIR = MEDIA .. "Fonts\\"
T.FONTS = {
    mono = DIR .. "JetBrainsMono-Regular.ttf",
    monoBold = DIR .. "JetBrainsMono-Bold.ttf",
    text = DIR .. "Rubik-Regular.ttf",
    textMedium = DIR .. "Rubik-Medium.ttf",
}

-- The game's own fonts for alphabets ours don't cover.
local GAME = {
    korean = "Fonts\\2002.TTF",
    simplifiedchinese = "Fonts\\ARKai_T.ttf",
    traditionalchinese = "Fonts\\blei00d.TTF",
    russian = "Fonts\\FRIZQT___CYR.TTF",
}

-- name -> { file, size, flags, color, fallback (a game font object), cyrillic (ours has it) }
local OBJECTS = {
    NGMFontTitle        = { "monoBold", 14, "", "yellow", "GameFontNormalLarge", true },
    NGMFontHuge         = { "monoBold", 22, "", "yellow", "GameFontNormalHuge", true },
    NGMFontLabel        = { "monoBold", 12, "", "yellow", "GameFontNormal", true },
    NGMFontLabelSmall   = { "monoBold", 11, "", "yellow", "GameFontNormalSmall", true },
    NGMFontText         = { "text", 13, "", "fg", "GameFontHighlight", false },
    NGMFontTextSmall    = { "text", 12, "", "fg", "GameFontHighlightSmall", false },
    NGMFontDim          = { "text", 13, "", "dim", "GameFontDisable", false },
    NGMFontDimSmall     = { "text", 12, "", "dim", "GameFontDisableSmall", false },
    NGMFontNumber       = { "mono", 11, "", "fg", "NumberFontNormalSmall", true },
    NGMFontButton       = { "monoBold", 12, "", "bg", "GameFontNormal", true },
    NGMFontButtonSmall  = { "monoBold", 10, "", "bg", "GameFontNormalSmall", true },
}

local function MakeFont(name, spec)
    local key, size, flags, color, fallback, cyrillic = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
    local file = T.FONTS[key]
    local obj
    -- a family: our file for roman (and Cyrillic, where ours has it), the game's for the rest
    if CreateFontFamily then
        local members = { { alphabet = "roman", file = file, height = size, flags = flags } }
        for alphabet, gameFile in pairs(GAME) do
            members[#members + 1] = { alphabet = alphabet, file = (alphabet == "russian" and cyrillic) and file or gameFile, height = size, flags = flags }
        end
        local ok, fam = pcall(CreateFontFamily, name, members)
        if ok and fam then obj = fam end
    end
    if not obj then
        obj = CreateFont(name)
        if not obj:SetFont(file, size, flags) and _G[fallback] then obj:SetFontObject(_G[fallback]) end
    end
    -- the file didn't load (a family member can't say): fall back to the game's font
    if not obj:GetFont() and _G[fallback] then obj:SetFontObject(_G[fallback]) end
    local c = T.C[color]
    obj:SetTextColor(c[1], c[2], c[3])
    return obj
end

for name, spec in pairs(OBJECTS) do
    if not _G[name] then _G[name] = MakeFont(name, spec) end
end

-- Upper case, as the dashboard's headings and buttons; text carrying the
-- game's escape codes (colours, links, icons) is left as it is.
function T.Upper(s)
    if type(s) ~= "string" or s:find("|", 1, true) then return s end
    return s:upper()
end

------------------------------------------------------------------------
-- Scanlines: a dark line every 4 units, tiled across `host` (a frame) or
-- `anchor` (a texture on it), drawn in `layer`. Returns the texture so a
-- caller can mask it (the round icons).
------------------------------------------------------------------------
function T:Scanlines(host, alpha, layer, sublevel, anchor)
    local tex = host:CreateTexture(nil, layer or "ARTWORK", nil, sublevel or 7)
    local ok = pcall(tex.SetTexture, tex, T.SCANLINES, "REPEAT", "REPEAT", "NEAREST")
    if not ok then tex:SetTexture(T.SCANLINES) end
    if tex.SetHorizTile then tex:SetHorizTile(true); tex:SetVertTile(true) end
    tex:SetAllPoints(anchor or host)
    tex:SetAlpha(alpha or 0.08)
    local function Fit()
        local w, h = tex:GetSize()
        if w and h and w > 0 and h > 0 then tex:SetTexCoord(0, w / 8, 0, h / 8) end
    end
    Fit()
    if host.HookScript then
        host:HookScript("OnSizeChanged", Fit)
        host:HookScript("OnShow", Fit)
    end
    return tex
end

------------------------------------------------------------------------
-- The guild's accent (Core/Accent.lua): everyday buttons and the open tab
-- wear it. Things that do register a repaint; it changes when the tabard
-- loads (after login) or the guild changes it.
------------------------------------------------------------------------
T.A = { face = T.C.yellow, shade = T.C.shade }
local accentUsers = {}
function T:OnAccent(fn) accentUsers[#accentUsers + 1] = fn end
function T:RefreshAccent()
    if not ns.Accent then return end
    local face, shade = ns.Accent.For(ns.Accent:Tabard())
    local function C3(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end
    if self.A.hex == face .. shade then return end
    self.A = { face = C3(face), shade = C3(shade), hex = face .. shade }
    for _, fn in ipairs(accentUsers) do pcall(fn) end
end

------------------------------------------------------------------------
-- Pixel edges, as the dashboard's boxes and buttons: four strips of
-- `thick` units just outside `anchor`, corners left open (notched).
------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"

function T:Edge(host, anchor, thick, color, layer, sublevel)
    local parts = {}
    local function Strip()
        local x = host:CreateTexture(nil, layer or "BORDER", nil, sublevel or 0)
        parts[#parts + 1] = x
        return x
    end
    local top = Strip()
    top:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
    top:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
    top:SetHeight(thick)
    local bottom = Strip()
    bottom:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thick)
    local left = Strip()
    left:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", 0, 0)
    left:SetWidth(thick)
    local right = Strip()
    right:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(thick)
    local e = { parts = parts }
    function e:SetColor(c, a) for _, x in ipairs(parts) do x:SetColorTexture(c[1], c[2], c[3], a or 1) end end
    function e:SetShown(on) for _, x in ipairs(parts) do x:SetShown(on) end end
    e:SetColor(color or T.C.edge)
    return e
end

-- A box: `fill` across the frame and a notched edge around it.
function T:Box(frame, fill, edge, thick)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(frame)
    local c = fill or T.C.bg1
    bg:SetColorTexture(c[1], c[2], c[3], 1)
    return bg, T:Edge(frame, frame, thick or 4, edge or T.C.edge, "BACKGROUND", -7)
end

-- A dashed rule (the dashboard's section headings: 4 tall, 8 on, 4 off).
function T:Dashes(host, layer)
    local tex = host:CreateTexture(nil, layer or "ARTWORK")
    local ok = pcall(tex.SetTexture, tex, T.DASH, "REPEAT", "CLAMP", "NEAREST")
    if not ok then tex:SetTexture(T.DASH) end
    if tex.SetHorizTile then tex:SetHorizTile(true) end
    tex:SetHeight(4)
    local c = T.C.line
    tex:SetVertexColor(c[1], c[2], c[3], 1)
    local function Fit()
        local w = tex:GetWidth()
        if w and w > 0 then tex:SetTexCoord(0, w / 12, 0, 1) end
    end
    if host.HookScript then
        host:HookScript("OnSizeChanged", Fit)
        host:HookScript("OnShow", Fit)
    end
    tex.Fit = Fit
    C_Timer.After(0, Fit)
    return tex
end

------------------------------------------------------------------------
-- Windows: the template's art (stone borders, gold title bar) hidden; the
-- dashboard's page instead: its dark background, a notched 4-unit edge,
-- faint scanlines. Everything in the window is then skinned (SkinTree).
------------------------------------------------------------------------
local ART = { "NineSlice", "Bg", "TitleBg", "TopTileStreaks", "TitleContainer", "Inset", "PortraitContainer" }

local function HideArt(region)
    if not region then return end
    if region.NineSlice then region.NineSlice:SetAlpha(0) end
    if region.Bg and region.Bg.SetAlpha then region.Bg:SetAlpha(0) end
    for _, r in ipairs({ region:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and r:GetDrawLayer() ~= "HIGHLIGHT" then r:SetAlpha(0) end
    end
end

function T:Skin(frame)
    if not frame or frame._ngmSkinned then return frame end
    frame._ngmSkinned = true
    pcall(function()
        HideArt(frame)
        for _, key in ipairs(ART) do
            local part = frame[key]
            if part and part ~= frame.CloseButton then HideArt(part) end
        end
        local portrait = frame.portrait or frame.Portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait)
        if portrait then portrait:SetAlpha(0) end
    end)
    local box = CreateFrame("Frame", nil, frame)
    box:SetAllPoints(frame)
    box:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    local bg = box:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(box)
    bg:SetColorTexture(T.C.bg[1], T.C.bg[2], T.C.bg[3], 0.97)
    T:Edge(box, box, 4, T.C.edge, "BACKGROUND", -7)
    T:Scanlines(box, 0.06, "BACKGROUND", -6)
    frame._ngmBox = box
    -- the title: mono, upper case, yellow, with the dashboard's hard red shadow
    local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText) or frame._title
    if title then
        title:SetFontObject(NGMFontTitle)
        if title.SetShadowColor then
            title:SetShadowColor(T.C.shade[1], T.C.shade[2], T.C.shade[3], 1)
            title:SetShadowOffset(2, -2)
        end
        local set = title.SetText
        set(title, T.Upper(title:GetText() or ""))
        hooksecurefunc(title, "SetText", function(fs, text)
            local up = T.Upper(text)
            if up ~= text then set(fs, up) end
        end)
    end
    local close = frame.CloseButton or (frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if close then T:SkinClose(close) end
    -- what's inside: now, and each time it opens (pages are built later)
    frame:HookScript("OnShow", function(f) C_Timer.After(0, function() T:SkinTree(f) end) end)
    T:SkinTree(frame)
    return frame
end

------------------------------------------------------------------------
-- Buttons, as the dashboard's: a solid face, a notched 3-unit border in
-- the text colour, a hard drop shadow in deep red; pressed, the button
-- moves onto its shadow. Mono upper case runs wider than the game's font,
-- so a label that doesn't fit drops a size, and past that ends in "...".
------------------------------------------------------------------------
local function Fit(b)
    local fs = b:GetFontString()
    if not fs or not b.SetNormalFontObject then return end
    local room = b:GetWidth() - (b.Arrow and 30 or 16)
    if room <= 0 then return end
    local function Use(font)
        b:SetNormalFontObject(font)
        b:SetHighlightFontObject(font)
    end
    fs:SetWidth(0)
    Use(NGMFontButton)
    local wide = (fs.GetUnboundedStringWidth or fs.GetStringWidth)(fs)
    if wide > room then Use(NGMFontButtonSmall) end
    fs:SetWidth(room)
    fs:SetWordWrap(false)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", b._ngmFace or b, "CENTER", b.Arrow and -7 or 0, 0)
end
T.FitButton = Fit

local function ClearArt(b)
    for _, key in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do
        if b[key] then b[key]:SetAlpha(0) end
    end
    for _, r in ipairs({ b:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
    end
    if b.SetNormalTexture then b:SetNormalTexture("") end
    if b.SetPushedTexture then b:SetPushedTexture("") end
    if b.SetHighlightTexture then b:SetHighlightTexture("") end
    if b.SetDisabledTexture then b:SetDisabledTexture("") end
end

-- The face, border and shadow; pressing moves face and border onto the
-- shadow. `inset`: the face sits that far inside the frame, so the border
-- stays within it and buttons laid side by side keep a margin.
local function Pressable(b, fill, thick, shadowAt, inset, shade)
    inset = inset or 0
    local function Fill() return type(fill) == "function" and fill() or fill end
    local function Shade() return shade and shade() or T.C.shade end
    local function Rest(tex, dx, dy)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", inset + dx, -inset + dy)
        tex:SetPoint("BOTTOMRIGHT", -inset + dx, inset + dy)
    end
    local shadow = b:CreateTexture(nil, "BACKGROUND", nil, -3)
    Rest(shadow, shadowAt[1], shadowAt[2])
    local face = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    Rest(face, 0, 0)
    local edge = T:Edge(b, face, thick, T.C.fg, "BACKGROUND", -2)
    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetColorTexture(1, 1, 1, 0.12)
    hi:SetAllPoints(face)
    b._ngmFace, b._ngmShadow, b._ngmEdge = face, shadow, edge
    b:HookScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        Rest(face, shadowAt[1], shadowAt[2])
        shadow:Hide()
    end)
    local function Up(self)
        Rest(face, 0, 0)
        shadow:SetShown(self:IsEnabled())
    end
    b:HookScript("OnMouseUp", Up)
    b:HookScript("OnHide", Up) -- a click that hides the button never gets its mouse-up
    local function State()
        local on = b:IsEnabled()
        local c = on and Fill() or T.C.line
        face:SetColorTexture(c[1], c[2], c[3], 1)
        local s = Shade()
        shadow:SetColorTexture(s[1], s[2], s[3], 1)
        edge:SetColor(on and T.C.fg or T.C.edge)
        shadow:SetShown(on)
    end
    if type(fill) == "function" then T:OnAccent(State) end
    hooksecurefunc(b, "Enable", State)
    hooksecurefunc(b, "Disable", State)
    if b.SetEnabled then hooksecurefunc(b, "SetEnabled", State) end
    State()
    return face
end

function T:SkinButton(b, style)
    if not b or b._ngmSkinned then return b end
    b._ngmSkinned = true
    -- everyday buttons wear the guild's accent; alt and bad keep theirs
    local fill = (style == "bad" and T.C.red) or (style == "alt" and T.C.aqua) or function() return T.A.face end
    ClearArt(b)
    Pressable(b, fill, 2, { 3, -4 }, 3, type(fill) == "function" and function() return T.A.shade end or nil)
    local fs = b:GetFontString()
    if fs then fs:SetFontObject(NGMFontButton) end
    if b.SetNormalFontObject then
        b:SetNormalFontObject(NGMFontButton)
        b:SetHighlightFontObject(NGMFontButton)
        b:SetDisabledFontObject(NGMFontDimSmall)
    end
    if b.SetText and b.GetText then
        local set = b.SetText
        set(b, T.Upper(b:GetText() or ""))
        hooksecurefunc(b, "SetText", function(self, text)
            local up = T.Upper(text)
            if up ~= text then set(self, up) end
            Fit(self)
        end)
    end
    Fit(b)
    b:HookScript("OnSizeChanged", Fit)
    b:HookScript("OnShow", Fit)
    return b
end

-- A window's close button: a small red button with an X.
function T:SkinClose(b)
    if not b or b._ngmSkinned then return b end
    b._ngmSkinned = true
    ClearArt(b)
    b:SetSize(18, 18)
    local p = b:GetParent()
    if p then
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -9, -7)
    end
    local face = Pressable(b, T.C.red, 2, { 3, -4 })
    local x = b:CreateFontString(nil, "OVERLAY", "NGMFontButton")
    x:SetPoint("CENTER", face, "CENTER", 1, 0)
    x:SetText("X")
    return b
end

------------------------------------------------------------------------
-- Everything else Blizzard drew, the dashboard's way. SkinTree walks a
-- window once each time it opens and skins what it hasn't yet.
------------------------------------------------------------------------
local function SolidFrame(host, anchor, fill, edge, thick, inset)
    inset = inset or 0
    local border = host:CreateTexture(nil, "BACKGROUND", nil, -8)
    border:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset - thick, thick - inset)
    border:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", thick - inset, inset - thick)
    border:SetColorTexture(edge[1], edge[2], edge[3], 1)
    local bg = host:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetPoint("TOPLEFT", border, "TOPLEFT", thick, -thick)
    bg:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -thick, thick)
    bg:SetColorTexture(fill[1], fill[2], fill[3], 1)
    return bg, border
end

-- Tick boxes: the dashboard's dark square with a 2-unit edge; ticked, a
-- yellow square inside.
function T:SkinCheck(cb)
    if cb._ngmSkinned then return end
    cb._ngmSkinned = true
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = cb[get] and cb[get](cb)
        if t then t:SetAlpha(0) end
    end
    local box = cb:CreateTexture(nil, "BACKGROUND", nil, -6)
    box:SetSize(14, 14)
    box:SetPoint("CENTER")
    box:SetColorTexture(0, 0, 0, 0)
    SolidFrame(cb, box, T.C.bg, T.C.edge, 2)
    local tick = cb:CreateTexture(nil, "ARTWORK")
    tick:SetSize(8, 8)
    tick:SetPoint("CENTER", box, "CENTER")
    tick:SetColorTexture(T.C.yellow[1], T.C.yellow[2], T.C.yellow[3], 1)
    cb:SetCheckedTexture(tick)
    if cb.SetDisabledCheckedTexture then
        local off = cb:CreateTexture(nil, "ARTWORK")
        off:SetSize(8, 8)
        off:SetPoint("CENTER", box, "CENTER")
        off:SetColorTexture(T.C.faint[1], T.C.faint[2], T.C.faint[3], 1)
        cb:SetDisabledCheckedTexture(off)
    end
    local hl = cb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(box)
    hl:SetColorTexture(1, 1, 1, 0.12)
    cb:SetHighlightTexture(hl)
    local label = cb.Text or cb.text
    if label and label.GetFontObject and label:GetFontObject() ~= NGMFontTextSmall then label:SetFontObject(NGMFontTextSmall) end
end

-- Text fields: the dashboard's dark field with a solid 2-unit edge.
function T:SkinEdit(eb)
    if eb._ngmSkinned then return end
    eb._ngmSkinned = true
    local name = eb:GetName()
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do
        local t = eb[key] or (name and _G[name .. key])
        if t then t:SetAlpha(0) end
    end
    local left = eb.searchIcon and -2 or -6
    local anchor = eb:CreateTexture(nil, "BACKGROUND", nil, -5)
    anchor:SetPoint("TOPLEFT", left, 0)
    anchor:SetPoint("BOTTOMRIGHT", 0, 0)
    anchor:SetColorTexture(0, 0, 0, 0)
    SolidFrame(eb, anchor, T.C.bg, T.C.edge, 2)
    if eb.searchIcon then eb.searchIcon:SetVertexColor(T.C.dim[1], T.C.dim[2], T.C.dim[3]) end
    eb:SetFontObject(NGMFontTextSmall)
    if eb.Instructions then eb.Instructions:SetFontObject(NGMFontDimSmall) end
end

-- Scroll bars: a thin dark track and a block for a thumb; the arrows go.
function T:SkinScroll(sf)
    local sb = sf.ScrollBar or (sf:GetName() and _G[sf:GetName() .. "ScrollBar"])
    if not sb or sb._ngmSkinned then return end
    sb._ngmSkinned = true
    local function Hide(f)
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
        end
        for _, c in ipairs({ f:GetChildren() }) do Hide(c) end
    end
    Hide(sb)
    local track = sb:CreateTexture(nil, "BACKGROUND", nil, -8)
    track:SetWidth(6)
    local c = T.C.line
    track:SetColorTexture(c[1], c[2], c[3], 1)
    local e = T.C.edge
    local thumbFrame = sb.Track and sb.Track.Thumb
    if thumbFrame then
        track:SetPoint("TOP", sb.Track, "TOP")
        track:SetPoint("BOTTOM", sb.Track, "BOTTOM")
        local t = thumbFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetPoint("TOP")
        t:SetPoint("BOTTOM")
        t:SetWidth(6)
        t:SetColorTexture(e[1], e[2], e[3], 1)
    else
        track:SetPoint("TOP", sb, "TOP", 0, 0)
        track:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
        local thumb = sb.ThumbTexture or (sb.GetThumbTexture and sb:GetThumbTexture())
        if thumb then
            thumb:SetColorTexture(e[1], e[2], e[3], 1)
            thumb:SetSize(6, 28)
            thumb:SetAlpha(1)
        end
    end
end

-- Panels drawn with the old tooltip border: the dashboard's box instead
-- (their own background colour is kept; the edge becomes notched pixels).
function T:SkinBackdrop(f)
    if f._ngmSkinned or not f.SetBackdrop then return end
    local info = f.backdropInfo
    local edgeFile = info and info.edgeFile
    if type(edgeFile) ~= "string" or not edgeFile:find("Tooltip") then return end
    f._ngmSkinned = true
    local r, g, b, a = f:GetBackdropColor()
    f:SetBackdrop({ bgFile = WHITE })
    if r then f:SetBackdropColor(r, g, b, a) end
    -- the old warm near-black becomes the dashboard's box colour
    if r and r < 0.1 and g < 0.1 and b < 0.1 then f:SetBackdropColor(T.C.bg1[1], T.C.bg1[2], T.C.bg1[3], 1) end
    T:Edge(f, f, 3, T.C.edge, "BACKGROUND", 1)
end

function T:SkinTree(root)
    if not root or not root.GetChildren then return end
    for _, c in ipairs({ root:GetChildren() }) do
        local kind = c.GetObjectType and c:GetObjectType()
        if not c._ngmSkinned then
            if kind == "CheckButton" and c.GetCheckedTexture and (c.Text or c.text or c:GetCheckedTexture()) and not c._ngmTab then
                T:SkinCheck(c)
            elseif kind == "EditBox" and (c.Left or c.Middle or c.searchIcon or (c:GetName() and _G[c:GetName() .. "Left"])) then
                T:SkinEdit(c)
            elseif kind == "ScrollFrame" then
                T:SkinScroll(c)
            elseif kind == "Button" and c == root.CloseButton then
                T:SkinClose(c)
            elseif c.backdropInfo then
                T:SkinBackdrop(c)
            end
        end
        T:SkinTree(c)
    end
end
------------------------------------------------------------------------
-- Toast: an arcade banner at the top of the screen. The title drops in
-- in steps, blinks three times, then the banner goes after a few seconds.
------------------------------------------------------------------------
local toast
function T:Toast(title, text)
    if not toast then
        toast = CreateFrame("Frame", nil, UIParent)
        toast:SetSize(360, 64)
        toast:SetPoint("TOP", 0, -140)
        toast:SetFrameStrata("DIALOG")
        T:Box(toast, T.C.bg1, T.C.yellow, 4)
        T:Scanlines(toast, 0.12, "ARTWORK")
        toast.title = toast:CreateFontString(nil, "OVERLAY", "NGMFontHuge")
        toast.title:SetPoint("TOP", 0, -10)
        toast.text = toast:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
        toast.text:SetPoint("TOP", toast.title, "BOTTOM", 0, -4)
        toast.text:SetWidth(330)
        -- drop in: four 6-unit steps
        local drop = toast:CreateAnimationGroup()
        for i = 1, 4 do
            local m = drop:CreateAnimation("Translation")
            m:SetOffset(0, i == 1 and 24 or -6)
            m:SetDuration(0.001)
            m:SetStartDelay(i == 1 and 0 or 0.06)
            m:SetOrder(i)
        end
        -- blink: hidden and shown, three times
        local blink = toast.title:CreateAnimationGroup()
        for i = 1, 6 do
            local a = blink:CreateAnimation("Alpha")
            a:SetFromAlpha(i % 2 == 1 and 1 or 0)
            a:SetToAlpha(i % 2 == 1 and 0 or 1)
            a:SetDuration(0.001)
            a:SetStartDelay(0.18)
            a:SetOrder(i)
        end
        toast.drop, toast.blink = drop, blink
        toast:SetScript("OnHide", function(self) self.blink:Stop() end)
    end
    toast.title:SetText(T.Upper(title or ""))
    toast.text:SetText(text or "")
    toast:SetHeight(text and text ~= "" and 70 or 48)
    toast:Show()
    toast.drop:Stop(); toast.drop:Play()
    toast.blink:Stop(); toast.blink:Play()
    toast.shown = (toast.shown or 0) + 1
    local mine = toast.shown
    C_Timer.After(3.5, function() if toast.shown == mine then toast:Hide() end end)
end
