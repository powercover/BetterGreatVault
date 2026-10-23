if not unpack then unpack = table.unpack end
local fails = 0
local function check(c, m) if not c then fails = fails + 1; print("FAIL: " .. m) end end
-- journal: raid 900 (bosses 9001..9004), dungeons 501..503 (whole-dungeon loot, no boss list)
local RAID, DUNGEONS = 900, { 501, 502, 503 }
local function Bosses(inst) if inst == RAID then return { 9001, 9002, 9003, 9004 } end return {} end
local ej = { class = 1, spec = 71, diff = 14, instance = nil, boss = nil, slot = 15 }
local classOf = { [71] = 1, [72] = 1, [73] = 1, [62] = 8, [63] = 8, [64] = 8 }
local items = {}
local function Item(id, specs) items[id] = specs end
for b = 1, 4 do
  Item(9000 + b * 10 + 1, { 71, 72, 73 }); Item(9000 + b * 10 + 2, { 62, 63, 64 }); Item(9000 + b * 10 + 3, { 71, 62 })
end
for _, d in ipairs(DUNGEONS) do Item(d * 10 + 1, { 71, 72 }); Item(d * 10 + 2, { 62 }) end
local function Usable(id)
  local s = items[id]
  if ej.class == 0 then return true end
  for _, spec in ipairs(s) do
    if classOf[spec] == ej.class and (ej.spec == 0 or ej.spec == spec) then return true end
  end
  return false
