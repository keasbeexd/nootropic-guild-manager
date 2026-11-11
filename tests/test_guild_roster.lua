-- Test: the game's guild roster integration. Rows get our tooltip lines and
-- Alt+click after Blizzard's SetMember through hooksecurefunc (no callbacks
-- registered inside Blizzard's list, which tainted the rank dropdown), and
-- nothing is added to the rows themselves (the alt tag is only on Find).
-- Run with tests/run.sh (it passes the repo root as arg[1]).
local ROOT = arg[1]
local ns = {}
function ns:On() end function ns:RegisterEvent() end function ns:Print() end
function ns.Debounce(_, _, fn) fn() end
function ns.NormalizeName(n) return n end
ns.DB = { Settings = function() return {} end }
ns.Roster = { byName = {
  ["Charliebrown Noises"] = { full = "Charliebrown Noises", isAlt = true },
  ["Probably Shawn"] = { full = "Probably Shawn", isAlt = false } }, byGuid = {} }
ns.InstallReminder = { StatusLine = function() end, MenuItem = function() end }

-- stand-ins for the game's frames
local function frame()
  local f = { shown = true, points = {} }
  function f:SetSize() end function f:SetWidth(w) self.w = w end function f:SetFrameLevel() end
  function f:GetFrameLevel() return 1 end function f:EnableMouse() end
  function f:ClearAllPoints() self.points = {} end
  function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function f:Show() self.shown = true end function f:Hide() self.shown = false end
  function f:SetShown(v) self.shown = v and true or false end
  function f:HookScript(what) self.hooks = (self.hooks or 0) + 1 end
  function f:CreateTexture() local t = frame() function t:SetAllPoints() end function t:SetColorTexture() end return t end
  function f:CreateFontString() local t = frame() function t:SetText(x) self.text = x end function t:GetStringWidth() return 14 end return t end
  return f
end
CreateFrame = function() return frame() end
local hooked = {}
hooksecurefunc = function(t, key, post)
  if type(t) == "string" then return end
  local orig = t[key]
  hooked[#hooked + 1] = key
  t[key] = function(...) local r = orig(...) post(...) return r end
end
CommunitiesMemberListEntryMixin = { SetMember = function(self, info) self.info = info end }
local function row()
  local r = frame()
  r.NameFrame = frame()
  r.SetMember = CommunitiesMemberListEntryMixin.SetMember -- a row made before we hooked
  function r:GetMemberInfo() return self.info end
  return r
end
local rows = { row(), row() }
local list = { ScrollBox = { ForEachFrame = function(_, fn) for _, r in ipairs(rows) do fn(r) end end },
               RefreshListDisplay = function() end }
C_Club = { GetGuildClubId = function() return 7 end }
CommunitiesFrame = { MemberList = list, GetSelectedClubId = function() return 7 end }
ScrollUtil = { AddInitializedFrameCallback = function() error("must not register callbacks inside Blizzard's list") end }
Menu = nil

assert(loadfile(ROOT .. "/UI/GuildRoster.lua"))("NGM", ns)
local GR = ns.GuildRoster
GR:Attach()
local count = function(k) local n = 0 for _, h in ipairs(hooked) do if h == k then n = n + 1 end end return n end
assert(count("SetMember") >= 1, "SetMember hooked")
assert(count("RefreshListDisplay") == 1)

-- Blizzard fills the rows
rows[1]:SetMember({ name = "Charliebrown Noises" })
rows[2]:SetMember({ name = "Probably Shawn" })
assert(rows[1].hooks == 2 and rows[2].hooks == 2, "tooltip and Alt+click hooked on each row")
assert(rows[1].NGMBadge == nil and rows[2].NGMBadge == nil, "nothing added to the rows")
-- rows reused while scrolling aren't hooked twice
rows[1]:SetMember({ name = "Probably Shawn" })
assert(rows[1].hooks == 2, "hooked once")
-- a row created after we hooked uses the hooked mixin method
local late = row()
late.SetMember = CommunitiesMemberListEntryMixin.SetMember
late:SetMember({ name = "Charliebrown Noises" })
assert(late.hooks == 2 and late.NGMBadge == nil, "new rows hooked too, nothing added")
print("OK")
