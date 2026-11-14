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
    ns.Theme:Skin(frame)       a window in the theme's colours (template art hidden)
    ns.Theme:SkinButton(b)     a button in the theme's colours
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
-- Windows: the template's art (stone borders, gold title bar) hidden, a
-- dark box with a square edge instead, as the dashboard's boxes.
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

function T:Skin(frame, opts)
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
    local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    box:SetAllPoints(frame)
    box:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    box:SetBackdropColor(T.C.bg[1], T.C.bg[2], T.C.bg[3], 0.97)
    box:SetBackdropBorderColor(T.C.edge[1], T.C.edge[2], T.C.edge[3], 1)
    frame._ngmBox = box
    -- arcade: a hard drop shadow (no blur) and faint scanlines
    local shadow = CreateFrame("Frame", nil, frame)
    shadow:SetPoint("TOPLEFT", 6, -6)
    shadow:SetPoint("BOTTOMRIGHT", 6, -6)
    shadow:SetFrameLevel(math.max(box:GetFrameLevel() - 1, 0))
    local dark = shadow:CreateTexture(nil, "BACKGROUND")
    dark:SetAllPoints()
    dark:SetColorTexture(0, 0, 0, 0.55)
    T:Scanlines(box, 0.10, "ARTWORK")
    -- a yellow HUD line under the title bar
    local hud = box:CreateTexture(nil, "ARTWORK", nil, 6)
    hud:SetColorTexture(T.C.yellow[1], T.C.yellow[2], T.C.yellow[3], 0.9)
    hud:SetHeight(2)
    hud:SetPoint("TOPLEFT", 2, -(opts and opts.hud or 24))
    hud:SetPoint("TOPRIGHT", -2, -(opts and opts.hud or 24))
    -- the title: mono, upper case, yellow
    local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText) or frame._title
    if title then
        title:SetFontObject(NGMFontTitle)
        local set = title.SetText
        set(title, T.Upper(title:GetText() or ""))
        hooksecurefunc(title, "SetText", function(fs, text)
            local up = T.Upper(text)
            if up ~= text then set(fs, up) end
        end)
    end
    return frame
end

------------------------------------------------------------------------
-- Buttons: yellow with dark mono text and a hard shadow, as the dashboard's.
-- Mono upper case runs wider than the game's font, so a label that doesn't
-- fit drops to a smaller size, and past that ends in "..." inside the face.
------------------------------------------------------------------------
local function Fit(b)
    local fs = b:GetFontString()
    if not fs or not b.SetNormalFontObject then return end
    local room = b:GetWidth() - (b.Arrow and 26 or 12)
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
    fs:SetPoint("CENTER", b, "CENTER", b.Arrow and -7 or 0, 0)
end
T.FitButton = Fit

function T:SkinButton(b, style)
    if not b or b._ngmSkinned then return b end
    b._ngmSkinned = true
    local fill = T.C[style == "bad" and "red" or style == "alt" and "aqua" or "yellow"]
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
    local shadow = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    shadow:SetColorTexture(T.C.shade[1], T.C.shade[2], T.C.shade[3], 1)
    shadow:SetPoint("TOPLEFT", 3, -3)
    shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    local face = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    face:SetColorTexture(fill[1], fill[2], fill[3], 1)
    face:SetAllPoints(b)
    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetColorTexture(1, 1, 1, 0.12)
    hi:SetAllPoints(b)
    b._ngmFace, b._ngmShadow = face, shadow
    local fs = b:GetFontString()
    if fs then fs:SetFontObject(NGMFontButton) end
    T:Scanlines(b, 0.10, "BACKGROUND", 0, face)
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
    -- pressed: the face moves onto its shadow
    b:HookScript("OnMouseDown", function(self) if self:IsEnabled() then face:SetPoint("TOPLEFT", 2, -2); face:SetPoint("BOTTOMRIGHT", 2, -2) end end)
    b:HookScript("OnMouseUp", function() face:ClearAllPoints(); face:SetAllPoints(b) end)
    local function State()
        local on = b:IsEnabled()
        local c = on and fill or T.C.line
        face:SetColorTexture(c[1], c[2], c[3], 1)
        shadow:SetShown(on)
    end
    hooksecurefunc(b, "Enable", State)
    hooksecurefunc(b, "Disable", State)
    if b.SetEnabled then hooksecurefunc(b, "SetEnabled", State) end
    State()
    return b
end

------------------------------------------------------------------------
-- Toast: an arcade banner at the top of the screen. The title drops in
-- in steps, blinks three times, then the banner goes after a few seconds.
------------------------------------------------------------------------
local toast
function T:Toast(title, text)
    if not toast then
        toast = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        toast:SetSize(360, 64)
        toast:SetPoint("TOP", 0, -140)
        toast:SetFrameStrata("DIALOG")
        toast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
        toast:SetBackdropColor(T.C.bg[1], T.C.bg[2], T.C.bg[3], 0.97)
        toast:SetBackdropBorderColor(T.C.yellow[1], T.C.yellow[2], T.C.yellow[3], 1)
        local sh = toast:CreateTexture(nil, "BACKGROUND", nil, -8)
        sh:SetColorTexture(T.C.shade[1], T.C.shade[2], T.C.shade[3], 1)
        sh:SetPoint("TOPLEFT", 5, -5)
        sh:SetPoint("BOTTOMRIGHT", 5, -5)
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
