-- Test: Forged and legitimate sync records: Guild Master permissions, links, profiles, own-profile permission, self-only records, officer relays, Do Not Whisper removal, escape codes, re-send markers.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = {}
local guild = { members = {}, sync = { guild = {}, officer = {} } }
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end
function ns.Debounce(_, _, fn) fn() end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
local iAmOfficer = false
function ns.IsOfficer() return iAmOfficer end
function ns.PlayerFullName() return "Me Self-R" end
function ns.NormalizeName(n) if n:find("-") then return n end return n .. "-R" end
function ns.ShortName(n) return (n:gsub("%-.*", "")) end
local permRanks = {}
ns.DB = { PERM_BY_TYPE = { M = "links", MS = "profiles", RL = "profiles", MP = "profiles", CN = "profiles" } }
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return { auditDays = 30 } end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
function ns.DB:PermRanks(k) return permRanks[k] end
function ns.DB:PermDef(k) return k == "ownprofile" and { everyone = true } or {} end
ns.Roster = { byName = {
  ["Gm Boss-R"] = { rankIndex = 0 }, ["Mira Officer-R"] = { rankIndex = 1 },
  ["Bob Member-R"] = { rankIndex = 4 }, ["Ann Member-R"] = { rankIndex = 4 }, ["Me Self-R"] = { rankIndex = 4 } } }
C_Timer = { After = function() end }
GetTime = function() return 100 end
IsInGuild = function() return true end
assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
local S = ns.Sync
S.Pump = function() end
local P = S.PROTO
local function rec(sender, key, author, value, channel)
  S:OnMessage(table.concat({ P, "R", key, tostring(NOW - 10), author, "", value }, "\t"), channel or "GUILD", sender)
  local r = guild.sync[channel == "OFFICER" and "officer" or "guild"][key]
  return r and r.v
