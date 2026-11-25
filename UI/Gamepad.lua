--[[
    Nootropic Guild Manager - Controller support (3.1, step 1)
    WoW: Forever has Blizzard's gamepad interface (Blizzard_Gamepad,
    Blizzard_GamepadSmartNavigation, Blizzard_GamepadSharedUtility). When the
    game is in gamepad style (C_InputInterfaceStyle), a window joins it by
    telling GamepadMode.FrameControlsManager when it's shown and hidden (the
    game's own note: "by either being a part of ShowUIPanel or by manually
    calling FrameShown on their OnShow event"). Smart navigation then finds
    the window's buttons, check boxes, edit boxes and scroll lists by itself:
    the D-pad moves between them, A clicks, B closes, the triggers switch
    between open windows.

    Our windows don't open through ShowUIPanel, so each one registers here.
    FrameShown and FrameHidden are wrapped by Blizzard (SecureHelper) to be
    safe to call from addons outside combat; our windows never open in
    combat. Nothing happens with keyboard and mouse, or when the game has no
    gamepad interface. Design: docs/CONTROLLER.md.
]]
local _, ns = ...
local GP = {}
ns.Gamepad = GP

GP.frames = {}

local function Manager()
    local gm = rawget(_G, "GamepadMode")
    return type(gm) == "table" and gm.FrameControlsManager or nil
end

-- Is the game in gamepad style right now?
function GP:Active()
    local style = rawget(_G, "C_InputInterfaceStyle")
    local enum = Enum and Enum.InputDeviceInterfaceType
    if not (Manager() and style and style.GetCurrentStyle and enum and enum.Gamepad) then return false end
    local ok, current = pcall(style.GetCurrentStyle)
    return ok and current == enum.Gamepad
end

local function Busy()
    return InCombatLockdown and InCombatLockdown()
end

function GP:Shown(frame)
    if not self:Active() or Busy() then return false end
    local m = Manager()
    local ok, res = pcall(m.FrameShown, m, frame, self.frames[frame] == "popup")
    if ok and res then frame.ngmGamepad = true end
    return ok and res == true
end

function GP:Hidden(frame)
    if not frame.ngmGamepad then return false end
    frame.ngmGamepad = nil
    local m = Manager()
    if not m then return false end
    return (pcall(m.FrameHidden, m, frame))
end

-- Registers one of our windows. kind: "window" (default) or "popup" (a
-- small window opened from another, focused at once).
function GP:Register(frame, kind)
    if not frame or self.frames[frame] then return end
    self.frames[frame] = kind or "window"
    frame:HookScript("OnShow", function(f) GP:Shown(f) end)
    frame:HookScript("OnHide", function(f) GP:Hidden(f) end)
end
