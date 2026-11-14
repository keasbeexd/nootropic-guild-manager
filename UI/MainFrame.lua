--[[
    Nootropic Guild Manager - Main window
    Blizzard portrait frame with icon tabs down the right side (Find,
    Play Together, Overview, Hall of Fame, Recruitment, Audit),
    a status line, and the member detail flyout.
]]
local _, ns = ...
local W = ns.Widgets
local UI = {}
ns.UI = UI

local FRAME_W, FRAME_H = 1000, 580
local MIN_W, MIN_H, MAX_W, MAX_H = 640, 520, 1800, 1100
local TAB_LABELS = { "Find", "Play Together", "Recruitment", "Audit", "Overview", "Hall of Fame" }
UI.TAB_ROSTER, UI.TAB_TOGETHER, UI.TAB_RECRUIT, UI.TAB_AUDIT, UI.TAB_OVERVIEW, UI.TAB_HOF = 1, 2, 3, 4, 5, 6
-- the order the tabs run down the window (ids stay stable for saved settings)
local TAB_ORDER = { 1, 2, 5, 6, 3, 4 }
local OFFICER_TABS = { [4] = true } -- Audit

------------------------------------------------------------------------
-- Creation
------------------------------------------------------------------------
function UI:Create()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "NootropicGMFrame", UIParent, "ButtonFrameTemplate")

    ns.Theme:Skin(f)

    W.CombatSafeClose(f)
    self.frame = f
    local size = ns.DB:Settings().frameSize or {}
    f:SetSize(math.max(MIN_W, math.min(MAX_W, size.w or FRAME_W)), math.max(MIN_H, math.min(MAX_H, size.h or FRAME_H)))
    f:SetToplevel(true)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI:SavePosition()
    end)
    f:Hide()
    tinsert(UISpecialFrames, f:GetName())

    self:UpdateTitle()
    self:BuildPortrait(f)
    self:RestorePosition()

    -- Status line along the bottom edge
    self.status = f:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    self.status:SetPoint("BOTTOMLEFT", 14, 8)
    self:BuildAddonCount(f)
    self.version = f:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    self.version:SetPoint("BOTTOMRIGHT", -14, 8)
    self.version:SetText("v" .. ns.version)
    self:BuildSyncDot(f)

    ns.RosterView.LIST_WIDTH = math.floor(f:GetWidth() - ns.RosterView.LIST_INSET)
    ns.RosterView:Build(f)
    ns.TogetherView:Build(f)
    ns.RecruitView:Build(f)
    ns.AuditView:Build(f)
    ns.OverviewView:Build(f)
    ns.HallOfFameView:Build(f)
    ns.DetailPanel:Build()
    self:BuildTabs(f)
    self:BuildResizeGrip(f)

    f:SetScript("OnShow", ns.Safe(function()
        ns.PlaySound("IG_CHARACTER_INFO_OPEN")
        ns.CheckOfficer()
        UI:LayoutTabs()
        ns.Roster:Request()
        UI:RefreshStatus()
        ns.RosterView:Refresh()
    end, "opening the window"))
    f:SetScript("OnHide", ns.Safe(function()
        ns.PlaySound("IG_CHARACTER_INFO_CLOSE")
    end, "closing the window"))
    ns:On("OFFICER_CHANGED", function()
        UI:LayoutTabs()
        if f:IsShown() then ns.RosterView:Relayout(); ns.RosterView:Refresh() end
    end)

    ns:On("ROSTER_UPDATED", function()
        UI:UpdateTitle() -- the guild name may have just arrived
        if f:IsShown() then
            UI:RefreshStatus()
            UI:LayoutTabs() -- your rank may have changed
        end
    end)
    ns:On("SETTINGS_CHANGED", function()
        UI:UpdateTitle()
        UI:RefreshStatus()
    end)
    ns:On("GUILD_SETTINGS_CHANGED", function() UI:LayoutTabs() end)

    self:SelectTab(1)
    return f
end

-- The portrait shows the addon icon (mug, stein or guild emblem).
function UI:BuildPortrait(f)
    self.portrait = ns.Brand:AttachPortrait(f)
end

function UI:BuildResizeGrip(f)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else
        if f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
        if f.SetMaxResize then f:SetMaxResize(MAX_W, MAX_H) end
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    -- pixel steps in the corner, as a resize mark
    for _, at in ipairs({ { 12, 0 }, { 8, 0 }, { 4, 0 }, { 12, 4 }, { 8, 4 }, { 12, 8 } }) do
        local px = grip:CreateTexture(nil, "ARTWORK")
        px:SetSize(2, 2)
        px:SetPoint("BOTTOMLEFT", at[1], at[2])
        local c = ns.Theme.C.faint
        ns.Theme:Paint(px, c)
    end
    local hl = grip:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        UI:SavePosition()
        UI:SaveSize()
    end)
    W.Tooltip(grip, "Drag to resize")
    self.resizeGrip = grip

    self.version:ClearAllPoints()
    self.version:SetPoint("BOTTOMRIGHT", -22, 8)

    f:SetScript("OnSizeChanged", function(self, w)
        ns.RosterView:SetListWidth((w or self:GetWidth()) - ns.RosterView.LIST_INSET)
        ns.RecruitView:OnResize()
        ns.AuditView:OnResize()
    end)
