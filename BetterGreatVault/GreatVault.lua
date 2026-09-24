local _, BGV = ...

BGV.GreatVault = {}

local GreatVault = BGV.GreatVault
local Utils = BGV.Utils

local cache
local runCache
local worldCache
local mapsReady = false
local mapsRequested = false
local retriedShortHistory = false

local DISPLAY_ORDER = { "Raid", "Activities", "World", "RankedPvP" }

function GreatVault.Invalidate()
    cache = nil
    runCache = nil
    worldCache = nil
end

function GreatVault.NoteMapsUpdated()
    mapsReady = true
end

function GreatVault.PrepareForNewRuns()
    mapsReady = false
    mapsRequested = false
    retriedShortHistory = false
end

function GreatVault.RequestRunData()
    if mapsRequested then
        return
    end
    if not (C_MythicPlus and type(C_MythicPlus.RequestMapInfo) == "function") then
        mapsReady = true
        return
    end
    mapsRequested = true
    Utils.Call(C_MythicPlus.RequestMapInfo)
end

local function ActivitySort(left, right)
    if left.type ~= right.type then
        return left.type < right.type
    end
    return left.index < right.index
end

local function RawActivities()
    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetActivities) == "function") then
        return {}
    end

    local activities = Utils.Call(C_WeeklyRewards.GetActivities)
    if type(activities) ~= "table" then
        return {}
    end
    return activities
end

local function IsDisplayActivity(activity)
    if type(activity) ~= "table" then
        return false
    end

    if not Utils.IsUsableNumber(activity.type) or not Utils.IsUsableNumber(activity.index) then
        return false
    end

    if not Utils.IsUsableNumber(activity.threshold) or not Utils.IsUsableNumber(activity.progress) then
        return false
    end

    local concessions = Utils.ThresholdType("Concession")
    local alsoReceive = Utils.ThresholdType("AlsoReceive")
    local none = Utils.ThresholdType("None")
    if Utils.SameType(activity.type, concessions) or Utils.SameType(activity.type, alsoReceive) or Utils.SameType(activity.type, none) then
        return false
    end

    return true
end

function GreatVault.CategoryName(activityType)
    if Utils.SameType(activityType, Utils.ThresholdType("Raid")) then
        return Utils.GlobalString("RAIDS", "Raid")
    end
    if Utils.SameType(activityType, Utils.ThresholdType("Activities")) then
        return Utils.GlobalString("DUNGEONS", "Dungeons")
    end
    if Utils.SameType(activityType, Utils.ThresholdType("World")) then
        return Utils.GlobalString("WORLD", "World")
    end
    if Utils.SameType(activityType, Utils.ThresholdType("RankedPvP")) then
        return Utils.GlobalString("PVP", "PvP")
    end
    return "Great Vault"
end

function GreatVault.UnitName(activity)
    if Utils.SameType(activity.type, Utils.ThresholdType("Raid")) then
        return "Raid Bosses"
    end
    if Utils.SameType(activity.type, Utils.ThresholdType("Activities")) then
        if Utils.IsHeroicDungeonTier(activity.activityTierID) then
            return "Heroic"
        end
        return "Mythic+"
    end
    if Utils.SameType(activity.type, Utils.ThresholdType("World")) then
        return "World"
    end
    if Utils.SameType(activity.type, Utils.ThresholdType("RankedPvP")) then
        return "PvP"
    end
    return "Activities"
end

function GreatVault.QualifierText(activity)
    if not Utils.IsUsableNumber(activity.level) then
        return nil
    end

    if Utils.SameType(activity.type, Utils.ThresholdType("Raid")) then
        return Utils.DifficultyName(activity.level)
    end

    if Utils.SameType(activity.type, Utils.ThresholdType("Activities")) then
        if Utils.IsHeroicDungeonTier(activity.activityTierID) then
            return "Heroic"
        end
        if activity.level >= 1 then
            return "+" .. activity.level
        end
        if activity.level == 0 then
            return "Mythic"
        end
        return nil
    end

    if Utils.SameType(activity.type, Utils.ThresholdType("World")) then
        if activity.level > 0 then
            local pattern = Utils.GlobalString("GREAT_VAULT_WORLD_TIER", "Tier %d")
            return string.format(pattern, activity.level)
        end
        return nil
    end

    if Utils.SameType(activity.type, Utils.ThresholdType("RankedPvP")) then
        if PVPUtil and type(PVPUtil.GetTierName) == "function" then
            local name = Utils.Call(PVPUtil.GetTierName, activity.level)
            if Utils.IsUsableString(name) then
                return name
            end
        end
    end
