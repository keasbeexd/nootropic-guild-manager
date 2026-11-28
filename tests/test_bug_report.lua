-- Test: /ngm bug: blocks of the NGM Addon (and only it) and its own errors
-- are noted, repeats counted, kept to 15 for 14 days; the report carries
-- versions, options and what happened, and no character or guild names.
local ROOT = arg[1]
local ns = { version = "3.1.1" }
local settings = {}
local handlers, printed = {}, {}
ns.DB = { Settings = function() return settings end }
function ns:RegisterEvent(e, fn) handlers[e] = fn end
function ns:Print(m) printed[#printed + 1] = m end
ns.Sync = { PeonGuild = function() return true end }
ns.DiscordCode = { DesktopInstalled = function() return false end }
ns.IsOfficer = function() return true end
ns.PlayerFullName = function() return "Secret Name" end
local clock = 1800000000
time = function() return clock end
date = function(_, t) return tostring(t) end
InCombatLockdown = function() return false end
GetBuildInfo = function() return "1.60.1", "12345", "Nov 1 2026", 16001 end
GetLocale = function() return "enUS" end
C_AddOns = { GetNumAddOns = function() return 2 end, GetAddOnInfo = function(i) return ({ "NootropicGuildManager", "Details" })[i] end,
  IsAddOnLoaded = function() return true end }
CommunitiesFrame = { IsShown = function() return true end }
assert(loadfile(ROOT .. "/Services/BugReport.lua"))("NGM", ns)
local B = ns.BugReport
B:Init()

handlers.ADDON_ACTION_BLOCKED(nil, "SomeOtherAddon", "CastSpellByName()")
assert(#(settings.bugLog or {}) == 0, "another addon's block isn't ours")
handlers.ADDON_ACTION_BLOCKED(nil, "NootropicGuildManager", "C_GuildInfo.SetNote()")
handlers.ADDON_ACTION_BLOCKED(nil, "NootropicGuildManager", "C_GuildInfo.SetNote()")
assert(#settings.bugLog == 1 and settings.bugLog[1].n == 2, "the same block counted, not listed twice")
assert(settings.bugLog[1].windows == "CommunitiesFrame", "which window was open")
assert(#printed == 1 and printed[1]:find("/ngm bug", 1, true), "told once a session")

local text = B:Text()
assert(text:find("NGM Addon 3.1.1", 1, true) and text:find("C_GuildInfo.SetNote() x2", 1, true), text)
assert(text:find("Other addons: Details", 1, true), "other addons by name")
assert(not text:find("Secret Name", 1, true), "no character names")

for i = 1, 20 do B:Note("error", "boom " .. i) end
assert(#settings.bugLog == 15, "the newest 15")
clock = clock + 15 * 86400
B:Note("error", "new")
assert(#settings.bugLog == 1, "older than 14 days: gone")
print("OK")
