--[[
    Nootropic Guild Manager - Who can craft it?
    The game doesn't let addons read another player's recipes, so each
    member's addon shares its own: whenever you open one of your profession
    windows, the recipes you've learned in it are read the same way the
    game's own window lists them (C_TradeSkillUI.GetFilteredRecipeIDs and
    GetRecipeInfo) and shared as sync record

      RP:<member>:<professionID> = "<profession name>;<id>,<id>,..."

    with recipe spell IDs in base 36 (about 4 bytes each). Every client turns
    an ID back into its name with C_Spell.GetSpellName, so names aren't sent.

    The window's filters (search text, "have materials") can hide recipes,
    so new ones are added to what's already shared rather than replacing it.
    A profession you no longer have is cleared.
]]
local _, ns = ...
local RCP = {}
ns.Recipes = RCP

RCP.MAX_PER_PROFESSION = 600 -- keeps one record within a few addon messages

local function Me() return ns.PlayerFullName() end

------------------------------------------------------------------------
-- Encoding
------------------------------------------------------------------------
local function Encode(name, ids)
    local list = {}
    for id in pairs(ids) do list[#list + 1] = id end
    table.sort(list)
    local out = {}
    for i, id in ipairs(list) do
        if i > RCP.MAX_PER_PROFESSION then break end
        out[i] = ns.Sync.Base36(id)
    end
    return (name or ""):gsub("[;,]", "") .. ";" .. table.concat(out, ",")
end

local function Decode(v)
    local name, rest = (v or ""):match("^([^;]*);(.*)$")
    if not name then return nil end
    local ids = {}
    for code in rest:gmatch("[^,]+") do
        local id = tonumber(code, 36)
        if id then ids[id] = true end
    end
    return name, ids
end
RCP.Encode, RCP.Decode = Encode, Decode

------------------------------------------------------------------------
-- Reading your own recipes (from your open profession window)
------------------------------------------------------------------------
local function Call(t, fn, ...)
    if t and t[fn] then
        local ok, a = pcall(t[fn], ...)
        if ok then return a end
    end
end

-- The profession the open window shows, if it's one of yours.
function RCP:OpenProfession()
    local T = C_TradeSkillUI
    if not T then return nil end
    -- someone else's list (a linked or NPC profession) isn't yours to share
    if Call(T, "IsNPCCrafting") or Call(T, "IsTradeSkillLinked") or Call(T, "IsTradeSkillGuild") then return nil end
    local base = Call(T, "GetBaseProfessionInfo")
    local child = Call(T, "GetChildProfessionInfo")
    local id = base and base.professionID
    if not id or id == 0 then return nil end
    return id, (base.professionName ~= "" and base.professionName) or (child and child.professionName), child and child.professionID
end

function RCP:Capture()
    if not (IsInGuild() and ns.DB:Guild() and ns.Sync.readyFor) then return end
    if not ns.Sharing:Get("recipes") then return end -- Options > Sharing
    local T = C_TradeSkillUI
    local profID, profName, childID = self:OpenProfession()
    if not (profID and T and T.GetFilteredRecipeIDs and T.GetRecipeInfo) then return end
    local key = ("RP:%s:%d"):format(Me(), profID)
    local _, ids = Decode(ns.Sync:Value(key) or "")
    ids = ids or {}
    local before = 0
    for _ in pairs(ids) do before = before + 1 end
    local list = Call(T, "GetFilteredRecipeIDs") or {}
    for _, recipeID in ipairs(list) do
        local info = Call(T, "GetRecipeInfo", recipeID)
        if info and info.learned then
            local inLine = true
            if T.IsRecipeInSkillLine then
                inLine = Call(T, "IsRecipeInSkillLine", recipeID, profID)
                    or (childID and Call(T, "IsRecipeInSkillLine", recipeID, childID)) or false
            end
            if inLine then ids[info.recipeID or recipeID] = true end
        end
    end
    local value = Encode(profName, ids)
    if value ~= (ns.Sync:Value(key) or "") then
        ns.Sync:Set(key, value)
        local after = 0
        for _ in pairs(ids) do after = after + 1 end
        if after > before and before > 0 then
            ns:Print(("Shared %d new %s recipe%s with the guild."):format(after - before, profName or "", after - before == 1 and "" or "s"))
        end
    end
end

-- Clears shared recipes for professions you no longer have.
function RCP:Prune()
    if not (IsInGuild() and ns.DB:Guild() and ns.Sync.readyFor) then return end
    local have = {}
    for _, p in ipairs(ns.Comm:Snapshot().profs or {}) do have[p.name:lower()] = true end
    if not next(have) then return end -- the game hasn't told us yet
    local prefix = "RP:" .. Me() .. ":"
    for key, rec in pairs(ns.Sync:Store("guild") or {}) do
        if key:sub(1, #prefix) == prefix and rec.v ~= "" then
            local name = Decode(rec.v)
            if name and not have[name:lower()] then ns.Sync:Set(key, "") end
        end
    end
end

------------------------------------------------------------------------
-- Looking up who can craft what
------------------------------------------------------------------------
local nameCache = {}
function RCP.RecipeName(id)
    local n = nameCache[id]
    if n == nil then
        n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)) or false
        nameCache[id] = n
    end
    return n or nil