end

local function MapName(mapID)
    if not Utils.IsUsableNumber(mapID) then
        return nil
    end

    if C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local name = Utils.Call(C_ChallengeMode.GetMapUIInfo, mapID)
        if Utils.IsUsableString(name) then
            return name
        end
    end

    return "Mythic+ " .. mapID
end

local function HistoryLength(history)
    return type(history) == "table" and #history or -1
end

local function CompletionTime(date)
    if type(date) ~= "table" then
        return nil
    end
    if not Utils.IsUsableNumber(date.year) or not Utils.IsUsableNumber(date.month) or not Utils.IsUsableNumber(date.monthDay) then
        return nil
    end
    local hour = Utils.IsUsableNumber(date.hour) and date.hour or 0
    local minute = Utils.IsUsableNumber(date.minute) and date.minute or 0
    return (((date.year * 12 + date.month) * 31 + date.monthDay) * 24 + hour) * 60 + minute
end

local function SortRunsByTime(runs)
    table.sort(runs, function(left, right)
        local leftTime = left.completedAt
        local rightTime = right.completedAt
        if leftTime and rightTime and leftTime ~= rightTime then
            return leftTime < rightTime
        end
        if leftTime and not rightTime then
            return true
        end
        if rightTime and not leftTime then
            return false
        end
        if left.level ~= right.level then
            return left.level > right.level
        end
        return (left.name or "") < (right.name or "")
    end)
end

local function ReadRunHistory()
    if not (C_MythicPlus and type(C_MythicPlus.GetRunHistory) == "function") then
        return nil
    end

    -- The second argument includes runs that finished over time. Those still count for the Great Vault.
    local candidates = {
        Utils.Call(C_MythicPlus.GetRunHistory, false, true, true),
        Utils.Call(C_MythicPlus.GetRunHistory, false, true),
        Utils.Call(C_MythicPlus.GetRunHistory, false, false, true),
        Utils.Call(C_MythicPlus.GetRunHistory, false, false),
    }

    local best
    local bestCount = -1
    for _, history in ipairs(candidates) do
        local count = HistoryLength(history)
        if count > bestCount then
            best = history
            bestCount = count
        end
    end
    return best
end

local function CompletedRuns()
    if runCache then
        return runCache
    end

    local history = ReadRunHistory()
    if type(history) ~= "table" then
        GreatVault.RequestRunData()
        return {}
    end

    local runs = {}
    for _, run in ipairs(history) do
        if type(run) == "table" and Utils.IsUsableNumber(run.level) and run.level >= 1 then
            runs[#runs + 1] = {
                level = run.level,
                mapID = Utils.IsUsableNumber(run.mapChallengeModeID) and run.mapChallengeModeID or nil,
                name = MapName(run.mapChallengeModeID),
                completed = run.completed ~= false,
                completedAt = CompletionTime(run.completionDate),
                kind = "keystone",
            }
        end
    end

    local numMythicPlus = 0
    if C_WeeklyRewards and type(C_WeeklyRewards.GetNumCompletedDungeonRuns) == "function" then
        local _, _, mythicPlus = Utils.Call(C_WeeklyRewards.GetNumCompletedDungeonRuns)
        numMythicPlus = tonumber(mythicPlus) or 0
    end
    local historyShort = numMythicPlus > #runs
    if not mapsReady or (historyShort and not retriedShortHistory) then
        if mapsReady and historyShort then
            retriedShortHistory = true
            mapsRequested = false
        end
        GreatVault.RequestRunData()
        if not mapsReady then
            SortRunsByTime(runs)
            return runs
        end
    end

    SortRunsByTime(runs)

    runCache = runs
    return runCache
end

local function DungeonCounts()
    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetNumCompletedDungeonRuns) == "function") then
        return 0, 0, 0
    end

    local heroic, mythic, mythicPlus = Utils.Call(C_WeeklyRewards.GetNumCompletedDungeonRuns)
    return tonumber(heroic) or 0, tonumber(mythic) or 0, tonumber(mythicPlus) or 0
end

