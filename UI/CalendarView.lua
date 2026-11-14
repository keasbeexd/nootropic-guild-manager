--[[
    Nootropic Guild Manager - Add to calendar
    The guild's upcoming events from NGM Peon that aren't in the WoW
    calendar yet, each with an Add button (one click adds one, as a guild
    announcement). Opens after /ngm peon brings some in; /ngm calendar too.

    ns.CalendarView:Open()
]]
local _, ns = ...
local W = ns.Widgets
local V = {}
ns.CalendarView = V

local ROWS, ROW_H = 8, 30
local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- In realm time, as the calendar shows it.
local function When(t)
    local d = ns.Calendar.RealmTime(t)
    return ("%s %d %s, %02d:%02d"):format(DAYS[d.wday], d.day, MONTHS[d.month], d.hour, d.min)
end

function V:Build()
    local f = CreateFrame("Frame", "NootropicGMCalendarAdd", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(460, 120)
    f:SetPoint("TOP", 0, -200)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.SetTitle(f, "Add to calendar")
    tinsert(UISpecialFrames, "NootropicGMCalendarAdd")
    self.frame = f

    self.lead = f:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.lead:SetPoint("TOPLEFT", 18, -34)
    self.lead:SetPoint("TOPRIGHT", -18, -34)
    self.lead:SetJustifyH("LEFT")
    self.lead:SetText("Your guild's events from NGM Peon. Add puts one in the WoW calendar as a guild announcement; sign-ups stay in Discord. Times are realm time.")

    self.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 18, -70 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -18, -70 - (i - 1) * ROW_H)
        r.When = r:CreateFontString(nil, "OVERLAY", "NGMFontNumber")
        r.When:SetPoint("LEFT", 0, 0)
        r.When:SetWidth(130)
        r.When:SetJustifyH("LEFT")
        r.Title = r:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
        r.Title:SetPoint("LEFT", r.When, "RIGHT", 8, 0)
        r.Title:SetPoint("RIGHT", -96, 0)
        r.Title:SetJustifyH("LEFT")
        r.Title:SetWordWrap(false)
        r.Add = W.Button(r, "Add", 80, 24)
        r.Add:SetPoint("RIGHT", 0, 0)
        r.Add:SetScript("OnClick", function() V:Add(r.event) end)
        self.rows[i] = r
    end

    self.result = f:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    self.result:SetPoint("BOTTOMLEFT", 18, 14)
    self.result:SetPoint("BOTTOMRIGHT", -18, 14)
    self.result:SetJustifyH("CENTER")
end

function V:Refresh()
    local list = ns.Calendar:Pending()
    local shown = math.min(#list, ROWS)
    for i, r in ipairs(self.rows) do
        local e = list[i]
        r.event = e
        if e then
            r.When:SetText(When(e.starts))
            r.Title:SetText(e.title)
            r:Show()
        else
            r:Hide()
        end
    end
    if #list == 0 then self.result:SetText("|cffb8bb26All caught up:|r every event is in the calendar.") end
    self.frame:SetHeight(70 + math.max(shown, 1) * ROW_H + 40)
end

function V:Add(e)
    if not e then return end
    local ok, why = ns.Calendar:Add(e)
    if ok then
        self.result:SetText("Adding " .. e.title .. "...")
    else
        self.result:SetText("|cfffb4934" .. why .. "|r")
    end
end

-- The game's answer (Services/Calendar.lua): added, or why not.
ns:On("CALENDAR_RESULT", function(ok, text)
    if not V.frame then return end
    V.result:SetText(ok and ("|cffb8bb26Added:|r " .. tostring(text)) or ("|cfffb4934Not added:|r " .. tostring(text)))
    V:Refresh()
end)

function V:Open()
    if not self.frame then self:Build() end
    ns.Calendar:Prepare() -- the game needs the calendar open before an event can be made
    -- beside the /ngm peon window when it's open, not on top of it
    local peon = ns.PeonPasteView and ns.PeonPasteView.frame
    self.frame:ClearAllPoints()
    if peon and peon:IsShown() then
        self.frame:SetPoint("TOPLEFT", peon, "TOPRIGHT", 16, 0)
    else
        self.frame:SetPoint("TOP", 0, -200)
    end
    self.result:SetText("")
    local can, why = ns.Calendar:CanAdd()
    if not can then self.result:SetText("|cfffb4934" .. why .. "|r") end
    self:Refresh()
    self.frame:Show()
end
