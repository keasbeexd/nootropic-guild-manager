-- Test: your addon version is announced only after the roster has given
-- your full name (the game first gives only "Deja"), once per session, and
-- sent only when it changed (the login check finds anyone who missed it).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = { version = "2.9.1" }
local guild = { members = {}, sync = { guild = {}, officer = {} }, realmless = true }
local handlers = {}
function ns:Fire(ev, ...) for _, h in ipairs(handlers[ev] or {}) do h(...) end end
function ns:On(ev, fn) handlers[ev] = handlers[ev] or {} table.insert(handlers[ev], fn) end
function ns:RegisterEvent() end
function ns.Debounce(_, _, fn) fn() end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.IsOfficer() return false end
local selfName = "Deja"            -- what the game gives before the roster loads
function ns.PlayerFullName() return selfName end
function ns.NormalizeName(n) return n end
ns.DB = { PERM_BY_TYPE = {} }
function ns.DB:Guild() return guild end
function ns.DB:GuildKey() return "Nootropic" end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return {} end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
ns.Roster = { byName = {}, selfRow = nil }
C_Timer = { After = function() end }
GetTime = function() return 1 end
IsInGuild = function() return true end
C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns) assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
local S = ns.Sync
local sent = {}
S.QueueOutgoing = function(_, key) sent[#sent + 1] = key end
S.PurgeUnknown, S.PruneAudit, S.PruneExpired, S.RebuildAll = function() end, function() return 0 end, function() end, function() return 0 end, function() end
S:Init()                                   -- ready() runs: roster not loaded yet

assert(guild.sync.guild["AV:Deja"] == nil, "no version under the first name only")
assert(#sent == 0, "nothing announced before the roster gives your full name")

-- the roster loads and finds you
selfName = "Deja Rollupz"
ns.Roster.selfRow = "Deja Rollupz"
ns:Fire("SELF_NAME_CHANGED", "Deja Rollupz")
ns:Fire("ROSTER_UPDATED")
assert(guild.sync.guild["AV:Deja Rollupz"].v == "2.9.1")
local n = 0 for _, k in ipairs(sent) do if k == "AV:Deja Rollupz" then n = n + 1 end end
assert(n >= 1, "announced under the full name")
local before = #sent
ns:Fire("ROSTER_UPDATED")
assert(#sent == before, "once per session, not on every roster update")

-- next login, same version: nothing to send
sent = {}
S.readyFor = nil
handlers = {}
S:Init()
ns:Fire("ROSTER_UPDATED")
assert(#sent == 0, "not re-sent when unchanged")

-- after an update: sent
ns.version = "2.12.0"
S.readyFor = nil
handlers = {}
S:Init()
ns:Fire("ROSTER_UPDATED")
assert(#sent == 1 and sent[1] == "AV:Deja Rollupz" and guild.sync.guild["AV:Deja Rollupz"].v == "2.12.0", "a new version is sent")
print("OK")
