--[[
    Nootropic Guild Manager - the game's Guild & Communities roster
    Adds this addon's data to Blizzard's own guild roster instead of
    replacing it:

      Tooltip   the addon's member lines (main or alt, spec, role, main
                professions, Discord, addon version)
      Menu      right-click a member: Profile, Main / Alt
      Alt+click a member opens their profile docked beside the window

    Only additive, taint-safe hooks are used: HookScript on the rows, hooksecurefunc on the rows' SetMember
    (Blizzard's way to run after their code without tainting it), and the
    official Menu.ModifyMenu. We never register callbacks inside Blizzard's
    member list: doing that from addon code left its row data tainted, and
    the rank dropdown (a protected action) reads that data, which got rank
    changes blocked now and then. Blizzard's frames, sorting and protected
    actions (invite, promote, remove) are left untouched.
    Off switch: Options > "Show alts and profiles on the Guild roster".
]]
local _, ns = ...
local GR = {}
ns.GuildRoster = GR

local decorated = setmetatable({}, { __mode = "k" }) -- rows we've added to

function GR:Enabled()
    return ns.DB:Settings().blizzRoster ~= false
end

function GR:SetEnabled(on)
    ns.DB:Settings().blizzRoster = on and true or false
    ns:Fire("SETTINGS_CHANGED")
end

------------------------------------------------------------------------
-- Which member a Blizzard row (or menu) is about
------------------------------------------------------------------------
local function IsGuildView()
    local cf = CommunitiesFrame
    if not (cf and C_Club and C_Club.GetGuildClubId) then return false end
    local guildId = C_Club.GetGuildClubId()
    local sel = cf.GetSelectedClubId and cf:GetSelectedClubId()
    return guildId ~= nil and sel == guildId
end

-- Our roster entry for a club member info table ({ guid, name, ... }).
local function EntryFor(info)
    if type(info) ~= "table" then return nil end
    local R = ns.Roster
    if info.guid and R.byGuid and R.byGuid[info.guid] then return R.byGuid[info.guid] end
    local name = info.name or info.fullName
    if name and name ~= "" then return R.byName[ns.NormalizeName(name)] end
end

local function RowEntry(row)
    local info = row.GetMemberInfo and row:GetMemberInfo()
    return EntryFor(info)
end

local function EntryForName(name)
    if not name or name == "" then return nil end
    return ns.Roster.byName[ns.NormalizeName(name)]
end

------------------------------------------------------------------------
-- Opening our profile beside the Guild & Communities window
------------------------------------------------------------------------
function GR:OpenProfile(e)
    if not e then return end
    local host = CommunitiesFrame
    if not (host and host:IsShown()) then host = nil end
    ns.DetailPanel:Show(e.full, host)
end

-- Our lines under Blizzard's own (HookScript runs after theirs): the same
-- member lines as every other tooltip in the addon.
function GR:AddTooltip(e)
    if not (e and GameTooltip:IsShown()) then return end
    GameTooltip:AddLine(" ")
    ns.RosterView:AddMemberLines(e)
    GameTooltip:AddLine("Alt+click or right-click for the profile.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function HookRow(row)
    if decorated[row] then return end
    decorated[row] = true
    row:HookScript("OnEnter", function(self)
        if not (GR:Enabled() and IsGuildView()) then return end
        if GameTooltip:GetOwner() ~= self then return end
        GR:AddTooltip(RowEntry(self))
    end)
    row:HookScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and IsAltKeyDown() and GR:Enabled() and IsGuildView() then
            GR:OpenProfile(RowEntry(self))
        end
    end)
end

local function ScrollBox()
    local list = CommunitiesFrame and CommunitiesFrame.MemberList
    return list and list.ScrollBox
end

------------------------------------------------------------------------
-- Right-click menu (Menu.ModifyMenu, the official way to add entries)
------------------------------------------------------------------------
local MENU_TAGS = {
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_MEMBER",
    "MENU_UNIT_GUILD",
}

