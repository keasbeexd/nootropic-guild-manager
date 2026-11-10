--[[
    Nootropic Guild Manager - Hall of Fame tab (everyone)
    Leaderboards from the character statistics guildmates share
    (Services/HallOfFame.lua): one card per statistic with the top five,
    guild totals on top. All time, this month or last month
    (Settings().hofPeriod). People count once, their characters added up,
    unless "Count alts" is on (Settings().hofAlts).
]]
local _, ns = ...
local W = ns.Widgets
local HV = {}
ns.HallOfFameView = HV

local GRAY = "|cff9d9d9d"
local GOLD = "|cffffd100"
local PERIODS = { { "all", "All time" }, { "month", "This month" }, { "last", "Last month" } }
local TOP = 5
local ROW_H = 16
local CARD_W, CARD_GAP = 230, 12
local CARD_H = 26 + TOP * ROW_H + 20
local TOTALS = { "quests", "kills", "bosses", "deaths" }

local function Me() return ns.PlayerFullName() end

function HV:Period()
    local p = ns.DB:Settings().hofPeriod
    for _, d in ipairs(PERIODS) do if d[1] == p then return p end end
    return "all"
end

local function PeriodText(p)
    for _, d in ipairs(PERIODS) do if d[1] == p then return d[2] end end
    return p
end

