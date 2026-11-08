-- Test: Default and class messages: first name, <guild>, no command word, all within 255 bytes; migrations of older defaults.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
function ns:Print() end function ns:On() end function ns:Fire() end function ns:RegisterEvent() end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.ShortName(n) return (n:gsub("%-.*", "")) end
function ns.SplitName(short) local a, b = short:match("^(%S+)%s+(.+)$") if a then return a, b end return short, "" end
local D = { CLASSES = {}, ClassName = function(_, c) return c end }
ns.Data = D
assert(loadfile(ROOT .. "/Core/Data.lua"))("NGM", ns)   -- real defaults
D = ns.Data
GetGuildInfo = function() return "Nootropic" end
StaticPopupDialogs = {}
ns.DB = { Now = function() return 0 end, Guild = function() return nil end }
assert(loadfile(ROOT .. "/Services/Recruit.lua"))("NGM", ns)
ns.Recruit.MaxLevel = function() return 60 end
assert(loadfile(ROOT .. "/Services/Messages.lua"))("NGM", ns)
local RC, MS = ns.Recruit, ns.Messages
local p = { short = "Audrey Pichhale", className = "Mage" }
local out = RC:Format(D.DEFAULT_WHISPER, p)
print(out)
assert(out:find("^Hey Audrey!") and out:find("for <Nootropic>,") and not out:lower():find("reply"))
for cls, t in pairs(MS.CLASS_DEFAULTS) do
  local o = RC:Format(t, p)
  assert(o:find("<Nootropic>") and not o:lower():find("just reply") and o:find("^H[ei]y? ?A?") , cls)
  assert(RC:LongestLength(t) <= 255, cls)
end
-- class migration: both old generations swap, edits stay
local r = { rules = {
  { preset = "WARRIOR", text = MS.OLD_CLASS_DEFAULTS.WARRIOR[1] },
  { preset = "ROGUE", text = MS.OLD_CLASS_DEFAULTS.ROGUE[2] },
  { preset = "MAGE", text = "mine" } }, classDefaults = true, classDefaultsAllFactions = true }
MS:Migrate(r)
assert(r.rules[1].text == MS.CLASS_DEFAULTS.WARRIOR and r.rules[2].text == MS.CLASS_DEFAULTS.ROGUE and r.rules[3].text == "mine")
-- default migration covers every earlier default
for _, old in ipairs(D.OLD_DEFAULT_WHISPERS) do assert(old ~= D.DEFAULT_WHISPER) end
print("old defaults:", #D.OLD_DEFAULT_WHISPERS, " keywords:", table.concat(D.DEFAULT_KEYWORDS, ","))
print("OK")
