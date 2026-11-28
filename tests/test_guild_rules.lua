-- Test: the Guild Info code (3.2, docs/PERMISSIONS.md): rules count when
-- they match the code; while they don't, the last ones that did; the Guild
-- Master's copy writes the code into the Guild Info (or hands the line back).
local ROOT = arg[1]
local ns = {}
local store, guild, gm = {}, {}, false
local info = "Welcome to the guild!"
local fired, setCalls = {}, 0
function ns:Fire(e) fired[#fired + 1] = e end
function ns:On() end
function ns:RegisterEvent() end
local function Hash(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967291 end return h end
local function B36(n) local d, s = "0123456789abcdefghijklmnopqrstuvwxyz", "" repeat local r = n % 36 s = d:sub(r + 1, r + 1) .. s n = (n - r) / 36 until n == 0 return s end
ns.Sync = { Store = function() return store end, Value = function(_, k) return store[k] and store[k].v end, Hash = Hash, Base36 = B36,
  CheckAll = function() ns.checked = true end }
ns.DB = { Guild = function() return guild end, IsGuildMaster = function() return gm end }
C_GuildInfo = { GetInfoText = function() return info end, SetInfoText = function(t) setCalls = setCalls + 1 info = t end }
InCombatLockdown = function() return false end
assert(loadfile(ROOT .. "/Services/GuildRules.lua"))("NGM", ns)
local GR = ns.GuildRules
local function check(name, got, want) print(("%-62s %s"):format(name, got == want and "ok" or ("FAIL (got " .. tostring(got) .. ")"))) assert(got == want) end

-- no code in the Guild Info: the rules as they are
store["GS:perm_links"] = { v = "1" }
GR:Refresh()
check("no code: rules as they are", GR:Value("perm_links"), "1")
check("no code: not stale", GR:Stale(), false)

-- the Guild Master's copy never writes the Guild Info (the game forbids it):
-- it hands back the line, and the Guild Master pastes it
gm = true
GR:Refresh()
local ok, line = GR:Publish()
check("not written by the NGM Addon", ok, false)
check("...the line to paste", line, GR:Line())
check("...and the game's write is never called", setCalls, 0)
info = info .. "\n" .. line -- pasted
check("pasted: in place", GR:Publish(), true)

-- a member's copy: matching
gm = false
GR:Refresh()
check("matching: the rules count", GR:Value("perm_links"), "1")
-- a made-up rule arrives that doesn't match the code
store["GS:perm_links"] = { v = "1,4" }
GR:Refresh()
check("not matching: stale", GR:Stale(), true)
check("...a sync check asks for the rules", ns.checked, true)
check("...the last rules that matched still count", GR:Value("perm_links"), "1")
-- the Guild Master changes it for real, and pastes the new line over the old
gm = true
GR:Refresh()
info = info:gsub("NGM:%w+", GR:Line())
gm = false
GR:Refresh()
check("matching again: the new rule counts", GR:Value("perm_links"), "1,4")
check("...and it's no longer stale", GR:Stale(), false)
check("still never written by the NGM Addon", setCalls, 0)
print("OK")
