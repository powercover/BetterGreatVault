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

function Rewards.ResolveReward(activity, onReady)
    local link = BestRewardLink(activity) or ExampleRewardLink(activity)
    if not link then
        return nil
    end

    local info = ItemInfoFromLink(link)
    if info.itemLevel or info.qualityName or info.upgradeTrack then
        return info
    end

    WatchItem(link, onReady)
    return nil
end

function Rewards.ResolveItemLevel(activity, onReady)
    local info = Rewards.ResolveReward(activity, onReady and function(resolved)
        if resolved and resolved.itemLevel then
            onReady(resolved.itemLevel)
        end
    end)
    return info and info.itemLevel or nil
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
local emptyTries = {}

function Rewards.InvalidateIcons()
    iconLists = {}
    emptyTries = {}
end

function Rewards.RetryEmptyIcons()
    emptyTries = {}
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

local function AddInstanceIcons(instanceID, icons, seen, encounterSet)
    if not Utils.IsUsableNumber(instanceID) or type(EJ_SelectInstance) ~= "function" or type(EJ_GetNumLoot) ~= "function" then
        return
    end
    if not (C_EncounterJournal and type(C_EncounterJournal.GetLootInfoByIndex) == "function") then
        return
    end

    EJ_SelectInstance(instanceID)
    local count = EJ_GetNumLoot() or 0
    for index = 1, count do
        local info = Utils.Call(C_EncounterJournal.GetLootInfoByIndex, index)
        local encounterID = type(info) == "table" and info.encounterID or nil
        local fromSlot = not encounterSet
            or not Utils.IsUsableNumber(encounterID)
            or encounterID == 0
            or encounterSet[encounterID]
        if type(info) == "table" and info.icon and fromSlot and not info.handError and not info.weaponTypeError and IsVaultGear(info.itemID) then
            local itemID = info.itemID
            if not itemID or not seen[itemID] then
                if itemID then
                    seen[itemID] = true
                end
                icons[#icons + 1] = {
                    itemID = Utils.IsUsableNumber(itemID) and itemID or nil,
                    icon = info.icon,
                }
            end
        end
    end
end

