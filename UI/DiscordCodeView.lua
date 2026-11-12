--[[
    Nootropic Guild Manager - /ngm discord: the NGM Peon setup code
    Shows the Guild Master the code to paste into NGM Peon's /ngm setup in
    Discord. Copying works like the invite prompt: the code is selected for
    you to press Ctrl+C; the addon never touches the clipboard or chat box.

    ns.DiscordCodeView:Open()
]]
local _, ns = ...
local W = ns.Widgets
local V = {}
ns.DiscordCodeView = V

function V:Build()
    local f = CreateFrame("Frame", "NootropicGMDiscordCode", UIParent, "BasicFrameTemplateWithInset")
    W.CombatSafeClose(f)
    f:SetSize(460, 262)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.SetTitle(f, "NGM Peon Setup")
    tinsert(UISpecialFrames, "NootropicGMDiscordCode") -- Escape closes it
    self.frame = f

    local steps = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    steps:SetPoint("TOPLEFT", 20, -36)
    steps:SetPoint("TOPRIGHT", -20, -36)
    steps:SetJustifyH("LEFT")
    steps:SetSpacing(4)
    steps:SetText("|cffffd1001.|r Invite NGM Peon to your guild's Discord (|cffffffffngmpeon.app|r).\n"
        .. "|cffffd1002.|r In Discord, run |cffffffff/ngm setup|r and paste this code.\n"
        .. "|cffffd1003.|r Sign in with Battle.net when NGM Peon asks.")
    self.steps = steps

    self.what = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.what:SetPoint("TOPLEFT", steps, "BOTTOMLEFT", 0, -12)
    self.what:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    self.what:SetJustifyH("LEFT")

    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(410, 22)
    box:SetPoint("BOTTOM", 0, 74)
    box:SetAutoFocus(false)
    box:SetScript("OnTextChanged", function(eb, user) if user then eb:SetText(V.code or ""); eb:HighlightText() end end)
    box:SetScript("OnEditFocusGained", function(eb) eb:HighlightText() end)
    box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnKeyDown", function(eb, key)
        if key == "C" and IsControlKeyDown() then
            C_Timer.After(0.05, function() eb:ClearFocus() end)
            V.hint:SetText("|cff33dd33Copied.|r Paste it into /ngm setup in Discord.")
        end
    end)
    self.box = box

    self.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.hint:SetPoint("BOTTOM", 0, 48)
    self.hint:SetWidth(420)

    local copy = W.Button(f, "Select Code", 130, 24)
    copy:SetPoint("BOTTOM", 0, 14)
    copy:SetScript("OnClick", function() V:Select() end)
    W.Tooltip(copy, "Copy the setup code", "Selects the code so you can copy it with Ctrl+C.")
    self.copy = copy
end

function V:Select()
    if not self.code then return end
    self.box:SetText(self.code)
    self.box:SetFocus()
    self.box:HighlightText()
    self.hint:SetText("Press |cffffffffCtrl+C|r to copy.")
end

function V:Open()
    local code, why = ns.DiscordCode:ForMyGuild()
    if not code then
        ns:Print("|cffff5555" .. why .. "|r")
        return
    end
    if not self.frame then self:Build() end
    self.code = code
    local n = #ns.DB:GuildRanks()
    self.what:SetText(("The code holds your guild's name, region, %d rank names and which ranks are Officer and Invite Member. "
        .. "It changes when your ranks do; make a new one after renaming ranks."):format(n))
    self.box:SetText(code)
    self.box:SetCursorPosition(0)
    self.hint:SetText("")
    self.frame:Show()
    self:Select()
end
