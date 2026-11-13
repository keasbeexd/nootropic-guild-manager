--[[
    Nootropic Guild Manager - /ngm peon: bring in a code from NGM Peon
    The dashboard's Sync tab (step 1) gives a code with what was
    set there: mains and alts, Tank / Healer / DPS, fixes for wrong links. It
    also says what NGM Peon already has, so the next /ngm discord only carries
    new changes. Pasted here, its records are taken under the addon's usual
    rules and shared with the guild (Services/DiscordCode.lua, ApplyPeon).

    ns.PeonPasteView:Open()
]]
local _, ns = ...
local W = ns.Widgets
local V = {}
ns.PeonPasteView = V

function V:Build()
    local f = CreateFrame("Frame", "NootropicGMPeonPaste", UIParent, "BasicFrameTemplateWithInset")
    W.CombatSafeClose(f)
    f:SetSize(460, 236)
    f:SetPoint("TOP", 0, -140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    W.SetTitle(f, "From NGM Peon")
    tinsert(UISpecialFrames, "NootropicGMPeonPaste") -- Escape closes it
    self.frame = f

    local steps = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    steps:SetPoint("TOPLEFT", 20, -36)
    steps:SetPoint("TOPRIGHT", -20, -36)
    steps:SetJustifyH("LEFT")
    steps:SetSpacing(4)
    steps:SetText("|cffffd1001.|r On |cffffffffngmpeon.app|r, open the Sync tab: step 1.\n"
        .. "|cffffd1002.|r Copy it and paste it below (Ctrl+V).\n"
        .. "|cffffd1003.|r Press Bring In.")

    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(410, 22)
    box:SetPoint("TOP", steps, "BOTTOM", 0, -16)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0) -- a code can run to thousands of characters
    if box.SetMaxBytes then box:SetMaxBytes(0) end
    box:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    box:SetScript("OnEnterPressed", function() V:BringIn() end)
    self.box = box

    self.result = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.result:SetPoint("TOP", box, "BOTTOM", 0, -12)
    self.result:SetWidth(420)
    self.result:SetJustifyH("CENTER")

    local go = W.Button(f, "Bring In", 130, 24)
    go:SetPoint("BOTTOM", 0, 14)
    go:SetScript("OnClick", function() V:BringIn() end)
    W.Tooltip(go, "Bring in the code", "Takes what NGM Peon has into your game and shares it with the guild.")
end

function V:BringIn()
    local got, why = ns.DiscordCode:ApplyPeon(self.box:GetText())
    if not got then
        self.result:SetText("|cffff5555" .. why .. "|r")
        return
    end
    local lines = { ("|cff33dd33Done.|r %d new, %d already here."):format(got.taken, got.had) }
    if got.refused > 0 then
        lines[#lines + 1] = ("|cffffaa33%d not taken|r: your rank can only bring in your own. An officer can bring in the rest."):format(got.refused)
    end
    self.result:SetText(table.concat(lines, "\n"))
    self.box:SetText("")
    self.box:ClearFocus()
end

function V:Open()
    if not self.frame then self:Build() end
    self.box:SetText("")
    self.result:SetText("")
    self.frame:Show()
    self.box:SetFocus()
end
