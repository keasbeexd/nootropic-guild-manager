-- Test: Roster change log: guild event log joins/rejoins/kicks/promotions, duplicates across reads and officers, level/note/name changes, join and rank-since records.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = { version = "2.1" }
local guild = { members = {}, sync = { guild = {}, officer = {} } }
local fired = {}
function ns:Fire(ev) fired[ev] = (fired[ev] or 0) + 1 end
function ns:On() end
function ns:RegisterEvent() end
function ns.Debounce(_, _, fn) fn() end
function ns.Safe(fn) return function(...) local ok, e = pcall(fn, ...) if not ok then print("ERR", e) end end end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.IsOfficer() return true end
function ns.PlayerFullName() return "Me-Realm" end
function ns.NormalizeName(n) if not n or n == "" then return nil end if n:find("-") then return n end return n .. "-Realm" end
function ns.ShortName(n) return (n:gsub("%-.*", "")) end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
ns.DB = { PERM_BY_TYPE = {} }
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return { auditDays = 30 } end
function ns.DB:GetMember(f) return guild.members[f] end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
function ns.DB:HasPerm() return true end
function ns.DB:IsGuildMaster() return false end
date = os.date
C_Timer = { After = function() end }
IsInGuild = function() return true end
local function load(f) assert(loadfile(ROOT .. "/" .. f))("NGM", ns) end
load("Core/Records.lua"); load("Core/Sync.lua"); load("Services/Audit.lua"); load("Services/RosterLog.lua")
ns.Sync.readyFor = "g"
ns.Sync.Broadcast = function() end
ns.Sync.QueueOutgoing = function() end

-- fake guild event log: type, p1, p2, rank, y, mo, d, h (ago)
local LOG
GetNumGuildEvents = function() return #LOG end
GetGuildEventInfo = function(i) return unpack(LOG[i]) end
LOG = {
  { "invite", "Mira", "Bob", nil, 0, 0, 3, 2 },
  { "join",   "Bob", nil, nil, 0, 0, 3, 2 },
  { "promote","Mira", "Bob", "Veteran", 0, 0, 1, 5 },
  { "promote","Mira", "Bob", "Officer", 0, 0, 0, 3 },
  { "quit",   "Ann", nil, nil, 0, 0, 2, 0 },
  { "remove", "Mira", "Zed", nil, 0, 0, 0, 1 },
}
local function dump(title)
  print("== " .. title)
  for _, e in ipairs(ns.Audit:Entries({})) do
    print(("  %-6s %-4s %-12s by %-12s %s"):format(math.floor((NOW - e.t) / 3600) .. "h", e.typ, ns.ShortName(e.member or "?"), ns.Audit.Who(e.author), ns.Audit:Describe(e):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  end
end
ns.RosterLog:ReadEventLog()
dump("first read")
local n1 = #ns.Audit:Entries({})
-- same log read again 40 minutes later (hour counts unchanged): no duplicates
NOW = NOW + 2400; ns.Sync.auditCache = nil
ns.RosterLog:ReadEventLog()
assert(#ns.Audit:Entries({}) == n1, "duplicate entries on re-read")
-- a second officer's copy, an hour off, arrives via sync with a different id
ns.Sync:AddAuditEntry("otherofficer1", NOW - 3600 * 75, "Mira-Realm", "Bob-Realm", "GM", "", "join", "Mira-Realm", "x")
assert(#ns.Audit:Entries({}) == n1, "cross-officer duplicate not merged")
print("join record:", guild.sync.officer["JN:Bob-Realm"].v, "rank record:", guild.sync.officer["RK:Bob-Realm"].v)
ns.Sync:RebuildAll()
print("profile lines:", table.concat(ns.RosterLog:Lines("Bob-Realm"), " / "))

-- Bob leaves and rejoins 2 days later
LOG = { { "quit", "Bob", nil, nil, 0, 0, 0, 30 }, { "join", "Bob", nil, nil, 0, 0, 0, 2 } }
ns.RosterLog:ReadEventLog()
dump("after rejoin")

-- roster snapshots
local function roster(lvl, pn, on, name)
  return { { full = name or "Bob-Realm", guid = "G1", level = lvl, publicNote = pn, officerNote = on } }
end
ns.RosterLog:OnRoster(roster(20, "", "alt of x"))        -- first snapshot: nothing
ns.RosterLog:OnRoster(roster(22, "raider", "alt of x"))  -- level + public note
ns.RosterLog:OnRoster(roster(22, "raider", "main", "Bobby-Realm")) -- rename + officer note
ns.RosterLog:OnRoster(roster(22, "raider", "main", "Bobby-Realm")) -- no change
dump("after roster changes")
-- categories filter
assert(#ns.Audit:Entries({ category = "LV" }) == 1)
-- purge keeps roster events
ns.Sync:PurgeUnknown(); ns.Sync.auditCache = nil
print("after purge:", #ns.Audit:Entries({}))
print("OK")
