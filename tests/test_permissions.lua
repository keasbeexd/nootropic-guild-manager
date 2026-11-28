-- Test: the Guild Master's permissions (3.2, docs/PERMISSIONS.md) in every
-- copy: defaults, chosen ranks, officer-only rows that can only be narrowed,
-- the author's rule holding when an officer passes a change on, feature
-- switches and messages, and ban records.
local ROOT = arg[1]
local NOW = 1800000000
local ns = {}
local guild = { members = {}, sync = { guild = {}, officer = {} } }
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end
function ns.Debounce(_, _, fn) fn() end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.IsOfficer() return false end
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
function ns.DB:RootOf(n) return n end
ns.Roster = { byName = {
  ["Gm Boss-R"] = { rankIndex = 0 }, ["Mira Officer-R"] = { rankIndex = 1 }, ["Vic Veteran-R"] = { rankIndex = 2 },
  ["Bob Member-R"] = { rankIndex = 4 }, ["Ann Member-R"] = { rankIndex = 4 }, ["Me Self-R"] = { rankIndex = 4 } } }
C_Timer = { After = function() end }
GetTime = function() return 100 end
IsInGuild = function() return true end
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns) assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
local S = ns.Sync
S.Pump = function() end
-- who may invite: officers and Veterans (the game's Invite Member)
S.RankFlags = function(_, i) return ({ [1] = { officer = true, invite = true }, [2] = { officer = false, invite = true }, [4] = { officer = false, invite = false } })[i] end
local P = S.PROTO
local T = NOW - 100
local function rec(sender, key, author, value)
  T = T + 1
  S:OnMessage(table.concat({ P, "R", key, tostring(T), author, "", value }, "\t"), "GUILD", sender)
  local r = guild.sync.guild[key]
  return r and r.v
end
local function check(name, got, want) print(("%-62s %s"):format(name, got == want and "ok" or ("FAIL (got " .. tostring(got) .. ")"))) assert(got == want) end

-- defaults: today's behavior
check("recruiting rows need the recruiting tools: a member can't add", rec("Bob Member-R", "DN:Spam-R", "Bob Member-R", "1;no"), nil)
check("default: a rank that may invite adds", rec("Vic Veteran-R", "DN:Spam-R", "Vic Veteran-R", "1;no"), "1;no")
check("default: a member can't take someone off it", rec("Bob Member-R", "DN:Spam-R", "Bob Member-R", ""), "1;no")
check("default: a rank that may invite can", rec("Vic Veteran-R", "DN:Spam-R", "Vic Veteran-R", ""), "")
check("default: anyone sends an install reminder", rec("Bob Member-R", "IR:Ann Member-R", "Bob Member-R", tostring(NOW - 50)) ~= nil, true)
check("default: a member can't hide someone from the Hall of Fame", rec("Bob Member-R", "HX:Ann Member-R", "Bob Member-R", "1"), nil)
check("default: an officer can", rec("Mira Officer-R", "HX:Ann Member-R", "Mira Officer-R", "1"), "1")

-- handed to every rank, the recruiting rows still need the recruiting tools
permRanks.dnw_remove = { [1] = true, [2] = true, [4] = true }
check("Do Not Whisper handed to members: still needs recruiting", S:Allowed("Bob Member-R", "dnw_remove"), false)
permRanks.dnw_remove = nil
-- the Officer Log: officers, narrowed by the Guild Master
check("an officer writes in the Officer Log", S:Allowed("Mira Officer-R", "officerlog"), true)
permRanks.officerlog = { [4] = true }
check("handed to members: still officers only, and Mira's rank isn't in it", S:Allowed("Bob Member-R", "officerlog") or S:Allowed("Mira Officer-R", "officerlog"), false)
permRanks.officerlog = nil

-- the Guild Master narrows Do Not Whisper to officers only
permRanks.dnw_add = { [1] = true }
check("ranks chosen: a member can't add any more", rec("Bob Member-R", "DN:Other-R", "Bob Member-R", "1;x"), nil)
check("ranks chosen: an officer can", rec("Mira Officer-R", "DN:Other-R", "Mira Officer-R", "1;x"), "1;x")
check("a member's add passed on by an officer: still refused", rec("Mira Officer-R", "DN:Third-R", "Bob Member-R", "1;x"), nil)

-- only the Guild Master: messages and rules
check("officer writes the guild's recruitment messages (default: only the Guild Master)", rec("Mira Officer-R", "GS:rmsgs", "Mira Officer-R", "1;a"), nil)
check("the Guild Master does", rec("Gm Boss-R", "GS:rmsgs", "Gm Boss-R", "1;a"), "1;a")
permRanks.rmsg = { [2] = true }
check("handed to Veterans: a Veteran writes them (not an officer rank)", rec("Vic Veteran-R", "GS:rmsgs", "Vic Veteran-R", "1;b"), "1;b")
check("an officer can't turn a feature off", rec("Mira Officer-R", "GS:feat_fame", "Mira Officer-R", "0"), nil)
check("the Guild Master can", rec("Gm Boss-R", "GS:feat_fame", "Gm Boss-R", "0"), "0")

-- officer-only rows can be narrowed, never widened
permRanks.audit = { [1] = true, [4] = true }
check("audit handed to members: still officers only", S:Allowed("Bob Member-R", "audit"), false)
check("audit: officers kept", S:Allowed("Mira Officer-R", "audit"), true)

-- sign-ups: the rule, but withdrawing is always allowed
permRanks.signup = { [1] = true }
check("sign-ups narrowed: a member can't sign up", rec("Bob Member-R", "ES:gabc:Bob Member-R", "Bob Member-R", "tank;"), nil)
permRanks.signup = nil
check("sign-ups back to everyone", rec("Bob Member-R", "ES:gabc:Bob Member-R", "Bob Member-R", "tank;"), "tank;")
permRanks.signup = { [1] = true }
check("withdrawing is always allowed", rec("Bob Member-R", "ES:gabc:Bob Member-R", "Bob Member-R", ""), "")

-- events: the Guild Master's rule once set
permRanks.ev_raid = { [2] = true }
check("raids handed to Veterans: a Veteran may create one", S:MayCreateEvent("Vic Veteran-R", "raid"), true)
check("...an officer not in it may not", S:MayCreateEvent("Mira Officer-R", "raid"), false)
check("...the Guild Master always may", S:MayCreateEvent("Gm Boss-R", "raid"), true)

-- bans: officers by default
local ban = ("%d;Mira Officer-R;Player-1-0ABC;Spammy Main-R;stole the bank"):format(NOW)
check("a member can't ban", rec("Bob Member-R", "BN:Spammy-R", "Bob Member-R", ban), nil)
check("an officer can", rec("Mira Officer-R", "BN:Spammy-R", "Mira Officer-R", ban), ban)
check("bans can't carry escape codes", S.ValidValue("BN", ("%d;x;;y;|Hx|h"):format(NOW)), false)
check("a ban's game ID is a player's", S.ValidValue("BN", ("%d;x;Creature-1;y;r"):format(NOW)), false)
check("unbanning is a ban permission too", rec("Bob Member-R", "BN:Spammy-R", "Bob Member-R", ""), ban)

-- your own copy writes by the same rules (S:Set goes through S:CanWrite)
local myBan = ("%d;Me Self-R;;Spammy Main-R;x"):format(NOW)
check("my own copy: a member can't ban", (S:Set("BN:Other Spammer-R", myBan)), nil)
permRanks.ban = { [4] = true }
check("handed to members: my copy bans", (S:Set("BN:Other Spammer-R", myBan)), true)
ns.Recruit = { GameInvite = function() return true end } -- the game lets my rank invite
check("...the Guild Master's messages too once handed out (not an officer rank)", (function() permRanks.rmsg = { [4] = true } permRanks.recruit = { [4] = true } return S:CanWrite("GS:rmsgs") end)(), true)
check("...but never the rules themselves", S:CanWrite("GS:perm_ban"), false)
permRanks.dnw_add, permRanks.dnw_remove = nil, nil
check("Do Not Whisper: adding (everyone who may recruit)", S:CanWrite("DN:Spam2-R", "1;x"), true)
check("...taking off: the default, ranks the game lets invite (mine may)", S:CanWrite("DN:Spam2-R", ""), true)
ns.Recruit.GameInvite = function() return false end
check("...without Invite Member, neither (recruiting needs it too)", S:CanWrite("DN:Spam2-R", "") or S:CanWrite("DN:Spam3-R", "1;x"), false)
print("OK")
