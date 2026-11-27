--[[
    Nootropic Guild Manager - Create or edit an event (3.1, docs/EVENTS.md)
    A small window from the Upcoming Events tab: kind, title, day and time
    (your own), length, description. Steppers instead of typed dates, so a
    controller works it as well as a mouse (docs/CONTROLLER.md). Lengths as
    NGM Peon's form.

    ns.EventForm:Open()        a new event
    ns.EventForm:Open(ev)      edit one made in game (ns.Events:List() entry)
]]
local _, ns = ...
local W = ns.Widgets
local F = {}
ns.EventForm = F

local KIND_LABEL = { dungeon = "Dungeon", raid = "Raid", event = "Event" }
local STEP = 15 * 60 -- the time moves in quarter hours
local MAX_DAYS = 60

local function Length(m)
    if m < 60 then return m .. " min" end
    return (m % 60 == 0) and ((m / 60) .. " h") or (("%.1f h"):format(m / 60))
end

-- a stepper: [<] label [>]
local function Stepper(parent, label, width, onStep)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(360, 26)
    row.Label = row:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    row.Label:SetPoint("LEFT", 0, 0)
    row.Label:SetWidth(90)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetText(label)
    row.Prev = W.Button(row, "<", 30, 24)
    row.Prev:SetPoint("LEFT", row.Label, "RIGHT", 0, 0)
    row.Prev:SetScript("OnClick", function() onStep(-1) end)
    row.Value = row:CreateFontString(nil, "OVERLAY", "NGMFontText")
    row.Value:SetPoint("LEFT", row.Prev, "RIGHT", 8, 0)
    row.Value:SetWidth(width)
    row.Value:SetJustifyH("CENTER")
    row.Next = W.Button(row, ">", 30, 24)
    row.Next:SetPoint("LEFT", row.Value, "RIGHT", 8, 0)
    row.Next:SetScript("OnClick", function() onStep(1) end)
    return row
end

