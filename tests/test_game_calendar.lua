-- Test: resets and holidays from the game (Services/GameCalendar.lua).
-- The game's calendar is on the server's clock (here: UTC), so its times
-- are turned into real moments; a holiday lasting several days is listed
-- once; the read starts at today even when the Calendar window shows
-- another month; next month is read too; ended holidays and ones past 30
-- days are left out; secret values are skipped; the weekly reset and
-- holidays come soonest first, with the daily reset apart.
local ROOT = arg[1]
date, time = os.date, os.time
local ns = {}
function ns:Fire() end
function ns:On() end
local printed = {}
function ns:Print(m) printed[#printed + 1] = m end
ns.GOLD = ""
local events = {}
function ns:RegisterEvent(e, fn) events[e] = fn return true end
ns.Debounce = function(_, _, fn) fn() end
C_Timer = { After = function() end }
assert(loadfile(ROOT .. "/Services/GameCalendar.lua"))("NGM", ns)
local GC = ns.GameCalendar

-- now: Wed 2026-11-25 20:00 UTC
local now = os.time({ year = 2026, month = 11, day = 25, hour = 20, min = 0, sec = 0 }) -- local wall clock
now = now + (now - os.time(os.date("!*t", now))) -- that wall clock as UTC
local function ct(epoch)
    local t = os.date("!*t", epoch)
    return { year = t.year, month = t.month, monthDay = t.day, hour = t.hour, minute = t.min, weekday = t.wday }
end
local guild = {}
ns.DB = { Now = function() return now end, Guild = function() return guild end }

C_DateAndTime = {
    GetCurrentCalendarTime = function() return ct(now + 25) end, -- seconds off: rounded away
    GetSecondsUntilDailyReset = function() return 8 * 3600 end,
    GetSecondsUntilWeeklyReset = function() return 6 * 86400 end,
}
local DAY = 86400
-- holidays by start/end; each shows on every day it covers
local holidays = {
    { title = "Feast of Winter Veil", starts = now + 20 * DAY, ends = now + 38 * DAY, description = "Presents!" },
    { title = "Pilgrim's Bounty", starts = now - 2 * DAY, ends = now + 2 * DAY, description = "Turkeys |cffff0000everywhere|r" },
    { title = "Over already", starts = now - 5 * DAY, ends = now - 1 * DAY, description = "" },
    { title = "Too far", starts = now + 40 * DAY, ends = now + 42 * DAY, description = "" },
}
local viewMonth = { year = 2026, month = 10 } -- the Calendar window was left on October
local function abs(offset)
    local m = viewMonth.year * 12 + (viewMonth.month - 1) + offset
    return math.floor(m / 12), m % 12 + 1
end
local function daysIn(y, m) return os.date("!*t", os.time({ year = m == 12 and y + 1 or y, month = m == 12 and 1 or m + 1, day = 1, hour = 12 }) - DAY).day end
local function on(offset, day)
    local y, m = abs(offset)
    local out = {}
    local dayStart = os.time({ year = y, month = m, day = day, hour = 0 }); dayStart = dayStart + (dayStart - os.time(os.date("!*t", dayStart)))
    for _, h in ipairs(holidays) do
        if h.starts < dayStart + DAY and h.ends >= dayStart then out[#out + 1] = h end
    end
    out[#out + 1] = { raid = true }
    return out
end
C_Calendar = {
    OpenCalendar = function() C_Calendar.opened = (C_Calendar.opened or 0) + 1 end,
    GetMonthInfo = function(offset)
        local y, m = abs(offset or 0)
        return { year = y, month = m, numDays = daysIn(y, m), firstWeekday = 1 }
    end,
    GetNumDayEvents = function(offset, day) return #on(offset, day) end,
    GetDayEvent = function(offset, day, i)
        local h = on(offset, day)[i]
        if h.raid then return { title = "Molten Core", calendarType = "RAID_RESET", startTime = ct(now), endTime = ct(now) } end
        return { title = h.title, calendarType = "HOLIDAY", startTime = ct(h.starts), endTime = ct(h.ends) }
    end,
    GetHolidayInfo = function(offset, day, i)
        local h = on(offset, day)[i]
        return { name = h.title, description = h.description, startTime = ct(h.starts), endTime = ct(h.ends) }
    end,
}

assert(GC:Offset() % 900 == 0, "rounded to 15 minutes")
local list, types = GC:Holidays(now)
assert(#list == 2, "two holidays in the next 30 days, each once: " .. #list)
assert(list[1].title == "Pilgrim's Bounty" and list[1].starts == now - 2 * DAY and list[1].ends == now + 2 * DAY, "on now, real times")
assert(list[2].title == "Feast of Winter Veil" and list[2].starts == now + 20 * DAY, "December read too (next month)")
assert(list[2].description == "Presents!")
assert(not list[1].description:find("|", 1, true), "no | from the game's text")
assert(types.RAID_RESET and types.RAID_RESET > 0 and types.HOLIDAY > 0)

-- the Calendar window showing this month instead: same answer
viewMonth = { year = 2026, month = 11 }
assert(#GC:Holidays(now) == 2)

-- resets, read and kept, Upcoming soonest first, daily apart
local got = GC:Read()
assert(got.daily == now + 8 * 3600 and got.weekly == now + 6 * DAY)
assert(guild.gameCalendar == got, "kept for NGM Peon")
local up, daily = GC:Upcoming(now)
assert(daily == now + 8 * 3600)
assert(#up == 3 and up[1].title == "Pilgrim's Bounty" and up[2].kind == "weekly" and up[3].title == "Feast of Winter Veil")

-- once a holiday has ended it drops off without a new read
up = GC:Upcoming(now + 3 * DAY)
assert(#up == 2 and up[1].kind == "weekly", "ended holiday gone")

-- secret values (chat lockdown) are skipped, not read
issecretvalue = function(v) return v == "Feast of Winter Veil" end
assert(#GC:Holidays(now) == 1)
issecretvalue = nil

-- the tab asks the game again only when the last read is old
GC.last, guild.gameCalendar = nil, nil
C_Calendar.opened = 0
GC:Refresh()
assert(C_Calendar.opened == 1, "nothing read yet: ask")
GC:Read()
GC:Refresh()
assert(C_Calendar.opened == 1, "fresh: don't ask")
now = now + GC.REFRESH + 1
GC:Refresh()
assert(C_Calendar.opened == 2, "old: ask")

-- the game's answer arriving: read and kept
GC:Init()
guild.gameCalendar = nil
events.CALENDAR_UPDATE_EVENT_LIST()
assert(guild.gameCalendar and #guild.gameCalendar.holidays >= 1)

-- no calendar at all: no errors, nothing listed
C_Calendar, C_DateAndTime = nil, nil
GC.last, guild.gameCalendar = nil, nil
local l2 = GC:Holidays(now)
assert(#l2 == 0 and #GC:Upcoming(now) == 0)
GC:Check()
assert(printed[1]:find("C_Calendar: no"))

print("OK")
