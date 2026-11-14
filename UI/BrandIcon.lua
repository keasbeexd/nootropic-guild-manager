--[[
    Nootropic Guild Manager - Brand icon
    One renderer for the addon's icon wherever it appears (window portrait,
    minimap button, Guild & Communities shortcut, options previews).
    Styles: your guild's tabard (the default) or the Nootropic medallion
    (Media/Logo.tga), which the tabard falls back to outside a guild or
    without one.

    Large icons copy Blizzard's own guild portrait (CommunitiesFrame
    PortraitOverlay): a 60x60 circle, the tabard background and border from
    Interface\GuildFrame\GuildFrame, and a 56x64 emblem centered on top,
    everything scaled from that 60px reference. Small ones (under 48px) get
    the guild's background color and the emblem only (see ShowEmblem).

      ns.Brand:AttachPortrait(frame)                 -- window portrait
      ns.Brand:Attach(host, size, point, opts)       -- anywhere else

    Large icons (the window portrait) are a little CRT screen, as the
    dashboard's arcade look: either style shown on rounded glass, with
    scanlines, darker curved edges and a glare, in a casing with a hard
    drop shadow. The tabard's own ring isn't drawn there.
]]
local _, ns = ...
local D = ns.Data
local Brand = {}
ns.Brand = Brand

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GUILD_ART = "Interface\\GuildFrame\\GuildFrame"
local BG_COORDS = { 0.63183594, 0.69238281, 0.61914063, 0.74023438 }
local BORDER_COORDS = { 0.63183594, 0.69238281, 0.74414063, 0.86523438 }

Brand.icons = {}

function Brand:Style()
    return ns.DB:Settings().iconStyle or "emblem"
end

