--[[
    Nootropic Guild Manager - Invite prompt
    WoW: Forever only lets Blizzard's own code send guild invites
    (C_GuildInfo.Invite is "allowed when untainted"): an addon calling it is
    blocked, even after a click. So the Invite button here is a secure macro
    button that runs "/ginvite <name>" on your click, exactly as if you had
    typed it, the same way the Recruitment tab's Search runs /who.

    Shown when someone replies with an invite keyword, and from "Invite to
    Guild" on the Recruitment list. Several waiting invites queue up.

    ns.InvitePrompt:Show(full, reply)
]]
local _, ns = ...
local W = ns.Widgets
local IP = {}
ns.InvitePrompt = IP

IP.queue = {} -- { { full, reply }, ... } waiting behind the one shown

function IP:Build()
    local f = CreateFrame("Frame", "NootropicGMInvitePrompt", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(360, 170)
    f:SetPoint("TOP", 0, -160)
    f:SetFrameStrata("DIALOG")
    -- not a top-level frame: raising itself on click would lift the Invite
    -- button above its secure overlay
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.SetTitle(f, "Guild Invite")
    self.frame = f

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 18, -34)
    text:SetPoint("TOPRIGHT", -18, -34)
    text:SetJustifyH("CENTER")
    text:SetSpacing(3)
    self.text = text

    self.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.more:SetPoint("BOTTOM", 0, 44)

    local invite = W.Button(f, "Invite", 130, 24)
    invite:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 14)
    -- Only reached when the secure button isn't over it (in combat, or a
    -- client without secure buttons): say why nothing happened.
    invite:SetScript("OnClick", function(btn)
        if InCombatLockdown() then
            ns:Print("You can't send guild invites in combat. Click Invite again once the fight is over.")
        elseif btn.secure then
            -- the secure button wasn't on top for that click; put it back
            btn.secure.Update()
            ns:Print("Click Invite once more to send the invite.")
        else
            ns:Print(("This game client has no secure buttons for addons. Type |cffffffff/ginvite %s|r to invite them."):format(IP.full and ns.ChatName(IP.full) or "<name>"))
        end
    end)
    self.inviteButton = invite
    W.SecureOverlay(invite, {
        macro = function() return IP:Macro() end,
        post = function() IP:AfterInvite() end,
    })

    local later = W.Button(f, "Not now", 110, 24)
    later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 14)
    later:SetScript("OnClick", function() IP:Next() end)

    -- the frame's own close button skips everything waiting
    if f.CloseButton then f.CloseButton:HookScript("OnClick", function() wipe(IP.queue); IP.full = nil end) end
end

-- The macro the secure button runs, or nil (nothing happens) when this
-- invite isn't allowed right now. A click reaches the secure button twice
-- (mouse down and up) and the game runs the macro on one of them, so the
-- macro must name the same person both times: the prompt only moves on to
-- the next invite after a short pause (AfterInvite).
IP.SETTLE = 0.6

function IP:Macro()
    local full = self.full
    if not full then return nil end
    if self.armed == full then return "/ginvite " .. ns.ChatName(full) end -- second half of the same click
    local ok, err = ns.Recruit:CanInviteNow(full)
    if not ok then
        self.armed = nil
        if err then ns:Print("|cffff5555" .. err .. "|r") end
        return nil
    end
    self.armed = full
    return "/ginvite " .. ns.ChatName(full)
end

function IP:AfterInvite()
    local full = self.armed
    if not full or self.settling then return end
    self.settling = true
    C_Timer.After(self.SETTLE, function()
        self.settling = nil
        self.armed = nil
        ns.Recruit:MarkInvited(full)
        ns:Print(("Guild invite sent to %s."):format(ns.ShortName(full)))
        if self.full == full then self:Next() end
    end)
end

function IP:Render()
    local name = ns.ShortName(self.full)
    if self.reply and self.reply ~= "" then
        self.text:SetText(("|cffffd100%s|r replied:\n\"%s\"\n\nInvite them to the guild?"):format(name, self.reply))
    else
        self.text:SetText(("Invite |cffffd100%s|r to the guild?"):format(name))
    end
    local n = #self.queue
    self.more:SetText(n > 0 and (n == 1 and "1 more waiting" or (n .. " more waiting")) or "")
end

function IP:Show(full, reply)
    if not full then return end
    if not self.frame then self:Build() end
    if self.full == full then
        self.reply = reply or self.reply
        self:Render()
        return
    end
    for _, q in ipairs(self.queue) do
        if q.full == full then q.reply = reply or q.reply; self:Render(); return end
    end
    if self.full and self.frame:IsShown() then
        table.insert(self.queue, { full = full, reply = reply })
        self:Render()
        return
    end
    self.full, self.reply = full, reply
    self:Render()
    self.frame:Show()
    ns.PlaySound("TELL_MESSAGE")
end

-- Shows the next waiting invite, or closes.
function IP:Next()
    local q = table.remove(self.queue, 1)
    if q then
        self.full, self.reply = q.full, q.reply
        self:Render()
    else
        self.full, self.reply = nil, nil
        if self.frame then self.frame:Hide() end
    end
end

-- /ngm diag: is the secure Invite button there and on top?
function IP:Diagnose()
    if not self.frame then self:Build() end
    local host, b = self.inviteButton, self.inviteButton.secure
    if not b then
        ns:Print("Invite prompt: no secure button (this client doesn't offer SecureActionButtonTemplate to addons).")
        return
    end
    ns:Print(("Invite prompt: secure button %s, prompt %s, layer %s/%d over %s/%d, combat=%s, macro=%q"):format(
        b:IsShown() and "shown" or "hidden", self.frame:IsShown() and "open" or "closed",
        b:GetFrameStrata(), b:GetFrameLevel(), host:GetFrameStrata(), host:GetFrameLevel(),
        tostring(InCombatLockdown()), tostring(b:GetAttribute("macrotext") or "")))
end
