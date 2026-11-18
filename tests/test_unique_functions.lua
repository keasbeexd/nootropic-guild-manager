-- Test: no function of the shared namespace (function ns.X / ns:X) is
-- defined twice. Lua quietly keeps the last one, so a second definition with
-- the same name replaces the first everywhere (3.0.9: a new ns.FormatAgo
-- taking seconds was replaced by the older one taking a time).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local seen, dupes = {}, {}
local list = assert(io.popen('find "' .. ROOT .. '/Core" "' .. ROOT .. '/Services" "' .. ROOT .. '/UI" -name "*.lua" | sort'))
for file in list:lines() do
    local n = 0
    for line in io.lines(file) do
        n = n + 1
        local name = line:match("^function ns[%.:]([%w_]+)%s*%(")
        if name then
            local here = file:sub(#ROOT + 2) .. ":" .. n
            if seen[name] then dupes[#dupes + 1] = ("ns.%s: %s and %s"):format(name, seen[name], here) end
            seen[name] = seen[name] or here
        end
    end
end
list:close()
assert(next(seen), "found the addon's files")
assert(#dupes == 0, "defined twice:\n  " .. table.concat(dupes, "\n  "))
print("OK")
