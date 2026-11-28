--[[
    Nootropic Guild Manager - Options
    Pages in the game's Options > AddOns list (also opened by /ngm options,
    or right-clicking the minimap button):

      Nootropic Guild Manager   appearance, minimap button, reset, sync and commands
        Recruiting              /who whisper button, sending, auto-invite, Do Not Whisper
        Officers                permissions (Guild Master), audit history
        About                   what the addon does, credits, links

    O:Open(key) opens one: nil (main), "recruiting", "officers" or "about".
]]
local _, ns = ...
local W, D = ns.Widgets, ns.Data
local O = {}
ns.Options = O

local PANEL_NAME = "Nootropic Guild Manager"
O.pages = {}   -- key -> outer frame
O.subcats = {} -- key -> settings category

------------------------------------------------------------------------
-- Layout: each page stacks rows top to bottom with a cursor
------------------------------------------------------------------------
local Layout = {}
Layout.__index = Layout

function Layout:Header(text)
    local title, line = W.SectionHeader(self.panel, text)
    title:SetPoint("TOPLEFT", 16, self.y)
    line:SetPoint("RIGHT", self.panel, "RIGHT", -16, 0)
    self.y = self.y - 26
    return title
end

-- Text blocks wrap at a fixed width. Pages are built while hidden, before
-- the game has sized them, so a block can't measure its own wrapped height;
-- an invisible copy on UIParent (always laid out) measures it instead. The
-- settings canvas is ~635 wide on Forever (SettingsPanel 920), so 564 fits.
local TEXT_W = 564
local measure
local function TextHeight(text, font, width)
    if not measure then
        measure = UIParent:CreateFontString(nil, "OVERLAY")
        measure:SetWordWrap(true)
        measure:SetJustifyH("LEFT")
        -- shown but invisible and off screen, so it's always laid out
        measure:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 200, -200)
        measure:SetAlpha(0)
    end
    measure:SetFontObject(font)
    measure:SetSpacing(3)
    measure:SetWidth(width or TEXT_W)
    measure:SetText(text ~= "" and text or " ")
    return math.ceil(measure:GetStringHeight() or 14)
end

-- A checkbox with an optional hint under it (wraps, like Text).
local HINT_INDENT = 26 -- the label starts 26 further right than text blocks
function Layout:Check(text, hint, onClick)
    local cb = CreateFrame("CheckButton", nil, self.panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 14, self.y)
    local label = cb.Text or cb.text
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "NGMFontText")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    end
    label:SetFontObject("NGMFontText")
    label:SetText(text)
    local hintH = 0
    if hint then
        local h = self.panel:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
        h:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        h:SetWidth(TEXT_W - HINT_INDENT)
        h:SetJustifyH("LEFT")
        h:SetWordWrap(true)
        h:SetSpacing(3)
        h:SetText(hint)
        cb.Hint = h
        hintH = TextHeight(hint, "NGMFontDimSmall", TEXT_W - HINT_INDENT)
    end
    cb:SetScript("OnClick", function(b) onClick(b:GetChecked() and true or false) end)
    self.y = self.y - (hint and (30 + hintH) or 30)
    return cb
end

-- A block of text (wraps at TEXT_W). Text set later with SetText should be
-- no longer than the text it was built with, or it would run into what's below.
function Layout:Text(text, font, gap)
    font = font or "NGMFontTextSmall"
    local fs = self.panel:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", 18, self.y)
    fs:SetWidth(TEXT_W)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetSpacing(3)
    fs:SetText(text)
    self.y = self.y - math.max(14, TextHeight(text, font)) - (gap or 8)
    return fs
end

-- Reserves `height` and returns the top of that row.
function Layout:Row(height)
    local y = self.y
    self.y = self.y - height
    return y
end

function Layout:Space(n) self.y = self.y - (n or 10) end

function Layout:Finish()
    self.panel:SetHeight(-self.y + 30)
    if self.root then self.root:SetHeight(-self.y + 30) end
end

