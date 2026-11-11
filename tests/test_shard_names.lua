-- Test: WoW: Forever shard tags ("Name-CAMWOWUS2Realm2PvP"). Names are plain;
-- records from older copies on another shard are accepted and land on the
-- right person; saved data from before 2.7.2 is tidied once (newer record
-- wins, private notes merged, per-character settings moved).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
GetBuildInfo = function() return "1.60.1", "70790", "Oct 1 2026", 16001 end
GetNormalizedRealmName = function() return "CAMWOWUS1Realm2PvP" end
C_Timer = { After = function() end }
GetTime = function() return 100 end
IsInGuild = function() return true end
local ns = {}
-- the real name helpers from Core.lua, with the rest stubbed
local core = assert(io.open(ROOT .. "/Core/Core.lua")):read("*a")
local helpers = core:match("(function ns%.Trim.-\nfunction ns%.ShortName)")
assert(helpers, "name helpers not found in Core.lua")
assert(loadstring("local ns = ...\n" .. helpers:gsub("\nfunction ns%.ShortName$", "")))(ns)
function ns.ShortName(full) return full and (full:match("^([^%-]+)") or full) or "" end
assert(ns.NO_REALMS, "Forever detected from the TOC version")
assert(ns.NormalizeName("Probably Shawn-CAMWOWUS2Realm2PvP") == "Probably Shawn")
assert(ns.NormalizeName("Marc Priest") == "Marc Priest")
assert(ns.NormalizeName("") == nil)

local guild = { members = {}, sync = { guild = {}, officer = {} } }
local settings = { schedules = {}, hof = {} }
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end
function ns.Debounce(_, _, fn) fn() end
local iAmOfficer = true
function ns.IsOfficer() return iAmOfficer end
function ns.PlayerFullName() return "Marc Priest" end
ns.DB = { PERM_BY_TYPE = { M = "links", MS = "profiles", RL = "profiles", MP = "profiles", CN = "profiles" } }
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return settings end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
function ns.DB:GetMember(f) return guild.members[f] end
function ns.DB:PermRanks() return nil end
function ns.DB:PermDef(k) return k == "ownprofile" and { everyone = true } or {} end
ns.Roster = { byName = {
  ["Marc Priest"] = { rankIndex = 0 }, ["Probably Shawn"] = { rankIndex = 1 }, ["Grud Sama"] = { rankIndex = 4 } } }
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns) assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
local S = ns.Sync
S.Pump = function() end
local P = S.PROTO

local function send(sender, key, author, value, t, channel)
  S:OnMessage(table.concat({ P, "R", key, tostring(t or NOW - 10), author, "", value }, "\t"), channel or "GUILD", sender)
end

-- an older copy on another shard sends its own records, tagged
local SH = "Probably Shawn-CAMWOWUS2Realm2PvP"
send(SH, "AV:" .. SH, SH, "2.7.1")
assert(guild.sync.guild["AV:Probably Shawn"] and guild.sync.guild["AV:Probably Shawn"].v == "2.7.1", "version lands on the plain name")
assert(guild.sync.guild["AV:Probably Shawn"].a == "Probably Shawn")
assert(not guild.sync.guild["AV:" .. SH])
-- a record that needs them to be in the roster (anyone may add Do Not Whisper)
send(SH, "DN:Spammer Guy-CAMWOWUS2Realm2PvP", SH, "1;no")
assert(guild.sync.guild["DN:Spammer Guy"], "roster check passes for a guildmate on another shard")
-- their own profile edit (needs their rank, looked up in the roster)
send(SH, "MS:" .. SH, SH, "Frost")
assert(guild.sync.guild["MS:Probably Shawn"] and guild.sync.guild["MS:Probably Shawn"].v == "Frost")
-- an officer link with a tagged main
S:OnMessage(P .. "\tD\tofficer\t", "OFFICER", SH)
send(SH, "M:Grud Sama-CAMWOWUS2Realm2PvP", SH, "Marc Priest-CAMWOWUS2Realm2PvP")
assert(guild.sync.guild["M:Grud Sama"].v == "Marc Priest", "main link uses plain names")
-- joined date with inviter, officer scope
send(SH, "JN:Grud Sama-CAMWOWUS2Realm2PvP", SH, "1794123241;Marc Priest-CAMWOWUS2Realm2PvP", nil, "OFFICER")
assert(guild.sync.officer["JN:Grud Sama"].v == "1794123241;Marc Priest")
print("live records from another shard: ok")

