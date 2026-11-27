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

-- a member brings in NGM Peon's code: they may not pass its records on, so they're kept for them alone
ns.PlayerFullName = function() return "Ann Member-R" end
check("a member keeps NGM Peon's link for themselves", S:KeepPeonOwn("LK:Ann Member-R", { v = "1", t = NOW, a = "NGM Peon" }), true)
check("...not in guild sync", guild.sync.guild["LK:Ann Member-R"], nil)
check("...and it counts: she may sign up", S:Linked("Ann Member-R"), true)
check("only NGM Peon's own records", S:KeepPeonOwn("LK:Bob Member-R", { v = "1", t = NOW, a = "Bob Member-R" }), false)
check("only the 3.1 kinds", S:KeepPeonOwn("M:Bob Member-R", { v = "", t = NOW, a = "NGM Peon" }), false)
check("an older copy doesn't replace a newer one", S:KeepPeonOwn("LK:Ann Member-R", { v = "", t = NOW - 5, a = "NGM Peon" }), false)
ns.PlayerFullName = function() return "Me Self-R" end

-- kept until 7 days after the event starts
local r = guild.sync.guild["EG:b1"]
check("an event expires 7 days after it starts", S:ExpiresAt("EG:b1", r), NOW + 86400 + 7 * 86400)
-- the Create form's service (Services/Events.lua): as an officer, then as a member
date, time = os.date, os.time
assert(loadfile(ROOT .. "/Services/Events.lua"))("NGM", ns)
local E = ns.Events
ns.PlayerFullName = function() return "Gm Boss-R" end
check("the Guild Master may create every kind", table.concat(E:KindsICanCreate(), ","), "dungeon,raid,event")
local f = { kind = "raid", starts = NOW + 3600, minutes = 120, title = "Onyxia; then MC", description = "Line one\nline two |cffff0000x" }
local id = assert(E:Create(f))
local made = S.ParseGameEvent(guild.sync.guild["EG:" .. id].v)
check("created: title without ;", made.title, "Onyxia, then MC")
check("one line, no escape codes", made.description, "Line one line two /cffff0000x")
check("it's listed for everyone, as made in game", (function() for _, e in ipairs(E:List()) do if e.id == id then return e.source .. ":" .. e.creator end end end)(), "game:Gm Boss-R")
check("a past time is refused", select(2, E:Create({ kind = "raid", starts = NOW - 60, minutes = 120, title = "Late" })), "Pick a time that's still to come.")
check("an odd length is refused", select(2, E:Create({ kind = "raid", starts = NOW + 60, minutes = 45, title = "X" })), "Pick a length.")
check("edited (the kind stays)", (E:Edit(id, { kind = "dungeon", starts = NOW + 7200, minutes = 60, title = "Onyxia" })), true)
check("...kind and creator kept", S.ParseGameEvent(guild.sync.guild["EG:" .. id].v).kind .. ":" .. S.ParseGameEvent(guild.sync.guild["EG:" .. id].v).creator, "raid:Gm Boss-R")
ns.PlayerFullName = function() return "Ann Member-R" end
check("a member may not edit it", select(2, E:Edit(id, { starts = NOW + 7200, minutes = 60, title = "Mine" })), "Only its creator or an officer can change it.")
ns.PlayerFullName = function() return "Gm Boss-R" end
check("cancelled", (E:Cancel(id)), true)
check("and listed as Cancelled (until its post would go)", (function() for _, e in ipairs(E:List()) do if e.id == id then return tostring(e.cancelled) end end return "gone" end)(), "true")

