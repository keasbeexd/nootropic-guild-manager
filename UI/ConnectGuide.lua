--[[
    Nootropic Guild Manager - Get Connected (3.1)
    With NGM Peon, the steps that put a member's game and Discord together,
    each with where it stands:

      1. NGM Addon             done (you're reading this)
      2. Link with NGM Peon    /ngm link in Discord (LK records, from NGM Peon)
      3. NGM Desktop           optional: sends and brings in by itself
      4. Discord in WoW        Options, Social, Discord: so guild chat shows in
                               Discord as you. Addons can't read it (C_Discord
                               is Blizzard's only), so NGM Peon tells: it sees
                               the guild chat Blizzard posts, as the player's
                               own account once connected (DX records). Only
                               when the guild's chat reaches its Discord
                               (GS:gamechat).

    Opens by itself a little after login when step 2 or 4 is still to do
    (NGM Desktop users too), at most every few days; Not Now and Don't Show
    Again. /ngm connect and Options open it any time.
]]
local _, ns = ...
local W = ns.Widgets
local CG = {}
ns.ConnectGuide = CG

CG.REMIND_EVERY = 3 * 86400
local GREEN, ORANGE, GRAY = "|cff6cbf5a", "|cfffe8019", "|cff9d9d9d"

-- this player's characters: their main and its alts
local function Mine()
    local me = ns.PlayerFullName()
    local root = ns.DB:RootOf(me) or me
    local out = { root }
    for _, a in ipairs(ns.DB:GetAltsOf(root) or {}) do out[#out + 1] = a end
    if root ~= me then
        local seen = false
        for _, n in ipairs(out) do if n == me then seen = true end end
        if not seen then out[#out + 1] = me end
    end
    return out
end

local function Linked()
    for _, n in ipairs(Mine()) do if ns.Sync:Linked(n) then return true end end
    return false
end

-- "1" connected, "0" not yet, nil not seen
function CG:DiscordInWoW()
    local state
    for _, n in ipairs(Mine()) do
        local rec = ns.Sync:Plan("DX:" .. n)
        if rec and rec.v == "1" then return "1" end
        if rec and rec.v == "0" then state = "0" end
    end
    return state
end

local function GuildChatOnDiscord()
    local rec = ns.Sync:Plan("GS:gamechat")
    return rec ~= nil and rec.v == "1"
end

function CG:OpenSocial()
    if InCombatLockdown and InCombatLockdown() then ns:Print("Not in combat. Try again after the fight.") return end
    local S = rawget(_G, "Settings")
    if S and S.OpenToCategory and S.SOCIAL_CATEGORY_ID then
        S.OpenToCategory(S.SOCIAL_CATEGORY_ID)
    else
        ns:Print("Press Escape, then Options, Social. Discord is at the bottom.")
    end
end

-- The steps, each { title, state = "done" | "todo" | "optional" | "unknown", text, button = { label, fn } }
function CG:Steps()
    local steps = {}
    steps[#steps + 1] = { title = "NGM Addon", state = "done", text = "Installed." }
    local linked = Linked()
    steps[#steps + 1] = { title = "Link with NGM Peon", state = linked and "done" or "todo",
        text = linked and "Your characters are linked: on Discord they count as you, and you can sign up for events here."
            or "In your guild's Discord, type " .. ns.GOLD .. "/ngm link|r and sign in with Battle.net. It shows here after the next update from NGM Peon." }
    local desktop = ns.DiscordCode:DesktopInstalled()
    steps[#steps + 1] = { title = "NGM Desktop", state = desktop and "done" or "optional",
        text = desktop and "Installed: your changes go to Discord, and NGM Peon's news comes in, at every logout and /reload."
            or "Recommended: from " .. ns.GOLD .. "ngmpeon.app|r. It sends your changes to Discord and brings NGM Peon's news in by itself, at every logout and /reload." }
    if GuildChatOnDiscord() then
        local dx = self:DiscordInWoW()
        steps[#steps + 1] = { title = "Discord in WoW", state = dx == "1" and "done" or dx == "0" and "todo" or "unknown",
            text = dx == "1" and "Connected: your guild chat shows in Discord as you."
                or ("So your guild chat shows in Discord as you, not as a stand-in: Options, Social, at the bottom, "
                    .. ns.GOLD .. "Enable Discord functionality|r, then sign in."
                    .. (dx == nil and " (NGM Peon hasn't seen your guild chat yet: it checks when you next talk in it.)" or "")),
            button = dx ~= "1" and { label = "Open Options", fn = function() CG:OpenSocial() end } or nil }
    end
    return steps
end

-- Worth opening by itself: with NGM Peon, linking or Discord in WoW still to do
function CG:Needed()
    if not (ns.Sync.PeonGuild and ns.Sync:PeonGuild()) then return false end
    for _, s in ipairs(self:Steps()) do
        if s.state == "todo" then return true end
    end
    return false
end

local LABEL = { done = GREEN .. "Done|r", todo = ORANGE .. "To do|r", optional = GRAY .. "Optional|r", unknown = GRAY .. "Not seen yet|r" }

function CG:Build()
    local f = CreateFrame("Frame", "NootropicGMConnect", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(480, 360)
    f:SetPoint("TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "NootropicGMConnect")
    ns.Gamepad:Register(f, "popup")
    W.SetTitle(f, "Get Connected")
    self.frame = f
    self.intro = f:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.intro:SetPoint("TOPLEFT", 18, -34)
    self.intro:SetPoint("TOPRIGHT", -18, -34)
    self.intro:SetJustifyH("LEFT")
    self.intro:SetText("Your guild uses NGM Peon on Discord. These steps put your game and Discord together:")
    self.rows = {}
    self.later = W.Button(f, "Not Now", 110, 24, "alt")
    self.later:SetPoint("BOTTOMRIGHT", -16, 14)
    self.later:SetScript("OnClick", function()
        ns.DB:Settings().connectNext = ns.DB:Now() + CG.REMIND_EVERY
        f:Hide()
    end)
    self.never = W.Button(f, "Don't Show Again", 150, 24, "alt")
    self.never:SetPoint("RIGHT", self.later, "LEFT", -8, 0)
    self.never:SetScript("OnClick", function()
        ns.DB:Settings().connectOff = true
        f:Hide()
        ns:Print("Get Connected won't open by itself again. Type /ngm connect to see it.")
    end)
    W.Tooltip(self.never, "Don't show again", "It won't open by itself. /ngm connect or Options still open it.")
    ns:On("EVENTS_CHANGED", function() if f:IsShown() then CG:Refresh() end end)
end

local function Row(i)
    local f = CG.frame
    local r = CG.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f)
    r.Title = r:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    r.Title:SetPoint("TOPLEFT", 0, 0)
    r.State = r:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    r.State:SetPoint("TOPRIGHT", 0, 0)
    r.Text = r:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    r.Text:SetPoint("TOPLEFT", r.Title, "BOTTOMLEFT", 0, -4)
    r.Text:SetJustifyH("LEFT")
    r.Button = W.Button(r, "", 130, 22)
    CG.rows[i] = r
    return r
end

function CG:Refresh()
    local f = self.frame
    local width = f:GetWidth() - 36
    local y = -34 - self.intro:GetStringHeight() - 14
    local steps = self:Steps()
    for i, s in ipairs(steps) do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 18, y)
        r:SetWidth(width)
        r.Title:SetText(("%d. %s"):format(i, s.title))
        r.State:SetText(LABEL[s.state] or "")
        r.Text:SetWidth(width)
        r.Text:SetText(s.text)
        local h = r.Title:GetStringHeight() + 4 + r.Text:GetStringHeight()
        r.Button:SetShown(s.button ~= nil)
        if s.button then
            r.Button:SetText(s.button.label)
            r.Button:SetScript("OnClick", s.button.fn)
            r.Button:ClearAllPoints()
            r.Button:SetPoint("TOPLEFT", r.Text, "BOTTOMLEFT", 0, -6)
            h = h + 30
        end
        r:SetHeight(h)
        r:Show()
        y = y - h - 14
    end
    for i = #steps + 1, #self.rows do self.rows[i]:Hide() end
    f:SetHeight(-y + 50)
end

function CG:Open()
    if InCombatLockdown and InCombatLockdown() then return end
    if not self.frame then self:Build() end
    self:Refresh()
    self.frame:Show()
end

-- A little after login (after the Welcome tour, if that's showing): when
-- linking or Discord in WoW is still to do, at most every few days.
function CG:Init()
    C_Timer.After(30, function()
        local st = ns.DB:Settings()
        if st.connectOff or (st.connectNext or 0) > ns.DB:Now() then return end
        if not st.welcomeDone or (ns.Welcome and ns.Welcome.frame and ns.Welcome.frame:IsShown()) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if not CG:Needed() then return end
        st.connectNext = ns.DB:Now() + CG.REMIND_EVERY
        CG:Open()
    end)
end