-- 1234567 -> "1,234,567"
function HV.Number(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

------------------------------------------------------------------------
-- Data
------------------------------------------------------------------------
-- { people, sharing, totals = { key = n }, boards = { key = { { e, n }... } }, mine = person key }
function HV:Boards()
    local period, alts = self:Period(), ns.DB:Settings().hofAlts
    local month = ns.HallOfFame.Month()
    local groups, order = {}, {}
    for _, e in ipairs(ns.Roster.members) do
        local key = alts and e.full or (e.main or e.full)
        local g = groups[key]
        if not g then
            g = { chars = {} }
            groups[key] = g
            order[#order + 1] = key
        end
        g.chars[#g.chars + 1] = e
        if e.full == key then g.e = e end
    end
    local boards, totals, sharing, noAddon = {}, {}, 0, 0
    for _, s in ipairs(ns.HallOfFame.STATS) do boards[s.key] = {} end
    for _, key in ipairs(order) do
        local g = groups[key]
        g.e = g.e or g.chars[1] -- main not in the guild: their first alt
        local sum, any, hasAddon = {}, false, false
        for _, c in ipairs(g.chars) do
            if c.hasAddon then hasAddon = true end
            local t = ns.HallOfFame:For(c.full, period, month)
            if t then
                any = true
                for k, n in pairs(t) do sum[k] = (sum[k] or 0) + n end
            end
        end
        if not hasAddon then noAddon = noAddon + 1 end
        if any then
            sharing = sharing + 1
            for k, n in pairs(sum) do
                if n > 0 and boards[k] then
                    table.insert(boards[k], { e = g.e, n = n, key = key })
                    totals[k] = (totals[k] or 0) + n
                end
            end
        end
    end
    for _, list in pairs(boards) do
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.e.short < b.e.short
        end)
    end
    local mine
    local me = Me()
    local myEntry = me and ns.Roster.byName[me]
    if myEntry then mine = alts and myEntry.full or (myEntry.main or myEntry.full) end
    return { people = #order, sharing = sharing, noAddon = noAddon, totals = totals, boards = boards, mine = mine }
end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local function Card(parent)
    local c = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    c:SetHeight(CARD_H)
    if c.SetBackdrop then
        c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        c:SetBackdropColor(0.05, 0.04, 0.03, 0.85)
        c:SetBackdropBorderColor(0.5, 0.42, 0.25, 0.9)
    end
    c.Icon = c:CreateTexture(nil, "ARTWORK")
    c.Icon:SetSize(18, 18)
    c.Icon:SetPoint("TOPLEFT", 8, -7)
    c.Title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.Title:SetPoint("LEFT", c.Icon, "RIGHT", 6, 0)
    c.Title:SetPoint("RIGHT", -8, 0)
    c.Title:SetJustifyH("LEFT")
    c.Title:SetWordWrap(false)
    c.rows = {}
    for i = 1, TOP do
        local r = {}
        r.Rank = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.Rank:SetPoint("TOPLEFT", 10, -28 - (i - 1) * ROW_H)
        r.Rank:SetWidth(16)
        r.Rank:SetJustifyH("RIGHT")
        r.Name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Name:SetPoint("LEFT", r.Rank, "RIGHT", 6, 0)
        r.Name:SetJustifyH("LEFT")
        r.Name:SetWordWrap(false)
        r.Value = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.Value:SetPoint("TOPRIGHT", -10, -28 - (i - 1) * ROW_H)
        r.Value:SetJustifyH("RIGHT")
        r.Name:SetPoint("RIGHT", r.Value, "LEFT", -6, 0)
        c.rows[i] = r
    end
    c.You = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.You:SetPoint("BOTTOMLEFT", 10, 7)
    c.You:SetPoint("BOTTOMRIGHT", -10, 7)
    c.You:SetJustifyH("LEFT")
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self) HV:ShowCardTip(self) end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

local function NameText(p, mine)
    local r, g, b = ns.ClassColor(p.e.classFile)
    local hex = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
    return hex .. p.e.short .. "|r" .. (p.key == mine and (GOLD .. " (you)|r") or "")
end

function HV:FillCard(c, stat, data)
    local list = data.boards[stat.key]
    c.stat, c.list = stat, list
    W.SetIcon(c.Icon, stat.icon)
    c.Title:SetText(stat.label)
    for i, r in ipairs(c.rows) do
        local p = list[i]
        if p then
            r.Rank:SetText(i .. ".")
            r.Name:SetText(NameText(p, data.mine))
            r.Value:SetText(HV.Number(p.n))
        else
            r.Rank:SetText("")
            r.Name:SetText(i == 1 and (GRAY .. "Nobody yet|r") or "")
            r.Value:SetText("")
        end
    end
    local you = ""
    for i, p in ipairs(list) do
        if p.key == data.mine then
            if i > TOP then you = ("You: #%d with %s"):format(i, HV.Number(p.n)) end
            break
        end
    end
    if you == "" and #list > 0 then
        you = ("Guild: %s"):format(HV.Number(data.totals[stat.key] or 0))
    end
    c.You:SetText(you)
end

function HV:ShowCardTip(c)
    if not c.stat then return end
    GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
    GameTooltip:AddLine(c.stat.label .. GRAY .. "  " .. PeriodText(self:Period()) .. "|r")
    if c.stat.tip then GameTooltip:AddLine(c.stat.tip, 1, 1, 1, true) end
    local mine = self.data and self.data.mine
    for i, p in ipairs(c.list or {}) do
        if i > 15 then GameTooltip:AddLine(("...and %d more"):format(#c.list - 15), 0.6, 0.6, 0.6) break end
        GameTooltip:AddDoubleLine(i .. ". " .. NameText(p, mine), HV.Number(p.n), 1, 1, 1, 1, 1, 1)
    end
    if self.data and self.data.totals[c.stat.key] then
        GameTooltip:AddDoubleLine("Guild total", HV.Number(self.data.totals[c.stat.key]), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function HV:Build(frame)
    local page = CreateFrame("Frame", nil, frame)
    page:SetAllPoints()
    page:Hide()
    self.page, self.frame = page, frame

    self.title = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -37)

    local periodBtn = W.Button(page, "", 120, 22)
    periodBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -32)
    periodBtn:SetScript("OnClick", function(btn)
        local items = { { text = "Show", isTitle = true } }
        for _, d in ipairs(PERIODS) do
            items[#items + 1] = { text = d[2], radio = true,
                checked = function() return HV:Period() == d[1] end,
                func = function() ns.DB:Settings().hofPeriod = d[1]; HV:Refresh() end }
        end
        W.ShowMenu(btn, items)
    end)
    W.Tooltip(periodBtn, "Period", "All time, or just this month or last month (UTC). A member's first month counts from when they installed the addon.")
    self.periodButton = periodBtn

    local alts = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    alts:SetSize(22, 22)
    alts:SetPoint("RIGHT", periodBtn, "LEFT", -110, 0)
    local label = alts.Text or alts.text or alts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:ClearAllPoints()
    label:SetPoint("LEFT", alts, "RIGHT", 2, 1)
    label:SetFontObject("GameFontHighlightSmall")
    label:SetText("Count alts")
    alts:SetScript("OnClick", function(cb)
        ns.DB:Settings().hofAlts = cb:GetChecked() and true or nil
        HV:Refresh()
    end)
    W.Tooltip(alts, "Count alts", "Off: each person's characters are added up under their main. On: every character on its own.")
    self.altsCheck = alts

    local inset = frame.Inset
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMHallOfFameScroll", page, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 6)
    scroll:EnableMouseWheel(true)
    self.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 400)
    scroll:SetScrollChild(content)
    self.content = content

    self.totals = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.totals:SetPoint("TOPLEFT", 0, 0)
    self.totals:SetJustifyH("LEFT")
    -- who's missing from the board: guildmates without the addon
    self.gap = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.gap:SetPoint("TOPLEFT", self.totals, "BOTTOMLEFT", 0, -6)
    self.gap:SetJustifyH("LEFT")
    self.gapButton = W.Button(content, "List them", 80, 18)
    self.gapButton:SetPoint("LEFT", self.gap, "RIGHT", 8, 0)
    self.gapButton:SetScript("OnClick", function() ns.UI:SetSearch("is:missing") end)
    W.Tooltip(self.gapButton, "Not on the board yet", "Lists them on the Find tab. Right-click someone there (or open their profile) to remind them to install the addon.")
    self.cards = {}
    self.note = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.note:SetJustifyH("LEFT")

    local function later() if page:IsVisible() then ns.Debounce("hofview", 0.3, function() HV:Refresh() end) end end
    page:SetScript("OnShow", function()
        ns.Roster:Request()
        ns.HallOfFame:Publish() -- your own numbers, fresh
        HV:Refresh()
    end)
    page:SetScript("OnSizeChanged", later)
    ns:On("ROSTER_UPDATED", later)
    ns:On("MEMBER_CHANGED", later)
    ns:On("HALL_OF_FAME_CHANGED", later)
end

function HV:Refresh()
    if not (self.page and self.page:IsVisible()) then return end
    local data = self:Boards()
    self.data = data
    local period = self:Period()
    self.periodButton:SetText(PeriodText(period))
    self.altsCheck:SetChecked(ns.DB:Settings().hofAlts and true or false)
    local who = ns.DB:Settings().hofAlts and "characters" or "people"
    self.title:SetText(("Hall of Fame  " .. GRAY .. "- %d of %d %s sharing|r"):format(data.sharing, data.people, who))

    local width = math.max(300, math.floor(self.scroll:GetWidth()))
    local parts = {}
    for _, k in ipairs(TOTALS) do
        local s = ns.HallOfFame.BY_KEY[k]
        parts[#parts + 1] = GOLD .. HV.Number(data.totals[k] or 0) .. "|r " .. s.label:lower()
    end
    self.totals:SetWidth(width)
    self.totals:SetText("Together: " .. table.concat(parts, GRAY .. "  ·  |r"))
    local top = math.max(16, self.totals:GetStringHeight()) + 12
    local who = ns.DB:Settings().hofAlts and (data.noAddon == 1 and "character" or "characters")
        or (data.noAddon == 1 and "guildmate" or "guildmates")
    self.gap:SetShown(data.noAddon > 0)
    self.gapButton:SetShown(data.noAddon > 0)
    if data.noAddon > 0 then
        local text = ("%d %s aren't on the board yet: no addon."):format(data.noAddon, who)
        if data.noAddon == 1 then text = text:gsub("aren't", "isn't") end
        self.gap:SetText(text)
        top = top + 24
    end

    local cols = math.max(1, math.floor((width + CARD_GAP) / (CARD_W + CARD_GAP)))
    local cardW = math.floor((width - (cols - 1) * CARD_GAP) / cols)
    for i, stat in ipairs(ns.HallOfFame.STATS) do
        local c = self.cards[i] or Card(self.content)
        self.cards[i] = c
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", col * (cardW + CARD_GAP), -(top + row * (CARD_H + CARD_GAP)))
        c:SetWidth(cardW)
        self:FillCard(c, stat, data)
        c:Show()
    end
    local rows = math.ceil(#ns.HallOfFame.STATS / cols)
    local y = top + rows * (CARD_H + CARD_GAP)

    local note
    if not ns.HallOfFame:Available() then
        note = "This game client doesn't give addons character statistics, so there's nothing to show."
    elseif data.sharing == 0 then
        note = "Nobody has shared their statistics yet. Each member's own addon shares them a little after they log in."
    else
        note = "From the game's own statistics (the Statistics page of the achievement window), shared by each member's addon. "
            .. "Members without the addon, or who turned off \"Share my statistics\" (Options > Sharing), aren't listed. Gold is never shared."
    end
    if period ~= "all" then
        note = note .. " Months run in UTC; a member's first month counts from when they installed the addon."
    end
    self.note:ClearAllPoints()
    self.note:SetPoint("TOPLEFT", 0, -y)
    self.note:SetWidth(width)
    self.note:SetText(note)
    self.content:SetSize(width, y + self.note:GetStringHeight() + 8)
end
