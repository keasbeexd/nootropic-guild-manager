--[[
    Nootropic Guild Manager - Invite prompt
    WoW: Forever blocks guild invites that come from an addon: calling
    C_GuildInfo.Invite is blocked, and so is /ginvite run by a secure macro
    button (2.1.6/2.1.7). /ginvite typed in the chat box works. So Invite
    puts "/ginvite <name>" in your chat box and you press Enter; the game's
    "You have invited ..." message marks them invited and shows the next one.

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
    self.more:SetPoint("TOPRIGHT", -30, -6)

    -- the game confirms a sent invite in a system message
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, _, msg) IP:OnSystemMessage(msg) end)

    local invite = W.Button(f, "Invite", 130, 24)
    invite:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 14)
    invite:SetScript("OnClick", function() IP:OpenInvite() end)
    W.Tooltip(invite, "Invite", "Puts /ginvite and their name in your chat box. Press Enter to send it.")
    self.inviteButton = invite

    self.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.hint:SetPoint("BOTTOM", 0, 44)

    local later = W.Button(f, "Not now", 110, 24)
    later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 14)
    later:SetScript("OnClick", function() IP:Next() end)

    -- the frame's own close button skips everything waiting
    if f.CloseButton then f.CloseButton:HookScript("OnClick", function() wipe(IP.queue); IP.full = nil end) end
end

-- "/ginvite First Last" into the chat box, ready for you to press Enter.
function IP:OpenInvite()
    local full = self.full
    if not full then return end
    local ok, err = ns.Recruit:CanInviteNow(full)
    if not ok then
        if err then ns:Print("|cffff5555" .. err .. "|r") end
        return
    end
    local text = "/ginvite " .. ns.ChatName(full)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat(text)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(text)
    else
        ns:Print(("Type |cffffffff%s|r to invite them."):format(text))
        return
    end
    self.opened = full
    self:Render()
end

-- "You have invited Audrey Pichhale to join your guild."
local INVITED = (ERR_GUILD_INVITE_S or "You have invited %s to join your guild.")
    :gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)")
INVITED = "^" .. INVITED .. "$"

function IP:OnSystemMessage(msg)
    local who = msg and msg:match(INVITED)
    if not who then return end
    local function same(full) return full and ns.ChatName(full):lower() == who:lower() end
    local hit
    if same(self.full) then
        hit = self.full
    else
        for i, q in ipairs(self.queue) do
            if same(q.full) then hit = q.full; table.remove(self.queue, i); break end
        end
    end
    if not hit then return end
    ns.Recruit:MarkInvited(hit)
    if hit == self.full then self:Next() else self:Render() end
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
    local opened = self.opened and self.opened == self.full
    self.hint:SetText(opened and "Press |cffffffffEnter|r in your chat box to send the invite." or "")
    self.inviteButton:SetText(opened and "Put it in chat again" or "Invite")
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
    self.opened = nil
end

-- /ngm diag
function IP:Diagnose()
    ns:Print(("Invite prompt: %s, %d waiting, chat box %s, invite message pattern %s"):format(
        self.frame and self.frame:IsShown() and ("showing " .. ns.ShortName(self.full or "?")) or "closed",
        #self.queue, (ChatFrameUtil and ChatFrameUtil.OpenChat) and "ChatFrameUtil.OpenChat" or (ChatFrame_OpenChat and "ChatFrame_OpenChat" or "none"),
        ERR_GUILD_INVITE_S and "from the game" or "built in"))
end
