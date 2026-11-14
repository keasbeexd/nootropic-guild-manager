--[[
    Nootropic Guild Manager - events from NGM Peon into the WoW calendar
    The code from NGM Peon (/ngm peon) carries the guild's events for the
    next 30 days. They're kept here, and /ngm peon lists the ones not yet
    in the calendar, each with an Add button: one click adds one, as a guild
    announcement (sign-ups stay in Discord). Adding needs a click (the game
    allows it only from one), and permission to add guild events.

    Each event is remembered as added with its start time, so it's never
    added twice; if its time changes in Discord, it's listed again.
    Remembered per character's guild (not shared with officers yet).

      ns.Calendar:Take(events)        keep the code's events -> how many to add
      ns.Calendar:Pending()           events still to add, soonest first
      ns.Calendar:Add(event)          true, or nil and why
      ns.Calendar.RealmTime(t)        server time -> the realm's date and time
]]
local _, ns = ...
local CAL = {}
ns.Calendar = CAL

CAL.TITLE_MAX = 31  -- the calendar's own limit
CAL.TEXT_MAX = 255
local KIND = { dungeon = "Dungeon", raid = "Raid", event = "Event" }

local function Store()
    local g = ns.DB:Guild()
    if not g then return nil end
    g.calendar = g.calendar or { events = {}, added = {} }
    return g.calendar
end

local function Key(e) return e.id .. ":" .. e.starts end

function CAL:Take(events)
    local s = Store()
    if not s then return 0 end
    s.events = events or {}
    -- forget what's long past
    local now = ns.DB:Now()
    for key, starts in pairs(s.added) do
        if type(starts) ~= "number" or starts < now - 7 * 86400 then s.added[key] = nil end
    end
    return #self:Pending()
end

function CAL:Pending()
    local s = Store()
    local list = {}
    if not s then return list end
    local now = ns.DB:Now()
    for _, e in ipairs(s.events) do
        if e.starts > now and not s.added[Key(e)] then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.starts < b.starts end)
    return list
end

-- Server time (UTC seconds) as the realm's own date and time, which is what
-- the calendar uses: the realm's clock now, against the server's.
function CAL.RealmTime(t)
    local cal = C_DateAndTime.GetCurrentCalendarTime()
    local now = GetServerTime()
    local realmNow = time({ year = cal.year, month = cal.month, day = cal.monthDay, hour = cal.hour, min = cal.minute, sec = 0 })
    local offset = realmNow - (now - now % 60)
    offset = math.floor(offset / 900 + 0.5) * 900 -- zones run in quarter hours
    return date("*t", t + offset)
end

-- Cuts text to at most n bytes without splitting a character.
local function Cut(s, n)
    if #s <= n then return s end
    s = s:sub(1, n)
    return (s:gsub("[\192-\255][\128-\191]*$", ""))
end

function CAL:CanAdd()
    if not (C_Calendar and C_Calendar.CreateGuildAnnouncementEvent and C_Calendar.AddEvent and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then
        return false, "This game client can't add calendar events."
    end
    if C_Calendar.CanAddEvent and not C_Calendar.CanAddEvent() then return false, "The game won't let you add calendar events right now." end
    return true
end

function CAL:Add(e)
    local ok, why = self:CanAdd()
    if not ok then return nil, why end
    if e.starts <= ns.DB:Now() then return nil, "That event has started." end
    local when = self.RealmTime(e.starts)
    local length = e.minutes >= 60 and (e.minutes / 60 .. " h") or (e.minutes .. " min")
    local text = ("%s, %s. %s%sSign up in Discord."):format(KIND[e.kind] or "Event", length, e.description or "", (e.description or "") ~= "" and " " or "")
    local done, err = pcall(function()
        if C_Calendar.CloseEvent then C_Calendar.CloseEvent() end
        C_Calendar.CreateGuildAnnouncementEvent()
        C_Calendar.EventSetTitle(Cut(e.title or "Event", self.TITLE_MAX))
        if C_Calendar.EventSetDescription then C_Calendar.EventSetDescription(Cut(text, self.TEXT_MAX)) end
        C_Calendar.EventSetDate(when.month, when.day, when.year)
        C_Calendar.EventSetTime(when.hour, when.min)
        C_Calendar.AddEvent()
    end)
    if not done then return nil, "The game refused: " .. tostring(err) end
    local s = Store()
    if s then s.added[Key(e)] = e.starts end
    return true
end

-- The game says when an add fails (no permission, a bad date): pass it on.
function CAL:Init()
    if not ns.RegisterEvent then return end
    ns:RegisterEvent("CALENDAR_UPDATE_ERROR", function(_, msg)
        if msg and msg ~= "" then ns:Print("|cfffb4934Calendar:|r " .. tostring(msg)) end
    end)
end
