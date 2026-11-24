-- Test: the Guild Feed's level-up sound picker. Our own sounds always,
-- the game's only where this client has them, LibSharedMedia's only when
-- another addon brought it (without its "None" or our own twice); a saved
-- choice that's gone plays the default; our sounds are offered to
-- LibSharedMedia at login.
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

-- without LibSharedMedia
local c = F:SoundChoices()
assert(#c.own == 2 and #c.game == 2 and #c.shared == 0, "own, the game's this client has, nothing shared")
assert(F:SoundKey() == "ngm:chime" and F:SoundName() == "NGM Chime", "default")
F:PlaySound()
assert(files[1]:match("Chime%.ogg$"), "the default plays our chime")
settings.levelUpSoundChoice = "kit:READY_CHECK"
F:PlaySound()
assert(played[1] == "READY_CHECK" and F:SoundName() == "Ready check")
settings.levelUpSoundChoice = "kit:MAP_PING"
assert(F:SoundKey() == "ngm:chime", "a game sound this client lacks falls back")
settings.levelUpSoundChoice = "lsm:Bell"
assert(F:SoundKey() == "ngm:chime", "a shared sound without LibSharedMedia falls back")

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
assert(F:SoundKey() == "lsm:Bell" and F:SoundName() == "Bell")
F:PlaySound()
assert(files[#files] == media.Bell, "plays the shared file")
settings.levelUpSoundChoice = "lsm:Gong"
F:PlaySound()
assert(files[#files] == 567, "a shared file id works too")
settings.levelUpSoundChoice = "lsm:None"
assert(F:SoundKey() == "ngm:chime", "None is no sound to pick")

-- login: ours go to LibSharedMedia
F:Init()
assert(#registered == 2 and registered[1][1] == "sound" and registered[1][2] == "NGM Chime" and registered[2][2] == "NGM Fanfare")
assert(handlers.ROSTER_UPDATED, "still listens to the roster")
print("OK")
