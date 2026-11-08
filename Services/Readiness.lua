--[[
    Nootropic Guild Manager - Raid readiness
    What each character still needs before the raids, worked out by their
    own addon (the game doesn't let addons read anyone else's quests or bags)
    and shared as sync record

      RR:<member> = "ony,brooch"   the checks they've completed

    Checks (ns.Data.READINESS, sources on Wowhead's WoW Forever database):
      ony      Onyxia's Lair needs the Drakefire Amulet (item 16309), the
               reward of "Blood of the Black Dragon Champion" (quest 6602,
               Horde) or "Drakefire Amulet" (quest 6502, Alliance). Done when
               either quest is completed or the amulet is in your bags/bank.
      brooch   The Brooch of the Wardens opens the Vord'anaar Prison inside
               The Barrow Deeps. Its item ID wasn't published at launch, so
               it's found in your bags by name (English clients) and its ID
               is remembered from then on, which also covers the bank.
    The Barrow Deeps and Hyjal Summit need no attunement.
]]
local _, ns = ...
local RD = {}
ns.Readiness = RD

local function Me() return ns.PlayerFullName() end

local function QuestDone(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        return ok and done and true or false
    end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
    return false
end

local function ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return 0 end
    local ok, n = pcall(fn, id, true) -- true: bank too
    return ok and n or 0
end

-- An item in your bags by its (English) name: its ID, or nil.
local function FindInBags(name)
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        local slots = C.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            if link and link:find("[" .. name .. "]", 1, true) then return info.itemID end
        end
    end
end

-- The item IDs found by name (account-wide, so every character benefits).
local function KnownIds()
    local s = ns.DB:Settings()
    s.knownItemIds = s.knownItemIds or {}
    return s.knownItemIds
end

function RD:Check(def)
    for _, q in ipairs(def.quests or {}) do
        if QuestDone(q) then return true end
    end
    if def.item and ItemCount(def.item) > 0 then return true end
    if def.itemName then
        local known = KnownIds()[def.itemName]
        if known and ItemCount(known) > 0 then return true end
        local found = FindInBags(def.itemName)
        if found then
            KnownIds()[def.itemName] = found
            return true
        end
    end
    return false
end

-- Your completed checks, as the shared value ("ony,brooch").
function RD:MyValue()
    local done = {}
    for _, def in ipairs(ns.Data.READINESS) do
        if def.key and self:Check(def) then done[#done + 1] = def.key end
    end
    return table.concat(done, ",")
end

function RD:Publish()
    if not (IsInGuild() and ns.DB:Guild() and ns.Sync.readyFor) then return end
    local me = Me()
    local value = self:MyValue()
    -- "" would read as "never checked": write a marker for "checked, none yet"
    if value == "" then value = "-" end
    if (ns.Sync:Value("RR:" .. me) or "") ~= value then ns.Sync:Set("RR:" .. me, value) end
end

-- A member's checks: { [key] = true }, or nil when their addon never said.
function RD:For(full)
    local v = ns.Sync:Value("RR:" .. full)
    if not v or v == "" then return nil end
    local set = {}
    for k in v:gmatch("[^,]+") do
        if k ~= "-" then set[k] = true end -- "-" = checked, nothing done yet
    end
    return set
end

function RD:Init()
    local function queue() ns.Debounce("readiness", 3, ns.Safe(function() RD:Publish() end, "Readiness")) end
    ns:RegisterEvent("QUEST_TURNED_IN", queue)
    ns:RegisterEvent("BAG_UPDATE_DELAYED", queue)
    ns:RegisterEvent("BANKFRAME_OPENED", queue)
    C_Timer.After(25, queue)
end
