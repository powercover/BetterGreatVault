-- Model of the WoW Retail Encounter Journal (EJ) for the Better Great Vault regression harness.
--
-- Two halves:
--   1. The C side: one global EJ state (selected tier, instance, encounter, difficulty, class/spec
--      loot filter, slot filter, "loot list out of date" flag, item cache) over a small content
--      database, exposed under the client's global API names.
--   2. The Lua side: Blizzard's Adventure Guide frame (`EncounterJournal`), modelled on
--      Interface/AddOns/Blizzard_EncounterJournal/Mainline/Blizzard_EncounterJournal.lua (live),
--      reduced to the code paths that touch EJ state.
-- Plus the engine around them: CreateFrame with event registration, a synchronous event bus, a
-- clock with C_Timer and OnUpdate, and bookkeeping of who (addon / guide / client) made each EJ call.
--
-- What Blizzard's code does (the facts this model copies):
--  * EncounterJournal_OnLoad registers EJ_LOOT_DATA_RECIEVED and EJ_DIFFICULTY_UPDATE and nothing
--    ever unregisters them (OnHide only drops SPELL_TEXT_UPDATE): the hidden guide keeps handling both.
--  * EncounterJournalDocumentation.lua marks both events SynchronousEvent = true, so they are
--    delivered inside the API call that causes them. EJ_DIFFICULTY_UPDATE carries difficultyID,
--    EJ_LOOT_DATA_RECIEVED an optional itemID.
--  * EncounterJournal_OnEvent:
--      EJ_LOOT_DATA_RECIEVED: if itemID and not EJ_IsLootListOutOfDate() then
--        EncounterJournal_LootCallback(itemID) (re-inits one button) else EncounterJournal_LootUpdate()
--        (rebuilds the whole loot list: EJ_GetNumLoot + GetLootInfoByIndex per row).
--      EJ_DIFFICULTY_UPDATE: EncounterJournal_UpdateDifficulty(d) -> if IsEJDifficulty(d) then
--        SetupDifficultyDropdown + EncounterJournal_Refresh().
--  * EncounterJournal_Refresh: LootUpdate(); if EncounterJournal.encounterID then
--    DisplayEncounter(encounterID, true) (-> EJ_SelectEncounter) elseif EncounterJournal.instanceID
--    then DisplayInstance(instanceID, true) (-> EJ_SelectInstance).
--  * EncounterJournal_DisplayInstance: `EncounterJournal.instanceID = id; EncounterJournal.encounterID
--    = nil; EJ_SelectInstance(id); EncounterJournal_LootUpdate()`. No explicit C-side "clear
--    encounter" call: it relies on EJ_SelectInstance clearing the selected encounter.
--  * EncounterJournal_DisplayEncounter: `EncounterJournal.encounterID = id; EJ_SelectEncounter(id);
--    EncounterJournal_LootUpdate()`. It never re-selects the instance.
--  * EncounterJournal_OnShow re-selects nothing (unless the player stands in an instance whose context
--    changed): C_EncounterJournal.OnOpen(), LootUpdate(), and EJ_ContentTab_Select(selectedTab) when
--    the instance list is showing (-> ListInstances -> EJ_GetInstanceByIndex over the current tier).
--  * Difficulty dropdown: EJ_SelectDifficulty -> EJ_SetDifficulty(value), only offered for
--    EJ_IsValidInstanceDifficulty(d). Filters: EJ_SetLootFilter / C_EncounterJournal.SetSlotFilter then
--    EncounterJournal_LootUpdate() directly. Expansion dropdown: EJ_SelectTier(t) then ListInstances
--    (EncounterJournal.instanceID / encounterID are left as they were).
--
-- Assumptions (not visible in Blizzard's Lua; each one is a config switch where it matters):
--  * EJ_SelectInstance clears the selected encounter (Blizzard's DisplayInstance depends on it) and
--    fires nothing (DisplayInstance calls LootUpdate itself). If the current difficulty is invalid for
--    the new instance it moves to the instance's first valid difficulty, silently by default
--    (cfg.fixDifficultyOnSelect / cfg.fireOnDifficultyFix).
--  * EJ_SelectEncounter of a boss from another instance: cfg.crossInstanceEncounter = "switch" (the
--    instance follows the boss; the most pessimistic choice, default), "select" or "ignore".
--  * EJ_SetDifficulty with a difficulty invalid for the selected instance is ignored with no event.
--    Otherwise it stores it, marks the list out of date and fires EJ_DIFFICULTY_UPDATE(d) then
--    EJ_LOOT_DATA_RECIEVED(), synchronously, even when d was already set (cfg.fireWhenUnchanged).
--  * EJ_SetLootFilter / EJ_ResetLootFilter / SetSlotFilter / ResetSlotFilter mark the list out of date
--    and fire EJ_LOOT_DATA_RECIEVED() synchronously (cfg.filterFiresLootEvent), also when unchanged.
--  * Any selection or filter change marks the list out of date; EJ_GetNumLoot() clears the flag.
--  * The list is the selected encounter's loot (or every boss's, in journal order, when none is
--    selected) at the current difficulty, filtered by class/spec and slot filter. Class 0 = no filter;
--    spec 0 = any spec of the class.
--  * Items not in the item cache come back with name/icon/link nil (or the instance name and a
--    placeholder icon with cfg.placeholderRows, the "cold journal" artifact the existing test models).
--    Reading such a row, C_Item.GetItemInfo or RequestLoadItemDataByID queue a load that completes
--    cfg.itemLoadDelay later and fires GET_ITEM_INFO_RECEIVED(itemID, true), plus
--    EJ_LOOT_DATA_RECIEVED(itemID) when the journal asked for it. GetItemInfoInstant/GetItemIconByID
--    always answer; GetItemSpecInfo needs the cache.
--  * "Cold" instances (M.cold[id]) return 0 rows and stay out of date until cfg.coldLootDelay after the
--    first read, then fire EJ_LOOT_DATA_RECIEVED().
--  * Tiers: 11 = older expansion, 12 = current expansion, 13 = "Current Season" (Blizzard's
--    GetEJTierData treats tier > #EJ_TIER_DATA as the current season; cfg.seasonTier). The login tier
--    is the season tier. EJ_GetInstanceByIndex depends on the tier; EJ_SelectInstance,
--    EJ_GetEncounterInfoByIndex(i, instanceID), EJ_GetInstanceForMap and GetInstanceForGameMap don't.
--  * C_ChallengeMode.GetMapUIInfo returns name, id, timeLimit, texture, backgroundTexture, mapID where
--    mapID is the game map (ChallengeModeInfoDocumentation). EJ_GetInstanceForMap takes a UiMapID and
--    C_EncounterJournal.GetInstanceForGameMap a game map; the two ID spaces don't overlap here.
--  * At login the loot filter is the player's class and active spec, the slot filter NoFilter, the
--    difficulty 14 and nothing is selected.
--  * EJ_GetInstanceByIndex/tier/encounter-info reads fire nothing. OnOpen/OnClose do nothing.
--  * Event delivery follows registration order; a frame unregistered mid-dispatch is skipped.
--  * C_Timer.After(0) runs on the next frame. Each frame: client async work, OnUpdate, then timers.
--  * debugprofilestop() = simulated wall clock plus a fixed CPU cost per EJ call (cfg.cost), so time
--    budgets inside a scan see time pass.

if not unpack and table.unpack then
    unpack = table.unpack
end

local M = {}
EJModel = M

local function pack(...)
    return { n = select("#", ...), ... }
end

M.cfg = {
    crossInstanceEncounter = "switch",
    fixDifficultyOnSelect = true,
    fireOnDifficultyFix = false,
    fireWhenUnchanged = true,
    filterFiresLootEvent = true,
    selectFiresLootEvent = false,
    itemLoadDelay = 0.1,
    coldLootDelay = 0.3,
    frameTime = 1 / 60,
    seasonTier = true,
    -- In game (12.x), EJ_GetEncounterInfoByIndex returns nothing for a keystone dungeon, with or
    -- without its instance ID, while EJ_GetNumLoot on the whole dungeon works.
    dungeonBossList = true,
    placeholderRows = false,
    uncachedModulo = 10,
    uncachedRemainder = 7,
    cost = { select = 0.25, difficulty = 0.5, filter = 0.4, numLoot = 0.2, row = 0.01, info = 0.01 },
}

function M.SetCfg(key, value)
    M.cfg[key] = value
end

---------------------------------------------------------------------------------------------------
-- Bookkeeping
---------------------------------------------------------------------------------------------------

M.clock = 0
M.cpuMs = 0
M.frameCount = 0
M.ctx = { addon = 0, ag = 0 }
M.errors = {}
M.chat = {}
M.blocked = {}

local function NewStats()
    return {
        calls = { addon = {}, ag = {}, client = {} },
        agRebuilds = 0,
        agRebuildsInAddon = 0,
        agCallbacks = 0,
        agCallbacksInAddon = 0,
        agHijacks = 0,
        hijackLog = {},
        events = {},
    }
end
M.stats = NewStats()

function M.ResetStats()
    M.stats = NewStats()
end

function M.Owner()
    if M.ctx.ag > 0 then
        return "ag"
    elseif M.ctx.addon > 0 then
        return "addon"
    end
    return "client"
end

local function Api(name, cost)
    local bucket = M.stats.calls[M.Owner()]
    bucket[name] = (bucket[name] or 0) + 1
    M.cpuMs = M.cpuMs + (M.cfg.cost[cost or "info"] or 0)
end

function M.CallCount(owner, prefix)
    local total = 0
    for name, count in pairs(M.stats.calls[owner] or {}) do
        if not prefix or name:find(prefix, 1, true) then
            total = total + count
        end
    end
    return total
end

-- Journal calls that change EJ state, by owner.
local MUTATORS = {
    EJ_SelectInstance = true, EJ_SelectEncounter = true, EJ_SetDifficulty = true, EJ_SetLootFilter = true,
    EJ_ResetLootFilter = true, SetSlotFilter = true, ResetSlotFilter = true, EJ_SelectTier = true,
    InitalizeSelectedTier = true,
}

function M.MutationCount(owner)
    local total = 0
    for name, count in pairs(M.stats.calls[owner] or {}) do
        if MUTATORS[name] then
            total = total + count
        end
    end
    return total
end

function M.RecordError(owner, err)
    M.errors[#M.errors + 1] = { owner = owner, message = tostring(err), at = M.clock }
end

function M.ErrorCount(owner)
    local count = 0
    for _, entry in ipairs(M.errors) do
        if not owner or entry.owner == owner then
            count = count + 1
        end
    end
    return count
end

function M.ErrorText(owner, limit)
    local lines = {}
    for _, entry in ipairs(M.errors) do
        if not owner or entry.owner == owner then
            lines[#lines + 1] = string.format("[%s @%.2fs] %s", entry.owner, entry.at, entry.message)
            if limit and #lines >= limit then
                break
            end
        end
    end
    return table.concat(lines, "\n")
end

-- Runs fn as code owned by `owner` ("addon", "ag" or "client"). Errors are recorded, like the
-- client's error handler, and never propagate into the caller.
function M.Invoke(owner, fn, ...)
    local args = pack(...)
    if owner == "addon" then
        M.ctx.addon = M.ctx.addon + 1
    elseif owner == "ag" then
        M.ctx.ag = M.ctx.ag + 1
    end
    local result = pack(xpcall(function()
        return fn(unpack(args, 1, args.n))
    end, debug.traceback))
    if owner == "addon" then
        M.ctx.addon = M.ctx.addon - 1
    elseif owner == "ag" then
        M.ctx.ag = M.ctx.ag - 1
    end
    if not result[1] then
        M.RecordError(owner, result[2])
        return false
    end
    return true, unpack(result, 2, result.n)
end

-- Calls into the addon (the harness acting as the addon's UI code).
function M.AddonCall(fn, ...)
    local result = pack(M.Invoke("addon", fn, ...))
    if not result[1] then
        return nil
    end
    return unpack(result, 2, result.n)
end

local function Contains(list, value)
    if type(list) ~= "table" then
        return false
    end
    for _, entry in ipairs(list) do
        if entry == value then
            return true
        end
    end
    return false
end
M.Contains = Contains

---------------------------------------------------------------------------------------------------
-- Frames and the event bus
---------------------------------------------------------------------------------------------------

M.frames = {}
M.registry = {}

local FrameMethods = {}
local FrameMeta = { __index = FrameMethods }

function M.NewFrame(kind, name, owner)
    local frame = setmetatable({
        __kind = kind or "Frame",
        __name = name,
        __owner = owner or M.Owner(),
        __events = {},
        __scripts = {},
        __hooks = {},
        __shown = true,
    }, FrameMeta)
    M.frames[#M.frames + 1] = frame
    if type(name) == "string" then
        _G[name] = frame
    end
    return frame
end

function FrameMethods:RegisterEvent(event)
    if self.__events[event] then
        return true
    end
    self.__events[event] = true
    local list = M.registry[event]
    if not list then
        list = {}
        M.registry[event] = list
    end
    list[#list + 1] = self
    return true
end

function FrameMethods:UnregisterEvent(event)
    if not self.__events[event] then
        return
    end
    self.__events[event] = nil
    local list = M.registry[event] or {}
    for index = #list, 1, -1 do
        if list[index] == self then
            table.remove(list, index)
        end
    end
end

function FrameMethods:UnregisterAllEvents()
    for event in pairs(self.__events) do
        self:UnregisterEvent(event)
    end
end

function FrameMethods:IsEventRegistered(event)
    return self.__events[event] == true
end

function FrameMethods:SetScript(script, fn)
    self.__scripts[script] = fn
end

function FrameMethods:GetScript(script)
    return self.__scripts[script]
end

function FrameMethods:HookScript(script, fn)
    local hooks = self.__hooks[script]
    if not hooks then
        hooks = {}
        self.__hooks[script] = hooks
    end
    hooks[#hooks + 1] = { fn = fn, owner = M.Owner() }
end

function FrameMethods:Show()
    if not self.__shown then
        self.__shown = true
        M.RunScript(self, "OnShow")
    end
end

function FrameMethods:Hide()
    if self.__shown then
        self.__shown = false
        M.RunScript(self, "OnHide")
    end
end

function FrameMethods:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
end

function FrameMethods:IsShown()
    return self.__shown
end

function FrameMethods:IsVisible()
    return self.__shown
end

function FrameMethods:GetName()
    return self.__name
end

function FrameMethods:GetObjectType()
    return self.__kind
end

function FrameMethods:GetID()
    return self.__id or 0
end

local function Noop() end
M.Noop = Noop

-- Widget calls the addon's non-UI files might make on a frame; they do nothing here.
for _, method in ipairs({
    "SetSize", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent",
    "SetFrameStrata", "SetFrameLevel", "SetAlpha", "EnableMouse", "SetMovable", "SetResizable",
    "SetClampedToScreen", "SetToplevel", "Raise", "Lower", "RegisterForClicks", "RegisterForDrag",
    "SetText", "SetTexture", "SetVertexColor", "SetTextColor", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetResizeBounds", "EnableMouseWheel", "SetScrollChild",
    "SetVerticalScroll", "SetHighlightTexture", "StartMoving", "StopMovingOrSizing",
}) do
    FrameMethods[method] = Noop
end

function FrameMethods:GetFrameLevel()
    return 1
end

function FrameMethods:GetWidth()
    return 800
end

function FrameMethods:GetHeight()
    return 600
end

function FrameMethods:GetParent()
    return self.__parent
end

function FrameMethods:IsMouseOver()
    return false
end

function FrameMethods:GetChildren()
    return
end

function M.RunScript(frame, script, ...)
    local fn = frame.__scripts[script]
    if fn then
        M.Invoke(frame.__owner, fn, frame, ...)
    end
    local hooks = frame.__hooks[script]
    if hooks then
        for _, hook in ipairs(hooks) do
            M.Invoke(hook.owner, hook.fn, frame, ...)
        end
    end
end

-- Synchronous delivery to every registered frame, in registration order.
function M.Fire(event, ...)
    M.stats.events[event] = (M.stats.events[event] or 0) + 1
    local list = M.registry[event]
    if not list then
        return
    end
    local snapshot = {}
    for index, frame in ipairs(list) do
        snapshot[index] = frame
    end
    for _, frame in ipairs(snapshot) do
        if frame.__events[event] then
            M.RunScript(frame, "OnEvent", event, ...)
        end
    end
end

function CreateFrame(kind, name, parent, template)
    local frame = M.NewFrame(kind, name, M.Owner() == "client" and "client" or M.Owner())
    frame.__parent = parent
    frame.__template = template
    return frame
end

UIParent = M.NewFrame("Frame", "UIParent", "client")

function ShowUIPanel(frame)
    if frame then
        frame:Show()
    end
end

function HideUIPanel(frame)
    if frame then
        frame:Hide()
    end
end

function hooksecurefunc(target, name, hook)
    if type(target) == "string" then
        target, name, hook = _G, target, name
    end
    local original = target[name]
    local owner = M.Owner()
    target[name] = function(...)
        local result = pack(original(...))
        M.Invoke(owner, hook, ...)
        return unpack(result, 1, result.n)
    end
end

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message)
        M.chat[#M.chat + 1] = tostring(message)
    end,
}

SlashCmdList = {}
UISpecialFrames = {}
ITEM_QUALITY3_DESC = "Rare"
ITEM_QUALITY4_DESC = "Epic"
math.randomseed(12345)

---------------------------------------------------------------------------------------------------
-- Clock and timers
---------------------------------------------------------------------------------------------------

M.timers = {}
M.timerSeq = 0

local function AddTimer(delay, fn, owner, interval, handle)
    M.timerSeq = M.timerSeq + 1
    local timer = {
        at = M.clock + math.max(tonumber(delay) or 0, 0),
        seq = M.timerSeq,
        fn = fn,
        owner = owner,
        interval = interval,
        handle = handle,
    }
    M.timers[#M.timers + 1] = timer
    return timer
end

-- Client-side asynchronous work (item data, cold loot lists, loot spec confirmations).
function M.Async(delay, fn)
    AddTimer(delay, fn, "client")
end

function GetTime()
    return M.clock
end

function debugprofilestop()
    return M.clock * 1000 + M.cpuMs
end

C_Timer = {}

function C_Timer.After(delay, fn)
    AddTimer(delay, fn, M.Owner())
end

local function NewHandle()
    local handle = { cancelled = false }
    function handle:Cancel()
        self.cancelled = true
    end
    function handle:IsCancelled()
        return self.cancelled
    end
    return handle
end

function C_Timer.NewTimer(delay, fn)
    local handle = NewHandle()
    AddTimer(delay, function()
        fn(handle)
    end, M.Owner(), nil, handle)
    return handle
end

function C_Timer.NewTicker(interval, fn, iterations)
    local handle = NewHandle()
    handle.remaining = iterations
    AddTimer(interval, function()
        fn(handle)
    end, M.Owner(), interval, handle)
    return handle
end

function M.Step(dt)
    dt = dt or M.cfg.frameTime
    M.clock = M.clock + dt
    M.frameCount = M.frameCount + 1
    local limit = M.timerSeq

    local function RunDue(onlyClient)
        local due = {}
        local keep = {}
        for _, timer in ipairs(M.timers) do
            local isClient = timer.owner == "client"
            if timer.seq <= limit and timer.at <= M.clock + 1e-9 and (isClient == onlyClient) then
                due[#due + 1] = timer
            else
                keep[#keep + 1] = timer
            end
        end
        M.timers = keep
        table.sort(due, function(left, right)
            if left.at ~= right.at then
                return left.at < right.at
            end
            return left.seq < right.seq
        end)
        for _, timer in ipairs(due) do
            if not (timer.handle and timer.handle.cancelled) then
                M.Invoke(timer.owner, timer.fn)
                if timer.interval and not (timer.handle and timer.handle.cancelled) then
                    local handle = timer.handle
                    if handle and handle.remaining then
                        handle.remaining = handle.remaining - 1
                        if handle.remaining <= 0 then
                            handle.cancelled = true
                        end
                    end
                    if not (handle and handle.cancelled) then
                        AddTimer(timer.interval, timer.fn, timer.owner, timer.interval, handle)
                    end
                end
            end
        end
    end

    RunDue(true)
    for _, frame in ipairs(M.frames) do
        if frame.__shown and frame.__scripts.OnUpdate then
            M.RunScript(frame, "OnUpdate", dt)
        end
    end
    RunDue(false)
end

function M.Run(seconds)
    local target = M.clock + seconds - 1e-9
    while M.clock < target do
        M.Step()
    end
end

-- Runs frames until predicate() is true or maxSeconds pass. Returns whether it became true.
function M.RunUntil(predicate, maxSeconds)
    local target = M.clock + maxSeconds
    while M.clock < target do
        if predicate() then
            return true
        end
        M.Step()
    end
    return predicate() and true or false
end

---------------------------------------------------------------------------------------------------
-- Content database
---------------------------------------------------------------------------------------------------

local DIFF = {
    DungeonNormal = 1, DungeonHeroic = 2, DungeonMythic = 23, DungeonChallenge = 8, DungeonTimewalker = 24,
    RaidLFR = 7, Raid10Normal = 3, Raid10Heroic = 5, Raid25Normal = 4, Raid25Heroic = 6, RaidWorld = 172,
    PrimaryRaidLFR = 17, PrimaryRaidNormal = 14, PrimaryRaidHeroic = 15, PrimaryRaidMythic = 16,
    RaidTimewalker = 33, Raid40 = 9,
}

-- Blizzard's EJ_DIFFICULTIES list (IsEJDifficulty).
local EJ_DIFFICULTIES = {
    DIFF.DungeonNormal, DIFF.DungeonHeroic, DIFF.DungeonMythic, DIFF.DungeonChallenge, DIFF.DungeonTimewalker,
    DIFF.RaidLFR, DIFF.Raid10Normal, DIFF.Raid10Heroic, DIFF.Raid25Normal, DIFF.Raid25Heroic, DIFF.RaidWorld,
    DIFF.PrimaryRaidLFR, DIFF.PrimaryRaidNormal, DIFF.PrimaryRaidHeroic, DIFF.PrimaryRaidMythic,
    DIFF.RaidTimewalker, DIFF.Raid40,
}

local function IsEJDifficulty(difficultyID)
    return Contains(EJ_DIFFICULTIES, difficultyID)
end

DifficultyUtil = {
    ID = DIFF,
    GetDifficultyName = function(difficultyID)
        local names = { [1] = "Normal", [2] = "Heroic", [23] = "Mythic", [8] = "Mythic Keystone",
            [17] = "Raid Finder", [14] = "Normal", [15] = "Heroic", [16] = "Mythic" }
        return names[difficultyID]
    end,
}

function GetDifficultyInfo(difficultyID)
    return DifficultyUtil.GetDifficultyName(difficultyID)
end

Enum = {
    WeeklyRewardChestThresholdType = { Activities = 1, RankedPvP = 2, Raid = 3, AlsoReceive = 4, Concession = 5, World = 6 },
    ItemClass = { Consumable = 0, Weapon = 2, Armor = 4, Miscellaneous = 15 },
    ItemArmorSubclass = { Generic = 0, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Cosmetic = 5, Shield = 6 },
    ItemSlotFilterType = {
        Head = 0, Neck = 1, Shoulder = 2, Cloak = 3, Chest = 4, Wrist = 5, Hand = 6, Waist = 7, Legs = 8,
        Feet = 9, MainHand = 10, OffHand = 11, Finger = 12, Trinket = 13, Other = 14, NoFilter = 15,
    },
}
local NO_FILTER = Enum.ItemSlotFilterType.NoFilter

M.CLASS_SPECS = {
    [11] = { 102, 103, 104, 105 },
    [1] = { 71, 72, 73 },
    [8] = { 62, 63, 64 },
    [5] = { 256, 257, 258 },
}
M.SPEC_NAMES = {
    [102] = "Balance", [103] = "Feral", [104] = "Guardian", [105] = "Restoration",
    [71] = "Arms", [72] = "Fury", [73] = "Protection",
    [62] = "Arcane", [63] = "Fire", [64] = "Frost",
    [256] = "Discipline", [257] = "Holy", [258] = "Shadow",
}
local ALL_SPECS = {}
for _, specs in pairs(M.CLASS_SPECS) do
    for _, spec in ipairs(specs) do
        ALL_SPECS[#ALL_SPECS + 1] = spec
    end
end
table.sort(ALL_SPECS)

local SPECS = {
    INT_LEATHER = { 102, 105 },
    AGI_LEATHER = { 103, 104 },
    PLATE = { 71, 72, 73 },
    CLOTH = { 62, 63, 64, 256, 257, 258 },
    INT_TRINKET = { 102, 105, 62, 63, 64, 256, 257, 258 },
    STR_TRINKET = { 71, 72, 73 },
    AGI_TRINKET = { 103, 104 },
    STAFF = { 102, 103, 104, 105, 62, 63, 64, 256, 257, 258 },
    SWORD = { 71, 72 },
}

local ARMOR_SLOTS = { "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_HAND", "INVTYPE_WAIST",
    "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST" }

local EQUIP = {
    INVTYPE_HEAD = { filter = 0, label = "Head" },
    INVTYPE_NECK = { filter = 1, label = "Neck", classID = 4, subClassID = 0 },
    INVTYPE_SHOULDER = { filter = 2, label = "Shoulder" },
    INVTYPE_CLOAK = { filter = 3, label = "Back", classID = 4, subClassID = 1 },
    INVTYPE_CHEST = { filter = 4, label = "Chest" },
    INVTYPE_WRIST = { filter = 5, label = "Wrist" },
    INVTYPE_HAND = { filter = 6, label = "Hands" },
    INVTYPE_WAIST = { filter = 7, label = "Waist" },
    INVTYPE_LEGS = { filter = 8, label = "Legs" },
    INVTYPE_FEET = { filter = 9, label = "Feet" },
    INVTYPE_2HWEAPON = { filter = 10, label = "Two-Hand", classID = 2, subClassID = 10 },
    INVTYPE_WEAPON = { filter = 10, label = "One-Hand", classID = 2, subClassID = 7 },
    INVTYPE_FINGER = { filter = 12, label = "Finger", classID = 4, subClassID = 0 },
    INVTYPE_TRINKET = { filter = 13, label = "Trinket", classID = 4, subClassID = 0 },
    NONEQUIP = { filter = 14, label = "", classID = 15, subClassID = 0 },
}
local ARMOR_SUBCLASS = { cloth = 1, leather = 2, mail = 3, plate = 4 }

M.items = {}
M.instances = {}
M.bosses = {}
M.cold = {}
M.ids = {}

local nextItemID = 240000

local function IsCachedByDefault(itemID)
    return itemID % M.cfg.uncachedModulo ~= M.cfg.uncachedRemainder
end

local function NewItem(opts)
    nextItemID = nextItemID + 1
    local equip = opts.nonGear and "NONEQUIP" or opts.equip
    local slot = EQUIP[equip]
    local item = {
        id = opts.id or nextItemID,
        name = opts.name,
        equipLoc = opts.nonGear and "" or equip,
        filterType = slot.filter,
        slotLabel = slot.label,
        classID = slot.classID or 4,
        subClassID = slot.subClassID or ARMOR_SUBCLASS[opts.armor or "cloth"] or 0,
        specs = opts.specs or "ALL",
        diffs = nil,
        nonGear = opts.nonGear == true,
    }
    if opts.diffs then
        item.diffs = {}
        for _, difficultyID in ipairs(opts.diffs) do
            item.diffs[difficultyID] = true
        end
    end
    item.icon = 1000000 + item.id
    item.cached = IsCachedByDefault(item.id)
    M.items[item.id] = item
    return item
end

local function NewInstance(opts)
    local instance = {
        id = opts.id,
        name = opts.name,
        isRaid = opts.isRaid == true,
        tiers = {},
        diffs = opts.diffs,
        diffSet = {},
        bosses = {},
        gameMapID = opts.gameMapID,
        uiMapID = opts.uiMapID,
        challengeMapID = opts.challengeMapID,
        season = opts.season == true,
    }
    for _, tier in ipairs(opts.tiers) do
        instance.tiers[tier] = true
    end
    for _, difficultyID in ipairs(opts.diffs) do
        instance.diffSet[difficultyID] = true
    end
    M.instances[instance.id] = instance
    return instance
end

local function NewBoss(instance, bossID, dungeonEncounterID, name)
    local boss = {
        id = bossID,
        dungeonEncounterID = dungeonEncounterID,
        name = name,
        instance = instance.id,
        index = #instance.bosses + 1,
        loot = {},
    }
    instance.bosses[#instance.bosses + 1] = bossID
    M.bosses[bossID] = boss
    return boss
end

local function Drop(boss, item)
    boss.loot[#boss.loot + 1] = item.id
    return item
end

function M.SetInstanceDifficulties(instanceID, diffs)
    local instance = M.instances[instanceID]
    instance.diffs = diffs
    instance.diffSet = {}
    for _, difficultyID in ipairs(diffs) do
        instance.diffSet[difficultyID] = true
    end
end

M.OLD_TIER = 11
M.EXPANSION_TIER = 12
M.SEASON_TIER = 13

local function BuildRaid(id, name, tiers, bossBase, encounterBase, bossCount, gameMapID, uiMapID)
    local raid = NewInstance({
        id = id, name = name, isRaid = true, tiers = tiers, diffs = { 14, 15, 16, 17 },
        gameMapID = gameMapID, uiMapID = uiMapID,
    })
    local shared
    for b = 1, bossCount do
        local boss = NewBoss(raid, bossBase + b, encounterBase + b, name .. " Boss " .. b)
        local function Item(opts)
            opts.name = opts.name or string.format("%s B%d %s", name, b, opts.equip or "Misc")
            return Drop(boss, NewItem(opts))
        end
        Item({ equip = ARMOR_SLOTS[b], armor = "leather", specs = SPECS.INT_LEATHER, name = string.format("%s B%d Int Leather", name, b) })
        Item({ equip = ARMOR_SLOTS[b % 8 + 1], armor = "leather", specs = SPECS.AGI_LEATHER, name = string.format("%s B%d Agi Leather", name, b) })
        Item({ equip = ARMOR_SLOTS[(b + 2) % 8 + 1], armor = "plate", specs = SPECS.PLATE, name = string.format("%s B%d Plate", name, b) })
        Item({ equip = ARMOR_SLOTS[(b + 4) % 8 + 1], armor = "cloth", specs = SPECS.CLOTH, name = string.format("%s B%d Cloth", name, b) })
        local trinketSpecs = (b % 3 == 1) and SPECS.INT_TRINKET or ((b % 3 == 2) and SPECS.STR_TRINKET or SPECS.AGI_TRINKET)
        Item({ equip = "INVTYPE_TRINKET", specs = trinketSpecs, name = string.format("%s B%d Trinket", name, b) })
        if b % 3 == 0 then
            Item({ equip = "INVTYPE_FINGER", name = string.format("%s B%d Band", name, b) })
        elseif b % 3 == 1 then
            Item({ equip = "INVTYPE_CLOAK", name = string.format("%s B%d Cloak", name, b) })
        else
            Item({ equip = "INVTYPE_NECK", name = string.format("%s B%d Choker", name, b) })
        end
        if b % 2 == 1 then
            Item({ equip = "INVTYPE_2HWEAPON", specs = SPECS.STAFF, name = string.format("%s B%d Staff", name, b) })
        else
            Item({ equip = "INVTYPE_WEAPON", specs = SPECS.SWORD, name = string.format("%s B%d Sword", name, b) })
        end
        -- Only on Mythic, so reading the wrong difficulty shows in the list.
        Item({ equip = "INVTYPE_FINGER", diffs = { 16 }, name = string.format("%s B%d Mythic Signet", name, b) })
        if b == 5 then
            Item({ equip = "INVTYPE_FINGER", diffs = { 15, 16 }, name = string.format("%s B%d Heroic Loop", name, b) })
        end
        if b == 3 then
            Item({ nonGear = true, name = string.format("%s B%d Token", name, b) })
        end
        if b == bossCount then
            Item({ nonGear = true, diffs = { 16 }, name = string.format("%s B%d Mount", name, b) })
        end
        -- The last two bosses share a trinket.
        if b == bossCount - 1 then
            shared = Item({ equip = "INVTYPE_TRINKET", specs = SPECS.INT_TRINKET, name = name .. " Shared Trinket" })
        elseif b == bossCount and shared then
            Drop(boss, shared)
        end
    end
    return raid
end

local function BuildDungeon(k, id, name, tiers, diffs, season, challengeMapID)
    local dungeon = NewInstance({
        id = id, name = name, tiers = tiers, diffs = diffs, season = season,
        gameMapID = 2900 + k, uiMapID = 2400 + k, challengeMapID = challengeMapID,
    })
    local shared
    for b = 1, 4 do
        local boss = NewBoss(dungeon, 2800 + k * 10 + b, 3400 + k * 10 + b, name .. " Boss " .. b)
        local function Item(opts)
            return Drop(boss, NewItem(opts))
        end
        Item({ equip = ARMOR_SLOTS[(k + b) % 8 + 1], armor = "leather", specs = SPECS.INT_LEATHER, name = string.format("%s B%d Int Leather", name, b) })
        Item({ equip = ARMOR_SLOTS[(k + b + 3) % 8 + 1], armor = "plate", specs = SPECS.PLATE, name = string.format("%s B%d Plate", name, b) })
        if b == 1 then
            Item({ equip = "INVTYPE_FINGER", diffs = { 23, 8 }, name = string.format("%s B%d Mythic Ring", name, b) })
        elseif b == 2 then
            Item({ equip = "INVTYPE_NECK", diffs = { 1, 2 }, name = string.format("%s B%d Heroic Pendant", name, b) })
            Item({ equip = ARMOR_SLOTS[(k + b + 5) % 8 + 1], armor = "leather", specs = SPECS.AGI_LEATHER, name = string.format("%s B%d Agi Leather", name, b) })
        elseif b == 3 then
            Item({ equip = "INVTYPE_2HWEAPON", specs = SPECS.STAFF, name = string.format("%s B%d Staff", name, b) })
            shared = Item({ equip = "INVTYPE_CLOAK", name = name .. " Shared Cloak" })
        else
            Item({ equip = "INVTYPE_TRINKET", specs = SPECS.INT_TRINKET, name = string.format("%s B%d Trinket", name, b) })
            Drop(boss, shared)
        end
    end
    return dungeon
end

function M.Build()
    nextItemID = 240000
    M.items, M.instances, M.bosses, M.cold = {}, {}, {}, {}
    local SEASON = M.SEASON_TIER
    local EXP = M.EXPANSION_TIER
    local OLD = M.OLD_TIER
    local raid = BuildRaid(1500, "Voidspire", { EXP, SEASON }, 2700, 3300, 8, 2900, 2400)
    local seasonNames = { "Ashen Vault", "Brine Grotto", "Cinder Hall", "Dusk Spire", "Ember Crypt", "Frost Deep", "Gilded Maze" }
    local seasonDungeons = {}
    for k, name in ipairs(seasonNames) do
        local dungeon = BuildDungeon(k, 1500 + k, name, { EXP, SEASON }, { 1, 2, 23, 8 }, true, 600 + k)
        seasonDungeons[#seasonDungeons + 1] = dungeon.id
    end
    -- Older-expansion dungeon in this season's Mythic+ rotation.
    local oldSeason = BuildDungeon(8, 1271, "Old Keep", { OLD, SEASON }, { 1, 2, 23, 8 }, true, 608)
    seasonDungeons[#seasonDungeons + 1] = oldSeason.id
    -- Current-expansion dungeon outside the rotation: no Mythic Keystone difficulty.
    local nonRotation = BuildDungeon(9, 1508, "Quiet Hollow", { EXP }, { 1, 2, 23 }, false, nil)
    -- Older-expansion dungeon outside the rotation.
    local oldDungeon = BuildDungeon(10, 1272, "Old Ruins", { OLD }, { 1, 2, 23 }, false, nil)
    local oldRaid = BuildRaid(1273, "Old Citadel", { OLD }, 2950, 3950, 3, 2950, 2450)

    M.ids = {
        raid = raid.id,
        raidBosses = raid.bosses,
        seasonDungeons = seasonDungeons,
        oldSeasonDungeon = oldSeason.id,
        nonRotation = nonRotation.id,
        oldDungeon = oldDungeon.id,
        oldRaid = oldRaid.id,
    }
end

function M.BossOf(instanceID, index)
    local instance = M.instances[instanceID]
    return instance and instance.bosses[index]
end

function M.SeasonMapIDs()
    local ids = {}
    for _, instanceID in ipairs(M.ids.seasonDungeons) do
        ids[#ids + 1] = M.instances[instanceID].challengeMapID
    end
    return ids
end

-- Marks items uncached by itemID modulo (every item whose id % modulo == remainder).
function M.SetUncached(modulo, remainder)
    M.cfg.uncachedModulo = modulo
    M.cfg.uncachedRemainder = remainder
    for id, item in pairs(M.items) do
        item.cached = IsCachedByDefault(id)
    end
end

function M.SetAllCold()
    for id in pairs(M.instances) do
        M.cold[id] = true
    end
end

-- The addon's world list is plain item IDs; give each a deterministic item record.
function M.RegisterWorldItems(list)
    local specsByBucket = { SPECS.INT_LEATHER, SPECS.PLATE, "ALL", SPECS.CLOTH }
    for index, itemID in ipairs(list or {}) do
        if not M.items[itemID] then
            local bucket = itemID % 4 + 1
            local specs = specsByBucket[bucket]
            local equip = ARMOR_SLOTS[itemID % 8 + 1]
            local armor = specs == SPECS.PLATE and "plate" or (specs == SPECS.CLOTH and "cloth" or "leather")
            if specs == "ALL" then
                equip = (itemID % 3 == 0) and "INVTYPE_FINGER" or ((itemID % 3 == 1) and "INVTYPE_CLOAK" or "INVTYPE_NECK")
            end
            NewItem({ id = itemID, equip = equip, armor = armor, specs = specs, name = "World Item " .. index })
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Player, specs, weekly rewards, challenge mode
---------------------------------------------------------------------------------------------------

M.player = {
    classID = 11, className = "Druid", classFile = "DRUID", specIndex = 1, lootSpec = 0, guid = "Player-1-A",
}

function M.CurrentSpecID()
    return M.CLASS_SPECS[M.player.classID][M.player.specIndex]
end

function M.LootSpecID()
    if M.player.lootSpec and M.player.lootSpec ~= 0 then
        return M.player.lootSpec
    end
    return M.CurrentSpecID()
end

function UnitClass()
    return M.player.className, M.player.classFile, M.player.classID
end

function UnitGUID()
    return M.player.guid
end

function UnitSex()
    return 2
end

function UnitLevel()
    return 90
end

function GetSpecialization()
    return M.player.specIndex
end

function GetNumSpecializations()
    return #M.CLASS_SPECS[M.player.classID]
end

function GetSpecializationInfo(index)
    local specID = M.CLASS_SPECS[M.player.classID][index]
    if not specID then
        return nil
    end
    return specID, M.SPEC_NAMES[specID], "", 100000 + specID, "DAMAGER"
end

function GetSpecializationInfoByID(specID)
    if not M.SPEC_NAMES[specID] then
        return nil
    end
    return specID, M.SPEC_NAMES[specID], "", 100000 + specID, "DAMAGER"
end

function GetLootSpecialization()
    return M.player.lootSpec
end

-- The server confirms a loot spec change a moment later.
function SetLootSpecialization(specID)
    M.player.lootSpec = specID or 0
    M.Async(0.05, function()
        M.Fire("PLAYER_LOOT_SPEC_UPDATED")
    end)
end

C_SpecializationInfo = {
    GetSpecialization = GetSpecialization,
    GetSpecializationInfo = GetSpecializationInfo,
}

M.weekly = { canClaim = false, generated = false, tierDifficulty = { [900] = 2, [901] = 8 } }

C_WeeklyRewards = {
    CanClaimRewards = function()
        return M.weekly.canClaim
    end,
    HasGeneratedRewards = function()
        return M.weekly.generated
    end,
    GetDifficultyIDForActivityTier = function(activityTierID)
        return M.weekly.tierDifficulty[activityTierID]
    end,
    GetActivities = function()
        return {}
    end,
    GetNextActivitiesIncrease = function()
        return false
    end,
}

M.challenge = { ready = true }

C_ChallengeMode = {}

function C_ChallengeMode.GetMapTable()
    if not M.challenge.ready then
        return {}
    end
    return M.SeasonMapIDs()
end

function C_ChallengeMode.GetMapUIInfo(mapChallengeModeID)
    if not M.challenge.ready then
        return nil
    end
    for _, instance in pairs(M.instances) do
        if instance.challengeMapID == mapChallengeModeID then
            return instance.name, mapChallengeModeID, 1800, 525000 + mapChallengeModeID, 526000 + mapChallengeModeID, instance.gameMapID
        end
    end
    return nil
end

function M.PublishChallengeMaps()
    M.challenge.ready = true
    M.Fire("CHALLENGE_MODE_MAPS_UPDATE")
end

---------------------------------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------------------------------

local itemWaiters = {}

local function ItemIDFrom(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        return tonumber(value:match("item:(%d+)")) or tonumber(value)
    end
end

local function ItemLink(item)
    return string.format("|cffa335ee|Hitem:%d::::::::90:::::|h[%s]|h|r", item.id, item.name)
end

function M.RequestItem(itemID, fromJournal)
    local item = M.items[itemID]
    if not item or item.cached then
        return
    end
    if fromJournal then
        item.journalAsked = true
    end
    if item.loading then
        return
    end
    item.loading = true
    M.Async(M.cfg.itemLoadDelay, function()
        item.loading = nil
        item.cached = true
        M.Fire("GET_ITEM_INFO_RECEIVED", itemID, true)
        M.Fire("ITEM_DATA_LOAD_RESULT", itemID, true)
        if item.journalAsked then
            item.journalAsked = nil
            M.Fire("EJ_LOOT_DATA_RECIEVED", itemID)
        end
        local waiters = itemWaiters[itemID]
        itemWaiters[itemID] = nil
        for _, waiter in ipairs(waiters or {}) do
            M.Invoke(waiter.owner, waiter.fn)
        end
    end)
end

local function SpecsOf(item)
    if item.specs == "ALL" then
        return ALL_SPECS
    end
    return item.specs
end

function GetItemInfoInstant(value)
    local item = M.items[ItemIDFrom(value) or -1]
    if not item then
        return nil
    end
    local typeName = item.classID == 2 and "Weapon" or (item.classID == 4 and "Armor" or "Miscellaneous")
    return item.id, typeName, "", item.equipLoc, item.icon, item.classID, item.subClassID
end

C_Item = {}

function C_Item.GetItemInfo(value)
    local item = M.items[ItemIDFrom(value) or -1]
    if not item then
        return nil
    end
    if not item.cached then
        M.RequestItem(item.id)
        return nil
    end
    local typeName = item.classID == 2 and "Weapon" or (item.classID == 4 and "Armor" or "Miscellaneous")
    return item.name, ItemLink(item), 4, 250, 80, typeName, "", 1, item.equipLoc, item.icon, 0, item.classID, item.subClassID
end
GetItemInfo = C_Item.GetItemInfo

function C_Item.GetItemIconByID(value)
    local item = M.items[ItemIDFrom(value) or -1]
    return item and item.icon or nil
end

function C_Item.GetItemNameByID(value)
    local item = M.items[ItemIDFrom(value) or -1]
    if item and not item.cached then
        M.RequestItem(item.id)
        return nil
    end
    return item and item.name or nil
end

function C_Item.RequestLoadItemDataByID(value)
    local itemID = ItemIDFrom(value)
    if itemID then
        M.RequestItem(itemID)
    end
end

function C_Item.IsItemDataCachedByID(value)
    local item = M.items[ItemIDFrom(value) or -1]
    return item ~= nil and item.cached
end

function C_Item.GetDetailedItemLevelInfo()
    return nil
end

function C_Item.IsItemKeystoneByID()
    return false
end

function GetItemSpecInfo(value)
    local item = M.items[ItemIDFrom(value) or -1]
    if not item then
        return nil
    end
    if not item.cached then
        M.RequestItem(item.id)
        return nil
    end
    local copy = {}
    for index, spec in ipairs(SpecsOf(item)) do
        copy[index] = spec
    end
    return copy
end

local ItemMixin = {}
ItemMixin.__index = ItemMixin

function ItemMixin:IsItemDataCached()
    local item = M.items[self.itemID]
    return item ~= nil and item.cached
end

function ItemMixin:ContinueOnLoad(fn)
    if self:IsItemDataCached() then
        fn()
        return
    end
    local list = itemWaiters[self.itemID]
    if not list then
        list = {}
        itemWaiters[self.itemID] = list
    end
    list[#list + 1] = { fn = fn, owner = M.Owner() }
    M.RequestItem(self.itemID)
end
ItemMixin.ContinueOnItemLoad = ItemMixin.ContinueOnLoad

Item = {}

function Item:CreateFromItemID(itemID)
    return setmetatable({ itemID = itemID }, ItemMixin)
end

function Item:CreateFromItemLink(link)
    return setmetatable({ itemID = ItemIDFrom(link) }, ItemMixin)
end

---------------------------------------------------------------------------------------------------
-- The EJ C side
---------------------------------------------------------------------------------------------------

function M.ResetJournalState()
    M.ej = {
        tier = M.cfg.seasonTier and M.SEASON_TIER or M.EXPANSION_TIER,
        instance = nil,
        encounter = nil,
        difficulty = 14,
        classID = M.player.classID,
        specID = M.CurrentSpecID(),
        slotFilter = NO_FILTER,
        outOfDate = false,
    }
    M.coldLoading = {}
end

local function Changed()
    M.ej.outOfDate = true
end

local function Selected()
    return M.instances[M.ej.instance]
end

local function Usable(item, classID, specID)
    if not classID or classID == 0 or item.specs == "ALL" then
        return true
    end
    if specID and specID > 0 then
        return Contains(item.specs, specID)
    end
    for _, spec in ipairs(M.CLASS_SPECS[classID] or {}) do
        if Contains(item.specs, spec) then
            return true
        end
    end
    return false
end
M.Usable = Usable

local function Drops(item, difficultyID)
    return item.diffs == nil or item.diffs[difficultyID] == true
end
M.Drops = Drops

-- Rows the journal lists for a selection (pure: no side effects, no counters).
function M.ComputeRows(instanceID, encounterID, difficultyID, classID, specID, slotFilter)
    local instance = M.instances[instanceID]
    if not instance then
        return {}
    end
    local bosses = instance.bosses
    if encounterID then
        bosses = { encounterID }
    end
    local rows = {}
    for _, bossID in ipairs(bosses) do
        local boss = M.bosses[bossID]
        for _, itemID in ipairs(boss and boss.loot or {}) do
            local item = M.items[itemID]
            if Drops(item, difficultyID) and Usable(item, classID, specID)
                and (slotFilter == nil or slotFilter == NO_FILTER or item.filterType == slotFilter) then
                rows[#rows + 1] = { itemID = itemID, bossID = bossID }
            end
        end
    end
    return rows
end

local function CurrentRows()
    local ej = M.ej
    return M.ComputeRows(ej.instance, ej.encounter, ej.difficulty, ej.classID, ej.specID, ej.slotFilter)
end

-- What the journal would list right now, as "itemID@bossID" text (for state comparisons).
function M.PeekList()
    local parts = {}
    for _, row in ipairs(CurrentRows()) do
        parts[#parts + 1] = row.itemID .. "@" .. row.bossID
    end
    return table.concat(parts, ",")
end

local function FixDifficulty(instance)
    if not (M.cfg.fixDifficultyOnSelect and instance and not instance.diffSet[M.ej.difficulty]) then
        return
    end
    M.ej.difficulty = instance.diffs[1]
    if M.cfg.fireOnDifficultyFix then
        M.Fire("EJ_DIFFICULTY_UPDATE", M.ej.difficulty)
        M.Fire("EJ_LOOT_DATA_RECIEVED")
    end
end

local function StartColdLoad(instanceID)
    if M.coldLoading[instanceID] then
        return
    end
    M.coldLoading[instanceID] = true
    M.Async(M.cfg.coldLootDelay, function()
        M.cold[instanceID] = nil
        M.coldLoading[instanceID] = nil
        M.ej.outOfDate = true
        M.Fire("EJ_LOOT_DATA_RECIEVED")
    end)
end

function EJ_GetNumTiers()
    Api("EJ_GetNumTiers")
    return M.cfg.seasonTier and M.SEASON_TIER or M.EXPANSION_TIER
end

function EJ_GetTierInfo(tier)
    Api("EJ_GetTierInfo")
    local names = { [M.OLD_TIER] = "Older Expansion", [M.EXPANSION_TIER] = "Current Expansion", [M.SEASON_TIER] = "Current Season" }
    return names[tier] or ("Tier " .. tostring(tier)), "link"
end

function EJ_GetCurrentTier()
    Api("EJ_GetCurrentTier")
    return M.ej.tier
end

function EJ_SelectTier(tier)
    Api("EJ_SelectTier", "select")
    if type(tier) == "number" and tier >= 1 and tier <= EJ_GetNumTiers() then
        M.ej.tier = tier
    end
end

local function InstancesInTier(isRaid)
    local list = {}
    for id, instance in pairs(M.instances) do
        if instance.tiers[M.ej.tier] and instance.isRaid == (isRaid == true) then
            list[#list + 1] = id
        end
    end
    table.sort(list)
    return list
end

function EJ_GetInstanceByIndex(index, isRaid)
    Api("EJ_GetInstanceByIndex")
    local id = InstancesInTier(isRaid)[index]
    local instance = M.instances[id]
    if not instance then
        return nil
    end
    return instance.id, instance.name, "description", 1, 2, 3, 4, instance.uiMapID, "link", true, instance.gameMapID
end

function EJ_GetInstanceInfo(instanceID)
    Api("EJ_GetInstanceInfo")
    local instance = instanceID and M.instances[instanceID] or Selected()
    if not instance then
        return nil
    end
    return instance.name, "description", 1, 2, 3, 4, instance.uiMapID, "link", true, instance.gameMapID, 0, instance.isRaid
end

function EJ_GetInstanceForMap(uiMapID)
    Api("EJ_GetInstanceForMap")
    for id, instance in pairs(M.instances) do
        if instance.uiMapID == uiMapID then
            return id
        end
    end
    return 0
end

function EJ_SelectInstance(instanceID)
    Api("EJ_SelectInstance", "select")
    local instance = M.instances[instanceID]
    if not instance then
        return
    end
    M.ej.instance = instanceID
    M.ej.encounter = nil
    Changed()
    FixDifficulty(instance)
    if M.cfg.selectFiresLootEvent then
        M.Fire("EJ_LOOT_DATA_RECIEVED")
    end
end

function EJ_GetEncounterInfo(encounterID)
    Api("EJ_GetEncounterInfo")
    local boss = M.bosses[encounterID]
    if not boss then
        return nil
    end
    local instance = M.instances[boss.instance]
    return boss.name, "description", boss.id, 0, "link", boss.instance, boss.dungeonEncounterID, instance.gameMapID
end

function EJ_GetEncounterInfoByIndex(index, instanceID)
    Api("EJ_GetEncounterInfoByIndex")
    local instance = instanceID and M.instances[instanceID] or Selected()
    if instance and not instance.isRaid and not M.cfg.dungeonBossList then
        return nil
    end
    local bossID = instance and instance.bosses[index]
    if not bossID then
        return nil
    end
    local boss = M.bosses[bossID]
    return boss.name, "description", boss.id, 0, "link", instance.id, boss.dungeonEncounterID, instance.gameMapID
end

function EJ_SelectEncounter(encounterID)
    Api("EJ_SelectEncounter", "select")
    local boss = M.bosses[encounterID]
    if not boss then
        return
    end
    if M.ej.instance ~= boss.instance then
        local mode = M.cfg.crossInstanceEncounter
        if mode == "ignore" then
            return
        elseif mode == "switch" then
            M.ej.instance = boss.instance
            FixDifficulty(M.instances[boss.instance])
        end
    end
    M.ej.encounter = encounterID
    Changed()
end

function EJ_GetDifficulty()
    Api("EJ_GetDifficulty")
    return M.ej.difficulty
end

function EJ_IsValidInstanceDifficulty(difficultyID)
    Api("EJ_IsValidInstanceDifficulty")
    local instance = Selected()
    return instance ~= nil and instance.diffSet[difficultyID] == true
end

function EJ_SetDifficulty(difficultyID)
    Api("EJ_SetDifficulty", "difficulty")
    local instance = Selected()
    if instance and not instance.diffSet[difficultyID] then
        return
    end
    if not instance and not IsEJDifficulty(difficultyID) then
        return
    end
    if M.ej.difficulty == difficultyID and not M.cfg.fireWhenUnchanged then
        return
    end
    M.ej.difficulty = difficultyID
    Changed()
    M.Fire("EJ_DIFFICULTY_UPDATE", difficultyID)
    M.Fire("EJ_LOOT_DATA_RECIEVED")
end

local function FilterChanged(changed)
    if not changed and not M.cfg.fireWhenUnchanged then
        return
    end
    Changed()
    if M.cfg.filterFiresLootEvent then
        M.Fire("EJ_LOOT_DATA_RECIEVED")
    end
end

function EJ_GetLootFilter()
    Api("EJ_GetLootFilter")
    return M.ej.classID, M.ej.specID
end

function EJ_SetLootFilter(classID, specID)
    Api("EJ_SetLootFilter", "filter")
    classID = classID or 0
    specID = specID or 0
    local changed = M.ej.classID ~= classID or M.ej.specID ~= specID
    M.ej.classID, M.ej.specID = classID, specID
    FilterChanged(changed)
end

function EJ_ResetLootFilter()
    Api("EJ_ResetLootFilter", "filter")
    local changed = M.ej.classID ~= 0 or M.ej.specID ~= 0
    M.ej.classID, M.ej.specID = 0, 0
    FilterChanged(changed)
end

function EJ_IsLootListOutOfDate()
    Api("EJ_IsLootListOutOfDate")
    if M.ej.instance and M.cold[M.ej.instance] then
        return true
    end
    return M.ej.outOfDate
end

function EJ_GetNumLoot()
    Api("EJ_GetNumLoot", "numLoot")
    if not M.ej.instance then
        return 0
    end
    if M.cold[M.ej.instance] then
        StartColdLoad(M.ej.instance)
        return 0
    end
    M.ej.outOfDate = false
    return #CurrentRows()
end

local function RowInfo(row)
    local item = M.items[row.itemID]
    local instance = M.instances[M.bosses[row.bossID].instance]
    local cached = item.cached
    if not cached then
        M.RequestItem(item.id, true)
    end
    local placeholder = M.cfg.placeholderRows
    return {
        itemID = item.id,
        encounterID = row.bossID,
        name = cached and item.name or (placeholder and instance.name or nil),
        icon = cached and item.icon or (placeholder and 136243 or nil),
        link = cached and ItemLink(item) or nil,
        slot = item.slotLabel,
        armorType = item.classID == 4 and "Leather" or nil,
        itemQuality = "ffa335ee",
        filterType = item.filterType,
        handError = false,
        weaponTypeError = false,
    }
end

EJ_GetNumEncountersForLootByIndex = function()
    return 1
end

C_EncounterJournal = {}

function C_EncounterJournal.GetLootInfoByIndex(index, encounterIndex)
    Api("GetLootInfoByIndex", "row")
    local instance = Selected()
    if not instance or M.cold[instance.id] then
        return nil
    end
    local rows
    if encounterIndex then
        local bossID = instance.bosses[encounterIndex]
        if not bossID then
            return nil
        end
        local ej = M.ej
        rows = M.ComputeRows(instance.id, bossID, ej.difficulty, ej.classID, ej.specID, ej.slotFilter)
    else
        rows = CurrentRows()
    end
    local row = rows[index]
    return row and RowInfo(row) or nil
end

function C_EncounterJournal.GetLootInfo(itemID)
    Api("GetLootInfo")
    local item = M.items[itemID]
    if not item then
        return nil
    end
    return { itemID = itemID, name = item.cached and item.name or nil, icon = item.icon }
end

function C_EncounterJournal.GetSlotFilter()
    Api("GetSlotFilter")
    return M.ej.slotFilter
end

function C_EncounterJournal.SetSlotFilter(filter)
    Api("SetSlotFilter", "filter")
    local changed = M.ej.slotFilter ~= filter
    M.ej.slotFilter = filter
    FilterChanged(changed)
end

function C_EncounterJournal.ResetSlotFilter()
    Api("ResetSlotFilter", "filter")
    local changed = M.ej.slotFilter ~= NO_FILTER
    M.ej.slotFilter = NO_FILTER
    FilterChanged(changed)
end

function C_EncounterJournal.InstanceHasDifficultyID(difficultyID)
    Api("InstanceHasDifficultyID")
    local instance = Selected()
    return instance ~= nil and instance.diffSet[difficultyID] == true
end

function C_EncounterJournal.GetBaseDifficultyID(difficultyID)
    return difficultyID
end

function C_EncounterJournal.InstanceHasLoot()
    Api("InstanceHasLoot")
    return Selected() ~= nil
end

function C_EncounterJournal.GetInstanceForGameMap(gameMapID)
    Api("GetInstanceForGameMap")
    for id, instance in pairs(M.instances) do
        if instance.gameMapID == gameMapID then
            return id
        end
    end
    return nil
end

function C_EncounterJournal.InitalizeSelectedTier()
    Api("InitalizeSelectedTier", "select")
    M.ej.tier = M.cfg.seasonTier and M.SEASON_TIER or M.EXPANSION_TIER
end

local function Restricted(name)
    return function()
        if M.ctx.addon > 0 and M.ctx.ag == 0 then
            M.blocked[#M.blocked + 1] = name
            error("ADDON_ACTION_BLOCKED: " .. name .. " is protected", 2)
        end
    end
end

C_EncounterJournal.OnOpen = Restricted("C_EncounterJournal.OnOpen")
C_EncounterJournal.OnClose = Restricted("C_EncounterJournal.OnClose")
C_EncounterJournal.SetTab = Restricted("C_EncounterJournal.SetTab")

function EJ_EndSearch() end

function EJ_GetCreatureInfo()
    return nil
end

function M.Snapshot()
    local ej = M.ej
    local guide = rawget(_G, "EncounterJournal")
    return {
        instance = ej.instance,
        encounter = ej.encounter,
        difficulty = ej.difficulty,
        classID = ej.classID,
        specID = ej.specID,
        slotFilter = ej.slotFilter,
        tier = ej.tier,
        peek = M.PeekList(),
        guideLoaded = guide ~= nil,
        guideShown = guide ~= nil and guide:IsShown(),
        guideInstance = guide and guide.instanceID,
        guideEncounter = guide and guide.encounterID,
        guideDifficultyEvent = guide ~= nil and guide:IsEventRegistered("EJ_DIFFICULTY_UPDATE"),
        guideLootEvent = guide ~= nil and guide:IsEventRegistered("EJ_LOOT_DATA_RECIEVED"),
    }
end

---------------------------------------------------------------------------------------------------
-- The Adventure Guide (Blizzard_EncounterJournal, Mainline)
---------------------------------------------------------------------------------------------------

local AG = {}
M.AG = AG

local TAB = { journeys = 1, monthly = 2, suggest = 3, dungeons = 4, raids = 5, loot = 6, tutorials = 7 }
AG.TAB = TAB
local EJ_JOURNEYS_MIN_TIER = 10

local function Panel(shown)
    local panel = { shown = shown }
    function panel:Show()
        self.shown = true
    end
    function panel:Hide()
        self.shown = false
    end
    function panel:IsShown()
        return self.shown
    end
    return panel
end

local function Tab(id)
    return {
        GetID = function()
            return id
        end,
    }
end

local function Guide()
    return rawget(_G, "EncounterJournal")
end

-- EncounterJournal_LootUpdate: the expensive full rebuild of the loot list.
function AG.LootUpdate()
    local guide = Guide()
    M.stats.agRebuilds = M.stats.agRebuilds + 1
    if M.ctx.addon > 0 then
        M.stats.agRebuildsInAddon = M.stats.agRebuildsInAddon + 1
    end
    local shown = {}
    for index = 1, EJ_GetNumLoot() do
        local info = C_EncounterJournal.GetLootInfoByIndex(index)
        if info then
            shown[#shown + 1] = info.itemID
        end
    end
    guide.shownLoot = shown
end

-- EncounterJournal_LootCallback: re-inits the one button showing itemID.
function AG.LootCallback()
    M.stats.agCallbacks = M.stats.agCallbacks + 1
    if M.ctx.addon > 0 then
        M.stats.agCallbacksInAddon = M.stats.agCallbacksInAddon + 1
    end
end

local function NoteHijack(what)
    if M.ctx.addon > 0 then
        M.stats.agHijacks = M.stats.agHijacks + 1
        if #M.stats.hijackLog < 10 then
            M.stats.hijackLog[#M.stats.hijackLog + 1] = string.format("@%.2fs %s", M.clock, what)
        end
    end
end

function AG.SetupDifficultyDropdown()
    for _, difficultyID in ipairs(EJ_DIFFICULTIES) do
        if EJ_IsValidInstanceDifficulty(difficultyID) then
            C_EncounterJournal.GetBaseDifficultyID(difficultyID)
        end
    end
end

local function PopulateBossDataProvider()
    local index = 1
    while true do
        local _, _, bossID = EJ_GetEncounterInfoByIndex(index)
        if not (bossID and bossID > 0) then
            break
        end
        index = index + 1
    end
end

function AG.DisplayInstance(instanceID)
    local guide = Guide()
    NoteHijack("EJ_SelectInstance(" .. tostring(instanceID) .. ") by the guide")
    EJ_GetDifficulty()
    guide.instanceSelect:Hide()
    guide.encounter:Show()
    guide.instanceID = instanceID
    guide.encounterID = nil
    EJ_SelectInstance(instanceID)
    AG.LootUpdate()
    EJ_GetInstanceInfo()
    PopulateBossDataProvider()
    C_EncounterJournal.InstanceHasLoot()
    -- EncounterJournal_SearchForOverview walks the bosses again.
    PopulateBossDataProvider()
    AG.SetupDifficultyDropdown()
end

function AG.DisplayEncounter(encounterID)
    local guide = Guide()
    NoteHijack("EJ_SelectEncounter(" .. tostring(encounterID) .. ") by the guide")
    EJ_GetEncounterInfo(encounterID)
    guide.encounterID = encounterID
    EJ_SelectEncounter(encounterID)
    AG.LootUpdate()
    C_EncounterJournal.InstanceHasLoot()
    PopulateBossDataProvider()
    guide.encounter:Show()
end

function AG.Refresh()
    local guide = Guide()
    AG.LootUpdate()
    if guide.encounterID then
        AG.DisplayEncounter(guide.encounterID)
    elseif guide.instanceID then
        AG.DisplayInstance(guide.instanceID)
    end
end

function AG.UpdateDifficulty(difficultyID)
    if IsEJDifficulty(difficultyID) then
        AG.SetupDifficultyDropdown()
        AG.Refresh()
    end
end

function AG.OnEvent(_, event, ...)
    if event == "EJ_LOOT_DATA_RECIEVED" then
        local itemID = ...
        if itemID and not EJ_IsLootListOutOfDate() then
            AG.LootCallback(itemID)
        else
            AG.LootUpdate()
        end
    elseif event == "EJ_DIFFICULTY_UPDATE" then
        AG.UpdateDifficulty(...)
    end
end

function AG.ListInstances()
    local guide = Guide()
    guide.encounter:Hide()
    guide.instanceSelect:Show()
    local showRaid = guide.selectedTab == TAB.raids
    local index = 1
    while EJ_GetInstanceByIndex(index, showRaid) do
        index = index + 1
    end
    EJ_GetInstanceByIndex(1, not showRaid)
end

function AG.ContentTabSelect(id)
    local guide = Guide()
    guide.selectedTab = id
    guide.encounter:Hide()
    guide.instanceSelect:Show()
    if id == TAB.dungeons or id == TAB.raids then
        AG.ListInstances()
    elseif id == TAB.journeys then
        if EJ_GetCurrentTier() < EJ_JOURNEYS_MIN_TIER then
            C_EncounterJournal.InitalizeSelectedTier()
            EJ_SelectTier(EJ_GetCurrentTier())
        end
    end
end

function AG.OnShow()
    local guide = Guide()
    C_EncounterJournal.OnOpen()
    AG.LootUpdate()
    -- Not inside an instance, so no EncounterJournal_ResetDisplay.
    if guide.instanceSelect:IsShown() and guide.selectedTab then
        AG.ContentTabSelect(guide.selectedTab)
    end
    AG.SetupDifficultyDropdown()
end

function AG.OnHide()
    C_EncounterJournal.OnClose()
end

-- Loading Blizzard_EncounterJournal: the frame, EncounterJournal_OnLoad, then the deferred
-- EventUtil.ContinueOnPlayerLogin block (Journeys tab + SelectJourneysTier), then ADDON_LOADED.
function AG.Load()
    if Guide() then
        return Guide()
    end
    local guide = M.NewFrame("Frame", "EncounterJournal", "ag")
    guide.__shown = false
    guide.instanceSelect = Panel(true)
    guide.encounter = Panel(false)
    guide.JourneysTab = Tab(TAB.journeys)
    guide.MonthlyActivitiesTab = Tab(TAB.monthly)
    guide.suggestTab = Tab(TAB.suggest)
    guide.dungeonsTab = Tab(TAB.dungeons)
    guide.raidsTab = Tab(TAB.raids)
    guide.LootJournalTab = Tab(TAB.loot)
    guide.TutorialsTab = Tab(TAB.tutorials)
    guide:SetScript("OnEvent", AG.OnEvent)
    guide:SetScript("OnShow", AG.OnShow)
    guide:SetScript("OnHide", AG.OnHide)
    M.Invoke("ag", function()
        guide:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
        guide:RegisterEvent("EJ_DIFFICULTY_UPDATE")
        guide:RegisterEvent("UNIT_PORTRAIT_UPDATE")
        guide:RegisterEvent("PORTRAITS_UPDATED")
        guide:RegisterEvent("SEARCH_DB_LOADED")
        guide:RegisterEvent("UI_MODEL_SCENE_INFO_UPDATED")
        EJ_GetInstanceByIndex(1, false)
        EJ_GetInstanceByIndex(1, true)
        AG.ContentTabSelect(TAB.journeys)
        EJ_SelectTier(EJ_GetCurrentTier())
    end)
    M.addonsLoaded["Blizzard_EncounterJournal"] = true
    M.Fire("ADDON_LOADED", "Blizzard_EncounterJournal")
    return guide
end

-- Player actions, doing what Blizzard's UI code does for each click.
local function Act(fn)
    return function(...)
        local ok = M.Invoke("ag", fn, ...)
        if not ok then
            error("Adventure Guide model action failed:\n" .. M.ErrorText("ag", 3))
        end
    end
end

AG.Open = Act(function()
    local guide = AG.Load()
    ShowUIPanel(guide)
end)

AG.Close = Act(function()
    HideUIPanel(Guide())
end)

AG.PickTab = Act(function(name)
    AG.ContentTabSelect(TAB[name])
end)

-- Instance button OnClick -> EncounterJournal_DisplayInstance(self.instanceID).
AG.PickInstance = Act(function(instanceID)
    local instance = M.instances[instanceID]
    local wanted = instance.isRaid and TAB.raids or TAB.dungeons
    if Guide().selectedTab ~= wanted then
        AG.ContentTabSelect(wanted)
    end
    AG.DisplayInstance(instanceID)
end)

-- EncounterJournalBossButton_OnClick -> EncounterJournal_DisplayEncounter(self.encounterID).
AG.PickBoss = Act(function(encounterID)
    local guide = Guide()
    assert(M.bosses[encounterID] and M.bosses[encounterID].instance == guide.instanceID,
        "boss " .. tostring(encounterID) .. " is not on the displayed instance")
    AG.DisplayEncounter(encounterID)
end)

-- Difficulty dropdown -> EncounterJournal_SelectDifficulty -> EJ_SetDifficulty(value).
AG.SetDifficulty = Act(function(difficultyID)
    assert(EJ_IsValidInstanceDifficulty(difficultyID), "difficulty " .. tostring(difficultyID) .. " is not offered")
    EJ_SetDifficulty(difficultyID)
end)

-- Class/spec filter -> EJ_SetLootFilter + EncounterJournal_OnFilterChanged (LootUpdate).
AG.SetLootFilter = Act(function(classID, specID)
    EJ_SetLootFilter(classID, specID)
    AG.LootUpdate()
end)

AG.ResetLootFilter = Act(function()
    EJ_ResetLootFilter()
    AG.LootUpdate()
end)

-- Slot filter -> C_EncounterJournal.SetSlotFilter + LootUpdate.
AG.SetSlotFilter = Act(function(filter)
    C_EncounterJournal.SetSlotFilter(filter)
    AG.LootUpdate()
end)

-- Expansion dropdown -> ExpansionDropdown_SelectInternal: EJ_SelectTier, ListInstances on the
-- dungeon/raid tabs. The guide's instanceID/encounterID are left as they were.
AG.PickTier = Act(function(tier)
    EJ_SelectTier(tier)
    local guide = Guide()
    if guide.selectedTab == TAB.dungeons or guide.selectedTab == TAB.raids then
        AG.ListInstances()
    end
end)

---------------------------------------------------------------------------------------------------
-- Add-on loading
---------------------------------------------------------------------------------------------------

M.addonsLoaded = {}

function M.LoadWeeklyRewards()
    if M.addonsLoaded["Blizzard_WeeklyRewards"] then
        return
    end
    local frame = M.NewFrame("Frame", "WeeklyRewardsFrame", "client")
    frame.__shown = false
    M.addonsLoaded["Blizzard_WeeklyRewards"] = true
    M.Fire("ADDON_LOADED", "Blizzard_WeeklyRewards")
end

C_AddOns = {
    IsAddOnLoaded = function(name)
        return M.addonsLoaded[name] == true
    end,
    LoadAddOn = function(name)
        if name == "Blizzard_EncounterJournal" then
            M.Invoke("client", AG.Load)
        elseif name == "Blizzard_WeeklyRewards" then
            M.LoadWeeklyRewards()
        end
        return true
    end,
}
IsAddOnLoaded = C_AddOns.IsAddOnLoaded
LoadAddOn = C_AddOns.LoadAddOn

M.Build()
M.ResetJournalState()

return M
