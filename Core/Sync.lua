--[[
    Nootropic Guild Manager - Sync engine (protocol 2)

    Shared data is stored as RECORDS: key -> { v = value, t = time, a = author }.
    Every change gets the server time and its author, and the newest version of
    a record always wins (ties broken by author name), so every copy converges
    on the same data no matter what order messages arrive in.

    Scopes
      guild    main/alt links, specs, roles, professions and contact info.
               Sent on the GUILD addon channel.
      officer  officer log and audit trail. Sent only on the OFFICER
               addon channel (the game delivers it only to ranks that can read
               officer chat). Nothing is ever whispered.

    Delivery
      1. Batches: local changes apply instantly but are sent together 15
         seconds after the first one (one BATCH id, also used to group the
         audit trail).
      2. Repair: clients regularly broadcast a DIGEST (16 checksums over all
         their records). Anyone whose checksums differ re-broadcasts just the
         mismatched buckets on the same channel (never by whisper), announced
         with a B marker so other clients don't send the same bucket again.
         Lost messages, offline officers and late joiners all heal this way.
      3. Transport: a byte-budget queue (live changes first), retries when the
         game reports throttling or combat lockdown, and splits long messages.

    Record keys
      M:<member>           member's main ("" = main) officers
      MS:<member>          spec override           officers, or the member
      RL:<member>          roles: "tank,healer,damage" (any of them)   officers, or the member
      MP:<member>          manual professions      officers, or the member
      P:<member>           addon-reported spec/professions   the member only
      L:<member>:<id>      officer log entry       officers (officer scope)
      A:<id>               audit entry             officers (officer scope)
      DN:<player>          Do Not Whisper entry    anyone in the guild ("" = removed)
      RS:<player>          recruitment status      anyone in the guild (kept 14 days;
                                                   blocks new whispers to them meanwhile)
      AV:<member>          addon version in use    the member only
      GS:<name>            guild-wide setting, e.g. GS:perm_links = "1,3" (who may link mains)   officers
      CN:<member>          contact: "discord;note" (Discord name, then
                           anything else: BattleTag, timezone...)   officers, or the member
      JN:<member>          when they joined: "time;inviter"   officers (officer scope)
      RK:<member>          their current rank since: "time;rank;by"   officers (officer scope)
      RP:<member>:<prof>   recipes they know in one profession: "name;id,id"
                           (base-36 spell IDs; Services/Recipes.lua)   the member only
      RR:<member>          raid readiness: attunements and keys
                           (Services/Readiness.lua)   the member only
      PS:<member>          sharing choices others must respect: "together" =
                           leave me out of Play Together (Services/Sharing.lua)   the member only
      SC:<member>          usual online hours: 168 bits (Monday 00:00 UTC
                           onward) as 42 hex digits   the member only
      HX:<member>          left out of the Hall of Fame: "1" ("" = shown)   officers
      HW:<month>           that month's Hall of Fame champions:
                           "quests=Name,Name;kills=Name" (Services/HallOfFame.lua)   officers
      HA:<month>           that month's champions were announced in guild chat:
                           "<time>" (the author announced them)   officers
      HC:<member>          their Hall of Fame numbers checked against the game:
                           "<time>;ok" or "<time>;bad;key=claimed/real,..."
                           (Services/HofCheck.lua)   officers (officer scope: only
                           officers ever receive it)
      IR:<member>          reminded to install the addon: "" (the time and who
                           are the record's own; kept 30 days)   anyone in the guild
      HF:<member>          Hall of Fame: their character statistics, all time,
                           this month and last (Services/HallOfFame.lua)   the member only

    Types with a ttl (or an expires function) expire: older records are
    deleted, left out of digests and repairs, and refused when they arrive.
]]
local _, ns = ...
local S = {}
ns.Sync = S

local PREFIX = "NootropicGM"
local PROTO = "5" -- 5: 2.1 (tags removed); 4: 2.0 (reviews, ratings and map positions removed); 3: batches, channel-only repair
S.PROTO = PROTO
S.FS = "\t"
local FS = "\t"
local US = "\031" -- separator inside audit values

S.BUCKETS = 16
S.AUDIT_SYNC_WINDOW = 30 * 86400 -- audit older than this isn't compared (retention differs per officer)
S.DIGEST_INTERVAL = 600          -- routine digest every 10 minutes
S.EXCHANGE_COOLDOWN = 120        -- at most one routine exchange every 2 minutes
S.BATCH_DELAY = 15               -- local changes are sent together after this many seconds
S.DUMP_SUPPRESS = 60             -- don't re-send a bucket someone just re-sent
S.BYTES_PER_SEC = 600            -- gentler than ChatThrottleLib's 800
S.BURST = 1800
S.CHUNK = 200
S.MAX_MSG = 250

S.TYPES = {
    M  = { scope = "guild",   officer = true, label = "Main / Alt" },
    MS = { scope = "guild",   officer = true, self = true, label = "Spec" },
    RL = { scope = "guild",   officer = true, self = true, label = "Role" },
    MP = { scope = "guild",   officer = true, self = true, label = "Professions" },
    P  = { scope = "guild",   selfOnly = true, label = "Reported spec / professions" },
    L  = { scope = "officer", officer = true, label = "Officer log" },
    A  = { scope = "officer", officer = true, noAudit = true, label = "Audit" },
    DN = { scope = "guild",   anyone = true, label = "Do Not Whisper" },
    RS = { scope = "guild",   anyone = true, noAudit = true, ttl = 14 * 86400, label = "Recruitment status" },
    AV = { scope = "guild",   selfOnly = true, noAudit = true, label = "Addon version" },
    GS = { scope = "guild",   officer = true, label = "Guild setting" },
    CN = { scope = "guild",   officer = true, self = true, label = "Contact" },
    SC = { scope = "guild",   selfOnly = true, noAudit = true, label = "Usually online" },
    RP = { scope = "guild",   selfOnly = true, noAudit = true, low = true, label = "Recipes" },
    RR = { scope = "guild",   selfOnly = true, noAudit = true, label = "Raid readiness" },
    PS = { scope = "guild",   selfOnly = true, noAudit = true, label = "Sharing choices" },
    HF = { scope = "guild",   selfOnly = true, noAudit = true, low = true, label = "Hall of Fame" },
    IR = { scope = "guild",   anyone = true, noAudit = true, ttl = 30 * 86400, label = "Install reminder" },
    HX = { scope = "guild",   officer = true, label = "Hidden from Hall of Fame" },
    HW = { scope = "guild",   officer = true, noAudit = true, label = "Hall of Fame champions" },
    HA = { scope = "guild",   officer = true, noAudit = true, label = "Champions announced" },
    HC = { scope = "officer", officer = true, noAudit = true, label = "Hall of Fame check" },
    JN = { scope = "officer", officer = true, noAudit = true, label = "Joined" },
    RK = { scope = "officer", officer = true, noAudit = true, label = "Rank since" },
}
-- Audit entry kinds that aren't records: changes to the guild roster itself
-- (Services/RosterLog.lua). GM joined/left, GK promoted/demoted, LV level,
-- GN public/officer note, NC name change.
S.ROSTER_EVENTS = { GM = true, GK = true, LV = true, GN = true, NC = true }
S.EVENT_DEDUPE = 6 * 3600 -- event-log times are only known to the hour

-- Same event seen by two officers: same signature. nil for kinds that
-- don't need it (their ids already match).
function S.EventSig(typ, member, new)
    if typ ~= "GM" and typ ~= "GK" then return nil end
    if new == "rejoin" then new = "join" end
    return typ .. "|" .. (member or "") .. "|" .. (new or "")
end
local CHANNEL = { guild = "GUILD", officer = "OFFICER" }
-- Types whose key is not about one member.
local NO_MEMBER = { A = true, GS = true, HW = true, HA = true }

S.officers = {} -- players seen sending on the officer channel this session
S.stats = { sent = 0, received = 0, applied = 0, retries = 0, dropped = 0, refused = 0 }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function Now() return ns.DB:Now() end
local function Me() return ns.PlayerFullName() end

-- Simple string hash, kept below 2^32 (exact in Lua numbers).
local function Hash(str)
    local h = 5381
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967291 end
    return h
end
S.Hash = Hash

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Base36(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local out = {}
    while n > 0 do
        local d = n % 36
        table.insert(out, 1, B36:sub(d + 1, d + 1))
        n = math.floor(n / 36)
    end
    return table.concat(out)
end
S.Base36 = Base36

-- Values never contain tabs/newlines (message separators) or "|" (the
-- game's escape character, which would garble chat and text display).
local function Clean(v)
    return (tostring(v or ""):gsub("[\t\r\n]", " "):gsub(US, ""):gsub("|", "/"))
end
S.Clean = Clean

function S.ParseKey(key)
    local typ, rest = key:match("^(%u+):(.*)$")
    if not typ or not S.TYPES[typ] then return nil end
    local member
    if typ == "L" or typ == "RP" then
        member = rest:match("^([^:]+):")
    elseif not NO_MEMBER[typ] then
        member = rest
    end
    return typ, member, rest
end

------------------------------------------------------------------------
-- Names without shard tags (WoW: Forever; see ns.NormalizeName)
-- Older copies of the addon still send "Name-<shard>"; every key, author
-- and name inside a value is brought to the plain name before it's checked
-- or stored, so everyone's copy keeps one record per person.
------------------------------------------------------------------------
local function CN(name)
    if not name or name == "" then return name end
    return ns.NormalizeName(name) or name
end
S.CanonName = CN

-- key -> the same key with plain names
function S.CanonKey(key)
    if not ns.NO_REALMS then return key end
    local typ, rest = key:match("^(%u+):(.*)$")
    if not typ or NO_MEMBER[typ] then return key end
    if typ == "L" or typ == "RP" then
        local member, tail = rest:match("^([^:]+):(.*)$")
        if not member then return key end
        return typ .. ":" .. CN(member) .. ":" .. tail
    end
    return typ .. ":" .. CN(rest)
end

-- Names inside values: mains, who invited or promoted, audit entries.
function S.CanonValue(typ, v)
    if not ns.NO_REALMS or not v or v == "" then return v end
    if typ == "M" then return CN(v) end
    if typ == "JN" then
        local t, by = v:match("^(%d+);(.*)$")
        if t then return t .. ";" .. (by ~= "" and CN(by) or "") end
    elseif typ == "RK" then
        local t, rank, by = v:match("^(%d+);([^;]*);(.*)$")
        if t then return t .. ";" .. rank .. ";" .. (by ~= "" and CN(by) or "") end
    elseif typ == "A" then
        local f = ns.Split(v, US)
        if #f >= 4 then
            f[1] = CN(f[1])
            if f[2] == "M" then f[3], f[4] = CN(f[3]), CN(f[4]) end
            return table.concat(f, US)
        end
    end
    return v
end

-- (key, rec) -> plain-name key and the record with its author and values tidied
function S.Canon(key, rec)
    if not ns.NO_REALMS then return key, rec end
    local ck = S.CanonKey(key)
    local typ = ck:match("^(%u+):")
    rec.a = CN(rec.a)
    rec.v = S.CanonValue(typ, rec.v)
    return ck, rec
end

-- One pass over saved data from before 2.7.2: records, private notes,
-- recruit history and your own per-character settings move to plain names.
-- Where two records become one, the newer wins (the same rule as sync), so
-- every copy ends up identical.
function S:CanonicalizeSaved()
    local g = ns.DB:Guild()
    if not ns.NO_REALMS or not g or g.realmless then return 0 end
    local moved = 0
    for _, scope in ipairs({ "guild", "officer" }) do
        local store = self:Store(scope)
        local out = {}
        for key, rec in pairs(store) do
            local before = key .. "\0" .. tostring(rec.a) .. "\0" .. tostring(rec.v)
            local ck, r = S.Canon(key, rec)
            if ck .. "\0" .. tostring(r.a) .. "\0" .. tostring(r.v) ~= before then moved = moved + 1 end
            local cur = out[ck]
            if not cur or S.Newer(r, cur) then out[ck] = r end
        end
        for k in pairs(store) do store[k] = nil end
        for k, r in pairs(out) do store[k] = r end
    end
    local function rekey(t, merge)
        if type(t) ~= "table" then return end
        local keys = {}
        for k in pairs(t) do if type(k) == "string" then keys[#keys + 1] = k end end
        for _, k in ipairs(keys) do
            local ck = CN(k)
            if ck ~= k then
                local v = t[k]
                t[k] = nil
                if t[ck] == nil then t[ck] = v elseif merge then merge(t[ck], v) end
                moved = moved + 1
            end
        end
    end
    rekey(g.members, function(cur, m)
        if m.note and m.note ~= "" and m.note ~= cur.note then
            cur.note = (cur.note and cur.note ~= "") and (cur.note .. " / " .. m.note) or m.note
        end
    end)
    if g.recruit then rekey(g.recruit.people) end
    local s = ns.DB:Settings()
    rekey(s.schedules)
    rekey(s.hof)
    g.realmless = true
    self.auditCache = nil
    return moved
end

-- When a record stops being kept (server time), or nil when it never expires.
function S:ExpiresAt(key, rec)
    local typ = S.ParseKey(key)
    if not typ then return nil end
    local def = S.TYPES[typ]
    return def.ttl and rec.t + def.ttl or nil
end

local function Newer(a, b)
    if a.t ~= b.t then return a.t > b.t end
    local aa, ba = a.a or "", b.a or ""
    if aa ~= ba then return aa > ba end
    return (a.v or "") > (b.v or "")
end
S.Newer = Newer

function S:Store(scope)
    local g = ns.DB:Guild()
    if not g then return nil end
    g.sync = g.sync or {}
    g.sync[scope] = g.sync[scope] or {}
    return g.sync[scope]
end

function S:Get(key)
    local typ = S.ParseKey(key)
    if not typ then return nil end
    local store = self:Store(S.TYPES[typ].scope)
    return store and store[key]
end

function S:Value(key)
    local rec = self:Get(key)
    return rec and rec.v
end

------------------------------------------------------------------------
-- Permissions
------------------------------------------------------------------------
function S:CanWrite(key)
    local typ, member, rest = S.ParseKey(key)
    if not typ then return false end
    local def = S.TYPES[typ]
    if def.selfOnly then return member == Me() end
    if def.anyone then return IsInGuild() end -- (DN removal is checked in RC:RemoveDNW)
    -- your own profile: the Guild Master decides (everyone by default)
    if def.self and member == Me() and ns.DB:HasPerm("ownprofile") then return true end
    -- permissions only the Guild Master changes
    if typ == "GS" and rest:sub(1, 5) == "perm_" then return ns.DB:IsGuildMaster() end
    -- what the Guild Master hands out per rank (Options > Officers > Permissions)
    local perm = def.scope == "guild" and ns.DB.PERM_BY_TYPE[typ]
    if perm then return ns.DB:HasPerm(perm) end
    if def.officer and ns.IsOfficer() then return true end
    return false
end

------------------------------------------------------------------------
-- Who may send a record. A record's author (rec.a) is only what the sender
-- claims; the sender is the one name the game vouches for. So:
--   * the author must be allowed to write the record (rank, permissions,
--     their own profile), checked against the guild roster
--   * a record someone else wrote may only be passed on (repair) by an
--     officer; the game only lets officer ranks send on the officer channel,
--     so S.officers can't be faked
--   * Guild Master permission settings must name the current Guild Master
--     as author, whoever passes them on
-- Without this any guildmate could forge permission changes or anyone's
-- profile with one hand-made addon message.
------------------------------------------------------------------------
local function Same(a, b) return a and b and a:lower() == b:lower() end

local function RosterEntry(name)
    if not name then return nil end
    local e = ns.Roster.byName[name]
    if e then return e end
    local lower = name:lower()
    for full, entry in pairs(ns.Roster.byName) do
        if full:lower() == lower then return entry end
    end
end

-- A player we know to be an officer: seen on the officer channel this
-- session, or you (when you are one).
function S:KnownOfficer(name)
    if not name then return false end
    if Same(name, Me()) then return ns.IsOfficer() end
    for who in pairs(self.officers) do
        if Same(who, name) then return true end
    end
    return false
end

local function IsGuildMaster(name)
    local e = RosterEntry(name)
    return e ~= nil and e.rankIndex == 0
end

-- Would `name` be allowed to write this record themselves?
function S:MayAuthor(name, typ, member, rest)
    local def = S.TYPES[typ]
    if not (def and name and name ~= "") then return false end
    if def.anyone then return RosterEntry(name) ~= nil end
    if def.selfOnly then return Same(name, member) end
    if typ == "GS" and rest:sub(1, 5) == "perm_" then return IsGuildMaster(name) end
    if def.self and Same(name, member) and self:RankMay(name, "ownprofile") then return true end
    local e = RosterEntry(name)
    if e and e.rankIndex == 0 then return true end
    local perm = def.scope == "guild" and ns.DB.PERM_BY_TYPE[typ]
    if perm then
        local set = ns.DB:PermRanks(perm)
        if set then return e ~= nil and set[e.rankIndex] == true end
        local pdef = ns.DB:PermDef(perm)
        if pdef and pdef.everyone then return e ~= nil end
    end
    if def.officer then return self:KnownOfficer(name) end
    return false
end

-- May `name` (a guildmate) do what the Guild Master allows for `perm`?
function S:RankMay(name, perm)
    local e = RosterEntry(name)
    if not e then return false end
    if e.rankIndex == 0 then return true end
    local set = ns.DB:PermRanks(perm)
    if set then return set[e.rankIndex] == true end
    local pdef = ns.DB:PermDef(perm)
    if pdef and pdef.everyone then return true end
    return self:KnownOfficer(name)
end

function S:SenderAllowed(typ, member, rest, def, rec, ctx)
    if def.scope == "officer" then return true end -- officer channel: officers only, by the game
    local sender, author = ctx.sender, rec.a
    -- anyone may put someone on the Do Not Whisper list; taking them off
    -- needs the recruit permission
    if typ == "DN" and (rec.v or "") == "" then
        return self:RankMay(author, "recruit") and (Same(sender, author) or self:KnownOfficer(sender))
    end
    -- install reminders say who sent them: only that person (or an officer
    -- passing it on) may send one, so nobody can block reminders for the
    -- whole guild in someone else's name
    if typ == "IR" then return Same(sender, author) or self:KnownOfficer(sender) end
    if def.anyone then return true end
    if typ == "GS" and rest:sub(1, 5) == "perm_" then
        return IsGuildMaster(author) and (Same(sender, author) or self:KnownOfficer(sender))
    end
    if Same(sender, author) then return self:MayAuthor(author, typ, member, rest) end
    -- passing on someone else's record: officers only, and self-only
    -- records must still be the member's own
    if not self:KnownOfficer(sender) then return false end
    if def.selfOnly and not Same(author, member) then return false end
    return true
end

-- Limits on what one guildmate can add (not who may write what, which is
-- SenderAllowed): a hand-made client could otherwise flood everyone's saved
-- data with records it's allowed to write (its own recipe lists under
-- made-up professions, Do Not Whisper entries...).
S.MAX_VALUE = 4000            -- bytes in one value (ours are far smaller)
S.MAX_PROFESSIONS = 12        -- recipe lists (RP) per member
S.NEW_KEYS_PER_WINDOW = 500   -- new records one non-officer may add...
S.NEW_KEYS_WINDOW = 600       -- ...per 10 minutes
local newKeys = {}            -- sender -> { count, since }

function S:WithinLimits(typ, member, rest, rec, ctx, store)
    if #(rec.v or "") > self.MAX_VALUE then return false end
    if (typ == "HW" or typ == "HA") and not rest:match("^%d%d%d%d%d%d$") then return false end
    -- reminders only about guildmates, holding the time they were sent
    if typ == "IR" then
        if not RosterEntry(member) then return false end
        local v = rec.v or ""
        if v ~= "" and not (v:match("^%d+$") and math.abs(tonumber(v) - rec.t) < 86400) then return false end
    end
    if typ == "RP" then
        if not rest:match("^[^:]+:%d+$") then return false end
        if not store[ctx.key] then
            local prefix, n = "RP:" .. member .. ":", 0
            for key in pairs(store) do
                if key:sub(1, #prefix) == prefix then n = n + 1 end
            end
            if n >= self.MAX_PROFESSIONS then return false end
        end
    end
    if not store[ctx.key] and not self:KnownOfficer(ctx.sender) then
        local now = GetTime()
        local c = newKeys[ctx.sender]
        if not c or now - c.since > self.NEW_KEYS_WINDOW then
            c = { count = 0, since = now }
            newKeys[ctx.sender] = c
        end
        if c.count >= self.NEW_KEYS_PER_WINDOW then return false end
        c.count = c.count + 1
    end
    return true
end

-- Should we accept this record from someone else?
-- Counts a refused record and remembers the last one, for /ngm sync.
-- What arrived from each guildmate this session (for /ngm sync <name>)
S.from = {}
function S:From(who)
    local f = self.from[who]
    if not f then
        f = { messages = 0, kinds = {}, applied = 0, refused = 0, older = 0 }
        self.from[who] = f
    end
    return f
end

function S:Refuse(ctx, rec, why)
    self.stats.refused = (self.stats.refused or 0) + 1
    if ctx.sender then self:From(ctx.sender).refused = self:From(ctx.sender).refused + 1 end
    self.lastRefused = { sender = ctx.sender, key = ctx.key, author = rec.a, why = why, at = Now() }
    return false
end

function S:Accept(typ, member, def, rec, ctx)
    if def.scope == "officer" then
        -- the game only delivers the officer channel to officer ranks
        if ctx.channel ~= "OFFICER" or not ns.IsOfficer() then return false end
    elseif ctx.channel ~= "GUILD" then
        return false
    end
    if def.selfOnly and rec.a ~= member then return self:Refuse(ctx, rec, "its author isn't the member it's about") end
    if not self:SenderAllowed(typ, member, select(3, S.ParseKey(ctx.key)) or "", def, rec, ctx) then
        return self:Refuse(ctx, rec, "the sender may not write it")
    end
    if rec.t > Now() + 300 then return self:Refuse(ctx, rec, "its time is in the future (clock?)") end
    if typ == "A" and rec.t < Now() - self:RetentionSeconds() then return false end
    local expires = self:ExpiresAt(ctx.key, rec)
    if expires and expires < Now() then return false end
    if not self:WithinLimits(typ, member, select(3, S.ParseKey(ctx.key)) or "", rec, ctx, self:Store(def.scope) or {}) then
        return self:Refuse(ctx, rec, "over a size or rate limit")
    end
    return true
end

-- Records left out of digests and repairs: old audit entries (each officer
-- keeps a different amount) and anything past its expiry.
function S:Excluded(key, rec, now)
    now = now or Now()
    if key:sub(1, 2) == "A:" then return rec.t < now - self.AUDIT_SYNC_WINDOW end
    local expires = self:ExpiresAt(key, rec)
    return expires ~= nil and expires < now
end

-- Deletes records past their expiry.
function S:PruneExpired()
    local now, removed = Now(), 0
    for _, scope in ipairs({ "guild", "officer" }) do
        local store = self:Store(scope)
        if store then
            local dead = {}
            for key, rec in pairs(store) do
                local expires = self:ExpiresAt(key, rec)
                if expires and expires < now then dead[#dead + 1] = key end
            end
            for _, key in ipairs(dead) do
                store[key] = nil
                removed = removed + 1
            end
        end
    end
    if removed > 0 then ns:Fire("RECRUITS_CHANGED") end
    return removed
end

------------------------------------------------------------------------
-- Writing and applying
------------------------------------------------------------------------
-- Changes a record locally and broadcasts it.
-- opts: migration (no audit/broadcast), author, force (skip permission)
function S:Set(key, value, opts)
    opts = opts or {}
    if not ns.DB:Guild() then return nil, "You are not in a guild." end
    local typ = S.ParseKey(key)
    if not typ then return nil, "Unknown record." end
    if not opts.force and not self:CanWrite(key) then
        return nil, "Only officers can change that."
    end
    value = Clean(value)
    local store = self:Store(S.TYPES[typ].scope)
    local cur = store[key]
    if cur and cur.v == value then return true end
    local t = opts.time or Now()
    if cur and cur.t >= t then t = cur.t + 1 end
    local rec = { v = value, t = t, a = opts.author or Me() }
    if not opts.migration and not opts.noBatch then rec.b = self:CurrentBatch() end
    self:Apply(key, rec, { origin = "local", migration = opts.migration })
    if not opts.migration then self:QueueOutgoing(key) end
    self:FlushNotify()
    return true
end

------------------------------------------------------------------------
-- Batching: changes made close together are sent (and audited) as one group
------------------------------------------------------------------------
S.outbox = {}

function S:CurrentBatch()
    if not self.batchId then
        self.batchId = Base36(Now()) .. Base36(math.random(0, 46655))
    end
    return self.batchId
end

function S:QueueOutgoing(key)
    self.outbox[key] = true
    if not self.outboxTimer then
        self.outboxTimer = true
        C_Timer.After(self.BATCH_DELAY, function() S:FlushOutgoing() end)
    end
end

-- Sends everything queued, newest version of each record.
function S:FlushOutgoing()
    self.outboxTimer = false
    self.batchId = nil
    local keys = {}
    for key in pairs(self.outbox) do keys[#keys + 1] = key end
    wipe(self.outbox)
    table.sort(keys)
    for _, key in ipairs(keys) do
        local rec = self:Get(key)
        if rec then self:Broadcast(key, rec) end
    end
    return #keys
end

-- Stores a record if it's newer than ours. Returns true when applied.
function S:Apply(key, rec, ctx)
    local typ, member = S.ParseKey(key)
    if not typ then return false end
    local def = S.TYPES[typ]
    local store = self:Store(def.scope)
    if not store then return false end
    rec.t = tonumber(rec.t) or 0
    rec.v = rec.v or ""
    ctx.key = key
    -- recruitment statuses are only kept by members who may recruit
    if ctx.origin == "remote" and typ == "RS" and not self:MayRecruit() then return false end
    if ctx.origin == "remote" and not self:Accept(typ, member, def, rec, ctx) then return false end
    local cur = store[key]
    if cur and not Newer(rec, cur) then
        if ctx.origin == "remote" and ctx.sender then self:From(ctx.sender).older = self:From(ctx.sender).older + 1 end
        return false
    end
    store[key] = rec
    if ctx.origin == "remote" and ctx.sender then self:From(ctx.sender).applied = self:From(ctx.sender).applied + 1 end
    self:Materialize(typ, key, member, rec)
    if not def.noAudit and not ctx.migration and ns.IsOfficer() then
        self:Audit(typ, key, member, cur, rec)
    end
    self.stats.applied = self.stats.applied + 1
    return true
end

------------------------------------------------------------------------
-- Values <-> the addon's working data
------------------------------------------------------------------------
local Codec = {}
S.Codec = Codec

function Codec.ParseSet(v)
    local set = {}
    for id in (v or ""):gmatch("[^,]+") do set[id] = true end
    return set
end

function Codec.Profs(list)
    local parts = {}
    for _, p in ipairs(list or {}) do
        parts[#parts + 1] = ("%s:%d"):format((p.name:gsub("[:,;]", "")), p.rank or 0)
    end
    return table.concat(parts, ",")
end
function Codec.ParseProfs(v)
    local list = {}
    for chunk in (v or ""):gmatch("[^,]+") do
        local name, rank = chunk:match("^([^:]+):?(%d*)$")
        if name then list[#list + 1] = { name = name, rank = tonumber(rank) or 0 } end
    end
    return list
end

-- Addon-reported data: "spec;dist;name:rank:max:icon,..."
function Codec.Report(snap)
    local parts = {}
    for i, p in ipairs(snap.profs or {}) do
        if i > 6 then break end
        parts[#parts + 1] = ("%s:%d:%d:%s"):format((p.name:gsub("[:,;]", "")), p.rank or 0, p.max or 0, p.icon and tostring(p.icon) or "")
    end
    return ("%s;%s;%s"):format(Clean(snap.spec or ""):gsub(";", ""), Clean(snap.dist or ""):gsub(";", ""), table.concat(parts, ","))
end
function Codec.ParseReport(v)
    local spec, dist, profs = (v or ""):match("^([^;]*);([^;]*);(.*)$")
    if not spec then return nil end
    local data = { spec = spec ~= "" and spec or nil, dist = dist ~= "" and dist or nil, profs = {} }
    for chunk in profs:gmatch("[^,]+") do
        local name, rank, max, icon = chunk:match("^([^:]*):(%d*):(%d*):?(%d*)$")
        if name and name ~= "" then
            data.profs[#data.profs + 1] = { name = name, rank = tonumber(rank) or 0, max = tonumber(max) or 0, icon = tonumber(icon) }
        end
    end
    return data
end

-- Officer log: "created;creator;text" ("" = deleted)
function Codec.Log(created, creator, text)
    return ("%d;%s;%s"):format(created, Clean(creator):gsub(";", ""), Clean(text))
end
function Codec.ParseLog(v)
    local created, creator, text = (v or ""):match("^(%d+);([^;]*);(.*)$")
    if not created then return nil end
    return { ts = tonumber(created), author = creator, text = text }
end

local pending = { members = {}, links = false, audit = false }

function S:Notify(kind, member)
    if kind == "member" then
        if member then pending.members[member] = true end
    else
        pending[kind] = true
    end
    if not self.notifyQueued then
        self.notifyQueued = true
        C_Timer.After(0.05, function() S:FlushNotify() end)
    end
end

function S:FlushNotify()
    self.notifyQueued = false
    local p = { members = pending.members, links = pending.links, audit = pending.audit }
    pending.members, pending.links, pending.audit = {}, false, false
    if p.links then ns:Fire("LINKS_CHANGED") end
    for member in pairs(p.members) do ns:Fire("MEMBER_CHANGED", member) end
    if p.audit then
        self.auditCache = nil
        ns:Fire("AUDIT_CHANGED")
    end
end

function S:Materialize(typ, key, member, rec)
    local v = rec.v
    if typ == "GS" then
        ns.Debounce("guildsettings", 0.1, function() ns:Fire("GUILD_SETTINGS_CHANGED") end)
        return
    elseif typ == "RP" then
        ns.Debounce("recipeschanged", 0.3, function() ns:Fire("RECIPES_CHANGED") end)
        return
    elseif typ == "HF" or typ == "HX" or typ == "HW" or typ == "HA" or typ == "HC" then
        ns.Debounce("hofchanged", 0.5, function() ns:Fire("HALL_OF_FAME_CHANGED") end)
        return
    elseif typ == "IR" then
        ns.Debounce("reminderschanged", 0.3, function() ns:Fire("MEMBER_CHANGED") end)
        return
    elseif typ == "DN" or typ == "RS" then
        -- Do Not Whisper entries are about people outside the guild: no member record
        ns.Debounce("dnwchanged", 0.1, function() ns:Fire("RECRUITS_CHANGED") end)
        return
    elseif typ == "A" then
        self.auditCache = nil
        self:Notify("audit")
        return
    end
    local m = ns.DB:EnsureMember(member)
    if not m then return end
    if typ == "M" then
        m.main = (v ~= "" and v ~= member) and v or nil
        self:Notify("links")
    elseif typ == "MS" then
        m.spec = v ~= "" and v or nil
    elseif typ == "RL" then
        m.roles = v ~= "" and v or nil
    elseif typ == "MP" then
        local list = Codec.ParseProfs(v)
        m.profs = #list > 0 and list or nil
    elseif typ == "P" then
        local data = v ~= "" and Codec.ParseReport(v) or nil
        if v == "" then m.auto = nil end -- they stopped sharing it
        if data then
            data.ts = rec.t
            m.auto = data
        end
    elseif typ == "CN" then
        m.contact = v ~= "" and v or nil
    elseif typ == "SC" then
        m.schedule = v ~= "" and v or nil
    elseif typ == "AV" then
        m.version = v ~= "" and v or nil
        ns.Debounce("versioncheck", 1, function() if ns.Roster.CheckVersion then ns.Roster:CheckVersion() end end)
    elseif typ == "JN" then
        local t, by = v:match("^(%d+);(.*)$")
        m.joined = t and { t = tonumber(t), by = by ~= "" and by or nil } or nil
    elseif typ == "RK" then
        local t, rank, by = v:match("^(%d+);([^;]*);(.*)$")
        m.rankSince = t and { t = tonumber(t), rank = rank ~= "" and rank or nil, by = by ~= "" and by or nil } or nil
    elseif typ == "L" then
        local id = key:match("^L:[^:]+:(.+)$")
        m.log = m.log or {}
        local entry = Codec.ParseLog(v)
        if entry then
            entry.id, entry.upd = id, rec.t
            m.log[id] = entry
        else
            m.log[id] = { id = id, del = true, upd = rec.t, ts = rec.t, text = "" }
        end
    end
    self:Notify("member", member)
end

-- Rebuilds the working data from records (after loading or migrating).
function S:RebuildAll()
    local g = ns.DB:Guild()
    if not g then return end
    for _, m in pairs(g.members) do
        m.tags, m.main, m.spec, m.profs, m.auto, m.log, m.version = nil, nil, nil, nil, nil, nil, nil
        m.rating = nil
        m.schedule, m.contact = nil, nil
        m.joined, m.rankSince = nil, nil
        m.about, m.status, m.statusAt, m.pronouns = nil, nil, nil, nil
    end
    for _, scope in ipairs({ "guild", "officer" }) do
        for key, rec in pairs(self:Store(scope)) do
            local typ, member = S.ParseKey(key)
            if typ then self:Materialize(typ, key, member, rec) end
        end
    end
    self:FlushNotify()
end

------------------------------------------------------------------------
-- Audit trail
------------------------------------------------------------------------
function S:RetentionSeconds()
    local days = ns.DB:Settings().auditDays or 30
    return days * 86400
end

-- Compact form of a reported-data value for the audit: spec + profession names.
local function ReportSummary(v)
    local d = Codec.ParseReport(v)
    if not d then return "" end
    local names = {}
    for _, p in ipairs(d.profs) do names[#names + 1] = p.name end
    table.sort(names)
    return (d.spec or "") .. ";" .. table.concat(names, ",")
end

function S:Audit(typ, key, member, cur, rec)
    local old = cur and cur.v or ""
    local new = rec.v
    if typ == "P" then
        old, new = cur and ReportSummary(old) or "", ReportSummary(new)
    end
    if old == new then return end
    local store = self:Store("officer")
    -- Same id on every officer's client, so copies of one change merge.
    local id = Base36(Hash(key .. "@" .. rec.t .. "@" .. (rec.a or ""))) .. Base36(rec.t)
    local akey = "A:" .. id
    if store[akey] then return end
    store[akey] = {
        v = table.concat({ member or "", typ, Clean(old), Clean(new), key:sub(#typ + 2), rec.b or "" }, US),
        t = rec.t, a = rec.a or "",
    }
    self.auditCache = nil
    self:Notify("audit")
end

-- Adds an audit entry that isn't about a record (a roster change), and
-- sends it to the other officers. False when it's already there.
function S:AddAuditEntry(id, t, author, member, typ, old, new, ref, batch)
    if not ns.IsOfficer() then return false end
    local store = self:Store("officer")
    if not store then return false end
    local akey = "A:" .. id
    if store[akey] then return false end
    store[akey] = {
        v = table.concat({ member or "", typ, Clean(old), Clean(new), Clean(ref or ""), batch or "" }, US),
        t = math.floor(t), a = author or "",
    }
    self.auditCache = nil
    self:Notify("audit")
    self:QueueOutgoing(akey)
    return true
end

-- Decoded audit entries, newest first: { id, t, author, member, typ, old, new, ref }
function S:AuditEntries()
    if self.auditCache then return self.auditCache end
    local out = {}
    local store = self:Store("officer")
    if store then
        for key, rec in pairs(store) do
            if key:sub(1, 2) == "A:" then
                local f = ns.Split(rec.v, US)
                local member, typ, old, new, ref, batch = f[1], f[2], f[3], f[4], f[5], f[6]
                if typ and typ ~= "" then
                    out[#out + 1] = {
                        id = key:sub(3), t = rec.t, author = rec.a, member = member ~= "" and member or nil,
                        typ = typ, old = old or "", new = new or "", ref = ref,
                        batch = (batch and batch ~= "") and batch or nil,
                    }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return a.id > b.id
    end)
    -- one event-log event noticed an hour apart by two officers: keep one
    local kept, last = {}, {}
    for _, e in ipairs(out) do
        local sig = S.EventSig(e.typ, e.member, e.new)
        if not (sig and last[sig] and last[sig] - e.t <= S.EVENT_DEDUPE) then
            kept[#kept + 1] = e
            if sig then last[sig] = e.t end
        end
    end
    self.auditCache = kept
    return kept
end

function S:PruneAudit()
    local store = self:Store("officer")
    if not store then return end
    local cutoff = Now() - self:RetentionSeconds()
    local removed = 0
    for key, rec in pairs(store) do
        if key:sub(1, 2) == "A:" and rec.t < cutoff then
            store[key] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        self.auditCache = nil
        ns:Fire("AUDIT_CHANGED")
    end
    return removed
end

------------------------------------------------------------------------
-- Digests (repair)
------------------------------------------------------------------------
local function Bucket(key) return Hash(key) % S.BUCKETS + 1 end

------------------------------------------------------------------------
-- Lanes: what's compared together.
--   guild    guild records, except recruitment statuses
--   officer  officer records (officer channel)
--   recruit  recruitment statuses (RS), only between members who may
--            recruit: 600+ of them churn constantly, and nobody else needs
--            them, so they no longer upset everyone's guild checksums
------------------------------------------------------------------------
local function LaneOf(key)
    local typ = key:match("^(%u+):")
    if typ == "RS" then return "recruit" end
    local def = typ and S.TYPES[typ]
    return def and def.scope
end
S.LaneOf = LaneOf

local function StoreScope(lane) return lane == "officer" and "officer" or "guild" end

function S:MayRecruit()
    return ns.Recruit and ns.Recruit.MayRecruit and ns.Recruit:MayRecruit() and true or false
end

-- May we (and our peer) use this lane on this channel?
function S:LaneOpen(lane, channel)
    if lane == "officer" then return channel == "OFFICER" and ns.IsOfficer() end
    if lane == "guild" then return channel == "GUILD" end
    if lane == "recruit" then return channel == "GUILD" and self:MayRecruit() end
    return false
end

function S:Digest(scope)
    local sums = {}
    for i = 1, self.BUCKETS do sums[i] = 0 end
    -- "legacy" is the whole guild store, as copies before 2.10 compare it
    local store = self:Store(StoreScope(scope))
    if not store then return sums end
    local now = Now()
    for key, rec in pairs(store) do
        if (scope == "legacy" or LaneOf(key) == scope) and not self:Excluded(key, rec, now) then
            local b = Bucket(key)
            -- the value is included so same-time copies with different contents still get reconciled
            sums[b] = (sums[b] + Hash(key .. FS .. rec.t .. FS .. (rec.a or "") .. FS .. (rec.v or ""))) % 4294967291
        end
    end
    return sums
end

local function EncodeDigest(sums)
    local parts = {}
    for i, s in ipairs(sums) do parts[i] = Base36(s) end
    return table.concat(parts, ",")
end

local function DecodeDigest(str)
    local sums = {}
    for part in (str or ""):gmatch("[^,]+") do sums[#sums + 1] = tonumber(part, 36) or -1 end
    return sums
end

-- Broadcast our digests so peers can tell us what we're missing (and vice versa).
function S:Exchange(force)
    if not IsInGuild() or not ns.DB:Guild() then return false end
    local now = GetTime()
    local since = now - (self.lastExchange or -1e9)
    if since < (force and 10 or self.EXCHANGE_COOLDOWN) then return false end
    self.lastExchange = now
    -- "g" is the guild lane (2.10+); "guild" the old whole-store checksums,
    -- only while someone online still runs an older copy
    self:Send(table.concat({ PROTO, "D", "g", EncodeDigest(self:Digest("guild")) }, FS), "GUILD", nil, "high")
    if not self:AllOnlineCurrent() then
        self:Send(table.concat({ PROTO, "D", "guild", EncodeDigest(self:Digest("legacy")) }, FS), "GUILD", nil, "high")
    end
    if ns.IsOfficer() then
        self:Send(table.concat({ PROTO, "D", "officer", EncodeDigest(self:Digest("officer")) }, FS), "OFFICER", nil, "high")
    end
    if self:MayRecruit() then
        self:Send(table.concat({ PROTO, "D", "recruit", EncodeDigest(self:Digest("recruit")) }, FS), "GUILD", nil, "high")
    end
    return true
end

S.dumped = { guild = {}, officer = {} } -- bucket -> GetTime() someone last re-sent it

S.LIST_VERSION = "2.10.0" -- copies from this version on compare record lists

-- Does `who` run a copy that understands record lists ("L")?
function S:PeerHasLists(who)
    local rec = self:Get("AV:" .. who)
    return rec ~= nil and ns.CompareVersions and ns.CompareVersions(rec.v or "", self.LIST_VERSION) >= 0
end

S.listAsked = {} -- "lane|who" -> GetTime() we last asked them

function S:OnDigest(scope, digest, sender, channel)
    if scope == "guild" then
        -- old-style checksums: a 2.10+ copy also sends "g", which we use instead
        if channel ~= "GUILD" or self:PeerHasLists(sender) then return end
        return self:OnLegacyDigest("legacy", "guild", DecodeDigest(digest))
    end
    if scope == "g" then scope = "guild" end
    if not self:LaneOpen(scope, channel) then return end
    local theirs = DecodeDigest(digest)
    local diff = self:DiffBuckets(scope, theirs)
    if #diff == 0 then return end
    -- "g" and "recruit" only come from 2.10+ copies
    if scope ~= "officer" or self:PeerHasLists(sender) then
        -- exact: send them our record list for the differing groups; they
        -- send back only what we're missing, and ask for what they are
        local k = scope .. "|" .. sender
        if GetTime() - (self.listAsked[k] or -1e9) < self.LIST_COOLDOWN then return end
        self.listAsked[k] = GetTime()
        C_Timer.After(1 + math.random() * 4, function()
            local still = S:DiffBuckets(scope, theirs, diff)
            if #still > 0 then S:SendList("q", scope, sender, still) end
        end)
        return
    end
    return self:OnLegacyDigest(scope, scope, theirs)
end

-- An older copy: the old way (re-send whole groups). A short random wait,
-- so when several clients notice the same gap only the first one re-sends
-- it (the others see its B marker and skip).
function S:OnLegacyDigest(digestScope, scope, theirs)
    local diff = self:DiffBuckets(digestScope, theirs)
    if #diff == 0 then return end
    C_Timer.After(2 + math.random() * 6, function()
        local still = S:DiffBuckets(digestScope, theirs, diff)
        local now = GetTime()
        local send = {}
        for _, b in ipairs(still) do
            if now - (S.dumped[scope][b] or -1e9) > S.DUMP_SUPPRESS then send[#send + 1] = b end
        end
        if #send > 0 then S:SendBuckets(scope, send) end
        -- they may have newer data than us: let them compare against ours
        S:Exchange(true)
    end)
end

------------------------------------------------------------------------
-- Record lists (2.10+). For each differing group, a compact list of what's
-- in it: "<key hash>.<time>.<version hash>" per record. The other copy then
-- sends exactly the records we lack or have older, and (for a query) sends
-- back its own list so we can send what it lacks.
--   PROTO L q|a <lane> <target> <bucket>:<entry>,<entry>;<bucket>:...
-- q (query) is answered with records plus an "a" list; an "a" list is
-- answered with records only, so it never loops.
------------------------------------------------------------------------
S.LIST_COOLDOWN = 60
S.LIST_MAX = 2600 -- characters of list per message (chunked under MAX_PARTS)

local function Entry(key, rec)
    return Base36(Hash(key)) .. "." .. Base36(rec.t) .. "." .. Base36(Hash((rec.a or "") .. FS .. (rec.v or "")) % 1679616)
end

-- Our records of a lane in the given buckets: { [bucket] = { key = rec } }
function S:LaneRecords(lane, buckets)
    local want, out = {}, {}
    for _, b in ipairs(buckets) do want[b] = true; out[b] = {} end
    local now = Now()
    for key, rec in pairs(self:Store(StoreScope(lane)) or {}) do
        local b = Bucket(key)
        if want[b] and LaneOf(key) == lane and not self:Excluded(key, rec, now) then out[b][key] = rec end
    end
    return out
end

function S:SendList(mode, lane, target, buckets)
    local channel = lane == "officer" and "OFFICER" or "GUILD"
    local parts, size = {}, 0
    local function flush()
        if #parts == 0 then return end
        self:Send(table.concat({ PROTO, "L", mode, lane, target, table.concat(parts, ";") }, FS), channel, nil, "high")
        parts, size = {}, 0
    end
    for b, recs in pairs(self:LaneRecords(lane, buckets)) do
        local entries = {}
        for key, rec in pairs(recs) do entries[#entries + 1] = Entry(key, rec) end
        table.sort(entries)
        -- a group too big for one message is split across several
        local chunk = {}
        local function emit()
            local text = b .. ":" .. table.concat(chunk, ",")
            if size + #text > self.LIST_MAX then flush() end
            parts[#parts + 1] = text
            size = size + #text + 1
            chunk = {}
        end
        for _, e in ipairs(entries) do
            chunk[#chunk + 1] = e
            if #chunk >= 120 then emit() end
        end
        emit()
    end
    flush()
end

local function ParseList(payload)
    local out = {}
    for group in (payload or ""):gmatch("[^;]+") do
        local b, list = group:match("^(%d+):(.*)$")
        b = tonumber(b)
        if b and b >= 1 and b <= S.BUCKETS then
            out[b] = out[b] or {}
            for e in list:gmatch("[^,]+") do
                local kh, t, vh = e:match("^(%w+)%.(%w+)%.(%w+)$")
                if kh then out[b][kh] = { t = tonumber(t, 36) or 0, vh = vh } end
            end
        end
    end
    return out
end
S.ParseList = ParseList

S.listAnswered = {} -- "lane|who" -> GetTime() we last answered their query

function S:OnList(mode, lane, target, payload, who, channel)
    if mode ~= "q" and mode ~= "a" then return end
    if not self:LaneOpen(lane, channel) or not Same(target, Me()) then return end
    if mode == "q" then
        local k = lane .. "|" .. who
        if GetTime() - (self.listAnswered[k] or -1e9) < 10 then return end
        self.listAnswered[k] = GetTime()
    end
    local theirs = ParseList(payload)
    local buckets = {}
    for b in pairs(theirs) do buckets[#buckets + 1] = b end
    if #buckets == 0 then return end
    local mine = self:LaneRecords(lane, buckets)
    -- officers pass on everything; in the recruit lane every recruiter does;
    -- everyone else only their own records
    local relayAll = lane == "officer" or lane == "recruit" or ns.IsOfficer()
    local me = Me()
    local channelName = lane == "officer" and "OFFICER" or "GUILD"
    local needBack = {}
    for b, recs in pairs(mine) do
        local seen = {}
        for key, rec in pairs(recs) do
            local kh = Base36(Hash(key))
            seen[kh] = true
            local t = theirs[b][kh]
            local myEntry = Entry(key, rec)
            local differs = not t or rec.t > t.t or (rec.t == t.t and myEntry:match("%.(%w+)$") ~= t.vh)
            if differs then
                local own = Same(rec.a, me)
                if own or relayAll then
                    self:Send(self:EncodeForWire(key, rec), channelName, nil, own and "high" or "bulk", self:EncodeRecord(key, rec))
                end
            end
            if t and (t.t > rec.t or (t.t == rec.t and myEntry:match("%.(%w+)$") ~= t.vh)) then needBack[b] = true end
        end
        for kh in pairs(theirs[b]) do
            if not seen[kh] then needBack[b] = true end
        end
    end
    if mode == "q" then
        local back = {}
        for b in pairs(needBack) do back[#back + 1] = b end
        if #back > 0 then self:SendList("a", lane, who, back) end
    end
end

------------------------------------------------------------------------
-- Compression (2.10+): big records (recipe lists, Hall of Fame) are sent
-- compressed ("Z") with the game's own Deflate + Base64, but only while
-- every guildmate online with the addon runs a copy that can read them.
------------------------------------------------------------------------
S.COMPRESS_OVER = 150

function S:CanCompress()
    local E = C_EncodingUtil
    if not (E and E.CompressString and E.DecompressString and E.EncodeBase64 and E.DecodeBase64) then return false end
    return self:AllOnlineCurrent()
end

-- Is every guildmate online with the addon on 2.10 or later? (cached 30 s)
function S:AllOnlineCurrent()
    local now = GetTime()
    if self.compressCheckedAt and now - self.compressCheckedAt < 30 then return self.compressOk end
    local ok = true
    for _, e in ipairs((ns.Roster and ns.Roster.members) or {}) do
        if e.online and e.hasAddon and not e.isSelf then
            if not (e.version and ns.CompareVersions and ns.CompareVersions(e.version, self.LIST_VERSION) >= 0) then
                ok = false
                break
            end
        end
    end
    self.compressCheckedAt, self.compressOk = now, ok
    return ok
end

-- The message for a record: compressed when that's worth it and safe.
function S:EncodeForWire(key, rec)
    local v = rec.v or ""
    if #v > self.COMPRESS_OVER and self:CanCompress() then
        local okC, packed = pcall(C_EncodingUtil.CompressString, v)
        local okB, text = false, nil
        if okC then okB, text = pcall(C_EncodingUtil.EncodeBase64, packed) end
        if okB and type(text) == "string" and #text + 20 < #v then
            return table.concat({ PROTO, "Z", key, tostring(rec.t), rec.a or "", rec.b or "", text }, FS)
        end
    end
    return self:EncodeRecord(key, rec)
end

local function Unpack(text)
    local E = C_EncodingUtil
    if not (E and E.DecodeBase64 and E.DecompressString) then return nil end
    local okB, packed = pcall(E.DecodeBase64, text)
    if not okB or type(packed) ~= "string" then return nil end
    local okD, v = pcall(E.DecompressString, packed)
    if not okD or type(v) ~= "string" or #v > S.MAX_VALUE then return nil end
    return v
end

function S:DiffBuckets(scope, theirs, only)
    local mine = self:Digest(scope)
    local out = {}
    local list = only
    if not list then
        list = {}
        for i = 1, self.BUCKETS do list[i] = i end
    end
    for _, b in ipairs(list) do
        if mine[b] ~= theirs[b] then out[#out + 1] = b end
    end
    return out
end

-- Re-broadcasts every record in the given buckets on the scope's channel.
function S:SendBuckets(scope, buckets)
    local store = self:Store(scope)
    if not store then return end
    if scope == "officer" and not ns.IsOfficer() then return end
    local channel = CHANNEL[scope]
    local want = {}
    local now = GetTime()
    for _, b in ipairs(buckets) do
        want[b] = true
        self.dumped[scope][b] = now
        self:Send(table.concat({ PROTO, "B", scope, tostring(b) }, FS), channel, nil, "bulk")
    end
    local now = Now()
    -- Officers pass on everything; everyone else only their own records.
    -- (Passing on every recruitment status and Do Not Whisper entry too, as
    -- before, queued hundreds of messages per repair on every copy, and a
    -- member's own records waited behind them: a new member's data could
    -- take ages to reach anyone. Those lists still spread through officers
    -- and the people who wrote them.)
    -- Your own records go in the fast lane, ahead of anything passed on.
    local relayAll = scope == "officer" or ns.IsOfficer()
    local me = Me()
    for key, rec in pairs(store) do
        if want[Bucket(key)] and not self:Excluded(key, rec, now) then
            local mine = Same(rec.a, me)
            if mine or relayAll then
                local msg = self:EncodeRecord(key, rec)
                self:Send(msg, channel, nil, mine and "high" or "bulk", msg)
            end
        end
    end
end

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------
function S:EncodeRecord(key, rec)
    return table.concat({ PROTO, "R", key, tostring(rec.t), rec.a or "", rec.b or "", rec.v or "" }, FS)
end

function S:Broadcast(key, rec)
    local typ = S.ParseKey(key)
    local def = S.TYPES[typ]
    local scope = def.scope
    if scope == "officer" and not ns.IsOfficer() then return end
    self:Send(self:EncodeForWire(key, rec), CHANNEL[scope], nil, def.low and "bulk" or "high")
end

local partials = {}
local reassembling = false
local MAX_PARTS = 16   -- a 250-byte message per part: far more than any record needs
local MAX_PENDING = 8  -- unfinished chunked messages kept per sender

function S:OnMessage(msg, channel, sender)
    local who = ns.NormalizeName(sender)
    if not who or who == Me() then return end
    if channel == "OFFICER" then self.officers[who] = true end
    local f = ns.Split(msg, FS)
    if f[1] ~= PROTO then return end -- other protocol versions are ignored
    self.stats.received = self.stats.received + 1
    local kind = f[2]
    local from = self:From(who)
    from.messages = from.messages + 1
    from.kinds[kind or "?"] = (from.kinds[kind or "?"] or 0) + 1
    from.last = GetTime()
    from.raw = sender
    if kind == "R" or kind == "Z" then
        local key, t, author, batch = f[3], tonumber(f[4]), f[5], f[6]
        if not key or not t then return end
        -- our own values never contain "|" (Clean); one arriving would be a
        -- hand-made escape code (textures, colors, links) for our tooltips
        if key:find("[|%c]") or (author or ""):find("[|%c]") then return end
        local raw = table.concat(f, FS, 7)
        if kind == "Z" then
            raw = Unpack(raw)
            if not raw then return end
        end
        local value = raw:gsub("|", "/")
        -- the same as our own edits (Clean): no line breaks or other control
        -- characters (fake extra lines in tooltips); audit entries keep their
        -- field separator
        local typ0 = key:match("^(%u+):")
        if typ0 ~= "A" then value = value:gsub(US, "") end
        value = value:gsub("[%z\1-\30\127]", " ")
        -- batch ids are ours (base-36, short); anything else is dropped
        if batch and not batch:match("^%w%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?%w?$") then batch = "" end
        local rec = { v = value, t = t, a = author, b = (batch ~= "" and batch) or nil }
        key, rec = S.Canon(key, rec)
        self:Apply(key, rec, { origin = "remote", channel = channel, sender = who })
        self:Notify("member") -- schedule a flush
    elseif kind == "D" then
        self:OnDigest(f[3], f[4], who, channel)
    elseif kind == "L" then
        self:OnList(f[3], f[4], f[5], table.concat(f, FS, 6), who, channel)
    elseif kind == "B" then
        -- "I'm re-sending bucket b": skip ours only if theirs will be
        -- accepted in full, i.e. an officer is sending it (SenderAllowed)
        local scope, b = f[3], tonumber(f[4])
        if b and self.dumped[scope] and (scope == "officer" or self:KnownOfficer(who)) then
            self.dumped[scope][b] = GetTime()
        end
    elseif kind == "C" then
        if reassembling then return end -- a chunk can't contain chunks
        -- chunk: id, index, total, data
        local id, i, n = f[3], tonumber(f[4]), tonumber(f[5])
        if not (id and i and n) then return end
        -- ours are a few parts at most; bound what one sender can pile up
        if n < 1 or n > MAX_PARTS or i < 1 or i > n or i % 1 ~= 0 then return end
        local pkey = who .. ":" .. id
        local p = partials[pkey]
        if not p then
            local pending = 0
            for k in pairs(partials) do if k:sub(1, #who + 1) == who .. ":" then pending = pending + 1 end end
            if pending >= MAX_PENDING then return end
            p = { parts = {}, count = 0, n = n, at = GetTime() }
            partials[pkey] = p
        end
        if n ~= p.n then return end
        if not p.parts[i] then
            p.parts[i] = table.concat(f, FS, 6)
            p.count = p.count + 1
        end
        if p.count == p.n then
            partials[pkey] = nil
            reassembling = true
            local ok, err = pcall(self.OnMessage, self, table.concat(p.parts), channel, sender)
            reassembling = false
            if not ok then error(err, 0) end
        end
        -- forget stale partial messages
        for k, v in pairs(partials) do
            if GetTime() - v.at > 60 then partials[k] = nil end
        end
    end
end

------------------------------------------------------------------------
-- Transport: byte budget, priorities, retries, chunking
------------------------------------------------------------------------
local queues = { high = {}, bulk = {} }
local tokens, lastRefill = nil, nil
local chunkId = 0
S.queues = queues

local RESULT_RETRY = { [3] = 1, [8] = 1, [11] = 5 } -- throttle, channel throttle, combat lockdown (seconds)

local function RawSend(msg, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not send then return "drop" end
    local ok, res = pcall(send, PREFIX, msg, channel, target)
    if not ok then return "drop" end
    if res == nil or res == true or res == 0 then return "ok" end
    if type(res) == "number" and RESULT_RETRY[res] then return "retry", RESULT_RETRY[res] end
    return "drop"
end

-- dedupe: messages already waiting to go out (identical text), so repeated
-- repairs don't pile the same record into the queue again and again
local waiting = {}
S.waiting = waiting

function S:Send(msg, channel, target, prio, dedupe)
    local q = queues[prio or "high"]
    if dedupe then
        if waiting[dedupe] then return end
        waiting[dedupe] = true
    end
    if #msg > self.MAX_MSG then
        chunkId = (chunkId + 1) % 46656
        local id = Base36(chunkId)
        local n = math.ceil(#msg / self.CHUNK)
        for i = 1, n do
            local part = msg:sub((i - 1) * self.CHUNK + 1, i * self.CHUNK)
            -- the last part releases the dedupe mark once it's gone
            q[#q + 1] = { table.concat({ PROTO, "C", id, tostring(i), tostring(n), part }, FS), channel, target, i == n and dedupe or nil }
        end
    else
        q[#q + 1] = { msg, channel, target, dedupe }
    end
    self:Pump()
end

function S:Pump()
    if self.pumping then return end
    self.pumping = true
    local function step()
        local now = GetTime()
        tokens = tokens or self.BURST
        lastRefill = lastRefill or now
        tokens = math.min(self.BURST, tokens + (now - lastRefill) * self.BYTES_PER_SEC)
        lastRefill = now
        while true do
            local q = (#queues.high > 0 and queues.high) or (#queues.bulk > 0 and queues.bulk)
            if not q then
                S.pumping = false
                return
            end
            local item = q[1]
            local cost = #item[1] + #PREFIX + 10
            if tokens < cost then break end
            local result, wait = RawSend(item[1], item[2], item[3])
            if result == "retry" then
                S.stats.retries = S.stats.retries + 1
                C_Timer.After(wait, step)
                return
            end
            table.remove(q, 1)
            if item[4] then waiting[item[4]] = nil end
            tokens = tokens - cost
            if result == "ok" then
                S.stats.sent = S.stats.sent + 1
            else
                S.stats.dropped = S.stats.dropped + 1
            end
        end
        C_Timer.After(0.25, step)
    end
    step()
end

function S:QueueSize()
    return #queues.high + #queues.bulk
end

------------------------------------------------------------------------
-- Migration from the old (protocol 1) data
------------------------------------------------------------------------
function S:Migrate()
    local g = ns.DB:Guild()
    if not g or g.syncVersion == 2 then return end
    local me = Me()
    local store = self:Store("guild")
    local officerStore = self:Store("officer")

    for full, m in pairs(g.members or {}) do
        if type(m) == "table" then
            if m.main then store["M:" .. full] = { v = m.main, t = 1, a = me } end
            if m.spec then store["MS:" .. full] = { v = Clean(m.spec), t = 1, a = me } end
            if m.profs and #m.profs > 0 then store["MP:" .. full] = { v = Codec.Profs(m.profs), t = 1, a = me } end
            if m.auto then store["P:" .. full] = { v = Codec.Report(m.auto), t = m.auto.ts or 1, a = full } end
            for id, e in pairs(m.log or {}) do
                local key = "L:" .. full .. ":" .. id
                if e.del then
                    officerStore[key] = { v = "", t = e.upd or e.ts or 1, a = me }
                else
                    officerStore[key] = { v = Codec.Log(e.ts or 1, e.author or "?", e.text or ""), t = e.upd or e.ts or 1, a = me }
                end
            end
        end
    end
    g.tags, g.nextTagId, g.logUpd = nil, nil, nil
    g.syncVersion = 2
    self.migrated = true
end

-- Deletes stored records of types this version no longer has (reviews,
-- ratings, map dot colors, polls, stats, goals, kudos, About me, status,
-- pronouns), and retired guild settings (tab titles and ranks, pronouns), so
-- they don't linger in the saved data or upset digests.
function S:PurgeUnknown()
    local removed = 0
    for _, scope in ipairs({ "guild", "officer" }) do
        local store = self:Store(scope)
        if store then
            local dead = {}
            for key, rec in pairs(store) do
                if not S.ParseKey(key) or key:match("^GS:tab_") or key == "GS:pronouns" or key == "GS:reviews"
                    or key == "GS:perm_tags" or key == "GS:perm_tagothers" then
                    dead[#dead + 1] = key
                elseif key:sub(1, 2) == "A:" then
                    -- audit entries about removed types
                    local typ = ns.Split(rec.v or "", US)[2]
                    if typ and typ ~= "" and not S.TYPES[typ] and not S.ROSTER_EVENTS[typ] then dead[#dead + 1] = key end
                end
            end
            for _, key in ipairs(dead) do store[key] = nil end
            removed = removed + #dead
        end
    end
    if removed > 0 then self.auditCache = nil end
    return removed
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
function S:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
    ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
        if prefix == PREFIX then S:OnMessage(msg, channel, sender) end
    end)

    -- Your version, announced once per session, and only once the roster has
    -- told us your full name: before that the game gives only your first name
    -- ("Deja"), and a record under that name is refused by guildmates (it
    -- doesn't match the sender, "Deja Rollupz"). It's re-sent even when
    -- unchanged, so a broadcast lost at a quick /reload heals at the next login.
    local announced = false
    local function announceVersion()
        if announced or not S.readyFor or not (ns.Roster and ns.Roster.selfRow) then return end
        announced = true
        local key = "AV:" .. Me()
        S:Set(key, ns.version)
        S:QueueOutgoing(key)
    end
    S.AnnounceVersion = announceVersion

    -- Guild data arrives a little after login; prepare once it's there.
    local function ready()
        local key = ns.DB:GuildKey()
        if not key or S.readyFor == key or not ns.DB:Guild() then return end
        S.readyFor = key
        S:Migrate()
        S:CanonicalizeSaved()
        S:PurgeUnknown()
        S:PruneAudit()
        S:PruneExpired()
        S:RebuildAll()
        -- tell the guild which version of the addon we run (once we know our name)
        announceVersion()
        C_Timer.After(5 + math.random() * 10, function() S:Exchange(true) end)
    end
    ns:RegisterEvent("GUILD_ROSTER_UPDATE", ready)
    ns:RegisterEvent("PLAYER_GUILD_UPDATE", ready)
    ready()

    -- the roster spells your name differently than expected: re-announce
    -- your version (and spec/professions) under that spelling
    ns:On("SELF_NAME_CHANGED", function()
        if not S.readyFor then return end
        announced = false
        announceVersion()
        if ns.Comm then ns.Comm:Report() end
    end)
    ns:On("ROSTER_UPDATED", announceVersion)

    -- flush queued changes when the player logs out or reloads (best effort;
    -- anything missed is repaired by the next digest exchange)
    ns:RegisterEvent("PLAYER_LOGOUT", function() S:FlushOutgoing() end)

    local function tick()
        S:PruneExpired()
        S:Exchange(false)
        C_Timer.After(S.DIGEST_INTERVAL, tick)
    end
    C_Timer.After(S.DIGEST_INTERVAL, tick)
end
