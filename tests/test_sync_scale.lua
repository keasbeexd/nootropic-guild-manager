-- Test: sync at scale. A simulated 300-member guild (tests/sim.lua) with the
-- real send budget (600 bytes a second per player), 40 online with the
-- addon (2 of them officers). Measures time and bytes for: a login with
-- nothing to catch up on, a member back after a few days, and a brand-new
-- install. Compression is a stand-in at 35% of the original size (text
-- like ours usually does at least that well with Deflate).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local Sim = dofile(ROOT .. "/tests/sim.lua")(ROOT)
local function check(name, ok) print(("%-70s %s"):format(name, ok and "ok" or "FAIL")) assert(ok) end

local N, ONLINE = 300, 40
local list = { { "Gm Boss", 0, "Guild Master" } }
for i = 1, 5 do list[#list + 1] = { "Officer " .. i, 1, "Officer" } end
for i = #list + 1, N do list[#list + 1] = { "Member " .. i, 3, "Member" } end
local g = Sim.Guild(list)
local T0 = g:Now() - 30 * 86400

-- everyone's records, as the officers' copies hold them
local archive = {}
local function put(key, v, t, a) archive[key] = { v = v, t = t, a = a } end
local seed = 7
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return seed % n end
for i, m in ipairs(list) do
  local n = m[1]
  local t = T0 + rnd(86400)
  put("AV:" .. n, "2.12.0", t, n)
  put("P:" .. n, "Holy;31/0/20;Alchemy:" .. rnd(300) .. ":300:136240,Herbalism:" .. rnd(300) .. ":300:136246", t, n)
  put("SC:" .. n, ("%042x"):format(rnd(2 ^ 30)):sub(1, 42), t, n)
  local hf = {}
  for s = 1, 24 do hf[#hf + 1] = tostring(rnd(5000)) end
  put("HF:" .. n, table.concat(hf, ","), t, n)
  put("RR:" .. n, "ony,brooch", t, n)
  if i % 3 == 0 then
    local ids = {}
    for r = 1, 90 do ids[#ids + 1] = ("%x"):format(rnd(46000) + 2000) end
    put("RP:" .. n .. ":171", "Alchemy;" .. table.concat(ids, ","), t, n)
  end
  if i % 4 == 0 then put("M:" .. n, "", t, "Officer 1") end
end
put("GS:officers", "Officer", T0, "Gm Boss")
local function copy(dst, filter)
  for k, r in pairs(archive) do
    if not filter or filter(k, r) then dst[k] = { v = r.v, t = r.t, a = r.a } end
  end
end

-- online: the Guild Master is away; 2 officers and 38 members are on
local online = { "Officer 1", "Officer 2" }
for i = 7, 7 + ONLINE - 3 do online[#online + 1] = "Member " .. i end
for _, n in ipairs(online) do
  local c = g:Client(n)
  copy(c.store)
  g:Login(n)
end
g:Settle()
local function essentials(k) return not k:find("^RP:") end
local function count(c, filter)
  local n = 0
  for k in pairs(c.store) do if not filter or filter(k) then n = n + 1 end end
  return n
end
local total, totalEssential = 0, 0
for k in pairs(archive) do total = total + 1 if essentials(k) then totalEssential = totalEssential + 1 end end

-- time until a copy holds `want` records matching filter (or `max` seconds)
local function until_(c, filter, want, max)
  local start = g:Clock()
  while g:Clock() - start < max do
    if count(c, filter) >= want then return g:Clock() - start end
    g:Run(1)
  end
  return math.huge
end

------------------------------------------------------------------------
-- A. logging in, nothing to catch up on
------------------------------------------------------------------------
local A = g:Client("Member 200")
copy(A.store)
g:ResetStats()
g:Login("Member 200")
local t = g:Settle()
print(("  A. in sync: %d messages, %d bytes, settled in %ds"):format(g.stats.messages, g.stats.bytes, t))
check("A login with nothing to catch up on costs a few tiny messages", g.stats.messages <= 4 and g.stats.bytes < 300)
check("and says it's in sync", A.S:Health() == "ok")

------------------------------------------------------------------------
-- B. back after a few days: 60 guildmates changed something
------------------------------------------------------------------------
local B = g:Client("Member 201")
copy(B.store)
g:Login("Member 201")
g:Settle()
g:Logout("Member 201")
local changed = 0
for i = 7, 300, 5 do
  local n = list[i][1]
  local r = { v = "Shadow;0/31/20;Tailoring:" .. i .. ":300:136249", t = g:Now() - 3600, a = n }
  archive["P:" .. n] = r
  for _, c in ipairs(g.clients) do if c.entry.online then c.store["P:" .. n] = { v = r.v, t = r.t, a = r.a } end end
  changed = changed + 1
end
g:ResetStats()
g:Login("Member 201")
local start = g:Clock()
local caught = math.huge
while g:Clock() - start < 600 do
  local ok = true
  for i = 7, 300, 5 do
    local n = list[i][1]
    if B.store["P:" .. n].t ~= archive["P:" .. n].t then ok = false break end
  end
  if ok then caught = g:Clock() - start break end
  g:Run(1)
end
g:Settle()
print(("  B. back after a few days (%d changes): caught up in %ds, %d messages, %d bytes"):format(changed, caught, g.stats.messages, g.stats.bytes))
check("B caught up within a minute", caught <= 60)
check("B is in sync afterwards", B.S:Health() == "ok")

------------------------------------------------------------------------
-- C. a brand-new install
------------------------------------------------------------------------
local C = g:Client("Member 202")
g:ResetStats()
g:Login("Member 202")
local tEss = until_(C, essentials, totalEssential - 2, 1800)
local tAll = until_(C, nil, total - 2, 1800)
g:Settle()
local busiest, who = 0, nil
local o1, o2 = g.stats.bySender["Officer 1"] or 0, g.stats.bySender["Officer 2"] or 0
for n, b in pairs(g.stats.bySender) do if b > busiest then busiest, who = b, n end end
print(("  C. new install: essentials (%d records) in %ds, everything (%d) by then; %d messages, %d KB; busiest sender %s sent %d KB")
  :format(totalEssential, tEss, total, g.stats.messages, math.floor(g.stats.bytes / 1024), tostring(who), math.floor(busiest / 1024)))
check(("the work is shared between the officers (%d KB / %d KB)"):format(o1 / 1024, o2 / 1024), math.min(o1, o2) > 0.25 * (o1 + o2))
check("C has the essentials within 5 minutes", tEss <= 300)
check("C has everything within 15 minutes", tAll <= 900)
check("C is in sync afterwards", C.S:Health() == "ok")

------------------------------------------------------------------------
-- D. and then nothing: an hour of quiet
------------------------------------------------------------------------
g:ResetStats()
g:Run(3600)
check("an hour with no changes: no messages from 43 copies", g.stats.messages == 0)
print("OK")
