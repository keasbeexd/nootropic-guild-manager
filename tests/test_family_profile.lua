-- Test: the Discord name and usual hours belong to the player, not one
-- character: every character of theirs shows the contact info set most
-- recently on any of them, and their hours together. Professions and the
-- rest stay per character (they're read from each character's own records).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
local members = {
  ["Marc Priest"] = {}, ["Marc Druid"] = { main = "Marc Priest" }, ["Marc Rogue"] = { main = "Marc Priest" }, ["Ann Solo"] = {},
}
local recs = {}
ns.DB = { GetMember = function(_, f) return members[f] end, Guild = function() return {} end }
ns.Roster = { altIndex = { ["Marc Priest"] = { "Marc Druid", "Marc Rogue" } } }
ns.Sync = { Get = function(_, k) return recs[k] end,
  Newer = function(a, b) return a.t > b.t end }
function ns:On() end function ns:RegisterEvent() end
assert(loadfile(ROOT .. "/Services/Profile.lua"))("NGM", ns)
local PF = ns.Profile
local function check(name, ok) print(("%-60s %s"):format(name, ok and "ok" or "FAIL")) assert(ok) end

recs["CN:Marc Priest"] = { v = "old;", t = 100 }
recs["CN:Marc Druid"] = { v = "keasbeexd;an old contact note", t = 200 }
local d, from = PF:Contact("Marc Rogue")
check("an alt with none of its own shows the newest of the family", d == "keasbeexd" and from == "Marc Druid")
d = PF:Contact("Marc Priest")
check("so does the main", d == "keasbeexd")
recs["CN:Marc Priest"] = { v = "newer;", t = 300 }
check("whichever was updated last wins", PF:Contact("Marc Druid") == "newer")
recs["CN:Marc Priest"] = { v = "", t = 400 }
check("clearing it (newest) clears it for everyone", PF:Contact("Marc Rogue") == nil)
check("someone without alts keeps their own", PF:Contact("Ann Solo") == nil)

-- usual hours: all their characters together
local function hex(set) -- 168 bits, as Profile stores them
  local bits = {}
  for i = 0, 167 do bits[i] = set[i] and 1 or 0 end
  local out = {}
  for i = 0, 167, 4 do out[#out + 1] = ("%x"):format(bits[i] * 8 + bits[i + 1] * 4 + bits[i + 2] * 2 + bits[i + 3]) end
  return table.concat(out)
end
members["Marc Priest"].schedule = hex({ [20] = true })
members["Marc Druid"].schedule = hex({ [44] = true })
local h = PF:Hours("Marc Rogue", "server")
check("hours: every character shows the player's, all together", h and h[20] and h[44])
local h2 = PF:Hours("Marc Priest", "server")
check("the same on the main", h2 and h2[20] and h2[44])
print("OK")