end

-- The icon of what a recipe makes (the crafted item's), else the recipe
-- spell's own (recipes that make no item, like a campfire). On Forever many
-- crafting spells carry a placeholder icon, so the item's is the right one.
local iconCache = {}
function RCP.RecipeIcon(id)
    local icon = iconCache[id]
    if icon ~= nil then return icon or nil end
    local T = C_TradeSkillUI
    if T and T.GetRecipeSchematic then
        local ok, sch = pcall(T.GetRecipeSchematic, id, false)
        local item = ok and type(sch) == "table" and sch.outputItemID
        if item and C_Item and C_Item.GetItemIconByID then
            local ok2, i = pcall(C_Item.GetItemIconByID, item)
            if ok2 then icon = i end
        end
    end
    if not icon and T and T.GetRecipeOutputItemData then
        local ok, out = pcall(T.GetRecipeOutputItemData, id)
        if ok and type(out) == "table" and out.itemID then icon = out.icon end
    end
    icon = icon or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or nil
    -- (not cached while the game hasn't loaded the item yet: asked again later)
    if icon then iconCache[id] = icon end
    return icon
end

-- Every shared list: { { full, prof, ids }, ... }
function RCP:AllLists()
    local out = {}
    for key, rec in pairs(ns.Sync:Store("guild") or {}) do
        if key:sub(1, 3) == "RP:" and rec.v ~= "" then
            local member = key:match("^RP:([^:]+):")
            local prof, ids = Decode(rec.v)
            if member and prof then out[#out + 1] = { full = member, prof = prof, ids = ids } end
        end
    end
    return out
end

-- Recipes matching `query` (part of a recipe name, any case), or every
-- recipe of `member`: { { id, name, prof, crafters = { full... } }, ... }
-- sorted by name. Only guildmates still in the guild count as crafters.
function RCP:Search(query, member)
    query = ns.Trim(query or ""):lower()
    local byId, out = {}, {}
    for _, list in ipairs(self:AllLists()) do
        if (not member or list.full == member) and (member or ns.Roster.byName[list.full]) then
            for id in pairs(list.ids) do
                local name = RCP.RecipeName(id)
                if name and (query == "" or name:lower():find(query, 1, true)) then
                    local r = byId[id]
                    if not r then
                        r = { id = id, name = name, prof = list.prof, crafters = {} }
                        byId[id] = r
                        out[#out + 1] = r
                    end
                    r.crafters[#r.crafters + 1] = list.full
                end
            end
        end
    end
    local function online(full) local e = ns.Roster.byName[full]; return e and e.online end
    for _, r in ipairs(out) do
        table.sort(r.crafters, function(a, b)
            local oa, ob = online(a), online(b)
            if oa ~= ob then return oa and true or false end
            return a < b
        end)
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- How many recipes `member` shares (all professions).
function RCP:Count(member)
    local n = 0
    for _, list in ipairs(self:AllLists()) do
        if list.full == member then for _ in pairs(list.ids) do n = n + 1 end end
    end
    return n
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
function RCP:Init()
    local function queue() ns.Debounce("recipecapture", 1, ns.Safe(function() RCP:Capture() end, "Recipes")) end
    ns:RegisterEvent("TRADE_SKILL_SHOW", queue)
    ns:RegisterEvent("TRADE_SKILL_LIST_UPDATE", queue)
    ns:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", queue)
    ns:RegisterEvent("SKILL_LINES_CHANGED", function()
        ns.Debounce("recipeprune", 5, ns.Safe(function() RCP:Prune() end, "Recipes"))
    end)
    C_Timer.After(30, ns.Safe(function() RCP:Prune() end, "Recipes"))
end
