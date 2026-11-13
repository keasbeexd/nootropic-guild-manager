-- Test: NGM Peon setup code: the addon makes exactly the code NGM Peon expects (reference codes from ngm-hub's formatSetupCode), and only for the Guild Master.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
assert(loadfile(ROOT .. "/Services/DiscordCode.lua"))("NGM", ns)
local DC = ns.DiscordCode

-- the same inputs ngm-hub's src/setupcode.ts was given
local a = DC:Make("us", "Nootropic", {
    { name = "Guild Master", officer = true, invite = true },
    { name = "Officer", officer = true, invite = true },
    { name = "Recruiter", officer = false, invite = true },
    { name = "Raider", officer = false, invite = false },
    { name = "Offizi\195\168re \226\156\166", officer = false, invite = false },
})
assert(a == "NGM1.dXMKTm9vdHJvcGljCk9JOkd1aWxkIE1hc3RlcgpPSTpPZmZpY2VyCi1JOlJlY3J1aXRlcgotLTpSYWlkZXIKLS06T2ZmaXppw6hyZSDinKY.53821c96", a)
local b = DC:Make("eu", "Dragon's Fury", { { name = "GM", officer = true, invite = true }, { name = "M" } })
assert(b == "NGM1.ZXUKRHJhZ29uJ3MgRnVyeQpPSTpHTQotLTpN.7a0407fb", b)
assert(DC.Adler32("Wikipedia") == "11e60398")
assert(DC.Base64Url("f") == "Zg" and DC.Base64Url("fo") == "Zm8" and DC.Base64Url("foo") == "Zm9v" and DC.Base64Url("\255\254") == "__4")

-- the player's own guild
local gm, region, flags = true, 1, { [1] = { officer = true, invite = true }, [2] = { officer = false, invite = false } }
GetGuildInfo = function() return "Nootropic" end
GetCurrentRegion = function() return region end
ns.DB = { IsGuildMaster = function() return gm end,
  GuildRanks = function() return { { index = 0, name = "Guild Master" }, { index = 1, name = "Officer" }, { index = 2, name = "Member" } } end }
ns.Sync = { RankFlags = function(_, i) return flags[i] end }
local code = DC:ForMyGuild("setup")
assert(code and code:find("^NGM1%."), tostring(code))
gm = false
local none, why = DC:ForMyGuild()
assert(none == nil and why:find("Guild Master"))
gm, flags[2] = true, nil
none, why = DC:ForMyGuild()
assert(none == nil and why:find("settings"))
flags[2], region = { officer = false, invite = false }, 2
none, why = DC:ForMyGuild()
assert(none == nil and why:find("US and EU"))

-- NGM2, the update code: the same example as ngm-hub's test/gameupdate.test.ts
local counts = {}
for i = 0, 83 do counts[i + 1] = (i % 12 >= 9) and 3 or ((i % 5 == 0) and 1 or 0) end
local u = DC:MakeUpdate("us", "Nootropic", {
    { name = "Guild Master", officer = true, invite = true },
    { name = "Officer", officer = true, invite = true },
    { name = "Member", officer = false, invite = false },
}, { since = 1794000000, upto = 1794540000, hours = { sharing = 12, counts = counts }, records = {
    { key = "M:Zo\195\171 Ash", v = "Marc Priest", t = 1794500000, a = "Marc Priest" },
    { key = "M:Marc Priest", v = "", t = 1794500000, a = "Marc Priest" },
    { key = "RL:Zo\195\171 Ash", v = "tank,damage", t = 1794510000, a = "Zo\195\171 Ash" },
} })
assert(u == "NGM2.dXMKTm9vdHJvcGljCk9JOkd1aWxkIE1hc3RlcgpPSTpPZmZpY2VyCi0tOk1lbWJlcgoKc2luY2UJdG8zbjljCnVwdG8JdG9mN3hjCmhvdXJzCWMJMSwwLDAsMCwwLDEsMCwwLDAsMywzLDMsMCwwLDAsMSwwLDAsMCwwLDEsMywzLDMsMCwxLDAsMCwwLDAsMSwwLDAsMywzLDMsMCwwLDAsMCwxLDAsMCwwLDAsMywzLDMsMCwwLDEsMCwwLDAsMCwxLDAsMywzLDMsMSwwLDAsMCwwLDEsMCwwLDAsMywzLDMsMCwwLDAsMSwwLDAsMCwwLDEsMywzLDMKUglNOlpvw6sgQXNoCXRvZWQyOAlNYXJjIFByaWVzdAlNYXJjIFByaWVzdApSCU06TWFyYyBQcmllc3QJdG9lZDI4CU1hcmMgUHJpZXN0CQpSCVJMOlpvw6sgQXNoCXRvZWtzMAlab8OrIEFzaAl0YW5rLGRhbWFnZQ.13f06304", u)
assert(DC.B36(0) == "0" and DC.B36(35) == "z" and DC.B36(36) == "10")

-- only changes: since NGM Peon's word, else the last code less two weeks; "all" sends everything
local now = 3000000
local store = {
    ["M:Old"] = { v = "", t = 1000, a = "Old" },
    ["M:New"] = { v = "Main", t = now - 10, a = "Off" },
    ["RL:New"] = { v = "tank", t = now - 5, a = "New" },
    ["CN:New"] = { v = "x", t = now - 5, a = "New" }, -- not sent: only M and RL
}
local guildData = {}
gm, region, flags[2] = true, 1, { officer = false, invite = false }
ns.DB.Guild = function() return guildData end
ns.DB.Now = function() return now end
ns.Sync.Store = function() return store end
local first, _, everything = DC:ForMyGuild()
assert(first:find("^NGM2%.") and everything == true, "first code: everything")
assert(guildData.peon.made == now)
assert(#DC:Changes(0) == 3 and #DC:Changes(now - 8) == 1)
now = now + 30 * 86400
local _, _, all2 = DC:ForMyGuild()
assert(all2 == false, "later codes: changes only")
guildData.peon.has = now - 100
local _, _, all3 = DC:ForMyGuild("all")
assert(all3 == true, "/ngm discord all: everything")
assert(DC:ForMyGuild("setup"):find("^NGM1%."), "/ngm discord setup: the short code")

print(a); print("OK")
