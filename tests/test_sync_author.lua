-- Test: sync by author (2.11). A small simulated guild: copies send checks,
-- ask each other for exactly what they lack, officers are recognised by
-- rank, a member whose guild channel doesn't deliver goes through an
-- officer, and nothing from outside the guild channels is read.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local clock = 100
local pending = {}
C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
GetTime = function() return clock end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
IsInGuild = function() return true end
local packed = {}
C_EncodingUtil = {
  CompressString = function(s) packed[#packed + 1] = s return "#" .. #packed end,
  DecompressString = function(s) local v = packed[tonumber(s:match("^#(%d+)$") or -1)] if not v then error("bad") end return v end,
  EncodeBase64 = function(s) return s end,
  DecodeBase64 = function(s) return s end,
}

-- the guild: name -> { rankIndex, rank }
local RANKS = {
  ["Gm Boss"] = { 0, "Guild Master" }, ["Ola Officer"] = { 1, "Officer" },
  ["Ann Member"] = { 3, "Member" }, ["Bob Member"] = { 3, "Member" },
  ["Myk Broken"] = { 3, "Member" }, ["Cat Member"] = { 3, "Member" },
}
local online = {}
local function Members()
  local list = {}
  for name, r in pairs(RANKS) do
    list[#list + 1] = { full = name, rankIndex = r[1], rank = r[2], online = online[name] or false, hasAddon = true, version = "2.11.0" }
  end
  return list
end

local clients, outbox = {}, {}
local current
local function Client(me, opts)
  opts = opts or {}
  local ns = {}
  local guild = { members = {}, sync = { guild = {}, officer = {} } }
  function ns:Fire() end function ns:On() end function ns:RegisterEvent() end
  function ns.Debounce(_, _, fn) fn() end
  function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
  function ns.IsOfficer() return RANKS[me][1] <= 1 end
  function ns.PlayerFullName() return me end
  function ns.NormalizeName(n) return n end
  function ns.ShortName(n) return n end
  function ns.ChatName(n) return n end
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
  function ns.DB:IsGuildMaster() return RANKS[me][1] == 0 end
  function ns.DB:HasPerm() return true end
  ns.Roster = { byName = {}, members = {} }
  ns.Recruit = { MayRecruit = function() return opts.recruits or false end }
  assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
  local S = ns.Sync
  S.BYTES_PER_SEC, S.BURST = 1e9, 1e9 -- the test delivers at once
  local c = { S = S, ns = ns, store = guild.sync.guild, officer = guild.sync.officer, name = me, broken = opts.broken }
  local realPump = S.Pump
  S.Pump = function(self) local prev = current current = c realPump(self) current = prev end
  clients[#clients + 1] = c
  online[me] = true
  return c
end

local function RefreshRosters()
  for _, c in ipairs(clients) do
    local list = Members()
    c.ns.Roster.members = list
    c.ns.Roster.byName = {}
    for _, e in ipairs(list) do c.ns.Roster.byName[e.full] = e end
  end
end

-- the game: each client's sends go to the outbox, then get delivered
C_ChatInfo = { SendAddonMessage = function(_, msg, channel, target)
  outbox[#outbox + 1] = { from = current, msg = msg, channel = channel, target = target }
  return 0
end }
local counts
local function Deliver(o)
  local kind = o.msg:match("^[^\t]+\t(%u)")
  counts[kind] = (counts[kind] or 0) + 1
  counts[o.channel] = (counts[o.channel] or 0) + 1
  if o.channel == "GUILD" or o.channel == "OFFICER" then
    if o.from.broken then return end -- accepted, delivered to nobody (not even back)
    for _, c in ipairs(clients) do
      if online[c.name] and (o.channel == "GUILD" or c.ns.IsOfficer()) then c.S:OnMessage(o.msg, o.channel, o.from.name) end
    end
  else
    for _, c in ipairs(clients) do
      if online[c.name] and (o.channel ~= "WHISPER" or c.name == o.target) and c ~= o.from then c.S:OnMessage(o.msg, o.channel, o.from.name) end
    end
  end
end
local function Run(rounds)
  counts = {}
  for _ = 1, rounds or 40 do
    clock = clock + 3
    for _, c in ipairs(clients) do
      if online[c.name] then current = c c.S:Pump() end
    end
    local box = outbox
    outbox = {}
    for _, o in ipairs(box) do Deliver(o) end
    local fns = pending
    pending = {}
    for _, fn in ipairs(fns) do fn() end
    if #box == 0 and #fns == 0 then break end
  end
  return counts
end
local function Records(c, author)
  local n = 0
  for _, rec in pairs(c.store) do if rec.a == author then n = n + 1 end end
  return n
end
local function check(name, ok) print(("%-64s %s"):format(name, ok and "ok" or "FAIL")) assert(ok) end
local function R(v, t, a) return { v = v, t = t, a = a } end
local function Sum(c, lane) local t = {} for a, s in pairs(c.S:AuthorSums(lane)) do t[#t + 1] = a .. s.h end table.sort(t) return table.concat(t, ",") end

------------------------------------------------------------------------
-- 1. two members: exactly what's missing, nothing else
------------------------------------------------------------------------
local A = Client("Ann Member")
local B = Client("Bob Member")
RefreshRosters()
for i = 1, 30 do
  A.store["P:Ann" .. i] = nil
  A.store["MS:Ann Member" .. i] = nil
end
A.store["P:Ann Member"] = R("a1", NOW - 100, "Ann Member")
A.store["SC:Ann Member"] = R("ff", NOW - 90, "Ann Member")
B.store["P:Ann Member"] = R("a0", NOW - 500, "Ann Member")  -- older
B.store["P:Bob Member"] = R("b1", NOW - 50, "Bob Member")
for i = 1, 40 do B.store["RP:Bob Member:" .. i] = R("x" .. i, NOW - 1000, "Bob Member") A.store["RP:Bob Member:" .. i] = R("x" .. i, NOW - 1000, "Bob Member") end
A.S:Exchange(true)
local c = Run()
check("member checks are tiny (no group checksums, lists or markers)", not c.D and not c.L and not c.B)
check("Bob got Ann's two newer records", B.store["P:Ann Member"].v == "a1" and B.store["SC:Ann Member"] ~= nil)
check("Ann got Bob's missing one", A.store["P:Bob Member"] and A.store["P:Bob Member"].v == "b1")
check("only the 3 missing records were sent (" .. (c.R or 0) .. ")", (c.R or 0) == 3)
check("both copies agree", Sum(A, "guild") == Sum(B, "guild"))

-- a member doesn't hand out someone else's records, and isn't asked to
A.store["P:Cat Member"] = R("cat", NOW - 10, "Cat Member")
A.S.lastExchange, B.S.lastExchange = nil, nil
A.S:Exchange(true) B.S:Exchange(true)
c = Run()
check("Cat's record doesn't spread through a regular member", B.store["P:Cat Member"] == nil)

------------------------------------------------------------------------
-- 2. officers by rank: the Guild Master's copy names the officer rank
------------------------------------------------------------------------
local GM = Client("Gm Boss")
local O = Client("Ola Officer")
RefreshRosters()
O.S:Exchange(true)   -- Ola's check goes on the officer channel too: the GM's copy notes the rank
Run()
check("the Guild Master's copy recorded the officer rank", (GM.S:Value("GS:officers") or ""):find("Officer", 1, true) ~= nil)
check("members know Ola is an officer without seeing the officer channel", A.S:KnownOfficer("Ola Officer") and B.S:KnownOfficer("Ola Officer"))
check("and that Bob isn't", not A.S:KnownOfficer("Bob Member"))

-- an officer passes on everyone's records, and members accept them
O.store["P:Cat Member"] = R("cat2", NOW - 5, "Cat Member")
O.store["M:Cat Member"] = R("", NOW - 5, "Ola Officer")
for _, x in ipairs(clients) do x.S.lastExchange = nil x.S.asked = {} end
O.S:Exchange(true)
Run()
check("members got Cat's record from the officer", B.store["P:Cat Member"] and B.store["P:Cat Member"].v == "cat2")
check("and the officer's own", A.store["M:Cat Member"] ~= nil)

-- a forged officer-rank record from a member is refused
B.S:OnMessage(table.concat({ B.S.PROTO, "R", "GS:officers", tostring(NOW + 1), "Ann Member", "", "Officer;Member" }, "\t"), "GUILD", "Ann Member")
check("only the Guild Master may name officer ranks", not (B.S:Value("GS:officers") or ""):find("Member", 1, true))

------------------------------------------------------------------------
-- 3. a guild channel that delivers nothing: through an officer
------------------------------------------------------------------------
local M = Client("Myk Broken", { broken = true })
RefreshRosters()
for _, x in ipairs(clients) do
  x.store["AV:Ola Officer"] = R("2.11.0", NOW - 900, "Ola Officer")
  x.store["GS:officers"] = GM.store["GS:officers"]
end
M.store["P:Myk Broken"] = R("myk", NOW - 20, "Myk Broken")
M.store["HF:Myk Broken"] = R("hof", NOW - 20, "Myk Broken")
M.store["P:Ann Member"] = R("forged", NOW, "Ann Member") -- not hers: must not be passed on
for i = 1, 3 do M.S:Send(M.S.PROTO .. "\tS\tguild\t", "GUILD", nil, "high") end
Run()
clock = clock + 30
check("she notices her guild messages don't come back", M.S:GuildBroken())
M.S.lastExchange = nil
M.S:Exchange(true)
c = Run()
check("her messages went to an officer by whisper", (c.WHISPER or 0) > 0)
check("everyone got her records through the officer", A.store["P:Myk Broken"] and B.store["HF:Myk Broken"] and GM.store["P:Myk Broken"])
check("but nothing she wrote for someone else", A.store["P:Ann Member"].v == "a1")
check("she has everyone's data (she receives fine)", M.store["P:Bob Member"] ~= nil)

-- whispering the officer someone else's record: not passed on, not kept
O.S:OnMessage(table.concat({ O.S.PROTO, "R", "P:Bob Member", tostring(NOW + 5), "Bob Member", "", "forged" }, "\t"), "WHISPER", "Myk Broken")
c = Run()
check("the officer won't pass on a record she didn't write", O.store["P:Bob Member"].v == "b1" and A.store["P:Bob Member"].v == "b1")

-- a flood of whispers is cut off
O.S.whispers = {}
for i = 1, 200 do O.S:OnMessage(table.concat({ O.S.PROTO, "R", "AV:Myk Broken", tostring(NOW + i), "Myk Broken", "", "v" .. i }, "\t"), "WHISPER", "Myk Broken") end
check("whispers past 120 a minute are ignored", O.store["AV:Myk Broken"].v == "v120")
Run()

-- whispers to a regular member, and party messages, are ignored
B.S:OnMessage(table.concat({ B.S.PROTO, "R", "P:Myk Broken", tostring(NOW), "Myk Broken", "", "whisp" }, "\t"), "WHISPER", "Myk Broken")
check("a whisper to a regular member isn't read", B.store["P:Myk Broken"].v == "myk")
B.S:OnMessage(table.concat({ B.S.PROTO, "R", "P:Myk Broken", tostring(NOW), "Myk Broken", "", "party" }, "\t"), "PARTY", "Myk Broken")
check("party messages aren't read", B.store["P:Myk Broken"].v == "myk")
O.S:OnMessage(table.concat({ O.S.PROTO, "R", "P:Stranger", tostring(NOW), "Stranger", "", "x" }, "\t"), "WHISPER", "Stranger")
check("an officer ignores whispers from outside the guild", O.store["P:Stranger"] == nil)

------------------------------------------------------------------------
-- 4. a lost older record: asking for everything fixes it
------------------------------------------------------------------------
for _, x in ipairs(clients) do x.S.lastExchange = nil x.S.asked = {} end
B.store["SC:Ann Member"] = nil  -- lost; Bob's newest from Ann is unchanged
B.S.storeVersion = B.S.storeVersion + 1
A.S:Exchange(true)
Run()
check("the lost older record came back", B.store["SC:Ann Member"] ~= nil)

------------------------------------------------------------------------
-- 5. recruitment statuses: only between recruiters
------------------------------------------------------------------------
online = {}
clients = {}
local R1 = Client("Ann Member", { recruits = true })
local R2 = Client("Bob Member", { recruits = true })
local NR = Client("Cat Member")
RefreshRosters()
for i = 1, 50 do R1.store["RS:Stranger" .. i] = R("1;0;0;", NOW - 60, "Ann Member") end
for i = 1, 20 do R1.store["RS:Other" .. i] = R("1;0;0;", NOW - 60, "Someone Else") end
R1.S:Exchange(true)
Run()
local n2, n3 = 0, 0
for k in pairs(R2.store) do if k:find("^RS:") then n2 = n2 + 1 end end
for k in pairs(NR.store) do if k:find("^RS:") then n3 = n3 + 1 end end
check("the other recruiter got all 70, others' too (" .. n2 .. ")", n2 == 70)
check("a member who can't recruit kept none (" .. n3 .. ")", n3 == 0)

------------------------------------------------------------------------
-- 6. compression, and older copies' messages
------------------------------------------------------------------------
local big = string.rep("abcdefgh;", 40)
R1.store["P:Ann Member"] = R(big, NOW - 1, "Ann Member")
R1.S:Broadcast("P:Ann Member", R1.store["P:Ann Member"])
c = Run()
check("a big record goes compressed and arrives whole", (c.Z or 0) == 1 and R2.store["P:Ann Member"].v == big)
R2.S:OnMessage(R2.S.PROTO .. "\tD\tguild\t0,0,0", "GUILD", "Ann Member")
R2.S:OnMessage(R2.S.PROTO .. "\tL\tq\tguild\tBob Member\t1:abc.1.2", "GUILD", "Ann Member")
c = Run()
check("an older copy's checks are ignored, not answered", next(c) == nil)
print("OK")
