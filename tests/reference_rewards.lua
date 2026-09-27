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

-- Loot database (DatabaseLevels / DatabaseItems / ClearDatabase): its own caches.
local dbBatches, dbLevels, dbRaid = {}, {}, nil

-- World spec answers: the vault's (by loot spec) and the database's (by class and spec).
local worldAnswers, dbWorldAnswers = {}, {}

-- The season's dungeons from its challenge maps ({ instanceID, name }), kept once resolved.
local seasonDungeons

if type(R.ShowingWeeklyProgress) ~= "function" then
    function R.ShowingWeeklyProgress()
        return not C_WeeklyRewards.CanClaimRewards() and not C_WeeklyRewards.HasGeneratedRewards()
    end
end

function R.IsScanning()
    return scanning
end

-- The vault's lists; the database keeps its reads and only rebuilds its level tables.
function R.InvalidateIcons()
    batches = {}
    worldAnswers = {}
    seasonDungeons = nil
    dbLevels = {}
end

function R.ClearDatabase()
    dbBatches, dbLevels, dbRaid = {}, {}, nil
    dbWorldAnswers = {}
end

local function IsGear(itemID)
    local _, _, _, equipLoc, _, classID = GetItemInfoInstant(itemID)
    return (classID == 2 or classID == 4) and VAULT_EQUIP[equipLoc] == true
end

-- `python scenarios.py --naive`: the same reader without isolation (no detach, no restore), the
-- old design's failure mode, to show the checks catch it.
local naive = rawget(_G, "BGV_REFERENCE_NAIVE") == true

local depth = 0

