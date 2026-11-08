-- Test: Built-in class messages: older versions are swapped for the current ones, edited messages are kept.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
function ns:On() end function ns:Fire() end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
ns.Data = { CLASSES = {}, ClassName = function(_, c) return c end }
ns.Recruit = { MaxLevel = function() return 60 end, Settings = function() end }
assert(loadfile(ROOT .. "/Services/Messages.lua"))("NGM", ns)
local MS = ns.Messages
local r = { rules = {
  { preset = "WARRIOR", text = MS.OLD_CLASS_DEFAULTS.WARRIOR[1], classes = { WARRIOR = true } },
  { preset = "MAGE", text = "my own mage message", classes = { MAGE = true } },
  { text = MS.OLD_CLASS_DEFAULTS.DRUID[1], classes = { DRUID = true } }, -- not a preset: untouched
}, classDefaults = true, classDefaultsAllFactions = true }
MS:Migrate(r)
assert(r.rules[1].text == MS.CLASS_DEFAULTS.WARRIOR, "warrior not updated")
assert(r.rules[2].text == "my own mage message", "edited message changed")
assert(r.rules[3].text == MS.OLD_CLASS_DEFAULTS.DRUID[1], "non-preset changed")
local n = 0 for _ in pairs(MS.OLD_CLASS_DEFAULTS) do n = n + 1 end
print("old defaults kept:", n); print(MS.CLASS_DEFAULTS.ROGUE); print("OK")
