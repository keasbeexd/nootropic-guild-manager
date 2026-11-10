-- Test: Social Butterfly (15-minute blocks with someone else talking, 8 a day,
-- spam counts once), last month's champions (winner takes all, ties share),
-- champion wins tallied per person and shared, Most Champion Wins not summed
-- across a person's characters.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = { Widgets = {} }
local guild = { members = {}, sync = { guild = {}, officer = {} } }
local settings = {}
function ns:Fire() end function ns:On() end function ns:RegisterEvent() end function ns:Print() end
function ns.Debounce(_, _, fn) fn() end
function ns.Safe(fn) return fn end
function ns.Split(s, sep) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end return t end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.IsOfficer() return false end
local me = "Marc Priest"
function ns.PlayerFullName() return me end
function ns.NormalizeName(n) return n end
ns.DB = { PERM_BY_TYPE = {} }
function ns.DB:Guild() return guild end
function ns.DB:Now() return NOW end
function ns.DB:Settings() return settings end
function ns.DB:EnsureMember(f) guild.members[f] = guild.members[f] or {} return guild.members[f] end
local function m(full, main, addon) return { full = full, short = full, classFile = "MAGE", main = main, hasAddon = addon } end
ns.Roster = { members = {
  m("Marc Priest", nil, true), m("Marc Druid", "Marc Priest", true),
  m("Probably Shawn", nil, true), m("Grud Sama", nil, true), m("No Addon", nil, false) } }
ns.Roster.byName = {}
for _, e in ipairs(ns.Roster.members) do ns.Roster.byName[e.full] = e end
C_Timer = { After = function() end, NewTicker = function() end }
GetTime = function() return 1 end
date, time = os.date, os.time
IsInGuild = function() return true end
assert(loadfile(ROOT .. "/Core/Sync.lua"))("NGM", ns)
ns.Sync.readyFor = "g"; ns.Sync.QueueOutgoing = function() end
assert(loadfile(ROOT .. "/Services/Sharing.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/HallOfFame.lua"))("NGM", ns)
local HF = ns.HallOfFame

-- Social Butterfly
local t0 = 1800000000 - (1800000000 % 86400) -- midnight UTC
for i = 1, 10 do HF:SocialNote(true, t0 + i) end      -- talking to yourself
assert(HF:SocialTotal() == 0, "no one else spoke")
HF:SocialNote(false, t0 + 20)                           -- someone answers
assert(HF:SocialTotal() == 1)
for i = 1, 10 do HF:SocialNote(true, t0 + 30 + i); HF:SocialNote(false, t0 + 50 + i) end
assert(HF:SocialTotal() == 1, "a chatty block counts once")
for b = 1, 20 do HF:SocialNote(false, t0 + b * 900); HF:SocialNote(true, t0 + b * 900 + 1) end
assert(HF:SocialTotal() == 8, "8 blocks a day at most: " .. HF:SocialTotal())
HF:SocialNote(true, t0 + 86400 + 5); HF:SocialNote(false, t0 + 86400 + 6)
assert(HF:SocialTotal() == 9, "the next day counts again")
assert(HF.Format(HF.BY_KEY.social, 9) == "2.2 h" or HF.Format(HF.BY_KEY.social, 9) == "2.3 h")
assert(HF.Format(HF.BY_KEY.quests, 12345) == "12,345")

-- last month's numbers from guildmates (records written last month)
local month = 202612
HF.Month = function() return month end
local function put(full, this, all)
  guild.sync.guild["HF:" .. full] = { v = HF.Encode(202611, all or this, this, 0, {}), t = 1, a = full }
end
put("Marc Priest", { quests = 40, kills = 100 })
put("Marc Druid", { quests = 20, deaths = 3 })          -- added to Marc's 40
put("Probably Shawn", { quests = 60, kills = 100, deaths = 9 })
put("Grud Sama", { kills = 50, deaths = 9 })
local champs = HF:Champions(month)
local function keys(c) local t = {} for _, p in ipairs(c.winners) do t[#t + 1] = p.key end table.sort(t) return table.concat(t, ",") end
assert(keys(champs.quests) == "Marc Priest,Probably Shawn" and champs.quests.n == 60, "alts added up; a tie shares the title")
assert(keys(champs.kills) == "Marc Priest,Probably Shawn")
assert(keys(champs.deaths) == "Grud Sama,Probably Shawn")
assert(not champs.hugs and not champs.champs, "no title without numbers, none for the wins card itself")

-- Marc's wins: two titles last month, tallied on this computer and shared
HF:UpdateWins()
assert(settings.hofWins["Marc Priest"][202611] == 2)
assert(HF:WinsTotal() == 2)
HF.Available = function() return false end -- no GetStatistic: social and wins still shared
local mine = HF:ReadMine()
assert(mine.champs == 2 and mine.social == 9)
-- both of Marc's characters report 2 wins: counted once for the person
guild.sync.guild["HF:Marc Priest"] = { v = HF.Encode(month, { champs = 2 }, {}, 0, {}), t = 2, a = "Marc Priest" }
guild.sync.guild["HF:Marc Druid"] = { v = HF.Encode(month, { champs = 2 }, {}, 0, {}), t = 2, a = "Marc Druid" }
local all = HF:Boards("all", false, month)
assert(all.boards.champs[1].key == "Marc Priest" and all.boards.champs[1].n == 2, "max, not 4")
assert(all.noAddon == 1)
-- a later month keeps the earlier titles
month = 202701
HF:UpdateWins()
assert(HF:WinsTotal() == 2, "January has no December data here, November's titles stay")
print("OK")
