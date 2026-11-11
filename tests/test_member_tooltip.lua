-- Test: the member tooltip (the same everywhere: the addon's lists, Play
-- Together, the game's guild roster) shows only main/alt, spec, role, the two
-- main professions, Discord and your private note.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
local lines = {}
GameTooltip = {
  AddLine = function(_, t) lines[#lines + 1] = t end,
  AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " = " .. r end,
  SetOwner = function() end, Show = function() end, IsShown = function() return true end,
}
ns.Widgets = {}
function ns:On() end function ns:RegisterEvent() end
function ns.ClassColor() return 1, 1, 1 end
assert(loadfile(ROOT .. "/Core/Data.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/UI/RosterView.lua"))("NGM", ns)
local RV = ns.RosterView
local e = {
  short = "Marc", level = 30, className = "Priest", isAlt = false, alts = { "Marc Druid" },
  spec = "Discipline", roleList = { "Healer" }, discord = "@keasbeexd",
  profs = { { name = "First Aid", rank = 80, max = 150 }, { name = "Herbalism", rank = 30, max = 75 },
            { name = "Cooking", rank = 1, max = 75 }, { name = "Alchemy", rank = 10, max = 75 }, { name = "Fishing", rank = 3, max = 75 } },
}
RV:AddMemberLines(e)
local text = table.concat(lines, "\n")
print(text)
assert(text:find("Main = ", 1, true) and text:find("1 alt", 1, true), "main, with alts counted")
assert(text:find("Spec = Discipline", 1, true) and text:find("Role = Healer", 1, true), "spec and role")
assert(text:find("Herbalism", 1, true) and text:find("Alchemy", 1, true), "the two main professions")
assert(not text:find("First Aid", 1, true) and not text:find("Cooking", 1, true) and not text:find("Fishing", 1, true), "no secondary skills")
assert(text:find("Discord = @keasbeexd", 1, true), "Discord")
assert(not text:find("Usually", 1, true) and not text:find("Addon version", 1, true) and not text:find("Rank", 1, true), "nothing else")
lines = {}
RV:AddMemberLines({ isAlt = true, mainShort = "Mykkie", profs = {} })
assert(lines[1] == "Alt of = Mykkie", "alt of whom")
print("OK")