end

function UI:SaveSize()
    local f = self.frame
    ns.DB:Settings().frameSize = { w = math.floor(f:GetWidth()), h = math.floor(f:GetHeight()) }
end

------------------------------------------------------------------------
-- Tabs: icon tiles down the right side of the window, as the dashboard's
-- tabs (see CreateSideTab). Hover one for its title.
------------------------------------------------------------------------
local TAB_SIZE, TAB_GAP = 40, 12
UI.TAB_OUTSIDE = 62 -- how far the tabs reach past the window's right edge

-- An icon file if this client has it, else the fallback.
local function IconIfPresent(path, fallback)
    if GetFileIDFromPath then
        local ok, id = pcall(GetFileIDFromPath, path)
        if ok and id then return path end
        if ok then return fallback end
    end
    return path
end

-- Each tab's icon.
UI.DEFAULT_TAB_ICONS = {
    -- a group of people, as on the Guild & Communities window's roster tab
    IconIfPresent("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend", "Interface\\Icons\\Spell_Holy_PrayerOfFortitude"), -- Roster
    "Interface\\Icons\\Ability_Mount_RidingHorse",    -- Play Together
    "Interface\\Icons\\Ability_Warrior_BattleShout",  -- Recruitment
    "Interface\\Icons\\INV_Misc_Spyglass_02",         -- Audit
    IconIfPresent("Interface\\Icons\\INV_Misc_Map_01", "Interface\\Icons\\INV_Misc_Book_09"), -- Overview
    IconIfPresent("Interface\\Icons\\INV_Misc_Trophy_Argent", "Interface\\Icons\\INV_Misc_Gem_Pearl_04"), -- Hall of Fame
}

-- The tabs always run down the window's right side.
function UI:TabSide()
    return "right"
end