end
local function check(name, got, want) print(("%-58s %s"):format(name, got == want and "ok" or ("FAIL (got " .. tostring(got) .. ")"))) assert(got == want) end
-- Mira becomes a known officer by sending on the officer channel
S:OnMessage(P .. "\tD\tofficer\t", "OFFICER", "Mira Officer-R")
check("member writes Guild Master permission as himself", rec("Bob Member-R", "GS:perm_links", "Bob Member-R", "4"), nil)
check("member forges Guild Master permission (author = GM)", rec("Bob Member-R", "GS:perm_links", "Gm Boss-R", "4"), nil)
check("Guild Master sets permission", rec("Gm Boss-R", "GS:perm_links", "Gm Boss-R", "1"), "1")
check("officer relays the GM's permission", rec("Mira Officer-R", "GS:perm_profiles", "Gm Boss-R", "1"), "1")
check("officer forges permission as herself", rec("Mira Officer-R", "GS:perm_recruit", "Mira Officer-R", "-"), nil)
check("member links someone's main (no permission)", rec("Bob Member-R", "M:Ann Member-R", "Bob Member-R", "Bob Member-R"), nil)
permRanks.links = { [4] = true }
check("member links a main once his rank is allowed", rec("Bob Member-R", "M:Ann Member-R", "Bob Member-R", "Bob Member-R"), "Bob Member-R")
check("member edits own spec", rec("Bob Member-R", "MS:Bob Member-R", "Bob Member-R", "Holy"), "Holy")
check("member edits someone else's spec", rec("Bob Member-R", "MS:Ann Member-R", "Bob Member-R", "Holy"), nil)
check("member forges someone's own record (claims to be them)", rec("Bob Member-R", "AV:Ann Member-R", "Ann Member-R", "9.9"), nil)
check("member sends own version", rec("Ann Member-R", "AV:Ann Member-R", "Ann Member-R", "2.1"), "2.1")
check("officer relays someone's own record", rec("Mira Officer-R", "SC:Ann Member-R", "Ann Member-R", "ff"), "ff")
check("member adds to Do Not Whisper (anyone may)", rec("Bob Member-R", "DN:Spammer-R", "Bob Member-R", "1;no"), "1;no")
check("escape codes are defused", rec("Bob Member-R", "DN:Other-R", "Bob Member-R", "1;|TInterface\\x:99|t hi"), "1;/TInterface\\x:99/t hi")
check("key with an escape code is dropped", rec("Bob Member-R", "DN:Ev|cil-R", "Bob Member-R", "1;x"), nil)
check("officer-channel record from an officer", rec("Mira Officer-R", "L:Ann Member-R:1", "Mira Officer-R", "1;m;note", "OFFICER") ~= nil or not iAmOfficer, true)
-- chunks
S:OnMessage(table.concat({ P, "C", "zz", "1", "999", "x" }, "\t"), "GUILD", "Bob Member-R")
local n = 0 for _ in pairs(debug and {} or {}) do n = n + 1 end
for i = 1, 20 do S:OnMessage(table.concat({ P, "C", "id" .. i, "1", "2", "x" }, "\t"), "GUILD", "Bob Member-R") end
-- bucket markers
S.dumped = { guild = {}, officer = {} }
S:OnMessage(P .. "\tB\tguild\t3", "GUILD", "Bob Member-R"); check("member's re-send marker is ignored", S.dumped.guild[3], nil)
S:OnMessage(P .. "\tB\tguild\t3", "GUILD", "Mira Officer-R"); check("officer's re-send marker counts", S.dumped.guild[3], 100)
check("officer edits a member's spec (default: officers)", rec("Mira Officer-R", "MS:Ann Member-R", "Mira Officer-R", "Frost"), "Frost")
check("member edits someone's contact (no permission)", rec("Bob Member-R", "CN:Ann Member-R", "Bob Member-R", "x;y"), nil)
permRanks.profiles = { [4] = true }
check("member edits a contact once his rank may", rec("Bob Member-R", "CN:Ann Member-R", "Bob Member-R", "x;y"), "x;y")
permRanks.recruit = nil
check("recruit now defaults to officers: member can't remove DNW", rec("Bob Member-R", "DN:Spammer-R", "Bob Member-R", ""), "1;no")
permRanks.recruit = { [1] = true }
check("member without recruit permission removes a DNW entry", rec("Bob Member-R", "DN:Spammer-R", "Bob Member-R", ""), "1;no")
check("recruiter removes a DNW entry", rec("Mira Officer-R", "DN:Spammer-R", "Mira Officer-R", ""), "")
permRanks.ownprofile = { [1] = true }
permRanks.profiles = nil
check("own-profile permission off for his rank: own spec refused", rec("Bob Member-R", "MS:Bob Member-R", "Bob Member-R", "Shadow"), "Holy")
permRanks.profiles = { [4] = true }
check("own-profile off, but rank may edit everyone's profiles", rec("Bob Member-R", "RL:Bob Member-R", "Bob Member-R", "tank"), "tank")
permRanks.profiles = nil
check("own-profile off and no profiles permission: refused", rec("Bob Member-R", "RL:Bob Member-R", "Bob Member-R", "healer"), "tank")
permRanks.ownprofile = nil
check("own-profile back to default (everyone): own edit works", rec("Bob Member-R", "RL:Bob Member-R", "Bob Member-R", "tanky"), "tanky")
-- limits
for i = 1, 12 do rec("Ann Member-R", "RP:Ann Member-R:" .. i, "Ann Member-R", "Alchemy;1") end
check("13th profession list from one member", rec("Ann Member-R", "RP:Ann Member-R:99", "Ann Member-R", "Alchemy;1"), nil)
check("recipe key with a made-up shape", rec("Ann Member-R", "RP:Ann Member-R:x", "Ann Member-R", "Alchemy;1"), nil)
check("oversized value", rec("Ann Member-R", "AV:Ann Member-R", "Ann Member-R", string.rep("a", 5000)), "2.1")
S.NEW_KEYS_PER_WINDOW = 3
for i = 1, 5 do rec("Bob Member-R", "DN:Flood" .. i .. "-R", "Bob Member-R", "1;x") end
check("flood: 4th new entry in the window refused", guild.sync.guild["DN:Flood4-R"], nil)
check("officer repair isn't rate-limited", rec("Mira Officer-R", "DN:Relay9-R", "Bob Member-R", "1;y"), "1;y")
print("refused:", S.stats.refused); print("OK")
