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

    The calls follow Blizzard's own calendar (Blizzard_Calendar, Forever):
    the calendar opened first (OpenCalendar), then create, date, title,
    description, time, type, add. It's only marked added once the game says
    so (CALENDAR_NEW_EVENT); an error (CALENDAR_UPDATE_ERROR) leaves it listed.

      ns.Calendar:Take(events)        keep the code's events -> how many to add
      ns.Calendar:Pending()           events still to add, soonest first
      ns.Calendar:Add(event)          true (sent), or nil and why
      ns.Calendar:Prepare()           asks the game for the calendar (before adding)
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
    -- tests up to 29 marked events added before the game said so (and the
    -- adds failed): start that list afresh, once
    if not g.calendar.confirmed then
        g.calendar.confirmed = true
        g.calendar.added = {}
    end
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

-- The calendar has to be opened before events can be made (Blizzard's
-- calendar does this when it opens).
function CAL:Prepare()
    if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
end

function CAL:Add(e)
    local ok, why = self:CanAdd()
    if not ok then return nil, why end
    if e.starts <= ns.DB:Now() then return nil, "That event has started." end
    if self.pending then return nil, "Still adding the last one. Try again in a moment." end
    self:Prepare()
    local when = self.RealmTime(e.starts)
    local length = e.minutes >= 60 and (e.minutes / 60 .. " h") or (e.minutes .. " min")
    local text = ("%s, %s. %s%sSign up in Discord."):format(KIND[e.kind] or "Event", length, e.description or "", (e.description or "") ~= "" and " " or "")
    local done, err = pcall(function()
        -- in Blizzard's order (CalendarDayContextMenu_CreateGuildAnnouncement,
        -- CalendarCreateEventFrame_Update, the Create button)
        if C_Calendar.CloseEvent then C_Calendar.CloseEvent() end
        C_Calendar.CreateGuildAnnouncementEvent()
        C_Calendar.EventSetDate(when.month, when.day, when.year)
        C_Calendar.EventSetTitle(Cut(e.title or "Event", self.TITLE_MAX))
        if C_Calendar.EventSetDescription then C_Calendar.EventSetDescription(Cut(text, self.TEXT_MAX)) end
        C_Calendar.EventSetTime(when.hour, when.min)
        if C_Calendar.EventSetType and Enum and Enum.CalendarEventType and Enum.CalendarEventType.Other then
            C_Calendar.EventSetType(Enum.CalendarEventType.Other)
        end
        C_Calendar.AddEvent()
    end)
    if not done then return nil, "The game refused: " .. tostring(err) end
    -- added once the game says so (Confirmed), not before
    self.pending = { key = Key(e), starts = e.starts, title = e.title }
    if C_Timer then
        local mine = self.pending
        C_Timer.After(15, function() if CAL.pending == mine then CAL.pending = nil; ns:Fire("CALENDAR_RESULT", false, "No answer from the game. Try again.") end end)
    end
    return true
end

-- The game: the event is made.
function CAL:Confirmed()
    local p = self.pending
    if not p then return end
    self.pending = nil
    local s = Store()
    if s then s.added[p.key] = p.starts end
    ns:Fire("CALENDAR_RESULT", true, p.title)
end

-- The game: it wasn't (msg: the game's error key, e.g. CALENDAR_ERROR_NEEDS_TITLE).
function CAL:Failed(msg)
    if not self.pending then return false end
    self.pending = nil
    local text = (msg and _G[msg]) or tostring(msg)
    ns:Fire("CALENDAR_RESULT", false, text)
    return true
end

-- The game says when an add fails (no permission, a bad date): pass it on.
function CAL:Init()
    if not ns.RegisterEvent then return end
    ns:RegisterEvent("CALENDAR_NEW_EVENT", function() CAL:Confirmed() end)
    ns:RegisterEvent("CALENDAR_UPDATE_ERROR", function(_, msg)
        -- ours: shown in the Add to calendar window; anything else, in chat
        if not CAL:Failed(msg) and msg and msg ~= "" then ns:Print("|cfffb4934Calendar:|r " .. tostring((msg and _G[msg]) or msg)) end
    end)
end
