-- GreatVault.NextStep: the fewest activities that unlock a slot or raise a reward, counted from
-- this week's runs, kills and delve tiers; unlocking wins a tie; nothing when all is done.
if not unpack then unpack = table.unpack end
local fails = 0
local function check(ok, message) if not ok then fails = fails + 1; print("NEXT FAIL: " .. message) end end

function GetLocale() return "enUS" end
Enum = { WeeklyRewardChestThresholdType = { Activities = 1, Raid = 3, World = 6, RankedPvP = 2 } }
DifficultyUtil = { GetDifficultyName = function(d) return ({ [17] = "Raid Finder", [14] = "Normal", [15] = "Heroic", [16] = "Mythic" })[d] end }
RAIDS, DUNGEONS, WORLD = "Raids", "Dungeons", "World"
local runs, heroic, mythic, tiers = {}, 0, 0, {}
C_MythicPlus = {
  GetRunHistory = function() return runs end,
  RequestMapInfo = function() end,
}
C_ChallengeMode = { GetMapUIInfo = function(id) return "Dungeon " .. id end }
C_WeeklyRewards = {
  GetNumCompletedDungeonRuns = function() return heroic, mythic, #runs end,
  GetSortedProgressForActivity = function() return tiers end,
}
BetterGreatVaultDB = {}
local BGV = {}
for _, f in ipairs({ "Locales/Locales.lua", "Utils.lua", "GreatVault.lua" }) do assert(loadfile(f))("BetterGreatVault", BGV) end
local GV = BGV.GreatVault
GV.NoteMapsUpdated()
local T = Enum.WeeklyRewardChestThresholdType

local function Slot(t, index, threshold, progress, extra)
  local slot = { type = t, index = index, threshold = threshold, progress = progress, unlocked = progress >= threshold,
    category = GV.CategoryName(t), unit = GV.UnitName({ type = t }) }
  for k, v in pairs(extra or {}) do slot[k] = v end
  return slot
end
local function Text(step)
  if not step then return "none" end
  local what, gives = GV.NextStepText(step)
  return what .. " | " .. gives
end

-- dungeons: +8, +8, +10, +7 done; slot 1 (best run, +10) wants +12, slot 2 (4th best, +7) wants +10
runs = { { level = 8, mapChallengeModeID = 1 }, { level = 8, mapChallengeModeID = 2 }, { level = 10, mapChallengeModeID = 3 }, { level = 7, mapChallengeModeID = 4 } }
GV.Invalidate()
local week = {
  Slot(T.Activities, 1, 1, 4, { itemLevel = 266, upgrade = { nextLevel = 12, itemLevel = 272 } }),
  Slot(T.Activities, 2, 4, 4, { itemLevel = 259, upgrade = { nextLevel = 10, itemLevel = 266 } }),
  Slot(T.Activities, 3, 8, 4),
}
local step = GV.NextStep(week)
check(step and step.slot.index == 1 and step.need == 1 and step.itemLevel == 272, "one +12 raises the first dungeon slot: " .. Text(step))
check(Text(step) == "+12 or higher x1 | Dungeons, slot 1, rises to 272 item level", "its lines: " .. Text(step))
-- slot 1 at its best: the next is slot 2, which needs three more at +10 (one done), or slot 3: four more to unlock
week[1].upgrade = nil
step = GV.NextStep(week)
check(step and step.slot.index == 2 and step.need == 3, "three +10s raise slot 2: " .. Text(step))
-- as many to unlock as to raise: unlocking wins
week[3].progress = 5
step = GV.NextStep(week)
check(step and step.slot.index == 3 and step.need == 3 and step.itemLevel == nil, "a tie: the unlock: " .. Text(step))
check(Text(step) == "Dungeons x3 | Dungeons, slot 3, unlocks", "the unlock's lines: " .. Text(step))
-- an upgrade the vault gives no item level for, or one no higher than now: not a step
week[3].progress = 4
week[2].upgrade = { nextLevel = 10 }
step = GV.NextStep(week)
check(step and step.slot.index == 3 and step.need == 4, "no item level: no upgrade step: " .. Text(step))
week[2].upgrade = { nextLevel = 10, itemLevel = 259 }
step = GV.NextStep(week)
check(step and step.slot.index == 3, "no higher: no upgrade step: " .. Text(step))

-- raid: kills on a difficulty count toward it and the ones below; Heroic x2, Normal x2, two left
local bosses = {
  { difficultyID = 15 }, { difficultyID = 15 }, { difficultyID = 14 }, { difficultyID = 14 }, { difficultyID = 0 }, {},
}
local raid = {
  Slot(T.Raid, 1, 2, 4, { itemLevel = 285, upgrade = { nextLevel = 16, itemLevel = 298 }, encounters = bosses }),
  Slot(T.Raid, 2, 4, 4, { itemLevel = 272, upgrade = { nextLevel = 15, itemLevel = 285 }, encounters = bosses }),
  Slot(T.Raid, 3, 6, 4, { encounters = bosses }),
}
step = GV.NextStep(raid)
check(step and step.slot.index == 3 and step.need == 2, "raid: two each way; the unlock wins: " .. Text(step))
raid[3] = nil
step = GV.NextStep(raid)
check(Text(step) == "Mythic or higher x2 | Raids, slot 1, rises to 298 item level", "raid: two each; the higher item level wins: " .. Text(step))
bosses[3].difficultyID = 15
step = GV.NextStep(raid)
check(step and step.slot.index == 2 and step.need == 1 and Text(step):find("^Heroic or higher x1"), "raid: one more Heroic boss raises slot 2: " .. Text(step))
raid[1].upgrade.nextLevel = 99
raid[2].upgrade = nil
check(GV.NextStep(raid) == nil, "a difficulty it can't rank: no step")

-- world: Tier 8 x2, Tier 5 x3
tiers = { { difficulty = 8, numPoints = 2 }, { difficulty = 5, numPoints = 3 } }
GV.Invalidate()
local world = {
  Slot(T.World, 1, 2, 5, { itemLevel = 282, upgrade = { nextLevel = 11, itemLevel = 289 } }),
  Slot(T.World, 2, 4, 5, { itemLevel = 272, upgrade = { nextLevel = 8, itemLevel = 282 } }),
  Slot(T.World, 3, 8, 5),
}
step = GV.NextStep(world)
check(Text(step) == "Tier 11 or higher x2 | World, slot 1, rises to 289 item level", "world: " .. Text(step))
world[1].upgrade = nil
step = GV.NextStep(world)
check(Text(step) == "Tier 8 or higher x2 | World, slot 2, rises to 282 item level", "world, slot 2: " .. Text(step))

-- everything done: nothing; PvP and unreadable slots are left out
local done = {
  Slot(T.Raid, 1, 2, 2, { itemLevel = 298 }),
  Slot(T.RankedPvP, 1, 1, 0),
  Slot(T.World, 1, 2, 0, { progress = setmetatable({}, {}) }),
}
check(GV.NextStep(done) == nil, "all done: no step: " .. Text(GV.NextStep(done)))
check(GV.NextStep(nil) == nil and GV.NextStep({ false, "x" }) == nil, "no snapshot: no step")

print(fails == 0 and "next step checks passed" or (fails .. " failed"))
