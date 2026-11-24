-- Test: the Guild Feed's sounds, one choice each for new events and
-- level-ups, Off included. Our own sounds always, the game's only where this
-- client has them, LibSharedMedia's only when another addon brought it
-- (without its "None" or our own twice); a choice that's gone plays the
-- feed's fallback; our sounds are offered to LibSharedMedia at login; and
-- 3.0.13's on/off box carries over.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local settings = {}
local handlers = {}
local played, files = {}, {}
local ns = {
    DB = { Settings = function() return settings end },
    On = function(_, ev, fn) handlers[ev] = fn end,
    PlaySound = function(kit) played[#played + 1] = kit end,
}
PlaySoundFile = function(f) files[#files + 1] = f end
SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 878, READY_CHECK = 8960 } -- no MAP_PING or RAID_WARNING here
assert(loadfile(ROOT .. "/Services/GuildFeed.lua"))("NGM", ns)
local F = ns.GuildFeed

-- every own sound file is in the repo
for _, s in ipairs(F.OWN_SOUNDS) do
    local rel = s.file:gsub("^Interface\\AddOns\\NootropicGuildManager\\", ""):gsub("\\", "/")
    assert(io.open(ROOT .. "/" .. rel), "missing " .. rel)
end

-- off unless picked
assert(F:SoundKey("levelUp") == "off" and F:SoundKey("event") == "off" and F:SoundName("off") == "Off")
F:PlayFeed("levelUp"); F:PlayFeed("event")
assert(#files == 0 and #played == 0, "off plays nothing")

-- without LibSharedMedia
local c = F:SoundChoices()
assert(#c.own == 5 and #c.game == 2 and #c.shared == 0, "own, the game's this client has, nothing shared")
settings.levelUpSoundChoice = "ngm:chime"
F:PlayFeed("levelUp")
assert(files[1]:match("Chime%.ogg$") and F:SoundName(F:SoundKey("levelUp")) == "NGM Chime")
settings.eventSoundChoice = "kit:READY_CHECK"
F:PlayFeed("event")
assert(played[1] == "READY_CHECK" and #files == 1, "each feed its own sound")
settings.eventSoundChoice = "kit:MAP_PING"
assert(F:SoundKey("event") == "ngm:horn", "a game sound this client lacks: the event fallback")
settings.levelUpSoundChoice = "lsm:Bell"
assert(F:SoundKey("levelUp") == "ngm:chime", "a shared sound without LibSharedMedia: the level-up fallback")

-- with LibSharedMedia from another addon
local registered = {}
local media = { None = 1, Bell = "Interface\\AddOns\\Other\\bell.ogg", Gong = 567 }
local lsm = {
    List = function(_, kind) assert(kind == "sound"); return { "Bell", "Gong", "NGM Chime", "None" } end,
    Fetch = function(_, kind, name, noDefault) assert(kind == "sound" and noDefault); return media[name] end,
    Register = function(_, kind, name, file) registered[#registered + 1] = { kind, name, file } end,
}
LibStub = function(major, silent) assert(silent); return major == "LibSharedMedia-3.0" and lsm or nil end
c = F:SoundChoices()
assert(#c.shared == 2 and c.shared[1] == "Bell" and c.shared[2] == "Gong", "shared, without None or ours")
assert(F:SoundKey("levelUp") == "lsm:Bell" and F:SoundName("lsm:Bell") == "Bell")
F:PlayFeed("levelUp")
assert(files[#files] == media.Bell, "plays the shared file")
settings.levelUpSoundChoice = "lsm:Gong"
F:PlayFeed("levelUp")
assert(files[#files] == 567, "a shared file id works too")
settings.levelUpSoundChoice = "lsm:None"
assert(F:SoundKey("levelUp") == "ngm:chime", "None is no sound to pick")

-- login: ours go to LibSharedMedia
F:Init()
assert(#registered == 5 and registered[1][1] == "sound" and registered[1][2] == "NGM Chime" and registered[5][2] == "NGM Bells")
assert(handlers.ROSTER_UPDATED, "still listens to the roster")

-- 3.0.13's "Play a sound with level-ups" box: on keeps a sound, off is Off
local function Migrated(old)
    NootropicGuildManagerDB = { settings = old }
    local dbns = {}
    assert(loadfile(ROOT .. "/Core/Database.lua"))("NGM", dbns)
    pcall(dbns.DB.Init, dbns.DB) -- the rest of Init needs the game; the move comes first
    return NootropicGuildManagerDB.settings
end
local s = Migrated({ levelUpSound = true })
assert(s.levelUpSoundChoice == "ngm:chime" and s.levelUpSound == nil, "on: the chime")
s = Migrated({ levelUpSound = false })
assert(s.levelUpSoundChoice == "off" and s.levelUpSound == nil, "off: Off")
s = Migrated({ levelUpSound = true, levelUpSoundChoice = "ngm:harp" })
assert(s.levelUpSoundChoice == "ngm:harp", "a test build's pick stays")
s = Migrated({})
assert(s.levelUpSoundChoice == "off" and s.eventSoundChoice == "off", "new players: both off")
print("OK")