-- True when there's a guild tabard to draw, and the game has loaded it:
-- drawn before then, the game paints its placeholder (a parchment) and the
-- icon kept it ("sometimes" a map on the Guild window's button).
function Brand:CanShowEmblem()
    if not IsInGuild() or not SetLargeGuildTabardTextures then return false end
    if C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
        local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
        if ok and info == nil then return false end
        if ok and type(info) == "table" and type(info.emblemFileID) == "number" and info.emblemFileID <= 0 then return false end
    end
    return true
end

local IconMixin = {}

-- Small icons (the minimap button, the Guild & Communities tab, Options
-- previews) can't use the guild portrait's art: it's drawn for 60 pixels,
-- and its ring doubles the host's own frame. They get the guild's
-- background color and the emblem instead.
local SMALL = 48

function IconMixin:ShowEmblem(on)
    local small = self.size < SMALL
    self.Bg:SetShown(on)
    self.Border:SetShown(on and not small and not self.crt)
    self.Emblem:SetShown(on)
    self.Icon:SetShown(not on)
end

-- The guild's tabard background color, or a dark gray.
local function TabardBackground()
    if C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
        local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
        local c = ok and info and info.backgroundColor
        if c and c.GetRGB then return c:GetRGB() end
    end
    return 0.15, 0.15, 0.15
end

-- again: this is the one recheck after drawing (never schedules another)
function IconMixin:Apply(again)
    local key = self.fixedStyle or Brand:Style()
    if key == "emblem" and Brand:CanShowEmblem() then
        local s = self.size / 60
        self.Emblem:SetSize(56 * s, 64 * s) -- the game sets width from height (7:8)
        local ok
        if self.size < SMALL or self.crt then
            -- the game colors the emblem (on the CRT, the tabard's colour
            -- fills the whole screen); the rest it would draw goes to
            -- textures that are never shown
            ok = pcall(SetLargeGuildTabardTextures, "player", self.Emblem, self.SpareBg, self.SpareBorder)
            self.Bg:SetColorTexture(TabardBackground())
            self.Bg:SetTexCoord(0, 1, 0, 1)
        else
            self.Bg:SetTexture(GUILD_ART)
            self.Bg:SetTexCoord(unpack(BG_COORDS))
            self.Border:SetTexture(GUILD_ART)
            self.Border:SetTexCoord(unpack(BORDER_COORDS))
            ok = pcall(SetLargeGuildTabardTextures, "player", self.Emblem, self.Bg, self.Border)
        end
        if ok then
            self:ShowEmblem(true)
            -- the tabard can finish loading just after: draw it once more (once)
            if not again and not self.recheck and C_Timer then
                self.recheck = true
                C_Timer.After(3, function() self.recheck = nil; self:Apply(true) end)
            end
            return
        end
    end
    self:ShowEmblem(false)
    local style = D:IconStyle(key)
    self.Icon:SetTexture(style.icon or D.DEFAULT_ICON)
    if style.fullArt then
        -- `crop`: trim the medallion's own gold ring where the host already
        -- draws a round border (the minimap button), so there's one ring
        local c = self.crop or 0
        self.Icon:SetTexCoord(c, 1 - c, c, 1 - c)
    else
        self.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim a game icon's border
    end
end

--[[
    host:  frame the textures are drawn on (so they layer with its own art)
    size:  icon size in pixels
    point: { point, relativeTo, relativePoint, x, y } for the icon
    opts:  layer (default ARTWORK), round (default true), style (fixed style),
           crop (0-0.5: trim that much off each edge of the medallion art)
]]
function Brand:Attach(host, size, point, opts)
    opts = opts or {}
    local layer = opts.layer or "ARTWORK"
    local s = size / 60
    local icon = { host = host, size = size, fixedStyle = opts.style, crop = opts.crop }
    for k, v in pairs(IconMixin) do icon[k] = v end

    -- Reference square everything is placed against.
    local slot = host:CreateTexture(nil, "BACKGROUND")
    slot:SetSize(size, size)
    slot:SetPoint(unpack(point))
    slot:SetColorTexture(0, 0, 0, 0)
    icon.Slot = slot

    icon.Icon = host:CreateTexture(nil, layer, nil, 1)
    icon.Icon:SetAllPoints(slot)
    icon.Bg = host:CreateTexture(nil, layer, nil, 1)
    icon.Bg:SetAllPoints(slot)
    icon.Emblem = host:CreateTexture(nil, layer, nil, 2)
    icon.Emblem:SetSize(56 * s, 64 * s)
    icon.Emblem:SetPoint("CENTER", slot, "CENTER", 0, 1 * s)
    icon.SpareBg = host:CreateTexture(nil, layer)
    icon.SpareBorder = host:CreateTexture(nil, layer)
    icon.SpareBg:Hide()
    icon.SpareBorder:Hide()
    icon.Border = host:CreateTexture(nil, layer, nil, 3)
    icon.Border:SetSize(size, 59 * s)
    icon.Border:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -1 * s)

    local masked = { icon.Icon, icon.Bg, icon.Emblem, icon.Border }
    local shape = MASK
    if size >= SMALL and ns.Theme and ns.Theme.CRT and opts.round ~= false then
        -- a CRT: casing and its hard shadow, a dark screen, then over the
        -- picture scanlines, the glass's darker edges and its glare
        local crt = ns.Theme.CRT
        icon.crt = true
        shape = crt.mask
        local casing = 6 * s
        icon.Shadow = host:CreateTexture(nil, layer, nil, -4)
        icon.Shadow:SetTexture(crt.mask)
        icon.Shadow:SetVertexColor(0, 0, 0, 0.7)
        icon.Shadow:SetPoint("TOPLEFT", slot, "TOPLEFT", -casing + 4 * s, casing - 4 * s)
        icon.Shadow:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", casing + 4 * s, -casing - 4 * s)
        icon.Casing = host:CreateTexture(nil, layer, nil, -3)
        icon.Casing:SetTexture(crt.mask)
        local e = ns.Theme.C.edge
        ns.Theme:Tint(icon.Casing, e)
        icon.Casing:SetPoint("TOPLEFT", slot, "TOPLEFT", -casing, casing)
        icon.Casing:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", casing, -casing)
        icon.Screen = host:CreateTexture(nil, layer, nil, -2)
        icon.Screen:SetAllPoints(slot)
        local bg = ns.Theme.C.bg
        ns.Theme:Paint(icon.Screen, bg)
        icon.Lines = ns.Theme:Scanlines(host, 0.35, layer, 4, slot)
        icon.Shade = host:CreateTexture(nil, layer, nil, 5)
        icon.Shade:SetTexture(crt.shade)
        icon.Shade:SetAllPoints(slot)
        icon.Glass = host:CreateTexture(nil, layer, nil, 6)
        icon.Glass:SetTexture(crt.glass)
        icon.Glass:SetAllPoints(slot)
        for _, t in ipairs({ icon.Screen, icon.Lines, icon.Shade, icon.Glass }) do masked[#masked + 1] = t end
    end
    if opts.round ~= false and host.CreateMaskTexture then
        local mask = host:CreateMaskTexture()
        if mask then
            mask:SetTexture(shape, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(slot)
            for _, t in ipairs(masked) do
                if t.AddMaskTexture then t:AddMaskTexture(mask) end
            end
        end
    end

    table.insert(self.icons, icon)
    icon:Apply()
    return icon
end

-- Window portrait, placed exactly like Blizzard's guild portrait overlay.
function Brand:AttachPortrait(frame)
    local p = (frame.PortraitContainer and frame.PortraitContainer.portrait) or frame.portrait or frame.Portrait
    if p then p:Hide() end
    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(frame:GetFrameLevel() + 300)
    overlay:EnableMouse(false)
    local icon = self:Attach(overlay, 60, { "TOPLEFT", overlay, "TOPLEFT", -2, 6 }, { layer = "BACKGROUND" })
    icon.Overlay = overlay
    return icon
end

function Brand:Refresh()
    for _, icon in ipairs(self.icons) do icon:Apply() end
    ns:Fire("BRAND_CHANGED")
end

function Brand:SetStyle(key)
    ns.DB:Settings().iconStyle = key
    self:Refresh()
end

function Brand:Init()
    -- The emblem isn't known until guild data arrives, and it can change.
    local function queue()
        if Brand:Style() == "emblem" then ns.Debounce("brand", 0.5, function() Brand:Refresh() end) end
        -- the guild's accent comes from the same tabard
        ns.Debounce("accent", 0.5, function() ns.Theme:RefreshAccent() end)
    end
    ns:RegisterEvent("PLAYER_GUILD_UPDATE", queue)
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", queue)
    queue()
end
