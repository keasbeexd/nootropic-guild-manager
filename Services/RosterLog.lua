--[[
    Nootropic Guild Manager - Roster change log (officers)
    Turns changes to the guild itself into audit entries:

      Guild event log   joins (and who invited them), rejoins, leaves, kicks,
                        promotions and demotions, with who did each one
      Roster snapshots  level-ups, public and officer note changes, and name
                        changes (same character GUID, new name)

    Join dates and "rank since" are also kept as their own records (JN, RK)
    so they outlast the audit's retention.

    Every officer sees the same changes. Entry ids are built from the change
    itself (not from who noticed it or when), so the copies merge. Event-log
    times are only known to the hour ("3 hours ago"), so the same event can
    land an hour apart on two clients: anything with the same signature
    within S.EVENT_DEDUPE is treated as one event.
]]
local _, ns = ...
local RL = {}
ns.RosterLog = RL

RL.QUERY_INTERVAL = 600          -- ask the server for the event log every 10 minutes
RL.SNAPSHOT_KEEP = 30 * 86400    -- forget characters not seen in the roster for 30 days

local function Now() return ns.DB:Now() end
local function Window() return ns.Sync.EVENT_DEDUPE end

-- The event log says how long ago something happened: years, months, days, hours.
local function EventTime(now, y, mo, d, h)
    return now - ((((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24 + (h or 0)) * 3600)
end

local function Id(...)
    local S = ns.Sync
    local s = table.concat({ ... }, "|")
    return "r" .. S.Base36(S.Hash(s)) .. S.Base36(S.Hash(s:reverse()))
end

------------------------------------------------------------------------
-- Writing entries
------------------------------------------------------------------------
-- Signatures of the event-log entries already in the audit: sig -> { times }
function RL:SigIndex()
    local index = {}
    for _, e in ipairs(ns.Sync:AuditEntries()) do
        local sig = ns.Sync.EventSig(e.typ, e.member, e.new)
        if sig then
            index[sig] = index[sig] or {}
            table.insert(index[sig], e.t)
        end
    end
    return index
end

local function Known(index, sig, t)
    for _, seen in ipairs(index[sig] or {}) do
        if math.abs(seen - t) <= Window() then return true end
    end
    return false
end

-- An event-log entry (GM membership, GK rank). Skipped when one like it is
-- already recorded, or when it's older than the audit keeps.
function RL:EventEntry(index, cutoff, typ, member, author, t, old, new, ref, batch)
    if not member or t < cutoff then return end
    local sig = ns.Sync.EventSig(typ, member, new)
    if Known(index, sig, t) then return end
    local id = Id(typ, member, new, ref or "", math.floor(t / Window()))
    if ns.Sync:AddAuditEntry(id, t, author, member, typ, old, new, ref, batch) then
        index[sig] = index[sig] or {}
        table.insert(index[sig], t)
    end
end

-- Join date record: written for a newer join, never moved back by an old one.
function RL:SaveJoined(member, t, by)
    local cur = ns.Sync:Get("JN:" .. member)
    if cur and cur.t >= t - Window() then return end
    ns.Sync:Set("JN:" .. member, ("%d;%s"):format(t, by or ""), { time = t, noBatch = true })
end

function RL:SaveRank(member, t, rank, by)
    local cur = ns.Sync:Get("RK:" .. member)
    if cur and cur.t > t then return end
    ns.Sync:Set("RK:" .. member, ("%d;%s;%s"):format(t, rank or "", by or ""), { time = t, noBatch = true })
end

------------------------------------------------------------------------
-- The guild event log
------------------------------------------------------------------------
function RL:Query()
    if not (ns.IsOfficer() and ns.Sync.readyFor) then return end
    if QueryGuildEventLog then QueryGuildEventLog() end
end

function RL:ReadEventLog()
    if not (ns.IsOfficer() and ns.Sync.readyFor and GetNumGuildEvents and GetGuildEventInfo) then return end
    if not ns.DB:Guild() then return end
    local now = Now()
    local events = {}
    for i = 1, GetNumGuildEvents() or 0 do
        local typ, p1, p2, rank, y, mo, d, h = GetGuildEventInfo(i)
        if typ and p1 and p1 ~= "" then
            events[#events + 1] = {
                typ = typ, i = i, rank = rank,
                p1 = ns.NormalizeName(p1),
                p2 = (p2 and p2 ~= "") and ns.NormalizeName(p2) or nil,
                t = EventTime(now, y, mo, d, h),
            }
        end
    end
    if #events == 0 then return end
    -- oldest first (ties keep the log's order), so later events win
    table.sort(events, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.i < b.i
    end)

    local cutoff = now - ns.Sync:RetentionSeconds()
    local index = self:SigIndex()
    local batch = "log" .. ns.Sync.Base36(now)
    local invites, prevRank = {}, {}
    for _, ev in ipairs(events) do
        if ev.typ == "invite" and ev.p2 then
            invites[ev.p2] = ev
        elseif ev.typ == "join" then
            local who = ev.p1
            local inv = invites[who]
            local by = (inv and inv.t <= ev.t + 3600 and ev.t - inv.t <= 7 * 86400) and inv.p1 or nil
            local prior = ns.Sync:Get("JN:" .. who)
            local kind = (prior and prior.t < ev.t - Window()) and "rejoin" or "join"
            self:EventEntry(index, cutoff, "GM", who, by or who, ev.t, "", kind, by or "", batch)
            self:SaveJoined(who, ev.t, by)
        elseif ev.typ == "quit" then
            self:EventEntry(index, cutoff, "GM", ev.p1, ev.p1, ev.t, "", "quit", "", batch)
        elseif ev.typ == "remove" and ev.p2 then
            self:EventEntry(index, cutoff, "GM", ev.p2, ev.p1, ev.t, "", "remove", "", batch)
        elseif (ev.typ == "promote" or ev.typ == "demote") and ev.p2 then
            self:EventEntry(index, cutoff, "GK", ev.p2, ev.p1, ev.t, prevRank[ev.p2] or "", ev.rank or "", ev.typ, batch)
            prevRank[ev.p2] = ev.rank
            self:SaveRank(ev.p2, ev.t, ev.rank, ev.p1)
        end
    end
end

------------------------------------------------------------------------
-- Roster snapshots: level, notes, names
------------------------------------------------------------------------
function RL:OnRoster(members)
    if not ns.Sync.readyFor or #members == 0 then return end
    local g = ns.DB:Guild()
    if not g then return end
    local now = Now()
    local snap = g.rosterSnap
    local first = snap == nil
    snap = snap or {}
    local officer = ns.IsOfficer()
    local S = ns.Sync
    local batch = "roster" .. S.Base36(now)
    for _, e in ipairs(members) do
        local key = e.guid or e.full
        local old = snap[key]
        if old and officer and not first then
            if e.guid and old.n and old.n ~= e.full then
                S:AddAuditEntry(Id("NC", e.guid, old.n, e.full), now, "", e.full, "NC", old.n, e.full, "", batch)
            end
            if old.l and old.l > 0 and e.level > old.l then
                S:AddAuditEntry(Id("LV", key, e.level), now, "", e.full, "LV", tostring(old.l), tostring(e.level), "", batch)
            end
            if old.p and old.p ~= e.publicNote then
                S:AddAuditEntry(Id("GN", key, "public", old.p, e.publicNote), now, "", e.full, "GN", old.p, e.publicNote, "public", batch)
            end
            if old.o and old.o ~= e.officerNote then
                S:AddAuditEntry(Id("GN", key, "officer", old.o, e.officerNote), now, "", e.full, "GN", old.o, e.officerNote, "officer", batch)
            end
        end
        snap[key] = {
            n = e.full, l = e.level, p = e.publicNote,
            -- officer notes read as "" for ranks that can't see them: only
            -- compare them while you can
            o = officer and e.officerNote or nil,
            s = now,
        }
    end
    for key, rec in pairs(snap) do
        if (rec.s or 0) < now - self.SNAPSHOT_KEEP then snap[key] = nil end
    end
    g.rosterSnap = snap
end

------------------------------------------------------------------------
-- What the profile and tooltips show
------------------------------------------------------------------------
-- { t, by } or nil
function RL:Joined(full)
    local m = ns.DB:GetMember(full)
    return m and m.joined
end

-- { t, rank, by } or nil
function RL:RankSince(full)
    local m = ns.DB:GetMember(full)
    return m and m.rankSince
end

-- "Joined Oct 12, 2026 (invited by Mira)", "Officer since Nov 3, 2026", or nil
function RL:Lines(full)
    if not ns.IsOfficer() then return nil end
    local lines = {}
    local j = self:Joined(full)
    if j then
        lines[#lines + 1] = "Joined " .. date("%b %d, %Y", j.t)
            .. (j.by and (" (invited by " .. ns.ShortName(j.by) .. ")") or "")
    end
    local r = self:RankSince(full)
    if r and r.rank then
        lines[#lines + 1] = r.rank .. " since " .. date("%b %d, %Y", r.t)
            .. (r.by and (" (by " .. ns.ShortName(r.by) .. ")") or "")
    end
    return #lines > 0 and lines or nil
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
function RL:Init()
    ns:RegisterEvent("GUILD_EVENT_LOG_UPDATE", function()
        ns.Debounce("guildeventlog", 1, ns.Safe(function() RL:ReadEventLog() end, "RosterLog"))
    end)
    local function tick()
        RL:Query()
        C_Timer.After(RL.QUERY_INTERVAL, tick)
    end
    -- give the guild data and sync a moment to load first
    C_Timer.After(20, tick)
end
