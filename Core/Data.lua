--[[
    Nootropic Guild Manager - Static data
    Classes, specializations, professions, roles and defaults.
]]
local _, ns = ...
local D = {}
ns.Data = D

------------------------------------------------------------------------
-- Specializations (talent trees) per class
------------------------------------------------------------------------
D.CLASS_SPECS = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER  = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE   = { "Assassination", "Combat", "Subtlety" },
    PRIEST  = { "Discipline", "Holy", "Shadow" },
    SHAMAN  = { "Elemental", "Enhancement", "Restoration" },
    MAGE    = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID   = { "Balance", "Feral Combat", "Restoration" },
}

local ICON = "Interface\\Icons\\"

D.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
function D:ClassName(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or CLASS_NAMES[classFile] or classFile
end

-- Talent tree icons, as shown on each class's talent tabs.
D.SPEC_ICONS = {
    WARRIOR = { ["Arms"] = "Ability_Rogue_Eviscerate", ["Fury"] = "Ability_Warrior_InnerRage", ["Protection"] = "INV_Shield_06" },
    PALADIN = { ["Holy"] = "Spell_Holy_HolyBolt", ["Protection"] = "Spell_Holy_DevotionAura", ["Retribution"] = "Spell_Holy_AuraOfLight" },
    HUNTER  = { ["Beast Mastery"] = "Ability_Hunter_BeastTaming", ["Marksmanship"] = "Ability_Marksmanship", ["Survival"] = "Ability_Hunter_SwiftStrike" },
    ROGUE   = { ["Assassination"] = "Ability_Rogue_Eviscerate", ["Combat"] = "Ability_BackStab", ["Subtlety"] = "Ability_Stealth" },
    PRIEST  = { ["Discipline"] = "Spell_Holy_WordFortitude", ["Holy"] = "Spell_Holy_GuardianSpirit", ["Shadow"] = "Spell_Shadow_ShadowWordPain" },
    SHAMAN  = { ["Elemental"] = "Spell_Nature_Lightning", ["Enhancement"] = "Spell_Nature_LightningShield", ["Restoration"] = "Spell_Nature_MagicImmunity" },
    MAGE    = { ["Arcane"] = "Spell_Holy_MagicalSentry", ["Fire"] = "Spell_Fire_FireBolt02", ["Frost"] = "Spell_Frost_FrostBolt02" },
    WARLOCK = { ["Affliction"] = "Spell_Shadow_DeathCoil", ["Demonology"] = "Spell_Shadow_Metamorphosis", ["Destruction"] = "Spell_Shadow_RainOfFire" },
    DRUID   = { ["Balance"] = "Spell_Nature_StarFall", ["Feral Combat"] = "Ability_Racial_BearForm", ["Restoration"] = "Spell_Nature_HealingTouch",
                ["Feral"] = "Ability_Racial_BearForm", ["Guardian"] = "Ability_Racial_BearForm" },
}
local specLookup = {}
for classFile, specs in pairs(D.SPEC_ICONS) do
    specLookup[classFile] = {}
    for name, icon in pairs(specs) do specLookup[classFile][name:lower()] = ICON .. icon end
end

-- Icon for a class's spec (case-insensitive), or nil when unknown.
function D:SpecIcon(classFile, spec)
    local t = classFile and specLookup[classFile]
    return t and spec and t[spec:lower()]
end

------------------------------------------------------------------------
-- Addon icon choices (window portrait, minimap button, shortcuts)
------------------------------------------------------------------------
D.ICON_STYLES = {
    { key = "mug",    label = "Ale Mug",        icon = ICON .. "INV_Drink_13" },
    { key = "stein",  label = "Brewfest Stein", icon = ICON .. "INV_Holiday_BrewfestBuff_01" },
    { key = "emblem", label = "Guild Emblem",   icon = ICON .. "INV_Drink_13" }, -- icon = fallback outside a guild
}
D.DEFAULT_ICON = ICON .. "INV_Drink_13"

function D:IconStyle(key)
    for _, s in ipairs(self.ICON_STYLES) do
        if s.key == key then return s end
    end
    return self.ICON_STYLES[1]
end

------------------------------------------------------------------------
-- Minimap button click actions (Options > Minimap Button)
------------------------------------------------------------------------
-- Tab actions are named after the tab's title (officers can rename tabs).
D.MINIMAP_ACTIONS = {
    { key = "roster",  tab = true },
    { key = "recruit", tab = true },
    { key = "audit",   tab = true, suffix = " (officers)" },
    { key = "options", label = "Open Options" },
    { key = "toggle",  label = "Show / hide window" },
    { key = "none",    label = "Do nothing" },
}
function D:MinimapActionLabel(key)
    for _, a in ipairs(self.MINIMAP_ACTIONS) do
        if a.key == key then
            if a.tab then return "Open " .. ns.TabName(a.key) .. (a.suffix or "") end
            return a.label
        end
    end
    return "Do nothing"
end

------------------------------------------------------------------------
-- Professions
------------------------------------------------------------------------
D.PROFESSIONS = {
    { name = "Alchemy",        icon = ICON .. "Trade_Alchemy" },
    { name = "Blacksmithing",  icon = ICON .. "Trade_BlackSmithing" },
    { name = "Enchanting",     icon = ICON .. "Trade_Engraving" },
    { name = "Engineering",    icon = ICON .. "Trade_Engineering" },
    { name = "Herbalism",      icon = ICON .. "Trade_Herbalism" },
    { name = "Leatherworking", icon = ICON .. "INV_Misc_ArmorKit_17" },
    { name = "Mining",         icon = ICON .. "Trade_Mining" },
    { name = "Skinning",       icon = ICON .. "INV_Misc_Pelt_Wolf_01" },
    { name = "Tailoring",      icon = ICON .. "Trade_Tailoring" },
    { name = "Cooking",        icon = ICON .. "INV_Misc_Food_15",           secondary = true },
    { name = "First Aid",      icon = ICON .. "Spell_Holy_SealOfSacrifice", secondary = true },
    { name = "Fishing",        icon = ICON .. "Trade_Fishing",              secondary = true },
}
D.PROF_MAX_RANK = 300
D.UNKNOWN_ICON = ICON .. "INV_Misc_QuestionMark"

local byName = {}
for _, p in ipairs(D.PROFESSIONS) do byName[p.name:lower()] = p end

function D:GetProfession(name)
    return name and byName[name:lower()]
end

function D:IsPrimary(name)
    local p = self:GetProfession(name)
    return not (p and p.secondary)
end

function D:ProfIcon(prof)
    if prof.icon then return prof.icon end
    local p = self:GetProfession(prof.name)
    return p and p.icon or D.UNKNOWN_ICON
end

-- Roles a character plays (set on their profile; any of them)
D.ROLES = {
    { key = "tank",   label = "Tank",   icon = "Interface\\Icons\\Ability_Defend",      color = { 0.25, 0.60, 1.00 } },
    { key = "healer", label = "Healer", icon = "Interface\\Icons\\Spell_Holy_HolyBolt", color = { 0.20, 0.80, 0.35 } },
    { key = "damage", label = "Damage", icon = "Interface\\Icons\\Ability_DualWield",   color = { 0.92, 0.22, 0.22 } },
}

function D:Role(key)
    for _, r in ipairs(self.ROLES) do if r.key == key then return r end end
end

D.MAX_LOG_LENGTH = 140 -- fits one addon message

------------------------------------------------------------------------
-- Recruitment defaults
------------------------------------------------------------------------
D.DEFAULT_WHISPER = "Hi $name! $guild is looking for friendly players to quest, run dungeons and raid with. Want an invite? Just reply \"invite\"."
D.DEFAULT_KEYWORDS = { "invite", "inv", "yes", "sure", "interested" }
D.MAX_KEYWORDS = 5
-- Replies that put someone on the Do Not Whisper list (whole words, any case)
D.DEFAULT_DNW_WORDS = { "dnw", "leave me alone", "do not whisper", "stop whispering", "not interested" }
D.WHISPER_MAX = 255

