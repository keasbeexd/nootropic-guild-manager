-- Test: events made in game (EG), sign-ups (ES) and links to NGM Peon (LK),
-- 3.1 (docs/EVENTS.md): who may create, edit and cancel, with and without
-- NGM Peon; sign-ups only by the member (with NGM Peon: linked characters);
-- LK only from NGM Peon; their own sync lane; expiry after the event.
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
local mains = { ["Bob Alt-R"] = "Bob Member-R" }
ns.DB = { PERM_BY_TYPE = {} }
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return { auditDays = 30 } end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
function ns.DB:PermRanks() return nil end
function ns.DB:PermDef() return {} end
function ns.DB:RootOf(n) return mains[n] or n end
ns.Roster = { byName = {
  ["Gm Boss-R"] = { rankIndex = 0 }, ["Mira Officer-R"] = { rankIndex = 1 }, ["Rae Raider-R"] = { rankIndex = 3 },
  ["Bob Member-R"] = { rankIndex = 4 }, ["Bob Alt-R"] = { rankIndex = 4 }, ["Ann Member-R"] = { rankIndex = 4 }, ["Me Self-R"] = { rankIndex = 4 } } }
C_Timer = { After = function() end }
GetTime = function() return 100 end
IsInGuild = function() return true end
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns) assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
local S = ns.Sync
S.Pump = function() end
local P = S.PROTO
local T = NOW - 200
local function rec(sender, key, author, value)
  T = T + 1 -- each change after the last (newest wins)
  S:OnMessage(table.concat({ P, "R", key, tostring(T), author, "", value }, "\t"), "GUILD", sender)
  local r = guild.sync.guild[key]
  return r and r.v
end
local function check(name, got, want) print(("%-62s %s"):format(name, got == want and "ok" or ("FAIL (got " .. tostring(got) .. ")"))) assert(got == want) end
local function b36(n) local s, d = "", "0123456789abcdefghijklmnopqrstuvwxyz" while n > 0 do local r = n % 36 s = d:sub(r + 1, r + 1) .. s n = (n - r) / 36 end return s end
local function ev(kind, creator, state, title) return table.concat({ kind, b36(NOW + 86400), b36(120), creator, state or "", title or "Molten Core", "Bring fire resist" }, ";") end
S:OnMessage(P .. "\tD\tofficer\t", "OFFICER", "Mira Officer-R") -- Mira: a known officer

-- the lane: 3.0 copies know "events" but not "plans", so they never compare these
check("EG, ES and LK travel in their own lane", S.LaneOf("EG:a1") .. S.LaneOf("ES:ga1:Bob Member-R") .. S.LaneOf("LK:Bob Member-R"), "plansplansplans")
check("NGM Peon's events keep theirs", S.LaneOf("EV:16"), "events")
check("every copy syncs the lane", S:InLane("plans"), true)

-- without NGM Peon: the Guild Master and officers
check("member creates an event (no NGM Peon)", rec("Bob Member-R", "EG:a1", "Bob Member-R", ev("raid", "Bob Member-R")), nil)
check("officer creates one", rec("Mira Officer-R", "EG:a1", "Mira Officer-R", ev("raid", "Mira Officer-R")), ev("raid", "Mira Officer-R"))
check("officer can't create one in someone else's name", rec("Mira Officer-R", "EG:a2", "Mira Officer-R", ev("raid", "Gm Boss-R")), nil)
check("the Guild Master edits it, keeping the creator", rec("Gm Boss-R", "EG:a1", "Gm Boss-R", ev("raid", "Mira Officer-R", "", "MC")), ev("raid", "Mira Officer-R", "", "MC"))
check("an edit can't change the creator", rec("Gm Boss-R", "EG:a1", "Gm Boss-R", ev("raid", "Gm Boss-R", "", "Mine")), ev("raid", "Mira Officer-R", "", "MC"))
check("a member can't cancel it", rec("Bob Member-R", "EG:a1", "Bob Member-R", ev("raid", "Mira Officer-R", "x", "MC")), ev("raid", "Mira Officer-R", "", "MC"))
check("broken values are refused", rec("Mira Officer-R", "EG:a3", "Mira Officer-R", "raid;zz"), nil)
check("no | (escape codes) in an event", rec("Mira Officer-R", "EG:a4", "Mira Officer-R", ev("raid", "Mira Officer-R", "", "|cffff0000Red")), "raid;" .. b36(NOW + 86400) .. ";" .. b36(120) .. ";Mira Officer-R;;/cffff0000Red;Bring fire resist")

