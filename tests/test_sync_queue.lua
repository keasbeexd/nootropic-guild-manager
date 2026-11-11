-- Test: repairs don't flood the send queue. A regular member passes on only
-- their own records, in the fast lane; officers pass on everything; the same
-- record is never queued twice while it's still waiting.
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
ns.Roster = { byName = {} }
C_Timer = { After = function() end }
GetTime = function() return 100 end
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
for i = 1, 300 do store["RS:Stranger" .. i] = { v = "1;0;0;", t = NOW - 60, a = "Someone Else" } end
store["DN:Spammer"] = { v = "1;no", t = 1, a = "Someone Else" }

local all = {} for b = 1, S.BUCKETS do all[b] = b end

-- a regular member: only her own records, in the fast lane
S:SendBuckets("guild", all)
local function records(q) local n = 0 for _, it in ipairs(q) do if it[1]:find("\tR\t", 1, true) then n = n + 1 end end return n end
assert(records(S.queues.high) == 2, "her two records, fast lane: " .. records(S.queues.high))
assert(records(S.queues.bulk) == 0, "nobody else's records passed on")
-- the next repair doesn't queue them again
S:SendBuckets("guild", all)
assert(records(S.queues.high) == 2, "no duplicates while waiting")

-- once sent, they can be queued again by a later repair
pumpOn = true
S:Pump()
assert(S:QueueSize() == 0 and #sentMsgs > 0)
pumpOn = false
S:SendBuckets("guild", all)
assert(records(S.queues.high) == 2, "re-queued after they went out")
S.queues.high[1] = nil S.queues.high = {} -- (reset)
for k in pairs(S.queues) do S.queues[k] = {} end
for k in pairs(S.waiting) do S.waiting[k] = nil end

-- an officer passes on everything (in the slow lane), her own still first
officer = true
S:SendBuckets("guild", all)
assert(records(S.queues.high) == 2 and records(S.queues.bulk) == 301, "officers relay everything: " .. records(S.queues.bulk))
print("OK")
