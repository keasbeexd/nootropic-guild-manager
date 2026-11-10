--[[
    Nootropic Guild Manager - Hall of Fame
    Guild leaderboards from the game's own character statistics (the
    Statistics page of the achievement window). The game only lets addons
    read your own, so each member's copy reads theirs and shares them as

      HF:<member> = "1;<month>;<all time>;<this month>;<last month id>;<last month>"

    <month> is the UTC month the record was written in (202611); each list
    is "key=n,key=n" (keys in HF.STATS). "This month" and "last month" are
    worked out by the member's own copy from a snapshot taken the first time
    it reads the statistics in a new month, so the first month counts from
    when the addon was installed. Gold is left out on purpose.

    Statistic IDs were read from the Forever client's own catalogue
    (build 1.60.1, Interface 16001), the Wrath-era set plus Forever additions.
    GetStatistic returns text: "1,234", "--" for never, or a money string.
]]
local _, ns = ...
local HF = {}
ns.HallOfFame = HF

HF.VERSION = "1"
HF.PUBLISH_EVERY = 600 -- shared again at most every 10 minutes (and at login)

-- key, statistic id(s), label, icon. A list of ids is added up.
HF.STATS = {
    { key = "champs",   label = "Most Champion Wins", icon = "Interface\\Icons\\INV_Crown_01", merge = "max", noChampion = true,
      tip = "Months spent at the top of a Hall of Fame card. Each card's leader for a month (all of them, on a tie) is its champion; every title counts." },
    { key = "social",   label = "Social Butterfly", icon = "Interface\\Icons\\Spell_Holy_MindVision",
      format = function(n) return ("%.1f h"):format(n / 4) end,
      tip = "Hours spent in guild chat conversations: 15-minute blocks where you and at least one guildmate both spoke (8 blocks a day at most). Only the count is shared, never what was said." },
    { key = "quests",   id = 98,   label = "Quests completed",  icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "kills",    id = 1197, label = "Kills",             icon = "Interface\\Icons\\Ability_DualWield" },
    { key = "bosses",   label = "Dungeon & raid bosses",         icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
      tip = "Final bosses killed: every dungeon and raid, Forever's own included." },
    { key = "dungeons", id = 932,  label = "Dungeons entered",  icon = "Interface\\Icons\\INV_Misc_Key_14" },
    { key = "hk",       id = 588,  label = "Honorable kills",   icon = "Interface\\Icons\\INV_BannerPVP_02" },
    { key = "bgs",      id = 840,  label = "Battlegrounds won", icon = "Interface\\Icons\\INV_Sword_27" },
    { key = "duels",    id = 319,  label = "Duels won",         icon = "Interface\\Icons\\Ability_Parry" },
    { key = "epics",    id = 341,  label = "Epics looted",      icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02" },
    { key = "deaths",   id = 60,   label = "Deaths",            icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
    { key = "falls",    id = 114,  label = "Deaths from falling", icon = "Interface\\Icons\\Spell_Magic_FeatherFall" },
    { key = "flights",  id = 349,  label = "Flights taken",     icon = "Interface\\Icons\\Ability_Mount_Wyvern_01" },
    { key = "hearths",  id = 353,  label = "Hearthstones used", icon = "Interface\\Icons\\INV_Misc_Rune_01" },
    { key = "fish",     id = 1518, label = "Fish caught",       icon = "Interface\\Icons\\INV_Misc_Fish_02" },
    { key = "hugs",     id = 1042, label = "Hugs given",        icon = "Interface\\Icons\\Spell_Holy_GreaterHeal" },
}
HF.BY_KEY = {}
for _, s in ipairs(HF.STATS) do HF.BY_KEY[s.key] = s end

-- Formats a statistic's value for display.
function HF.Format(stat, n)
    if stat and stat.format then return stat.format(n or 0) end
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- Final-boss kill statistics, one per dungeon or raid.
HF.BOSS_IDS = {
    15027, 15028, 63570, 1092, 15029, 6137, 63573, 63571, 63572, 63589, 6140, 6139, 1093, 6786,
    6141, 6142, 1094, 6143, 6144, 1095, 6145, 1096, 6146, 15030, 15031, 1098, 63574, 63575, 63581, 63580,
}

local function Me() return ns.PlayerFullName() end

-- UTC month as a number: 202611
function HF.Month(t)
    return tonumber(date("!%Y%m", t or time()))
end

function HF.PrevMonth(m)
    local y, mo = math.floor(m / 100), m % 100
    if mo == 1 then return (y - 1) * 100 + 12 end
    return y * 100 + mo - 1
end

------------------------------------------------------------------------
-- Reading your own statistics
------------------------------------------------------------------------
function HF:Available()
    return type(GetStatistic) == "function"
end

-- "1,234" -> 1234; "--", money strings and anything unreadable -> nil
function HF.Parse(raw)
    if type(raw) == "number" then return raw end
    if type(raw) ~= "string" or raw == "" or raw == "--" then return nil end
    if raw:find("|", 1, true) then return nil end -- money (coin textures)
    local digits = raw:match("^%s*([%d,%.%s]+)")
    if not digits then return nil end
    return tonumber((digits:gsub("[^%d]", "")))
end

local function Read(id)
    local ok, raw = pcall(GetStatistic, id)
    if not ok then return nil end
    if issecretvalue and issecretvalue(raw) then return nil end
    return HF.Parse(raw)
end

-- { key = n } for every statistic the game answered (nil when it can't).
function HF:ReadMine()
    local out, any = {}, false
    local social = self:SocialTotal()
    if social > 0 then out.social, any = social, true end
    local champs = self:WinsTotal()
    if champs > 0 then out.champs, any = champs, true end
    if not self:Available() then return any and out or nil end
    for _, s in ipairs(self.STATS) do
        local n
        if s.id then
            n = Read(s.id)
        elseif s.key == "bosses" then
            for _, id in ipairs(self.BOSS_IDS) do
                local v = Read(id)
                if v then n = (n or 0) + v end
            end
        end
        if n then
            out[s.key] = n
            any = true
        end
    end
    return any and out or nil
end

------------------------------------------------------------------------
-- Monthly snapshots (this computer, per character)
------------------------------------------------------------------------
local function Minus(a, b)
    local out = {}
    for k, v in pairs(a) do
        local d = v - ((b and b[k]) or 0)
        if d > 0 then out[k] = d end
    end
    return out
end

-- Updates the snapshots in `state` for statistics `cur` read in `month`;
-- returns this month's and last month's numbers.
function HF.Advance(state, cur, month)
    if not state.month then
        state.month, state.base = month, cur
    elseif state.month ~= month then
        if state.month == HF.PrevMonth(month) then
            state.last, state.lastMonth = Minus(cur, state.base), state.month
        else
            state.last, state.lastMonth = nil, nil -- not played last month
        end
        state.month, state.base = month, cur
    end
    -- a statistic that went down (reset by the game): start it over
    for k, v in pairs(cur) do
        if state.base[k] and v < state.base[k] then state.base[k] = v end
    end
    return Minus(cur, state.base), state.last or {}
end

local function MyState()
    local s = ns.DB:Settings()
    s.hof = s.hof or {}
    local me = Me()
    s.hof[me] = s.hof[me] or {}
    return s.hof[me]
end

------------------------------------------------------------------------
-- The shared record
------------------------------------------------------------------------
local function EncodeList(t)
    local parts = {}
    for _, s in ipairs(HF.STATS) do
        if t[s.key] then parts[#parts + 1] = s.key .. "=" .. math.floor(t[s.key]) end
    end
    return table.concat(parts, ",")
end

local function DecodeList(v)
    local t = {}
    for k, n in (v or ""):gmatch("(%w+)=(%d+)") do
        if HF.BY_KEY[k] then t[k] = tonumber(n) end
    end
    return t
end

function HF.Encode(month, all, this, lastMonth, last)
    return table.concat({ HF.VERSION, tostring(month), EncodeList(all), EncodeList(this),
                          tostring(lastMonth or 0), EncodeList(last or {}) }, ";")
end

-- A shared value -> { month, all, this, lastMonth, last }, or nil.
function HF.Decode(v)
    if not v or v == "" then return nil end
    local parts = ns.Split(v, ";")
    if parts[1] ~= HF.VERSION then return nil end
    return { month = tonumber(parts[2]) or 0, all = DecodeList(parts[3]), this = DecodeList(parts[4]),
             lastMonth = tonumber(parts[5]) or 0, last = DecodeList(parts[6]) }
end

function HF:Publish()
    if not (IsInGuild() and ns.DB:Guild() and ns.Sync.readyFor) then return end
    if not ns.Sharing:Get("stats") then return end
    self:UpdateWins()
    local cur = self:ReadMine()
    if not cur then return end
    self.dirty = false
    local month = HF.Month()
    local state = MyState()
    local this, last = HF.Advance(state, cur, month)
    local value = HF.Encode(month, cur, this, state.lastMonth, last)
    local key = "HF:" .. Me()
    if (ns.Sync:Value(key) or "") ~= value then ns.Sync:Set(key, value) end
end

-- A character's numbers for a period ("all", "month" or "last"), as of
-- now: { key = n }, or nil when they don't share any.
function HF:For(full, period, nowMonth)
    local r = HF.Decode(ns.Sync:Value("HF:" .. full))
    if not r then return nil end
    if period == "all" then return r.all end
    nowMonth = nowMonth or HF.Month()
    if period == "month" then
        return r.month == nowMonth and r.this or {}
    end
    -- last month: what they had then, from a record written then or since
    local want = HF.PrevMonth(nowMonth)
    if r.month == nowMonth then return r.lastMonth == want and r.last or {} end
    if r.month == want then return r.this end
    return {}
end

------------------------------------------------------------------------
-- Leaderboards (shared by the Hall of Fame tab and the champions)
------------------------------------------------------------------------
-- Every guildmate's numbers for a period, people with their characters added
-- up under their main (or each character on its own with `alts`):
-- { people, sharing, noAddon, totals = { key = n }, boards = { key = { { e, n, key }... } } }
-- Most Champion Wins takes a person's best character instead of the sum
-- (every character of a person reports the same wins).
function HF:Boards(period, alts, month)
    month = month or HF.Month()
    local groups, order = {}, {}
    for _, e in ipairs(ns.Roster.members) do
        local key = alts and e.full or (e.main or e.full)
        local g = groups[key]
        if not g then
            g = { chars = {} }
            groups[key] = g
            order[#order + 1] = key
        end
        g.chars[#g.chars + 1] = e
        if e.full == key then g.e = e end
    end
    local boards, totals, sharing, noAddon = {}, {}, 0, 0
    for _, s in ipairs(self.STATS) do boards[s.key] = {} end
    for _, key in ipairs(order) do
        local g = groups[key]
        g.e = g.e or g.chars[1] -- main not in the guild: their first alt
        local sum, any, hasAddon = {}, false, false
        for _, c in ipairs(g.chars) do
            if c.hasAddon then hasAddon = true end
            local t = self:For(c.full, period, month)
            if t then
                any = true
                for k, n in pairs(t) do
                    local s = self.BY_KEY[k]
                    if s and s.merge == "max" then sum[k] = math.max(sum[k] or 0, n)
                    else sum[k] = (sum[k] or 0) + n end
                end
            end
        end
        if not hasAddon then noAddon = noAddon + 1 end
        if any then
            sharing = sharing + 1
            for k, n in pairs(sum) do
                if n > 0 and boards[k] then
                    table.insert(boards[k], { e = g.e, n = n, key = key })
                    totals[k] = (totals[k] or 0) + n
                end
            end
        end
    end
    for _, list in pairs(boards) do
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.e.short < b.e.short
        end)
    end
    return { people = #order, sharing = sharing, noAddon = noAddon, totals = totals, boards = boards }
end

-- Last month's champion of each card (people, not characters): winner takes
-- all, and a tie makes everyone at the top a champion.
-- { key = { n = best, winners = { { e, n, key }... } } }
function HF:Champions(month)
    month = month or HF.Month()
    local data = self:Boards("last", false, month)
    local out = {}
    for _, s in ipairs(self.STATS) do
        if not s.noChampion then
            local list = data.boards[s.key]
            local top = list[1] and list[1].n or 0
            if top > 0 then
                local winners = {}
                for _, p in ipairs(list) do
                    if p.n == top then winners[#winners + 1] = p else break end
                end
                out[s.key] = { n = top, winners = winners }
            end
        end
    end
    return out
end

-- Your champion titles, kept per person (your main) and month on this
-- computer: Settings().hofWins[person][month] = number of titles. Worked out
-- again each time your numbers are shared, so late arrivals still count.
local function MyPerson()
    local me = Me()
    local e = me and ns.Roster.byName[me]
    return e and (e.main or e.full) or me
end

HF.WINS_AFTER = 100 -- seconds after login: guildmates' numbers have synced by then

function HF:UpdateWins()
    -- right after login only your own numbers are here, and you'd top every card
    if self.startedAt and GetTime() - self.startedAt < self.WINS_AFTER then return end
    local person = MyPerson()
    if not person or not ns.Roster.members or #ns.Roster.members == 0 then return end
    local month = HF.Month()
    local last = HF.PrevMonth(month)
    local wins = 0
    for _, c in pairs(self:Champions(month)) do
        for _, p in ipairs(c.winners) do
            if p.key == person then wins = wins + 1 break end
        end
    end
    local s = ns.DB:Settings()
    s.hofWins = s.hofWins or {}
    s.hofWins[person] = s.hofWins[person] or {}
    s.hofWins[person][last] = wins > 0 and wins or nil
end

function HF:WinsTotal()
    local person = MyPerson()
    local mine = person and (ns.DB:Settings().hofWins or {})[person]
    local n = 0
    for _, w in pairs(mine or {}) do n = n + w end
    return n
end

------------------------------------------------------------------------
-- Social Butterfly: time in guild chat conversations
-- The day is cut into 15-minute blocks. A block counts when you said
-- something in guild chat AND another guildmate did too (talking to
-- yourself doesn't count), at most 8 blocks per (UTC) day. Ten messages in a
-- row count once, so spamming gets nothing. Kept per character on this
-- computer: Settings().hof[character].social = { total, day, today, block, me, them, counted }.
------------------------------------------------------------------------
HF.SOCIAL_BLOCK = 900
HF.SOCIAL_DAY_CAP = 8

local function SocialState()
    local st = MyState()
    st.social = st.social or { total = 0 }
    return st.social
end

-- `fromMe`: you said it; otherwise a guildmate did. `now` for tests.
function HF:SocialNote(fromMe, now)
    now = now or time()
    local s = SocialState()
    local block = math.floor(now / self.SOCIAL_BLOCK)
    if s.block ~= block then
        s.block, s.me, s.them, s.counted = block, false, false, false
    end
    local day = tonumber(date("!%Y%m%d", now))
    if s.day ~= day then s.day, s.today = day, 0 end
    if fromMe then s.me = true else s.them = true end
    if s.me and s.them and not s.counted and (s.today or 0) < self.SOCIAL_DAY_CAP then
        s.counted = true
        s.today = (s.today or 0) + 1
        s.total = (s.total or 0) + 1
        self.dirty = true
    end
end

function HF:SocialTotal()
    local me = Me()
    local st = me and (ns.DB:Settings().hof or {})[me]
    return st and st.social and st.social.total or 0
end

function HF:OnGuildChat(_, _, sender)
    if issecretvalue and issecretvalue(sender) then return end
    local who = ns.NormalizeName(sender)
    if not who then return end
    self:SocialNote(who == Me())
end

function HF:Init()
    -- the statistics change with nearly every kill: note it, and share at
    -- most every 10 minutes
    ns:RegisterEvent("CRITERIA_UPDATE", function() HF.dirty = true end)
    ns:RegisterEvent("CHAT_MSG_GUILD", function(...) HF:OnGuildChat(...) end)
    local publish = ns.Safe(function() HF:Publish() end, "HallOfFame")
    self.startedAt = GetTime()
    C_Timer.After(30, publish)
    C_Timer.After(self.WINS_AFTER + 20, publish) -- champion wins, once guildmates' numbers are in
    C_Timer.NewTicker(self.PUBLISH_EVERY, function() if HF.dirty then publish() end end)
end
