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
    if not self:Available() then return nil end
    local out, any = {}, false
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

function HF:Init()
    -- the statistics change with nearly every kill: note it, and share at
    -- most every 10 minutes
    ns:RegisterEvent("CRITERIA_UPDATE", function() HF.dirty = true end)
    local publish = ns.Safe(function() HF:Publish() end, "HallOfFame")
    C_Timer.After(30, publish)
    C_Timer.NewTicker(self.PUBLISH_EVERY, function() if HF.dirty then publish() end end)
end
