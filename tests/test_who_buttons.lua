-- Test: /who whisper buttons stay off the guild roster, the friends list and
-- our own windows, and never appear for you or a guildmate (a /who that
-- included you used to put one on your own Guild & Communities row).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = { Widgets = {} }
function ns:RegisterEvent() end
function ns.NormalizeName(n) local b = n and n:match("^([^%-]*)") return (b and b ~= "") and b or nil end
function ns.PlayerFullName() return "Marc Priest" end
ns.Roster = { byName = { ["Probably Shawn"] = {} } }
assert(loadfile(ROOT .. "/UI/WhoWhisper.lua"))("NGM", ns)
local WI = ns.WhoWhisper

local function frame(name, parent)
  return { GetName = function() return name end, GetParent = function() return parent end }
end
GameTooltip = frame("GameTooltip")
local communities = frame("CommunitiesFrame")
local list = frame(nil, frame(nil, communities))
local guildRow = frame(nil, list)
local who = frame("WhoFrame", frame("FriendsFrame"))
local whoRow = frame(nil, frame(nil, who))
local friendsRow = frame(nil, frame("FriendsListFrame", frame("FriendsFrame")))
local ourRow = frame(nil, frame("NootropicGMFrame"))

assert(WI.Excluded(guildRow), "guild roster row")
assert(WI.Excluded(friendsRow), "friends list row")
assert(WI.Excluded(ourRow), "our own window")
assert(not WI.Excluded(whoRow), "/who row keeps its button")

assert(not WI.Recruitable({ name = "Marc Priest-CAMWOWUS1Realm2PvP" }), "not for yourself")
assert(not WI.Recruitable({ name = "Probably Shawn" }), "not for a guildmate")
assert(WI.Recruitable({ name = "Some Stranger" }))
assert(not WI.Recruitable({ name = "" }))
print("OK")
