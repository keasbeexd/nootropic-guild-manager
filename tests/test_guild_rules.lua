-- Test: the Guild Info code (3.2, docs/PERMISSIONS.md): the Guild Master
-- pastes it (never written by the NGM Addon); every copy reads it only while
-- the game restricts nothing, as GRM does, and keeps the last code read;
-- rules count when they match, and while they don't, every row is only the
-- Guild Master.
local ROOT = arg[1]
local ns = {}
local store, guild, gm = {}, {}, false
local info = "Welcome to the guild!"
local reads, writes, combat, active = 0, 0, false, false
local events, printed = {}, {}
function ns:Fire() end
function ns:On(e, fn) events[e] = fn end
function ns:RegisterEvent(e, fn) events[e] = fn end
function ns:Print(m) printed[#printed + 1] = m end
local function Hash(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967291 end return h end
local function B36(n) local d, s = "0123456789abcdefghijklmnopqrstuvwxyz", "" repeat local r = n % 36 s = d:sub(r + 1, r + 1) .. s n = (n - r) / 36 until n == 0 return s end
ns.Sync = { Store = function() return store end, Value = function(_, k) return store[k] and store[k].v end, Hash = Hash, Base36 = B36,
  CheckAll = function() ns.checked = true end }
ns.DB = { Guild = function() return guild end, IsGuildMaster = function() return gm end,
  PERMS = { { key = "links" }, { key = "signup" } } }
C_GuildInfo = { GetInfoText = function() reads = reads + 1 return info end, SetInfoText = function() writes = writes + 1 end }
InCombatLockdown = function() return combat end
Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1 } }
C_RestrictedActions = { IsAddOnRestrictionActive = function(t) return active and t == 1 end }
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
assert(loadfile(ROOT .. "/Services/GuildRules.lua"))("NGM", ns)
local GR = ns.GuildRules
GR:Init()
local function check(name, got, want) print(("%-62s %s"):format(name, got == want and "ok" or ("FAIL (got " .. tostring(got) .. ")"))) assert(got == want) end

-- no code in the Guild Info: the rules as they are
store["GS:perm_links"] = { v = "1" }
store["GS:feat_fame"] = { v = "0" }
GR:Refresh()
check("no code: rules as they are", GR:Value("perm_links"), "1")
check("no code: not stale", GR:Stale(), false)

-- the Guild Master: the line to paste (never written)
gm = true
GR:Refresh()
check("the Guild Master's line isn't in place yet", GR:LineInPlace(), false)
timers[1]()
check("...told at login, with the line", printed[1] and printed[1]:find(GR:Line(), 1, true) ~= nil, true)
info = info .. "\n" .. GR:Line() -- pasted
check("pasted: in place", GR:LineInPlace(), true)

-- a member's copy: matching
gm = false
GR:Refresh()
check("matching: the rules count", GR:Value("perm_links"), "1")

-- a made-up rule arrives that doesn't match the code: strict
store["GS:perm_links"] = { v = "1,4" }
GR:Refresh()
check("not matching: stale", GR:Stale(), true)
check("...a sync check asks for the rules", ns.checked, true)
check("...every row only the Guild Master", GR:Value("perm_links"), "-")
check("...even rows never set", GR:Value("perm_signup"), "-")
check("...switches as they last matched", GR:Value("feat_fame"), "0")

-- in combat (or any restriction): the Guild Info isn't read; the last code counts
local before = reads
combat = true
GR:Refresh()
check("in combat: not read", reads, before)
check("...the last code read still counts (strict)", GR:Value("perm_links"), "-")
combat, active = false, true
GR:Refresh()
check("an encounter (any restriction): not read", reads, before)
active = false

-- the Guild Master changes it for real and pastes the new line; restrictions lift
gm = true
local line = GR:Line()
gm = false
info = info:gsub("NGM:%w+", line)
events.ADDON_RESTRICTION_STATE_CHANGED(nil, 1, 0)
check("restrictions lifted: read again, matching", GR:Value("perm_links"), "1,4")
check("...and no longer stale", GR:Stale(), false)
check("the NGM Addon never writes the Guild Info", writes, 0)
print("OK")