-- Reads with the loot filter set to classID/specID (the player's class and loot spec by default).
local function WithScan(fn, classID, specID)
    if not classID then
        classID = select(3, UnitClass("player"))
        specID = Utils.LootSpecID()
    end
    if depth > 0 and not naive then
        -- A nested read (another addon calling in mid-scan): its own filter, then the outer one back.
        local outerClass, outerSpec = EJ_GetLootFilter()
        if outerClass ~= classID or outerSpec ~= (specID or 0) then
            EJ_SetLootFilter(classID, specID or 0)
        end
        depth = depth + 1
        local ok, err = pcall(fn)
        depth = depth - 1
        local nowClass, nowSpec = EJ_GetLootFilter()
        if nowClass ~= outerClass or nowSpec ~= outerSpec then
            EJ_SetLootFilter(outerClass, outerSpec)
        end
        if not ok then
            error(err, 0)
        end
        return
    end
    if naive then
        EJ_SetLootFilter(classID, specID or 0)
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
    depth = 1
    local saved = {
        difficulty = EJ_GetDifficulty(),
        slot = C_EncounterJournal.GetSlotFilter(),
        instance = guide and guide.instanceID,
        encounter = guide and guide.encounterID,
    }
    if not saved.instance then
        -- No guide selection: the journal's own, from its link (|Hjournal:0:instanceID:...|h).
        local link = select(8, EJ_GetInstanceInfo())
        saved.instance = type(link) == "string" and tonumber(link:match("journal:%d+:(%d+)")) or nil
    end
    saved.classID, saved.specID = EJ_GetLootFilter()
    specID = specID or 0
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
    depth = 0
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
    local function Add(info, bossID)
        local itemID = info and info.itemID
        if not itemID or not IsGear(itemID) then
            return
        end
        if seen[itemID] then
            seen[itemID].bosses[bossID or info.encounterID or 0] = true
            return
        end
        local name = C_Item.GetItemInfo(itemID)
        if type(name) == "string" and name ~= "" then
            local entry = {
                itemID = itemID,
                name = name,
                icon = C_Item.GetItemIconByID(itemID),
                encounterID = bossID or info.encounterID,
                instanceID = instanceID,
                bosses = { [bossID or info.encounterID or 0] = true },
            }
            seen[itemID] = entry
            entries[#entries + 1] = entry
        else
            pending = true
        end
    end
    local function ReadRows(bossID)
        local count = EJ_GetNumLoot() or 0
        if count == 0 and EJ_IsLootListOutOfDate() then
            pending = true
        end
        for row = 1, count do
            Add(C_EncounterJournal.GetLootInfoByIndex(row), bossID)
        end
    end
    local index = 1
    while true do
        local _, _, bossID = EJ_GetEncounterInfoByIndex(index, instanceID)
        if not bossID then
            break
        end
        if not bossSet or bossSet[bossID] then
            EJ_SelectEncounter(bossID)
            ReadRows(bossID)
        end
        index = index + 1
    end
    if index == 1 then
        -- The journal lists no bosses (keystone dungeons in game): read the whole instance.
        ReadRows(nil)
    end
    return entries, pending
end

-- opts (database): { cache, classID, specID }; without it the vault's own cache and loot spec.
local function Collect(jobs, opts)
    local cache = opts and opts.cache or batches
    local entries, seen, pending = {}, {}, false
    local todo = {}
    for _, job in ipairs(jobs) do
        job.key = BatchKey(job.instanceID, job.difficultyID, job.bossSet)
        if opts then
            job.key = table.concat({ "db", job.key, tostring(opts.classID), tostring(opts.specID) }, ":")
        end
        if not cache[job.key] then
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
                    cache[job.key] = batch
                end
            end
        end, opts and opts.classID, opts and opts.specID)
    end
    for _, job in ipairs(jobs) do
        for _, entry in ipairs(cache[job.key] or {}) do
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

local function SeasonDungeons()
    if seasonDungeons then
        return seasonDungeons
    end
    local maps = C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then
        return nil
    end
    local list = {}
    for _, mapID in ipairs(maps) do
        local name, _, _, _, _, gameMapID = C_ChallengeMode.GetMapUIInfo(mapID)
        local instanceID = gameMapID and C_EncounterJournal.GetInstanceForGameMap(gameMapID)
        if not instanceID then
            return nil
        end
        list[#list + 1] = { instanceID = instanceID, name = name }
    end
    seasonDungeons = list
    return list
end

local function DungeonJobs(slot)
    local dungeons = SeasonDungeons()
    if not dungeons then
        return nil
    end
    local difficultyID = Utils.IsHeroicDungeonTier(slot.activityTierID) and DifficultyUtil.ID.DungeonHeroic or 8
    local jobs = {}
    for _, dungeon in ipairs(dungeons) do
        jobs[#jobs + 1] = { instanceID = dungeon.instanceID, difficultyID = difficultyID, name = dungeon.name }
    end
    return jobs
end

-- World items any of `specs` can use, with the spec answers cached in `answers`.
local function WorldList(specs, answers)
    local entries, pending = {}, false
    for _, itemID in ipairs(BGV.WorldLoot or {}) do
        if IsGear(itemID) then
            local usable = answers[itemID]
            if usable == nil and #specs == 0 then
                -- No specs (all classes): no spec filter.
                usable = true
            elseif usable == nil then
                local itemSpecs = GetItemSpecInfo(itemID)
                if type(itemSpecs) == "table" then
                    usable = false
                    for _, id in ipairs(itemSpecs) do
                        for _, spec in ipairs(specs) do
                            usable = usable or id == spec
                        end
                    end
                    answers[itemID] = usable
                end
            end
            if usable == nil then
                pending = true
            elseif usable then
                local name = C_Item.GetItemInfo(itemID)
                if type(name) == "string" then
                    entries[#entries + 1] = {
                        itemID = itemID, name = name, icon = C_Item.GetItemIconByID(itemID),
                        source = BGV.WorldLootSource and BGV.WorldLootSource[itemID] or "World",
                    }
                else
                    pending = true
                end
            end
        end
    end
    return entries, pending
end

local function WorldItems()
    local specID = Utils.LootSpecID()
    local key = tostring(specID)
    worldAnswers[key] = worldAnswers[key] or {}
    return WorldList({ specID }, worldAnswers[key])
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

----------------------------------------------------------------------------------------------------
-- Loot database: everything the vault can award this season, for any class and spec, at the
-- vault's item level for a raid difficulty, keystone level or world tier.
----------------------------------------------------------------------------------------------------

local RAID_MYTHIC, RAID_CEILING = 334, 344

-- Tiers and item levels this character's vault has shown, kept per season in its saved variables.
local function SeasonData()
    local season = C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetCurrentSeason()
    local saved = BetterGreatVaultDB
    if not (type(season) == "number" and season > 0 and type(saved) == "table") then
        return { tiers = {}, levels = {} }
    end
    local data = saved.rewardData
    if type(data) ~= "table" or data.season ~= season then
        data = { season = season }
        saved.rewardData = data
    end
    data.tiers = data.tiers or {}
    data.levels = data.levels or {}
    return data
end

local function Learn()
    local data = SeasonData()
    local T = Enum.WeeklyRewardChestThresholdType
    for _, activity in ipairs(C_WeeklyRewards.GetActivities() or {}) do
        local tier = activity.activityTierID
        if type(tier) == "number" and tier > 0 then
            if activity.type == T.Activities and not Utils.IsHeroicDungeonTier(tier) then
                data.tiers.mplus = tier
            elseif activity.type == T.World then
                data.tiers.world = tier
            end
        end
    end
    -- Slot item levels only describe a level in the progress week (a claim week's are rolled items).
    if not R.ShowingWeeklyProgress() then
        return data
    end
    for _, slot in ipairs(BGV.GreatVault.GetSnapshot() or {}) do
        if slot.unlocked and type(slot.level) == "number" and type(slot.itemLevel) == "number" then
            local kind
            if slot.type == T.Raid and slot.level ~= 16 then
                kind = "raid"
            elseif slot.type == T.Activities and not Utils.IsHeroicDungeonTier(slot.activityTierID) then
                kind = "mplus"
            elseif slot.type == T.World then
                kind = "world"
            end
            if kind then
                data.levels[kind] = data.levels[kind] or {}
                data.levels[kind][slot.level] = slot.itemLevel
            end
        end
    end
    return data
end

local function Steps(nextStep)
    local steps, level = {}, 0
    for _ = 1, 30 do
        local nextLevel, itemLevel = nextStep(level)
        if not (type(nextLevel) == "number" and nextLevel > level and type(itemLevel) == "number" and itemLevel > 0) then
            break
        end
        steps[#steps + 1] = { level = nextLevel, itemLevel = itemLevel }
        level = nextLevel
    end
    return steps
end

local function TierSteps(tier)
    if not tier then
        return {}
    end
    return Steps(function(level)
        local hasData, _, nextLevel, itemLevel = C_WeeklyRewards.GetNextActivitiesIncrease(tier, level)
        if hasData == true then
            return nextLevel, itemLevel
        end
    end)
end

local function KeystoneSteps()
    if type(C_WeeklyRewards.GetNextMythicPlusIncrease) ~= "function" then
        return {}
    end
    return Steps(function(level)
        local hasData, nextLevel, itemLevel = C_WeeklyRewards.GetNextMythicPlusIncrease(level)
        if hasData == true then
            return nextLevel, itemLevel
        end
    end)
end

local function AtStep(steps, level)
    local itemLevel
    for _, step in ipairs(steps) do
        if step.level <= level then
            itemLevel = step.itemLevel
        end
    end
    return itemLevel
end

local function BuildLevels(source)
    local data = Learn()
    local learned = data.levels[source] or {}
    local levels = {}
    if source == "raid" then
        for _, difficultyID in ipairs({ 17, 14, 15, 16 }) do
            local label = Utils.DifficultyName(difficultyID) or tostring(difficultyID)
            if difficultyID == 16 then
                levels[#levels + 1] = { level = 16, label = label, itemLevel = RAID_MYTHIC, ceiling = RAID_CEILING }
            else
                levels[#levels + 1] = { level = difficultyID, label = label, itemLevel = learned[difficultyID] }
            end
        end
    else
        -- The tier this character's vault reported, else the season's (256 keystone, 249 world).
        local tier = data.tiers[source]
        local steps = TierSteps(tier)
        if #steps == 0 then
            local seasonTier = ({ mplus = 256, world = 249 })[source]
            if seasonTier ~= tier then
                local seasonSteps = TierSteps(seasonTier)
                if #seasonSteps > 0 then
                    tier, steps = seasonTier, seasonSteps
                end
            end
        end
        if source == "mplus" and #steps == 0 then
            steps = KeystoneSteps()
        end
        -- Below the first step: a learned slot value there, else the vault's own answer below 0.
        local base
        local first = steps[1]
        if first then
            for level, itemLevel in pairs(learned) do
                if level < first.level and itemLevel < first.itemLevel then
                    base = itemLevel
                end
            end
            if not base and tier then
                local hasData, _, nextLevel, itemLevel = C_WeeklyRewards.GetNextActivitiesIncrease(tier, -1)
                if hasData == true and type(nextLevel) == "number" and nextLevel < first.level
                    and type(itemLevel) == "number" and itemLevel > 0 and itemLevel < first.itemLevel then
                    base = itemLevel
                end
            end
        end
        local low = source == "mplus" and 2 or 1
        local last = #steps > 0 and steps[#steps].level or (source == "mplus" and 10 or 8)
        for level = low, last do
            -- Live steps first; learned values only fill the gaps.
            local itemLevel = AtStep(steps, level) or learned[level]
            if not itemLevel and first and level < first.level then
                itemLevel = base
            end
            levels[#levels + 1] = { level = level, label = (source == "mplus" and "+" or "Tier ") .. level, itemLevel = itemLevel }
        end
    end
    -- The highest level with a known item level; none if nothing is known.
    for index = #levels, 1, -1 do
        if levels[index].itemLevel then
            levels.default = levels[index].level
            break
        end
    end
    return levels
end

function R.DatabaseLevels(source)
    if not dbLevels[source] then
        dbLevels[source] = BuildLevels(source)
    end
    return dbLevels[source]
end

-- Every boss of the season's raids (the vault's boss list, killed or not), by instance.
local function SeasonRaid()
    if dbRaid then
        return dbRaid
    end
    local scope = { instances = {}, bossSets = {}, names = {}, order = {}, ceiling = {} }
    local byInstance = {}
    local rows = C_WeeklyRewards.GetActivityEncounterInfo(Enum.WeeklyRewardChestThresholdType.Raid, 1) or {}
    for _, row in ipairs(rows) do
        local name, _, bossID, _, _, instanceID = EJ_GetEncounterInfo(row.encounterID)
        if bossID and instanceID then
            if not byInstance[instanceID] then
                byInstance[instanceID] = {}
                scope.instances[#scope.instances + 1] = instanceID
            end
            table.insert(byInstance[instanceID], { bossID = bossID, name = name, uiOrder = row.uiOrder or 0 })
        end
    end
    for position, instanceID in ipairs(scope.instances) do
        local list = byInstance[instanceID]
        table.sort(list, function(left, right)
            return left.uiOrder < right.uiOrder
        end)
        scope.bossSets[instanceID] = {}
        for index, boss in ipairs(list) do
            scope.bossSets[instanceID][boss.bossID] = true
            scope.names[boss.bossID] = boss.name
            scope.order[boss.bossID] = position * 100 + index
            if #list >= 3 and index > #list - 2 then
                scope.ceiling[boss.bossID] = true
            end
        end
    end
    if #scope.instances > 0 then
        dbRaid = scope
    end
    return scope
end

local function LevelInfo(source, level)
    for _, info in ipairs(R.DatabaseLevels(source)) do
        if info.level == level then
            return info
        end
    end
    return {}
end

local function Stamp(entries, info, extra)
    local stamped = {}
    for index, raw in ipairs(entries) do
        local entry = {
            itemID = raw.itemID, name = raw.name, icon = raw.icon, encounterID = raw.encounterID,
            quality = 4, itemLevel = info.itemLevel,
        }
        extra(entry, raw)
        stamped[index] = entry
    end
    return stamped
end

function R.DatabaseItems(source, level, classID, specID)
    if type(classID) ~= "number" then
        return {}, false
    end
    specID = specID or 0
    local info = LevelInfo(source, level)
    local opts = { cache = dbBatches, classID = classID, specID = specID }
    if source == "raid" then
        local scope = SeasonRaid()
        if #scope.instances == 0 then
            -- The vault's boss list isn't there yet.
            return {}, true
        end
        local jobs = {}
        for _, instanceID in ipairs(scope.instances) do
            jobs[#jobs + 1] = { instanceID = instanceID, difficultyID = level, bossSet = scope.bossSets[instanceID] }
        end
        local entries, pending = Collect(jobs, opts)
        return Stamp(entries, info, function(entry, raw)
            local atCeiling = false
            for bossID in pairs(raw.bosses or {}) do
                atCeiling = atCeiling or scope.ceiling[bossID] == true
            end
            if info.ceiling and atCeiling then
                entry.itemLevel = info.ceiling
            end
            entry.bossOrder = scope.order[raw.encounterID]
            entry.source = scope.names[raw.encounterID]
        end), pending
    elseif source == "mplus" then
        local jobs = DungeonJobs({})
        if not jobs then
            return {}, true
        end
        local names = {}
        for _, job in ipairs(jobs) do
            names[job.instanceID] = job.name
        end
        local entries, pending = Collect(jobs, opts)
        return Stamp(entries, info, function(entry, raw)
            entry.source = names[raw.instanceID]
        end), pending
    elseif source == "world" then
        local specs = {}
        if specID > 0 then
            specs[1] = specID
        else
            for index = 1, 5 do
                local id = GetSpecializationInfoForClassID(classID, index)
                if id then
                    specs[#specs + 1] = id
                end
            end
        end
        local key = classID .. ":" .. specID
        dbWorldAnswers[key] = dbWorldAnswers[key] or {}
        local entries, pending = WorldList(specs, dbWorldAnswers[key])
        for _, entry in ipairs(entries) do
            entry.quality = 4
            entry.itemLevel = info.itemLevel
        end
        return entries, pending
    end
    return {}, false
end
