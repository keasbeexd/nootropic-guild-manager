--[[
    Nootropic Guild Manager - Upcoming Events tab
    The guild's upcoming events from NGM Peon (Services/Events.lua), as the
    dashboard's Upcoming Events tab shows them: when (your own time), what,
    how long, how many are coming, and where to sign up (the Discord channel
    and server). Each in a box, as the dashboard's. Below them, what the
    game itself has coming (Services/GameCalendar.lua): the daily reset as
    a line at the top, the weekly reset and holidays in boxes of their own.
]]
local _, ns = ...
local W = ns.Widgets
local EV = {}
ns.EventsView = EV

local GRAY = "|cff9d9d9d"
local KIND = { dungeon = "Dungeon", raid = "Raid", event = "Event" }
local PAD, EDGE, GAP = 14, 4, 16

local function Card(parent)
    local T = ns.Theme
    local c = CreateFrame("Frame", nil, parent)
    T:Box(c, T.C.bg1, T.C.edge, EDGE)
    c.Title = c:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    c.Title:SetPoint("TOPLEFT", PAD, -PAD)
    c.Title:SetPoint("RIGHT", -140, 0)
    c.Title:SetJustifyH("LEFT")
    c.Title:SetWordWrap(false)
    c.Coming = c:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    c.Coming:SetPoint("TOPRIGHT", -PAD, -PAD - 1)
    c.Coming:SetJustifyH("RIGHT")
    c.When = c:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    c.When:SetPoint("TOPLEFT", c.Title, "BOTTOMLEFT", 0, -6)
    c.When:SetJustifyH("LEFT")
    c.Text = c:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    c.Text:SetPoint("TOPLEFT", c.When, "BOTTOMLEFT", 0, -6)
    c.Text:SetJustifyH("LEFT")
    c.Where = c:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    c.Where:SetJustifyH("LEFT")
    -- events made in game: Edit (its creator, or a manager)
    c.Edit = W.Button(c, "Edit", 70, 22)
    c.Edit:SetPoint("BOTTOMRIGHT", -PAD + 4, PAD - 6)
    c.Edit:Hide()
    return c
end

function EV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame

    self.title = page:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -37)
    -- Create (3.1): for ranks that may create some kind of event
    self.create = W.Button(page, "Create Event", 120, 22)
    self.create:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -32)
    self.create:SetScript("OnClick", function() ns.EventForm:Open() end)
    W.Tooltip(self.create, "Create an event", "Your guild sees it at once. With NGM Peon, it's posted in Discord with your next update.")

    local inset = frame.Inset
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMEventsScroll", page, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 6)
    scroll:EnableMouseWheel(true)
    self.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 400)
    scroll:SetScrollChild(content)
    self.content = content
    self.cards = {}
    self.empty = content:CreateFontString(nil, "OVERLAY", "NGMFontDim")
    self.empty:SetPoint("TOPLEFT", EDGE, -EDGE)
    self.empty:SetJustifyH("LEFT")
    self.note = content:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.note:SetJustifyH("LEFT")
    self.daily = content:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.daily:SetJustifyH("LEFT")
    self.gameHeader = content:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    self.gameHeader:SetJustifyH("LEFT")
    self.gameCards = {}

    page:SetScript("OnShow", function()
        if ns.GameCalendar then ns.GameCalendar:Refresh() end
        EV:Refresh()
    end)
    page:SetScript("OnSizeChanged", function() if page:IsVisible() then EV:Refresh() end end)
    ns:On("EVENTS_CHANGED", function() EV:Refresh() end)
    ns:On("GAME_CALENDAR_CHANGED", function() EV:Refresh() end)
end

-- One of the game's own: the weekly reset or a holiday. No sign-ups.
local function FillGameCard(c, item, inner, now)
    local GC = ns.GameCalendar
    c.Title:SetText(ns.Theme.Upper(item.title ~= "" and item.title or "Holiday"))
    c.Coming:SetText("")
    if item.kind == "weekly" then
        c.When:SetText(("%s  " .. GRAY .. "·|r  Reset  " .. GRAY .. "·|r  in %s"):format(date("%a %d %b, %H:%M", item.starts), GC.Short(item.starts - now)))
    elseif item.starts <= now then
        c.When:SetText(("On now, until %s  " .. GRAY .. "·|r  Holiday"):format(date("%a %d %b, %H:%M", item.ends)))
    else
        c.When:SetText(("%s to %s  " .. GRAY .. "·|r  Holiday"):format(date("%a %d %b, %H:%M", item.starts), date("%a %d %b, %H:%M", item.ends)))
    end
    c.Text:SetWidth(inner - 2 * PAD)
    c.Text:SetText(item.description or "")
    c.Text:SetShown((item.description or "") ~= "")
    c.Where:SetText("")
    c.Where:Hide()
    local h = PAD + c.Title:GetStringHeight() + 6 + c.When:GetStringHeight()
        + (c.Text:IsShown() and (6 + c.Text:GetStringHeight()) or 0) + PAD
    c:SetHeight(h)
    return h
end

