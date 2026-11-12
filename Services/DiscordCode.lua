--[[
    Nootropic Guild Manager - NGM Peon setup code (3.0)
    The Guild Master's copy makes a short code for NGM Peon's /ngm setup in
    Discord. It carries what Blizzard's web API can't: the guild's rank
    names, and which ranks the game marks Officer and Invite Member.

        NGM1.<payload, base64url>.<adler-32 of the payload, 8 hex digits>

    The payload is lines: region (us/eu), guild name, then one line per rank
    (rank 0 first): two flags ("O" Officer or "-", "I" Invite or "-"), a
    colon, the rank name. NGM Peon reads it in ngm-hub's src/setupcode.ts;
    tests/test_discord_code.lua checks both sides make the same code.

    The code proves nothing by itself: NGM Peon still has the Guild Master
    sign in with Battle.net.

    ns.DiscordCode:Make(region, guild, ranks) -> code
    ns.DiscordCode:ForMyGuild()               -> code, or nil and why
]]
local _, ns = ...
local DC = {}
ns.DiscordCode = DC

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

-- base64url, no padding. Arithmetic only (no bit library needed).
function DC.Base64Url(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(v / 262144) % 64
        local c2 = math.floor(v / 4096) % 64
        local c3 = math.floor(v / 64) % 64
        local c4 = v % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
        if b then out[#out + 1] = B64:sub(c3 + 1, c3 + 1) end
        if c then out[#out + 1] = B64:sub(c4 + 1, c4 + 1) end
    end
    return table.concat(out)
end

-- Adler-32 as 8 hex digits, written as two halves (the game's string.format
-- can't print numbers past 2^31 in hex).
function DC.Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return ("%04x%04x"):format(b, a)
end

-- ranks: { { name =, officer =, invite = }, ... } in rank order, 0 first
function DC:Make(region, guild, ranks)
    local lines = { region, guild }
    for _, r in ipairs(ranks) do
        lines[#lines + 1] = (r.officer and "O" or "-") .. (r.invite and "I" or "-") .. ":" .. r.name
    end
    local payload = table.concat(lines, "\n")
    return "NGM1." .. DC.Base64Url(payload) .. "." .. DC.Adler32(payload)
end

local REGIONS = { [1] = "us", [3] = "eu" }

function DC:Region()
    local ok, id = pcall(function() return GetCurrentRegion and GetCurrentRegion() end)
    return ok and REGIONS[id] or nil
end

-- The code for the player's own guild. Only the Guild Master's game is
-- sure to see every rank's settings, so only the Guild Master makes it.
function DC:ForMyGuild()
    local guild = GetGuildInfo and GetGuildInfo("player")
    if not guild then return nil, "You're not in a guild." end
    if not (ns.DB.IsGuildMaster and ns.DB:IsGuildMaster()) then
        return nil, "Only the Guild Master can make the setup code: only their game sees every rank's settings."
    end
    local region = self:Region()
    if not region then return nil, "NGM Peon serves the US and EU regions only, for now." end
    local ranks = {}
    for _, r in ipairs(ns.DB:GuildRanks()) do
        local f = r.index == 0 and { officer = true, invite = true } or ns.Sync:RankFlags(r.index)
        if not f then
            return nil, "The game isn't sharing your ranks' settings right now. Open the guild window's rank settings once, then try again."
        end
        if r.name:find("\n", 1, true) then return nil, "A rank name has a line break in it." end
        ranks[#ranks + 1] = { name = r.name, officer = f.officer, invite = f.invite }
    end
    if #ranks < 2 then return nil, "The game hasn't loaded your guild's ranks yet. Try again in a moment." end
    return self:Make(region, guild, ranks)
end
