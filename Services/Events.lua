--[[
    Nootropic Guild Manager - Upcoming Events (from NGM Peon)
    NGM Peon's code (/ngm peon) carries the guild's events for the next 30
    days: when, what, how long, how many are coming, and the Discord channel
    and server to sign up in. The Upcoming Events tab lists them, as the
    dashboard's Upcoming Events tab does. (The WoW calendar can't take
    them: the game only lets its own interface fill an event in.)

    An officer bringing the code in writes each as a guild record (EV:<id>,
    Core/Records.lua), so everyone's addon gets them through guild sync;
    events gone from NGM Peon (cancelled) are cleared. Anyone else keeps
    the code's events for themselves.

      ns.Events:Take(events)   the code's events -> upcoming, new, removed (counts)
      ns.Events:List()         upcoming events, soonest first
      ns.Events:Announce()     a chat line for each event this character
                               hasn't heard of (Options, Guild Feed), however
                               it arrived: NGM Desktop, /ngm peon or guild sync

    Events made in game (3.1, docs/EVENTS.md): EG:<id> records, shared with
    the guild by sync at once; with NGM Peon, also posted in Discord.

      ns.Events:KindsICanCreate()   { "dungeon", ... } for the Create form
      ns.Events:Create(fields)      -> id, or nil and why
      ns.Events:Edit(id, fields)    -> true, or nil and why
      ns.Events:Cancel(id)          -> true, or nil and why
      ns.Events:MayEdit(ev)         this character may edit or cancel it
    fields: { kind, starts, minutes, title, description }

    Sign-ups (3.1): ES:<event>:<member> records, as NGM Peon's post (ngm-hub
    src/events/model.ts): by role for dungeons and raids, Going for events;
    first come first in up to each role's limit, the rest on the bench. You
    sign up as your main, or pick an alt. With NGM Peon only linked
    characters may (LK), as on Discord.

      ns.Events:Parts(kind)         the buttons
      ns.Events:Fields(ev)          { { name =, value = } } as the post's fields
      ns.Events:Mine(ev)            your part and the character picked
      ns.Events:CanSignUp(ev)       true, or nil and why not
      ns.Events:SignUp(ev, part, picked)
]]
local _, ns = ...
local E = {}
ns.Events = E

