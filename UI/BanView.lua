--[[
    Nootropic Guild Manager - Ban List window (3.2, docs/PERMISSIONS.md)
    Everyone banned, as people (main and alts together): when, by whom, and
    why (for ranks the Guild Master lets see reasons). Ban a Player and Unban
    for ranks allowed to ban. Opens with /ngm bans or the Recruitment tab's
    Ban List button (the guild roster's right-click menu bans by name); only for ranks allowed to see the list.
]]
local _, ns = ...
local W = ns.Widgets
local BV = {}
ns.BanView = BV

local WIDTH, HEIGHT, ROW_H = 560, 440, 52

function BV:Build()
    local f = CreateFrame("Frame", "NootropicGMBanList", UIParent, "BasicFrameTemplateWithInset")
    ns.Theme:Skin(f)
    W.CombatSafeClose(f)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "NootropicGMBanList")
    ns.Gamepad:Register(f, "window")
    W.SetTitle(f, "Ban List")
    self.frame = f

    local intro = f:CreateFontString(nil, "OVERLAY", "NGMFontTextSmall")
    intro:SetPoint("TOPLEFT", 16, -32)
    intro:SetPoint("RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("A ban covers the person: their main and every alt linked to them. Anyone in the guild who invites them gets a big warning, and recruiting skips them.")

    local scroll = W.TryCreate("ScrollFrame", "NootropicGMBanScroll", f, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -66)
    scroll:SetPoint("BOTTOMRIGHT", -32, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 50, 10)
    scroll:SetScrollChild(content)
    self.content, self.rows = content, {}
    self.empty = content:CreateFontString(nil, "OVERLAY", "NGMFontDim")
    self.empty:SetPoint("TOP", 0, -30)
    self.empty:SetText("Nobody is banned.")

    self.add = W.Button(f, "Ban a Player...", 140, 24, "bad")
    self.add:SetPoint("BOTTOMLEFT", 14, 14)
    self.add:SetScript("OnClick", function() BV:AskBan() end)
    f:SetScript("OnShow", function() BV:Refresh() end)
    ns:On("BANS_CHANGED", function() if f:IsShown() then BV:Refresh() end end)
end

-- A name, then a reason
function BV:AskBan(name)
    local function reason(full)
        W.Prompt(("Why is %s banned? (optional; only ranks allowed to see reasons see it)"):format(ns.ShortName(full)), "", function(why)
            local n, err = ns.Bans:Ban(full, why)
            if n then ns:Print(("%s is banned (%d character%s)."):format(ns.ShortName(full), n, n == 1 and "" or "s"))
            else ns:Print("|cffff2020" .. (err or "That didn't work.") .. "|r") end
        end, 200)
    end
    if name then reason(name) return end
    W.Prompt("Whose name? (any of their characters: the ones linked to them are banned too)", "", function(text)
        text = ns.Trim(text or "")
        if text ~= "" then reason(ns.NormalizeName(text)) end
    end, 40)
end

local function Row(i)
    local r = BV.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, BV.content)
    r:SetHeight(ROW_H - 4)
    r.Name = r:CreateFontString(nil, "OVERLAY", "NGMFontLabel")
    r.Name:SetPoint("TOPLEFT", 4, -4)
    r.Info = r:CreateFontString(nil, "OVERLAY", "NGMFontDimSmall")
    r.Info:SetPoint("TOPLEFT", r.Name, "BOTTOMLEFT", 0, -3)
    r.Info:SetPoint("RIGHT", -100, 0)
    r.Info:SetJustifyH("LEFT")
    r.Remove = W.Button(r, "Unban", 80, 22, "alt")
    r.Remove:SetPoint("RIGHT", -4, 0)
    BV.rows[i] = r
    return r
end

function BV:Refresh()
    local B = ns.Bans
    -- one row per person (by main)
    local people, order = {}, {}
    for _, b in ipairs(B:All()) do
        local key = b.main ~= "" and b.main or b.full
        if not people[key] then people[key] = { main = key, ban = b, chars = {} } order[#order + 1] = key end
        table.insert(people[key].chars, ns.ShortName(b.full))
    end
    local canBan = ns.DB:HasPerm("ban")
    local y = 0
    for i, key in ipairs(order) do
        local p = people[key]
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
        r.Name:SetText(ns.ShortName(p.main) .. "  |cff9d9d9d" .. table.concat(p.chars, ", ") .. "|r")
        local reason = B:Reason(p.ban)
        r.Info:SetText(("Banned %s by %s"):format(ns.FormatAgo(p.ban.t), ns.ShortName(p.ban.by)) .. (reason and (": " .. reason) or ""))
        r.Remove:SetShown(canBan)
        r.Remove:SetScript("OnClick", function()
            W.Confirm(("Unban %s and all their characters?"):format(ns.ShortName(p.main)), function()
                local n, err = B:Unban(p.ban.full)
                ns:Print(n and (ns.ShortName(p.main) .. " is no longer banned.") or ("|cffff2020" .. (err or "That didn't work.") .. "|r"))
            end)
        end)
        r:Show()
        y = y + ROW_H
    end
    for i = #order + 1, #self.rows do self.rows[i]:Hide() end
    self.empty:SetShown(#order == 0)
    self.content:SetHeight(math.max(y, 10))
    self.add:SetShown(canBan)
end

function BV:Open()
    if InCombatLockdown and InCombatLockdown() then return end
    if not ns.DB:HasPerm("banlist") then ns:Print("Your rank can't see the ban list (the Guild Master's Permissions).") return end
    if not self.frame then self:Build() end
    self.frame:Show()
    self:Refresh()
end
