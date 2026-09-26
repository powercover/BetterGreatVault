local _, BGV = ...

BGV.Rewards = {}

local Rewards = BGV.Rewards
local Utils = BGV.Utils

local function QualityName(quality)
    if not Utils.IsUsableNumber(quality) then
        return nil
    end

    local key = "ITEM_QUALITY" .. quality .. "_DESC"
    local name = _G[key]
    if type(name) == "string" and name ~= "" then
        return name
    end
end

local function ItemInfoFromLink(link)
    local info = { link = link }
    if not Utils.IsUsableString(link) or not (C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function") then
        return info
    end

    local itemLevel = Utils.Call(C_Item.GetDetailedItemLevelInfo, link)
    if Utils.IsUsableNumber(itemLevel) and itemLevel > 0 then
        info.itemLevel = itemLevel
    end

    if type(C_Item.GetItemInfo) == "function" then
        local _, _, quality = Utils.Call(C_Item.GetItemInfo, link)
        info.quality = Utils.IsUsableNumber(quality) and quality or nil
        info.qualityName = QualityName(info.quality)
    end

    if type(C_Item.GetItemUpgradeInfo) == "function" then
        local upgrade = Utils.Call(C_Item.GetItemUpgradeInfo, link)
        if type(upgrade) == "table" then
            if Utils.IsUsableString(upgrade.trackString) then
                info.upgradeTrack = upgrade.trackString
            end
            if Utils.IsUsableNumber(upgrade.currentLevel) then
                info.upgradeLevel = upgrade.currentLevel
            end
            if Utils.IsUsableNumber(upgrade.maxLevel) and upgrade.maxLevel > 0 then
                info.upgradeMax = upgrade.maxLevel
            end
        end
    end

    if type(C_Item.GetItemIconByID) == "function" then
        local icon = Utils.Call(C_Item.GetItemIconByID, link)
        if icon and not Utils.IsSecret(icon) then
            info.icon = icon
        end
    end

    return info
end

local function WatchItem(link, onReady)
    if not onReady or type(Item) ~= "table" or type(Item.CreateFromItemLink) ~= "function" then
        return
    end

    local item = Utils.Call(Item.CreateFromItemLink, Item, link)
    if not item or type(item.ContinueOnLoad) ~= "function" then
        return
    end

    if type(item.IsItemDataCached) == "function" and item:IsItemDataCached() then
        return
    end

    item:ContinueOnLoad(function()
        local info = ItemInfoFromLink(link)
        if info.itemLevel or info.qualityName or info.upgradeTrack then
            onReady(info)
        end
    end)
end

local function BestRewardLink(activity)
    if type(activity) ~= "table" or type(activity.rewards) ~= "table" then
        return nil
    end

    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetItemHyperlink) == "function") then
        return nil
    end

    local bestLink
    local bestLevel = -1

    for _, reward in ipairs(activity.rewards) do
        local itemDBID = type(reward) == "table" and reward.itemDBID or nil
        if itemDBID ~= nil and not Utils.IsSecret(itemDBID) then
            local isKeystone = false
            if C_Item and type(C_Item.IsItemKeystoneByID) == "function" and Utils.IsUsableNumber(reward.id) then
                isKeystone = Utils.Call(C_Item.IsItemKeystoneByID, reward.id) == true
            end

            if not isKeystone then
                local link = Utils.Call(C_WeeklyRewards.GetItemHyperlink, itemDBID)
                local info = ItemInfoFromLink(link)
                if info.itemLevel and info.itemLevel > bestLevel then
                    bestLevel = info.itemLevel
                    bestLink = link
                elseif Utils.IsUsableString(link) and not bestLink then
                    bestLink = link
                end
            end
        end
    end

    return bestLink
end

local function ExampleRewardLink(activity)
    if type(activity) ~= "table" or not Utils.IsUsableNumber(activity.id) then
        return nil
    end

    if not Utils.IsUsableNumber(activity.progress) or not Utils.IsUsableNumber(activity.threshold) then
        return nil
    end

    -- Example links describe the unlocked reward. Locked slots do not have a final item level yet.
    if activity.progress < activity.threshold then
        return nil
    end

    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetExampleRewardItemHyperlinks) == "function") then
        return nil
    end

    return Utils.Call(C_WeeklyRewards.GetExampleRewardItemHyperlinks, activity.id)
end

local MYTHIC_VAULT_ILVL = 334
local MYTHIC_VAULT_STEP = 6

local function RaidMythicID()
    local ids = DifficultyUtil and DifficultyUtil.ID
    if ids and Utils.IsUsableNumber(ids.PrimaryRaidMythic) then
        return ids.PrimaryRaidMythic
    end
    if Enum and Enum.Difficulty and Utils.IsUsableNumber(Enum.Difficulty.Mythic) then
        return Enum.Difficulty.Mythic
    end
    return 16
end

local function IsEndBossBand(info)
    if Utils.IsUsableNumber(info.upgradeLevel) and info.upgradeLevel > MYTHIC_VAULT_STEP then
        return true
    end
    return Utils.IsUsableNumber(info.itemLevel) and info.itemLevel > MYTHIC_VAULT_ILVL
