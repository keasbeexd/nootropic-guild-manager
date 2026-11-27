-- Test: the ban list (3.2): a person with all their characters, by game ID
-- (renames don't get round it), unban the family, reasons only for ranks
-- allowed, the invite message matched from the game's own string.
local ROOT = arg[1]
local ns = {}
local store, printed, perms = {}, {}, { ban = true, banlist = true, banreason = true }
function ns:Fire() end function ns:On() end
local events = {}
function ns:RegisterEvent(e, fn) events[e] = fn end
function ns:Print(m) printed[#printed + 1] = m end
function ns.ShortName(n) return (n:gsub("%-.*", "")) end
function ns.NormalizeName(n) return n end
function ns.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ns.PlayerFullName() return "Officer Me" end
ns.Sync = { Store = function() return store end, Set = function(_, k, v) store[k] = { v = v } end,
  Clean = function(v) return (tostring(v or ""):gsub("|", "/")) end }
ns.DB = { Now = function() return 1800000000 end, HasPerm = function(_, k) return perms[k] end,
  RootOf = function(_, n) return ({ ["Bad Alt"] = "Bad Main" })[n] or n end,
  GetAltsOf = function(_, n) return n == "Bad Main" and { "Bad Alt" } or {} end }
ns.Roster = { byName = { ["Bad Main"] = { guid = "Player-1-AAA", rankIndex = 4 }, ["Bad Alt"] = { guid = "Player-1-BBB", rankIndex = 4 } } }
ERR_GUILD_INVITE_S = "You have invited %s to join your guild."
C_Timer = { NewTimer = function() return { Cancel = function() end } end }
CreateFrame = function() local f = { Text = {} } function f:SetSize() end function f:SetPoint() end function f:SetFrameStrata() end
  function f:CreateFontString() return { SetAllPoints = function() end, SetTextColor = function() end, SetJustifyH = function() end, SetText = function(t, s) t.s = s end } end
  function f:Hide() end function f:Show() end function f:SetAlpha() end return f end
UIParent = {}
assert(loadfile(ROOT .. "/Services/Bans.lua"))("NGM", ns)
local BN = ns.Bans
BN:Init()

assert(BN:Ban("Bad Alt", "stole; the bank") == 2, "the whole family")
assert(BN:IsBanned("Bad Main") and BN:IsBanned("Bad Alt"))
-- renamed: the game ID still matches
ns.Roster.byName["Renamed Main"] = { guid = "Player-1-AAA" }
assert(BN:IsBanned("Renamed Main"), "by game ID")
assert(BN:Reason(BN:Find("Bad Main")) == "stole, the bank", "the reason, without its separator")
perms.banreason = false
assert(BN:Reason(BN:Find("Bad Main")) == nil, "no reason for ranks not allowed")
-- the invite: matched from the game's own string
events.CHAT_MSG_SYSTEM(nil, "You have invited Bad Alt to join your guild.")
assert(printed[#printed]:find("Banned: Bad Alt (alt of Bad Main)", 1, true), printed[#printed])
local n = #printed
events.CHAT_MSG_SYSTEM(nil, "You have invited Good Guy to join your guild.")
assert(#printed == n, "nobody else")
-- unban: the family
assert(BN:Unban("Bad Main") == 2)
assert(not BN:IsBanned("Bad Alt"))
perms.ban = false
assert(BN:Ban("Someone") == nil, "a rank without the permission can't")
print("OK")
