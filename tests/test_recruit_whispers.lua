-- Test: Recruitment whispers: 255-byte limit with two-part names, first-name fallback, whole-word and UTF-8-safe cuts, Do Not Whisper reply rules.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = { version = "x" }
local printed = {}
function ns:Print(m) printed[#printed + 1] = m end
function ns:On() end
function ns:Fire() end
function ns:RegisterEvent() end
function ns.PlaySound() end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.ShortName(n) return (n:gsub("%-.*", "")) end
function ns.NormalizeName(n) return n end
function ns.SplitName(short) local a, b = short:match("^(%S+)%s+(.+)$") if a then return a, b end return short, "" end
ns.Data = { WHISPER_MAX = 255, MAX_KEYWORDS = 6, ClassName = function() return "Warrior" end }
ns.DB = { Now = function() return NOW end }
GetGuildInfo = function() return "Nootropic" end
StaticPopupDialogs = {}
local f = assert(loadfile(ROOT .. "/Services/Recruit.lua")); f("NGM", ns)
local RC = ns.Recruit
local data = assert(io.open(ROOT .. "/Core/Data.lua")):read("*a")
local DEF = loadstring("return " .. data:match("D%.DEFAULT_WHISPER = (\"[^\n]*\")"))()

-- 1. lengths
print("default longest:", RC:LongestLength(DEF), RC:LengthText(DEF))
local p = { short = "Abcdefghijkl Abcdefghijkl", className = "Warrior", level = 60 }
local out = RC:Format(DEF, p); print("default filled:", #out, out:sub(1, 40) .. "...")
assert(#out <= 255 and out:find("Hey Abcdefghijkl!", 1, true))
-- 2. too long -> first name only
local long = ("x"):rep(235) .. " Hi $name!"
local o2 = RC:Format(long, p); print("long template ->", #o2, o2:sub(-20)); assert(#o2 <= 255 and not o2:find("Abcdefghijkl Abcdefghijkl", 1, true))
-- 3. still too long -> cut at a word, no broken UTF-8
local huge = ("word "):rep(60) .. "end"
local o3 = RC:Format(huge, p); print("huge ->", #o3, "ends with", o3:sub(-5)); assert(#o3 <= 255 and o3:sub(-4) == "word")
local accented = ("é"):rep(200)
local o4 = RC:Format(accented, p); assert(#o4 <= 255 and #o4 % 2 == 0, "split a UTF-8 letter"); print("accented ->", #o4, "bytes, whole letters")
print(RC:LengthText(long))

-- 4. DNW reply tracking
local people, dnw, confirm = {}, {}, {}
RC.Settings = function() return { autoInvite = true, inviteMode = "confirm", dnwEnabled = true, people = people,
  keywords = { "invite", "inv" }, dnwWords = { "dnw", "not interested", "no" } } end
RC.Get = function(_, full) return people[full] end
RC.ShareStatus = function() end
RC.AddDNW = function(_, full) dnw[full] = true end
RC.ConfirmInvite = function(_, full) confirm[full] = true end
local function person(n) people[n] = { full = n, whispered = NOW - 60, lastWhisper = "auto msg" } return people[n] end
person("A"); RC:OnWhisper("no thanks", "A")
person("B"); RC:OnWhisperSent("want to run deadmines?", "B"); RC:OnWhisper("no", "B")
person("C"); RC:OnWhisperSent("auto msg", "C"); RC:OnWhisper("no", "C")
person("D"); RC:OnWhisper("no guild yet, inv pls", "D")
person("E").whispered = NOW - 2 * 86400; RC:OnWhisper("no", "E")
person("F"); RC:OnWhisper("I know a guy", "F")
print("DNW:", dnw.A, dnw.B, dnw.C, dnw.D, dnw.E, dnw.F, " confirm D:", confirm.D)
assert(dnw.A and not dnw.B and dnw.C and not dnw.D and not dnw.E and not dnw.F and confirm.D)
print("OK")