local function CreateSideTab(f, i)
    -- as the dashboard's tabs: a dark tile with a notched edge; the open one
    -- yellow-edged with a hard red shadow; hovered, the edge lights up
    local T = ns.Theme
    local tab = CreateFrame("CheckButton", "NootropicGMFrameTab" .. i, f)
    tab._ngmTab, tab._ngmSkinned = true, true
    tab:SetSize(TAB_SIZE, TAB_SIZE)
    tab.Shadow = tab:CreateTexture(nil, "BACKGROUND", nil, -8)
    T:Paint(tab.Shadow, T.C.shade)
    tab.Shadow:SetPoint("TOPLEFT", 5, -6)
    tab.Shadow:SetPoint("BOTTOMRIGHT", 5, -6)
    tab.Shadow:Hide()
    tab.Bg = tab:CreateTexture(nil, "BACKGROUND", nil, -6)
    tab.Bg:SetAllPoints()
    T:Paint(tab.Bg, T.C.bg1)
    tab.Edge = T:Edge(tab, tab, 3, T.C.edge, "BACKGROUND", -5)
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Icon:SetPoint("TOPLEFT", 4, -4)
    tab.Icon:SetPoint("BOTTOMRIGHT", -4, 4)
    tab.iconCoords = { 0.08, 0.92, 0.08, 0.92 }
    tab.gap = TAB_GAP
    tab:SetID(i)
    local function Paint(self)
        -- the open tab: the guild's accent, as the buttons
        local c = self.selected and T.A.face or self.hover and T.C.fg or T.C.edge
        self.Edge:SetColor(c)
        T:Paint(self.Shadow, T.A.shade)
        self.Shadow:SetShown(self.selected and true or false)
        self.Icon:SetDesaturated(not self.selected and not self.hover)
        self.Icon:SetAlpha((self.selected or self.hover) and 1 or 0.75)
    end
    function tab:SetSelected(on) self.selected = on and true or false; Paint(self) end
    -- the tile is the same on any side
    function tab:SetSide(side) self.side = side end
    tab:HookScript("OnEnter", function(self) self.hover = true; Paint(self) end)
    tab:HookScript("OnLeave", function(self) self.hover = false; Paint(self) end)
    Paint(tab)
    T:OnAccent(function() Paint(tab) end)
    tab:SetScript("OnClick", function(self)
        UI:SelectTab(self:GetID())
        ns.PlaySound("IG_CHARACTER_INFO_TAB")
    end)
    tab:SetScript("OnEnter", function(self)
        local id = self:GetID()
        GameTooltip:SetOwner(self, self.side == "left" and "ANCHOR_LEFT" or self.side == "bottom" and "ANCHOR_BOTTOM" or "ANCHOR_RIGHT")
        GameTooltip:AddLine(UI:TabTitle(id) .. (OFFICER_TABS[id] and " |cffa89984(officers only)|r" or ""))
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tab
end

function UI:BuildTabs(f)
    f.Tabs = {}
    for i in ipairs(TAB_LABELS) do f.Tabs[i] = CreateSideTab(f, i) end
    self:LayoutTabs()
end

function UI:TabIcon(id)
    return self.DEFAULT_TAB_ICONS[id]
end

function UI:IsTabAvailable(id)
    if id == UI.TAB_RECRUIT then return ns.DB:HasPerm("recruit") end
    return not OFFICER_TABS[id] or ns.IsOfficer()
end

function UI:TabTitle(id)
    return TAB_LABELS[id]
end

-- Shows only the tabs this player may use: down the chosen side, or along
-- the bottom (left to right).
function UI:LayoutTabs()
    local f = self.frame
    if not (f and f.Tabs) then return end
    local side = self:TabSide()
    local left, bottom = side == "left", side == "bottom"
    -- keep the tabs on screen when the window is dragged to that edge
    if f.SetClampRectInsets then
        if bottom then
            f:SetClampRectInsets(0, 0, 0, -UI.TAB_OUTSIDE)
        elseif left then
            f:SetClampRectInsets(-UI.TAB_OUTSIDE, 0, 0, 0)
        else
            f:SetClampRectInsets(0, UI.TAB_OUTSIDE, 0, 0)
        end
    end
    local prev
    for _, i in ipairs(TAB_ORDER) do
        local tab = f.Tabs[i]
        tab:SetSide(side)
        W.SetIcon(tab.Icon, self:TabIcon(i))
        if tab.iconCoords then tab.Icon:SetTexCoord(unpack(tab.iconCoords)) end
        tab:ClearAllPoints()
        if self:IsTabAvailable(i) then
            if prev then
                if bottom then
                    -- turned, the art is a little wider than the tab
                    tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", tab.gap + 5, 0)
                elseif left then
                    tab:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -tab.gap)
                else
                    tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -tab.gap)
                end
            elseif bottom then
                -- under the window, starting near its left corner
                tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 24, 2)
            elseif left then
                -- below the round portrait in the top-left corner
                tab:SetPoint("TOPRIGHT", f, "TOPLEFT", 2, -72)
            else
                tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 12, -48)
            end
            tab:SetSelected(i == self.tab)
            tab:Show()
            prev = tab
        else
            tab:Hide()
        end
    end
    if self.tab and not self:IsTabAvailable(self.tab) then self:SelectTab(UI.TAB_ROSTER) end
    self:UpdateTitle()
end

function UI:SelectTab(id)
    local f = self.frame
    if not self:IsTabAvailable(id) then id = UI.TAB_ROSTER end
    self.tab = id
    for i, tab in ipairs(f.Tabs or {}) do tab:SetSelected(i == id) end
    self:UpdateTitle()

    -- Roster and Recruitment need room above the inset for a second toolbar row.
    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("TOPLEFT", 4, (id == UI.TAB_ROSTER or id == UI.TAB_RECRUIT) and -86 or -64)
    f.Inset:SetPoint("BOTTOMRIGHT", -6, 26)

    ns.RosterView.page:SetShown(id == UI.TAB_ROSTER)
    ns.TogetherView.page:SetShown(id == UI.TAB_TOGETHER)
    ns.RecruitView.page:SetShown(id == UI.TAB_RECRUIT)
    ns.AuditView.page:SetShown(id == UI.TAB_AUDIT)
    ns.OverviewView.page:SetShown(id == UI.TAB_OVERVIEW)
    ns.HallOfFameView.page:SetShown(id == UI.TAB_HOF)
    if id ~= UI.TAB_ROSTER and ns.DetailPanel.host == f then ns.DetailPanel:Hide() end
end

------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------
function UI:Title() return "Nootropic Guild Manager" end

-- The window title, with the open tab's name ("Nootropic Guild Manager - Insights").
function UI:UpdateTitle()
    if not self.frame then return end
    local title = self:Title()
    if self.tab and self.frame.Tabs then title = title .. "  |cffebdbb2-  " .. self:TabTitle(self.tab) .. "|r" end
    W.SetTitle(self.frame, title)
end