end

-- Last two bosses of the multi-boss raid. A one-boss lair does not unlock 9/6.
local function MythicEndBossKilled(encounters)
    if type(encounters) ~= "table" then
        return false
    end

    local byInstance = {}
    for _, encounter in ipairs(encounters) do
        if type(encounter) == "table" then
            local key = encounter.journalInstanceID or encounter.instanceID or 0
            local list = byInstance[key]
            if not list then
                list = {}
                byInstance[key] = list
            end
            list[#list + 1] = encounter
        end
    end

    local raid
    for _, list in pairs(byInstance) do
        if not raid or #list > #raid then
            raid = list
        end
    end
    if not raid or #raid < 3 then
        return false
    end

    table.sort(raid, function(left, right)
        return (left.uiOrder or 0) > (right.uiOrder or 0)
    end)

    local mythicID = RaidMythicID()
    for index = 1, 2 do
        local encounter = raid[index]
        local difficulty = encounter and encounter.difficultyID
        if Utils.IsUsableNumber(difficulty) and difficulty >= mythicID then
            return true
        end
    end
    return false
end

local function CapRaidReward(activity, info)
    if type(activity) ~= "table" or type(info) ~= "table" or not IsEndBossBand(info) then
        return info
    end
    if not Utils.SameType(activity.type, Utils.ThresholdType("Raid")) then
        return info
    end
    if activity.level ~= RaidMythicID() or MythicEndBossKilled(activity.bgvEncounters) then
        return info
    end

    info.itemLevel = MYTHIC_VAULT_ILVL
    info.upgradeLevel = MYTHIC_VAULT_STEP
    if not Utils.IsUsableNumber(info.upgradeMax) or info.upgradeMax < MYTHIC_VAULT_STEP then
        info.upgradeMax = MYTHIC_VAULT_STEP
    end
    return info
end

function Rewards.ResolveReward(activity, onReady)
    local link = BestRewardLink(activity) or ExampleRewardLink(activity)
    if not link then
        return nil
    end

    local info = ItemInfoFromLink(link)
    info = CapRaidReward(activity, info)
    if info.itemLevel or info.qualityName or info.upgradeTrack then
        return info
    end

    WatchItem(link, function(ready)
        if onReady then
            onReady(CapRaidReward(activity, ready))
        end
    end)
    return nil
end

-- Next breakpoint from season data. This is an upgrade, not the current slot reward.
function Rewards.GetNextIncrease(activity)
    if type(activity) ~= "table" then
        return nil
    end

    if not Utils.IsUsableNumber(activity.activityTierID) or not Utils.IsUsableNumber(activity.level) then
        return nil
    end

    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetNextActivitiesIncrease) == "function") then
        return nil
    end

    local hasSeasonData, nextActivityTierID, nextLevel, itemLevel =
        Utils.Call(C_WeeklyRewards.GetNextActivitiesIncrease, activity.activityTierID, activity.level)

    if hasSeasonData ~= true then
        return nil
    end

    if not Utils.IsUsableNumber(nextLevel) and not Utils.IsUsableNumber(itemLevel) then
        return nil
    end

    return {
        nextActivityTierID = Utils.IsUsableNumber(nextActivityTierID) and nextActivityTierID or nil,
        nextLevel = Utils.IsUsableNumber(nextLevel) and nextLevel or nil,
        itemLevel = Utils.IsUsableNumber(itemLevel) and itemLevel or nil,
    }
end

local iconLists = {}
local journalBatches = {}
local iconBatches = {}
local specKnown = {}
local specAnswers = {}

function Rewards.InvalidateIcons()
    iconLists = {}
    journalBatches = {}
    iconBatches = {}
    specKnown = {}
    specAnswers = {}
end

local function LiveJournalBudget()
    return type(debugprofilestop) == "function"
end

local function AllowJournalSelect(budget)
    if not budget or not LiveJournalBudget() then
        return true
    end
    if budget.used >= 1 then
        return false
    end
    budget.used = budget.used + 1
    return true
end