local function CollectIcons(difficultyID, instanceIDs, encounterSet)
    if not Rewards.EnsureJournal() or type(EJ_SetLootFilter) ~= "function" or type(instanceIDs) ~= "table" or #instanceIDs == 0 then
        return {}
    end

    local _, _, classID = UnitClass("player")
    local specIndex = type(GetSpecialization) == "function" and GetSpecialization() or nil
    local specID = specIndex and type(GetSpecializationInfo) == "function" and GetSpecializationInfo(specIndex) or nil
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
    for _, instanceID in ipairs(instanceIDs) do
        AddInstanceIcons(instanceID, icons, seen, encounterSet)
    end

    if oldClass and type(EJ_SetLootFilter) == "function" then
        EJ_SetLootFilter(oldClass, oldSpec or 0)
    elseif type(EJ_ResetLootFilter) == "function" then
        EJ_ResetLootFilter()
    end
    if oldDifficulty and type(EJ_SetDifficulty) == "function" then
        EJ_SetDifficulty(oldDifficulty)
    end

    return icons
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
    local rewardRank = RAID_RANK[slot.level] or 0
    if type(slot.encounters) ~= "table" then
        return ids, encounters
    end

    local function AddEncounter(encounter)
        if Utils.IsUsableNumber(encounter.journalEncounterID) then
            encounters[encounter.journalEncounterID] = true
        end
        if Utils.IsUsableNumber(encounter.activityEncounterID) then
            encounters[encounter.activityEncounterID] = true
        end
        local instanceID = encounter.journalInstanceID
        if Utils.IsUsableNumber(instanceID) and not seen[instanceID] then
            seen[instanceID] = true
            ids[#ids + 1] = instanceID
        end
    end

    local function CountsForSlot(encounter)
        local bossRank = RAID_RANK[encounter.difficultyID] or 0
        return encounter.defeated and (rewardRank == 0 or bossRank >= rewardRank)
    end

    local byInstance = {}
    for _, encounter in ipairs(slot.encounters) do
        local instanceID = encounter.journalInstanceID
        if Utils.IsUsableNumber(instanceID) then
            local list = byInstance[instanceID]
            if not list then
                list = {}
                byInstance[instanceID] = list
            end
            list[#list + 1] = encounter
        elseif CountsForSlot(encounter) then
            AddEncounter(encounter)
        end
    end

    for _, list in pairs(byInstance) do
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
    end

    return ids, encounters
end

local function MythicPlusInstances()
    local ids = {}
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

    local maps = Utils.Call(C_ChallengeMode.GetMapTable)
    local wantedNames = {}
    if type(maps) == "table" then
    for _, mapID in ipairs(maps) do
        if type(C_ChallengeMode.GetMapUIInfo) == "function" then
            local ok, name, infoID, _, _, _, uiMapID = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
            if ok then
                if type(name) == "string" and name ~= "" and not Utils.IsSecret(name) then
                    wantedNames[name] = true
                end
                if Utils.IsUsableNumber(uiMapID) and type(EJ_GetInstanceForMap) == "function" then
                    local found, instanceID = pcall(EJ_GetInstanceForMap, uiMapID)
                    if found then
                        AddInstance(instanceID)
                    end
                end
                if Utils.IsUsableNumber(infoID) and infoID ~= mapID and type(EJ_GetInstanceForMap) == "function" then
                    local found, instanceID = pcall(EJ_GetInstanceForMap, infoID)
                    if found then
                        AddInstance(instanceID)
                    end
                end
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

    return ids
end

function Rewards.PossibleIcons(slot)
    if type(slot) ~= "table" or not slot.unlocked or not Rewards.ShowingWeeklyProgress() then
        return {}
    end

    Rewards.EnsureJournal()

    local specIndex = type(GetSpecialization) == "function" and GetSpecialization() or 0
    local key
    local difficultyID
    local instanceIDs
    local encounterSet
    local fallbackDifficulty

    if Utils.SameType(slot.type, Utils.ThresholdType("Raid")) then
        difficultyID = slot.level
        instanceIDs, encounterSet = RaidScope(slot)
        local encounterKey = {}
        if type(encounterSet) == "table" then
            for encounterID in pairs(encounterSet) do
                encounterKey[#encounterKey + 1] = encounterID
            end
            table.sort(encounterKey)
        end
        key = "raid:" .. tostring(difficultyID) .. ":" .. table.concat(instanceIDs, ",") .. ":" .. table.concat(encounterKey, ",") .. ":" .. tostring(specIndex)
    elseif Utils.SameType(slot.type, Utils.ThresholdType("Activities")) then
        difficultyID = DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonMythic or 23
        fallbackDifficulty = 8
        instanceIDs = MythicPlusInstances()
        key = "mplus:" .. tostring(specIndex)
    elseif Utils.SameType(slot.type, Utils.ThresholdType("World")) then
        key = "world:" .. tostring(specIndex)
        if iconLists[key] then
            return iconLists[key]
        end
        local icons = {}
        local itemIDs = BGV.Bis and BGV.Bis.WorldItems and BGV.Bis.WorldItems() or {}
        for _, itemID in ipairs(itemIDs) do
            if IsVaultGear(itemID) then
            local icon
            if type(GetItemInfoInstant) == "function" then
                icon = select(5, GetItemInfoInstant(itemID))
            end
            if (not icon or icon == 0) and C_Item and C_Item.GetItemIconByID then
                icon = C_Item.GetItemIconByID(itemID)
            end
            if icon and icon ~= 0 and not Utils.IsSecret(icon) then
                icons[#icons + 1] = { itemID = itemID, icon = icon }
            end
            end
        end
        if #icons > 1 then
            for index = #icons, 2, -1 do
                local swap = math.random(index)
                icons[index], icons[swap] = icons[swap], icons[index]
            end
        end
        if #icons > 0 then
            iconLists[key] = icons
        end
        return icons
    else
        return {}
    end

    if iconLists[key] then
        return iconLists[key]
    end

    local icons = CollectIcons(difficultyID, instanceIDs, encounterSet)
    if #icons == 0 and encounterSet then
        icons = CollectIcons(difficultyID, instanceIDs, nil)
    end
    if #icons == 0 and fallbackDifficulty and fallbackDifficulty ~= difficultyID then
        icons = CollectIcons(fallbackDifficulty, instanceIDs, encounterSet)
        if #icons == 0 and encounterSet then
            icons = CollectIcons(fallbackDifficulty, instanceIDs, nil)
        end
    end
    if #icons > 0 then
        for index = #icons, 2, -1 do
            local swap = math.random(index)
            icons[index], icons[swap] = icons[swap], icons[index]
        end
        iconLists[key] = icons
        emptyTries[key] = nil
    else
        emptyTries[key] = (emptyTries[key] or 0) + 1
    end
    return icons
end
