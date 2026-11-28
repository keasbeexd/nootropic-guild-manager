-- Test: the Guild Info code (3.2, docs/PERMISSIONS.md) is off for now: the
-- game restricts reading the Guild Info (C_GuildInfo.GetInfoText), so the
-- NGM Addon never reads or writes it, and the Guild Master's rules count as
-- they are.
local ROOT = arg[1]
local ns = {}
local store, guild, gm = {}, {}, false
local reads, writes = 0, 0
function ns:Fire() end
function ns:On() end
function ns:RegisterEvent() end
function ns:Print() error("nothing to tell") end
local function Hash(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967291 end return h end
local function B36(n) local d, s = "0123456789abcdefghijklmnopqrstuvwxyz", "" repeat local r = n % 36 s = d:sub(r + 1, r + 1) .. s n = (n - r) / 36 until n == 0 return s end
ns.Sync = { Store = function() return store end, Value = function(_, k) return store[k] and store[k].v end, Hash = Hash, Base36 = B36 }
ns.DB = { Guild = function() return guild end, IsGuildMaster = function() return gm end }
C_GuildInfo = { GetInfoText = function() reads = reads + 1 return "x" end, SetInfoText = function() writes = writes + 1 end }
C_Timer = { After = function(_, fn) fn() end }
assert(loadfile(ROOT .. "/Services/GuildRules.lua"))("NGM", ns)
local GR = ns.GuildRules
GR:Init()
local function check(name, got, want) print(("%-62s %s"):format(name, got == want and "ok" or ("FAIL (got " .. tostring(got) .. ")"))) assert(got == want) end

store["GS:perm_links"] = { v = "1" }
GR:Refresh()
check("a member's copy: the rules as they are", GR:Value("perm_links"), "1")
check("...never stale", GR:Stale(), false)
gm = true
GR:Refresh()
check("the Guild Master's copy: the same", GR:Value("perm_links"), "1")
check("no line to check", GR:LineInPlace(), nil)
check("the Guild Info is never read", reads, 0)
check("...or written", writes, 0)
print("OK")
