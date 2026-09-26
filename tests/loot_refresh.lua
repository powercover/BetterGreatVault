-- Cold journal after a character change:
-- the season map is empty, then only the first dungeons have a name
-- and a placeholder icon, and item data for the new character is not loaded.
-- A completed slot must not keep that partial list.

if not unpack and table.unpack then
    unpack = table.unpack
end

local failures = 0

local function check(condition, message)
    if condition then
        return
    end
    failures = failures + 1
    print("FAIL: " .. message)
end

local DUNGEONS = {
    { instanceID = 101, mapID = 1, uiMapID = 1001, name = "Ara-Kara" },
    { instanceID = 102, mapID = 2, uiMapID = 1002, name = "City of Echoes" },
    { instanceID = 103, mapID = 3, uiMapID = 1003, name = "The Dawnbreaker" },
    { instanceID = 104, mapID = 4, uiMapID = 1004, name = "Priory of the Sacred Flame" },
    { instanceID = 105, mapID = 5, uiMapID = 1005, name = "Eco-Dome" },
    { instanceID = 106, mapID = 6, uiMapID = 1006, name = "Halls of Atonement" },
    { instanceID = 107, mapID = 7, uiMapID = 1007, name = "Operation Floodgate" },
    { instanceID = 108, mapID = 8, uiMapID = 1008, name = "Tazavesh" },
}

local PLACEHOLDER_ICON = 136243

local state = {
    guid = "Player-1-A",
    classID = 11,
    spec = 577,
    specReady = false,
    maps = nil,
    selected = nil,
    outOfDate = {},
    loot = {},
    items = {},
    requested = {},
}

local function knownItem(itemID)
    local row = state.items[itemID]
    if not row or row.unknown then
        return nil
    end
    return row
end

Enum = {
    WeeklyRewardChestThresholdType = {
        Raid = 1,
        Activities = 2,
        World = 3,
    },
    ItemClass = { Weapon = 2, Armor = 4 },
    ItemArmorSubclass = { Cosmetic = 5 },
}

C_WeeklyRewards = {
    CanClaimRewards = function()
        return false
    end,
    HasGeneratedRewards = function()
        return false
    end,
}

C_ChallengeMode = {}

function C_ChallengeMode.GetMapTable()
    return state.maps
end

function C_ChallengeMode.GetMapUIInfo(mapID)
    for _, dungeon in ipairs(DUNGEONS) do
        if dungeon.mapID == mapID then
            return dungeon.name, dungeon.mapID, 0, 0, 0, dungeon.uiMapID
        end
    end
end

function EJ_GetCurrentTier()
    return 1
end

function EJ_SelectTier()
end

function EJ_GetInstanceForMap(uiMapID)
    for _, dungeon in ipairs(DUNGEONS) do
        if dungeon.uiMapID == uiMapID then
            return dungeon.instanceID
        end
    end
end

function EJ_GetInstanceByIndex()
    return nil
end

function EJ_GetInstanceInfo(instanceID)
    for _, dungeon in ipairs(DUNGEONS) do
        if dungeon.instanceID == instanceID then
            return dungeon.name
        end
    end
end

function EJ_SelectInstance(instanceID)
    state.selected = instanceID
end

function EJ_IsLootListOutOfDate()
    return state.outOfDate[state.selected] == true
end

function EJ_GetNumLoot()
    if state.outOfDate[state.selected] then
        return 0
    end
    local rows = state.loot[state.selected]
    return rows and #rows or 0
end

function EJ_SetLootFilter()
end

function EJ_GetLootFilter()
    return nil
end

function EJ_ResetLootFilter()
end

function EJ_SetDifficulty()
end

function EJ_GetDifficulty()
    return nil
end

C_EncounterJournal = {}

-- GetMapUIInfo's last return (dungeon.uiMapID here) stands in for the game map ID.
function C_EncounterJournal.GetInstanceForGameMap(mapID)
    return EJ_GetInstanceForMap(mapID)
end

function C_EncounterJournal.GetLootInfoByIndex(index)
    local rows = state.loot[state.selected]
    return rows and rows[index] or nil
end

function C_EncounterJournal.ResetSlotFilter()
end

function GetSpecialization()
    return 1
