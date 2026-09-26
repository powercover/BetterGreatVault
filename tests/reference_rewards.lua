-- Reference loot scanner used only by `python scenarios.py --reference`, to show the harness passes
-- for a design that isolates its scans (it replaces the addon's public BGV.Rewards loot functions).
-- It follows the planned fix: detach the Adventure Guide's two journal events, save the journal
-- state, per instance select -> validate/set difficulty -> per boss select + read, then restore the
-- guide's instance, difficulty, boss and filters and reattach the events, all synchronously.

local _, BGV = ...
local R = BGV.Rewards
local Utils = BGV.Utils

local GUIDE_EVENTS = { "EJ_DIFFICULTY_UPDATE", "EJ_LOOT_DATA_RECIEVED" }
local VAULT_EQUIP = {
    INVTYPE_HEAD = true, INVTYPE_NECK = true, INVTYPE_SHOULDER = true, INVTYPE_CLOAK = true,
    INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true, INVTYPE_WEAPON = true, INVTYPE_SHIELD = true, INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
}
local RANK = { [17] = 1, [14] = 2, [15] = 3, [16] = 4 }

local batches = {}
local scanning = false

if type(R.ShowingWeeklyProgress) ~= "function" then
    function R.ShowingWeeklyProgress()
        return not C_WeeklyRewards.CanClaimRewards() and not C_WeeklyRewards.HasGeneratedRewards()
    end
end

function R.IsScanning()
    return scanning
end

function R.InvalidateIcons()
    batches = {}
end

local function IsGear(itemID)
    local _, _, _, equipLoc, _, classID = GetItemInfoInstant(itemID)
    return (classID == 2 or classID == 4) and VAULT_EQUIP[equipLoc] == true
end

-- `python scenarios.py --naive`: the same reader without isolation (no detach, no restore), the
-- old design's failure mode, to show the checks catch it.
local naive = rawget(_G, "BGV_REFERENCE_NAIVE") == true

local function WithScan(fn)
    if naive then
        local _, _, classID = UnitClass("player")
        EJ_SetLootFilter(classID, Utils.LootSpecID())
        C_EncounterJournal.ResetSlotFilter()
        scanning = true
        local ok, err = pcall(fn)
        scanning = false
        if not ok then
            error(err, 0)
        end
        return
    end
    local guide = EncounterJournal
    local detached = {}
    if guide then
        for _, event in ipairs(GUIDE_EVENTS) do
            if guide:IsEventRegistered(event) then
                guide:UnregisterEvent(event)
                detached[#detached + 1] = event
            end
        end
    end
    scanning = true
    local saved = {
        difficulty = EJ_GetDifficulty(),
        slot = C_EncounterJournal.GetSlotFilter(),
        instance = guide and guide.instanceID,
        encounter = guide and guide.encounterID,
    }
    saved.classID, saved.specID = EJ_GetLootFilter()
    local _, _, classID = UnitClass("player")
    local specID = Utils.LootSpecID()
    if saved.classID ~= classID or saved.specID ~= specID then
        EJ_SetLootFilter(classID, specID)
    end
    if saved.slot ~= Enum.ItemSlotFilterType.NoFilter then
        C_EncounterJournal.ResetSlotFilter()
    end
    local ok, err = pcall(fn)
    if saved.instance then
        EJ_SelectInstance(saved.instance)
    end
    if EJ_GetDifficulty() ~= saved.difficulty then
        EJ_SetDifficulty(saved.difficulty)
    end
    if saved.encounter then
        EJ_SelectEncounter(saved.encounter)
    end
    local nowClass, nowSpec = EJ_GetLootFilter()
    if nowClass ~= saved.classID or nowSpec ~= saved.specID then
        EJ_SetLootFilter(saved.classID, saved.specID)
    end
    if C_EncounterJournal.GetSlotFilter() ~= saved.slot then
        C_EncounterJournal.SetSlotFilter(saved.slot)
    end
    scanning = false
    for _, event in ipairs(detached) do
        guide:RegisterEvent(event)
    end
    if not ok then
        error(err, 0)
    end
end

local function BatchKey(instanceID, difficultyID, bossSet)
    local ids = {}
    for bossID in pairs(bossSet or {}) do
        ids[#ids + 1] = bossID
    end
    table.sort(ids)
    return table.concat({ instanceID, difficultyID, tostring(Utils.LootSpecID()), table.concat(ids, ",") }, ":")
end

local function ReadInstance(instanceID, difficultyID, bossSet)
    EJ_SelectInstance(instanceID)
    if not EJ_IsValidInstanceDifficulty(difficultyID) then
        return {}, false
    end
    if EJ_GetDifficulty() ~= difficultyID then
        EJ_SetDifficulty(difficultyID)
    end
    local entries, seen, pending = {}, {}, false
    local index = 1
    while true do
        local _, _, bossID = EJ_GetEncounterInfoByIndex(index, instanceID)
        if not bossID then
            break
        end
        if not bossSet or bossSet[bossID] then
            EJ_SelectEncounter(bossID)
            local count = EJ_GetNumLoot() or 0
            if count == 0 and EJ_IsLootListOutOfDate() then
                pending = true
            end
            for row = 1, count do
                local info = C_EncounterJournal.GetLootInfoByIndex(row)
                local itemID = info and info.itemID
                if itemID and not seen[itemID] and IsGear(itemID) then
                    local name = C_Item.GetItemInfo(itemID)
                    if type(name) == "string" and name ~= "" then
                        seen[itemID] = true
                        entries[#entries + 1] = {
                            itemID = itemID,
                            name = name,
                            icon = C_Item.GetItemIconByID(itemID),
                            encounterID = info.encounterID,
                        }
                    else
                        pending = true
                    end
                end
            end
        end
        index = index + 1
    end
    return entries, pending
end

local function Collect(jobs)
    local entries, seen, pending = {}, {}, false
    local todo = {}
    for _, job in ipairs(jobs) do
        job.key = BatchKey(job.instanceID, job.difficultyID, job.bossSet)
        if not batches[job.key] then
            todo[#todo + 1] = job
        end
    end
    if #todo > 0 then
        WithScan(function()
            for _, job in ipairs(todo) do
                local batch, batchPending = ReadInstance(job.instanceID, job.difficultyID, job.bossSet)
                if batchPending then
                    pending = true
                else
                    batches[job.key] = batch
                end
            end
        end)
    end
    for _, job in ipairs(jobs) do
        for _, entry in ipairs(batches[job.key] or {}) do
            if not seen[entry.itemID] then
                seen[entry.itemID] = true
                entries[#entries + 1] = entry
            end
        end
    end
    return entries, pending
end

local function RaidJobs(slot)
    local want = RANK[slot.level] or 0
    local byInstance, order = {}, {}
    for _, encounter in ipairs(slot.encounters or {}) do
        local key = encounter.journalInstanceID
        if not byInstance[key] then
            byInstance[key] = {}
            order[#order + 1] = key
        end
        table.insert(byInstance[key], encounter)
    end
    local jobs = {}
    for _, instanceID in ipairs(order) do
        local list = byInstance[instanceID]
        local function Counts(encounter)
            return encounter.defeated and (want == 0 or (RANK[encounter.difficultyID] or 0) >= want)
        end
        local furthest
        for _, encounter in ipairs(list) do
            if Counts(encounter) and (not furthest or encounter.uiOrder > furthest) then
                furthest = encounter.uiOrder
            end
        end
        local bossSet = {}
        for _, encounter in ipairs(list) do
            if (furthest and encounter.uiOrder <= furthest) or Counts(encounter) then
                bossSet[encounter.journalEncounterID] = true
            end
        end
        if next(bossSet) then
            jobs[#jobs + 1] = { instanceID = instanceID, difficultyID = slot.level, bossSet = bossSet }
        end
    end
    return jobs
end

local function DungeonJobs(slot)
    local maps = C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then
        return nil
    end
    local difficultyID = Utils.IsHeroicDungeonTier(slot.activityTierID) and DifficultyUtil.ID.DungeonHeroic or 8
    local jobs = {}
    for _, mapID in ipairs(maps) do
        local gameMapID = select(6, C_ChallengeMode.GetMapUIInfo(mapID))
        local instanceID = gameMapID and C_EncounterJournal.GetInstanceForGameMap(gameMapID)
        if not instanceID then
            return nil
        end
        jobs[#jobs + 1] = { instanceID = instanceID, difficultyID = difficultyID }
    end
    return jobs
end

local function WorldItems()
    local entries, pending = {}, false
    local specID = Utils.LootSpecID()
    for _, itemID in ipairs(BGV.WorldLoot or {}) do
        if IsGear(itemID) then
            local specs = GetItemSpecInfo(itemID)
            if type(specs) ~= "table" then
                pending = true
            else
                local usable = false
                for _, id in ipairs(specs) do
                    usable = usable or id == specID
                end
                if usable then
                    local name = C_Item.GetItemInfo(itemID)
                    if type(name) == "string" then
                        entries[#entries + 1] = { itemID = itemID, name = name, icon = C_Item.GetItemIconByID(itemID) }
                    else
                        pending = true
                    end
                end
            end
        end
    end
    return entries, pending
end

function R.ItemsForSlot(slot)
    if type(slot) ~= "table" or not slot.unlocked then
        return {}
    end
    if Utils.SameType(slot.type, Utils.ThresholdType("Raid")) then
        return Collect(RaidJobs(slot))
    elseif Utils.SameType(slot.type, Utils.ThresholdType("Activities")) then
        local jobs = DungeonJobs(slot)
        if not jobs then
            return {}, true
        end
        return Collect(jobs)
    elseif Utils.SameType(slot.type, Utils.ThresholdType("World")) then
        return WorldItems()
    end
    return {}
end

function R.PossibleIcons(slot)
    if type(slot) ~= "table" or not slot.unlocked or not R.ShowingWeeklyProgress() then
        return {}
    end
    local entries, pending = R.ItemsForSlot(slot)
    local icons = {}
    local limit = Utils.SameType(slot.type, Utils.ThresholdType("World")) and 20 or nil
    for _, entry in ipairs(entries) do
        if limit and #icons >= limit then
            break
        end
        icons[#icons + 1] = { itemID = entry.itemID, icon = entry.icon }
    end
    return icons, pending == true
end
