--[[
    Nootropic Guild Manager - the Guild Info code (3.2, docs/PERMISSIONS.md)
    Keeps every copy on the Guild Master's rules (GS:perm_*, GS:feat_*,
    GS:lock_*), as GRM does: a short line in the guild's Guild Info,
    "NGM:7k3f9a2c", a fingerprint of all the rules. Only ranks the game lets
    edit the Guild Info can change it, so the game itself vouches for it.

    The Guild Master pastes the line (the game forbids addons to write the
    Guild Info). Every copy reads it only while the game restricts nothing
    (combat, encounters, keystones, PvP matches, some maps, chat: reading it
    then is blocked), as GRM does, and keeps the last code it read for the
    rest of the time.

      Value(name)   the rule every copy uses: the Guild Master's own copy
                    uses what it has; anyone else's, the rules as they are
                    when they match the code, else strict: every row only
                    the Guild Master (switches and locks as they last
                    matched) until they match; no code at all: as they are
                    (a guild not using it, or a Guild Master before 3.2)
      Stale()       our rules don't match the code (yet): the page says so,
                    and a sync check asks guildmates for them
      Line()        the line for the Guild Info, for the rules as they are
      LineInPlace() is it there? (nil: no rules set, or not read yet)
]]
local _, ns = ...
local GR = {}
ns.GuildRules = GR

local PATTERN = "NGM:(%w+)"

local function RawRules()
    local out = {}
    for key, rec in pairs((ns.Sync.Store and ns.Sync:Store("guild")) or {}) do
        local name = key:match("^GS:(perm_.+)$") or key:match("^GS:(feat_.+)$") or key:match("^GS:(lock_.+)$")
        if name and (rec.v or "") ~= "" then out[name] = rec.v end
    end
    return out
end

-- A fingerprint of the rules: the same on every copy with the same rules.
function GR.Fingerprint(rules)
    local keys = {}
    for k in pairs(rules) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. rules[k] end
    return ns.Sync.Base36(ns.Sync.Hash(table.concat(parts, ";")))
end

-- Is the game restricting addons right now? (Enum.AddOnRestrictionType:
-- combat, encounter, keystone, PvP match, map, chat.) Reading the Guild
-- Info then is blocked, so we don't.
local restricting = {} -- [type] = state, from ADDON_RESTRICTION_STATE_CHANGED
local function Restricted()
    if InCombatLockdown and InCombatLockdown() then return true end
    for _, state in pairs(restricting) do if state and state > 0 then return true end end
    local RA, E = rawget(_G, "C_RestrictedActions"), rawget(_G, "Enum")
    if RA and RA.IsAddOnRestrictionActive and E and E.AddOnRestrictionType then
        for _, t in pairs(E.AddOnRestrictionType) do
            local ok, on = pcall(RA.IsAddOnRestrictionActive, t)
            if ok and on then return true end
        end
    end
    return false
end
GR.Restricted = Restricted

-- The Guild Info's text, or nil while the game restricts reading it
local function InfoText()
    if Restricted() then return nil end
    local get = C_GuildInfo and C_GuildInfo.GetInfoText
    if not get then return nil end
    local ok, text = pcall(get)
    if not ok or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
    return text
end

-- The code in the Guild Info, or nil: read when we may, else the last one
-- read (kept with the guild: "" = read, and there's none)
function GR:Code()
    local g = ns.DB:Guild()
    local text = InfoText()
    if text then
        local code = text:match(PATTERN) or ""
        if g then g.infoCode = code end
        return code ~= "" and code or nil
    end
    local last = g and g.infoCode
    return (last and last ~= "") and last or nil
end

-- Works out which rules count, once per change
function GR:Refresh()
    local g = ns.DB:Guild()
    if not g then self.effective, self.stale = nil, false return end
    local raw = RawRules()
    local code = self:Code()
    local mine = GR.Fingerprint(raw)
    if ns.DB:IsGuildMaster() or not code then
        self.effective, self.stale = raw, false
    elseif mine == code then
        self.effective, self.stale = raw, false
        g.rulesMatched = { code = code, rules = raw } -- the last rules that matched
    else
        -- not matching: strict. Every row only the Guild Master until the
        -- rules match again (switches and locks as they last matched:
        -- they hand nobody anything)
        local strict = {}
        for k, v in pairs((g.rulesMatched and g.rulesMatched.rules) or {}) do
            if not k:find("^perm_") then strict[k] = v end
        end
        for _, p in ipairs(ns.DB.PERMS or {}) do strict["perm_" .. p.key] = "-" end
        self.effective = strict
        if not self.stale then
            -- ask guildmates for the Guild Master's rules (a sync check)
            if ns.Sync.CheckAll then pcall(ns.Sync.CheckAll, ns.Sync) end
        end
        self.stale = true
    end
    self.code, self.mine = code, mine
    ns:Fire("GUILD_RULES_CHANGED")
end

function GR:Value(name)
    if not self.effective then self:Refresh() end
    local v = self.effective and self.effective[name]
    if v == nil and not self.effective then return ns.Sync:Value("GS:" .. name) end
    return v
end

function GR:Stale() return self.stale == true end

function GR:Raw() return RawRules() end

-- The line for the Guild Info, as it should be now
function GR:Line() return "NGM:" .. GR.Fingerprint(RawRules()) end

-- Does the Guild Info have the line for the rules as they are now? (nil
-- when the guild has no rules set, or the Guild Info hasn't been read yet)
function GR:LineInPlace()
    if not next(RawRules()) then return nil end
    local g = ns.DB:Guild()
    self:Code() -- read it now if we may
    if not (g and g.infoCode) then return nil end
    return g.infoCode == GR.Fingerprint(RawRules())
end

function GR:Init()
    local function again() GR.effective = nil GR:Refresh() end
    ns:On("GUILD_SETTINGS_CHANGED", again)
    -- the Guild Info comes with the roster (and changes with it)
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", function()
        if Restricted() then return end
        local code = GR:Code()
        if code ~= GR.code then again() end
    end)
    -- restrictions lifted: read it again (it may have changed meanwhile)
    ns:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(_, kind, state)
        if kind ~= nil then restricting[kind] = state end
        if not Restricted() then
            local code = GR:Code()
            if code ~= GR.code then again() end
        end
    end)
    -- at login, the Guild Master is told if the Guild Info needs the new line
    C_Timer.After(25, function()
        if ns.DB:IsGuildMaster() and GR:LineInPlace() == false then
            ns:Print(("Put |cffffffff%s|r in your Guild Info, or everyone's permissions will default to Guild Master only, for safety reasons. (Options, Permissions, Copy the line.)"):format(GR:Line()))
        end
    end)
end
