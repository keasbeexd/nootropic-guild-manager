--[[
    Nootropic Guild Manager - Database
    SavedVariables (NootropicGuildManagerDB):

      settings = { minimap, iconStyle, communitiesButton,
                   auditDays, onlineOnly, sortKey, sortAsc, hiddenColumns,
                   columnWidths, frameSize, framePos }
      guilds["<Guild>"] = {     -- "<Guild>-<Realm>" outside WoW: Forever
          sync    = { guild = { [key] = record }, officer = { ... } }, -- see Core/Records.lua
          members = { ["First Second"] = { note = "private, never shared", + fields built from sync records } },
          recruit = { ... },                                           -- see Services/Recruit.lua
      }

    Shared data (links, specs, professions, officer log) is
    written through ns.Sync, which checks permissions, versions, broadcasts
    and audits each change. Setters return true, or nil plus an error.
]]
local _, ns = ...
local DB = {}
ns.DB = DB

local DEFAULTS = {
    version = 1,
    settings = {
        minimap = { angle = 200, hide = false, left = "roster", right = "options", shift = "recruit" },
        iconStyle = "emblem",        -- "emblem" (your guild's tabard) | "nootropic" (the medallion)
        communitiesButton = true,    -- shortcut on the Guild & Communities window
        blizzRoster = true,          -- alts and tooltips on the game's guild roster
        showAddonCount = true,       -- "x using ... Guild Manager" at the bottom of the window
        eventNotices = true,         -- Guild Feed: a chat line for each new event from NGM Peon
        levelUps = true,             -- Guild Feed: a chat line when a guildmate levels up
        levelUpSoundChoice = "off",  -- Guild Feed: the level-up sound ("off", or a Services/GuildFeed.lua key)
        eventSoundChoice = "off",    -- Guild Feed: the new-event sound
        whoWhisperButton = true,     -- recruitment whisper button on the game's /who results
        shareRecipes = true,         -- share my recipes
        playRange = 5,               -- Play Together: levels either side of yours (0 = any)
        overviewDays = 30,           -- Overview: count members online in this many days (0 = everyone)
        hofPeriod = "all",           -- Hall of Fame: "all", "month" or "last"
        whisperPerHour = 40,         -- whisper queue cap per rolling hour (0 = only the 12-second spacing)
        auditDays = 30,              -- audit history kept: 30, 60 or 90 days
        onlineOnly = false,
        sortKey = "rank",
        sortAsc = true,
        -- the game's own roster already shows level, class, zone and rank
        hiddenColumns = { second = true }, -- false = shown on purpose
        columnWidths = {},
        frameSize = { w = 1000, h = 580 },
    },
    guilds = {},
}

local function ApplyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function DB:Init()
    NootropicGuildManagerDB = NootropicGuildManagerDB or {}
    local sv = NootropicGuildManagerDB
    -- 3.0.14: the level-up sound's on/off box became a choice with Off
    local old = sv.settings
    if old and old.levelUpSound ~= nil then
        if old.levelUpSound ~= true then old.levelUpSoundChoice = "off"
        elseif old.levelUpSoundChoice == nil or old.levelUpSoundChoice == "off" then old.levelUpSoundChoice = "ngm:chime" end
        old.levelUpSound = nil
    end
    ApplyDefaults(DEFAULTS, sv)
    -- 2.0: settings of removed features
    local st = sv.settings
    st.ratingHiddenOnce, st.hiddenColumns.rating = nil, nil
    st.tabSide, st.compact, st.miniPos, st.export = nil, nil, nil, nil
    st.shareLocation, st.showOnMap, st.customDots = nil, nil, nil
    st.reviewed, st.kudosGiven = nil, nil
    sv.inspectLog = nil
    -- 2.12: the guild tabard is the default and the only other choice is
    -- the medallion (the mug and stein are gone); everyone moves to the
    -- tabard once, and can pick the medallion again in Options
    if not st.tabardDefault then
        st.tabardDefault = true
        st.iconStyle = "emblem"
    end
    -- 3.0: the guild's tabard and the guild's theme are the defaults; anyone
    -- who changed either while testing starts from them once more
    if not st.guildLookDefault then
        st.guildLookDefault = true
        st.iconStyle = "emblem"
        st.theme = nil
    end
    st.logoMigrated, st.titleUseGuild = nil, nil
    -- 2.6.1: every column but Second Name starts shown. Anyone still on the
    -- old default (version, second, level, class, zone, rank hidden, nothing
    -- else changed) moves over once; customised columns are kept.
    if not st.columnsMigrated then
        st.columnsMigrated = true
        local old = { version = true, second = true, level = true, class = true, zone = true, rank = true }
        local same = true
        for k, v in pairs(st.hiddenColumns) do
            if (v and true or false) ~= (old[k] or false) then same = false end
        end
        for k in pairs(old) do
            if not st.hiddenColumns[k] then same = false end
        end
        if same then
            wipe(st.hiddenColumns)
            st.hiddenColumns.second = true
        end
    end
    -- 2.1: tags
    for _, k in ipairs({ "left", "right", "shift" }) do
        if st.minimap[k] == "tags" then st.minimap[k] = "roster" end
    end
    st.hiddenColumns.tags, st.columnWidths.tags = nil, nil
    if st.sortKey == "tags" then st.sortKey, st.sortAsc = "rank", true end
    if type(st.columnOrder) == "table" then
        for i = #st.columnOrder, 1, -1 do
            if st.columnOrder[i] == "tags" then table.remove(st.columnOrder, i) end
        end
    end
    for _, mine in pairs(st.schedules or {}) do mine.days = nil end
    for _, g in pairs(sv.guilds) do
        g.myGoals, g.myStats, g.goalHistory, g.pollsSeen = nil, nil, nil, nil
        g.kudosOutbox, g.reviewOutbox = nil, nil
    end
    self.sv = sv
end

function DB:Settings()
    return self.sv.settings
end

function DB:Now()
    return (GetServerTime and GetServerTime()) or time()
end

------------------------------------------------------------------------
-- Guild scope
------------------------------------------------------------------------
function DB:GuildKey()
    if not IsInGuild() then return nil end
    local name, _, _, realm = GetGuildInfo("player")
    if not name or name == "" then return nil end
    if ns.NO_REALMS then return name end -- see ns.NormalizeName
    if not realm or realm == "" then realm = ns.PlayerRealm() end
    return name .. "-" .. realm
end

-- 2.7.2: on WoW: Forever the guild was saved as "<Guild>-<shard>"; it's
-- now just "<Guild>". Adopts the old entries (the biggest as the base, the
-- rest merged in; Core/Records.lua then tidies the names inside).
local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local function MergeGuild(into, from)
    local newer = ns.Sync and ns.Sync.Newer
    for _, scope in ipairs({ "guild", "officer" }) do
        into.sync[scope] = into.sync[scope] or {}
        for k, rec in pairs((from.sync or {})[scope] or {}) do
            local cur = into.sync[scope][k]
            if not cur or (newer and newer(rec, cur)) then into.sync[scope][k] = rec end
        end
    end
    for full, m in pairs(from.members or {}) do
        local cur = into.members[full]
        if not cur then
            into.members[full] = m
        elseif m.note and m.note ~= "" and m.note ~= cur.note then
            cur.note = (cur.note and cur.note ~= "") and (cur.note .. " / " .. m.note) or m.note
        end
    end
    if from.recruit and not into.recruit then into.recruit = from.recruit end
end

function DB:AdoptShardGuilds(key)
    local found = {}
    for k, g in pairs(self.sv.guilds) do
        if k ~= key and k:sub(1, #key + 1) == key .. "-" and type(g) == "table" then found[#found + 1] = k end
    end
    if #found == 0 then return nil end
    table.sort(found, function(a, b)
        local na = Count((self.sv.guilds[a].sync or {}).guild) + Count((self.sv.guilds[a].sync or {}).officer)
        local nb = Count((self.sv.guilds[b].sync or {}).guild) + Count((self.sv.guilds[b].sync or {}).officer)
        if na ~= nb then return na > nb end
        return a < b
    end)
    local base = self.sv.guilds[found[1]]
    base.members = base.members or {}
    base.sync = base.sync or { guild = {}, officer = {} }
    for i = 2, #found do MergeGuild(base, self.sv.guilds[found[i]]) end
    for _, k in ipairs(found) do self.sv.guilds[k] = nil end
    base.realmless = nil -- names inside still carry shard tags: Sync tidies them
    self.sv.guilds[key] = base
    return base
end

function DB:Guild()
    local key = self:GuildKey()
    if not key then return nil end
    local g = self.sv.guilds[key]
    if not g and ns.NO_REALMS then g = self:AdoptShardGuilds(key) end
    if not g then
        g = { members = {}, sync = { guild = {}, officer = {} }, realmless = ns.NO_REALMS or nil }
        self.sv.guilds[key] = g
    end
    return g
end

------------------------------------------------------------------------
-- Permissions (docs/PERMISSIONS.md): the Guild Master picks which ranks may
-- do each of these, on the Permissions page, and only they change them.
-- GS:perm_<key> = "" (the default) or rank numbers "1,3,4" ("-" = nobody
-- but the Guild Master). The Guild Master (rank 0) always may.
-- Who may while it's unset (S.PERM_DEFAULT: everyone, officers, recruiters
-- = the game's Invite Member ranks, or gm = only the Guild Master), and the
-- officer-only ones (S.PERM_NARROW: the game only delivers that data to
-- officers, so the Guild Master can narrow them, never widen them), are in
-- Core/Records.lua: the one list every copy goes by.
-- Every copy checks shared changes against these (S:Allowed); what only
-- happens on a player's own computer is gated in the NGM Addon.
-- Feature switches: GS:feat_<key> = "0" turns a feature off for the guild.
------------------------------------------------------------------------
DB.PERMS = {
    { group = "Profiles", key = "links", label = "Link mains and alts",
      hint = "Mark alts, change mains, unlink." },
    { group = "Profiles", key = "ownprofile", label = "Edit their own profile",
      hint = "Spec, roles, professions and contact info on their own characters. What their NGM Addon reports by itself (version, professions it reads, usual play hours) isn't affected." },
    { group = "Profiles", key = "ownmain", label = "Choose their own main on NGM Peon's dashboard",
      hint = "Members linked to NGM Peon pick their main among their own characters there. Linking mains and alts in game is the row above." },
    { group = "Profiles", key = "profiles", label = "Edit other guildmates' profiles",
      hint = "Spec, roles, professions and contact info on anyone's profile (their own included)." },
    { group = "Events", key = "ev_dungeon", label = "Create dungeons", event = "dungeon",
      hint = "Events made in game. With NGM Peon, the same on the dashboard." },
    { group = "Events", key = "ev_raid", label = "Create raids", event = "raid",
      hint = "Events made in game. With NGM Peon, the same on the dashboard." },
    { group = "Events", key = "ev_event", label = "Create events", event = "event",
      hint = "Guild nights and other events made in game. With NGM Peon, the same on the dashboard." },
    { group = "Events", key = "ev_manage", label = "Edit or cancel anyone's events",
      hint = "Everyone may edit and cancel the events they made." },
    { group = "Events", key = "signup", label = "Sign up for events",
      hint = "In game and, with NGM Peon, with the Discord post's buttons." },
    { group = "Recruiting", key = "recruit", label = "Use the recruiting tools",
      hint = "Recruitment whispers, the button on /who results and the Invite prompt. Whispers happen on each player's own computer, so a changed copy of the NGM Addon could still send them; what they record is checked by everyone." },
    { group = "Recruiting", key = "rmsg", label = "Write the guild's recruitment messages",
      hint = "The messages everyone's recruitment whispers start from (or must use, with Everyone uses the guild's messages). Only ranks that may use the recruiting tools." },
    { group = "Recruiting", key = "dnw_add", label = "Add to Do Not Whisper",
      hint = "Put someone on the guild's Do Not Whisper list. Only ranks that may use the recruiting tools." },
    { group = "Recruiting", key = "dnw_remove", label = "Take off Do Not Whisper",
      hint = "Take someone off the guild's Do Not Whisper list. Only ranks that may use the recruiting tools." },
    { group = "Members", key = "remind", label = "Send install reminders",
      hint = "Whisper a guildmate to install the NGM Addon." },
    { group = "Members", key = "imsg", label = "Write the install reminder text",
      hint = "The text everyone's install reminders start from (or must use, with Everyone uses the guild's text)." },
    { group = "Members", key = "ban", label = "Ban and unban players",
      hint = "Put someone (with all their characters) on the guild's ban list, or take them off." },
    { group = "Members", key = "banlist", label = "See the ban list",
      hint = "The Ban List window. Everyone is still warned when they invite someone banned." },
    { group = "Members", key = "banreason", label = "See ban reasons",
      hint = "Why someone was banned, in the Ban List and the warnings." },
    { group = "Officers", key = "officerlog", label = "Write in the Officer Log",
      hint = "Officer data: the game only gives it to ranks it marks Officer, so this can only be narrowed." },
    { group = "Officers", key = "audit", label = "See the Audit tab",
      hint = "Officer data: the game only gives it to ranks it marks Officer, so this can only be narrowed." },
    { group = "Hall of Fame", key = "hofhide", label = "Hide someone from the Hall of Fame",
      hint = "Leave a guildmate off the boards." },
    { group = "Hall of Fame", key = "hofannounce", label = "Announce champions in guild chat",
      hint = "The monthly champions line in guild chat." },
    { group = "NGM Peon", key = "peonnews", label = "Bring in NGM Peon's news for the guild",
      hint = "Their game passes NGM Peon's news on to everyone. Only officers' copies are trusted with it, so this can only be narrowed." },
    { group = "NGM Peon", key = "peoncode", label = "Make codes for NGM Peon",
      hint = "/ngm discord, and NGM Desktop sending the whole guild's changes." },
}
DB.PERM_BY_TYPE = { M = "links",
    MS = "profiles", RL = "profiles", MP = "profiles", CN = "profiles" }

-- Feature switches (the whole guild, on unless the Guild Master turned them off)
DB.FEATURES = {
    { key = "recruit", label = "Recruiting", hint = "The Recruitment tab, whispers, the /who button and the Invite prompt." },
    { key = "together", label = "Play Together", hint = "The Play Together tab." },
    { key = "events", label = "Upcoming Events", hint = "The Upcoming Events tab: events, sign-ups, resets and holidays." },
    { key = "overview", label = "Overview", hint = "The Overview tab." },
    { key = "crafting", label = "Who Can Craft", hint = "The Who Can Craft window." },
    { key = "fame", label = "Hall of Fame", hint = "The Hall of Fame tab and champions." },
    { key = "levelups", label = "Level-ups in chat", hint = "The Guild Feed's level-up lines." },
    { key = "reminders", label = "Install reminders", hint = "Whispering guildmates to install the NGM Addon." },
    { key = "connect", label = "Get Connected", hint = "The checklist that opens by itself (with NGM Peon)." },
}

-- The rules as every copy uses them: the Guild Master's, as long as they
-- match the Guild Info's code (Services/GuildRules.lua), else the last ones
-- that did.
function DB:Rule(name)
    if ns.GuildRules then return ns.GuildRules:Value(name) end
    return ns.Sync:Value("GS:" .. name)
end

function DB:FeatureOn(key) return self:Rule("feat_" .. key) ~= "0" end

-- "Everyone uses the guild's ..." (rmsg: recruitment messages, imsg: the install reminder text)
function DB:SetLock(key, on)
    if not self:IsGuildMaster() then return nil, "Only the Guild Master can change this." end
    return ns.Sync:Set("GS:lock_" .. key, on and "1" or "")
end

function DB:SetFeature(key, on)
    if not self:IsGuildMaster() then return nil, "Only the Guild Master can change this." end
    return ns.Sync:Set("GS:feat_" .. key, on and "" or "0")
end

-- { [rankIndex] = true }, or nil for the default.
function DB:PermRanks(key)
    local v = self:Rule("perm_" .. key)
    if not v or v == "" then return nil end
    local set = {}
    for n in v:gmatch("%d+") do set[tonumber(n)] = true end
    return set
end

function DB:IsGuildMaster()
    return IsInGuild() and self:MyRankIndex() == 0
end

-- May you do `key`? (the Guild Master always may)
function DB:PermDef(key)
    for _, p in ipairs(self.PERMS) do if p.key == key then return p end end
end

-- May you do `key`? (the same rule every copy applies: S:Allowed)
function DB:HasPerm(key)
    if not IsInGuild() then return false end
    local rank = self:MyRankIndex()
    if rank == 0 then return true end
    local set = self:PermRanks(key)
    local needs = ns.Sync.PERM_NEEDS[key]
    if needs and not self:HasPerm(needs) then return false end
    if set then return rank ~= nil and set[rank] == true and (not ns.Sync.PERM_NARROW[key] or ns.IsOfficer()) end
    local default = ns.Sync.PERM_DEFAULT[key] or "officers"
    if default == "everyone" then return true end
    if default == "recruiters" then return ns.Sync:MayRecruit() end
    if default == "gm" then return false end
    return ns.IsOfficer()
end

-- May this rank (r = { index, name }) do `key`? (for the Permissions page's
-- choices: the recruiting rows only offer ranks that may recruit, officer
-- data only officer ranks)
function DB:RankMay(r, key)
    if r.index == 0 then return true end
    local S = ns.Sync
    local needs = S.PERM_NEEDS[key]
    if needs and not self:RankMay(r, needs) then return false end
    local flags = S:RankFlags(r.index)
    local officer = flags and flags.officer or (not flags and S:RankIsOfficer({ rankIndex = r.index, rank = r.name }))
    local set = self:PermRanks(key)
    if set then return set[r.index] == true and (not S.PERM_NARROW[key] or officer == true) end
    local default = S.PERM_DEFAULT[key] or "officers"
    if default == "everyone" then return true end
    if default == "gm" then return false end
    if default == "recruiters" then
        if flags then return flags.invite == true end
        local ranks = S:RecruiterRanks()
        if ranks then return ranks[(r.name or ""):lower()] == true end
    end
    return officer == true
end

-- Can this row be handed to this rank at all? (what it needs, officer data)
function DB:RankCanHold(r, key)
    local S = ns.Sync
    if r.index == 0 then return true end
    if S.PERM_NEEDS[key] and not self:RankMay(r, S.PERM_NEEDS[key]) then return false end
    if S.PERM_NARROW[key] then
        local flags = S:RankFlags(r.index)
        if flags then return flags.officer end
        return S:RankIsOfficer({ rankIndex = r.index, rank = r.name }) == true
    end
    return true
end

-- set = { [rankIndex] = true } or nil for the default (officers).
function DB:SetPermRanks(key, set)
    if not self:IsGuildMaster() then return nil, "Only the Guild Master can change permissions." end
    local list = {}
    for n in pairs(set or {}) do if n ~= 0 then list[#list + 1] = n end end
    table.sort(list)
    local v = set and table.concat(list, ",") or ""
    if set and v == "" then v = "-" end -- nobody but the Guild Master
    return ns.Sync:Set("GS:perm_" .. key, v)
end

-- The default's name: "Everyone" or "Officers".
local DEFAULT_TEXT = { everyone = "Everyone", officers = "Officers", recruiters = "Ranks that may invite", gm = "Only the Guild Master" }
function DB:PermDefaultText(key)
    local default = ns.Sync.PERM_DEFAULT[key] or "officers"
    if default == "everyone" and ns.Sync.PERM_NEEDS[key] == "recruit" then return "Everyone who may recruit" end
    return DEFAULT_TEXT[default]
end

-- Short, for a button (as the dashboard says it): "Officers (default)",
-- "Everyone", "Only the Guild Master", "Raid Leader and above" (a top run of
-- ranks), or "Officer, Veteran +2". full = true: every name.
function DB:PermText(key, full)
    local set = self:PermRanks(key)
    if not set then return self:PermDefaultText(key) .. " (default)" end
    local ranks, names, all, run = self:GuildRanks(), {}, true, true
    for _, r in ipairs(ranks) do
        if r.index ~= 0 then
            if set[r.index] then names[#names + 1] = r.name else all = false end
        end
    end
    if #names == 0 then return "Only the Guild Master" end
    if all then return "Everyone" end
    -- ranks 1..k exactly: "<rank k> and above"
    local k = 0
    for i = 1, #ranks - 1 do if set[i] then k = i else break end end
    for i in pairs(set) do if i > k then run = false end end
    if run and k > 0 then
        for _, r in ipairs(ranks) do if r.index == k then return r.name .. " and above" end end
    end
    if full or #names <= 2 then return table.concat(names, ", ") end
    return ("%s, %s +%d"):format(names[1], names[2], #names - 2)
end

-- Your rank number in the guild (0 = Guild Master), or nil.
function DB:MyRankIndex()
    if not IsInGuild() then return nil end
    local _, _, index = GetGuildInfo("player")
    return index
end

-- The guild's ranks: { { index = 0, name = "Guild Master" }, ... }
function DB:GuildRanks()
    local out = {}
    local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for i = 1, n do
        out[#out + 1] = { index = i - 1, name = GuildControlGetRankName(i) or ("Rank " .. i) }
    end
    return out
end

------------------------------------------------------------------------
-- Members
------------------------------------------------------------------------
function DB:GetMember(full)
    local g = self:Guild()
    return g and full and g.members[full]
end

function DB:EnsureMember(full)
    local g = self:Guild()
    if not g or not full then return nil end
    local m = g.members[full]
    if not m then
        m = {}
        g.members[full] = m
    end
    return m
end

-- Who may edit what on a character's profile.
function DB:CanEditProfile(full) return ns.Sync:CanWrite("MS:" .. full) end
function DB:CanEditLinks() return self:HasPerm("links") end

-- Private notes never leave this computer.
function DB:SetNote(full, text)
    local m = self:EnsureMember(full)
    if not m then return end
    text = ns.Trim(text)
    if text == "" then text = nil end
    if m.note == text then return end
    m.note = text
    ns:Fire("MEMBER_CHANGED", full)
end

-- Roles: { tank = true, ... } (the member, or officers)
function DB:SetRoles(full, set)
    local list = {}
    for _, r in ipairs(ns.Data.ROLES) do
        if set and set[r.key] then list[#list + 1] = r.key end
    end
    return ns.Sync:Set("RL:" .. full, table.concat(list, ","))
end

function DB:SetManualSpec(full, spec)
    spec = spec and ns.Trim(spec) or ""
    return ns.Sync:Set("MS:" .. full, spec)
end

local function FindProf(list, name)
    if not list then return end
    local lower = name:lower()
    for i, p in ipairs(list) do
        if p.name:lower() == lower then return p, i end
    end
end

local function SaveProfs(full, list)
    return ns.Sync:Set("MP:" .. full, ns.Sync.Codec.Profs(list))
end

local function CopyProfs(full)
    local m = DB:GetMember(full)
    local list = {}
    for _, p in ipairs(m and m.profs or {}) do list[#list + 1] = { name = p.name, rank = p.rank } end
    return list
end

function DB:AddManualProf(full, name)
    if not name or name == "" then return end
    local list = CopyProfs(full)
    if FindProf(list, name) then return true end
    table.insert(list, { name = name, rank = 0 })
    return SaveProfs(full, list)
end

function DB:SetManualProfRank(full, name, rank)
    local list = CopyProfs(full)
    local p = FindProf(list, name)
    if not p then return end
    p.rank = math.max(0, math.min(999, math.floor(tonumber(rank) or 0)))
    return SaveProfs(full, list)
end

function DB:RemoveManualProf(full, name)
    local list = CopyProfs(full)
    local _, i = FindProf(list, name)
    if not i then return end
    table.remove(list, i)
    return SaveProfs(full, list)
end

------------------------------------------------------------------------
-- Mains and alts (shared; officers only)
-- Only alts store a link. A main's alts are everyone pointing at it, so
-- editing either side keeps both in sync. Links always point at the
-- top-level main, never at another alt.
------------------------------------------------------------------------
function DB:GetMainOf(full)
    local m = self:GetMember(full)
    return m and m.main
end

function DB:GetAltsOf(full)
    local out = {}
    local g = self:Guild()
    if not g or not full then return out end
    for name, m in pairs(g.members) do
        if m.main == full then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function DB:RootOf(full)
    local seen = {}
    while full and not seen[full] do
        seen[full] = true
        local m = self:GetMember(full)
        if not (m and m.main) then return full end
        full = m.main
    end
    return full
end

local function Link(alt, main)
    return ns.Sync:Set("M:" .. alt, main or "")
end

-- Marks `alt` as an alt of `main`. If `main` is currently one of alt's own
-- alts, `main` is promoted to lead the whole family instead.
function DB:SetMain(alt, main)
    if not alt or not main then return nil, "Pick a character." end
    if alt == main then return nil, "A character can't be its own alt." end
    if not self:Guild() then return nil, "You are not in a guild." end
    if not self:CanEditLinks() then return nil, "Your rank can't link mains and alts." end
    local root = self:RootOf(main)
    if root == alt then return self:MakeMain(main) end
    local family = self:GetAltsOf(alt)
    local ok, err = Link(alt, root)
    if not ok then return nil, err end
    for _, a in ipairs(family) do Link(a, root) end
    return true
end

function DB:ClearMain(alt)
    if not self:CanEditLinks() then return nil, "Your rank can't link mains and alts." end
    if self:GetMainOf(alt) then return Link(alt, nil) end
    return true
end

-- Makes `full` the main of its family (its old main becomes an alt).
function DB:MakeMain(full)
    if not self:CanEditLinks() then return nil, "Your rank can't link mains and alts." end
    local root = self:RootOf(full)
    if not root or root == full then return true end
    local family = self:GetAltsOf(root)
    Link(full, nil)
    Link(root, full)
    for _, a in ipairs(family) do
        if a ~= full then Link(a, full) end
    end
    return true
end

------------------------------------------------------------------------
-- Officer log (shared with officers only)
------------------------------------------------------------------------
function DB:AddLogEntry(full, text)
    text = ns.Trim(text):gsub("|", "/"):gsub("[\r\n]+", " ")
    if text == "" then return nil end
    text = text:sub(1, ns.Data.MAX_LOG_LENGTH)
    local ts = self:Now()
    local id = ns.Sync.Base36(ts) .. ns.Sync.Base36(math.random(0, 46655))
    local ok, err = ns.Sync:Set("L:" .. full .. ":" .. id, ns.Sync.Codec.Log(ts, ns.ShortName(ns.PlayerFullName()), text))
    if not ok then return nil, err end
    local m = self:GetMember(full)
    return m and m.log and m.log[id]
end

function DB:DeleteLogEntry(full, id)
    local m = self:GetMember(full)
    local entry = m and m.log and m.log[id]
    if not entry or entry.del then return nil end
    local ok = ns.Sync:Set("L:" .. full .. ":" .. id, "")
    return ok and m.log[id] or nil
end

-- Visible entries, newest first.
function DB:GetLog(full)
    local out = {}
    local m = self:GetMember(full)
    if m and m.log then
        for _, e in pairs(m.log) do
            if not e.del then out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.id > b.id
    end)
    return out
end

------------------------------------------------------------------------
-- Data reported by the player's own copy of the addon
------------------------------------------------------------------------
function DB:SetSelfReport(snap)
    local me = ns.PlayerFullName()
    if not me then return end
    return ns.Sync:Set("P:" .. me, ns.Sync.Codec.Report(snap))
end