-- sign-ups, as NGM Peon's post: a dungeon (1 / 1 / 3), first come first in, the rest on the bench
ns.DB.GetAltsOf = function(_, main) return main == "Bob Member-R" and { "Bob Alt-R" } or {} end
ns.Roster.byName["Bob Alt-R"].className, ns.Roster.byName["Bob Alt-R"].level = "Priest", 60
local dung = assert(E:Create({ kind = "dungeon", starts = NOW + 3600, minutes = 60, title = "Strat" }))
local dev = { source = "game", id = dung, kind = "dungeon", starts = NOW + 3600 }
ns.PlayerFullName = function() return "Me Self-R" end -- guildmates' sign-ups arrive from others
rec("Rae Raider-R", "ES:g" .. dung .. ":Rae Raider-R", "Rae Raider-R", "tank;")
rec("Mira Officer-R", "ES:g" .. dung .. ":Gm Boss-R", "Gm Boss-R", "tank;") -- linked? no: refused with NGM Peon
check("with NGM Peon, an unlinked member's sign-up is refused", guild.sync.guild["ES:g" .. dung .. ":Gm Boss-R"], nil)
rec("Mira Officer-R", "LK:Gm Boss-R", "NGM Peon", "1")
rec("Mira Officer-R", "LK:Bob Alt-R", "NGM Peon", "1")
rec("Gm Boss-R", "ES:g" .. dung .. ":Gm Boss-R", "Gm Boss-R", "tank;")
local fields = E:Fields(dev)
check("first tank in, the second on the bench", fields[1].name .. " " .. fields[1].value, "Tanks (1/1) Rae Raider")
check("limits shown, as on the post", fields[2].name .. "|" .. fields[3].name, "Healers (0/1)|DPS (0/3)")
check("bench", fields[4].name .. " " .. fields[4].value, "Bench (1) Gm Boss")
-- you sign up as your main; with NGM Peon the character brought must be linked
ns.PlayerFullName = function() return "Bob Alt-R" end
check("not linked: why, not buttons", select(2, E:CanSignUp(dev)), "Link your characters to sign up: type /ngm link in Discord.")
check("bringing a linked alt works", (E:SignUp(dev, "healer", "Bob Alt-R")), true)
check("kept under the main, with the alt picked", guild.sync.guild["ES:g" .. dung .. ":Bob Member-R"].v, "healer;Bob Alt-R")
check("Mine", table.concat({ E:Mine(dev) }, ","), "healer,Bob Alt-R")
check("the card lists the alt, with class and level", E:Fields(dev)[2].value, "Bob Alt · Priest 60")
check("changing role keeps the alt", (E:SignUp(dev, "absent")) and guild.sync.guild["ES:g" .. dung .. ":Bob Member-R"].v, "absent;Bob Alt-R")
check("Can't come listed by name", E:Fields(dev)[#E:Fields(dev)].name, "Can't come (1)")
check("events: Going instead of roles", table.concat(E:Parts("event"), ","), "going,tentative,absent")
-- NGM Peon posts the event made in game: EL links them, so it's listed once, as NGM Peon's
rec("Mira Officer-R", "EV:16", "NGM Peon", "dungeon;" .. b36(NOW + 3600) .. ";1o;0;dungeons;Nootropic;Strat;")
check("NGM Peon's link is only NGM Peon's to write", rec("Bob Member-R", "EL:16", "Bob Member-R", dung .. ";1,1,3"), nil)
rec("Mira Officer-R", "EL:16", "NGM Peon", dung .. ";2,1,3")
local strat = {}
for _, e in ipairs(E:List()) do if e.title == "Strat" then strat[#strat + 1] = e end end
check("listed once, as NGM Peon's", #strat .. ":" .. strat[1].source .. ":" .. tostring(strat[1].game), "1:peon:" .. dung)
check("still edited in game, through its EG", strat[1].made and (strat[1].made.id .. ":" .. strat[1].made.source .. ":" .. strat[1].made.title), dung .. ":game:Strat")
check("a member who did not make it may not", E:MayEdit(strat[1].made), false)
check("not changed since NGM Peon posted it", tostring(strat[1].changed), "nil")
ns.PlayerFullName = function() return "Gm Boss-R" end
assert(E:Edit(dung, { starts = NOW + 3600, minutes = 60, title = "Strat Live" }))
local live
for _, e in ipairs(E:List()) do if e.game == dung then live = e end end
check("changed in game: shown as changed until NGM Peon has it", live.title .. ":" .. tostring(live.changed), "Strat Live:true")
assert(E:Edit(dung, { starts = NOW + 3600, minutes = 60, title = "Strat" }))
ns.PlayerFullName = function() return "Bob Alt-R" end
check("with the post's limits", E:Fields(strat[1])[1].name, "Tanks (2/2)")
check("sign-ups from before the link still count", E:Fields(strat[1])[1].value, "Rae Raider, Gm Boss")
-- a Discord sign-up (NGM Peon's copy, newer) wins over the in-game one for the same member
rec("Mira Officer-R", "ES:p16:Rae Raider-R", "NGM Peon", "healer;")
check("newest per member wins, whichever side", E:Fields(strat[1])[2].value, "Rae Raider")
-- cancelled in game: marked, closed, and gone with its Discord post ("Clear old posts")
ns.PlayerFullName = function() return "Gm Boss-R" end
assert(E:Cancel(dung))
local function find() for _, e in ipairs(E:List()) do if e.game == dung or (e.source == "game" and e.id == dung) then return e end end end
local gone = find()
check("cancelled: still listed, marked", gone and tostring(gone.cancelled), "true")
check("cancelled: not editable", E:MayEdit(gone.made or gone), false)
check("cancelled: sign-ups closed", select(2, E:CanSignUp(gone)), "Cancelled: sign-ups are closed.")
local EventRules = S.EventRules
S.EventRules = function() return { lowest = {}, officers = true, keep = 60 } end
local PeonGuild = S.PeonGuild
S.PeonGuild = function() return true end
check("listed while its post stays", E.Shown(gone, NOW + 3599, NOW), true)
check("gone when its post goes", E.Shown(gone, NOW + 3600, NOW), false)
check("a past one: listed until Clear old posts after it ends", E.Shown({ starts = NOW, minutes = 60 }, NOW + 3600 + 3599), true)
check("then gone", E.Shown({ starts = NOW, minutes = 60 }, NOW + 7200), false)
S.EventRules = function() return { lowest = {}, officers = true } end
check("Never: until it ends", E.Shown({ starts = NOW, minutes = 60 }, NOW + 3599) and not E.Shown({ starts = NOW, minutes = 60 }, NOW + 3600), true)
S.EventRules, S.PeonGuild = EventRules, PeonGuild
check("closed once started", select(2, E:CanSignUp({ source = "game", id = dung, kind = "dungeon", starts = NOW - 1 })), "Sign-ups are closed: it has started.")

-- NGM Peon's records only through an officer's copy: a character called "Ngm Peon" can't speak for it
ns.PlayerFullName = function() return "Me Self-R" end
ns.Roster.byName["Ngm Peon"] = { rankIndex = 4 }
check("a guildmate named Ngm Peon can't write NGM Peon's links", rec("Ngm Peon", "LK:Ann Member-R", "NGM Peon", "1"), nil)
check("nor pass them on as a member", rec("Bob Member-R", "EL:1z", "NGM Peon", ";1,1,3;;"), nil)
check("an officer can", rec("Mira Officer-R", "EL:1z", "NGM Peon", ";1,1,3;;"), ";1,1,3;;")
check("a sign-up's character has no escape codes", S.ValidValue("ES", "tank;|Hurl:x|h[Click]|h"), false)
check("a plain name is fine", S.ValidValue("ES", "tank;Bob Alt-R"), true)

-- NGM Peon's post link (EL): limits, reminder, and a cancelled post with its event
local L = E.ParseLink("1a", "g9;1,1,3;u;")
check("link: limits and reminder", L.game .. ":" .. L.limits.dps .. ":" .. L.remind .. ":" .. tostring(L.cancelledAt), "g9:3:30:nil")
check("link: the 3.1.0 tests' form still reads", E.ParseLink("1a", ";2,,").limits.tank, 2)
local snap = "raid;" .. b36(NOW + 7200) .. ";3c;2;raids;Nootropic;Ony Night;Bring cloaks"
local cancelledLink = ";,,;f;" .. b36(NOW - 60) .. ";" .. snap
check("link: valid with a cancelled post's event", S.ValidValue("EL", cancelledLink), true)
check("link: refused if the event is broken", S.ValidValue("EL", ";,,;f;" .. b36(NOW - 60) .. ";raid;zz"), false)
-- cancelled on the dashboard: NGM Peon no longer lists it (no EV), the link carries it
ns.PlayerFullName = function() return "Me Self-R" end
rec("Mira Officer-R", "EL:1b", "NGM Peon", cancelledLink)
local ony
for _, e in ipairs(E:List()) do if e.title == "Ony Night" then ony = e end end
check("cancelled on the dashboard: listed, Cancelled", ony and tostring(ony.cancelled) .. ":" .. ony.source .. ":" .. ony.channel, "true:peon:raids")
check("sign-ups closed", select(2, E:CanSignUp(ony)), "Cancelled: sign-ups are closed.")

-- your sign-up against NGM Peon's copy (holds across /reload)
S.PeonGuild = function() return true end
local live = { source = "peon", id = 77, kind = "event", starts = NOW + 3600, minutes = 60 }
ns.PlayerFullName = function() return "Ann Member-R" end
guild.sync.guild["ES:p" .. b36(77) .. ":Ann Member-R"] = { v = "going;", t = NOW - 10, a = "Ann Member-R" }
check("signed up in game, NGM Peon hasn't it: unsent", E:MineUnsent(live), true)
guild.sync.guild["ES:p" .. b36(77) .. ":Ann Member-R"] = { v = "going;", t = NOW - 9, a = "NGM Peon" }
check("NGM Peon sent it back (a second newer): sent", E:MineUnsent(live), false)
guild.sync.guild["ES:p" .. b36(77) .. ":Ann Member-R"] = { v = "", t = NOW - 5, a = "Ann Member-R" }
check("withdrawn after: unsent", E:MineUnsent(live), true)
-- NGM Peon's copy reaches the game through guild sync whatever the member's name
-- (it's newer, so a tie on the author never decides it)
ns.PlayerFullName = function() return "Me Self-R" end
T = NOW - 5 -- NGM Peon's copy: a second after hers
check("NGM Peon's copy replaces hers", rec("Mira Officer-R", "ES:p" .. b36(77) .. ":Ann Member-R", "NGM Peon", ""), "")
check("and it's what the guild holds", guild.sync.guild["ES:p" .. b36(77) .. ":Ann Member-R"].a, "NGM Peon")

-- reminders, as NGM Peon's: once, to those signed up (not Can't come)
local printed = {}
ns.Print = function(_, m) printed[#printed + 1] = m end
ns.GOLD = ""
ns.GameCalendar = { Short = function(s) return math.floor(s / 60) .. " min" end }
local listed = { { source = "peon", id = 78, kind = "event", starts = NOW + 600, minutes = 60, remind = 15, title = "Fishing" } }
local List, Mine = E.List, E.Mine
E.List = function() return listed end
E.Mine = function() return "going" end
E:Remind() E:Remind()
check("reminded once", #printed .. ":" .. (printed[1] or ""), "1:Reminder: Fishing|r starts in 10 min.")
listed[1].starts = NOW + 1200
E:Remind()
check("not before its time", #printed, 1)
E.Mine = function() return "absent" end
listed[1].starts = NOW + 300
E:Remind()
check("not to Can't come", #printed, 1)
E.List, E.Mine, S.PeonGuild = List, Mine, PeonGuild
print("OK")
