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

    NGM2, the update code (pasted on the dashboard's Ranks tab), is NGM1's
    lines, an empty line, then what changed in game:
        since<TAB>t                 changes after this time (0 = everything)
        upto<TAB>t                  when the code was made
        hours<TAB>n<TAB>c,c,...     people sharing hours, then the 84 When we
                                    play counts (7 days x 12 two-hour blocks,
                                    server time, Monday first), as the Overview
        R<TAB>key<TAB>t<TAB>author<TAB>value   main/alt (M) and roles (RL)
    Times are server time in seconds, in base 36. Only changes are sent:
    since = what NGM Peon last said it has, else the last code made, less two
    weeks (a code made but never pasted is covered). Newest wins on both
    sides, so sending something twice is harmless. /ngm discord all sends
    everything; /ngm discord setup makes the short NGM1 code.

    ns.DiscordCode:Make(region, guild, ranks) -> code
    ns.DiscordCode:MakeUpdate(region, guild, ranks, update) -> code
    ns.DiscordCode:ForMyGuild(mode)           -> code, or nil and why
                                                 (mode: nil, "all" or "setup");
                                                 update codes also: everything?,
                                                 how many records, since when
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


local function B36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local d, out = "0123456789abcdefghijklmnopqrstuvwxyz", {}
    while n > 0 do
        local r = n % 36
        table.insert(out, 1, d:sub(r + 1, r + 1))
        n = math.floor(n / 36)
    end
    return table.concat(out)
end
DC.B36 = B36

local function RankLines(region, guild, ranks)
    local lines = { region, guild }
    for _, r in ipairs(ranks) do
        lines[#lines + 1] = (r.officer and "O" or "-") .. (r.invite and "I" or "-") .. ":" .. r.name
    end
    return lines
end

-- ranks: { { name =, officer =, invite = }, ... } in rank order, 0 first
function DC:Make(region, guild, ranks)
    local payload = table.concat(RankLines(region, guild, ranks), "\n")
    return "NGM1." .. DC.Base64Url(payload) .. "." .. DC.Adler32(payload)
end

-- update: { since =, upto =, hours = { sharing =, counts = {84} } or nil,
--           records = { { key =, v =, t =, a = }, ... } }
function DC:MakeUpdate(region, guild, ranks, update)
    local lines = RankLines(region, guild, ranks)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "since\t" .. B36(update.since)
    lines[#lines + 1] = "upto\t" .. B36(update.upto)
    if update.hours then
        local c = {}
        for i = 1, 84 do c[i] = B36(update.hours.counts[i] or 0) end
        lines[#lines + 1] = "hours\t" .. B36(update.hours.sharing) .. "\t" .. table.concat(c, ",")
    end
    for _, r in ipairs(update.records) do
        lines[#lines + 1] = "R\t" .. r.key .. "\t" .. B36(r.t) .. "\t" .. r.a .. "\t" .. r.v
    end
    local payload = table.concat(lines, "\n")
    return "NGM2." .. DC.Base64Url(payload) .. "." .. DC.Adler32(payload)
end

DC.OVERLAP = 14 * 86400 -- a code made but never pasted: the next one covers it

-- Main/alt and roles records changed after `since`, oldest first.
function DC:Changes(since)
    local out = {}
    local store = ns.Sync:Store("guild") or {}
    for key, rec in pairs(store) do
        local typ = key:match("^(%u+):")
        if (typ == "M" or typ == "RL") and (rec.t or 0) > since and rec.a and rec.a ~= ""
            and ns.Sync.ValidValue(typ, rec.v) then
            out[#out + 1] = { key = key, v = rec.v or "", t = rec.t, a = rec.a }
        end
    end
    table.sort(out, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.key < y.key end)
    return out
end

-- The Overview's When we play, counted as its default view (active in 30
-- days, a player's characters once): 84 counts, Monday 00:00 first.
function DC:Hours()
    if not (ns.OverviewView and ns.OverviewView.Census) then return nil end
    local c = ns.OverviewView:Census(30, false)
    local counts = {}
    for k = 0, 83 do counts[k + 1] = c.heat[k] or 0 end
    return { sharing = c.sharing or 0, counts = counts }
end

local REGIONS = { [1] = "us", [3] = "eu" }

function DC:Region()
    local ok, id = pcall(function() return GetCurrentRegion and GetCurrentRegion() end)
    return ok and REGIONS[id] or nil
end

-- The code for the player's own guild. Only the Guild Master's game is
-- sure to see every rank's settings, so only the Guild Master makes it.
function DC:ForMyGuild(mode)
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
    if mode == "setup" then return self:Make(region, guild, ranks) end
    -- the update code: only what changed since NGM Peon last had it all
    local g = ns.DB:Guild() or {}
    g.peon = g.peon or {}
    local upto = ns.DB:Now()
    local since = 0
    if mode ~= "all" then
        if g.peon.has then since = g.peon.has
        elseif g.peon.made then since = math.max(0, g.peon.made - self.OVERLAP) end
    end
    local records = self:Changes(since)
    local code = self:MakeUpdate(region, guild, ranks, { since = since, upto = upto, hours = self:Hours(), records = records })
    g.peon.made = upto
    return code, nil, since == 0, #records, since
end