function EV:Refresh()
    if not (self.page and self.page:IsVisible()) then return end
    local list = ns.Events:List()
    self.title:SetText(("Upcoming Events  " .. GRAY .. "- %d in the next 30 days|r"):format(#list))
    self.create:SetShown(#ns.Events:KindsICanCreate() > 0)
    local manager = ns.Sync:EventManager(ns.PlayerFullName())
    local width = math.max(300, math.floor(self.scroll:GetWidth()))
    local inner = width - 2 * EDGE
    local y = EDGE
    local now = ns.DB:Now()
    local game, daily = {}, nil
    if ns.GameCalendar then game, daily = ns.GameCalendar:Upcoming(now) end
    self.daily:SetShown(daily ~= nil)
    if daily then
        self.daily:ClearAllPoints()
        self.daily:SetPoint("TOPLEFT", EDGE, -y)
        self.daily:SetWidth(inner)
        self.daily:SetText(("Daily reset in " .. ns.GOLD .. "%s|r  " .. GRAY .. "·|r  %s"):format(ns.GameCalendar.Short(daily - now), date("%H:%M", daily)))
        y = y + self.daily:GetStringHeight() + GAP
    end
    self.empty:SetShown(#list == 0)
    self.empty:ClearAllPoints()
    self.empty:SetPoint("TOPLEFT", EDGE, -y)
    self.empty:SetWidth(inner)
    self.empty:SetText(ns.Sync:PeonGuild()
        and ("No upcoming events yet. Create one here, or on the " .. ns.GOLD .. "NGM Peon dashboard|r (/ngm dashboard in Discord, Create Events tab).")
        or "No upcoming events yet. The Guild Master and officers can create one here.")
    for i, ev in ipairs(list) do
        local c = self.cards[i] or Card(self.content)
        self.cards[i] = c
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", EDGE, -y)
        c:SetWidth(inner)
        c.Title:SetText(ns.Theme.Upper(ev.title ~= "" and ev.title or "Event"))
        c.Coming:SetText(("%d coming"):format(ev.coming or 0))
        local length = ev.minutes >= 60 and ((ev.minutes / 60) .. " h") or (ev.minutes .. " min")
        c.When:SetText(("%s  " .. GRAY .. "·|r  %s  " .. GRAY .. "·|r  %s"):format(date("%a %d %b, %H:%M", ev.starts), KIND[ev.kind] or "Event", length))
        c.Text:SetWidth(inner - 2 * PAD)
        c.Text:SetText(ev.description or "")
        c.Text:SetShown((ev.description or "") ~= "")
        c.Where:ClearAllPoints()
        c.Where:SetPoint("TOPLEFT", c.Text:IsShown() and c.Text or c.When, "BOTTOMLEFT", 0, -8)
        c.Where:SetWidth(inner - 2 * PAD)
        local editable = ev.source == "game" and ns.Events:MayEdit(ev)
        c.Where:SetWidth(inner - 2 * PAD - (editable and 80 or 0))
        if ev.source == "game" then
            -- made in game: who made it; with NGM Peon, posted with the next update
            c.Coming:SetText("")
            c.Where:SetText(("Made in game by %s%s"):format(ns.ShortName(ev.creator),
                ns.Sync:PeonGuild() and ("  " .. GRAY .. "·|r  NGM Peon posts it with the next update") or ""))
        else
            -- sign-ups are in Discord only: one list per event
            local where = ev.channel ~= "" and (" " .. GRAY .. "·|r #" .. ev.channel) or ""
            local server = ev.server ~= "" and (" " .. GRAY .. "on|r " .. ev.server) or ""
            c.Where:SetText(ns.GOLD .. "Sign up in Discord|r" .. where .. server
                .. (manager and ("\n" .. GRAY .. "Made on the dashboard: edit it there.|r") or ""))
        end
        c.Edit:SetShown(editable)
        c.Edit:SetScript("OnClick", function() ns.EventForm:Open(ev) end)
        local h = PAD + c.Title:GetStringHeight() + 6 + c.When:GetStringHeight()
            + (c.Text:IsShown() and (6 + c.Text:GetStringHeight()) or 0) + 8 + math.max(c.Where:GetStringHeight(), editable and 16 or 0) + PAD
        c:SetHeight(h)
        c:Show()
        y = y + h + GAP
    end
    for i = #list + 1, #self.cards do self.cards[i]:Hide() end
    if #list == 0 then y = y + self.empty:GetStringHeight() + GAP end
    -- the game's own: weekly reset and holidays
    self.gameHeader:SetShown(#game > 0)
    if #game > 0 then
        self.gameHeader:ClearAllPoints()
        self.gameHeader:SetPoint("TOPLEFT", EDGE, -y)
        self.gameHeader:SetText(ns.Theme.Upper("Resets and holidays"))
        y = y + self.gameHeader:GetStringHeight() + 8
    end
    for i, item in ipairs(game) do
        local c = self.gameCards[i] or Card(self.content)
        self.gameCards[i] = c
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", EDGE, -y)
        c:SetWidth(inner)
        local h = FillGameCard(c, item, inner, now)
        c:Show()
        y = y + h + GAP
    end
    for i = #game + 1, #self.gameCards do self.gameCards[i]:Hide() end
    self.note:ClearAllPoints()
    self.note:SetPoint("TOPLEFT", EDGE, -y)
    self.note:SetWidth(inner)
    self.note:SetText("Times are your own. Sign up in Discord, with the buttons on each event's post. New ones reach the game when an officer brings in NGM Peon's code (" .. ns.GOLD .. "/ngm peon|r).")
    self.content:SetSize(width, y + 40)
end
