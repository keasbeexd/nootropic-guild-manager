-- Test: lean sync (2.10). Two copies compare record lists and send each
-- other exactly the records the other lacks; big records travel compressed
-- only while everyone online can read them; recruitment statuses have their
-- own lane between members who may recruit; older copies still get the old
-- whole-group repair.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local pending = {}
C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
GetTime = function() return 100 end
IsInGuild = function() return true end
-- a stand-in for the game's Deflate + Base64: reversible, and shorter for
-- the repetitive values we use here
local packed = {}
C_EncodingUtil = {
  CompressString = function(s) packed[#packed + 1] = s return "#" .. #packed end,
  DecompressString = function(s) local v = packed[tonumber(s:match("^#(%d+)$") or -1)] if not v then error("bad") end return v end,
  EncodeBase64 = function(s) return s end,
  DecodeBase64 = function(s) return s end,
}

local function Client(me, opts)
  local ns = {}
  local guild = { members = {}, sync = { guild = {}, officer = {} } }
  function ns:Fire() end function ns:On() end function ns:RegisterEvent() end
  function ns.Debounce(_, _, fn) fn() end
  function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
  function ns.IsOfficer() return opts.officer or false end
  function ns.PlayerFullName() return me end
  function ns.NormalizeName(n) return n end
  function ns.ShortName(n) return n end
  function ns.CompareVersions(a, b)
    local function parts(v) local t = {} for d in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(d) end return t end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
      local p, q = x[i] or 0, y[i] or 0
      if p ~= q then return p < q and -1 or 1 end
    end
    return 0
  end
  ns.DB = { PERM_BY_TYPE = {} }
  function ns.DB:Guild() return guild end
  function ns.DB:Now() return NOW end
  function ns.DB:Settings() return { auditDays = 30 } end
  function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
  function ns.DB:PermRanks() return nil end
  function ns.DB:PermDef() return { everyone = true } end
  ns.Roster = { byName = {}, members = opts.members or {} }
  for _, n in ipairs({ "Ann", "Bob", "Cat", "Old" }) do ns.Roster.byName[n] = { rankIndex = 4 } end
  ns.Recruit = { MayRecruit = function() return opts.recruits or false end }
  assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
  local S = ns.Sync
  S.Pump = function() end
  return { S = S, store = guild.sync.guild, name = me }
end

-- deliver everything queued, from each client to the others, until quiet;
-- counts record messages (R/Z) that went out
local function Run(clients)
  local records, kinds = 0, {}
  for _ = 1, 50 do
    local moved = false
    for _, c in ipairs(clients) do
      for _, lane in ipairs({ "high", "bulk" }) do
        local q = c.S.queues[lane]
        c.S.queues[lane] = {}
        for _, it in ipairs(q) do
          moved = true
          if it[4] then c.S.waiting[it[4]] = nil end
          local kind = it[1]:match("^[^\t]+\t(%u)")
          kinds[kind] = (kinds[kind] or 0) + 1
          if kind == "R" or kind == "Z" then records = records + 1 end
          local scope = kind == "D" and it[1]:match("^[^\t]+\tD\t(%w+)")
          if scope then kinds["D:" .. scope] = (kinds["D:" .. scope] or 0) + 1 end
          for _, o in ipairs(clients) do
            if o ~= c then o.S:OnMessage(it[1], it[2], c.name) end
          end
        end
      end
    end
    local fns = pending
    pending = {}
    for _, fn in ipairs(fns) do moved = true fn() end
    if not moved then break end
  end
  return records, kinds
end

local function check(name, ok) print(("%-62s %s"):format(name, ok and "ok" or "FAIL")) assert(ok) end
local function R(v, t, a) return { v = v, t = t, a = a } end
local function Reset(c) for k in pairs(c.S.queues) do c.S.queues[k] = {} end for k in pairs(c.S.waiting) do c.S.waiting[k] = nil end end

------------------------------------------------------------------------
-- 1. exact differences between two 2.10 copies
------------------------------------------------------------------------
local current = { { full = "Ann", online = true, hasAddon = true, version = "2.10.0" },
                  { full = "Bob", online = true, hasAddon = true, version = "2.10.0" } }
local A = Client("Ann", { members = current })
local B = Client("Bob", { members = current })
for _, c in ipairs({ A, B }) do
  c.store["AV:Ann"] = R("2.10.0", NOW - 500, "Ann")
  c.store["AV:Bob"] = R("2.10.0", NOW - 500, "Bob")
  for i = 1, 60 do c.store["N:Ann" .. i] = nil end
end
-- lots in common...
for i = 1, 40 do
  A.store["MS:Ann" .. i] = nil
  A.store["P:Ann" .. i] = R("spec" .. i, NOW - 1000, "Ann")
  B.store["P:Ann" .. i] = R("spec" .. i, NOW - 1000, "Ann")
end
-- ...and a few differences
A.store["P:Ann"] = R("new", NOW - 10, "Ann")          -- Bob has an older one
B.store["P:Ann"] = R("old", NOW - 900, "Ann")
B.store["P:Bob"] = R("mine", NOW - 20, "Bob")         -- Ann lacks it
A.store["HF:Ann"] = R("1", NOW - 30, "Ann")           -- Bob lacks it

local guildA = A.S:Digest("guild")
check("the copies start out different", table.concat(guildA, ",") ~= table.concat(B.S:Digest("guild"), ","))
A.S:Exchange(true)
local sent, kinds = Run({ A, B })
check("lists were exchanged", (kinds.L or 0) >= 2)
check("no whole groups re-sent", (kinds.B or 0) == 0)
check("only the 3 differing records were sent (" .. sent .. ")", sent == 3)
check("Bob got Ann's newer record", B.store["P:Ann"].v == "new")
check("Bob got the one he lacked", B.store["HF:Ann"] and B.store["HF:Ann"].v == "1")
check("Ann got Bob's", A.store["P:Bob"] and A.store["P:Bob"].v == "mine")
check("now the same", table.concat(A.S:Digest("guild"), ",") == table.concat(B.S:Digest("guild"), ","))
check("no old-style checksums while everyone online is current", (kinds["D:g"] or 0) >= 1 and not kinds["D:guild"])

-- a non-officer doesn't pass on someone else's record
Reset(A) Reset(B)
B.store["P:Cat"] = nil
A.store["P:Cat"] = R("cat", NOW - 5, "Cat")
A.S.listAsked, B.S.listAsked, A.S.listAnswered, B.S.listAnswered = {}, {}, {}, {}
A.S.lastExchange, B.S.lastExchange = nil, nil
B.S:Exchange(true)
sent = Run({ A, B })
check("Cat's record isn't relayed by a regular member", B.store["P:Cat"] == nil and sent == 0)

------------------------------------------------------------------------
-- 2. compression
------------------------------------------------------------------------
Reset(A)
local big = string.rep("abcdefgh;", 40)
A.store["P:Ann"] = R(big, NOW - 1, "Ann")
A.S:Broadcast("P:Ann", A.store["P:Ann"])
local q = A.S.queues.high
local last = q[#q] and q[#q][1] or ""
check("a big record goes compressed", last:match("^[^\t]+\tZ\t") ~= nil)
sent = Run({ A, B })
check("and arrives whole", B.store["P:Ann"].v == big)
-- an older copy online: no compression
current[#current + 1] = { full = "Old", online = true, hasAddon = true, version = "2.9.3" }
A.S.compressCheckedAt = nil
A.S:Broadcast("P:Ann", A.store["P:Ann"])
q = A.S.queues.high
check("not while an older copy is online", q[#q][1]:match("^[^\t]+\tR\t") ~= nil or q[#q][1]:match("^[^\t]+\tC\t") ~= nil)
Reset(A)
-- a damaged compressed record is dropped
B.S:OnMessage(table.concat({ B.S.PROTO, "Z", "P:Ann", tostring(NOW), "Ann", "", "#999" }, "\t"), "GUILD", "Ann")
check("a damaged compressed record is ignored", B.store["P:Ann"].v == big)

------------------------------------------------------------------------
-- 3. recruitment statuses: their own lane
------------------------------------------------------------------------
local R1 = Client("Ann", { recruits = true, members = current })
local R2 = Client("Bob", { recruits = true, members = current })
local NR = Client("Cat", { recruits = false, members = current })
for _, c in ipairs({ R1, R2, NR }) do
  c.store["AV:Ann"] = R("2.10.0", NOW - 500, "Ann")
  c.store["AV:Bob"] = R("2.10.0", NOW - 500, "Bob")
  c.store["AV:Cat"] = R("2.10.0", NOW - 500, "Cat")
end
for i = 1, 100 do R1.store["RS:Stranger" .. i] = R("1;0;0;", NOW - 60, "Ann") end
check("statuses don't change the guild checksums",
  table.concat(R1.S:Digest("guild"), ",") == table.concat(NR.S:Digest("guild"), ","))
R1.S:Exchange(true)
sent = Run({ R1, R2, NR })
local n2, n3 = 0, 0
for k in pairs(R2.store) do if k:find("^RS:") then n2 = n2 + 1 end end
for k in pairs(NR.store) do if k:find("^RS:") then n3 = n3 + 1 end end
check("the other recruiter got all 100 (" .. n2 .. ")", n2 == 100)
check("the member who can't recruit kept none (" .. n3 .. ")", n3 == 0)
-- the recruiter passes on statuses someone else wrote
R2.store["RS:Stranger1"] = nil
R1.store["RS:Stranger1"] = nil
local R3 = Client("Cat", { recruits = true, members = current })
R3.store["AV:Bob"] = R("2.10.0", NOW - 500, "Bob")
R3.store["AV:Ann"] = R("2.10.0", NOW - 500, "Ann")
R3.S:Exchange(true)
Run({ R2, R3 })
local n4 = 0
for k in pairs(R3.store) do if k:find("^RS:") then n4 = n4 + 1 end end
check("recruiters pass on everyone's statuses (" .. n4 .. ")", n4 == 99)

------------------------------------------------------------------------
-- 4. an older copy: old-style checksums, whole-group repair
------------------------------------------------------------------------
local mixed = { { full = "Ann", online = true, hasAddon = true, version = "2.10.0" },
                { full = "Old", online = true, hasAddon = true, version = "2.9.3" } }
local N = Client("Ann", { members = mixed })
N.store["AV:Ann"] = R("2.10.0", NOW - 500, "Ann")
N.store["AV:Old"] = R("2.9.3", NOW - 500, "Old")
N.store["P:Ann"] = R("x", NOW - 50, "Ann")
N.S:Exchange(true)
local d = {}
for _, it in ipairs(N.S.queues.high) do local s = it[1]:match("^[^\t]+\tD\t(%w+)") if s then d[s] = true end end
check("sends old-style checksums while an older copy is online", d.guild and d.g)
Reset(N)
-- the old copy's checksums (all zeros: it has nothing) make us re-send groups
local zeros = {} for i = 1, N.S.BUCKETS do zeros[i] = "0" end
N.S:OnMessage(table.concat({ N.S.PROTO, "D", "guild", table.concat(zeros, ",") }, "\t"), "GUILD", "Old")
for _, fn in ipairs(pending) do fn() end pending = {}
local gotB, gotRec = false, false
for _, it in ipairs(N.S.queues.high) do
  if it[1]:find("\tR\tP:Ann\t", 1, true) then gotRec = true end
end
for _, it in ipairs(N.S.queues.bulk) do if it[1]:find("\tB\tguild\t", 1, true) then gotB = true end end
check("the older copy gets the old repair", gotB and gotRec)
Reset(N)
-- and a current copy's old-style checksums are ignored (it also sends "g")
N.S.dumped.guild = {} N.S.lastExchange = nil
N.store["AV:Ann2"] = R("2.10.0", NOW - 500, "Ann2")
N.S:OnMessage(table.concat({ N.S.PROTO, "D", "guild", table.concat(zeros, ",") }, "\t"), "GUILD", "Ann2")
for _, fn in ipairs(pending) do fn() end pending = {}
check("a current copy's old-style checksums are ignored", #N.S.queues.high == 0 and #N.S.queues.bulk == 0)
print("OK")
