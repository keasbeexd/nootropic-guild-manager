-- Test: checking Hall of Fame numbers against the game's comparison when an
-- officer inspects a guildmate: claims above the real number (plus a margin)
-- are flagged, lower ones (shared numbers lag a little) aren't; officers
-- only; once per 6 hours; the result is shared and shown to officers.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = { Widgets = {} }
local guild = { members = {}, sync = { guild = {}, officer = {} } }
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end function ns:Print() end
function ns.Debounce(_, _, fn) fn() end
function ns.Safe(fn) return fn end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
iAmOfficer = true
function ns.IsOfficer() return iAmOfficer end
function ns.PlayerFullName() return "Marc Priest" end
function ns.NormalizeName(n) return n end
function ns.ShortName(n) return n end
function ns.FormatAgo() return "just now" end
ns.DB = { PERM_BY_TYPE = {} }
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return {} end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
function ns.DB:PermRanks() return nil end
function ns.DB:PermDef() return {} end
local cheat = { full = "Grud Sama", short = "Grud Sama", guid = "G-1" }
local honest = { full = "Mykkie Moo", short = "Mykkie Moo", guid = "G-2" }
ns.Roster = { members = { cheat, honest }, byName = { ["Grud Sama"] = cheat, ["Mykkie Moo"] = honest, ["Marc Priest"] = { rankIndex = 0 } },
  byGuid = { ["G-1"] = cheat, ["G-2"] = honest } }
local clock = 100
C_Timer = { After = function() end, NewTicker = function() end }
GetTime = function() return clock end
IsInGuild = function() return true end
date, time = os.date, os.time
assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
ns.Sync.readyFor = "g"; ns.Sync.QueueOutgoing = function() end
assert(loadfile(ROOT .. "/Services/Sharing.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/HallOfFame.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/HofCheck.lua"))("NGM", ns)
local HF, CK = ns.HallOfFame, ns.HofCheck

-- what each shares, and what the game really says
guild.sync.guild["HF:Grud Sama"] = { v = HF.Encode(202701, { quests = 900, kills = 1000, deaths = 5 }, {}, 0, {}), t = 1, a = "Grud Sama" }
guild.sync.guild["HF:Mykkie Moo"] = { v = HF.Encode(202701, { quests = 98, kills = 760 }, {}, 0, {}), t = 1, a = "Mykkie Moo" }
local real = { ["G-1"] = { [98] = "150", [1197] = "1,005", [60] = "9" }, ["G-2"] = { [98] = "100", [1197] = "764" } }
local comparing
SetAchievementComparisonUnit = function(unit) comparing = unit == "target" and UnitGUID("target") end
GetComparisonStatistic = function(id) return comparing and real[comparing][id] or "--" end
ClearAchievementComparisonUnit = function() comparing = nil end
local targetGuid
UnitGUID = function(u) if u == "target" then return targetGuid end end

assert(CK.Compare({ quests = 900, kills = 1000 }, { quests = 150, kills = 1005 }) == "bad;quests=900/150")
assert(CK.Compare({ quests = 98 }, { quests = 100 }) == "ok", "a little behind the game is fine")
assert(CK.Compare({ quests = 102 }, { quests = 100 }) == "ok", "within the margin")

-- an officer inspects the cheater
targetGuid = "G-1"
CK:OnInspectReady("G-1")
assert(CK.pending and comparing == "G-1")
CK:OnComparisonReady("G-1")
assert(comparing == nil, "comparison cleared afterwards")
local res = CK:Result("Grud Sama")
assert(res and not res.ok and #res.bad == 1 and res.bad[1].key == "quests" and res.bad[1].claimed == 900 and res.bad[1].real == 150)
assert(CK:TooltipLine("Grud Sama"):find("don't match"))
-- the honest one
clock = clock + 20
targetGuid = "G-2"
CK:OnInspectReady("G-2"); CK:OnComparisonReady("G-2")
assert(CK:Result("Mykkie Moo").ok and CK:TooltipLine("Mykkie Moo"):find("match the game"))
-- once per 6 hours
clock = clock + 60
targetGuid = "G-1"
CK:OnInspectReady("G-1")
assert(not CK.pending, "checked recently")
-- non-officers neither check nor see results
iAmOfficer = false
clock = clock + 7 * 3600
CK:OnInspectReady("G-1")
assert(not CK.pending and CK:TooltipLine("Grud Sama") == nil)
-- and can't forge a result
ns.Sync:OnMessage(table.concat({ ns.Sync.PROTO, "R", "HC:Mykkie Moo", tostring(NOW), "Grud Sama", "", tostring(NOW) .. ";bad;quests=1/0" }, "\t"), "GUILD", "Grud Sama")
iAmOfficer = true
assert(CK:Result("Mykkie Moo").ok, "only officers write check results")
print("OK")
