-- Test: who may use the recruiting tools (3.2, docs/PERMISSIONS.md), with
-- the real DB:HasPerm and RC:MayRecruit: the default is the game's Invite
-- Member (no loop between the two), and handed to a rank, it still needs
-- Invite Member.
local ROOT = arg[1]
local ns = {}
function ns:On() end function ns:Fire() end function ns:RegisterEvent() end function ns:Print() end
local rank, canInvite, permRanks = 4, false, {}
IsInGuild = function() return true end
IsGuildLeader = function() return rank == 0 end
CanGuildInvite = function() return canInvite end
GetGuildInfo = function() return "Guild", "Member", rank end
StaticPopupDialogs = {}
ns.IsOfficer = function() return false end
ns.Sync = { PERM_DEFAULT = { recruit = "recruiters", dnw_add = "everyone" }, PERM_NARROW = {}, PERM_NEEDS = { dnw_add = "recruit" },
  PERM_INVITE = { recruit = true } }
assert(loadfile(ROOT .. "/Core/Database.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Recruit.lua"))("NGM", ns)
local DB, RC = ns.DB, ns.Recruit
DB.PermRanks = function(_, k) return permRanks[k] end
DB.Rule = function() return nil end
DB.MyRankIndex = function() return rank end
local function check(name, got, want) print(("%-62s %s"):format(name, got == want and "ok" or ("FAIL (got " .. tostring(got) .. ")"))) assert(got == want) end

check("default, a rank the game doesn't let invite: no (and no loop)", RC:MayRecruit(), false)
check("...Do Not Whisper needs it too", DB:HasPerm("dnw_add"), false)
canInvite = true
check("default, a rank that may invite: yes", RC:MayRecruit(), true)
check("...and Do Not Whisper", DB:HasPerm("dnw_add"), true)
permRanks.recruit = { [4] = true }
canInvite = false
check("handed to a rank without Invite Member: still no", RC:MayRecruit(), false)
canInvite = true
check("...with it: yes", RC:MayRecruit(), true)
rank = 0
check("the Guild Master: always", RC:MayRecruit(), true)
print("OK")
