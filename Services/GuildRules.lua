--[[
    Nootropic Guild Manager - the Guild Info code (3.2, docs/PERMISSIONS.md)
    Keeps every copy on the Guild Master's rules (GS:perm_* and GS:feat_*),
    as GRM does: a short line in the guild's Guild Info, "NGM:7k3f9a2c", a
    fingerprint of all the rules. Only ranks the game lets edit the Guild
    Info can change it, so the game itself vouches for it.

      Value(name)   the rule every copy uses: the Guild Master's own copy
                    uses what it has; anyone else's, the rules as they are
                    when they match the code, else the last ones that did
                    (the defaults the first time); no code at all: as they
                    are (a guild not using it, or a Guild Master before 3.2)
      Stale()       our rules don't match the code (yet): the page says so,
                    and a sync check asks guildmates for them
      Publish()     the Guild Master's copy: put the new code in the Guild
                    Info (out of combat), or hand back the line to paste
]]
local _, ns = ...
local GR = {}
ns.GuildRules = GR

local PATTERN = "NGM:(%w+)"

local function RawRules()
    local out = {}
    for key, rec in pairs((ns.Sync.Store and ns.Sync:Store("guild")) or {}) do
        local name = key:match("^GS:(perm_.+)$") or key:match("^GS:(feat_.+)$")
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

local function InfoText()
    local get = (C_GuildInfo and C_GuildInfo.GetInfoText) or rawget(_G, "GetGuildInfoText")
    if not get then return nil end
    local ok, text = pcall(get)
    return ok and type(text) == "string" and text or nil
end

-- The code in the Guild Info, or nil
function GR:Code()
    local text = InfoText()
    return text and text:match(PATTERN) or nil
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
        self.effective = (g.rulesMatched and g.rulesMatched.rules) or {}
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

-- The line for the Guild Info, as it should be now
function GR:Line() return "NGM:" .. GR.Fingerprint(RawRules()) end

-- The Guild Master's copy: the new code into the Guild Info. True when it's
-- there; false and the line to paste when the game wouldn't take it.
function GR:Publish()
    if not ns.DB:IsGuildMaster() then return false end
    local line = self:Line()
    if InCombatLockdown and InCombatLockdown() then
        self.pending = true
        return false, line
    end
    local text = InfoText() or ""
    if text:find(line, 1, true) then self.pasteLine = nil return true end
    local new = text:find(PATTERN) and text:gsub("NGM:%w+", line, 1) or ((text ~= "" and (text .. "\n") or "") .. line)
    if #new > 499 then self.pasteLine = line return false, line end
    local set = (C_GuildInfo and C_GuildInfo.SetInfoText) or rawget(_G, "SetGuildInfoText")
    local ok = set and pcall(set, new)
    -- the game may answer later: check back
    if ok then
        self.pasteLine = nil
        if C_Timer then C_Timer.After(3, function() if not (InfoText() or ""):find(line, 1, true) then GR.pasteLine = line ns:Fire("GUILD_RULES_CHANGED") end end) end
        return true
    end
    self.pasteLine = line
    return false, line
end

function GR:Init()
    local function again() GR.effective = nil GR:Refresh() end
    ns:On("GUILD_SETTINGS_CHANGED", function()
        again()
        -- the Guild Master changed a rule: the code follows
        if ns.DB:IsGuildMaster() and GR.code ~= GR.mine then GR:Publish() end
    end)
    -- the Guild Info comes with the roster (and changes with it)
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", function()
        local code = GR:Code()
        if code ~= GR.code then again() end
    end)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if GR.pending then GR.pending = nil GR:Publish() end
    end)
end