end
local function Rows()
  local rows = {}
  if ej.instance == RAID then
    local list = ej.boss and { ej.boss } or Bosses(RAID)
    for _, b in ipairs(list) do
      for k = 1, 3 do
        local id = 9000 + (b - 9000) * 10 + k
        if Usable(id) then rows[#rows + 1] = { itemID = id, encounterID = b, handError = (k == 3) or nil } end
      end
    end
  elseif ej.instance then
    for k = 1, 2 do
      local id = ej.instance * 10 + k
      if Usable(id) then rows[#rows + 1] = { itemID = id, encounterID = 0 } end
    end
  end
  return rows
end
function EJ_GetLootFilter() return ej.class, ej.spec end
function EJ_SetLootFilter(c, s) ej.class, ej.spec = c, s end
function EJ_ResetLootFilter() ej.class, ej.spec = 0, 0 end
function EJ_GetDifficulty() return ej.diff end
function EJ_SetDifficulty(d) ej.diff = d end
function EJ_IsValidInstanceDifficulty() return true end
function EJ_SelectInstance(id) ej.instance = id; ej.boss = nil end
function EJ_SelectEncounter(id) ej.boss = id end
function EJ_GetEncounterInfoByIndex(i, inst)
  local b = Bosses(inst or ej.instance)[i]
  if b then return "Boss " .. b, "", b, 0, "", inst, b + 50000, 0 end
end
function EJ_GetEncounterInfo(id) return "Boss " .. id, "", id, 0, "", RAID, id + 50000 end
function EJ_GetInstanceInfo(id) return "Instance " .. tostring(id or ej.instance) end
function EJ_IsLootListOutOfDate() return false end
function EJ_GetNumLoot() return #Rows() end
function EJ_GetCurrentTier() return 13 end
function EJ_SelectTier() end
C_EncounterJournal = {
  GetLootInfoByIndex = function(i) return Rows()[i] end,
  GetSlotFilter = function() return ej.slot end,
  SetSlotFilter = function(s) ej.slot = s end,
  ResetSlotFilter = function() ej.slot = 15 end,
  GetInstanceForGameMap = function(m) return m end,
}
Enum = { WeeklyRewardChestThresholdType = { Activities = 1, Raid = 3, World = 6 }, ItemSlotFilterType = { NoFilter = 15 }, ItemQuality = { Epic = 4 } }
DifficultyUtil = {
  ID = { PrimaryRaidLFR = 17, PrimaryRaidNormal = 14, PrimaryRaidHeroic = 15, PrimaryRaidMythic = 16 },
  GetDifficultyName = function(d) return ({ [17] = "Raid Finder", [14] = "Normal", [15] = "Heroic", [16] = "Mythic" })[d] end,
}
C_ChallengeMode = { GetMapTable = function() return DUNGEONS end, GetMapUIInfo = function(id) return "Dungeon " .. id, id, 0, 0, 0, id end }
C_MythicPlus = {
  GetCurrentSeason = function() return 18 end, -- Midnight Season 2
  GetRewardLevelForDifficultyLevel = function(l) return ({ [2] = 305, [3] = 305, [8] = 305 })[l] or 300, 0 end,
}
local ACTIVITIES = {
  { type = 1, index = 1, level = 15, activityTierID = 256, progress = 1, threshold = 1 },
  { type = 6, index = 1, level = 1, activityTierID = 249, progress = 2, threshold = 2 },
  { type = 3, index = 1, level = 15, activityTierID = 0, progress = 9, threshold = 2 },
}
local STEPS = { [256] = { { 4, 308 }, { 6, 311 }, { 7, 315 }, { 10, 318 } }, [249] = { { 2, 282 }, { 3, 285 }, { 8, 305 } } }
C_WeeklyRewards = {
  CanClaimRewards = function() return false end,
  HasGeneratedRewards = function() return false end,
  GetActivities = function() return ACTIVITIES end,
  GetNextActivitiesIncrease = function(tier, level)
    local steps = STEPS[tier]
    if not steps then return false end
    for _, s in ipairs(steps) do if s[1] > level then return true, tier, s[1], s[2] end end
    return false
  end,
  GetActivityEncounterInfo = function()
    local t = {}
    for i, b in ipairs(Bosses(RAID)) do t[i] = { encounterID = b, bestDifficulty = 0, uiOrder = i, instanceID = 2000 } end
    return t
  end,
  GetDifficultyIDForActivityTier = function() return 8 end,
}
function GetItemSpecInfo(id) return items[id] end
function GetItemInfoInstant(id) return id, "Armor", "Cloth", "INVTYPE_HEAD", 7, 4, 1 end
C_Item = { GetItemInfo = function(id) return "Item " .. id, "link", 3 end, GetItemIconByID = function() return 7 end }
function UnitClass() return "Warrior", "WARRIOR", 1 end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 71 end
function GetLootSpecialization() return 0 end
function GetSpecializationInfoForClassID(c, i)
  local t = { [0] = { 74, 79, 81 }, [1] = { 71, 72, 73 }, [8] = { 62, 63, 64 } }
  local pets = { [74] = "Ferocity", [79] = "Cunning", [81] = "Tenacity" }
  if pets[t[c] and t[c][i]] then return t[c][i], pets[t[c][i]] end
  local id = t[c] and t[c][i]
  if id then return id, "Spec " .. id end
end
C_SpecializationInfo = { GetNumSpecializationsForClassID = function() return 3 end }
BetterGreatVaultDB = {}
local BGV = {}
for _, f in ipairs({ "Locales/Locales.lua", "Utils.lua", "WorldLoot.lua", "Rewards.lua", "GreatVault.lua" }) do assert(loadfile(f))("BetterGreatVault", BGV) end
BGV.WorldLoot = { 111, 112, 113 }
Item(111, { 71 }); Item(112, { 62, 63 }); Item(113, { 64 })
BGV.WorldLootSource = { [111] = "Delves", [112] = "Prey", [113] = "World Boss" }
BGV.GreatVault.GetSnapshot = function()
  return { { type = 6, level = 1, unlocked = true, itemLevel = 279 }, { type = 3, level = 15, unlocked = true, itemLevel = 321 } }
end
local R = BGV.Rewards
local function Levels(source)
  local t = {}
  for _, l in ipairs(R.DatabaseLevels(source)) do
    t[#t + 1] = l.label .. "=" .. tostring(l.itemLevel) .. (l.ceiling and ("/" .. l.ceiling) or "")
  end
  return table.concat(t, " ") .. " default=" .. tostring(R.DatabaseLevels(source).default)
end
print("raid  ", Levels("raid"))
print("mplus ", Levels("mplus"))
print("world ", Levels("world"))
check(R.DatabaseLevels("mplus")[7].itemLevel == 315, "+8 should be 315 (vault step), got " .. tostring(R.DatabaseLevels("mplus")[7].itemLevel))
check(R.DatabaseLevels("mplus")[1].itemLevel == nil, "+2 unknown without the vault's own answer (no GetRewardLevelForDifficultyLevel)")
check(R.DatabaseLevels("world")[1].itemLevel == 279, "world tier 1 from the character's own vault")
check(R.DatabaseLevels("raid")[3].itemLevel == 321, "heroic learned from the character's vault")
check(R.DatabaseLevels("raid")[1].itemLevel == nil, "raid finder unknown")
local function Items(source, level, class, spec)
  local list, pending = R.DatabaseItems(source, level, class, spec)
  local t = {}
  for _, e in ipairs(list) do t[#t + 1] = e.itemID .. "@" .. tostring(e.itemLevel) end
  table.sort(t)
  return table.concat(t, " "), pending, list
end
local before = { ej.class, ej.spec, ej.diff, ej.slot }
local text, pending = Items("raid", 16, 8, 0)
print("raid mage all specs mythic:", text, pending)
check(text:find("9042@344") and text:find("9012@334") and not text:find("9011"), "mage raid items with ceiling on last two bosses")
text = Items("raid", 16, 8, 63)
print("raid mage 63 mythic:", text)
check(not text:find("9013"), "spec 63 must not see 71/62-only items")
text = Items("mplus", 10, 1, 72)
print("mplus warrior 72 +10:", text)
check(text == "5011@318 5021@318 5031@318", "M+ +10 items for spec 72")
text = Items("mplus", 8, 1, 72)
check(text == "5011@315 5021@315 5031@315", "M+ +8 items at 315: " .. text)
text = Items("world", 3, 8, 0)
print("world mage all tier3:", text)
check(text == "112@285 113@285", "world items for all mage specs")
text = Items("raid", 17, 1, 71)
check(text:find("9011@nil"), "raid finder item level unknown stays nil: " .. text)
check(ej.class == before[1] and ej.spec == before[2] and ej.diff == before[3] and ej.slot == before[4], "journal restored")
-- the database keeps items flagged unusable for the viewing character; the vault's own list doesn't
local mageAll = Items("raid", 16, 8, 0)
check(mageAll:find("9013@334"), "database keeps a handError item for another class: " .. mageAll)
local vaultSlot = { type = 3, index = 1, unlocked = true, level = 16, itemLevel = 334,
  encounters = { { journalInstanceID = RAID, journalEncounterID = 9001, uiOrder = 1, difficultyID = 16, defeated = true, name = "Boss 9001" } } }
local vault = R.ItemsForSlot(vaultSlot)
local vaultIDs = {}
for _, e in ipairs(vault) do vaultIDs[#vaultIDs + 1] = e.itemID end
table.sort(vaultIDs)
check(table.concat(vaultIDs, ",") == "9011", "vault list still drops the handError item: " .. table.concat(vaultIDs, ","))
-- a read nested inside a database read puts the outer filter back
check(ej.class == before[1] and ej.spec == before[2], "journal restored after the vault read")
check(not R.IsScanning(), "scan closed")
check(BetterGreatVaultDB.rewardData and BetterGreatVaultDB.rewardData.tiers.mplus == 256, "tiers remembered for the season")
R.ClearDatabase()
print(fails == 0 and "database smoke checks passed" or (fails .. " failed"))
