# Controller support (NGM Addon 3.1)

Goal: use the whole NGM Addon with a gamepad. That means opening the window, moving between tabs, buttons, lists and fields, selecting, editing and closing.

## What WoW: Forever gives us

Checked in Blizzard's Forever UI source (Gethe/wow-ui-source, branch `forever`). Forever's game type is `camelot` (the packager names Forever TOCs `_Camelot`).

- **Blizzard's gamepad interface loads on Forever.** That's `Blizzard_Gamepad`, `Blizzard_GamepadSmartNavigation` and `Blizzard_GamepadSharedUtility` (`AllowLoadGameType: camelot`). The game switches to it when the player uses a controller: `C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad`, which is what `InputUtil.IsGamepadUIEnabled()` checks.
- **Smart navigation** (`SmartNavigation`) finds a window's Buttons, CheckButtons, EditBoxes, frames with mouse scripts, and ScrollBox lists by itself (`Utility.FindButtons`).
  - The D-pad moves between them.
  - A (`PAD1`) clicks.
  - B (`PAD2`) closes.
  - It runs a control's OnEnter when it's selected, so tooltips show.
- **Joining it.** `GamepadMode.FrameControlsManager` handles windows. Blizzard's own note: a frame joins "by either being a part of ShowUIPanel or by manually calling FrameShown on their OnShow event". `FrameShown` and `FrameHidden` are wrapped by Blizzard's `SecureHelper`, so addons may call them outside combat. The triggers (`PADLTRIGGER` / `PADRTRIGGER`) move between open windows.
- **Markers for addons**, also wrapped to be safe from addon code:
  - `SmartNavigation_MarkFrameIgnored` (skip a control and its children)
  - `SmartNavigation_MarkFrameFocusable` (make a non-button selectable)
  - `SmartNavigation_SetButtonFrame` (send selection to another control)
  - `SmartNavigation_AddJumpNavigationOverride` (where a direction goes)
  - `SmartNavigation_MarkFrameSubSection` (a focus group)
- **The low-level API** also exists: `frame:EnableGamePadButton` / `EnableGamePadStick` (protected: out of combat only), the `OnGamePadButtonDown` script, `C_GamePad`, and the `GAME_PAD_CONNECTED` / `GAME_PAD_ACTIVE_CHANGED` events. Button names: `PAD1`-`PAD4`, `PADDUP`/`PADDDOWN`/`PADDLEFT`/`PADDRIGHT`, `PADLSHOULDER`/`PADRSHOULDER`, `PADLTRIGGER`/`PADRTRIGGER`, `PADBACK`/`PADFORWARD`.
- **Not open to addons.** Most of `SmartNavigationMixin` runs only from secure code (`EnsureIsSecure`), and so do Blizzard's binding groups for its own windows. We can't change what A and B do inside smart navigation.

## Approach

Use Blizzard's navigation rather than building our own. Our windows join it the same way Blizzard's do, and we only add what it can't work out by itself. Everything stays off with keyboard and mouse.

## Button map

| Button | Does | From |
|---|---|---|
| D-pad | Move between controls | Blizzard |
| A | Click / tick / start typing in a field | Blizzard |
| B | Close the window (or back out of a field) | Blizzard |
| Triggers | Switch between open windows (main window, profile, Do Not Whisper...) | Blizzard |
| Shoulders | Previous / next tab | NGM Addon (step 3) |
| X | The right-click menu of the selected row (Find, Play Together, Recruitment) | NGM Addon (step 3) |
| Y | Jump to the tab's search box | NGM Addon (step 3) |

Opening the window works today: the game's Key Bindings has a key for the window and each tab (3.0.14), and a controller button can be bound to them there.

Typing: an edit box takes focus on A. Text then needs a keyboard or the system's on-screen keyboard (Steam Deck, Windows). Forever's UI source has no on-screen keyboard of its own.

## Steps

1. **Windows join the gamepad interface** (`UI/Gamepad.lua`, done). All nine windows register: the main window, profile, Do Not Whisper, Who Can Craft, recruiting messages, the welcome tour, and the member picker, NGM Peon paste and NGM Peon setup popups. Checked in game (3.1.0); since then the event form, Get Connected and the confirm window joined too.
2. **In-game audit, tab by tab, with a controller.** Note what can't be reached or does the wrong thing. Likely suspects:
   - list rows that only react to right-click
   - the resize grip and dragging (ignore them)
   - Hall of Fame cards and Overview bars, which are hover-only frames (make them focusable)
   - the heatmap grid
   - old `UIDropDownMenu` pickers
3. **Our own buttons:** shoulders for tabs, X for row menus, Y for search. We need to check how an addon may bind these safely: `GamepadMode.CreateBindingGroup` might taint, and the fallback is `EnableGamePadButton` with `OnGamePadButtonDown` on our window, out of combat. A button legend sits along the bottom while in gamepad style.
4. **Polish:** a selection that's easy to see on every tab, a sensible first control per tab, a scroll position that follows the selection.
5. **Taint check** with `/console taintLog 1` through a full session: opening, every tab, combat, closing. This must not get mixed up with the open rank-change taint report.

## Risks

- **Taint:** calling Blizzard's wrapped functions is meant to be safe, but anything we hand to secure code (frames, callbacks) can spread taint. Every step gets a taint-log pass before release.
- **Combat:** our windows close in combat, and step 1 never calls in during combat.
- **No controller to test with on our side:** every step needs a test zip and someone with a controller.