local function MenuEntry(owner, contextData)
    local cd = contextData or {}
    local e = EntryFor(cd.clubMemberInfo) or EntryForName(cd.name)
    if not e and owner and owner.GetMemberInfo then e = EntryFor(owner:GetMemberInfo()) end
    return e
end

function GR:AddMenu(owner, root, contextData)
    if not self:Enabled() then return end
    local e = MenuEntry(owner, contextData)
    if not e then return end
    local full = e.full
    root:CreateDivider()
    root:CreateTitle("Nootropic Guild Manager")
    root:CreateButton("Profile", function() GR:OpenProfile(ns.Roster.byName[full]) end)
    local remind = ns.InstallReminder:MenuItem(e)
    if remind then
        local b = root:CreateButton(remind.text, remind.func)
        if remind.disabled and b.SetEnabled then b:SetEnabled(false) end
    end
    if ns.DB:CanEditLinks() then
        local sub = root:CreateButton("Main / Alt")
        local cur = ns.Roster.byName[full]
        if cur and cur.isAlt then
            sub:CreateButton("Change main...", function() GR:OpenProfile(cur); ns.DetailPanel:PickMainFor(full) end)
            sub:CreateButton("Make " .. cur.short .. " the main", function() ns.DB:MakeMain(full) end)
            sub:CreateButton("Unlink from " .. (cur.mainShort or "main"), function() ns.DB:ClearMain(full) end)
        else
            sub:CreateButton("Mark as alt of...", function() GR:OpenProfile(cur); ns.DetailPanel:PickMainFor(full) end)
            sub:CreateButton("Add an alt...", function() GR:OpenProfile(cur); ns.DetailPanel:PickAltFor(full) end)
        end
    end
end

------------------------------------------------------------------------
-- Hooking the window when it loads
------------------------------------------------------------------------
function GR:Attach()
    if self.attached then return end
    local sb = ScrollBox()
    if not sb then return end
    self.attached = true
    -- Rows are filled by Blizzard's SetMember: run after it, securely.
    -- Hooking the mixin covers rows created from now on; rows that already
    -- exist get the same hook on themselves.
    local function after(row) HookRow(row) end
    if hooksecurefunc and CommunitiesMemberListEntryMixin and CommunitiesMemberListEntryMixin.SetMember then
        hooksecurefunc(CommunitiesMemberListEntryMixin, "SetMember", after)
    end
    local function hookExisting()
        if not sb.ForEachFrame then return end
        sb:ForEachFrame(function(row)
            if not decorated[row] and row.SetMember then hooksecurefunc(row, "SetMember", after) end
            HookRow(row)
        end)
    end
    hookExisting()
    local list = CommunitiesFrame.MemberList
    if list and list.RefreshListDisplay then
        hooksecurefunc(list, "RefreshListDisplay", hookExisting)
    end
end

function GR:Diagnose()
    local sb = ScrollBox()
    local rows, named = 0, 0
    if sb and sb.ForEachFrame then
        sb:ForEachFrame(function(row)
            rows = rows + 1
            if RowEntry(row) then named = named + 1 end
        end)
    end
    ns:Print(("Guild roster: hooked=%s, guild view=%s, rows=%d, matched=%d, menus=%s"):format(
        tostring(self.attached or false), tostring(IsGuildView()), rows, named,
        tostring(self.menus or false)))
end

function GR:Init()
    if Menu and Menu.ModifyMenu then
        for _, tag in ipairs(MENU_TAGS) do
            pcall(Menu.ModifyMenu, tag, function(owner, root, contextData) GR:AddMenu(owner, root, contextData) end)
        end
        self.menus = true
    end
    ns:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_Communities" then GR:Attach() end
    end)
    if hooksecurefunc and _G.ToggleCommunitiesFrame then
        hooksecurefunc("ToggleCommunitiesFrame", function() GR:Attach() end)
    end
    self:Attach()
end
