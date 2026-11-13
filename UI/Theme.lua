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

local DIR = "Interface\\AddOns\\NootropicGuildManager\\Media\\Fonts\\"
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
------------------------------------------------------------------------
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
        end)
    end
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