-- sign-ups: the member themselves, from any of their characters
check("member signs up", rec("Bob Member-R", "ES:ga1:Bob Member-R", "Bob Member-R", "tank;"), "tank;")
check("from an alt, for their main, bringing the alt", rec("Bob Alt-R", "ES:ga1:Bob Member-R", "Bob Alt-R", "dps;Bob Alt-R"), "dps;Bob Alt-R")
check("someone else signs them up", rec("Ann Member-R", "ES:ga1:Bob Member-R", "Ann Member-R", "absent;"), "dps;Bob Alt-R")
check("an officer passes on someone's sign-up", rec("Mira Officer-R", "ES:ga1:Ann Member-R", "Ann Member-R", "healer;"), "healer;")
check("only known parts", rec("Ann Member-R", "ES:ga1:Ann Member-R", "Ann Member-R", "boss;"), "healer;")
check("withdrawn", rec("Ann Member-R", "ES:ga1:Ann Member-R", "Ann Member-R", ""), "")

-- LK: only NGM Peon writes them (an officer brings them in)
check("member claims to be linked", rec("Bob Member-R", "LK:Bob Member-R", "Bob Member-R", "1"), nil)
check("member forges NGM Peon", rec("Bob Member-R", "LK:Bob Member-R", "NGM Peon", "1"), nil)
check("officer passes on NGM Peon's link", rec("Mira Officer-R", "LK:Rae Raider-R", "NGM Peon", "1"), "1")

-- with NGM Peon: its Event Settings decide; linked characters only sign up
rec("Mira Officer-R", "GS:peon", "NGM Peon", "1")
rec("Mira Officer-R", "GS:evranks", "NGM Peon", "dungeon=3;raid=-;event=4;officers=0")
check("with NGM Peon, Event Settings: rank 3 makes dungeons", rec("Rae Raider-R", "EG:b1", "Rae Raider-R", ev("dungeon", "Rae Raider-R")), ev("dungeon", "Rae Raider-R"))
check("...but not raids (managers only)", rec("Rae Raider-R", "EG:b2", "Rae Raider-R", ev("raid", "Rae Raider-R")), nil)
check("rank 4 makes events", rec("Bob Member-R", "EG:b3", "Bob Member-R", ev("event", "Bob Member-R")), ev("event", "Bob Member-R"))
check("the creator cancels their own", rec("Bob Member-R", "EG:b3", "Bob Member-R", ev("event", "Bob Member-R", "x")), ev("event", "Bob Member-R", "x"))
check("officers aren't managers here (officers=0)", rec("Mira Officer-R", "EG:b4", "Mira Officer-R", ev("raid", "Mira Officer-R")), nil)
check("the Guild Master always is", rec("Gm Boss-R", "EG:b4", "Gm Boss-R", ev("raid", "Gm Boss-R")), ev("raid", "Gm Boss-R"))
check("MayCreateEvent agrees", tostring(S:MayCreateEvent("Rae Raider-R", "dungeon")) .. tostring(S:MayCreateEvent("Rae Raider-R", "raid")), "truefalse")
check("unlinked member can't sign up", rec("Ann Member-R", "ES:gb1:Ann Member-R", "Ann Member-R", "tank;"), nil)
check("linked member can", rec("Rae Raider-R", "ES:gb1:Rae Raider-R", "Rae Raider-R", "tank;"), "tank;")
check("withdrawing needs no link", rec("Bob Member-R", "ES:ga1:Bob Member-R", "Bob Member-R", ""), "")
check("NGM Peon's copy of a Discord sign-up", rec("Mira Officer-R", "ES:p42:Ann Member-R", "NGM Peon", "going;"), "going;")

-- kept until 7 days after the event starts
local r = guild.sync.guild["EG:b1"]
check("an event expires 7 days after it starts", S:ExpiresAt("EG:b1", r), NOW + 86400 + 7 * 86400)
print("OK")
