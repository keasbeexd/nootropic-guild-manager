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

-- a change that isn't on Discord yet, and when Discord gets it
local function Pending(label, rec) return ns.DiscordCode:PendingText(label, rec) end
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
    -- where Edit would be, for one edited elsewhere: where to edit it (as the dashboard's "Made in game: edit it there")
    c.Made = c:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    c.Made:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    c.Made:SetJustifyH("RIGHT")
    -- sign-ups (3.1): who's coming, as NGM Peon's post, and the buttons
    c.Signups = c:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    c.Signups:SetJustifyH("LEFT")
    c.Signups:SetSpacing(3)
    c.Parts = {}
    for _, part in ipairs({ "tank", "healer", "dps", "going", "tentative", "absent" }) do
        local b = W.Button(c, ns.Events.PART_BUTTON[part], part == "absent" and 86 or 72, 22)
        b:Hide()
        c.Parts[part] = b
    end
    c.Change = W.Button(c, "Change character", 130, 22)
    c.Change:Hide()
    c.Notice = c:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    c.Notice:SetJustifyH("LEFT")
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
    -- with NGM Desktop: send your changes now (a /reload writes them for the app)
    self.send = W.Button(page, "Send to Discord", 130, 22)
    self.send:SetPoint("RIGHT", self.create, "LEFT", -6, 0)
    -- straight from the click, as Reload and Sync (bottom right): the reload needs a click of yours
    self.send:SetScript("OnClick", function() ns.DiscordCode:ReloadAndSync() end)
    W.Tooltip(self.send, "Send to Discord", "NGM Desktop sends what the game saves at a /reload. This reloads your UI now.")
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

-- Sign-ups on a card: who's coming (as NGM Peon's post), your buttons, and
-- Change character; or why you can't sign up. Returns the height it took.
function EV:FillSignups(c, ev, inner, top)
    local E = ns.Events
    local lines = {}
    local coming = 0
    for _, f in ipairs(E:Fields(ev)) do
        lines[#lines + 1] = ns.GOLD .. f.name .. "|r  " .. f.value
        if f.name:match("^Tanks") or f.name:match("^Healers") or f.name:match("^DPS") or f.name:match("^Going") then
            coming = coming + (tonumber(f.name:match("%((%d+)")) or 0)
        end
    end
    if ev.source == "game" and not ev.cancelled then c.Coming:SetText(("%d coming"):format(coming)) end
    c.Signups:ClearAllPoints()
    c.Signups:SetPoint("TOPLEFT", PAD, -(top + 8))
    c.Signups:SetWidth(inner - 2 * PAD)
    c.Signups:SetText(table.concat(lines, "\n"))
    local y = top + 8 + c.Signups:GetStringHeight() + 8
    local mine, picked = E:Mine(ev)
    local ok, why = E:CanSignUp(ev, picked)
    for _, b in pairs(c.Parts) do b:Hide() end
    c.Change:Hide()
    c.Notice:Hide()
    if not ok then
        c.Notice:ClearAllPoints()
        c.Notice:SetPoint("TOPLEFT", PAD, -y)
        c.Notice:SetWidth(inner - 2 * PAD)
        c.Notice:SetText(why)
        c.Notice:Show()
        return (y - top) + c.Notice:GetStringHeight()
    end
    local x = PAD
    for _, part in ipairs(E:Parts(ev.kind)) do
        local b = c.Parts[part]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, -y)
        if b.LockHighlight then if mine == part then b:LockHighlight() else b:UnlockHighlight() end end
        b:SetScript("OnClick", function()
            local done, err = E:SignUp(ev, part)
            if not done then ns:Print(err or "That didn't work.")
            else ns:Print(("Signed up: %s. %s"):format(E.PART_BUTTON[part], ns.DiscordCode:Reach())) end
            EV:Refresh()
        end)
        W.Tooltip(b, E.PART_BUTTON[part], mine == part and "You're signed up as this." or "Sign up as this.")
        b:Show()
        x = x + b:GetWidth() + 4
    end
    local mains = E:MyCharacters()
    if #mains > 1 then
        c.Change:ClearAllPoints()
        c.Change:SetPoint("TOPLEFT", x + 8, -y)
        c.Change:SetScript("OnClick", function(btn)
            if not mine then ns:Print("Pick your role first, then the character you're bringing.") return end
            local items = { { text = "Which character are you bringing?", isTitle = true } }
            for _, name in ipairs(mains) do
                items[#items + 1] = { text = ns.ShortName(name), radio = true,
                    checked = function() return (picked == "" and name == mains[1]) or picked == name end,
                    func = function()
                        local done, err = E:SignUp(ev, mine, name == mains[1] and "" or name)
                        if not done then ns:Print(err or "That didn't work.")
                        else ns:Print(("You're coming as %s. %s"):format(ns.ShortName(name), ns.DiscordCode:Reach())) end
                        EV:Refresh()
                    end }
            end
            W.ShowMenu(btn, items)
        end)
        W.Tooltip(c.Change, "Change character", "Which of your characters you're bringing (your main unless you pick another).")
        c.Change:Show()
    end
    -- with NGM Peon: your sign-up changed this session isn't on the Discord post yet
    local unsent, yours = E:MineUnsent(ev)
    if ns.Sync:PeonGuild() and unsent then
        c.Notice:ClearAllPoints()
        c.Notice:SetPoint("TOPLEFT", PAD, -(y + 28))
        c.Notice:SetWidth(inner - 2 * PAD)
        c.Notice:SetText(Pending("Your sign-up isn't on the Discord post yet", yours))
        c.Notice:Show()
        return (y - top) + 28 + c.Notice:GetStringHeight()
    end
    return (y - top) + 24
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
    self.send:SetShown(ns.Sync:PeonGuild() and ns.Events:Unsent() and ns.DiscordCode:DesktopInstalled())
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
        -- cancelled: said first, in red, as the Discord post's title
        c.Title:SetText((ev.cancelled and ("|cff" .. ns.Theme.HEX.red .. "Cancelled:|r " .. GRAY) or "")
            .. ns.Theme.Upper(ev.title ~= "" and ev.title or "Event") .. (ev.cancelled and "|r" or ""))
        c.Coming:SetText(("%d coming"):format(ev.coming or 0))
        local length = ev.minutes >= 60 and ((ev.minutes / 60) .. " h") or (ev.minutes .. " min")
        -- and how long until it starts, as the post shows it
        local rel = ev.starts > now and ("in " .. ns.GameCalendar.Short(ev.starts - now))
            or (now < ev.starts + ev.minutes * 60 and "started" or "over")
        c.When:SetText(("%s  " .. GRAY .. "·|r  %s  " .. GRAY .. "·|r  %s  " .. GRAY .. "·|r  %s"):format(date("%a %d %b, %H:%M", ev.starts), KIND[ev.kind] or "Event", length, rel))
        c.Text:SetWidth(inner - 2 * PAD)
        c.Text:SetText(ev.description or "")
        c.Text:SetShown((ev.description or "") ~= "")
        c.Where:ClearAllPoints()
        c.Where:SetPoint("TOPLEFT", c.Text:IsShown() and c.Text or c.When, "BOTTOMLEFT", 0, -8)
        c.Where:SetWidth(inner - 2 * PAD)
        -- made in game (NGM Peon's post of one too): edited in game
        local made = ev.source == "game" and ev or ev.made
        local editable = made ~= nil and ns.Events:MayEdit(made)
        c.Where:SetWidth(inner - 2 * PAD - (editable and 80 or 0))
        local onDiscord = ev.source ~= "game" and (ns.GOLD .. "On Discord|r"
            .. (ev.channel ~= "" and (" " .. GRAY .. "·|r #" .. ev.channel) or "") .. (ev.server ~= "" and (" " .. GRAY .. "on|r " .. ev.server) or "")) or nil
        if ev.cancelled then
            -- listed until its Discord post goes ("Clear old posts")
            c.Coming:SetText("")
            local lines = {}
            if onDiscord then lines[#lines + 1] = onDiscord end
            if ev.cancelledInGame then lines[#lines + 1] = GRAY .. ("Cancelled in game by %s"):format(ns.ShortName(ev.cancelledBy or ev.creator or "")) .. "|r" end
            if ev.cancelUnsent then lines[#lines + 1] = Pending("Cancel not on Discord yet", ns.Sync:Get("EG:" .. (ev.game or ev.id))) end
            c.Where:SetText(table.concat(lines, "\n"))
        elseif ev.source == "game" then
            -- made in game: who made it; with NGM Peon, posted with the next update
            c.Coming:SetText("")
            c.Where:SetText(("Made in game by %s"):format(ns.ShortName(ev.creator))
                .. (ns.Sync:PeonGuild() and ("\n" .. Pending("Not on Discord yet", ns.Sync:Get("EG:" .. ev.id))) or ""))
        else
            c.Where:SetText(onDiscord
                .. (ev.made and ("\n" .. GRAY .. ("Made in game by %s"):format(ns.ShortName(ev.made.creator)) .. "|r"
                    .. (ev.changed and ("\n" .. Pending("Changes not on Discord yet", ns.Sync:Get("EG:" .. ev.game))) or ""))
                    or ""))
        end
        c.Edit:SetShown(editable)
        c.Edit:SetScript("OnClick", function() ns.EventForm:Open(made) end)
        local elsewhere = not editable and manager and not ev.cancelled and ev.source ~= "game" and not ev.made
        c.Made:SetText(elsewhere and "Made on the dashboard: edit it there" or "")
        c.Made:SetShown(elsewhere)
        local h = PAD + c.Title:GetStringHeight() + 6 + c.When:GetStringHeight()
            + (c.Text:IsShown() and (6 + c.Text:GetStringHeight()) or 0) + 8 + c.Where:GetStringHeight()
        h = h + EV:FillSignups(c, ev, inner, h) + math.max(PAD, (editable or elsewhere) and 30 or 0)
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
    self.note:SetText(ns.Sync:PeonGuild()
        and ((ns.DiscordCode:PeonGot() > 0 and ("NGM Peon's news last came in " .. date("%a %d %b, %H:%M", ns.DiscordCode:PeonGot()) .. ". ") or "")
            .. "Times are your own. Sign up here or with the buttons on each event's post in Discord: both count. Changes travel between the game and Discord when someone with " .. ns.GOLD .. "NGM Desktop|r reloads or logs out (yours with your own; everyone's with an officer's), or when an officer uses the codes (" .. ns.GOLD .. "/ngm discord|r, " .. ns.GOLD .. "/ngm peon|r).")
        or "Times are your own. Sign up with the buttons on each event.")
    self.content:SetSize(width, y + 40)
end
