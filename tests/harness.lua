-- Glue between ej_model.lua and the addon: loads the addon's non-UI files, stands in for its UI
-- (the Great Vault pump, the hovered reel, the loot table's polling), builds vault slots, computes
-- the ground truth from the model's database and runs the scenario checks.
--
-- Only public entry points are relied on: BGV.Rewards.ItemsForSlot(slot), PossibleIcons(slot),
-- InvalidateIcons(), IsScanning() (optional), BGV.LootTable.ItemsFor(slot) (optional), and Core.lua's
-- event frame through the model's event bus.

local M = EJModel
local H = {}
Harness = H

local BGV = {}
H.BGV = BGV

local function pack(...)
    return { n = select("#", ...), ... }
end

local function Noop() end

local function Permissive(t)
    return setmetatable(t or {}, {
        __index = function()
            return Noop
        end,
    })
end

H.status = {}
H.counters = { itemsForSlot = 0, possibleIcons = 0, invalidations = 0 }
H.results = {}
H.info = {}

---------------------------------------------------------------------------------------------------
-- Vault slots
---------------------------------------------------------------------------------------------------

-- Best difficulty per raid boss this week (0 = not killed): Mythic and Heroic kills including the
-- last two bosses, one Normal kill and one boss not killed.
H.RAID_KILLS = { 16, 16, 15, 15, 14, 0, 16, 15 }

function H.BuildSlots()
    local encounters = {}
    for b, bossID in ipairs(M.ids.raidBosses) do
        local boss = M.bosses[bossID]
        local difficultyID = H.RAID_KILLS[b]
        encounters[b] = {
            name = boss.name,
            instanceName = M.instances[boss.instance].name,
            journalInstanceID = boss.instance,
            journalEncounterID = bossID,
            dungeonEncounterID = boss.dungeonEncounterID,
            activityEncounterID = boss.dungeonEncounterID,
            instanceID = M.instances[boss.instance].gameMapID,
            difficultyID = difficultyID,
            uiOrder = b,
            defeated = difficultyID > 0,
        }
    end
    M.weekly.raidKills = H.RAID_KILLS
    local T = Enum.WeeklyRewardChestThresholdType
    -- Tiers and item levels agree with the game's steps (ej_model.lua M.weekly): keystone tier 256
    -- (+10 = 318), world tier 249 (tier 8 = 305), raid Mythic 334. The Heroic raid slot's 311 is the
    -- harness's own choice (the game gives no step for it; only a resolved slot says).
    H.slots = {
        R1 = { type = T.Raid, index = 1, unlocked = true, level = 16, itemLevel = 334, threshold = 2, progress = 7, encounters = encounters },
        R2 = { type = T.Raid, index = 2, unlocked = true, level = 15, itemLevel = 311, threshold = 4, progress = 7, encounters = encounters },
        M1 = { type = T.Activities, index = 1, unlocked = true, level = 10, itemLevel = 318, activityTierID = 256, threshold = 1, progress = 8 },
        M2 = { type = T.Activities, index = 2, unlocked = true, level = 0, itemLevel = 272, activityTierID = 900, threshold = 4, progress = 8 },
        W1 = { type = T.World, index = 1, unlocked = true, level = 8, itemLevel = 305, activityTierID = 249, threshold = 2, progress = 3, qualifier = "Delves" },
    }
    H.slotOrder = { "M1", "M2", "R1", "R2", "W1" }
    H.vaultSlots = {}
    H.nameOf = {}
    for _, name in ipairs(H.slotOrder) do
        H.vaultSlots[#H.vaultSlots + 1] = H.slots[name]
        H.nameOf[H.slots[name]] = name
    end
end

-- Scenario helpers: change a vault slot's field (nil clears it, e.g. an item level not resolved
-- yet), or add a raid slot at another difficulty.
function H.SetSlot(name, field, value)
    H.slots[name][field] = value
end

function H.AddRaidSlot(name, level, itemLevel)
    H.AddSlot(name, "Raid", 3, level, itemLevel)
end

-- An extra unlocked vault slot, e.g. ("M3", "Activities", 3, 2, 305, 256): a keystone slot at +2.
function H.AddSlot(name, typeName, index, level, itemLevel, tier)
    local slot = {
        type = Enum.WeeklyRewardChestThresholdType[typeName], index = index, unlocked = true, level = level,
        itemLevel = itemLevel, activityTierID = tier, threshold = 8, progress = 8,
        encounters = typeName == "Raid" and H.slots.R1.encounters or nil,
    }
    H.slots[name] = slot
    H.vaultSlots[#H.vaultSlots + 1] = slot
    H.nameOf[slot] = name
end

local function SlotName(slot)
    if type(slot) ~= "table" then
        return "?"
    end
    return H.nameOf[slot] or (tostring(slot.type) .. ":" .. tostring(slot.index))
end

local function Split(csv)
    local list = {}
    for name in tostring(csv):gmatch("[^,%s]+") do
        list[#list + 1] = name
    end
    return list
end

---------------------------------------------------------------------------------------------------
-- Ground truth
---------------------------------------------------------------------------------------------------

local RANK = { [17] = 1, [14] = 2, [15] = 3, [16] = 4 }

-- The vault's raid pool as the addon documents it (Rewards.lua RaidScope): bosses killed at the
-- slot's difficulty or higher, plus every boss up to the furthest of those in journal order.
function H.RaidPool(slot)
    local want = RANK[slot.level] or 0
    local function Counts(encounter)
        return encounter.defeated and (want == 0 or (RANK[encounter.difficultyID] or 0) >= want)
    end
    local furthest
    for _, encounter in ipairs(slot.encounters) do
        if Counts(encounter) and (not furthest or encounter.uiOrder > furthest) then
            furthest = encounter.uiOrder
        end
    end
    local pool = {}
    for _, encounter in ipairs(slot.encounters) do
        if (furthest and encounter.uiOrder <= furthest) or Counts(encounter) then
            pool[#pool + 1] = encounter.journalEncounterID
        end
    end
    return pool
end

function H.SlotDifficulty(slot)
    local T = Enum.WeeklyRewardChestThresholdType
    if slot.type == T.Raid then
        return slot.level
    elseif slot.type == T.Activities then
        return M.weekly.tierDifficulty[slot.activityTierID] == 2 and 2 or 8
    end
end

-- Item IDs the slot can award for the loot spec: pool + difficulty + spec, gear only.
function H.Truth(slot, specID)
    local set, list = {}, {}
    local function Usable(item)
        return item.specs == "ALL" or M.Contains(item.specs, specID)
    end
    local function Add(itemID)
        if not set[itemID] then
            set[itemID] = true
            list[#list + 1] = itemID
        end
    end
    local T = Enum.WeeklyRewardChestThresholdType
    local difficultyID = H.SlotDifficulty(slot)
    local bosses = {}
    if slot.type == T.Raid then
        bosses = H.RaidPool(slot)
    elseif slot.type == T.Activities then
        for _, instanceID in ipairs(M.ids.seasonDungeons) do
            local instance = M.instances[instanceID]
            if instance.diffSet[difficultyID] then
                for _, bossID in ipairs(instance.bosses) do
                    bosses[#bosses + 1] = bossID
                end
            end
        end
    elseif slot.type == T.World then
        for _, itemID in ipairs(BGV.WorldLoot or {}) do
            local item = M.items[itemID]
            if item and not item.nonGear and Usable(item) then
                Add(itemID)
            end
        end
        return set, list
    end
    for _, bossID in ipairs(bosses) do
        for _, itemID in ipairs(M.bosses[bossID].loot) do
            local item = M.items[itemID]
            if not item.nonGear and M.Drops(item, difficultyID) and Usable(item) then
                Add(itemID)
            end
        end
    end
    return set, list
end

local function Describe(itemID)
    local item = M.items[itemID]
    return string.format("%s(%s)", tostring(itemID), item and item.name or "?")
end

local function Sample(list, limit)
    local parts = {}
    for index, itemID in ipairs(list) do
        if index > limit then
            parts[#parts + 1] = string.format("... +%d", #list - limit)
            break
        end
        parts[#parts + 1] = Describe(itemID)
    end
    return table.concat(parts, ", ")
end

---------------------------------------------------------------------------------------------------
-- Loading the addon
---------------------------------------------------------------------------------------------------

H.loadErrors = {}

function H.LoadFile(path, optional)
    local chunk, err = loadfile(path)
    if not chunk then
        H.loadErrors[#H.loadErrors + 1] = path .. ": " .. tostring(err)
        return false, err
    end
    M.ctx.addon = M.ctx.addon + 1
    local ok, runErr = xpcall(function()
        chunk("BetterGreatVault", BGV)
    end, debug.traceback)
    M.ctx.addon = M.ctx.addon - 1
    if not ok then
        if optional then
            H.info[#H.info + 1] = "optional " .. path .. " failed to load: " .. tostring(runErr):gsub("\n.*", "")
        else
            H.loadErrors[#H.loadErrors + 1] = path .. ": " .. tostring(runErr)
        end
        return false, runErr
    end
    return true
end

local function Status(slot)
    local name = SlotName(slot)
    local status = H.status[name]
    if not status then
        status = { calls = 0 }
        H.status[name] = status
    end
    return status, name
end

local function Observe(slot, pending, fromIcons)
    local status = Status(slot)
    status.firstAt = status.firstAt or M.clock
    if not fromIcons then
        status.calls = status.calls + 1
    end
    status.lastPending = pending == true
    if pending ~= true and not status.finishedAt then
        status.finishedAt = M.clock
        status.callsToFinish = status.calls
    end
end

function H.ResetStatus()
    H.status = {}
end

local function WrapRewards()
    local R = BGV.Rewards
    local items = R.ItemsForSlot
    R.ItemsForSlot = function(slot, ...)
        H.counters.itemsForSlot = H.counters.itemsForSlot + 1
        local result = pack(items(slot, ...))
        if type(result[1]) == "table" then
            Observe(slot, result[2], false)
        end
        return unpack(result, 1, result.n)
    end
    local icons = R.PossibleIcons
    R.PossibleIcons = function(slot, ...)
        H.counters.possibleIcons = H.counters.possibleIcons + 1
        local listCalls = H.counters.itemsForSlot
        local result = pack(icons(slot, ...))
        if type(slot) == "table" and type(R.ShowingWeeklyProgress) == "function" and R.ShowingWeeklyProgress() then
            local status = Status(slot)
            status.firstAt = status.firstAt or M.clock
            -- A reel built without going through ItemsForSlot is its own pass.
            if H.counters.itemsForSlot == listCalls then
                status.calls = status.calls + 1
            end
            if result[2] == false then
                Observe(slot, false, true)
            end
        end
        return unpack(result, 1, result.n)
    end
    local invalidate = R.InvalidateIcons
    R.InvalidateIcons = function(...)
        H.counters.invalidations = H.counters.invalidations + 1
        H.ResetStatus()
        if H.DbRestart then
            H.DbRestart("InvalidateIcons")
        end
        return invalidate(...)
    end
    local clear = R.ClearDatabase
    if type(clear) == "function" then
        R.ClearDatabase = function(...)
            H.counters.clears = (H.counters.clears or 0) + 1
            if H.DbRestart then
                H.DbRestart("ClearDatabase")
            end
            return clear(...)
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Stand-in for UI.lua: the Great Vault pump, the hovered reel and the loot table's polling
---------------------------------------------------------------------------------------------------

local function VaultOpen()
    return WeeklyRewardsFrame ~= nil and WeeklyRewardsFrame:IsShown()
end

local function ProgressWeek()
    return BGV.Rewards and type(BGV.Rewards.ShowingWeeklyProgress) == "function" and BGV.Rewards.ShowingWeeklyProgress()
end

local PUMP_STALL_DELAY = 0.25
local PUMP_STALL_RETRIES = 20

local UI = Permissive({ hooked = true })
H.UI = UI

-- UI.ScheduleContent: fills every unlocked slot's reel list, one slot at a time.
function UI.ScheduleContent(frame)
    if not ProgressWeek() then
        return
    end
    if not frame or not VaultOpen() or frame.bgvContentQueued then
        return
    end
    frame.bgvContentQueued = true
    C_Timer.After(0, function()
        frame.bgvContentQueued = nil
        if not VaultOpen() or frame.bgvPumping then
            return
        end
        frame.bgvPumping = true
        local generation = (frame.bgvPumpGen or 0) + 1
        frame.bgvPumpGen = generation
        frame.bgvPumpStalls = 0
        local index = frame.bgvPumpIndex or 1
        local function Step()
            if frame.bgvPumpGen ~= generation then
                return
            end
            if not VaultOpen() then
                frame.bgvPumping = nil
                return
            end
            local snapshot = H.vaultSlots
            while index <= #snapshot and not snapshot[index].unlocked do
                index = index + 1
            end
            frame.bgvPumpIndex = index
            if index > #snapshot then
                frame.bgvPumping = nil
                frame.bgvPumpIndex = nil
                frame.bgvPumpCount = nil
                return
            end
            local icons, pending = BGV.Rewards.PossibleIcons(snapshot[index])
            local count = type(icons) == "table" and #icons or 0
            if pending and count <= (frame.bgvPumpCount or -1) then
                frame.bgvPumpStalls = (frame.bgvPumpStalls or 0) + 1
                if frame.bgvPumpStalls <= PUMP_STALL_RETRIES then
                    C_Timer.After(PUMP_STALL_DELAY, Step)
                    return
                end
                frame.bgvPumping = nil
                frame.bgvPumpWait = true
                return
            end
            frame.bgvPumpStalls = 0
            if pending then
                frame.bgvPumpCount = count
            else
                index = index + 1
                frame.bgvPumpIndex = index
                frame.bgvPumpCount = nil
            end
            if index <= #snapshot then
                C_Timer.After(0.05, Step)
            else
                frame.bgvPumping = nil
                frame.bgvPumpIndex = nil
            end
        end
        C_Timer.After(0.05, Step)
    end)
end

local REEL_REFRESH = 0.25
local POLL_DELAY = 0.25

local function DriverUpdate(_, elapsed)
    local hover = H.hover
    if hover and VaultOpen() and hover.pending then
        hover.refreshClock = hover.refreshClock + elapsed
        if hover.refreshClock >= ((hover.count == 0) and 0 or REEL_REFRESH) then
            hover.refreshClock = 0
            local icons, pending = BGV.Rewards.PossibleIcons(hover.slot)
            hover.pending = pending == true
            hover.count = type(icons) == "table" and #icons or 0
        end
    end
    local poll = H.poll
    if poll then
        poll.clock = poll.clock + elapsed
        if poll.clock >= POLL_DELAY then
            poll.clock = 0
            for _, name in ipairs(poll.names) do
                local status = H.status[name]
                if not (status and status.finishedAt) then
                    local slot = H.slots[name]
                    if BGV.LootTable and type(BGV.LootTable.ItemsFor) == "function" then
                        BGV.LootTable.ItemsFor(slot)
                    else
                        BGV.Rewards.ItemsForSlot(slot)
                    end
                end
            end
        end
    end
    -- The loot table's database view, polling its lists while they load.
    local dbPoll = H.dbPoll
    if dbPoll then
        dbPoll.clock = dbPoll.clock + elapsed
        if dbPoll.clock >= POLL_DELAY then
            dbPoll.clock = 0
            H.DbPollOnce()
        end
    end
end

-- The Great Vault opens: Blizzard shows the frame, then UI.lua's OnShow hook schedules the reels.
function H.OpenVault()
    if not WeeklyRewardsFrame then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    end
    ShowUIPanel(WeeklyRewardsFrame)
    M.AddonCall(UI.ScheduleContent, WeeklyRewardsFrame)
end

function H.CloseVault()
    H.hover = nil
    HideUIPanel(WeeklyRewardsFrame)
end

-- The pointer moves onto a slot: the reel asks for icons, then keeps asking while they load.
function H.Hover(name)
    local slot = H.slots[name]
    H.hover = { slot = slot, refreshClock = 0, pending = false, count = 0 }
    if not VaultOpen() then
        return
    end
    local icons, pending = M.AddonCall(BGV.Rewards.PossibleIcons, slot)
    H.hover.pending = pending == true
    H.hover.count = type(icons) == "table" and #icons or 0
end

-- The loot table (minimap path) is open on these slots and polls while they load.
function H.StartPoll(csv)
    H.poll = { names = Split(csv), clock = POLL_DELAY }
end

function H.StopPoll()
    H.poll = nil
end

---------------------------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------------------------

function H.MarkUser()
    H.userSnap = M.Snapshot()
    H.userRebuilds = M.stats.agRebuilds
end

-- Returns nil on success, or the load error text.
function H.Boot(reference, testsDir)
    H.BuildSlots()
    BGV.UI = UI
    BGV.Tooltip = Permissive({})
    BGV.Minimap = Permissive({})
    BGV.Settings = Permissive({})
    BGV.GreatVault = Permissive({
        GetSnapshot = function()
            return H.vaultSlots
        end,
    })

    H.LoadFile("Locales/Locales.lua")
    H.LoadFile("Utils.lua")
    H.LoadFile("WorldLoot.lua")
    M.RegisterWorldItems(BGV.WorldLoot)
    H.LoadFile("Rewards.lua")
    if reference then
        BGV.Rewards = BGV.Rewards or {}
        H.LoadFile((testsDir or "tests") .. "/reference_rewards.lua")
    end
    -- The real GreatVault.lua for its RaidRows (the loot database's season raid scope), with the
    -- harness's vault slots standing in for its snapshot.
    local stub = BGV.GreatVault
    if not H.LoadFile("GreatVault.lua", true) then
        BGV.GreatVault = stub
    end
    BGV.GreatVault.GetSnapshot = function()
        return H.vaultSlots
    end
    H.LoadFile("LootTable.lua", true)
    H.LoadFile("Core.lua")
    if #H.loadErrors > 0 then
        return table.concat(H.loadErrors, "\n")
    end
    for _, name in ipairs({ "ItemsForSlot", "PossibleIcons", "InvalidateIcons" }) do
        if type(BGV.Rewards[name]) ~= "function" then
            return "BGV.Rewards." .. name .. " is missing"
        end
    end
    if type(BGV.Rewards.IsScanning) ~= "function" then
        H.info[#H.info + 1] = "BGV.Rewards.IsScanning() not defined"
    end
    WrapRewards()

    M.Invoke("addon", function()
        local driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", DriverUpdate)
        H.driver = driver
    end)

    M.Fire("ADDON_LOADED", "BetterGreatVault")
    M.Fire("PLAYER_LOGIN")
    M.Fire("PLAYER_ENTERING_WORLD", true, false)
    M.Run(0.2)
    H.bootStats = { rebuilds = M.stats.agRebuilds }
    H.MarkUser()
    return nil
end

---------------------------------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------------------------------

H.FINISH_LIMIT = 10
H.PASS_LIMIT = 400
H.SETTLE_LIMIT = 20

local function Result(key, status, detail)
    H.results[#H.results + 1] = { key = key, status = status, detail = detail or "" }
end

function H.Finished(name)
    local status = H.status[name]
    return status ~= nil and status.finishedAt ~= nil
end

function H.Settle(csv, maxSeconds)
    local names = Split(csv)
    return M.RunUntil(function()
        for _, name in ipairs(names) do
            if not H.Finished(name) then
                return false
            end
        end
        return true
    end, maxSeconds or H.SETTLE_LIMIT)
end

local function CheckFinish(names)
    local failures, notes = {}, {}
    for _, name in ipairs(names) do
        local status = H.status[name]
        if not status or not status.firstAt then
            failures[#failures + 1] = name .. " never requested"
        elseif not status.finishedAt then
            failures[#failures + 1] = string.format("%s still pending after %.1fs (%d passes)", name,
                M.clock - status.firstAt, status.calls)
        else
            local took = status.finishedAt - status.firstAt
            notes[#notes + 1] = string.format("%s %.2fs/%dp", name, took, status.callsToFinish or 0)
            if took > H.FINISH_LIMIT or (status.callsToFinish or 0) > H.PASS_LIMIT then
                failures[#failures + 1] = string.format("%s took %.1fs / %d passes", name, took, status.callsToFinish or 0)
            end
        end
    end
    if #failures > 0 then
        Result("b", "FAIL", table.concat(failures, "; "))
        return false
    end
    Result("b", "PASS", table.concat(notes, " "))
    return true
end

local function CheckLists(names, report)
    report = report or Result
    -- Slots nothing finished (e.g. the pump stalled before them) get polled directly for up to
    -- 10s, as an open loot table would, so this check is about the lists themselves.
    local unfinished = {}
    for _, name in ipairs(names) do
        if not H.Finished(name) then
            unfinished[#unfinished + 1] = name
        end
    end
    if #unfinished > 0 then
        local previous = H.poll
        H.StartPoll(table.concat(unfinished, ","))
        H.Settle(table.concat(unfinished, ","), 10)
        H.poll = previous
    end
    local specID = M.LootSpecID()
    local failures, notes = {}, {}
    local progress = ProgressWeek()
    for _, name in ipairs(names) do
        local slot = H.slots[name]
        local truthSet, truthList = H.Truth(slot, specID)
        local items, pending = M.AddonCall(BGV.Rewards.ItemsForSlot, slot)
        local got, dupes, broken = {}, {}, {}
        local gotList = {}
        for _, entry in ipairs(type(items) == "table" and items or {}) do
            local itemID = type(entry) == "table" and entry.itemID or nil
            if itemID then
                if got[itemID] then
                    dupes[#dupes + 1] = itemID
                end
                got[itemID] = true
                gotList[#gotList + 1] = itemID
                if type(entry.name) ~= "string" or entry.name == "" or entry.name == "Item" or not entry.icon or entry.icon == 136243 then
                    broken[#broken + 1] = itemID
                end
            end
        end
        local missing, extra = {}, {}
        for _, itemID in ipairs(truthList) do
            if not got[itemID] then
                missing[#missing + 1] = itemID
            end
        end
        for _, itemID in ipairs(gotList) do
            if not truthSet[itemID] then
                extra[#extra + 1] = itemID
            end
        end
        local problems = {}
        if pending == true then
            problems[#problems + 1] = "pending at final read"
        end
        if #missing > 0 then
            problems[#problems + 1] = string.format("missing %d/%d: %s", #missing, #truthList, Sample(missing, 3))
        end
        if #extra > 0 then
            problems[#problems + 1] = string.format("extra %d: %s", #extra, Sample(extra, 3))
        end
        if #dupes > 0 then
            problems[#problems + 1] = "duplicates: " .. Sample(dupes, 3)
        end
        if #broken > 0 then
            problems[#problems + 1] = "rows without name/icon: " .. Sample(broken, 3)
        end
        -- The reel spins the same items (the world reel is a sample of at most 20).
        if progress then
            local icons, iconsPending = M.AddonCall(BGV.Rewards.PossibleIcons, slot)
            local iconSet, iconCount, iconExtra = {}, 0, {}
            for _, icon in ipairs(type(icons) == "table" and icons or {}) do
                if icon.itemID and not iconSet[icon.itemID] then
                    iconSet[icon.itemID] = true
                    iconCount = iconCount + 1
                    if not truthSet[icon.itemID] then
                        iconExtra[#iconExtra + 1] = icon.itemID
                    end
                end
            end
            local want = #truthList
            if slot.type == Enum.WeeklyRewardChestThresholdType.World then
                want = math.min(want, 20)
            end
            if iconsPending == true then
                problems[#problems + 1] = "reel pending"
            end
            if #iconExtra > 0 then
                problems[#problems + 1] = "reel extra: " .. Sample(iconExtra, 3)
            end
            if iconCount ~= want then
                problems[#problems + 1] = string.format("reel has %d items, want %d", iconCount, want)
            end
        end
        if #problems > 0 then
            failures[#failures + 1] = name .. ": " .. table.concat(problems, ", ")
        else
            notes[#notes + 1] = string.format("%s=%d", name, #truthList)
        end
    end
    if #failures > 0 then
        report("a", "FAIL", table.concat(failures, " | "))
        return false
    end
    report("a", "PASS", table.concat(notes, " "))
    return true
end

local ALWAYS = { "classID", "specID", "slotFilter", "tier", "guideInstance", "guideEncounter",
    "guideDifficultyEvent", "guideLootEvent" }
local WITH_SELECTION = { "instance", "encounter", "difficulty", "peek" }

local function CheckRestore()
    local before, after = H.userSnap, M.Snapshot()
    local failures, notes = {}, {}
    local function Compare(field, list)
        if before[field] ~= after[field] then
            local text
            if field == "peek" then
                local function Rows(value)
                    local count = 0
                    for _ in tostring(value):gmatch("[^,]+") do
                        count = count + 1
                    end
                    return count
                end
                text = string.format("journal loot list differs (%d rows before, %d after)", Rows(before.peek), Rows(after.peek))
            else
                text = string.format("%s %s -> %s", field, tostring(before[field]), tostring(after[field]))
            end
            list[#list + 1] = text
        end
    end
    for _, field in ipairs(ALWAYS) do
        Compare(field, failures)
    end
    if before.guideInstance ~= nil then
        for _, field in ipairs(WITH_SELECTION) do
            Compare(field, failures)
        end
    else
        for _, field in ipairs(WITH_SELECTION) do
            if field ~= "peek" then
                Compare(field, notes)
            end
        end
    end
    if #failures > 0 then
        Result("c", "FAIL", table.concat(failures, "; "))
        return false
    end
    local detail = before.guideLoaded and "guide state intact" or "no guide loaded"
    if #notes > 0 then
        detail = detail .. " (no guide selection; info: " .. table.concat(notes, ", ") .. ")"
    end
    Result("c", "PASS", detail)
    return true
end

local function CheckGuideWork()
    local stats = M.stats
    local post = stats.agRebuilds - (H.userRebuilds or 0) - stats.agRebuildsInAddon
    if stats.agRebuildsInAddon > 0 or stats.agHijacks > 0 then
        local detail = string.format("%d guide loot rebuilds and %d guide re-selects inside addon calls",
            stats.agRebuildsInAddon, stats.agHijacks)
        if #stats.hijackLog > 0 then
            detail = detail .. "; first: " .. table.concat(stats.hijackLog, ", ", 1, math.min(3, #stats.hijackLog))
        end
        Result("d", "FAIL", detail)
        return false
    end
    Result("d", "PASS", string.format("0 in addon calls; %d later rebuilds outside (async item events); %d cheap callbacks in addon",
        post, stats.agCallbacksInAddon))
    return true
end

local function CheckErrors(key)
    key = key or "e"
    local count = #M.errors
    if count > 0 or #M.blocked > 0 then
        local detail = string.format("%d Lua error(s)", count)
        if #M.blocked > 0 then
            detail = detail .. ", blocked: " .. table.concat(M.blocked, ", ")
        end
        if count > 0 then
            detail = detail .. ": " .. M.ErrorText(nil, 1):gsub("\n", " / "):sub(1, 400)
        end
        Result(key, "FAIL", detail)
        return false
    end
    Result(key, "PASS", "")
    return true
end

local function LootReads(owner)
    local calls = M.stats.calls[owner]
    return (calls.EJ_GetNumLoot or 0) + (calls.GetLootInfoByIndex or 0)
end

-- After everything finished: journal events keep arriving (the guide's item loads, other
-- addons); the addon must not rescan because of them.
local function CheckQuiet(skip)
    if skip then
        Result("f", "SKIP", "lists never finished")
        return true
    end
    local before = {
        items = H.counters.itemsForSlot,
        mutations = M.MutationCount("addon"),
        reads = LootReads("addon"),
        invalidations = H.counters.invalidations,
    }
    local sample = {}
    for _, instanceID in ipairs(M.ids.seasonDungeons) do
        local bossID = M.instances[instanceID].bosses[1]
        sample[#sample + 1] = M.bosses[bossID].loot[1]
    end
    for index = 1, 20 do
        local itemID = sample[(index - 1) % #sample + 1]
        M.Async(index * 0.5, function()
            M.Fire("EJ_LOOT_DATA_RECIEVED", itemID)
            M.Fire("GET_ITEM_INFO_RECEIVED", itemID, true)
        end)
    end
    for index = 1, 5 do
        M.Async(index * 2 - 0.25, function()
            M.Fire("EJ_LOOT_DATA_RECIEVED")
        end)
    end
    M.Run(10.5)
    local items = H.counters.itemsForSlot - before.items
    local mutations = M.MutationCount("addon") - before.mutations
    local reads = LootReads("addon") - before.reads
    local invalidations = H.counters.invalidations - before.invalidations
    local detail = string.format("10s of journal events: %d ItemsForSlot, %d EJ state changes, %d EJ loot reads, %d invalidations",
        items, mutations, reads, invalidations)
    if mutations > 0 or reads > 0 or items > 10 then
        Result("f", "FAIL", detail)
        return false
    end
    Result("f", "PASS", detail)
    return true
end

-- Runs the standard checks for the named slots; returns nothing, results go to H.results.
function H.Verify(csv)
    local names = Split(csv)
    H.Settle(csv, H.SETTLE_LIMIT)
    local finished = CheckFinish(names)
    CheckLists(names)
    M.Run(3)
    CheckRestore()
    CheckGuideWork()
    CheckQuiet(not finished)
    CheckErrors()
end

---------------------------------------------------------------------------------------------------
-- Loot database mode: Rewards.DatabaseLevels(source), DatabaseItems(source, level, classID,
-- specID), ClearDatabase(). Checks (keys):
--   itm  items equal the ground truth for the class/spec filter and the whole season scope, at the
--        expected item levels (ceiling for raid Mythic's last two bosses), epic, boss order, source
--   lvl  DatabaseLevels tables
--   rst  every database call leaves the journal and the guide as they were, and the guide rebuilds
--        or re-selects nothing during it
--   vlt  the vault's lists are untouched by database browsing (and the other way round): same
--        results, no extra journal calls
--   prf  settled database lists make no journal calls
--   clr  ClearDatabase drops the database's caches but not the vault's
--   rec  lists recover after a loot spec change / InvalidateIcons / ClearDatabase mid-load
--   err  no Lua errors
---------------------------------------------------------------------------------------------------

H.DB_KEYS = { "itm", "lvl", "rst", "vlt", "prf", "clr", "rec", "err" }

-- Expected item levels, from the user's in-game data (ej_model.lua M.weekly): the vault's upgrade
-- steps give keystones +4..+10 (+8 is 315, not the 305 GetRewardLevelForDifficultyLevel says) and
-- world tiers 2..8. Levels below the first step (+2/+3, world tier 1) come only from the vault's
-- own answer below level 0 or from a resolved vault slot: by default neither, so they're unknown.
-- Raid Mythic is 334, 344 for the last two bosses; other raid difficulties only from a slot.
H.DB_STEPS = {
    mplus = { first = 2, last = 10, itemLevels = { [4] = 308, [5] = 308, [6] = 311, [7] = 315, [8] = 315, [9] = 315, [10] = 318 } },
    world = { first = 1, last = 8, itemLevels = { [2] = 282, [3] = 285, [4] = 289, [5] = 292, [6] = 295, [7] = 298, [8] = 305 } },
}
H.DB_RAID_ORDER = { 17, 14, 15, 16 }
H.DB_RAID_MYTHIC = 334
H.DB_RAID_CEILING = 344

-- What the game has told the addon in the scenario: `known` item levels for levels without a
-- step (from resolved vault slots or the vault's answer below its first step; the harness's R2
-- slot is Heroic at 311), and whether the upgrade steps are available for a source. Steps come
-- first; known values only fill the levels steps don't cover.
H.dbExpect = {
    known = { raid = { [15] = 311 }, mplus = {}, world = {} },
    steps = { mplus = true, world = true },
}

function H.DbExpect(source, level, itemLevel)
    H.dbExpect.known[source][level] = itemLevel
end

function H.DbExpectSteps(source, present)
    H.dbExpect.steps[source] = present and true or false
end

function H.ExpectedLevels(source)
    local list = {}
    local known = H.dbExpect.known[source] or {}
    if source == "raid" then
        for _, difficultyID in ipairs(H.DB_RAID_ORDER) do
            if difficultyID == 16 then
                list[#list + 1] = { level = 16, itemLevel = H.DB_RAID_MYTHIC, ceiling = H.DB_RAID_CEILING }
            else
                list[#list + 1] = { level = difficultyID, itemLevel = known[difficultyID] }
            end
        end
    else
        local steps = H.DB_STEPS[source]
        for level = steps.first, steps.last do
            local itemLevel = H.dbExpect.steps[source] and steps.itemLevels[level] or nil
            if itemLevel == nil then
                itemLevel = known[level]
            end
            list[#list + 1] = { level = level, itemLevel = itemLevel }
        end
    end
    -- The default is the highest level with a known item level; none if nothing is known.
    for index = #list, 1, -1 do
        if list[index].itemLevel then
            list.default = list[index].level
            break
        end
    end
    return list
end

local function ExpectedLevel(source, level)
    for _, info in ipairs(H.ExpectedLevels(source)) do
        if info.level == level then
            return info
        end
    end
    return {}
end

H.db = {}
H.dbCalls = 0
H.dbRestarts = 0

local function DbCheck(key)
    local check = H.db[key]
    if not check then
        check = { fails = {}, failCount = 0, notes = {} }
        H.db[key] = check
    end
    return check
end

local function DbFail(key, message)
    local check = DbCheck(key)
    check.failCount = check.failCount + 1
    if #check.fails < 4 then
        check.fails[#check.fails + 1] = message
    end
end

local function DbNote(key, message)
    local check = DbCheck(key)
    if #check.notes < 16 then
        check.notes[#check.notes + 1] = message
    end
end

-- Journal calls that read or change the journal's selection (a scan), vs every journal call.
local SCAN_CALLS = {
    EJ_SelectInstance = true, EJ_SelectEncounter = true, EJ_SetDifficulty = true, EJ_SetLootFilter = true,
    EJ_ResetLootFilter = true, SetSlotFilter = true, ResetSlotFilter = true, EJ_SelectTier = true,
    InitalizeSelectedTier = true, EJ_GetNumLoot = true, GetLootInfoByIndex = true, EJ_GetEncounterInfoByIndex = true,
}

local function AddonCalls()
    local all, scan = 0, 0
    for name, count in pairs(M.stats.calls.addon) do
        all = all + count
        if SCAN_CALLS[name] then
            scan = scan + count
        end
    end
    return all, scan
end

local CALL_ALWAYS = { "classID", "specID", "slotFilter", "tier", "guideShown", "guideInstance", "guideEncounter",
    "guideDifficultyEvent", "guideLootEvent" }

-- What a call changed in the journal and the guide. The selection must come back exactly when the
-- guide shows one; with none, the addon reads the selected instance back from the journal's link
-- (a boss selected with no guide isn't tracked, and nothing shows it).
local function StateChanges(before, after)
    local changes = {}
    local function Compare(field)
        if before[field] ~= after[field] then
            changes[#changes + 1] = field == "peek" and "journal loot list differs"
                or string.format("%s %s -> %s", field, tostring(before[field]), tostring(after[field]))
        end
    end
    for _, field in ipairs(CALL_ALWAYS) do
        Compare(field)
    end
    if before.guideInstance ~= nil then
        Compare("instance")
        Compare("encounter")
        Compare("difficulty")
        Compare("peek")
    elseif before.instance ~= nil then
        Compare("instance")
        Compare("difficulty")
    end
    return changes
end

local function ListName(source, level, classID, specID)
    return string.format("%s@%s class %s spec %s", source, tostring(level), tostring(classID), tostring(specID or 0))
end

-- One Rewards.DatabaseItems call, checked for what it leaves behind. Returns items, pending, and
-- the journal calls it made (all, and those that read or change the selection).
function H.DbCall(source, level, classID, specID)
    local before = M.Snapshot()
    local rebuilds, hijacks = M.stats.agRebuilds, M.stats.agHijacks
    local all0, scan0 = AddonCalls()
    local items, pending = M.AddonCall(BGV.Rewards.DatabaseItems, source, level, classID, specID)
    local all1, scan1 = AddonCalls()
    local after = M.Snapshot()
    H.dbCalls = H.dbCalls + 1
    local problems = StateChanges(before, after)
    if M.stats.agRebuilds ~= rebuilds then
        problems[#problems + 1] = string.format("guide rebuilt its loot list %d time(s)", M.stats.agRebuilds - rebuilds)
    end
    if M.stats.agHijacks ~= hijacks then
        problems[#problems + 1] = string.format("guide re-selected %d time(s)", M.stats.agHijacks - hijacks)
    end
    DbCheck("rst")
    if #problems > 0 then
        DbFail("rst", ListName(source, level, classID, specID) .. ": " .. table.concat(problems, ", "))
    end
    return items, pending, all1 - all0, scan1 - scan0
end

H.dbLists = {}

-- The database lists the loot table polls, as "source/level/classID/specID", comma separated
-- (replaces the current ones). Polled every 0.25s while loading.
function H.DbStart(csv)
    H.dbLists = {}
    for spec in tostring(csv):gmatch("[^,%s]+") do
        local source, level, classID, specID = spec:match("^(%a+)/(%d+)/(%d+)/(%d+)$")
        assert(source, "bad database list " .. spec)
        level, classID, specID = tonumber(level), tonumber(classID), tonumber(specID)
        H.dbLists[#H.dbLists + 1] = {
            source = source, level = level, classID = classID, specID = specID,
            name = ListName(source, level, classID, specID), calls = 0, callsSinceRestart = 0,
        }
    end
    H.dbRestarts = 0
    H.dbPoll = { clock = POLL_DELAY }
end

function H.DbStop()
    H.dbPoll = nil
end

-- InvalidateIcons / ClearDatabase: the loot table re-reads what it shows.
function H.DbRestart()
    if #H.dbLists == 0 then
        return
    end
    H.dbRestarts = H.dbRestarts + 1
    for _, list in ipairs(H.dbLists) do
        list.finishedAt = nil
        list.restartedAt = M.clock
        list.callsSinceRestart = 0
    end
end

local function Record(list, items, pending)
    list.calls = list.calls + 1
    list.callsSinceRestart = list.callsSinceRestart + 1
    list.firstAt = list.firstAt or M.clock
    list.items = items
    list.pending = pending == true
    if not list.pending and not list.finishedAt then
        list.finishedAt = M.clock
        list.callsToFinish = list.callsSinceRestart
    end
end

function H.DbPollOnce()
    for _, list in ipairs(H.dbLists) do
        if not list.finishedAt then
            local items, pending = H.DbCall(list.source, list.level, list.classID, list.specID)
            Record(list, items, pending)
        end
    end
end

function H.DbSettle(maxSeconds)
    return M.RunUntil(function()
        for _, list in ipairs(H.dbLists) do
            if not list.finishedAt then
                return false
            end
        end
        return true
    end, maxSeconds or H.SETTLE_LIMIT)
end

function H.Invalidate()
    M.AddonCall(BGV.Rewards.InvalidateIcons)
end

function H.ClearDatabase()
    M.AddonCall(BGV.Rewards.ClearDatabase)
end

-- The items the vault can award from `source` at `level` for the class/spec filter (specID 0: any
-- of the class's specs), over the whole season: every raid boss, every rotation dungeon with a
-- keystone difficulty, every world item. Returns set, list and per-item expectations.
function H.DbTruth(source, level, classID, specID)
    specID = specID or 0
    local expected = ExpectedLevel(source, level)
    local set, list, meta = {}, {}, {}
    local function Add(itemID, info)
        set[itemID] = true
        list[#list + 1] = itemID
        meta[itemID] = info
    end
    local function Wanted(item, difficultyID)
        return not item.nonGear and (difficultyID == nil or M.Drops(item, difficultyID)) and M.Usable(item, classID, specID)
    end
    if source == "raid" then
        local raid = M.instances[M.ids.raid]
        local count = #raid.bosses
        for index, bossID in ipairs(raid.bosses) do
            -- Raid Mythic's ceiling: the raid's last two bosses (of three or more).
            local atCeiling = count >= 3 and index > count - 2
            for _, itemID in ipairs(M.bosses[bossID].loot) do
                if Wanted(M.items[itemID], level) then
                    if not set[itemID] then
                        Add(itemID, { bossOrder = 100 + index, source = M.bosses[bossID].name, ceiling = atCeiling })
                    elseif atCeiling then
                        meta[itemID].ceiling = true
                    end
                end
            end
        end
    elseif source == "mplus" then
        for _, instanceID in ipairs(M.ids.seasonDungeons) do
            local instance = M.instances[instanceID]
            if instance.diffSet[8] then
                for _, bossID in ipairs(instance.bosses) do
                    for _, itemID in ipairs(M.bosses[bossID].loot) do
                        if not set[itemID] and Wanted(M.items[itemID], 8) then
                            Add(itemID, { source = instance.name })
                        end
                    end
                end
            end
        end
    elseif source == "world" then
        for _, itemID in ipairs(BGV.WorldLoot or {}) do
            local item = M.items[itemID]
            if item and not set[itemID] and Wanted(item, nil) then
                Add(itemID, { source = BGV.WorldLootSource and BGV.WorldLootSource[itemID] or "World" })
            end
        end
    end
    for _, itemID in ipairs(list) do
        local info = meta[itemID]
        info.itemLevel = expected.itemLevel
        if expected.ceiling and info.ceiling then
            info.itemLevel = expected.ceiling
        end
    end
    return set, list, meta
end

local function CheckDbList(list, items, pending, key)
    local truthSet, truthList, meta = H.DbTruth(list.source, list.level, list.classID, list.specID)
    local got, gotList, dupes, broken, wrong = {}, {}, {}, {}, {}
    local ceilings = 0
    for _, entry in ipairs(type(items) == "table" and items or {}) do
        local itemID = type(entry) == "table" and entry.itemID or nil
        if itemID then
            if got[itemID] then
                dupes[#dupes + 1] = itemID
            end
            got[itemID] = true
            gotList[#gotList + 1] = itemID
            if type(entry.name) ~= "string" or entry.name == "" or entry.name == "Item" or not entry.icon or entry.icon == 136243 then
                broken[#broken + 1] = itemID
            end
            local want = meta[itemID]
            if want then
                if entry.itemLevel ~= want.itemLevel then
                    wrong[#wrong + 1] = string.format("%s ilvl %s, want %s", Describe(itemID), tostring(entry.itemLevel), tostring(want.itemLevel))
                end
                if entry.quality ~= 4 then
                    wrong[#wrong + 1] = string.format("%s quality %s", Describe(itemID), tostring(entry.quality))
                end
                if list.source == "raid" and entry.bossOrder ~= want.bossOrder then
                    wrong[#wrong + 1] = string.format("%s boss order %s, want %s", Describe(itemID), tostring(entry.bossOrder), tostring(want.bossOrder))
                end
                if entry.source ~= want.source then
                    wrong[#wrong + 1] = string.format("%s source %s, want %s", Describe(itemID), tostring(entry.source), tostring(want.source))
                end
                if want.ceiling and entry.itemLevel == H.DB_RAID_CEILING then
                    ceilings = ceilings + 1
                end
            end
        end
    end
    local missing, extra = {}, {}
    for _, itemID in ipairs(truthList) do
        if not got[itemID] then
            missing[#missing + 1] = itemID
        end
    end
    for _, itemID in ipairs(gotList) do
        if not truthSet[itemID] then
            extra[#extra + 1] = itemID
        end
    end
    local problems = {}
    if pending == true then
        problems[#problems + 1] = "pending at final read"
    end
    if #missing > 0 then
        problems[#problems + 1] = string.format("missing %d/%d: %s", #missing, #truthList, Sample(missing, 3))
    end
    if #extra > 0 then
        problems[#problems + 1] = string.format("extra %d: %s", #extra, Sample(extra, 3))
    end
    if #dupes > 0 then
        problems[#problems + 1] = "duplicates: " .. Sample(dupes, 3)
    end
    if #broken > 0 then
        problems[#problems + 1] = "rows without name/icon: " .. Sample(broken, 3)
    end
    for index = 1, math.min(#wrong, 3) do
        problems[#problems + 1] = wrong[index]
    end
    if #wrong > 3 then
        problems[#problems + 1] = string.format("+%d more wrong fields", #wrong - 3)
    end
    if #truthList == 0 then
        problems[#problems + 1] = "scenario error: empty ground truth"
    end
    if #problems > 0 then
        DbFail(key, list.name .. ": " .. table.concat(problems, ", "))
        return false
    end
    local expected = ExpectedLevel(list.source, list.level)
    DbNote(key, string.format("%s=%d@%s%s", list.name, #truthList, tostring(expected.itemLevel),
        ceilings > 0 and string.format(" (%d at %d)", ceilings, H.DB_RAID_CEILING) or ""))
    return true
end

-- Every current list finished loading in time, and its items match the ground truth.
function H.DbCheckItems()
    DbCheck("itm")
    for _, list in ipairs(H.dbLists) do
        if not list.finishedAt then
            DbFail("itm", string.format("%s still loading after %d passes", list.name, list.callsSinceRestart))
        else
            local took = list.finishedAt - (list.restartedAt or list.firstAt or list.finishedAt)
            if took > H.FINISH_LIMIT or (list.callsToFinish or 0) > H.PASS_LIMIT then
                DbFail("itm", string.format("%s took %.1fs / %d passes", list.name, took, list.callsToFinish or 0))
            end
        end
        local items, pending = H.DbCall(list.source, list.level, list.classID, list.specID)
        CheckDbList(list, items, pending, "itm")
    end
end

-- While a list's source data isn't there yet it must say it's loading, not finish empty (the
-- loot table keeps a finished list and stops asking).
function H.DbCheckLoading(label)
    DbCheck("itm")
    for _, list in ipairs(H.dbLists) do
        local items, pending = H.DbCall(list.source, list.level, list.classID, list.specID)
        if type(items) == "table" and #items == 0 and pending ~= true then
            DbFail("itm", string.format("%s: %s came back finished and empty", label, list.name))
        end
    end
end

local function LevelText(levels)
    local parts = {}
    for _, info in ipairs(levels) do
        parts[#parts + 1] = string.format("%s=%s%s", tostring(info.level), tostring(info.itemLevel),
            info.ceiling and ("/" .. tostring(info.ceiling)) or "")
    end
    return table.concat(parts, " ")
end

function H.CheckLevels(source)
    DbCheck("lvl")
    local levels = M.AddonCall(BGV.Rewards.DatabaseLevels, source)
    local expected = H.ExpectedLevels(source)
    if type(levels) ~= "table" then
        DbFail("lvl", source .. ": DatabaseLevels returned nothing")
        return
    end
    local problems = {}
    if #levels ~= #expected then
        problems[#problems + 1] = string.format("%d levels, want %d", #levels, #expected)
    end
    for index, want in ipairs(expected) do
        local got = levels[index]
        if type(got) ~= "table" or got.level ~= want.level then
            problems[#problems + 1] = string.format("level #%d is %s, want %s", index, tostring(got and got.level), tostring(want.level))
        else
            if got.itemLevel ~= want.itemLevel then
                problems[#problems + 1] = string.format("%s ilvl %s, want %s", tostring(want.level), tostring(got.itemLevel), tostring(want.itemLevel))
            end
            if got.ceiling ~= want.ceiling then
                problems[#problems + 1] = string.format("%s ceiling %s, want %s", tostring(want.level), tostring(got.ceiling), tostring(want.ceiling))
            end
            if type(got.label) ~= "string" or got.label == "" then
                problems[#problems + 1] = string.format("%s has no label", tostring(want.level))
            end
        end
    end
    if levels.default ~= expected.default then
        problems[#problems + 1] = string.format("default %s, want %s", tostring(levels.default), tostring(expected.default))
    end
    if #problems > 0 then
        DbFail("lvl", source .. ": " .. table.concat(problems, "; ") .. " [got " .. LevelText(levels) .. "]")
    else
        DbNote("lvl", source .. " " .. LevelText(levels))
    end
end

local function SerializeEntries(items)
    local parts = {}
    for _, entry in ipairs(type(items) == "table" and items or {}) do
        parts[#parts + 1] = table.concat({ tostring(entry.itemID), tostring(entry.itemLevel), tostring(entry.source),
            tostring(entry.name), tostring(entry.quality), tostring(entry.icon), tostring(entry.bossOrder) }, ":")
    end
    return table.concat(parts, ",")
end

local function SerializeIcons(icons)
    local parts = {}
    for _, icon in ipairs(type(icons) == "table" and icons or {}) do
        parts[#parts + 1] = tostring(icon.itemID) .. ":" .. tostring(icon.icon)
    end
    return table.concat(parts, ",")
end

-- One read of a vault slot's list and reel, with the journal calls it made.
local function VaultRead(name)
    local slot = H.slots[name]
    local all0, scan0 = AddonCalls()
    local items, pending = M.AddonCall(BGV.Rewards.ItemsForSlot, slot)
    local icons, iconsPending
    if ProgressWeek() then
        icons, iconsPending = M.AddonCall(BGV.Rewards.PossibleIcons, slot)
    end
    local all1, scan1 = AddonCalls()
    return {
        text = SerializeEntries(items) .. "#" .. SerializeIcons(icons) .. "#" .. tostring(pending) .. "/" .. tostring(iconsPending),
        all = all1 - all0,
        scan = scan1 - scan0,
        count = type(items) == "table" and #items or 0,
    }
end

-- Remembers the settled vault lists (their results and the journal calls a warm read makes).
function H.MarkVault(csv)
    DbCheck("vlt")
    H.vaultMark = {}
    H.vaultMarkOrder = Split(csv)
    for _, name in ipairs(H.vaultMarkOrder) do
        -- A first read may still build the reel (its list is kept once built); mark a warm one.
        VaultRead(name)
        local read = VaultRead(name)
        H.vaultMark[name] = read
        if read.scan > 0 then
            DbFail("vlt", name .. ": the vault list was still reading the journal when marked")
        end
    end
end

local function CompareVault(label, key)
    local same = true
    for _, name in ipairs(H.vaultMarkOrder or {}) do
        local mark = H.vaultMark[name]
        local read = VaultRead(name)
        if read.text ~= mark.text then
            same = false
            DbFail(key, string.format("%s: %s list changed (%d items, was %d)", label, name, read.count, mark.count))
        end
        if read.all ~= mark.all or read.scan > 0 then
            same = false
            DbFail(key, string.format("%s: %s made %d journal call(s) (%d reading/selecting), a warm read makes %d",
                label, name, read.all, read.scan, mark.all))
        end
    end
    return same
end

function H.CheckVault(label)
    DbCheck("vlt")
    if CompareVault(label, "vlt") then
        DbNote("vlt", label .. ": vault lists identical, no extra journal calls")
    end
end

-- Remembers the settled database lists.
function H.MarkDb()
    H.dbMark = {}
    for index, list in ipairs(H.dbLists) do
        local items, pending = H.DbCall(list.source, list.level, list.classID, list.specID)
        H.dbMark[index] = { text = SerializeEntries(items), pending = pending == true, count = type(items) == "table" and #items or 0 }
    end
end

local function CompareDb(label, key, allowReads)
    local same = true
    for index, list in ipairs(H.dbLists) do
        local mark = H.dbMark and H.dbMark[index]
        local items, pending, all = H.DbCall(list.source, list.level, list.classID, list.specID)
        if mark and SerializeEntries(items) ~= mark.text then
            same = false
            DbFail(key, string.format("%s: %s changed (%d items, was %d)", label, list.name, type(items) == "table" and #items or 0, mark.count))
        end
        if pending == true then
            same = false
            DbFail(key, string.format("%s: %s is loading again", label, list.name))
        end
        if all > 0 and not allowReads then
            same = false
            DbFail(key, string.format("%s: %s made %d journal call(s)", label, list.name, all))
        end
    end
    return same
end

function H.CheckDb(label)
    DbCheck("vlt")
    if CompareDb(label, "vlt") then
        DbNote("vlt", label .. ": database lists identical, no journal calls")
    end
end

-- Settled database lists, read again and again (the loot table re-lays out on every event):
-- no journal calls, same results.
function H.CheckDbPerf(passes)
    DbCheck("prf")
    local calls, changed, loading = 0, 0, 0
    local first = {}
    for pass = 1, passes do
        for index, list in ipairs(H.dbLists) do
            local items, pending, all = H.DbCall(list.source, list.level, list.classID, list.specID)
            calls = calls + all
            local text = SerializeEntries(items)
            if pass == 1 then
                first[index] = text
            elseif first[index] ~= text then
                changed = changed + 1
            end
            if pending == true then
                loading = loading + 1
            end
        end
    end
    local detail = string.format("%d passes over %d lists: %d journal calls, %d changed, %d loading", passes, #H.dbLists, calls, changed, loading)
    if calls > 0 or changed > 0 or loading > 0 then
        DbFail("prf", detail)
    else
        DbNote("prf", detail)
    end
end

-- ClearDatabase: the vault's lists stay warm (same results, no extra journal calls); the database
-- reads the journal again, rebuilds its level tables and raid scope, and settles to the same lists.
function H.CheckClear()
    DbCheck("clr")
    H.ClearDatabase()
    local asked = M.stats.specInfo
    CompareVault("after ClearDatabase", "clr")
    if M.stats.specInfo ~= asked then
        DbFail("clr", "the vault's world spec answers were dropped by ClearDatabase")
    end
    local weekly = M.WeeklyCount("GetActivities")
    M.AddonCall(BGV.Rewards.DatabaseLevels, "mplus")
    if M.WeeklyCount("GetActivities") == weekly then
        DbFail("clr", "DatabaseLevels still served from before ClearDatabase")
    end
    local scope = M.WeeklyCount("GetActivityEncounterInfo")
    local readsRaid, readsWorld = false, false
    asked = M.stats.specInfo
    for _, list in ipairs(H.dbLists) do
        local _, _, _, scan = H.DbCall(list.source, list.level, list.classID, list.specID)
        if list.source == "world" then
            readsWorld = true
        elseif scan == 0 then
            DbFail("clr", list.name .. ": still served from the cleared cache")
        end
        readsRaid = readsRaid or list.source == "raid"
    end
    if readsRaid and M.WeeklyCount("GetActivityEncounterInfo") == scope then
        DbFail("clr", "the season raid scope wasn't rebuilt")
    end
    if readsWorld and M.stats.specInfo == asked then
        DbFail("clr", "the database's world spec answers weren't dropped")
    end
    H.DbSettle(H.SETTLE_LIMIT)
    if CompareDb("after ClearDatabase", "clr", true) then
        DbNote("clr", "database re-read and settled to the same lists; vault lists and answers untouched")
    end
end

-- InvalidateIcons (loot spec change, new vault data): the database keeps what it read, so its
-- settled lists stay complete and need no journal reads, but its level tables are rebuilt.
function H.CheckInvalidateKeepsDb()
    DbCheck("clr")
    H.Invalidate()
    local weekly = M.WeeklyCount("GetActivities")
    M.AddonCall(BGV.Rewards.DatabaseLevels, "mplus")
    if M.WeeklyCount("GetActivities") == weekly then
        DbFail("clr", "InvalidateIcons didn't rebuild the database's level tables")
    end
    local kept = true
    for _, list in ipairs(H.dbLists) do
        local items, pending, _, scan = H.DbCall(list.source, list.level, list.classID, list.specID)
        if scan > 0 then
            kept = false
            DbFail("clr", list.name .. ": InvalidateIcons dropped its journal reads")
        end
        if pending == true then
            kept = false
            DbFail("clr", string.format("%s: loading again right after InvalidateIcons (%d items)", list.name,
                type(items) == "table" and #items or 0))
        end
    end
    H.DbSettle(H.SETTLE_LIMIT)
    if kept then
        DbNote("clr", "InvalidateIcons kept the database's reads and rebuilt its levels")
    end
end

-- After disruptions mid-load, every list finished again within the limits.
function H.CheckDbRecovery()
    DbCheck("rec")
    if H.dbRestarts == 0 then
        DbFail("rec", "nothing restarted the database lists")
    end
    for _, list in ipairs(H.dbLists) do
        if not list.finishedAt then
            DbFail("rec", string.format("%s still loading %.1fs after the last restart", list.name, M.clock - (list.restartedAt or list.firstAt or M.clock)))
        else
            local took = list.finishedAt - (list.restartedAt or list.firstAt or list.finishedAt)
            if took > H.FINISH_LIMIT then
                DbFail("rec", string.format("%s took %.1fs after the last restart", list.name, took))
            end
        end
    end
    DbNote("rec", string.format("%d restarts, lists finished again", H.dbRestarts))
end

-- The vault's own lists, against their ground truth (e.g. for a new loot spec).
function H.CheckVaultTruth(csv, key)
    key = key or "rec"
    DbCheck(key)
    CheckLists(Split(csv), function(_, status, detail)
        if status == "FAIL" then
            DbFail(key, "vault lists: " .. detail)
        else
            DbNote(key, "vault lists " .. detail)
        end
    end)
end

-- Another addon that calls Rewards.DatabaseItems from EJ_LOOT_DATA_RECIEVED while one of our scans
-- is open (the event fires inside our own journal calls): a nested read with its own class filter,
-- up to `times` times, never from inside itself.
function H.ArmNestedRead(spec, times)
    local source, level, classID, specID = tostring(spec):match("^(%a+)/(%d+)/(%d+)/(%d+)$")
    assert(source, "bad nested read " .. tostring(spec))
    H.nested = {
        source = source, level = tonumber(level), classID = tonumber(classID), specID = tonumber(specID),
        name = ListName(source, tonumber(level), tonumber(classID), tonumber(specID)),
        remaining = times or 1, results = {},
    }
    if H.nestedFrame then
        return
    end
    M.Invoke("addon", function()
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
        frame:SetScript("OnEvent", function()
            local nested = H.nested
            local R = BGV.Rewards
            if not nested or nested.active or nested.remaining <= 0 or not (R.IsScanning and R.IsScanning()) then
                return
            end
            nested.remaining = nested.remaining - 1
            nested.active = true
            local items, pending = R.DatabaseItems(nested.source, nested.level, nested.classID, nested.specID)
            nested.active = false
            nested.results[#nested.results + 1] = { items = items, pending = pending }
        end)
        H.nestedFrame = frame
    end)
end

-- The nested reads happened, and any of them that came back finished is right for its own filter.
function H.CheckNestedReads()
    DbCheck("itm")
    local nested = H.nested
    if not nested or #nested.results == 0 then
        DbFail("itm", "scenario error: no nested read happened")
        return
    end
    local finished = 0
    for _, result in ipairs(nested.results) do
        if result.pending ~= true then
            finished = finished + 1
            CheckDbList(nested, result.items, result.pending, "itm")
        end
    end
    DbNote("itm", string.format("%d nested read(s) of %s inside our scans, %d finished", #nested.results, nested.name, finished))
end

-- Scenario sanity: the lists include rows the journal flags for the player (handError /
-- weaponTypeError), so the check that the database lists them means something.
function H.CheckFlaggedListed()
    DbCheck("itm")
    local flagged = 0
    for _, list in ipairs(H.dbLists) do
        local items = H.DbCall(list.source, list.level, list.classID, list.specID)
        for _, entry in ipairs(type(items) == "table" and items or {}) do
            local item = M.items[entry.itemID]
            local handError, weaponTypeError = M.EquipErrors(item)
            if handError or weaponTypeError then
                flagged = flagged + 1
            end
        end
    end
    if flagged == 0 then
        DbFail("itm", "scenario error: no listed row carries an equip flag for the player")
    else
        DbNote("itm", string.format("%d listed rows the journal flags for the player (%s)", flagged, M.player.className))
    end
end

function H.DbReport()
    if M.stats.agRebuildsInAddon > 0 or M.stats.agHijacks > 0 then
        DbFail("rst", string.format("%d guide loot rebuilds and %d re-selects inside addon calls",
            M.stats.agRebuildsInAddon, M.stats.agHijacks))
    end
    if H.dbCalls > 0 then
        DbNote("rst", string.format("%d database calls checked", H.dbCalls))
    end
    for _, key in ipairs(H.DB_KEYS) do
        if key == "err" then
            CheckErrors("err")
        else
            local check = H.db[key]
            if check then
                if check.failCount > 0 then
                    local detail = table.concat(check.fails, " | ")
                    if check.failCount > #check.fails then
                        detail = detail .. string.format(" (+%d more)", check.failCount - #check.fails)
                    end
                    Result(key, "FAIL", detail)
                else
                    Result(key, "PASS", table.concat(check.notes, "; "))
                end
            end
        end
    end
end

function H.ResultText()
    local lines = {}
    for _, result in ipairs(H.results) do
        lines[#lines + 1] = table.concat({ result.key, result.status, (result.detail:gsub("[\t\n]", " ")) }, "\t")
    end
    for _, note in ipairs(H.info) do
        lines[#lines + 1] = table.concat({ "info", "INFO", (tostring(note):gsub("[\t\n]", " ")) }, "\t")
    end
    return table.concat(lines, "\n")
end

function H.Chat()
    return table.concat(M.chat, "\n")
end

return H
