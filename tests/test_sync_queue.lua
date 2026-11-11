-- Test: answering requests doesn't flood the send queue. A regular member
-- answers only for their own records, in the fast lane; officers answer for
-- anyone (slow lane, their own still fast); the same record is never queued
-- twice while it's still waiting; one requester can't keep us busy.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = {}
local guild = { members = {}, sync = { guild = {}, officer = {} } }
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end
function ns.Debounce(_, _, fn) fn() end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
local officer = false
function ns.IsOfficer() return officer end
function ns.PlayerFullName() return "Mykkie Sickyy" end
function ns.NormalizeName(n) return n end
ns.DB = { PERM_BY_TYPE = {} }
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return {} end
ns.Roster = { byName = { ["Someone Else"] = { rankIndex = 3, rank = "Member" } } }
C_Timer = { After = function() end }
local clock = 100
GetTime = function() return clock end
IsInGuild = function() return true end
local sentMsgs = {}
C_ChatInfo = { SendAddonMessage = function(_, msg) sentMsgs[#sentMsgs + 1] = msg return 0 end }
assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
local S = ns.Sync
local pumpOn = false
local realPump = S.Pump
S.Pump = function(self) if pumpOn then return realPump(self) end end

local store = guild.sync.guild
store["AV:Mykkie Sickyy"] = { v = "2.9.2", t = 1, a = "Mykkie Sickyy" }
store["P:Mykkie Sickyy"] = { v = ";;", t = 1, a = "Mykkie Sickyy" }
for i = 1, 300 do store["P:Stranger" .. i] = { v = "x", t = NOW - 60, a = "Someone Else" } end

local function records(q) local n = 0 for _, it in ipairs(q) do if it[1]:find("\tR\t", 1, true) then n = n + 1 end end return n end
local function ask(author, from) S:OnAsk("guild", "Mykkie Sickyy", author, "0", from or "Asker", "GUILD") end
local function reset() for k in pairs(S.queues) do S.queues[k] = {} end for k in pairs(S.waiting) do S.waiting[k] = nil end S.answered = {} S.answerCount = {} end

-- a regular member: only her own records, in the fast lane
ask("Mykkie Sickyy")
ask("Someone Else")
assert(records(S.queues.high) == 2, "her two records, fast lane: " .. records(S.queues.high))
assert(records(S.queues.bulk) == 0, "nobody else's records passed on")
-- asked again at once: answered once
ask("Mykkie Sickyy", "Another Asker")
assert(records(S.queues.high) == 2, "the same answer isn't repeated right away")
-- later, but still waiting to go out: not queued twice
clock = clock + 60
ask("Mykkie Sickyy")
assert(records(S.queues.high) == 2, "no duplicates while waiting")
-- once sent, they can be queued again
pumpOn = true
S:Pump()
assert(S:QueueSize() == 0 and #sentMsgs > 0)
pumpOn = false
clock = clock + 60
ask("Mykkie Sickyy")
assert(records(S.queues.high) == 2, "re-queued after they went out")
reset()

-- an officer passes on anyone's (in the slow lane)
officer = true
ask("Someone Else")
assert(records(S.queues.bulk) == 300, "officers answer for anyone: " .. records(S.queues.bulk))
reset()

-- one requester can't keep us busy: 30 answers a minute
local n = 0
for i = 1, 50 do S:OnAsk("guild", "Mykkie Sickyy", "Mykkie Sickyy", "0", "Pest", "GUILD") clock = clock + 0.01 S.answered = {} end
n = records(S.queues.high)
for k in pairs(S.waiting) do S.waiting[k] = nil end
assert(S.answerCount["Pest"].n == 30, "capped at 30: " .. S.answerCount["Pest"].n)
print("OK")