local function Input(parent, label, maxLetters)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(360, 26)
    row.Label = row:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    row.Label:SetPoint("LEFT", 0, 0)
    row.Label:SetWidth(90)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetText(label)
    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(262, 22)
    box:SetPoint("LEFT", row.Label, "RIGHT", 6, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(maxLetters)
    box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    row.Box = box
    return row
end

function F:Build()
    local f = CreateFrame("Frame", "NootropicGMEventForm", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(420, 330)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "NootropicGMEventForm") -- Escape closes it
    ns.Gamepad:Register(f, "popup")
    self.frame = f

    local y = -36
    -- kind: one button each (only the kinds your rank may create)
    self.kindLabel = f:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    self.kindLabel:SetPoint("TOPLEFT", 20, y - 6)
    self.kindLabel:SetText("Kind")
    self.kindButtons = {}
    for i, k in ipairs(ns.Sync.EVENT_KINDS) do
        local b = W.Button(f, KIND_LABEL[k], 84, 24)
        b:SetPoint("TOPLEFT", 110 + (i - 1) * 90, y)
        b:SetScript("OnClick", function() F.kind = k F:Show() end)
        self.kindButtons[k] = b
    end
    y = y - 34
    self.title = Input(f, "Title", ns.Events.MAX_TITLE)
    self.title:SetPoint("TOPLEFT", 20, y)
    y = y - 32
    self.day = Stepper(f, "Day", 150, function(d) F:MoveDay(d) end)
    self.day:SetPoint("TOPLEFT", 20, y)
    y = y - 32
    self.time = Stepper(f, "Time (yours)", 150, function(d) F:MoveTime(d) end)
    self.time:SetPoint("TOPLEFT", 20, y)
    y = y - 32
    self.length = Stepper(f, "Length", 150, function(d) F:MoveLength(d) end)
    self.length:SetPoint("TOPLEFT", 20, y)
    y = y - 32
    self.description = Input(f, "Description", ns.Events.MAX_DESCRIPTION)
    self.description:SetPoint("TOPLEFT", 20, y)
    y = y - 34

    self.result = f:CreateFontString(nil, "OVERLAY", "NGMFontLabelSmall")
    self.result:SetPoint("TOPLEFT", 20, y)
    self.result:SetPoint("TOPRIGHT", -20, y)
    self.result:SetJustifyH("LEFT")

    self.save = W.Button(f, "Create", 120, 24)
    self.save:SetPoint("BOTTOMRIGHT", -16, 14)
    self.save:SetScript("OnClick", function() F:Save() end)
    self.cancelEvent = W.Button(f, "Cancel Event", 120, 24)
    self.cancelEvent:SetPoint("BOTTOMLEFT", 16, 14)
    self.cancelEvent:SetScript("OnClick", function() F:CancelEvent() end)
    W.Tooltip(self.cancelEvent, "Cancel this event", "It's taken off everyone's Upcoming Events (and with NGM Peon, its post says Cancelled).")
end

-- the day and time, in your own clock
function F:MoveDay(d)
    local t = self.starts + d * 86400
    local today = time({ year = date("*t").year, month = date("*t").month, day = date("*t").day, hour = 0 })
    if t < today or t > today + MAX_DAYS * 86400 then return end
    self.starts = t
    self:Show()
end

function F:MoveTime(d)
    local day = date("*t", self.starts)
    local t = self.starts + d * STEP
    -- stays on the same day (the Day row changes the day)
    if date("*t", t).day ~= day.day then return end
    self.starts = t
    self:Show()
end

function F:MoveLength(d)
    local list, at = ns.Events.DURATIONS, 1
    for i, m in ipairs(list) do if m == self.minutes then at = i end end
    at = math.max(1, math.min(#list, at + d))
    self.minutes = list[at]
    self:Show()
end

-- refreshes what's shown
function F:Show()
    local f = self.frame
    local editing = self.editing ~= nil
    W.SetTitle(f, editing and "Edit Event" or "Create Event")
    local allowed = {}
    for _, k in ipairs(editing and { self.kind } or ns.Events:KindsICanCreate()) do allowed[k] = true end
    for k, b in pairs(self.kindButtons) do
        b:SetShown(allowed[k] == true)
        if b.LockHighlight then
            if k == self.kind then b:LockHighlight() else b:UnlockHighlight() end
        end
    end
    self.day.Value:SetText(date("%a %d %b", self.starts))
    self.time.Value:SetText(date("%H:%M", self.starts))
    self.length.Value:SetText(Length(self.minutes))
    self.save:SetText(editing and "Save" or "Create")
    self.cancelEvent:SetShown(editing)
    f:Show()
end

function F:Open(ev)
    if InCombatLockdown and InCombatLockdown() then return end
    if not self.frame then self:Build() end
    self.result:SetText("")
    if ev then
        self.editing, self.kind, self.starts, self.minutes = ev.id, ev.kind, ev.starts, ev.minutes
        self.title.Box:SetText(ev.title or "")
        self.description.Box:SetText(ev.description or "")
    else
        local kinds = ns.Events:KindsICanCreate()
        if #kinds == 0 then
            ns:Print("Your rank can't create events" .. (ns.Sync:PeonGuild() and " (NGM Peon's Event Settings)." or ": the Guild Master and officers can."))
            return
        end
        -- tomorrow, 20:00 your time
        local t = date("*t", ns.DB:Now() + 86400)
        self.editing, self.kind, self.minutes = nil, kinds[1], 120
        self.starts = time({ year = t.year, month = t.month, day = t.day, hour = 20, min = 0, sec = 0 })
        self.title.Box:SetText("")
        self.description.Box:SetText("")
    end
    self:Show()
end

function F:Save()
    local fields = { kind = self.kind, starts = self.starts, minutes = self.minutes, title = self.title.Box:GetText(), description = self.description.Box:GetText() }
    local ok, why
    if self.editing then ok, why = ns.Events:Edit(self.editing, fields) else ok, why = ns.Events:Create(fields) end
    if not ok then
        self.result:SetText("|cff" .. ns.Theme.HEX.red .. (why or "That didn't work.") .. "|r")
        return
    end
    self.frame:Hide()
    ns:Fire("EVENTS_CHANGED")
    ns:Print((self.editing and "Event saved. " or ("Event created: " .. ns.GOLD .. fields.title .. "|r. ")) .. ns.DiscordCode:Reach())
end

function F:CancelEvent()
    if not self.editing then return end
    local id = self.editing
    W.Confirm("Cancel this event for everyone?", function()
        local ok, why = ns.Events:Cancel(id)
        if not ok then ns:Print(why or "That didn't work.") return end
        F.frame:Hide()
        ns:Fire("EVENTS_CHANGED")
        ns:Print("Event cancelled. " .. ns.DiscordCode:Reach())
    end)
end