end

function GetSpecializationInfo()
    return state.spec
end

function UnitClass()
    return "Druid", "DRUID", state.classID
end

function UnitGUID()
    return state.guid
end

function GetItemSpecInfo(itemID)
    if not state.specReady or not knownItem(itemID) then
        return nil
    end
    return { state.spec }
end

function GetItemInfoInstant(itemID)
    local row = knownItem(itemID)
    if not row then
        return nil
    end
    return itemID, "Armor", "Cloth", row.equip, row.icon, 4, 1
end

C_Item = {}

function C_Item.GetItemInfo(itemID)
    local row = knownItem(itemID)
    if not row then
        return nil
    end
    return row.name, "item:" .. itemID, 4
end

function C_Item.GetItemIconByID(itemID)
    local row = knownItem(itemID)
    return row and row.icon or nil
end

function C_Item.RequestLoadItemDataByID(itemID)
    state.requested[itemID] = true
end

local BGV = {}

local function loadModule(path)
    local chunk, err = loadfile(path)
    if not chunk then
        error(err)
    end
    chunk("BetterGreatVault", BGV)
end

loadModule("Utils.lua")
loadModule("Rewards.lua")
loadModule("LootTable.lua")

BGV.WorldLoot = { 93001, 93002, 93003 }

local function clearLists()
    BGV.LootTable.Invalidate()
    BGV.Rewards.InvalidateIcons()
end

local function learn(itemID, name, icon, equip)
    state.items[itemID] = {
        name = name,
        icon = icon,
        equip = equip,
    }
end

local function journalRow(itemID, name, icon, encounterID)
    return {
        itemID = itemID,
        name = name,
        icon = icon,
        encounterID = encounterID,
    }
end

