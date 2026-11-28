-- Test: calls the game refuses the NGM Addon on WoW: Forever ("Interface
-- action failed"), found with /ngm bug in 3.2's tests, are never made again:
-- writing the Guild Info, and asking whether Discord is connected. Reading
-- the Guild Info only in Services/GuildRules.lua, which reads it only while
-- the game restricts nothing. (Comments may name them.)
local ROOT = arg[1]
local BANNED = { "C_GuildInfo%.GetInfoText", "C_GuildInfo%.SetInfoText", "GetGuildInfoText", "SetGuildInfoText", "C_Discord" }
local ALLOWED = { ["Services/GuildRules.lua"] = { ["C_GuildInfo%.GetInfoText"] = true } }
local bad = 0
local p = io.popen('find "' .. ROOT .. '/Core" "' .. ROOT .. '/Services" "' .. ROOT .. '/UI" -name "*.lua"')
for file in p:lines() do
    local n, inBlock = 0, false
    for line in io.lines(file) do
        n = n + 1
        local code = line
        if inBlock then
            if code:find("%]%]") then inBlock = false code = code:gsub("^.-%]%]", "") else code = "" end
        end
        if code:find("^%s*%-%-%[%[") then inBlock = not code:find("%]%]") code = "" end
        code = code:gsub("%-%-.*$", "")
        for _, b in ipairs(BANNED) do
            local rel = file:sub(#ROOT + 2)
            if code:find(b) and not (ALLOWED[rel] and ALLOWED[rel][b]) then print(("%s:%d calls %s"):format(file:sub(#ROOT + 2), n, b:gsub("%%", ""))) bad = bad + 1 end
        end
    end
end
p:close()
assert(bad == 0, "the game refuses these")
print("OK")
