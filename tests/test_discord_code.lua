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
local code = DC:ForMyGuild()
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
print(a); print("OK")
