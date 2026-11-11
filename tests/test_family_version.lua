-- Test: a player's characters show the newest addon version seen on any of
-- them (it's one install), and an alt that's unlinked shows its own again.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local ns = { version = "2.12.0" }
local members = {
  ["Marc Priest"] = { version = "2.12.0" },              -- you, running 2.12.0
  ["Marc Druid"] = { main = "Marc Priest" },             -- never logged in with it
  ["Myk Main"] = { version = "2.10.0" },
  ["Myk Alt"] = { main = "Myk Main", version = "2.11.0" },
  ["Solo Guy"] = {},
}
local g = { members = members }
function ns:On() end function ns:RegisterEvent() end function ns:Fire() end
function ns.PlayerFullName() return "Marc Priest" end
function ns.SplitName(s) return s:match("^(%S+)%s*(.*)$") end
function ns.ShortName(n) return n end
function ns.IsOfficer() return false end
function ns.CompareVersions(a, b)
  local function parts(v) local t = {} for d in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(d) end return t end
  local x, y = parts(a), parts(b)
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p < q and -1 or 1 end
  end
  return 0
end
ns.DB = { GetMember = function(_, f) return members[f] end, Guild = function() return g end }
ns.Sync = { Get = function() return nil end }
assert(loadfile(ROOT .. "/Core/Data.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Profile.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Roster.lua"))("NGM", ns)
local R = ns.Roster
R:BuildAltIndex()
local function entry(full)
  local e = { full = full, short = full, level = 30, classFile = "PRIEST", className = "Priest", rank = "Member",
    rankIndex = 3, zone = "", publicNote = "", officerNote = "", online = false, status = 0, lastOnline = 0 }
  R:Decorate(e)
  return e
end
local function check(name, ok) print(("%-62s %s"):format(name, ok and "ok" or "FAIL")) assert(ok) end
check("an alt never logged in with the addon shows its main's version", entry("Marc Druid").version == "2.12.0" and entry("Marc Druid").hasAddon)
check("the newest of the family wins (the alt's, here)", entry("Myk Main").version == "2.11.0" and entry("Myk Alt").version == "2.11.0")
check("someone without the addon or links has none", entry("Solo Guy").version == nil and not entry("Solo Guy").hasAddon)
members["Myk Alt"].main = nil
R:BuildAltIndex()
check("unlinked, each shows its own again", entry("Myk Main").version == "2.10.0" and entry("Myk Alt").version == "2.11.0")
-- sorting: alts always right under their main
members["Myk Alt"].main = "Myk Main"
R:BuildAltIndex()
local list = {}
for _, n in ipairs({ "Solo Guy", "Marc Druid", "Myk Alt", "Marc Priest", "Myk Main" }) do
  local e = entry(n)
  e.online = (n == "Myk Alt" or n == "Solo Guy")
  e.lastOnline = ({ ["Marc Priest"] = 2, ["Marc Druid"] = 50, ["Myk Main"] = 10 })[n] or 0
  list[#list + 1] = e
end
local function names(l) local t = {} for i, e in ipairs(l) do t[i] = e.full end return table.concat(t, ", ") end
R:Sort(list, "name", true, true)
check("by name: alts under their main (" .. names(list) .. ")", names(list) == "Marc Priest, Marc Druid, Myk Main, Myk Alt, Solo Guy")
R:Sort(list, "seen", true, true)
check("by last online: an online alt brings its family up (" .. names(list) .. ")",
  names(list) == "Myk Main, Myk Alt, Solo Guy, Marc Priest, Marc Druid")
local only = { list[1] }
for _, e in ipairs(list) do if e.full == "Myk Alt" then only[2] = e end end
R:Sort(only, "name", true, true)
check("an alt whose main isn't listed keeps its own place", #only == 2)
print("OK")
