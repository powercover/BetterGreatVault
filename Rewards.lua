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
local specKnown = {}
local specAnswers = {}

-- Reads of an instance that didn't settle (see CollectEntries): batchKey -> { tries, since }.
local readAttempts = {}

-- Batches kept after giving up on a read, and what could still complete them (see
-- Rewards.RetryGivenUp): batchKey -> { items = { [itemID] = true } or nil, stale = bool }.
local givenUp = {}

-- Timed retries already spent on lists given up on while empty and out of date: batchKey -> n.
local staleRetries = {}

local mythicMaps

-- /bgv debug: what each instance's read found during a load pass (instanceID -> text).
local loadTrace
local lastTraceLine

function Rewards.LastLoadTrace()
    return lastTraceLine
end

function Rewards.InvalidateIcons()
    iconLists = {}
    journalBatches = {}
    readAttempts = {}
    givenUp = {}
    staleRetries = {}
    specKnown = {}
    specAnswers = {}
    mythicMaps = nil
end

-- The journal's state (selected instance and boss, difficulty, loot and slot filters) is global
-- and shared with the Adventure Guide, which stays registered for its journal events even while
-- hidden. Both events fire inside the call that causes them: on EJ_DIFFICULTY_UPDATE the guide
-- re-selects the boss or instance the player last browsed before our EJ_SetDifficulty returns
-- (our reads then came back as that boss's loot, or empty), and on EJ_LOOT_DATA_RECIEVED it
-- rebuilds its loot list. So a scan detaches those two handlers, saves the journal state, sets
-- its own, reads, then puts everything back and reattaches them, all inside one call: nothing
-- else runs in between, and the journal is left as the guide (or the game) had it.
local GUIDE_EVENTS = { "EJ_DIFFICULTY_UPDATE", "EJ_LOOT_DATA_RECIEVED" }

local scan

-- True while a scan is running: journal events fired then are our own changes, not new data.
function Rewards.IsScanning()
    return scan ~= nil
end

local function SetDifficultyIfNeeded(difficultyID)
    if Utils.IsUsableNumber(difficultyID) and type(EJ_SetDifficulty) == "function"
        and not (type(EJ_GetDifficulty) == "function" and EJ_GetDifficulty() == difficultyID) then
        EJ_SetDifficulty(difficultyID)
    end
end

-- EJ_SetDifficulty is ignored when the difficulty isn't valid for the selected instance.
local function OnWantedDifficulty(difficultyID)
    if not difficultyID or type(EJ_GetDifficulty) ~= "function" then
        return true
    end
    local current = EJ_GetDifficulty()
    return current == nil or current == difficultyID
end

local function SetLootFilterIfNeeded(classID, specID)
    if not Utils.IsUsableNumber(classID) or type(EJ_SetLootFilter) ~= "function" then
        return
    end
    specID = specID or 0
    if type(EJ_GetLootFilter) == "function" then
        local currentClass, currentSpec = EJ_GetLootFilter()
        if currentClass == classID and (currentSpec or 0) == specID then
            return
        end
    end
    EJ_SetLootFilter(classID, specID)
end

local function SlotFilter()
    if C_EncounterJournal and type(C_EncounterJournal.GetSlotFilter) == "function" then
        return C_EncounterJournal.GetSlotFilter()
    end
end

-- The journal's selected instance, from its link (|Hjournal:0:instanceID:difficultyID|h). Only
-- needed when the guide shows no instance of its own, e.g. it was never opened.
local function SelectedInstance()
    if type(EJ_GetInstanceInfo) ~= "function" then
        return nil
    end
    -- pcall directly: earlier returns can be nil, which Utils.Call's unpack may cut off at.
    local ok, _, _, _, _, _, _, _, link = pcall(EJ_GetInstanceInfo)
    local instanceID = ok and type(link) == "string" and tonumber(link:match("journal:%d+:(%d+)")) or nil
    if Utils.IsUsableNumber(instanceID) and instanceID > 0 then
        return instanceID
    end
end

-- Another addon doing the same dance (e.g. BonusRollPreview) can hand the guide its events back
-- from a handler that runs inside one of our journal calls; detach them again right after.
local function KeepGuideDetached()
    local guide = scan and scan.guide
    if not guide then
        return
    end
    for _, event in ipairs(GUIDE_EVENTS) do
        if guide:IsEventRegistered(event) then
            guide:UnregisterEvent(event)
            local listed = false
            for _, detached in ipairs(scan.detached) do
                listed = listed or detached == event
            end
            if not listed then
                scan.detached[#scan.detached + 1] = event
            end
        end
    end
end

-- Opened lazily, by the first read of an uncached instance; closed by Rewards.ItemsForSlot.
local function OpenScan(specID)
    if scan then
        return
    end
    local saved = { detached = {} }
    local guide = EncounterJournal
    if type(guide) == "table" and type(guide.IsEventRegistered) == "function"
        and type(guide.UnregisterEvent) == "function" and type(guide.RegisterEvent) == "function" then
        saved.guide = guide
        saved.guideInstance = guide.instanceID
        saved.guideEncounter = guide.encounterID
        for _, event in ipairs(GUIDE_EVENTS) do
            if guide:IsEventRegistered(event) then
                guide:UnregisterEvent(event)
                saved.detached[#saved.detached + 1] = event
            end
        end
    end
    scan = saved
    if type(EJ_GetLootFilter) == "function" then
        saved.class, saved.spec = EJ_GetLootFilter()
    end
    saved.difficulty = type(EJ_GetDifficulty) == "function" and EJ_GetDifficulty() or nil
    saved.slotFilter = SlotFilter()
    saved.tier = type(EJ_GetCurrentTier) == "function" and EJ_GetCurrentTier() or nil
    if not Utils.IsUsableNumber(saved.guideInstance) then
        saved.instance = SelectedInstance()
    end

    local _, _, classID = UnitClass("player")
    SetLootFilterIfNeeded(classID, specID)
    local noFilter = Enum and Enum.ItemSlotFilterType and Enum.ItemSlotFilterType.NoFilter
    if C_EncounterJournal and type(C_EncounterJournal.ResetSlotFilter) == "function"
        and (noFilter == nil or saved.slotFilter ~= noFilter) then
        C_EncounterJournal.ResetSlotFilter()
    end
end

local function RestoreJournal(saved)
    if Utils.IsUsableNumber(saved.tier) and type(EJ_SelectTier) == "function"
        and type(EJ_GetCurrentTier) == "function" and EJ_GetCurrentTier() ~= saved.tier then
        EJ_SelectTier(saved.tier)
    end
    -- The guide's own fields still say what it shows. Select its instance before restoring the
    -- difficulty, which is only accepted if valid for the selected instance, then its boss.
    local instanceID = Utils.IsUsableNumber(saved.guideInstance) and saved.guideInstance or saved.instance
    if Utils.IsUsableNumber(instanceID) and type(EJ_SelectInstance) == "function" then
        EJ_SelectInstance(instanceID)
    end
    SetDifficultyIfNeeded(saved.difficulty)
    if Utils.IsUsableNumber(saved.guideEncounter) and type(EJ_SelectEncounter) == "function" then
        EJ_SelectEncounter(saved.guideEncounter)
    end
    SetLootFilterIfNeeded(saved.class, saved.spec)
    if saved.slotFilter ~= nil and saved.slotFilter ~= SlotFilter()
        and C_EncounterJournal and type(C_EncounterJournal.SetSlotFilter) == "function" then
        C_EncounterJournal.SetSlotFilter(saved.slotFilter)
    end
end

local function CloseScan()
    local saved = scan
    if not saved then
        return
    end
    local ok, err = pcall(RestoreJournal, saved)
    scan = nil
    -- Reattach the guide even if restoring failed: without these events it would stop updating.
    for _, event in ipairs(saved.detached) do
        saved.guide:RegisterEvent(event)
    end
    if not ok then
        error(err, 0)
    end
end

-- Time a pass may spend reading uncached instances. At least one is always read, so every list
-- keeps making progress; the rest wait for the next pass.
local SCAN_BUDGET_MS = 8

local function NewBudget()
    return { reads = 0, start = type(debugprofilestop) == "function" and debugprofilestop() or nil }
end

local function AllowRead(budget)
    if budget.reads > 0 and budget.start and debugprofilestop() - budget.start >= SCAN_BUDGET_MS then
        return false
    end
    budget.reads = budget.reads + 1
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

-- C_ChallengeMode.GetMapUIInfo's last return is a game map ID (the dungeon's instance map), not
-- a UI map ID, so it resolves through GetInstanceForGameMap; EJ_GetInstanceForMap takes UI maps.
local function JournalInstanceForGameMap(mapID)
    if not Utils.IsUsableNumber(mapID) then
        return nil
    end
    local instanceID
    if C_EncounterJournal and type(C_EncounterJournal.GetInstanceForGameMap) == "function" then
        instanceID = Utils.Call(C_EncounterJournal.GetInstanceForGameMap, mapID)
    end
    if Utils.IsUsableNumber(instanceID) and instanceID > 0 then
        return instanceID
    end
end

-- The season's Mythic+ dungeons, from its challenge maps: the journal instance IDs to scan, an
-- instanceID -> dungeon name map, how many challenge maps there are and how many didn't resolve.
-- Doesn't touch the journal's selection. Built once per cache reset; with no challenge maps yet
-- (map info not loaded on a cold login) it isn't kept, and map info is requested.
local function MythicPlusMapInfo()
    if mythicMaps then
        return mythicMaps.ids, mythicMaps.names, mythicMaps.seasonMaps, mythicMaps.unresolved
    end
    local ids = {}
    local names = {}
    local seen = {}
    local seasonMaps = 0
    local unresolved = 0
    Rewards.EnsureJournal()
    local maps = C_ChallengeMode and Utils.Call(C_ChallengeMode.GetMapTable)
    if type(maps) == "table" and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        seasonMaps = #maps
        for _, mapID in ipairs(maps) do
            local name, _, _, _, _, gameMapID = Utils.Call(C_ChallengeMode.GetMapUIInfo, mapID)
            local instanceID = JournalInstanceForGameMap(gameMapID)
            if instanceID then
                if not seen[instanceID] then
                    seen[instanceID] = true
                    ids[#ids + 1] = instanceID
                end
                if Utils.IsUsableString(name) and not names[instanceID] then
                    names[instanceID] = name
                end
            else
                unresolved = unresolved + 1
            end
        end
    end
    if seasonMaps > 0 then
        mythicMaps = { ids = ids, names = names, seasonMaps = seasonMaps, unresolved = unresolved }
    elseif BGV.GreatVault and type(BGV.GreatVault.RequestRunData) == "function" then
        BGV.GreatVault.RequestRunData()
    end
    return ids, names, seasonMaps, unresolved
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

    -- Every reel spins the same items the loot table lists for that slot (Rewards.ItemsForSlot),
    -- so both share one scan and its cached journal reads.
    local lootSpecID = Utils.LootSpecID()
    local worldSlot = Utils.SameType(slot.type, Utils.ThresholdType("World"))
    local key
    if Utils.SameType(slot.type, Utils.ThresholdType("Raid")) then
        -- The boss pool is part of the key, so a new kill gives the reel a fresh list.
        local instanceIDs, encounterSet = RaidScope(slot)
        local encounterKey = {}
        if type(encounterSet) == "table" then
            for encounterID in pairs(encounterSet) do
                encounterKey[#encounterKey + 1] = encounterID
            end
            table.sort(encounterKey)
        end
        key = "loot:raid:" .. tostring(lootSpecID) .. ":" .. tostring(slot.level) .. ":" .. table.concat(instanceIDs, ",") .. ":" .. table.concat(encounterKey, ",") .. ":" .. tostring(slot.index or 0)
    elseif Utils.SameType(slot.type, Utils.ThresholdType("Activities")) then
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

-- A read that can't be trusted (the journal refused the difficulty, listed no bosses, returned an
-- empty list it flags as out of date, or listed another instance's loot) is retried a few times
-- over at least a second, then kept as it is: a list that never settles is re-read on every pass
-- and keeps the reels and the loot table polling. Items whose info hasn't loaded yet get longer,
-- since that data does arrive, just later.
local FAILED_READ_TRIES = 3
local FAILED_READ_SECONDS = 1
local ITEM_WAIT_TRIES = 2
local ITEM_WAIT_SECONDS = 8

local STALE_EMPTY = "empty list, flagged out of date"

local function GiveUp(batchKey, tries, seconds)
    local now = type(GetTime) == "function" and GetTime() or nil
    local attempt = readAttempts[batchKey]
    if not attempt then
        attempt = { tries = 0, since = now }
        readAttempts[batchKey] = attempt
    end
    attempt.tries = attempt.tries + 1
    local waited = (now and attempt.since) and (now - attempt.since) or 0
    return attempt.tries >= tries and waited >= seconds
end

local function BossList(instanceID)
    local bosses = {}
    for bossIndex = 1, 40 do
        local name, _, bossID, _, _, _, dungeonEncounterID = Utils.Call(EJ_GetEncounterInfoByIndex, bossIndex, instanceID)
        if not Utils.IsUsableNumber(bossID) then
            break
        end
        bosses[#bosses + 1] = {
            id = bossID,
            alt = Utils.IsUsableNumber(dungeonEncounterID) and dungeonEncounterID or nil,
            name = Utils.IsUsableString(name) and name or nil,
        }
    end
    return bosses
end

-- Whether loot row `index` drops from one of the encounters in `set`. An item several bosses drop
-- is listed under one of them, with the others under further encounter indexes.
local function RowFrom(index, info, set)
    if Utils.IsUsableNumber(info.encounterID) and set[info.encounterID] then
        return true
    end
    if type(EJ_GetNumEncountersForLootByIndex) == "function" then
        local count = Utils.Call(EJ_GetNumEncountersForLootByIndex, index)
        for encounterIndex = 2, Utils.IsUsableNumber(count) and count or 0 do
            local other = Utils.Call(C_EncounterJournal.GetLootInfoByIndex, index, encounterIndex)
            if type(other) == "table" and Utils.IsUsableNumber(other.encounterID) and set[other.encounterID] then
                return true
            end
        end
    end
    return false
end

-- Reads one instance's loot inside an open scan. Raids go boss by boss, only through the bosses
-- in the slot's pool (encounterSet): with a boss selected the list is that boss's loot, and each
-- item gets its source. Mythic+ dungeons are read whole. Returns { entries, bosses, rows,
-- missing (items whose info hasn't loaded), problem (why the read can't be trusted),
-- unsupported (the instance has no such difficulty) }.
local function ReadInstance(instanceID, difficultyID, encounterSet, names)
    local read = { entries = {}, bosses = 0, rows = 0, missing = 0, missingItems = {} }
    -- Mythic+ reads the whole dungeon: the journal lists no bosses for keystone dungeons (in game,
    -- EJ_GetEncounterInfoByIndex returns nothing for them, with or without the instance ID), and
    -- nothing needs a per-boss source there. Raids read boss by boss for their kill pool.
    local byBoss = encounterSet ~= nil and type(EJ_GetEncounterInfoByIndex) == "function" and type(EJ_SelectEncounter) == "function"
    local function UseDifficulty()
        EJ_SelectInstance(instanceID)
        SetDifficultyIfNeeded(difficultyID)
        KeepGuideDetached()
        return OnWantedDifficulty(difficultyID)
    end
    -- Twice: another addon's handler running inside the first EJ_SetDifficulty can move the
    -- selection elsewhere.
    if not UseDifficulty() and not UseDifficulty() and byBoss then
        -- In case a boss selected elsewhere outlived EJ_SelectInstance and the difficulty was
        -- judged against its instance: select one of ours and try again.
        local first = BossList(instanceID)[1]
        if first then
            EJ_SelectEncounter(first.id)
            SetDifficultyIfNeeded(difficultyID)
            KeepGuideDetached()
        end
    end
    if not OnWantedDifficulty(difficultyID) then
        -- Judge the difficulty against this instance, whatever ended up selected.
        EJ_SelectInstance(instanceID)
        if type(EJ_IsValidInstanceDifficulty) == "function" and not EJ_IsValidInstanceDifficulty(difficultyID) then
            read.unsupported = true
        else
            read.problem = "journal kept difficulty " .. tostring(EJ_GetDifficulty())
        end
        return read
    end

    local byItem = {}
    local function AddRow(info, boss)
        local itemID = info.itemID
        if info.handError or info.weaponTypeError or not Utils.IsUsableNumber(itemID) or not IsVaultGear(itemID) then
            return
        end
        local existing = byItem[itemID]
        if existing then
            -- Dropped by several of the bosses read: any of them can award it.
            if boss then
                existing.encounterIDs[#existing.encounterIDs + 1] = boss.id
                existing.encounterIDs[#existing.encounterIDs + 1] = boss.alt
            end
            return
        end
        -- The row's own name and icon aren't the item's until its data has loaded (a cold journal
        -- lists the dungeon's name and a placeholder icon), so wait for the item itself.
        local equipLoc, icon, name, quality = ItemFields(itemID)
        if not (icon and icon ~= 0 and type(name) == "string" and name ~= "") then
            read.missing = read.missing + 1
            read.missingItems[itemID] = true
            return
        end
        local encounterID = boss and boss.id or info.encounterID
        local source = type(names) == "table" and (names[encounterID] or (boss and boss.alt and names[boss.alt])) or nil
        local entry = {
            itemID = itemID,
            name = name,
            icon = icon,
            equipLoc = equipLoc,
            equipLabel = EQUIP_LABEL[equipLoc] or "Gear",
            quality = quality,
            source = source or (boss and boss.name) or "Raid",
            encounterID = encounterID,
            encounterIDs = { encounterID, boss and boss.alt or nil },
        }
        byItem[itemID] = entry
        read.entries[#read.entries + 1] = entry
    end

    local stale = false
    local function ReadRows(boss, own)
        stale = stale or (type(EJ_IsLootListOutOfDate) == "function" and EJ_IsLootListOutOfDate() == true)
        local count = EJ_GetNumLoot() or 0
        read.rows = read.rows + count
        local mine = boss and { [boss.id] = true } or nil
        if boss and boss.alt then
            mine[boss.alt] = true
        end
        for index = 1, count do
            local info = Utils.Call(C_EncounterJournal.GetLootInfoByIndex, index)
            if type(info) == "table" then
                local tied = Utils.IsUsableNumber(info.encounterID) and info.encounterID ~= 0
                if not boss then
                    -- Whole-instance read (journal API without boss selection).
                    if InEncounterPool(encounterSet, info.encounterID) then
                        AddRow(info, nil)
                    end
                elseif not tied then
                    -- Tied to no boss: Mythic+ keeps it, raids skip it (the vault awards boss loot).
                    if not encounterSet then
                        AddRow(info, boss)
                    end
                elseif RowFrom(index, info, mine) then
                    AddRow(info, boss)
                elseif not RowFrom(index, info, own) then
                    read.problem = "another instance's loot in the list"
                end
                -- Other rows belong to this instance's other bosses (the journal sometimes lists a
                -- whole instance with a boss selected); they're read with their own boss.
            end
        end
    end

    local bosses = byBoss and BossList(instanceID) or {}
    read.bosses = #bosses
    if #bosses == 0 then
        -- Whole instance: Mythic+ always (see above); a raid whose bosses the journal won't
        -- list is filtered to the slot's pool by each row's boss instead.
        ReadRows(nil, nil)
    else
        local own = {}
        for _, boss in ipairs(bosses) do
            own[boss.id] = true
            if boss.alt then
                own[boss.alt] = true
            end
        end
        for _, boss in ipairs(bosses) do
            if not encounterSet or encounterSet[boss.id] or (boss.alt and encounterSet[boss.alt]) then
                EJ_SelectEncounter(boss.id)
                KeepGuideDetached()
                ReadRows(boss, own)
            end
        end
    end
    if read.rows == 0 and stale then
        read.problem = STALE_EMPTY
    end
    return read
end

-- The journal may never announce that a list it flagged out of date has loaded, so a list given
-- up on while empty and out of date is also retried on a timer, a few times.
local STALE_RETRY_SECONDS = 3
local STALE_RETRY_LIMIT = 3

local function ScheduleStaleRetry(batchKey)
    local spent = staleRetries[batchKey] or 0
    if spent >= STALE_RETRY_LIMIT or not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    staleRetries[batchKey] = spent + 1
    C_Timer.After(STALE_RETRY_SECONDS, function()
        if givenUp[batchKey] and type(BGV.RetryLootLists) == "function" then
            BGV.RetryLootLists(nil)
        end
    end)
end

local function CollectEntries(difficultyID, instanceIDs, encounterSet, names, budget)
    if type(instanceIDs) ~= "table" or #instanceIDs == 0 then
        return {}, false
    end
    if not Rewards.EnsureJournal() or type(EJ_SelectInstance) ~= "function"
        or not (C_EncounterJournal and type(C_EncounterJournal.GetLootInfoByIndex) == "function") then
        return {}, true
    end

    local specID = Utils.LootSpecID()
    local entries = {}
    local seen = {}
    local pending = false
    budget = budget or NewBudget()
    for _, instanceID in ipairs(instanceIDs) do
        if Utils.IsUsableNumber(instanceID) then
            local batchKey = JournalBatchKey(difficultyID, instanceID, encounterSet, specID)
            local batch = journalBatches[batchKey]
            if batch then
                if loadTrace then
                    loadTrace[instanceID] = "cached(" .. #batch .. ")"
                end
            elseif not AllowRead(budget) then
                pending = true
                if loadTrace then
                    loadTrace[instanceID] = "next pass"
                end
            else
                OpenScan(specID)
                local read = ReadInstance(instanceID, difficultyID, encounterSet, names)
                batch = read.entries
                local settled, status
                if read.unsupported then
                    settled = true
                    status = "no difficulty " .. tostring(difficultyID) .. " in the journal, skipped"
                elseif read.problem then
                    settled = GiveUp(batchKey, FAILED_READ_TRIES, FAILED_READ_SECONDS)
                    status = read.problem .. (settled and ", gave up" or ", retrying")
                elseif read.missing > 0 then
                    settled = GiveUp(batchKey, ITEM_WAIT_TRIES, ITEM_WAIT_SECONDS)
                    status = string.format("item info missing %d%s", read.missing, settled and ", gave up" or "")
                else
                    settled = true
                    status = string.format("%s, %d loot, %d kept",
                        read.bosses > 0 and (read.bosses .. " bosses") or "whole instance", read.rows, #batch)
                end
                if settled then
                    journalBatches[batchKey] = batch
                    readAttempts[batchKey] = nil
                    if read.problem or read.missing > 0 then
                        givenUp[batchKey] = {
                            items = read.missing > 0 and read.missingItems or nil,
                            stale = read.problem == STALE_EMPTY,
                        }
                        if read.problem == STALE_EMPTY then
                            ScheduleStaleRetry(batchKey)
                        end
                    end
                else
                    pending = true
                end
                if loadTrace then
                    loadTrace[instanceID] = status
                end
            end
            for _, entry in ipairs(batch or {}) do
                if not seen[entry.itemID] then
                    seen[entry.itemID] = true
                    entries[#entries + 1] = entry
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
    return entries, pending
end

-- A read given up on is kept, so a list can't poll forever, but it may still complete: when an
-- item it was missing loads (GET_ITEM_INFO_RECEIVED / EJ_LOOT_DATA_RECIEVED with that item), or,
-- for a list that was empty and out of date, when the journal reports new loot data (itemID nil).
-- Drops those batches so the next pass reads them again; returns true if it dropped any.
function Rewards.RetryGivenUp(itemID)
    local dropped = false
    for batchKey, why in pairs(givenUp) do
        if (itemID and why.items and why.items[itemID]) or (not itemID and why.stale) then
            journalBatches[batchKey] = nil
            readAttempts[batchKey] = nil
            givenUp[batchKey] = nil
            dropped = true
        end
    end
    if dropped then
        iconLists = {}
    end
    return dropped
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

-- /bgv debug: one line per load pass (printed only when it changes) with what each instance's
-- read found. `names` maps instanceID -> display name.
local function ReportLoadTrace(kind, instanceIDs, names, pending, specID, difficultyID)
    if not loadTrace then
        return
    end
    local parts = {}
    for _, instanceID in ipairs(instanceIDs) do
        local name = type(names) == "table" and names[instanceID] or JournalInstanceName(instanceID)
        parts[#parts + 1] = string.format("%s (%s): %s", name or "?", tostring(instanceID), loadTrace[instanceID] or "not reached")
    end
    local guide = EncounterJournal
    local line = string.format("%s loot %s | loot spec %s, difficulty %s, guide on %s/%s | %s",
        kind,
        pending and "LOADING" or "done",
        tostring(specID), tostring(difficultyID),
        tostring(guide and guide.instanceID), tostring(guide and guide.encounterID),
        table.concat(parts, "; "))
    if line ~= lastTraceLine then
        lastTraceLine = line
        Utils.Print(line)
    end
    loadTrace = nil
end

local function ReportLine(line)
    if BetterGreatVaultDB and BetterGreatVaultDB.debug and line ~= lastTraceLine then
        lastTraceLine = line
        Utils.Print(line)
    end
end

local function AtCeiling(entry, ceilingEncounters)
    if type(entry.encounterIDs) == "table" then
        for _, encounterID in ipairs(entry.encounterIDs) do
            if ceilingEncounters[encounterID] then
                return true
            end
        end
        return false
    end
    return entry.encounterID ~= nil and ceilingEncounters[entry.encounterID] == true
end

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
        local capped = slotAtCeiling and not AtCeiling(entry, ceilingEncounters)
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

local function SlotItems(slot)
    Rewards.EnsureJournal()

    if Utils.SameType(slot.type, Utils.ThresholdType("Raid")) then
        local instanceIDs, encounterSet, names, ceilingEncounters = RaidScope(slot)
        loadTrace = BetterGreatVaultDB and BetterGreatVaultDB.debug and {} or nil
        local entries, pending = CollectEntries(slot.level, instanceIDs, encounterSet, names)
        local raidNames = {}
        for _, instanceID in ipairs(instanceIDs) do
            raidNames[instanceID] = JournalInstanceName(instanceID)
        end
        ReportLoadTrace("Raid", instanceIDs, raidNames, pending, Utils.LootSpecID(), slot.level)
        return StampReward(entries, slot, ceilingEncounters), pending
    end

    if Utils.SameType(slot.type, Utils.ThresholdType("Activities")) then
        local difficultyID = KEYSTONE_DIFFICULTY
        if Utils.IsHeroicDungeonTier(slot.activityTierID) then
            difficultyID = DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonHeroic or 2
        end
        local instanceIDs, challengeNames, seasonMaps, unresolved = MythicPlusMapInfo()
        if #instanceIDs == 0 then
            -- No challenge maps yet: map info is on its way (CHALLENGE_MODE_MAPS_UPDATE resets the
            -- lists). Maps that the journal can't place won't change, so that isn't loading.
            ReportLine(string.format("M+ loot %s | no dungeon list: %d challenge maps, %d not found in the journal",
                seasonMaps == 0 and "LOADING" or "done", seasonMaps or 0, unresolved or 0))
            return {}, seasonMaps == 0
        end
        local groups = {}
        local pending = false
        local budget = NewBudget()
        local specID = Utils.LootSpecID()
        loadTrace = BetterGreatVaultDB and BetterGreatVaultDB.debug and {} or nil
        for _, instanceID in ipairs(instanceIDs) do
            local batch, batchPending = CollectEntries(difficultyID, { instanceID }, nil, nil, budget)
            if batchPending then
                pending = true
            end
            if #batch > 0 then
                groups[#groups + 1] = {
                    name = challengeNames[instanceID] or JournalInstanceName(instanceID) or "Mythic+",
                    entries = batch,
                }
            end
        end
        ReportLoadTrace("M+", instanceIDs, challengeNames, pending, specID, difficultyID)
        table.sort(groups, function(left, right)
            return left.name < right.name
        end)
        local entries = {}
        local sources = {}
        for _, group in ipairs(groups) do
            for _, entry in ipairs(group.entries) do
                entries[#entries + 1] = entry
                sources[#entries] = group.name
            end
        end
        local stamped = StampReward(entries, slot)
        for index, entry in ipairs(stamped) do
            entry.source = sources[index]
        end
        return stamped, pending
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
                    if type(debugprofilestop) == "function" and lookups >= 40 then
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
                            source = BGV.WorldLootSource and BGV.WorldLootSource[itemID] or "World",
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

-- Every read runs inside one scan (see OpenScan), closed here even if reading failed, so the
-- journal and the Adventure Guide are always put back before anything else can run.
local scanDepth = 0

function Rewards.ItemsForSlot(slot)
    if type(slot) ~= "table" or not slot.unlocked then
        return {}
    end
    -- Only the outermost call closes the scan, should anything call back into us mid-scan.
    scanDepth = scanDepth + 1
    local ok, entries, pending = pcall(SlotItems, slot)
    scanDepth = scanDepth - 1
    if scanDepth == 0 then
        CloseScan()
    end
    if not ok then
        error(entries, 0)
    end
    return entries, pending
end
