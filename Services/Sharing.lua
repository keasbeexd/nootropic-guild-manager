--[[
    Nootropic Guild Manager - What you share
    Switches for what your own copy of the addon shares with the guild (all on
    by default, saved for all your characters):

      report    your spec and professions as the game reports them (P record)
      recipes   the recipes you've learned (RP records, Who Can Craft?)
      together  appearing in guildmates' Play Together lists
      stats     your character statistics for the Hall of Fame (HF record)

    Turning one off stops sharing it and clears what was already shared:
    the records are emptied, so guildmates' copies drop them too. Hiding from
    Play Together is itself shared (PS:<member> = "together"), because the
    lists are built on other people's computers.

    "Learn when I usually play" lives in Services/Profile.lua (per character).
]]
local _, ns = ...
local SH = {}
ns.Sharing = SH

SH.KEYS = {
    report   = "shareReport",
    recipes  = "shareRecipes",
    together = "showInTogether",
    stats    = "shareStats",
}

local function Me() return ns.PlayerFullName() end

function SH:Get(key)
    return ns.DB:Settings()[self.KEYS[key]] ~= false
end

function SH:Set(key, on)
    ns.DB:Settings()[self.KEYS[key]] = on and true or false
    self:Enforce(key)
    ns:Fire("SETTINGS_CHANGED")
end

-- Makes what's shared match the switches (one key, or all of them).
function SH:Enforce(only)
    if not (IsInGuild() and ns.DB:Guild() and ns.Sync.readyFor) then return end
    local me = Me()
    if not only or only == "report" then
        if self:Get("report") then
            ns.Comm:Report()
        elseif (ns.Sync:Value("P:" .. me) or "") ~= "" then
            ns.Sync:Set("P:" .. me, "")
        end
    end
    if (not only or only == "recipes") and not self:Get("recipes") then
        local prefix = "RP:" .. me .. ":"
        for key, rec in pairs(ns.Sync:Store("guild") or {}) do
            if key:sub(1, #prefix) == prefix and rec.v ~= "" then ns.Sync:Set(key, "") end
        end
    end
    if not only or only == "stats" then
        if self:Get("stats") then
            ns.HallOfFame:Publish()
        elseif (ns.Sync:Value("HF:" .. me) or "") ~= "" then
            ns.Sync:Set("HF:" .. me, "")
        end
    end
    if not only or only == "together" then
        local value = self:Get("together") and "" or "together"
        if (ns.Sync:Value("PS:" .. me) or "") ~= value then ns.Sync:Set("PS:" .. me, value) end
    end
end

-- Has `full` asked to be left out of Play Together lists?
function SH:HiddenFromTogether(full)
    local v = ns.Sync:Value("PS:" .. full)
    return v ~= nil and v:find("together", 1, true) ~= nil
end

function SH:Init()
    -- once the guild's data has loaded
    C_Timer.After(20, ns.Safe(function() SH:Enforce() end, "Sharing"))
end
