-- Test: Upcoming Events from NGM Peon's code (the same example as ngm-hub's
-- EVENT_VECTOR): read with where to sign up and who's coming; an officer
-- shares them with the guild (EV records) and clears cancelled ones; anyone
-- else keeps them for themselves; past ones aren't listed; and the records'
-- rules (Core/Records.lua) take only well-formed ones.
local ROOT = arg[1]
date, time = os.date, os.time
local ns = {}
local printed = {}
function ns:Fire() end
function ns:On() end
function ns:Print(m) printed[#printed + 1] = m end
ns.GOLD = ""
ns.GOLD, ns.ORANGE, ns.BLUE = "|cfffabd2f", "|cfffe8019", "|cff83a598"
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
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
assert(loadfile(ROOT .. "/Services/DiscordCode.lua"))("NGM", ns)
assert(loadfile(ROOT .. "/Services/Events.lua"))("NGM", ns)
local DC, E = ns.DiscordCode, ns.Events

local c = assert(DC:ParsePeon("NGMP1.dXMKTm9vdHJvcGljCmhhcwl0b2Y3eGMKRQkxNglyYWlkCXRvaW8wMAk1MAlNb2x0ZW4gQ29yZQlCcmluZyBmaXJlIHJlc2lzdC4gT24gdGltZSEJcmFpZHMJTm9vdHJvcGljCWM.87cb2139"))
local ev = c.events[1]
assert(ev.id == 42 and ev.kind == "raid" and ev.starts == 1794700800 and ev.minutes == 180 and ev.title == "Molten Core"
  and ev.description == "Bring fire resist. On time!" and ev.channel == "raids" and ev.server == "Nootropic" and ev.coming == 12)

-- a guild record round trip
local back = E.Parse("16", E.Value(ev))
for _, k in ipairs({ "kind", "starts", "minutes", "coming", "channel", "server", "title", "description" }) do assert(back[k] == ev[k], k) end
assert(E.Parse("x", "") == nil, "cleared: gone")

-- someone who isn't an officer: kept for themselves
local now = 1794600000
local guild, store, officer = {}, {}, false
local settings = {}
ns.DB = { Guild = function() return guild end, Now = function() return now end, Settings = function() return settings end }
ns.Sync = { CanWrite = function() return officer end, Get = function(_, k) return store[k] end,
  Set = function(_, k, v) store[k] = { v = v } end, Store = function() return store end }
local up, new, removed = E:Take(c.events)
assert(up == 1 and new == 1 and removed == 0 and next(store) == nil, "not shared")
assert(E:List()[1].title == "Molten Core")

-- kept for themselves, tidied: no "|" (WoW's escape character) from a title
do
    local saved = guild.upcoming
    guild.upcoming = nil
    local ev2 = { id = 99, kind = "raid", starts = now + 3600, minutes = 60, title = "MC |cffff0000now|r", description = "|TInterface\\X:999|t", channel = "", server = "", coming = 0 }
    E:Take({ ev2 })
    assert(guild.upcoming[1].title == "MC /cffff0000now/r" and not guild.upcoming[1].description:find("|", 1, true), guild.upcoming[1].title)
    assert(ev2.title:find("|", 1, true), "the code's own copy is left alone")
    guild.upcoming = saved
end

-- an officer: shared with the guild; one NGM Peon no longer has is cleared
officer = true
store["EV:z"] = { v = E.Value({ kind = "event", starts = now + 3600, minutes = 60, coming = 0, channel = "", server = "", title = "Old", description = "" }) }
up, new, removed = E:Take(c.events)
assert(up == 1 and new == 0 and removed == 1, "the old one, cancelled: 1 event removed")
assert(store["EV:16"] and store["EV:16"].v == E.Value(ev), "shared as EV:<id>")
assert(store["EV:z"].v == "", "cancelled in Discord: cleared")
-- one that has started stays listed (sign-ups closed) until it ends, as its
-- Discord post does; it isn't "removed" when NGM Peon stops listing it
now = ev.starts + 1
assert(#E:List() == 1, "started: still listed")
up, new, removed = E:Take({})
assert(up == 1 and new == 0 and removed == 0)
now = ev.starts + ev.minutes * 60
assert(#E:List() == 0, "over: gone")

-- the records' rules
assert(loadfile(ROOT .. "/Core/Records.lua"))("NGM", ns)
local S = ns.Sync
assert(S and S.ValidValue, "the records code loaded")
do
    assert(S.ValidValue("EV", E.Value(ev)) and S.ValidValue("EV", ""))
    assert(not S.ValidValue("EV", "party;1;1;0;x;y;z;"), "an unknown kind")
    assert(not S.ValidValue("EV", "raid;1;1;0;x\ty;y;z;"), "no tabs")
    -- their own sync lane: a 2.12 copy ignores lanes it doesn't know, so
    -- events never make its fingerprints differ from a 3.0 officer's
    assert(S.LaneOf("EV:16") == "events" and S.LaneOf("M:Marc") == "guild")
    assert(S.LANE_STORE.events == "guild" and S.LANE_CHANNEL.events == "GUILD")
end
-- New events in chat: the first look only notes what's there; later ones
-- are told once each; the Guild Feed switch turns the lines off
do
    guild.eventsSeen, guild.upcoming = nil, {}
    local realSync, store2 = ns.Sync, {}
    ns.Sync = { CanWrite = function() return false end, Store = function() return store2 end, Set = function() end }
    local rang = 0
    ns.GuildFeed = { PlayFeed = function(_, feed) assert(feed == "event"); rang = rang + 1 end }
    E:Take({ { id = 1, kind = "raid", starts = now + 7200, minutes = 60, title = "Molten Core", channel = "raids" } })
    printed = {}
    E:Announce()
    assert(#printed == 0, "first look: nothing told")
    E:Take({ { id = 1, kind = "raid", starts = now + 7200, minutes = 60, title = "Molten Core", channel = "raids" },
             { id = 2, kind = "dungeon", starts = now + 9000, minutes = 60, title = "Deadmines", channel = "" } })
    E:Announce()
    assert(#printed == 1 and printed[1]:find("New dungeon posted", 1, true) and printed[1]:find("Deadmines", 1, true), printed[1])
    assert(rang == 1, "the new-event sound, once")
    E:Announce()
    assert(#printed == 1 and rang == 1, "told once")
    settings.eventNotices = false
    E:Take({ { id = 3, kind = "event", starts = now + 9000, minutes = 60, title = "Fishing", channel = "" } })
    E:Announce()
    assert(#printed == 1 and rang == 1, "switched off: no line, no sound")
    settings.eventNotices = nil
    ns.Sync, ns.GuildFeed = realSync, nil
end

-- Guild Feed: who levelled since the last roster (a level read as 0 is no ding)
do
    assert(loadfile(ROOT .. "/Services/GuildFeed.lua"))("NGM", ns)
    local ch = ns.GuildFeed.Changes({ { full = "A", level = 31 }, { full = "B", level = 20 }, { full = "C", level = 12 }, { full = "D", level = 5 } },
        { A = 30, B = 20, C = 0 })
    assert(#ch == 1 and ch[1].full == "A", "only A levelled")
end
print("OK")
