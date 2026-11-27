--[[
    Nootropic Guild Manager - the ban list (3.2, docs/PERMISSIONS.md)
    A ban is about a person, not one name: their main and every alt linked
    to them, each by the character's permanent game ID (GUID) when the game
    gives one, so a rename doesn't get round it. As GRM does it, plus warnings
    at invite time.

      BN:<character> = "time;by;guid;main;reason"   ("" = unbanned)

    Who may ban, see the list and see reasons: the Guild Master's
    Permissions page (ban, banlist, banreason). Everyone is warned when they
    invite someone banned; a banned character in the guild is pointed out
    once a session to whoever may see the list. NGM Addon only: NGM Peon
    keeps no ban data.
]]
local _, ns = ...
local BN = {}
ns.Bans = BN

local function Parse(v)
    if not v or v == "" then return nil end
    local t, by, guid, main, reason = v:match("^(%d+);([^;]*);([^;]*);([^;]*);(.*)$")
    if not t then return nil end
    return { t = tonumber(t), by = by, guid = guid ~= "" and guid or nil, main = main, reason = reason }
end

-- Every banned character: { full, t, by, guid, main, reason }
function BN:All()
    local out = {}
    for key, rec in pairs((ns.Sync.Store and ns.Sync:Store("guild")) or {}) do
        local full = key:match("^BN:(.+)$")
        local b = full and Parse(rec.v)
        if b then b.full = full out[#out + 1] = b end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

-- The ban covering this character (by game ID first, then name), or nil
function BN:Find(full, guid)
    if not full and not guid then return nil end
    guid = guid or (full and ns.Roster.byName[full] and ns.Roster.byName[full].guid)
    local byName
    for _, b in ipairs(self:All()) do
        if guid and b.guid == guid then return b end
        if full and b.full == full then byName = b end
    end
    return byName
end

function BN:IsBanned(full, guid) return self:Find(full, guid) ~= nil end

-- The reason, for those allowed to see it
function BN:Reason(b)
    if not (b and b.reason ~= "" and ns.DB:HasPerm("banreason")) then return nil end
    return b.reason
end

-- Their whole family: their main and every alt linked to them
local function Family(full)
    local root = ns.DB:RootOf(full) or full
    local out = { root }
    for _, a in ipairs(ns.DB:GetAltsOf(root) or {}) do out[#out + 1] = a end
    if root ~= full then
        local seen = false
        for _, n in ipairs(out) do if n == full then seen = true end end
        if not seen then out[#out + 1] = full end
    end
    return out, root
end

function BN:Ban(full, reason)
    if not ns.DB:HasPerm("ban") then return nil, "Your rank can't ban players (the Guild Master's Permissions)." end
    full = full and ns.NormalizeName(ns.Trim(full))
    if not full or full == "" then return nil, "Whose name?" end
    if full == ns.PlayerFullName() then return nil, "That's you." end
    local e = ns.Roster.byName[full]
    if e and e.rankIndex == 0 then return nil, "Not the Guild Master." end
    reason = ns.Sync.Clean(reason or ""):gsub(";", ","):sub(1, 200)
    local chars, main = Family(full)
    local me, now = ns.PlayerFullName(), ns.DB:Now()
    for _, c in ipairs(chars) do
        local guid = ns.Roster.byName[c] and ns.Roster.byName[c].guid or ""
        ns.Sync:Set("BN:" .. c, table.concat({ now, me, guid, main, reason }, ";"))
    end
    ns:Fire("BANS_CHANGED")
    return #chars
end

-- Unban the whole family (everyone banned with the same main)
function BN:Unban(full)
    if not ns.DB:HasPerm("ban") then return nil, "Your rank can't unban players (the Guild Master's Permissions)." end
    local b = self:Find(full)
    if not b then return nil, "Not banned." end
    local n = 0
    for _, x in ipairs(self:All()) do
        if x.main == b.main or x.full == b.full then ns.Sync:Set("BN:" .. x.full, "") n = n + 1 end
    end
    ns:Fire("BANS_CHANGED")
    return n
end

------------------------------------------------------------------------
-- The warning: big, on screen (our own frame: not the game's raid warning,
-- which an addon writing to can taint), with a sound and a chat line
------------------------------------------------------------------------
function BN:Warn(full, why)
    local b = self:Find(full)
    if not b then return end
    local who = ns.ShortName(full) .. ((b.main ~= "" and b.main ~= full) and (" (alt of " .. ns.ShortName(b.main) .. ")") or "")
    local reason = self:Reason(b)
    local line = ("Banned: %s. %s"):format(who, why) .. (reason and (" Reason: " .. reason) or "")
    ns:Print("|cffff2020" .. line .. "|r")
    if not self.alert then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(900, 80)
        f:SetPoint("TOP", 0, -160)
        f:SetFrameStrata("HIGH")
        f.Text = f:CreateFontString(nil, "OVERLAY", "NGMFontHuge")
        f.Text:SetAllPoints()
        f.Text:SetTextColor(1, 0.15, 0.15)
        f.Text:SetJustifyH("CENTER")
        f:Hide()
        self.alert = f
    end
    self.alert.Text:SetText(line)
    self.alert:Show()
    self.alert:SetAlpha(1)
    if self.hideTimer then self.hideTimer:Cancel() end
    self.hideTimer = C_Timer.NewTimer(8, function() BN.alert:Hide() end)
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

-- "You have invited %s to join your guild.", built from the game's own
-- string (whatever language), so it matches only that message
local function InvitePattern()
    local s = rawget(_G, "ERR_GUILD_INVITE_S")
    if type(s) ~= "string" or not s:find("%%s") then return nil end
    return "^" .. s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end

function BN:Init()
    local pattern = InvitePattern()
    if pattern then
        ns:RegisterEvent("CHAT_MSG_SYSTEM", function(_, msg)
            if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
            local name = msg:match(pattern)
            if name and BN:IsBanned(ns.NormalizeName(name)) then BN:Warn(ns.NormalizeName(name), "You just invited them to the guild.") end
        end)
    end
    -- banned characters in the guild: once a session, to whoever may see the list
    local told = {}
    ns:On("ROSTER_UPDATED", function()
        if not ns.DB:HasPerm("banlist") then return end
        for full, e in pairs(ns.Roster.byName) do
            if not told[full] and BN:IsBanned(full, e.guid) then
                told[full] = true
                BN:Warn(full, "They're in the guild.")
            end
        end
    end)
end
