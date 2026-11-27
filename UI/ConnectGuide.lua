--[[
    Nootropic Guild Manager - Get Connected (3.1)
    With NGM Peon, the steps that put a member's game and Discord together,
    each with where it stands:

      1. NGM Addon             done (you're reading this)
      2. Link with NGM Peon    /ngm link in Discord (LK records, from NGM Peon)
      3. Discord in WoW        Options, Social, Discord: so guild chat shows in
                               Discord as you. Addons can't read it (C_Discord
                               is Blizzard's only), so NGM Peon tells: it sees
                               the guild chat Blizzard posts, as the player's
                               own account once connected (DX records). Only
                               when the guild's chat reaches its Discord
                               (GS:gamechat).

    NGM Desktop isn't a step: a short note under the steps says it's there
    to help the guild sync faster.

    Opens by itself a little after every login and /reload while linking or
    Discord in WoW is still to do (NGM Desktop users too). Not Now closes it
    until the next one; Don't Show Again until the next version of the NGM
    Addon (connectOff holds the version it was chosen on). /ngm connect and
    Options open it any time.
]]
local _, ns = ...
local W = ns.Widgets
local CG = {}
ns.ConnectGuide = CG

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

-- The steps, each { title, state = "done" | "todo" | "unknown", text, button = { label, fn } }
function CG:Steps()
    local steps = {}
    steps[#steps + 1] = { title = "NGM Addon", state = "done", text = "Installed." }
    local linked = Linked()
    steps[#steps + 1] = { title = "Link with NGM Peon", state = linked and "done" or "todo",
        text = linked and "Your characters are linked: on Discord they count as you, and you can sign up for events here."
            or "In your guild's Discord, type " .. ns.GOLD .. "/ngm link|r and sign in with Battle.net. It shows here after the next update from NGM Peon." }
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
    if ns.DB.FeatureOn and not ns.DB:FeatureOn("connect") then return false end -- off for the guild
    for _, s in ipairs(self:Steps()) do
        if s.state == "todo" then return true end
    end
    return false
end

local LABEL = { done = GREEN .. "Done|r", todo = ORANGE .. "To do|r", unknown = GRAY .. "Not seen yet|r" }

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
    self.tip = f:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.tip:SetJustifyH("LEFT")
    self.later = W.Button(f, "Not Now", 110, 24, "alt")
    self.later:SetPoint("BOTTOMRIGHT", -16, 14)
    self.later:SetScript("OnClick", function() f:Hide() end)
    self.never = W.Button(f, "Don't Show Again", 170, 24, "alt")
    self.never:SetPoint("RIGHT", self.later, "LEFT", -8, 0)
    self.never:SetScript("OnClick", function()
        ns.DB:Settings().connectOff = ns.version or "?"
        f:Hide()
        ns:Print("Get Connected won't open by itself until the next version of the NGM Addon. Type /ngm connect to see it.")
    end)
    W.Tooltip(self.never, "Don't show again", "It won't open by itself until the next version of the NGM Addon. /ngm connect or Options still open it.")
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
    -- not a step: a note that NGM Desktop helps, for everyone
    self.tip:ClearAllPoints()
    self.tip:SetPoint("TOPLEFT", 18, y + 4)
    self.tip:SetWidth(width)
    self.tip:SetText("Tip: NGM Desktop helps your guild sync faster. It sends your changes to Discord and brings NGM Peon's news in by itself, at every logout and /reload. Get it from ngmpeon.app, or My settings on NGM Peon's dashboard.")
    y = y - self.tip:GetStringHeight() - 10
    f:SetHeight(-y + 50)
end

CG.NEVER_WAIT = 5 -- seconds before Don't Show Again can be pressed: time to see what it is

-- Don't Show Again, counting down to when it can be pressed
function CG:HoldNever()
    local b, left = self.never, self.NEVER_WAIT
    if self.neverTicker then self.neverTicker:Cancel() end
    b:Disable()
    b:SetText(("Don't Show Again (%d)"):format(left))
    local function Ready()
        b:SetText("Don't Show Again")
        b:Enable()
    end
    if not (C_Timer and C_Timer.NewTicker) then Ready() return end
    self.neverTicker = C_Timer.NewTicker(1, function()
        left = left - 1
        if left > 0 then b:SetText(("Don't Show Again (%d)"):format(left)) return end
        if CG.neverTicker then CG.neverTicker:Cancel() CG.neverTicker = nil end
        Ready()
    end, self.NEVER_WAIT)
end

function CG:Open()
    if InCombatLockdown and InCombatLockdown() then return end
    -- only for guilds using NGM Peon: an addon-only guild has nothing to connect
    if not (ns.Sync.PeonGuild and ns.Sync:PeonGuild()) then
        ns:Print("Get Connected is for guilds using NGM Peon on Discord (ngmpeon.app). Your guild uses the NGM Addon on its own: nothing to connect.")
        return
    end
    if not self.frame then self:Build() end
    self:Refresh()
    self.frame:Show()
    self:HoldNever()
end

-- Turned off with Don't Show Again on this version? (a new version asks again)
function CG:Silenced()
    local off = ns.DB:Settings().connectOff
    return off ~= nil and off ~= false and off == (ns.version or "?")
end

-- A little after every login and /reload (after the Welcome tour, if that's
-- showing), while linking or Discord in WoW is still to do.
function CG:Init()
    C_Timer.After(15, function()
        local st = ns.DB:Settings()
        if CG:Silenced() then return end
        if not st.welcomeDone or (ns.Welcome and ns.Welcome.frame and ns.Welcome.frame:IsShown()) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if CG:Needed() then CG:Open() end
    end)
end
