--[[
    Nootropic Guild Manager - /ngm bug
    A report players can copy into a bug report, without knowing what a
    taint log is:

      Blocked   when the game blocks the NGM Addon from a protected action
                (ADDON_ACTION_BLOCKED / _FORBIDDEN: it names the function,
                e.g. "C_GuildInfo.SetNote()"), it's noted with the time,
                whether in combat, and the Blizzard windows open. Chat says
                so once a session, pointing at /ngm bug.
      Errors    the NGM Addon's own script errors (ns.Safe).
      Report    /ngm bug: version, game build, locale, which of the NGM
                Addon's options are on, other addons loaded, and the recent
                blocks and errors, in a box to copy.

    Kept on this computer only (Settings().bugLog, the newest 15, for 14
    days), never sent anywhere. No names of guildmates, guild or character.
    /ngm bug log tries to turn on the game's own taint log for more detail
    (the game may not let addons: then it says how).
]]
local _, ns = ...
local B = {}
ns.BugReport = B

local KEEP, MAX = 14 * 86400, 15
local ADDON = "NootropicGuildManager"

local function Log()
    local st = ns.DB:Settings()
    st.bugLog = st.bugLog or {}
    local now = time()
    for i = #st.bugLog, 1, -1 do
        if (st.bugLog[i].t or 0) < now - KEEP then table.remove(st.bugLog, i) end
    end
    return st.bugLog
end