-- A scrolling page with a title. Returns the outer frame and a layout.
local function NewPage(key, name, subtitle)
    local outer = CreateFrame("Frame", "NootropicGMOptions" .. key, UIParent)
    outer.name = name
    outer:Hide()
    local scroll = W.TryCreate("ScrollFrame", "NootropicGMOptionsScroll" .. key, outer, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(600, 800)
    scroll:SetScrollChild(panel)
    outer:SetScript("OnSizeChanged", function(_, w) panel:SetWidth(math.max(400, (w or 600) - 30)) end)
    outer:SetScript("OnShow", function(f)
        O:Refresh()
    end)
    O.pages[key] = outer

    -- the addon's own logo, whatever the icon choice (this is about the addon)
    local logo = ns.Brand:Attach(panel, 36, { "TOPLEFT", panel, "TOPLEFT", 16, -14 })
    local title = panel:CreateFontString(nil, "OVERLAY", "NGMFontTitle")
    title:SetPoint("TOPLEFT", logo.Slot, "TOPRIGHT", 10, -2)
    title:SetText(key == "main" and PANEL_NAME or (PANEL_NAME .. "  |cffffffff-  " .. name .. "|r"))
    local sub = panel:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(subtitle)
    outer.Sub = sub
    O.logos = O.logos or {}
    O.logos[#O.logos + 1] = logo
    -- everything below the title goes in Body, so a page a rank can't use
    -- hides it and shows one line (Locked) instead
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT")
    body:SetPoint("TOPRIGHT")
    body:SetHeight(800)
    local locked = panel:CreateFontString(nil, "OVERLAY", "NGMFontText")
    locked:SetPoint("TOPLEFT", 16, -66)
    locked:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    locked:SetJustifyH("LEFT")
    locked:Hide()
    outer.Body, outer.Locked = body, locked
    return outer, setmetatable({ panel = body, root = panel, y = -66 }, Layout)
end

-- Small dropdown-style button that picks one of D.MINIMAP_ACTIONS.
local function ActionPicker(L, label, key)
    local y = L:Row(28)
    local text = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontText")
    text:SetPoint("TOPLEFT", 42, y - 4)
    text:SetText(label)
    local b = W.Button(L.panel, "", 200, 22)
    b:SetPoint("TOPLEFT", 150, y)
    b:SetScript("OnClick", function(self)
        local items = { { text = label, isTitle = true } }
        for _, a in ipairs(D.MINIMAP_ACTIONS) do
            items[#items + 1] = {
                text = D:MinimapActionLabel(a.key), radio = true,
                checked = function() return ns.DB:Settings().minimap[key] == a.key end,
                func = function()
                    ns.DB:Settings().minimap[key] = a.key
                    O:Refresh()
                end,
            }
        end
        W.ShowMenu(self, items)
    end)
    b.key = key
    return b
end

-- Picks a Guild Feed sound (feed: "levelUp" or "event"): Off, the NGM
-- Addon's own, the game's, and any from LibSharedMedia (in groups when
-- there are many). Picking one plays it.
local SHARED_PER_MENU = 25
local function SoundPicker(L, feed, title)
    local F = ns.GuildFeed
    local y = L:Row(28)
    local text = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontText")
    text:SetPoint("TOPLEFT", 42, y - 4)
    text:SetText("Sound")
    local b = W.Button(L.panel, "", 200, 22)
    b:SetPoint("TOPLEFT", 150, y)
    local function Item(key, name)
        return {
            text = name, radio = true,
            checked = function() return F:SoundKey(feed) == key end,
            func = function()
                ns.DB:Settings()[F.FEEDS[feed].choice] = key
                F:PlaySound(key)
                O:Refresh()
            end,
        }
    end
    b:SetScript("OnClick", function(self)
        local c = F:SoundChoices()
        local items = { { text = title, isTitle = true }, Item(F.OFF, "Off"), { divider = true } }
        for _, s in ipairs(c.own) do items[#items + 1] = Item(s.key, s.name) end
        if #c.game > 0 then
            items[#items + 1] = { divider = true }
            for _, s in ipairs(c.game) do items[#items + 1] = Item(s.key, s.name) end
        end
        if #c.shared > 0 then
            items[#items + 1] = { divider = true }
            local n = #c.shared
            for first = 1, n, SHARED_PER_MENU do
                local last = math.min(first + SHARED_PER_MENU - 1, n)
                local sub = {}
                for i = first, last do sub[#sub + 1] = Item("lsm:" .. c.shared[i], c.shared[i]) end
                local label = "SharedMedia"
                if n > SHARED_PER_MENU then label = ("SharedMedia: %s - %s"):format(c.shared[first], c.shared[last]) end
                items[#items + 1] = { text = label, submenu = sub }
            end
        end
        W.ShowMenu(self, items)
    end)
    b.Label, b.feed = text, feed
    return b
end

-- Six small word boxes (keywords, Do Not Whisper words), three per row.
local function WordBoxes(L, maxLetters, onChange)
    local boxes = {}
    local top = L:Row(54)
    for i = 1, D.MAX_KEYWORDS do
        local eb = CreateFrame("EditBox", nil, L.panel, "InputBoxTemplate")
        eb:SetSize(120, 20)
        eb:SetAutoFocus(false)
        eb:SetFontObject("NGMFontTextSmall")
        eb:SetMaxLetters(maxLetters)
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        eb:SetPoint("TOPLEFT", 26 + col * 132, top - row * 26)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        eb:HookScript("OnTextChanged", function(self, user) if user then onChange(i, ns.Trim(self:GetText())) end end)
        boxes[i] = eb
    end
    return boxes
end

local function RecruitChanged() ns:Fire("RECRUITS_CHANGED") end

------------------------------------------------------------------------
-- Main page: appearance, minimap button, reset, about
------------------------------------------------------------------------
function O:BuildMain()
    local outer, L = NewPage("main", PANEL_NAME,
        ("Version %s  -  /ngm to open  -  more settings on the Recruiting and Officers pages below this one"):format(ns.version))
    self.panel = outer

    L:Header("How It Works")
    L:Text(("Open the window with |cffffffff/ngm|r or the minimap button. Its tabs: " .. ns.GOLD .. "Find|r (search the guild), " .. ns.GOLD .. "Play Together|r (who's around near your level), " .. ns.GOLD .. "Recruitment|r and, for officers, " .. ns.GOLD .. "Audit|r. Click anyone for their profile: spec, professions and recipes, raid readiness, contact info and your private notes."))
    L:Text(("Everyone running the NGM Addon shares what their own copy knows: spec, professions, recipes (when they open a profession window), raid attunements and when they usually play. The more of the guild uses it, the more it knows. Private notes never leave your computer. The " .. ns.GOLD .. "About|r page below has links and credits."), "NGMFontDimSmall")
    L:Space(4)

    L:Header("Appearance")
    self.addonCountCheck = L:Check("Show how many guildmates use the NGM Addon",
        "The \"x using ... Guild Manager\" text at the bottom of the window.", function(on)
            ns.DB:Settings().showAddonCount = on
            ns:Fire("SETTINGS_CHANGED")
        end)
    self.communitiesCheck = L:Check("Shortcut on the Guild & Communities window",
        "A side tab with the NGM Addon icon.", function(on) ns.Communities:SetEnabled(on) end)
    self.blizzRosterCheck = L:Check("Show alts and profiles on the Guild roster",
        "On the game's Guild & Communities roster: this addon's details in the tooltip, and Profile and Main / Alt in the right-click menu. Alt+click a member for their profile.",
        function(on) ns.GuildRoster:SetEnabled(on) end)

    L:Space(4)

    L:Header("Guild Feed  |cff9d9d9d(in your own chat, never sent)|r")
    self.eventNoticesCheck = L:Check("Show new guild events",
        "A line when a new raid, dungeon or event from NGM Peon reaches the game: what, when (your time) and where to sign up.",
        function(on) ns.DB:Settings().eventNotices = on; O:Refresh() end)
    self.eventSoundPicker = SoundPicker(L, "event", "New event sound")
    self.levelUpsCheck = L:Check("Show guild level-ups",
        "A line when someone in the guild levels up (\"Pip reached level 31!\"), while you're online.",
        function(on) ns.DB:Settings().levelUps = on; O:Refresh() end)
    self.levelUpSoundPicker = SoundPicker(L, "levelUp", "Level-up sound")

    L:Space(4)

    L:Header("Sharing  |cff9d9d9d(what only your copy knows)|r")
    self.shareRecipesCheck = L:Check("Share my recipes",
        "Recipes you've learned, so guildmates can find you in Who Can Craft?. Shared when you open a profession window. Off: your recipes are cleared.",
        function(on) ns.Sharing:Set("recipes", on) end)
    self.learnCheck = L:Check("Learn when I usually play",
        "Notes the hour every 10 minutes while you play (last 4 weeks, this computer only) and shares just the summary, shown as \"Usually online\" on your profile. Off: nothing is noted or shared. (This character.)",
        function(on) ns.Profile:SetLearn(on) end)
    L:Text("Only what comes from your own copy of the NGM Addon has a switch. Your spec, professions, statistics (never gold) and guild chat time (never the words) are always shared: they're public anyway, from Blizzard and the game.", "NGMFontDimSmall")
    local wy = L:Row(30)
    local tour = W.Button(L.panel, "Show the Welcome Tour", 190, 24, "alt")
    tour:SetPoint("TOPLEFT", 18, wy)
    tour:SetScript("OnClick", function() ns.Welcome:Open() end)
    W.Tooltip(tour, "Welcome tour", "The first-launch walkthrough again: what each tab does, your sharing choices, your profile basics (and permissions, for the Guild Master). Also /ngm welcome.")
    L:Space(4)

    -- Install reminder: the whisper "Remind to install the addon" sends
    L:Header("Install Reminder")
    L:Text(("What guildmates without the NGM Addon get when you click " .. ns.GOLD .. "Remind to install the NGM Addon|r on their profile or right-click menu. ")
        .. (ns.GOLD .. "$first|r, " .. ns.GOLD .. "$name|r and " .. ns.GOLD .. "$guild|r are filled in. Add your Discord invite if you'd like it to cover that too. Once per 30 days per player (alts count), for the whole guild. Saved as you type."))
    local ry = L:Row(84)
    local ef, box = W.ScrollEditor(L.panel, 255)
    ef:SetPoint("TOPLEFT", 22, ry)
    ef:SetSize(TEXT_W - 8, 70)
    box:SetFontObject("NGMFontTextSmall")
    box:SetWidth(TEXT_W - 26)
    self.reminderBox = box
    local count = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    count:SetJustifyH("LEFT")
    self.reminderCount = count
    local function update()
        count:SetText(ns.Recruit:LengthText(box:GetText() ~= "" and box:GetText() or ns.InstallReminder.DEFAULT)
            .. (box:GetText() == "" and "  (empty: the default text is used)" or ""))
    end
    box:HookScript("OnTextChanged", function(eb, user)
        -- the guild's text is read-only here: it's changed by sharing yours
        if user and ns.InstallReminder:UsingGuild() then eb:SetText(ns.InstallReminder:GuildText()) return end
        if user then ns.InstallReminder:SetText(eb:GetText()) end
        update()
    end)
    local cy = L:Row(26)
    local default = W.Button(L.panel, "Default Text", 110, 22, "alt")
    default:SetPoint("TOPLEFT", 18, cy)
    default:SetScript("OnClick", function()
        ns.InstallReminder:SetText("")
        box:SetText(ns.InstallReminder.DEFAULT)
        box:ClearFocus()
    end)
    count:SetPoint("LEFT", default, "RIGHT", 10, 0)
    -- the guild's text (3.2, docs/PERMISSIONS.md)
    self.reminderGuild = L:Text(("x"):rep(120), "NGMFontDimSmall", 4)
    local gy = L:Row(26)
    local switch = W.Button(L.panel, "", 130, 22, "alt")
    switch:SetPoint("TOPLEFT", 18, gy)
    switch:SetScript("OnClick", function()
        ns.InstallReminder:SetOwn(ns.InstallReminder:UsingGuild())
        box:SetText(ns.InstallReminder:Text())
        O:Refresh()
    end)
    local share = W.Button(L.panel, "Share as the Guild's", 150, 22)
    share:SetPoint("LEFT", switch, "RIGHT", 8, 0)
    share:SetScript("OnClick", function()
        local ok, err = ns.InstallReminder:Publish()
        ns:Print(ok and "Shared as the guild's install reminder text." or ("|cffff2020" .. (err or "That didn't work.") .. "|r"))
        O:Refresh()
    end)
    W.Tooltip(share, "Share as the guild's", "Your text becomes the guild's install reminder (the Guild Master's Permissions say who may).")
    self.reminderSwitch, self.reminderShare = switch, share
    L:Space(4)

    L:Header("Minimap Button")
    self.minimapCheck = L:Check("Show minimap button", nil, function(on) ns.Minimap:SetShown(on) end)
    self.clickPickers = {
        ActionPicker(L, "Left-click", "left"),
        ActionPicker(L, "Right-click", "right"),
        ActionPicker(L, "Shift-click", "shift"),
    }
    L:Space(8)

    L:Header("Reset")
    local y = L:Row(32)
    local resetWin = W.Button(L.panel, "Window Size and Position", 190, 24, "alt")
    resetWin:SetPoint("TOPLEFT", 18, y)
    resetWin:SetScript("OnClick", function()
        ns.UI:ResetPosition()
        ns:Print("Window size and position reset.")
    end)
    local resetCols = W.Button(L.panel, "List Columns", 140, 24, "alt")
    resetCols:SetPoint("LEFT", resetWin, "RIGHT", 8, 0)
    resetCols:SetScript("OnClick", function()
        W.Confirm("Reset the columns of the roster and the recruitment list to their default order, widths and visibility?", function()
            ns.RosterView:ResetColumns()
            ns.RecruitView.cols:Reset()
            ns:Print("List columns reset to defaults.")
        end)
    end)
    W.Tooltip(resetCols, "Reset list columns", "Default column order, widths and which columns are shown, on the roster and the recruitment list.")
    L:Space(6)

    L:Header("Sync and Commands")
    self.syncStatus = L:Text("", "NGMFontTextSmall", 6)
    y = L:Row(32)
    local syncNow = W.Button(L.panel, "Sync Now", 110, 24)
    syncNow:SetPoint("TOPLEFT", 18, y)
    syncNow:SetScript("OnClick", function()
        ns.Comm:Report()
        if ns.Sync:CheckAll() then
            ns.Sync.reportLane = "guild"
            ns:Print("Checking with your guild now...")
        end
        O:Refresh()
    end)
    W.Tooltip(syncNow, "Sync now", "Checks your data against your guildmates' and fetches anything you're missing. It also happens by itself each time you log in, and changes are sent as you make them.")
    local open = W.Button(L.panel, "Open Guild Manager", 170, 24)
    open:SetPoint("LEFT", syncNow, "RIGHT", 8, 0)
    open:SetScript("OnClick", function() ns.UI:OpenTab(ns.UI.TAB_ROSTER) end)
    local connect = W.Button(L.panel, "Get Connected", 140, 24, "alt")
    connect:SetPoint("LEFT", open, "RIGHT", 8, 0)
    connect:SetScript("OnClick", function() ns.ConnectGuide:Open() end)
    self.connectButton = connect -- shown only in guilds using NGM Peon (O:Refresh)
    W.Tooltip(connect, "Get Connected", "With NGM Peon: linking your characters and Discord in WoW, and where each stands.")
    L:Text((ns.GOLD .. "Commands|r\n")
        .. "|cffffffff/ngm|r open or close     |cffffffff/ngm find <text>|r search the roster     |cffffffff/ngm recruit|r recruiting\n"
        .. "|cffffffff/ngm sync|r sync now     |cffffffff/ngm diag|r troubleshooting     |cffffffff/ngm help|r every command", "NGMFontTextSmall")
    L:Finish()
end

------------------------------------------------------------------------
-- Recruiting page
------------------------------------------------------------------------
function O:BuildRecruiting()
    local outer, L = NewPage("recruiting", "Recruiting", "Saved for the guild you're in. Messages and searching are on the Recruitment tab.")
    self.recruitNoGuild = L:Text("|cffff2020Join a guild to change these settings.|r")

    L:Header("/who Window")
    self.whoWhisperCheck = L:Check("Recruitment whisper button on /who results",
        "A button on each player in the game's /who search that sends them your recruitment whisper.",
        function(on) ns.WhoWhisper:SetEnabled(on) end)
    L:Space(4)

    L:Header("Sending Whispers")
    L:Text("The Recruitment tab sends whispers one at a time, at least 12 seconds apart. Blizzard doesn't publish a whisper limit: silences come from players reporting spam, so a friendly message matters more than the pace.")
    local hy = L:Row(30)
    local hourLabel = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontText")
    hourLabel:SetPoint("TOPLEFT", 20, hy - 4)
    hourLabel:SetText("Whispers per hour")
    local hourBtn = W.Button(L.panel, "", 160, 22)
    hourBtn:SetPoint("TOPLEFT", 170, hy)
    local function HourText(n) return n == 0 and "No hourly cap (300 max)" or (n .. " per hour") end
    hourBtn:SetScript("OnClick", function(btn)
        local items = { { text = "Whispers per hour", isTitle = true } }
        for _, n in ipairs(ns.Recruit.HOURLY_CHOICES) do
            items[#items + 1] = { text = HourText(n) .. (n == 40 and "  |cff9d9d9d(default)|r" or ""), radio = true,
                checked = function() return (ns.DB:Settings().whisperPerHour or 40) == n end,
                func = function() ns.DB:Settings().whisperPerHour = n; O:Refresh(); RecruitChanged() end }
        end
        W.ShowMenu(btn, items)
    end)
    W.Tooltip(hourBtn, "Whispers per hour", "How many whispers the queue sends in any hour. Saved for all your characters.")
    hourBtn.HourText = HourText
    self.hourButton = hourBtn
    L:Space(4)

    L:Header("Auto-Invite")
    self.autoCheck = L:Check("Invite popup when they reply with a keyword",
        "Only replies from players you whispered from the NGM Addon are checked. WoW: Forever only lets you send guild invites yourself, so this pops up an Invite button to click.", function(on)
            local r = ns.Recruit:Settings()
            if r then r.autoInvite = on end
            RecruitChanged()
        end)
    L:Text((ns.GOLD .. "Keywords|r  |cff9d9d9d(whole words, any case)|r"), "NGMFontTextSmall", 4)
    self.keywordBoxes = WordBoxes(L, 24, function(i, text)
        local r = ns.Recruit:Settings()
        if r then r.keywords[i] = text end
        RecruitChanged()
    end)
    L:Space(4)

    L:Header("Do Not Whisper")
    self.dnwCheck = L:Check("Add people to the Do Not Whisper list",
        "When someone answers the NGM Addon's whisper with one of these words, nobody in the guild whispers or invites them again. Replies after you've whispered them yourself don't count.",
        function(on)
            local r = ns.Recruit:Settings()
            if r then r.dnwEnabled = on end
            RecruitChanged()
        end)
    L:Text((ns.GOLD .. "Words|r  |cff9d9d9d(whole words, any case)|r"), "NGMFontTextSmall", 4)
    self.dnwBoxes = WordBoxes(L, 32, function(i, text)
        local r = ns.Recruit:Settings()
        if r then r.dnwWords[i] = text end
        RecruitChanged()
    end)
    local y = L:Row(30)
    self.dnwCount = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.dnwCount:SetPoint("TOPLEFT", 26, y - 5)
    local view = W.Button(L.panel, "View List", 100, 22, "alt")
    view:SetPoint("TOPLEFT", 290, y)
    view:SetScript("OnClick", function() ns.DNWView:Open() end)
    W.Tooltip(view, "Do Not Whisper list", "Who is on it for good, and who was whispered in the last 14 days (with the time left). Shared with everyone in the guild using the NGM Addon.")
    self.dnwView = view
    L:Finish()
    return outer
end

------------------------------------------------------------------------
-- Officers page
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Permissions (the Guild Master): which ranks may do what
------------------------------------------------------------------------
function O:PermMenu(owner, key)
    local DB = ns.DB
    local narrow = ns.Sync.PERM_NARROW[key]
    local needs = ns.Sync.PERM_NEEDS[key]
    local invite = ns.Sync.PERM_INVITE[key]
    local function Set(set)
        local ok, err = DB:SetPermRanks(key, set)
        if not ok and err then ns:Print("|cffff2020" .. err .. "|r") end
        O:Refresh()
    end
    -- the ranks that may now: the chosen ones, or the default's
    local function Current()
        local out, set = {}, DB:PermRanks(key)
        for _, r in ipairs(DB:GuildRanks()) do
            if r.index ~= 0 and (set and set[r.index] or (not set and DB:RankMay(r, key))) then out[r.index] = true end
        end
        return out
    end
    local holdable = {}
    for _, r in ipairs(DB:GuildRanks()) do if r.index ~= 0 and DB:RankCanHold(r, key) then holdable[#holdable + 1] = r end end
    local items = { { text = "Who may do this", isTitle = true } }
    items[#items + 1] = { text = DB:PermDefaultText(key) .. " (default)", radio = true,
        checked = function() return DB:PermRanks(key) == nil end, func = function() Set(nil) end }
    if not narrow and not needs and not invite then
        -- every rank
        items[#items + 1] = { text = "Everyone", radio = true,
            checked = function()
                local set = DB:PermRanks(key)
                if not set then return false end
                for _, r in ipairs(holdable) do if not set[r.index] then return false end end
                return true
            end,
            func = function()
                local set = {}
                for _, r in ipairs(holdable) do set[r.index] = true end
                Set(set)
            end }
    end
    items[#items + 1] = { text = "Only me (the Guild Master)", radio = true,
        checked = function() local set = DB:PermRanks(key) return set ~= nil and next(set) == nil end,
        func = function() Set({}) end }
    items[#items + 1] = { divider = true }
    items[#items + 1] = { text = narrow and "These officer ranks" or needs and "These ranks (ones that may recruit)" or invite and "These ranks (ones that may invite)" or "These ranks", isTitle = true }
    items[#items + 1] = { text = (DB:GuildRanks()[1] and DB:GuildRanks()[1].name or "Guild Master") .. "  |cff9d9d9d(always)|r", isTitle = true }
    for _, r in ipairs(holdable) do
        items[#items + 1] = {
            text = r.name,
            -- ticked: may now (the default's ranks too, while it's the default)
            checked = function() return Current()[r.index] == true end,
            -- from the default, a tick adds to (or takes from) what it allows
            func = function()
                local set = Current()
                set[r.index] = not set[r.index] or nil
                Set(set)
            end,
        }
    end
    W.ShowMenu(owner, items)
end

------------------------------------------------------------------------
-- Permissions page (3.2, docs/PERMISSIONS.md): who may do what, the whole
-- guild; only the Guild Master changes it, everyone sees what their rank may do
------------------------------------------------------------------------
function O:BuildPermissions()
    local outer, L = NewPage("permissions", "Permissions", "Who may do what in the guild. Only the Guild Master changes these.")
    self.rulesStatus = L:Text(("x"):rep(160), "NGMFontTextSmall", 4)
    local y = L:Row(26)
    self.rulesCopy = W.Button(L.panel, "Copy the line", 130, 22, "alt")
    self.rulesCopy:SetPoint("TOPLEFT", 18, y)
    self.rulesCopy:SetScript("OnClick", function() W.Copy(ns.GuildRules:Line()) end)
    W.Tooltip(self.rulesCopy, "The Guild Info line", "Paste it anywhere in the Guild Info (Guild & Communities, Guild Info). Every copy of the NGM Addon checks its rules against it.")
    L:Space(6)
    self.permRows = {}
    local group
    for _, perm in ipairs(ns.DB.PERMS) do
        if perm.group ~= group then
            group = perm.group
            L:Header(group)
        end
        local ry = L:Row(28)
        local label = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontText")
        label:SetPoint("TOPLEFT", 20, ry - 4)
        label:SetWidth(250)
        label:SetJustifyH("LEFT")
        label:SetText(perm.label)
        local btn = W.Button(L.panel, "", 210, 22)
        btn:SetPoint("TOPLEFT", 276, ry)
        btn:SetScript("OnClick", function(b) O:PermMenu(b, perm.key) end)
        W.Tooltip(btn, perm.label, perm.hint, function() return "|cffffd100Who may:|r " .. ns.DB:PermText(perm.key, true) end)
        local you = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
        you:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        self.permRows[#self.permRows + 1] = { key = perm.key, btn = btn, you = you }
        -- the locks sit with what they lock
        if perm.key == "rmsg" then
            self.lockRmsg = L:Check("Everyone uses the guild's recruitment messages", "On: nobody can use their own. Off: the guild's are where everyone starts, and they may write their own.",
                function(on) local ok, err = ns.DB:SetLock("rmsg", on) if not ok and err then ns:Print(err) end O:Refresh() end)
        elseif perm.key == "imsg" then
            self.lockImsg = L:Check("Everyone uses the guild's install reminder text", "On: nobody can use their own text. Off: the guild's is where everyone starts.",
                function(on) local ok, err = ns.DB:SetLock("imsg", on) if not ok and err then ns:Print(err) end O:Refresh() end)
        end
    end
    L:Header("Features, for the whole guild")
    L:Text("Off, a feature is hidden for everyone in the guild. What's already shared is kept, so turning it back on loses nothing.", "NGMFontDimSmall")
    self.featureChecks = {}
    for _, f in ipairs(ns.DB.FEATURES) do
        self.featureChecks[f.key] = L:Check(f.label, f.hint, function(on)
            local ok, err = ns.DB:SetFeature(f.key, on)
            if not ok and err then ns:Print(err) end
            O:Refresh()
        end)
    end
    L:Text("Who's an officer and who may invite follow the game's own rank settings (Guild Control: Officer, and Invite Member). Officer data (the Officer Log, the Audit) only ever reaches officer ranks: those rows can only be narrowed.", "NGMFontDimSmall")
    L:Finish()
    return outer
end

function O:RefreshPermControls()
    if not self.permRows then return end
    local DB, GR = ns.DB, ns.GuildRules
    local gm = DB:IsGuildMaster()
    for _, row in ipairs(self.permRows) do
        row.btn:SetText(DB:PermText(row.key))
        -- too long for the button (a long rank name, say): without "(default)"
        local fs = row.btn.GetFontString and row.btn:GetFontString()
        if fs and fs:GetStringWidth() > row.btn:GetWidth() - 16 then row.btn:SetText((DB:PermText(row.key):gsub(" %(default%)$", ""))) end
        row.btn:SetEnabled(gm)
        row.btn:SetAlpha(gm and 1 or 0.7)
        row.you:SetText(gm and "" or (DB:HasPerm(row.key) and "|cff6cbf5ayou may|r" or "you may not"))
    end
    for key, cb in pairs(self.featureChecks or {}) do
        cb:SetChecked(DB:FeatureOn(key))
        cb:SetEnabled(gm)
    end
    for _, pair in ipairs({ { self.lockRmsg, "rmsg" }, { self.lockImsg, "imsg" } }) do
        if pair[1] then pair[1]:SetChecked(DB:Rule("lock_" .. pair[2]) == "1") pair[1]:SetEnabled(gm) end
    end
    -- the Guild Info code (Services/GuildRules.lua)
    local text, showCopy
    if gm then
        local inPlace = GR:LineInPlace()
        if inPlace == false then
            text, showCopy = "|cffff8000Put this in your Guild Info, or everyone's permissions will default to Guild Master only, for safety reasons:|r |cffffffff" .. GR:Line() .. "|r", true
        elseif inPlace then
            text = "|cff6cbf5aIn the Guild Info:|r " .. GR:Line() .. ". Every copy checks your rules against it, so nobody can change them but you."
        elseif next(GR:Raw()) then
            text, showCopy = "Your rules' line for the Guild Info: |cffffffff" .. GR:Line() .. "|r (the Guild Info is checked again out of combat).", true
        else
            text = "Nothing set yet: everything works as before. Change a row and the page gives you a line for the Guild Info."
        end
    elseif GR:Stale() then
        text = "|cffff8000Guild rules not up to date:|r they don't match the Guild Info yet, so every row is Guild Master only for now. Fetching the Guild Master's from guildmates."
    else
        text = GR:Code() and "|cff6cbf5aIn step with the Guild Info.|r Only the Guild Master can change these." or "Only the Guild Master can change these."
    end
    self.rulesStatus:SetText(text)
    self.rulesCopy:SetShown(showCopy == true)
end

function O:BuildOfficers()
    local outer, L = NewPage("officers", "Officers", "For the ranks the game marks Officer.")
    self.officerNote = L:Text("|cffff2020Only officers can change these.|r")
    L:Text("Who may do what (officers included) is on the Permissions page.", "NGMFontDimSmall")

    L:Header("Audit History  |cff9d9d9d(your copy)|r")
    L:Text("How long to keep the record of who changed what. Older entries are deleted.")
    local y = L:Row(30)
    self.auditRadios = {}
    for i, days in ipairs({ 30, 60, 90 }) do
        local rb = CreateFrame("CheckButton", nil, L.panel, "UIRadioButtonTemplate")
        rb:SetSize(20, 20)
        rb:SetPoint("TOPLEFT", 20 + (i - 1) * 110, y)
        local label = rb.text or rb.Text
        if type(label) ~= "table" then label = nil end
        if not label then
            label = rb:CreateFontString(nil, "OVERLAY", "NGMFontText")
            label:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        end
        label:SetFontObject("NGMFontText")
        label:SetText(days .. " days")
        rb.days = days
        rb:SetScript("OnClick", function()
            ns.DB:Settings().auditDays = days
            local removed = ns.Sync:PruneAudit() or 0
            if removed > 0 then ns:Print(("Removed %d audit entries older than %d days."):format(removed, days)) end
            O:Refresh()
        end)
        self.auditRadios[i] = rb
    end
    L:Finish()
    return outer
end

------------------------------------------------------------------------
-- About page
------------------------------------------------------------------------
-- A read-only box holding a link: click to select it, Ctrl+C to copy.
local function LinkRow(L, link)
    local y = L:Row(46)
    local icon = L.panel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("TOPLEFT", 18, y - 4)
    icon:SetTexture(link.icon)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local label = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    label:SetText(link.label)
    local hint = L.panel:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    hint:SetPoint("LEFT", label, "RIGHT", 8, 0)
    hint:SetText(link.hint or "")
    local box = CreateFrame("EditBox", nil, L.panel, "InputBoxTemplate")
    box:SetSize(360, 20)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -3)
    box:SetAutoFocus(false)
    box:SetText(link.url)
    box:SetCursorPosition(0)
    box:SetScript("OnTextChanged", function(eb, user) if user then eb:SetText(link.url); eb:HighlightText() end end)
    box:SetScript("OnEditFocusGained", function(eb) eb:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(eb) eb:HighlightText(0, 0) end)
    box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnKeyDown", function(eb, key)
        if key == "C" and IsControlKeyDown() then C_Timer.After(0.05, function() eb:ClearFocus() end) end
    end)
    W.Tooltip(box, link.label, "Click, then Ctrl+C to copy. Paste it into your browser: the game can't open web links itself.")
    return box
end

function O:BuildAbout()
    local outer, L = NewPage("about", "About", "Who made it, what it does, and where to find more.")

    -- a big banner: the guild's mug, the name, a tagline
    local y = L:Row(92)
    local banner = CreateFrame("Frame", nil, L.panel, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", 14, y)
    banner:SetPoint("RIGHT", L.panel, "RIGHT", -16, 0)
    banner:SetHeight(84)
    banner:SetBackdrop({ bgFile = W.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    ns.Theme:Fill(banner, ns.Theme.C.bg1, 0.9)
    ns.Theme:EdgeColor(banner, ns.Theme.C.yellow)
    local logo = ns.Brand:Attach(banner, 64, { "LEFT", banner, "LEFT", 12, 0 })
    O.logos[#O.logos + 1] = logo
    local name = banner:CreateFontString(nil, "OVERLAY", "NGMFontHuge")
    name:SetPoint("TOPLEFT", logo.Slot, "TOPRIGHT", 14, -6)
    name:SetText((ns.GOLD .. "Nootropic|r Guild Manager"))
    local tag = banner:CreateFontString(nil, "OVERLAY", "NGMFontText")
    tag:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    tag:SetText("Your whole guild, in one window. Built for WoW: Forever.")
    local ver = banner:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    ver:SetPoint("TOPLEFT", tag, "BOTTOMLEFT", 0, -5)
    ver:SetText(("Version %s  -  free, source on GitHub (PolyForm Shield)"):format(ns.version))

    L:Space(6)
    L:Header("What's Inside")
    L:Text((ns.GOLD .. "Find|r  search the whole guild by name, class, spec, profession or Discord, with mains and alts grouped together.\n")
        .. (ns.GOLD .. "Play Together|r  who's online near your level right now, and who usually plays at this hour.\n")
        .. (ns.GOLD .. "Overview|r  how many of each class, level and profession, and a heatmap of when the guild plays.\n")
        .. (ns.GOLD .. "Hall of Fame|r  guild leaderboards from everyone's statistics: quests, kills, bosses, deaths and more (with NGM Peon, the whole guild's).\n")
        .. (ns.GOLD .. "Who Can Craft?|r  every recipe your guildmates know, searchable, with online crafters first.\n")
        .. (ns.GOLD .. "Profiles|r  specs, roles, professions, Discord, usual play hours, raid readiness and your private notes.\n")
        .. (ns.GOLD .. "Upcoming Events|r  the guild's dungeons, raids and nights, made in game or on NGM Peon: when, who's coming, and sign-ups right here.\n")
        .. (ns.GOLD .. "Recruitment|r  friendly whispers to players without a guild, a guild-wide 14-day lockout and a shared Do Not Whisper list.\n")
        .. (ns.GOLD .. "For officers|r  an audit of every change (joins, leaves, promotions, level-ups), an officer log, and Guild Master permissions."))
    L:Text("Everything is shared with guildmates running the NGM Addon, so the more of the guild uses it, the more it knows. NGM Peon (optional) carries it to your guild's Discord and back, and NGM Desktop (optional) does that by itself.", "NGMFontDimSmall")

    L:Header("What's Shared")
    L:Text((ns.GOLD .. "With guildmates running the NGM Addon|r  your characters' spec and roles, professions and recipes, raid readiness, when you usually play, your Discord name if you set one, your NGM Addon version, your Hall of Fame statistics (never gold, and never what anyone writes), events you create and your sign-ups, and, if you recruit, who you whispered and the Do Not Whisper list. The guild's ban list (reasons only to ranks the Guild Master allows), its shared messages, and the Guild Master's permissions. With NGM Peon, also whether each character is linked to it and has connected WoW to Discord (for Get Connected).\n")
        .. (ns.GOLD .. "Officers only|r  the officer log, the audit, join dates and rank history.\n")
        .. (ns.GOLD .. "Never leaves your computer|r  your private notes.\n")
        .. (ns.GOLD .. "With NGM Peon|r  only if your guild uses it, and only what a code carries: the Guild Master's or an officer's (mains and alts, roles, when the guild plays, join dates, the game's resets and holidays, events made in game and sign-ups), or a member's own through NGM Desktop (their own characters' mains, roles, events and sign-ups). Each code also says how far the game has NGM Peon's news."))

    L:Header("Links")
    L:Text("Click the link, press |cffffffffCtrl+C|r, and paste it into your browser.", "NGMFontDimSmall", 4)
    for _, link in ipairs(D.LINKS) do LinkRow(L, link) end

    L:Header("Credits")
    L:Text(("Maintained by " .. ns.GOLD .. "Keasbeexd|r for " .. ns.GOLD .. "<Nootropic>|r.\n")
        .. "Built on the original Nootropic Guild Manager by " .. ns.GOLD .. "aigoodandy|r, with permission.")
    L:Text("Not affiliated with Blizzard Entertainment or Discord.", "NGMFontDimSmall")
    L:Finish()
    return outer
end

function O:Build()
    self:BuildMain()
    self.subPages = {
        { key = "recruiting", frame = self:BuildRecruiting() },
        { key = "permissions", frame = self:BuildPermissions() },
        { key = "officers", frame = self:BuildOfficers() },
        { key = "about", frame = self:BuildAbout() },
    }
    ns:On("SETTINGS_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("BRAND_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("GUILD_SETTINGS_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("GUILD_RULES_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("OFFICER_CHANGED", function() if O:AnyShown() then O:Refresh() end end)
    ns:On("RECRUITS_CHANGED", function()
        if O.pages.recruiting and O.pages.recruiting:IsShown() then O:RefreshRecruiting() end
    end)
end

function O:AnyShown()
    for _, page in pairs(self.pages) do if page:IsShown() then return true end end
    return false
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function SetUsable(widget, on)
    widget:SetEnabled(on)
    widget:SetAlpha(on and 1 or 0.45)
end

function O:Refresh()
    local s = ns.DB:Settings()
    for _, logo in ipairs(self.logos or {}) do logo:Apply() end

    -- main
    self.addonCountCheck:SetChecked(s.showAddonCount ~= false)
    self.eventNoticesCheck:SetChecked(s.eventNotices ~= false)
    self.levelUpsCheck:SetChecked(s.levelUps ~= false)
    for _, pick in ipairs({ { self.eventSoundPicker, s.eventNotices ~= false }, { self.levelUpSoundPicker, s.levelUps ~= false } }) do
        pick[1]:SetText(ns.GuildFeed:SoundName(ns.GuildFeed:SoundKey(pick[1].feed)))
        SetUsable(pick[1], pick[2]) -- no line, no sound
    end
    if self.connectButton then self.connectButton:SetShown(ns.Sync.PeonGuild and ns.Sync:PeonGuild() or false) end
    self.communitiesCheck:SetChecked(s.communitiesButton ~= false)
    self.blizzRosterCheck:SetChecked(s.blizzRoster ~= false)
    self.learnCheck:SetChecked(ns.Profile:LearnEnabled())
    self.shareRecipesCheck:SetChecked(ns.Sharing:Get("recipes"))
    if not self.reminderBox:HasFocus() then self.reminderBox:SetText(ns.InstallReminder:Text()) end
    local IR = ns.InstallReminder
    local guildText, locked, using = IR:GuildText(), IR:Locked(), IR:UsingGuild()
    self.reminderGuild:SetText(not guildText and "The guild has no shared text yet."
        or locked and "Using the guild's text: the Guild Master set it for everyone."
        or using and "Using the guild's text. You can use your own instead."
        or "Using your own text, not the guild's.")
    self.reminderSwitch:SetShown(guildText ~= nil and not locked)
    self.reminderSwitch:SetText(using and "Use My Own" or "Use the Guild's")
    self.reminderShare:SetShown(ns.DB:HasPerm("imsg"))
    self.minimapCheck:SetChecked(not s.minimap.hide)
    for _, b in ipairs(self.clickPickers) do b:SetText(D:MinimapActionLabel(s.minimap[b.key])) end
    self.syncStatus:SetText((ns.GOLD .. "Sync:|r ") .. select(2, ns.Sync:Health()))

    self:RefreshRecruiting()

    -- officers
    local officer = ns.IsOfficer()
    -- only what your rank can use: the page explains instead of showing locked settings
    self:ShowFor("officers", officer or ns.DB:IsGuildMaster(),
        "Only officers use this page: who may do what (the Guild Master's permissions) and how long the Audit keeps history.")
    self.officerNote:SetShown(not officer)
    self:RefreshPermControls()
    for _, rb in ipairs(self.auditRadios) do
        rb:SetChecked((s.auditDays or 30) == rb.days)
        SetUsable(rb, officer)
    end
end

-- Shows a page's settings, or only a line saying who uses it.
function O:ShowFor(key, may, why)
    local page = self.pages[key]
    if not (page and page.Body) then return end
    page.Body:SetShown(may and true or false)
    page.Locked:SetText(why)
    page.Locked:SetShown(not may)
end

function O:RefreshRecruiting()
    self:ShowFor("recruiting", ns.Recruit:MayRecruit(), IsInGuild() and
        "Your rank can't recruit. Ranks the Guild Master gives Invite Member (in the game's Guild Control) set up recruiting here and on the Recruitment tab."
        or "Join a guild to set up recruiting.")
    local s = ns.DB:Settings()
    self.whoWhisperCheck:SetChecked(s.whoWhisperButton ~= false)
    self.hourButton:SetText(self.hourButton.HourText(s.whisperPerHour or 40))
    local r = ns.Recruit:Settings()
    self.recruitNoGuild:SetShown(r == nil)
    for _, w in ipairs({ self.autoCheck, self.dnwCheck, self.dnwView }) do SetUsable(w, r ~= nil) end
    for _, eb in ipairs(self.keywordBoxes) do eb:SetEnabled(r ~= nil) end
    for _, eb in ipairs(self.dnwBoxes) do eb:SetEnabled(r ~= nil) end
    if not r then
        self.dnwCount:SetText("")
        return
    end
    self.autoCheck:SetChecked(r.autoInvite)
    self.dnwCheck:SetChecked(r.dnwEnabled)
    for i, eb in ipairs(self.keywordBoxes) do
        if not eb:HasFocus() then eb:SetText(r.keywords[i] or "") end
    end
    for i, eb in ipairs(self.dnwBoxes) do
        if not eb:HasFocus() then eb:SetText(r.dnwWords[i] or "") end
    end
    local n = #ns.Recruit:DNWList()
    self.dnwCount:SetText(n == 1 and "1 person on the list" or (n .. " people on the list"))
end

------------------------------------------------------------------------
-- Registration with the game's options window
------------------------------------------------------------------------
function O:Init()
    self:Build()
    local main = self.panel
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(main, PANEL_NAME)
        self.category = category
        if Settings.RegisterCanvasLayoutSubcategory then
            for _, p in ipairs(self.subPages) do
                self.subcats[p.key] = Settings.RegisterCanvasLayoutSubcategory(category, p.frame, p.frame.name)
            end
        end
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(main)
        for _, p in ipairs(self.subPages) do
            p.frame.parent = PANEL_NAME
            InterfaceOptions_AddCategory(p.frame)
        end
    end
end

-- key: nil for the main page, or "recruiting", "officers".
function O:Open(key)
    if not self.panel then return end
    -- the game blocks opening its settings panel in combat (and logs taint)
    if InCombatLockdown and InCombatLockdown() then
        ns:Print("Options can't open during combat. Try again once you're out of combat.")
        return
    end
    if Settings and Settings.OpenToCategory and self.category then
        local cat = key and self.subcats[key] or self.category
        local id = cat.GetID and cat:GetID() or cat.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        local frame = key and self.pages[key] or self.panel
        -- Called twice: the first call only opens the frame on some clients.
        InterfaceOptionsFrame_OpenToCategory(frame)
        InterfaceOptionsFrame_OpenToCategory(frame)
    end
end
