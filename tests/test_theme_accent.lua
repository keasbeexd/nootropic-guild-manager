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
check("f0f0f0", "2050c0", "60afb3", "227277") -- white field, blue ring: the ring
check("f0f0f0", "111111", "fabd2f", "9d0006") -- no hue anywhere: house
check(nil, nil, "fabd2f", "9d0006")
check("zzzzzz", nil, "fabd2f", "9d0006")
local function check3(bg, border, emblem, face, shade)
    local f, s = A.For(bg, border, emblem)
    assert(f == face and s == shade, ("%s/%s/%s: got %s %s, want %s %s"):format(bg, border, emblem, f, s, face, shade))
end
check3("111111", "6a2c91", "3fae4a", "72bd68", "77225f") -- black field, green crest, purple ring
check3("111111", "6a2c91", "c0c0c0", "c961ac", "77225f") -- only the ring has a hue
print("OK")