local function publishMaps()
    state.maps = {}
    for _, dungeon in ipairs(DUNGEONS) do
        state.maps[#state.maps + 1] = dungeon.mapID
    end
end

local function coldDungeons()
    publishMaps()
    state.loot = {}
    state.outOfDate = {}
    for index, dungeon in ipairs(DUNGEONS) do
        local itemID = 80000 + index
        if index == 1 then
            learn(itemID, "Spymaster's Wrap", 60000 + index, "INVTYPE_HEAD")
            state.loot[dungeon.instanceID] = {
                journalRow(itemID, "Spymaster's Wrap", 60000 + index, 70000 + index),
            }
        elseif index <= 3 then
            state.items[itemID] = { unknown = true }
            state.loot[dungeon.instanceID] = {
                journalRow(itemID, dungeon.name, PLACEHOLDER_ICON, 70000 + index),
            }
        else
            state.outOfDate[dungeon.instanceID] = true
            state.loot[dungeon.instanceID] = {
                journalRow(80000 + index, dungeon.name, PLACEHOLDER_ICON, 70000 + index),
            }
        end
    end
end

local function finishDungeons()
    state.outOfDate = {}
    state.specReady = true
    for index, dungeon in ipairs(DUNGEONS) do
        local itemID = 80000 + index
        local name = "Helm of " .. dungeon.name
        local icon = 60000 + index
        learn(itemID, name, icon, "INVTYPE_HEAD")
        state.loot[dungeon.instanceID] = {
            journalRow(itemID, name, icon, 70000 + index),
        }
    end
end

local function raidSlot(index, instanceID, encounterID)
    return {
        type = 1,
        index = index,
        unlocked = true,
        itemLevel = 334,
        level = 16,
        encounters = {
            {
                name = "Boss " .. index,
                journalInstanceID = instanceID,
                journalEncounterID = encounterID,
                dungeonEncounterID = encounterID,
                activityEncounterID = encounterID,
                instanceID = instanceID,
                difficultyID = 16,
                uiOrder = 1,
                defeated = true,
            },
        },
    }
end

local mplusSlot = {
    type = 2,
    index = 1,
    unlocked = true,
    itemLevel = 320,
    level = 8,
}

local worldSlot = {
    type = 3,
    index = 1,
    unlocked = true,
    itemLevel = 310,
    level = 1,
    qualifier = "Delves",
}

local function sources(items)
    local counts = {}
    for _, entry in ipairs(items) do
        local name = entry.source or ""
        counts[name] = (counts[name] or 0) + 1
    end
    return counts
end

local function itemIDs(items)
    local ids = {}
    for _, entry in ipairs(items) do
        ids[#ids + 1] = entry.itemID
    end
    return ids
end

local function coldLogin()
    clearLists()
    state.guid = "Player-1-A"
    state.classID = 11
    state.spec = 577
    state.specReady = false
    state.maps = nil
    state.loot = {}
    state.outOfDate = {}
    state.items = {}
    state.requested = {}

    learn(91001, "Duskblaze Pauldrons", 40001, "INVTYPE_SHOULDER")
    learn(93001, "World Helm", 70001, "INVTYPE_HEAD")
    learn(93002, "World Pendant", 70002, "INVTYPE_NECK")
    learn(93003, "World Trinket", 70003, "INVTYPE_TRINKET")

    local earlyItems, earlyPending = BGV.LootTable.ItemsFor(mplusSlot)
    check(earlyPending == true, "M+ slot was saved before the season map loaded")
    check(#earlyItems == 0, "M+ slot listed loot before any dungeon was available")

    coldDungeons()
    state.loot[201] = { journalRow(91001, "Duskblaze Pauldrons", 40001, 501) }
    state.outOfDate[202] = true
    state.loot[202] = { journalRow(91099, "Boss 2", PLACEHOLDER_ICON, 502) }
    local raidReady, raidReadyPending = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(raidReadyPending == false, "a loaded raid slot should finish")
    check(raidReady[1] and raidReady[1].itemID == 91001, "ready raid slot lost its item")

    local raidCold, raidColdPending = BGV.LootTable.ItemsFor(raidSlot(2, 202, 502))
    check(raidColdPending == true, "raid slot with an unloaded journal was treated as finished")
    check(#raidCold == 0, "unloaded raid slot showed placeholder loot")

    local mplusCold, mplusPending = BGV.LootTable.ItemsFor(mplusSlot)
    check(mplusPending == true, "completed M+ slot was treated as finished while later dungeons were still loading")
    local coldSources = sources(mplusCold)
    check(coldSources["Ara-Kara"] == 1, "the one dungeon that had real loot did not show it")
    check(coldSources["City of Echoes"] == nil, "City of Echoes loaded its name without loot")
    check(coldSources["The Dawnbreaker"] == nil, "The Dawnbreaker loaded its name without loot")
    for _, entry in ipairs(mplusCold) do
        check(entry.name ~= entry.source, "dungeon name was listed as the item: " .. tostring(entry.name))
        check(entry.icon ~= PLACEHOLDER_ICON, "placeholder icon was shown as loot")
    end
    check(state.requested[80002] == true, "unresolved M+ item was not asked to load")

    local reelCold = BGV.Rewards.PossibleIcons(mplusSlot)
    check(#reelCold == 1, "M+ reel kept placeholders, count " .. tostring(#reelCold))

    local worldCold, worldPending = BGV.LootTable.ItemsFor(worldSlot)
    check(worldPending == true, "world slot was saved before spec item data loaded")
    check(#worldCold == 0, "world slot showed items before they loaded")

    finishDungeons()
    learn(91002, "Vault Legguards", 40002, "INVTYPE_LEGS")
    state.loot[202] = { journalRow(91002, "Vault Legguards", 40002, 502) }

    local mplusDone, mplusDonePending = BGV.LootTable.ItemsFor(mplusSlot)
    check(mplusDonePending == false, "M+ slot stayed pending after every dungeon loaded")
    local doneSources = sources(mplusDone)
    for _, dungeon in ipairs(DUNGEONS) do
        check(doneSources[dungeon.name] ~= nil, "missing loot for " .. dungeon.name)
    end
    for _, entry in ipairs(mplusDone) do
        check(type(entry.itemID) == "number", "finished M+ row has no item")
        check(entry.name ~= entry.source, "finished row is still just the dungeon name")
        check(entry.icon and entry.icon ~= PLACEHOLDER_ICON, "finished row still uses the placeholder icon")
    end

    local reelDone = BGV.Rewards.PossibleIcons(mplusSlot)
    check(#reelDone == #DUNGEONS, "M+ reel stayed on the first dungeons, count " .. tostring(#reelDone))

    local raidDone, raidDonePending = BGV.LootTable.ItemsFor(raidSlot(2, 202, 502))
    check(raidDonePending == false, "raid slot stayed pending after its journal loaded")
    check(raidDone[1] and raidDone[1].itemID == 91002, "raid slot stayed empty or kept the placeholder")

    local worldDone, worldDonePending = BGV.LootTable.ItemsFor(worldSlot)
    check(worldDonePending == false, "world slot stayed pending after item data loaded")
    check(#worldDone == 3, "world slot stayed empty, count " .. tostring(#worldDone))
end

local function characterChange()
    clearLists()
    state.guid = "Player-1-A"
    state.spec = 577
    state.classID = 11
    state.specReady = true
    state.outOfDate = {}
    learn(91001, "Duskblaze Pauldrons", 40001, "INVTYPE_SHOULDER")
    state.loot[201] = { journalRow(91001, "Duskblaze Pauldrons", 40001, 501) }

    local first = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(itemIDs(first)[1] == 91001, "first character raid item was not cached")

    state.guid = "Player-1-B"
    state.spec = 256
    state.classID = 2
    learn(91011, "Other Pauldrons", 40011, "INVTYPE_SHOULDER")
    state.loot[201] = { journalRow(91011, "Other Pauldrons", 40011, 501) }

    local second, pending = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(pending == false, "second character raid slot did not finish")
    check(itemIDs(second)[1] == 91011, "second character still saw the previous character's loot")
    check(itemIDs(second)[1] ~= 91001, "previous character item leaked into the new list")
end

local function journalEventRefreshesSameCharacter()
    clearLists()
    state.guid = "Player-1-A"
    state.spec = 577
    state.specReady = true
    state.outOfDate = {}
    learn(91001, "Duskblaze Pauldrons", 40001, "INVTYPE_SHOULDER")
    state.loot[201] = { journalRow(91001, "Duskblaze Pauldrons", 40001, 501) }
    local before = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(itemIDs(before)[1] == 91001, "setup item missing before the journal event")

    learn(91012, "Updated Pauldrons", 40012, "INVTYPE_SHOULDER")
    state.loot[201] = { journalRow(91012, "Updated Pauldrons", 40012, 501) }
    local stale = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(itemIDs(stale)[1] == 91001, "a finished list should stay cached until the journal event")

    BGV.LootTable.Invalidate()
    local fresh = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(itemIDs(fresh)[1] == 91012, "journal refresh kept the stale item")
end

local function sameCharacterZoneKeepsTheList()
    clearLists()
    state.guid = "Player-1-A"
    state.spec = 577
    state.specReady = true
    state.outOfDate = {}
    learn(91001, "Duskblaze Pauldrons", 40001, "INVTYPE_SHOULDER")
    state.loot[201] = { journalRow(91001, "Duskblaze Pauldrons", 40001, 501) }
    BGV.LootTable.OnCharacterChanged()
    local cached = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(itemIDs(cached)[1] == 91001, "zone setup item missing")

    learn(91012, "Updated Pauldrons", 40012, "INVTYPE_SHOULDER")
    state.loot[201] = { journalRow(91012, "Updated Pauldrons", 40012, 501) }
    BGV.LootTable.OnCharacterChanged()
    local kept = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(itemIDs(kept)[1] == 91001, "a zone change on the same character cleared finished loot")

    state.guid = "Player-1-C"
    state.spec = 256
    learn(91013, "Third Pauldrons", 40013, "INVTYPE_SHOULDER")
    state.loot[201] = { journalRow(91013, "Third Pauldrons", 40013, 501) }
    BGV.LootTable.OnCharacterChanged()
    local switched, pending = BGV.LootTable.ItemsFor(raidSlot(1, 201, 501))
    check(pending == false, "character change left the raid slot pending")
    check(itemIDs(switched)[1] == 91013, "character change kept the previous character's item")
end

coldLogin()
characterChange()
journalEventRefreshesSameCharacter()
sameCharacterZoneKeepsTheList()

if failures > 0 then
    error(failures .. " loot refresh check(s) failed")
end

print("loot refresh checks passed")
