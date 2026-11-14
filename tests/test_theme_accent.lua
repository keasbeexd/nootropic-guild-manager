-- The guild accent: the same vectors as ngm-hub's test/accent.test.ts
local ns = {}
local ROOT = arg[1] or ".."
assert(loadfile(ROOT .. "/Core/Accent.lua"))("NootropicGuildManager", ns)
local A = ns.Accent
local function check(bg, border, face, shade)
    local f, s = A.For(bg, border)
    assert(f == face and s == shade, ("%s/%s: got %s %s, want %s %s"):format(tostring(bg), tostring(border), f, s, face, shade))
end
check("5b2a86", "d4a017", "c85fad", "8e680b")
check("1f4fa8", "111111", "5badb0", "1f777a")
check("a8201a", "111111", "f12e1e", "901309")
check("f0f0f0", "2050c0", "fabd2f", "9d0006") -- white: no real hue
check(nil, nil, "fabd2f", "9d0006")
check("zzzzzz", nil, "fabd2f", "9d0006")
print("OK")
