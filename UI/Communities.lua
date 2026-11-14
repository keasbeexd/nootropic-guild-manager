--[[
    Nootropic Guild Manager - Guild & Communities shortcut
    Adds a side tab with the addon icon to the game's Guild & Communities
    window, placed like Blizzard's own side tabs (32x32, frame level 510)
    but drawn as the addon's pixel tiles (as its own side tabs). No pushed
    art: the click opens our window, and the button can miss its mouse-up,
    which left Blizzard's pushed art stuck on. The older GuildFrame gets one
    too if this client has it. Each window gets its own tab, so one loading
    first never blocks the other.
]]
local _, ns = ...
local CM = {}
ns.Communities = CM

-- Blizzard's side tabs, top to bottom; ours goes under the last one present.
local SIDE_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }
local TAB_LEVEL = 510

CM.buttons = {} -- [hostName] = button

local function Hosts()
    local list = {}
    if CommunitiesFrame then list[#list + 1] = { name = "CommunitiesFrame", frame = CommunitiesFrame } end
    if GuildFrame then list[#list + 1] = { name = "GuildFrame", frame = GuildFrame } end
    return list
end

function CM:IsEnabled()
    return ns.DB:Settings().communitiesButton ~= false
end

function CM:SetEnabled(on)
    ns.DB:Settings().communitiesButton = on and true or false
    self:Attach()
    for _, b in pairs(self.buttons) do b:SetShown(on) end
    ns:Fire("SETTINGS_CHANGED")
end

local function CreateTab(host)
    local b = CreateFrame("Button", nil, host)
    b:SetSize(32, 32)
    b:SetFrameLevel(math.max(TAB_LEVEL, host:GetFrameLevel() + 10))

    local anchor
    for _, key in ipairs(SIDE_TABS) do
        if host[key] then anchor = host[key] end
    end
    if anchor then
        b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    else
        b:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -36)
    end

    local T = ns.Theme
    local bg = b:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetColorTexture(T.C.bg1[1], T.C.bg1[2], T.C.bg1[3], 1)
    local edge = T:Edge(b, b, 3, T.C.edge, "BACKGROUND", -5)

    b.Icon = ns.Brand:Attach(b, 28, { "CENTER", b, "CENTER", 0, 0 }, { round = false })

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)
    b:HookScript("OnEnter", function() edge:SetColor(T.C.fg) end)
    b:HookScript("OnLeave", function() edge:SetColor(T.C.edge) end)
    -- each time the window opens: the icon fresh (the tabard can load late)
    b:SetScript("OnShow", function(self) self.Icon:Apply() end)
    b:SetScript("OnClick", function() ns.UI:Show() end)
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.UI:Title())
        GameTooltip:AddLine("Search the guild, recruit and see the audit.", 1, 1, 1, true)
        GameTooltip:AddLine("You can hide this tab in the addon's options.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function CM:Attach()
    for _, h in ipairs(Hosts()) do
        local b = self.buttons[h.name]
        if not b then
            b = CreateTab(h.frame)
            self.buttons[h.name] = b
        end
        b:SetShown(self:IsEnabled())
    end
end

-- /ngm diag: what the shortcut can see, for troubleshooting.
function CM:Diagnose()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities")
    ns:Print(("Guild & Communities: addon loaded=%s, CommunitiesFrame=%s, GuildFrame=%s, shortcut enabled=%s"):format(
        tostring(loaded), tostring(CommunitiesFrame ~= nil), tostring(GuildFrame ~= nil), tostring(self:IsEnabled())))
    for name, b in pairs(self.buttons) do
        local _, rel = b:GetPoint(1)
        local relName = rel and rel.GetName and rel:GetName() or (rel and tostring(rel)) or "?"
        ns:Print(("  tab on %s: shown=%s visible=%s level=%d, under %s"):format(name, tostring(b:IsShown()), tostring(b:IsVisible()), b:GetFrameLevel() or 0, relName))
        -- what the button draws (the "map" hunt): each picture, shown or not, and its file
        local i = b.Icon
        if i then
            for _, key in ipairs({ "Icon", "Bg", "Emblem", "Border" }) do
                local t = i[key]
                if t then ns:Print(("    %s: shown=%s file=%s"):format(key, tostring(t:IsShown()), tostring(t:GetTexture()))) end
            end
            ns:Print(("    style=%s emblem ready=%s"):format(tostring(ns.Brand:Style()), tostring(ns.Brand:CanShowEmblem())))
        end
        -- anything of the game's drawn at the same spot, above it
        if b.GetCenter and b:GetParent() then
            local bx, by = b:GetCenter()
            for _, c in ipairs({ b:GetParent():GetChildren() }) do
                if c ~= b and c:IsVisible() and c.GetCenter then
                    local cx, cy = c:GetCenter()
                    if cx and bx and math.abs(cx - bx) < 16 and math.abs(cy - by) < 16 then
                        ns:Print(("    also here: %s level=%d"):format(c:GetName() or tostring(c), c:GetFrameLevel() or 0))
                    end
                end
            end
        end
    end
    if next(self.buttons) == nil then ns:Print("  no tab yet - open the Guild & Communities window once, then run /ngm diag again.") end
end

function CM:Init()
    -- The Guild & Communities window loads on demand, so watch for it.
    ns:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_Communities" or name == "Blizzard_GuildUI" then CM:Attach() end
    end)
    -- Some clients create the window without a separate load event.
    if hooksecurefunc then
        for _, fn in ipairs({ "ToggleGuildFrame", "ToggleCommunitiesFrame" }) do
            if _G[fn] then hooksecurefunc(fn, function() CM:Attach() end) end
        end
    end
    self:Attach()
end
