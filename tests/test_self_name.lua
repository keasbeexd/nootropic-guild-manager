-- Test: finding your own roster row when the game gives only your first name
-- and you have several characters with that first name in the guild.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = { Data = {} }
function ns:Fire(ev, v) ns.fired = v end function ns:On() end function ns:RegisterEvent() end
function ns.NormalizeName(n) return n end
function ns.ShortName(n) return (n:match("^(%S+)")) end
function ns.PlayerFullName() return ns.selfName or "Mykkie" end
local rows
function GetGuildRosterInfo(i)
  local r = rows[i]
  -- name, rank, rankIndex, level, class, zone, note, officerNote, online, status, classFile, ..., guid (17)
  return r[1], "", 0, r[2], "", "", "", "", r[3], 0, r[4], nil, nil, nil, nil, nil, r[5]
end
UnitName = function() return "Mykkie" end
UnitClass = function() return "Paladin", "PALADIN" end
UnitLevel = function() return 7 end
local guid = nil
UnitGUID = function() return guid end
assert(loadfile(ROOT .. "/Services/Roster.lua"))("NGM", ns)
local R = ns.Roster
local function check(name, ok) print(("%-58s %s"):format(name, ok and "ok" or "FAIL")) assert(ok) end

-- the offline mage comes first in the roster
rows = { { "Mykkie Frost", 16, false, "MAGE", "g-mage" }, { "Mykkie Sickyy", 7, true, "PALADIN", "g-pala" } }
R:FindSelf(#rows)
check("no character id: the online paladin, not the mage", R.selfRow == "Mykkie Sickyy" and ns.selfName == "Mykkie Sickyy")

ns.selfName = nil
guid = "g-mage" -- the character id wins when the game gives it
R:FindSelf(#rows)
check("the character id decides when available", R.selfRow == "Mykkie Frost")

ns.selfName, guid = nil, nil
rows = { { "Solo Name", 7, false, "PALADIN" } }
UnitName = function() return "Solo" end
R:FindSelf(#rows)
check("a unique first name still matches", R.selfRow == "Solo Name")
print("OK")