-- The Blizzard windows open right now (where it happened)
local function OpenWindows()
    local out = {}
    for _, name in ipairs({ "CommunitiesFrame", "GuildFrame", "FriendsFrame", "CharacterFrame", "SettingsPanel", "StaticPopup1", "GameMenuFrame" }) do
        local f = rawget(_G, name)
        if type(f) == "table" and f.IsShown and f:IsShown() then out[#out + 1] = name end
    end
    return table.concat(out, ", ")
end

-- kind: "blocked", "forbidden" or "error"
function B:Note(kind, what)
    local log = Log()
    what = tostring(what or ""):gsub("[\r\n]+", " | "):sub(1, 300)
    -- the same thing again: counted, not listed twice
    for _, e in ipairs(log) do
        if e.kind == kind and e.what == what then
            e.n, e.t = (e.n or 1) + 1, time()
            return
        end
    end
    table.insert(log, 1, { t = time(), kind = kind, what = what, version = ns.version,
        combat = InCombatLockdown and InCombatLockdown() or false, windows = OpenWindows() })
    while #log > MAX do table.remove(log) end
end

function B:Init()
    local told = false
    local function Blocked(kind)
        return function(_, addon, fn)
            if addon ~= ADDON then return end
            -- what the NGM Addon was handling at that moment (this frame only:
            -- an error part-way can leave an old name behind)
            local d = ns.doing
            local during = d and GetTime and d.at == GetTime() and d.name or nil
            B:Note(kind, tostring(fn or "?") .. (during and (" during " .. during) or ""))
            if not told then
                told = true
                ns:Print(("The game blocked the NGM Addon (%s). Type |cffffffff/ngm bug|r for a report to send us: it says what happened, nothing personal."):format(tostring(fn or "?")))
            end
        end
    end
    ns:RegisterEvent("ADDON_ACTION_BLOCKED", Blocked("blocked"))
    ns:RegisterEvent("ADDON_ACTION_FORBIDDEN", Blocked("forbidden"))
end

local function YesNo(v) return v and "yes" or "no" end

function B:Text()
    local st = ns.DB:Settings()
    local version, build, _, interface = GetBuildInfo()
    local lines = {
        "NGM Addon bug report",
        ("NGM Addon %s, game %s (%s, interface %s), %s"):format(ns.version or "?", tostring(version), tostring(build), tostring(interface), GetLocale and GetLocale() or "?"),
        ("Guild uses NGM Peon: %s. NGM Desktop: %s. Officer: %s. Controller style: %s."):format(
            YesNo(ns.Sync.PeonGuild and ns.Sync:PeonGuild()), YesNo(ns.DiscordCode and ns.DiscordCode:DesktopInstalled()),
            YesNo(ns.IsOfficer and ns.IsOfficer()), YesNo(ns.Gamepad and ns.Gamepad:Active())),
        ("Options: guild roster extras %s, Guild & Communities shortcut %s, minimap button %s, recruit /who button %s."):format(
            YesNo(st.blizzRoster ~= false), YesNo(st.communitiesButton ~= false), YesNo(not (st.minimap and st.minimap.hide)), YesNo(st.whoWhisperButton ~= false)),
    }
    local cvar = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("taintLog")
    if cvar and cvar ~= "0" then lines[#lines + 1] = "The game's taint log is on: Logs/taint.log in the game folder has more." end
    -- other addons running (their names only)
    local others = {}
    local A = C_AddOns
    if A and A.GetNumAddOns then
        for i = 1, A.GetNumAddOns() do
            local name = A.GetAddOnInfo(i)
            if name and name ~= ADDON and A.IsAddOnLoaded(i) then others[#others + 1] = name end
        end
    end
    lines[#lines + 1] = "Other addons: " .. (#others > 0 and table.concat(others, ", ") or "none")
    lines[#lines + 1] = ""
    local log = Log()
    if #log == 0 then
        lines[#lines + 1] = "Nothing recorded yet. If something goes wrong, do it again, then type /ngm bug."
    else
        lines[#lines + 1] = "What happened, newest first:"
        for _, e in ipairs(log) do
            lines[#lines + 1] = ("%s  %s  %s%s%s (NGM Addon %s)%s"):format(date("%Y-%m-%d %H:%M", e.t), e.kind, e.what,
                (e.n or 1) > 1 and (" x" .. e.n) or "", e.combat and ", in combat" or "", e.version or "?",
                (e.windows and e.windows ~= "") and (", open: " .. e.windows) or "")
        end
    end
    return table.concat(lines, "\n")
end

-- The window: the report, selected, to copy
function B:Open()
    if InCombatLockdown and InCombatLockdown() then ns:Print("Not in combat. Type /ngm bug after the fight.") return end
    local W = ns.Widgets
    if not self.frame then
        local f = CreateFrame("Frame", "NootropicGMBugReport", UIParent, "BasicFrameTemplateWithInset")
        ns.Theme:Skin(f)
        W.CombatSafeClose(f)
        f:SetSize(560, 400)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "NootropicGMBugReport")
        ns.Gamepad:Register(f, "popup")
        W.SetTitle(f, "Bug Report")
        local how = f:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
        how:SetPoint("TOPLEFT", 16, -32)
        how:SetPoint("TOPRIGHT", -16, -32)
        how:SetJustifyH("LEFT")
        how:SetText("Press |cffffffffCtrl+C|r to copy it, then paste it in a bug report: ngmpeon.app, Report a bug (or Options, About, Bugs and ideas). It holds nothing personal: no names of characters or guildmates.")
        local scroll, box = W.ScrollEditor(f, 0)
        scroll:SetPoint("TOPLEFT", 16, -70)
        scroll:SetPoint("BOTTOMRIGHT", -34, 16)
        box:SetScript("OnTextChanged", function(eb, user) if user then eb:SetText(B.text or "") eb:HighlightText() end end) -- read only
        self.frame, self.box = f, box
    end
    self.text = self:Text()
    self.box:SetText(self.text)
    self.frame:Show()
    self.box:SetFocus()
    self.box:HighlightText()
end

-- /ngm bug log: the game's own taint log, if it lets addons turn it on
function B:TaintLog()
    local ok = C_CVar and C_CVar.SetCVar and pcall(C_CVar.SetCVar, "taintLog", "1")
    if ok and C_CVar.GetCVar("taintLog") == "1" then
        ns:Print("The game's detailed log is on. Do what went wrong again, then /reload: Logs/taint.log in the game folder has the detail. /ngm bug says it's on.")
    else
        ns:Print("The game doesn't let addons turn its detailed log on. Type |cffffffff/console taintLog 1|r yourself if you're asked for it; /ngm bug alone is usually enough.")
    end
end
