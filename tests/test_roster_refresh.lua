-- Roster refresh: the game sends a fresh roster only when asked, so the
-- NGM Addon asks once a minute (not in combat), and Guild Feed level-ups
-- arrive within a minute instead of whenever someone opens the Guild window.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
function ns:On() end
function ns:RegisterEvent() end
function ns:Fire() end
local tickers, asked, combat, guilded = {}, 0, false, true
C_Timer = { After = function() end, NewTicker = function(s, fn) tickers[#tickers + 1] = { s, fn }; return {} end }
C_GuildInfo = { GuildRoster = function() asked = asked + 1 end }
IsInGuild = function() return guilded end
InCombatLockdown = function() return combat end
assert(loadfile(ROOT .. "/Services/Roster.lua"))("NGM", ns)
local R = ns.Roster

R:StartRefresh()
assert(#tickers == 1 and tickers[1][1] == 60, "asks every minute")
R:StartRefresh()
assert(#tickers == 1, "one ticker, however often it's started")
local tick = tickers[1][2]
tick()
assert(asked == 1, "asks for the roster")
combat = true; tick()
assert(asked == 1, "not in combat")
combat = false; guilded = false; tick()
assert(asked == 1, "not without a guild")
guilded = true; tick()
assert(asked == 2)
print("OK")