-- "x using <title>" after the status line. Click: roster of addon users with versions.
function UI:BuildAddonCount(f)
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(16)
    b:SetPoint("LEFT", self.status, "RIGHT", 0, 0)
    b.Text = b:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    b.Text:SetPoint("LEFT", 0, 0)
    b.Underline = b:CreateTexture(nil, "OVERLAY")
    b.Underline:SetHeight(1)
    ns.Theme:Paint(b.Underline, ns.Theme.C.yellow, 0.8)
    b.Underline:Hide()
    b:SetScript("OnEnter", function(self)
        self.Underline:ClearAllPoints()
        self.Underline:SetPoint("TOPLEFT", self.Text, "BOTTOMLEFT", self.dashWidth or 0, -1)
        self.Underline:SetPoint("TOPRIGHT", self.Text, "BOTTOMRIGHT", 0, -1)
        self.Underline:Show()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Who uses the addon?")
        GameTooltip:AddLine("Click to list guildmates running it, with the version each one has.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.Underline:Hide()
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() UI:ShowAddonUsers() end)
    self.addonCount = b
end

-- A dot by the version: green in sync, yellow working on it, grey nobody to
-- compare with, red a problem. Hover for details; click to check now.
local DOT_COLOR = { ok = { 0.25, 1, 0.25 }, busy = { 1, 0.82, 0 }, alone = { 0.55, 0.55, 0.55 }, problem = { 1, 0.3, 0.3 } }

function UI:BuildSyncDot(f)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(12, 12)
    b:SetPoint("RIGHT", self.version, "LEFT", -6, 0)
    b.Dot = b:CreateTexture(nil, "OVERLAY")
    b.Dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
    b.Dot:SetAllPoints()
    b:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Sync")
        for _, line in ipairs(ns.Sync:StatusLines()) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:AddLine("Click to check now.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        if ns.Sync:CheckAll() then ns.Sync.reportLane = "guild" end
    end)
    self.syncDot = b
    local function refresh()
        local c = DOT_COLOR[(ns.Sync:Health())] or DOT_COLOR.alone
        b.Dot:SetVertexColor(c[1], c[2], c[3])
    end
    ns:On("SYNC_STATUS", refresh)
    refresh()
end

-- Roster tab, Version column on, only members running the addon.
function UI:ShowAddonUsers()
    local hidden = ns.DB:Settings().hiddenColumns
    if hidden.version ~= false then hidden.version = false end
    self:Show()
    self:SelectTab(UI.TAB_ROSTER)
    ns.RosterView:Relayout()
    ns.RosterView:ShowAddonUsers() -- Filter > Only guildmates using the addon
    ns.PlaySound("IG_CHARACTER_INFO_TAB")
end

function UI:RefreshStatus()
    if not self.status then return end
    local count = self.addonCount
    if not IsInGuild() then
        self.status:SetText("Not in a guild")
        count:Hide()
        return
    end
    local guild = GetGuildInfo("player") or "Guild"
    local total, online, withAddon = ns.Roster:Stats()
    self.status:SetText(((ns.GOLD .. "%s|r   %d members  -  |cffb8bb26%d online|r")):format(guild, total, online))
    if ns.DB:Settings().showAddonCount == false then
        count:Hide()
        return
    end
    -- the dash isn't part of the underline
    local dash = "  -  "
    count.Text:SetText(dash)
    count.dashWidth = count.Text:GetStringWidth()
    count.Text:SetText(dash .. ("%d using %s"):format(withAddon, self:Title()))
    count:SetWidth(math.ceil(count.Text:GetStringWidth()) + 2)
    count:Show()
end

------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------
function UI:SavePosition()
    local point, _, relPoint, x, y = self.frame:GetPoint(1)
    ns.DB:Settings().framePos = { point = point, relPoint = relPoint, x = x, y = y }
end

function UI:RestorePosition()
    local f, pos = self.frame, ns.DB:Settings().framePos
    f:ClearAllPoints()
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -120, 40)
    end
end

function UI:ResetPosition()
    local s = ns.DB:Settings()
    s.framePos = nil
    s.frameSize = { w = FRAME_W, h = FRAME_H }
    if self.frame then
        self.frame:SetSize(FRAME_W, FRAME_H)
        self:RestorePosition()
    end
end

------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------
function UI:Show()
    self:Create():Show()
end

function UI:Hide()
    if self.frame then self.frame:Hide() end
end

-- Opens the window on a tab (and refreshes it right away). If the window is
-- already showing that tab, closes it instead, so one click toggles.
function UI:OpenTab(id, toggle)
    local f = self:Create()
    if toggle and f:IsShown() and self.tab == id then
        f:Hide()
        return
    end
    f:Show()
    self:SelectTab(id)
    if id == UI.TAB_ROSTER then ns.RosterView:Refresh() end
end

function UI:Toggle()
    local f = self:Create()
    f:SetShown(not f:IsShown())
end

function UI:SetSearch(text)
    self:Create()
    self:SelectTab(1)
    ns.RosterView:SetSearch(text)
end
