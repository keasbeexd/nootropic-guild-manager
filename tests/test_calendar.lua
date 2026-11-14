-- Test: events from NGM Peon's code into the WoW calendar: the code's E lines
-- (the same example as ngm-hub's EVENT_VECTOR), what's still to add, realm
-- time, and the calls made to add one.
local ROOT = arg[1]
date, time = os.date, os.time -- the game has these as globals
local ns = {}
ns.Split = function(s, sep)
    local out, from = {}, 1
    while true do
        local i = s:find(sep, from, true)
        if not i then out[#out + 1] = s:sub(from) break end
        out[#out + 1] = s:sub(from, i - 1)
        from = i + #sep
    end
    return out
end
assert(loadfile(ROOT .. "/Services/DiscordCode.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Calendar.lua"))("NGM", ns)
local DC, CAL = ns.DiscordCode, ns.Calendar
local fired = {}
ns.Fire = function(_, msg, ...) fired[#fired + 1] = { msg, ... } end
ns.Print = function() end
Enum = { CalendarEventType = { Other = 4 } }

local c = assert(DC:ParsePeon("NGMP1.dXMKTm9vdHJvcGljCmhhcwl0b2Y3eGMKRQkxNglyYWlkCXRvaW8wMAk1MAlNb2x0ZW4gQ29yZQlCcmluZyBmaXJlIHJlc2lzdC4gT24gdGltZSE.68a01aeb"))
assert(#c.events == 1)
local e = c.events[1]
assert(e.id == 42 and e.kind == "raid" and e.starts == 1794700800 and e.minutes == 180 and e.title == "Molten Core" and e.description == "Bring fire resist. On time!")

-- kept, and listed until added
local now = 1794600000
local guild = {}
ns.DB = { Guild = function() return guild end, Now = function() return now end }
assert(CAL:Take(c.events) == 1 and #CAL:Pending() == 1)

-- realm time: the realm's clock against the server's (here the realm runs 5 hours behind UTC)
GetServerTime = function() return now end
local realm = date("*t", now - 5 * 3600)
C_DateAndTime = { GetCurrentCalendarTime = function() return { year = realm.year, month = realm.month, monthDay = realm.day, hour = realm.hour, minute = realm.min } end }
local want = date("*t", e.starts - 5 * 3600)
local got = CAL.RealmTime(e.starts)
assert(got.year == want.year and got.month == want.month and got.day == want.day and got.hour == want.hour and got.min == want.min)

-- adding: in Blizzard's order (Blizzard_Calendar on Forever): the calendar
-- (opened when the window opens), then a guild announcement's date, title, text, time and type; added
-- only once the game confirms it (CALENDAR_NEW_EVENT), never twice
local calls = {}
local function rec(name) return function(...) calls[#calls + 1] = { name, ... } end end
C_Calendar = { CanAddEvent = function() return true end, OpenCalendar = rec("open"), CloseEvent = rec("close"), CreateGuildAnnouncementEvent = rec("create"),
  EventSetTitle = rec("title"), EventSetDescription = rec("text"), EventSetDate = rec("date"), EventSetTime = rec("time"), EventSetType = rec("type"), AddEvent = rec("add") }
assert(CAL:Add(e))
local seq = {}
for _, call in ipairs(calls) do seq[#seq + 1] = call[1] end
assert(table.concat(seq, ",") == "close,create,date,title,text,time,type,add", table.concat(seq, ","))
local by = {}
for _, call in ipairs(calls) do by[call[1]] = call end
assert(by.title[2] == "Molten Core" and by.text[2] == "Raid, 3 h. Bring fire resist. On time! Sign up in Discord.", by.text[2])
assert(by.date[2] == want.month and by.date[3] == want.day and by.date[4] == want.year and by.time[2] == want.hour and by.time[3] == want.min)
assert(by.type[2] == 4, "type Other, as Blizzard's")
assert(#CAL:Pending() == 1, "not confirmed yet: still listed")
assert(not CAL:Add(e), "one at a time")
-- the game says no: still listed, and the reason passed on
CAL:Failed("CALENDAR_ERROR_NEEDS_TITLE")
assert(#CAL:Pending() == 1 and fired[#fired][1] == "CALENDAR_RESULT" and fired[#fired][2] == false)
-- the game says yes: added
assert(CAL:Add(e))
CAL:Confirmed()
assert(fired[#fired][2] == true)
assert(#CAL:Pending() == 0, "added: not listed again")
-- moved in Discord: listed again
CAL:Take({ { id = 42, kind = "raid", starts = e.starts + 3600, minutes = 180, title = "Molten Core", description = "" } })
assert(#CAL:Pending() == 1)
-- titles fit the calendar's 31 characters, without splitting a character
local long = { id = 7, kind = "event", starts = now + 100, minutes = 60, title = ("\195\171"):rep(20), description = "" }
calls = {}
assert(CAL:Add(long))
CAL:Confirmed()
by = {}
for _, call in ipairs(calls) do by[call[1]] = call end
assert(#by.title[2] <= 31 and by.title[2] == ("\195\171"):rep(15), #by.title[2])
-- started, or a client that can't: refused with a reason
assert(not CAL:Add({ id = 8, kind = "event", starts = now - 1, minutes = 60, title = "x", description = "" }))
C_Calendar.CanAddEvent = function() return false end
local ok, why = CAL:Add(e)
assert(not ok and why:find("won't let you"))
print("OK")
