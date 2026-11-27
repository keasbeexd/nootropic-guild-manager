-- Test: Get Connected (3.1): each step's state from NGM Peon's records (LK
-- linked, DX Discord in WoW, GS:gamechat), NGM Desktop; opens by itself only
-- with NGM Peon and something still to do.
local ROOT = arg[1]
local ns = {}
ns.GOLD = ""
local plan, peon, desktop = {}, true, false
ns.Sync = {
    Linked = function(_, n) local r = plan["LK:" .. n] return r ~= nil and r.v == "1" end,
    Plan = function(_, k) return plan[k] end,
    PeonGuild = function() return peon end,
}
ns.DiscordCode = { DesktopInstalled = function() return desktop end }
ns.DB = { RootOf = function(_, n) return n == "Ann Alt" and "Ann Main" or n end,
    GetAltsOf = function(_, n) return n == "Ann Main" and { "Ann Alt" } or {} end }
ns.PlayerFullName = function() return "Ann Alt" end
ns.Widgets = {}
assert(loadfile(ROOT .. "/UI/ConnectGuide.lua"))("NGM", ns)
local CG = ns.ConnectGuide
local function states()
    local out = {}
    for _, s in ipairs(CG:Steps()) do out[#out + 1] = s.title .. "=" .. s.state end
    return table.concat(out, ", ")
end

assert(states() == "NGM Addon=done, Link with NGM Peon=todo, NGM Desktop=optional", states())
assert(CG:Needed(), "not linked: worth opening")
-- linked (any of their characters: the main counts for the alt playing)
plan["LK:Ann Main"] = { v = "1" }
desktop = true
assert(states() == "NGM Addon=done, Link with NGM Peon=done, NGM Desktop=done", states())
assert(not CG:Needed(), "all done")
-- the guild's chat reaches Discord: Discord in WoW joins the list
plan["GS:gamechat"] = { v = "1" }
assert(states():find("Discord in WoW=unknown", 1, true), states())
assert(not CG:Needed(), "not seen yet: listed, but no reason to open by itself")
plan["DX:Ann Alt"] = { v = "0" }
assert(states():find("Discord in WoW=todo", 1, true) and CG:Needed(), states())
assert(CG:Steps()[4].button and CG:Steps()[4].button.label == "Open Options")
plan["DX:Ann Main"] = { v = "1" }
assert(states():find("Discord in WoW=done", 1, true) and not CG:Needed(), states())
-- without NGM Peon: never opens by itself
plan, peon = {}, false
assert(not CG:Needed())
print("OK")