-- saved data from before 2.7.2 (a copy of a real one when available)
local function tidy(g, s)
  guild, settings = g, s
  g.realmless = nil
  return S:CanonicalizeSaved()
end
local old = { members = {
    ["Probably Shawn-CAMWOWUS1Realm2PvP"] = { note = "tank" },
    ["Probably Shawn-CAMWOWUS2Realm2PvP"] = { note = "brings snacks" } },
  recruit = { people = { ["Some Recruit-CAMWOWUS2Realm2PvP"] = { whispered = 1 } } },
  sync = { guild = {
    ["MS:Probably Shawn-CAMWOWUS1Realm2PvP"] = { v = "Holy", t = 10, a = "Marc Priest-CAMWOWUS1Realm2PvP" },
    ["MS:Probably Shawn-CAMWOWUS2Realm2PvP"] = { v = "Frost", t = 20, a = "Probably Shawn-CAMWOWUS2Realm2PvP" },
    ["RP:Marc Priest-CAMWOWUS1Realm2PvP:129"] = { v = "First Aid;1", t = 5, a = "Marc Priest-CAMWOWUS1Realm2PvP" },
    ["GS:perm_links"] = { v = "1", t = 3, a = "Marc Priest-CAMWOWUS1Realm2PvP" },
  }, officer = {
    ["A:abc"] = { v = table.concat({ "Grud Sama-CAMWOWUS2Realm2PvP", "M", "", "Marc Priest-CAMWOWUS2Realm2PvP", "", "" }, "\031"), t = 7, a = "Probably Shawn-CAMWOWUS2Realm2PvP" },
    ["L:Grud Sama-CAMWOWUS1Realm2PvP:x1"] = { v = "1;Marc;hi", t = 8, a = "Marc Priest-CAMWOWUS1Realm2PvP" },
  } } }
local s = { schedules = { ["Marc Priest-CAMWOWUS1Realm2PvP"] = { learn = true } }, hof = { ["Marc Priest-CAMWOWUS1Realm2PvP"] = { month = 1 } } }
local moved = tidy(old, s)
local g = old.sync
assert(g.guild["MS:Probably Shawn"].v == "Frost", "newer of the two wins")
assert(g.guild["RP:Marc Priest:129"] and g.guild["GS:perm_links"])
assert(g.officer["L:Grud Sama:x1"] and g.officer["A:abc"].a == "Probably Shawn")
assert(g.officer["A:abc"].v:find("^Grud Sama\031M\031\031Marc Priest\031"), "audit names tidied")
assert(old.members["Probably Shawn"].note == "tank / brings snacks" or old.members["Probably Shawn"].note == "brings snacks / tank", "notes merged")
assert(old.recruit.people["Some Recruit"] and s.schedules["Marc Priest"] and s.hof["Marc Priest"])
assert(old.realmless and S:CanonicalizeSaved() == 0, "runs once")
for _, scope in ipairs({ "guild", "officer" }) do
  for k, r in pairs(g[scope]) do assert(not (k .. (r.a or "")):find("CAMWOW"), k) end
end
print("old saved data tidied:", moved, "changes")

-- the real thing, if a copy was left next to the tests (not in the repo)
local svPath = os.getenv("NGM_SV")
if svPath then
  local f = assert(loadfile(svPath))
  local env = {}
  setfenv(f, env)
  f()
  for name, gg in pairs(env.NootropicGuildManagerDB.guilds) do
    local before = {}
    for _, scope in ipairs({ "guild", "officer" }) do
      local n = 0 for _ in pairs(gg.sync[scope]) do n = n + 1 end
      before[scope] = n
    end
    local changes = tidy(gg, env.NootropicGuildManagerDB.settings)
    local left = 0
    for _, scope in ipairs({ "guild", "officer" }) do
      local n = 0
      for k, r in pairs(gg.sync[scope]) do
        n = n + 1
        if (k .. (r.a or "")):find("CAMWOW") then left = left + 1 end
      end
      print(("  %s %s: %d -> %d records"):format(name, scope, before[scope], n))
    end
    print("  changes", changes, "tags left", left)
    assert(left == 0)
    local av = gg.sync.guild["AV:Probably Shawn"]
    print("  Probably Shawn's version:", av and av.v)
  end
end
print("OK")
