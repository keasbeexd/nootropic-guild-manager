-- Test: Do Not Whisper window data: 14-day lockouts from shared records, the hourly cap setting, and the name right-click menu.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local NOW = 1800000000
local ns = {}
function ns:On() end function ns:Fire() end function ns:RegisterEvent() end function ns:Print() end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.ShortName(n) return (n:gsub("%-.*", "")) end
function ns.NormalizeName(n) if n:find("-") then return n end return n .. "-Realm" end
function ns.PlayerFullName() return "Me-Realm" end
ns.Data = { WHISPER_MAX = 255, MAX_KEYWORDS = 6 }
local settings = { whisperPerHour = 40 }
local store = {}
ns.DB = { Now = function() return NOW end, Guild = function() return {} end, Settings = function() return settings end, HasPerm = function() return true end }
CanGuildInvite = function() return true end
ns.Sync = { TYPES = { RS = { ttl = 14 * 86400 } }, Store = function() return store end,
  Get = function(_, k) return store[k] end, Value = function(_, k) return store[k] and store[k].v end,
  Clean = function(v) return v end,
  Set = function(_, k, v) store[k] = { v = v, t = NOW, a = "Me-Realm" } return true end }
ns.Widgets = {}
ns.Roster = { byName = { ["Guildie-Realm"] = {} } }
IsInGuild = function() return true end
StaticPopupDialogs = {}
assert(loadfile(ROOT .. "/Services/Recruit.lua"))("NGM", ns)
local RC = ns.Recruit
local d = 86400
store["RS:Fresh-Realm"] = { v = (NOW - 2*d) .. ";;;", t = NOW - 2*d, a = "Mira-Realm" }
store["RS:Old-Realm"]   = { v = (NOW - 13*d) .. ";" .. (NOW - 12*d) .. ";;no ty", t = NOW - 12*d, a = "Bob-Realm" }
store["RS:Expired-Realm"] = { v = (NOW - 15*d) .. ";;;", t = NOW - 15*d, a = "X-Realm" }
store["RS:Both-Realm"]  = { v = (NOW - 1*d) .. ";;;", t = NOW - d, a = "Me-Realm" }
RC:AddDNW("Both-Realm", "leave me alone")
RC:AddDNW("Manual-Realm", "(added by hand)")
local locked = RC:LockedList()
for _, l in ipairs(locked) do print("locked", l.full, ns.ShortName(l.by), ("%.1f days left"):format((l.untilT - NOW) / d)) end
assert(#locked == 2 and locked[1].full == "Fresh-Realm" and locked[2].full == "Old-Realm")
print("dnw", #RC:DNWList())
-- hourly cap
print("cap", RC:HourlyMax()); settings.whisperPerHour = 0; print("cap none", RC:HourlyMax())
-- menu hook
GetUnitName = function() return "Unitguy" end; UnitIsPlayer = function() return true end
assert(loadfile(ROOT .. "/UI/DNWView.lua"))("NGM", ns)
ns.Safe = function(fn) return fn end
local made = {}
local root = { CreateDivider = function() end, CreateTitle = function() end,
  CreateButton = function(_, text, fn) made[#made + 1] = text; fn() end }
ns.DNWView:AddMenu(root, { name = "Spammer" }); ns.DNWView:AddMenu(root, { name = "Spammer" })
ns.DNWView:AddMenu(root, { name = "Guildie" }); ns.DNWView:AddMenu(root, { unit = "target" })
print("menu:", table.concat(made, " | ")); assert(made[1] == "Add to Do Not Whisper" and made[2] == "Take off Do Not Whisper" and #made == 3)
assert(RC:IsDNW("Unitguy-Realm") and not RC:IsDNW("Spammer-Realm"))
print("OK")