local function B36(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local s, d = "", "0123456789abcdefghijklmnopqrstuvwxyz"
    while n > 0 do
        local r = n % 36
        s = d:sub(r + 1, r + 1) .. s
        n = (n - r) / 36
    end
    return s
end
local function Clean(s) return ((s or ""):gsub("[;\t\n]", ",")) end
-- one key per listed event, whichever side made it (NGM Peon's ids are numbers)
local function ListKey(ev) return ev.source == "game" and ("g" .. ev.id) or B36(ev.id) end
E.ListKey = ListKey

function E.Value(ev)
    return table.concat({ ev.kind, B36(ev.starts), B36(ev.minutes), B36(ev.coming or 0), Clean(ev.channel), Clean(ev.server), Clean(ev.title), Clean(ev.description) }, ";")
end

function E.Parse(id, v)
    if not v or v == "" then return nil end
    local f = {}
    for part in (v .. ";"):gmatch("([^;]*);") do f[#f + 1] = part end
    local starts, minutes, coming = tonumber(f[2] or "", 36), tonumber(f[3] or "", 36), tonumber(f[4] or "", 36)
    if not (starts and minutes) then return nil end
    return { id = tonumber(id, 36) or 0, kind = f[1], starts = starts, minutes = minutes, coming = coming or 0, channel = f[5] or "", server = f[6] or "",
             title = f[7] or "", description = table.concat(f, ";", 8) }
end

local function Local()
    local g = ns.DB:Guild()
    if not g then return nil end
    g.upcoming = g.upcoming or {}
    g.calendar = nil -- the old "Add to calendar" list
    return g.upcoming
end

function E:Take(events)
    events = events or {}
    local now = ns.DB:Now()
    local key = function(ev) return "EV:" .. B36(ev.id) end
    -- what was listed before, to say what's new and what's gone
    local before = {}
    for _, ev in ipairs(self:List()) do before[ListKey(ev)] = ev.starts end
    if ns.Sync and ns.Sync.CanWrite and ns.Sync:CanWrite("EV:0") then
        -- an officer: for the whole guild
        local wanted = {}
        for _, ev in ipairs(events) do
            local k, v = key(ev), E.Value(ev)
            wanted[k] = true
            local cur = ns.Sync:Get(k)
            if not cur or cur.v ~= v then ns.Sync:Set(k, v) end
        end
        -- upcoming ones NGM Peon no longer has (cancelled): cleared
        for k, rec in pairs(ns.Sync:Store("guild") or {}) do
            if k:sub(1, 3) == "EV:" and not wanted[k] and rec.v ~= "" then
                local ev = E.Parse(k:sub(4), rec.v)
                if ev and ev.starts > now then ns.Sync:Set(k, "") end
            end
        end
    end
    local l = Local()
    if l then
        -- started ones stay while their post does (NGM Peon lists only what's to come)
        local started = {}
        for _, ev in ipairs(l) do if ev.starts <= now and E.Shown(ev, now) then started[#started + 1] = ev end end
        wipe(l)
        for _, ev in ipairs(started) do l[#l + 1] = ev end
        -- kept as sent, so tidied like a shared record: no "|" (the game's
        -- escape character), since titles come from members on Discord
        for _, ev in ipairs(events) do
            for i = #l, 1, -1 do if l[i].id == ev.id then table.remove(l, i) end end
            local c = {}
            for k, v in pairs(ev) do c[k] = type(v) == "string" and (v:gsub("|", "/")) or v end
            l[#l + 1] = c
        end
    end
    local list = self:List()
    local added, after = 0, {}
    for _, ev in ipairs(list) do
        local id = ListKey(ev)
        after[id] = true
        if not before[id] and not ev.cancelled then added = added + 1 end
    end
    local removed = 0
    -- gone from NGM Peon while still to come (one that has started isn't "removed")
    for id, starts in pairs(before) do if not after[id] and starts > now then removed = removed + 1 end end
    ns:Fire("EVENTS_CHANGED")
    return #list, added, removed
end

-- NGM Peon's post for an event (EL): the event made in game it came from,
-- its limits, its reminder (minutes before) and, once cancelled, when; a
-- cancelled post carries the event too (it isn't upcoming any more).
--   "<EG id>;<tank>,<healer>,<dps>;<remind>;<cancelled>[;<EV value>]"
function E.ParseLink(id, v)
    local game, t, h, d, rest = (v or ""):match("^(%w*);(%d*),(%d*),(%d*)(.*)$")
    if not game then return nil end
    local out = { game = game ~= "" and game or nil, limits = { tank = tonumber(t), healer = tonumber(h), dps = tonumber(d) } }
    local remind, at, snap = rest:match("^;(%w*);(%w*);?(.*)$")
    if remind then
        out.remind = tonumber(remind, 36)
        out.cancelledAt = tonumber(at, 36)
        if out.cancelledAt and snap ~= "" then out.event = E.Parse(id, snap) end
    end
    return out
end

-- Listed as long as its Discord post stays up: NGM Peon's "Clear old
-- posts" (GS:evranks keep) after it ends, or after it was cancelled. With
-- Never, or without NGM Peon: until it ends. Sign-ups close at the start.
function E.Shown(ev, now, cancelledAt)
    local rules = ns.Sync and ns.Sync.PeonGuild and ns.Sync:PeonGuild() and ns.Sync:EventRules()
    local keep = rules and rules.keep
    local ends = ev.starts + ev.minutes * 60
    if ev.cancelled then
        if keep then return now < (cancelledAt or now) + keep * 60 end
        return now < ends
    end
    return now < ends + (keep or 0) * 60
end

function E:List()
    local now, byId, list = ns.DB:Now(), {}, {}
    local store = (ns.Sync and ns.Sync.Store and ns.Sync:Store("guild")) or {}
    for k, rec in pairs(store) do
        if k:sub(1, 3) == "EV:" then
            local ev = E.Parse(k:sub(4), rec.v)
            if ev then byId[k:sub(4)] = ev end
        end
    end
    -- what this character brought in itself (not an officer: not shared)
    for _, ev in ipairs(Local() or {}) do
        local id = B36(ev.id)
        if not byId[id] then byId[id] = ev end
    end
    -- NGM Peon's posts (EL), from guild sync and this character's own copies
    local links = {}
    for _, src in ipairs({ store, (ns.Sync.PeonOwn and ns.Sync:PeonOwn()) or {} }) do
        for k in pairs(src) do if k:sub(1, 3) == "EL:" then links[k:sub(4)] = true end end
    end
    for id in pairs(links) do
        local rec = ns.Sync.Plan and ns.Sync:Plan("EL:" .. id) or store["EL:" .. id]
        local link = rec and E.ParseLink(id, rec.v)
        if link then
            if link.cancelledAt and link.event and not byId[id] then byId[id] = link.event end
            if byId[id] then byId[id].link = link end
        end
    end
    local posted = {}
    for _, ev in pairs(byId) do
        ev.source = "peon"
        local link, cancelledAt = ev.link, nil
        ev.link = nil
        if link then
            ev.limits, ev.remind = link.limits, link.remind
            if link.cancelledAt then ev.cancelled, cancelledAt = true, link.cancelledAt end
            if link.game then
                ev.game, posted[link.game] = link.game, true
                local grec = store["EG:" .. link.game]
                local held = grec and ns.Sync.ParseGameEvent(grec.v)
                if held then ev.creator = held.creator end
                if held and held.cancelled then
                    -- cancelled in game: until NGM Peon has it, Discord doesn't say so yet
                    ev.cancelledInGame, ev.cancelledBy = true, grec.a
                    if not ev.cancelled then ev.cancelled, ev.cancelUnsent = true, true end
                    cancelledAt = cancelledAt or grec.t
                elseif held and not ev.cancelled then
                    -- made in game: still edited there, through its EG record
                    held.id, held.source = link.game, "game"
                    ev.made = held
                    -- changed in game since NGM Peon posted it (it can't be changed
                    -- elsewhere): shown as changed (clocks differ, so by content)
                    if held.title ~= ev.title or held.starts ~= ev.starts or held.minutes ~= ev.minutes
                        or (held.description or "") ~= (ev.description or "") then
                        ev.title, ev.description, ev.starts, ev.minutes = held.title, held.description, held.starts, held.minutes
                        ev.changed = true
                    end
                end
            end
        end
        if E.Shown(ev, now, cancelledAt) then list[#list + 1] = ev end
    end
    -- made in game (shared through guild sync); once NGM Peon has posted one, it's listed as NGM Peon's
    for k, rec in pairs(store) do
        if k:sub(1, 3) == "EG:" and not posted[k:sub(4)] then
            local ev = ns.Sync.ParseGameEvent(rec.v)
            if ev and E.Shown(ev, now, rec.t) then
                ev.id, ev.source, ev.channel, ev.server, ev.coming = k:sub(4), "game", "", "", 0
                ev.cancelledInGame, ev.cancelledBy = ev.cancelled, rec.a
                list[#list + 1] = ev
            end
        end
    end
    table.sort(list, function(a, b) return a.starts < b.starts end)
    return list
end

------------------------------------------------------------------------
-- Events made in game (EG records)
------------------------------------------------------------------------
-- Changes this session that NGM Peon hasn't had yet (the game writes its
-- saved data, which NGM Desktop sends, only at /reload or logout).
E.unsent = {}
function E:Unsent() return next(self.unsent) ~= nil end
local function Mark(key) E.unsent[key] = true end

E.DURATIONS = { 30, 60, 90, 120, 180, 240, 300, 360 } -- minutes, as NGM Peon's form (ngm-hub src/events/model.ts)
E.MAX_TITLE, E.MAX_DESCRIPTION = 100, 400

-- text for a record: one line, no ";" in the title (the value's separator)
local function OneLine(s, max) return ((s or ""):gsub("[\r\n\t]+", " "):gsub("|", "/"):gsub("^%s+", ""):gsub("%s+$", "")):sub(1, max) end

function E.GameValue(ev)
    return table.concat({ ev.kind, B36(ev.starts), B36(ev.minutes), ev.creator, ev.cancelled and "x" or "",
        (OneLine(ev.title, E.MAX_TITLE):gsub(";", ",")), OneLine(ev.description, E.MAX_DESCRIPTION) }, ";")
end

function E:KindsICanCreate()
    local out = {}
    for _, k in ipairs(ns.Sync.EVENT_KINDS) do
        if ns.Sync:MayCreateEvent(ns.PlayerFullName(), k) then out[#out + 1] = k end
    end
    return out
end

local function Check(f)
    if not (f.kind == "dungeon" or f.kind == "raid" or f.kind == "event") then return "Pick Dungeon, Raid or Event." end
    if OneLine(f.title, E.MAX_TITLE) == "" then return "Give it a title." end
    if not f.starts or f.starts <= ns.DB:Now() then return "Pick a time that's still to come." end
    local okLength = false
    for _, m in ipairs(E.DURATIONS) do if m == f.minutes then okLength = true end end
    if not okLength then return "Pick a length." end
end

local function NewId()
    return B36(ns.DB:Now()) .. B36(math.random(36, 36 * 36 - 1))
end

function E:Create(f)
    local why = Check(f)
    if why then return nil, why end
    local me = ns.PlayerFullName()
    if not ns.Sync:MayCreateEvent(me, f.kind) then return nil, "Your rank can't create that kind of event." end
    local id = NewId()
    local ok, err = ns.Sync:Set("EG:" .. id, E.GameValue({ kind = f.kind, starts = f.starts, minutes = f.minutes, creator = me, title = f.title, description = f.description }))
    if not ok then return nil, err end
    Mark("EG:" .. id)
    return id
end

local function Held(id)
    local rec = (ns.Sync:Store("guild") or {})["EG:" .. id]
    return rec and ns.Sync.ParseGameEvent(rec.v)
end

function E:MayEdit(ev)
    if not ev or ev.source ~= "game" or ev.cancelled then return false end
    local me = ns.PlayerFullName()
    return ns.Sync.Same(me, ev.creator) or ns.Sync:EventManager(me)
end

function E:Edit(id, f)
    local was = Held(id)
    if not was or was.cancelled then return nil, "That event is gone." end
    if not self:MayEdit({ source = "game", creator = was.creator }) then return nil, "Only its creator or an officer can change it." end
    if was.starts <= ns.DB:Now() then return nil, "It has started: it can't be changed now." end
    f.kind = was.kind -- the kind stays (as on the dashboard)
    local why = Check(f)
    if why then return nil, why end
    Mark("EG:" .. id)
    return ns.Sync:Set("EG:" .. id, E.GameValue({ kind = was.kind, starts = f.starts, minutes = f.minutes, creator = was.creator, title = f.title, description = f.description }))
end

function E:Cancel(id)
    local was = Held(id)
    if not was or was.cancelled then return nil, "That event is gone." end
    if not self:MayEdit({ source = "game", creator = was.creator }) then return nil, "Only its creator or an officer can cancel it." end
    was.cancelled = true
    Mark("EG:" .. id)
    return ns.Sync:Set("EG:" .. id, E.GameValue(was))
end

------------------------------------------------------------------------
-- Sign-ups (ES records)
------------------------------------------------------------------------
E.PART_LABEL = { tank = "Tanks", healer = "Healers", dps = "DPS", going = "Going", tentative = "Tentative", absent = "Can't come" }
E.PART_BUTTON = { tank = "Tank", healer = "Healer", dps = "DPS", going = "Going", tentative = "Tentative", absent = "Can't come" }
E.LIMITS = { dungeon = { tank = 1, healer = 1, dps = 3 }, raid = {}, event = {} } -- NGM Peon's defaults

function E:Parts(kind)
    if kind == "event" then return { "going", "tentative", "absent" } end
    return { "tank", "healer", "dps", "tentative", "absent" }
end

-- the sign-up key's event part: "g<EG id>" or "p<NGM Peon id>"
function E.SignupEvent(ev) return ev.source == "game" and ("g" .. ev.id) or ("p" .. B36(ev.id)) end

-- every sign-up record for this event, newest per member: NGM Peon's id,
-- and (once NGM Peon has posted an event made in game) the ones from before
local function Records(ev)
    local prefixes = { "ES:" .. E.SignupEvent(ev) .. ":" }
    if ev.game then prefixes[2] = "ES:g" .. ev.game .. ":" end
    local best = {}
    -- guild sync's, and NGM Peon's copies this member keeps for themselves
    for _, src in ipairs({ (ns.Sync and ns.Sync:Store("guild")) or {}, (ns.Sync and ns.Sync.PeonOwn and ns.Sync:PeonOwn()) or {} }) do
        for k, rec in pairs(src) do
            for _, prefix in ipairs(prefixes) do
                if k:sub(1, #prefix) == prefix then
                    local member = k:sub(#prefix + 1)
                    if not best[member] or rec.t > best[member].t then best[member] = rec end
                end
            end
        end
    end
    return best
end

function E:SignUps(ev)
    local out = {}
    for member, rec in pairs(Records(ev)) do
        local part, picked = (rec.v or ""):match("^(%l+);(.*)$")
        if part then out[#out + 1] = { member = member, part = part, picked = picked, name = picked ~= "" and picked or member, t = rec.t } end
    end
    return out
end

-- who's in and who's on the bench (first come first in, per role)
function E.Place(list, limits)
    table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.member < b.member end)
    local inn, bench = { tank = {}, healer = {}, dps = {}, going = {}, tentative = {}, absent = {} }, {}
    for _, s in ipairs(list) do
        local cap = limits[s.part]
        if inn[s.part] and cap and #inn[s.part] >= cap then bench[#bench + 1] = s
        elseif inn[s.part] then inn[s.part][#inn[s.part] + 1] = s end
    end
    return inn, bench
end

local function Who(s)
    local e = ns.Roster and ns.Roster.byName and ns.Roster.byName[s.name]
    local name = ns.ShortName and ns.ShortName(s.name) or s.name
    if e and (e.className or "") ~= "" then return name .. " · " .. e.className .. ((e.level or 0) > 0 and (" " .. e.level) or "") end
    return name
end

-- the post's fields, as NGM Peon's (src/events/model.ts fields)
function E:Fields(ev)
    local limits = ev.limits or E.LIMITS[ev.kind] or {}
    local inn, bench = E.Place(self:SignUps(ev), limits)
    local function list(xs) if #xs == 0 then return "-" end local t = {} for i, s in ipairs(xs) do t[i] = Who(s) end return table.concat(t, ", ") end
    local out = {}
    if ev.kind == "event" then
        out[#out + 1] = { name = ("Going (%d)"):format(#inn.going), value = list(inn.going) }
    else
        for _, part in ipairs({ "tank", "healer", "dps" }) do
            out[#out + 1] = { name = ("%s (%d%s)"):format(E.PART_LABEL[part], #inn[part], limits[part] and ("/" .. limits[part]) or ""), value = list(inn[part]) }
        end
    end
    if #bench > 0 then out[#out + 1] = { name = ("Bench (%d)"):format(#bench), value = list(bench) } end
    if #inn.tentative > 0 then out[#out + 1] = { name = ("Tentative (%d)"):format(#inn.tentative), value = list(inn.tentative) } end
    if #inn.absent > 0 then
        local t = {} for i, s in ipairs(inn.absent) do t[i] = ns.ShortName and ns.ShortName(s.name) or s.name end
        out[#out + 1] = { name = ("Can't come (%d)"):format(#inn.absent), value = table.concat(t, ", ") }
    end
    return out
end

local function MyMain() return ns.DB:RootOf(ns.PlayerFullName()) or ns.PlayerFullName() end

function E:Mine(ev)
    local rec = Records(ev)[MyMain()]
    if not rec or (rec.v or "") == "" then return nil end
    return rec.v:match("^(%l+);(.*)$")
end

-- Is your sign-up for this event still to reach the Discord post? NGM
-- Peon sends back every sign-up it has ("" for none), a second newer than
-- the change it took from the game, so its copy replaces yours (newest
-- wins): yours is unsent while the newest is still your own. Holds across
-- /reload.
function E:MineUnsent(ev)
    if not (ns.Sync and ns.Sync.PeonGuild and ns.Sync:PeonGuild()) then return false end
    local me = MyMain()
    local peonName = ns.Sync.PEON or "NGM Peon"
    local keys = { "ES:" .. E.SignupEvent(ev) .. ":" .. me }
    if ev.game then keys[2] = "ES:g" .. ev.game .. ":" .. me end
    local newest
    for _, src in ipairs({ ns.Sync:Store("guild") or {}, (ns.Sync.PeonOwn and ns.Sync:PeonOwn()) or {} }) do
        for _, k in ipairs(keys) do
            local rec = src[k]
            if rec and (not newest or rec.t > newest.t or (rec.t == newest.t and rec.a == peonName)) then newest = rec end
        end
    end
    if not newest or newest.a == peonName then return false end
    if ev.source == "game" then return newest.v ~= "", newest end -- not posted yet: it goes with its event
    return true, newest
end

function E:CanSignUp(ev, picked)
    if ev.cancelled then return nil, "Cancelled: sign-ups are closed." end
    if ns.DB.HasPerm and not ns.DB:HasPerm("signup") then return nil, "Your rank can't sign up for events (the Guild Master's Permissions)." end
    if ev.starts <= ns.DB:Now() then return nil, "Sign-ups are closed: it has started." end
    if ns.Sync:PeonGuild() and not ns.Sync:Linked((picked and picked ~= "") and picked or MyMain()) then
        return nil, "Link your characters to sign up: type /ngm link in Discord."
    end
    return true
end

function E:SignUp(ev, part, picked)
    if not ns.Sync.PARTS[part] then return nil, "Pick a role." end
    if picked == nil then picked = select(2, self:Mine(ev)) or "" end
    local ok, why = self:CanSignUp(ev, picked)
    if not ok then return nil, why end
    Mark("ES:" .. E.SignupEvent(ev))
    return ns.Sync:Set("ES:" .. E.SignupEvent(ev) .. ":" .. MyMain(), part .. ";" .. picked)
end

-- your characters to pick from: your main and its alts
function E:MyCharacters()
    local main = MyMain()
    local out = { main }
    for _, alt in ipairs(ns.DB:GetAltsOf(main) or {}) do out[#out + 1] = alt end
    return out
end

local KIND = { raid = "raid", dungeon = "dungeon", event = "event" }

-- One chat line per event this character hasn't been told about, once
-- (g.eventsSeen). The first time, everything listed counts as seen.
function E:Announce()
    local g = ns.DB:Guild()
    if not g then return end
    local list = self:List()
    local first = g.eventsSeen == nil
    local seen = g.eventsSeen or {}
    local now = ns.DB:Now()
    local on = ns.DB:Settings().eventNotices ~= false
    local told = 0
    for _, ev in ipairs(list) do
        local id = ListKey(ev)
        if not seen[id] and not ev.cancelled then
            seen[id] = ev.starts
            if on and not first and told < 5 then
                told = told + 1
                local where = ev.channel ~= "" and (" Sign up in " .. ns.GOLD .. "#" .. ev.channel .. "|r on Discord.") or ""
                ns:Print(("New %s posted: " .. ns.GOLD .. "%s|r, %s (your time).%s"):format(
                    KIND[ev.kind] or "event", ev.title ~= "" and ev.title or "untitled", date("%a %d %b, %H:%M", ev.starts), where))
            end
        end
    end
    if told > 0 and ns.GuildFeed then ns.GuildFeed:PlayFeed("event") end
    for id, starts in pairs(seen) do if starts < now - 86400 then seen[id] = nil end end -- done with
    g.eventsSeen = seen
end

-- NGM Peon's reminder, in game too: at the post's reminder time (EL), a
-- chat line for each event you're signed up for (not Can't come), once.
function E:Remind()
    local g = ns.DB:Guild()
    if not g then return end
    local now = ns.DB:Now()
    g.eventsReminded = g.eventsReminded or {}
    local done = g.eventsReminded
    for k, at in pairs(done) do if at < now - 86400 then done[k] = nil end end
    for _, ev in ipairs(self:List()) do
        if ev.remind and not ev.cancelled and ev.starts > now and now >= ev.starts - ev.remind * 60 then
            -- keyed by its time too: an event moved later is reminded again, as on Discord
            local key = ListKey(ev) .. "@" .. ev.starts
            local part = not done[key] and self:Mine(ev)
            if part and part ~= "absent" then
                done[key] = ev.starts
                local left = ev.starts - now
                ns:Print(("Reminder: %s%s|r starts in %s."):format(ns.GOLD, ev.title ~= "" and ev.title or "Event", ns.GameCalendar.Short(left)))
            end
        end
    end
end

function E:Init()
    ns:On("EVENTS_CHANGED", function() E:Announce() end)
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, function() E:Remind() end) end
end
