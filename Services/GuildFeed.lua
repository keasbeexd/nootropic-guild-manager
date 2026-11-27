--[[
    Nootropic Guild Manager - Guild Feed: level-ups in chat
    When a guildmate's level goes up in the game's roster, a line in your
    chat ("Pip reached level 31!"), and a sound if you like (Options, Guild
    Feed; pick it there: the NGM Addon's own, a few of the game's, or any
    from LibSharedMedia when another addon brings it). Only in your own chat
    window: nothing is ever sent to guild chat.
    Your own level-ups are left to the game. The first roster after a login
    or /reload only notes everyone's level, so nothing is announced twice.
    (New events from NGM Peon: Services/Events.lua, E:Announce.)
]]
local _, ns = ...
local F = {}
ns.GuildFeed = F

F.MAX_LINES = 5 -- per roster update: a guild-wide jump is a few lines, not a flood

-- The sounds to pick from (Options, Guild Feed), for level-ups and for new
-- events, each its own choice (F.FEEDS). Saved as a key: "off" no sound,
-- "ngm:<name>" our own, "kit:<SOUNDKIT name>" the game's, "lsm:<name>" one
-- from LibSharedMedia. A choice that's gone (an addon removed) plays the
-- feed's fallback instead.
local SOUND_DIR = "Interface\\AddOns\\NootropicGuildManager\\Media\\Sounds\\"
F.OWN_SOUNDS = {
    { key = "ngm:chime", name = "NGM Chime", file = SOUND_DIR .. "Chime.ogg" },
    { key = "ngm:fanfare", name = "NGM Fanfare", file = SOUND_DIR .. "Fanfare.ogg" },
    { key = "ngm:horn", name = "NGM Horn", file = SOUND_DIR .. "Horn.ogg" },
    { key = "ngm:harp", name = "NGM Harp", file = SOUND_DIR .. "Harp.ogg" },
    { key = "ngm:bells", name = "NGM Bells", file = SOUND_DIR .. "Bells.ogg" },
}
-- names checked against Forever's own list (wow-ui-source, forever branch:
-- Blizzard_SharedXML/Mainline/SoundKitConstants.lua); any this client
-- lacks is left out. (LEVEL_UP isn't on Forever's list.)
F.GAME_SOUNDS = {
    { key = "kit:IG_QUEST_LIST_COMPLETE", name = "Quest complete" },
    { key = "kit:READY_CHECK", name = "Ready check" },
    { key = "kit:MAP_PING", name = "Map ping" },
    { key = "kit:RAID_WARNING", name = "Raid warning" },
}
F.OFF = "off"
-- each feed's setting, and what plays when its choice is gone
F.FEEDS = {
    levelUp = { choice = "levelUpSoundChoice", fallback = "ngm:chime" },
    event = { choice = "eventSoundChoice", fallback = "ngm:horn" },
}

-- LibSharedMedia-3.0, only when another addon loaded it (we don't bring it)
local function SharedMedia()
    return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end

local function Own(key)
    for _, s in ipairs(F.OWN_SOUNDS) do if s.key == key then return s end end
end

local function GameAvailable(key)
    local kit = key:match("^kit:(.+)$")
    return kit and SOUNDKIT and SOUNDKIT[kit] and true or false
end

-- What the picker lists: { own = {...}, game = {...}, shared = { names } }.
-- Shared leaves out LibSharedMedia's "None" and the sounds we registered.
function F:SoundChoices()
    local out = { own = F.OWN_SOUNDS, game = {}, shared = {} }
    for _, s in ipairs(F.GAME_SOUNDS) do
        if GameAvailable(s.key) then out.game[#out.game + 1] = s end
    end
    local lsm = SharedMedia()
    local names = lsm and lsm:List("sound")
    if names then
        local ours = {}
        for _, s in ipairs(F.OWN_SOUNDS) do ours[s.name] = true end
        for _, name in ipairs(names) do
            if name ~= "None" and not ours[name] then out.shared[#out.shared + 1] = name end
        end
    end
    return out
end

-- The sound a key plays: "file", path or file id; or "kit", SOUNDKIT name.
-- nil when it isn't available on this computer.
function F:ResolveSound(key)
    if type(key) ~= "string" then return nil end
    local own = Own(key)
    if own then return "file", own.file end
    if GameAvailable(key) then return "kit", key:sub(5) end
    local name = key:match("^lsm:(.+)$")
    local lsm = name and SharedMedia()
    local data = lsm and lsm:Fetch("sound", name, true)
    if data and data ~= 1 then return "file", data end -- 1 is LibSharedMedia's "None"
end

-- A feed's saved choice: "off", the sound if it's still there, else the
-- feed's fallback.
function F:SoundKey(feed)
    local f = F.FEEDS[feed]
    local key = ns.DB:Settings()[f.choice]
    if key == nil or key == F.OFF then return F.OFF end
    if self:ResolveSound(key) then return key end
    return f.fallback
end

function F:SoundName(key)
    if key == F.OFF then return "Off" end
    local own = Own(key)
    if own then return own.name end
    for _, s in ipairs(F.GAME_SOUNDS) do if s.key == key then return s.name end end
    return key:match("^lsm:(.+)$") or key
end

function F:PlaySound(key)
    local how, what = self:ResolveSound(key)
    if how == "kit" then ns.PlaySound(what)
    elseif how == "file" and PlaySoundFile then pcall(PlaySoundFile, what) end
end

-- A feed's sound, unless it's off.
function F:PlayFeed(feed)
    local key = self:SoundKey(feed)
    if key ~= F.OFF then self:PlaySound(key) end
end

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
        if s.levelUps ~= false and ns.DB:FeatureOn("levelups") then
            local me, told = ns.PlayerFullName(), 0
            for _, e in ipairs(F.Changes(members, last)) do
                if e.full ~= me and told < F.MAX_LINES then
                    told = told + 1
                    ns:Print(("|c%s%s|r reached level %d!"):format(ns.ClassHex(e.classFile), e.short or e.full, e.level))
                end
            end
            if told > 0 then F:PlayFeed("levelUp") end
        end
    end
    last = now
end

function F:Init()
    ns:On("ROSTER_UPDATED", function() F:OnRoster() end)
    -- our sounds, for other addons' sound pickers too (PLAYER_LOGIN: every
    -- addon that brings LibSharedMedia has loaded)
    local lsm = SharedMedia()
    if lsm then
        for _, s in ipairs(F.OWN_SOUNDS) do pcall(lsm.Register, lsm, "sound", s.name, s.file) end
    end
end
