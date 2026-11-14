--[[
    Nootropic Guild Manager - the guild's accent
    The guild tabard's colours given a Gruvbox flare, for buttons and the
    open tab: the face keeps the guild's hue, pulled 60% toward the nearest
    Gruvbox colour, at Gruvbox's saturation and brightness; the shadow is
    the border's hue at Gruvbox's deep shade. A tabard with no real hue
    (white, black, grey), or none, keeps the house yellow and red.
    NGM Peon works out the same (ngm-hub src/accent.ts; same test vectors).

      ns.Accent.For(bgHex, borderHex) -> faceHex, shadeHex
      ns.Accent:Tabard()              -> bgHex, borderHex (or nil)
]]
local _, ns = ...
local A = {}
ns.Accent = A

local GRUVBOX = { "fb4934", "b8bb26", "fabd2f", "83a598", "d3869b", "8ec07c", "fe8019" }
A.HOUSE = { face = "fabd2f", shade = "9d0006" }

local function Rgb(h)
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
local function Hex(r, g, b)
    local function c(x) return math.floor(math.max(0, math.min(1, x)) * 255 + 0.5 + 1e-6) end -- the same rounding as NGM Peon
    return ("%02x%02x%02x"):format(c(r), c(g), c(b))
end
local function Clamp(x, a, b) return math.max(a, math.min(b, x)) end

-- HLS as Python's colorsys (hue 0..1)
local function ToHls(r, g, b)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local l = (max + min) / 2
    if max == min then return 0, l, 0 end
    local d = max - min
    local s = l <= 0.5 and d / (max + min) or d / (2 - max - min)
    local rc, gc, bc = (max - r) / d, (max - g) / d, (max - b) / d
    local h
    if r == max then h = bc - gc elseif g == max then h = 2 + rc - bc else h = 4 + gc - rc end
    return (h / 6) % 1, l, s
end
local function FromHls(h, l, s)
    if s == 0 then return l, l, l end
    local m2 = l <= 0.5 and l * (1 + s) or l + s - l * s
    local m1 = 2 * l - m2
    local function v(hue)
        hue = hue % 1
        if hue < 1 / 6 then return m1 + (m2 - m1) * hue * 6 end
        if hue < 0.5 then return m2 end
        if hue < 2 / 3 then return m1 + (m2 - m1) * (2 / 3 - hue) * 6 end
        return m1
    end
    return v(h + 1 / 3), v(h), v(h - 1 / 3)
end
local function HueDelta(a, b)
    local d = (b - a) % 1
    return d > 0.5 and d - 1 or d
end

local function Flare(hex, light)
    local h, l, s = ToHls(Rgb(hex))
    if s < 0.15 or l < 0.06 or l > 0.94 then return nil end
    local best
    for _, g in ipairs(GRUVBOX) do
        local gh, gl, gs = ToHls(Rgb(g))
        if not best or math.abs(HueDelta(h, gh)) < math.abs(HueDelta(h, best[1])) then best = { gh, gl, gs } end
    end
    local h2 = (h + 0.6 * HueDelta(h, best[1])) % 1
    local s2 = light and Clamp(0.35 * s + 0.65 * best[3], 0.35, 0.9) or Clamp(0.5 * s + 0.5 * best[3], 0.55, 0.85)
    local l2 = light and Clamp(0.3 * l + 0.7 * best[2], 0.5, 0.68) or 0.3
    return Hex(FromHls(h2, l2, s2))
end

local function Valid(x) return type(x) == "string" and x:match("^%x%x%x%x%x%x$") and x:lower() end

function A.For(bg, border)
    bg, border = Valid(bg), Valid(border)
    local face = bg and Flare(bg, true)
    if not face then return A.HOUSE.face, A.HOUSE.shade end
    local shade = border and Flare(border, false)
    if not shade then
        local h, _, s = ToHls(Rgb(face))
        shade = Hex(FromHls(h, 0.3, Clamp(s, 0.6, 0.9)))
    end
    return face, shade
end

-- Your guild's tabard colours as hex, or nil (no guild, no tabard yet).
function A:Tabard()
    if not (IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GetGuildTabardInfo) then return nil end
    local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
    if not (ok and info and info.backgroundColor and info.borderColor) then return nil end
    local function h(c) return Hex(c:GetRGB()) end
    return h(info.backgroundColor), h(info.borderColor)
end