function GreatVault.DungeonRows(threshold)
    local rows = {}
    local runs = CompletedRuns()
    local counted = 0
    local limit = Utils.IsUsableNumber(threshold) and threshold or 0
    local byLevel = {}
    for _, run in ipairs(runs) do
        byLevel[#byLevel + 1] = run
    end
    table.sort(byLevel, function(left, right)
        if left.level ~= right.level then
            return left.level > right.level
        end
        local leftTime = left.completedAt or 0
        local rightTime = right.completedAt or 0
        if leftTime ~= rightTime then
            return leftTime < rightTime
        end
        return (left.name or "") < (right.name or "")
    end)
    local countsFor = {}
    local rewardRun
    for index, run in ipairs(byLevel) do
        if index <= limit then
            countsFor[run] = true
            if index == limit then
                rewardRun = run
            end
        end
    end

    for _, run in ipairs(runs) do
        local counts = countsFor[run] == true
        if counts then
            counted = counted + 1
        end
        rows[#rows + 1] = {
            name = run.name,
            level = run.level,
            counts = counts,
            setsReward = run == rewardRun,
            text = string.format("+%d %s%s", run.level, run.name or "Mythic+", run.completed and "" or " (incomplete)"),
        }
    end

    if not Utils.IsUsableNumber(threshold) or counted >= threshold then
        return rows
    end

    local heroic, mythic = DungeonCounts()
    local missing = threshold - counted

    while mythic > 0 and missing > 0 do
        rows[#rows + 1] = {
            name = "Mythic dungeon",
            level = 0,
            counts = true,
            setsReward = missing == 1,
            text = "Mythic dungeon",
        }
        mythic = mythic - 1
        missing = missing - 1
        counted = counted + 1
    end

    while heroic > 0 and missing > 0 do
        rows[#rows + 1] = {
            name = "Heroic dungeon",
            level = -1,
            counts = true,
            setsReward = missing == 1,
            text = "Heroic dungeon",
        }
        heroic = heroic - 1
        missing = missing - 1
    end

    return rows
end

local function EncounterName(encounterID)
    if not Utils.IsUsableNumber(encounterID) or type(EJ_GetEncounterInfo) ~= "function" then
        return nil, nil
    end

    local name, _, journalEncounterID, _, _, journalInstanceID = Utils.Call(EJ_GetEncounterInfo, encounterID)
    local instanceName
    if Utils.IsUsableNumber(journalInstanceID) and type(EJ_GetInstanceInfo) == "function" then
        instanceName = Utils.Call(EJ_GetInstanceInfo, journalInstanceID)
    end

    if not Utils.IsUsableString(name) then
        name = nil
    end
    if not Utils.IsUsableString(instanceName) then
        instanceName = nil
    end
    return name, instanceName, journalInstanceID, journalEncounterID
end

function GreatVault.RaidRows(activityType, index, threshold)
    if BGV.Rewards and BGV.Rewards.EnsureJournal then
        BGV.Rewards.EnsureJournal()
    end
    local rows = {}
    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetActivityEncounterInfo) == "function") then
        return rows
    end

    local encounters = Utils.Call(C_WeeklyRewards.GetActivityEncounterInfo, activityType, index)
    if type(encounters) ~= "table" then
        return rows
    end

    local killed = {}
    for _, encounter in ipairs(encounters) do
        if type(encounter) == "table" and Utils.IsUsableNumber(encounter.bestDifficulty) and encounter.bestDifficulty > 0 then
            killed[#killed + 1] = encounter
        end
    end

    table.sort(killed, function(left, right)
        if left.bestDifficulty ~= right.bestDifficulty then
            return left.bestDifficulty > right.bestDifficulty
        end
        return (left.uiOrder or 0) < (right.uiOrder or 0)
    end)

    local countedUntil = {}
    local limit = Utils.IsUsableNumber(threshold) and threshold or 0
    for killIndex, encounter in ipairs(killed) do
        if killIndex <= limit then
            countedUntil[encounter] = killIndex
        end
    end

    local ordered = {}
    for _, encounter in ipairs(encounters) do
        ordered[#ordered + 1] = encounter
    end
    table.sort(ordered, function(left, right)
        if left.instanceID ~= right.instanceID then
            return (left.instanceID or 0) < (right.instanceID or 0)
        end
        local leftKilled = (left.bestDifficulty or 0) > 0
        local rightKilled = (right.bestDifficulty or 0) > 0
        if leftKilled ~= rightKilled then
            return leftKilled
        end
        return (left.uiOrder or 0) < (right.uiOrder or 0)
    end)

    for _, encounter in ipairs(ordered) do
        local name, instanceName, journalInstanceID, journalEncounterID = EncounterName(encounter.encounterID)
        local difficultyName = Utils.DifficultyName(encounter.bestDifficulty)
        local killIndex = countedUntil[encounter]
        rows[#rows + 1] = {
            name = name or ("Encounter " .. tostring(encounter.encounterID)),
            instanceName = instanceName,
            journalInstanceID = Utils.IsUsableNumber(journalInstanceID) and journalInstanceID or nil,
            journalEncounterID = Utils.IsUsableNumber(journalEncounterID) and journalEncounterID or nil,
            activityEncounterID = Utils.IsUsableNumber(encounter.encounterID) and encounter.encounterID or nil,
            difficultyID = Utils.IsUsableNumber(encounter.bestDifficulty) and encounter.bestDifficulty or nil,
            uiOrder = Utils.IsUsableNumber(encounter.uiOrder) and encounter.uiOrder or nil,
            difficultyName = difficultyName,
            defeated = Utils.IsUsableNumber(encounter.bestDifficulty) and encounter.bestDifficulty > 0,
            counts = killIndex ~= nil,
            setsReward = killIndex == limit and limit > 0,
        }
    end

    return rows
end

local function WorldProgress()
    if worldCache then
        return worldCache
    end

    worldCache = {}
    local worldType = Utils.ThresholdType("World")
    if not worldType or not (C_WeeklyRewards and type(C_WeeklyRewards.GetSortedProgressForActivity) == "function") then
        return worldCache
    end

    local progress = Utils.Call(C_WeeklyRewards.GetSortedProgressForActivity, worldType, true)
    if type(progress) ~= "table" then
        return worldCache
    end

    for _, tier in ipairs(progress) do
        if type(tier) == "table" and Utils.IsUsableNumber(tier.numPoints) and tier.numPoints > 0 then
            worldCache[#worldCache + 1] = {
                difficulty = Utils.IsUsableNumber(tier.difficulty) and tier.difficulty or 0,
                count = tier.numPoints,
            }
        end
    end

    return worldCache
end

function GreatVault.WorldRows(threshold)
    local rows = {}
    local remaining = Utils.IsUsableNumber(threshold) and threshold or 0

    for _, tier in ipairs(WorldProgress()) do
        local used = math.min(tier.count, math.max(remaining, 0))
        local text
        if tier.difficulty > 1 then
            text = string.format("Delve tier %d x%d", tier.difficulty, tier.count)
        else
            text = string.format("World activities x%d", tier.count)
        end

        rows[#rows + 1] = {
            difficulty = tier.difficulty,
            count = tier.count,
            used = used,
            counts = used > 0,
            text = text,
        }
        remaining = remaining - used
    end

    return rows
end

local function FindNext(activity, activities)
    local nextSlot
    for _, candidate in ipairs(activities) do
        if candidate ~= activity and Utils.SameType(candidate.type, activity.type) and candidate.index > activity.index then
            if not nextSlot or candidate.index < nextSlot.index then
                nextSlot = candidate
            end
        end
    end
    return nextSlot
end

local function BuildSlot(activity, activities)
    local unlocked = activity.progress >= activity.threshold
    local nextSlot = FindNext(activity, activities)
    local slot = {
        type = activity.type,
        index = activity.index,
        id = Utils.IsUsableNumber(activity.id) and activity.id or nil,
        activityTierID = Utils.IsUsableNumber(activity.activityTierID) and activity.activityTierID or nil,
        threshold = activity.threshold,
        progress = activity.progress,
        level = Utils.IsUsableNumber(activity.level) and activity.level or nil,
        unlocked = unlocked,
        category = GreatVault.CategoryName(activity.type),
        unit = GreatVault.UnitName(activity),
        qualifier = GreatVault.QualifierText(activity),
        raidString = Utils.IsUsableString(activity.raidString) and activity.raidString or nil,
        itemLevel = nil,
        itemQuality = nil,
        upgrade = unlocked and BGV.Rewards.GetNextIncrease(activity) or nil,
        runs = nil,
        encounters = nil,
        worldTiers = nil,
        nextThreshold = nextSlot and nextSlot.threshold or nil,
        nextProgress = nextSlot and nextSlot.progress or nil,
        nextIndex = nextSlot and nextSlot.index or nil,
        source = activity,
    }

    local reward = BGV.Rewards.ResolveReward(activity)
    if type(reward) == "table" then
        slot.itemLevel = reward.itemLevel
        slot.itemQuality = reward.qualityName
        slot.upgradeTrack = reward.upgradeTrack
        slot.upgradeLevel = reward.upgradeLevel
        slot.upgradeMax = reward.upgradeMax
        slot.rewardIcon = reward.icon
    end

    if Utils.SameType(activity.type, Utils.ThresholdType("Activities")) then
        slot.runs = GreatVault.DungeonRows(activity.threshold)
    elseif Utils.SameType(activity.type, Utils.ThresholdType("Raid")) then
        slot.encounters = GreatVault.RaidRows(activity.type, activity.index, activity.threshold)
        slot.killSummary = GreatVault.KillSummary(slot.encounters)
    elseif Utils.SameType(activity.type, Utils.ThresholdType("World")) then
        slot.worldTiers = GreatVault.WorldRows(activity.threshold)
    end

    return slot
end

function GreatVault.KillSummary(encounters)
    if type(encounters) ~= "table" then
        return nil
    end

    local counts = {}
    local order = {}
    for _, encounter in ipairs(encounters) do
        if encounter.defeated and type(encounter.difficultyName) == "string" then
            if not counts[encounter.difficultyName] then
                order[#order + 1] = encounter.difficultyName
                counts[encounter.difficultyName] = 0
            end
            counts[encounter.difficultyName] = counts[encounter.difficultyName] + 1
        end
    end

    if #order == 0 then
        return nil
    end

    local parts = {}
    for _, name in ipairs(order) do
        parts[#parts + 1] = string.format("%s x%d", name, counts[name])
    end
    return table.concat(parts, ", ")
end

function GreatVault.GetSnapshot()
    if cache then
        return cache
    end

    local activities = {}
    for _, activity in ipairs(RawActivities()) do
        if IsDisplayActivity(activity) then
            activities[#activities + 1] = activity
        end
    end

    table.sort(activities, ActivitySort)

    local snapshot = {}
    for _, activity in ipairs(activities) do
        snapshot[#snapshot + 1] = BuildSlot(activity, activities)
    end

    table.sort(snapshot, function(left, right)
        local leftOrder, rightOrder = 99, 99
        for index, name in ipairs(DISPLAY_ORDER) do
            if Utils.SameType(left.type, Utils.ThresholdType(name)) then
                leftOrder = index
            end
            if Utils.SameType(right.type, Utils.ThresholdType(name)) then
                rightOrder = index
            end
        end
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end
        return left.index < right.index
    end)

    cache = snapshot
    return cache
end

function GreatVault.SlotFor(activityType, index)
    for _, slot in ipairs(GreatVault.GetSnapshot()) do
        if Utils.SameType(slot.type, activityType) and slot.index == index then
            return slot
        end
    end
end

function GreatVault.ProgressText(slot)
    return string.format("%d / %d %s", slot.progress, slot.threshold, slot.unit)
end

function GreatVault.DetailText(slot)
    local lines = {}
    if type(slot.killSummary) == "string" and slot.killSummary ~= "" then
        lines[#lines + 1] = "Kills: " .. slot.killSummary
    end
    local reward = GreatVault.RewardText(slot)
    if type(reward) == "string" and reward ~= "" then
        lines[#lines + 1] = reward
    end
    if #lines == 0 then
        return nil
    end
    return table.concat(lines, "\n")
end

function GreatVault.RewardText(slot)
    if type(slot.upgradeTrack) == "string"
        and Utils.IsUsableNumber(slot.upgradeLevel)
        and Utils.IsUsableNumber(slot.upgradeMax)
        and Utils.IsUsableNumber(slot.itemLevel) then
        return string.format(
            "Reward: %s %d/%d (%d ilvl)",
            slot.upgradeTrack,
            slot.upgradeLevel,
            slot.upgradeMax,
            slot.itemLevel
        )
    end
    if Utils.IsUsableNumber(slot.itemLevel) then
        return string.format("%d ilvl", slot.itemLevel)
    end
end
