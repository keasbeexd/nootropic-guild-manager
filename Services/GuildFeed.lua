--[[
    Nootropic Guild Manager - Guild Feed: level-ups in chat
    When a guildmate's level goes up in the game's roster, a line in your
    chat ("Pip reached level 31!"), and a sound if you like (Options, Guild
    Feed). Only in your own chat window: nothing is ever sent to guild chat.
    Your own level-ups are left to the game. The first roster after a login
    or /reload only notes everyone's level, so nothing is announced twice.
    (New events from NGM Peon: Services/Events.lua, E:Announce.)
]]
local _, ns = ...
local F = {}
ns.GuildFeed = F

F.MAX_LINES = 5 -- per roster update: a guild-wide jump is a few lines, not a flood
-- tried in order; ns.PlaySound skips any this client doesn't have
F.SOUNDS = { "LEVEL_UP", "IG_QUEST_LIST_COMPLETE", "READY_CHECK" }

local last -- full name -> level, as of the previous roster

-- Who levelled since the last roster: { { full, short, classFile, level } }
function F.Changes(members, before)
    local out = {}
    for _, e in ipairs(members) do
        local was = before[e.full]
        -- a level read as 0 (the roster not loaded yet) is no ding
        if was and was > 0 and e.level and e.level > was then out[#out + 1] = e end
    end
    return out
end

function F:OnRoster()
    local members = ns.Roster.members or {}
    if #members == 0 then return end
    local now = {}
    for _, e in ipairs(members) do now[e.full] = e.level end
    if last then
        local s = ns.DB:Settings()
        if s.levelUps ~= false then
            local me, told = ns.PlayerFullName(), 0
            for _, e in ipairs(F.Changes(members, last)) do
                if e.full ~= me and told < F.MAX_LINES then
                    told = told + 1
                    ns:Print(("|c%s%s|r reached level %d!"):format(ns.ClassHex(e.classFile), e.short or e.full, e.level))
                end
            end
            if told > 0 and s.levelUpSound then
                for _, kit in ipairs(F.SOUNDS) do
                    if SOUNDKIT and SOUNDKIT[kit] then ns.PlaySound(kit) break end
                end
            end
        end
    end
    last = now
end

function F:Init()
    ns:On("ROSTER_UPDATED", function() F:OnRoster() end)
end
