-- Test: every Find column starts shown (3.2.1): a new install, and anyone
-- still on the old default (only Second Name hidden) moves over once;
-- columns someone hid themselves stay hidden.
local ROOT = arg[1]
local ns = {}
function ns:On() end function ns:Fire() end function ns:RegisterEvent() end function ns:Print() end
ns.Sync = { PERM_DEFAULT = {}, PERM_NARROW = {}, PERM_NEEDS = {}, PERM_INVITE = {} }
local function load(sv)
    NootropicGuildManagerDB = sv
    assert(loadfile(ROOT .. "/Core/Database.lua"))("NGM", ns)
    ns.DB:Init()
    return ns.DB:Settings().hiddenColumns
end
local function check(name, got, want) print(("%-62s %s"):format(name, got == want and "ok" or ("FAIL (got " .. tostring(got) .. ")"))) assert(got == want) end

check("new install: Second Name shown", load(nil).second, nil)
check("old default (only Second Name hidden): shown once", load({ settings = { columnsMigrated = true, hiddenColumns = { second = true } } }).second, nil)
local mine = load({ settings = { columnsMigrated = true, hiddenColumns = { second = true, zone = true } } })
check("hidden by hand alongside: kept", mine.second == true and mine.zone == true, true)
check("moved once: hiding it again sticks", load({ settings = { columnsMigrated = true, columnsAllShown = true, hiddenColumns = { second = true } } }).second, true)
print("OK")