local function JournalBatchKey(difficultyID, instanceID, encounterSet, specID)
    local encounterKey = ""
    if type(encounterSet) == "table" then
        local ids = {}
        for encounterID in pairs(encounterSet) do
            ids[#ids + 1] = tostring(encounterID)
        end
        table.sort(ids)
        encounterKey = table.concat(ids, ",")
    end
    return table.concat({
        tostring(difficultyID),
        tostring(instanceID),
        tostring(specID),
        encounterKey,
    }, ":")
end

function Rewards.ShowingWeeklyProgress()
    if not C_WeeklyRewards then
        return false
    end
    if type(C_WeeklyRewards.CanClaimRewards) == "function" and C_WeeklyRewards.CanClaimRewards() then
        return false
    end
    if type(C_WeeklyRewards.HasGeneratedRewards) == "function" and C_WeeklyRewards.HasGeneratedRewards() then
        return false
    end
    return true
end

function Rewards.EnsureJournal()
    if type(EJ_SelectInstance) == "function" and type(EJ_GetNumLoot) == "function" then
        return true
    end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif type(LoadAddOn) == "function" then
        LoadAddOn("Blizzard_EncounterJournal")
    end
    return type(EJ_SelectInstance) == "function" and type(EJ_GetNumLoot) == "function"
end

local VAULT_EQUIP = {
    INVTYPE_HEAD = true,
    INVTYPE_NECK = true,
    INVTYPE_SHOULDER = true,
    INVTYPE_CLOAK = true,
    INVTYPE_CHEST = true,
    INVTYPE_ROBE = true,
    INVTYPE_WRIST = true,
    INVTYPE_HAND = true,
    INVTYPE_WAIST = true,
    INVTYPE_LEGS = true,
    INVTYPE_FEET = true,
    INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true,
    INVTYPE_WEAPON = true,
    INVTYPE_SHIELD = true,
    INVTYPE_RANGED = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
}

local function IsVaultGear(itemID)
    if not Utils.IsUsableNumber(itemID) or type(GetItemInfoInstant) ~= "function" then
        return false
    end
    local _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstant(itemID)
    local weaponClass = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
    local armorClass = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
    if not Utils.IsUsableNumber(classID) or type(equipLoc) ~= "string" then
        return true
    end
    if classID ~= weaponClass and classID ~= armorClass then
        return false
    end
    local cosmetic = Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic
    if cosmetic and classID == armorClass and subClassID == cosmetic then
        return false
    end
    return type(equipLoc) == "string" and VAULT_EQUIP[equipLoc] == true
end

local function InEncounterPool(encounterSet, encounterID)
    if not encounterSet then
        return true
    end
    return Utils.IsUsableNumber(encounterID) and encounterID ~= 0 and encounterSet[encounterID] == true
end

local function AddInstanceIcons(instanceID, icons, seen, encounterSet, difficultyID)
    if not Utils.IsUsableNumber(instanceID) or type(EJ_SelectInstance) ~= "function" or type(EJ_GetNumLoot) ~= "function" then
        return
    end
    if not (C_EncounterJournal and type(C_EncounterJournal.GetLootInfoByIndex) == "function") then
        return
    end

    EJ_SelectInstance(instanceID)
    if difficultyID and type(EJ_SetDifficulty) == "function" then
        EJ_SetDifficulty(difficultyID)
    end
    if type(EJ_IsLootListOutOfDate) == "function" and EJ_IsLootListOutOfDate() then
        return true
    end
    local unresolved = false
    local count = EJ_GetNumLoot() or 0
    for index = 1, count do
        local info = Utils.Call(C_EncounterJournal.GetLootInfoByIndex, index)
        local encounterID = type(info) == "table" and info.encounterID or nil
        local fromSlot = InEncounterPool(encounterSet, encounterID)
        if type(info) == "table" and fromSlot and not info.handError and not info.weaponTypeError then
            local itemID = info.itemID
            if info.icon and info.icon ~= 0 and IsVaultGear(itemID) and Utils.IsUsableNumber(itemID) then
                if not seen[itemID] then
                    seen[itemID] = true
                    icons[#icons + 1] = {
                        itemID = itemID,
                        icon = info.icon,
                    }
                end
            elseif info.name or info.icon or info.encounterID or itemID then
                unresolved = true
            end
        end
    end
    return unresolved
end

local function CollectIcons(difficultyID, instanceIDs, encounterSet)
    if not Rewards.EnsureJournal() or type(EJ_SetLootFilter) ~= "function" or type(instanceIDs) ~= "table" or #instanceIDs == 0 then
        return {}, not Rewards.EnsureJournal()
    end

    local _, _, classID = UnitClass("player")
    local specID = Utils.LootSpecID()
    local oldClass, oldSpec
    if type(EJ_GetLootFilter) == "function" then
        oldClass, oldSpec = EJ_GetLootFilter()
    end
    local oldDifficulty = type(EJ_GetDifficulty) == "function" and EJ_GetDifficulty() or nil

    if type(EJ_ResetLootFilter) == "function" then
        EJ_ResetLootFilter()
    end
    if C_EncounterJournal and type(C_EncounterJournal.ResetSlotFilter) == "function" then
        C_EncounterJournal.ResetSlotFilter()
    end
    if classID and specID then
        EJ_SetLootFilter(classID, specID)
    end
    if difficultyID and type(EJ_SetDifficulty) == "function" then
        EJ_SetDifficulty(difficultyID)
    end

    local icons = {}
    local seen = {}
    local pending = false
    local budget = { used = 0 }
    for _, instanceID in ipairs(instanceIDs) do
        local batchKey = JournalBatchKey(difficultyID, instanceID, encounterSet, specID)
        local cached = iconBatches[batchKey]
        if cached then
            for _, icon in ipairs(cached) do
                local itemID = icon.itemID
                if not itemID or not seen[itemID] then
                    if itemID then
                        seen[itemID] = true
                    end
                    icons[#icons + 1] = icon
                end
            end
        elseif not AllowJournalSelect(budget) then
            pending = true
            break
        else
            local startCount = #icons
            if AddInstanceIcons(instanceID, icons, seen, encounterSet, difficultyID) then
                pending = true
            else
                local batch = {}
                for index = startCount + 1, #icons do
                    batch[#batch + 1] = icons[index]
                end
                iconBatches[batchKey] = batch
            end
        end
    end

    if oldClass and type(EJ_SetLootFilter) == "function" then
        EJ_SetLootFilter(oldClass, oldSpec or 0)
    elseif type(EJ_ResetLootFilter) == "function" then
        EJ_ResetLootFilter()
    end
    if oldDifficulty and type(EJ_SetDifficulty) == "function" then
        EJ_SetDifficulty(oldDifficulty)
    end

    return icons, pending
end

local RAID_RANK = {
    [17] = 1,
    [14] = 2,
    [15] = 3,
    [16] = 4,
}

local function RaidScope(slot)
    local ids = {}
    local seen = {}
    local encounters = {}
    local names = {}
    local ceiling = {}
    local rewardRank = RAID_RANK[slot.level] or 0
    if type(slot.encounters) ~= "table" then
        return ids, encounters, names, ceiling
    end

    local function AddID(encounterID)
        if Utils.IsUsableNumber(encounterID) then
            encounters[encounterID] = true
        end
    end

    local function AddInstance(instanceID)
        if Utils.IsUsableNumber(instanceID) and not seen[instanceID] then
            seen[instanceID] = true
            ids[#ids + 1] = instanceID
        end
    end

    local function AddEncounter(encounter)
        AddID(encounter.journalEncounterID)
        AddID(encounter.dungeonEncounterID)
        AddID(encounter.activityEncounterID)
        AddInstance(encounter.journalInstanceID)
        if type(encounter.name) == "string" then
            local function Remember(encounterID)
                if Utils.IsUsableNumber(encounterID) then
                    names[encounterID] = encounter.name
                end
            end
            Remember(encounter.journalEncounterID)
            Remember(encounter.dungeonEncounterID)
            Remember(encounter.activityEncounterID)
        end
    end

    -- The vault's ceiling reward (above the season's normal Mythic cap) can only ever come
    -- from the raid's last two bosses in Journal order, and only if that specific boss was
    -- itself killed at Mythic or higher. Earlier bosses stay at the normal cap even once the
    -- slot overall is eligible for the ceiling. Mark those specific bosses here so
    -- StampReward can cap every other entry back down regardless of the slot's own reward.
    local function MarkCeilingEncounter(encounter)
        local mythicID = RaidMythicID()
        if not (Utils.IsUsableNumber(encounter.difficultyID) and encounter.difficultyID >= mythicID) then
            return
        end
        local function Mark(encounterID)
            if Utils.IsUsableNumber(encounterID) then
                ceiling[encounterID] = true
            end
        end
        Mark(encounter.journalEncounterID)
        Mark(encounter.dungeonEncounterID)
        Mark(encounter.activityEncounterID)
    end

    local function CountsForSlot(encounter)
        local bossRank = RAID_RANK[encounter.difficultyID] or 0
        return encounter.defeated and (rewardRank == 0 or bossRank >= rewardRank)
    end

    local byInstance = {}
    local groupOrder = {}
    for _, encounter in ipairs(slot.encounters) do
        local key = encounter.journalInstanceID or encounter.instanceID or 0
        local list = byInstance[key]
        if not list then
            list = {}
            byInstance[key] = list
            groupOrder[#groupOrder + 1] = key
        end
        list[#list + 1] = encounter
    end

    for _, key in ipairs(groupOrder) do
        local list = byInstance[key]
        local furthest
        for _, encounter in ipairs(list) do
            if CountsForSlot(encounter) and Utils.IsUsableNumber(encounter.uiOrder) then
                if not furthest or encounter.uiOrder > furthest then
                    furthest = encounter.uiOrder
                end
            end
        end
        for _, encounter in ipairs(list) do
            local inPool = furthest and Utils.IsUsableNumber(encounter.uiOrder) and encounter.uiOrder <= furthest
            if inPool or CountsForSlot(encounter) then
                AddEncounter(encounter)
            end
        end

        if #list >= 3 then
            local lastTwo = {}
            for _, encounter in ipairs(list) do
                lastTwo[#lastTwo + 1] = encounter
            end
            table.sort(lastTwo, function(left, right)
                return (left.uiOrder or 0) > (right.uiOrder or 0)
            end)
            for index = 1, 2 do
                if lastTwo[index] then
                    MarkCeilingEncounter(lastTwo[index])
                end
            end
        end
    end

    return ids, encounters, names, ceiling
end

-- Single pass over the season's challenge maps: returns both the deduped instance ID
-- list (which dungeons to scan for loot) and an instanceID -> display name map, instead
-- of walking C_ChallengeMode.GetMapTable() and calling GetMapUIInfo per map twice over.
local function MythicPlusMapInfo()
    local ids = {}
    local names = {}
    local seen = {}
    Rewards.EnsureJournal()
    if type(EJ_GetCurrentTier) == "function" and type(EJ_SelectTier) == "function" then
        local tier = EJ_GetCurrentTier()
        if tier then
            EJ_SelectTier(tier)
        end
    end

    local function AddInstance(instanceID)
        if Utils.IsUsableNumber(instanceID) and instanceID > 0 and not seen[instanceID] then
            seen[instanceID] = true
            ids[#ids + 1] = instanceID
        end
    end

    if type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local maps = Utils.Call(C_ChallengeMode.GetMapTable)
        if type(maps) == "table" then
            for _, mapID in ipairs(maps) do
                local name, infoID, _, _, _, uiMapID = Utils.Call(C_ChallengeMode.GetMapUIInfo, mapID)
                local resolvedID
                if Utils.IsUsableNumber(uiMapID) and type(EJ_GetInstanceForMap) == "function" then
                    local instanceID = Utils.Call(EJ_GetInstanceForMap, uiMapID)
                    if Utils.IsUsableNumber(instanceID) and instanceID > 0 then
                        AddInstance(instanceID)
                        resolvedID = resolvedID or instanceID
                    end
                end
                if Utils.IsUsableNumber(infoID) and infoID ~= mapID and type(EJ_GetInstanceForMap) == "function" then
                    local instanceID = Utils.Call(EJ_GetInstanceForMap, infoID)
                    if Utils.IsUsableNumber(instanceID) and instanceID > 0 then
                        AddInstance(instanceID)
                        resolvedID = resolvedID or instanceID
                    end
                end
                if resolvedID and Utils.IsUsableString(name) and not names[resolvedID] then
                    names[resolvedID] = name
                end
            end
        end
    end

    if type(EJ_GetInstanceByIndex) == "function" then
        for index = 1, 40 do
            local instanceID = EJ_GetInstanceByIndex(index, false)
            if not instanceID then
                break
            end
            AddInstance(instanceID)
        end
    end

    return ids, names
end

local function SpecCanUse(itemID, specID)
    if type(GetItemSpecInfo) ~= "function" or not specID then
        return true
    end
    local specs = GetItemSpecInfo(itemID)
    if type(specs) ~= "table" then
        if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end
    for _, id in ipairs(specs) do
        if id == specID then
            return true
        end
    end
    return false
end

local WORLD_REEL_LIMIT = 20

local function SampleIcons(icons, limit)
    local count = #icons
    if count == 0 then
        return icons
    end
    if count > limit then
        count = limit
    end
    local pool = {}
    for index = 1, #icons do
        pool[index] = icons[index]
    end
    for index = #pool, 2, -1 do
        local swap = math.random(index)
        pool[index], pool[swap] = pool[swap], pool[index]
    end
    local sample = {}
    for index = 1, count do
        sample[index] = pool[index]
    end
    return sample
end

local function ShuffleIcons(icons)
    if #icons < 2 then
        return icons
    end
    local order = {}
    for index = 1, #icons do
        order[index] = icons[index]
    end
    for index = #order, 2, -1 do
        local swap = math.random(index)
        order[index], order[swap] = order[swap], order[index]
    end
    return order
end

local function IconIdentity(icon)
    if type(icon) ~= "table" then
        return nil
    end
    return icon.itemID or icon.icon
end

local function StableOrder(slotKey, icons, pending, limit)
    local cached = iconLists[slotKey]
    if cached and cached.bgvFinal then
        return cached
    end
    if not cached then
        local seeded = icons
        if limit and #icons > limit then
            seeded = SampleIcons(icons, limit)
        else
            seeded = ShuffleIcons(icons)
        end
        cached = seeded
        iconLists[slotKey] = cached
    else
        local seen = {}
        for _, icon in ipairs(cached) do
            local identity = IconIdentity(icon)
            if identity then
                seen[identity] = true
            end
        end
        local extra = {}
        for _, icon in ipairs(icons) do
            local identity = IconIdentity(icon)
            if identity and not seen[identity] then
                seen[identity] = true
                extra[#extra + 1] = icon
            end
        end
        if #extra > 1 then
            extra = ShuffleIcons(extra)
        end
        for _, icon in ipairs(extra) do
            if not limit or #cached < limit then
                cached[#cached + 1] = icon
            end
        end
    end
    if not pending then
        cached.bgvFinal = true
    end
    cached.bgvCount = #cached
    return cached
end

function Rewards.PossibleIcons(slot)
    if type(slot) ~= "table" or not slot.unlocked or not Rewards.ShowingWeeklyProgress() then
        return {}
    end

    local lootSpecID = Utils.LootSpecID()
    if Utils.SameType(slot.type, Utils.ThresholdType("Raid")) then
        local instanceIDs, encounterSet = RaidScope(slot)
        local encounterKey = {}
        if type(encounterSet) == "table" then
            for encounterID in pairs(encounterSet) do
                encounterKey[#encounterKey + 1] = encounterID
            end
            table.sort(encounterKey)
        end
        local slotKey = "raid:" .. tostring(slot.level) .. ":" .. table.concat(instanceIDs, ",") .. ":" .. table.concat(encounterKey, ",") .. ":" .. tostring(lootSpecID) .. ":slot:" .. tostring(slot.index or 0)
        local finished = iconLists[slotKey]
        if finished and finished.bgvFinal then
            return finished, false
        end
        local icons, pending = CollectIcons(slot.level, instanceIDs, encounterSet)
        if #icons == 0 then
            if finished then
                return finished, pending == true
            end
            return icons, pending == true
        end
        return StableOrder(slotKey, icons, pending == true), pending == true
    end

    local worldSlot = Utils.SameType(slot.type, Utils.ThresholdType("World"))
    local key
    if Utils.SameType(slot.type, Utils.ThresholdType("Activities")) then
        key = "loot:mplus:" .. tostring(lootSpecID) .. ":" .. tostring(slot.index) .. ":" .. tostring(slot.itemLevel)
    elseif worldSlot then
        key = "loot:world:" .. tostring(lootSpecID) .. ":" .. tostring(slot.index) .. ":" .. tostring(slot.itemLevel)
    else
        return {}
    end

    local slotKey = key .. ":slot"
    local finished = iconLists[slotKey]
    if finished and finished.bgvFinal then
        return finished, false
    end

    local entries, pending = Rewards.ItemsForSlot(slot)
    local icons = {}
    local seen = {}
    if type(entries) == "table" then
        for _, entry in ipairs(entries) do
            local itemID = type(entry) == "table" and entry.itemID or nil
            local icon = type(entry) == "table" and entry.icon or nil
            if (not icon or icon == 0) and Utils.IsUsableNumber(itemID) and C_Item and type(C_Item.GetItemIconByID) == "function" then
                icon = Utils.Call(C_Item.GetItemIconByID, itemID)
            end
            local dedupe = itemID or icon
            if icon and icon ~= 0 and not Utils.IsSecret(icon) and dedupe and not seen[dedupe] then
                seen[dedupe] = true
                icons[#icons + 1] = {
                    itemID = Utils.IsUsableNumber(itemID) and itemID or nil,
                    icon = icon,
                }
            end
        end
    end

    if #icons == 0 then
        if finished then
            return finished, pending == true
        end
        return icons, pending == true
    end

    if worldSlot then
        return StableOrder(slotKey, icons, pending == true, WORLD_REEL_LIMIT), pending == true
    end

    return StableOrder(slotKey, icons, pending == true), pending == true
end

local EQUIP_LABEL = {
    INVTYPE_HEAD = "Head",
    INVTYPE_NECK = "Neck",
    INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_CLOAK = "Cloak",
    INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest",
    INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands",
    INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet",
    INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket",
    INVTYPE_WEAPON = "Weapon",
    INVTYPE_SHIELD = "Weapon",
    INVTYPE_RANGED = "Weapon",
    INVTYPE_2HWEAPON = "Weapon",
    INVTYPE_WEAPONMAINHAND = "Weapon",
    INVTYPE_WEAPONOFFHAND = "Weapon",
    INVTYPE_HOLDABLE = "Weapon",
    INVTYPE_RANGEDRIGHT = "Weapon",
    INVTYPE_THROWN = "Weapon",
}

local function ItemFields(itemID)
    local equipLoc, icon, name, quality
    if Utils.IsUsableNumber(itemID) and type(GetItemInfoInstant) == "function" then
        local instantName, _, _, loc, instantIcon = GetItemInfoInstant(itemID)
        equipLoc = type(loc) == "string" and loc or nil
        icon = instantIcon
        name = type(instantName) == "string" and instantName or nil
    end
    if Utils.IsUsableNumber(itemID) and C_Item and type(C_Item.GetItemInfo) == "function" then
        local infoName, _, infoQuality = Utils.Call(C_Item.GetItemInfo, itemID)
        if type(infoName) == "string" and infoName ~= "" then
            name = infoName
        end
        if Utils.IsUsableNumber(infoQuality) then
            quality = infoQuality
        end
    end
    if (not name or name == "") and Utils.IsUsableNumber(itemID) and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    if (not icon or icon == 0) and Utils.IsUsableNumber(itemID) and C_Item and type(C_Item.GetItemIconByID) == "function" then
        local fileID = Utils.Call(C_Item.GetItemIconByID, itemID)
        if fileID and fileID ~= 0 and not Utils.IsSecret(fileID) then
            icon = fileID
        end
    end
    return equipLoc, icon, name, quality
end

local function CollectEntries(difficultyID, instanceIDs, encounterSet, names, budget)
    if not Rewards.EnsureJournal() or type(EJ_SetLootFilter) ~= "function" or type(instanceIDs) ~= "table" or #instanceIDs == 0 then
        return {}, not Rewards.EnsureJournal()
    end

    local _, _, classID = UnitClass("player")
    local specID = Utils.LootSpecID()
    local oldClass, oldSpec
    if type(EJ_GetLootFilter) == "function" then
        oldClass, oldSpec = EJ_GetLootFilter()
    end
    local oldDifficulty = type(EJ_GetDifficulty) == "function" and EJ_GetDifficulty() or nil

    if type(EJ_ResetLootFilter) == "function" then
        EJ_ResetLootFilter()
    end
    if C_EncounterJournal and type(C_EncounterJournal.ResetSlotFilter) == "function" then
        C_EncounterJournal.ResetSlotFilter()
    end
    if classID and specID then
        EJ_SetLootFilter(classID, specID)
    end
    if difficultyID and type(EJ_SetDifficulty) == "function" then
        EJ_SetDifficulty(difficultyID)
    end

    local entries = {}
    local seen = {}
    local pending = false
    local deferred = false
    if not budget then
        budget = { used = 0 }
    end
    for _, instanceID in ipairs(instanceIDs) do
        if Utils.IsUsableNumber(instanceID) and type(EJ_SelectInstance) == "function" and type(EJ_GetNumLoot) == "function" and C_EncounterJournal and type(C_EncounterJournal.GetLootInfoByIndex) == "function" then
            local batchKey = JournalBatchKey(difficultyID, instanceID, encounterSet, specID)
            local cached = journalBatches[batchKey]
            if cached then
                for _, entry in ipairs(cached) do
                    if not seen[entry.itemID] then
                        seen[entry.itemID] = true
                        entries[#entries + 1] = entry
                    end
                end
            elseif not AllowJournalSelect(budget) then
                pending = true
                deferred = true
                break
            else
                local instancePending = false
                local startCount = #entries
                EJ_SelectInstance(instanceID)
                if encounterSet and difficultyID and type(EJ_SetDifficulty) == "function" then
                    EJ_SetDifficulty(difficultyID)
                end
                if type(EJ_IsLootListOutOfDate) == "function" and EJ_IsLootListOutOfDate() then
                    instancePending = true
                else
                    local count = EJ_GetNumLoot() or 0
                    for index = 1, count do
                        local info = Utils.Call(C_EncounterJournal.GetLootInfoByIndex, index)
                        local encounterID = type(info) == "table" and info.encounterID or nil
                        local fromSlot = InEncounterPool(encounterSet, encounterID)
                        local itemID = type(info) == "table" and info.itemID or nil
                        if type(info) == "table" and fromSlot and not info.handError and not info.weaponTypeError and IsVaultGear(itemID) and Utils.IsUsableNumber(itemID) and not seen[itemID] then
                            local equipLoc, icon, name, quality = ItemFields(itemID)
                            local shownIcon = icon or info.icon
                            local shownName = name or info.name
                            if shownIcon and shownIcon ~= 0 and type(shownName) == "string" and shownName ~= "" then
                                seen[itemID] = true
                                local source = type(names) == "table" and names[encounterID] or nil
                                entries[#entries + 1] = {
                                    itemID = itemID,
                                    name = shownName,
                                    icon = shownIcon,
                                    equipLoc = equipLoc,
                                    equipLabel = EQUIP_LABEL[equipLoc] or "Gear",
                                    quality = quality,
                                    source = source or "Raid",
                                    encounterID = encounterID,
                                }
                            else
                                instancePending = true
                            end
                        end
                    end
                end
                if instancePending then
                    pending = true
                else
                    local batch = {}
                    for index = startCount + 1, #entries do
                        batch[#batch + 1] = entries[index]
                    end
                    journalBatches[batchKey] = batch
                end
            end
        end
    end

    if oldClass and type(EJ_SetLootFilter) == "function" then
        EJ_SetLootFilter(oldClass, oldSpec or 0)
    elseif type(EJ_ResetLootFilter) == "function" then
        EJ_ResetLootFilter()
    end
    if oldDifficulty and type(EJ_SetDifficulty) == "function" then
        EJ_SetDifficulty(oldDifficulty)
    end

    table.sort(entries, function(left, right)
        if left.equipLabel ~= right.equipLabel then
            return left.equipLabel < right.equipLabel
        end
        return (left.name or "") < (right.name or "")
    end)
    return entries, pending, deferred
end

local function JournalInstanceName(instanceID)
    if type(EJ_GetInstanceInfo) ~= "function" then
        return nil
    end
    local name = Utils.Call(EJ_GetInstanceInfo, instanceID)
    if Utils.IsUsableString(name) then
        return name
    end
end

local KEYSTONE_DIFFICULTY = 8

-- Returns fresh copies: the input entries are cached journal batches shared by every slot
-- that draws on the same dungeon or boss, so stamping them in place would let one slot's
-- item level leak into another slot's list.
--
-- Raid only (ceilingEncounters ~= nil): the slot's reward can sit above the season's normal
-- Mythic cap once one of the raid's last two bosses is killed on Mythic (see CapRaidReward),
-- but only loot from those specific bosses can actually reach it. Every other boss's loot in
-- that slot stays at the normal cap.
local function StampReward(entries, slot, ceilingEncounters)
    local slotAtCeiling = ceilingEncounters ~= nil and IsEndBossBand(slot)
    local stamped = {}
    for index, source in ipairs(entries) do
        local entry = {}
        for key, value in pairs(source) do
            entry[key] = value
        end
        local capped = slotAtCeiling and not (entry.encounterID and ceilingEncounters[entry.encounterID])
        entry.upgradeTrack = slot.upgradeTrack
        if capped then
            entry.itemLevel = MYTHIC_VAULT_ILVL
            entry.upgradeLevel = MYTHIC_VAULT_STEP
            entry.upgradeMax = Utils.IsUsableNumber(slot.upgradeMax) and math.max(slot.upgradeMax, MYTHIC_VAULT_STEP) or MYTHIC_VAULT_STEP
        else
            entry.itemLevel = slot.itemLevel
            entry.upgradeLevel = slot.upgradeLevel
            entry.upgradeMax = slot.upgradeMax
        end
        entry.rewardLink = slot.rewardLink
        entry.qualityName = slot.itemQuality
        if slot.quality then
            entry.quality = slot.quality
        end
        stamped[index] = entry
    end
    return stamped
end

function Rewards.ItemsForSlot(slot)
    if type(slot) ~= "table" or not slot.unlocked then
        return {}
    end
    Rewards.EnsureJournal()

    if Utils.SameType(slot.type, Utils.ThresholdType("Raid")) then
        local instanceIDs, encounterSet, names, ceilingEncounters = RaidScope(slot)
        local entries, pending = CollectEntries(slot.level, instanceIDs, encounterSet, names)
        return StampReward(entries, slot, ceilingEncounters), pending
    end

    if Utils.SameType(slot.type, Utils.ThresholdType("Activities")) then
        local difficultyID = KEYSTONE_DIFFICULTY
        if Utils.IsHeroicDungeonTier(slot.activityTierID) then
            difficultyID = DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonHeroic or 2
        end
        local instanceIDs, challengeNames = MythicPlusMapInfo()
        if #instanceIDs == 0 then
            return {}, true
        end
        local groups = {}
        local pending = false
        local budget = { used = 0 }
        local specID = Utils.LootSpecID()
        for _, instanceID in ipairs(instanceIDs) do
            local batch, batchPending, deferred = CollectEntries(difficultyID, { instanceID }, nil, nil, budget)
            if deferred then
                pending = true
                break
            end
            if batchPending then
                pending = true
            end
            local name = challengeNames[instanceID] or JournalInstanceName(instanceID) or "Mythic+"
            local usable = {}
            local rejected = false
            for _, entry in ipairs(batch) do
                local named = type(entry.name) == "string" and entry.name ~= "" and entry.name ~= "Item" and entry.name ~= name
                local icon = entry.icon and entry.icon ~= 0
                if named and icon and Utils.IsUsableNumber(entry.itemID) then
                    usable[#usable + 1] = entry
                else
                    rejected = true
                    pending = true
                end
            end
            if rejected or batchPending then
                journalBatches[JournalBatchKey(difficultyID, instanceID, nil, specID)] = nil
            end
            if #usable > 0 then
                groups[#groups + 1] = { name = name, entries = usable }
            end
        end
        table.sort(groups, function(left, right)
            return left.name < right.name
        end)
        local entries = {}
        for _, group in ipairs(groups) do
            for _, entry in ipairs(group.entries) do
                entry.source = group.name
                entries[#entries + 1] = entry
            end
        end
        return StampReward(entries, slot), pending
    end

    if Utils.SameType(slot.type, Utils.ThresholdType("World")) then
        local specID = Utils.LootSpecID()
        local entries = {}
        local pending = false
        local rows = BGV.WorldLoot
        if type(rows) ~= "table" then
            return entries, pending
        end
        local lookups = 0
        for _, itemID in ipairs(rows) do
            if Utils.IsUsableNumber(itemID) and IsVaultGear(itemID) then
                local answerKey = tostring(specID) .. ":" .. tostring(itemID)
                local allowed
                if specKnown[answerKey] then
                    allowed = specAnswers[answerKey]
                else
                    if LiveJournalBudget() and lookups >= 40 then
                        pending = true
                        break
                    end
                    lookups = lookups + 1
                    allowed = SpecCanUse(itemID, specID)
                    if allowed == nil then
                        pending = true
                    else
                        specKnown[answerKey] = true
                        specAnswers[answerKey] = allowed and true or false
                    end
                end
                if allowed then
                    local equipLoc, icon, name, quality = ItemFields(itemID)
                    if icon and icon ~= 0 then
                        entries[#entries + 1] = {
                            itemID = itemID,
                            name = name or "Item",
                            icon = icon,
                            equipLoc = equipLoc,
                            equipLabel = EQUIP_LABEL[equipLoc] or "Gear",
                            quality = quality,
                            source = slot.qualifier or "World",
                        }
                    else
                        pending = true
                    end
                end
            end
        end
        table.sort(entries, function(left, right)
            if left.equipLabel ~= right.equipLabel then
                return left.equipLabel < right.equipLabel
            end
            return (left.name or "") < (right.name or "")
        end)
        return StampReward(entries, slot), pending
    end

    return {}
end
