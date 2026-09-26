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
    local T = Enum.WeeklyRewardChestThresholdType
    H.slots = {
        R1 = { type = T.Raid, index = 1, unlocked = true, level = 16, itemLevel = 289, threshold = 2, progress = 7, encounters = encounters },
        R2 = { type = T.Raid, index = 2, unlocked = true, level = 15, itemLevel = 282, threshold = 4, progress = 7, encounters = encounters },
        M1 = { type = T.Activities, index = 1, unlocked = true, level = 10, itemLevel = 285, activityTierID = 901, threshold = 1, progress = 8 },
        M2 = { type = T.Activities, index = 2, unlocked = true, level = 0, itemLevel = 272, activityTierID = 900, threshold = 4, progress = 8 },
        W1 = { type = T.World, index = 1, unlocked = true, level = 8, itemLevel = 275, activityTierID = 902, threshold = 2, progress = 3, qualifier = "Delves" },
    }
    H.slotOrder = { "M1", "M2", "R1", "R2", "W1" }
    H.vaultSlots = {}
    H.nameOf = {}
    for _, name in ipairs(H.slotOrder) do
        H.vaultSlots[#H.vaultSlots + 1] = H.slots[name]
        H.nameOf[H.slots[name]] = name
    end
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
        return invalidate(...)
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

    H.LoadFile("Utils.lua")
    H.LoadFile("WorldLoot.lua")
    M.RegisterWorldItems(BGV.WorldLoot)
    H.LoadFile("Rewards.lua")
    if reference then
        BGV.Rewards = BGV.Rewards or {}
        H.LoadFile((testsDir or "tests") .. "/reference_rewards.lua")
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

local function CheckLists(names)
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
        Result("a", "FAIL", table.concat(failures, " | "))
        return false
    end
    Result("a", "PASS", table.concat(notes, " "))
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

local function CheckErrors()
    local count = #M.errors
    if count > 0 or #M.blocked > 0 then
        local detail = string.format("%d Lua error(s)", count)
        if #M.blocked > 0 then
            detail = detail .. ", blocked: " .. table.concat(M.blocked, ", ")
        end
        if count > 0 then
            detail = detail .. ": " .. M.ErrorText(nil, 1):gsub("\n", " / "):sub(1, 400)
        end
        Result("e", "FAIL", detail)
        return false
    end
    Result("e", "PASS", "")
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
