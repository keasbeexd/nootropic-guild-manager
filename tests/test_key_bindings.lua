-- Test: Bindings.xml has a key for every tab, in the window's tab order, in
-- the NGM Addon's own section of the game's Key Bindings (3.0.14-test1: a
-- header="" attribute put them under Other with a stray HEADER_ row), each
-- with a name the game's Key Bindings can show, and
-- a tab's key opens that tab (or closes the window when it's already open;
-- a tab your rank can't use only says so).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local xml = assert(io.open(ROOT .. "/Bindings.xml")):read("*a")
local src = assert(io.open(ROOT .. "/UI/MainFrame.lua")):read("*a")
local labels = {}
for l in src:match("local TAB_LABELS = (%b{})"):gmatch('"([^"]+)"') do labels[#labels + 1] = l end
local order = {}
for n in src:match("local TAB_ORDER = (%b{})"):gmatch("%d+") do order[#order + 1] = tonumber(n) end
assert(#labels == 7 and #order == #labels, "tab labels and order found")

-- the bindings, in file order
local binds = {}
for name, attrs, body in xml:gmatch('<Binding name="([%w_]+)"([^>]*)>(.-)</Binding>') do binds[#binds + 1] = { name = name, attrs = attrs, body = body } end
assert(not xml:match("header="), "no header attribute (it shows as a binding row)")
assert(#binds == #labels, "one key per tab, nothing else")
for k, id in ipairs(order) do
    local b = binds[k]
    assert(b.attrs == ' category="BINDING_HEADER_NOOTROPICGM"', b.name .. " is in the NGM Addon's own section")
    assert(b.name == "NOOTROPICGM_TAB" .. id, ("binding %d is tab %d, in the window's order"):format(k, id))
    assert(b.body == ("NootropicGuildManager_OpenTab(%d)"):format(id), b.name .. " opens its own tab")
end

-- run the bindings' part of MainFrame.lua against stand-ins
local chunk = src:match("(BINDING_HEADER_NOOTROPICGM.-\nend)\n\nfunction UI:SetSearch")
assert(chunk, "binding code found")
local printed, opened = nil, nil
local allowed = { [4] = false }
local UI = {
    IsTabAvailable = function(_, id) return allowed[id] ~= false end,
    TabTitle = function(_, id) return labels[id] end,
    OpenTab = function(_, id, toggle) opened = { id, toggle } end,
}
local ns = { Print = function(_, msg) printed = msg end }
assert(load("local UI, ns, TAB_LABELS = ...\n" .. chunk))(UI, ns, labels)
assert(BINDING_HEADER_NOOTROPICGM == "Nootropic Guild Manager")
for i, label in ipairs(labels) do assert(_G["BINDING_NAME_NOOTROPICGM_TAB" .. i] == label .. " tab", "a name for tab " .. i) end

NootropicGuildManager_OpenTab(7)
assert(opened[1] == 7 and opened[2] == true, "a tab's key opens it, and closes the window when it's showing")
opened = nil
NootropicGuildManager_OpenTab(4)
assert(not opened and printed == "The Audit tab isn't open to your rank.", "a tab your rank can't use only says so")
NootropicGuildManager_OpenTab(99)
assert(not opened, "no such tab")
print("OK")
