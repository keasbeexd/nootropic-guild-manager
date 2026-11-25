-- Test: controller support, step 1 (UI/Gamepad.lua): our windows tell the
-- game's gamepad interface when they open and close, only in gamepad
-- style, never in combat, and nothing breaks when the game has none.
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
assert(loadfile(ROOT .. "/UI/Gamepad.lua"))("NGM", ns)
local GP = ns.Gamepad

local function Frame()
  local f = { hooks = {} }
  function f:HookScript(event, fn) self.hooks[event] = fn end
  function f:Fire(event) if self.hooks[event] then self.hooks[event](self) end end
  return f
end

-- no gamepad interface at all: nothing happens, nothing errors
local w = Frame()
GP:Register(w)
w:Fire("OnShow"); w:Fire("OnHide")
assert(not GP:Active() and not w.ngmGamepad)

-- the game's gamepad interface
local calls = {}
Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
local style = 0
C_InputInterfaceStyle = { GetCurrentStyle = function() return style end }
GamepadMode = { FrameControlsManager = {
  FrameShown = function(self, frame, isPopup) calls[#calls + 1] = { "shown", frame, isPopup } return true end,
  FrameHidden = function(self, frame) calls[#calls + 1] = { "hidden", frame } end,
} }
local combat = false
InCombatLockdown = function() return combat end

-- keyboard and mouse: left alone
w:Fire("OnShow"); w:Fire("OnHide")
assert(#calls == 0, "keyboard and mouse: nothing")

-- gamepad style: shown and hidden
style = 1
w:Fire("OnShow")
assert(#calls == 1 and calls[1][1] == "shown" and calls[1][2] == w and calls[1][3] == false)
w:Fire("OnHide")
assert(#calls == 2 and calls[2][1] == "hidden" and calls[2][2] == w)
w:Fire("OnHide")
assert(#calls == 2, "hidden twice: told once")

-- popups are passed as popups
local p = Frame()
GP:Register(p, "popup")
p:Fire("OnShow")
assert(calls[3][1] == "shown" and calls[3][3] == true)
p:Fire("OnHide")

-- registering twice hooks once
GP:Register(w)
w:Fire("OnShow"); w:Fire("OnHide")
assert(#calls == 6)

-- in combat: never
combat = true
w:Fire("OnShow"); w:Fire("OnHide")
assert(#calls == 6, "combat: nothing")
combat = false

-- an error in the game's code doesn't reach ours
GamepadMode.FrameControlsManager.FrameShown = function() error("boom") end
w:Fire("OnShow")
assert(not w.ngmGamepad)
print("OK")
