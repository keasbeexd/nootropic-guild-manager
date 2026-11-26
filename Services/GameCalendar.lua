--[[
    Nootropic Guild Manager - Resets and holidays (3.1)
    What the game itself has coming, shown on the Upcoming Events tab next
    to NGM Peon's events: the next daily reset, the next weekly reset, and
    the holidays in the game's calendar for the next 30 days.

      Resets    C_DateAndTime.GetSecondsUntilDailyReset / WeeklyReset
      Holidays  C_Calendar: OpenCalendar asks the game for the calendar,
                CALENDAR_UPDATE_EVENT_LIST says it's here, GetDayEvent reads
                each day ("HOLIDAY" entries; one holiday lasting several days
                shows on each of them, so it's kept once). GetHolidayInfo
                gives its description.

    Every copy reads its own game, so nothing is synced between guildmates.
    Lean: the calendar is asked for once after login and again when the tab
    opens if the last read is over an hour old. The read is kept in the
    guild's saved data (g.gameCalendar) for NGM Peon (Discord Events).

    Calendar times are the game server's clock, not yours: each is turned
    into a real moment with the difference between the server's calendar
    "now" and GetServerTime(), rounded to 15 minutes (time zones are).

      ns.GameCalendar:Read()       -> { at, daily, weekly, holidays = {...} }
      ns.GameCalendar:Upcoming()   the weekly reset and holidays, soonest first
      ns.GameCalendar:Check()      what the game gives, in chat (/ngm events check)
]]
local _, ns = ...
local GC = {}
ns.GameCalendar = GC

GC.DAYS = 30
GC.REFRESH = 3600 -- seconds before the tab asks the game again

local function Now() return (ns.DB and ns.DB:Now()) or time() end

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- server calendar time -> real moment, with the offset from Offset()
local function Moment(ct, offset)
    if type(ct) ~= "table" or not (ct.year and ct.month and ct.monthDay) then return nil end
    return time({ year = ct.year, month = ct.month, day = ct.monthDay, hour = ct.hour or 0, min = ct.minute or 0, sec = 0 }) + offset
end

-- seconds to add to a server calendar time read as local time
function GC:Offset()
    local dt = rawget(_G, "C_DateAndTime")
    if not (dt and dt.GetCurrentCalendarTime) then return 0 end
    local ok, ct = pcall(dt.GetCurrentCalendarTime)
    if not ok or type(ct) ~= "table" then return 0 end
    local raw = Moment(ct, 0)
    if not raw then return 0 end
    local d = Now() - raw
    return math.floor(d / 900 + 0.5) * 900
end

function GC:Resets(now)
    now = now or Now()
    local dt = rawget(_G, "C_DateAndTime")
    local out = {}
    if dt then
        for key, fn in pairs({ daily = "GetSecondsUntilDailyReset", weekly = "GetSecondsUntilWeeklyReset" }) do
            local ok, s = pcall(dt[fn] or error)
            if ok and type(s) == "number" and s > 0 then out[key] = now + math.floor(s) end
        end
    end
    return out
end

-- The days to read: { offset, day, numDays } from the server's today on,
-- with month offsets counted from the month the game's calendar shows
-- (it's whatever the Calendar window last showed, so it isn't moved).
local function Days(cal, n)
    local ok, view = pcall(cal.GetMonthInfo, 0)
    local dt = rawget(_G, "C_DateAndTime")
    if not (ok and type(view) == "table" and dt and dt.GetCurrentCalendarTime) then return {} end
    local ok2, today = pcall(dt.GetCurrentCalendarTime)
    if not (ok2 and type(today) == "table") then return {} end
    local offset = (today.year * 12 + today.month) - (view.year * 12 + view.month)
    local day, out = today.monthDay, {}
    local okm, month = pcall(cal.GetMonthInfo, offset)
    local numDays = okm and type(month) == "table" and month.numDays or 31
    for _ = 1, n do
        out[#out + 1] = { offset = offset, day = day }
        day = day + 1
        if day > numDays then
            day, offset = 1, offset + 1
            okm, month = pcall(cal.GetMonthInfo, offset)
            numDays = okm and type(month) == "table" and month.numDays or 31
        end
    end
    return out
end

-- Holidays in the next GC.DAYS days (including ones already on), plus a
-- count of everything the calendar listed, by type (for Check).
function GC:Holidays(now)
    now = now or Now()
    local cal = rawget(_G, "C_Calendar")
    local list, types = {}, {}
    if not (cal and cal.GetNumDayEvents and cal.GetDayEvent and cal.GetMonthInfo) then return list, types end
    local offset, seen, upto = self:Offset(), {}, now + self.DAYS * 86400
    for _, d in ipairs(Days(cal, self.DAYS + 1)) do
        local ok, n = pcall(cal.GetNumDayEvents, d.offset, d.day)
        for i = 1, (ok and type(n) == "number") and n or 0 do
            local okE, ev = pcall(cal.GetDayEvent, d.offset, d.day, i)
            if okE and type(ev) == "table" and not Secret(ev.title) then
                local kind = ev.calendarType or "?"
                types[kind] = (types[kind] or 0) + 1
                if kind == "HOLIDAY" then
                    local starts, ends = Moment(ev.startTime, offset), Moment(ev.endTime, offset)
                    local key = (ev.title or "") .. "@" .. tostring(starts)
                    if starts and ends and not seen[key] and ends > now and starts <= upto then
                        seen[key] = true
                        local h = { title = (ev.title or ""):gsub("|", "/"), starts = starts, ends = ends, description = "" }
                        if cal.GetHolidayInfo then
                            local okH, info = pcall(cal.GetHolidayInfo, d.offset, d.day, i)
                            if okH and type(info) == "table" and type(info.description) == "string" and not Secret(info.description) then
                                h.description = info.description:gsub("|", "/")
                            end
                        end
                        list[#list + 1] = h
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.starts < b.starts end)
    return list, types
end

-- Reads both and keeps them (g.gameCalendar).
function GC:Read()
    local now = Now()
    local r = self:Resets(now)
    local holidays = self:Holidays(now)
    local out = { at = now, daily = r.daily, weekly = r.weekly, holidays = holidays }
    local g = ns.DB and ns.DB:Guild()
    if g then g.gameCalendar = out end
    self.last = out
    return out
end

function GC:Get()
    local g = ns.DB and ns.DB:Guild()
    return self.last or (g and g.gameCalendar) or nil
end

-- What the Upcoming Events tab lists from the game: the weekly reset and
-- the holidays, soonest first. Resets are worked out fresh each time (no
-- calendar needed); holidays come from the last read.
function GC:Upcoming(now)
    now = now or Now()
    local out = {}
    local r = self:Resets(now)
    if r.weekly then out[#out + 1] = { kind = "weekly", title = "Weekly reset", starts = r.weekly } end
    local got = self:Get()
    for _, h in ipairs(got and got.holidays or {}) do
        if h.ends > now then
            out[#out + 1] = { kind = "holiday", title = h.title, starts = h.starts, ends = h.ends, description = h.description }
        end
    end
    table.sort(out, function(a, b) return a.starts < b.starts end)
    return out, r.daily
end

-- Asks the game for its calendar; the answer comes as CALENDAR_UPDATE_EVENT_LIST.
function GC:Request()
    local cal = rawget(_G, "C_Calendar")
    if not (cal and cal.OpenCalendar) then return false end
    self.asked = Now()
    return (pcall(cal.OpenCalendar))
end

-- The tab opening: read now, and ask again if the last read is old.
function GC:Refresh()
    local got = self:Get()
    if not got or Now() - (got.at or 0) > self.REFRESH then self:Request() end
end

local function Short(s)
    if s >= 86400 then return ("%d d %d h"):format(s / 86400, (s % 86400) / 3600) end
    if s >= 3600 then return ("%d h %d min"):format(s / 3600, (s % 3600) / 60) end
    return ("%d min"):format(math.max(1, s / 60))
end
GC.Short = Short

-- /ngm events check: what the game gives, for testing on Forever.
function GC:Check()
    local now = Now()
    local cal, dt = rawget(_G, "C_Calendar"), rawget(_G, "C_DateAndTime")
    ns:Print(("Game calendar check. C_Calendar: %s, C_DateAndTime: %s."):format(cal and "yes" or "no", dt and "yes" or "no"))
    local r = self:Resets(now)
    ns:Print(("  Daily reset: %s. Weekly reset: %s."):format(
        r.daily and (date("%a %d %b, %H:%M", r.daily) .. " (in " .. Short(r.daily - now) .. ")") or "none",
        r.weekly and (date("%a %d %b, %H:%M", r.weekly) .. " (in " .. Short(r.weekly - now) .. ")") or "none"))
    ns:Print(("  Server clock offset: %+d min. Holidays shown in the Calendar's filter: %s."):format(
        self:Offset() / 60, tostring(GetCVar and GetCVar("calendarShowHolidays"))))
    local list, types = self:Holidays(now)
    local parts = {}
    for k, n in pairs(types) do parts[#parts + 1] = k .. " " .. n end
    table.sort(parts)
    ns:Print(("  Calendar entries, next %d days: %s."):format(self.DAYS, #parts > 0 and table.concat(parts, ", ") or "none (try again in a few seconds)"))
    ns:Print(("  Holidays: %d."):format(#list))
    for i = 1, math.min(#list, 10) do
        local h = list[i]
        ns:Print(("    %s: %s to %s"):format(h.title, date("%a %d %b, %H:%M", h.starts), date("%a %d %b, %H:%M", h.ends)))
    end
    self:Request()
end

function GC:Init()
    ns:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", function()
        ns.Debounce("gamecalendar", 1, function()
            GC:Read()
            ns:Fire("GAME_CALENDAR_CHANGED")
        end)
    end)
    -- once after login, when the game has settled
    C_Timer.After(15, function() GC:Request() end)
end
